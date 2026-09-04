import Foundation

enum GlobalBackgroundWorkKind: String, Codable, CaseIterable, Identifiable {
  case cognition = "COGNITION"
  case research = "RESEARCH"
  case autonomousWork = "AUTONOMOUS_WORK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalBackgroundWorkKind {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .cognition
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum GlobalBackgroundDeferralReason: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case networkUnavailable = "NETWORK_UNAVAILABLE"
  case networkUnvalidated = "NETWORK_UNVALIDATED"
  case meteredNetwork = "METERED_NETWORK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalBackgroundDeferralReason {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .none
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct GlobalBackgroundExecutionDecision: Codable, Equatable {
  var allowed: Bool
  var nextEligibleAtMillis: Int64
  var reason: GlobalBackgroundDeferralReason

  init(
    allowed: Bool,
    nextEligibleAtMillis: Int64,
    reason: GlobalBackgroundDeferralReason = .none
  ) {
    self.allowed = allowed
    self.nextEligibleAtMillis = max(0, nextEligibleAtMillis)
    self.reason = reason
  }

  enum CodingKeys: String, CodingKey {
    case allowed
    case nextEligibleAtMillis = "next_eligible_at_millis"
    case reason
  }
}

enum GlobalBackgroundExecutionBudgetPolicy {
  static let networkRecoveryRetryMillis: Int64 = 10 * 60 * 1_000
  static let meteredNetworkRetryMillis: Int64 = 60 * 60 * 1_000

  static func decide(
    kind: GlobalBackgroundWorkKind,
    environment: AgentTaskBudgetEnvironment,
    settings: GlobalAgentSettings,
    nowMillis: Int64,
    explicitUserOverride: Bool = false
  ) -> GlobalBackgroundExecutionDecision {
    // Scheduling is independent of battery and network state. Individual tools
    // report unavailable resources and durable work resumes from its checkpoint.
    return allowed(nowMillis)
  }

  private static func allowed(_ nowMillis: Int64) -> GlobalBackgroundExecutionDecision {
    GlobalBackgroundExecutionDecision(allowed: true, nextEligibleAtMillis: nowMillis)
  }

}
