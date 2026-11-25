import Foundation

enum GalaxySSIHealthAtlasReadings {
  enum Purpose: String, Codable { case overview, trend }
  enum Outcome: String, Codable { case started, complete, blocked }
  struct Audit: Codable, Identifiable {
    let id: UUID
    let at: Date
    let entryID: String
    let purpose: Purpose
    let metrics: [GalaxySSIHealthMetric]
    let from: Date?
    let through: Date
    let zone: String
    let source: String
    let consentEvent: UUID?
    var outcome: Outcome
  }
  struct Snapshot {
    let latest: [GalaxySSIHealthMetric: GalaxySSIHealthReading]
    let trend: [GalaxySSIHealthReading]
  }

  static func latest(_ current: [GalaxySSIHealthReading], entryID: String, now: Date) -> [GalaxySSIHealthMetric: GalaxySSIHealthReading] {
    let metrics = Set(GalaxySSIHealthAtlasMetrics.forEntry(entryID))
    var result: [GalaxySSIHealthMetric: GalaxySSIHealthReading] = [:]
    for reading in current where metrics.contains(reading.metric) && !reading.deleted && reading.isValid && reading.measuredAt <= now {
      if let previous = result[reading.metric],
         (previous.measuredAt, previous.id.uuidString) >= (reading.measuredAt, reading.id.uuidString) { continue }
      result[reading.metric] = reading
    }
    return result
  }

  static func snapshot(_ current: [GalaxySSIHealthReading], entryID: String,
                       spec: GalaxySSIHealthTrendAnalysis.Spec, now: Date) -> Snapshot {
    let window = spec.interval
    let mapped = GalaxySSIHealthAtlasMetrics.forEntry(entryID).contains(spec.metric)
    return Snapshot(latest: latest(current, entryID: entryID, now: now),
      trend: mapped ? current.filter { $0.metric == spec.metric && !$0.deleted && $0.isValid &&
        $0.measuredAt >= window.start && $0.measuredAt < window.end && $0.measuredAt <= min(now, spec.through) } : [])
  }
}

@MainActor
extension GalaxySSIHealthRecords {
  func atlasMeasurements(entryID: String, spec: GalaxySSIHealthTrendAnalysis.Spec, now: Date) throws -> GalaxySSIHealthAtlasReadings.Snapshot {
    let metrics = GalaxySSIHealthAtlasMetrics.forEntry(entryID)
    guard metrics.contains(spec.metric), (1...366).contains(spec.days), now.timeIntervalSinceReferenceDate.isFinite,
      spec.through.timeIntervalSinceReferenceDate.isFinite, spec.through <= now else { throw Failure.invalid }
    var archive = try load()
    let permitted = archive.derivesOverview == true
    let consent = archive.privacyEvents?.last(where: { $0.scope == .overview })?.id
    let ids = [UUID(), UUID()]
    let outcome: GalaxySSIHealthAtlasReadings.Outcome = permitted ? .started : .blocked
    var audit = archive.atlasReadAudit ?? []
    audit.append(.init(id: ids[0], at: now, entryID: entryID, purpose: .overview, metrics: metrics,
      from: nil, through: now, zone: spec.calendar.timeZone.identifier, source: "all", consentEvent: consent, outcome: outcome))
    audit.append(.init(id: ids[1], at: now, entryID: entryID, purpose: .trend, metrics: [spec.metric],
      from: spec.interval.start, through: min(now, spec.interval.end), zone: spec.calendar.timeZone.identifier,
      source: "all", consentEvent: consent, outcome: outcome))
    archive.atlasReadAudit = Array(audit.suffix(200))
    try persistAtlasReadAudit(archive)
    guard permitted else { throw Failure.permission }
    let snapshot = GalaxySSIHealthAtlasReadings.snapshot(archive.current, entryID: entryID, spec: spec, now: now)
    for index in archive.atlasReadAudit?.indices ?? 0..<0 {
      if let id = archive.atlasReadAudit?[index].id, ids.contains(id) { archive.atlasReadAudit?[index].outcome = .complete }
    }
    try persistAtlasReadAudit(archive)
    return snapshot
  }
}
