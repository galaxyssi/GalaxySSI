import Foundation

struct GalaxySSIHealthMeasurementPeriod: Hashable, Identifiable, Sendable {
  enum Kind: String, CaseIterable, Sendable { case week = "WEEK", month = "MONTH" }
  let kind: Kind
  let first: String
  var id: String { kind.rawValue + ":" + first }

  init(kind: Kind, on date: Date, zone: TimeZone) throws {
    guard date.timeIntervalSinceReferenceDate.isFinite else { throw GalaxySSIHealthRecords.Failure.invalid }
    let calendar = Self.calendar(zone)
    guard let start = calendar.dateInterval(of: kind == .week ? .weekOfYear : .month, for: date)?.start else {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    let key = GalaxySSIHealthActivityComparison.dayKey(start, zone: zone)
    guard key >= (kind == .week ? "1969-12-29" : "1970-01-01") else { throw GalaxySSIHealthRecords.Failure.invalid }
    self.kind = kind; first = key
  }
  init(key: String) throws {
    let parts = key.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])),
          GalaxySSIHealthActivityComparison.validDay(String(parts[1])), let zone = TimeZone(secondsFromGMT: 0) else {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    let day = try Self.date(String(parts[1]), zone: zone)
    let period = try Self(kind: kind, on: day, zone: zone)
    guard period.first == String(parts[1]) else { throw GalaxySSIHealthRecords.Failure.invalid }
    self = period
  }
  func interval(zone: TimeZone) throws -> DateInterval {
    let start = try Self.date(first, zone: zone), calendar = Self.calendar(zone)
    guard let end = calendar.date(byAdding: kind == .week ? .day : .month, value: kind == .week ? 7 : 1, to: start) else {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    return DateInterval(start: max(Date(timeIntervalSince1970: 0), start), end: end)
  }
  func firstDate(zone: TimeZone) throws -> Date { try Self.date(first, zone: zone) }
  func previous() throws -> Self {
    let zone = TimeZone(secondsFromGMT: 0)!
    let calendar = Self.calendar(zone)
    let start = try Self.date(first, zone: zone)
    guard let prior = calendar.date(byAdding: .day, value: -1, to: start) else {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    return try Self(kind: kind, on: prior, zone: zone)
  }
  static func calendar(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
    return calendar
  }
  private static func date(_ key: String, zone: TimeZone) throws -> Date {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, let date = calendar(zone).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
      throw GalaxySSIHealthRecords.Failure.invalid
    }
    return date
  }
}

enum GalaxySSIHealthMeasurementPeriods {
  typealias Period = GalaxySSIHealthMeasurementPeriod
  struct Key: Hashable {
    let metric: GalaxySSIHealthMetric
    let unit: String
    let condition: String
    let side: String
    init(_ reading: GalaxySSIHealthReading) {
      metric = reading.metric; unit = reading.unit; condition = reading.normalizedMeasurementCondition; side = reading.normalizedMeasurementSide
    }
  }
  struct Series: Identifiable {
    let key: Key
    var latest: GalaxySSIHealthReading
    var count: Int
    var outsideCount: Int
    var unverifiedMethods: Bool
    var id: Key { key }
  }
  struct Summary {
    let period: Period?
    let series: [Series]
  }
  struct PeriodPage {
    let periods: [Period]
    let next: String?
  }
  struct Cursor: Hashable {
    let measuredAt: Date
    let id: UUID
    init(_ reading: GalaxySSIHealthReading) { measuredAt = reading.measuredAt; id = reading.id }
    func follows(_ reading: GalaxySSIHealthReading) -> Bool {
      (reading.measuredAt, reading.id.uuidString) < (measuredAt, id.uuidString)
    }
  }
  struct RecordPage {
    let readings: [GalaxySSIHealthReading]
    let next: Cursor?
  }

  static func summary(_ readings: [GalaxySSIHealthReading], period: Period?, now: Date,
                      zone: TimeZone, unverified: Set<UUID> = [], compareRanges: Bool = true) throws -> Summary {
    let scope = try eligible(readings, period: period, now: now, zone: zone)
    let rows: [GalaxySSIHealthReading]
    if period == nil {
      var latest: [GalaxySSIHealthMetric: GalaxySSIHealthReading] = [:]
      for reading in scope {
        try Task.checkCancellation()
        if let old = latest[reading.metric], newer(old, than: reading) { continue }
        latest[reading.metric] = reading
      }
      rows = Array(latest.values)
    } else { rows = scope }
    var series: [Key: Series] = [:]
    for reading in rows {
      try Task.checkCancellation()
      let key = Key(reading)
      let outside = compareRanges && GalaxySSIHealthOverviewRange.report(reading)?.outside == true
      let requiresReview = unverified.contains(reading.id) || GalaxySSIHealthMeasurementComparison.unverifiedMethod(reading)
      if var prior = series[key] {
        prior.count += 1; prior.outsideCount += outside ? 1 : 0
        prior.unverifiedMethods = prior.unverifiedMethods || requiresReview
        if newer(reading, than: prior.latest) { prior.latest = reading }
        series[key] = prior
      } else {
        series[key] = .init(key: key, latest: reading, count: 1, outsideCount: outside ? 1 : 0, unverifiedMethods: requiresReview)
      }
    }
    return Summary(period: period, series: orderedKeys(Array(series.keys)).compactMap { series[$0] })
  }

