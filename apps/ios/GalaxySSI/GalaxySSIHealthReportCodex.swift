import Foundation

enum GalaxySSIHealthReportCodex {
  static let prefix = "health-report-vision:"
  static let maximumImageBytes = 224 * 1024
  static let maximumReplyBytes = 131_072

  static func supports(_ contact: GalaxySSIContact, now: Date = Date()) -> Bool {
    contact.isCommunicable && contact.connectorAgentId == "codex" && contact.deliveryMode.isGalaxySSILinkFamily &&
      contact.private_health_report_vision_v1 == true && AgentConnectorAvailability.desktopAgentReady(contact: contact, now: now)
  }

  struct Target: Equatable {
    let route: GalaxySSIHealthDesktopResearch.Route
    let authority: String
    var title: String { authority + " / Auto \u{00B7} Codex / " + route.connector.modelId }
  }

  struct Request: Equatable {
    let id: UUID
    let target: Target
    let source: Int64
    let identity: AgentTaskIdentity

    init(target: Target, id: UUID = UUID()) {
      self.id = id; self.target = target
      source = max(1, Int64(AgentModelLoopRecoveryIdentity.sha256(id.uuidString).prefix(13), radix: 16) ?? 0)
      identity = .init(clientRouteId: target.route.connector.clientRouteId, conversationId: prefix + id.uuidString,
        taskId: id.uuidString, turnId: id.uuidString)
    }

    func payload(jpeg: Data, instructions: String) throws -> [String: Any] {
      guard (1...maximumImageBytes).contains(jpeg.count), jpeg.starts(with: [0xff, 0xd8]),
            !instructions.isBlank, instructions.utf8.count <= 16_384,
            let invocation = AgentInvocationRequestJsonCodec.encode(modelId: target.route.connector.modelId,
              reasoningEffort: target.route.connector.reasoningEffort), invocation["model_id"] == target.route.connector.modelId
      else { throw MqttRouteError.invalidPayload }
      return ["type": "text", "message_id": id.uuidString, "content": instructions,
        "request_kind": "screen_analysis", "execution_mode": "auto_complete", "response_language": "auto",
        "contact_id": target.route.connector.contactId, "desktop_id": target.route.connector.desktopId,
        "agent_id": "codex", "client_route_id": identity.clientRouteId, "conversation_id": identity.conversationId,
        "task_id": identity.taskId, "turn_id": identity.turnId, "client_message_id": source, "source_message_id": String(source),
        "attachments": [["id": id.uuidString, "name": "report.jpg", "mime_type": "image/jpeg", "size": jpeg.count,
          "transport_size": jpeg.count, "data_b64": jpeg.base64EncodedString()]], "agent_invocation": invocation]
    }

    var cancellation: [String: Any] {
      ["type": "agent_task_cancel", "message_id": UUID().uuidString, "agent_id": "codex",
       "contact_id": target.route.connector.contactId, "desktop_id": target.route.connector.desktopId,
       "client_route_id": identity.clientRouteId, "conversation_id": identity.conversationId,
       "task_id": identity.taskId, "turn_id": identity.turnId, "source_message_id": String(source)]
    }

    func matches(_ payload: [String: Any], desktop: String, route: String) -> Bool {
      desktop == target.route.connector.desktopId && route == identity.clientRouteId &&
        payload.string("client_route_id") == identity.clientRouteId &&
        payload.string("contact_id") == target.route.connector.contactId && payload.string("agent_id") == "codex" &&
        payload.string("conversation_id") == identity.conversationId && payload.string("task_id") == identity.taskId &&
        payload.string("turn_id") == identity.turnId &&
        payload.string("source_message_id").ifBlank(String(payload.int("source_message_id"))) == String(source)
    }

    var evidenceBinding: AgentDesktopReplyBinding? {
      let record = AgentManagedResponseRecord(ownerRunId: prefix + id.uuidString, supervisorRunId: id.uuidString,
        agentId: "codex", deliveryMode: .observe, sourceMessageId: source, contactId: target.route.connector.contactId,
        conversationId: identity.conversationId, turnId: identity.turnId, taskId: identity.taskId,
        createdAtMillis: AgentControlPlaneClock.nowMillis())
      return .managed(record: record, desktopId: target.route.connector.desktopId, agentId: "codex", identity: identity)
    }
  }

