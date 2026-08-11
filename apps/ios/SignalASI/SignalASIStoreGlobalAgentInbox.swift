import Foundation

extension SignalASIStore {
  func globalProactiveInboxItems(limit: Int = 50) -> [GlobalProactiveInboxItem] {
    GlobalProactiveInboxPolicy.project(
      messages: globalProactiveMessages,
      feedback: globalAgentFeedback,
      limit: limit
    )
  }

  func globalProactiveInboxNewCount(limit: Int = 100) -> Int {
    GlobalProactiveInboxPolicy.newCount(globalProactiveInboxItems(limit: limit))
  }

  @discardableResult
  func appendGlobalProactiveMessage(_ message: GlobalProactiveMessage) -> GlobalProactiveMessage {
    let now = Self.nowMillis()
    var stored = message
    if stored.createdAtMillis <= 0 {
      stored.createdAtMillis = now
    }
    if stored.status == .delivered && stored.deliveredAtMillis <= 0 {
      stored.deliveredAtMillis = now
    }
    globalProactiveMessages.removeAll { $0.id == stored.id }
    globalProactiveMessages = Array((globalProactiveMessages + [stored]).suffix(500))
    return stored
  }

  @discardableResult
  func markGlobalProactiveInboxViewed(_ item: GlobalProactiveInboxItem) -> Bool {
    let updated = GlobalProactiveInboxPolicy.markViewed(
      messages: globalProactiveMessages,
      messageIds: item.messageIds,
      nowMillis: Self.nowMillis()
    )
    guard updated != globalProactiveMessages else { return false }
    globalProactiveMessages = Array(updated.suffix(500))
    return true
  }

  @discardableResult
  func recordGlobalInsightFeedback(
    inboxItem: GlobalProactiveInboxItem,
    kind: GlobalAgentFeedbackKind
  ) -> Bool {
    let targetIds = inboxItem.messageIds
    guard !targetIds.isEmpty else { return false }
    let now = Self.nowMillis()
    var matched = 0
    var updatedMessages = globalProactiveMessages
    var updatedFeedback = globalAgentFeedback.filter { !targetIds.contains($0.proactiveMessageId) }

    for index in updatedMessages.indices where targetIds.contains(updatedMessages[index].id) {
      matched += 1
      var message = updatedMessages[index]
      message.viewedAtMillis = max(message.viewedAtMillis, now)
      switch kind {
      case .helpful:
        if message.status == .pending || message.status == .notified || message.status == .delivering {
          message.status = .delivered
          message.deliveredAtMillis = max(message.deliveredAtMillis, now)
        }
      case .notRelevant, .tooFrequent:
        message.status = .dismissed
      }
      updatedMessages[index] = message
      updatedFeedback.append(
        GlobalAgentFeedback(
          proactiveMessageId: message.id,
          deliveryGroupId: message.deliveryGroupId.ifBlank(inboxItem.key),
          conversationId: message.deliveredConversationId
            .ifBlank(inboxItem.destinationConversationId)
            .ifBlank(message.sourceConversationId),
          topic: message.topic.ifBlank(inboxItem.topic),
          target: message.target,
          kind: kind,
          createdAtMillis: now
        )
      )
    }

    guard matched > 0 else { return false }
    globalProactiveMessages = Array(updatedMessages.suffix(500))
    globalAgentFeedback = Array(updatedFeedback.suffix(500))
    return true
  }
}
