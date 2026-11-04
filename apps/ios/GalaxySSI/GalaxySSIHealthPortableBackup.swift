import CryptoKit
import Foundation
import Security

enum GalaxySSIHealthPortableBackup {
  static let maximumFileBytes = 48 * 1024 * 1024
  private static let maximumSourceBytes = 32 * 1024 * 1024
  private static let magic = Data("GalaxySSI-Health-Backup-v1\n".utf8)
  private static let saltSize = 16
  private static let iterationsV1 = 600_000

  enum Failure: Error { case invalid, limit, stale, password, owner }

  struct Summary: Sendable, Equatable {
    let readings: Int
    let originals: Int
    let tables: Int
    let links: Int
    let missing: Int
    let estimatedBytes: Int
    let start: Date?
    let end: Date?
  }

  struct Plan: Equatable {
    let summary: Summary
    let readingVersions: [String]
    let originalDigests: [String]
    let tableDigests: [String]
  }

  private struct OriginalFile: Codable {
    let manifest: GalaxySSIHealthOriginalStore.Original
    let bytes: Data?
  }

  private struct Payload: Codable {
    let owner: String?
    let readings: [GalaxySSIHealthReading]
    let originals: [OriginalFile]
    let tables: [GalaxySSIHealthTableImport.Batch]
    let unreadableOriginals: Int
  }

  @MainActor
  static func plan(records: GalaxySSIHealthRecords, originals: GalaxySSIHealthOriginalStore) throws -> Plan {
    let archive = try records.load()
    let listing = try originals.list()
    return makePlan(archive.current, listing: listing, tables: archive.tableBatches ?? [])
  }

  @MainActor
  static func prepare(_ expected: Plan, records: GalaxySSIHealthRecords,
                      originals: GalaxySSIHealthOriginalStore) throws -> (Data, Summary) {
    let archive = try records.load()
    let readings = archive.current
    let listing = try originals.list()
    let tables = archive.tableBatches ?? []
    guard makePlan(readings, listing: listing, tables: tables) == expected else { throw Failure.stale }
    guard expected.summary.estimatedBytes <= maximumSourceBytes, readings.count <= 10_000 else { throw Failure.limit }
    let files = listing.originals.map { OriginalFile(manifest: $0, bytes: try? originals.read($0)) }
    let payload = Payload(owner: records.owner, readings: readings, originals: files, tables: tables,
                          unreadableOriginals: listing.unavailable)
    let summary = try validate(payload)
    let data = try JSONEncoder().encode(payload)
    guard data.count <= maximumFileBytes - magic.count - saltSize - 28 else { throw Failure.limit }
    return (data, summary)
  }

