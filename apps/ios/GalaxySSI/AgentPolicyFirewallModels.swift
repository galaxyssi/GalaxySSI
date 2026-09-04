import CryptoKit
import Foundation

enum AgentExternalRequestDirection: String, Codable, CaseIterable, Identifiable {
  case outbound = "OUTBOUND"
  case inbound = "INBOUND"

  var id: String { rawValue }
}

private extension Array where Element == String {
  func stableDistinct() -> [String] {
    var seen = Set<String>()
    return filter { seen.insert($0).inserted }
  }
}

enum AgentPolicyFirewallVerdict: String, Codable, CaseIterable, Identifiable {
  case allow = "ALLOW"
  case requireConfirmation = "REQUIRE_CONFIRMATION"
  case deny = "DENY"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPolicyFirewallVerdict {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .deny
  }
}

struct AgentDelegationDisclosure: Codable, Equatable {
  var contextKeys: Set<String>
  var artifactIds: Set<String>
  var includesConversationHistory: Bool
  var includesInternalMemory: Bool
  var includesSystemPrompt: Bool
  var includesCredentials: Bool

  init(
    contextKeys: Set<String> = [],
    artifactIds: Set<String> = [],
    includesConversationHistory: Bool = false,
    includesInternalMemory: Bool = false,
    includesSystemPrompt: Bool = false,
    includesCredentials: Bool = false
  ) {
    self.contextKeys = contextKeys
    self.artifactIds = artifactIds
    self.includesConversationHistory = includesConversationHistory
    self.includesInternalMemory = includesInternalMemory
    self.includesSystemPrompt = includesSystemPrompt
    self.includesCredentials = includesCredentials
  }

  enum CodingKeys: String, CodingKey {
    case contextKeys = "context_keys"
    case artifactIds = "artifact_ids"
    case includesConversationHistory = "includes_conversation_history"
    case includesInternalMemory = "includes_internal_memory"
    case includesSystemPrompt = "includes_system_prompt"
    case includesCredentials = "includes_credentials"
  }
}

struct AgentExternalPolicyRequest: Codable, Equatable {
  var requestId: String
  var nonce: String
  var direction: AgentExternalRequestDirection
  var sourceTeamId: String
  var destinationTeamId: String
  var requesterAgentId: String
  var targetAgentIds: Set<String>
  var goal: String
  var requiredCapabilities: Set<AgentCapability>
  var disclosure: AgentDelegationDisclosure
  var dataSensitivity: AgentDataSensitivity
  var risk: AgentRisk
  var delegationDepth: Int
  var estimatedCostUnits: Int
  var secureTransport: Bool
  var identityProofVerified: Bool
  var createdAtMillis: Int64
  var expiresAtMillis: Int64

  init(
    requestId: String,
    nonce: String,
    direction: AgentExternalRequestDirection,
    sourceTeamId: String,
    destinationTeamId: String,
    requesterAgentId: String,
    targetAgentIds: Set<String>,
    goal: String,
    requiredCapabilities: Set<AgentCapability> = [],
    disclosure: AgentDelegationDisclosure = AgentDelegationDisclosure(),
    dataSensitivity: AgentDataSensitivity = .personal,
    risk: AgentRisk = .low,
    delegationDepth: Int = 0,
    estimatedCostUnits: Int = 0,
    secureTransport: Bool,
    identityProofVerified: Bool,
    createdAtMillis: Int64,
    expiresAtMillis: Int64
  ) {
    self.requestId = requestId
    self.nonce = nonce
    self.direction = direction
    self.sourceTeamId = sourceTeamId
    self.destinationTeamId = destinationTeamId
    self.requesterAgentId = requesterAgentId
    self.targetAgentIds = targetAgentIds
    self.goal = goal
    self.requiredCapabilities = requiredCapabilities
    self.disclosure = disclosure
    self.dataSensitivity = dataSensitivity
    self.risk = risk
    self.delegationDepth = delegationDepth
    self.estimatedCostUnits = estimatedCostUnits
    self.secureTransport = secureTransport
    self.identityProofVerified = identityProofVerified
    self.createdAtMillis = max(createdAtMillis, 0)
    self.expiresAtMillis = max(expiresAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case requestId = "request_id"
    case nonce
    case direction
    case sourceTeamId = "source_team_id"
    case destinationTeamId = "destination_team_id"
    case requesterAgentId = "requester_agent_id"
    case targetAgentIds = "target_agent_ids"
    case goal
    case requiredCapabilities = "required_capabilities"
    case disclosure
    case dataSensitivity = "data_sensitivity"
    case risk
    case delegationDepth = "delegation_depth"
    case estimatedCostUnits = "estimated_cost_units"
    case secureTransport = "secure_transport"
    case identityProofVerified = "identity_proof_verified"
    case createdAtMillis = "created_at_millis"
    case expiresAtMillis = "expires_at_millis"
  }
}

struct AgentPersonalPolicy: Codable, Equatable {
  var maxDelegationDepth: Int
  var maxTargets: Int
  var maxArtifacts: Int
  var maxGoalCharacters: Int
  var maxEstimatedCostUnits: Int
  var maxRequestLifetimeMillis: Int64
  var allowedContextKeys: Set<String>
  var automaticallyAllowedOutboundTrust: Set<AgentResourceTrust>

