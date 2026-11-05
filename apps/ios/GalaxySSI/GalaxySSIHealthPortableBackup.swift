import CryptoKit
import Foundation
import Security

enum GalaxySSIHealthPortableBackup {
  static let maximumFileBytes = 48 * 1024 * 1024
  private static let maximumSourceBytes = 32 * 1024 * 1024
  private static let magicV1 = Data("GalaxySSI-Health-Backup-v1\n".utf8)
  private static let magic = Data("GalaxySSI-Health-Backup-v2\n".utf8)
  private static let maximumLinks = 20_000
  private static let saltSize = 16
  private static let iterationsV1 = 600_000

  enum Failure: Error { case invalid, limit, stale, password, owner }

  struct Summary: Sendable, Equatable {
    let readings: Int
    let originals: Int
    let tables: Int
    let links: Int
    let secondaryLinks: Int
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
    let sourceDigest: String
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
    let sourceFrames: [SourceFrame]?
  }

  private struct SourceFrame: Codable {
    let report: GalaxySSIHealthReportReview.Evidence?
    let table: GalaxySSIHealthTableImport.Evidence?

    var target: GalaxySSIHealthReportReview.Target? {
      if let report { return report.target }
      return table.map { .init(record: $0.target.record, revision: $0.target.revision) }
    }
  }

  @MainActor
  static func plan(records: GalaxySSIHealthRecords, originals: GalaxySSIHealthOriginalStore) throws -> Plan {
    let archive = try records.load()
    let listing = try originals.list()
    let readings = archive.current
    return try makePlan(readings, listing: listing, tables: archivedTables(archive.tableBatches ?? []),
                        frames: sourceFrames(archive, readings: readings))
  }

  @MainActor
  static func prepare(_ expected: Plan, records: GalaxySSIHealthRecords,
                      originals: GalaxySSIHealthOriginalStore) throws -> (Data, Summary) {
    let archive = try records.load()
    let readings = archive.current
    let listing = try originals.list()
    let tables = archivedTables(archive.tableBatches ?? [])
    let frames = sourceFrames(archive, readings: readings)
    guard try makePlan(readings, listing: listing, tables: tables, frames: frames) == expected else { throw Failure.stale }
    guard expected.summary.estimatedBytes <= maximumSourceBytes, readings.count <= 10_000 else { throw Failure.limit }
    let files = listing.originals.map { OriginalFile(manifest: $0, bytes: try? originals.read($0)) }
    let payload = Payload(owner: records.owner, readings: readings, originals: files, tables: tables,
                          unreadableOriginals: listing.unavailable, sourceFrames: frames)
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
    let version2 = archive.starts(with: magic)
    guard archive.count <= maximumFileBytes, archive.count > headerCount + 28, version2 || archive.starts(with: magicV1)
    else { throw Failure.invalid }
    let header = Data(archive.prefix(headerCount))
    let salt = Data(header.suffix(saltSize))
    let key = try key(password, salt: salt)
    try Task.checkCancellation()
    let box = try AES.GCM.SealedBox(combined: Data(archive.dropFirst(headerCount)))
    let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
    try Task.checkCancellation()
    let payload = try JSONDecoder().decode(Payload.self, from: plaintext)
    guard (payload.sourceFrames != nil) == version2 else { throw Failure.invalid }
    return RestoreInput(plaintext: plaintext, summary: try validate(payload))
  }

  private static func key(_ password: String, salt: Data) throws -> SymmetricKey {
    guard password.count >= 8, password.utf8.count <= 1_024 else { throw Failure.password }
    return SymmetricKey(data: try GalaxySSIBackupManager.pbkdf2SHA256(
      password: password, salt: salt, iterations: iterationsV1, keyByteCount: 32))
  }

  private static func archivedTables(_ tables: [GalaxySSIHealthTableImport.Batch]) -> [GalaxySSIHealthTableImport.Batch] {
    tables.filter { !$0.data.isEmpty }
  }

