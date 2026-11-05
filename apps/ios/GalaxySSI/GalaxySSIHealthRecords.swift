import CryptoKit
import Foundation

struct GalaxySSIHealthReading: Codable, Identifiable, Equatable {
  var id = UUID()
  var revision = 0
  var metric: GalaxySSIHealthMetric
  var measuredAt = Date()
  var value: Decimal?
  var diastolic: Decimal?
  var pulse: Decimal?
  var conditions = ""
  var notes = ""
  var deleted = false
  var bluetoothReceipt: GalaxySSIHealthBluetoothReceipt?
  var tableSource: GalaxySSIHealthTableImport.Source?
  var reported: GalaxySSIHealthReportedResult?
  var reportedNotation: String?
  var unitOverride: String?
  var referenceInterval: String?
  var healthKitSource: GalaxySSIHealthKitImport.Source?
  var reportSource: GalaxySSIHealthReportReview.Source?

  var unit: String { unitOverride ?? metric.unit }
  var resultKind: String { reported?.kind.rawValue ?? "number" }

  var isValid: Bool {
    func positive(_ number: Decimal) -> Bool {
      !number.isNaN && number > 0
    }
    guard measuredAt.timeIntervalSinceReferenceDate.isFinite,
          conditions.utf8.count <= 512, notes.utf8.count <= 4096,
          (reportedNotation?.utf8.count ?? 0) <= 128,
          (referenceInterval?.utf8.count ?? 0) <= 512 else { return false }
    if let reported {
      guard value == nil, metric.laboratory, diastolic == nil, pulse == nil,
            reported == GalaxySSIHealthReportedResult.parse(reported.raw, metric: metric)
      else { return false }
      return reported.kind == .qualitative ? unit.isEmpty : metric.units.contains(unit)
    }
    guard let value, !value.isNaN, metric.form != .qualitative, metric.units.contains(unit),
          metric.form == .positive ? value > 0 : value >= 0 else { return false }
    if metric.form == .count {
      var decimal = value, whole = Decimal.zero
      NSDecimalRound(&whole, &decimal, 0, .down)
      guard whole == value else { return false }
    }
    if metric == .bloodPressure {
      guard let diastolic, positive(diastolic), value > diastolic else { return false }
      return pulse.map(positive) ?? true
    }
    return diastolic == nil && pulse == nil
  }

  func sameMeasurement(as other: Self) -> Bool {
    if let device = bluetoothReceipt?.device, let otherDevice = other.bluetoothReceipt?.device,
       device != otherDevice { return false }
    return metric == other.metric && abs(measuredAt.timeIntervalSince(other.measuredAt)) < 60 &&
      unit == other.unit && value == other.value && reported?.canonical == other.reported?.canonical &&
      diastolic == other.diastolic && pulse == other.pulse
  }
}

struct GalaxySSIHealthDraft: Codable, Identifiable, Equatable {
  var id = UUID()
  var existing: GalaxySSIHealthReading?
  var metric: GalaxySSIHealthMetric = .bloodPressure
  var measuredAt = Date()
  var value = ""
  var diastolic = ""
  var pulse = ""
  var conditions = ""
  var notes = ""
  var unitOverride: String?
  var referenceInterval: String?

  var fitsStorageLimits: Bool {
    [value, diastolic, pulse].allSatisfy { $0.utf8.count <= 128 } &&
      conditions.utf8.count <= 512 && notes.utf8.count <= 4096 && (referenceInterval?.utf8.count ?? 0) <= 512
  }
}

struct GalaxySSIHealthOverview {
  enum Freshness: Equatable { case recent, stale, missing }

  struct Metric: Identifiable {
    let metric: GalaxySSIHealthMetric
    let reading: GalaxySSIHealthReading?
    let freshness: Freshness
    var id: GalaxySSIHealthMetric { metric }
  }

  let metrics: [Metric]
  var recentCount: Int { metrics.filter { $0.freshness == .recent }.count }