  // This allowlist is deliberately separate from durable chat and recovery-query wire policies.
  static func acceptsOutgoing(_ payload: [String: Any], desktop: String, route: String) -> Bool {
    let conversation = payload.string("conversation_id")
    guard conversation.hasPrefix(prefix), let id = UUID(uuidString: String(conversation.dropFirst(prefix.count))),
          conversation == prefix + id.uuidString, payload.string("task_id") == id.uuidString,
          payload.string("turn_id") == id.uuidString, payload.string("agent_id") == "codex",
          payload.string("desktop_id") == desktop, payload.string("client_route_id") == route,
          !route.isBlank, !payload.string("contact_id").isBlank,
          Int64(payload.string("source_message_id")) == max(1, Int64(AgentModelLoopRecoveryIdentity.sha256(id.uuidString).prefix(13), radix: 16) ?? 0),
          UUID(uuidString: payload.string("message_id")) != nil else { return false }
    let base: Set<String> = ["type", "message_id", "agent_id", "contact_id", "desktop_id", "client_route_id",
      "conversation_id", "task_id", "turn_id", "source_message_id"]
    switch payload.string("type") {
    case "text":
      guard Set(payload.keys) == base.union(["content", "request_kind", "execution_mode", "response_language",
        "client_message_id", "attachments", "agent_invocation"]), payload.string("request_kind") == "screen_analysis",
        payload.string("execution_mode") == "auto_complete", payload.string("response_language") == "auto",
        !payload.string("content").isBlank, payload.string("content").utf8.count <= 16_384,
        String(payload.int("client_message_id")) == payload.string("source_message_id"),
        let invocation = payload["agent_invocation"] as? [String: String], Set(invocation.keys) == ["model_id", "reasoning_effort"],
        !(invocation["model_id"] ?? "").isBlank, (invocation["model_id"] ?? "").utf8.count <= 200,
        AgentModelReasoningEffort(rawValue: invocation["reasoning_effort"] ?? "") != nil,
        let attachments = payload["attachments"] as? [[String: Any]], attachments.count == 1, let image = attachments.first,
        Set(image.keys) == ["id", "name", "mime_type", "size", "transport_size", "data_b64"],
        image.string("id") == id.uuidString, image.string("name") == "report.jpg", image.string("mime_type") == "image/jpeg",
        image.string("data_b64").utf8.count <= (maximumImageBytes + 2) / 3 * 4,
        let data = Data(base64Encoded: image.string("data_b64")), (1...maximumImageBytes).contains(data.count),
        data.starts(with: [0xff, 0xd8]), image.int("size") == data.count, image.int("transport_size") == data.count
      else { return false }
      return true
    case "agent_task_cancel": return Set(payload.keys) == base
    case "agent_task_result_received":
      return Set(payload.keys) == base.union(["execution_generation", "sha256", "receipt_id"]) &&
        AgentResultReceipt.fromPayload(payload, desktopId: desktop).map {
          $0.executionGeneration == 1 && $0.id == payload.string("receipt_id")
        } == true
    default: return false
    }
  }
}

@MainActor
final class GalaxySSIHealthReportCodexExchange {
  enum Outcome: Equatable { case result(String), failed }
  private struct Pending { let request: GalaxySSIHealthReportCodex.Request; var outcome: Outcome? }
  private var active: [String: Pending] = [:]

  func begin(_ request: GalaxySSIHealthReportCodex.Request) throws {
    guard active.count < 4, active[request.identity.conversationId] == nil else { throw MqttRouteError.invalidPayload }
    active[request.identity.conversationId] = Pending(request: request)
  }
  func outcome(_ request: GalaxySSIHealthReportCodex.Request) -> Outcome? { active[request.identity.conversationId]?.outcome }
  func finish(_ request: GalaxySSIHealthReportCodex.Request) { active.removeValue(forKey: request.identity.conversationId) }
  func removeAll() { active.removeAll() }

  func receive(_ payload: [String: Any], desktop: String, route: String) -> AgentResultReceipt? {
    let key = payload.string("conversation_id")
    guard var pending = active[key], pending.request.matches(payload, desktop: desktop, route: route),
          payload["peer_chat"] as? Bool != true, pending.outcome == nil else { return nil }
    let status = AgentRemoteOutcomePolicy.normalizedStatus(payload.string("task_status").ifBlank(payload.string("status")))
    guard ["text", "agent_task_event"].contains(payload.string("type")),
          AgentRemoteOutcomePolicy.isTerminal(status),
          (Int64(payload.string("execution_generation")) ?? Int64(payload.int("execution_generation"))) == 1 else { return nil }
    if AgentRemoteOutcomePolicy.isFailure(status) { pending.outcome = .failed }
    else if payload.string("type") == "text", status == "completed" {
      let content = payload.string("content").ifBlank(payload.string("text"))
      pending.outcome = payload["success"] as? Bool != false && !content.isBlank &&
        content.utf8.count <= GalaxySSIHealthReportCodex.maximumReplyBytes && emptyText(payload["rich_output"]) &&
        emptyText(payload["rich_output_json"]) && (payload["attachments"] == nil || payload["attachments"] is NSNull ||
          (payload["attachments"] as? [Any])?.isEmpty == true) ? .result(content) : .failed
    }
    active[key] = pending
    guard pending.outcome != nil, payload.string("type") == "text" else { return nil }
    return AgentResultReceipt.fromPayload(payload, desktopId: desktop)
  }

  private func emptyText(_ value: Any?) -> Bool {
    value == nil || value is NSNull || (value as? String)?.isEmpty == true
  }
}
