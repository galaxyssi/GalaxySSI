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
    let metric: GalaxySSIHealthMetric
    let measuredAt: Date
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
      guard let data = try readAuthenticated() else {
        return .init(measurements: 0, linked: [], originals: nil)
      }
      return try project(data)
    }

    func search(_ query: OriginalQuery, in originals: [Original]) throws -> Set<UUID> {
      try query.matches(originals, metadata: query.needsMeasurements ? readAuthenticated() : nil)
    }

    private func readAuthenticated() throws -> Data? {
      try Task.checkCancellation()
      let sealed: Data
      do { sealed = try Data(contentsOf: file) }
      catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
        return nil
      }
      guard let key else { throw CocoaError(.fileReadNoPermission) }
      let data = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: context)
      try Task.checkCancellation()
      return data
    }
  }

  struct OriginalQuery: Sendable {
    private let text: String
    private let terms: [String]
    private let dates: Range<Date>?
    private let metrics: Set<GalaxySSIHealthMetric>

    init(_ query: String, timeZone: TimeZone) {
      let text = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
      let terms = Self.words(text).map(String.init)
      let dates = Self.dateRange(text, timeZone: timeZone)
      self.text = text
      self.terms = terms
      self.dates = dates
      let key = terms.joined()
      metrics = dates != nil || key.isEmpty ? [] : Set(GalaxySSIHealthMetric.allCases.filter { metric in
        let localized = GalaxySSILocalization.string("galaxyssi.health.metric_alias." + metric.rawValue,
          fallback: "", language: "zh-CN")
        let names = [metric.rawValue, metric.entry.title, metric.title(language: "zh-CN")] +
          metric.entry.aliases + localized.split(separator: "|").map(String.init)
        return names.contains { name in
          let candidate = Self.words(Self.normalize(name)).joined()
          return candidate == key || (key.count >= 3 && candidate.contains(key))
        }
      })
    }

    var needsMeasurements: Bool { dates != nil || !metrics.isEmpty }

    func matches(_ originals: [Original], metadata: Data?) throws -> Set<UUID> {
      try Task.checkCancellation()
      let archive = try metadata.map { try JSONDecoder().decode(Archive.self, from: $0) }
      if let archive, archive.version != 1 { throw CocoaError(.fileReadCorruptFile) }
      var current: [UUID: Revision] = [:]
      for revision in archive?.revisions ?? [] {
        try Task.checkCancellation()
        current[revision.id] = revision
      }
      var targets = Set<Evidence.Target>()
      var linked = Set<Reference>()
      for revision in current.values where !revision.deleted {
        try Task.checkCancellation()
        guard dates?.contains(revision.measuredAt) ?? metrics.contains(revision.metric) else { continue }
        targets.insert(.init(record: revision.id, revision: revision.revision))
        if let source = revision.reportSource { linked.insert(source.reference) }
      }
      for evidence in archive?.reportEvidence ?? [] {
        try Task.checkCancellation()
        if targets.contains(evidence.target) { linked.insert(evidence.source.reference) }
      }
      let index = archive?.originalIndex
      let removed = index.map { $0.removals.pending.union($0.removals.metadata.map(\.id)) } ?? []
      var matches = Set<UUID>()
      for start in stride(from: 0, to: originals.count, by: 30) {
        try Task.checkCancellation()
        for original in originals[start..<min(start + 30, originals.count)] {
          guard !removed.contains(original.id), index.map({ $0.originals[original.id] == original }) ?? true
          else { continue }
          let name = Self.normalize(original.name)
          let nameTerms = Self.words(name)
          if text.isEmpty || name.contains(text) ||
            (dates == nil && !terms.isEmpty && terms.allSatisfy { term in nameTerms.contains { $0.contains(term) } }) ||
            dates?.contains(original.importedAt) == true ||
            linked.contains(.init(id: original.id, sha256: original.sha256)) {
            matches.insert(original.id)
          }
        }
      }
      return matches
    }

    private static func normalize(_ value: String) -> String {
      value.precomposedStringWithCompatibilityMapping.lowercased()
    }

    private static func words(_ value: String) -> [Substring] {
      value.split { !$0.isLetter && !$0.isNumber }
    }

    private static func dateRange(_ value: String, timeZone: TimeZone) -> Range<Date>? {
      let pattern = #"^(\d{4})[-./\u5e74](\d{1,2})(?:[-./\u6708](\d{1,2})\u65e5?|\u6708)?$"#
      guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
            match.range.length == value.utf16.count else { return nil }
      func number(_ group: Int) -> Int? {
        Range(match.range(at: group), in: value).flatMap { Int(value[$0]) }
      }
      guard let year = number(1), (1970...9998).contains(year),
            let month = number(2), (1...12).contains(month) else { return nil }
      let day = number(3) ?? 1
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = timeZone
      guard let date = calendar.date(from: .init(year: year, month: month, day: day)),
            calendar.component(.day, from: date) == day,
            calendar.component(.month, from: date) == month,
            let end = calendar.dateInterval(of: number(3) == nil ? .month : .day, for: date)?.end
      else { return nil }
      let start = max(calendar.startOfDay(for: date), Date(timeIntervalSince1970: 0))
      return start < end ? start..<end : nil
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
