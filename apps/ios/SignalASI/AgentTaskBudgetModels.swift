import Foundation

enum AgentTaskBudgetProfile: String, Codable, CaseIterable, Identifiable {
  case adaptive
  case fast
  case economy
  case privateMode = "private"
  case custom

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentTaskBudgetProfile {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == candidate } ?? .adaptive
  }

  var displayName: String {
    switch self {
    case .adaptive: return "Adaptive"
    case .fast: return "Fast"
    case .economy: return "Economy"
    case .privateMode: return "Private"
    case .custom: return "Custom"
    }
  }

  var detail: String {
    switch self {
    case .adaptive:
      return "Resource usage is recorded for telemetry without stopping the task."
    case .fast:
      return "Run without time, token, memory, or network byte cutoffs."
    case .economy:
      return "Keep resource usage visible while preserving task completion."
    case .privateMode:
      return "Use phone, private, and trusted paired resources only."
    case .custom:
      return "Use the limits configured below."
    }
  }
}

enum AgentTaskNetworkPolicy: String, Codable, CaseIterable, Identifiable {
  case any
  case unmeteredOnly = "unmetered_only"
  case trustedOnly = "trusted_only"
  case offlineOnly = "offline_only"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentTaskNetworkPolicy {
    let candidate = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == candidate } ?? .any
  }

  var displayName: String {
    switch self {
    case .any: return "Any Available Network"
    case .unmeteredOnly: return "Unmetered Only"
    case .trustedOnly: return "Trusted and Private Only"
    case .offlineOnly: return "Offline Only"
    }
  }
}

struct AgentTaskBudget: Codable, Equatable {
  static let mib: Int64 = 1_048_576
  static let gib: Int64 = 1_073_741_824
  static let maximumElapsedSeconds: Int64 = 7 * 24 * 60 * 60
  static let maximumCostMicros: Int64 = 1_000_000_000
  static let maximumTokens: Int64 = 10_000_000
  static let maximumNetworkBytes: Int64 = 10 * gib
  static let maximumMemoryBytes: Int64 = 16 * gib

  var profile: AgentTaskBudgetProfile
  var maxElapsedSeconds: Int64
  var maxCostMicros: Int64
  var maxInputTokens: Int64
  var maxOutputTokens: Int64
  var maxNetworkBytes: Int64
  var minimumBatteryPercent: Int
  var maxMemoryBytes: Int64
  var networkPolicy: AgentTaskNetworkPolicy
  var allowCloud: Bool
  var allowPaidProviders: Bool

  init(
    profile: AgentTaskBudgetProfile = .adaptive,
    maxElapsedSeconds: Int64 = 0,
    maxCostMicros: Int64 = 0,
    maxInputTokens: Int64 = 0,
    maxOutputTokens: Int64 = 0,
    maxNetworkBytes: Int64 = 0,
    minimumBatteryPercent: Int = 0,
    maxMemoryBytes: Int64 = 0,
    networkPolicy: AgentTaskNetworkPolicy = .any,
    allowCloud: Bool = true,
    allowPaidProviders: Bool = true
  ) {
    self.profile = profile
    self.maxElapsedSeconds = maxElapsedSeconds
    self.maxCostMicros = maxCostMicros
    self.maxInputTokens = maxInputTokens
    self.maxOutputTokens = maxOutputTokens
    self.maxNetworkBytes = maxNetworkBytes
    self.minimumBatteryPercent = minimumBatteryPercent
    self.maxMemoryBytes = maxMemoryBytes
    self.networkPolicy = networkPolicy
    self.allowCloud = allowCloud
    self.allowPaidProviders = allowPaidProviders
  }

  static let `default` = AgentTaskBudget.forProfile(.adaptive)

  static func forProfile(_ profile: AgentTaskBudgetProfile) -> AgentTaskBudget {
    switch profile {
    case .adaptive:
      return AgentTaskBudget(profile: profile)
    case .fast:
      return AgentTaskBudget(profile: profile)
    case .economy:
      return AgentTaskBudget(profile: profile)
    case .privateMode:
      return AgentTaskBudget(
        profile: profile,
        networkPolicy: .trustedOnly,
        allowCloud: false,
        allowPaidProviders: false
      )
    case .custom:
      return AgentTaskBudget(profile: .custom)
    }
  }

