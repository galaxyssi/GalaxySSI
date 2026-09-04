import Foundation

enum AgentWorkflowStringMatch: String, Codable, CaseIterable, Identifiable {
  case equals = "EQUALS"
  case contains = "CONTAINS"

  var id: String { rawValue }
}

enum AgentWorkflowBatteryComparison: String, Codable, CaseIterable, Identifiable {
  case below = "BELOW"
  case atMost = "AT_MOST"
  case atLeast = "AT_LEAST"
  case above = "ABOVE"

  var id: String { rawValue }
}

enum AgentWorkflowCondition: Codable, Equatable, Identifiable {
  case text(expected: String, match: AgentWorkflowStringMatch, ignoreCase: Bool)
  case packageName(expected: String, match: AgentWorkflowStringMatch, ignoreCase: Bool)
  case deviceCharging(required: Bool)
  case batteryThreshold(percent: Int, comparison: AgentWorkflowBatteryComparison)
  case networkAvailable(required: Bool)
  case timeWindow(startMinuteOfDay: Int, endMinuteOfDay: Int)

  private enum CodingKeys: String, CodingKey {
    case type
    case expected
    case match
    case ignoreCase = "ignore_case"
    case required
    case percent
    case comparison
    case startMinuteOfDay = "start_minute_of_day"
    case endMinuteOfDay = "end_minute_of_day"
  }

  private enum ConditionType: String {
    case text
    case packageName = "package_name"
    case deviceCharging = "device_charging"
    case batteryThreshold = "battery_threshold"
    case networkAvailable = "network_available"
    case timeWindow = "time_window"
  }

  var id: String {
    switch self {
    case let .text(expected, match, ignoreCase):
      return "text|\(expected)|\(match.rawValue)|\(ignoreCase)"
    case let .packageName(expected, match, ignoreCase):
      return "package_name|\(expected)|\(match.rawValue)|\(ignoreCase)"
    case let .deviceCharging(required):
      return "device_charging|\(required)"
    case let .batteryThreshold(percent, comparison):
      return "battery_threshold|\(percent)|\(comparison.rawValue)"
    case let .networkAvailable(required):
      return "network_available|\(required)"
    case let .timeWindow(start, end):
      return "time_window|\(start)|\(end)"
    }
  }

  func validate() throws {
    switch self {
    case let .text(expected, _, _), let .packageName(expected, _, _):
      guard !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw AgentProactiveTaskError.invalid("Workflow condition expected value must not be blank")
      }
    case let .batteryThreshold(percent, _):
      guard (0...100).contains(percent) else {
        throw AgentProactiveTaskError.invalid("Battery threshold must be between 0 and 100")
      }
    case let .timeWindow(start, end):
      guard (0...1_439).contains(start), (0...1_439).contains(end) else {
        throw AgentProactiveTaskError.invalid("Workflow time window must be between 0 and 1439")
      }
    case .deviceCharging, .networkAvailable:
      break
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard let type = ConditionType(rawValue: try container.decode(String.self, forKey: .type)) else {
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unsupported workflow condition type"
      )
    }
    switch type {
    case .text:
      self = .text(
        expected: try container.decode(String.self, forKey: .expected),
        match: try Self.decodeMatch(container, defaultValue: .contains),
        ignoreCase: try container.decodeIfPresent(Bool.self, forKey: .ignoreCase) ?? true
      )
    case .packageName:
      self = .packageName(
        expected: try container.decode(String.self, forKey: .expected),
        match: try Self.decodeMatch(container, defaultValue: .equals),
        ignoreCase: try container.decodeIfPresent(Bool.self, forKey: .ignoreCase) ?? true
      )
    case .deviceCharging:
      self = .deviceCharging(required: try container.decodeIfPresent(Bool.self, forKey: .required) ?? true)
    case .batteryThreshold:
      self = .batteryThreshold(
        percent: try container.decode(Int.self, forKey: .percent),
        comparison: try Self.decodeComparison(container)
      )
    case .networkAvailable:
      self = .networkAvailable(required: try container.decodeIfPresent(Bool.self, forKey: .required) ?? true)
    case .timeWindow:
      self = .timeWindow(
        startMinuteOfDay: try container.decode(Int.self, forKey: .startMinuteOfDay),
        endMinuteOfDay: try container.decode(Int.self, forKey: .endMinuteOfDay)
      )
    }
    try validate()
  }

  func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .text(expected, match, ignoreCase):
      try container.encode(ConditionType.text.rawValue, forKey: .type)
      try container.encode(expected, forKey: .expected)
      try container.encode(match, forKey: .match)
      try container.encode(ignoreCase, forKey: .ignoreCase)
    case let .packageName(expected, match, ignoreCase):
      try container.encode(ConditionType.packageName.rawValue, forKey: .type)
      try container.encode(expected, forKey: .expected)
      try container.encode(match, forKey: .match)
      try container.encode(ignoreCase, forKey: .ignoreCase)
    case let .deviceCharging(required):
      try container.encode(ConditionType.deviceCharging.rawValue, forKey: .type)
      try container.encode(required, forKey: .required)
    case let .batteryThreshold(percent, comparison):
      try container.encode(ConditionType.batteryThreshold.rawValue, forKey: .type)
      try container.encode(percent, forKey: .percent)
      try container.encode(comparison, forKey: .comparison)
    case let .networkAvailable(required):
      try container.encode(ConditionType.networkAvailable.rawValue, forKey: .type)
      try container.encode(required, forKey: .required)
    case let .timeWindow(start, end):
      try container.encode(ConditionType.timeWindow.rawValue, forKey: .type)
      try container.encode(start, forKey: .startMinuteOfDay)
      try container.encode(end, forKey: .endMinuteOfDay)
    }
  }

  private static func decodeMatch(
    _ container: KeyedDecodingContainer<CodingKeys>,
    defaultValue: AgentWorkflowStringMatch
  ) throws -> AgentWorkflowStringMatch {
    guard let raw = try container.decodeIfPresent(String.self, forKey: .match) else {
      return defaultValue
    }
    guard let match = AgentWorkflowStringMatch(rawValue: raw) else {
      throw DecodingError.dataCorruptedError(
        forKey: .match,
        in: container,
        debugDescription: "Unsupported workflow string match"
      )
    }
    return match
  }

  private static func decodeComparison(
    _ container: KeyedDecodingContainer<CodingKeys>
  ) throws -> AgentWorkflowBatteryComparison {
    let raw = try container.decode(String.self, forKey: .comparison)
    guard let comparison = AgentWorkflowBatteryComparison(rawValue: raw) else {
      throw DecodingError.dataCorruptedError(
        forKey: .comparison,
        in: container,
        debugDescription: "Unsupported battery comparison"
      )
    }
    return comparison
  }
}

