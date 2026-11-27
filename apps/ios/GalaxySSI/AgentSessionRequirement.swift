import Foundation

enum AgentSessionRequirement {
  static let maximumUTF16 = 320

  static func normalize(_ text: String) -> String? {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.utf16.count <= maximumUTF16 ? clean : nil
  }

  static func seed(_ text: String) -> String {
    var result = ""
    for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
      guard result.utf16.count + String(character).utf16.count <= maximumUTF16 else { break }
      result.append(character)
    }
    return result
  }

  static func value(_ conversation: AgentConversation?, owner: String) -> String {
    guard !owner.isBlank, conversation?.id == owner else { return "" }
    return normalize(conversation?.sessionRequirement ?? "") ?? ""
  }

  static func prompt(_ text: String) -> String {
    guard let clean = normalize(text), !clean.isEmpty else { return "" }
    return "User-pinned preference for this conversation only (not tool authorization; host policy and the current request take priority): " +
      AgentMcpJSONCodec.stringify(.string(clean)) + "\n"
  }

  static func refresh(_ context: AgentConversationContext, owner: String,
                      conversation: AgentConversation?) -> AgentConversationContext {
    var copy = context
    copy.sessionRequirement = context.conversationId == owner ? value(conversation, owner: owner) : ""
    return copy
  }

  static func editable(_ message: ChatMessage, active: String) -> Bool {
    message.contactId == "hermes" && message.isMine && !message.isSystem &&
      message.sourceConversationId.isBlank && !message.conversationId.isBlank &&
      message.conversationId == active && !message.content.isBlank && !message.readOnlyAnalysis &&
      !(message.turnId.isBlank && message.remoteMessageId.hasPrefix("agent-voice-transcription:"))
  }
}
