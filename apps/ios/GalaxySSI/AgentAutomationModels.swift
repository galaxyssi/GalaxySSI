import CryptoKit
import Foundation

enum AgentConnectorTimeoutStage: String, Codable, CaseIterable, Identifiable {
  case notAccepted = "NOT_ACCEPTED"
  case notRunning = "NOT_RUNNING"
  case readOnlyStale = "READ_ONLY_STALE"

  var id: String { rawValue }
}

struct AgentConnectorTimeoutSchedule: Codable, Equatable {
  var acceptedMs: Int64
  var runningMs: Int64
  var liveStaleMs: Int64

  enum CodingKeys: String, CodingKey {
    case acceptedMs = "accepted_ms"
    case runningMs = "running_ms"
    case liveStaleMs = "live_stale_ms"
  }

  init(acceptedMs: Int64, runningMs: Int64, liveStaleMs: Int64) {
    self.acceptedMs = acceptedMs
    self.runningMs = runningMs
    self.liveStaleMs = liveStaleMs
  }
}

enum AgentFailoverResourceLocation: String, Codable, CaseIterable, Identifiable {
  case phone = "PHONE"
  case trustedDesktop = "TRUSTED_DESKTOP"
  case privateNetwork = "PRIVATE_NETWORK"
  case cloud = "CLOUD"

  var id: String { rawValue }
}

struct AgentFailoverResource: Codable, Equatable {
  var location: AgentFailoverResourceLocation
  var failureDomain: String

  enum CodingKeys: String, CodingKey {
    case location
    case failureDomain = "failure_domain"
  }

  init(location: AgentFailoverResourceLocation, failureDomain: String = "") {
    self.location = location
    self.failureDomain = failureDomain
  }
}

enum AgentFailoverPolicy {
  static func fallbackTier(primary: AgentFailoverResource?, candidate: AgentFailoverResource) -> Int {
    guard let primary = primary, primary.location == .trustedDesktop else {
      return 0
    }
    switch candidate.location {
    case .cloud, .phone:
      return 0
    case .trustedDesktop, .privateNetwork:
      return candidate.failureDomain != primary.failureDomain ? 1 : 2
    }
  }

  static func shouldFailOver(
    stage: AgentConnectorTimeoutStage,
    status: String,
    liveReadOnly: Bool
  ) -> Bool {
    switch stage {
    case .notAccepted:
      return normalizedStatus(status).isEmpty
    case .notRunning:
      return normalizedStatus(status).isEmpty || waitingStatuses.contains(normalizedStatus(status))
    case .readOnlyStale:
      return liveReadOnly && normalizedStatus(status) == "running"
    }
  }

  static func shouldKeepOnlyResourceAlive(
    stage: AgentConnectorTimeoutStage,
    status: String,
    hasFallback: Bool
  ) -> Bool {
    if hasFallback {
      return false
    }
    switch stage {
    case .notAccepted:
      return normalizedStatus(status).isEmpty
    case .notRunning:
      return normalizedStatus(status).isEmpty || waitingStatuses.contains(normalizedStatus(status))
    case .readOnlyStale:
      return false
    }
  }

  static func domainCooldownMs(consecutiveFailures: Int) -> Int64 {
    switch max(consecutiveFailures, 1) {
    case 1:
      return 60_000
    case 2:
      return 5 * 60_000
    case 3:
      return 15 * 60_000
    default:
      return 60 * 60_000
    }
  }

  private static func normalizedStatus(_ status: String) -> String {
    status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static let waitingStatuses: Set<String> = ["accepted", "queued", "starting"]
}

enum AgentConnectorTimingPolicy {
  static func deadlines(hasAttachments: Bool) -> AgentConnectorTimeoutSchedule {
    hasAttachments ? attachment : interactive
  }

  private static let interactive = AgentConnectorTimeoutSchedule(
    acceptedMs: 5_000,
    runningMs: 8_000,
    liveStaleMs: 15_000
  )

  private static let attachment = AgentConnectorTimeoutSchedule(
    acceptedMs: 60_000,
    runningMs: 90_000,
    liveStaleMs: 180_000
  )
}

enum AgentProactiveTaskError: LocalizedError, Equatable {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let message):
      return message
    }
  }
}

private enum AgentProactiveWire {
  static func token(_ value: String?) -> String {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
  }
}

private enum AgentProactiveJSON {
  static func object(_ value: String, label: String) throws -> AgentMcpJSONObject {
    guard let data = value.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      throw AgentProactiveTaskError.invalid("\(label) must be a JSON object")
    }
    return object
  }

  static func objectString(_ value: String, label: String) throws -> String {
    AgentMcpJSONCodec.stringify(try object(value, label: label))
  }

  static func decodedObjectString<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
  ) -> String {
    guard container.contains(key),
      let object = try? container.decode(AgentMcpJSONObject.self, forKey: key) else {
      return "{}"
    }
    return AgentMcpJSONCodec.stringify(object)
  }
}

