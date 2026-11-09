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
  private static var activeRecognitionRuns: Set<UUID> = []

  enum Failure: Error {
    case invalid, stale, duplicate, unavailable, permission
  }

  enum PrivacyScope: String, Codable {
    case overview, weeklyReport, importOriginals, profileAnalysis, localCare
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
    var backgroundCount: Int?
  }

  struct Archive: Codable {
    var originalIndex: GalaxySSIHealthOriginalStore.Index?
    var measurementExports: [GalaxySSIHealthMeasurementExport.Receipt]?
    var reportReview: [GalaxySSIHealthReportReview.Item]?
    var reportEvidence: [GalaxySSIHealthReportReview.Evidence]?
    var tableReviews: [GalaxySSIHealthReviewReminders.TableDraft]?
    var reviewReminderState: GalaxySSIHealthReviewReminders.State?
    var recognitionJobs: [GalaxySSIHealthRecognitionJobs.Job]?
    var photoCaptureDraft: GalaxySSIHealthPhotoDraft.Batch?
    var version = 1
    var recordingReminders: GalaxySSIHealthRecordingReminders.Ledger?
    var restoreReceipts: Set<UUID>?
    var revisions: [GalaxySSIHealthReading] = []
    var lastMeasurementDeletion: MeasurementDeletion?
    var metricDeletionHistory: [GalaxySSIHealthMetricDeletion.Audit]?
    var draft: GalaxySSIHealthDraft?
    var sleepReminders: GalaxySSIHealthSleepReminder.Ledger?
    var healthKitSync: [String: GalaxySSIHealthKitSync.Checkpoint]?
    var healthKitIncidents: [String: GalaxySSIHealthKitSync.Incident]?
    var healthKitSyncSelection: Set<GalaxySSIHealthKitImport.Scope>?
    var healthKitSyncDelivery: GalaxySSIHealthSyncDelivery.State?
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
    var localCarePermission: UUID?
    var localCareLegacyPermission: UUID?
    var localCareAllowed: Bool?
    var localCare: GalaxySSIHealthCare.Ledger?
    var localCareLastEvaluatedAt: Date?
    var localCareDiscussions: [String: GalaxySSIHealthCareDiscussion.Thread]?
    var archivedCareDiscussions: [String: GalaxySSIHealthCareDiscussion.Thread]?
    var localCarePlans: [String: GalaxySSIHealthCarePlan.Proposal]?
    var localCareEvidence: [String: [GalaxySSIHealthCareEvidence.Receipt]]?
    var localCareFollowUps: [String: GalaxySSIHealthCareFollowUp.Reminder]?
    var localCareFeedback: [String: [GalaxySSIHealthCareFollowUp.FeedbackReceipt]]?
    var localCareResearch: GalaxySSIHealthCareResearch.Ledger?
    var localCareQuestions: [String: GalaxySSIHealthCareQuestions.Ledger]?
    var localCareAnswerDrafts: [String: [GalaxySSIHealthCareAnswerDraft.Item]]?
    var localCareEncounters: GalaxySSIHealthEncounter.Ledger?
    var localCareEncounterDocuments: [UUID: GalaxySSIHealthEncounterDocument.Link]?
    var localCareInstructions: GalaxySSIHealthInstruction.Ledger?
    var localInstructionProposals: [UUID: GalaxySSIHealthInstructionProposal.Proposal]?
    var localVisitJournals: GalaxySSIHealthVisitJournal.Ledger?
    var localCareAgenda: Data?

    var keepsNewImportOriginals: Bool { retainImportOriginals ?? true }

    func matchesLocalCarePermission(_ permission: UUID) -> Bool {
      localCareAllowed == true && (permission == localCarePermission || permission == localCareLegacyPermission)
    }

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
    // Dependent operations revalidate the saved profile even if refreshing the care archive must wait.
    try? reconcileLocalCareProfileScopes(profile: updated)
    NotificationCenter.default.post(name: Self.profileInputsChanged, object: owner)
  }

  func setProfileAnalysisAllowed(_ allowed: Bool) throws {
    try setPrivacy(.profileAnalysis, enabled: allowed)
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
    var archive = try JSONDecoder().decode(Archive.self,
      from: AES.GCM.open(box, using: key(create: false), authenticating: context))
    guard archive.version == 1 else { throw Failure.unavailable }
    if archive.localCareAllowed == true,
       let event = archive.privacyEvents?.last(where: { $0.scope == .localCare }), event.enabled {
      if archive.localCarePermission == nil { archive.localCarePermission = event.id }
      // Earlier builds issued discussion and reminder permissions from the audit event.
      if event.id != archive.localCarePermission { archive.localCareLegacyPermission = event.id }
    }
    return archive
  }

  func dataFilesReader() throws -> GalaxySSIHealthDataFiles.Reader {
    let url = try file
    return .init(file: url, context: context, key: try? key(create: false))
  }

  func beginMeasurementExport(format: GalaxySSIHealthMeasurementExport.Format, rows: Int,
                              includesOriginals: Bool) throws -> UUID {
    var archive = try load()
    let receipt = GalaxySSIHealthMeasurementExport.Receipt(id: UUID(), at: Date(), format: format,
      rows: rows, includesOriginals: includesOriginals, status: .prepared)
    archive.measurementExports = Array(((archive.measurementExports ?? []) + [receipt]).suffix(50))
    try persist(archive, notify: false)
    return receipt.id
  }

  func finishMeasurementExport(_ id: UUID, verified: Bool) throws {
    var archive = try load()
    guard let index = archive.measurementExports?.firstIndex(where: { $0.id == id }),
          archive.measurementExports?[index].status == .prepared else { return }
    archive.measurementExports?[index].status = verified ? .verified : .unverified
    try persist(archive, notify: false)
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
    case .localCare:
      previous = archive.localCareAllowed ?? false
      archive.localCareAllowed = enabled
      if previous != enabled {
        archive.localCarePermission = enabled ? UUID() : nil
        archive.localCareLegacyPermission = nil
      }
    }
    guard previous != enabled else { return }
    if (previous ?? (scope == .importOriginals)) != enabled {
      var history = archive.privacyEvents ?? []
      let eventID = scope == .localCare && enabled ? (archive.localCarePermission ?? UUID()) : UUID()
      history.append(.init(id: eventID, at: Date(), scope: scope, enabled: enabled))
      archive.privacyEvents = Array(history.suffix(100))
    }
    try persist(archive)
    if scope == .overview { NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner) }
    if scope == .profileAnalysis { NotificationCenter.default.post(name: Self.profileInputsChanged, object: owner) }
  }

  func reconcileLocalCare(now: Date = Date()) throws {
    var archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    let readings = Dictionary(grouping: archive.current.filter { $0.isValid && $0.measuredAt <= now }, by: \.metric)
    var ledger = archive.localCare ?? .init()
    var changed = false
    if archive.localCarePermission == nil {
      archive.localCarePermission = UUID()
      changed = true
    }
    let previousConcerns = ledger.current
    for metric in GalaxySSIHealthMetric.allCases {
      let key = metric.rawValue
      let prior = ledger.current[key]
      let series = readings[metric] ?? []
      let assessed = GalaxySSIHealthCare.assess(series, context: prior?.context)
      let warning = GalaxySSIHealthCarePriority.evaluate(series.first)
      guard prior != nil || assessed?.signals.isEmpty == false || warning != nil else { continue }
      let next = assessed ?? .removed
      if let prior {
        let maintenanceChanged = prior.stage == .maintenance &&
          (prior.maintenanceHistoryVersion != GalaxySSIHealthCareSeries.version(series) ||
            (archive.localCarePermission.flatMap {
              GalaxySSIHealthCareMaintenance.nextDue(prior, permission: $0)
            }.map { $0 <= now } ?? true))
        guard prior.revision < Int.max,
              prior.assessment != next || maintenanceChanged || prior.bloodPressureWarning != warning else { continue }
        var updated = prior
        updated.revision += 1
        updated.updatedAt = max(prior.updatedAt, now)
        updated.assessment = next
        updated.bloodPressureWarning = warning
        if updated.context?.record != next.record { updated.context = nil }
        if prior.stage != .paused && !(prior.stage == .closed && next.signals.isEmpty && warning == nil) {
          updated.stage = next.record == nil || next.signals.contains(.glucoseContext) || next.signals.contains(.notExact)
            ? .verify : .reassess
        }
        if prior.stage == .maintenance {
          updated.stage = .reassess
          updated.maintenanceHistoryVersion = nil
          updated.maintenanceReview = nil
          updated.reviewNote = nil
        }
        ledger.publish(updated)
      } else {
        guard try ledger.deletedInput[key] != GalaxySSIHealthCare.inputDigest(next) else { continue }
        ledger.publish(.init(id: UUID(), metric: metric, revision: 1, updatedAt: now, assessment: next,
          stage: next.signals.contains(.guidelineReview) ? .evidence : .verify, bloodPressureWarning: warning))
      }
      changed = true
    }
    let comparisonsChanged = ledger.reconcileComparisons(readings: readings, previous: previousConcerns, now: now)
    guard changed || comparisonsChanged || archive.localCareLastEvaluatedAt == nil else { return }
    archive.localCare = ledger
    archive.localCareLastEvaluatedAt = now
    try persist(archive)
  }

  func reconcileLocalCareMaintenance(now: Date = Date()) throws -> Date? {
    let before = try load()
    guard before.localCareAllowed == true,
          before.localCare?.current.values.contains(where: { $0.stage == .maintenance }) == true else { return nil }
    try reconcileLocalCare(now: now)
    let after = try load()
    guard let permission = after.localCarePermission, let ledger = after.localCare else { return nil }
    return ledger.current.values.compactMap {
      GalaxySSIHealthCareMaintenance.nextDue($0, permission: permission)
    }.filter { $0 > now }.min()
  }

  static func currentCareBloodPressureWarning(_ archive: Archive, now: Date = Date())
      -> (concern: GalaxySSIHealthCare.Concern, warning: GalaxySSIHealthCarePriority.Warning)? {
    guard archive.localCareAllowed == true,
          let concern = archive.localCare?.current[GalaxySSIHealthMetric.bloodPressure.rawValue],
          let warning = concern.bloodPressureWarning,
          GalaxySSIHealthCarePriority.evaluate(archive.current.first(where: {
            $0.metric == .bloodPressure && $0.isValid && $0.measuredAt <= now
          })) == warning else { return nil }
    return (concern, warning)
  }

  func acknowledgeLocalCareBloodPressure(_ warning: GalaxySSIHealthCarePriority.Warning, now: Date = Date()) throws {
    var archive = try load()
    guard var ledger = archive.localCare, Self.currentCareBloodPressureWarning(archive, now: now)?.warning == warning
    else { throw Failure.stale }
    guard ledger.acknowledgedBloodPressure != warning.record else { return }
    ledger.acknowledgedBloodPressure = warning.record
    archive.localCare = ledger
    try persist(archive)
  }

  func localCareHistory(_ id: UUID, before revision: Int = Int.max) throws -> [GalaxySSIHealthCare.Concern] {
    let archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    let history = archive.localCare?.history[id.uuidString] ?? []
    return Array(history.reversed().lazy.filter { $0.revision < revision }.prefix(30))
  }

  func openLocalCareDiscussion(id: UUID, metric: GalaxySSIHealthMetric) throws -> GalaxySSIHealthCareDiscussion.Thread {
    let current = try load()
    if current.localCare?.current[metric.rawValue]?.profileScope != nil {
      try reconcileLocalCareProfileScopes(profile: loadProfile())
    }
    var archive = try load()
    _ = try currentDiscussionConcern(id: id, metric: metric, archive: archive, now: Date())
    let key = id.uuidString
    var threads = archive.localCareDiscussions ?? [:]
    if let existing = threads[key] { return existing }
    let thread = GalaxySSIHealthCareDiscussion.Thread(concernID: id)
    threads[key] = thread
    archive.localCareDiscussions = threads
    try persist(archive)
    return thread
  }

  func setLocalCareProfileScope(_ concern: GalaxySSIHealthCare.Concern, link: GalaxySSIHealthCareProfileScope.Link?,
                                now: Date = Date()) throws {
    var archive = try load()
    var ledger = archive.localCare ?? .init()
    guard archive.localCareAllowed == true, ledger.current[concern.metric.rawValue] == concern else { throw Failure.stale }
    if let link, try !link.isCurrent(loadProfile()) { throw Failure.stale }
    guard concern.profileScope != link else { return }
    try applyLocalCareProfileScope(link, to: concern, archive: &archive, ledger: &ledger, now: now)
    archive.localCare = ledger
    try persist(archive)
  }

  private func reconcileLocalCareProfileScopes(profile: GalaxySSIHealthProfile, now: Date = Date()) throws {
    var archive = try load()
    guard archive.localCareAllowed == true, var ledger = archive.localCare else { return }
    var changed = false
    for concern in Array(ledger.current.values) {
      guard let scope = concern.profileScope, !scope.isCurrent(profile) else { continue }
      let updated = try GalaxySSIHealthCareProfileScope.Link(scope.selection, profile: profile)
      try applyLocalCareProfileScope(updated, to: concern, archive: &archive, ledger: &ledger, now: now)
      changed = true
    }
    if changed {
      archive.localCare = ledger
      try persist(archive)
    }
  }

  private func applyLocalCareProfileScope(_ scope: GalaxySSIHealthCareProfileScope.Link?,
      to concern: GalaxySSIHealthCare.Concern, archive: inout Archive,
      ledger: inout GalaxySSIHealthCare.Ledger, now: Date) throws {
    guard concern.revision < Int.max else { throw Failure.stale }
    var updated = concern
    updated.profileScope = scope
    updated.profileScopeEpoch = UUID()
    updated.revision += 1
    updated.updatedAt = max(now, updated.updatedAt)
    if updated.stage != .paused, updated.stage != .closed {
      updated.stage = .reassess
      updated.maintenanceHistoryVersion = nil
      updated.reviewNote = nil
    }
    ledger.publish(updated)
    if var old = archive.localCareDiscussions?[concern.id.uuidString] {
      archive.localCareDiscussions?[concern.id.uuidString] = .init(concernID: concern.id)
      if !old.turns.isEmpty {
        old.archivedAt = now
        var previous = archive.archivedCareDiscussions ?? [:]
        previous[old.id.uuidString] = old
        archive.archivedCareDiscussions = previous
      }
    }
    archive.localCareFollowUps = archive.localCareFollowUps?.filter { $0.value.concernID != concern.id }
  }

  func localCareProfileIsCurrent(_ scope: GalaxySSIHealthCareProfileScope.Link?) -> Bool {
    guard let scope else { return true }
    return (try? loadProfile()).map(scope.isCurrent) == true
  }

  private func localCareProfilePayload(_ concern: GalaxySSIHealthCare.Concern) throws -> AgentMcpJSONObject? {
    guard let scope = concern.profileScope else { return nil }
    guard let date = concern.assessment.measuredAt else { throw Failure.stale }
    return try scope.snapshot(loadProfile(), measuredAt: date)
  }

  private func localCareEncounterScope(id: UUID, metric: GalaxySSIHealthMetric, archive: Archive, now: Date)
      throws -> (GalaxySSIHealthCare.Concern, GalaxySSIHealthEncounter.Stamp) {
    guard archive.localCareAllowed == true, let permission = archive.localCarePermission else { throw Failure.permission }
    guard let concern = archive.localCare?.current[metric.rawValue], concern.id == id else { throw Failure.stale }
    let readings = archive.current.filter { $0.metric == metric && $0.isValid && $0.measuredAt <= now }
    guard (GalaxySSIHealthCare.assess(readings, context: concern.context) ?? .removed) == concern.assessment else {
      throw Failure.stale
    }
    return (concern, .init(concern: id, metric: metric, revision: concern.revision, permission: permission,
      records: readings.map(GalaxySSIHealthCare.Record.init)))
  }

  func localCareEncounterPage(id: UUID, metric: GalaxySSIHealthMetric, entryID: UUID? = nil, before: Int? = nil,
      expected: GalaxySSIHealthEncounter.Stamp? = nil, now: Date = Date()) throws -> GalaxySSIHealthEncounter.Page {
    let archive = try load()
    let (_, stamp) = try localCareEncounterScope(id: id, metric: metric, archive: archive, now: now)
    guard before == nil || expected != nil, expected == nil || expected == stamp else { throw Failure.stale }
    return try (archive.localCareEncounters ?? .init()).page(stamp, entryID: entryID, before: before)
  }

  func saveLocalCareEncounter(_ draft: GalaxySSIHealthEncounter.Draft, id: UUID, operation: UUID,
      expected: GalaxySSIHealthEncounter.Stamp, expectedEntry: Int?, now: Date = Date()) throws -> GalaxySSIHealthEncounter.Receipt {
    var archive = try load()
    let (concern, stamp) = try localCareEncounterScope(id: expected.concern, metric: expected.metric, archive: archive, now: now)
    guard expected.matchesInputs(stamp) else { throw Failure.stale }
    var encounters = archive.localCareEncounters ?? .init()
    let (receipt, inserted) = try encounters.save(id: id, operation: operation, expected: expected,
      expectedEntry: expectedEntry, draft: draft, concern: concern, now: now)
    if inserted {
      guard var care = archive.localCare else { throw Failure.stale }
      var current = concern
      current.revision = receipt.entry.revision
      current.updatedAt = receipt.entry.updated
      care.publish(current)
      archive.localCare = care
      archive.localCareEncounters = encounters
      try persist(archive)
    }
    return receipt
  }

  func deleteLocalCareEncounter(_ entry: GalaxySSIHealthEncounter.Entry,
      expected: GalaxySSIHealthEncounter.Stamp, now: Date = Date()) throws {
    var archive = try load()
    let (concern, stamp) = try localCareEncounterScope(id: expected.concern, metric: expected.metric, archive: archive, now: now)
    guard expected == stamp, concern.revision < Int.max - 1, entry.concern == concern.id,
          var care = archive.localCare, var encounters = archive.localCareEncounters,
          encounters.entries[entry.id] == entry else { throw Failure.stale }
    encounters.remove(concern: concern.id, entry: entry.id)
    var current = concern
    Self.invalidateInstructionActions(in: &current, archive: &archive) { $0.visit == entry.id }
    current.revision += 1
    current.updatedAt = max(now, current.updatedAt)
    care.publish(current)
    archive.localCare = care
    archive.localCareEncounters = encounters
    archive.localCareEncounterDocuments = archive.localCareEncounterDocuments?.filter { $0.value.visit != entry.id }
    archive.localCareInstructions?.remove(concern: concern.id, visit: entry.id)
    archive.localInstructionProposals = archive.localInstructionProposals?.filter { $0.value.binding.visit != entry.id }
    archive.localVisitJournals?.remove(concern: concern.id, visit: entry.id)
    try persist(archive)
  }

  typealias VisitDocuments = GalaxySSIHealthEncounterDocument

  var visitOriginalStore: GalaxySSIHealthOriginalStore {
    .init(owner: owner, secrets: secrets, fixtureDirectory: isolatedFile?.appendingPathExtension("visit-originals"),
      restoreRecordsFile: isolatedFile)
  }

  func visitDocumentContext(concern: UUID, metric: GalaxySSIHealthMetric, visit: UUID,
      archive: Archive, now: Date) throws -> (GalaxySSIHealthCare.Concern, VisitDocuments.Scope) {
    let (current, stamp) = try localCareEncounterScope(id: concern, metric: metric, archive: archive, now: now)
    guard let entry = archive.localCareEncounters?.entries[visit], entry.concern == concern else { throw Failure.stale }
    return (current, .init(stamp: stamp, visit: entry))
  }

  func visitDocumentContext(_ expected: VisitDocuments.Scope, archive: Archive, now: Date)
      throws -> (GalaxySSIHealthCare.Concern, VisitDocuments.Scope) {
    try visitDocumentContext(concern: expected.stamp.concern, metric: expected.stamp.metric,
      visit: expected.visit.id, archive: archive, now: now)
  }

  func visitDocumentPage(concern: UUID, metric: GalaxySSIHealthMetric, visit: UUID, before: Int? = nil,
      expected: VisitDocuments.Scope? = nil, now: Date = Date()) throws -> VisitDocuments.Page {
    let originals = visitOriginalStore
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let archive = try load()
      let (_, scope) = try visitDocumentContext(concern: concern, metric: metric, visit: visit, archive: archive, now: now)
      guard before == nil || expected != nil, expected == nil || expected == scope else { throw Failure.stale }
      let links = (archive.localCareEncounterDocuments ?? [:]).values
        .filter { link in link.concern == concern && link.visit == visit && (before.map { link.revision < $0 } ?? true) }
        .sorted { $0.revision > $1.revision }
        .prefix(VisitDocuments.pageSize + 1)
      let key = try key(create: false)
      let items = try links.prefix(VisitDocuments.pageSize).map { link -> VisitDocuments.Item in
        let item = try originals.visitOriginal(id: link.originalID, lease: lease)
        return .init(link: link, original: item.flatMap { VisitDocuments.matches(link, original: $0, key: key) ? $0 : nil })
      }
      return .init(scope: scope, items: items,
        next: links.count > VisitDocuments.pageSize ? items.last?.link.revision : nil)
    }
  }

  func visitDocumentLibrary(_ expected: VisitDocuments.Scope, after: VisitDocuments.Original? = nil,
      now: Date = Date()) throws -> VisitDocuments.LibraryPage {
    let originals = visitOriginalStore
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let (_, scope) = try visitDocumentContext(expected, archive: load(), now: now)
      guard scope == expected else { throw Failure.stale }
      let found = try originals.visitOriginals(after: after, limit: VisitDocuments.pageSize + 1, lease: lease)
      let page = Array(found.prefix(VisitDocuments.pageSize))
      return .init(originals: page, next: found.count > page.count ? page.last : nil)
    }
  }

  func previewVisitDocument(_ original: VisitDocuments.Original, page: Int, expected: VisitDocuments.Scope,
      link: VisitDocuments.Link? = nil, validUntil: Date? = nil, now: Date = Date()) throws -> VisitDocuments.Preview {
    let expires = min(validUntil ?? .distantFuture, now.addingTimeInterval(VisitDocuments.previewLifetime))
    guard now < expires else { throw Failure.stale }
    let originals = visitOriginalStore
    return try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      let archive = try load()
      let (_, scope) = try visitDocumentContext(expected, archive: archive, now: now)
      guard scope == expected, try originals.visitOriginal(id: original.id, lease: lease) == original else {
        throw Failure.stale
      }
      if let link {
        guard archive.localCareEncounterDocuments?[link.id] == link, link.visit == scope.visit.id,
              link.concern == scope.stamp.concern, link.page == nil || link.page == page,
              VisitDocuments.matches(link, original: original, key: try key(create: false)) else { throw Failure.stale }
      }
      let (image, count) = try VisitDocuments.render(originals.read(original, lease: lease), kind: original.kind, page: page)
      guard link == nil || link?.pageCount == count else { throw Failure.stale }
      return .init(scope: scope, original: original, page: page, count: count, image: image,
        expires: expires, operation: UUID())
    }
  }

  @discardableResult
  func linkVisitDocument(_ preview: VisitDocuments.Preview, whole: Bool, now: Date = Date()) throws -> VisitDocuments.Link {
    let originals = visitOriginalStore
    let (result, inserted) = try originals.withRestoreLease { lease -> (VisitDocuments.Link, Bool) in
      try originals.reconcileRestores(lease: lease)
      var archive = try load()
      let (concern, scope) = try visitDocumentContext(preview.scope, archive: archive, now: now)
      guard now < preview.expires, scope.visit == preview.scope.visit, scope.stamp.matchesInputs(preview.scope.stamp),
            try originals.visitOriginal(id: preview.original.id, lease: lease) == preview.original else { throw Failure.stale }
      let (_, count) = try VisitDocuments.render(originals.read(preview.original, lease: lease),
        kind: preview.original.kind, page: preview.page)
      guard count == preview.count else { throw Failure.stale }
      let fingerprint = VisitDocuments.fingerprint(preview.original, key: try key(create: false))
      let page = whole ? nil : preview.page
      var links = archive.localCareEncounterDocuments ?? [:]
      if let existing = links[preview.operation] {
        guard existing.concern == concern.id, existing.visit == scope.visit.id, existing.visitRevision == scope.visit.revision,
              existing.expectedConcernRevision == preview.scope.stamp.revision, existing.originalID == preview.original.id,
              existing.fingerprint == fingerprint, existing.page == page, existing.pageCount == count else { throw Failure.stale }
        return (existing, false)
      }
      guard scope == preview.scope, concern.revision < Int.max - 1 else { throw Failure.stale }
      if let existing = links.values.first(where: {
        $0.visit == scope.visit.id && $0.visitRevision == scope.visit.revision &&
          $0.originalID == preview.original.id && $0.fingerprint == fingerprint && $0.page == page && $0.pageCount == count
      }) { return (existing, false) }
      let link = VisitDocuments.Link(id: preview.operation, concern: concern.id, visit: scope.visit.id,
        visitRevision: scope.visit.revision, expectedConcernRevision: concern.revision, revision: concern.revision + 1,
        originalID: preview.original.id, fingerprint: fingerprint, page: page, pageCount: count)
      links[link.id] = link
      archive.localCareEncounterDocuments = links
      try publishVisitDocumentChange(concern, archive: &archive, now: now, notify: false)
      return (link, true)
    }
    if inserted { NotificationCenter.default.post(name: Self.recordsChanged, object: owner) }
    return result
  }

  func unlinkVisitDocument(_ link: VisitDocuments.Link, expected: VisitDocuments.Scope, now: Date = Date()) throws {
    var archive = try load()
    let (concern, scope) = try visitDocumentContext(expected, archive: archive, now: now)
    guard scope == expected, link.concern == concern.id, link.visit == scope.visit.id, concern.revision < Int.max - 1,
          archive.localCareEncounterDocuments?[link.id] == link else { throw Failure.stale }
    guard archive.localCareInstructions?.uses(linkID: link.id) != true else {
      throw GalaxySSIHealthInstruction.Failure.sourceInUse
    }
    archive.localCareEncounterDocuments?.removeValue(forKey: link.id)
    try publishVisitDocumentChange(concern, archive: &archive, now: now)
  }

  func publishVisitDocumentChange(_ concern: GalaxySSIHealthCare.Concern, archive: inout Archive,
      now: Date, notify: Bool = true) throws {
    guard var care = archive.localCare else { throw Failure.stale }
    var current = concern
    current.revision += 1
    current.updatedAt = max(now, current.updatedAt)
    care.publish(current)
    archive.localCare = care
    try persist(archive, notify: notify)
  }

  func persistInstructionProposals(_ archive: Archive) throws { try persist(archive, notify: false) }

  func verifiedVisitDocumentOriginal(_ link: VisitDocuments.Link, scope: VisitDocuments.Scope,
      archive: Archive, originals: GalaxySSIHealthOriginalStore, lease: GalaxySSIHealthOriginalStore.RestoreLease)
      throws -> VisitDocuments.Original {
    guard archive.localCareEncounterDocuments?[link.id] == link, link.concern == scope.stamp.concern, link.visit == scope.visit.id,
          let original = try originals.visitOriginal(id: link.originalID, lease: lease),
          VisitDocuments.matches(link, original: original, key: try key(create: false)) else { throw Failure.stale }
    return original
  }

  func localCareVisitPreview(id: UUID, metric: GalaxySSIHealthMetric, sections: Set<GalaxySSIHealthCareVisit.Section>,
      language: String, now: Date = Date()) throws -> GalaxySSIHealthCareVisit.Preview {
    typealias Visit = GalaxySSIHealthCareVisit
    typealias Questions = GalaxySSIHealthCareQuestions
    guard !sections.isEmpty else { throw Failure.invalid }
    let archive = try load()
    guard archive.localCareAllowed == true, let permission = archive.localCarePermission else { throw Failure.permission }
    let readings = archive.current.filter { $0.metric == metric && $0.isValid && $0.measuredAt <= now }
    guard let concern = archive.localCare?.current[metric.rawValue], concern.id == id,
          let measuredAt = concern.assessment.measuredAt, concern.assessment.record != nil,
          GalaxySSIHealthCare.assess(readings, context: concern.context) == concern.assessment else { throw Failure.stale }
    let presentation = Visit.Presentation(language: language)
    let link = sections.contains(.profile) ? concern.profileScope : nil
    let profile = try link.map { _ in try loadProfile() }
    let profilePayload = try link.flatMap { scope in try profile.map { try scope.snapshot($0, measuredAt: measuredAt) } }
    var items: [Visit.Item] = []
    var limitations = [presentation.t("limitations", "Selected local information only. Not a diagnosis, treatment plan or complete medical history.")]
    var questionVersion: String?
    if sections.contains(.measurements) {
      items += readings.prefix(8).map { presentation.measurement($0, concern: concern, latest: readings.first) }
      if readings.count > 8 { limitations.append(presentation.t("more_records", "Only the eight latest readings are included.")) }
    }
    if sections.contains(.context) { items.append(presentation.context(concern)) }
    if sections.contains(.actions) {
      let context = careAgendaContext(concern, readings: readings)
      let actions = concern.adoptedActions ?? []
      items += actions.prefix(48).map { action in
        var pending = action
        pending.outcome = nil
        return presentation.action(action, concern: concern,
          stale: !careActionIsCurrent(pending, concern: concern, archive: archive, context: context, now: now))
      }
      if actions.count > 48 { limitations.append(presentation.t("more_actions", "Only the first 48 confirmed actions are included.")) }
    }
    if sections.contains(.questions) {
      let ledger = archive.localCareQuestions?[id.uuidString] ?? .init()
      let page = try ledger.page(scope: Questions.scope(concern), basis: Questions.basis(concern),
        known: Questions.known(concern, profile: profilePayload), after: nil)
      questionVersion = page.ledgerVersion
      items += page.rows.prefix(8).map { presentation.question($0, page: page) }
      if page.rows.count > 8 || page.next != nil {
        limitations.append(presentation.t("more_questions", "Only the first eight questions are included."))
      }
    }
    if sections.contains(.profile) { items += try presentation.profile(profile, link: link, at: measuredAt) }
    let stamp = Visit.Stamp(revision: concern.revision, permission: permission, records: readings.map(GalaxySSIHealthCare.Record.init),
      questionVersion: questionVersion, profile: link)
    let revision = String(format: presentation.t("revision", "Revision %lld"), Int64(concern.revision))
    return .init(created: now, sections: sections, stamp: stamp, heading: presentation.t("title", "Prepare for a visit"),
      introduction: [metric.title(language: language), presentation.date(now), revision].joined(separator: " · "),
      limitations: limitations.joined(separator: "\n"), items: items)
  }

  func localCareVisitSource(_ reference: GalaxySSIHealthCare.Record, metric: GalaxySSIHealthMetric) throws -> GalaxySSIHealthReading {
    let archive = try load()
    guard archive.localCareAllowed == true, let reading = archive.current.first(where: {
      $0.metric == metric && $0.id == reference.id && $0.revision == reference.revision
    }) else { throw Failure.stale }
    return reading
  }

  func localCareQuestionPage(id: UUID, metric: GalaxySSIHealthMetric, after: UUID? = nil,
                             now: Date = Date()) throws -> GalaxySSIHealthCareQuestions.Page {
    let archive = try load()
    let concern = try currentDiscussionConcern(id: id, metric: metric, archive: archive, now: now)
    return try localCareQuestionPage(concern, archive: archive, after: after)
  }

  private func localCareQuestionPage(_ concern: GalaxySSIHealthCare.Concern, archive: Archive,
      after: UUID?) throws -> GalaxySSIHealthCareQuestions.Page {
    typealias Questions = GalaxySSIHealthCareQuestions
    let ledger = archive.localCareQuestions?[concern.id.uuidString] ?? .init()
    return try ledger.page(scope: Questions.scope(concern), basis: Questions.basis(concern),
      known: Questions.known(concern, profile: localCareProfilePayload(concern)), after: after)
  }

  func reviewLocalCareQuestion(id: UUID, metric: GalaxySSIHealthMetric, row: GalaxySSIHealthCareQuestions.Row,
      state: GalaxySSIHealthCareQuestions.State, answer: String? = nil, now: Date = Date()) throws {
    var archive = try load()
    let concern = try currentDiscussionConcern(id: id, metric: metric, archive: archive, now: now)
    try applyLocalCareQuestionReview(concern, row: row, state: state, answer: answer, now: now, archive: &archive)
    try persist(archive)
  }

  private func applyLocalCareQuestionReview(_ original: GalaxySSIHealthCare.Concern, row: GalaxySSIHealthCareQuestions.Row,
      state: GalaxySSIHealthCareQuestions.State, answer: String?, now: Date, archive: inout Archive) throws {
    typealias Questions = GalaxySSIHealthCareQuestions
    var concern = original
    let id = concern.id
    guard var care = archive.localCare, var ledger = archive.localCareQuestions?[id.uuidString],
          concern.revision < Int.max else { throw Failure.stale }
    let facts = try Questions.known(concern, profile: localCareProfilePayload(concern))
    let conflicts = facts[row.proposal.key].map { !Questions.matches(answer, fact: $0) } == true
    let effective = state == .answered && conflicts ? Questions.State.conflict : state
    try ledger.review(row, scope: Questions.scope(concern), basis: Questions.basis(concern), state: effective,
      answer: answer, now: now)
    archive.localCareQuestions?[id.uuidString] = ledger
    concern.questionRevision = UUID()
    concern.revision += 1
    concern.updatedAt = max(now, concern.updatedAt)
    concern.stage = .reassess
    concern.maintenanceReview = nil
    concern.maintenanceHistoryVersion = nil
    concern.reviewNote = nil
    care.publish(concern)
    archive.localCare = care
    archive.localCareResearch?.revoke(id)
    archive.localCareFollowUps = archive.localCareFollowUps?.filter { $0.value.concernID != id }
  }

  @discardableResult
  func stageLocalCareAnswerDraft(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      arguments: AgentMcpJSONObject, now: Date = Date()) throws -> GalaxySSIHealthCareAnswerDraft.Item {
    typealias Draft = GalaxySSIHealthCareAnswerDraft
    guard approval.allowsAnswerDraft, !approval.feedbackHistoryAllowed, approval.research == nil,
          !approval.asksQuestions, !approval.proposesPlan,
          approval.history == nil, approval.model != nil, let page = approval.questions else { throw Failure.permission }
    let input = try Draft.Input(arguments)
    let digest = Draft.digest(approval.question)
    guard Draft.matches(input.quote, in: approval.question),
          let row = Draft.eligible(page).first(where: { $0.id == input.question && $0.revision == input.revision })
    else { throw Failure.invalid }
    var archive = try load()
    let key = approval.concernID.uuidString
    var thread = try checkedDiscussion(approval, archive: archive, now: now)
    guard let index = thread.turns.indices.last else { throw Failure.stale }
    let turn = thread.turns[index]
    guard turn.id == approval.id, turn.destination == approval.destinationDigest,
          turn.feedbackHistoryAllowed != true,
          turn.answerDraftSourceDigest == digest, turn.questionContextIncluded == true,
          turn.questionSnapshotVersion == page.ledgerVersion, Draft.digest(turn.question) == digest,
          turn.answer == nil, turn.proposalID == nil else { throw Failure.stale }
    var drafts = archive.localCareAnswerDrafts ?? [:]
    var items = drafts[key] ?? []
    if let prior = items.first(where: { $0.thread == thread.id && $0.turn == turn.id && $0.question == row.id }) {
      return prior
    }
    guard items.count < Draft.limit else { throw Failure.invalid }
    let item = Draft.Item(thread: thread.id, turn: turn.id, question: row.id, revision: row.revision,
      basis: page.basis, questionText: row.proposal.question, scope: row.scope, carePermission: approval.carePermission,
      onlinePermission: approval.onlinePermission, profileScopeEpoch: approval.profileScopeEpoch,
      sourceDigest: digest, quote: input.quote, answer: input.answer, createdAt: now)
    items.insert(item, at: 0)
    drafts[key] = items
    archive.localCareAnswerDrafts = drafts
    thread.turns[index].answerDraftStaged = true
    archive.localCareDiscussions?[key] = thread
    try persist(archive)
    return item
  }

  private func localCareAnswerDraftRow(_ draft: GalaxySSIHealthCareAnswerDraft.Item,
      concern: GalaxySSIHealthCare.Concern, archive: Archive) -> GalaxySSIHealthCareQuestions.Row? {
    typealias Draft = GalaxySSIHealthCareAnswerDraft
    typealias Questions = GalaxySSIHealthCareQuestions
    let key = concern.id.uuidString
    guard archive.matchesLocalCarePermission(draft.carePermission),
          archive.healthOnlinePermission == draft.onlinePermission, concern.profileScopeEpoch == draft.profileScopeEpoch,
          localCareProfileIsCurrent(concern.profileScope),
          let thread = archive.localCareDiscussions?[key], thread.id == draft.thread,
          let turn = thread.turns.first(where: { $0.id == draft.turn }),
          turn.answerDraftSourceDigest == draft.sourceDigest, turn.questionContextIncluded == true,
          Draft.digest(turn.question) == draft.sourceDigest, Draft.matches(draft.quote, in: turn.question),
          let row = archive.localCareQuestions?[key]?.revisions[draft.question.uuidString]?.last,
          row.revision == draft.revision, row.scope == draft.scope, row.basis == draft.basis,
          draft.scope == Questions.scope(concern), draft.basis == Questions.basis(concern),
          let known = try? Questions.known(concern, profile: localCareProfilePayload(concern)),
          row.displayedState(basis: draft.basis, known: known[row.proposal.key]) == .open
    else { return nil }
    return row
  }

  func localCareAnswerDraftPage(id: UUID, metric: GalaxySSIHealthMetric, after: UUID? = nil,
      now: Date = Date()) throws -> GalaxySSIHealthCareAnswerDraft.Page {
    typealias Draft = GalaxySSIHealthCareAnswerDraft
    let archive = try load()
    let concern = try currentDiscussionConcern(id: id, metric: metric, archive: archive, now: now)
    let visible = (archive.localCareAnswerDrafts?[id.uuidString] ?? []).filter {
      $0.state == .pending && localCareAnswerDraftRow($0, concern: concern, archive: archive) != nil
    }
    let start: Int
    if let after {
      guard let index = visible.firstIndex(where: { $0.id == after }) else { throw Failure.stale }
      start = index + 1
    } else { start = 0 }
    let items = Array(visible.dropFirst(start).prefix(Draft.pageSize))
    return .init(items: items, next: start + items.count < visible.count ? items.last?.id : nil)
  }

  func reviewLocalCareAnswerDraft(id: UUID, metric: GalaxySSIHealthMetric,
      draft: GalaxySSIHealthCareAnswerDraft.Item, answer: String?, now: Date = Date()) throws {
    var archive = try load()
    let concern = try currentDiscussionConcern(id: id, metric: metric, archive: archive, now: now)
    let key = id.uuidString
    guard var items = archive.localCareAnswerDrafts?[key],
          let index = items.firstIndex(where: { $0.id == draft.id }), items[index] == draft, draft.state == .pending,
          let row = localCareAnswerDraftRow(draft, concern: concern, archive: archive) else { throw Failure.stale }
    if let answer {
      let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
      guard GalaxySSIHealthCareAnswerDraft.valid(text) else { throw Failure.invalid }
      try applyLocalCareQuestionReview(concern, row: row, state: .answered, answer: text, now: now, archive: &archive)
      items[index].state = .accepted
      items[index].reviewedAnswer = text
    } else {
      items[index].state = .dismissed
    }
    items[index].reviewedAt = max(now, draft.createdAt)
    archive.localCareAnswerDrafts?[key] = items
    try persist(archive)
  }

  func saveLocalCareQuestionProposals(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      arguments: AgentMcpJSONObject, now: Date = Date()) throws {
    typealias Questions = GalaxySSIHealthCareQuestions
    guard approval.asksQuestions, let approvedPage = approval.questions else { throw Failure.permission }
    let proposals = try Questions.parse(arguments)
    var archive = try load()
    var thread = try checkedDiscussion(approval, archive: archive, now: now)
    let key = approval.concernID.uuidString
    guard let index = thread.turns.indices.last, thread.turns[index].id == approval.id,
          thread.turns[index].questionsRequested == true, thread.turns[index].questionsRetained != true,
          thread.turns[index].answer == nil, thread.turns[index].proposalID == nil,
          let concern = archive.localCare?.current[approval.metric.rawValue] else { throw Failure.stale }
    var ledgers = archive.localCareQuestions ?? [:]
    var ledger = ledgers[key] ?? .init()
    try ledger.propose(proposals, scope: Questions.scope(concern), basis: approvedPage.basis,
      known: approvedPage.known, turn: approval.id, now: now)
    ledgers[key] = ledger
    archive.localCareQuestions = ledgers
    thread.turns[index].questionsRetained = true
    archive.localCareDiscussions?[key] = thread
    try persist(archive)
  }

  func prepareLocalCareDiscussion(id: UUID, metric: GalaxySSIHealthMetric, question: String,
      destinationID: String, model: CloudModelConfig, credential: String, proposesPlan: Bool = false,
      allowsHistory: Bool = false, research: GalaxySSIHealthCareResearch.Job? = nil,
      includesQuestions: Bool = false, asksQuestions: Bool = false, allowsAnswerDraft: Bool = false,
      includesActionFeedback: Bool = true,
      feedbackHistoryAllowed: Bool = false, now: Date = Date())
      throws -> GalaxySSIHealthCareDiscussion.Approval {
    guard research == nil || (proposesPlan && !allowsHistory) else { throw Failure.invalid }
    guard !asksQuestions || (!proposesPlan && !allowsHistory && research == nil),
          research == nil || !includesQuestions else { throw Failure.invalid }
    guard !allowsAnswerDraft || (includesQuestions && !asksQuestions && !proposesPlan && !allowsHistory &&
            !feedbackHistoryAllowed && research == nil)
    else { throw Failure.permission }
    guard !feedbackHistoryAllowed || (research == nil && !asksQuestions) else { throw Failure.invalid }
    let archive = try load()
    let concern = try currentDiscussionConcern(id: id, metric: metric, archive: archive, now: now)
    guard let care = archive.localCarePermission,
          let online = archive.healthOnlinePermission, let thread = archive.localCareDiscussions?[id.uuidString],
          thread.turns.count < GalaxySSIHealthCareDiscussion.maximumTurns,
          let endpoint = GalaxySSIHealthCareDiscussion.endpoint(for: model),
          CloudModelCredentialPolicy.isStoredCredential(credential) else { throw Failure.permission }
    let credentialDigest = SHA256.hash(data: Data(credential.utf8))
    let destination = GalaxySSIHealthCareDiscussion.destination(contactID: destinationID, model: model, endpoint: endpoint,
      credential: credentialDigest)
    let turn = research?.id ?? UUID()
    let sharesFeedback = research == nil ? (includesActionFeedback && !allowsAnswerDraft) :
      archive.localCareResearch?.authorizations[id.uuidString]?.sharesActionFeedback == true
    let sharesHistory = research == nil ? feedbackHistoryAllowed :
      archive.localCareResearch?.authorizations[id.uuidString]?.sharesFeedbackHistory == true
    let feedback = sharesFeedback ? localCareModelFeedback(concern, thread: thread, destination: destination,
      archive: archive, includesHistory: sharesHistory) : nil
    var approval = GalaxySSIHealthCareDiscussion.Approval(id: turn, owner: owner, threadID: thread.id,
      priorTurnID: thread.turns.last?.id,
      concernID: id, metric: metric, concernRevision: concern.revision, carePermission: care,
      onlinePermission: online, destinationID: destinationID, destinationDigest: destination,
      destination: .cloud(model: model, endpoint: endpoint, credential: credentialDigest),
      question: question, payload: try GalaxySSIHealthCareDiscussion.payload(concern: concern, question: question,
        thread: thread, destination: destination, savedProfile: localCareProfilePayload(concern), actionFeedback: feedback),
      reviewedAt: now, proposesPlan: proposesPlan, profileScope: concern.profileScope,
      profileScopeEpoch: concern.profileScopeEpoch, research: research)
    approval.includesActionFeedback = sharesFeedback
    approval.actionFeedbackContextIncluded = feedback != nil
    approval.feedbackHistoryAllowed = sharesHistory
    if includesQuestions || asksQuestions {
      let page = try localCareQuestionPage(concern, archive: archive, after: nil)
      approval.questions = page
      if allowsAnswerDraft {
        guard !GalaxySSIHealthCareAnswerDraft.eligible(page).isEmpty else { throw Failure.stale }
      } else {
        approval.questionCursor = .init(page, remaining: GalaxySSIHealthCareQuestions.maximumContinuations)
      }
      approval.asksQuestions = asksQuestions
      approval.allowsAnswerDraft = allowsAnswerDraft
    }
    if let research {
      if let authorization = archive.localCareResearch?.authorizations[id.uuidString], authorization.sharesQuestionSnapshot == true {
        let page = try localCareQuestionPage(concern, archive: archive, after: nil)
        approval.questions = page
        if authorization.sharesQuestionPages == true {
          approval.questionCursor = .init(page, remaining: GalaxySSIHealthCareQuestions.maximumContinuations)
        }
      }
      let handoff = try makeLocalCareResearchHandoff(research, concern: concern, archive: archive)
      approval.researchHandoff = handoff
      approval.proposesPlan = handoff.plansOnly
      try validateLocalCareResearch(approval, archive: archive, concern: concern, state: .preparing, now: now)
    }
    if allowsHistory {
      let page = try localCareMeasurementPage(id: id, metric: metric, now: now)
      guard page.binding.revision == concern.revision, page.binding.permission == care else { throw Failure.stale }
      approval.history = .init(binding: page.binding, recent: try GalaxySSIHealthCareHistoryTool.output(page,
        metric: metric, turn: turn, remaining: GalaxySSIHealthCareHistoryTool.maximumPages))
    }
    return approval
  }

  func prepareLocalCareDesktopDiscussion(id: UUID, metric: GalaxySSIHealthMetric, question: String,
      route: GalaxySSIHealthDesktopResearch.Route, research: GalaxySSIHealthCareResearch.Job? = nil,
      resume: GalaxySSIHealthDesktopResearch.Binding? = nil, includesQuestions: Bool = false,
      includesActionFeedback: Bool = true,
      now: Date = Date()) throws -> GalaxySSIHealthCareDiscussion.Approval {
    guard research == nil || !includesQuestions else { throw Failure.invalid }
    let archive = try load()
    let concern = try currentDiscussionConcern(id: id, metric: metric, archive: archive, now: now)
    guard let care = archive.localCarePermission, let online = archive.healthOnlinePermission,
          var thread = archive.localCareDiscussions?[id.uuidString] else { throw Failure.permission }
    let turn = research?.id ?? UUID()
    let reviewedAt: Date
    let effectiveQuestion: String
    if let resume {
      guard resume.job == turn, resume.route == route, let active = thread.turns.last, active.id == turn,
            active.answer == nil, active.proposalID == nil else { throw Failure.stale }
      thread.turns.removeLast()
      effectiveQuestion = active.question
      reviewedAt = Date(timeIntervalSince1970: Double(resume.createdAtMillis) / 1_000)
    } else {
      effectiveQuestion = question
      reviewedAt = now
    }
    guard thread.turns.count < GalaxySSIHealthCareDiscussion.maximumTurns else { throw Failure.permission }
    let sharesFeedback = research == nil ? includesActionFeedback :
      archive.localCareResearch?.authorizations[id.uuidString]?.sharesActionFeedback == true
    let feedback = sharesFeedback ? localCareModelFeedback(concern, thread: thread, destination: route.digest, archive: archive) : nil
    var approval = GalaxySSIHealthCareDiscussion.Approval(id: turn, owner: owner, threadID: thread.id,
      priorTurnID: thread.turns.last?.id, concernID: id, metric: metric, concernRevision: concern.revision,
      carePermission: care, onlinePermission: online, destinationID: route.connector.contactId,
      destinationDigest: route.digest, destination: .paired(route), question: effectiveQuestion,
      payload: try GalaxySSIHealthCareDiscussion.payload(concern: concern, question: effectiveQuestion, thread: thread,
        destination: route.digest, savedProfile: localCareProfilePayload(concern), actionFeedback: feedback), reviewedAt: reviewedAt,
      profileScope: concern.profileScope, profileScopeEpoch: concern.profileScopeEpoch, research: research)
    approval.includesActionFeedback = sharesFeedback
    approval.actionFeedbackContextIncluded = feedback != nil
    if includesQuestions || (research != nil && archive.localCareResearch?.authorizations[id.uuidString]?.sharesQuestionSnapshot == true) {
      approval.questions = try localCareQuestionPage(concern, archive: archive, after: nil)
    }
    if resume != nil {
      guard archive.localCareDiscussions?[id.uuidString]?.turns.last?.questionSnapshotVersion ==
        approval.questions?.ledgerVersion else { throw Failure.stale }
    }
    if let research {
      let handoff = try makeLocalCareResearchHandoff(research, concern: concern, archive: archive)
      approval.researchHandoff = handoff
      approval.proposesPlan = handoff.plansOnly
      if resume != nil { approval.evidence = archive.localCareEvidence?[turn.uuidString] ?? [] }
      try validateLocalCareResearch(approval, archive: archive, concern: concern,
        state: resume == nil ? .preparing : .dispatched, now: now)
    }
    return approval
  }

  func authorizeLocalCareResearch(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      sources: Set<GalaxySSIHealthCareEvidence.PublicSource>, sharesActionFeedback: Bool = false,
      now: Date = Date()) throws {
    guard !sources.isEmpty, approval.research == nil, approval.history == nil, !approval.asksQuestions, !approval.allowsAnswerDraft,
          !approval.feedbackHistoryAllowed, !approval.allowsStandingFeedbackPages || approval.model != nil,
          !sharesActionFeedback || approval.includesActionFeedback,
          !approval.allowsStandingQuestionPages || (approval.questions != nil && approval.model != nil)
    else { throw Failure.invalid }
    var archive = try load()
    let thread = try checkedDiscussion(approval, archive: archive, now: now)
    guard thread.turns.last?.id == approval.priorTurnID else { throw Failure.stale }
    var ledger = archive.localCareResearch ?? .init()
    ledger.renew(.init(concern: approval.concernID, metric: approval.metric, thread: approval.threadID,
      localPermission: approval.carePermission, onlinePermission: approval.onlinePermission,
      profileScopeEpoch: approval.profileScopeEpoch,
      contact: approval.destinationID, model: approval.modelID, endpoint: approval.endpoint,
      destination: approval.destinationDigest, sources: sources, authorizedAt: now, handoffVersion: 1,
      pairedDesktop: approval.pairedDesktop, sharesQuestionSnapshot: approval.questions == nil ? nil : true,
      sharesQuestionPages: approval.allowsStandingQuestionPages ? true : nil,
      sharesActionFeedback: sharesActionFeedback ? true : nil,
      sharesFeedbackHistory: approval.allowsStandingFeedbackPages ? true : nil))
    archive.localCareResearch = ledger
    try persist(archive)
  }

  func revokeLocalCareResearch(_ concern: UUID) throws {
    var archive = try load()
    guard archive.localCareResearch?.authorizations[concern.uuidString] != nil else { return }
    archive.localCareResearch?.revoke(concern)
    try persist(archive)
  }

  func reconcileLocalCareResearch(now: Date = Date()) throws
      -> [(GalaxySSIHealthCareResearch.Authorization, GalaxySSIHealthCareResearch.Job)] {
    typealias Research = GalaxySSIHealthCareResearch
    let initial = try load()
    guard let saved = initial.localCareResearch, !saved.authorizations.isEmpty else { return [] }
    if initial.localCareAllowed == true { try reconcileLocalCare(now: now) }
    var archive = try load()
    var ledger = archive.localCareResearch ?? .init()
    let previous = ledger
    for authorization in Array(ledger.authorizations.values) {
      guard authorization.handoffVersion == 1, archive.localCarePermission == authorization.localPermission,
            archive.healthOnlinePermission == authorization.onlinePermission,
            archive.localCareDiscussions?[authorization.concern.uuidString]?.id == authorization.thread,
            let concern = try? currentDiscussionConcern(id: authorization.concern, metric: authorization.metric,
              archive: archive, now: now), concern.profileScopeEpoch == authorization.profileScopeEpoch,
            localCareProfileIsCurrent(concern.profileScope) else {
        ledger.revoke(authorization.concern)
        continue
      }
      ledger.reconcile(authorization, trigger: try localCareResearchTrigger(concern, archive: archive, now: now),
        revision: concern.revision, process: Research.process, now: now)
    }
    if ledger != previous {
      archive.localCareResearch = ledger
      try persist(archive)
    }
    let queued: [(Research.Authorization, Research.Job)] = ledger.authorizations.values.compactMap { auth in
      guard let job = ledger.jobs[auth.concern.uuidString], job.state == .queued else { return nil }
      return (auth, job)
    }
    return queued.sorted { ($0.1.createdAt, $0.1.id.uuidString) < ($1.1.createdAt, $1.1.id.uuidString) }
  }

  func transitionLocalCareResearch(_ job: GalaxySSIHealthCareResearch.Job, concern: UUID,
      to state: GalaxySSIHealthCareResearch.State) throws -> GalaxySSIHealthCareResearch.Job {
    var archive = try load()
    guard var ledger = archive.localCareResearch else { throw Failure.stale }
    try ledger.transition(job, concern: concern, to: state, process: GalaxySSIHealthCareResearch.process)
    guard let updated = ledger.jobs[concern.uuidString] else { throw Failure.stale }
    archive.localCareResearch = ledger
    try persist(archive)
    return updated
  }

  func currentLocalCareResearchJob(_ authorization: GalaxySSIHealthCareResearch.Authorization, id: UUID,
      now: Date = Date()) -> GalaxySSIHealthCareResearch.Job? {
    guard let archive = try? load(), archive.localCareResearch?.authorizations[authorization.concern.uuidString] == authorization,
          archive.localCarePermission == authorization.localPermission,
          archive.healthOnlinePermission == authorization.onlinePermission,
          archive.localCareDiscussions?[authorization.concern.uuidString]?.id == authorization.thread,
          let job = archive.localCareResearch?.jobs[authorization.concern.uuidString], job.id == id,
          job.state.active, let concern = try? currentDiscussionConcern(id: authorization.concern,
            metric: authorization.metric, archive: archive, now: now), concern.revision == job.revision,
          concern.profileScopeEpoch == authorization.profileScopeEpoch, localCareProfileIsCurrent(concern.profileScope),
          (try? localCareResearchTrigger(concern, archive: archive, now: now)) == job.trigger
    else { return nil }
    return job
  }

  private func localCareResearchTrigger(_ concern: GalaxySSIHealthCare.Concern, archive: Archive, now: Date) throws -> String {
    let measurements = archive.current.filter { $0.metric == concern.metric && $0.isValid && $0.measuredAt <= now }
    let key = concern.id.uuidString
    guard let authorization = archive.localCareResearch?.authorizations[key],
          let thread = archive.localCareDiscussions?[key], thread.id == authorization.thread else { throw Failure.stale }
    let plans = scopedLocalCareResearchPlans(thread.turns, authorization: authorization, archive: archive)
    return try GalaxySSIHealthCareResearch.trigger(concern, history: GalaxySSIHealthCareSeries.version(measurements),
      now: now, scopedActions: scopedLocalCareResearchActions(concern, plans: plans,
        includesFeedback: authorization.sharesActionFeedback == true || authorization.sharesFeedbackHistory == true),
      clinicalFeedback: scopedClinicalFeedback(concern, authorization: authorization, archive: archive))
  }

  func bindLocalCareDesktopResearch(_ authorization: GalaxySSIHealthCareResearch.Authorization,
      job: UUID, sender: String, reviewedAt: Date, now: Date = Date()) throws -> GalaxySSIHealthDesktopResearch.Binding {
    guard let route = authorization.pairedDesktop,
          let current = currentLocalCareResearchJob(authorization, id: job, now: now), current.state == .dispatched,
          let at = Int64(exactly: (reviewedAt.timeIntervalSince1970 * 1_000).rounded(.down)) else { throw Failure.stale }
    var archive = try load()
    guard var research = archive.localCareResearch,
          research.authorizations[authorization.concern.uuidString] == authorization,
          research.jobs[authorization.concern.uuidString] == current else { throw Failure.stale }
    var transport = research.desktopTransport ?? .init()
    if let existing = transport.active[job.uuidString] { return existing }
    let binding = try GalaxySSIHealthDesktopResearch.Binding(route: route, authorization: authorization,
      job: current, sender: sender, createdAtMillis: at)
    try transport.bind(binding)
    research.desktopTransport = transport
    archive.localCareResearch = research
    try persist(archive)
    return binding
  }

  func dispatchedLocalCareDesktopResearch() throws
      -> [(GalaxySSIHealthCareResearch.Authorization, GalaxySSIHealthCareResearch.Job, GalaxySSIHealthDesktopResearch.Binding)] {
    guard let research = try load().localCareResearch else { return [] }
    return (research.desktopTransport?.active.values.sorted { $0.createdAtMillis < $1.createdAtMillis } ?? []).compactMap {
      guard let auth = research.authorizations[$0.concern.uuidString], auth.id == $0.authorization,
            let job = research.jobs[$0.concern.uuidString], job.id == $0.job, job.state == .dispatched else { return nil }
      return (auth, job, $0)
    }
  }

  func currentLocalCareDesktopResearch(_ identity: AgentTaskIdentity, contact: String, source: Int64,
      now: Date = Date()) -> GalaxySSIHealthDesktopResearch.Binding? {
    guard identity.conversationId.hasPrefix(GalaxySSIHealthDesktopResearch.conversationPrefix),
          let job = UUID(uuidString: identity.turnId),
          let archive = try? load(), let research = archive.localCareResearch,
          let binding = research.desktopTransport?.active[job.uuidString], binding.identity == identity,
          binding.route.connector.contactId == contact, binding.source == source,
          let authorization = research.authorizations[binding.concern.uuidString],
          authorization.id == binding.authorization, authorization.pairedDesktop == binding.route,
          let current = currentLocalCareResearchJob(authorization, id: job, now: now),
          current.state == .dispatched, current.revision == binding.revision, current.trigger == binding.trigger
    else { return nil }
    if authorization.sharesQuestionSnapshot == true {
      guard let thread = archive.localCareDiscussions?[binding.concern.uuidString], thread.turns.last?.id == job,
            let expected = thread.turns.last?.questionSnapshotVersion,
            let concern = archive.localCare?.current[authorization.metric.rawValue],
            (try? localCareQuestionPage(concern, archive: archive, after: nil).ledgerVersion) == expected else { return nil }
    }
    return binding
  }

  func pendingLocalCareDesktopCancellations() throws -> [GalaxySSIHealthDesktopResearch.Cancellation] {
    let pending = try load().localCareResearch?.desktopTransport?.pendingCancellation ?? [:]
    return pending.values.sorted { ($0.createdAtMillis, $0.binding.owner) < ($1.createdAtMillis, $1.binding.owner) }
  }

  func markLocalCareDesktopCancellationQueued(_ item: GalaxySSIHealthDesktopResearch.Cancellation) throws {
    var archive = try load()
    guard var research = archive.localCareResearch, var transport = research.desktopTransport else { throw Failure.stale }
    try transport.handedOff(item)
    research.desktopTransport = transport
    archive.localCareResearch = research
    try persist(archive)
  }

  private func scopedLocalCareResearchPlans(_ turns: [GalaxySSIHealthCareDiscussion.Turn],
      authorization: GalaxySSIHealthCareResearch.Authorization, archive: Archive) -> [GalaxySSIHealthCareResearchHandoff.PlanContext] {
    let questionRevision = archive.localCare?.current[authorization.metric.rawValue]?.questionRevision
    return turns.compactMap { turn in
      guard turn.destination == authorization.destination, let id = turn.proposalID,
            turn.feedbackHistoryAllowed != true || authorization.sharesFeedbackHistory == true,
            let plan = archive.localCarePlans?[id.uuidString], plan.concernID == authorization.concern,
            plan.onlinePermission == authorization.onlinePermission, plan.carePermission == authorization.localPermission,
            plan.profileScopeEpoch == authorization.profileScopeEpoch, plan.questionRevision == questionRevision,
            plan.destinationDigest == authorization.destination
      else { return nil }
      return .init(proposal: plan, includeDescriptions: turn.historyIncluded != true)
    }
  }

  private func scopedLocalCareResearchActions(_ concern: GalaxySSIHealthCare.Concern,
      plans: [GalaxySSIHealthCareResearchHandoff.PlanContext],
      includesFeedback: Bool) -> [GalaxySSIHealthCarePlan.AdoptedAction] {
    let selected = Dictionary(plans.filter { $0.proposal.state == .accepted }
      .map { ($0.proposal.id, $0.proposal.selected) }, uniquingKeysWith: { first, _ in first })
    return (concern.adoptedActions ?? []).compactMap { action in
      guard action.instruction == nil, action.action.kind != .clinicalInstruction,
            selected[action.proposalID]?.contains(action.action.id) == true else { return nil }
      var scoped = action
      if !includesFeedback || scoped.feedback?.isInScope(concern) == false { scoped.feedback = nil }
      return scoped
    }
  }

  private func localCareModelFeedback(_ concern: GalaxySSIHealthCare.Concern,
      thread: GalaxySSIHealthCareDiscussion.Thread, destination: String, archive: Archive,
      includesHistory: Bool = false) -> [AgentMcpJSONValue]? {
    let proposals = Set(thread.turns.filter { $0.destination == destination &&
      ($0.feedbackHistoryAllowed != true || includesHistory) }.compactMap(\.proposalID))
    let currentBasis = try? GalaxySSIHealthCare.inputDigest(concern.assessment)
    let latest = (concern.adoptedActions ?? []).compactMap { action -> (GalaxySSIHealthCarePlan.AdoptedAction,
        GalaxySSIHealthCareFollowUp.Feedback, Bool)? in
      guard action.instruction == nil, action.action.kind != .clinicalInstruction,
            let feedback = action.feedback, feedback.isInScope(concern), proposals.contains(action.proposalID),
            let plan = archive.localCarePlans?[action.proposalID.uuidString], plan.state == .accepted,
            plan.selected.contains(action.action.id), plan.concernID == concern.id, plan.destinationDigest == destination,
            plan.onlinePermission == archive.healthOnlinePermission, archive.matchesLocalCarePermission(plan.carePermission),
            plan.profileScope == concern.profileScope, plan.profileScopeEpoch == concern.profileScopeEpoch,
            plan.questionRevision == concern.questionRevision, plan.assessmentDigest == feedback.planBasis
      else { return nil }
      return (action, feedback, currentBasis == feedback.planBasis && concern.context == plan.sourceContext)
    }.sorted {
      ($0.1.recordedAt, $0.1.id.uuidString) > ($1.1.recordedAt, $1.1.id.uuidString)
    }
    guard !latest.isEmpty else { return nil }
    let date = ISO8601DateFormatter()
    return latest.prefix(6).map { action, feedback, basisCurrent in
      .object(["action_id": .string(AgentModelLoopRecoveryIdentity.sha256(["discussion": thread.id.uuidString, "action": action.id])),
        "action_title": .string(action.action.description), "kind": .string(feedback.kind.rawValue),
        "note": .string(feedback.note), "recorded_at": .string(date.string(from: feedback.recordedAt)),
        "self_reported": .bool(true), "health_improvement_verified": .bool(false),
        "plan_basis_current": .bool(basisCurrent), "history_included": .bool(false)])
    }
  }

  private func scopedClinicalFeedback(_ concern: GalaxySSIHealthCare.Concern,
      authorization: GalaxySSIHealthCareResearch.Authorization, archive: Archive) -> [String: UUID] {
    guard authorization.sharesFeedbackHistory == true, authorization.pairedDesktop == nil else { return [:] }
    var latest: [String: UUID] = [:]
    for action in concern.adoptedActions ?? [] {
      guard let instruction = action.instruction, let feedback = action.feedback,
            action.action.kind == .clinicalInstruction, feedback.isInScope(concern),
            instruction.profileEpoch == concern.profileScopeEpoch,
            archive.matchesLocalCarePermission(instruction.permission), instruction.assessment == feedback.planBasis
      else { continue }
      latest[action.id] = feedback.id
    }
    return latest
  }

  private func makeLocalCareResearchHandoff(_ job: GalaxySSIHealthCareResearch.Job, concern: GalaxySSIHealthCare.Concern,
      archive: Archive) throws -> GalaxySSIHealthCareResearchHandoff.Handoff {
    typealias Handoff = GalaxySSIHealthCareResearchHandoff
    let key = concern.id.uuidString
    guard let ledger = archive.localCareResearch, let authorization = ledger.authorizations[key],
          let thread = archive.localCareDiscussions?[key], thread.id == authorization.thread else { throw Failure.stale }
    let measurements = archive.current.filter { $0.metric == concern.metric && $0.isValid && $0.measuredAt <= job.createdAt }
    let turns = thread.turns.filter { $0.destination == authorization.destination && $0.id != job.id }
    let plans = scopedLocalCareResearchPlans(turns, authorization: authorization, archive: archive)
    let actions = scopedLocalCareResearchActions(concern, plans: plans,
      includesFeedback: authorization.sharesActionFeedback == true || authorization.sharesFeedbackHistory == true)
    let basis = try Handoff.Basis(concern, history: GalaxySSIHealthCareSeries.version(measurements),
      observedAt: job.createdAt, actions: actions,
      clinicalFeedback: scopedClinicalFeedback(concern, authorization: authorization, archive: archive))
    let plan = plans.last(where: { context in
      let proposal = context.proposal
      return proposal.state == .accepted && proposal.selected.contains { basis.due.contains("\(proposal.id.uuidString):\($0)") }
    }) ?? plans.last(where: { $0.proposal.state != .dismissed })
    let checkpoint = ledger.checkpoints?[key]
    var sources: [GalaxySSIHealthCareEvidence.Receipt] = []
    for turn in turns.reversed() where (turn.answer != nil || turn.proposalID != nil) &&
        (turn.automaticResearchCompleted == true || checkpoint?.turn == turn.id) {
      for receipt in archive.localCareEvidence?[turn.id.uuidString] ?? [] {
        if Handoff.reusable(receipt, turn: turn.id, owner: owner, authorization: authorization, job: job) {
          sources.append(receipt)
        }
        if sources.count == 8 { break }
      }
      if sources.count == 8 { break }
    }
    return Handoff.make(job: job, authorization: authorization, basis: basis, prior: checkpoint,
      hasEarlierResult: turns.contains { $0.answer != nil || $0.proposalID != nil }, plan: plan,
      recordedPlan: plans.last?.proposal.state, actionCount: actions.count, historicalSources: sources,
      essentialContextMissing: concern.assessment.signals.contains(.glucoseContext),
      priorityWarning: concern.bloodPressureWarning != nil)
  }

  private func validateLocalCareResearch(_ approval: GalaxySSIHealthCareDiscussion.Approval, archive: Archive,
      concern: GalaxySSIHealthCare.Concern, state: GalaxySSIHealthCareResearch.State, now: Date) throws {
    let key = approval.concernID.uuidString
    guard let binding = approval.research, let handoff = approval.researchHandoff,
          approval.proposesPlan == handoff.plansOnly, approval.history == nil,
          !approval.allowsStandingFeedbackPages,
          let authorization = archive.localCareResearch?.authorizations[key], authorization.id == binding.authorization,
          (authorization.sharesQuestionSnapshot == true) == (approval.questions != nil),
          (authorization.sharesActionFeedback == true) == approval.includesActionFeedback,
          (authorization.sharesFeedbackHistory == true) == approval.feedbackHistoryAllowed,
          !approval.feedbackHistoryAllowed || approval.model != nil,
          (approval.questionCursor == nil || (authorization.sharesQuestionPages == true && approval.model != nil)),
          authorization.handoffVersion == 1,
          authorization.thread == approval.threadID, authorization.destination == approval.destinationDigest,
          authorization.model == approval.modelID, authorization.endpoint == approval.endpoint,
          authorization.pairedDesktop == approval.pairedDesktop,
          authorization.localPermission == approval.carePermission, authorization.onlinePermission == approval.onlinePermission,
          authorization.profileScopeEpoch == approval.profileScopeEpoch,
          let job = archive.localCareResearch?.jobs[key], job.id == approval.id, job.trigger == binding.trigger,
          (job.owner == GalaxySSIHealthCareResearch.process ||
            (state == .dispatched && archive.localCareResearch?.desktopTransport?.active[job.id.uuidString] != nil)),
          job.state == state, job.revision == concern.revision,
          try job.trigger == localCareResearchTrigger(concern, archive: archive, now: now),
          try handoff == makeLocalCareResearchHandoff(job, concern: concern, archive: archive)
    else { throw Failure.stale }
  }

  func validateLocalCareDiscussionApproval(_ approval: GalaxySSIHealthCareDiscussion.Approval) throws {
    let archive = try load()
    let now = Date()
    let thread = try checkedDiscussion(approval, archive: archive, now: now)
    guard thread.turns.last?.id == approval.priorTurnID else { throw Failure.stale }
    try validateLocalCareDiscussionHistory(approval, now: now)
    if approval.research != nil {
      let concern = try currentDiscussionConcern(id: approval.concernID, metric: approval.metric, archive: archive, now: now)
      try validateLocalCareResearch(approval, archive: archive, concern: concern, state: .preparing, now: now)
    }
  }

  func beginLocalCareDiscussionTurn(_ approval: GalaxySSIHealthCareDiscussion.Approval, now: Date = Date()) throws {
    guard !approval.allowsAnswerDraft || !approval.feedbackHistoryAllowed else { throw Failure.permission }
    var archive = try load()
    var thread = try checkedDiscussion(approval, archive: archive, now: now)
    guard thread.turns.last?.id == approval.priorTurnID,
          !thread.turns.contains(where: { $0.id == approval.id }),
          thread.turns.count < GalaxySSIHealthCareDiscussion.maximumTurns,
          let concern = archive.localCare?.current[approval.metric.rawValue],
          approval.computedDestinationDigest == approval.destinationDigest,
          try GalaxySSIHealthCareDiscussion.payload(concern: concern, question: approval.question, thread: thread,
            destination: approval.destinationDigest, savedProfile: localCareProfilePayload(concern),
            actionFeedback: approval.includesActionFeedback ? localCareModelFeedback(concern, thread: thread,
              destination: approval.destinationDigest, archive: archive, includesHistory: approval.feedbackHistoryAllowed) : nil) == approval.payload
    else { throw Failure.stale }
    if approval.research != nil {
      try validateLocalCareResearch(approval, archive: archive, concern: concern, state: .preparing, now: now)
      let sources = archive.localCareResearch?.authorizations[approval.concernID.uuidString]?.sources
      let allowed: Set<URL>? = approval.proposesPlan ? sources.map { Set($0.map(\.url)) } : []
      guard allowed == Set(approval.evidence.map(\.url)) else { throw Failure.stale }
    }
    if approval.proposesPlan {
      let evidence = approval.evidence
      guard (1...3).contains(evidence.count), Set(evidence.map(\.id)).count == evidence.count,
            Set(evidence.map(\.url)).count == evidence.count,
            evidence.allSatisfy({ $0.valid(for: approval, now: now) }) else { throw Failure.permission }
      var saved = archive.localCareEvidence ?? [:]
      saved[approval.id.uuidString] = evidence
      archive.localCareEvidence = saved
    } else if !approval.evidence.isEmpty { throw Failure.permission }
    try validateLocalCareDiscussionHistory(approval, now: now)
    thread.turns.append(.init(id: approval.id, question: approval.question, destination: approval.destinationDigest,
      measurement: concern.assessment.record,
      planRequested: approval.proposesPlan ? true : nil, historyIncluded: approval.history == nil ? nil : true,
      questionsRequested: approval.asksQuestions ? true : nil, questionContextIncluded: approval.questions == nil ? nil : true,
      questionSnapshotVersion: approval.questions?.ledgerVersion,
      answerDraftSourceDigest: approval.allowsAnswerDraft ? GalaxySSIHealthCareAnswerDraft.digest(approval.question) : nil,
      actionFeedbackContextIncluded: approval.actionFeedbackContextIncluded || approval.feedbackCursor != nil ? true : nil,
      feedbackHistoryAllowed: approval.feedbackCursor == nil ? nil : true))
    archive.localCareDiscussions?[approval.concernID.uuidString] = thread
    if let job = approval.research {
      try archive.localCareResearch?.transition(job, concern: approval.concernID, to: .dispatched,
        process: GalaxySSIHealthCareResearch.process)
    }
    try persist(archive)
  }

  func validateLocalCareDiscussionTurn(_ approval: GalaxySSIHealthCareDiscussion.Approval, now: Date = Date()) throws {
    let archive = try load()
    let thread = try checkedDiscussion(approval, archive: archive, now: now)
    if approval.research != nil {
      let concern = try currentDiscussionConcern(id: approval.concernID, metric: approval.metric, archive: archive, now: now)
      try validateLocalCareResearch(approval, archive: archive, concern: concern, state: .dispatched, now: now)
    }
    guard thread.turns.last?.id == approval.id, thread.turns.last?.answer == nil,
          thread.turns.last?.proposalID == nil,
          thread.turns.last?.questionsRetained != true,
          thread.turns.last?.answerDraftStaged != true,
          (thread.turns.last?.answerDraftSourceDigest != nil) == approval.allowsAnswerDraft,
          thread.turns.last?.questionSnapshotVersion == approval.questions?.ledgerVersion,
          (thread.turns.last?.questionsRequested == true) == approval.asksQuestions,
          (thread.turns.last?.planRequested == true) == approval.proposesPlan,
          (thread.turns.last?.feedbackHistoryAllowed == true) == (approval.feedbackCursor != nil),
          (thread.turns.last?.historyIncluded == true) == (approval.history != nil) else { throw Failure.stale }
    try validateLocalCareDiscussionHistory(approval, now: now)
  }

  private func validateLocalCareDiscussionHistory(_ approval: GalaxySSIHealthCareDiscussion.Approval, now: Date) throws {
    guard let history = approval.history else { return }
    _ = try localCareMeasurementPage(id: approval.concernID, metric: approval.metric, expected: history.binding, now: now)
  }

  func readLocalCareDiscussionHistory(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      after cursor: GalaxySSIHealthCareSeries.Cursor, now: Date = Date()) throws -> GalaxySSIHealthCareSeries.Page {
    guard let history = approval.history else { throw Failure.permission }
    try validateLocalCareDiscussionTurn(approval, now: now)
    return try localCareMeasurementPage(id: approval.concernID, metric: approval.metric,
      expected: history.binding, after: cursor, now: now)
  }

  func readLocalCareDiscussionFeedback(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      cursor: GalaxySSIHealthCareFeedbackTool.Cursor, remaining: Int, now: Date = Date())
      throws -> (payload: AgentMcpJSONObject, cursor: GalaxySSIHealthCareFeedbackTool.Cursor?) {
    guard let grant = approval.feedbackCursor, !approval.asksQuestions,
          cursor.turn == grant.turn, cursor.revision == grant.revision,
          cursor.before.map({ $0 > 0 && $0 <= grant.revision }) ?? true else { throw Failure.permission }
    try validateLocalCareDiscussionTurn(approval, now: now)
    let archive = try load()
    let concern = try currentDiscussionConcern(id: approval.concernID, metric: approval.metric, archive: archive, now: now)
    guard concern.revision == grant.revision else { throw Failure.stale }
    let page = try localCareFeedbackPage(concernID: concern.id, metric: concern.metric, before: cursor.before ?? Int.max)
    let currentBasis = try GalaxySSIHealthCare.inputDigest(concern.assessment)
    let actions = Dictionary((concern.adoptedActions ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let date = ISO8601DateFormatter()
    var checkedInstructions: [String: Bool] = [:]
    let rows = try page.items.map { receipt -> (Int, AgentMcpJSONObject) in
      guard receipt.concernID == concern.id, receipt.revision <= concern.revision else { throw Failure.stale }
      let revision = AgentMcpJSONValue.int(Int64(receipt.revision))
      let action = actions[receipt.actionID]
      let planID = receipt.actionID.split(separator: ":", maxSplits: 1).first.map { String($0) } ?? ""
      let redacted: AgentMcpJSONObject = ["revision": revision, "redacted": .bool(true),
        "reason": .string("outside_current_sharing_scope")]
      guard receipt.feedback.isInScope(concern) else { return (receipt.revision, redacted) }
      let current: Bool
      let instruction = action?.instruction
      if let action, let instruction {
        guard action.action.kind == .clinicalInstruction, instruction.profileEpoch == concern.profileScopeEpoch,
              archive.matchesLocalCarePermission(instruction.permission),
              instruction.assessment == receipt.feedback.planBasis else { return (receipt.revision, redacted) }
        if let checked = checkedInstructions[action.id] {
          current = checked
        } else {
          current = instructionActionIsCurrent(action, concern: concern, archive: archive, now: now)
          checkedInstructions[action.id] = current
        }
      } else {
        guard action?.action.kind != .clinicalInstruction, let plan = archive.localCarePlans?[planID],
              plan.concernID == concern.id, plan.destinationDigest == approval.destinationDigest,
              plan.onlinePermission == approval.onlinePermission, archive.matchesLocalCarePermission(plan.carePermission),
              plan.profileScope == concern.profileScope, plan.profileScopeEpoch == concern.profileScopeEpoch
        else { return (receipt.revision, redacted) }
        current = plan.state == .accepted && plan.questionRevision == concern.questionRevision &&
          plan.sourceContext == concern.context && currentBasis == receipt.feedback.planBasis
      }
      var row: AgentMcpJSONObject = ["revision": revision,
        "action_id": .string(AgentModelLoopRecoveryIdentity.sha256(["discussion": approval.threadID.uuidString, "action": receipt.actionID])),
        "action_title": .string(receipt.actionTitle), "action_in_current_plan": .bool(action != nil && instruction == nil),
        "current_action_state": action.map { .string($0.outcome == nil ? "confirmed" : "recorded") } ?? .null,
        "kind": .string(receipt.feedback.kind.rawValue), "note": .string(receipt.feedback.note),
        "recorded_at": .string(date.string(from: receipt.feedback.recordedAt)), "self_reported": .bool(true),
        "health_improvement_verified": .bool(false), "plan_basis_current": .bool(current),
        "action_requires_review": .bool(action == nil || !current)]
      if let instruction {
        row["instruction_invalidated"] = .bool(instruction.invalidated)
        row["instruction_source_verified"] = .bool(false)
      }
      return (receipt.revision, row)
    }
    try validateLocalCareDiscussionTurn(approval, now: now)
    return cursor.output(rows: rows, next: page.next, remaining: remaining)
  }

  func finishLocalCareDiscussionTurn(_ approval: GalaxySSIHealthCareDiscussion.Approval, answer: String,
                                     now: Date = Date()) throws {
    guard !approval.proposesPlan, !approval.asksQuestions, !answer.isBlank, answer.utf8.count <= 6_144 else { throw Failure.invalid }
    var archive = try load()
    var thread = try checkedDiscussion(approval, archive: archive, now: now)
    guard let index = thread.turns.indices.last, thread.turns[index].id == approval.id,
          thread.turns[index].answer == nil, thread.turns[index].proposalID == nil,
          thread.turns[index].questionsRequested != true,
          thread.turns[index].planRequested != true else { throw Failure.stale }
    if approval.research != nil {
      let concern = try currentDiscussionConcern(id: approval.concernID, metric: approval.metric, archive: archive, now: now)
      try completeLocalCareResearch(approval, concern: concern, archive: &archive, now: now)
      thread.turns[index].automaticResearchCompleted = true
    }
    thread.turns[index].answer = answer
    archive.localCareDiscussions?[approval.concernID.uuidString] = thread
    try persist(archive)
  }

  func saveLocalCarePlan(_ approval: GalaxySSIHealthCareDiscussion.Approval, arguments: AgentMcpJSONObject,
                         now: Date = Date()) throws {
    guard approval.proposesPlan else { throw Failure.permission }
    var archive = try load()
    var thread = try checkedDiscussion(approval, archive: archive, now: now)
    var plans = archive.localCarePlans ?? [:]
    let key = approval.id.uuidString
    let digest = AgentMcpJSONCodec.sha256(arguments)
    if let prior = plans[key] {
      guard prior.requestDigest == digest, prior.concernID == approval.concernID,
            thread.turns.contains(where: { $0.id == approval.id && $0.proposalID == prior.id }) else { throw Failure.stale }
      return
    }
    guard let index = thread.turns.indices.last, thread.turns[index].id == approval.id,
          thread.turns[index].answer == nil, thread.turns[index].proposalID == nil, thread.turns[index].planRequested == true,
          let concern = archive.localCare?.current[approval.metric.rawValue] else { throw Failure.stale }
    guard let evidence = archive.localCareEvidence?[key], !evidence.isEmpty, evidence == approval.evidence,
          evidence.allSatisfy({ $0.valid(for: approval, now: now) }) else { throw Failure.permission }
    let approvedHistory = try approval.history.map {
      try localCareMeasurementPage(id: approval.concernID, metric: approval.metric, expected: $0.binding, now: now)
    }
    let draft = try GalaxySSIHealthCarePlan.parse(arguments, evidence: evidence, now: now, approvedHistory: approvedHistory)
    if approval.research != nil {
      try completeLocalCareResearch(approval, concern: concern, archive: &archive, now: now)
      thread.turns[index].automaticResearchCompleted = true
    }
    plans[key] = try .init(id: approval.id, concernID: approval.concernID, metric: approval.metric,
      concernRevision: approval.concernRevision, assessmentDigest: GalaxySSIHealthCare.inputDigest(concern.assessment),
      sourceContext: concern.context,
      profileScope: approval.profileScope,
      profileScopeEpoch: approval.profileScopeEpoch,
      questionRevision: concern.questionRevision,
      carePermission: approval.carePermission, onlinePermission: approval.onlinePermission, contactID: approval.destinationID,
      modelID: approval.modelID, endpoint: approval.endpoint, destinationDigest: approval.destinationDigest,
      createdAt: now, requestDigest: digest, draft: draft, pairedDesktop: approval.pairedDesktop)
    thread.turns[index].proposalID = approval.id
    archive.localCarePlans = plans
    archive.localCareDiscussions?[approval.concernID.uuidString] = thread
    try persist(archive)
  }

  private func completeLocalCareResearch(_ approval: GalaxySSIHealthCareDiscussion.Approval,
      concern: GalaxySSIHealthCare.Concern, archive: inout Archive, now: Date) throws {
    try validateLocalCareResearch(approval, archive: archive, concern: concern, state: .dispatched, now: now)
    let key = approval.concernID.uuidString
    guard var ledger = archive.localCareResearch, let job = ledger.jobs[key],
          let authorization = ledger.authorizations[key], let handoff = approval.researchHandoff else { throw Failure.stale }
    try ledger.transition(job, concern: approval.concernID, to: .completed, process: GalaxySSIHealthCareResearch.process)
    if let binding = ledger.desktopTransport?.active[job.id.uuidString] {
      try ledger.desktopTransport?.finish(binding)
    }
    var checkpoints = ledger.checkpoints ?? [:]
    checkpoints[key] = .init(authorization: authorization, turn: job.id, revision: job.revision,
      startedAt: job.createdAt, basis: handoff.basis)
    ledger.checkpoints = checkpoints
    archive.localCareResearch = ledger
  }

  func resolveLocalCarePlan(_ proposal: GalaxySSIHealthCarePlan.Proposal, selected: Set<Int>?,
                            currentDestination: String? = nil,
                            acceptMaintenance: Bool = false,
                            now: Date = Date()) throws {
    guard selected != nil || !acceptMaintenance else { throw Failure.invalid }
    var archive = try load()
    guard archive.localCareAllowed == true,
          var ledger = archive.localCare, var current = ledger.current[proposal.metric.rawValue],
          current.id == proposal.concernID,
          var saved = archive.localCarePlans?[proposal.id.uuidString], saved == proposal, saved.state == .pending,
          now >= saved.createdAt else { throw Failure.stale }
    if let selected {
      let checked = try currentDiscussionConcern(id: saved.concernID, metric: saved.metric, archive: archive, now: now)
      guard currentDestination == saved.destinationDigest,
            checked.revision == saved.concernRevision, checked.revision < Int.max,
            checked.profileScopeEpoch == saved.profileScopeEpoch, checked.profileScope == saved.profileScope,
            checked.questionRevision == saved.questionRevision,
            localCareProfileIsCurrent(saved.profileScope),
            try GalaxySSIHealthCare.inputDigest(checked.assessment) == saved.assessmentDigest,
            archive.healthOnlinePermission == saved.onlinePermission,
            archive.matchesLocalCarePermission(saved.carePermission),
            Self.localCarePlanEvidenceMatches(saved, archive: archive, owner: owner),
            !selected.isEmpty, selected.isSubset(of: Set(saved.draft.actions.map(\.id))) else { throw Failure.stale }
      let actions = saved.draft.actions.filter { selected.contains($0.id) }
      guard actions.allSatisfy({ saved.draft.sources.indices.contains($0.sourceIndex) &&
        GalaxySSIHealthCareApplicability.canAdopt($0, concern: checked) &&
        $0.dueUntil.map { $0 >= now } != false }) else { throw Failure.stale }
      var adopted = current.adoptedActions ?? []
      guard !adopted.contains(where: { $0.proposalID == saved.id }) else { throw Failure.stale }
      let review: GalaxySSIHealthCareMaintenance.Review?
      if acceptMaintenance {
        guard let draft = saved.draft.maintenance, selected.contains(draft.recheckIndex),
              let recheck = actions.first(where: { $0.id == draft.recheckIndex }), let due = recheck.dueFrom
        else { throw Failure.stale }
        let evaluation = try localCareMaintenanceEvaluation(saved, concern: checked, archive: archive, now: now)
        guard evaluation.gaps.isEmpty else { throw Failure.stale }
        review = try .init(proposalID: saved.id, actionID: "\(saved.id.uuidString):\(draft.recheckIndex)",
          historyVersion: draft.historyVersion, contextBasis: GalaxySSIHealthCareTarget.basis(checked),
          targetRevision: checked.targetRevision, carePermission: saved.carePermission, confirmedAt: now,
          due: due, basis: draft.basis, rationale: draft.rationale, source: saved.draft.sources[draft.sourceIndex],
          samples: evaluation.samples)
      } else { review = nil }
      adopted += actions.map { .init(proposalID: saved.id, action: $0, source: saved.draft.sources[$0.sourceIndex],
        confirmedAt: now) }
      current.adoptedActions = adopted
      if current.stage == .maintenance { current.reviewNote = nil }
      current.stage = actions.contains(where: { $0.kind == .recheck }) ? .waitingResults : .reviewPlan
      current.maintenanceReview = review
      current.maintenanceHistoryVersion = review?.historyVersion
      if let review {
        current.stage = .maintenance
        current.reviewNote = review.rationale
        saved.maintenanceAccepted = true
      }
      current.revision += 1
      current.updatedAt = max(current.updatedAt, now)
      ledger.publish(current)
      archive.localCare = ledger
      saved.selected = selected
      saved.state = .accepted
    } else { saved.state = .dismissed }
    saved.resolvedAt = now
    archive.localCarePlans?[saved.id.uuidString] = saved
    try persist(archive)
  }

  func validateLocalCarePlanReview(_ proposal: GalaxySSIHealthCarePlan.Proposal, now: Date = Date()) throws
    -> GalaxySSIHealthCare.Concern {
    let archive = try load()
    let concern = try currentDiscussionConcern(id: proposal.concernID, metric: proposal.metric, archive: archive, now: now)
    guard archive.localCarePlans?[proposal.id.uuidString] == proposal, proposal.state == .pending,
          concern.revision == proposal.concernRevision,
          concern.profileScopeEpoch == proposal.profileScopeEpoch, concern.profileScope == proposal.profileScope,
          concern.questionRevision == proposal.questionRevision,
          localCareProfileIsCurrent(proposal.profileScope),
          try GalaxySSIHealthCare.inputDigest(concern.assessment) == proposal.assessmentDigest,
          archive.healthOnlinePermission == proposal.onlinePermission,
          archive.matchesLocalCarePermission(proposal.carePermission),
          Self.localCarePlanEvidenceMatches(proposal, archive: archive, owner: owner)
    else { throw Failure.stale }
    return concern
  }

  func localCareMaintenancePreview(_ proposal: GalaxySSIHealthCarePlan.Proposal, now: Date = Date())
      throws -> GalaxySSIHealthCareMaintenance.Evaluation {
    let concern = try validateLocalCarePlanReview(proposal, now: now)
    return try localCareMaintenanceEvaluation(proposal, concern: concern, archive: load(), now: now)
  }

  private func localCareMaintenanceEvaluation(_ proposal: GalaxySSIHealthCarePlan.Proposal,
      concern: GalaxySSIHealthCare.Concern, archive: Archive, now: Date) throws -> GalaxySSIHealthCareMaintenance.Evaluation {
    guard let draft = proposal.draft.maintenance, archive.matchesLocalCarePermission(proposal.carePermission)
    else { throw Failure.stale }
    let readings = archive.current.filter { $0.metric == concern.metric && $0.isValid && $0.measuredAt <= now }
    let version = GalaxySSIHealthCareSeries.version(readings)
    let binding = GalaxySSIHealthCareSeries.Binding(concern: concern.id, revision: concern.revision,
      historyVersion: version, permission: proposal.carePermission)
    let page = try GalaxySSIHealthCareSeries.page(readings, binding: binding, after: nil)
    return GalaxySSIHealthCareMaintenance.evaluate(proposal.draft, draft: draft, concern: concern,
      readings: readings, page: page, now: now)
  }

  private static func localCarePlanEvidenceMatches(_ proposal: GalaxySSIHealthCarePlan.Proposal, archive: Archive,
                                                   owner: String) -> Bool {
    guard let receipts = archive.localCareEvidence?[proposal.id.uuidString], !proposal.draft.sources.isEmpty,
          let thread = archive.localCareDiscussions?[proposal.concernID.uuidString] else { return false }
    return proposal.draft.sources.allSatisfy { source in
      guard let proof = source.provenance, let receipt = receipts.first(where: { $0.id == proof.receiptID })
      else { return false }
      let binding = receipt.binding
      return binding.owner == owner && binding.thread == thread.id && binding.turn == proposal.id &&
        binding.concern == proposal.concernID && binding.revision == proposal.concernRevision &&
        binding.carePermission == proposal.carePermission && binding.onlinePermission == proposal.onlinePermission &&
        binding.destination == proposal.destinationDigest && receipt.observedAt <= proposal.createdAt &&
        receipt.match(url: source.url, quote: proof.quote) == proof
    }
  }

  func scheduleLocalCareFollowUp(concernID: UUID, metric: GalaxySSIHealthMetric, actionID: String,
                                 expectedRevision: Int? = nil, replacing token: UUID?, at requested: Date,
                                 now: Date = Date()) throws {
    guard requested.timeIntervalSinceReferenceDate.isFinite, requested > now else { throw Failure.invalid }
    var archive = try load()
    guard archive.localCareFollowUps?[actionID]?.id == token,
          expectedRevision == nil || archive.localCare?.current[metric.rawValue]?.revision == expectedRevision,
          Self.careFollowUpPreferences(archive) != nil,
          careFollowUpIsCurrent(concernID: concernID, metric: metric, actionID: actionID, archive: archive, now: now)
    else { throw Failure.stale }
    var reminders = archive.localCareFollowUps ?? [:]
    reminders[actionID] = .init(id: UUID(), actionID: actionID, concernID: concernID, metric: metric, requestedAt: requested)
    archive.localCareFollowUps = reminders
    try persist(archive)
  }

  func cancelLocalCareFollowUp(_ reminder: GalaxySSIHealthCareFollowUp.Reminder) throws {
    var archive = try load()
    guard archive.localCareFollowUps?[reminder.actionID]?.id == reminder.id else { throw Failure.stale }
    archive.localCareFollowUps?.removeValue(forKey: reminder.actionID)
    try persist(archive)
  }

  func recordLocalCareOutcome(concernID: UUID, metric: GalaxySSIHealthMetric, action: GalaxySSIHealthCarePlan.AdoptedAction,
                              note: String, now: Date = Date()) throws {
    guard let current = try load().localCare?.current[metric.rawValue], current.id == concernID else { throw Failure.stale }
    _ = try recordLocalCareFeedback(concernID: concernID, metric: metric, action: action,
      expectedRevision: current.revision, kind: .completed, note: note, operation: UUID(), now: now)
  }

  @discardableResult
  func recordLocalCareFeedback(concernID: UUID, metric: GalaxySSIHealthMetric, action: GalaxySSIHealthCarePlan.AdoptedAction,
      expectedRevision: Int, kind: GalaxySSIHealthCareFollowUp.Feedback.Kind, note: String,
      operation: UUID, now: Date = Date()) throws -> GalaxySSIHealthCareFollowUp.FeedbackReceipt {
    let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !note.isEmpty, note.utf8.count <= 2_000, now.timeIntervalSince1970.isFinite,
          now.timeIntervalSince1970 > 0, expectedRevision > 0, expectedRevision < Int.max else {
      throw Failure.invalid
    }
    var archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    guard var ledger = archive.localCare, var current = ledger.current[metric.rawValue], current.id == concernID
    else { throw Failure.stale }
    let key = concernID.uuidString
    if let saved = archive.localCareFeedback?.values.lazy.compactMap({ $0.first(where: { $0.id == operation }) }).first {
      guard saved.concernID == concernID, saved.actionID == action.id, saved.feedback.kind == kind,
            saved.feedback.note == note, expectedRevision == saved.revision - 1 else { throw Failure.stale }
      return saved
    }
    guard current.stage != .closed, current.revision < Int.max,
          expectedRevision == current.revision,
          let index = current.adoptedActions?.firstIndex(of: action), action.outcome == nil else { throw Failure.stale }
    guard careOutcomeIsCurrent(action, concern: current, archive: archive,
      profileCurrent: localCareProfileIsCurrent(current.profileScope), now: now),
      let basis = action.instruction?.assessment ?? archive.localCarePlans?[action.proposalID.uuidString]?.assessmentDigest
    else { throw Failure.stale }
    let feedback = GalaxySSIHealthCareFollowUp.Feedback(id: operation, kind: kind, note: note, recordedAt: now,
      scope: GalaxySSIHealthCareQuestions.scope(current), profileEpoch: current.profileScopeEpoch,
      planBasis: basis)
    current.adoptedActions?[index].feedback = feedback
    if kind == .completed { current.adoptedActions?[index].outcome = .init(note: note, reportedAt: now) }
    if current.stage == .maintenance {
      current.maintenanceReview = nil
      current.maintenanceHistoryVersion = nil
      current.reviewNote = nil
    }
    if current.stage != .paused { current.stage = .reassess }
    current.revision += 1
    current.updatedAt = max(current.updatedAt, now)
    ledger.publish(current)
    archive.localCare = ledger
    let receipt = GalaxySSIHealthCareFollowUp.FeedbackReceipt(concernID: concernID, actionID: action.id,
      actionTitle: action.action.description, revision: current.revision, feedback: feedback)
    var receipts = archive.localCareFeedback ?? [:]
    receipts[key, default: []].append(receipt)
    archive.localCareFeedback = receipts
    if kind == .completed { archive.localCareFollowUps?.removeValue(forKey: action.id) }
    try persist(archive)
    return receipt
  }

  func localCareFeedbackPage(concernID: UUID, metric: GalaxySSIHealthMetric, actionID: String? = nil,
      before revision: Int = Int.max, limit: Int = 30) throws -> GalaxySSIHealthCareFollowUp.FeedbackPage {
    guard (1...30).contains(limit), revision > 0 else { throw Failure.invalid }
    let archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    guard archive.localCare?.current[metric.rawValue]?.id == concernID else { throw Failure.stale }
    let receipts = archive.localCareFeedback?[concernID.uuidString] ?? []
    var lo = 0
    var hi = receipts.count
    while lo < hi {
      let mid = lo + (hi - lo) / 2
      if receipts[mid].revision < revision { lo = mid + 1 } else { hi = mid }
    }
    let rows = Array(receipts[..<lo].reversed().lazy.filter {
      actionID == nil || $0.actionID == actionID
    }.prefix(limit + 1))
    let items = Array(rows.prefix(limit))
    return .init(items: items, next: rows.count > limit ? items.last?.revision : nil)
  }

  func localCareFollowUpDelivery(pending: [String: Date], delivered: Set<String>, permitted: Bool,
      calendar: Calendar, now: Date) throws -> GalaxySSIHealthCareFollowUp.DeliveryPlan {
    let archive = try load()
    let reminders = (archive.localCareFollowUps ?? [:]).values.filter {
      careFollowUpIsCurrent(concernID: $0.concernID, metric: $0.metric, actionID: $0.actionID, archive: archive, now: now)
    }
    return GalaxySSIHealthCareFollowUp.deliveryPlan(reminders: reminders, preferences: Self.careFollowUpPreferences(archive),
      permitted: permitted, pending: pending, delivered: delivered, calendar: calendar, now: now)
  }

  func markLocalCareFollowUpSubmitted(_ delivery: GalaxySSIHealthCareFollowUp.Delivery,
                                      calendar: Calendar, now: Date) throws {
    var archive = try load()
    let expected = delivery.reminder
    guard var reminder = archive.localCareFollowUps?[expected.actionID], reminder.id == expected.id,
          reminder.submittedFor == expected.submittedFor || reminder.submittedFor == delivery.due,
          delivery.due >= reminder.requestedAt.addingTimeInterval(-1),
          let preferences = Self.careFollowUpPreferences(archive),
          preferences.nextAllowed(delivery.due, calendar: calendar) == delivery.due,
          careFollowUpIsCurrent(concernID: reminder.concernID, metric: reminder.metric,
            actionID: reminder.actionID, archive: archive, now: now) else { throw Failure.stale }
    guard reminder.submittedFor != delivery.due else { return }
    reminder.submittedFor = delivery.due
    archive.localCareFollowUps?[reminder.actionID] = reminder
    try persist(archive)
  }

  func localCareFollowUpTarget(token: UUID, now: Date) throws -> GalaxySSIHealthCareFollowUp.Reminder? {
    let archive = try load()
    guard Self.careFollowUpPreferences(archive) != nil,
          let reminder = archive.localCareFollowUps?.values.first(where: { $0.id == token }),
          reminder.submittedFor.map({ $0 <= now.addingTimeInterval(2) }) == true,
          careFollowUpIsCurrent(concernID: reminder.concernID, metric: reminder.metric, actionID: reminder.actionID,
            archive: archive, now: now) else { return nil }
    return reminder
  }

  static func careFollowUpPreferences(_ archive: Archive) -> GalaxySSIHealthReviewDelivery.Preferences? {
    guard archive.reviewReminderState?.enabled == true,
          let preferences = archive.reviewReminderState?.notificationPreferences, preferences.enabled else { return nil }
    return preferences
  }

  func careFollowUpIsCurrent(concernID: UUID, metric: GalaxySSIHealthMetric, actionID: String,
                                    archive: Archive, now: Date = Date(), verifyOriginal: Bool = true) -> Bool {
    guard archive.localCareAllowed == true,
          let concern = archive.localCare?.current[metric.rawValue], concern.id == concernID,
          let adopted = concern.adoptedActions?.first(where: { $0.id == actionID }) else { return false }
    return careActionIsCurrent(adopted, concern: concern, archive: archive,
      context: careAgendaContext(concern, archive: archive, now: now), now: now, verifyOriginal: verifyOriginal)
  }

  private func careAgendaContext(_ concern: GalaxySSIHealthCare.Concern, archive: Archive, now: Date)
      -> GalaxySSIHealthCareAgenda.Context {
    let readings = archive.current.filter { $0.metric == concern.metric && $0.isValid && $0.measuredAt <= now }
    return careAgendaContext(concern, readings: readings)
  }

  private func careAgendaContext(_ concern: GalaxySSIHealthCare.Concern, readings: [GalaxySSIHealthReading])
      -> GalaxySSIHealthCareAgenda.Context {
    return .init(assessmentCurrent: GalaxySSIHealthCare.assess(readings, context: concern.context) == concern.assessment,
      profileCurrent: localCareProfileIsCurrent(concern.profileScope))
  }

  private func careActionIsCurrent(_ adopted: GalaxySSIHealthCarePlan.AdoptedAction,
      concern: GalaxySSIHealthCare.Concern, archive: Archive, context: GalaxySSIHealthCareAgenda.Context,
      now: Date, verifyOriginal: Bool = true) -> Bool {
    guard adopted.outcome == nil, concern.stage != .paused, concern.stage != .closed, concern.assessment.record != nil,
          context.assessmentCurrent, context.profileCurrent else { return false }
    if adopted.action.kind == .clinicalInstruction || adopted.instruction != nil {
      return instructionActionIsCurrent(adopted, concern: concern, archive: archive, now: now,
        verifyOriginal: verifyOriginal)
    }
    guard let plan = archive.localCarePlans?[adopted.proposalID.uuidString], plan.concernID == concern.id,
          plan.state == .accepted, plan.selected.contains(adopted.action.id),
          concern.profileScopeEpoch == plan.profileScopeEpoch, concern.profileScope == plan.profileScope,
          concern.questionRevision == plan.questionRevision,
          archive.healthOnlinePermission == plan.onlinePermission,
          archive.matchesLocalCarePermission(plan.carePermission),
          concern.context == plan.sourceContext,
          (try? GalaxySSIHealthCare.inputDigest(concern.assessment)) == plan.assessmentDigest else { return false }
    return true
  }

  private func careOutcomeIsCurrent(_ action: GalaxySSIHealthCarePlan.AdoptedAction, concern: GalaxySSIHealthCare.Concern,
      archive: Archive, profileCurrent: Bool, now: Date) -> Bool {
    guard profileCurrent, action.outcome == nil, concern.stage != .closed else { return false }
    if action.action.kind == .clinicalInstruction || action.instruction != nil {
      return instructionActionIsCurrent(action, concern: concern, archive: archive, now: now)
    }
    guard let plan = archive.localCarePlans?[action.proposalID.uuidString], plan.concernID == concern.id,
          plan.state == .accepted, plan.selected.contains(action.action.id),
          plan.profileScopeEpoch == concern.profileScopeEpoch, plan.profileScope == concern.profileScope,
          plan.questionRevision == concern.questionRevision else { return false }
    return true
  }

  private func careAgendaContexts(_ archive: Archive, now: Date) -> [String: GalaxySSIHealthCareAgenda.Context] {
    let relevant = (archive.localCare?.current ?? [:]).filter { !($0.value.adoptedActions ?? []).isEmpty }
    guard !relevant.isEmpty else { return [:] }
    let readings = Dictionary(grouping: archive.current.filter { $0.isValid && $0.measuredAt <= now }, by: \.metric)
    return relevant.mapValues { careAgendaContext($0, readings: readings[$0.metric] ?? []) }
  }

  private func careAgendaRow(_ action: GalaxySSIHealthCarePlan.AdoptedAction, concern: GalaxySSIHealthCare.Concern,
      archive: Archive, context: GalaxySSIHealthCareAgenda.Context, now: Date)
      -> (GalaxySSIHealthCareAgenda.Row, GalaxySSIHealthCareFollowUp.Reminder?) {
    typealias Agenda = GalaxySSIHealthCareAgenda
    let current = careActionIsCurrent(action, concern: concern, archive: archive, context: context, now: now)
    let bucket: Agenda.Bucket = action.outcome != nil ? .recorded : (current ? .planned : .review)
    let reminder = archive.localCareFollowUps?[action.id].flatMap {
      current && $0.concernID == concern.id && $0.metric == concern.metric && $0.actionID == action.id ? $0 : nil
    }
    let key = Agenda.Key(bucket: bucket, due: reminder?.requestedAt ?? action.action.dueFrom,
      concern: concern.id, action: action.id)
    let row = Agenda.Row(key: key, metric: concern.metric, revision: concern.revision, reminderID: reminder?.id,
      submittedFor: reminder?.submittedFor, canRecord: careOutcomeIsCurrent(action, concern: concern, archive: archive,
        profileCurrent: context.profileCurrent, now: now))
    return (row, reminder)
  }

  private func makeCareAgenda(_ archive: Archive, context: [String: GalaxySSIHealthCareAgenda.Context], now: Date)
      -> GalaxySSIHealthCareAgenda.Projection {
    let rows = context.flatMap { metric, state -> [GalaxySSIHealthCareAgenda.Row] in
      guard let concern = archive.localCare?.current[metric] else { return [] }
      return (concern.adoptedActions ?? []).map { careAgendaRow($0, concern: concern, archive: archive, context: state, now: now).0 }
    }
    return .init(carePermission: archive.localCarePermission, onlinePermission: archive.healthOnlinePermission,
      context: context, rows: rows)
  }

  func localCareAgendaPage(filter: GalaxySSIHealthCareAgenda.Filter?, scope: GalaxySSIHealthCareAgenda.Scope? = nil,
      after: GalaxySSIHealthCareAgenda.Cursor? = nil, limit: Int = GalaxySSIHealthCareAgenda.pageSize,
      calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) throws -> GalaxySSIHealthCareAgenda.Page {
    typealias Agenda = GalaxySSIHealthCareAgenda
    let archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    if let scope, archive.localCare?.current[scope.metric.rawValue]?.id != scope.concern { throw Failure.stale }
    guard let dayEnd = calendar.dateInterval(of: .day, for: now)?.end else { throw Failure.invalid }
    let context = careAgendaContexts(archive, now: now)
    let index: Agenda.Projection
    if let data = archive.localCareAgenda, let saved = try? JSONDecoder().decode(Agenda.Projection.self, from: data),
       saved.version == Agenda.version, saved.context == context,
       saved.carePermission == archive.localCarePermission, saved.onlinePermission == archive.healthOnlinePermission {
      index = saved
    } else {
      index = makeCareAgenda(archive, context: context, now: now)
    }
    let rows = try index.page(filter: filter, scope: scope, dayEnd: dayEnd, after: after, limit: limit)
    var actionsByMetric: [String: [String: GalaxySSIHealthCarePlan.AdoptedAction]] = [:]
    let checkedItems = try rows.map { row -> Agenda.Item in
      guard let concern = archive.localCare?.current[row.metric.rawValue], concern.id == row.key.concern,
            let state = context[row.metric.rawValue] else { throw Failure.stale }
      if actionsByMetric[row.metric.rawValue] == nil {
        actionsByMetric[row.metric.rawValue] = Dictionary((concern.adoptedActions ?? []).map { ($0.id, $0) },
          uniquingKeysWith: { first, _ in first })
      }
      guard let action = actionsByMetric[row.metric.rawValue]?[row.key.action] else { throw Failure.stale }
      let (checked, reminder) = careAgendaRow(action, concern: concern, archive: archive, context: state, now: now)
      guard checked == row else { throw Failure.stale }
      return .init(scope: .init(concern: concern.id, metric: concern.metric), revision: concern.revision, action: action, reminder: reminder,
        plannedAt: row.key.due, bucket: row.key.bucket, canRecord: row.canRecord)
    }
    let next = rows.count > limit ? rows.prefix(limit).last.map {
      Agenda.Cursor(generation: index.generation, filter: filter, scope: scope, dayEnd: dayEnd, key: $0.key)
    } : nil
    return .init(items: Array(checkedItems.prefix(limit)), next: next, dayEnd: dayEnd,
      remindersEnabled: Self.careFollowUpPreferences(archive) != nil)
  }
  private func currentDiscussionConcern(id: UUID, metric: GalaxySSIHealthMetric, archive: Archive,
                                        now: Date) throws -> GalaxySSIHealthCare.Concern {
    guard archive.localCareAllowed == true else { throw Failure.permission }
    let readings = archive.current.filter { $0.metric == metric && $0.isValid && $0.measuredAt <= now }
    guard let concern = archive.localCare?.current[metric.rawValue], concern.id == id,
          concern.stage != .paused && concern.stage != .closed, concern.assessment.record != nil,
          GalaxySSIHealthCare.assess(readings, context: concern.context) == concern.assessment else { throw Failure.stale }
    if let saved = concern.comparison {
      let (sample, comparison) = GalaxySSIHealthCareComparison.reconcile(readings, prior: concern)
      guard sample == saved.after, comparison == saved else { throw Failure.stale }
    }
    return concern
  }

  private func checkedDiscussion(_ approval: GalaxySSIHealthCareDiscussion.Approval, archive: Archive, now: Date)
      throws -> GalaxySSIHealthCareDiscussion.Thread {
    let concern = try currentDiscussionConcern(id: approval.concernID, metric: approval.metric, archive: archive, now: now)
    guard owner == approval.owner, approval.isCurrent(at: now), concern.revision == approval.concernRevision,
          archive.healthOnlinePermission == approval.onlinePermission,
          archive.matchesLocalCarePermission(approval.carePermission),
          concern.profileScopeEpoch == approval.profileScopeEpoch, concern.profileScope == approval.profileScope,
          localCareProfileIsCurrent(approval.profileScope),
          let thread = archive.localCareDiscussions?[concern.id.uuidString], thread.id == approval.threadID
    else { throw Failure.permission }
    if let snapshot = approval.questions {
      let current = try localCareQuestionPage(concern, archive: archive, after: nil)
      guard current.basis == snapshot.basis, current.ledgerVersion == snapshot.ledgerVersion,
            current.payload == snapshot.payload else { throw Failure.stale }
    }
    return thread
  }

  func readLocalCareDiscussionQuestions(_ approval: GalaxySSIHealthCareDiscussion.Approval, after cursor: UUID,
      now: Date = Date()) throws -> GalaxySSIHealthCareQuestions.Page {
    guard let original = approval.questions, approval.questionCursor != nil else { throw Failure.permission }
    try validateLocalCareDiscussionTurn(approval, now: now)
    let archive = try load()
    let concern = try currentDiscussionConcern(id: approval.concernID, metric: approval.metric, archive: archive, now: now)
    let page = try localCareQuestionPage(concern, archive: archive, after: cursor)
    guard page.basis == original.basis, page.ledgerVersion == original.ledgerVersion else { throw Failure.stale }
    return page
  }

  func setLocalCareContext(_ concern: GalaxySSIHealthCare.Concern,
                           applicability: GalaxySSIHealthCare.Context.Applicability,
                           answers: GalaxySSIHealthCare.Context.Answers? = nil, now: Date = Date()) throws {
    if let hours = answers?.fastingHours, !(0...72).contains(hours) { throw Failure.invalid }
    if concern.metric != .glucose {
      guard applicability == .unknown,
            answers.map({ $0 == GalaxySSIHealthCare.Context.Answers(collection: $0.collection) }) != false
      else { throw Failure.invalid }
    }
    try updateLocalCare(concern, now: now) { current, archive in
      let readings = archive.current.filter { $0.metric == current.metric && $0.isValid && $0.measuredAt <= now }
      guard let record = current.assessment.record,
            readings.first.map(GalaxySSIHealthCare.Record.init) == record else { throw Failure.stale }
      let previous = current.context.flatMap { $0.record == record ? $0 : nil }
      var context = GalaxySSIHealthCare.Context(record: record, applicability: applicability)
      context.answers = answers == GalaxySSIHealthCare.Context.Answers() ? nil : (answers ?? previous?.answers)
      guard applicability != .applicable || context.answers?.conflictsWithApplicable != true else { throw Failure.invalid }
      context.confirmedAt = context.answers.map { $0 == previous?.answers ? (previous?.confirmedAt ?? now) : now }
      guard let assessment = GalaxySSIHealthCare.assess(readings, context: context) else { throw Failure.stale }
      current.context = context
      current.assessment = assessment
      if current.stage == .maintenance, current.maintenanceReview != nil, context != previous {
        current.stage = .reassess
        current.maintenanceReview = nil
        current.maintenanceHistoryVersion = nil
        current.reviewNote = nil
      } else if current.metric == .glucose, current.stage != .paused, current.stage != .maintenance {
        current.stage = applicability == .unknown ? .verify : .evidence
      }
    }
  }

  func reviewLocalCare(_ concern: GalaxySSIHealthCare.Concern, stage: GalaxySSIHealthCare.Stage,
                       reason: String, now: Date = Date()) throws {
    guard [.paused, .reassess, .closed].contains(stage),
          !reason.isBlank, reason.utf8.count <= 2_048 else { throw Failure.invalid }
    try updateLocalCare(concern, now: now) { current, _ in
      current.maintenanceHistoryVersion = nil
      current.maintenanceReview = nil
      current.stage = stage
      current.reviewNote = reason
    }
  }

  func setLocalCareTarget(_ concern: GalaxySSIHealthCare.Concern, target: GalaxySSIHealthCare.Target) throws {
    guard [target.value, target.source, target.rationale, target.confirmedBy].allSatisfy({
      !$0.isBlank && $0.utf8.count <= 1_024
    }), target.confirmedAt.timeIntervalSinceReferenceDate.isFinite, target.numeric == nil else { throw Failure.invalid }
    try updateLocalCare(concern, now: target.confirmedAt) { current, _ in
      guard current.target != target else { return }
      try Self.advanceLocalCareTargetRevision(&current)
      current.target = target
    }
  }

  func confirmLocalCareNumericTarget(_ concern: GalaxySSIHealthCare.Concern, component: GalaxySSIHealthCareTarget.Component,
      bounds: GalaxySSIHealthCareTarget.Bounds, source: String, rationale: String, confirmedBy: String,
      now: Date = Date()) throws {
    guard now.timeIntervalSinceReferenceDate.isFinite,
          [source, rationale, confirmedBy].allSatisfy({ !$0.isBlank && $0.utf8.count <= 1_024 }),
          GalaxySSIHealthCareTarget.canConfirm(bounds, component: component, concern: concern) else { throw Failure.invalid }
    try updateLocalCare(concern, now: now) { current, _ in
      try Self.advanceLocalCareTargetRevision(&current)
      let unit = current.assessment.unit
      current.target = try .init(value: bounds.description + " " + unit, source: source, rationale: rationale,
        confirmedBy: confirmedBy, confirmedAt: now,
        numeric: .init(component: component, bounds: bounds, unit: unit, basis: GalaxySSIHealthCareTarget.basis(current)))
    }
  }

  func revokeLocalCareTarget(_ concern: GalaxySSIHealthCare.Concern, now: Date = Date()) throws {
    var archive = try load()
    guard archive.localCareAllowed == true, var ledger = archive.localCare,
          var current = ledger.current[concern.metric.rawValue], current == concern,
          current.target != nil, current.revision < Int.max else { throw Failure.stale }
    try Self.advanceLocalCareTargetRevision(&current)
    current.target = nil
    current.revision += 1
    current.updatedAt = max(now, current.updatedAt)
    ledger.publish(current)
    archive.localCare = ledger
    try persist(archive)
  }

  private static func advanceLocalCareTargetRevision(_ concern: inout GalaxySSIHealthCare.Concern) throws {
    let prior = concern.targetRevision ?? 0
    guard (0..<Int.max).contains(prior) else { throw Failure.invalid }
    concern.targetRevision = prior + 1
    if concern.stage == .maintenance, concern.maintenanceReview != nil {
      concern.stage = .reassess
      concern.maintenanceReview = nil
      concern.maintenanceHistoryVersion = nil
      concern.reviewNote = nil
    }
  }

  func localCareTargetComparison(_ concern: GalaxySSIHealthCare.Concern, now: Date = Date())
      -> GalaxySSIHealthCareTarget.Comparison {
    guard let target = concern.target?.numeric,
          let readings = currentLocalCareTargetReadings(concern, now: now) else { return .reviewRequired }
    return GalaxySSIHealthCareTarget.compare(target, concern: concern, reading: readings.first)
  }

  func isCurrentLocalCareTargetReview(_ concern: GalaxySSIHealthCare.Concern) -> Bool {
    currentLocalCareTargetReadings(concern, now: Date()) != nil
  }

  private func currentLocalCareTargetReadings(_ concern: GalaxySSIHealthCare.Concern,
                                              now: Date) -> [GalaxySSIHealthReading]? {
    guard let archive = try? load(), archive.localCareAllowed == true,
          archive.localCare?.current[concern.metric.rawValue] == concern else { return nil }
    let readings = archive.current.filter { $0.metric == concern.metric && $0.isValid && $0.measuredAt <= now }
    return (GalaxySSIHealthCare.assess(readings, context: concern.context) ?? .removed) == concern.assessment ? readings : nil
  }

  func deleteLocalCare(_ concern: GalaxySSIHealthCare.Concern, now: Date = Date()) throws {
    var archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    let key = concern.metric.rawValue
    guard var ledger = archive.localCare, ledger.current[key] == concern else { throw Failure.stale }
    let readings = archive.current.filter { $0.metric == concern.metric && $0.isValid && $0.measuredAt <= now }
    guard (GalaxySSIHealthCare.assess(readings, context: concern.context) ?? .removed) == concern.assessment
    else { throw Failure.stale }
    if concern.measurement != nil || concern.comparison != nil {
      let (measurement, comparison) = GalaxySSIHealthCareComparison.reconcile(readings, prior: concern)
      guard concern.measurement == measurement, concern.comparison == comparison else { throw Failure.stale }
    }
    ledger.deletedInput[key] = try GalaxySSIHealthCare.inputDigest(GalaxySSIHealthCare.assess(readings, context: nil) ?? .removed)
    ledger.current.removeValue(forKey: key)
    ledger.history.removeValue(forKey: concern.id.uuidString)
    archive.localCareQuestions?.removeValue(forKey: concern.id.uuidString)
    archive.localCareAnswerDrafts?.removeValue(forKey: concern.id.uuidString)
    archive.localCareFeedback?.removeValue(forKey: concern.id.uuidString)
    archive.localCareEncounters?.remove(concern: concern.id)
    archive.localCareEncounterDocuments = archive.localCareEncounterDocuments?.filter { $0.value.concern != concern.id }
    archive.localCareInstructions?.remove(concern: concern.id)
    archive.localInstructionProposals = archive.localInstructionProposals?.filter { $0.value.binding.concern != concern.id }
    archive.localVisitJournals?.remove(concern: concern.id)
    archive.localCare = ledger
    try persist(archive)
  }

  private func updateLocalCare(_ concern: GalaxySSIHealthCare.Concern, now: Date,
                               change: (inout GalaxySSIHealthCare.Concern, Archive) throws -> Void) throws {
    var archive = try load()
    guard archive.localCareAllowed == true else { throw Failure.permission }
    guard var ledger = archive.localCare, var current = ledger.current[concern.metric.rawValue], current == concern,
          current.revision < Int.max else { throw Failure.stale }
    let readings = archive.current.filter { $0.metric == concern.metric && $0.isValid && $0.measuredAt <= now }
    guard (GalaxySSIHealthCare.assess(readings, context: current.context) ?? .removed) == current.assessment
    else { throw Failure.stale }
    if current.measurement != nil || current.comparison != nil {
      let (measurement, comparison) = GalaxySSIHealthCareComparison.reconcile(readings, prior: current)
      guard current.measurement == measurement, current.comparison == comparison else { throw Failure.stale }
    }
    try change(&current, archive)
    guard current != concern else { return }
    current.revision += 1
    current.updatedAt = max(now, current.updatedAt)
    ledger.publish(current)
    archive.localCare = ledger
    try persist(archive)
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

  func editPhotoCaptureDraft(expected: UUID, page: UUID?, offset: Int? = nil) throws {
    var archive = try load()
    guard var draft = archive.photoCaptureDraft, draft.version == expected else { throw Failure.stale }
    if let page {
      try draft.edit(page, offset: offset)
      archive.photoCaptureDraft = draft
    } else { archive.photoCaptureDraft = nil }
    try persist(archive)
  }

  func persistPhotoCaptureDraft(_ updated: Archive, expected: UUID?) throws {
    guard try load().photoCaptureDraft?.version == expected else { throw Failure.stale }
    try persist(updated)
  }

  func submitPhotoCaptureDraft(expected: UUID, originals: GalaxySSIHealthOriginalStore) throws {
    guard originals.owner == owner else { throw Failure.invalid }
    try originals.withRestoreLease { lease in
      try originals.reconcileRestores(lease: lease)
      var archive = try load()
      guard let draft = archive.photoCaptureDraft, draft.version == expected, !draft.pages.isEmpty,
            draft.pages.count <= GalaxySSIHealthPhotoDraft.maximumPages else { throw Failure.stale }
      let existing = archive.recognitionJobs ?? []
      guard existing.count + draft.pages.count <= GalaxySSIHealthRecognitionJobs.maximumJobs else { throw Failure.invalid }
      let jobs = try draft.pages.enumerated().map { index, page -> GalaxySSIHealthRecognitionJobs.Job in
        _ = try originals.read(page.original, lease: lease)
        let crop = try originals.readCrop(for: page.original)?.metadata.revision
        return .init(original: page.original,
          captureSource: .init(batchID: draft.id, mode: draft.mode, order: index + 1, cropRevision: crop),
          addedAt: Date(), pageCount: 1)
      }
      archive.photoCaptureDraft = nil
      archive.recognitionJobs = jobs + existing
      try persist(archive)
    }
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
    if filter == nil {
      archive.reportReview?.removeAll { $0.reading.metric == metric }
      pruneReviewActions(&archive)
    }
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
    if filter == nil { NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner) }
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  @discardableResult
  func enqueueRecognition(original: GalaxySSIHealthOriginalStore.Original, pageCount: Int,
                          requiresPDFPassword: Bool = false) throws -> GalaxySSIHealthRecognitionJobs.Job {
    guard (1...GalaxySSIHealthRecognitionJobs.maximumPages).contains(pageCount),
          original.kind == .pdf || (pageCount == 1 && !requiresPDFPassword),
          GalaxySSIHealthRecognitionJobs.validDigest(original.sha256) else { throw Failure.invalid }
    var archive = try load()
    var jobs = archive.recognitionJobs ?? []
    if let existing = jobs.first(where: { $0.original.id == original.id && $0.original.sha256 == original.sha256 }) {
      guard existing.pageCount == pageCount, (existing.requiresPDFPassword == true) == requiresPDFPassword
      else { throw Failure.stale }
      return existing
    }
    guard jobs.count < GalaxySSIHealthRecognitionJobs.maximumJobs else { throw Failure.invalid }
    let job = GalaxySSIHealthRecognitionJobs.Job(original: original, addedAt: Date(), pageCount: pageCount,
      requiresPDFPassword: requiresPDFPassword ? true : nil)
    jobs.insert(job, at: 0)
    archive.recognitionJobs = jobs
    try persist(archive)
    return job
  }

  func reconcileAbandonedRecognitionJobs(process: UUID = GalaxySSIHealthRecognitionJobs.processID) throws {
    var archive = try load()
    guard var jobs = archive.recognitionJobs else { return }
    let abandoned = jobs.indices.filter {
      let job = jobs[$0]
      return job.phase == .running &&
        (job.runProcess != process || job.run.map(Self.activeRecognitionRuns.contains) != true)
    }
    guard !abandoned.isEmpty else { return }
    let abandonedRuns = abandoned.compactMap { jobs[$0].run }
    for index in abandoned {
      jobs[index].phase = .interrupted
      jobs[index].run = nil
      jobs[index].runProcess = nil
      jobs[index].version = UUID()
    }
    archive.recognitionJobs = jobs
    try persist(archive)
    Self.activeRecognitionRuns.subtract(abandonedRuns)
  }

  func beginRecognitionJob(id: UUID, expected: UUID, unlockedProtectedPDF: Bool = false) throws -> UUID {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.version == expected }),
          var job = archive.recognitionJobs?[index], job.phase != .cancelled, job.phase != .completed, job.phase != .running,
          job.pages.count < job.pageCount else { throw Failure.stale }
    guard job.requiresPDFPassword != true || unlockedProtectedPDF,
          !unlockedProtectedPDF || job.original.kind == .pdf else { throw Failure.invalid }
    let run = UUID()
    if unlockedProtectedPDF { job.requiresPDFPassword = true }
    job.run = run
    job.runProcess = GalaxySSIHealthRecognitionJobs.processID
    job.phase = .running
    job.version = UUID()
    archive.recognitionJobs?[index] = job
    Self.activeRecognitionRuns.insert(run)
    do { try persist(archive) }
    catch { Self.activeRecognitionRuns.remove(run); throw error }
    return run
  }

  func commitRecognitionPage(id: UUID, run: UUID, page: GalaxySSIHealthRecognitionJobs.Page) throws {
    var archive = try load()
    guard Self.activeRecognitionRuns.contains(run),
          let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.run == run }),
          var job = archive.recognitionJobs?[index], job.phase == .running,
          page.index == job.pages.count, page.index < job.pageCount,
          page.lines.count <= 150, Set(page.lines.map(\.id)).count == page.lines.count,
          page.lines.allSatisfy({ GalaxySSIHealthRecognitionJobs.validDigest($0.id) && $0.ordinal >= 0 &&
            !$0.text.isEmpty && $0.text.count <= 500 && $0.text.utf8.count <= 8_192 &&
            [$0.bounds.minX, $0.bounds.minY, $0.bounds.width, $0.bounds.height].allSatisfy(\.isFinite) })
    else { throw Failure.stale }
    let currentBytes = (archive.recognitionJobs ?? []).flatMap(\.pages).reduce(0) { $0 + $1.textBytes }
    guard currentBytes + page.textBytes <= GalaxySSIHealthRecognitionJobs.maximumTextBytes else { throw Failure.invalid }
    job.pages.append(page)
    job.version = UUID()
    if job.pages.count == job.pageCount { job.phase = .completed; job.run = nil; job.runProcess = nil }
    archive.recognitionJobs?[index] = job
    try persist(archive)
    if job.phase == .completed { Self.activeRecognitionRuns.remove(run) }
  }

  func finishRecognitionJob(id: UUID, run: UUID, phase: GalaxySSIHealthRecognitionJobs.Phase) throws {
    guard phase == .cancelled || phase == .failed || phase == .interrupted else { throw Failure.invalid }
    // A stopped reader must not remain live when protected storage is temporarily unavailable.
    defer { Self.activeRecognitionRuns.remove(run) }
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.run == run && $0.phase == .running })
    else { throw Failure.stale }
    archive.recognitionJobs?[index].phase = phase
    archive.recognitionJobs?[index].run = nil
    archive.recognitionJobs?[index].runProcess = nil
    archive.recognitionJobs?[index].version = UUID()
    try persist(archive)
  }

  func cancelRecognitionJob(id: UUID, expected: UUID) throws {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.version == expected &&
      $0.phase != .completed && $0.phase != .cancelled })
    else { throw Failure.stale }
    let run = archive.recognitionJobs?[index].run
    archive.recognitionJobs?[index].phase = .cancelled
    archive.recognitionJobs?[index].run = nil
    archive.recognitionJobs?[index].runProcess = nil
    archive.recognitionJobs?[index].version = UUID()
    try persist(archive)
    if let run { Self.activeRecognitionRuns.remove(run) }
  }

  func removeRecognitionJob(id: UUID, expected: UUID) throws {
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.version == expected })
    else { throw Failure.stale }
    let run = archive.recognitionJobs?[index].run
    archive.recognitionJobs?.remove(at: index)
    try persist(archive)
    if let run { Self.activeRecognitionRuns.remove(run) }
  }

  func stageReportItem(_ input: GalaxySSIHealthReportReview.Item, replacing expected: UUID?) throws {
    var archive = try load()
    guard archive.reportEvidence?.contains(where: { $0.source == input.source }) != true else { throw Failure.duplicate }
    var pending = archive.reportReview ?? []
    let index = pending.firstIndex { $0.source == input.source }
    guard index.map({ pending[$0].version }) == expected, expected != input.version else { throw Failure.stale }
    guard input.validDraftValue, input.reading.reportSource == input.source,
          input.source.evidenceKey.map(GalaxySSIHealthRecognitionJobs.validDigest) != false,
          input.reading.revision == 0, !input.reading.deleted,
          !input.excerpt.isEmpty, input.excerpt.count <= 500 else { throw Failure.invalid }
    var reviewed = input
    reviewed.stagedAt = Date()
    if let index { pending[index] = reviewed }
    else {
      guard pending.count < 300 else { throw Failure.invalid }
      pending.append(reviewed)
    }
    archive.reportReview = pending
    pruneReviewActions(&archive)
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func discardReportItem(source: GalaxySSIHealthReportReview.Source, version: UUID) throws {
    var archive = try load()
    guard let index = archive.reportReview?.firstIndex(where: { $0.source == source && $0.version == version })
    else { throw Failure.stale }
    archive.reportReview?.remove(at: index)
    pruneReviewActions(&archive)
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
            archive.reportEvidence?.contains(where: { $0.source == item.source }) != true,
            !(existing + appended).contains(where: { $0.sameMeasurement(as: reading) }) else { throw Failure.duplicate }
      reading.revision = 1
      appended.append(reading)
    }
    archive.revisions.append(contentsOf: appended)
    archive.reportReview = pending.filter { !versions.contains($0.version) }
    pruneReviewActions(&archive)
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
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
    pruneReviewActions(&archive)
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
  }

  func importTable(_ data: Data, name: String, json: Bool, mapping: GalaxySSIHealthTableImport.Mapping,
                   expected: [GalaxySSIHealthTableImport.Status],
                   worksheet: GalaxySSIHealthXLSX.Selection? = nil, retainOriginal: Bool = true,
                   linkDuplicates: [Int: GalaxySSIHealthTableImport.EvidenceTarget] = [:],
                   reviewVersion: UUID? = nil) throws -> Int {
    var archive = try load()
    if let reviewVersion {
      guard archive.tableReviews?.contains(where: {
        $0.version == reviewVersion && $0.data == data && $0.retainOriginal == retainOriginal
      }) == true
      else { throw Failure.stale }
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
        links.append(.init(target: selected, source: row.source(batch: id, sha256: hash, table: table, mapping: mapping)))
      }
      guard row.status == .ready, var reading = row.reading else { continue }
      reading.revision = 1
      reading.tableSource = row.source(batch: id, sha256: hash, table: table, mapping: mapping)
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
    if let reviewVersion {
      if let draft = archive.tableReviews?.first(where: { $0.version == reviewVersion }) {
        archive.reviewReminderState?.actions.removeValue(forKey: "table:" + draft.id.uuidString)
      }
      archive.tableReviews?.removeAll { $0.version == reviewVersion }
    }
    try persist(archive)
    if reviewVersion != nil { NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner) }
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return readings.count
  }

  func importHealthKit(_ readings: [GalaxySSIHealthReading], at now: Date = Date()) throws -> Int {
    var archive = try load()
    let count = try appendHealthKit(readings, to: &archive, at: now)
    guard count > 0 else { return 0 }
    try persist(archive)
    NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner)
    return count
  }

  private func appendHealthKit(_ readings: [GalaxySSIHealthReading], to archive: inout Archive, at now: Date) throws -> Int {
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
    let metrics = Set(additions.map(\.metric))
    var importedAt = archive.healthKitImportedAt ?? [:]
    for scope in GalaxySSIHealthKitImport.Scope.allCases where metrics.contains(scope.metric) {
      importedAt[scope] = now
    }
    archive.healthKitImportedAt = importedAt
    return additions.count
  }

  func beginHealthKitSync(_ scope: GalaxySSIHealthKitImport.Scope, floor: Date, reset: Bool, at now: Date = Date()) throws
    -> GalaxySSIHealthKitSync.Checkpoint {
    guard scope != .steps, floor.timeIntervalSinceReferenceDate.isFinite else { throw Failure.invalid }
    var archive = try load()
    if archive.healthKitIncidents?[scope.rawValue] == nil, let previous = archive.syncIncident(scope) {
      archive.setSyncIncident(previous)
    }
    var checkpoints = archive.healthKitSync ?? [:]
    var checkpoint = checkpoints[scope.rawValue] ?? .init(floor: floor)
    if reset {
      checkpoint = .init(floor: floor, previousCoverageUnverified: checkpoints[scope.rawValue] != nil,
                         finishedAt: checkpoint.finishedAt)
    }
    if checkpoint.status == .success || checkpoint.status == .empty {
      checkpoint.insertedThisRun = 0
      checkpoint.readThisRun = 0
    }
    checkpoint.run = UUID()
    checkpoint.lastAttemptAt = now
    checkpoint.status = .running
    checkpoints[scope.rawValue] = checkpoint
    archive.healthKitSync = checkpoints
    try persist(archive)
    return checkpoint
  }

  func commitHealthKitPage(scope: GalaxySSIHealthKitImport.Scope, expected: GalaxySSIHealthKitSync.Checkpoint,
                           page: GalaxySSIHealthKitSync.Page, at now: Date) throws -> GalaxySSIHealthKitSync.Checkpoint {
    var archive = try load()
    guard var checkpoint = archive.healthKitSync?[scope.rawValue], checkpoint == expected,
          checkpoint.status == .running,
          page.anchor.map({ (1...16_384).contains($0.count) }) ??
            (checkpoint.anchor == nil && page.providerCount == 0 && !page.more),
          !page.more || (page.providerCount > 0 && page.anchor != checkpoint.anchor),
          (0...GalaxySSIHealthKitSync.pageSize * 2).contains(page.providerCount),
          page.rows.count <= page.providerCount, page.rows.allSatisfy({ $0.metric == scope.metric })
    else { throw Failure.stale }
    let count = try appendHealthKit(page.rows, to: &archive, at: now)
    checkpoint.anchor = page.anchor
    checkpoint.insertedThisRun += count
    checkpoint.readThisRun += page.rows.count
    var resolvedIncident = false
    if !page.more {
      checkpoint.status = checkpoint.readThisRun == 0 ? .empty : .success
      checkpoint.finishedAt = now
      if var incident = archive.syncIncident(scope), incident.resolvedAt == nil {
        incident.resolvedAt = now
        incident.version = UUID()
        archive.setSyncIncident(incident)
        resolvedIncident = true
      }
    }
    archive.healthKitSync?[scope.rawValue] = checkpoint
    try persist(archive)
    if resolvedIncident { NotificationCenter.default.post(name: Self.syncIncidentsChanged, object: owner) }
    if count > 0 { NotificationCenter.default.post(name: Self.trendInputsChanged, object: owner) }
    return checkpoint
  }

  func finishHealthKitSync(_ scope: GalaxySSIHealthKitImport.Scope, run: UUID,
                           status: GalaxySSIHealthKitSync.Status, at now: Date = Date()) throws {
    var archive = try load()
    guard archive.healthKitSync?[scope.rawValue]?.run == run,
          archive.healthKitSync?[scope.rawValue]?.status == .running else { return }
    if status.raisesIncident { archive.recordSyncFailure(scope, status: status, at: now) }
    archive.healthKitSync?[scope.rawValue]?.status = status
    try persist(archive)
    if status.raisesIncident { NotificationCenter.default.post(name: Self.syncIncidentsChanged, object: owner) }
  }

  func recordHealthKitAuthorizationFailure(_ scopes: Set<GalaxySSIHealthKitImport.Scope>,
                                          status: GalaxySSIHealthKitSync.Status, at now: Date = Date()) throws {
    guard status.raisesIncident, scopes.contains(where: { $0 != .steps }) else { return }
    var archive = try load()
    for scope in scopes where scope != .steps {
      archive.recordSyncFailure(scope, status: status, at: now)
    }
    try persist(archive)
    NotificationCenter.default.post(name: Self.syncIncidentsChanged, object: owner)
  }

  func acknowledgeHealthKitIncident(_ expected: GalaxySSIHealthKitSync.Incident, at now: Date = Date()) throws {
    var archive = try load()
    guard var incident = archive.syncIncident(expected.scope), incident == expected, !incident.handled
    else { throw Failure.stale }
    incident.acknowledgedAt = now
    incident.version = UUID()
    archive.setSyncIncident(incident)
    try persist(archive)
    NotificationCenter.default.post(name: Self.syncIncidentsChanged, object: owner)
  }

  static let syncIncidentsChanged = Notification.Name("galaxyssi.health.syncIncidentsChanged")

  func updateHealthKitSyncSelection(_ scopes: Set<GalaxySSIHealthKitImport.Scope>, enabled: Bool) throws {
    guard !scopes.contains(.steps) else { throw Failure.invalid }
    var archive = try load()
    let old = archive.healthKitSyncSelection ?? []
    let selected = enabled ? old.union(scopes) : old.subtracting(scopes)
    guard selected != old else { return }
    archive.healthKitSyncSelection = selected
    if !enabled {
      for scope in scopes { archive.healthKitSyncDelivery?.receipts.removeValue(forKey: scope) }
    }
    try persist(archive)
    NotificationCenter.default.post(name: Self.syncIncidentsChanged, object: owner)
  }

  func setSyncNotificationsEnabled(_ enabled: Bool) throws {
    var archive = try load()
    var state = archive.healthKitSyncDelivery ?? .init()
    guard state.enabled != enabled else { return }
    state.enabled = enabled
    if !enabled { state.receipts.removeAll() }
    archive.healthKitSyncDelivery = state
    try persist(archive)
    NotificationCenter.default.post(name: Self.syncIncidentsChanged, object: owner)
  }

  func reconcileSyncDelivery(now: Date, calendar: Calendar, permitted: Bool, scheduled: Set<UUID>,
                             delivered: Set<UUID>) throws -> GalaxySSIHealthSyncDelivery.Plan {
    var archive = try load()
    guard var state = archive.healthKitSyncDelivery else { return .init() }
    let plan = GalaxySSIHealthSyncDelivery.plan(state: state, selected: archive.healthKitSyncSelection ?? [],
      incidents: archive.syncIncidents, settings: archive.recordingReminders?.settings ?? .init(),
      now: now, calendar: calendar, permitted: permitted, scheduled: scheduled, delivered: delivered)
    if state.receipts != plan.receipts {
      state.receipts = plan.receipts
      archive.healthKitSyncDelivery = state
      try persist(archive)
    }
    return plan
  }

  func markSyncDeliverySubmitted(_ receipt: GalaxySSIHealthSyncDelivery.Receipt, calendar: Calendar) throws {
    var archive = try load()
    guard var state = archive.healthKitSyncDelivery, state.enabled,
          let entry = state.receipts.first(where: {
            $0.value.token == receipt.token && $0.value.incident == receipt.incident && $0.value.due == receipt.due
          }), let due = receipt.due, archive.healthKitSyncSelection?.contains(entry.key) == true,
          let incident = archive.syncIncident(entry.key), incident.id == receipt.incident, !incident.handled,
          GalaxySSIHealthSyncDelivery.dueAfter(due, settings: archive.recordingReminders?.settings ?? .init(),
                                               calendar: calendar) == due else { throw Failure.stale }
    guard !entry.value.submitted else { return }
    state.receipts[entry.key]?.submitted = true
    archive.healthKitSyncDelivery = state
    try persist(archive)
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

  func updateSleepEpisode(version: UUID, completion: Bool = false, snooze: Date? = nil) throws {
    var archive = try load()
    guard archive.derivesOverview == true, var ledger = archive.sleepReminders, ledger.preferences.enabled,
          let index = ledger.episodes.firstIndex(where: { $0.version == version && !$0.closed }),
          !ledger.episodes[index].completed else { throw Failure.stale }
    if completion { ledger.episodes[index].completed = true }
    if let snooze {
      ledger.episodes[index].snoozedUntil = snooze
      ledger.episodes[index].deliveredAt = nil
      ledger.episodes[index].notificationDue = nil
    }
    ledger.episodes[index].version = UUID()
    archive.sleepReminders = ledger
    try persist(archive)
    NotificationCenter.default.post(name: GalaxySSIHealthSleepReminder.changed, object: owner)
  }

  func saveSleepDelivery(_ episode: GalaxySSIHealthSleepReminder.Episode,
                         preferences: GalaxySSIHealthSleepReminder.Preferences,
                         settings: GalaxySSIHealthRecordingReminders.Settings?,
                         due: Date?, delivered: Date?) throws {
    var archive = try load()
    guard archive.derivesOverview == true, archive.recordingReminders?.settings == settings,
          var ledger = archive.sleepReminders, ledger.preferences == preferences,
          let index = ledger.episodes.firstIndex(of: episode), !episode.closed, !episode.completed
    else { throw Failure.stale }
    ledger.episodes[index].notificationDue = due
    ledger.episodes[index].deliveredAt = delivered
    guard ledger.episodes[index] != episode else { return }
    archive.sleepReminders = ledger
    try persist(archive, notify: false)
  }

  func commitRestore(_ archive: Archive, receipt: UUID, originals: [GalaxySSIHealthOriginalStore.Original] = [],
                     notify: Bool = true) throws {
    var updated = archive
    if !originals.isEmpty {
      guard var index = updated.originalIndex, try load().originalIndex == index else { throw Failure.stale }
      for original in originals { try index.include(original) }
      updated.originalIndex = index
    }
    var receipts = updated.restoreReceipts ?? []
    receipts.insert(receipt)
    updated.restoreReceipts = receipts
    try persist(updated, notify: notify)
  }

  func setOriginalIndex(_ index: GalaxySSIHealthOriginalStore.Index,
                        expected: GalaxySSIHealthOriginalStore.Index?) throws {
    var archive = try load()
    guard archive.originalIndex == expected else { throw Failure.stale }
    archive.originalIndex = index
    try persist(archive, notify: false)
  }

  static let reviewInputsChanged = Notification.Name("galaxyssi.health.reviewInputsChanged")

  private func pruneReviewActions(_ archive: inout Archive) {
    guard let actions = archive.reviewReminderState?.actions, !actions.isEmpty else { return }
    let active = Dictionary(uniqueKeysWithValues: GalaxySSIHealthReviewReminders.jobs(in: archive).map {
      ($0.key, $0.versions)
    })
    archive.reviewReminderState?.actions = actions.filter { active[$0.key] == $0.value.versions }
  }

  func saveTableReview(_ draft: GalaxySSIHealthReviewReminders.TableDraft, replacing expected: UUID?) throws {
    guard !draft.data.isEmpty, draft.data.count <= GalaxySSIHealthTableImport.maximumBytes,
          !draft.name.isEmpty, draft.name.count <= 180 else { throw Failure.invalid }
    var archive = try load()
    var drafts = archive.tableReviews ?? []
    if let expected {
      guard let index = drafts.firstIndex(where: { $0.id == draft.id && $0.version == expected }),
            expected != draft.version else { throw Failure.stale }
      drafts[index] = draft
    } else {
      guard drafts.count < GalaxySSIHealthReviewReminders.maximumTableDrafts else { throw Failure.invalid }
      guard !drafts.contains(where: { $0.id == draft.id }) else { throw Failure.stale }
      drafts.append(draft)
    }
    archive.tableReviews = drafts
    archive.reviewReminderState?.actions.removeValue(forKey: "table:" + draft.id.uuidString)
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func discardTableReview(_ draft: GalaxySSIHealthReviewReminders.TableDraft) throws {
    var archive = try load()
    guard let index = archive.tableReviews?.firstIndex(where: { $0.id == draft.id && $0.version == draft.version })
    else { throw Failure.stale }
    archive.tableReviews?.remove(at: index)
    archive.reviewReminderState?.actions.removeValue(forKey: "table:" + draft.id.uuidString)
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func setReviewRemindersEnabled(_ enabled: Bool) throws {
    var archive = try load()
    var state = archive.reviewReminderState ?? .init()
    if state.enabled != enabled {
      if enabled && state.notificationPreferences?.enabled == true {
        GalaxySSIHealthReviewDelivery.suppressExisting(GalaxySSIHealthReviewReminders.jobs(in: archive), in: &state, at: Date())
      } else { state.deliveries = nil }
    }
    state.enabled = enabled
    archive.reviewReminderState = state
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func updateReviewReminder(_ job: GalaxySSIHealthReviewReminders.Job, action: GalaxySSIHealthReviewReminders.Action) throws {
    var archive = try load()
    let jobs = GalaxySSIHealthReviewReminders.jobs(in: archive)
    guard jobs.contains(job) else { throw Failure.stale }
    var state = archive.reviewReminderState ?? .init()
    guard state.enabled else { throw Failure.stale }
    let active = Dictionary(uniqueKeysWithValues: jobs.map { ($0.key, $0.versions) })
    state.actions = state.actions.filter { active[$0.key] == $0.value.versions }
    state.actions[job.key] = .init(versions: job.versions, action: action)
    archive.reviewReminderState = state
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func setReviewNotificationPreferences(_ preferences: GalaxySSIHealthReviewDelivery.Preferences) throws {
    guard (0..<24).contains(preferences.quietStart), (0..<24).contains(preferences.quietEnd) else { throw Failure.invalid }
    var archive = try load()
    var state = archive.reviewReminderState ?? .init()
    if (state.notificationPreferences?.enabled == true) != preferences.enabled {
      if preferences.enabled && state.enabled {
        GalaxySSIHealthReviewDelivery.suppressExisting(GalaxySSIHealthReviewReminders.jobs(in: archive), in: &state, at: Date())
      } else { state.deliveries = nil }
    }
    state.notificationPreferences = preferences
    archive.reviewReminderState = state
    try persist(archive)
    NotificationCenter.default.post(name: Self.reviewInputsChanged, object: owner)
  }

  func reconcileReviewDelivery(now: Date, calendar: Calendar, permitted: Bool, scheduled: Set<UUID>,
                               delivered: Set<UUID>, availableOriginals: Set<UUID>) throws -> GalaxySSIHealthReviewDelivery.Plan {
    var archive = try load()
    guard var state = archive.reviewReminderState else { return .init() }
    let before = state.deliveries ?? [:]
    let jobs = GalaxySSIHealthReviewReminders.jobs(in: archive).filter {
      $0.kind == .table || availableOriginals.contains($0.target)
    }
    let plan = GalaxySSIHealthReviewDelivery.plan(
      jobs: jobs, state: state, now: now,
      calendar: calendar, permitted: permitted, scheduled: scheduled, delivered: delivered,
      settings: archive.recordingReminders?.settings)
    if plan.tickets != before {
      state.deliveries = plan.tickets
      archive.reviewReminderState = state
      try persist(archive)
    }
    return plan
  }

  func markReviewDeliverySubmitted(_ ticket: GalaxySSIHealthReviewDelivery.Ticket, calendar: Calendar) throws {
    var archive = try load()
    guard var state = archive.reviewReminderState, let key = state.deliveries?.first(where: {
      $0.value.token == ticket.token && $0.value.due == ticket.due && !$0.value.suppressed
    })?.key,
    let job = GalaxySSIHealthReviewReminders.jobs(in: archive).first(where: { $0.key == key && $0.versions == ticket.versions }),
    state.enabled, state.notificationPreferences?.enabled == true,
    GalaxySSIHealthReviewDelivery.action(for: job, state: state) != .handled,
    GalaxySSIHealthReviewDelivery.cycle(for: job, state: state) == ticket.cycle,
    state.notificationPreferences?.deliveryDate(ticket.due, settings: archive.recordingReminders?.settings,
      calendar: calendar) == ticket.due
    else { throw Failure.stale }
    if state.deliveries?[key]?.submitted == true { return }
    state.deliveries?[key]?.submitted = true
    archive.reviewReminderState = state
    try persist(archive)
  }

  private func persist(_ archive: Archive, notify: Bool = true) throws {
    var archive = archive
    if let reminders = archive.localCareFollowUps, !reminders.isEmpty {
      let now = Date()
      let enabled = Self.careFollowUpPreferences(archive) != nil
      archive.localCareFollowUps = reminders.filter {
        enabled && careFollowUpIsCurrent(concernID: $0.value.concernID, metric: $0.value.metric,
          actionID: $0.key, archive: archive, now: now, verifyOriginal: false)
      }
    }
    if archive.localCareAllowed == true, !(archive.localCare?.current.values.contains { concern in
      concern.adoptedActions?.contains { $0.instruction != nil } == true
    } ?? false) {
      let now = Date()
      let context = careAgendaContexts(archive, now: now)
      archive.localCareAgenda = context.isEmpty ? nil : try JSONEncoder().encode(makeCareAgenda(archive, context: context, now: now))
    } else {
      archive.localCareAgenda = nil
    }
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
