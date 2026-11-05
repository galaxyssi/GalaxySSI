import CryptoKit
import Foundation
import Security

enum GalaxySSIHealthPortableBackup {
  static let maximumFileBytes = 48 * 1024 * 1024
  private static let maximumSourceBytes = 32 * 1024 * 1024
  private static let magicV1 = Data("GalaxySSI-Health-Backup-v1\n".utf8)
  private static let magic = Data("GalaxySSI-Health-Backup-v2\n".utf8)
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
    let secondarySources: [SecondarySources?]
    let originalDigests: [String]
    let tableDigests: [String]
  }

  private struct OriginalFile: Codable {
    let manifest: GalaxySSIHealthOriginalStore.Original
    let bytes: Data?
  }

  private struct Payload: Codable {
    let owner: String?
    var readings: [GalaxySSIHealthReading]
    let originals: [OriginalFile]
    let tables: [GalaxySSIHealthTableImport.Batch]
    let unreadableOriginals: Int
    var sourceFrames: [SourceFrame]?
  }

  struct SecondarySources: Codable, Equatable {
    var reports: [GalaxySSIHealthReportReview.Source] = []
    var tables: [GalaxySSIHealthTableImport.Source] = []
  }

  private struct SourceFrame: Codable {
    let record: UUID
    let revision: Int
    let report: GalaxySSIHealthReportReview.Source?
    let table: GalaxySSIHealthTableImport.Source?
    let secondary: SecondarySources?
  }

  @MainActor
  static func plan(records: GalaxySSIHealthRecords, originals: GalaxySSIHealthOriginalStore) throws -> Plan {
    let archive = try records.load()
    let listing = try originals.list()
    return makePlan(readingsWithEvidence(archive), listing: listing, tables: archivedTables(archive.tableBatches ?? []))
  }

  @MainActor
  static func prepare(_ expected: Plan, records: GalaxySSIHealthRecords,
                      originals: GalaxySSIHealthOriginalStore) throws -> (Data, Summary) {
    let archive = try records.load()
    let readings = readingsWithEvidence(archive)
    let listing = try originals.list()
    let tables = archivedTables(archive.tableBatches ?? [])
    guard makePlan(readings, listing: listing, tables: tables) == expected else { throw Failure.stale }
    guard expected.summary.estimatedBytes <= maximumSourceBytes, readings.count <= 10_000 else { throw Failure.limit }
    let files = listing.originals.map { OriginalFile(manifest: $0, bytes: try? originals.read($0)) }
    let payload = Payload(owner: records.owner, readings: readings, originals: files, tables: tables,
                          unreadableOriginals: listing.unavailable)
    let summary = try validate(payload)
    var framed = payload
    framed.sourceFrames = readings.compactMap { reading in
      guard reading.reportSource != nil || reading.tableSource != nil || reading.secondarySources != nil else { return nil }
      return .init(record: reading.id, revision: reading.revision, report: reading.reportSource,
                   table: reading.tableSource, secondary: reading.secondarySources)
    }
    framed.readings = readings.map { reading in
      var item = reading
      item.reportSource = nil; item.tableSource = nil; item.secondarySources = nil
      return item
    }
    let data = try JSONEncoder().encode(framed)
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
    fileprivate let framed: Bool
  }

  static func unlock(_ archive: Data, password: String) throws -> RestoreInput {
    let headerCount = magic.count + saltSize
    let framed = archive.starts(with: magic)
    guard archive.count <= maximumFileBytes, archive.count > headerCount + 28, framed || archive.starts(with: magicV1)
    else { throw Failure.invalid }
    let header = Data(archive.prefix(headerCount))
    let salt = Data(header.suffix(saltSize))
    let key = try key(password, salt: salt)
    try Task.checkCancellation()
    let box = try AES.GCM.SealedBox(combined: Data(archive.dropFirst(headerCount)))
    let plaintext = try AES.GCM.open(box, using: key, authenticating: header)
    try Task.checkCancellation()
    return RestoreInput(plaintext: plaintext, summary: try validate(decode(plaintext, framed: framed)), framed: framed)
  }

  private static func decode(_ data: Data, framed: Bool) throws -> Payload {
    var payload = try JSONDecoder().decode(Payload.self, from: data)
    guard framed else {
      guard payload.sourceFrames == nil else { throw Failure.invalid }
      return payload
    }
    guard let frames = payload.sourceFrames, frames.count <= payload.readings.count, payload.readings.count <= 10_000
    else { throw Failure.limit }
    var offsets: [UUID: Int] = [:]
    for (index, reading) in payload.readings.enumerated() {
      guard offsets.updateValue(index, forKey: reading.id) == nil, reading.reportSource == nil,
            reading.tableSource == nil, reading.secondarySources == nil else { throw Failure.invalid }
    }
    for frame in frames {
      guard let index = offsets.removeValue(forKey: frame.record), payload.readings[index].revision == frame.revision,
            frame.report != nil || frame.table != nil || frame.secondary != nil else { throw Failure.invalid }
      payload.readings[index].reportSource = frame.report
      payload.readings[index].tableSource = frame.table
      payload.readings[index].secondarySources = frame.secondary
    }
    return payload
  }

  private static func key(_ password: String, salt: Data) throws -> SymmetricKey {
    guard password.count >= 8, password.utf8.count <= 1_024 else { throw Failure.password }
    return SymmetricKey(data: try GalaxySSIBackupManager.pbkdf2SHA256(
      password: password, salt: salt, iterations: iterationsV1, keyByteCount: 32))
  }

  private static func archivedTables(_ tables: [GalaxySSIHealthTableImport.Batch]) -> [GalaxySSIHealthTableImport.Batch] {
    tables.filter { !$0.data.isEmpty }
  }

  private static func readingsWithEvidence(_ archive: GalaxySSIHealthRecords.Archive) -> [GalaxySSIHealthReading] {
    let reports = Dictionary(grouping: archive.reportEvidence ?? [], by: { $0.target.record })
    let tables = Dictionary(grouping: archive.tableEvidence ?? [], by: { $0.target.record })
    return archive.current.map { reading in
      var copy = reading
      var sources = reading.secondarySources ?? .init()
      for link in reports[reading.id] ?? [] where link.target.revision == reading.revision {
        if link.source != reading.reportSource && !sources.reports.contains(link.source) {
          sources.reports.append(link.source)
        }
      }
      for link in tables[reading.id] ?? [] where link.target.revision == reading.revision {
        if link.source != reading.tableSource && !sources.tables.contains(link.source) {
          sources.tables.append(link.source)
        }
      }
      if !sources.reports.isEmpty || !sources.tables.isEmpty { copy.secondarySources = sources }
      return copy
    }
  }

  private static func makePlan(_ readings: [GalaxySSIHealthReading], listing: GalaxySSIHealthOriginalStore.Listing,
                               tables: [GalaxySSIHealthTableImport.Batch]) -> Plan {
    let hashes = tables.map { ($0.id, digest($0.data)) }
    let present = Dictionary(hashes, uniquingKeysWith: { first, _ in first })
    let links = readings.flatMap(tableLinks)
    let reports = readings.flatMap(reportLinks)
    let originalHashes = Dictionary(uniqueKeysWithValues: listing.originals.map { ($0.id, $0.sha256) })
    let absent = Set(links.filter { present[$0.batch] != $0.sha256 }.map(\.batch)).count +
      Set(reports.filter { originalHashes[$0.original] != $0.sha256 }.map(\.original)).count
    let size = listing.originals.reduce(0) { $0 + $1.bytes } + tables.reduce(0) { $0 + $1.data.count }
    let summary = Summary(readings: readings.count, originals: listing.originals.count, tables: tables.count,
                          links: links.count + reports.count, missing: listing.unavailable + absent, estimatedBytes: size,
                          start: readings.last?.measuredAt, end: readings.first?.measuredAt)
    return Plan(summary: summary,
      readingVersions: readings.map { "\($0.id):\($0.revision)" },
      secondarySources: readings.map(\.secondarySources),
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
    guard payload.readings.allSatisfy({ tableLinks($0).count + reportLinks($0).count <= 32 })
    else { throw Failure.limit }
    let links = payload.readings.flatMap(tableLinks)
    let reports = payload.readings.flatMap(reportLinks)
    guard links.count + reports.count <= 20_000,
          links.allSatisfy({ $0.row >= 0 && validDigest($0.sha256) }),
          reports.allSatisfy({ $0.page >= 0 && $0.region >= 0 && validDigest($0.sha256) })
    else { throw Failure.invalid }
    missing += Set(links.filter { tables[$0.batch] != $0.sha256 }.map(\.batch)).count
    let present: [UUID: String] = Dictionary(uniqueKeysWithValues: payload.originals.compactMap { file in
      file.bytes == nil ? nil : (file.manifest.id, file.manifest.sha256)
    })
    missing += Set(reports.filter { present[$0.original] != $0.sha256 }.map(\.original)).count
    let dates = payload.readings.map(\.measuredAt)
    return Summary(readings: payload.readings.count, originals: payload.originals.count, tables: payload.tables.count,
                   links: links.count + reports.count, missing: missing, estimatedBytes: size, start: dates.min(), end: dates.max())
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func validDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func reportLinks(_ reading: GalaxySSIHealthReading) -> [GalaxySSIHealthReportReview.Source] {
    (reading.reportSource.map { [$0] } ?? []) + (reading.secondarySources?.reports ?? [])
  }

  private static func tableLinks(_ reading: GalaxySSIHealthReading) -> [GalaxySSIHealthTableImport.Source] {
    (reading.tableSource.map { [$0] } ?? []) + (reading.secondarySources?.tables ?? [])
  }
}

extension GalaxySSIHealthPortableBackup {
  struct RestoreConflict: Identifiable, Equatable {
    enum Restriction: Equatable { case deleted, source, draft, ambiguous }
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
    fileprivate let snapshot: [String]

    var hasChanges: Bool { readings + originals + tables + newLinks > 0 }
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
        revision.secondarySources = conflict.local.secondarySources
        replacements.append(revision)
      }
      archive.revisions.append(contentsOf: replacements)
      guard var index = archive.originalIndex else { throw Failure.stale }
      index.include(files.map(\.0))
      archive.originalIndex = index
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
    let payload = try decode(input.plaintext, framed: input.framed)
    guard payload.owner == records.owner, originals.owner == records.owner,
          originals.restoreRecordsFile == records.isolatedFile else { throw Failure.owner }
    let listing = try originals.list(lease: lease)
    var archive = try records.load()
    let local = archive.current
    var latest: [UUID: GalaxySSIHealthReading] = [:]
    for reading in archive.revisions { latest[reading.id] = reading }
    let tables = archive.tableBatches ?? []
    let localTableHashes = Dictionary(tables.map { ($0.id, digest($0.data)) }, uniquingKeysWith: { first, _ in first })
    var snapshot = latest.values.map { "r:\($0.id):\($0.revision):\($0.deleted)" }
    snapshot += localTableHashes.map { "t:\($0.key):\($0.value)" }
    snapshot += listing.originals.map { "o:\($0.id):\($0.sha256)" }
    snapshot.append("unavailable:\(listing.unavailable)")
    var conflicts: [RestoreConflict] = []
    var duplicates = 0
    var skippedLinks = 0
    var additions: [GalaxySSIHealthReading] = []
    var matchingIDs: [(GalaxySSIHealthReading, GalaxySSIHealthReading)] = []
    for var reading in payload.readings {
      if let existing = latest[reading.id] {
        matchingIDs.append((existing, reading))
      } else if local.contains(where: { $0.sameMeasurement(as: reading) }) ||
        archive.revisions.contains(where: { existing in
          guard let receipt = reading.bluetoothReceipt, let previous = existing.bluetoothReceipt else { return false }
          return receipt.isReplay(of: previous)
        }) {
        duplicates += 1
        skippedLinks += reportLinks(reading).count + tableLinks(reading).count
      } else {
        reading.revision = 1
        additions.append(reading)
      }
    }
    var tableTargets = Dictionary(tables.map { (digest($0.data), $0.id) }, uniquingKeysWith: { first, _ in first })
    var tableIDs: [UUID: UUID] = [:]
    var newTables: [GalaxySSIHealthTableImport.Batch] = []
    for batch in payload.tables {
      let hash = digest(batch.data)
      if let target = tableTargets[hash] { tableIDs[batch.id] = target }
      else if localTableHashes[batch.id] == nil {
        tableTargets[hash] = batch.id
        tableIDs[batch.id] = batch.id
        newTables.append(batch)
      }
    }
    let combinedTables = tables + newTables
    guard combinedTables.count <= 30,
          combinedTables.reduce(0, { $0 + $1.data.count }) <= 12 * GalaxySSIHealthTableImport.maximumBytes
    else { throw Failure.limit }
    let combinedHashes = Dictionary(combinedTables.map { ($0.id, digest($0.data)) },
      uniquingKeysWith: { first, _ in first })
    var missing = payload.unreadableOriginals
    var files: [(GalaxySSIHealthOriginalStore.Original, Data)] = []
    var originalTargets: [String: UUID] = [:]
    var newFiles = 0
    for file in payload.originals {
      let candidates = listing.originals.filter { $0.sha256 == file.manifest.sha256 }
      if originalTargets[file.manifest.sha256] != nil { continue }
      if let verified = candidates.first(where: { (try? originals.read($0, lease: lease)) != nil }) {
        snapshot.append("verified:\(file.manifest.sha256)")
        originalTargets[file.manifest.sha256] = verified.id
        continue
      }
      guard let bytes = file.bytes else { missing += 1; continue }
      try GalaxySSIHealthOriginalStore.validateRestoreOriginal(file.manifest, data: bytes)
      if let repair = candidates.first {
        files.append((repair, bytes))
        originalTargets[file.manifest.sha256] = repair.id
        snapshot.append("repair:\(repair.id)")
      } else {
        guard !(try originals.containsRestoreID(file.manifest.id)) else { missing += 1; continue }
        files.append((file.manifest, bytes))
        originalTargets[file.manifest.sha256] = file.manifest.id
        newFiles += 1
      }
    }
    let referencedDigests = Set(payload.readings.flatMap(reportLinks).map(\.sha256))
    for candidate in listing.originals where originalTargets[candidate.sha256] == nil &&
      referencedDigests.contains(candidate.sha256) {
      if (try? originals.read(candidate, lease: lease)) != nil {
        originalTargets[candidate.sha256] = candidate.id
        snapshot.append("verified:\(candidate.id):\(candidate.sha256)")
      }
    }
    guard listing.originals.count + listing.unavailable + newFiles <= 500,
          listing.originals.reduce(0, { $0 + $1.bytes }) + files.reduce(0, { $0 + $1.1.count }) <= 512 * 1024 * 1024
    else { throw Failure.limit }
    func mappedReport(_ link: GalaxySSIHealthReportReview.Source) -> GalaxySSIHealthReportReview.Source {
      guard let target = originalTargets[link.sha256] else { return link }
      return .init(original: target, sha256: link.sha256, page: link.page, region: link.region,
        fromOCR: link.fromOCR, evidenceKey: link.evidenceKey, documentOrder: link.documentOrder,
        cropRevision: link.cropRevision)
    }
    func mappedTable(_ link: GalaxySSIHealthTableImport.Source) -> GalaxySSIHealthTableImport.Source {
      guard let target = tableIDs[link.batch] ?? tableTargets[link.sha256], combinedHashes[target] == link.sha256
      else { return link }
      return .init(batch: target, row: link.row, sha256: link.sha256, sheet: link.sheet,
                   worksheetPath: link.worksheetPath, columns: link.columns)
    }
    func mapped(_ reading: GalaxySSIHealthReading) -> GalaxySSIHealthReading {
      var item = reading
      item.reportSource = item.reportSource.map(mappedReport)
      item.tableSource = item.tableSource.map(mappedTable)
      item.secondarySources = item.secondarySources.map {
        SecondarySources(reports: $0.reports.map(mappedReport), tables: $0.tables.map(mappedTable))
      }
      return item
    }
    func withoutLinks(_ reading: GalaxySSIHealthReading) -> GalaxySSIHealthReading {
      var value = reading
      value.reportSource = nil; value.tableSource = nil; value.secondarySources = nil
      return value
    }
    additions = additions.map(mapped)
    var newLinks = additions.reduce(0) { $0 + reportLinks($1).count + tableLinks($1).count }
    var reusedLinks = 0
    var updates: [GalaxySSIHealthReading] = []
    for (existing, input) in matchingIDs {
      var incoming = mapped(input)
      incoming.revision = existing.revision
      if incoming == existing {
        duplicates += 1
        reusedLinks += reportLinks(incoming).count + tableLinks(incoming).count
      } else if !existing.deleted, existing.revision < Int.max, archive.draft?.existing?.id != existing.id,
                withoutLinks(existing) == withoutLinks(incoming),
                (existing.reportSource == nil || incoming.reportSource == nil || existing.reportSource == incoming.reportSource),
                (existing.tableSource == nil || incoming.tableSource == nil || existing.tableSource == incoming.tableSource) {
        var merged = existing.secondarySources ?? .init()
        var reports = reportLinks(existing), tables = tableLinks(existing)
        var added = 0, reused = 0
        for link in reportLinks(incoming) {
          if reports.contains(link) { reused += 1 } else { reports.append(link); merged.reports.append(link); added += 1 }
        }
        for link in tableLinks(incoming) {
          if tables.contains(link) { reused += 1 } else { tables.append(link); merged.tables.append(link); added += 1 }
        }
        guard reports.count + tables.count <= 32 else { throw Failure.limit }
        reusedLinks += reused
        if added > 0 {
          var update = existing
          update.secondarySources = merged
          update.revision += 1
          updates.append(update)
          newLinks += added
        } else { duplicates += 1 }
      } else {
        let restriction: RestoreConflict.Restriction?
        if existing.deleted { restriction = .deleted }
        else if archive.draft?.existing?.id == existing.id { restriction = .draft }
        else if existing.metric != incoming.metric || existing.bluetoothReceipt != incoming.bluetoothReceipt ||
                  existing.healthKitSource != incoming.healthKitSource || existing.reportSource != incoming.reportSource ||
                  existing.tableSource != incoming.tableSource ||
                  incoming.tableSource.map({ combinedHashes[$0.batch] != $0.sha256 }) == true {
          restriction = .source
        } else if (local + additions).contains(where: { $0.id != existing.id && $0.sameMeasurement(as: incoming) }) {
          restriction = .ambiguous
        } else { restriction = nil }
        conflicts.append(.init(local: existing, backup: incoming, restriction: restriction))
        skippedLinks += reportLinks(input).count + tableLinks(input).count
      }
    }
    let linked = additions + updates
    missing += Set(linked.flatMap(tableLinks).filter { combinedHashes[$0.batch] != $0.sha256 }.map(\.batch)).count
    missing += Set(linked.flatMap(reportLinks).filter { originalTargets[$0.sha256] == nil }.map(\.original)).count
    archive.revisions.append(contentsOf: additions)
    archive.revisions.append(contentsOf: updates)
    archive.tableBatches = combinedTables
    let preview = RestorePreview(readings: additions.count, duplicates: duplicates, conflicts: conflicts,
      originals: files.count, tables: newTables.count, missing: missing, newLinks: newLinks,
      reusedLinks: reusedLinks, skippedLinks: skippedLinks, snapshot: snapshot.sorted())
    return (preview, archive, files)
  }
}