enum AgentProactiveTriggerKind: String, Codable, CaseIterable, Identifiable {
  case manual = "MANUAL"
  case cron = "CRON"
  case interval = "INTERVAL"
  case goalCheckpoint = "GOAL_CHECKPOINT"
  case webhook = "WEBHOOK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentProactiveTriggerKind {
    let normalized = AgentProactiveWire.token(value)
    return allCases.first { $0.rawValue == normalized } ?? .manual
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

enum AgentProactiveActionKind: String, Codable, CaseIterable, Identifiable {
  case agent = "AGENT"
  case subagentTeam = "SUBAGENT_TEAM"
  case workflow = "WORKFLOW"
  case nativeTool = "NATIVE_TOOL"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentProactiveActionKind {
    let normalized = AgentProactiveWire.token(value)
    return allCases.first { $0.rawValue == normalized } ?? .agent
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

enum AgentProactiveMisfirePolicy: String, Codable, CaseIterable, Identifiable {
  case skip = "SKIP"
  case fireOnce = "FIRE_ONCE"
  case catchUp = "CATCH_UP"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentProactiveMisfirePolicy {
    let normalized = AgentProactiveWire.token(value)
    return allCases.first { $0.rawValue == normalized } ?? .fireOnce
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

enum AgentProactiveRunStatus: String, Codable, CaseIterable, Identifiable {
  case queued = "QUEUED"
  case running = "RUNNING"
  case waiting = "WAITING"
  case retrying = "RETRYING"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case skipped = "SKIPPED"

  var id: String { rawValue }
  var terminal: Bool {
    [.completed, .failed, .cancelled, .skipped].contains(self)
  }

  static func fromWireValue(_ value: String?) -> AgentProactiveRunStatus {
    let normalized = AgentProactiveWire.token(value)
    return allCases.first { $0.rawValue == normalized } ?? .queued
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

enum AgentProactiveTeamRole: String, Codable, CaseIterable, Identifiable {
  case lead = "LEAD"
  case executor = "EXECUTOR"
  case observer = "OBSERVER"
  case verifier = "VERIFIER"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentProactiveTeamRole {
    let normalized = AgentProactiveWire.token(value)
    return allCases.first { $0.rawValue == normalized } ?? .observer
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

struct AgentProactiveTrigger: Codable, Equatable {
  static let minIntervalSeconds: Int64 = 60
  static let maxIntervalSeconds: Int64 = 365 * 24 * 60 * 60

  var kind: AgentProactiveTriggerKind
  var cron: String
  var timeZone: String
  var intervalSeconds: Int64
  var goalId: String
  var webhookId: String
  var eventFilter: [String: String]

  init(
    kind: AgentProactiveTriggerKind,
    cron: String = "",
    timeZone: String = "UTC",
    intervalSeconds: Int64 = 0,
    goalId: String = "",
    webhookId: String = "",
    eventFilter: [String: String] = [:]
  ) throws {
    let cleanTimeZone = timeZone.trimmingCharacters(in: .whitespacesAndNewlines)
    let storedTimeZone = cleanTimeZone.isEmpty ? "UTC" : cleanTimeZone
    _ = try AgentCronExpression.parseZone(storedTimeZone)
    if kind == .cron {
      _ = try AgentCronExpression.parse(cron)
    }
    if [.interval, .goalCheckpoint].contains(kind),
      !(Self.minIntervalSeconds...Self.maxIntervalSeconds).contains(intervalSeconds) {
      throw AgentProactiveTaskError.invalid("Proactive interval must be between 60 seconds and one year")
    }
    if kind == .goalCheckpoint {
      try AgentProactiveTaskScheduler.requireIdentifier(goalId, label: "Goal id")
    }
    if kind == .webhook && !webhookId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try AgentProactiveTaskScheduler.requireIdentifier(webhookId, label: "Webhook id")
    }
    guard eventFilter.count <= 32 else {
      throw AgentProactiveTaskError.invalid("Webhook event filter has too many fields")
    }

    self.kind = kind
    self.cron = cron
    self.timeZone = storedTimeZone
    self.intervalSeconds = intervalSeconds
    self.goalId = goalId
    self.webhookId = webhookId
    self.eventFilter = eventFilter
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case cron
    case timeZone = "time_zone"
    case intervalSeconds = "interval_seconds"
    case goalId = "goal_id"
    case webhookId = "webhook_id"
    case eventFilter = "event_filter"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      kind: try container.decodeIfPresent(AgentProactiveTriggerKind.self, forKey: .kind) ?? .manual,
      cron: try container.decodeIfPresent(String.self, forKey: .cron) ?? "",
      timeZone: try container.decodeIfPresent(String.self, forKey: .timeZone) ?? "UTC",
      intervalSeconds: try container.decodeIfPresent(Int64.self, forKey: .intervalSeconds) ?? 0,
      goalId: try container.decodeIfPresent(String.self, forKey: .goalId) ?? "",
      webhookId: try container.decodeIfPresent(String.self, forKey: .webhookId) ?? "",
      eventFilter: try container.decodeIfPresent([String: String].self, forKey: .eventFilter) ?? [:]
    )
  }
}

struct AgentProactiveTeamMember: Codable, Equatable {
  var agentId: String
  var role: AgentProactiveTeamRole
  var instructions: String

  init(
    agentId: String,
    role: AgentProactiveTeamRole,
    instructions: String = ""
  ) throws {
    let cleanAgentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanAgentId.isEmpty && cleanAgentId.count <= 128 else {
      throw AgentProactiveTaskError.invalid("Team Agent id is invalid")
    }
    guard instructions.count <= 8_192 else {
      throw AgentProactiveTaskError.invalid("Team instructions are too long")
    }
    self.agentId = cleanAgentId
    self.role = role
    self.instructions = instructions
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case role
    case instructions
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      agentId: try container.decodeIfPresent(String.self, forKey: .agentId) ?? "",
      role: try container.decodeIfPresent(AgentProactiveTeamRole.self, forKey: .role) ?? .observer,
      instructions: try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
    )
  }
}

struct AgentProactiveAction: Codable, Equatable {
  var kind: AgentProactiveActionKind
  var targetId: String
  var prompt: String
  var argumentsJson: String
  var team: [AgentProactiveTeamMember]
  var deliveryMode: String
  var contactId: String
  var clientRouteId: String
  var grantedPermissions: Set<String>
  var grantedConsents: Set<String>

  init(
    kind: AgentProactiveActionKind,
    targetId: String = "",
    prompt: String = "",
    argumentsJson: String = "{}",
    team: [AgentProactiveTeamMember] = [],
    deliveryMode: String = "store",
    contactId: String = "system",
    clientRouteId: String = "",
    grantedPermissions: Set<String> = [],
    grantedConsents: Set<String> = []
  ) throws {
    guard prompt.count <= 65_536 else {
      throw AgentProactiveTaskError.invalid("Proactive prompt is too long")
    }
    let canonicalArguments = try AgentProactiveJSON.objectString(
      argumentsJson,
      label: "Proactive native tool arguments"
    )
    let cleanDeliveryMode = deliveryMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "store"
      : deliveryMode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard ["store", "notify", "mobile"].contains(cleanDeliveryMode) else {
      throw AgentProactiveTaskError.invalid("Proactive delivery mode is invalid")
    }
    if kind == .subagentTeam {
      guard !team.isEmpty && team.count <= 12 else {
        throw AgentProactiveTaskError.invalid("Agent team must contain 1 to 12 members")
      }
      guard team.filter({ $0.role == .lead }).count == 1 else {
        throw AgentProactiveTaskError.invalid("Agent team requires exactly one lead")
      }
      guard Set(team.map(\.agentId)).count == team.count else {
        throw AgentProactiveTaskError.invalid("Agent team members must be unique")
      }
    } else {
      let cleanTargetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanTargetId.isEmpty && cleanTargetId.count <= 128 else {
        throw AgentProactiveTaskError.invalid("Proactive action target is invalid")
      }
    }

    self.kind = kind
    self.targetId = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.prompt = prompt
    self.argumentsJson = canonicalArguments
    self.team = team
    self.deliveryMode = cleanDeliveryMode
    self.contactId = contactId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "system"
      : contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.clientRouteId = clientRouteId
    self.grantedPermissions = Set(grantedPermissions.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    self.grantedConsents = Set(grantedConsents.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case targetId = "target_id"
    case prompt
    case argumentsJson = "arguments"
    case team
    case deliveryMode = "delivery_mode"
    case contactId = "contact_id"
    case clientRouteId = "client_route_id"
    case grantedPermissions = "granted_permissions"
    case grantedConsents = "granted_consents"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      kind: try container.decodeIfPresent(AgentProactiveActionKind.self, forKey: .kind) ?? .agent,
      targetId: try container.decodeIfPresent(String.self, forKey: .targetId) ?? "",
      prompt: try container.decodeIfPresent(String.self, forKey: .prompt) ?? "",
      argumentsJson: AgentProactiveJSON.decodedObjectString(from: container, forKey: .argumentsJson),
      team: try container.decodeIfPresent([AgentProactiveTeamMember].self, forKey: .team) ?? [],
      deliveryMode: try container.decodeIfPresent(String.self, forKey: .deliveryMode) ?? "store",
      contactId: try container.decodeIfPresent(String.self, forKey: .contactId) ?? "system",
      clientRouteId: try container.decodeIfPresent(String.self, forKey: .clientRouteId) ?? "",
      grantedPermissions: try container.decodeIfPresent(Set<String>.self, forKey: .grantedPermissions) ?? [],
      grantedConsents: try container.decodeIfPresent(Set<String>.self, forKey: .grantedConsents) ?? []
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(kind, forKey: .kind)
    try container.encode(targetId, forKey: .targetId)
    try container.encode(prompt, forKey: .prompt)
    try container.encode(AgentProactiveJSON.object(argumentsJson, label: "Proactive native tool arguments"), forKey: .argumentsJson)
    try container.encode(team, forKey: .team)
    try container.encode(deliveryMode, forKey: .deliveryMode)
    try container.encode(contactId, forKey: .contactId)
    try container.encode(clientRouteId, forKey: .clientRouteId)
    try container.encode(Array(grantedPermissions).sorted(), forKey: .grantedPermissions)
    try container.encode(Array(grantedConsents).sorted(), forKey: .grantedConsents)
  }
}

struct AgentProactivePolicy: Codable, Equatable {
  var misfire: AgentProactiveMisfirePolicy
  var catchUpLimit: Int
  var jitterSeconds: Int
  var maxAttempts: Int
  var retryBackoffSeconds: Int
  var maxConcurrency: Int
  var maxConsecutiveFailures: Int
  var deadlineAtMillis: Int64
  var maxRuns: Int
  var network: String
  var requiresCharging: Bool

  init(
    misfire: AgentProactiveMisfirePolicy = .fireOnce,
    catchUpLimit: Int = 3,
    jitterSeconds: Int = 0,
    maxAttempts: Int = 3,
    retryBackoffSeconds: Int = 5,
    maxConcurrency: Int = 1,
    maxConsecutiveFailures: Int = 5,
    deadlineAtMillis: Int64 = 0,
    maxRuns: Int = 0,
    network: String = "any",
    requiresCharging: Bool = false
  ) throws {
    guard (1...32).contains(catchUpLimit) else {
      throw AgentProactiveTaskError.invalid("Proactive catch-up limit is invalid")
    }
    guard (0...86_400).contains(jitterSeconds) else {
      throw AgentProactiveTaskError.invalid("Proactive jitter is invalid")
    }
    guard (1...12).contains(maxAttempts) else {
      throw AgentProactiveTaskError.invalid("Proactive max attempts is invalid")
    }
    guard (1...86_400).contains(retryBackoffSeconds) else {
      throw AgentProactiveTaskError.invalid("Proactive retry backoff is invalid")
    }
    guard (1...16).contains(maxConcurrency) else {
      throw AgentProactiveTaskError.invalid("Proactive max concurrency is invalid")
    }
    guard (1...100).contains(maxConsecutiveFailures) else {
      throw AgentProactiveTaskError.invalid("Proactive max consecutive failures is invalid")
    }
    guard deadlineAtMillis >= 0 && maxRuns >= 0 else {
      throw AgentProactiveTaskError.invalid("Proactive policy counters are invalid")
    }
    let cleanNetwork = network.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? "any"
      : network.trimmingCharacters(in: .whitespacesAndNewlines)
    guard ["any", "unmetered", "offline"].contains(cleanNetwork) else {
      throw AgentProactiveTaskError.invalid("Proactive network policy is invalid")
    }

    self.misfire = misfire
    self.catchUpLimit = catchUpLimit
    self.jitterSeconds = jitterSeconds
    self.maxAttempts = maxAttempts
    self.retryBackoffSeconds = retryBackoffSeconds
    self.maxConcurrency = maxConcurrency
    self.maxConsecutiveFailures = maxConsecutiveFailures
    self.deadlineAtMillis = deadlineAtMillis
    self.maxRuns = maxRuns
    self.network = cleanNetwork
    self.requiresCharging = requiresCharging
  }

  enum CodingKeys: String, CodingKey {
    case misfire
    case catchUpLimit = "catch_up_limit"
    case jitterSeconds = "jitter_seconds"
    case maxAttempts = "max_attempts"
    case retryBackoffSeconds = "retry_backoff_seconds"
    case maxConcurrency = "max_concurrency"
    case maxConsecutiveFailures = "max_consecutive_failures"
    case deadlineAtMillis = "deadline_at_millis"
    case maxRuns = "max_runs"
    case network
    case requiresCharging = "requires_charging"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      misfire: try container.decodeIfPresent(AgentProactiveMisfirePolicy.self, forKey: .misfire) ?? .fireOnce,
      catchUpLimit: try container.decodeIfPresent(Int.self, forKey: .catchUpLimit) ?? 3,
      jitterSeconds: try container.decodeIfPresent(Int.self, forKey: .jitterSeconds) ?? 0,
      maxAttempts: try container.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 3,
      retryBackoffSeconds: try container.decodeIfPresent(Int.self, forKey: .retryBackoffSeconds) ?? 5,
      maxConcurrency: try container.decodeIfPresent(Int.self, forKey: .maxConcurrency) ?? 1,
      maxConsecutiveFailures: try container.decodeIfPresent(Int.self, forKey: .maxConsecutiveFailures) ?? 5,
      deadlineAtMillis: try container.decodeIfPresent(Int64.self, forKey: .deadlineAtMillis) ?? 0,
      maxRuns: try container.decodeIfPresent(Int.self, forKey: .maxRuns) ?? 0,
      network: try container.decodeIfPresent(String.self, forKey: .network) ?? "any",
      requiresCharging: try container.decodeIfPresent(Bool.self, forKey: .requiresCharging) ?? false
    )
  }
}

struct AgentProactiveTask: Codable, Equatable, Identifiable {
  var taskId: String
  var name: String
  var trigger: AgentProactiveTrigger
  var action: AgentProactiveAction
  var policy: AgentProactivePolicy
  var enabled: Bool
  var nextRunAtMillis: Int64
  var lastRunAtMillis: Int64
  var lastStatus: AgentProactiveRunStatus
  var runCount: Int
  var consecutiveFailures: Int
  var revision: Int
  var createdAtMillis: Int64
  var updatedAtMillis: Int64

  var id: String { taskId }

  init(
    taskId: String = UUID().uuidString,
    name: String,
    trigger: AgentProactiveTrigger,
    action: AgentProactiveAction,
    policy: AgentProactivePolicy = AgentProactiveTask.defaultPolicy(),
    enabled: Bool = true,
    nextRunAtMillis: Int64 = 0,
    lastRunAtMillis: Int64 = 0,
    lastStatus: AgentProactiveRunStatus = .queued,
    runCount: Int = 0,
    consecutiveFailures: Int = 0,
    revision: Int = 1,
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0
  ) throws {
    try AgentProactiveTaskScheduler.requireIdentifier(taskId, label: "Task id")
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty && cleanName.count <= 120 else {
      throw AgentProactiveTaskError.invalid("Proactive task name is invalid")
    }

    self.taskId = taskId
    self.name = cleanName
    self.trigger = trigger
    self.action = action
    self.policy = policy
    self.enabled = enabled
    self.nextRunAtMillis = max(nextRunAtMillis, 0)
    self.lastRunAtMillis = max(lastRunAtMillis, 0)
    self.lastStatus = lastStatus
    self.runCount = max(runCount, 0)
    self.consecutiveFailures = max(consecutiveFailures, 0)
    self.revision = max(revision, 1)
    self.createdAtMillis = max(createdAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case protocolVersion = "protocol"
    case taskId = "task_id"
    case name
    case trigger
    case action
    case policy
    case enabled
    case nextRunAtMillis = "next_run_at_millis"
    case lastRunAtMillis = "last_run_at_millis"
    case lastStatus = "last_status"
    case runCount = "run_count"
    case consecutiveFailures = "consecutive_failures"
    case revision
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion) ?? ""
    guard protocolVersion == AgentProactiveTaskScheduler.protocolVersion else {
      throw AgentProactiveTaskError.invalid("Unsupported proactive task protocol")
    }
    try self.init(
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
      trigger: try container.decode(AgentProactiveTrigger.self, forKey: .trigger),
      action: try container.decode(AgentProactiveAction.self, forKey: .action),
      policy: try container.decodeIfPresent(AgentProactivePolicy.self, forKey: .policy) ?? AgentProactiveTask.defaultPolicy(),
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
      nextRunAtMillis: try container.decodeIfPresent(Int64.self, forKey: .nextRunAtMillis) ?? 0,
      lastRunAtMillis: try container.decodeIfPresent(Int64.self, forKey: .lastRunAtMillis) ?? 0,
      lastStatus: try container.decodeIfPresent(AgentProactiveRunStatus.self, forKey: .lastStatus) ?? .queued,
      runCount: try container.decodeIfPresent(Int.self, forKey: .runCount) ?? 0,
      consecutiveFailures: try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0,
      revision: try container.decodeIfPresent(Int.self, forKey: .revision) ?? 1,
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(AgentProactiveTaskScheduler.protocolVersion, forKey: .protocolVersion)
    try container.encode(taskId, forKey: .taskId)
    try container.encode(name, forKey: .name)
    try container.encode(trigger, forKey: .trigger)
    try container.encode(action, forKey: .action)
    try container.encode(policy, forKey: .policy)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(nextRunAtMillis, forKey: .nextRunAtMillis)
    try container.encode(lastRunAtMillis, forKey: .lastRunAtMillis)
    try container.encode(lastStatus, forKey: .lastStatus)
    try container.encode(runCount, forKey: .runCount)
    try container.encode(consecutiveFailures, forKey: .consecutiveFailures)
    try container.encode(revision, forKey: .revision)
    try container.encode(createdAtMillis, forKey: .createdAtMillis)
    try container.encode(updatedAtMillis, forKey: .updatedAtMillis)
  }

  static func defaultPolicy() -> AgentProactivePolicy {
    try! AgentProactivePolicy()
  }
}

struct AgentProactiveRun: Codable, Equatable, Identifiable {
  var runId: String
  var taskId: String
  var scheduledForMillis: Int64
  var status: AgentProactiveRunStatus
  var attempt: Int
  var causeJson: String
  var startedAtMillis: Int64
  var completedAtMillis: Int64
  var resultSummary: String
  var errorCode: String
  var linkedExecutionId: String
  var teamRunId: String

  var id: String { runId }

  init(
    runId: String,
    taskId: String,
    scheduledForMillis: Int64,
    status: AgentProactiveRunStatus,
    attempt: Int = 1,
    causeJson: String = "{}",
    startedAtMillis: Int64 = 0,
    completedAtMillis: Int64 = 0,
    resultSummary: String = "",
    errorCode: String = "",
    linkedExecutionId: String = "",
    teamRunId: String = ""
  ) throws {
    self.runId = runId
    self.taskId = taskId
    self.scheduledForMillis = max(scheduledForMillis, 0)
    self.status = status
    self.attempt = max(attempt, 1)
    self.causeJson = try AgentProactiveJSON.objectString(causeJson, label: "Proactive run cause")
    self.startedAtMillis = max(startedAtMillis, 0)
    self.completedAtMillis = max(completedAtMillis, 0)
    self.resultSummary = String(resultSummary.prefix(4_096))
    self.errorCode = String(errorCode.prefix(128))
    self.linkedExecutionId = linkedExecutionId
    self.teamRunId = teamRunId
  }

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case taskId = "task_id"
    case scheduledForMillis = "scheduled_for_millis"
    case status
    case attempt
    case causeJson = "cause"
    case startedAtMillis = "started_at_millis"
    case completedAtMillis = "completed_at_millis"
    case resultSummary = "result_summary"
    case errorCode = "error_code"
    case linkedExecutionId = "linked_execution_id"
    case teamRunId = "team_run_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      runId: try container.decodeIfPresent(String.self, forKey: .runId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      scheduledForMillis: try container.decodeIfPresent(Int64.self, forKey: .scheduledForMillis) ?? 0,
      status: try container.decodeIfPresent(AgentProactiveRunStatus.self, forKey: .status) ?? .failed,
      attempt: try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 1,
      causeJson: AgentProactiveJSON.decodedObjectString(from: container, forKey: .causeJson),
      startedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .startedAtMillis) ?? 0,
      completedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .completedAtMillis) ?? 0,
      resultSummary: try container.decodeIfPresent(String.self, forKey: .resultSummary) ?? "",
      errorCode: try container.decodeIfPresent(String.self, forKey: .errorCode) ?? "",
      linkedExecutionId: try container.decodeIfPresent(String.self, forKey: .linkedExecutionId) ?? "",
      teamRunId: try container.decodeIfPresent(String.self, forKey: .teamRunId) ?? ""
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(runId, forKey: .runId)
    try container.encode(taskId, forKey: .taskId)
    try container.encode(scheduledForMillis, forKey: .scheduledForMillis)
    try container.encode(status, forKey: .status)
    try container.encode(attempt, forKey: .attempt)
    try container.encode(AgentProactiveJSON.object(causeJson, label: "Proactive run cause"), forKey: .causeJson)
    try container.encode(startedAtMillis, forKey: .startedAtMillis)
    try container.encode(completedAtMillis, forKey: .completedAtMillis)
    try container.encode(resultSummary, forKey: .resultSummary)
    try container.encode(errorCode, forKey: .errorCode)
    try container.encode(linkedExecutionId, forKey: .linkedExecutionId)
    try container.encode(teamRunId, forKey: .teamRunId)
  }
}

struct AgentProactiveDueOccurrence: Codable, Equatable {
  var scheduledForMillis: Int64
  var status: AgentProactiveRunStatus

  enum CodingKeys: String, CodingKey {
    case scheduledForMillis = "scheduled_for_millis"
    case status
  }
}

struct AgentProactiveDueResult: Codable, Equatable {
  var occurrences: [AgentProactiveDueOccurrence]
  var nextRunAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case occurrences
    case nextRunAtMillis = "next_run_at_millis"
  }
}

enum AgentProactiveTaskScheduler {
  static let protocolVersion = "galaxyssi.proactive-task.v1"
  static let windowMillis: Int64 = 60_000

  static func initialNextRun(task: AgentProactiveTask, nowMillis: Int64) throws -> Int64 {
    let base: Int64
    switch task.trigger.kind {
    case .cron:
      base = try AgentCronExpression.parse(task.trigger.cron)
        .nextAfter(timestampMillis: nowMillis - windowMillis, timeZoneIdentifier: task.trigger.timeZone)
    case .interval, .goalCheckpoint:
      base = nowMillis + task.trigger.intervalSeconds * 1_000
    case .manual, .webhook:
      base = 0
    }
    return base + deterministicJitter(
      taskId: task.taskId,
      occurrence: base,
      jitterSeconds: task.policy.jitterSeconds
    )
  }

  static func dueOccurrences(task: AgentProactiveTask, nowMillis: Int64) throws -> AgentProactiveDueResult {
    let scheduled = task.nextRunAtMillis
    switch task.trigger.kind {
    case .interval, .goalCheckpoint:
      let interval = task.trigger.intervalSeconds * 1_000
      let count = max(((nowMillis - scheduled) / interval) + 1, 1)
      let next = scheduled + count * interval
      if nowMillis - scheduled <= windowMillis {
        return AgentProactiveDueResult(
          occurrences: [AgentProactiveDueOccurrence(scheduledForMillis: scheduled, status: .queued)],
          nextRunAtMillis: next
        )
      }
      let retained = min(Int64(task.policy.catchUpLimit), count)
      let first = count - retained
      var due: [Int64] = []
      for offset in first..<count {
        due.append(scheduled + offset * interval)
      }
      return AgentProactiveDueResult(
        occurrences: occurrences(for: due, misfire: task.policy.misfire),
        nextRunAtMillis: next
      )
    case .cron:
      let cron = try AgentCronExpression.parse(task.trigger.cron)
      let baseNext = try cron.nextAfter(timestampMillis: nowMillis, timeZoneIdentifier: task.trigger.timeZone)
      let next = baseNext + deterministicJitter(
        taskId: task.taskId,
        occurrence: baseNext,
        jitterSeconds: task.policy.jitterSeconds
      )
      if nowMillis - scheduled <= windowMillis {
        return AgentProactiveDueResult(
          occurrences: [AgentProactiveDueOccurrence(scheduledForMillis: scheduled, status: .queued)],
          nextRunAtMillis: next
        )
      }
      switch task.policy.misfire {
      case .skip:
        return AgentProactiveDueResult(
          occurrences: [AgentProactiveDueOccurrence(scheduledForMillis: scheduled, status: .skipped)],
          nextRunAtMillis: next
        )
      case .fireOnce:
        return AgentProactiveDueResult(
          occurrences: [AgentProactiveDueOccurrence(scheduledForMillis: nowMillis, status: .queued)],
          nextRunAtMillis: next
        )
      case .catchUp:
        var values: [Int64] = []
        var cursor = nowMillis
        while values.count < task.policy.catchUpLimit {
          let previous = try cron.previousAtOrBefore(
            timestampMillis: cursor,
            timeZoneIdentifier: task.trigger.timeZone
          )
          if previous < scheduled {
            break
          }
          values.append(previous)
          cursor = previous - windowMillis
        }
        return AgentProactiveDueResult(
          occurrences: values.sorted().map {
            AgentProactiveDueOccurrence(scheduledForMillis: $0, status: .queued)
          },
          nextRunAtMillis: next
        )
      }
    case .manual, .webhook:
      return AgentProactiveDueResult(occurrences: [], nextRunAtMillis: 0)
    }
  }

  static func recordOutcome(
    task: AgentProactiveTask,
    status: AgentProactiveRunStatus,
    completedAtMillis: Int64
  ) throws -> AgentProactiveTask {
    let failures: Int
    switch status {
    case .completed:
      failures = 0
    case .failed:
      failures = task.consecutiveFailures + 1
    default:
      failures = task.consecutiveFailures
    }
    let nextRunCount = task.runCount + 1
    let enabled = task.enabled &&
      failures < task.policy.maxConsecutiveFailures &&
      (task.policy.maxRuns == 0 || nextRunCount < task.policy.maxRuns)
    return try AgentProactiveTask(
      taskId: task.taskId,
      name: task.name,
      trigger: task.trigger,
      action: task.action,
      policy: task.policy,
      enabled: enabled,
      nextRunAtMillis: enabled ? task.nextRunAtMillis : 0,
      lastRunAtMillis: completedAtMillis,
      lastStatus: status,
      runCount: nextRunCount,
      consecutiveFailures: failures,
      revision: task.revision,
      createdAtMillis: task.createdAtMillis,
      updatedAtMillis: completedAtMillis
    )
  }

  static func shouldDisable(task: AgentProactiveTask, nowMillis: Int64) -> Bool {
    (task.policy.deadlineAtMillis > 0 && nowMillis > task.policy.deadlineAtMillis) ||
      (task.policy.maxRuns > 0 && task.runCount >= task.policy.maxRuns) ||
      task.consecutiveFailures >= task.policy.maxConsecutiveFailures
  }

  static func deterministicJitter(taskId: String, occurrence: Int64, jitterSeconds: Int) -> Int64 {
    if jitterSeconds <= 0 || occurrence <= 0 {
      return 0
    }
    let digest = Array(SHA256.hash(data: Data("\(taskId):\(occurrence)".utf8)))
    let unsigned = digest.prefix(4).reduce(UInt64(0)) { partial, byte in
      (partial << 8) | UInt64(byte)
    }
    return Int64(unsigned % UInt64(jitterSeconds * 1_000 + 1))
  }

  static func stableRunId(taskId: String, occurrence: String) -> String {
    let identity = "\(taskId)\u{1f}\(occurrence)"
    let digest = SHA256.hash(data: Data(identity.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    return "ios-proactive-run-\(digest)"
  }

  static func remoteWebhookEventMatches(
    filter: [String: String],
    payload: [String: Any]
  ) -> Bool {
    filter.allSatisfy { path, expected in
      var current: Any? = payload
      for segment in path.split(separator: ".") {
        guard let object = current as? [String: Any] else { return false }
        current = object[String(segment)]
      }
      if let value = current as? String {
        return value == expected
      }
      if let value = current as? NSNumber {
        return value.stringValue == expected
      }
      return false
    }
  }

  static func requireIdentifier(_ value: String, label: String) throws {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.range(
      of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"#,
      options: .regularExpression
    ) != nil else {
      throw AgentProactiveTaskError.invalid("\(label) is invalid")
    }
  }

  private static func occurrences(
    for due: [Int64],
    misfire: AgentProactiveMisfirePolicy
  ) -> [AgentProactiveDueOccurrence] {
    switch misfire {
    case .skip:
      return due.map { AgentProactiveDueOccurrence(scheduledForMillis: $0, status: .skipped) }
    case .fireOnce:
      guard let last = due.last else { return [] }
      return [AgentProactiveDueOccurrence(scheduledForMillis: last, status: .queued)]
    case .catchUp:
      return due.map { AgentProactiveDueOccurrence(scheduledForMillis: $0, status: .queued) }
    }
  }
}

enum GlobalProactiveTarget: String, Codable, CaseIterable, Identifiable {
  case currentConversation = "CURRENT_CONVERSATION"
  case newConversation = "NEW_CONVERSATION"
  case globalDigest = "GLOBAL_DIGEST"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalProactiveTarget {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .currentConversation
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

enum GlobalProactiveMessageStatus: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case notified = "NOTIFIED"
  case delivering = "DELIVERING"
  case delivered = "DELIVERED"
  case dismissed = "DISMISSED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalProactiveMessageStatus {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .pending
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

enum GlobalAgentFeedbackKind: String, Codable, CaseIterable, Identifiable {
  case helpful = "HELPFUL"
  case notRelevant = "NOT_RELEVANT"
  case tooFrequent = "TOO_FREQUENT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> GlobalAgentFeedbackKind {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .helpful
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

struct GlobalProactiveMessage: Codable, Equatable, Identifiable {
  var id: String
  var sourceEventId: String
  var sourceConversationId: String
  var target: GlobalProactiveTarget
  var title: String
  var content: String
  var topic: String
  var urgent: Bool
  var causalEventIds: Set<String>
  var status: GlobalProactiveMessageStatus
  var createdAtMillis: Int64
  var notifiedAtMillis: Int64
  var deliveryConversationId: String
  var deliveryLeaseExpiresAtMillis: Int64
  var deliveryAttemptCount: Int
  var deliveryBudgetCounted: Bool
  var lastDeliveryError: String
  var deliveredAtMillis: Int64
  var deliveredConversationId: String
  var deliveryGroupId: String
  var viewedAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    sourceEventId: String,
    sourceConversationId: String,
    target: GlobalProactiveTarget,
    title: String,
    content: String,
    topic: String,
    urgent: Bool,
    causalEventIds: Set<String> = [],
    status: GlobalProactiveMessageStatus = .pending,
    createdAtMillis: Int64 = 0,
    notifiedAtMillis: Int64 = 0,
    deliveryConversationId: String = "",
    deliveryLeaseExpiresAtMillis: Int64 = 0,
    deliveryAttemptCount: Int = 0,
    deliveryBudgetCounted: Bool = false,
    lastDeliveryError: String = "",
    deliveredAtMillis: Int64 = 0,
    deliveredConversationId: String = "",
    deliveryGroupId: String = "",
    viewedAtMillis: Int64 = 0
  ) {
    self.id = id
    self.sourceEventId = sourceEventId
    self.sourceConversationId = sourceConversationId
    self.target = target
    self.title = title
    self.content = content
    self.topic = topic
    self.urgent = urgent
    self.causalEventIds = causalEventIds
    self.status = status
    self.createdAtMillis = max(0, createdAtMillis)
    self.notifiedAtMillis = max(0, notifiedAtMillis)
    self.deliveryConversationId = deliveryConversationId
    self.deliveryLeaseExpiresAtMillis = max(0, deliveryLeaseExpiresAtMillis)
    self.deliveryAttemptCount = max(0, deliveryAttemptCount)
    self.deliveryBudgetCounted = deliveryBudgetCounted
    self.lastDeliveryError = lastDeliveryError
    self.deliveredAtMillis = max(0, deliveredAtMillis)
    self.deliveredConversationId = deliveredConversationId
    self.deliveryGroupId = deliveryGroupId
    self.viewedAtMillis = max(0, viewedAtMillis)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case sourceEventId = "source_event_id"
    case sourceConversationId = "source_conversation_id"
    case target
    case title
    case content
    case topic
    case urgent
    case causalEventIds = "causal_event_ids"
    case status
    case createdAtMillis = "created_at_millis"
    case notifiedAtMillis = "notified_at_millis"
    case deliveryConversationId = "delivery_conversation_id"
    case deliveryLeaseExpiresAtMillis = "delivery_lease_expires_at_millis"
    case deliveryAttemptCount = "delivery_attempt_count"
    case deliveryBudgetCounted = "delivery_budget_counted"
    case lastDeliveryError = "last_delivery_error"
    case deliveredAtMillis = "delivered_at_millis"
    case deliveredConversationId = "delivered_conversation_id"
    case deliveryGroupId = "delivery_group_id"
    case viewedAtMillis = "viewed_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      sourceEventId: try container.decodeIfPresent(String.self, forKey: .sourceEventId) ?? "",
      sourceConversationId: try container.decodeIfPresent(String.self, forKey: .sourceConversationId) ?? "",
      target: try container.decodeIfPresent(GlobalProactiveTarget.self, forKey: .target) ?? .currentConversation,
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      content: try container.decodeIfPresent(String.self, forKey: .content) ?? "",
      topic: try container.decodeIfPresent(String.self, forKey: .topic) ?? "",
      urgent: try container.decodeIfPresent(Bool.self, forKey: .urgent) ?? false,
      causalEventIds: try container.decodeIfPresent(Set<String>.self, forKey: .causalEventIds) ?? [],
      status: try container.decodeIfPresent(GlobalProactiveMessageStatus.self, forKey: .status) ?? .pending,
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      notifiedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .notifiedAtMillis) ?? 0,
      deliveryConversationId: try container.decodeIfPresent(String.self, forKey: .deliveryConversationId) ?? "",
      deliveryLeaseExpiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .deliveryLeaseExpiresAtMillis) ?? 0,
      deliveryAttemptCount: try container.decodeIfPresent(Int.self, forKey: .deliveryAttemptCount) ?? 0,
      deliveryBudgetCounted: try container.decodeIfPresent(Bool.self, forKey: .deliveryBudgetCounted) ?? false,
      lastDeliveryError: try container.decodeIfPresent(String.self, forKey: .lastDeliveryError) ?? "",
      deliveredAtMillis: try container.decodeIfPresent(Int64.self, forKey: .deliveredAtMillis) ?? 0,
      deliveredConversationId: try container.decodeIfPresent(String.self, forKey: .deliveredConversationId) ?? "",
      deliveryGroupId: try container.decodeIfPresent(String.self, forKey: .deliveryGroupId) ?? "",
      viewedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .viewedAtMillis) ?? 0
    )
  }
}

struct GlobalAgentFeedback: Codable, Equatable, Identifiable {
  var id: String
  var proactiveMessageId: String
  var deliveryGroupId: String
  var conversationId: String
  var topic: String
  var target: GlobalProactiveTarget
  var kind: GlobalAgentFeedbackKind
  var createdAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    proactiveMessageId: String,
    deliveryGroupId: String,
    conversationId: String,
    topic: String,
    target: GlobalProactiveTarget,
    kind: GlobalAgentFeedbackKind,
    createdAtMillis: Int64 = 0
  ) {
    self.id = id
    self.proactiveMessageId = proactiveMessageId
    self.deliveryGroupId = deliveryGroupId
    self.conversationId = conversationId
    self.topic = topic
    self.target = target
    self.kind = kind
    self.createdAtMillis = max(0, createdAtMillis)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case proactiveMessageId = "proactive_message_id"
    case deliveryGroupId = "delivery_group_id"
    case conversationId = "conversation_id"
    case topic
    case target
    case kind
    case createdAtMillis = "created_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      proactiveMessageId: try container.decodeIfPresent(String.self, forKey: .proactiveMessageId) ?? "",
      deliveryGroupId: try container.decodeIfPresent(String.self, forKey: .deliveryGroupId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      topic: try container.decodeIfPresent(String.self, forKey: .topic) ?? "",
      target: try container.decodeIfPresent(GlobalProactiveTarget.self, forKey: .target) ?? .currentConversation,
      kind: try container.decodeIfPresent(GlobalAgentFeedbackKind.self, forKey: .kind) ?? .helpful,
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0
    )
  }
}

struct GlobalProactiveInboxItem: Codable, Equatable, Identifiable {
  var key: String
  var messageIds: Set<String>
  var title: String
  var content: String
  var topic: String
  var target: GlobalProactiveTarget
  var urgent: Bool
  var sourceConversationId: String
  var destinationConversationId: String
  var causalEventIds: Set<String>
  var createdAtMillis: Int64
  var deliveredAtMillis: Int64
  var viewedAtMillis: Int64
  var feedbackKind: GlobalAgentFeedbackKind?

  var id: String { key }
  var isNew: Bool { viewedAtMillis <= 0 && feedbackKind == nil }

  enum CodingKeys: String, CodingKey {
    case key
    case messageIds = "message_ids"
    case title
    case content
    case topic
    case target
    case urgent
    case sourceConversationId = "source_conversation_id"
    case destinationConversationId = "destination_conversation_id"
    case causalEventIds = "causal_event_ids"
    case createdAtMillis = "created_at_millis"
    case deliveredAtMillis = "delivered_at_millis"
    case viewedAtMillis = "viewed_at_millis"
    case feedbackKind = "feedback_kind"
  }
}

enum GlobalProactiveInboxPolicy {
  static func project(
    messages: [GlobalProactiveMessage],
    feedback: [GlobalAgentFeedback],
    limit: Int = 50
  ) -> [GlobalProactiveInboxItem] {
    guard limit > 0 else { return [] }

    var feedbackByMessage: [String: GlobalAgentFeedbackKind] = [:]
    for item in feedback.sorted(by: { $0.createdAtMillis < $1.createdAtMillis }) {
      feedbackByMessage[item.proactiveMessageId] = item.kind
    }

    var orderedKeys: [String] = []
    var groups: [String: [GlobalProactiveMessage]] = [:]
    for message in messages where message.status == .delivered {
      let key = inboxKey(message)
      if groups[key] == nil {
        orderedKeys.append(key)
      }
      groups[key, default: []].append(message)
    }

    let projected = orderedKeys.compactMap { key -> GlobalProactiveInboxItem? in
      guard let group = groups[key] else { return nil }
      return projectGroup(group, feedbackByMessage: feedbackByMessage)
    }

    let sorted = projected.sorted { left, right in
      if left.isNew != right.isNew {
        return left.isNew && !right.isNew
      }
      if left.urgent != right.urgent {
        return left.urgent && !right.urgent
      }
      if left.deliveredAtMillis != right.deliveredAtMillis {
        return left.deliveredAtMillis > right.deliveredAtMillis
      }
      if left.createdAtMillis != right.createdAtMillis {
        return left.createdAtMillis > right.createdAtMillis
      }
      return left.key < right.key
    }
    return Array(sorted.prefix(min(max(limit, 1), 100)))
  }

  static func newCount(_ items: [GlobalProactiveInboxItem]) -> Int {
    items.filter(\.isNew).count
  }

  static func markViewed(
    messages: [GlobalProactiveMessage],
    messageIds: Set<String>,
    nowMillis: Int64
  ) -> [GlobalProactiveMessage] {
    guard !messageIds.isEmpty && nowMillis > 0 else { return messages }
    return messages.map { message in
      guard messageIds.contains(message.id),
        message.status == .delivered,
        message.viewedAtMillis <= 0
      else {
        return message
      }
      var updated = message
      updated.viewedAtMillis = nowMillis
      return updated
    }
  }

  private static func projectGroup(
    _ group: [GlobalProactiveMessage],
    feedbackByMessage: [String: GlobalAgentFeedbackKind]
  ) -> GlobalProactiveInboxItem? {
    let ordered = group.enumerated().sorted { left, right in
      if left.element.createdAtMillis != right.element.createdAtMillis {
        return left.element.createdAtMillis < right.element.createdAtMillis
      }
      return left.offset < right.offset
    }.map(\.element)
    guard let primary = ordered.last else { return nil }

    var kinds: [GlobalAgentFeedbackKind] = []
    for message in ordered {
      guard let kind = feedbackByMessage[message.id], !kinds.contains(kind) else { continue }
      kinds.append(kind)
    }
    if kinds.contains(.notRelevant) || kinds.contains(.tooFrequent) {
      return nil
    }

    let content: String
    if ordered.count == 1 {
      content = primary.content.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      content = ordered.map { message in
        let cleanTopic = message.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTopic.isEmpty {
          return "\u{2022} \(cleanContent)"
        }
        return "\u{2022} \(cleanTopic): \(cleanContent)"
      }.joined(separator: "\n")
    }

    let viewedValues = ordered.map(\.viewedAtMillis)
    let viewedAtMillis = viewedValues.allSatisfy { $0 > 0 } ? (viewedValues.max() ?? 0) : 0
    return GlobalProactiveInboxItem(
      key: inboxKey(primary),
      messageIds: Set(ordered.map(\.id)),
      title: GlobalAgentText.productTitle(primary.title),
      content: content,
      topic: primary.topic.trimmingCharacters(in: .whitespacesAndNewlines),
      target: primary.target,
      urgent: ordered.contains { $0.urgent },
      sourceConversationId: primary.sourceConversationId,
      destinationConversationId: ordered.last { !$0.deliveredConversationId.isEmpty }?.deliveredConversationId ?? "",
      causalEventIds: Set(ordered.flatMap(\.causalEventIds)),
      createdAtMillis: ordered.map(\.createdAtMillis).min() ?? 0,
      deliveredAtMillis: ordered.map(\.deliveredAtMillis).max() ?? 0,
      viewedAtMillis: viewedAtMillis,
      feedbackKind: kinds.count == 1 ? kinds[0] : nil
    )
  }

  private static func inboxKey(_ message: GlobalProactiveMessage) -> String {
    if message.target == .globalDigest && !message.deliveryGroupId.isEmpty {
      return "global-agent-digest:\(message.deliveryGroupId)"
    }
    return "global-agent:\(message.id)"
  }
}
