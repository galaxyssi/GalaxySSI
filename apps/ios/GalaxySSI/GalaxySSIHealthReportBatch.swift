import Foundation

enum GalaxySSIHealthReportBatch {
  typealias Quick = GalaxySSIHealthReportQuickImport
  static let conditions = ["fasting", "after_meal_1h", "after_meal_2h", "after_meal", "non_fasting", "unspecified"]
  static let nonFasting = Set(conditions.filter { !["fasting", "unspecified"].contains($0) })
  enum Deferred: String, Codable, Hashable { case sampleTime, unit, conflict, invalid }

  struct Scope: Equatable {
    var needsTime = false
    var needsDate = false
    var needsCondition = false
    var needed: Bool { needsTime || needsCondition }
    mutating func include(_ other: Self) {
      needsTime = needsTime || other.needsTime; needsDate = needsDate || other.needsDate
      needsCondition = needsCondition || other.needsCondition
    }
  }

  struct Supplement {
    var day: Date?
    var clock: Date?
    var condition = "unspecified"
  }

  struct Consent: Equatable {
    let metrics: UUID?
    let online: UUID?
    init(_ archive: GalaxySSIHealthRecords.Archive) throws {
      guard archive.derivesOverview == true else { throw GalaxySSIHealthRecords.Failure.permission }
      metrics = archive.privacyEvents?.last(where: { $0.scope == .overview })?.id
      online = archive.healthOnlinePermission
    }
  }

  struct Review: Identifiable {
    let id = UUID()
    let owner: String
    let plans: [Quick.Plan]
    let scope: Scope
    let consent: Consent
    let recordsVersion: String
    let zone: String
    let expires: Date
  }

  static func reason(_ reading: GalaxySSIHealthReading, conflicting: Bool, now: Date) -> Deferred? {
    if conflicting { return .conflict }
    if reading.reported?.kind != .qualitative && !reading.metric.units.contains(reading.unit) { return .unit }
    if !reading.isValid { return .invalid }
    if reading.measuredAt.timeIntervalSince1970 <= 0 || reading.measuredAt > now { return .sampleTime }
    return nil
  }

  static func scope(_ plan: Quick.Plan, now: Date) -> Scope {
    let conflicts = Set(Dictionary(grouping: plan.items, by: { $0.reading.metric }).filter {
      Set($0.value.map { Quick.valueKey($0.reading) }).count > 1
    }.keys)
    let repairable = plan.items.filter {
      let problem = reason($0.reading, conflicting: conflicts.contains($0.reading.metric), now: now)
      return problem == nil || problem == .sampleTime
    }
    let time = repairable.contains { $0.reading.measuredAt.timeIntervalSince1970 <= 0 }
    return .init(needsTime: time, needsDate: time && plan.collectedDate == nil,
      needsCondition: repairable.contains { $0.reading.metric == .glucose && Quick.conditionKey($0.reading.conditions).isEmpty })
  }

