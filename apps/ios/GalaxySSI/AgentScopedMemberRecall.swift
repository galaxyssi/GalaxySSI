import Foundation
import CoreFoundation

enum AgentScopedMemberRecall {
  static let flag = "scoped_member_recall_v1"
  enum Generation: Equatable { case current, next, unavailable }

  static func generation(observed: Int64?, requested: Int64) -> Generation {
    guard AgentRemoteOutcomePolicy.validGeneration(requested) else { return .unavailable }
    if requested == (observed ?? 1) { return .current }
    if requested > 1, observed == requested - 1 { return .next }
    return .unavailable
  }

  static func trueFlag(_ raw: Any?) -> Bool {
    guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
    return number.boolValue
  }
  static func handles(_ payload: [String: Any]) -> Bool {
    payload.string("type") == AgentDesktopCollaborationArchiveRecall.requestType &&
      (payload.string("phase") == "authorize" || payload[flag] != nil)
  }
  static func acceptsResponse(_ payload: [String: Any]) -> Bool {
    let fields: Set<String> = ["type", "contract", "request_id", "phase", "execution_generation", "client_route_id",
      "conversation_id", "task_id", "turn_id", "source_message_id", "contact_id", "agent_id", "result", "message_id"]
    let identityFields = ["client_route_id", "conversation_id", "task_id", "turn_id", "source_message_id", "contact_id", "agent_id"]
    guard Set(payload.keys).isSubset(of: fields), identityFields.allSatisfy({ key in
      guard let value = payload[key] as? String else { return false }
      return !value.isBlank && value.utf8.count <= 200
    }), let nonce = payload["request_id"] as? String, (1...128).contains(nonce.utf8.count),
      let generation = strictInteger(payload["execution_generation"]), AgentRemoteOutcomePolicy.validGeneration(generation),
      payload.string("type") == AgentDesktopCollaborationArchiveRecall.responseType,
      payload.string("contract") == AgentDesktopCollaborationArchiveRecall.contract, payload.string("agent_id") == "codex",
      ["authorize", "read", "confirm"].contains(payload.string("phase")),
      let result = payload["result"] as? [String: Any], let success = result["success"] as? NSNumber,
      CFGetTypeID(success) == CFBooleanGetTypeID() else { return false }
    if payload.string("phase") == "authorize" {
      guard Set(result.keys) == ["success", "status"] else { return false }
      return (trueFlag(result["success"]) && result.string("status") == "authorized") ||
        (!trueFlag(result["success"]) && ["generation_not_ready", "unavailable"].contains(result.string("status")) &&
          (result["success"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true)
    }
    return true
  }
  private static func strictInteger(_ raw: Any?) -> Int64? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 9_007_199_254_740_991,
      Double(number.int64Value) == number.doubleValue else { return nil }
    return number.int64Value
  }

  struct Offer: Codable, Equatable {
    let profile: String
    let desktop: String
    let fingerprint: String
    let route: String
    let contact: String
    let transportBinding: String
    let scope: AgentCollaborationToolEvidenceScope
    let teamID: String
    let personID: UUID
    let primaryMemberID: String
    let model: String
    let effort: AgentModelReasoningEffort
    let deliveryMode: AgentDeliveryMode

    var digest: String { AgentModelLoopRecoveryIdentity.sha256(self) }
    func matchesPeer(_ current: GalaxySSIContact, link: ServerLink) -> Bool {
      current.id == contact && current.isCommunicable && current.deliveryMode == .pcConnector &&
        current.connectorAgentId == "codex" && current.desktopId == desktop && link.paired &&
        link.desktopId == desktop && !fingerprint.isBlank && link.desktopFingerprint == fingerprint &&
        current.identityFingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame &&
        link.routes.clientRouteId == route &&
        GalaxySSITransportReceiptJournal.binding(peerId: desktop, routes: link.routes) == transportBinding
    }
    func matches(_ payload: [String: Any]) -> Bool {
      guard !model.isBlank, !contact.isBlank,
        let invocation = AgentInvocationRequestJsonCodec.encode(modelId: model, reasoningEffort: effort) else { return false }
      let run = deliveryMode == .respond ? scope.runId : AgentControlPlaneActionExecutor.stableRunId(
        conversationId: teamID, turnId: scope.runId, actionId: "agent-team-member", agentId: scope.memberId)
      return Self.original(payload) && AgentScopedMemberRecall.trueFlag(payload[AgentScopedMemberRecall.flag]) &&
        payload.string("contact_id") == contact &&
        payload.string("desktop_id") == desktop && payload.string("client_route_id") == route &&
        payload.string("conversation_id") == scope.conversationId && payload.string("turn_id") == scope.turnId &&
        payload.string("client_message_id") == scope.sourceId && payload.string("task_id") == scope.sourceId &&
        payload.string("team_id") == teamID && payload.string("agent_instance_id") == scope.memberId &&
        payload.string("run_id") == run && payload.string("delivery_mode") == deliveryMode.rawValue &&
        payload["agent_invocation"] as? [String: String] == invocation
    }
    static func original(_ payload: [String: Any]) -> Bool {
      payload.string("type") == "text" && payload["agent_team_message"] == nil &&
        payload.string("agent_id") == "codex" && payload.string("request_kind").isEmpty &&
        payload.string("connector_task_mode").isEmpty && payload["_recovered_task"] == nil &&
        payload["_backend_conversation_id"] == nil && payload.string("execution_mode") == AgentTaskExecutionMode.autoComplete.rawValue &&
        payload.string("result_contract") == AgentOutboundTeamContext.workspaceResultContract
    }
    func encode(_ payload: inout [String: Any]) -> Bool {
      var candidate = payload
      candidate.removeValue(forKey: "agent_team_message")
      candidate[AgentScopedMemberRecall.flag] = true
      guard matches(candidate) else { return false }
      payload = candidate
      return true
    }
  }

  struct Request {
    let payload: [String: Any]
    let phase: String
    let nonce: String
    let expiry: Int64
    let generation: Int64
    let contact: String
    let source: String
    let arguments: AgentMcpJSONObject
    let identity: AgentTaskIdentity
    let fingerprint: String

    init?(_ payload: [String: Any], now: Int64) {
      let phase = payload.string("phase"), nonce = payload.string("request_id")
      let source = payload.string("source_message_id"), contact = payload.string("contact_id")
      let textFields = ["type", "contract", "request_id", "phase", "client_route_id", "conversation_id", "task_id",
        "turn_id", "contact_id", "source_message_id", "agent_id"]
      guard textFields.allSatisfy({ payload[$0] is String }), now >= 0,
        payload.string("type") == AgentDesktopCollaborationArchiveRecall.requestType,
        payload.string("contract") == AgentDesktopCollaborationArchiveRecall.contract,
        payload.string("agent_id") == "codex", ["authorize", "read", "confirm"].contains(phase),
        (1...128).contains(nonce.utf8.count), UUID(uuidString: source) != nil,
        payload.string("task_id") == source,
        payload[AgentScopedMemberRecall.flag] == nil || AgentScopedMemberRecall.trueFlag(payload[AgentScopedMemberRecall.flag]),
        phase == "authorize" || AgentScopedMemberRecall.trueFlag(payload[AgentScopedMemberRecall.flag]),
        let expiry = AgentScopedMemberRecall.strictInteger(payload["expires_at"]), expiry > now, expiry - now <= 60_000,
        let generation = AgentScopedMemberRecall.strictInteger(payload["execution_generation"]), AgentRemoteOutcomePolicy.validGeneration(generation),
        let raw = payload["arguments"] as? [String: Any],
        let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]), data.count <= 4_096,
        let arguments = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else { return nil }
      let fields: Set<String> = ["client_route_id", "conversation_id", "task_id", "turn_id", "contact_id",
        "source_message_id", "agent_id", "execution_generation", "type", "contract", "request_id", "expires_at",
        "phase", "arguments", "message_id", "reply_to", AgentScopedMemberRecall.flag]
      guard Set(payload.keys).isSubset(of: fields.union(["delivery"])) else { return nil }
      if phase == "authorize" {
        guard arguments.isEmpty, Set(payload.keys).isSubset(of: fields), payload["delivery"] == nil else { return nil }
      }
      let identity = AgentTaskIdentity(clientRouteId: payload.string("client_route_id"),
        conversationId: payload.string("conversation_id"), taskId: source, turnId: payload.string("turn_id"))
      guard identity.isComplete, [contact, source, identity.clientRouteId, identity.conversationId, identity.turnId]
        .allSatisfy({ !$0.isBlank && $0.utf8.count <= 200 }),
        phase == "confirm" ? payload["delivery"] is [String: String] : payload["delivery"] == nil else { return nil }
      if phase == "confirm" {
        guard let delivery = payload["delivery"] as? [String: String], Set(delivery.keys) == ["receipt_id", "content_sha256"],
          let receipt = delivery["receipt_id"], (1...128).contains(receipt.utf8.count),
          let hash = delivery["content_sha256"], AgentCollaborationSourceAccess.validDigest(hash) else { return nil }
      }
      self.payload = payload; self.phase = phase; self.nonce = nonce; self.expiry = expiry
      self.generation = generation; self.contact = contact; self.source = source
      self.identity = identity; self.arguments = arguments
      var semantic: [String: Any] = payload.filter { !["message_id", "reply_to"].contains($0.key) }
      semantic["arguments"] = raw
      guard let bytes = try? JSONSerialization.data(withJSONObject: semantic, options: [.sortedKeys]) else { return nil }
      fingerprint = AgentBlobProtocol.sha256(bytes)
    }
  }

  struct Probe: Equatable {
    let offer: Offer
    let generation: Generation
  }

  struct AuthorizationReplay {
    private struct Entry { let fingerprint: String; let offer: String; let waiting: Bool; let expiry: Int64 }
    private var entries: [String: Entry] = [:]
    mutating func pin(_ request: Request, offer: Offer, waiting: Bool, now: Int64) -> Bool {
      entries = entries.filter { $0.value.expiry > now }
      guard request.expiry > now else { return false }
      let key = AgentModelLoopRecoveryIdentity.sha256([offer.desktop, request.nonce])
      if let entry = entries[key] {
        return entry.fingerprint == request.fingerprint && entry.offer == offer.digest && entry.waiting == waiting
      }
      guard entries.count < 128 else { return false }
      entries[key] = Entry(fingerprint: request.fingerprint, offer: offer.digest, waiting: waiting, expiry: request.expiry)
      return true
    }
  }

  static let unavailable: AgentMcpJSONObject = ["success": .bool(false), "status": .string("unavailable")]
  static func authorize(_ request: Request, replay: inout AuthorizationReplay, now: Int64,
                        probe: () -> Probe?) -> AgentMcpJSONObject {
    guard request.phase == "authorize", let first = probe(), let last = probe(), first.offer == last.offer,
      first.generation != .unavailable, last.generation != .unavailable else { return unavailable }
    if first.generation != last.generation {
      guard last.generation == .current, probe() == last else { return unavailable }
    }
    let waiting = last.generation == .next
    guard replay.pin(request, offer: last.offer, waiting: waiting, now: now) else { return unavailable }
    return ["success": .bool(!waiting), "status": .string(waiting ? "generation_not_ready" : "authorized")]
  }
}
