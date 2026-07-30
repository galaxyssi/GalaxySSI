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
  case powerSave = "POWER_SAVE"
  case criticalBattery = "CRITICAL_BATTERY"
  case lowBattery = "LOW_BATTERY"
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
  static let criticalBatteryPercent = 14
  static let lowBatteryPercent = 24
  static let powerSaveRetryMillis: Int64 = 30 * 60 * 1_000
  static let criticalBatteryRetryMillis: Int64 = 60 * 60 * 1_000
  static let lowBatteryReasoningRetryMillis: Int64 = 20 * 60 * 1_000
  static let lowBatteryResearchRetryMillis: Int64 = 45 * 60 * 1_000
  static let networkRecoveryRetryMillis: Int64 = 10 * 60 * 1_000
  static let meteredNetworkRetryMillis: Int64 = 60 * 60 * 1_000

  static func decide(
    kind: GlobalBackgroundWorkKind,
    environment: AgentTaskBudgetEnvironment,
    settings: GlobalAgentSettings,
    nowMillis: Int64,
    explicitUserOverride: Bool = false
  ) -> GlobalBackgroundExecutionDecision {
    if explicitUserOverride {
      return allowed(nowMillis)
    }
    if settings.protectBatteryForBackgroundWork {
      if environment.powerSaveMode {
        return deferred(nowMillis, powerSaveRetryMillis, .powerSave)
      }
      if !environment.charging && (0...criticalBatteryPercent).contains(environment.batteryPercent) {
        return deferred(nowMillis, criticalBatteryRetryMillis, .criticalBattery)
      }
      if !environment.charging &&
        ((criticalBatteryPercent + 1)...lowBatteryPercent).contains(environment.batteryPercent) {
        let retry = kind == .research ? lowBatteryResearchRetryMillis : lowBatteryReasoningRetryMillis
        return deferred(nowMillis, retry, .lowBattery)
      }
    }
    if kind == .research {
      if !environment.networkAvailable {
        return deferred(nowMillis, networkRecoveryRetryMillis, .networkUnavailable)
      }
      if !environment.networkValidated {
        return deferred(nowMillis, networkRecoveryRetryMillis, .networkUnvalidated)
      }
      if environment.networkMetered && !settings.allowMeteredBackgroundResearch {
        return deferred(nowMillis, meteredNetworkRetryMillis, .meteredNetwork)
      }
    }
    return allowed(nowMillis)
  }

  private static func allowed(_ nowMillis: Int64) -> GlobalBackgroundExecutionDecision {
    GlobalBackgroundExecutionDecision(allowed: true, nextEligibleAtMillis: nowMillis)
  }

  private static func deferred(
    _ nowMillis: Int64,
    _ retryMillis: Int64,
    _ reason: GlobalBackgroundDeferralReason
  ) -> GlobalBackgroundExecutionDecision {
    GlobalBackgroundExecutionDecision(
      allowed: false,
      nextEligibleAtMillis: nowMillis + retryMillis,
      reason: reason
    )
  }
}
