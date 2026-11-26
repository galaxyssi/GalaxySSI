import Foundation

enum GalaxySSIHealthCareLegacyReplyPresentation {
  struct Marker: Identifiable, Equatable {
    let id: UUID
    let turn: UUID
    let source: UUID
    let startedAt: Date
    let receivedAt: Date

    var seconds: Int32 { Int32(min(86_400, max(0, receivedAt.timeIntervalSince(startedAt)))) }
  }

  static func marker(receipt: ChatMessage, original: ChatMessage, conversation: AgentConversation,
      hasRecovery: Bool, domainTurns: Set<UUID>, hasAnswer: Bool, now: Date = Date()) -> Marker? {
    guard GalaxySSIHealthCareAgentScope.concernID(conversation) != nil,
          !hasRecovery, !hasAnswer, let turn = UUID(uuidString: receipt.turnId),
          turn == original.id, !domainTurns.contains(turn),
          UUID(uuidString: original.turnId.ifBlank(original.id.uuidString)) == turn,
          original.isMine, !original.isSystem, !receipt.isMine, !receipt.isSystem,
          original.contactId == "hermes", receipt.contactId == "hermes",
          original.conversationId == conversation.id, receipt.conversationId == conversation.id,
          original.sourceConversationId.isBlank, receipt.sourceConversationId.isBlank,
          original.requestKind == .conversation, receipt.requestKind == .conversation,
          !original.readOnlyAnalysis, !receipt.readOnlyAnalysis,
          !receipt.remoteMessageId.isBlank, [.delivered, .read].contains(receipt.deliveryStatus),
          receipt.content.utf8.count <= 128_000, receipt.richOutputJson.utf8.count <= 128_000,
          isControl(receipt),
          !receipt.deliveryTrace.contains(where: { event in
            let stage = event.stage.lowercased()
            return ["interim", "milestone", "partial", "failed", "cancelled", "blocked"]
              .contains(where: stage.contains)
          }),
          original.createdAt.timeIntervalSinceReferenceDate.isFinite,
          receipt.createdAt.timeIntervalSinceReferenceDate.isFinite,
          now.timeIntervalSinceReferenceDate.isFinite else { return nil }
    let final = receipt.deliveryTrace.filter {
      ["agent_reply_received", "cloud_reply_received", "delivered"].contains($0.stage) &&
        $0.createdAt.timeIntervalSinceReferenceDate.isFinite && $0.createdAt >= original.createdAt && $0.createdAt <= now
    }.map(\.createdAt).max()
    guard !receipt.remoteMessageId.hasPrefix("agent-stream-") || final != nil else { return nil }
    let received = final ?? receipt.createdAt
    guard received >= original.createdAt, received <= now else { return nil }
    return Marker(id: receipt.id, turn: turn, source: original.id, startedAt: original.createdAt, receivedAt: received)
  }

  static func isControl(_ message: ChatMessage) -> Bool {
    !message.isMine && (CloudSupervisedResearch.isTranscriptControlReply(message) ||
      AgentModelPlanParser.containsUnexecutedControlReply(message.content) ||
      AgentModelPlanParser.containsUnexecutedControlReply(message.richOutputJson))
  }
}
