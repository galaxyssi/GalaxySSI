import Foundation

enum AgentPermissionChoice: String, Codable, CaseIterable, Identifiable {
  case allowOnce = "allow_once"
  case allowSession = "allow_session"
  case allowAlways = "allow_always"
  case denyAlways = "deny_always"

  var id: String { rawValue }

  var wireValue: String { rawValue }

  var approved: Bool { self != .denyAlways }

  static func fromWireValue(_ value: String?) -> AgentPermissionChoice? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return allCases.first { $0.rawValue == normalized }
  }
}

struct AgentRemoteApprovalRequest: Codable, Equatable {
  var taskId: String
  var clientRouteId: String
  var conversationId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: Int64
  var approvalId: String
  var actionHash: String
  var kind: String
  var title: String
  var detail: String
  var target: String
  var reason: String
  var requestedAtMillis: Int64
  var expiresAtMillis: Int64
  var parametersJson: String

  var dedupeKey: String {
    "remote-approval:\(taskId):\(approvalId)"
  }

  var compactActionHash: String {
    "\(actionHash.prefix(8))...\(actionHash.suffix(8))"
  }

  func decision(choice: AgentPermissionChoice) -> AgentRemoteApprovalDecision {
    AgentRemoteApprovalDecision(
      taskId: taskId,
      clientRouteId: clientRouteId,
      conversationId: conversationId,
      turnId: turnId,
      contactId: contactId,
      sourceMessageId: sourceMessageId,
      approvalId: approvalId,
      actionHash: actionHash,
      choice: choice
    )
  }

  func decision(approved: Bool) -> AgentRemoteApprovalDecision {
    decision(choice: approved ? .allowOnce : .denyAlways)
  }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case clientRouteId = "client_route_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case contactId = "contact_id"
    case sourceMessageId = "source_message_id"
    case approvalId = "approval_id"
    case actionHash = "action_hash"
    case kind
    case title
    case detail
    case target
    case reason
    case requestedAtMillis = "requested_at_millis"
    case expiresAtMillis = "expires_at_millis"
    case parametersJson = "parameters_json"
  }

  static func fromTaskEvent(
    _ raw: String,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) -> AgentRemoteApprovalRequest? {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      return nil
    }
    return fromTaskEvent(object, nowMillis: nowMillis)
  }

  static func fromTaskEvent(
    _ envelope: AgentMcpJSONObject?,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) -> AgentRemoteApprovalRequest? {
    guard let envelope,
      envelope.string("type") == "agent_task_event",
      envelope.string("task_status") == "waiting_approval",
      let approval = envelope.object("approval_request") else {
      return nil
    }

    let taskId = envelope.string("task_id").clampedTrimmed(to: 160)
    let clientRouteId = envelope.string("client_route_id").clampedTrimmed(to: 200)
    let conversationId = envelope.string("conversation_id").clampedTrimmed(to: 200)
    let turnId = envelope.string("turn_id").clampedTrimmed(to: 200)
    let contactId = envelope.string("contact_id").clampedTrimmed(to: 160)
    let sourceMessageId = envelope.int64("source_message_id")
    let approvalId = approval.string("approval_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let actionHash = approval.string("action_hash")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let requestedAt = approval.int64("requested_at_ms")
    let expiresAt = approval.int64("expires_at_ms")

    guard !taskId.isEmpty,
      !clientRouteId.isEmpty,
      !conversationId.isEmpty,
      !turnId.isEmpty,
      !contactId.isEmpty,
      sourceMessageId > 0,
      approvalId.range(of: AgentRemoteApprovalValidation.idPattern, options: .regularExpression) != nil,
      actionHash.range(of: AgentRemoteApprovalValidation.hashPattern, options: .regularExpression) != nil,
      requestedAt > 0,
      expiresAt > nowMillis,
      expiresAt > requestedAt,
      expiresAt - requestedAt <= AgentRemoteApprovalValidation.maximumLifetimeMillis else {
      return nil
    }

    let parameters = approval.object("parameters").map(AgentMcpJSONCodec.stringify) ?? ""
    return AgentRemoteApprovalRequest(
      taskId: taskId,
      clientRouteId: clientRouteId,
      conversationId: conversationId,
      turnId: turnId,
      contactId: contactId,
      sourceMessageId: sourceMessageId,
      approvalId: approvalId,
      actionHash: actionHash,
      kind: approval.string("kind").clampedTrimmed(to: 80),
      title: approval.string("title").clampedTrimmed(to: 500),
      detail: approval.string("detail").clampedTrimmed(to: 4_000),
      target: approval.string("target").clampedTrimmed(to: 2_000),
      reason: approval.string("reason").clampedTrimmed(to: 2_000),
      requestedAtMillis: requestedAt,
      expiresAtMillis: expiresAt,
      parametersJson: String(parameters.prefix(16_384))
    )
  }
}