  private static func makePlan(_ readings: [GalaxySSIHealthReading], listing: GalaxySSIHealthOriginalStore.Listing,
                               tables: [GalaxySSIHealthTableImport.Batch], frames: [SourceFrame]) throws -> Plan {
    guard frames.count <= maximumLinks else { throw Failure.limit }
    let hashes = tables.map { ($0.id, digest($0.data)) }
    let present = Dictionary(hashes, uniquingKeysWith: { first, _ in first })
    let links = readings.compactMap(\.tableSource) + frames.compactMap { $0.table?.source }
    let reports = readings.compactMap(\.reportSource) + frames.compactMap { $0.report?.source }
    let originals = Dictionary(uniqueKeysWithValues: listing.originals.filter { $0.kind == .pdf }.map { ($0.id, $0.sha256) })
    let absent = Set(links.filter { present[$0.batch] != $0.sha256 }.map(\.batch)).count +
      Set(reports.filter { originals[$0.original] != $0.sha256 }.map(\.original)).count
    let size = listing.originals.reduce(0) { $0 + $1.bytes } + tables.reduce(0) { $0 + $1.data.count }
    let summary = Summary(readings: readings.count, originals: listing.originals.count, tables: tables.count,
                          links: links.count + reports.count, secondaryLinks: frames.count,
                          missing: listing.unavailable + absent, estimatedBytes: size,
                          start: readings.last?.measuredAt, end: readings.first?.measuredAt)
    return Plan(summary: summary,
      readingVersions: readings.map { "\($0.id):\($0.revision)" },
      originalDigests: listing.originals.map { "\($0.id):\($0.sha256)" },
      tableDigests: hashes.map { "\($0.0):\($0.1)" }, sourceDigest: try framesDigest(frames))
  }