  static func seal(_ plaintext: Data, password: String) throws -> Data {
    guard plaintext.count <= maximumFileBytes - magic.count - saltSize - 28 else { throw Failure.limit }
    var salt = Data(count: saltSize)
    let status = salt.withUnsafeMutableBytes { buffer -> OSStatus in
      guard let address = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, saltSize, address)
    }
    guard status == errSecSuccess else { throw Failure.invalid }
    let header = magic + salt
    let key = try key(password, salt: salt)
    try Task.checkCancellation()
    guard let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: header).combined else { throw Failure.invalid }
    return header + sealed
  }

  static func verify(_ archive: Data, password: String) throws -> Summary {
    try unlock(archive, password: password).summary
  }

  struct RestoreInput: Sendable {
    fileprivate let plaintext: Data
    let summary: Summary
  }

  static func unlock(_ archive: Data, password: String) throws -> RestoreInput {
    let headerCount = magic.count + saltSize
    guard archive.count <= maximumFileBytes, archive.count > headerCount + 28, archive.starts(with: magic)
    else { throw Failure.invalid }
    let header = Data(archive.prefix(headerCount))
    let salt = Data(header.suffix(saltSize))
    let key = try key(password, salt: salt)
    try Task.checkCancellation()
    let box = try AES.GCM.SealedBox(combined: Data(archive.dropFirst(headerCount)))
    let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
    try Task.checkCancellation()
    return RestoreInput(plaintext: plaintext, summary: try validate(JSONDecoder().decode(Payload.self, from: plaintext)))
  }

  private static func key(_ password: String, salt: Data) throws -> SymmetricKey {
    guard password.count >= 8, password.utf8.count <= 1_024 else { throw Failure.password }
    return SymmetricKey(data: try GalaxySSIBackupManager.pbkdf2SHA256(
      password: password, salt: salt, iterations: iterationsV1, keyByteCount: 32))
  }

  private static func makePlan(_ readings: [GalaxySSIHealthReading], listing: GalaxySSIHealthOriginalStore.Listing,
                               tables: [GalaxySSIHealthTableImport.Batch]) -> Plan {
    let hashes = tables.map { ($0.id, digest($0.data)) }
    let present = Dictionary(hashes, uniquingKeysWith: { first, _ in first })
    let links = readings.compactMap(\.tableSource)
    let absent = Set(links.filter { present[$0.batch] != $0.sha256 }.map(\.batch)).count
    let size = listing.originals.reduce(0) { $0 + $1.bytes } + tables.reduce(0) { $0 + $1.data.count }
    let summary = Summary(readings: readings.count, originals: listing.originals.count, tables: tables.count,
                          links: links.count, missing: listing.unavailable + absent, estimatedBytes: size,
                          start: readings.last?.measuredAt, end: readings.first?.measuredAt)
    return Plan(summary: summary,
      readingVersions: readings.map { "\($0.id):\($0.revision)" },
      originalDigests: listing.originals.map { "\($0.id):\($0.sha256)" },
      tableDigests: hashes.map { "\($0.0):\($0.1)" })
  }

  private static func validate(_ payload: Payload) throws -> Summary {
    guard payload.readings.count <= 10_000, payload.originals.count <= 500, payload.tables.count <= 30,
          (0...500).contains(payload.unreadableOriginals),
          Set(payload.readings.map(\.id)).count == payload.readings.count,
          Set(payload.originals.map { $0.manifest.id }).count == payload.originals.count,
          Set(payload.tables.map(\.id)).count == payload.tables.count,
          payload.readings.allSatisfy({ $0.revision > 0 && !$0.deleted && $0.isValid }) else { throw Failure.invalid }
    var size = 0
    var missing = payload.unreadableOriginals
    for entry in payload.originals {
      let ext = entry.manifest.fileExtension.utf8
      guard (1...GalaxySSIHealthOriginalStore.maximumFileBytes).contains(entry.manifest.bytes),
            entry.manifest.name.count <= 180, (1...8).contains(ext.count),
            ext.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) }),
            entry.manifest.kind != .pdf || entry.manifest.fileExtension == "pdf" else { throw Failure.invalid }
      if let data = entry.bytes {
        guard data.count == entry.manifest.bytes, digest(data) == entry.manifest.sha256 else { throw Failure.invalid }
        size += data.count
      } else { missing += 1 }
    }
    var tables: [UUID: String] = [:]
    for batch in payload.tables {
      guard (1...GalaxySSIHealthTableImport.maximumBytes).contains(batch.data.count) else { throw Failure.invalid }
      tables[batch.id] = digest(batch.data)
      size += batch.data.count
    }
    guard size <= maximumSourceBytes else { throw Failure.limit }
    let links = payload.readings.compactMap(\.tableSource)
    missing += Set(links.filter { tables[$0.batch] != $0.sha256 }.map(\.batch)).count
    let dates = payload.readings.map(\.measuredAt)
    return Summary(readings: payload.readings.count, originals: payload.originals.count, tables: payload.tables.count,
                   links: links.count, missing: missing, estimatedBytes: size, start: dates.min(), end: dates.max())
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

extension GalaxySSIHealthPortableBackup {
  struct RestorePreview: Equatable {
    let readings: Int
    let duplicates: Int
    let conflicts: [GalaxySSIHealthReading]
    let originals: Int
    let tables: Int
    let missing: Int
    fileprivate let snapshot: [String]

    var hasChanges: Bool { readings + originals + tables > 0 }
  }

