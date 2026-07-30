import CryptoKit
import Foundation

enum GlobalConversationEventType: String, Codable, CaseIterable, Identifiable {
  case messageCreated = "MESSAGE_CREATED"
  case messageUpdated = "MESSAGE_UPDATED"
  case messageDeleted = "MESSAGE_DELETED"
  case conversationCreated = "CONVERSATION_CREATED"
  case conversationUpdated = "CONVERSATION_UPDATED"
  case conversationMerged = "CONVERSATION_MERGED"
  case conversationDeleted = "CONVERSATION_DELETED"
  case attachmentAdded = "ATTACHMENT_ADDED"
  case artifactCreated = "ARTIFACT_CREATED"
  case taskUpdated = "TASK_UPDATED"
  case toolStarted = "TOOL_STARTED"
  case toolCompleted = "TOOL_COMPLETED"
  case toolCancelled = "TOOL_CANCELLED"
  case toolFailed = "TOOL_FAILED"
  case toolResult = "TOOL_RESULT"
  case cognitionResult = "COGNITION_RESULT"
  case userFeedback = "USER_FEEDBACK"
  case memoryCreated = "MEMORY_CREATED"
  case memoryUpdated = "MEMORY_UPDATED"
  case memoryConflicted = "MEMORY_CONFLICTED"
  case memoryDeleted = "MEMORY_DELETED"
  case knowledgeImported = "KNOWLEDGE_IMPORTED"
  case knowledgeUpdated = "KNOWLEDGE_UPDATED"
  case knowledgeAccessChanged = "KNOWLEDGE_ACCESS_CHANGED"
  case knowledgeDeleted = "KNOWLEDGE_DELETED"
  case authorizationGranted = "AUTHORIZATION_GRANTED"
  case authorizationRevoked = "AUTHORIZATION_REVOKED"
  case authorizationPolicyChanged = "AUTHORIZATION_POLICY_CHANGED"
  case resourceRegistered = "RESOURCE_REGISTERED"
  case resourceUpdated = "RESOURCE_UPDATED"
  case resourceRemoved = "RESOURCE_REMOVED"
  case resourceStateChanged = "RESOURCE_STATE_CHANGED"
  case capabilitySnapshotReset = "CAPABILITY_SNAPSHOT_RESET"

  var id: String { rawValue }

  var isCapabilityLifecycleEvent: Bool {
    Self.capabilityLifecycleEvents.contains(self)
  }

  private static let capabilityLifecycleEvents: Set<GlobalConversationEventType> = [
    .authorizationGranted,
    .authorizationRevoked,
    .authorizationPolicyChanged,
    .resourceRegistered,
    .resourceUpdated,
    .resourceRemoved,
    .resourceStateChanged,
    .capabilitySnapshotReset
  ]
}

enum GlobalConversationActor: String, Codable, CaseIterable, Identifiable {
  case user = "USER"
  case assistant = "ASSISTANT"
  case tool = "TOOL"
  case system = "SYSTEM"
  case globalAgent = "GLOBAL_AGENT"

  var id: String { rawValue }
}

enum GlobalConversationSensitivity: String, Codable, CaseIterable, Identifiable {
  case personal = "PERSONAL"
  case sessionPrivate = "SESSION_PRIVATE"

  var id: String { rawValue }
}

struct GlobalConversationEvent: Codable, Equatable, Identifiable {
  var id: String
  var type: GlobalConversationEventType
  var conversationId: String
  var messageId: String
  var actor: GlobalConversationActor
  var timestampMillis: Int64
  var content: String
  var contentRef: String
  var conversationTitle: String
  var topicHints: Set<String>
  var sensitivity: GlobalConversationSensitivity
  var metadata: [String: String]
  var causalEventIds: Set<String>
  var retractedEventIds: Set<String>

  init(
    id: String = UUID().uuidString,
    type: GlobalConversationEventType,
    conversationId: String,
    messageId: String = "",
    actor: GlobalConversationActor,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    content: String = "",
    contentRef: String = "",
    conversationTitle: String = "",
    topicHints: Set<String> = [],
    sensitivity: GlobalConversationSensitivity = .personal,
    metadata: [String: String] = [:],
    causalEventIds: Set<String> = [],
    retractedEventIds: Set<String> = []
  ) {
    self.id = id
    self.type = type
    self.conversationId = conversationId
    self.messageId = messageId
    self.actor = actor
    self.timestampMillis = timestampMillis
    self.content = content
    self.contentRef = contentRef
    self.conversationTitle = conversationTitle
    self.topicHints = topicHints
    self.sensitivity = sensitivity
    self.metadata = metadata
    self.causalEventIds = causalEventIds
    self.retractedEventIds = retractedEventIds
  }

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case conversationId = "conversation_id"
    case messageId = "message_id"
    case actor
    case timestampMillis = "timestamp_millis"
    case content
    case contentRef = "content_ref"
    case conversationTitle = "conversation_title"
    case topicHints = "topic_hints"
    case sensitivity
    case metadata
    case causalEventIds = "causal_event_ids"
    case retractedEventIds = "retracted_event_ids"
  }
}

enum GlobalWorldLayer: String, Codable, CaseIterable, Identifiable {
  case conversation = "CONVERSATION"
  case topic = "TOPIC"
  case user = "USER"
  case realtime = "REALTIME"

  var id: String { rawValue }
}