  var normalized: AgentTaskBudget {
    AgentTaskBudget(
      profile: profile,
      maxElapsedSeconds: max(0, min(maxElapsedSeconds, Self.maximumElapsedSeconds)),
      maxCostMicros: max(0, min(maxCostMicros, Self.maximumCostMicros)),
      maxInputTokens: max(0, min(maxInputTokens, Self.maximumTokens)),
      maxOutputTokens: max(0, min(maxOutputTokens, Self.maximumTokens)),
      maxNetworkBytes: max(0, min(maxNetworkBytes, Self.maximumNetworkBytes)),
      minimumBatteryPercent: max(0, min(minimumBatteryPercent, 100)),
      maxMemoryBytes: max(0, min(maxMemoryBytes, Self.maximumMemoryBytes)),
      networkPolicy: networkPolicy,
      allowCloud: allowCloud,
      allowPaidProviders: allowPaidProviders
    )
  }

  enum CodingKeys: String, CodingKey {
    case version
    case profile
    case maxElapsedSeconds = "max_elapsed_seconds"
    case maxCostMicros = "max_cost_micros"
    case maxInputTokens = "max_input_tokens"
    case maxOutputTokens = "max_output_tokens"
    case maxNetworkBytes = "max_network_bytes"
    case minimumBatteryPercent = "minimum_battery_percent"
    case maxMemoryBytes = "max_memory_bytes"
    case networkPolicy = "network_policy"
    case allowCloud = "allow_cloud"
    case allowPaidProviders = "allow_paid_providers"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let profile = AgentTaskBudgetProfile.fromWireValue(try container.decodeIfPresent(String.self, forKey: .profile))
    let fallback = Self.forProfile(profile)
    self = AgentTaskBudget(
      profile: profile,
      maxElapsedSeconds: try container.decodeIfPresent(Int64.self, forKey: .maxElapsedSeconds) ?? fallback.maxElapsedSeconds,
      maxCostMicros: try container.decodeIfPresent(Int64.self, forKey: .maxCostMicros) ?? fallback.maxCostMicros,
      maxInputTokens: try container.decodeIfPresent(Int64.self, forKey: .maxInputTokens) ?? fallback.maxInputTokens,
      maxOutputTokens: try container.decodeIfPresent(Int64.self, forKey: .maxOutputTokens) ?? fallback.maxOutputTokens,
      maxNetworkBytes: try container.decodeIfPresent(Int64.self, forKey: .maxNetworkBytes) ?? fallback.maxNetworkBytes,
      minimumBatteryPercent: try container.decodeIfPresent(Int.self, forKey: .minimumBatteryPercent) ?? fallback.minimumBatteryPercent,
      maxMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .maxMemoryBytes) ?? fallback.maxMemoryBytes,
      networkPolicy: AgentTaskNetworkPolicy.fromWireValue(
        try container.decodeIfPresent(String.self, forKey: .networkPolicy) ?? fallback.networkPolicy.rawValue
      ),
      allowCloud: try container.decodeIfPresent(Bool.self, forKey: .allowCloud) ?? fallback.allowCloud,
      allowPaidProviders: try container.decodeIfPresent(Bool.self, forKey: .allowPaidProviders) ?? fallback.allowPaidProviders
    ).normalized
  }

  func encode(to encoder: Encoder) throws {
    let value = normalized
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(value.profile.rawValue, forKey: .profile)
    try container.encode(value.maxElapsedSeconds, forKey: .maxElapsedSeconds)
    try container.encode(value.maxCostMicros, forKey: .maxCostMicros)
    try container.encode(value.maxInputTokens, forKey: .maxInputTokens)
    try container.encode(value.maxOutputTokens, forKey: .maxOutputTokens)
    try container.encode(value.maxNetworkBytes, forKey: .maxNetworkBytes)
    try container.encode(value.minimumBatteryPercent, forKey: .minimumBatteryPercent)
    try container.encode(value.maxMemoryBytes, forKey: .maxMemoryBytes)
    try container.encode(value.networkPolicy.rawValue, forKey: .networkPolicy)
    try container.encode(value.allowCloud, forKey: .allowCloud)
    try container.encode(value.allowPaidProviders, forKey: .allowPaidProviders)
  }
}

