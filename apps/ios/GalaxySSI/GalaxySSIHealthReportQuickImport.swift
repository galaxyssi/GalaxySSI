import Foundation

enum GalaxySSIHealthReportQuickImport {
  typealias Review = GalaxySSIHealthReportReview
  struct Supplement {
    var measuredAt: Date?
    var fasting = ""
  }
  struct Outcome: Codable, Equatable {
    var saved = 0
    var duplicates = 0
    var pending = 0
    var partial = false
    var releaseOriginal = false
  }
  struct Plan: Equatable, Identifiable {
    let job: GalaxySSIHealthRecognitionJobs.Job
    let items: [Review.Item]
    let collectedDate: Date?
    let zone: String
    var id: UUID { job.version }
    var needsDate: Bool { items.contains { $0.reading.measuredAt.timeIntervalSince1970 <= 0 } }
    var needsFasting: Bool { items.contains { $0.reading.metric == .glucose && ["", "unspecified"].contains($0.reading.conditions) } }
    var needsSupplement: Bool { needsDate || needsFasting }
  }

  static func plan(job: GalaxySSIHealthRecognitionJobs.Job, archive: GalaxySSIHealthRecords.Archive, now: Date) throws -> Plan {
    guard let result = job.reportVision, job.original.kind == .image, job.captureSource?.mode != .device,
          [.completed, .failed].contains(job.phase),
          let zone = job.reportVisionZone.flatMap(TimeZone.init(identifier:)) else { throw GalaxySSIHealthRecords.Failure.stale }
    _ = try GalaxySSIHealthReportVision.parse(String(decoding: JSONEncoder().encode(result), as: UTF8.self))
    let context = GalaxySSIHealthOCRSourceContext.inspect(["Collected at: " + result.collected], timeZone: zone)
    let sampled = context.sample?.date
    let date = sampled.flatMap { $0 > Date(timeIntervalSince1970: 0) && $0 <= now ? $0 : nil }
    var dateOnly: Date?
    if result.collected.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil {
      dateOnly = GalaxySSIHealthOCRSourceContext.inspect(["Collected at: " + result.collected + " 12:00"], timeZone: zone).sample?.date
    }
    let live = Set(archive.current.map(\.id))
    let items = try result.rows.compactMap { row -> Review.Item? in
      let source = GalaxySSIHealthReportVision.source(row, job: job)
      guard job.reportImportedSources?.contains(source.regionIdentity) != true,
            !archive.revisions.contains(where: { $0.reportSource == source }),
            archive.reportEvidence?.contains(where: { $0.source == source && live.contains($0.target.record) }) != true else { return nil }
      if let edited = archive.reportReview?.first(where: { $0.source == source }) { return edited }
      let recordID = try MqttPeerChatProjection.stableID(["model-report-reading", job.id.uuidString, source.regionIdentity])
      let version = try MqttPeerChatProjection.stableID(["model-report-draft", job.id.uuidString, source.regionIdentity])
      guard let id = UUID(uuidString: recordID), let token = UUID(uuidString: version) else { throw GalaxySSIHealthRecords.Failure.invalid }
      let raw = row.values["value"] ?? ""
      let number = row.metric.form == .qualitative ? nil : GalaxySSIHealthReportedResult.number(raw)
      let typed = number == nil ? GalaxySSIHealthReportedResult.parse(raw, metric: row.metric) : nil
      let reading = GalaxySSIHealthReading(id: id, metric: row.metric, measuredAt: date ?? Date(timeIntervalSince1970: 0),
        value: number, diastolic: row.values["diastolic"].flatMap(GalaxySSIHealthReportedResult.number),
        conditions: row.metric == .glucose ? result.fasting ?? "" : "", reported: typed,
        reportedNotation: row.metric.laboratory ? raw : nil, unitOverride: row.unit,
        referenceInterval: row.reference.isEmpty ? nil : row.reference, reportSource: source)
      return Review.Item(version: token, source: source, excerpt: row.source, reading: reading)
    }
    return .init(job: job, items: items, collectedDate: dateOnly, zone: zone.identifier)
  }

  static func valueKey(_ reading: GalaxySSIHealthReading) -> String {
    AgentModelLoopRecoveryIdentity.sha256([reading.unit, reading.value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
      reading.reported?.canonical ?? "", reading.diastolic.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""])
  }

  static func conditionKey(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed == "unspecified" ? "" : trimmed
  }

  static func validSupplementDate(_ date: Date, plan: Plan, now: Date) -> Bool {
    guard date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0, date <= now,
          let zone = TimeZone(identifier: plan.zone) else { return false }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let dates = GalaxySSIHealthEncounter.possibleTimes(day: date, hour: calendar.component(.hour, from: date),
      minute: calendar.component(.minute, from: date), zone: zone)
    return dates.count == 1 && (plan.collectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? true)
  }

  static func text(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.report_quick." + key, fallback: fallback, language: language)
  }
}

extension GalaxySSIHealthRecords {
  private func quickReportSource(_ job: GalaxySSIHealthRecognitionJobs.Job, originals: GalaxySSIHealthOriginalStore) throws {
    guard originals.owner == owner, originals.restoreRecordsFile == isolatedFile else { throw Failure.permission }
    _ = try originals.read(job.original)
    if let revision = job.captureSource?.cropRevision {
      guard try originals.readCrop(for: job.original)?.metadata.revision == revision else { throw Failure.stale }
    }
  }