enum GlobalWorldItemKind: String, Codable, CaseIterable, Identifiable {
  case topic = "TOPIC"
  case goal = "GOAL"
  case task = "TASK"
  case decision = "DECISION"
  case preference = "PREFERENCE"
  case fact = "FACT"
  case risk = "RISK"
  case opportunity = "OPPORTUNITY"
  case state = "STATE"

  var id: String { rawValue }
}

enum GlobalWorldContextVisibility: String, Codable, CaseIterable, Identifiable {
  case shareable = "SHAREABLE"
  case localOnly = "LOCAL_ONLY"

  var id: String { rawValue }
}

struct AgentResourceHealth: Codable, Equatable {
  var successes: Int
  var failures: Int
  var consecutiveFailures: Int
  var averageLatencyMs: Int64
  var circuitOpenUntil: Int64
  var lastUpdatedAt: Int64

  var reliabilityPercent: Int {
    let samples = successes + failures
    guard samples > 0 else { return 90 }
    return max(0, min(100, successes * 100 / samples))
  }

  init(
    successes: Int = 0,
    failures: Int = 0,
    consecutiveFailures: Int = 0,
    averageLatencyMs: Int64 = 0,
    circuitOpenUntil: Int64 = 0,
    lastUpdatedAt: Int64 = 0
  ) {
    self.successes = max(successes, 0)
    self.failures = max(failures, 0)
    self.consecutiveFailures = max(consecutiveFailures, 0)
    self.averageLatencyMs = max(averageLatencyMs, 0)
    self.circuitOpenUntil = max(circuitOpenUntil, 0)
    self.lastUpdatedAt = max(lastUpdatedAt, 0)
  }

  enum CodingKeys: String, CodingKey {
    case successes
    case failures
    case consecutiveFailures = "consecutive_failures"
    case averageLatencyMs = "average_latency_ms"
    case circuitOpenUntil = "circuit_open_until"
    case lastUpdatedAt = "last_updated_at"
  }
}

enum GlobalAgentText {
  static func stableKey(_ values: String...) -> String {
    let normalized = values.map(normalize).joined(separator: "|").prefix(2_000)
    return privateFingerprint(String(normalized)).prefix(32).description
  }