  init(
    maxDelegationDepth: Int = 3,
    maxTargets: Int = 12,
    maxArtifacts: Int = 20,
    maxGoalCharacters: Int = 8_000,
    maxEstimatedCostUnits: Int = 32,
    maxRequestLifetimeMillis: Int64 = 10 * 60 * 1_000,
    allowedContextKeys: Set<String> = AgentPersonalPolicy.defaultAllowedContextKeys,
    automaticallyAllowedOutboundTrust: Set<AgentResourceTrust> = [.phoneSystem, .verifiedPaired]
  ) {
    self.maxDelegationDepth = maxDelegationDepth
    self.maxTargets = maxTargets
    self.maxArtifacts = maxArtifacts
    self.maxGoalCharacters = maxGoalCharacters
    self.maxEstimatedCostUnits = maxEstimatedCostUnits
    self.maxRequestLifetimeMillis = maxRequestLifetimeMillis
    self.allowedContextKeys = allowedContextKeys
    self.automaticallyAllowedOutboundTrust = automaticallyAllowedOutboundTrust
  }

  enum CodingKeys: String, CodingKey {
    case maxDelegationDepth = "max_delegation_depth"
    case maxTargets = "max_targets"
    case maxArtifacts = "max_artifacts"
    case maxGoalCharacters = "max_goal_characters"
    case maxEstimatedCostUnits = "max_estimated_cost_units"
    case maxRequestLifetimeMillis = "max_request_lifetime_millis"
    case allowedContextKeys = "allowed_context_keys"
    case automaticallyAllowedOutboundTrust = "automatically_allowed_outbound_trust"
  }

  static let defaultAllowedContextKeys: Set<String> = [
    "objective",
    "constraints",
    "expected_output",
    "evidence",
    "artifact_manifest",
    "trace_parent",
    "locale",
    "deadline",
    "budget"
  ]
}

struct AgentPolicyFirewallDecision: Codable, Equatable {
  var verdict: AgentPolicyFirewallVerdict
  var requestId: String
  var reasonCodes: [String]
  var requiredGrants: [AgentPermissionRequest]
  var matchedGrantIds: Set<String>
  var evaluatedAtMillis: Int64
  var replayClaimed: Bool

  var allowed: Bool { verdict == .allow }

  init(
    verdict: AgentPolicyFirewallVerdict,
    requestId: String,
    reasonCodes: [String],
    requiredGrants: [AgentPermissionRequest] = [],
    matchedGrantIds: Set<String> = [],
    evaluatedAtMillis: Int64,
    replayClaimed: Bool = false
  ) {
    self.verdict = verdict
    self.requestId = requestId
    self.reasonCodes = reasonCodes.stableDistinct()
    self.requiredGrants = requiredGrants
    self.matchedGrantIds = matchedGrantIds
    self.evaluatedAtMillis = max(evaluatedAtMillis, 0)
    self.replayClaimed = replayClaimed
  }