struct AgentWorkflowConditionSnapshot: Equatable {
  var text: String?
  var packageName: String?
  var isDeviceCharging: Bool?
  var batteryPercent: Int?
  var isNetworkAvailable: Bool?
  var minuteOfDay: Int?

  init(
    text: String? = nil,
    packageName: String? = nil,
    isDeviceCharging: Bool? = nil,
    batteryPercent: Int? = nil,
    isNetworkAvailable: Bool? = nil,
    minuteOfDay: Int? = nil
  ) {
    self.text = text
    self.packageName = packageName
    self.isDeviceCharging = isDeviceCharging
    self.batteryPercent = batteryPercent.map { min(max($0, 0), 100) }
    self.isNetworkAvailable = isNetworkAvailable
    self.minuteOfDay = minuteOfDay.map { min(max($0, 0), 1_439) }
  }
}

enum AgentWorkflowConditionEvaluator {
  static func evaluate(
    _ condition: AgentWorkflowCondition,
    snapshot: AgentWorkflowConditionSnapshot
  ) -> Bool {
    switch condition {
    case let .text(expected, match, ignoreCase):
      return matchesString(snapshot.text, expected: expected, match: match, ignoreCase: ignoreCase)
    case let .packageName(expected, match, ignoreCase):
      return matchesString(snapshot.packageName, expected: expected, match: match, ignoreCase: ignoreCase)
    case let .deviceCharging(required):
      return snapshot.isDeviceCharging == required
    case let .batteryThreshold(percent, comparison):
      guard let battery = snapshot.batteryPercent else { return false }
      switch comparison {
      case .below: return battery < percent
      case .atMost: return battery <= percent
      case .atLeast: return battery >= percent
      case .above: return battery > percent
      }
    case let .networkAvailable(required):
      return snapshot.isNetworkAvailable == required
    case let .timeWindow(start, end):
      guard let minute = snapshot.minuteOfDay else { return false }
      if start == end { return true }
      if start < end { return (start..<end).contains(minute) }
      return minute >= start || minute < end
    }
  }

  static func evaluateAll(
    _ conditions: [AgentWorkflowCondition],
    snapshot: AgentWorkflowConditionSnapshot
  ) -> Bool {
    conditions.allSatisfy { evaluate($0, snapshot: snapshot) }
  }

  static func evaluateAny(
    _ conditions: [AgentWorkflowCondition],
    snapshot: AgentWorkflowConditionSnapshot
  ) -> Bool {
    conditions.contains { evaluate($0, snapshot: snapshot) }
  }

  private static func matchesString(
    _ actual: String?,
    expected: String,
    match: AgentWorkflowStringMatch,
    ignoreCase: Bool
  ) -> Bool {
    guard let actual else { return false }
    switch match {
    case .equals:
      return ignoreCase
        ? actual.caseInsensitiveCompare(expected) == .orderedSame
        : actual == expected
    case .contains:
      return actual.range(of: expected, options: ignoreCase ? [.caseInsensitive] : []) != nil
    }
  }
}