  init(current: [GalaxySSIHealthReading], now: Date, calendar: Calendar) {
    let today = calendar.startOfDay(for: now)
    let cutoff = calendar.date(byAdding: .day, value: -6, to: today) ?? today
    var latest: [GalaxySSIHealthMetric: GalaxySSIHealthReading] = [:]
    for reading in current where !reading.deleted && reading.measuredAt <= now {
      if let previous = latest[reading.metric], previous.measuredAt >= reading.measuredAt { continue }
      latest[reading.metric] = reading
    }
    let overviewMetrics: [GalaxySSIHealthMetric] = [.bloodPressure, .glucose, .weight, .heartRate]
    metrics = overviewMetrics.map { metric in
      let reading = latest[metric]
      return Metric(metric: metric, reading: reading,
                    freshness: reading.map { $0.measuredAt >= cutoff ? .recent : .stale } ?? .missing)
    }
  }
}

@MainActor
struct GalaxySSIHealthRecords {
  static let trendInputsChanged = Notification.Name("galaxyssi.health.trendInputsChanged")

  enum Failure: Error {
    case invalid, stale, duplicate, unavailable, permission
  }

  enum PrivacyScope: String, Codable {
    case overview, weeklyReport
  }

  struct PrivacyEvent: Codable, Identifiable {
    var id = UUID()
    var at: Date
    var scope: PrivacyScope
    var enabled: Bool
  }

  struct Archive: Codable {
    var reportReview: [GalaxySSIHealthReportReview.Item]?
    var reportEvidence: [GalaxySSIHealthReportReview.Evidence]?
    var version = 1
    var revisions: [GalaxySSIHealthReading] = []
    var draft: GalaxySSIHealthDraft?
    var healthKitSync: [String: GalaxySSIHealthKitSync.Checkpoint]?
    var healthKitSelection: Set<String>?
    var healthKitReadAt: [String: Date]?
    var healthKitErasureLog: [GalaxySSIHealthKitCopies.Erasure]?
    var derivesOverview: Bool?
    var weeklyReportAllowed: Bool?
    var weeklyExportRequests: [GalaxySSIWeeklyHealthReport.ExportRequest]?
    var privacyEvents: [PrivacyEvent]?
    var tableBatches: [GalaxySSIHealthTableImport.Batch]?
    var tableEvidence: [GalaxySSIHealthTableImport.Evidence]?
    var bluetoothErasureLog: [GalaxySSIHealthBluetoothHistory.Erasure]?

    var current: [GalaxySSIHealthReading] {
      var seen = Set<UUID>()
      return revisions.reversed().filter { seen.insert($0.id).inserted && !$0.deleted }
        .sorted { ($0.measuredAt, $0.id.uuidString) > ($1.measuredAt, $1.id.uuidString) }
    }
  }

  let owner: String
  let secrets: GalaxySSISecretStore
  var isolatedFile: URL? = nil

  private var context: Data { Data("galaxyssi.health.records.v1:\(owner)".utf8) }
  private var account: String { "health.records.v1." + owner }
  private var file: URL {
    get throws { try storageFile(context: context, fixtureExtension: nil) }
  }