  enum CodingKeys: String, CodingKey {
    case verdict
    case requestId = "request_id"
    case reasonCodes = "reason_codes"
    case requiredGrants = "required_grants"
    case matchedGrantIds = "matched_grant_ids"
    case evaluatedAtMillis = "evaluated_at_millis"
    case replayClaimed = "replay_claimed"
  }
}

struct AgentPolicyFirewallAuditEvent: Codable, Equatable, Identifiable {
  var eventId: String
  var requestId: String
  var direction: AgentExternalRequestDirection
  var sourceTeamId: String
  var destinationTeamId: String
  var requesterAgentId: String
  var targetAgentIds: Set<String>
  var verdict: AgentPolicyFirewallVerdict
  var reasonCodes: [String]
  var dataSensitivity: AgentDataSensitivity
  var risk: AgentRisk
  var capabilityNames: Set<String>
  var artifactCount: Int
  var goalHash: String
  var evaluatedAtMillis: Int64

  var id: String { eventId }

  enum CodingKeys: String, CodingKey {
    case eventId = "event_id"
    case requestId = "request_id"
    case direction
    case sourceTeamId = "source_team_id"
    case destinationTeamId = "destination_team_id"
    case requesterAgentId = "requester_agent_id"
    case targetAgentIds = "target_agent_ids"
    case verdict
    case reasonCodes = "reason_codes"
    case dataSensitivity = "data_sensitivity"
    case risk
    case capabilityNames = "capabilities"
    case artifactCount = "artifact_count"
    case goalHash = "goal_hash"
    case evaluatedAtMillis = "evaluated_at_millis"
  }
}

protocol AgentPolicyReplayStore: AnyObject {
  func claim(requestId: String, nonce: String, expiresAtMillis: Int64, nowMillis: Int64) -> Bool
  func clear()
}

private struct AgentPolicyReplayClaim: Equatable {
  var requestId: String
  var nonceHash: String
  var expiresAtMillis: Int64
}

final class InMemoryAgentPolicyReplayStore: AgentPolicyReplayStore {
  private let lock = NSRecursiveLock()
  private var claims: [String: AgentPolicyReplayClaim] = [:]

  func claim(
    requestId: String,
    nonce: String,
    expiresAtMillis: Int64,
    nowMillis: Int64
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    claims = claims.filter { $0.value.expiresAtMillis > nowMillis }
    let nonceHash = agentPolicySha256(nonce)
    if claims[requestId] != nil || claims.values.contains(where: { $0.nonceHash == nonceHash }) {
      return false
    }
    claims[requestId] = AgentPolicyReplayClaim(
      requestId: requestId,
      nonceHash: nonceHash,
      expiresAtMillis: expiresAtMillis
    )
    return true
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    claims.removeAll()
  }
}

protocol AgentPolicyFirewallAuditStore: AnyObject {
  func append(_ event: AgentPolicyFirewallAuditEvent)
  func list() -> [AgentPolicyFirewallAuditEvent]
  func clear()
}

final class InMemoryAgentPolicyFirewallAuditStore: AgentPolicyFirewallAuditStore {
  private let lock = NSRecursiveLock()
  private var events: [AgentPolicyFirewallAuditEvent] = []

  func append(_ event: AgentPolicyFirewallAuditEvent) {
    lock.lock()
    defer { lock.unlock() }
    events.append(event)
  }

  func list() -> [AgentPolicyFirewallAuditEvent] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    events.removeAll()
  }
}

final class AgentPersonalPolicyFirewall {
  static let DELEGATION_SCOPE = "galaxyssi.agent.external_delegate"

  private let grantStore: InMemoryAgentPermissionGrantStore
  private let replayStore: AgentPolicyReplayStore
  private let auditStore: AgentPolicyFirewallAuditStore
  private let policy: AgentPersonalPolicy
  private let clock: () -> Int64

  init(
    grantStore: InMemoryAgentPermissionGrantStore,
    replayStore: AgentPolicyReplayStore = InMemoryAgentPolicyReplayStore(),
    auditStore: AgentPolicyFirewallAuditStore = InMemoryAgentPolicyFirewallAuditStore(),
    policy: AgentPersonalPolicy = AgentPersonalPolicy(),
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.grantStore = grantStore
    self.replayStore = replayStore
    self.auditStore = auditStore
    self.policy = policy
    self.clock = clock
  }

