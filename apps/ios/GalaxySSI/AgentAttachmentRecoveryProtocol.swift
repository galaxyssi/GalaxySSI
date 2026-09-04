import Foundation

struct AgentAttachmentRecoveryRequest: Equatable {
  static let requestType = "input_attachment_request"
  static let resultType = "input_attachment_request_result"

  var requestId: String
  var clientRouteId: String
  var conversationId: String
  var taskId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: Int64
  var attachmentIds: [String]

  static func decode(_ payload: AgentMcpJSONObject) -> AgentAttachmentRecoveryRequest? {
    guard payload.string("type") == requestType else {
      return nil
    }
    let requestId = payload.string("request_id").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard isValidRequestId(requestId),
          let sourceMessageId = sourceMessageId(from: payload["source_message_id"]),
          sourceMessageId > 0,
          let clientRouteId = identity(payload, "client_route_id"),
          let conversationId = identity(payload, "conversation_id"),
          let taskId = identity(payload, "task_id"),
          let turnId = identity(payload, "turn_id"),
          let contactId = identity(payload, "contact_id") else {
      return nil
    }
    let attachmentIds = requestedAttachmentIds(payload["attachment_ids"]?.arrayValue ?? [])
    guard !attachmentIds.isEmpty else {
      return nil
    }
    return AgentAttachmentRecoveryRequest(
      requestId: requestId,
      clientRouteId: clientRouteId,
      conversationId: conversationId,
      taskId: taskId,
      turnId: turnId,
      contactId: contactId,
      sourceMessageId: sourceMessageId,
      attachmentIds: attachmentIds
    )
  }

  func result(
    status: String,
    availableAttachmentIds: [String] = [],
    missingAttachmentIds: [String] = [],
    error: String = "",
    timeMillis: Int64 = AgentAttachmentRecoveryRequest.currentTimeMillis()
  ) -> AgentMcpJSONObject {
    var payload: AgentMcpJSONObject = [
      "type": .string(Self.resultType),
      "request_id": .string(requestId),
      "client_route_id": .string(clientRouteId),
      "conversation_id": .string(conversationId),
      "task_id": .string(taskId),
      "turn_id": .string(turnId),
      "contact_id": .string(contactId),
      "source_message_id": .string(String(sourceMessageId)),
      "status": .string(status),
      "available_attachment_ids": .array(availableAttachmentIds.map { .string($0) }),
      "missing_attachment_ids": .array(missingAttachmentIds.map { .string($0) }),
      "time": .int(timeMillis)
    ]
    let trimmedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedError.isEmpty {
      payload["error"] = .string(String(trimmedError.prefix(Self.maxErrorCharacters)))
    }
    return payload
  }

  private static func requestedAttachmentIds(_ values: [AgentMcpJSONValue]) -> [String] {
    var result: [String] = []
    for value in values.prefix(maxAttachments) {
      let attachmentId = (value.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !attachmentId.isEmpty,
            attachmentId.count <= maxAttachmentIdCharacters,
            !result.contains(attachmentId) else {
        continue
      }
      result.append(attachmentId)
    }
    return result
  }

  private static func identity(_ payload: AgentMcpJSONObject, _ key: String) -> String? {
    let value = payload.string(key).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty,
          value.count <= maxIdentityCharacters,
          !value.unicodeScalars.contains(where: { $0.value < 32 }) else {
      return nil
    }
    return value
  }

  private static func sourceMessageId(from value: AgentMcpJSONValue?) -> Int64? {
    switch value {
    case .string(let raw):
      return Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    case .int(let raw):
      return raw
    case .double(let raw) where raw.isFinite && raw.rounded(.towardZero) == raw:
      return Int64(raw)
    default:
      return nil
    }
  }

  private static func isValidRequestId(_ value: String) -> Bool {
    value.count == 32 && value.unicodeScalars.allSatisfy { scalar in
      let value = scalar.value
      return (value >= 48 && value <= 57) || (value >= 97 && value <= 102)
    }
  }

  private static func currentTimeMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private static let maxAttachments = 10
  private static let maxAttachmentIdCharacters = 120
  private static let maxIdentityCharacters = 256
  private static let maxErrorCharacters = 300
}