  private func storageFile(context: Data, fixtureExtension: String?) throws -> URL {
    if let isolatedFile {
      return fixtureExtension.map { isolatedFile.appendingPathExtension($0) } ?? isolatedFile
    }
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true)
    let directory = base.appendingPathComponent("HealthRecords", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                            attributes: [.protectionKey: FileProtectionType.complete])
    var excludedDirectory = directory
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try excludedDirectory.setResourceValues(resources)
    let name = SHA256.hash(data: context).map { String(format: "%02x", $0) }.joined()
    return directory.appendingPathComponent(name)
  }

  private var profileContext: Data { Data("galaxyssi.health.profile.v1:\(owner)".utf8) }
  private var profileAccount: String { "health.profile.v1." + owner }

  func loadProfile() throws -> GalaxySSIHealthProfile {
    let file = try storageFile(context: profileContext, fixtureExtension: "profile")
    let data: Data
    do { data = try Data(contentsOf: file) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return GalaxySSIHealthProfile()
    }
    let box = try AES.GCM.SealedBox(combined: data)
    let payload = try AES.GCM.open(box, using: key(create: false, account: profileAccount), authenticating: profileContext)
    return try JSONDecoder().decode(GalaxySSIHealthProfile.self, from: payload)
  }

  func writeProfile(_ input: GalaxySSIHealthProfile) throws {
    guard input.isValid else { throw Failure.invalid }
    guard try loadProfile().revision == input.revision else { throw Failure.stale }
    var updated = input
    updated.revision = UUID()
    let payload = try JSONEncoder().encode(updated)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: true, account: profileAccount),
                                        authenticating: profileContext).combined else { throw Failure.unavailable }
    try sealed.write(to: storageFile(context: profileContext, fixtureExtension: "profile"),
                     options: [.atomic, .completeFileProtection])
  }

  func load() throws -> Archive {
    let data: Data
    do { data = try Data(contentsOf: file) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return Archive()
    }
    let box = try AES.GCM.SealedBox(combined: data)
    let archive = try JSONDecoder().decode(Archive.self,
      from: AES.GCM.open(box, using: key(create: false), authenticating: context))
    guard archive.version == 1 else { throw Failure.unavailable }
    return archive
  }

  func storeDraft(_ draft: GalaxySSIHealthDraft) throws {
    guard draft.fitsStorageLimits else { throw Failure.invalid }
    var archive = try load()
    if let existing = draft.existing {
      guard let latest = archive.revisions.last(where: { $0.id == existing.id }),
            !latest.deleted, latest.revision == existing.revision else { throw Failure.stale }
    }
    archive.draft = draft
    try persist(archive)
  }

  func previewBluetoothErase(_ device: UUID) throws -> GalaxySSIHealthBluetoothHistory.ErasePlan {
    try makeBluetoothErasePlan(device, archive: load())
  }

  func healthKitCopyCounts() throws -> [String: Int] {
    let archive = try load()
    return Dictionary(uniqueKeysWithValues: GalaxySSIHealthKitImport.Scope.allCases.map { scope in
      let ids = Set(archive.revisions.filter { GalaxySSIHealthKitCopies.includes($0, scope: scope) }.map(\.id))
      return (scope.rawValue, ids.count)
    })
  }

  func previewHealthKitErase(_ scope: GalaxySSIHealthKitImport.Scope) throws -> GalaxySSIHealthKitCopies.Plan {
    try makeHealthKitErasePlan(scope, archive: load())
  }

  func eraseHealthKitCopies(_ expected: GalaxySSIHealthKitCopies.Plan) throws -> Int {
    var archive = try load()
    let current = try makeHealthKitErasePlan(expected.scope, archive: archive)
    guard current == expected else { throw Failure.stale }
    let ids = Set(current.versions.map(\.id))
    archive.revisions.removeAll { ids.contains($0.id) }
    if let existing = archive.draft?.existing, ids.contains(existing.id) { archive.draft = nil }
    archive.tableEvidence?.removeAll { ids.contains($0.target.record) }
    archive.reportEvidence?.removeAll { ids.contains($0.target.record) }
    var audit = archive.healthKitErasureLog ?? []
    audit.append(.init(at: Date(), scope: expected.scope.rawValue, records: current.count))
    archive.healthKitErasureLog = Array(audit.suffix(50))
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return current.count
  }

  private func makeHealthKitErasePlan(_ scope: GalaxySSIHealthKitImport.Scope, archive: Archive) throws
    -> GalaxySSIHealthKitCopies.Plan {
    let versions = archive.revisions.filter { GalaxySSIHealthKitCopies.includes($0, scope: scope) }
    let ids = Set(versions.map(\.id))
    guard !ids.isEmpty,
          archive.revisions.allSatisfy({ !ids.contains($0.id) || GalaxySSIHealthKitCopies.includes($0, scope: scope) })
    else { throw Failure.stale }
    let dates = versions.map(\.measuredAt)
    guard let start = dates.min(), let end = dates.max() else { throw Failure.stale }
    let draft = archive.draft.flatMap { draft in
      draft.existing.map { ids.contains($0.id) } == true ? draft : nil
    }
    return .init(scope: scope, count: ids.count, start: start, end: end, versions: versions, draft: draft,
                 links: (archive.tableEvidence ?? []).filter { ids.contains($0.target.record) },
                 reportLinks: (archive.reportEvidence ?? []).filter { ids.contains($0.target.record) })
  }

  @discardableResult
  func eraseBluetoothHistory(_ expected: GalaxySSIHealthBluetoothHistory.ErasePlan) throws -> Int {
    var archive = try load()
    let current = try makeBluetoothErasePlan(expected.device, archive: archive)
    guard current == expected else { throw Failure.stale }
    let ids = Set(current.versions.map(\.id))
    archive.revisions.removeAll { ids.contains($0.id) }
    if let existing = archive.draft?.existing, ids.contains(existing.id) { archive.draft = nil }
    archive.tableEvidence?.removeAll { ids.contains($0.target.record) }
    var audit = archive.bluetoothErasureLog ?? []
    audit.append(.init(at: Date(), records: current.count))
    archive.bluetoothErasureLog = Array(audit.suffix(50))
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return current.count
  }

  private func makeBluetoothErasePlan(_ device: UUID, archive: Archive) throws -> GalaxySSIHealthBluetoothHistory.ErasePlan {
    guard archive.derivesOverview == true else { throw Failure.permission }
    let versions = archive.revisions.filter { $0.bluetoothReceipt?.device == device && $0.metric == .bloodPressure }
    let ids = Set(versions.map(\.id))
    guard !ids.isEmpty,
          archive.revisions.allSatisfy({ !ids.contains($0.id) ||
            ($0.bluetoothReceipt?.device == device && $0.metric == .bloodPressure) })
    else { throw Failure.stale }
    var seen = Set<UUID>()
    let dates = versions.reversed().filter { seen.insert($0.id).inserted }.map(\.measuredAt)
    guard let start = dates.min(), let end = dates.max() else { throw Failure.stale }
    let draft = archive.draft.flatMap { draft in
      draft.existing.map { ids.contains($0.id) } == true ? draft : nil
    }
    return .init(device: device, count: ids.count, start: start, end: end, versions: versions,
      draft: draft, links: (archive.tableEvidence ?? []).filter { ids.contains($0.target.record) },
      permissionVersion: archive.privacyEvents?.last(where: { $0.scope == .overview })?.id)
  }

  func setWeeklyReportAllowed(_ enabled: Bool) throws {
    try setPrivacy(.weeklyReport, enabled: enabled)
  }

  func prepareWeeklyExport(_ preview: GalaxySSIWeeklyHealthReport, includeRows: Bool) throws {
    var archive = try load()
    guard archive.weeklyReportAllowed == true else { throw Failure.permission }
    let current = GalaxySSIWeeklyHealthReport(current: archive.current, interval: preview.interval,
                                              metrics: preview.metrics, through: Date())
    guard current.readings == preview.readings, !preview.readings.isEmpty else { throw Failure.stale }
    var requests = archive.weeklyExportRequests ?? []
    requests.append(.init(at: Date(), interval: preview.interval, metrics: preview.metrics,
                          includeRows: includeRows, revisionCount: preview.readings.count))
    archive.weeklyExportRequests = Array(requests.suffix(50))
    try persist(archive)
  }

  func setOverviewPermission(_ enabled: Bool) throws {
    try setPrivacy(.overview, enabled: enabled)
  }

  func setPrivacy(_ scope: PrivacyScope, enabled: Bool) throws {
    var archive = try load()
    let previous: Bool?
    switch scope {
    case .overview:
      previous = archive.derivesOverview
      archive.derivesOverview = enabled
    case .weeklyReport:
      previous = archive.weeklyReportAllowed
      archive.weeklyReportAllowed = enabled
    }
    guard previous != enabled else { return }
    if (previous ?? false) != enabled {
      var history = archive.privacyEvents ?? []
      history.append(.init(at: Date(), scope: scope, enabled: enabled))
      archive.privacyEvents = Array(history.suffix(100))
    }
    try persist(archive)
    if scope == .overview { NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner) }
  }

  func discardDraft(id: UUID) throws {
    var archive = try load()
    guard archive.draft?.id == id else { return }
    archive.draft = nil
    try persist(archive)
  }

  func write(_ input: GalaxySSIHealthReading, allowDuplicate: Bool = false, draftId: UUID? = nil) throws {
    guard input.isValid else { throw Failure.invalid }
    var archive = try load()
    let latest = archive.revisions.last { $0.id == input.id }
    guard (latest?.revision ?? 0) == input.revision, latest?.deleted != true,
          !input.deleted || latest != nil else { throw Failure.stale }
    if let latest {
      guard latest.bluetoothReceipt == input.bluetoothReceipt, latest.tableSource == input.tableSource,
            latest.healthKitSource == input.healthKitSource,
            latest.reportSource == input.reportSource
      else { throw Failure.invalid }
    } else if let receipt = input.bluetoothReceipt, archive.revisions.contains(where: {
      $0.bluetoothReceipt.map { receipt.isReplay(of: $0) } == true
    }) {
      throw Failure.duplicate
    }
    if !input.deleted && !allowDuplicate &&
        archive.current.contains(where: { $0.id != input.id && $0.sameMeasurement(as: input) }) {
      throw Failure.duplicate
    }
    var revision = input
    revision.revision += 1
    archive.revisions.append(revision)
    if let draftId, archive.draft?.id == draftId { archive.draft = nil }
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  func stageReportItem(_ input: GalaxySSIHealthReportReview.Item, replacing expected: UUID?) throws {
    var archive = try load()
    var pending = archive.reportReview ?? []
    let index = pending.firstIndex { $0.source == input.source }
    guard index.map({ pending[$0].version }) == expected else { throw Failure.stale }
    guard input.reading.isValid, input.reading.reportSource == input.source,
          input.reading.revision == 0, !input.reading.deleted,
          !input.excerpt.isEmpty, input.excerpt.count <= 500 else { throw Failure.invalid }
    if let index { pending[index] = input }
    else {
      guard pending.count < 300 else { throw Failure.invalid }
      pending.append(input)
    }
    archive.reportReview = pending
    try persist(archive)
  }

  func discardReportItem(source: GalaxySSIHealthReportReview.Source, version: UUID) throws {
    var archive = try load()
    guard let index = archive.reportReview?.firstIndex(where: { $0.source == source && $0.version == version })
    else { throw Failure.stale }
    archive.reportReview?.remove(at: index)
    try persist(archive)
  }

  func confirmReportItems(_ versions: Set<UUID>, original: GalaxySSIHealthOriginalStore.Original) throws {
    var archive = try load()
    let pending = archive.reportReview ?? []
    let chosen = pending.filter { versions.contains($0.version) }
    guard !chosen.isEmpty, chosen.count == versions.count,
          chosen.allSatisfy({ $0.source.original == original.id && $0.source.sha256 == original.sha256 })
    else { throw Failure.stale }
    let existing = archive.current
    var appended: [GalaxySSIHealthReading] = []
    for item in chosen {
      var reading = item.reading
      guard reading.isValid, reading.revision == 0, !reading.deleted, reading.reportSource == item.source,
            !archive.revisions.contains(where: { $0.id == reading.id || $0.reportSource == item.source }),
            !(existing + appended).contains(where: { $0.sameMeasurement(as: reading) }) else { throw Failure.duplicate }
      reading.revision = 1
      appended.append(reading)
    }
    archive.revisions.append(contentsOf: appended)
    archive.reportReview = pending.filter { !versions.contains($0.version) }
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  func linkReportDuplicates(_ selected: [UUID: GalaxySSIHealthReportReview.Target],
                            original: GalaxySSIHealthOriginalStore.Original) throws {
    var archive = try load()
    let pending = archive.reportReview ?? []
    let current = archive.current
    let chosen = pending.filter { selected[$0.version] != nil }
    guard !chosen.isEmpty, chosen.count == selected.count else { throw Failure.stale }
    var evidence = archive.reportEvidence ?? []
    for item in chosen {
      guard item.source.original == original.id, item.source.sha256 == original.sha256,
            let target = selected[item.version],
            GalaxySSIHealthReportReview.exactTarget(for: item, current: current) == target else {
        throw Failure.stale
      }
      if let linked = evidence.first(where: { $0.source == item.source }) {
        guard linked.target == target else { throw Failure.duplicate }
      } else {
        guard evidence.count < 5_000,
              !archive.revisions.contains(where: { $0.reportSource == item.source && $0.id != target.record })
        else { throw Failure.duplicate }
        evidence.append(.init(target: target, source: item.source, excerpt: item.excerpt))
      }
    }
    archive.reportEvidence = evidence
    archive.reportReview = pending.filter { selected[$0.version] == nil }
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  func importTable(_ data: Data, name: String, json: Bool, mapping: GalaxySSIHealthTableImport.Mapping,
                   expected: [GalaxySSIHealthTableImport.Status],
                   worksheet: GalaxySSIHealthXLSX.Selection? = nil,
                   linkDuplicates: [Int: GalaxySSIHealthTableImport.EvidenceTarget] = [:]) throws -> Int {
    var archive = try load()
    let table: GalaxySSIHealthTableImport.Table
    if let worksheet { table = try GalaxySSIHealthXLSX(data).table(worksheet) }
    else { table = try GalaxySSIHealthTableImport.parse(data, json: json) }
    let preview = try GalaxySSIHealthTableImport.preview(table, mapping: mapping, current: archive.current)
    guard preview.map(\.status) == expected else { throw GalaxySSIHealthTableImport.Failure.stale }
    let id = UUID(), hash = GalaxySSIHealthTableImport.digest(data)
    var readings = [GalaxySSIHealthReading]()
    var links: [GalaxySSIHealthTableImport.Evidence] = []
    for row in preview {
      if let selected = linkDuplicates[row.id] {
        guard row.duplicateTarget == selected else { throw Failure.stale }
        links.append(.init(target: selected, source: .init(batch: id, row: row.id, sha256: hash,
          sheet: table.sheet, worksheetPath: table.sheetPath, columns: mapping.sourceColumns)))
      }
      guard row.status == .ready, var reading = row.reading else { continue }
      reading.revision = 1
      reading.tableSource = .init(batch: id, row: row.id, sha256: hash, sheet: table.sheet,
                                  worksheetPath: table.sheetPath, columns: mapping.sourceColumns)
      readings.append(reading)
    }
    guard links.count == linkDuplicates.count else { throw Failure.stale }
    guard !readings.isEmpty || !links.isEmpty else { return 0 }
    var batches = archive.tableBatches ?? []
    guard batches.count < 30,
          batches.reduce(data.count, { $0 + $1.data.count }) <= 12 * GalaxySSIHealthTableImport.maximumBytes
    else { throw GalaxySSIHealthTableImport.Failure.limit }
    batches.insert(.init(id: id, name: String(name.prefix(180)), at: Date(), data: data,
                         inserted: readings.count, undone: nil, linked: links.isEmpty ? nil : links.count), at: 0)
    archive.tableBatches = batches
    if !links.isEmpty { archive.tableEvidence = (archive.tableEvidence ?? []) + links }
    archive.revisions.append(contentsOf: readings)
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return readings.count
  }

  func importHealthKit(_ readings: [GalaxySSIHealthReading]) throws -> Int {
    var archive = try load()
    let count = try appendHealthKit(readings, to: &archive)
    guard !readings.isEmpty else { return 0 }
    let metrics = Set(readings.map(\.metric))
    var readAt = archive.healthKitReadAt ?? [:]
    for scope in GalaxySSIHealthKitImport.Scope.allCases where metrics.contains(scope.metric) {
      readAt[scope.rawValue] = Date()
    }
    archive.healthKitReadAt = readAt
    try persist(archive)
    if count > 0 { NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner) }
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
    return count
  }

  private func appendHealthKit(_ readings: [GalaxySSIHealthReading], to archive: inout Archive) throws -> Int {
    guard readings.count <= GalaxySSIHealthKitImport.limit else { throw Failure.invalid }
    var seen = Set(archive.revisions.compactMap { $0.healthKitSource?.key })
    var additions: [GalaxySSIHealthReading] = []
    for var reading in readings {
      guard let source = reading.healthKitSource, source.key.utf8.count == 64, reading.revision == 0,
            !reading.deleted, reading.isValid else { throw Failure.invalid }
      guard seen.insert(source.key).inserted else { continue }
      reading.revision = 1
      additions.append(reading)
    }
    archive.revisions.append(contentsOf: additions)
    return additions.count
  }

  func beginHealthKitSync(_ scope: GalaxySSIHealthKitImport.Scope, floor: Date, reset: Bool) throws
    -> GalaxySSIHealthKitSync.Checkpoint {
    var archive = try load()
    var checkpoints = archive.healthKitSync ?? [:]
    var checkpoint = checkpoints[scope.rawValue] ?? .init(floor: floor)
    if reset {
      checkpoint = .init(floor: floor, previousCoverageUnverified: true, finishedAt: checkpoint.finishedAt)
    }
    checkpoint.run = UUID()
    checkpoint.status = .running
    checkpoint.insertedThisRun = 0
    checkpoint.readThisRun = 0
    checkpoints[scope.rawValue] = checkpoint
    archive.healthKitSync = checkpoints
    try persist(archive)
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
    return checkpoint
  }

  func commitHealthKitPage(scope: GalaxySSIHealthKitImport.Scope, expected: GalaxySSIHealthKitSync.Checkpoint,
                           page: GalaxySSIHealthKitSync.Page, at now: Date) throws -> GalaxySSIHealthKitSync.Checkpoint {
    var archive = try load()
    guard var checkpoint = archive.healthKitSync?[scope.rawValue], checkpoint == expected,
          checkpoint.status == .running, page.anchor.count <= 16_384,
          (0...GalaxySSIHealthKitSync.pageSize * 2).contains(page.providerCount),
          page.rows.count <= page.providerCount, page.rows.allSatisfy({ $0.metric == scope.metric })
    else { throw Failure.stale }
    let count = try appendHealthKit(page.rows, to: &archive)
    checkpoint.anchor = page.anchor
    checkpoint.insertedThisRun += count
    checkpoint.readThisRun += page.rows.count
    if !page.rows.isEmpty {
      var readAt = archive.healthKitReadAt ?? [:]
      readAt[scope.rawValue] = now
      archive.healthKitReadAt = readAt
    }
    if !page.more {
      checkpoint.status = checkpoint.readThisRun == 0 ? .empty : .success
      checkpoint.finishedAt = now
    }
    archive.healthKitSync?[scope.rawValue] = checkpoint
    try persist(archive)
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
    if count > 0 { NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner) }
    return checkpoint
  }

  func finishHealthKitSync(_ scope: GalaxySSIHealthKitImport.Scope, run: UUID,
                           status: GalaxySSIHealthKitSync.Status) throws {
    var archive = try load()
    guard archive.healthKitSync?[scope.rawValue]?.run == run,
          archive.healthKitSync?[scope.rawValue]?.status == .running else { return }
    archive.healthKitSync?[scope.rawValue]?.status = status
    try persist(archive)
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
  }

  static let healthKitCoverageChanged = Notification.Name("galaxyssi.health.healthKitCoverageChanged")

  func setHealthKitSelection(_ selection: Set<GalaxySSIHealthKitImport.Scope>) throws {
    var archive = try load()
    let scopes = Set(selection.map(\.rawValue))
    guard archive.healthKitSelection != scopes else { return }
    archive.healthKitSelection = scopes
    try persist(archive)
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
  }

  func undoTableBatch(_ id: UUID) throws -> Int {
    var archive = try load()
    guard let index = archive.tableBatches?.firstIndex(where: { $0.id == id }),
          archive.tableBatches?[index].undone == nil else { return 0 }
    let tombstones = archive.current.filter { $0.tableSource?.batch == id && $0.revision == 1 }.map {
      var reading = $0
      reading.revision += 1
      reading.deleted = true
      return reading
    }
    archive.tableBatches?[index].undone = tombstones.count
    archive.tableEvidence?.removeAll { $0.source.batch == id }
    archive.revisions.append(contentsOf: tombstones)
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return tombstones.count
  }

  private func persist(_ archive: Archive) throws {
    let payload = try JSONEncoder().encode(archive)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: true),
                                        authenticating: context).combined else { throw Failure.unavailable }
    try sealed.write(to: file, options: [.atomic, .completeFileProtection])
  }

  private func key(create: Bool, account override: String? = nil) throws -> SymmetricKey {
    let account = override ?? self.account
    if let encoded = secrets.string(account: account) {
      guard let data = Data(base64Encoded: encoded), data.count == 32 else { throw Failure.unavailable }
      return SymmetricKey(data: data)
    }
    guard create else { throw Failure.unavailable }
    let key = SymmetricKey(size: .bits256)
    try secrets.setString(key.withUnsafeBytes { Data($0).base64EncodedString() }, account: account)
    return key
  }
}
