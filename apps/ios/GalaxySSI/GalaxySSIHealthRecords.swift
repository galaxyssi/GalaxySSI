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

struct GalaxySSIHealthDraft: Codable, Identifiable {
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
  static let profileInputsChanged = Notification.Name("galaxyssi.health.profileInputsChanged")

  enum Failure: Error {
    case invalid, stale, duplicate, unavailable, permission
  }

  enum PrivacyScope: String, Codable {
    case overview, weeklyReport, importOriginals, profileAnalysis
  }

  struct PrivacyEvent: Codable, Identifiable {
    var id = UUID()
    var at: Date
    var scope: PrivacyScope
    var enabled: Bool
  }

  struct MeasurementDeletion: Codable, Equatable {
    let id: UUID
    let revision: Int
  }

  struct ProfileAnalysisAudit: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let fields: Set<GalaxySSIHealthProfile.AnalysisField>
  }

  struct Archive: Codable {
    var reportReview: [GalaxySSIHealthReportReview.Item]?
    var reportEvidence: [GalaxySSIHealthReportReview.Evidence]?
    var version = 1
    var recordingReminders: GalaxySSIHealthRecordingReminders.Ledger?
    var restoreReceipts: Set<UUID>?
    var revisions: [GalaxySSIHealthReading] = []
    var lastMeasurementDeletion: MeasurementDeletion?
    var metricDeletionHistory: [GalaxySSIHealthMetricDeletion.Audit]?
    var draft: GalaxySSIHealthDraft?
    var sleepReminders: GalaxySSIHealthSleepReminder.Ledger?
    var derivesOverview: Bool?
    var weeklyReportAllowed: Bool?
    var weeklyExportRequests: [GalaxySSIWeeklyHealthReport.ExportRequest]?
    var privacyEvents: [PrivacyEvent]?
    var tableBatches: [GalaxySSIHealthTableImport.Batch]?
    var tableEvidence: [GalaxySSIHealthTableImport.Evidence]?
    var healthOnlinePermission: UUID?
    var healthKitImportedAt: [GalaxySSIHealthKitImport.Scope: Date]?
    var retainImportOriginals: Bool?
    var profileAnalysisPermission: UUID?
    var profileAnalysisAudit: [ProfileAnalysisAudit]?

    var keepsNewImportOriginals: Bool { retainImportOriginals ?? true }

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
  static let sourceAttentionChanged = Notification.Name("galaxyssi.health.sourceAttentionChanged")
  private var sourceAttentionContext: Data { Data("galaxyssi.health.sourceAttention.v1:\(owner)".utf8) }
  private var sourceAttentionAccount: String { "health.sourceAttention.v1." + owner }

  func loadSourceAttention() throws -> GalaxySSIHealthSourceAttention {
    let file = try storageFile(context: sourceAttentionContext, fixtureExtension: "source-attention")
    let data: Data
    do { data = try Data(contentsOf: file) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return GalaxySSIHealthSourceAttention()
    }
    let box = try AES.GCM.SealedBox(combined: data)
    let payload = try AES.GCM.open(box, using: key(create: false, account: sourceAttentionAccount),
                                  authenticating: sourceAttentionContext)
    return try JSONDecoder().decode(GalaxySSIHealthSourceAttention.self, from: payload)
  }

  func updateSourceAttention(_ update: (inout GalaxySSIHealthSourceAttention) -> Void) throws {
    let current = try loadSourceAttention()
    var next = current
    update(&next)
    guard current != next else { return }
    let payload = try JSONEncoder().encode(next)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: true, account: sourceAttentionAccount),
                                        authenticating: sourceAttentionContext).combined else { throw Failure.unavailable }
    try sealed.write(to: storageFile(context: sourceAttentionContext, fixtureExtension: "source-attention"),
                     options: [.atomic, .completeFileProtection])
    NotificationCenter.default.post(name: Self.sourceAttentionChanged, object: owner)
  }

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
    let previous = try loadProfile()
    guard previous.revision == input.revision else { throw Failure.stale }
    var updated = input
    updated.revision = UUID()
    var versions: [GalaxySSIHealthProfile.AnalysisField: UUID] = [:]
    for field in GalaxySSIHealthProfile.AnalysisField.allCases {
      versions[field] = previous.analysisValue(field) == updated.analysisValue(field)
        ? previous.analysisVersion(field) : UUID()
    }
    updated.analysisVersions = versions
    let payload = try JSONEncoder().encode(updated)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: true, account: profileAccount),
                                        authenticating: profileContext).combined else { throw Failure.unavailable }
    try sealed.write(to: storageFile(context: profileContext, fixtureExtension: "profile"),
                     options: [.atomic, .completeFileProtection])
    NotificationCenter.default.post(name: Self.profileInputsChanged, object: owner)
  }

  func setProfileAnalysisAllowed(_ allowed: Bool) throws {
    try setPrivacy(.profileAnalysis, enabled: allowed)
  }

  func captureProfileAnalysis(_ fields: Set<GalaxySSIHealthProfile.AnalysisField>) throws
    -> GalaxySSIHealthProfile.AnalysisContext? {
    guard !fields.isEmpty else { return nil }
    var archive = try load()
    guard let permission = archive.profileAnalysisPermission, archive.derivesOverview == true else { throw Failure.permission }
    let snapshot = GalaxySSIHealthProfile.AnalysisContext(profile: try loadProfile(), permission: permission, fields: fields)
    var audit = archive.profileAnalysisAudit ?? []
    audit.append(.init(at: Date(), fields: fields))
    archive.profileAnalysisAudit = Array(audit.suffix(50))
    try persist(archive)
    return snapshot
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

  func setWeeklyReportAllowed(_ enabled: Bool) throws {
    try setPrivacy(.weeklyReport, enabled: enabled)
  }

  func prepareWeeklyExport(_ preview: GalaxySSIWeeklyHealthReport, includeRows: Bool) throws {
    var archive = try load()
    guard archive.weeklyReportAllowed == true else { throw Failure.permission }
    let current: GalaxySSIWeeklyHealthReport?
    if let link = preview.assistantScope {
      guard archive.derivesOverview == true else { throw Failure.permission }
      current = GalaxySSIWeeklyHealthReport(current: archive.current, assistantScope: link, selected: preview.metrics)
    } else if let evidence = preview.sleepEvidence {
      guard archive.derivesOverview == true else { throw Failure.permission }
      current = GalaxySSIWeeklyHealthReport(current: archive.current, sleepEvidence: evidence)
    } else {
      current = GalaxySSIWeeklyHealthReport(current: archive.current, interval: preview.interval,
                                            metrics: preview.metrics, through: Date())
    }
    guard current?.readings == preview.readings, current?.comparisonReadings == preview.comparisonReadings,
          current?.interval == preview.interval, !preview.readings.isEmpty else { throw Failure.stale }
    var requests = archive.weeklyExportRequests ?? []
    requests.append(.init(at: Date(), interval: preview.interval, metrics: preview.metrics,
                          includeRows: includeRows, revisionCount: preview.readings.count))
    archive.weeklyExportRequests = Array(requests.suffix(50))
    try persist(archive)
  }

  func setOverviewPermission(_ enabled: Bool) throws {
    try setPrivacy(.overview, enabled: enabled)
  }

  func setHealthOnlinePermission(_ enabled: Bool) throws {
    var archive = try load()
    guard (archive.healthOnlinePermission != nil) != enabled else { return }
    archive.healthOnlinePermission = enabled ? UUID() : nil
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
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
    case .importOriginals:
      previous = archive.retainImportOriginals
      archive.retainImportOriginals = enabled
    case .profileAnalysis:
      previous = archive.profileAnalysisPermission != nil
      archive.profileAnalysisPermission = enabled ? UUID() : nil
    }
    guard previous != enabled else { return }
    if (previous ?? (scope == .importOriginals)) != enabled {
      var history = archive.privacyEvents ?? []
      history.append(.init(at: Date(), scope: scope, enabled: enabled))
      archive.privacyEvents = Array(history.suffix(100))
    }
    try persist(archive)
    if scope == .overview { NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner) }
    if scope == .profileAnalysis { NotificationCenter.default.post(name: Self.profileInputsChanged, object: owner) }
  }

  func discardDraft(id: UUID) throws {
    var archive = try load()
    guard archive.draft?.id == id else { return }
    archive.draft = nil
    try persist(archive)
  }

  func write(_ input: GalaxySSIHealthReading, allowDuplicate: Bool = false, draftId: UUID? = nil,
             rememberDeletion: Bool = false) throws {
    guard input.isValid else { throw Failure.invalid }
    var archive = try load()
    let latest = archive.revisions.last { $0.id == input.id }
    guard (latest?.revision ?? 0) == input.revision, input.revision < Int.max, latest?.deleted != true,
          !input.deleted || latest != nil else { throw Failure.stale }
    if let latest {
      guard latest.metric == input.metric,
            latest.bluetoothReceipt == input.bluetoothReceipt, latest.tableSource == input.tableSource,
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
    if rememberDeletion && revision.deleted {
      archive.lastMeasurementDeletion = .init(id: revision.id, revision: revision.revision)
      if archive.draft?.existing?.id == revision.id { archive.draft = nil }
    }
    if let draftId, archive.draft?.id == draftId { archive.draft = nil }
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  func undoMeasurementDeletion(_ deletion: MeasurementDeletion) throws -> GalaxySSIHealthReading {
    var archive = try load()
    guard (2..<Int.max).contains(deletion.revision),
          let tombstone = archive.revisions.last(where: { $0.id == deletion.id }),
          tombstone.deleted, tombstone.revision == deletion.revision,
          let previous = archive.revisions.last(where: {
            $0.id == deletion.id && $0.revision == deletion.revision - 1 && !$0.deleted
          }) else { throw Failure.stale }
    var restored = tombstone
    restored.deleted = false
    restored.revision = previous.revision
    guard restored == previous, restored.isValid,
          archive.draft?.existing?.id != deletion.id,
          !((archive.tableBatches ?? []).contains {
            $0.id == restored.tableSource?.batch && $0.undone != nil
          }) else { throw Failure.stale }
    guard !archive.current.contains(where: { current in
      if current.sameMeasurement(as: restored) { return true }
      if let receipt = restored.bluetoothReceipt, let other = current.bluetoothReceipt,
         receipt.isReplay(of: other) { return true }
      if let source = restored.tableSource, let other = current.tableSource,
         source.batch == other.batch && source.row == other.row { return true }
      return false
    }) else { throw Failure.duplicate }
    restored.revision = deletion.revision + 1
    archive.revisions.append(restored)
    if archive.lastMeasurementDeletion == deletion { archive.lastMeasurementDeletion = nil }
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return restored
  }

  func previewMetricDeletion(_ metric: GalaxySSIHealthMetric, filter: GalaxySSIHealthMetricDeletion.Filter? = nil)
    throws -> GalaxySSIHealthMetricDeletion.Preview {
    try GalaxySSIHealthMetricDeletion.preview(metric, filter: filter, in: load())
  }

  func previewBluetoothHistoryDeletion(device: UUID) throws -> GalaxySSIHealthMetricDeletion.Preview {
    try GalaxySSIHealthMetricDeletion.preview(.bloodPressure, filter: .bluetooth, bluetoothDevice: device, in: load())
  }

  func deleteMetricHistory(_ reviewed: GalaxySSIHealthMetricDeletion.Preview) throws {
    var archive = try load()
    let metric = reviewed.scope.metric
    let filter = reviewed.scope.filter
    let current = try GalaxySSIHealthMetricDeletion.preview(metric, filter: filter,
      bluetoothDevice: reviewed.bluetoothDevice, in: archive)
    guard current == reviewed, !current.scope.isEmpty else { throw Failure.stale }
    let ids = current.ids
    archive.revisions.removeAll { ids.contains($0.id) }
    archive.tableEvidence?.removeAll { ids.contains($0.target.record) }
    archive.reportEvidence?.removeAll { ids.contains($0.target.record) }
    if filter == nil { archive.reportReview?.removeAll { $0.reading.metric == metric } }
    if let draft = archive.draft, GalaxySSIHealthMetricDeletion.includes(draft, metric: metric, filter: filter, ids: ids) {
      archive.draft = nil
    }
    if let last = archive.lastMeasurementDeletion, ids.contains(last.id) { archive.lastMeasurementDeletion = nil }
    if metric == .sleepDuration {
      if filter == nil { archive.sleepReminders?.episodes = [] }
      else {
        archive.sleepReminders?.episodes.removeAll { episode in
          (episode.first.revisions + episode.latest.revisions).contains { reference in
            guard let id = UUID(uuidString: String(reference.prefix(while: { $0 != ":" }))) else { return false }
            return ids.contains(id)
          }
        }
      }
    }
    var history = archive.metricDeletionHistory ?? []
    history.append(.init(at: Date(), scope: current.scope))
    archive.metricDeletionHistory = Array(history.suffix(100))
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  func stageReportItem(_ input: GalaxySSIHealthReportReview.Item, replacing expected: UUID?) throws {
    var archive = try load()
    guard archive.reportEvidence?.contains(where: { $0.source == input.source }) != true else { throw Failure.duplicate }
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
            archive.reportEvidence?.contains(where: { $0.source == item.source }) != true,
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
                            original: GalaxySSIHealthOriginalStore.Original, store: GalaxySSIHealthOriginalStore) throws {
    guard store.owner == owner, store.restoreRecordsFile == isolatedFile, original.kind == .pdf else { throw Failure.invalid }
    _ = try store.read(original)
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
                   worksheet: GalaxySSIHealthXLSX.Selection? = nil, retainOriginal: Bool = true,
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
          batches.reduce(retainOriginal ? data.count : 0, { $0 + $1.data.count }) <= 12 * GalaxySSIHealthTableImport.maximumBytes
    else { throw GalaxySSIHealthTableImport.Failure.limit }
    batches.insert(.init(id: id, name: String(name.prefix(180)), at: Date(), data: retainOriginal ? data : Data(),
                         inserted: readings.count, undone: nil, linked: links.isEmpty ? nil : links.count,
                         sourceDigest: hash), at: 0)
    archive.tableBatches = batches
    if !links.isEmpty { archive.tableEvidence = (archive.tableEvidence ?? []) + links }
    archive.revisions.append(contentsOf: readings)
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return readings.count
  }

  func importHealthKit(_ readings: [GalaxySSIHealthReading], at now: Date = Date()) throws -> Int {
    guard readings.count <= GalaxySSIHealthKitImport.limit else { throw Failure.invalid }
    var archive = try load()
    var seen = Set(archive.revisions.compactMap { $0.healthKitSource?.key })
    var additions: [GalaxySSIHealthReading] = []
    for var reading in readings {
      guard let source = reading.healthKitSource, source.key.utf8.count == 64, reading.revision == 0,
            !reading.deleted, reading.isValid else { throw Failure.invalid }
      guard seen.insert(source.key).inserted else { continue }
      reading.revision = 1
      additions.append(reading)
    }
    guard !additions.isEmpty else { return 0 }
    archive.revisions.append(contentsOf: additions)
    let metrics = Set(additions.map(\.metric))
    var importedAt = archive.healthKitImportedAt ?? [:]
    for scope in GalaxySSIHealthKitImport.Scope.allCases where metrics.contains(scope.metric) {
      importedAt[scope] = now
    }
    archive.healthKitImportedAt = importedAt
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return additions.count
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

  func loadRecordingReminders(at now: Date, calendar: Calendar) throws -> GalaxySSIHealthRecordingReminders.Ledger {
    var archive = try load()
    let previous = archive.recordingReminders ?? .init()
    var ledger = previous
    ledger.reconcile(at: now, calendar: calendar)
    if ledger != previous { archive.recordingReminders = ledger; try persist(archive) }
    return ledger
  }

  func saveRecordingReminderSettings(_ settings: GalaxySSIHealthRecordingReminders.Settings, at now: Date) throws {
    guard settings.isValid else { throw Failure.invalid }
    var archive = try load()
    var ledger = archive.recordingReminders ?? .init(settings: settings)
    guard ledger.settings.version == settings.version else { throw Failure.stale }
    let before = ledger.settings
    ledger.settings = settings
    ledger.settings.version = UUID()
    if before.effectiveAt == nil || !before.enabled || !settings.enabled || before.hour != settings.hour || before.minute != settings.minute ||
        before.category != settings.category {
      ledger.settings.effectiveAt = settings.enabled ? now : nil
    }
    if !settings.enabled {
      for index in ledger.history.indices where ledger.history[index].completedAt == nil && !ledger.history[index].disabled {
        ledger.history[index].disabled = true
        ledger.history[index].version = UUID()
      }
    }
    archive.recordingReminders = ledger
    try persist(archive)
    NotificationCenter.default.post(name: GalaxySSIHealthRecordingReminders.changed, object: owner)
  }

  func updateRecordingReminder(_ expected: GalaxySSIHealthRecordingReminders.Occurrence, complete: Bool,
                               at now: Date, calendar: Calendar = .autoupdatingCurrent) throws {
    var archive = try load()
    guard var ledger = archive.recordingReminders, ledger.settings.enabled,
          expected.day == GalaxySSIHealthRecordingReminders.Ledger.key(now, calendar: calendar),
          let index = ledger.history.firstIndex(where: { $0.day == expected.day && $0.version == expected.version }),
          ledger.history[index].completedAt == nil, !ledger.history[index].disabled else { throw Failure.stale }
    if complete { ledger.history[index].completedAt = now }
    else { ledger.history[index].snoozedUntil = now.addingTimeInterval(3_600) }
    ledger.history[index].version = UUID()
    archive.recordingReminders = ledger
    try persist(archive)
    NotificationCenter.default.post(name: GalaxySSIHealthRecordingReminders.changed, object: owner)
  }

  @discardableResult
  func reconcileSleepReminders(at now: Date, calendar: Calendar) throws -> GalaxySSIHealthSleepReminder.Ledger {
    var archive = try load()
    let before = archive.sleepReminders ?? .init()
    var ledger = before
    ledger.reconcile(current: archive.current, allowed: archive.derivesOverview == true, now: now, calendar: calendar)
    if before != ledger { archive.sleepReminders = ledger; try persist(archive) }
    return ledger
  }

  func setSleepPreferences(_ preferences: GalaxySSIHealthSleepReminder.Preferences) throws {
    guard GalaxySSIHealthSleepReminder.thresholds.contains(preferences.threshold),
          (0..<24).contains(preferences.quietStart), (0..<24).contains(preferences.quietEnd) else { throw Failure.invalid }
    var archive = try load()
    var ledger = archive.sleepReminders ?? .init()
    ledger.preferences = preferences
    if !preferences.enabled, let active = ledger.episodes.firstIndex(where: { !$0.closed }) { ledger.close(active) }
    archive.sleepReminders = ledger
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  func updateSleepEpisode(version: UUID, completion: Bool = false, snooze: Date? = nil, delivered: Date? = nil) throws {
    var archive = try load()
    guard archive.derivesOverview == true, var ledger = archive.sleepReminders, ledger.preferences.enabled,
          let index = ledger.episodes.firstIndex(where: { $0.version == version && !$0.closed }),
          !ledger.episodes[index].completed else { throw Failure.stale }
    if completion { ledger.episodes[index].completed = true }
    if let snooze {
      ledger.episodes[index].snoozedUntil = snooze
      ledger.episodes[index].deliveredAt = nil
    }
    if let delivered { ledger.episodes[index].deliveredAt = delivered }
    ledger.episodes[index].version = UUID()
    archive.sleepReminders = ledger
    try persist(archive)
  }

  func commitRestore(_ archive: Archive, receipt: UUID, notify: Bool = true) throws {
    var updated = archive
    var receipts = updated.restoreReceipts ?? []
    receipts.insert(receipt)
    updated.restoreReceipts = receipts
    try persist(updated, notify: notify)
  }

  private func persist(_ archive: Archive, notify: Bool = true) throws {
    let payload = try JSONEncoder().encode(archive)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: true),
                                        authenticating: context).combined else { throw Failure.unavailable }
    try sealed.write(to: file, options: [.atomic, .completeFileProtection])
    if notify { NotificationCenter.default.post(name: Self.recordsChanged, object: owner) }
  }

  static let recordsChanged = Notification.Name("galaxyssi.health.records.changed")

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