  static func normalize(_ value: String) -> String {
    value.lowercased()
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func privateFingerprint(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

enum GlobalCapabilityObservationExtractor {
  static func snapshotReset(
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: "capability-snapshot-reset:\(timestampMillis)",
      type: .capabilitySnapshotReset,
      conversationId: capabilityConversationId,
      actor: .system,
      timestampMillis: timestampMillis,
      conversationTitle: capabilityTopic,
      metadata: [
        "origin": "capability_reconciliation",
        "projection": "reset_capabilities",
        "context_visibility": GlobalWorldContextVisibility.localOnly.rawValue
      ]
    )
  }

  static func authorizationMutations(
    before: Set<String>,
    after: Set<String>,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [GlobalConversationEvent] {
    before.union(after).sorted().compactMap { consentKey in
      if before.contains(consentKey), after.contains(consentKey) {
        return nil
      }
      return authorizationEvent(
        consentKey: consentKey,
        granted: after.contains(consentKey),
        timestampMillis: timestampMillis
      )
    }
  }

  static func safetyPolicyMutation(
    before: AgentSafetySettings?,
    after: AgentSafetySettings,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> GlobalConversationEvent? {
    if before == after {
      return nil
    }
    let stableKey = "capability:authorization:agent-safety-policy"
    let executionState = after.executionPaused ? "paused" : "active"
    let taskMode = after.taskExecutionMode.rawValue.replacingOccurrences(of: "_", with: " ")
    let permissionMode = after.permissionMode.rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    let summary = "The local Agent task mode is \(taskMode); the action policy uses \(permissionMode) mode; execution is \(executionState); local actions are \(allowed(after.localActionsAllowed)); connector calls are \(allowed(after.connectorCallsAllowed)); device control is \(allowed(after.deviceControlAllowed))."
    let fingerprint = GlobalAgentText.stableKey(
      after.taskExecutionMode.androidName,
      after.permissionMode.rawValue,
      String(after.highRiskGuard),
      String(after.memoryCapture),
      String(after.screenObservationAllowed),
      String(after.localActionsAllowed),
      String(after.connectorCallsAllowed),
      String(after.deviceControlAllowed),
      String(after.executionPaused)
    )
    return GlobalConversationEvent(
      id: "capability-safety-policy:\(fingerprint):\(timestampMillis)",
      type: .authorizationPolicyChanged,
      conversationId: capabilityConversationId,
      messageId: "agent-safety-policy",
      actor: .system,
      timestampMillis: timestampMillis,
      content: summary,
      contentRef: "encrypted://agent-authorization/safety-policy",
      conversationTitle: authorizationTopic,
      topicHints: [authorizationTopic],
      metadata: [
        "origin": "agent_safety_policy",
        "task_execution_mode": after.taskExecutionMode.rawValue,
        "permission_mode": after.permissionMode.rawValue.lowercased(),
        "high_risk_guard": String(after.highRiskGuard),
        "memory_capture": String(after.memoryCapture),
        "screen_observation_allowed": String(after.screenObservationAllowed),
        "local_actions_allowed": String(after.localActionsAllowed),
        "connector_calls_allowed": String(after.connectorCallsAllowed),
        "device_control_allowed": String(after.deviceControlAllowed),
        "execution_paused": String(after.executionPaused),
        "identity_stable_key": stableKey,
        "identity_summary": summary,
        "identity_kind": GlobalWorldItemKind.decision.rawValue,
        "identity_layer": GlobalWorldLayer.user.rawValue,
        "identity_topic": authorizationTopic,
        "replace_stable_keys": stableKey,
        "context_visibility": GlobalWorldContextVisibility.localOnly.rawValue,
        "projection": "replace"
      ]
    )
  }

  static func mcpMutations(
    before: [AgentMcpConnection],
    after: [AgentMcpConnection],
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [GlobalConversationEvent] {
    let previous: [String: CapabilityResourceSnapshot] = before.reduce(into: [:]) { result, connection in
      result[connection.id] = mcpSnapshot(connection, nowMillis: timestampMillis)
    }
    let current: [String: CapabilityResourceSnapshot] = after.reduce(into: [:]) { result, connection in
      result[connection.id] = mcpSnapshot(connection, nowMillis: timestampMillis)
    }
    resourceMutations(
      before: previous,
      after: current,
      timestampMillis: timestampMillis
    )
  }

  static func agentMutations(
    before: [AgentRegistration],
    after: [AgentRegistration],
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [GlobalConversationEvent] {
    let previous: [String: CapabilityResourceSnapshot] = before.reduce(into: [:]) { result, registration in
      result[registration.agentId] = agentSnapshot(registration)
    }
    let current: [String: CapabilityResourceSnapshot] = after.reduce(into: [:]) { result, registration in
      result[registration.agentId] = agentSnapshot(registration)
    }
    resourceMutations(
      before: previous,
      after: current,
      timestampMillis: timestampMillis
    )
  }

  static func homeAssistantMutations(
    before: HomeAssistantSettings,
    after: HomeAssistantSettings,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [GlobalConversationEvent] {
    let previous: [String: CapabilityResourceSnapshot] = homeAssistantSnapshot(before).map { [homeAssistantId: $0] } ?? [:]
    let current: [String: CapabilityResourceSnapshot] = homeAssistantSnapshot(after).map { [homeAssistantId: $0] } ?? [:]
    return resourceMutations(before: previous, after: current, timestampMillis: timestampMillis)
  }

  static func customDeviceMutations(
    before: [CustomDeviceConnector],
    after: [CustomDeviceConnector],
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [GlobalConversationEvent] {
    let previous: [String: CapabilityResourceSnapshot] = before.reduce(into: [:]) { result, connector in
      result[connector.id] = customDeviceSnapshot(connector)
    }
    let current: [String: CapabilityResourceSnapshot] = after.reduce(into: [:]) { result, connector in
      result[connector.id] = customDeviceSnapshot(connector)
    }
    resourceMutations(
      before: previous,
      after: current,
      timestampMillis: timestampMillis
    )
  }

  static func resourceHealthTransition(
    resourceId: String,
    before: AgentResourceHealth,
    after: AgentResourceHealth,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> GlobalConversationEvent? {
    guard !resourceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    let previousState = healthState(before, nowMillis: timestampMillis)
    let currentState = healthState(after, nowMillis: timestampMillis)
    guard previousState != currentState else {
      return nil
    }
    let idHash = safeId("health", resourceId)
    let stateKey = stateStableKey(kind: "health", idHash: idHash)
    let resourceClass: String
    if resourceId.hasPrefix("domain:") {
      resourceClass = "failure domain"
    } else if resourceId.hasPrefix("target:") {
      resourceClass = "callable target"
    } else {
      resourceClass = "runtime resource"
    }
    let shortHash = idHash.prefix(8)
    let stateSummary: String
    switch currentState {
    case .unknown:
      stateSummary = "The \(resourceClass) \(shortHash) has no recent health evidence."
    case .healthy:
      stateSummary = "The \(resourceClass) \(shortHash) is available."
    case .degraded:
      stateSummary = "The \(resourceClass) \(shortHash) is degraded after \(after.consecutiveFailures) consecutive failures."
    case .unavailable:
      stateSummary = "The \(resourceClass) \(shortHash) is temporarily unavailable after \(after.consecutiveFailures) consecutive failures."
    }
    let fingerprint = GlobalAgentText.stableKey(currentState.rawValue, String(after.consecutiveFailures))
    return GlobalConversationEvent(
      id: "capability-health:\(idHash):\(fingerprint):\(timestampMillis)",
      type: .resourceStateChanged,
      conversationId: capabilityConversationId,
      messageId: idHash,
      actor: .system,
      timestampMillis: timestampMillis,
      content: stateSummary,
      contentRef: "encrypted://agent-resource-health/\(idHash)",
      conversationTitle: capabilityTopic,
      topicHints: [capabilityTopic],
      metadata: projectionMetadata(
        resourceKind: "health",
        resourceIdHash: idHash,
        identityKey: "",
        identitySummary: "",
        stateKey: stateKey,
        stateSummary: stateSummary,
        stateCode: currentState.rawValue.lowercased(),
        replaceKeys: [stateKey]
      ).merging([
        "origin": "resource_health",
        "consecutive_failures": String(after.consecutiveFailures),
        "reliability_percent": String(after.reliabilityPercent)
      ]) { _, new in new }
    )
  }

  private static func authorizationEvent(
    consentKey: String,
    granted: Bool,
    timestampMillis: Int64
  ) -> GlobalConversationEvent {
    let idHash = safeId("authorization", consentKey)
    let stableKey = "capability:authorization:\(idHash)"
    let scope = authorizationScope(consentKey)
    let summary = granted
      ? "The user granted remembered confirmation consent for \(scope)."
      : "The user revoked remembered confirmation consent for \(scope)."
    return GlobalConversationEvent(
      id: "capability-authorization:\(idHash):\(granted ? "granted" : "revoked"):\(timestampMillis)",
      type: granted ? .authorizationGranted : .authorizationRevoked,
      conversationId: capabilityConversationId,
      messageId: idHash,
      actor: .system,
      timestampMillis: timestampMillis,
      content: summary,
      contentRef: "encrypted://agent-authorization/\(idHash)",
      conversationTitle: authorizationTopic,
      topicHints: [authorizationTopic],
      metadata: [
        "origin": "confirmation_consent",
        "authorization_scope": scope,
        "authorization_state": granted ? "granted" : "revoked",
        "identity_stable_key": stableKey,
        "identity_summary": summary,
        "identity_kind": GlobalWorldItemKind.decision.rawValue,
        "identity_layer": GlobalWorldLayer.user.rawValue,
        "identity_topic": authorizationTopic,
        "replace_stable_keys": stableKey,
        "context_visibility": GlobalWorldContextVisibility.localOnly.rawValue,
        "projection": "replace"
      ]
    )
  }

  private static func resourceMutations(
    before: [String: CapabilityResourceSnapshot],
    after: [String: CapabilityResourceSnapshot],
    timestampMillis: Int64
  ) -> [GlobalConversationEvent] {
    before.keys.reduce(into: Set(after.keys)) { result, key in result.insert(key) }
      .sorted()
      .compactMap { resourceId in
        let previous = before[resourceId]
        let current = after[resourceId]
        if previous?.materialFingerprint == current?.materialFingerprint {
          return nil
        }
        if let current {
          return resourceUpserted(previous: previous, current: current, timestampMillis: timestampMillis)
        }
        if let previous {
          return resourceRemoved(previous: previous, timestampMillis: timestampMillis)
        }
        return nil
      }
  }

  private static func resourceUpserted(
    previous: CapabilityResourceSnapshot?,
    current: CapabilityResourceSnapshot,
    timestampMillis: Int64
  ) -> GlobalConversationEvent {
    let type: GlobalConversationEventType = previous == nil ? .resourceRegistered : .resourceUpdated
    return GlobalConversationEvent(
      id: "capability-resource:\(current.resourceKind):\(current.idHash):\(current.materialFingerprint):\(timestampMillis)",
      type: type,
      conversationId: capabilityConversationId,
      messageId: current.idHash,
      actor: .system,
      timestampMillis: timestampMillis,
      content: "\(current.identitySummary) \(current.stateSummary)".trimmingCharacters(in: .whitespacesAndNewlines),
      contentRef: "encrypted://agent-capabilities/\(current.resourceKind)/\(current.idHash)",
      conversationTitle: capabilityTopic,
      topicHints: [capabilityTopic],
      metadata: projectionMetadata(
        resourceKind: current.resourceKind,
        resourceIdHash: current.idHash,
        identityKey: current.identityKey,
        identitySummary: current.identitySummary,
        stateKey: current.stateKey,
        stateSummary: current.stateSummary,
        stateCode: current.stateCode,
        replaceKeys: [current.identityKey, current.stateKey]
      ).merging(current.safeMetadata) { _, new in new }
        .merging(["origin": "capability_registry"]) { _, new in new }
    )
  }

  private static func resourceRemoved(
    previous: CapabilityResourceSnapshot,
    timestampMillis: Int64
  ) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: "capability-resource-removed:\(previous.resourceKind):\(previous.idHash):\(timestampMillis)",
      type: .resourceRemoved,
      conversationId: capabilityConversationId,
      messageId: previous.idHash,
      actor: .system,
      timestampMillis: timestampMillis,
      content: "The \(previous.resourceKind.replacingOccurrences(of: "_", with: " ")) resource \(previous.displayName) was removed.",
      contentRef: "encrypted://agent-capabilities/\(previous.resourceKind)/\(previous.idHash)",
      conversationTitle: capabilityTopic,
      metadata: [
        "origin": "capability_registry",
        "resource_kind": previous.resourceKind,
        "resource_id_hash": previous.idHash,
        "replace_stable_keys": [previous.identityKey, previous.stateKey].joined(separator: ","),
        "context_visibility": GlobalWorldContextVisibility.localOnly.rawValue,
        "projection": "retract_stable_keys"
      ]
    )
  }

  private static func projectionMetadata(
    resourceKind: String,
    resourceIdHash: String,
    identityKey: String,
    identitySummary: String,
    stateKey: String,
    stateSummary: String,
    stateCode: String,
    replaceKeys: Set<String>
  ) -> [String: String] {
    [
      "resource_kind": resourceKind,
      "resource_id_hash": resourceIdHash,
      "identity_stable_key": identityKey,
      "identity_summary": identitySummary,
      "identity_kind": GlobalWorldItemKind.fact.rawValue,
      "identity_layer": GlobalWorldLayer.user.rawValue,
      "identity_topic": capabilityTopic,
      "state_stable_key": stateKey,
      "state_summary": stateSummary,
      "state_kind": GlobalWorldItemKind.state.rawValue,
      "state_layer": GlobalWorldLayer.realtime.rawValue,
      "state_topic": capabilityTopic,
      "resource_state": stateCode,
      "replace_stable_keys": replaceKeys.filter { !$0.isEmpty }.sorted().joined(separator: ","),
      "context_visibility": GlobalWorldContextVisibility.localOnly.rawValue,
      "projection": "replace"
    ]
  }

  private static func mcpSnapshot(
    _ connection: AgentMcpConnection,
    nowMillis: Int64
  ) -> CapabilityResourceSnapshot {
    let idHash = safeId("mcp", connection.id)
    let authState = connection.effectiveAuthState(nowMillis: nowMillis)
    let callable = connection.isCallable(nowMillis: nowMillis)
    let stateCode: String
    if !connection.enabled {
      stateCode = "disabled"
    } else if [.notConfigured, .challengeRequired, .authenticating, .reauthenticationRequired, .error].contains(authState) {
      stateCode = "needs_setup"
    } else {
      switch connection.state {
      case .connecting:
        stateCode = "connecting"
      case .connected:
        stateCode = "available"
      case .error:
        stateCode = "error"
      case .unavailable:
        stateCode = "unavailable"
      case .needsSetup:
        stateCode = "needs_setup"
      case .installed:
        stateCode = callable ? "ready" : "unavailable"
      }
    }
    let name = cleanLabel(connection.displayName, fallback: "MCP resource")
    let identity = "\(name) is an installed \(connection.distribution.rawValue.replacingOccurrences(of: "_", with: " ")) MCP resource with \(connection.toolIds.count) tools."
    let state: String
    switch stateCode {
    case "available":
      state = "\(name) is connected and callable."
    case "ready":
      state = "\(name) is ready when requested."
    case "connecting":
      state = "\(name) is connecting."
    case "needs_setup":
      state = "\(name) requires authentication or setup."
    case "disabled":
      state = "\(name) is disabled."
    case "error":
      state = "\(name) is unavailable because its connection failed."
    default:
      state = "\(name) is unavailable."
    }
    let fingerprint = GlobalAgentText.stableKey(
      name,
      connection.catalogId,
      privateFingerprint(connection.endpoint),
      connection.distribution.rawValue,
      connection.transport.rawValue,
      connection.authProfile.method.rawValue,
      authState.rawValue,
      connection.state.rawValue,
      String(connection.enabled),
      String(callable),
      connection.toolIds.sorted().joined(separator: "|"),
      connection.packageVersion,
      connection.packageSha256
    )
    return CapabilityResourceSnapshot(
      resourceKind: "mcp",
      idHash: idHash,
      displayName: name,
      identitySummary: identity,
      stateSummary: state,
      stateCode: stateCode,
      materialFingerprint: fingerprint,
      safeMetadata: [
        "distribution": connection.distribution.rawValue,
        "transport": connection.transport.rawValue,
        "auth_state": authState.rawValue,
        "connection_state": connection.state.rawValue,
        "enabled": String(connection.enabled),
        "callable": String(callable),
        "tool_count": String(Set(connection.toolIds).count)
      ]
    )
  }

  private static func agentSnapshot(_ registration: AgentRegistration) -> CapabilityResourceSnapshot {
    let idHash = safeId("agent", registration.agentId)
    let name = cleanLabel(registration.displayName, fallback: "Agent resource")
    let atCapacity = !registration.hasCapacity
    let stateCode: String
    switch registration.status {
    case .online, .idle:
      stateCode = atCapacity ? "busy" : "available"
    case .busy:
      stateCode = "busy"
    case .degraded:
      stateCode = "degraded"
    case .updating:
      stateCode = "updating"
    case .permissionRequired:
      stateCode = "permission_required"
    case .offline:
      stateCode = "offline"
    case .unreachable:
      stateCode = "unreachable"
    }
    let location = registration.location.rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    let identity = "\(name) is a registered \(location) Agent resource with \(registration.capabilities.count) capabilities."
    let state: String
    switch stateCode {
    case "available":
      state = "\(name) is available."
    case "busy":
      state = "\(name) is busy\(atCapacity ? " and at capacity" : "")."
    case "degraded":
      state = "\(name) is degraded."
    case "updating":
      state = "\(name) is updating."
    case "permission_required":
      state = "\(name) requires local permission."
    case "offline":
      state = "\(name) is offline."
    default:
      state = "\(name) is unreachable."
    }
    let fingerprint = GlobalAgentText.stableKey(
      name,
      registration.kind.rawValue,
      registration.location.rawValue,
      registration.status.rawValue,
      registration.capabilities.map(\.rawValue).sorted().joined(separator: "|"),
      registration.toolIds.sorted().joined(separator: "|"),
      String(registration.permissionScopes.count),
      registration.`protocol`.preferred,
      registration.connectionKind.rawValue,
      registration.cost.rawValue,
      registration.latency.rawValue,
      registration.trust.rawValue,
      String(atCapacity),
      String(registration.maxParallelRuns),
      registration.capabilitiesHash
    )
    return CapabilityResourceSnapshot(
      resourceKind: "agent",
      idHash: idHash,
      displayName: name,
      identitySummary: identity,
      stateSummary: state,
      stateCode: stateCode,
      materialFingerprint: fingerprint,
      safeMetadata: [
        "agent_kind": registration.kind.rawValue.lowercased(),
        "location": registration.location.rawValue.lowercased(),
        "endpoint_state": registration.status.rawValue.lowercased(),
        "connection_kind": registration.connectionKind.rawValue.lowercased(),
        "trust": registration.trust.rawValue.lowercased(),
        "capability_count": String(registration.capabilities.count),
        "tool_count": String(registration.toolIds.count),
        "at_capacity": String(atCapacity)
      ]
    )
  }

  private static func homeAssistantSnapshot(_ settings: HomeAssistantSettings) -> CapabilityResourceSnapshot? {
    let present = settings.enabled ||
      !settings.baseUrl.isEmpty ||
      !settings.accessToken.isEmpty ||
      !settings.defaultEntityId.isEmpty
    guard present else {
      return nil
    }
    let idHash = safeId("home_assistant", homeAssistantId)
    let stateCode: String
    if settings.configured {
      stateCode = "ready"
    } else if settings.enabled {
      stateCode = "needs_setup"
    } else {
      stateCode = "disabled"
    }
    let identity = "Home Assistant is registered as a smart-device resource."
    let state: String
    switch stateCode {
    case "ready":
      state = "Home Assistant is enabled and ready."
    case "needs_setup":
      state = "Home Assistant is enabled but requires connection setup."
    default:
      state = "Home Assistant is disabled."
    }
    return CapabilityResourceSnapshot(
      resourceKind: "home_assistant",
      idHash: idHash,
      displayName: "Home Assistant",
      identitySummary: identity,
      stateSummary: state,
      stateCode: stateCode,
      materialFingerprint: GlobalAgentText.stableKey(
        String(settings.enabled),
        String(settings.credentialsConfigured),
        privateFingerprint(settings.baseUrl),
        privateFingerprint(settings.defaultEntityId),
        String(!settings.defaultEntityId.isEmpty)
      ),
      safeMetadata: [
        "enabled": String(settings.enabled),
        "credentials_configured": String(settings.credentialsConfigured),
        "default_target_configured": String(!settings.defaultEntityId.isEmpty)
      ]
    )
  }

  private static func customDeviceSnapshot(_ connector: CustomDeviceConnector) -> CapabilityResourceSnapshot {
    let idHash = safeId("custom_device", connector.id)
    let name = cleanLabel(connector.name, fallback: "Custom device")
    let stateCode: String
    if !connector.enabled {
      stateCode = "disabled"
    } else if connector.configured {
      stateCode = "ready"
    } else {
      stateCode = "needs_setup"
    }
    let transport = connector.transport.rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
    let identity = "\(name) is a registered \(transport) device resource."
    let state: String
    switch stateCode {
    case "ready":
      state = "\(name) is enabled and configured."
    case "disabled":
      state = "\(name) is disabled."
    default:
      state = "\(name) requires connection setup."
    }
    return CapabilityResourceSnapshot(
      resourceKind: "custom_device",
      idHash: idHash,
      displayName: name,
      identitySummary: identity,
      stateSummary: state,
      stateCode: stateCode,
      materialFingerprint: GlobalAgentText.stableKey(
        name,
        connector.transport.rawValue,
        privateFingerprint(connector.endpoint),
        privateFingerprint(connector.commandTarget),
        String(!connector.username.isEmpty),
        String(!connector.authToken.isEmpty),
        connector.risk.rawValue,
        String(connector.enabled),
        String(connector.configured)
      ),
      safeMetadata: [
        "transport": connector.transport.rawValue.lowercased(),
        "risk": connector.risk.rawValue.lowercased(),
        "enabled": String(connector.enabled),
        "configured": String(connector.configured)
      ]
    )
  }

  private static func healthState(
    _ health: AgentResourceHealth,
    nowMillis: Int64
  ) -> ObservedHealthState {
    if health.successes + health.failures == 0 {
      return .unknown
    }
    if health.circuitOpenUntil > nowMillis || health.consecutiveFailures >= 3 {
      return .unavailable
    }
    if health.consecutiveFailures > 0 {
      return .degraded
    }
    return .healthy
  }

  private static func authorizationScope(_ consentKey: String) -> String {
    if consentKey == "location" { return "location access" }
    if consentKey == "microphone" { return "microphone use" }
    if consentKey == "downloads" { return "downloads" }
    if consentKey == "contacts_write" { return "contact changes" }
    if consentKey == "calendar_write" { return "calendar changes" }
    if consentKey == "bluetooth_discovery" { return "Bluetooth discovery" }
    if consentKey == "wifi_scan" { return "Wi-Fi scanning" }
    if consentKey == "installed_apps_read" { return "installed-app inspection" }
    if consentKey.hasPrefix("device_control:") { return "a configured device target" }
    return "a local action category"
  }

  private static func cleanLabel(_ value: String, fallback: String) -> String {
    let clean = value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? fallback : String(clean.prefix(maxLabelCharacters))
  }

  private static func allowed(_ value: Bool) -> String {
    value ? "allowed" : "blocked"
  }

  private static func safeId(_ kind: String, _ id: String) -> String {
    privateFingerprint("\(kind)\u{0000}\(id)").prefix(32).description
  }

  private static func privateFingerprint(_ value: String) -> String {
    GlobalAgentText.privateFingerprint(value)
  }

  private static func identityStableKey(kind: String, idHash: String) -> String {
    "capability:resource:\(kind):\(idHash):identity"
  }

  private static func stateStableKey(kind: String, idHash: String) -> String {
    "capability:resource:\(kind):\(idHash):state"
  }

  private struct CapabilityResourceSnapshot {
    var resourceKind: String
    var idHash: String
    var displayName: String
    var identitySummary: String
    var stateSummary: String
    var stateCode: String
    var materialFingerprint: String
    var safeMetadata: [String: String]

    var identityKey: String { identityStableKey(kind: resourceKind, idHash: idHash) }
    var stateKey: String { stateStableKey(kind: resourceKind, idHash: idHash) }
  }

  private enum ObservedHealthState: String {
    case unknown = "UNKNOWN"
    case healthy = "HEALTHY"
    case degraded = "DEGRADED"
    case unavailable = "UNAVAILABLE"
  }

  private static let capabilityConversationId = "global-capabilities"
  private static let capabilityTopic = "Available capabilities"
  private static let authorizationTopic = "Local authorization"
  private static let homeAssistantId = "home-assistant"
  private static let maxLabelCharacters = 120
}

struct AgentModelPlannerSettings: Codable, Equatable {
  static let maximumCloudContactIdLength = 120
  static let maximumActions = 12
  static let maximumReplans = 5
  static let maximumAgentHops = 8
  static let minimumToolCalls = 4
  static let maximumToolCalls = 32
  static let minimumLoopIterations = 1
  static let maximumLoopIterations = 24
  static let minimumPhaseRetries = 0
  static let maximumPhaseRetries = 5
  static let minimumNoProgressTimeoutSeconds = 60
  static let maximumNoProgressTimeoutSeconds = 3_600

  var enabled: Bool
  var shareScreenText: Bool
  var maxActions: Int
  var cloudContactId: String
  var dynamicReplanning: Bool
  var maxReplans: Int
  var multiAgentCoordination: Bool
  var shareAgentOutputsWithPlanner: Bool
  var maxAgentHops: Int
  var maxToolCalls: Int
  var maxLoopIterations: Int
  var maxPhaseRetries: Int
  var noProgressTimeoutSeconds: Int

  init(
    enabled: Bool = false,
    shareScreenText: Bool = false,
    maxActions: Int = 8,
    cloudContactId: String = "",
    dynamicReplanning: Bool = true,
    maxReplans: Int = 3,
    multiAgentCoordination: Bool = true,
    shareAgentOutputsWithPlanner: Bool = false,
    maxAgentHops: Int = 4,
    maxToolCalls: Int = 16,
    maxLoopIterations: Int = 8,
    maxPhaseRetries: Int = 2,
    noProgressTimeoutSeconds: Int = 180
  ) {
    self.enabled = enabled
    self.shareScreenText = shareScreenText
    self.maxActions = max(1, min(maxActions, Self.maximumActions))
    self.cloudContactId = String(
      cloudContactId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumCloudContactIdLength)
    )
    self.dynamicReplanning = dynamicReplanning
    self.maxReplans = max(1, min(maxReplans, Self.maximumReplans))
    self.multiAgentCoordination = multiAgentCoordination
    self.shareAgentOutputsWithPlanner = shareAgentOutputsWithPlanner
    self.maxAgentHops = max(1, min(maxAgentHops, Self.maximumAgentHops))
    self.maxToolCalls = max(Self.minimumToolCalls, min(maxToolCalls, Self.maximumToolCalls))
    self.maxLoopIterations = max(Self.minimumLoopIterations, min(maxLoopIterations, Self.maximumLoopIterations))
    self.maxPhaseRetries = max(Self.minimumPhaseRetries, min(maxPhaseRetries, Self.maximumPhaseRetries))
    self.noProgressTimeoutSeconds = max(
      Self.minimumNoProgressTimeoutSeconds,
      min(noProgressTimeoutSeconds, Self.maximumNoProgressTimeoutSeconds)
    )
  }

  static let `default` = AgentModelPlannerSettings()

  var normalized: AgentModelPlannerSettings {
    AgentModelPlannerSettings(
      enabled: enabled,
      shareScreenText: shareScreenText,
      maxActions: maxActions,
      cloudContactId: cloudContactId,
      dynamicReplanning: dynamicReplanning,
      maxReplans: maxReplans,
      multiAgentCoordination: multiAgentCoordination,
      shareAgentOutputsWithPlanner: shareAgentOutputsWithPlanner,
      maxAgentHops: maxAgentHops,
      maxToolCalls: maxToolCalls,
      maxLoopIterations: maxLoopIterations,
      maxPhaseRetries: maxPhaseRetries,
      noProgressTimeoutSeconds: noProgressTimeoutSeconds
    )
  }

  enum CodingKeys: String, CodingKey {
    case version
    case enabled
    case shareScreenText = "share_screen_text"
    case maxActions = "max_actions"
    case cloudContactId = "cloud_contact_id"
    case dynamicReplanning = "dynamic_replanning"
    case maxReplans = "max_replans"
    case multiAgentCoordination = "multi_agent_coordination"
    case shareAgentOutputsWithPlanner = "share_agent_outputs_with_planner"
    case maxAgentHops = "max_agent_hops"
    case maxToolCalls = "max_tool_calls"
    case maxLoopIterations = "max_loop_iterations"
    case maxPhaseRetries = "max_phase_retries"
    case noProgressTimeoutSeconds = "no_progress_timeout_seconds"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
      shareScreenText: try container.decodeIfPresent(Bool.self, forKey: .shareScreenText) ?? false,
      maxActions: try container.decodeIfPresent(Int.self, forKey: .maxActions) ?? 8,
      cloudContactId: try container.decodeIfPresent(String.self, forKey: .cloudContactId) ?? "",
      dynamicReplanning: try container.decodeIfPresent(Bool.self, forKey: .dynamicReplanning) ?? true,
      maxReplans: try container.decodeIfPresent(Int.self, forKey: .maxReplans) ?? 3,
      multiAgentCoordination: try container.decodeIfPresent(Bool.self, forKey: .multiAgentCoordination) ?? true,
      shareAgentOutputsWithPlanner: try container.decodeIfPresent(Bool.self, forKey: .shareAgentOutputsWithPlanner) ?? false,
      maxAgentHops: try container.decodeIfPresent(Int.self, forKey: .maxAgentHops) ?? 4,
      maxToolCalls: try container.decodeIfPresent(Int.self, forKey: .maxToolCalls) ?? 16,
      maxLoopIterations: try container.decodeIfPresent(Int.self, forKey: .maxLoopIterations) ?? 8,
      maxPhaseRetries: try container.decodeIfPresent(Int.self, forKey: .maxPhaseRetries) ?? 2,
      noProgressTimeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .noProgressTimeoutSeconds) ?? 180
    )
  }

  func encode(to encoder: Encoder) throws {
    let value = normalized
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(5, forKey: .version)
    try container.encode(value.enabled, forKey: .enabled)
    try container.encode(value.shareScreenText, forKey: .shareScreenText)
    try container.encode(value.maxActions, forKey: .maxActions)
    try container.encode(value.cloudContactId, forKey: .cloudContactId)
    try container.encode(value.dynamicReplanning, forKey: .dynamicReplanning)
    try container.encode(value.maxReplans, forKey: .maxReplans)
    try container.encode(value.multiAgentCoordination, forKey: .multiAgentCoordination)
    try container.encode(value.shareAgentOutputsWithPlanner, forKey: .shareAgentOutputsWithPlanner)
    try container.encode(value.maxAgentHops, forKey: .maxAgentHops)
    try container.encode(value.maxToolCalls, forKey: .maxToolCalls)
    try container.encode(value.maxLoopIterations, forKey: .maxLoopIterations)
    try container.encode(value.maxPhaseRetries, forKey: .maxPhaseRetries)
    try container.encode(value.noProgressTimeoutSeconds, forKey: .noProgressTimeoutSeconds)
  }
}

struct LanguagePolicySettings: Codable, Equatable {
  static let auto = "auto"
  static let zhCN = "zh-CN"
  static let en = "en"
  static let enUS = "en-US"
  static let zhHK = "zh-HK"
  static let zhTW = "zh-TW"

  static let interfaceChoices = [auto, zhCN, en]
  static let voiceChoices = [auto, zhCN, enUS, zhHK, zhTW]

  var interfaceLanguage: String
  var responseLanguage: String
  var asrLanguage: String
  var ttsLanguage: String

  init(
    interfaceLanguage: String = LanguagePolicySettings.auto,
    responseLanguage: String = LanguagePolicySettings.auto,
    asrLanguage: String = LanguagePolicySettings.auto,
    ttsLanguage: String = LanguagePolicySettings.auto
  ) {
    self.interfaceLanguage = Self.normalizeInterface(interfaceLanguage)
    self.responseLanguage = Self.normalizeVoice(responseLanguage)
    self.asrLanguage = Self.normalizeVoice(asrLanguage)
    self.ttsLanguage = Self.normalizeVoice(ttsLanguage)
  }

  static let `default` = LanguagePolicySettings()

  var asrLocaleIdentifier: String {
    Self.localeIdentifier(for: Self.resolve(asrLanguage))
  }

  enum CodingKeys: String, CodingKey {
    case interfaceLanguage = "interface_language"
    case responseLanguage = "response_language"
    case asrLanguage = "asr_language"
    case ttsLanguage = "tts_language"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      interfaceLanguage: try container.decodeIfPresent(String.self, forKey: .interfaceLanguage) ?? Self.auto,
      responseLanguage: try container.decodeIfPresent(String.self, forKey: .responseLanguage) ?? Self.auto,
      asrLanguage: try container.decodeIfPresent(String.self, forKey: .asrLanguage) ?? Self.auto,
      ttsLanguage: try container.decodeIfPresent(String.self, forKey: .ttsLanguage) ?? Self.auto
    )
  }

  static func normalizeInterface(_ value: String) -> String {
    let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return interfaceChoices.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } ?? auto
  }

  static func normalizeVoice(_ value: String) -> String {
    let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return voiceChoices.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } ?? auto
  }

  static func resolve(_ value: String) -> String {
    let normalized = normalizeVoice(value)
    guard normalized == auto else { return normalized }
    return Locale.current.identifier.replacingOccurrences(of: "_", with: "-").ifBlank(enUS)
  }

  static func localeIdentifier(for languageTag: String) -> String {
    resolve(languageTag).replacingOccurrences(of: "-", with: "_")
  }

  static func displayName(_ value: String) -> String {
    switch normalizeVoice(value) {
    case zhCN: return "Simplified Chinese"
    case enUS: return "English (United States)"
    case zhHK: return "Traditional Chinese (Hong Kong)"
    case zhTW: return "Traditional Chinese (Taiwan)"
    default: return "Automatic"
    }
  }

  static func interfaceDisplayName(_ value: String) -> String {
    switch normalizeInterface(value) {
    case zhCN: return "Simplified Chinese"
    case en: return "English"
    default: return "Automatic"
    }
  }

  static func modelLanguageName(_ value: String) -> String {
    let resolved = resolve(value)
    if resolved.caseInsensitiveCompare(zhCN) == .orderedSame || resolved.hasPrefix("zh-Hans") {
      return "Simplified Chinese"
    }
    if resolved.caseInsensitiveCompare(zhHK) == .orderedSame ||
       resolved.caseInsensitiveCompare(zhTW) == .orderedSame ||
       resolved.hasPrefix("zh-Hant") {
      return "Traditional Chinese"
    }
    let locale = Locale(identifier: localeIdentifier(for: resolved))
    let english = Locale(identifier: "en_US")
    return english.localizedString(forLanguageCode: locale.languageCode ?? "")?.capitalized ?? "English"
  }
}
