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
  var secondarySources: GalaxySSIHealthPortableBackup.SecondarySources?

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
  static let profileInputsChanged = Notification.Name("galaxyssi.health.profileInputsChanged")

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

  struct ProfileAnalysisAudit: Codable {
    let at: Date
    let fields: Set<GalaxySSIHealthProfile.AnalysisField>
    var backgroundCount: Int?
  }

  struct Archive: Codable {
    var reportReview: [GalaxySSIHealthReportReview.Item]?
    var reportEvidence: [GalaxySSIHealthReportReview.Evidence]?
    var tableReview: GalaxySSIHealthReviewReminders.TableDraft?
    var reviewReminderState: GalaxySSIHealthReviewReminders.State?
    var recognitionJobs: [GalaxySSIHealthRecognitionJobs.Job]?
    var photoDraft: GalaxySSIHealthPhotoDraft?
    var originalIndex: GalaxySSIHealthOriginalStore.Index?
    var originalRemovalLog: [GalaxySSIHealthOriginalStore.RemovalEvent]?
    var version = 1
    var recordingReminders: GalaxySSIHealthRecordingReminders.Ledger?
    var restoreReceipts: Set<UUID>?
    var revisions: [GalaxySSIHealthReading] = []
    var draft: GalaxySSIHealthDraft?
    var healthKitSync: [String: GalaxySSIHealthKitSync.Checkpoint]?
    var healthKitSelection: Set<String>?
    var healthKitReadAt: [String: Date]?
    var healthKitErasureLog: [GalaxySSIHealthKitCopies.Erasure]?
    var metricErasureLog: [GalaxySSIHealthMetricHistory.Erasure]?
    var sleepReminders: GalaxySSIHealthSleepReminder.Ledger?
    var healthKitIncidents: [String: GalaxySSIHealthKitSync.Incident]?
    var derivesOverview: Bool?
    var weeklyReportAllowed: Bool?
    var weeklyExportRequests: [GalaxySSIWeeklyHealthReport.ExportRequest]?
    var privacyEvents: [PrivacyEvent]?
    var retainNewImportOriginals: Bool?
    var retainsNewImportOriginals: Bool { retainNewImportOriginals ?? true }
    var tableBatches: [GalaxySSIHealthTableImport.Batch]?
    var tableEvidence: [GalaxySSIHealthTableImport.Evidence]?
    var bluetoothErasureLog: [GalaxySSIHealthBluetoothHistory.Erasure]?
    var healthOnlinePermission: UUID?
    var profileAnalysisPermission: UUID?
    var profileAnalysisAudit: [ProfileAnalysisAudit]?

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
    let entries = Dictionary(previous.background.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    updated.background = updated.background.map { value in
      var entry = value
      if let before = entries[entry.id], before.sameContent(as: entry) {
        entry.analysisRevision = previous.backgroundVersion(before) ?? UUID()
      } else { entry.analysisRevision = UUID() }
      return entry
    }
    let payload = try JSONEncoder().encode(updated)
    guard let sealed = try AES.GCM.seal(payload, using: key(create: true, account: profileAccount),
                                        authenticating: profileContext).combined else { throw Failure.unavailable }
    try sealed.write(to: storageFile(context: profileContext, fixtureExtension: "profile"),
                     options: [.atomic, .completeFileProtection])
    NotificationCenter.default.post(name: Self.profileInputsChanged, object: owner)
  }

  func setProfileAnalysisAllowed(_ allowed: Bool) throws {
    var archive = try load()
    guard (archive.profileAnalysisPermission != nil) != allowed else { return }
    archive.profileAnalysisPermission = allowed ? UUID() : nil
    try persist(archive)
    NotificationCenter.default.post(name: Self.profileInputsChanged, object: owner)
  }

  func captureProfileAnalysis(_ fields: Set<GalaxySSIHealthProfile.AnalysisField>,
                              background: [UUID: UUID] = [:]) throws
    -> GalaxySSIHealthProfile.AnalysisContext? {
    guard !fields.isEmpty || !background.isEmpty else { return nil }
    var archive = try load()
    guard let permission = archive.profileAnalysisPermission, archive.derivesOverview == true else { throw Failure.permission }
    let profile = try loadProfile()
    guard profile.matchesBackground(background) else { throw Failure.stale }
    let snapshot = GalaxySSIHealthProfile.AnalysisContext(profile: profile, permission: permission, fields: fields,
                                                         backgroundVersions: background)
    var audit = archive.profileAnalysisAudit ?? []
    audit.append(.init(at: Date(), fields: fields, backgroundCount: background.count))
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

  func previewMetricErase(_ metric: GalaxySSIHealthMetric) throws -> GalaxySSIHealthMetricHistory.Plan {
    try makeMetricErasePlan(metric, archive: load())
  }

  func eraseMetricHistory(_ expected: GalaxySSIHealthMetricHistory.Plan) throws -> Int {
    var archive = try load()
    let plan = try makeMetricErasePlan(expected.metric, archive: archive)
    guard plan == expected else { throw Failure.stale }
    let ids = Set(plan.versions.map(\.id))
    archive.revisions.removeAll { ids.contains($0.id) }
    if plan.draft != nil { archive.draft = nil }
    archive.tableEvidence?.removeAll { ids.contains($0.target.record) }
    archive.reportEvidence?.removeAll { ids.contains($0.target.record) }
    var history = archive.metricErasureLog ?? []
    history.append(.init(at: Date(), metric: plan.metric, records: plan.count))
    archive.metricErasureLog = Array(history.suffix(50))
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return plan.count
  }

  private func makeMetricErasePlan(_ metric: GalaxySSIHealthMetric, archive: Archive) throws
    -> GalaxySSIHealthMetricHistory.Plan {
    let versions = archive.revisions.filter { $0.metric == metric }
    let ids = Set(versions.map(\.id))
    guard !ids.isEmpty, archive.revisions.allSatisfy({ !ids.contains($0.id) || $0.metric == metric }),
          let start = versions.map(\.measuredAt).min(), let end = versions.map(\.measuredAt).max()
    else { throw Failure.stale }
    var seen = Set<UUID>()
    let latest = versions.reversed().filter { seen.insert($0.id).inserted }
    let counts = Dictionary(grouping: latest, by: GalaxySSIHealthMetricHistory.Source.init).mapValues(\.count)
    return .init(metric: metric, start: start, end: end, counts: counts, versions: versions,
      draft: archive.draft.flatMap { draft in
        draft.existing.map { ids.contains($0.id) } == true ? draft : nil
      },
      tableLinks: (archive.tableEvidence ?? []).filter { ids.contains($0.target.record) },
      reportLinks: (archive.reportEvidence ?? []).filter { ids.contains($0.target.record) })
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
    archive.reportEvidence?.removeAll { ids.contains($0.target.record) }
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
    let dates = versions.map(\.measuredAt)
    guard let start = dates.min(), let end = dates.max() else { throw Failure.stale }
    let draft = archive.draft.flatMap { draft in
      draft.existing.map { ids.contains($0.id) } == true ? draft : nil
    }
    return .init(device: device, count: ids.count, start: start, end: end, versions: versions,
      draft: draft, links: (archive.tableEvidence ?? []).filter { ids.contains($0.target.record) },
      reportLinks: (archive.reportEvidence ?? []).filter { ids.contains($0.target.record) },
      permissionVersion: archive.privacyEvents?.last(where: { $0.scope == .overview })?.id)
  }

  func setWeeklyReportAllowed(_ enabled: Bool) throws {
    try setPrivacy(.weeklyReport, enabled: enabled)
  }

  func prepareWeeklyExport(_ preview: GalaxySSIWeeklyHealthReport, includeRows: Bool,
                           link: GalaxySSIWeeklyHealthReport.Link? = nil) throws {
    var archive = try load()
    guard archive.weeklyReportAllowed == true else { throw Failure.permission }
    if let link {
      guard archive.derivesOverview == true, link.interval == preview.interval, link.comparison == preview.comparison,
            preview.metrics.isSubset(of: link.metrics), link.isCurrent(archive.current) else { throw Failure.stale }
    }
    let current = GalaxySSIWeeklyHealthReport(current: archive.current, interval: preview.interval,
                                              metrics: preview.metrics, through: Date(), comparison: preview.comparison)
    guard current.readings == preview.readings, current.comparisonReadings == preview.comparisonReadings,
          !preview.readings.isEmpty else { throw Failure.stale }
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

  func setRetainNewImportOriginals(_ enabled: Bool) throws {
    var archive = try load()
    guard archive.retainsNewImportOriginals != enabled else { return }
    archive.retainNewImportOriginals = enabled
    try persist(archive)
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
            latest.reportSource == input.reportSource, latest.secondarySources == input.secondarySources
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

  func savePhotoDraft(_ input: GalaxySSIHealthPhotoDraft) throws -> GalaxySSIHealthPhotoDraft {
    var archive = try load()
    guard archive.photoDraft?.version == input.version,
          input.pages.count <= GalaxySSIHealthPhotoDraft.maximumPages,
          Set(input.pages.map(\.id)).count == input.pages.count,
          input.pages.allSatisfy({ $0.original.kind == .image }) else { throw Failure.stale }
    var next = input
    next.version = UUID()
    archive.photoDraft = next
    try persist(archive)
    return next
  }

  func submitPhotoDraft(_ expected: GalaxySSIHealthPhotoDraft, store: GalaxySSIHealthOriginalStore) throws {
    var archive = try load()
    guard let draft = archive.photoDraft, draft == expected, !draft.pages.isEmpty, store.owner == owner else {
      throw Failure.stale
    }
    var jobs = archive.recognitionJobs ?? []
    guard jobs.count + draft.pages.count <= GalaxySSIHealthRecognitionJobs.maximumJobs else { throw Failure.invalid }
    var batch: [GalaxySSIHealthRecognitionJobs.Job] = []
    for (index, page) in draft.pages.enumerated() {
      _ = try store.read(page.original)
      var job = GalaxySSIHealthRecognitionJobs.Job(original: page.original, addedAt: Date(), pageCount: 1)
      job.photoBatch = draft.version
      job.documentOrder = index
      if page.useCrop {
        guard let crop = try store.readCrop(for: page.original), crop.metadata.revision == page.cropRevision
        else { throw Failure.stale }
        job.cropRevision = crop.metadata.revision
      }
      batch.append(job)
    }
    jobs.insert(contentsOf: batch, at: 0)
    archive.recognitionJobs = jobs
    archive.photoDraft = nil
    try persist(archive)
  }

  func enqueueRecognition(original: GalaxySSIHealthOriginalStore.Original, pageCount: Int) throws {
    guard (1...GalaxySSIHealthRecognitionJobs.maximumPages).contains(pageCount) else { throw Failure.invalid }
    var archive = try load()
    var jobs = archive.recognitionJobs ?? []
    guard !jobs.contains(where: { $0.original.id == original.id && $0.original.sha256 == original.sha256 }) else { return }
    guard jobs.count < GalaxySSIHealthRecognitionJobs.maximumJobs else { throw Failure.invalid }
    jobs.insert(.init(original: original, addedAt: Date(), pageCount: pageCount), at: 0)
    archive.recognitionJobs = jobs
    try persist(archive)
  }

  func beginRecognitionJob(id: UUID, expected: UUID?) throws -> UUID {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.run == expected }),
          var job = archive.recognitionJobs?[index], job.phase != .cancelled, job.phase != .completed,
          job.pages.count < job.pageCount else { throw Failure.stale }
    let run = UUID()
    job.run = run
    job.phase = .running
    archive.recognitionJobs?[index] = job
    try persist(archive)
    return run
  }

  func commitRecognitionPage(id: UUID, run: UUID, page: GalaxySSIHealthRecognitionJobs.Page) throws {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.run == run }),
          var job = archive.recognitionJobs?[index], job.phase == .running,
          page.index == job.pages.count, page.index < job.pageCount,
          page.lines.count <= 150, Set(page.lines.map(\.id)).count == page.lines.count,
          page.lines.allSatisfy({ $0.id.utf8.count == 64 && !$0.text.isEmpty && $0.text.count <= 500 })
    else { throw Failure.stale }
    let currentBytes = (archive.recognitionJobs ?? []).flatMap(\.pages).reduce(0) { $0 + $1.textBytes }
    guard currentBytes + page.textBytes <= GalaxySSIHealthRecognitionJobs.maximumTextBytes else { throw Failure.invalid }
    job.pages.append(page)
    if job.pages.count == job.pageCount { job.phase = .completed; job.run = nil }
    archive.recognitionJobs?[index] = job
    try persist(archive)
  }

  func finishRecognitionJob(id: UUID, run: UUID, phase: GalaxySSIHealthRecognitionJobs.Phase) throws {
    guard phase == .cancelled || phase == .failed || phase == .interrupted else { throw Failure.invalid }
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.run == run && $0.phase == .running })
    else { throw Failure.stale }
    archive.recognitionJobs?[index].phase = phase
    archive.recognitionJobs?[index].run = nil
    try persist(archive)
  }

  func cancelRecognitionJob(id: UUID, expected: UUID?) throws {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.run == expected && $0.phase != .completed })
    else { throw Failure.stale }
    archive.recognitionJobs?[index].phase = .cancelled
    archive.recognitionJobs?[index].run = nil
    try persist(archive)
  }

  func removeRecognitionJob(id: UUID, expected: UUID?) throws {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.run == expected })
    else { throw Failure.stale }
    archive.recognitionJobs?.remove(at: index)
    try persist(archive)
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
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func discardReportItem(source: GalaxySSIHealthReportReview.Source, version: UUID) throws {
    var archive = try load()
    guard let index = archive.reportReview?.firstIndex(where: { $0.source == source && $0.version == version })
    else { throw Failure.stale }
    archive.reportReview?.remove(at: index)
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
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
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
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
                   linkDuplicates: [Int: GalaxySSIHealthTableImport.EvidenceTarget] = [:],
                   reviewID: UUID? = nil, retainOriginal: Bool = true) throws -> Int {
    var archive = try load()
    if let reviewID {
      guard let review = archive.tableReview, review.id == reviewID, review.data == data,
            (review.retainOriginal ?? true) == retainOriginal else { throw Failure.stale }
    }
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
                         inserted: readings.count, undone: nil, linked: links.isEmpty ? nil : links.count, sourceDigest: hash), at: 0)
    archive.tableBatches = batches
    if !links.isEmpty { archive.tableEvidence = (archive.tableEvidence ?? []) + links }
    archive.revisions.append(contentsOf: readings)
    if reviewID != nil { archive.tableReview = nil }
    try persist(archive)
    if reviewID != nil { NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner) }
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
      archive.healthKitIncidents?.removeValue(forKey: scope.rawValue)
    }
    archive.healthKitSync?[scope.rawValue] = checkpoint
    try persist(archive)
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
    if !page.more { NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner) }
    if count > 0 { NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner) }
    return checkpoint
  }

  func finishHealthKitSync(_ scope: GalaxySSIHealthKitImport.Scope, run: UUID,
                           status: GalaxySSIHealthKitSync.Status) throws {
    var archive = try load()
    guard archive.healthKitSync?[scope.rawValue]?.run == run,
          archive.healthKitSync?[scope.rawValue]?.status == .running else { return }
    archive.healthKitSync?[scope.rawValue]?.status = status
    let failed = status == .failed || status == .permission || status == .unavailable
    if failed {
      let now = Date()
      var incidents = archive.healthKitIncidents ?? [:]
      if var previous = incidents[scope.rawValue] {
        previous.version = UUID()
        previous.lastFailureAt = now
        previous.status = status
        previous.attempts = min(previous.attempts, Int.max - 1) + 1
        previous.acknowledged = false
        incidents[scope.rawValue] = previous
      } else {
        incidents[scope.rawValue] = .init(scope: scope.rawValue, startedAt: now, lastFailureAt: now, status: status)
      }
      archive.healthKitIncidents = incidents
    }
    try persist(archive)
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
    if failed { NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner) }
  }

  func acknowledgeHealthKitIncident(_ incident: GalaxySSIHealthKitSync.Incident) throws {
    var archive = try load()
    guard archive.healthKitIncidents?[incident.scope] == incident else { throw Failure.stale }
    archive.healthKitIncidents?[incident.scope]?.acknowledged = true
    archive.healthKitIncidents?[incident.scope]?.version = UUID()
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  static let healthKitCoverageChanged = Notification.Name("galaxyssi.health.healthKitCoverageChanged")

  func setHealthKitSelection(_ selection: Set<GalaxySSIHealthKitImport.Scope>) throws {
    var archive = try load()
    let scopes = Set(selection.map(\.rawValue))
    guard archive.healthKitSelection != scopes else { return }
    archive.healthKitSelection = scopes
    try persist(archive)
    NotificationCenter.default.post(name: Self.healthKitCoverageChanged, object: owner)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
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

  static let reviewInputsChanged = Notification.Name("galaxyssi.health.reviewInputsChanged")

  func saveTableReview(_ draft: GalaxySSIHealthReviewReminders.TableDraft, replacing expected: UUID?) throws {
    guard !draft.data.isEmpty, draft.data.count <= GalaxySSIHealthTableImport.maximumBytes else { throw Failure.invalid }
    var archive = try load()
    guard archive.tableReview?.id == expected else { throw Failure.stale }
    archive.tableReview = draft
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func discardTableReview(_ id: UUID) throws {
    var archive = try load()
    guard archive.tableReview?.id == id else { throw Failure.stale }
    archive.tableReview = nil
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func setReviewRemindersEnabled(_ enabled: Bool) throws {
    var archive = try load()
    var state = archive.reviewReminderState ?? .init()
    state.enabled = enabled
    archive.reviewReminderState = state
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func updateReviewReminder(_ job: GalaxySSIHealthReviewReminders.Job, action: GalaxySSIHealthReviewReminders.Action) throws {
    var archive = try load()
    guard GalaxySSIHealthReviewReminders.jobs(in: archive).contains(job) else { throw Failure.stale }
    var state = archive.reviewReminderState ?? .init()
    state.actions[job.key] = action
    let active = Set(GalaxySSIHealthReviewReminders.jobs(in: archive).map(\.key))
    state.actions = state.actions.filter { active.contains($0.key) }
    archive.reviewReminderState = state
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func setReviewNotificationPreferences(_ preferences: GalaxySSIHealthReviewDelivery.Preferences) throws {
    guard (0..<24).contains(preferences.quietStart), (0..<24).contains(preferences.quietEnd) else { throw Failure.invalid }
    var archive = try load()
    var state = archive.reviewReminderState ?? .init()
    state.notificationPreferences = preferences
    archive.reviewReminderState = state
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func reconcileReviewDelivery(now: Date, calendar: Calendar, permitted: Bool, scheduled: Set<UUID>,
                               delivered: Set<UUID>) throws -> [GalaxySSIHealthReviewDelivery.Ticket] {
    var archive = try load()
    guard var state = archive.reviewReminderState else { return [] }
    let before = state.deliveries ?? [:]
    let (tickets, desired) = GalaxySSIHealthReviewDelivery.plan(
      jobs: GalaxySSIHealthReviewReminders.deliveryJobs(in: archive), state: state, now: now,
      calendar: calendar, permitted: permitted, scheduled: scheduled, delivered: delivered)
    if tickets != before {
      state.deliveries = tickets
      archive.reviewReminderState = state
      try persist(archive)
    }
    return desired
  }

  func markReviewDeliverySubmitted(_ ticket: GalaxySSIHealthReviewDelivery.Ticket) throws {
    var archive = try load()
    guard var state = archive.reviewReminderState, let key = state.deliveries?.first(where: {
      $0.value.token == ticket.token && $0.value.due == ticket.due
    })?.key,
    let job = GalaxySSIHealthReviewReminders.deliveryJobs(in: archive).first(where: { $0.key == key }),
    state.notificationPreferences?.allows(job, reviewEnabled: state.enabled) == true,
    state.actions[key] != .handled else { throw Failure.stale }
    let cycle: Date?
    if case .snoozed(let until) = state.actions[key] { cycle = until } else { cycle = nil }
    guard cycle == ticket.cycle,
          state.notificationPreferences?.nextAllowed(ticket.due, calendar: .autoupdatingCurrent) == ticket.due
    else { throw Failure.stale }
    state.deliveries?[key]?.submitted = true
    archive.reviewReminderState = state
    try persist(archive)
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

  func commitRestore(_ archive: Archive, receipt: UUID) throws {
    var updated = archive
    var receipts = updated.restoreReceipts ?? []
    receipts.insert(receipt)
    updated.restoreReceipts = receipts
    try persist(updated)
  }

  func previewOriginalRemoval(_ original: GalaxySSIHealthOriginalStore.Original) throws
    -> GalaxySSIHealthOriginalStore.Removal {
    try originalRemoval(original, archive: load())
  }

  func commitOriginalRemoval(_ expected: GalaxySSIHealthOriginalStore.Removal) throws {
    var archive = try load()
    guard try originalRemoval(expected.original, archive: archive) == expected,
          var index = archive.originalIndex else { throw Failure.stale }
    index.originals.removeAll { $0.id == expected.id }
    index.removedOriginals = (index.removedOriginals ?? []) + [expected.original]
    index.pendingRemovals.insert(expected.id)
    archive.originalIndex = index
    let event = GalaxySSIHealthOriginalStore.RemovalEvent(at: Date(), kind: expected.original.kind,
      bytes: expected.original.bytes, linkedMeasurements: expected.count)
    archive.originalRemovalLog = Array(((archive.originalRemovalLog ?? []) + [event]).suffix(50))
    try persist(archive)
  }

  private func originalRemoval(_ original: GalaxySSIHealthOriginalStore.Original, archive: Archive) throws
    -> GalaxySSIHealthOriginalStore.Removal {
    guard archive.originalIndex?.originals.contains(original) == true else { throw Failure.stale }
    let current = archive.current
    let linked = GalaxySSIHealthReportReview.linked(original: original, revisions: archive.revisions,
      current: current, evidence: archive.reportEvidence ?? [])
    let ids = Set(linked.map { $0.reading.id })
    return .init(original: original, linked: linked, current: current.filter { ids.contains($0.id) })
  }

  func setOriginalIndex(_ index: GalaxySSIHealthOriginalStore.Index,
                        expected: GalaxySSIHealthOriginalStore.Index?) throws {
    var archive = try load()
    guard archive.originalIndex == expected else { throw Failure.stale }
    archive.originalIndex = index
    try persist(archive)
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
