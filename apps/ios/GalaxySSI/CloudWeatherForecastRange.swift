import Foundation

struct CloudWeatherForecastRange {
  private static let horizon = 16
  private let offset: Int
  private let days: Int
  private let date: String?

  var providerDays: Int { date == nil ? offset + days : Self.horizon }

  init(arguments: AgentMcpJSONObject) throws {
    let offset = try Self.integer(arguments["day_offset"], default: 0)
    let days = try Self.integer(arguments["days"], default: 1)
    guard (0..<Self.horizon).contains(offset), (1...Self.horizon).contains(days),
          offset + days <= Self.horizon else { throw Failure.horizon }
    var date: String?
    if let supplied = arguments["date"] {
      guard arguments["day_offset"] == nil else { throw Failure.conflictingDate }
      let utc = TimeZone(secondsFromGMT: 0)!
      guard let value = supplied.stringValue, value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#,
        options: .regularExpression) != nil, Self.parse(value, with: Self.formatter(utc)) != nil else {
        throw Failure.invalidDate
      }
      date = value
    }
    self.offset = offset
    self.days = days
    self.date = date
  }

  struct Selection {
    let firstDate: String
    let lastDate: String
    let startsToday: Bool
    let daily: AgentMcpJSONObject
  }

  func select(from daily: AgentMcpJSONObject, timeZone: TimeZone, now: Date) throws -> Selection {
    let formatter = Self.formatter(timeZone)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let today = calendar.startOfDay(for: now)
    let horizon = (0..<Self.horizon).compactMap { offset in
      calendar.date(byAdding: .day, value: offset, to: today).map { formatter.string(from: $0) }
    }
    guard horizon.count == Self.horizon else { throw Failure.horizon }
    let start: Int
    if let date {
      guard let index = horizon.firstIndex(of: date) else { throw Failure.horizon }
      start = index
    } else {
      start = offset
    }
    guard start + days <= Self.horizon else { throw Failure.horizon }
    guard let dates = daily["time"]?.arrayValue, (1...Self.horizon).contains(dates.count),
          dates.allSatisfy({ $0.stringValue != nil }), Set(dates.compactMap(\.stringValue)).count == dates.count else {
      throw Failure.misaligned
    }
    var indices: [Int] = []
    let requestedDates = horizon[start..<(start + days)]
    for expected in requestedDates {
      guard let index = dates.firstIndex(of: .string(expected)) else { throw Failure.missingDate(expected) }
      indices.append(index)
    }
    var selected: AgentMcpJSONObject = [:]
    for (field, raw) in daily {
      guard let values = raw.arrayValue, values.count == dates.count else { throw Failure.misaligned }
      selected[field] = .array(indices.map { values[$0] })
    }
    return Selection(firstDate: horizon[start], lastDate: horizon[start + days - 1],
      startsToday: start == 0, daily: selected)
  }

  private static func integer(_ raw: AgentMcpJSONValue?, default fallback: Int) throws -> Int {
    switch raw {
    case nil: return fallback
    case .int(let number): if let integer = Int(exactly: number) { return integer }
    case .double(let number): if let integer = Int(exactly: number) { return integer }
    default: break
    }
    throw Failure.invalidRange
  }

  private static func formatter(_ timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    return formatter
  }

  private static func parse(_ text: String, with formatter: DateFormatter) -> Date? {
    guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
    return date
  }

  private enum Failure: LocalizedError {
    case invalidRange, conflictingDate, invalidDate, horizon, missingDate(String), misaligned

    var errorDescription: String? {
      switch self {
      case .invalidRange: return "Forecast offsets and range lengths must be whole numbers."
      case .conflictingDate: return "Use either date or day_offset, not both."
      case .invalidDate: return "Use a valid destination-local date in YYYY-MM-DD format."
      case .horizon: return "Requested dates fall outside the next 16 local forecast days."
      case .missingDate(let date): return "The weather provider did not return the requested local date \(date)."
      case .misaligned: return "The weather provider returned misaligned or ambiguous daily values."
      }
    }
  }
}
