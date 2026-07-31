import Foundation

enum AgentCronExpressionError: LocalizedError, Equatable {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let detail):
      return detail
    }
  }
}

struct AgentCronExpression: Equatable {
  let expression: String
  private let minute: Field
  private let hour: Field
  private let day: Field
  private let month: Field
  private let weekday: Field

  func matches(date: Date, timeZone: TimeZone) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
    let cronWeekday = ((components.weekday ?? 1) - 1) % 7
    let dayMatches = day.values.contains(components.day ?? -1)
    let weekdayMatches = weekday.values.contains(cronWeekday)
    let calendarMatches: Bool
    if day.wildcard && weekday.wildcard {
      calendarMatches = true
    } else if day.wildcard {
      calendarMatches = weekdayMatches
    } else if weekday.wildcard {
      calendarMatches = dayMatches
    } else {
      calendarMatches = dayMatches || weekdayMatches
    }
    return minute.values.contains(components.minute ?? -1) &&
      hour.values.contains(components.hour ?? -1) &&
      month.values.contains(components.month ?? -1) &&
      calendarMatches
  }

  func nextAfter(timestampMillis: Int64, timeZoneIdentifier: String) throws -> Int64 {
    let timeZone = try Self.parseZone(timeZoneIdentifier)
    var candidate = floorToMinute(timestampMillis: timestampMillis, timeZone: timeZone, minuteOffset: 1)
    for _ in 0..<Self.maxScanMinutes {
      if matches(date: candidate, timeZone: timeZone) {
        return Self.millis(candidate)
      }
      candidate = candidate.addingTimeInterval(60)
    }
    throw AgentCronExpressionError.invalid("Cron has no occurrence within six years")
  }

  func previousAtOrBefore(timestampMillis: Int64, timeZoneIdentifier: String) throws -> Int64 {
    let timeZone = try Self.parseZone(timeZoneIdentifier)
    var candidate = floorToMinute(timestampMillis: timestampMillis, timeZone: timeZone, minuteOffset: 0)
    for _ in 0..<Self.maxScanMinutes {
      if matches(date: candidate, timeZone: timeZone) {
        return Self.millis(candidate)
      }
      candidate = candidate.addingTimeInterval(-60)
    }
    throw AgentCronExpressionError.invalid("Cron has no occurrence within six years")
  }

  static func parse(_ expression: String) throws -> AgentCronExpression {
    let parts = expression
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
    guard parts.count == 5 else {
      throw AgentCronExpressionError.invalid("Cron requires five fields")
    }
    return AgentCronExpression(
      expression: parts.joined(separator: " "),
      minute: try parseField(parts[0], minimum: 0, maximum: 59),
      hour: try parseField(parts[1], minimum: 0, maximum: 23),
      day: try parseField(parts[2], minimum: 1, maximum: 31),
      month: try parseField(parts[3], minimum: 1, maximum: 12, aliases: monthNames),
      weekday: try parseField(parts[4], minimum: 0, maximum: 6, aliases: weekdayNames, sundayAlias: true)
    )
  }

  static func parseZone(_ timeZoneIdentifier: String) throws -> TimeZone {
    let clean = timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    let identifier = clean.isEmpty ? "UTC" : clean
    guard let zone = TimeZone(identifier: identifier) else {
      throw AgentCronExpressionError.invalid("Unknown time zone: \(timeZoneIdentifier)")
    }
    return zone
  }

  private func floorToMinute(timestampMillis: Int64, timeZone: TimeZone, minuteOffset: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let date = Date(timeIntervalSince1970: Double(timestampMillis) / 1_000)
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    components.second = 0
    components.nanosecond = 0
    let floored = calendar.date(from: components) ?? date
    return calendar.date(byAdding: .minute, value: minuteOffset, to: floored) ?? floored.addingTimeInterval(Double(minuteOffset) * 60)
  }

  private static func parseField(
    _ text: String,
    minimum: Int,
    maximum: Int,
    aliases: [String: Int] = [:],
    sundayAlias: Bool = false
  ) throws -> Field {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !clean.isEmpty else {
      throw AgentCronExpressionError.invalid("Cron field is blank")
    }
    var output = Set<Int>()
    for clause in clean.split(separator: ",", omittingEmptySubsequences: false).map(String.init) {
      let parts = clause.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
      let base = parts[0]
      let step: Int
      if parts.count == 2 {
        guard let value = Int(parts[1]) else {
          throw AgentCronExpressionError.invalid("Invalid cron step")
        }
        step = value
      } else {
        step = 1
      }
      guard step > 0 else {
        throw AgentCronExpressionError.invalid("Cron step must be positive")
      }
      let range: ClosedRange<Int>
      if base == "*" {
        range = minimum...maximum
      } else if base.contains("-") {
        let edges = base.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard edges.count == 2 else {
          throw AgentCronExpressionError.invalid("Invalid cron range")
        }
        let lower = try numeric(edges[0], aliases: aliases, sundayAlias: sundayAlias)
        let upper = try numeric(edges[1], aliases: aliases, sundayAlias: sundayAlias)
        guard upper >= lower else {
          throw AgentCronExpressionError.invalid("Cron ranges cannot wrap")
        }
        range = lower...upper
      } else {
        let value = try numeric(base, aliases: aliases, sundayAlias: sundayAlias)
        range = value...value
      }
      guard range.lowerBound >= minimum && range.upperBound <= maximum else {
        throw AgentCronExpressionError.invalid("Cron value is outside \(minimum)..\(maximum)")
      }
      for value in stride(from: range.lowerBound, through: range.upperBound, by: step) {
        output.insert(value)
      }
    }
    guard !output.isEmpty else {
      throw AgentCronExpressionError.invalid("Cron field has no values")
    }
    return Field(values: output, wildcard: clean == "*")
  }

  private static func numeric(
    _ raw: String,
    aliases: [String: Int],
    sundayAlias: Bool
  ) throws -> Int {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let alias = aliases[clean] {
      return alias
    }
    guard let value = Int(clean) else {
      throw AgentCronExpressionError.invalid("Invalid cron token: \(raw)")
    }
    return sundayAlias && value == 7 ? 0 : value
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private struct Field: Equatable {
    var values: Set<Int>
    var wildcard: Bool
  }

  private static let maxScanMinutes = 3_200_000
  private static let monthNames = [
    "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
    "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
  ]
  private static let weekdayNames = [
    "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6
  ]
}