  static func supplement(_ input: Supplement, plan: Quick.Plan, inputZone: String, now: Date) throws -> Quick.Supplement {
    guard conditions.contains(input.condition), let zone = TimeZone(identifier: plan.zone),
          let chosenZone = TimeZone(identifier: inputZone) else { throw GalaxySSIHealthRecords.Failure.invalid }
    var output = Quick.Supplement(fasting: input.condition)
    if scope(plan, now: now).needsTime {
      guard let clock = input.clock else { throw GalaxySSIHealthRecords.Failure.invalid }
      var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
      var chosen = calendar; chosen.timeZone = chosenZone
      let day: DateComponents
      if let printed = plan.collectedDate { day = calendar.dateComponents([.year, .month, .day], from: printed) }
      else if let selected = input.day { day = chosen.dateComponents([.year, .month, .day], from: selected) }
      else { throw GalaxySSIHealthRecords.Failure.invalid }
      var noon = day; noon.hour = 12
      guard let date = calendar.date(from: noon) else { throw GalaxySSIHealthRecords.Failure.invalid }
      let times = GalaxySSIHealthEncounter.possibleTimes(day: date, hour: chosen.component(.hour, from: clock),
        minute: chosen.component(.minute, from: clock), zone: zone)
      guard times.count == 1, let at = times.first, Quick.validSupplementDate(at, plan: plan, now: now) else {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      output.measuredAt = at
    }
    return output
  }

  static func nearby(_ reading: GalaxySSIHealthReading, current: [GalaxySSIHealthReading]) -> GalaxySSIHealthReading? {
    current.filter {
      !$0.deleted && $0.revision > 0 && $0.reportSource != nil && $0.healthKitSource == nil && $0.tableSource == nil && $0.bluetoothReceipt == nil &&
      $0.metric == reading.metric && $0.unit == reading.unit && Quick.conditionKey($0.conditions) == Quick.conditionKey(reading.conditions) &&
      abs($0.measuredAt.timeIntervalSince(reading.measuredAt)) <= 3_600
    }.sorted {
      let left = abs($0.measuredAt.timeIntervalSince(reading.measuredAt)), right = abs($1.measuredAt.timeIntervalSince(reading.measuredAt))
      if left != right { return left < right }
      if $0.measuredAt != $1.measuredAt { return $0.measuredAt > $1.measuredAt }
      return $0.id.uuidString > $1.id.uuidString
    }.first
  }

  static func recordsVersion(_ archive: GalaxySSIHealthRecords.Archive) -> String {
    AgentModelLoopRecoveryIdentity.sha256(archive.current.sorted { $0.id.uuidString < $1.id.uuidString })
  }

  static func ready(_ plans: [Quick.Plan], archive: GalaxySSIHealthRecords.Archive) -> Bool {
    let groups = Set(plans.compactMap { $0.job.reportBatchID })
    return (archive.recognitionJobs ?? []).filter { $0.reportBatchID.map(groups.contains) == true }.allSatisfy {
      if $0.phase == .failed || $0.phase == .cancelled { return true }
      return $0.reportModelFirst == true ? $0.reportVision != nil : $0.phase == .completed
    }
  }

  static func conditionTitle(_ value: String, language: String) -> String {
    let fallback: String
    switch value {
    case "fasting": fallback = "Fasting"
    case "after_meal_1h": fallback = "One hour after a meal"
    case "after_meal_2h": fallback = "Two hours after a meal"
    case "after_meal": fallback = "After a meal"
    case "non_fasting": fallback = "Not fasting"
    default: fallback = "Unknown"
    }
    return Quick.text(value == "unspecified" ? "unknown" : value, fallback, language)
  }

  static func deferredTitle(_ value: Deferred, language: String) -> String {
    let fallback: String
    switch value {
    case .sampleTime: fallback = "Sampling time missing or invalid"
    case .unit: fallback = "Unit could not be confirmed"
    case .conflict: fallback = "Conflicting results for the same measurement"
    case .invalid: fallback = "Result could not be used"
    }
    return Quick.text("deferred_" + value.rawValue, fallback, language)
  }
}

extension GalaxySSIHealthRecords {
  func reportBatchReview(ids: [UUID], originals: GalaxySSIHealthOriginalStore,
      zone: TimeZone = .autoupdatingCurrent, now: Date = Date()) throws -> GalaxySSIHealthReportBatch.Review {
    typealias Batch = GalaxySSIHealthReportBatch
    guard !ids.isEmpty, ids.count <= GalaxySSIHealthRecognitionJobs.maximumJobs, Set(ids).count == ids.count,
          originals.owner == owner, originals.restoreRecordsFile == isolatedFile else { throw Failure.invalid }
    let archive = try load(), consent = try Batch.Consent(archive)
    var scope = Batch.Scope()
    let plans = try ids.map { id -> GalaxySSIHealthReportQuickImport.Plan in
      guard let job = archive.recognitionJobs?.first(where: { $0.id == id }),
            job.reportImportOutcome?.contextConfirmed != true else { throw Failure.stale }
      try quickReportSource(job, originals: originals)
      let plan = try GalaxySSIHealthReportQuickImport.plan(job: job, archive: archive, now: now, automatic: true, retryDeferred: true)
      scope.include(Batch.scope(plan, now: now))
      return plan
    }
    guard Batch.ready(plans, archive: archive) else { throw Failure.stale }
    return .init(owner: owner, plans: plans, scope: scope, consent: consent, recordsVersion: Batch.recordsVersion(archive),
      zone: zone.identifier, expires: now.addingTimeInterval(600))
  }

  func completeReportBatch(_ review: GalaxySSIHealthReportBatch.Review, supplement: GalaxySSIHealthReportBatch.Supplement,
      originals: GalaxySSIHealthOriginalStore, confirmed: Bool, zone: TimeZone = .autoupdatingCurrent, now: Date = Date())
      throws -> [GalaxySSIHealthReportQuickImport.Outcome] {
    typealias Batch = GalaxySSIHealthReportBatch
    var archive = try load()
    guard confirmed, review.owner == owner, now < review.expires, zone.identifier == review.zone, !review.plans.isEmpty,
          review.plans.count <= GalaxySSIHealthRecognitionJobs.maximumJobs,
          Set(review.plans.map { $0.job.id }).count == review.plans.count,
          Batch.ready(review.plans, archive: archive),
          try Batch.Consent(archive) == review.consent,
          Batch.recordsVersion(archive) == review.recordsVersion else { throw Failure.stale }
    // Preflight every job and all local times before applying any measurement. Confirmation is local, with no await or resend.
    let inputs = try review.plans.map { plan -> GalaxySSIHealthReportQuickImport.Supplement in
      guard archive.recognitionJobs?.contains(plan.job) == true else { throw Failure.stale }
      try quickReportSource(plan.job, originals: originals)
      return try Batch.supplement(supplement, plan: plan, inputZone: review.zone, now: now)
    }
    let outcomes = try zip(review.plans, inputs).map { plan, input in
      try applyQuickReport(plan, supplement: input, originals: originals, now: now, automatic: true,
        imageBytes: plan.job.reportImportOutcome?.imageBytes ?? 0, archive: &archive,
        persist: false, replaceNearby: true, contextConfirmed: true, active: { true })
    }
    try persistQuickReport(archive)
    return outcomes
  }
}
