import CryptoKit
import Foundation

enum GalaxySSIHealthDataFiles {
  typealias Original = GalaxySSIHealthOriginalStore.Original
  typealias Index = GalaxySSIHealthOriginalStore.Index

  struct Reference: Hashable, Sendable {
    let id: UUID
    let sha256: String
  }

  struct Recent: Identifiable, Sendable {
    enum Status: Equatable, Sendable { case linked, unlinked, unavailable }
    let original: Original
    let status: Status
    var id: UUID { original.id }
    var reference: Reference { .init(id: id, sha256: original.sha256) }
  }

  struct Counts: Equatable, Sendable {
    var measurements = 0
    var camera = 0
    var uploaded = 0
  }

  private struct Revision: Decodable, Sendable {
    let id: UUID
    let revision: Int
    let deleted: Bool
    let reportSource: Source?
  }

  private struct Source: Decodable, Sendable {
    let original: UUID
    let sha256: String
    var reference: Reference { .init(id: original, sha256: sha256) }
  }

  private struct Evidence: Decodable, Sendable {
    struct Target: Decodable, Hashable, Sendable {
      let record: UUID
      let revision: Int
    }
    let target: Target
    let source: Source
  }

  private struct Archive: Decodable {
    let version: Int
    let revisions: [Revision]
    let reportEvidence: [Evidence]?
    let originalIndex: Index?
  }

  struct Reader: Sendable {
    let file: URL
    let context: Data
    let key: SymmetricKey?

    func read() throws -> Snapshot {
      try Task.checkCancellation()
      let sealed: Data
      do { sealed = try Data(contentsOf: file) }
      catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
        return .init(measurements: 0, linked: [], originals: nil)
      }
      guard let key else { throw CocoaError(.fileReadNoPermission) }
      let data = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: context)
      try Task.checkCancellation()
      return try project(data)
    }
  }

  static func project(_ data: Data) throws -> Snapshot {
    let archive = try JSONDecoder().decode(Archive.self, from: data)
    guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
    var latest = [UUID: Revision]()
    for revision in archive.revisions {
      try Task.checkCancellation()
      latest[revision.id] = revision
    }
    let current = latest.values.filter { !$0.deleted }
    let live = Set(current.map(\.id))
    var linked = Set<Reference>()
    // A source from an earlier revision still belongs to a live measurement.
    var validTargets = Set<Evidence.Target>()
    for revision in archive.revisions where !revision.deleted && live.contains(revision.id) {
      try Task.checkCancellation()
      validTargets.insert(.init(record: revision.id, revision: revision.revision))
      if let source = revision.reportSource { linked.insert(source.reference) }
    }
    for item in archive.reportEvidence ?? [] where validTargets.contains(item.target) {
      try Task.checkCancellation()
      linked.insert(item.source.reference)
    }
    return .init(measurements: current.count, linked: linked, originals: try archive.originalIndex.map(active))
  }

  static func active(_ index: Index) throws -> [Original] {
    try Task.checkCancellation()
    let removed = index.removals.pending.union(index.removals.metadata.map(\.id))
    return index.originals.values.filter { !removed.contains($0.id) }.sorted(by: newer)
  }

  private static func newer(_ lhs: Original, _ rhs: Original) -> Bool {
    (lhs.importedAt, lhs.id.uuidString) > (rhs.importedAt, rhs.id.uuidString)
  }

  struct Snapshot: Sendable {
    let measurements: Int
    let linked: Set<Reference>
    var originals: [Original]?

    func recent(in directory: URL) throws -> [Recent] {
      try (originals ?? []).prefix(4).map { original in
        try Task.checkCancellation()
        let file = directory.appendingPathComponent(original.id.uuidString)
        let resources = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let available = resources?.isRegularFile == true && resources?.isSymbolicLink == false
        let reference = Reference(id: original.id, sha256: original.sha256)
        return Recent(original: original, status: available ? (linked.contains(reference) ? .linked : .unlinked) : .unavailable)
      }
    }

    func page(after cursor: Original?) -> ArraySlice<Original> {
      guard let originals else { return [] }
      if let cursor {
        guard let start = originals.firstIndex(where: { GalaxySSIHealthDataFiles.newer(cursor, $0) }) else { return [] }
        return originals[start...].prefix(30)
      }
      return originals.prefix(30)
    }

    func counts() async throws -> Counts {
      var result = Counts(measurements: measurements)
      var cursor: Original?
      while true {
        try Task.checkCancellation()
        let batch = page(after: cursor)
        guard let last = batch.last else { return result }
        for original in batch {
          switch original.acquisition {
          case .camera: result.camera += 1
          case .uploaded: result.uploaded += 1
          case nil: break
          }
        }
        cursor = last
        await Task.yield()
      }
    }
  }
}
