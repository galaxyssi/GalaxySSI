import Foundation

enum GalaxySSIHealthActivityKind: Int, CaseIterable, Codable, Sendable {
  case steps, cycling
  var maximum: Int64 { self == .steps ? Int64(Int32.max) : 172_800_000 }
}

struct GalaxySSIHealthActivityDay: Equatable, Sendable {
  let kind: GalaxySSIHealthActivityKind
  let day: String
  let total: Int64
}

struct GalaxySSIHealthActivityComparison {
  struct Pair: Identifiable {
    let id: Int
    let day: Date
    let previousDay: Date
    let current: Int64?
    let previous: Int64?
  }
  let pairs: [Pair]
  var coverage: Int { pairs.filter { $0.current != nil }.count }
  var paired: [Pair] { pairs.filter { $0.current != nil && $0.previous != nil } }
  var currentTotal: Int64 { pairs.compactMap(\.current).reduce(0, +) }
  var currentPaired: Int64 { paired.compactMap(\.current).reduce(0, +) }
  var previousPaired: Int64 { paired.compactMap(\.previous).reduce(0, +) }
  var changePercent: Double? {
    previousPaired > 0 ? Double(currentPaired - previousPaired) * 100 / Double(previousPaired) : nil
  }

  static func dayKey(_ date: Date, zone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static func validDay(_ key: String) -> Bool {
    utcDate(key) != nil
  }

  static func rangeSize(first: String, last: String) -> Int? {
    guard let start = utcDate(first), let end = utcDate(last), let zone = TimeZone(secondsFromGMT: 0) else { return nil }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    return calendar.dateComponents([.day], from: start, to: end).day.map { $0 + 1 }
  }

  private static func utcDate(_ key: String) -> Date? {
    guard key.utf8.count == 10 else { return nil }
    let parts = key.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
          let year = Int(parts[0]), (1...9999).contains(year), let month = Int(parts[1]), let day = Int(parts[2]),
          let zone = TimeZone(secondsFromGMT: 0) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
          dayKey(date, zone: zone) == key else { return nil }
    return date
  }

  init(first: Date, last: Date, now: Date, calendar supplied: Calendar,
       rows: [GalaxySSIHealthActivityDay], kind: GalaxySSIHealthActivityKind) throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = supplied.timeZone
    guard first.timeIntervalSinceReferenceDate.isFinite, last.timeIntervalSinceReferenceDate.isFinite,
          now.timeIntervalSinceReferenceDate.isFinite else { throw GalaxySSIHealthRecords.Failure.invalid }
    let start = calendar.startOfDay(for: first), end = calendar.startOfDay(for: last)
    guard let count = calendar.dateComponents([.day], from: start, to: end).day.map({ $0 + 1 }),
          (1...366).contains(count), end < calendar.startOfDay(for: now),
          let previousStart = calendar.date(byAdding: .day, value: -count, to: start) else {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    var totals: [String: Int64] = [:]
    for row in rows where row.kind == kind {
      guard Self.validDay(row.day), (0...kind.maximum).contains(row.total) else { throw GalaxySSIHealthRecords.Failure.invalid }
      totals[row.day] = max(totals[row.day] ?? 0, row.total)
    }
    pairs = try (0..<count).map { index in
      guard let day = calendar.date(byAdding: .day, value: index, to: start),
            let prior = calendar.date(byAdding: .day, value: index, to: previousStart) else {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      return Pair(id: index, day: day, previousDay: prior,
        current: totals[Self.dayKey(day, zone: calendar.timeZone)],
        previous: totals[Self.dayKey(prior, zone: calendar.timeZone)])
    }
  }

  static func checkpoints(_ state: GalaxySSIHealthMotion.State) -> [GalaxySSIHealthActivityDay] {
    var rows: [GalaxySSIHealthActivityDay] = []
    if let steps = state.steps, let zone = TimeZone(identifier: steps.zone),
       steps.sampledThrough != nil || steps.total > 0 {
      rows.append(.init(kind: .steps, day: dayKey(steps.day, zone: zone), total: Int64(steps.total)))
    }
    var cycling = state.cycling
    if let through = cycling.confirmedThrough, let zone = TimeZone(identifier: cycling.zone) {
      var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
      cycling.settle(now: through, calendar: calendar)
    }
    for day in state.cycling.days + cycling.days {
      guard let zone = TimeZone(identifier: day.zone), day.seconds.isFinite,
            (0...172_800).contains(day.seconds) else { continue }
      rows.append(.init(kind: .cycling, day: dayKey(day.start, zone: zone), total: Int64(day.seconds * 1_000)))
    }
    return rows
  }
}