  private static func sourceFrames(_ archive: GalaxySSIHealthRecords.Archive,
                                   readings: [GalaxySSIHealthReading]) -> [SourceFrame] {
    let versions = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0.revision) })
    let reports = (archive.reportEvidence ?? []).filter { versions[$0.target.record] == $0.target.revision }
    let tables = (archive.tableEvidence ?? []).filter { versions[$0.target.record] == $0.target.revision }
    return reports.map { .init(report: $0, table: nil) } + tables.map { .init(report: nil, table: $0) }
  }

  private static func framesDigest(_ frames: [SourceFrame]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return digest(try encoder.encode(frames))
  }

  private static func validDigest(_ hash: String) -> Bool {
    hash.utf8.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
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
    let frames = payload.sourceFrames ?? []
    guard frames.count <= maximumLinks else { throw Failure.limit }
    let versions = Dictionary(uniqueKeysWithValues: payload.readings.map { ($0.id, $0.revision) })
    for frame in frames {
      guard (frame.report == nil) != (frame.table == nil), let target = frame.target,
            versions[target.record] == target.revision else { throw Failure.invalid }
      if let report = frame.report {
        guard report.source.fromOCR, report.source.page >= 0, report.source.region >= 0,
              validDigest(report.source.sha256), !report.excerpt.isEmpty, report.excerpt.count <= 500,
              report.excerpt.utf8.count <= 8_192 else { throw Failure.invalid }
      }
      if let table = frame.table {
        let source = table.source
        guard source.row >= 0, validDigest(source.sha256),
              (source.sheet?.utf8.count ?? 0) <= 1_024, (source.worksheetPath?.utf8.count ?? 0) <= 1_024,
              (source.columns?.count ?? 0) <= 64,
              source.columns?.allSatisfy({ $0.key.utf8.count <= 128 && (0..<64).contains($0.value) }) != false
        else { throw Failure.invalid }
      }
    }
    let links = payload.readings.compactMap(\.tableSource) + frames.compactMap { $0.table?.source }
    let reports = payload.readings.compactMap(\.reportSource) + frames.compactMap { $0.report?.source }
    missing += Set(links.filter { tables[$0.batch] != $0.sha256 }.map(\.batch)).count
    let originalHashes = Dictionary(uniqueKeysWithValues: payload.originals.filter { $0.manifest.kind == .pdf }
      .map { ($0.manifest.id, $0.manifest.sha256) })
    missing += Set(reports.filter { originalHashes[$0.original] != $0.sha256 }.map(\.original)).count
    let dates = payload.readings.map(\.measuredAt)
    return Summary(readings: payload.readings.count, originals: payload.originals.count, tables: payload.tables.count,
                   links: links.count + reports.count, secondaryLinks: frames.count, missing: missing,
                   estimatedBytes: size, start: dates.min(), end: dates.max())
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

extension GalaxySSIHealthPortableBackup {
  struct RestoreConflict: Identifiable, Equatable {
    enum Restriction: Equatable { case deleted, source, draft, ambiguous, revisionLimit }
    let local: GalaxySSIHealthReading
    let backup: GalaxySSIHealthReading
    let restriction: Restriction?
    var id: UUID { backup.id }
  }

  struct RestorePreview: Equatable {
    let readings: Int
    let duplicates: Int
    let conflicts: [RestoreConflict]
    let originals: Int
    let tables: Int
    let missing: Int
    let newLinks: Int
    let reusedLinks: Int
    let skippedLinks: Int
    fileprivate let repairedLinks: Int
    fileprivate let snapshot: [String]

    var hasChanges: Bool { readings + originals + tables + newLinks + repairedLinks > 0 }
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
                      originals: GalaxySSIHealthOriginalStore, replacing selected: Set<UUID> = []) throws {
    try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let (fresh, proposed, files) = try restoreWork(input, records: records, originals: originals, lease: lease)
      let accepted = fresh.conflicts.filter { selected.contains($0.id) && $0.restriction == nil }
      guard fresh == expected, fresh.hasChanges || !selected.isEmpty,
            accepted.count == selected.count else { throw Failure.stale }
      var archive = proposed
      let unchanged = archive.current.filter { !selected.contains($0.id) }
      var replacements: [GalaxySSIHealthReading] = []
      for conflict in accepted {
        guard conflict.local.revision < Int.max,
              !(unchanged + replacements).contains(where: { $0.sameMeasurement(as: conflict.backup) })
        else { throw Failure.stale }
        var revision = conflict.backup
        revision.revision = conflict.local.revision + 1
        replacements.append(revision)
      }
      archive.revisions.append(contentsOf: replacements)
      let receipt = UUID()
      do {
        try originals.stageRestore(files, receipt: receipt, lease: lease)
        try records.commitRestore(archive, receipt: receipt, notify: false)
      } catch {
        try? originals.reconcileRestores(lease: lease)
        throw error
      }
      // The receipt is the publication point. Later access retries interrupted promotion.
      try? originals.reconcileRestores(lease: lease)
    }
    NotificationCenter.default.post(name: GalaxySSIHealthRecords.recordsChanged, object: records.owner)
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
    var pendingConflicts: [(GalaxySSIHealthReading, GalaxySSIHealthReading)] = []
    var duplicates = 0
    var additions: [GalaxySSIHealthReading] = []
    for var reading in payload.readings {
      if let existing = latest[reading.id] {
        var normalized = reading
        normalized.revision = existing.revision
        if existing == normalized {
          duplicates += 1
        } else { pendingConflicts.append((existing, reading)) }
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
    var tableDigests = Set(tables.filter { $0.undone == nil && !$0.data.isEmpty }.map { digest($0.data) })
    let primaryTables = Set(payload.readings.compactMap { $0.tableSource?.batch })
    let newTables = payload.tables.filter {
      guard localTableHashes[$0.id] == nil else { return false }
      let newDigest = tableDigests.insert(digest($0.data)).inserted
      return payload.sourceFrames == nil || primaryTables.contains($0.id) || newDigest
    }
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
        guard !(try originals.containsRestoreID(file.manifest.id, lease: lease)) else { missing += 1; continue }
        files.append((file.manifest, bytes))
        newFiles += 1
      }
    }
    guard listing.originals.count + listing.unavailable + newFiles <= 500,
          listing.originals.reduce(0, { $0 + $1.bytes }) + files.reduce(0, { $0 + $1.1.count }) <= 512 * 1024 * 1024
    else { throw Failure.limit }
    let staged = Dictionary(uniqueKeysWithValues: files.filter { $0.0.kind == .pdf }.map { ($0.0.id, $0.0.sha256) })
    let originalsByID = Dictionary(uniqueKeysWithValues: listing.originals.map { ($0.id, $0) })
    var verifiedReports: [UUID: String] = [:]
    var unavailableReports = Set<UUID>()
    func reportIsAvailable(_ source: GalaxySSIHealthReportReview.Source) -> Bool {
      if let digest = staged[source.original] ?? verifiedReports[source.original] { return digest == source.sha256 }
      guard !unavailableReports.contains(source.original), let original = originalsByID[source.original],
            original.kind == .pdf, original.sha256 == source.sha256 else { return false }
      guard (try? originals.read(original, lease: lease)) != nil else {
        unavailableReports.insert(source.original)
        return false
      }
      verifiedReports[source.original] = original.sha256
      return true
    }
    let measurements = local + additions
    let conflicts = pendingConflicts.map { existing, incoming in
      let restriction: RestoreConflict.Restriction?
      if existing.deleted { restriction = .deleted }
      else if archive.draft?.existing?.id == existing.id { restriction = .draft }
      else if existing.revision == Int.max { restriction = .revisionLimit }
      else if existing.metric != incoming.metric || existing.bluetoothReceipt != incoming.bluetoothReceipt ||
                existing.healthKitSource != incoming.healthKitSource ||
                existing.reportSource != incoming.reportSource || existing.tableSource != incoming.tableSource ||
                incoming.reportSource.map({ !reportIsAvailable($0) }) == true ||
                incoming.tableSource.map({ combinedHashes[$0.batch] != $0.sha256 }) == true {
        restriction = .source
      } else if measurements.contains(where: { $0.id != existing.id && $0.sameMeasurement(as: incoming) }) {
        restriction = .ambiguous
      } else { restriction = nil }
      return RestoreConflict(local: existing, backup: incoming, restriction: restriction)
    }
    archive.revisions.append(contentsOf: additions)
    archive.tableBatches = combinedTables
    let links = try restoreSourceFrames(payload.sourceFrames ?? [], readings: payload.readings,
      archive: &archive, previous: latest, listing: listing, staged: files, originals: originals, lease: lease)
    if let fingerprint = links.fingerprint { snapshot.append(fingerprint) }
    let preview = RestorePreview(readings: additions.count, duplicates: duplicates, conflicts: conflicts,
      originals: files.count, tables: newTables.count, missing: missing + links.missing,
      newLinks: links.added, reusedLinks: links.reused, skippedLinks: links.skipped,
      repairedLinks: links.repaired, snapshot: snapshot.sorted())
    return (preview, archive, files)
  }

  private enum SourceSlot: Hashable {
    case report(String, Int, Int, Bool)
    case table(String, String?, Int)

    init(_ source: GalaxySSIHealthReportReview.Source) {
      self = .report(source.sha256, source.page, source.region, source.fromOCR)
    }

    init(_ source: GalaxySSIHealthTableImport.Source) {
      self = .table(source.sha256, source.worksheetPath ?? source.sheet, source.row)
    }
  }

  private struct SourceRestore {
    var added = 0
    var reused = 0
    var skipped = 0
    var repaired = 0
    var missing = 0
    var fingerprint: String?
  }

  @MainActor
  private static func restoreSourceFrames(_ frames: [SourceFrame], readings: [GalaxySSIHealthReading],
    archive: inout GalaxySSIHealthRecords.Archive, previous: [UUID: GalaxySSIHealthReading],
    listing: GalaxySSIHealthOriginalStore.Listing, staged: [(GalaxySSIHealthOriginalStore.Original, Data)],
    originals: GalaxySSIHealthOriginalStore, lease: GalaxySSIHealthOriginalStore.RestoreLease) throws -> SourceRestore {
    guard !frames.isEmpty else { return .init() }
    typealias Target = GalaxySSIHealthReportReview.Target
    let referenced = Set(frames.compactMap { $0.target?.record })
    let current = archive.current
    let live = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
    var targets: [UUID: Target] = [:]
    func matches(_ local: GalaxySSIHealthReading, _ backup: GalaxySSIHealthReading) -> Bool {
      var normalized = backup
      normalized.id = local.id
      normalized.revision = local.revision
      return local == normalized
    }
    for reading in readings where referenced.contains(reading.id) {
      if let exact = live[reading.id] {
        if matches(exact, reading) { targets[reading.id] = .init(record: exact.id, revision: exact.revision) }
      } else if previous[reading.id] == nil {
        let candidates = current.lazy.filter { matches($0, reading) }.prefix(2)
        if candidates.count == 1, let existing = candidates.first {
          targets[reading.id] = .init(record: existing.id, revision: existing.revision)
        }
      }
    }

    let reportHashes = Set(frames.compactMap { $0.report?.source.sha256 })
    var reportIDs: [String: UUID] = [:]
    var availableReports: [UUID: String] = [:]
    for (original, _) in staged where original.kind == .pdf && reportHashes.contains(original.sha256) {
      reportIDs[original.sha256] = original.id
      availableReports[original.id] = original.sha256
    }
    for original in listing.originals where original.kind == .pdf && reportHashes.contains(original.sha256) {
      if availableReports[original.id] == original.sha256 || (try? originals.read(original, lease: lease)) != nil {
        if reportIDs[original.sha256] == nil { reportIDs[original.sha256] = original.id }
        availableReports[original.id] = original.sha256
      }
    }
    var tableIDs: [String: UUID] = [:]
    var availableTables: [UUID: String] = [:]
    for batch in archive.tableBatches ?? [] where batch.undone == nil && !batch.data.isEmpty {
      let hash = digest(batch.data)
      if tableIDs[hash] == nil { tableIDs[hash] = batch.id }
      availableTables[batch.id] = hash
    }

    var slots: [SourceSlot: Set<Target>] = [:]
    func reserve(_ slot: SourceSlot, for target: Target) { slots[slot, default: []].insert(target) }
    for reading in current {
      let target = Target(record: reading.id, revision: reading.revision)
      if let source = reading.reportSource { reserve(SourceSlot(source), for: target) }
      if let source = reading.tableSource { reserve(SourceSlot(source), for: target) }
    }
    var priorReports = archive.reportEvidence ?? []
    var priorTables = archive.tableEvidence ?? []
    var reportOffsets: [SourceSlot: Int] = [:]
    var tableOffsets: [SourceSlot: Int] = [:]
    for (index, link) in priorReports.enumerated() where live[link.target.record] != nil {
      let slot = SourceSlot(link.source)
      reserve(slot, for: link.target)
      reportOffsets[slot] = index
    }
    for (index, link) in priorTables.enumerated() where live[link.target.record] != nil {
      let slot = SourceSlot(link.source)
      reserve(slot, for: .init(record: link.target.record, revision: link.target.revision))
      tableOffsets[slot] = index
    }

    var result = SourceRestore()
    var added: [SourceFrame] = []
    var missing = Set<String>()
    for frame in frames {
      guard let record = frame.target?.record, let target = targets[record],
            archive.draft?.existing?.id != target.record else { result.skipped += 1; continue }
      let slot: SourceSlot
      let mapped: SourceFrame
      if let link = frame.report {
        let source = link.source
        slot = SourceSlot(source)
        if reportIDs[source.sha256] == nil { missing.insert("pdf:\(source.sha256)") }
        mapped = .init(report: .init(target: target, source: .init(original: reportIDs[source.sha256] ?? source.original,
          sha256: source.sha256, page: source.page, region: source.region, fromOCR: source.fromOCR), excerpt: link.excerpt),
          table: nil)
      } else if let link = frame.table {
        let source = link.source
        slot = SourceSlot(source)
        if tableIDs[source.sha256] == nil { missing.insert("table:\(source.sha256)") }
        mapped = .init(report: nil, table: .init(target: .init(record: target.record, revision: target.revision),
          source: .init(batch: tableIDs[source.sha256] ?? source.batch, row: source.row, sha256: source.sha256,
            sheet: source.sheet, worksheetPath: source.worksheetPath, columns: source.columns)))
      } else { throw Failure.invalid }
      if let owners = slots[slot] {
        guard owners == Set([target]) else { result.skipped += 1; continue }
        result.reused += 1
        if let link = mapped.report, let index = reportOffsets[slot], reportIDs[link.source.sha256] != nil,
           availableReports[priorReports[index].source.original] != link.source.sha256 {
          let existing = priorReports[index]
          priorReports[index] = .init(target: existing.target, source: link.source, excerpt: existing.excerpt)
          result.repaired += 1
        }
        if let link = mapped.table, let index = tableOffsets[slot], tableIDs[link.source.sha256] != nil,
           availableTables[priorTables[index].source.batch] != link.source.sha256 {
          let existing = priorTables[index]
          let source = existing.source
          priorTables[index] = .init(target: existing.target, source: .init(batch: link.source.batch,
            row: source.row, sha256: source.sha256, sheet: source.sheet, worksheetPath: source.worksheetPath,
            columns: source.columns))
          result.repaired += 1
        }
      } else {
        reserve(slot, for: target)
        added.append(mapped)
      }
    }
    let reports = added.compactMap(\.report)
    let tables = added.compactMap(\.table)
    guard priorReports.count + reports.count <= 5_000, priorTables.count + tables.count <= maximumLinks
    else { throw Failure.limit }
    if !reports.isEmpty || result.repaired > 0 { archive.reportEvidence = priorReports + reports }
    if !tables.isEmpty || result.repaired > 0 { archive.tableEvidence = priorTables + tables }
    result.added = added.count
    result.missing = missing.count
    result.fingerprint = "links:\(try framesDigest(sourceFrames(archive, readings: current)))"
    return result
  }
}
