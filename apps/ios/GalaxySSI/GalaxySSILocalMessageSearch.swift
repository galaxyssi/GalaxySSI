import Foundation

enum GalaxySSILocalMessageSearch {
  enum Failure: Error { case unavailable }
  enum Kind: String { case agent, peer }
  struct Source: Equatable, Identifiable {
    let kind: Kind
    let id: String
    let title: String
    let archived: Bool
    var route = ""
    var contactID: String? { kind == .peer ? id : nil }
    var conversationID: String? { kind == .agent ? id : nil }
  }
  struct Hit: Equatable, Identifiable {
    let owner: String
    let source: Source
    let message: UUID
    let cursor: GalaxySSIChatHistoryCursor
    let at: Date
    let snippet: String
    let filename: Bool
    var id: String { source.kind.rawValue + ":" + source.id + ":" + message.uuidString }
  }
  struct Line: Identifiable, Equatable {
    let id: UUID
    let mine: Bool
    let text: String
    let files: [String]
    let at: Date
  }
  struct Context {
    let lines: [Line]
    let older: GalaxySSIChatHistoryCursor?
    let newer: GalaxySSIChatHistoryCursor?
  }

  static func query(_ value: String) -> String? {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return !clean.isEmpty && clean.utf16.count <= 256 ? clean : nil
  }
  static func ordinary(_ conversation: AgentConversation) -> Bool {
    !conversation.privateMode && !conversation.trackingPaused && conversation.globalTopicKey.isBlank &&
      conversation.mergedIntoConversationId.isBlank && [.active, .archived].contains(conversation.status)
  }
  static func peer(_ contact: GalaxySSIContact, archived: Bool) -> Source? {
    guard !["hermes", "system"].contains(contact.id), (!contact.deleted || contact.isDesktopHistoryOnly),
      contact.isDesktopHistoryOnly == archived, GalaxySSIConversationHubContactHistoryPolicy.includes(contact),
      contact.isDesktopHistoryOnly || contact.type.lowercased() == "person" || contact.isDesktopDeviceContact else { return nil }
    return .init(kind: .peer, id: contact.id, title: contact.displayName.ifBlank(contact.id), archived: archived,
      route: AgentModelLoopRecoveryIdentity.sha256(["fingerprint": contact.identityFingerprint,
        "desktop": contact.desktopId, "setup": contact.setupStatus]))
  }
  static func excerpt(_ text: String, query: String) -> String? {
    guard !query.isEmpty, let range = text.range(of: query, options: .caseInsensitive) else { return nil }
    let start = text.index(range.lowerBound, offsetBy: -14, limitedBy: text.startIndex) ?? text.startIndex
    let end = text.index(range.upperBound, offsetBy: 58, limitedBy: text.endIndex) ?? text.endIndex
    return (start > text.startIndex ? "\u{2026}" : "") + text[start..<end]
      .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines) + (end < text.endIndex ? "\u{2026}" : "")
  }
  static func line(_ message: ChatMessage, source: Source) -> Line? {
    guard !message.isSystem, message.sourceConversationId.isBlank,
      source.kind == .peer ? message.contactId == source.id : message.conversationId == source.id,
      !CloudSupervisedResearch.isTranscriptControlReply(message),
      !AgentModelPlanParser.containsUnexecutedControlReply(message.content),
      !message.remoteMessageId.hasPrefix(AgentReplyWaitingIndicatorPolicy.dedupePrefix),
      !message.remoteMessageId.hasPrefix("agent-stream-preview-") else { return nil }
    let row = source.kind == .peer ? AgentPeerChatTransport.migrateStoredHistory([source.id: [message]]).messages[source.id]?.first ?? message : message
    let blocks = AgentRichContentCodec.decode(row.richOutputJson)
    guard !blocks.contains(where: { $0.type == .approval }) else { return nil }
    let files = blocks.filter { [.file, .image, .audio, .video].contains($0.type) }.map(\.title).filter { !$0.isBlank }
    guard !row.content.isBlank || !files.isEmpty else { return nil }
    return .init(id: row.id, mine: row.isMine, text: row.content, files: files, at: row.createdAt)
  }
  static func hit(_ message: ChatMessage, source: Source, owner: String, query: String) -> Hit? {
    guard let line = line(message, source: source) else { return nil }
    let body = excerpt(line.text, query: query)
    guard let match = body ?? line.files.lazy.compactMap({ excerpt($0, query: query) }).first else { return nil }
    return .init(owner: owner, source: source, message: message.id, cursor: .init(message), at: message.createdAt,
      snippet: match, filename: body == nil)
  }
}