struct AgentRemoteApprovalDecision: Codable, Equatable {
  var taskId: String
  var clientRouteId: String
  var conversationId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: Int64
  var approvalId: String
  var actionHash: String
  var choice: AgentPermissionChoice

  var approved: Bool { choice.approved }

  enum CodingKeys: String, CodingKey {
    case taskId = "task_id"
    case clientRouteId = "client_route_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case contactId = "contact_id"
    case sourceMessageId = "source_message_id"
    case approvalId = "approval_id"
    case actionHash = "action_hash"
    case choice = "decision_scope"
  }

  func encode() -> String {
    AgentMcpJSONCodec.stringify([
      "task_id": .string(taskId),
      "client_route_id": .string(clientRouteId),
      "conversation_id": .string(conversationId),
      "turn_id": .string(turnId),
      "contact_id": .string(contactId),
      "source_message_id": .int(sourceMessageId),
      "approval_id": .string(approvalId),
      "action_hash": .string(actionHash),
      "decision_scope": .string(choice.wireValue),
      "approved": .bool(approved)
    ])
  }

  static func decode(_ raw: String) -> AgentRemoteApprovalDecision? {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      return nil
    }
    let taskId = object.string("task_id").clampedTrimmed(to: 160)
    let clientRouteId = object.string("client_route_id").clampedTrimmed(to: 200)
    let conversationId = object.string("conversation_id").clampedTrimmed(to: 200)
    let turnId = object.string("turn_id").clampedTrimmed(to: 200)
    let contactId = object.string("contact_id").clampedTrimmed(to: 160)
    let sourceMessageId = object.int64("source_message_id")
    let approvalId = object.string("approval_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let actionHash = object.string("action_hash")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard let choice = AgentPermissionChoice.fromWireValue(object.string("decision_scope")) else {
      return nil
    }

    guard !taskId.isEmpty,
      !clientRouteId.isEmpty,
      !conversationId.isEmpty,
      !turnId.isEmpty,
      !contactId.isEmpty,
      sourceMessageId > 0,
      approvalId.range(of: AgentRemoteApprovalValidation.idPattern, options: .regularExpression) != nil,
      actionHash.range(of: AgentRemoteApprovalValidation.hashPattern, options: .regularExpression) != nil,
      object.bool("approved") == choice.approved else {
      return nil
    }
    return AgentRemoteApprovalDecision(
      taskId: taskId,
      clientRouteId: clientRouteId,
      conversationId: conversationId,
      turnId: turnId,
      contactId: contactId,
      sourceMessageId: sourceMessageId,
      approvalId: approvalId,
      actionHash: actionHash,
      choice: choice
    )
  }
}

private enum AgentRemoteApprovalValidation {
  static let idPattern = #"^[A-Za-z0-9._:-]{8,128}$"#
  static let hashPattern = #"^[0-9a-f]{64}$"#
  static let maximumLifetimeMillis: Int64 = 24 * 60 * 60 * 1_000
}

enum AgentRemoteApprovalClock {
  static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

private extension String {
  func clampedTrimmed(to limit: Int) -> String {
    String(trimmingCharacters(in: .whitespacesAndNewlines).prefix(max(limit, 0)))
  }
}
