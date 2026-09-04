import Foundation

struct AgentAttentionDecisionRecord: Codable, Equatable, Identifiable {
  var id: String { messageId }
  var messageId: String
  var decision: AgentAttentionDecision
  var relatedGoal: String
  var whyNow: String
  var impactIfIgnored: String
  var createdAtMillis: Int64
}

final class AgentAttentionDecisionStore {
  private struct State: Codable { var records: [String: AgentAttentionDecisionRecord] = [:] }

  static let defaultKey = "galaxyssi-ios-attention-decisions-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentAttentionDecisionStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func get(messageId: String) -> AgentAttentionDecisionRecord? {
    locked { load().records[messageId.trimmingCharacters(in: .whitespacesAndNewlines)] }
  }

  func save(_ value: AgentAttentionDecisionRecord) {
    guard !value.messageId.isBlank else { return }
    locked {
      var state = load()
      state.records[value.messageId] = value
      state.records = Dictionary(uniqueKeysWithValues: state.records.values
        .sorted { $0.createdAtMillis > $1.createdAtMillis }.prefix(2_000).map { ($0.messageId, $0) })
      persist(state)
    }
  }

  func list(limit: Int = 2_000) -> [AgentAttentionDecisionRecord] {
    locked { Array(load().records.values.sorted { $0.createdAtMillis > $1.createdAtMillis }.prefix(min(max(limit, 1), 2_000))) }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }

  private func persist(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

enum AgentAttentionBudgetRuntime {
  static func decide(
    message: GlobalProactiveMessage,
    threshold: Double,
    store: AgentAttentionDecisionStore = AgentAttentionDecisionStore(),
    device: AgentDeviceEvalSnapshot = AgentDeviceEvalProbe.capture()
  ) -> AgentAttentionDecisionRecord {
    if let existing = store.get(messageId: message.id) { return existing }
    let actionTerms = ["recommend", "risk", "opportunity", "should", "\u{5efa}\u{8bae}", "\u{98ce}\u{9669}", "\u{673a}\u{4f1a}"]
    let relevance: Double
    switch message.target {
    case .currentConversation: relevance = 0.97
    case .newConversation: relevance = 0.90
    case .globalDigest: relevance = 0.72
    }
    let candidate = AgentAttentionCandidate(
      relevance: relevance,
      novelty: AgentEvalClock.nowMillis() - message.createdAtMillis <= 24 * 60 * 60_000 ? 0.96 : 0.72,
      credibility: message.causalEventIds.isEmpty ? 0.72 : 0.96,
      actionability: actionTerms.contains { message.content.localizedCaseInsensitiveContains($0) } ? 0.96 : 0.62,
      interruptionCost: message.urgent ? 0.10 : {
        switch message.target {
        case .currentConversation: return 0.20
        case .newConversation: return 0.38
        case .globalDigest: return 0.12
        }
      }(),
      tokenCost: min(max(Double(message.content.count) / 4_000, 0.03), 0.75),
      batteryCost: device.powerSaveMode || (0...15).contains(device.batteryPercent) ? 0.78 : 0.10,
      urgent: message.urgent
    )
    let record = AgentAttentionDecisionRecord(
      messageId: message.id,
      decision: AgentAttentionBudgetPolicy.evaluate(candidate: candidate, threshold: threshold),
      relatedGoal: String(message.topic.prefix(1_000)),
      whyNow: message.urgent ? "A time-sensitive risk or conflict was detected." : "New evidence became relevant to this topic.",
      impactIfIgnored: message.urgent ? "The current plan may continue with an unresolved material risk." : "A useful decision or follow-up may be delayed.",
      createdAtMillis: AgentEvalClock.nowMillis()
    )
    store.save(record)
    return record
  }
}

enum AgentCognitiveEvalBridge {
  static func shouldNotify(_ message: GlobalProactiveMessage) -> Bool {
    let threshold = AgentEvalOpsStore().settings().attentionThreshold
    return AgentAttentionBudgetRuntime.decide(message: message, threshold: threshold).decision.disposition == .notifyNow
  }

  static func recordDelivered(_ messages: [GlobalProactiveMessage]) {
    let store = AgentEvalOpsStore()
    let threshold = store.settings().attentionThreshold
    messages.forEach { message in
      _ = store.recordProactiveDelivery(
        message,
        attention: AgentAttentionBudgetRuntime.decide(message: message, threshold: threshold)
      )
    }
  }

  static func recordFeedback(messageId: String, kind: GlobalAgentFeedbackKind) {
    let pair: (Bool, Bool)
    switch kind {
    case .helpful: pair = (true, true)
    case .notRelevant: pair = (false, false)
    case .tooFrequent: pair = (true, false)
    }
    let store = AgentEvalOpsStore()
    _ = store.recordProactiveFeedback(runId: store.proactiveRunId(messageId), relevant: pair.0, accepted: pair.1)
  }
}

struct AgentProtocolEndpointGrant: Codable, Equatable, Identifiable {
  var id: String { "\(protocolKind.rawValue):\(endpointId)" }
  var endpointId: String
  var protocolKind: AgentStandardProtocol
  var displayName: String
  var identityFingerprint: String
  var allowedCapabilities: Set<AgentCapability>
  var enabled: Bool
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
}

final class AgentProtocolEndpointGrantStore {
  private struct State: Codable { var grants: [String: AgentProtocolEndpointGrant] = [:] }

  static let defaultKey = "galaxyssi-ios-protocol-endpoint-grants-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentProtocolEndpointGrantStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  @discardableResult
  func save(_ value: AgentProtocolEndpointGrant) -> Bool {
    var value = value
    value.endpointId = String(value.endpointId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    value.displayName = String(value.displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    value.identityFingerprint = String(value.identityFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
    value.updatedAtMillis = AgentEvalClock.nowMillis()
    guard !value.endpointId.isEmpty, !value.identityFingerprint.isEmpty else { return false }
    locked {
      var state = load()
      state.grants[value.id] = value
      persist(state)
    }
    return true
  }

  func get(protocolKind: AgentStandardProtocol, endpointId: String) -> AgentProtocolEndpointGrant? {
    locked { load().grants["\(protocolKind.rawValue):\(endpointId.trimmingCharacters(in: .whitespacesAndNewlines))"] }
  }

  func list() -> [AgentProtocolEndpointGrant] {
    locked { load().grants.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }

  private func persist(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

struct AgentProtocolInboundDecision: Equatable {
  var allowed: Bool
  var request: AgentRunRequest?
  var reason: String
  var endpointId: String
  var protocolKind: AgentStandardProtocol
}

final class AgentProtocolBoundaryGateway {
  private let grants: AgentProtocolEndpointGrantStore
  private let settings: () -> AgentEvalOpsSettings

  init(
    grants: AgentProtocolEndpointGrantStore = AgentProtocolEndpointGrantStore(),
    settings: @escaping () -> AgentEvalOpsSettings = { AgentEvalOpsStore().settings() }
  ) {
    self.grants = grants
    self.settings = settings
  }

  func decodeInbound(
    protocolKind: AgentStandardProtocol,
    endpointId: String,
    payload: AgentMcpJSONObject
  ) -> AgentProtocolInboundDecision {
    let endpointId = endpointId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard settings().protocolAdaptersEnabled else { return denied(protocolKind, endpointId, "protocol_adapters_disabled") }
    guard [.acp, .a2a].contains(protocolKind) else {
      return denied(protocolKind, endpointId, "protocol_uses_dedicated_permission_runtime")
    }
    guard let data = try? JSONEncoder().encode(AgentMcpJSONValue.object(payload)), data.count <= 256 * 1_024 else {
      return denied(protocolKind, endpointId, "payload_too_large")
    }
    guard let grant = grants.get(protocolKind: protocolKind, endpointId: endpointId) else {
      return denied(protocolKind, endpointId, "endpoint_not_authorized")
    }
    guard grant.enabled else { return denied(protocolKind, endpointId, "endpoint_disabled") }
    let request = protocolKind == .acp
      ? AgentACPBoundaryAdapter().decodeRequest(payload)
      : AgentA2ABoundaryAdapter().decodeRequest(payload)
    guard let request else { return denied(protocolKind, endpointId, "malformed_request") }
    guard grant.allowedCapabilities.isSuperset(of: request.requiredCapabilities) else {
      return denied(protocolKind, endpointId, "capability_not_granted")
    }
    guard !request.goal.isBlank, request.goal.count <= 8_000 else {
      return denied(protocolKind, endpointId, "invalid_goal")
    }
    return AgentProtocolInboundDecision(
      allowed: true, request: request, reason: "authorized", endpointId: endpointId, protocolKind: protocolKind
    )
  }

  private func denied(
    _ protocolKind: AgentStandardProtocol,
    _ endpointId: String,
    _ reason: String
  ) -> AgentProtocolInboundDecision {
    AgentProtocolInboundDecision(
      allowed: false, request: nil, reason: reason, endpointId: endpointId, protocolKind: protocolKind
    )
  }
}
