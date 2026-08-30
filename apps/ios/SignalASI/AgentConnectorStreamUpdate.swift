import Foundation

enum AgentConnectorStreamHandoff {
  static func persistThenRetire<Result>(
    persistFinal: () throws -> Result?,
    retireLiveStream: () -> Void
  ) rethrows -> Result? {
    guard let result = try persistFinal() else { return nil }
    retireLiveStream()
    return result
  }
}

struct AgentConnectorStreamUpdate: Equatable {
  let sourceMessageId: String
  let contactId: String
  let conversationId: String
  let turnId: String
  let taskId: String
  let content: String
  let sequence: Int64

  init?(payload: [String: Any]) {
    guard payload.string("type") == "agent_task_event",
          AgentRemoteTaskStatusPolicy.normalize(
            payload.string("task_status").ifBlank(payload.string("status"))
          ) == "running",
          let partial = payload.dictionary("partial_result") else {
      return nil
    }
    if let visible = partial["user_visible"] as? Bool, !visible {
      return nil
    }
    if let visible = partial["user_visible"] as? NSNumber, !visible.boolValue {
      return nil
    }
    let text = partial.string("text")
      .ifBlank(partial.string("content"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }

    let sourceMessageId = payload.string("source_message_id")
      .ifBlank(String(payload.int("source_message_id")))
    guard !sourceMessageId.isEmpty, sourceMessageId != "0" else { return nil }
    self.sourceMessageId = sourceMessageId
    contactId = payload.string("contact_id").ifBlank("hermes")
    conversationId = payload.string("conversation_id")
    turnId = payload.string("turn_id")
    taskId = payload.string("task_id")
    content = String(text.prefix(Self.maximumContentCharacters))
    sequence = max(0, Int64(partial.int("sequence")))
  }

  var streamKey: String {
    Self.streamKey(sourceMessageId: sourceMessageId, turnId: turnId)
  }

  static func streamKey(sourceMessageId: String, turnId: String) -> String {
    let cleanSourceMessageId = sourceMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleanSourceMessageId.isEmpty, cleanSourceMessageId != "0" {
      return "source:\(cleanSourceMessageId)"
    }
    let cleanTurnId = turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleanTurnId.isEmpty ? "unknown" : "turn:\(cleanTurnId)"
  }

  private static let maximumContentCharacters = 64_000
}