struct AgentTaskBudgetUsage: Codable, Equatable {
  var elapsedMillis: Int64 = 0
  var inputTokens: Int64 = 0
  var outputTokens: Int64 = 0
  var costMicros: Int64 = 0
  var networkBytes: Int64 = 0
  var peakMemoryBytes: Int64 = 0
  var usageEstimated: Bool = false

  enum CodingKeys: String, CodingKey {
    case elapsedMillis = "elapsed_ms"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case costMicros = "cost_micros"
    case networkBytes = "network_bytes"
    case peakMemoryBytes = "peak_memory_bytes"
    case usageEstimated = "usage_estimated"
  }

  init(
    elapsedMillis: Int64 = 0,
    inputTokens: Int64 = 0,
    outputTokens: Int64 = 0,
    costMicros: Int64 = 0,
    networkBytes: Int64 = 0,
    peakMemoryBytes: Int64 = 0,
    usageEstimated: Bool = false
  ) {
    self.elapsedMillis = max(0, elapsedMillis)
    self.inputTokens = max(0, inputTokens)
    self.outputTokens = max(0, outputTokens)
    self.costMicros = max(0, costMicros)
    self.networkBytes = max(0, networkBytes)
    self.peakMemoryBytes = max(0, peakMemoryBytes)
    self.usageEstimated = usageEstimated
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      elapsedMillis: try container.decodeIfPresent(Int64.self, forKey: .elapsedMillis) ?? 0,
      inputTokens: try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0,
      outputTokens: try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0,
      costMicros: try container.decodeIfPresent(Int64.self, forKey: .costMicros) ?? 0,
      networkBytes: try container.decodeIfPresent(Int64.self, forKey: .networkBytes) ?? 0,
      peakMemoryBytes: try container.decodeIfPresent(Int64.self, forKey: .peakMemoryBytes) ?? 0,
      usageEstimated: try container.decodeIfPresent(Bool.self, forKey: .usageEstimated) ?? false
    )
  }
}

struct AgentTaskBudgetEnvironment: Equatable {
  var batteryPercent: Int = -1
  var charging: Bool = false
  var powerSaveMode: Bool = false
  var networkAvailable: Bool = false
  var networkValidated: Bool = false
  var networkMetered: Bool = false
  var appMemoryBytes: Int64 = 0
  var availableMemoryBytes: Int64 = 0

}

enum AgentTaskBudgetLimit: String, Equatable {
  case time
  case cost
  case inputTokens = "input_tokens"
  case outputTokens = "output_tokens"
  case network
  case battery
  case memory
  case cloud
  case paidProvider = "paid_provider"
}

struct AgentTaskBudgetDecision: Equatable {
  var allowed: Bool
  var limit: AgentTaskBudgetLimit?
  var reason: String

  static let approved = AgentTaskBudgetDecision(allowed: true, limit: nil, reason: "")
}

enum AgentTaskBudgetPolicy {
  static func evaluate(
    budget: AgentTaskBudget,
    usage: AgentTaskBudgetUsage,
    environment: AgentTaskBudgetEnvironment = AgentTaskBudgetEnvironment(),
    networkRequired: Bool = false,
    trustedNetworkTarget: Bool = false,
    cloudProvider: Bool = false,
    paidProvider: Bool = false
  ) -> AgentTaskBudgetDecision {
    let limits = budget.normalized
    // Resource counters are telemetry. Runtime owners handle actual memory,
    // thermal, battery, and connectivity failures without terminating a task.
    if cloudProvider && !limits.allowCloud {
      return denied(.cloud, "Cloud resources are disabled for this task")
    }
    if paidProvider && !limits.allowPaidProviders {
      return denied(.paidProvider, "Paid resources are disabled for this task")
    }
    if networkRequired {
      if !environment.networkAvailable {
        return denied(.network, "Network is unavailable")
      }
      switch limits.networkPolicy {
      case .any:
        break
      case .unmeteredOnly where environment.networkMetered:
        return denied(.network, "Task requires an unmetered network")
      case .trustedOnly where !trustedNetworkTarget:
        return denied(.network, "Task allows trusted network targets only")
      case .offlineOnly:
        return denied(.network, "Task is limited to offline resources")
      default:
        break
      }
    }
    return .approved
  }

  private static func denied(_ limit: AgentTaskBudgetLimit, _ reason: String) -> AgentTaskBudgetDecision {
    AgentTaskBudgetDecision(allowed: false, limit: limit, reason: reason)
  }
}
