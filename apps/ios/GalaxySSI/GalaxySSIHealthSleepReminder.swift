import Foundation

enum GalaxySSIHealthSleepReminder {
  static let thresholds = [30, 45, 60, 90]
  static let ruleVersion = 1

  struct Preferences: Codable, Equatable {
    var enabled = false
    var threshold = 45
    var merge = true
    var notifications = false
    var quietStart = 22
    var quietEnd = 8

    func isQuiet(at date: Date, calendar: Calendar) -> Bool {
      let hour = calendar.component(.hour, from: date)
      if quietStart == quietEnd { return false }
      return quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : hour >= quietStart || hour < quietEnd
    }
  }

  struct Day: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let minutes: Decimal?
  }

  struct Evidence: Codable, Equatable {
    let day: Date
    let calculatedAt: Date
    let zone: String
    let rule: Int
    let threshold: Int
    let revisions: [String]
    let days: [Day]
    let baselineMean: Decimal
    let currentMean: Decimal

    var decrease: Decimal { baselineMean - currentMean }

    var windows: (baseline: DateInterval, recent: DateInterval, calendar: Calendar)? {
      guard days.count == 21, let zone = TimeZone(identifier: self.zone) else { return nil }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = zone
      guard calendar.startOfDay(for: day) == day,
            days.enumerated().allSatisfy({ index, saved in
              calendar.date(byAdding: .day, value: index - 21, to: day) == saved.date
            }) else { return nil }
      return (.init(start: days[0].date, end: days[14].date), .init(start: days[14].date, end: day), calendar)
    }

    func contributors(_ current: [GalaxySSIHealthReading], baseline: Bool) -> [GalaxySSIHealthReading]? {
      guard let windows, rule == GalaxySSIHealthSleepReminder.ruleVersion,
            let verified = GalaxySSIHealthSleepReminder.evidence(current, at: day, calendar: windows.calendar,
                                                                threshold: threshold),
            matches(verified), baselineMean == verified.baselineMean, currentMean == verified.currentMean else { return nil }
      return GalaxySSIHealthSleepReminder.sleepReadings(current, in: baseline ? windows.baseline : windows.recent)
    }

    func matches(_ other: Self) -> Bool {
      day == other.day && zone == other.zone && rule == other.rule && threshold == other.threshold &&
        revisions == other.revisions && days == other.days
    }
  }

  struct Episode: Codable, Equatable, Identifiable {
    var id = UUID()
    var version = UUID()
    let first: Evidence
    var latest: Evidence
    var closed = false
    var completed = false
    var snoozedUntil: Date?
    var deliveredAt: Date?
  }

  struct Ledger: Codable, Equatable {
    var preferences = Preferences()
    var episodes: [Episode] = []

    mutating func reconcile(current: [GalaxySSIHealthReading], allowed: Bool, now: Date, calendar: Calendar) {
      let active = episodes.firstIndex { !$0.closed }
      guard preferences.enabled, allowed,
            let evidence = GalaxySSIHealthSleepReminder.evidence(current, at: now, calendar: calendar,
                                                               threshold: preferences.threshold)
      else {
        if let active { close(active) }
        return
      }
      if let active {
        if episodes[active].latest.matches(evidence) { return }
        if preferences.merge || episodes[active].latest.day == evidence.day {
          episodes[active].latest = evidence
          episodes[active].version = UUID()
          return
        }
        close(active)
      }
      if let prior = episodes.first, prior.first.day == evidence.day { return }
      if !preferences.merge, let prior = episodes.first,
         let next = calendar.date(byAdding: .day, value: 7, to: prior.first.day), evidence.day < next { return }
      episodes.insert(.init(first: evidence, latest: evidence), at: 0)
      episodes = Array(episodes.prefix(30))
    }

    mutating func close(_ index: Int) {
      episodes[index].closed = true
      episodes[index].version = UUID()
    }
  }

  static func evidence(_ current: [GalaxySSIHealthReading], at now: Date, calendar: Calendar,
                       threshold: Int) -> Evidence? {
    let today = calendar.startOfDay(for: now)
    let dates = (1...21).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    guard dates.count == 21, let start = dates.first else { return nil }
    let usable = sleepReadings(current, in: DateInterval(start: start, end: today))
    let grouped = Dictionary(grouping: usable) { calendar.startOfDay(for: $0.measuredAt) }
    let days = dates.map { date in
      let values = (grouped[date] ?? []).compactMap { reading in
        reading.value.map { reading.unit == "h" ? $0 * 60 : $0 }
      }
      return Day(date: date, minutes: mean(values))
    }
    let baseline = days.prefix(14).compactMap(\.minutes), recent = days.suffix(7).compactMap(\.minutes)
    guard baseline.count >= 10, recent.count >= 5, let before = mean(baseline), let after = mean(recent),
          before - after >= Decimal(threshold) else { return nil }
    return Evidence(day: today, calculatedAt: now, zone: calendar.timeZone.identifier, rule: ruleVersion,
      threshold: threshold, revisions: usable.map { "\($0.id):\($0.revision)" }.sorted(), days: days,
      baselineMean: before, currentMean: after)
  }

  private static func sleepReadings(_ current: [GalaxySSIHealthReading], in interval: DateInterval) -> [GalaxySSIHealthReading] {
    current.filter {
      !$0.deleted && $0.metric == .sleepDuration && $0.measuredAt >= interval.start &&
        $0.measuredAt < interval.end && ($0.unit == "h" || $0.unit == "min") && $0.isValid
    }
  }

  private static func mean(_ values: [Decimal]) -> Decimal? {
    guard !values.isEmpty else { return nil }
    let result = values.reduce(Decimal.zero, +) / Decimal(values.count)
    return result.isNaN ? nil : result
  }
}