  func evaluate(
    _ request: AgentExternalPolicyRequest,
    registrations: [AgentRegistration]
  ) -> AgentPolicyFirewallDecision {
    decide(request, registrations: registrations, consume: false)
  }

  func admit(
    _ request: AgentExternalPolicyRequest,
    registrations: [AgentRegistration]
  ) -> AgentPolicyFirewallDecision {
    decide(request, registrations: registrations, consume: true)
  }

  func auditEvents() -> [AgentPolicyFirewallAuditEvent] {
    auditStore.list()
  }

  private func decide(
    _ request: AgentExternalPolicyRequest,
    registrations: [AgentRegistration],
    consume: Bool
  ) -> AgentPolicyFirewallDecision {
    let now = max(clock(), 0)
    var registrationsById: [String: AgentRegistration] = [:]
    registrations.forEach { registrationsById[$0.agentId] = $0 }
    let hardDenials = hardDenials(request, registrationsById: registrationsById, now: now)
    if !hardDenials.isEmpty {
      let denial = decision(request, verdict: .deny, reasons: hardDenials, nowMillis: now)
      audit(request, denial)
      return denial
    }

    let participants = policyParticipants(request, registrationsById: registrationsById)
    let grantRequests = participants.map { registration in
      AgentPermissionRequest(
        subjectType: .agent,
        subjectId: registration.agentId,
        scope: Self.DELEGATION_SCOPE,
        action: request.direction.rawValue.lowercased(),
        resource: request.sourceTeamId,
        target: request.destinationTeamId
      )
    }
    let grantDecisions = grantRequests.map { permission in
      (permission, grantDecision(permission, consume: false))
    }
    let matchedGrantIds = Set(grantDecisions.compactMap { $0.1.grant?.grantId })
    let allGranted = grantDecisions.allSatisfy { $0.1.granted }
    let freshSingleUseRequired = requiresFreshSingleUseGrant(request)
    let freshSingleUseGranted = allGranted && grantDecisions.allSatisfy { $0.1.grant?.lifetime == .singleUse }
    let reasons = confirmationReasons(
      request: request,
      participants: participants,
      allGranted: allGranted,
      freshSingleUseRequired: freshSingleUseRequired,
      freshSingleUseGranted: freshSingleUseGranted
    )
    if !reasons.isEmpty {
      let confirmation = decision(
        request,
        verdict: .requireConfirmation,
        reasons: reasons,
        nowMillis: now,
        requiredGrants: grantRequests,
        matchedGrantIds: matchedGrantIds
      )
      audit(request, confirmation)
      return confirmation
    }

    if !consume {
      let allowed = decision(
        request,
        verdict: .allow,
        reasons: [allGranted ? "explicit_grant_active" : "trusted_low_risk_outbound"],
        nowMillis: now,
        matchedGrantIds: matchedGrantIds
      )
      audit(request, allowed)
      return allowed
    }

    let replayClaimed = replayStore.claim(
      requestId: request.requestId,
      nonce: request.nonce,
      expiresAtMillis: request.expiresAtMillis,
      nowMillis: now
    )
    if !replayClaimed {
      let denial = decision(
        request,
        verdict: .deny,
        reasons: ["replay_detected"],
        nowMillis: now
      )
      audit(request, denial)
      return denial
    }

    var consumedGrantIds = Set<String>()
    if allGranted {
      for permission in grantRequests {
        let consumed = grantDecision(permission, consume: true)
        guard consumed.granted else {
          let denial = decision(
            request,
            verdict: .deny,
            reasons: ["grant_consumption_failed"],
            nowMillis: now,
            matchedGrantIds: consumedGrantIds,
            replayClaimed: true
          )
          audit(request, denial)
          return denial
        }
        if let grantId = consumed.grant?.grantId {
          consumedGrantIds.insert(grantId)
        }
      }
    }

    let allowed = decision(
      request,
      verdict: .allow,
      reasons: [allGranted ? "explicit_grant_consumed" : "trusted_low_risk_outbound"],
      nowMillis: now,
      matchedGrantIds: consumedGrantIds,
      replayClaimed: true
    )
    audit(request, allowed)
    return allowed
  }