  static func page(_ readings: [GalaxySSIHealthReading], kind: Period.Kind, now: Date, zone: TimeZone,
                   before: String? = nil) throws -> PeriodPage {
    guard now.timeIntervalSinceReferenceDate.isFinite else { throw GalaxySSIHealthRecords.Failure.invalid }
    if let before { _ = try Period(key: kind.rawValue + ":" + before) }
    var unique: [String: Period] = [:]
    for reading in readings {
      try Task.checkCancellation()
      guard reading.metric != .steps, reading.isValid, !reading.deleted, reading.measuredAt <= now,
            reading.measuredAt.timeIntervalSince1970 >= 0,
            let period = try? Period(kind: kind, on: reading.measuredAt, zone: zone),
            before.map({ period.first < $0 }) ?? true else { continue }
      unique[period.first] = period
    }
    let periods = unique.values.sorted { $0.first > $1.first }
    let visible = Array(periods.prefix(12))
    return .init(periods: visible, next: periods.count > 12 ? visible.last?.first : nil)
  }

  static func records(_ readings: [GalaxySSIHealthReading], period: Period?, now: Date, zone: TimeZone,
                      after: Cursor? = nil, abnormal: Bool = false, outsideIDs: Set<UUID> = []) throws -> RecordPage {
    let scope = try eligible(readings, period: period, now: now, zone: zone).sorted { newer($0, than: $1) }
    var rows: [GalaxySSIHealthReading] = []
    for reading in scope {
      try Task.checkCancellation()
      guard after.map({ $0.follows(reading) }) ?? true,
            !abnormal || outsideIDs.contains(reading.id) || GalaxySSIHealthOverviewRange.report(reading)?.outside == true else { continue }
      rows.append(reading)
      if rows.count == 31 { break }
    }
    return .init(readings: Array(rows.prefix(30)), next: rows.count > 30 ? Cursor(rows[29]) : nil)
  }

  static func delta(_ before: Series?, _ after: Series?, component: GalaxySSIHealthTrend.Component = .value) -> Decimal? {
    guard let before, let after, before.key == after.key, !before.unverifiedMethods, !after.unverifiedMethods else { return nil }
    return GalaxySSIHealthMeasurementComparison.delta(before.latest, after.latest, component: component)
  }
  static func highlighted(_ series: Series) -> Bool {
    series.outsideCount > 0 || GalaxySSIHealthOverviewRange.report(series.latest)?.outside == true
  }
  static func orderedKeys(_ keys: [Key]) -> [Key] {
    let order = Dictionary(uniqueKeysWithValues: GalaxySSIHealthMetric.allCases.enumerated().map { ($0.element, $0.offset) })
    return Set(keys).sorted {
      (order[$0.metric] ?? 0, $0.condition, $0.unit, $0.side) < (order[$1.metric] ?? 0, $1.condition, $1.unit, $1.side)
    }
  }
  static func newer(_ a: GalaxySSIHealthReading, than b: GalaxySSIHealthReading) -> Bool {
    (a.measuredAt, a.id.uuidString) > (b.measuredAt, b.id.uuidString)
  }
  private static func eligible(_ readings: [GalaxySSIHealthReading], period: Period?, now: Date,
                               zone: TimeZone) throws -> [GalaxySSIHealthReading] {
    guard now.timeIntervalSinceReferenceDate.isFinite else { throw GalaxySSIHealthRecords.Failure.invalid }
    let interval = try period?.interval(zone: zone)
    var rows: [GalaxySSIHealthReading] = []
    for reading in readings {
      try Task.checkCancellation()
      guard !reading.deleted, reading.isValid, reading.metric != .steps, reading.measuredAt <= now,
            reading.measuredAt.timeIntervalSince1970 >= 0,
            interval.map({ reading.measuredAt >= $0.start && reading.measuredAt < $0.end }) ?? true else { continue }
      rows.append(reading)
    }
    return rows
  }
}
