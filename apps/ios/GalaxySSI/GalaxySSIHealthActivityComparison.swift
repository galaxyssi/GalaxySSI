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

struct GalaxySSIHealthActivityComparison: Equatable, Sendable {
  struct Pair: Identifiable, Equatable, Sendable {
    let id: Int
    let day: Date
    let current: Int64?
  }
  private(set) var pairs: [Pair]
  var coverage: Int { pairs.filter { $0.current != nil }.count }
  var currentTotal: Int64 { pairs.compactMap(\.current).reduce(0, +) }
  func dateTickIndices(limit: Int) -> [Int] {
    let count = min(max(2, min(7, limit)), pairs.count)
    guard count > 1 else { return Array(pairs.indices) }
    return (0..<count).map { $0 * (pairs.count - 1) / (count - 1) }
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
          (1...366).contains(count), end <= calendar.startOfDay(for: now) else {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    var totals: [String: Int64] = [:]
    for row in rows where row.kind == kind {
      guard Self.validDay(row.day), (0...kind.maximum).contains(row.total) else { throw GalaxySSIHealthRecords.Failure.invalid }
      totals[row.day] = max(totals[row.day] ?? 0, row.total)
    }
    pairs = try (0..<count).map { index in
      guard let day = calendar.date(byAdding: .day, value: index, to: start) else {
        throw GalaxySSIHealthRecords.Failure.invalid
      }
      return Pair(id: index, day: day, current: totals[Self.dayKey(day, zone: calendar.timeZone)])
    }
  }

  static func trailing(days: Int, now: Date, calendar supplied: Calendar) throws -> ClosedRange<Date> {
    guard (1...366).contains(days), now.timeIntervalSinceReferenceDate.isFinite else { throw GalaxySSIHealthRecords.Failure.invalid }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = supplied.timeZone
    let end = calendar.startOfDay(for: now)
    guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { throw GalaxySSIHealthRecords.Failure.invalid }
    return start...end
  }

  func withDay(_ row: GalaxySSIHealthActivityDay?, kind: GalaxySSIHealthActivityKind, zone: TimeZone) throws -> Self {
    guard let row, row.kind == kind else { return self }
    guard Self.validDay(row.day), (0...kind.maximum).contains(row.total) else { throw GalaxySSIHealthRecords.Failure.invalid }
    guard let index = pairs.firstIndex(where: { Self.dayKey($0.day, zone: zone) == row.day }) else { return self }
    var result = self
    let pair = pairs[index]
    result.pairs[index] = Pair(id: pair.id, day: pair.day, current: max(pair.current ?? 0, row.total))
    return result
  }

  // Display-only projection: an active ride never becomes a permanent history row here.
  static func today(_ state: GalaxySSIHealthMotion.State?, kind: GalaxySSIHealthActivityKind,
                    now: Date, calendar: Calendar) -> GalaxySSIHealthActivityDay? {
    guard let state, now.timeIntervalSinceReferenceDate.isFinite else { return nil }
    let key = dayKey(now, zone: calendar.timeZone)
    switch kind {
    case .steps:
      guard let steps = state.steps, steps.sampledThrough != nil || steps.total > 0,
            steps.sampledThrough.map({ $0 <= now }) != false,
            let total = steps.today(now, calendar: calendar), (0...GalaxySSIHealthMotion.maximumSteps).contains(total) else { return nil }
      return .init(kind: kind, day: key, total: Int64(total))
    case .cycling:
      let cycling = state.cycling
      let saved = cycling.days.first { $0.start == calendar.startOfDay(for: now) && $0.zone == calendar.timeZone.identifier }
      let sameZone = cycling.zone == calendar.timeZone.identifier
      let seconds = sameZone ? cycling.today(now, calendar: calendar) : saved?.seconds ?? 0
      guard seconds.isFinite, seconds >= 0, seconds <= Double(kind.maximum) / 1000,
            saved != nil || seconds > 0 || (sameZone && state.cyclingEnabled != nil) else { return nil }
      return .init(kind: kind, day: key, total: Int64(seconds * 1000))
    }
  }

  static func checkpoints(_ state: GalaxySSIHealthMotion.State) -> [GalaxySSIHealthActivityDay] {
    var rows: [GalaxySSIHealthActivityDay] = []
    if let steps = state.steps, let zone = TimeZone(identifier: steps.zone),
       steps.sampledThrough != nil || steps.total > 0 {
      rows.append(.init(kind: .steps, day: dayKey(steps.day, zone: zone), total: Int64(steps.total)))
    }
    for day in state.cycling.days {
      guard let zone = TimeZone(identifier: day.zone), day.seconds.isFinite,
            (0...172_800).contains(day.seconds) else { continue }
      rows.append(.init(kind: .cycling, day: dayKey(day.start, zone: zone), total: Int64(day.seconds * 1_000)))
    }
    return rows
  }
}