  private func hardDenials(
    _ request: AgentExternalPolicyRequest,
    registrationsById: [String: AgentRegistration],
    now: Int64
  ) -> [String] {
    var reasons: [String] = []
    if request.requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request.requestId.count > Self.maxIdCharacters {
      reasons.append("request_id_invalid")
    }
    if request.nonce.count < Self.minNonceCharacters || request.nonce.count > Self.maxNonceCharacters {
      reasons.append("nonce_invalid")
    }
    if request.sourceTeamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      request.destinationTeamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      request.sourceTeamId.count > Self.maxIdCharacters ||
      request.destinationTeamId.count > Self.maxIdCharacters {
      reasons.append("team_identity_invalid")
    }
    if request.sourceTeamId == request.destinationTeamId {
      reasons.append("cross_team_boundary_missing")
    }
    if request.requesterAgentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      request.requesterAgentId.count > Self.maxIdCharacters {
      reasons.append("requester_identity_invalid")
    }
    if request.targetAgentIds.isEmpty || request.targetAgentIds.count > policy.maxTargets {
      reasons.append("target_count_invalid")
    }
    if request.targetAgentIds.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.count > Self.maxIdCharacters }) {
      reasons.append("target_identity_invalid")
    }
    if request.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request.goal.count > policy.maxGoalCharacters {
      reasons.append("goal_boundary_invalid")
    }
    if !request.secureTransport {
      reasons.append("secure_transport_required")
    }
    if !request.identityProofVerified {
      reasons.append("identity_proof_required")
    }
    if request.createdAtMillis > now + Self.maxClockSkewMillis {
      reasons.append("request_from_future")
    }
    if request.expiresAtMillis <= now {
      reasons.append("request_expired")
    }
    if request.expiresAtMillis <= request.createdAtMillis ||
      request.expiresAtMillis - request.createdAtMillis > policy.maxRequestLifetimeMillis {
      reasons.append("request_lifetime_invalid")
    }
    if request.delegationDepth < 0 || request.delegationDepth > policy.maxDelegationDepth {
      reasons.append("delegation_depth_exceeded")
    }
    if request.estimatedCostUnits < 0 || request.estimatedCostUnits > policy.maxEstimatedCostUnits {
      reasons.append("budget_exceeded")
    }
    if request.disclosure.artifactIds.count > policy.maxArtifacts {
      reasons.append("artifact_count_exceeded")
    }
    if request.disclosure.includesConversationHistory {
      reasons.append("conversation_history_forbidden")
    }
    if request.disclosure.includesInternalMemory {
      reasons.append("internal_memory_forbidden")
    }
    if request.disclosure.includesSystemPrompt {
      reasons.append("system_prompt_forbidden")
    }
    if request.disclosure.includesCredentials {
      reasons.append("credentials_forbidden")
    }
    if !policy.allowedContextKeys.isSuperset(of: request.disclosure.contextKeys) {
      reasons.append("context_boundary_violation")
    }
    if request.risk == .blocked {
      reasons.append("blocked_risk")
    }

    let participantIds = request.direction == .outbound ? request.targetAgentIds : Set([request.requesterAgentId])
    let participants = participantIds.compactMap { registrationsById[$0] }
    if participants.count != participantIds.count {
      reasons.append("participant_not_registered")
    }
    if participants.contains(where: { $0.trust == .unknown }) {
      reasons.append("participant_not_trusted")
    }
    let routableStatuses: Set<AgentEndpointStatus> = [.online, .idle, .busy]
    if participants.contains(where: { !routableStatuses.contains($0.status) }) {
      reasons.append("participant_not_routable")
    }
    let targetRegistrations = request.targetAgentIds.compactMap { registrationsById[$0] }
    if targetRegistrations.count != request.targetAgentIds.count {
      reasons.append("target_not_registered")
    }
    let availableCapabilities = targetRegistrations.reduce(into: Set<AgentCapability>()) { result, registration in
      result.formUnion(registration.capabilities)
    }
    if !availableCapabilities.isSuperset(of: request.requiredCapabilities) {
      reasons.append("capability_contract_unmet")
    }
    if request.dataSensitivity == .restricted &&
      targetRegistrations.contains(where: { ![AgentResourceTrust.phoneSystem, .verifiedPaired].contains($0.trust) }) {
      reasons.append("restricted_data_boundary")
    }
    return reasons.stableDistinct()
  }

  private func policyParticipants(
    _ request: AgentExternalPolicyRequest,
    registrationsById: [String: AgentRegistration]
  ) -> [AgentRegistration] {
    let registrations: [AgentRegistration]
    switch request.direction {
    case .outbound:
      registrations = request.targetAgentIds.compactMap { registrationsById[$0] }
    case .inbound:
      registrations = [registrationsById[request.requesterAgentId]].compactMap { $0 }
    }
    var seen = Set<String>()
    return registrations.filter { seen.insert($0.agentId).inserted }
  }

  private func confirmationReasons(
    request: AgentExternalPolicyRequest,
    participants: [AgentRegistration],
    allGranted: Bool,
    freshSingleUseRequired: Bool,
    freshSingleUseGranted: Bool
  ) -> [String] {
    var reasons: [String] = []
    if freshSingleUseRequired && !freshSingleUseGranted {
      return ["fresh_single_use_grant_required"]
    }
    if allGranted {
      return []
    }
    if request.direction == .inbound {
      reasons.append("inbound_request_requires_grant")
    }
    if request.dataSensitivity == .confidential || request.dataSensitivity == .restricted {
      reasons.append("sensitive_data_requires_grant")
    }
    if !request.disclosure.artifactIds.isEmpty {
      reasons.append("artifacts_require_grant")
    }
    if participants.contains(where: { !policy.automaticallyAllowedOutboundTrust.contains($0.trust) }) {
      reasons.append("external_trust_boundary_requires_grant")
    }
    return reasons.stableDistinct()
  }

  private func requiresFreshSingleUseGrant(_ request: AgentExternalPolicyRequest) -> Bool {
    request.dataSensitivity == .restricted ||
      request.risk.weight >= AgentRisk.high.weight ||
      !request.requiredCapabilities.isDisjoint(with: [.deviceControl, .appNavigation, .systemSettings])
  }

  private func grantDecision(
    _ request: AgentPermissionRequest,
    consume: Bool
  ) -> AgentPermissionDecision {
    (try? grantStore.authorize(request, consume: consume)) ??
      AgentPermissionDecision(granted: false, grant: nil, reason: "host_grant_error")
  }

  private func decision(
    _ request: AgentExternalPolicyRequest,
    verdict: AgentPolicyFirewallVerdict,
    reasons: [String],
    nowMillis: Int64,
    requiredGrants: [AgentPermissionRequest] = [],
    matchedGrantIds: Set<String> = [],
    replayClaimed: Bool = false
  ) -> AgentPolicyFirewallDecision {
    AgentPolicyFirewallDecision(
      verdict: verdict,
      requestId: request.requestId,
      reasonCodes: reasons,
      requiredGrants: requiredGrants,
      matchedGrantIds: matchedGrantIds,
      evaluatedAtMillis: nowMillis,
      replayClaimed: replayClaimed
    )
  }

  private func audit(
    _ request: AgentExternalPolicyRequest,
    _ decision: AgentPolicyFirewallDecision
  ) {
    auditStore.append(AgentPolicyFirewallAuditEvent(
      eventId: "\(request.requestId):\(decision.evaluatedAtMillis):\(decision.verdict.rawValue)",
      requestId: request.requestId,
      direction: request.direction,
      sourceTeamId: request.sourceTeamId,
      destinationTeamId: request.destinationTeamId,
      requesterAgentId: request.requesterAgentId,
      targetAgentIds: request.targetAgentIds,
      verdict: decision.verdict,
      reasonCodes: decision.reasonCodes,
      dataSensitivity: request.dataSensitivity,
      risk: request.risk,
      capabilityNames: Set(request.requiredCapabilities.map(\.rawValue)),
      artifactCount: request.disclosure.artifactIds.count,
      goalHash: agentPolicySha256(request.goal),
      evaluatedAtMillis: decision.evaluatedAtMillis
    ))
  }

  private static let minNonceCharacters = 16
  private static let maxNonceCharacters = 256
  private static let maxIdCharacters = 256
  private static let maxClockSkewMillis: Int64 = 30_000
}

private func agentPolicySha256(_ value: String) -> String {
  SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}
