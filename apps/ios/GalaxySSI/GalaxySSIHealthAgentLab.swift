import UIKit

enum GalaxySSIHealthAgentLab {
  enum Mode: String { case results, abnormal, note, remind }
  struct Policy: Equatable {
    let allowed: Bool
    let event: UUID?
    init(_ archive: GalaxySSIHealthRecords.Archive) {
      allowed = archive.derivesOverview == true
      event = archive.privacyEvents?.last(where: { $0.scope == .overview })?.id
    }
  }
  struct Audit: Codable {
    let id: UUID
    let at: Date
    let through: Date
    let zone: String
    let once: Bool
    let allowed: Bool
    let consent: UUID?
  }
  struct Snapshot {
    let day: Date?
    let imported: Bool
    let rows: [GalaxySSIHealthReading]
    let olderUntil: Date?
    let policy: Policy
    var abnormal: [GalaxySSIHealthReading] { rows.filter { GalaxySSIHealthOverviewRange.report($0)?.outside == true } }
    var unknown: Int { rows.filter { row in
      guard let range = GalaxySSIHealthOverviewRange.report(row) else { return true }
      return range.position == .notComparable
    }.count }
  }

  // This capability is created only by an explicit local button, never by a model or transcript marker.
  @MainActor final class Once {
    let owner: String
    let policy: Policy
    let through: Date
    private let deadline: TimeInterval
    private var used = false
    init(owner: String, policy: Policy, through: Date, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
      self.owner = owner; self.policy = policy; self.through = through; deadline = uptime + 60
    }
    func claim(owner: String, policy: Policy, through: Date,
      uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
      guard !used, self.owner == owner, self.policy == policy, self.through == through,
        uptime.isFinite, uptime >= deadline - 60, uptime <= deadline else { return false }
      used = true
      return true
    }
  }

  static func snapshot(_ readings: [GalaxySSIHealthReading], policy: Policy, through: Date,
    now: Date, calendar: Calendar) throws -> Snapshot {
    guard through.timeIntervalSince1970.isFinite, through.timeIntervalSince1970 > 0,
      now.timeIntervalSince1970.isFinite, through <= now else { throw GalaxySSIHealthRecords.Failure.invalid }
    var eligible: [GalaxySSIHealthReading] = []
    for reading in readings {
      try Task.checkCancellation()
      if reading.metric.laboratory, !reading.deleted, reading.isValid, reading.measuredAt <= through {
        eligible.append(reading)
      }
    }
    eligible.sort { ($0.measuredAt, $0.id.uuidString) > ($1.measuredAt, $1.id.uuidString) }
    let imported = eligible.contains { $0.reportSource != nil }
    let source = imported ? eligible.filter { $0.reportSource != nil } : eligible
    guard let latest = source.first else {
      return Snapshot(day: nil, imported: false, rows: [], olderUntil: nil, policy: policy)
    }
    let day = calendar.startOfDay(for: latest.measuredAt)
    return Snapshot(day: day, imported: imported,
      rows: source.filter { $0.measuredAt >= day },
      olderUntil: source.contains(where: { $0.measuredAt < day }) ? day.addingTimeInterval(-0.001) : nil, policy: policy)
  }
}

extension GalaxySSIHealthRecords {
  func localLabMeasurements(through: Date, once: GalaxySSIHealthAgentLab.Once? = nil,
    calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) throws -> GalaxySSIHealthAgentLab.Snapshot {
    guard UIApplication.shared.applicationState == .active, UIApplication.shared.isProtectedDataAvailable,
      !owner.isBlank, through.timeIntervalSince1970.isFinite, through.timeIntervalSince1970 > 0, through <= now else {
      throw Failure.permission
    }
    var archive = try load()
    let policy = GalaxySSIHealthAgentLab.Policy(archive)
    let permitted = once.map { $0.claim(owner: owner, policy: policy, through: through) } ?? policy.allowed
    var audit = archive.localLabReadAudit ?? []
    audit.append(.init(id: UUID(), at: now, through: through, zone: calendar.timeZone.identifier,
      once: once != nil, allowed: permitted, consent: policy.event))
    archive.localLabReadAudit = Array(audit.suffix(100))
    try persistLocalLabAudit(archive)
    guard permitted else { throw Failure.permission }
    return try GalaxySSIHealthAgentLab.snapshot(archive.current, policy: policy, through: through, now: now, calendar: calendar)
  }

  func annotateLocalLab(_ expected: GalaxySSIHealthReading, policy: GalaxySSIHealthAgentLab.Policy,
    note: String, condition: String? = nil) throws {
    let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard UIApplication.shared.applicationState == .active, UIApplication.shared.isProtectedDataAvailable,
      expected.metric.laboratory, !text.isEmpty, text.count <= 500,
      condition.map({ ["fasting", "non_fasting", "after_meal", "after_meal_1h", "after_meal_2h"].contains($0) }) ?? true else {
      throw Failure.invalid
    }
    let archive = try load()
    guard policy.allowed, GalaxySSIHealthAgentLab.Policy(archive) == policy else { throw Failure.permission }
    guard archive.current.first(where: { $0.id == expected.id }) == expected else { throw Failure.stale }
    var updated = expected
    updated.notes = [expected.notes, text].filter { !$0.isEmpty }.joined(separator: "\n")
    if let condition { updated.conditions = condition }
    guard updated.isValid else { throw Failure.invalid }
    try write(updated)
  }
}