  func quickReportPlan(job id: UUID, originals: GalaxySSIHealthOriginalStore, now: Date = Date()) throws -> GalaxySSIHealthReportQuickImport.Plan {
    let archive = try load()
    guard let job = archive.recognitionJobs?.first(where: { $0.id == id }) else { throw Failure.stale }
    try quickReportSource(job, originals: originals)
    return try GalaxySSIHealthReportQuickImport.plan(job: job, archive: archive, now: now)
  }

  func saveQuickReport(_ expected: GalaxySSIHealthReportQuickImport.Plan, supplement: GalaxySSIHealthReportQuickImport.Supplement,
      originals: GalaxySSIHealthOriginalStore, now: Date = Date(), active: () -> Bool) throws -> GalaxySSIHealthReportQuickImport.Outcome {
    typealias Quick = GalaxySSIHealthReportQuickImport
    guard active(), !Task.isCancelled, now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0 else { throw Failure.stale }
    try quickReportSource(expected.job, originals: originals)
    var archive = try load()
    guard let index = archive.recognitionJobs?.firstIndex(where: { $0 == expected.job }),
          try Quick.plan(job: expected.job, archive: archive, now: now) == expected,
          !expected.needsDate || supplement.measuredAt.map({ Quick.validSupplementDate($0, plan: expected, now: now) }) == true,
          !expected.needsFasting || ["fasting", "non_fasting", "unspecified"].contains(supplement.fasting)
    else { throw Failure.stale }
    if expected.items.isEmpty { return Quick.Outcome(partial: expected.job.reportVision?.partial == true) }
    var items = expected.items
    for i in items.indices {
      var reading = items[i].reading
      if reading.measuredAt.timeIntervalSince1970 <= 0, let date = supplement.measuredAt { reading.measuredAt = date }
      if reading.metric == .glucose, ["", "unspecified"].contains(reading.conditions), !supplement.fasting.isEmpty {
        reading.conditions = supplement.fasting
      }
      guard reading.measuredAt.timeIntervalSince1970 > 0, reading.measuredAt <= now,
            reading.measuredAt.timeIntervalSince1970.isFinite else { throw Failure.invalid }
      items[i] = .init(version: items[i].version, source: items[i].source, excerpt: items[i].excerpt, reading: reading, stagedAt: now)
    }
    let ambiguous = Set(Dictionary(grouping: items, by: { $0.reading.metric }).filter {
      Set($0.value.map { Quick.valueKey($0.reading) }).count > 1
    }.keys)
    var pending = archive.reportReview ?? []
    var evidence = archive.reportEvidence ?? []
    var imported = expected.job.reportImportedSources ?? []
    var outcome = Quick.Outcome(partial: expected.job.reportVision?.partial == true)
    for item in items {
      guard active(), !Task.isCancelled, item.source.recognition == .model, item.reading.revision == 0,
            item.reading.reportSource == item.source, !item.reading.deleted else { throw Failure.stale }
      var reading = item.reading
      let duplicates = archive.current.filter { $0.measuredAt == reading.measuredAt &&
        Quick.conditionKey($0.conditions) == Quick.conditionKey(reading.conditions) && $0.sameMeasurement(as: reading) }
      pending.removeAll { $0.source == item.source }
      if ambiguous.contains(reading.metric) || !reading.isValid || duplicates.count > 1 {
        guard pending.count < 300 else { throw Failure.invalid }
        pending.append(item); outcome.pending += 1
        continue
      }
      if let previous = duplicates.first {
        guard evidence.count < 5000 else { throw Failure.invalid }
        evidence.append(.init(target: .init(record: previous.id, revision: previous.revision), source: item.source, excerpt: item.excerpt))
        outcome.duplicates += 1
      } else {
        guard !archive.revisions.contains(where: { $0.id == reading.id }) else { throw Failure.stale }
        reading.revision = 1
        archive.revisions.append(reading); outcome.saved += 1
      }
      imported.insert(item.source.regionIdentity)
    }
    archive.reportEvidence = evidence
    archive.reportReview = pending
    outcome.releaseOriginal = !expected.items.isEmpty && outcome.pending == 0 && !outcome.partial &&
      archive.reviewOnlyReportOriginals?.contains(expected.job.original.id) == true
    archive.recognitionJobs?[index].reportImportedSources = imported
    archive.recognitionJobs?[index].reportImportOutcome = outcome
    archive.recognitionJobs?[index].version = UUID()
    guard active(), !Task.isCancelled else { throw Failure.stale }
    try persistQuickReport(archive)
    return outcome
  }

  func markQuickReportRelease(job id: UUID, original: UUID) throws -> Bool {
    var archive = try load()
    guard archive.reviewOnlyReportOriginals?.contains(original) == true,
          let index = archive.recognitionJobs?.firstIndex(where: { $0.id == id && $0.original.id == original }),
          let job = archive.recognitionJobs?[index] else { return false }
    if job.phase != .cancelled {
      guard job.reportVision?.partial == false,
            try GalaxySSIHealthReportQuickImport.plan(job: job, archive: archive, now: Date()).items.isEmpty else { return false }
    }
    if job.reportImportOutcome?.releaseOriginal != true {
      var outcome = job.reportImportOutcome ?? .init()
      outcome.pending = 0; outcome.releaseOriginal = true
      archive.recognitionJobs?[index].reportImportOutcome = outcome
      archive.recognitionJobs?[index].version = UUID()
      try persistQuickReport(archive)
    }
    return true
  }

  func forgetReleasedQuickReportOriginal(_ original: UUID) throws {
    var archive = try load()
    guard archive.reviewOnlyReportOriginals?.remove(original) != nil else { return }
    try persistQuickReport(archive)
  }
}