  @MainActor
  static func previewRestore(_ input: RestoreInput, records: GalaxySSIHealthRecords,
                             originals: GalaxySSIHealthOriginalStore) throws -> RestorePreview {
    try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      return try restoreWork(input, records: records, originals: originals, lease: lease).0
    }
  }

  @MainActor
  static func restore(_ input: RestoreInput, expected: RestorePreview, records: GalaxySSIHealthRecords,
                      originals: GalaxySSIHealthOriginalStore) throws {
    try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let (fresh, archive, files) = try restoreWork(input, records: records, originals: originals, lease: lease)
      guard fresh == expected, fresh.hasChanges else { throw Failure.stale }
      let receipt = UUID()
      do {
        try originals.stageRestore(files, receipt: receipt, lease: lease)
        try records.commitRestore(archive, receipt: receipt)
      } catch {
        try? originals.reconcileRestores(lease: lease)
        throw error
      }
      // The receipt is the publication point. A later read retries interrupted promotion.
      try? originals.reconcileRestores(lease: lease)
    }
    NotificationCenter.default.post(name: GalaxySSIHealthRecords.trendInputsChanged, object: records.owner)
  }

  @MainActor
  private static func restoreWork(_ input: RestoreInput, records: GalaxySSIHealthRecords,
                                  originals: GalaxySSIHealthOriginalStore,
                                  lease: GalaxySSIHealthOriginalStore.RestoreLease) throws
    -> (RestorePreview, GalaxySSIHealthRecords.Archive, [(GalaxySSIHealthOriginalStore.Original, Data)]) {
    let payload = try JSONDecoder().decode(Payload.self, from: input.plaintext)
    guard payload.owner == records.owner, originals.owner == records.owner,
          originals.restoreRecordsFile == records.isolatedFile else { throw Failure.owner }
    var archive = try records.load()
    let local = archive.current
    var latest: [UUID: GalaxySSIHealthReading] = [:]
    for reading in archive.revisions { latest[reading.id] = reading }
    let listing = try originals.list(lease: lease)
    let tables = archive.tableBatches ?? []
    let localTableHashes = Dictionary(tables.map { ($0.id, digest($0.data)) }, uniquingKeysWith: { first, _ in first })
    var snapshot = latest.values.map { "r:\($0.id):\($0.revision):\($0.deleted)" }
    snapshot += localTableHashes.map { "t:\($0.key):\($0.value)" }
    snapshot += listing.originals.map { "o:\($0.id):\($0.sha256)" }
    snapshot.append("unavailable:\(listing.unavailable)")
    var conflicts: [GalaxySSIHealthReading] = []
    var duplicates = 0
    var additions: [GalaxySSIHealthReading] = []
    for var reading in payload.readings {
      if let existing = latest[reading.id] {
        var normalized = reading
        normalized.revision = existing.revision
        if existing == normalized {
          duplicates += 1
        } else { conflicts.append(reading) }
      } else if local.contains(where: { $0.sameMeasurement(as: reading) }) ||
        archive.revisions.contains(where: { existing in
          guard let receipt = reading.bluetoothReceipt, let previous = existing.bluetoothReceipt else { return false }
          return receipt.isReplay(of: previous)
        }) {
        duplicates += 1
      } else {
        reading.revision = 1
        additions.append(reading)
      }
    }
    let newTables = payload.tables.filter { localTableHashes[$0.id] == nil }
    let combinedTables = tables + newTables
    guard combinedTables.count <= 30,
          combinedTables.reduce(0, { $0 + $1.data.count }) <= 12 * GalaxySSIHealthTableImport.maximumBytes
    else { throw Failure.limit }
    let combinedHashes = Dictionary(combinedTables.map { ($0.id, digest($0.data)) },
      uniquingKeysWith: { first, _ in first })
    let missingTables = Set(additions.compactMap(\.tableSource)
      .filter { combinedHashes[$0.batch] != $0.sha256 }.map(\.batch)).count
    var missing = payload.unreadableOriginals + missingTables
    var files: [(GalaxySSIHealthOriginalStore.Original, Data)] = []
    var usedDigests = Set<String>()
    var newFiles = 0
    for file in payload.originals {
      let candidates = listing.originals.filter { $0.sha256 == file.manifest.sha256 }
      if candidates.contains(where: { (try? originals.read($0, lease: lease)) != nil }) {
        snapshot.append("verified:\(file.manifest.sha256)")
        continue
      }
      guard let bytes = file.bytes else { missing += 1; continue }
      guard usedDigests.insert(file.manifest.sha256).inserted else { continue }
      try GalaxySSIHealthOriginalStore.validateRestoreOriginal(file.manifest, data: bytes)
      if let repair = candidates.first {
        files.append((repair, bytes))
        snapshot.append("repair:\(repair.id)")
      } else {
        guard !(try originals.containsRestoreID(file.manifest.id)) else { missing += 1; continue }
        files.append((file.manifest, bytes))
        newFiles += 1
      }
    }
    guard listing.originals.count + listing.unavailable + newFiles <= 500,
          listing.originals.reduce(0, { $0 + $1.bytes }) + files.reduce(0, { $0 + $1.1.count }) <= 512 * 1024 * 1024
    else { throw Failure.limit }
    archive.revisions.append(contentsOf: additions)
    archive.tableBatches = combinedTables
    let preview = RestorePreview(readings: additions.count, duplicates: duplicates, conflicts: conflicts,
      originals: files.count, tables: newTables.count, missing: missing, snapshot: snapshot.sorted())
    return (preview, archive, files)
  }
}
