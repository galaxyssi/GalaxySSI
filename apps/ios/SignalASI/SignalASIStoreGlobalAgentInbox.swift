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
    GlobalProactiveDeliveryBus.signalReady()
    return stored
  }

  @discardableResult
  func deliverPendingGlobalProactiveMessages(
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [GlobalProactiveMessage] {
    let settings = globalAgentSettings
    guard settings.enabled, settings.proactiveInsightsEnabled else { return [] }

    let profile = GlobalAgentLearningPolicy.profile(
      feedback: globalAgentFeedback,
      nowMillis: nowMillis
    )
    var history = globalProactiveInterventionHistory()
    var delivered: [GlobalProactiveMessage] = []

    for message in globalProactiveMessages
      .filter({ $0.target != .globalDigest })
      .filter({ GlobalProactiveDeliveryPolicy.isRecoverable($0, nowMillis: nowMillis) })
      .sorted(by: { $0.createdAtMillis < $1.createdAtMillis }) {
      guard GlobalProactiveDeliveryPolicy.canDeliver(
        message: message,
        settings: settings,
        profile: profile,
        history: history,
        nowMillis: nowMillis
      ) else { continue }

      let conversations = agentSessions(includeArchived: true)
      guard let route = resolveGlobalProactiveRoute(
        message: message,
        conversations: conversations,
        settings: settings
      ) else { continue }

      let groupId = message.deliveryGroupId.ifBlank(message.id)
      guard claimGlobalProactiveMessage(
        messageId: message.id,
        conversationId: route.conversationId,
        deliveryGroupId: groupId,
        nowMillis: nowMillis
      ) else { continue }

      let dedupeKey = "global-agent:\(message.id)"
      let alreadyPersisted = agentSessionMessages(route.conversationId).contains {
        $0.remoteMessageId == dedupeKey || $0.turnId == dedupeKey
      }
      if !alreadyPersisted {
        _ = appendIncoming(
          globalProactiveTranscriptText(message),
          from: "hermes",
          remoteMessageId: dedupeKey,
          traceStage: "global_agent_proactive_delivery",
          conversationId: route.conversationId,
          turnId: dedupeKey
        )
      }

      guard completeGlobalProactiveMessage(
        messageId: message.id,
        conversationId: route.conversationId,
        deliveryGroupId: groupId,
        countBudget: !message.deliveryBudgetCounted,
        nowMillis: nowMillis
      ) else { continue }
      if let completed = globalProactiveMessages.first(where: { $0.id == message.id }) {
        delivered.append(completed)
        history.notificationTimestamps.append(max(nowMillis, 0))
        let topic = GlobalAgentText.normalize(message.topic)
        if !topic.isEmpty {
          history.lastTopicNotificationMillis[topic] = max(nowMillis, 0)
        }
        history.countedDeliveryGroupIds.append(groupId)
      }
    }
    return delivered
  }

  @discardableResult
  private func claimGlobalProactiveMessage(
    messageId: String,
    conversationId: String,
    deliveryGroupId: String,
    nowMillis: Int64,
    leaseMillis: Int64 = 120_000
  ) -> Bool {
    guard let index = globalProactiveMessages.firstIndex(where: { $0.id == messageId }) else { return false }
    var message = globalProactiveMessages[index]
    guard GlobalProactiveDeliveryPolicy.isRecoverable(message, nowMillis: nowMillis) else { return false }
    message.status = .delivering
    message.deliveryConversationId = conversationId
    message.deliveryGroupId = deliveryGroupId
    message.deliveryLeaseExpiresAtMillis = max(nowMillis, 0) + max(leaseMillis, 1)
    message.deliveryAttemptCount += 1
    message.lastDeliveryError = ""
    globalProactiveMessages[index] = message
    return true
  }

  @discardableResult
  private func completeGlobalProactiveMessage(
    messageId: String,
    conversationId: String,
    deliveryGroupId: String,
    countBudget: Bool,
    nowMillis: Int64
  ) -> Bool {
    guard let index = globalProactiveMessages.firstIndex(where: { $0.id == messageId }) else { return false }
    var message = globalProactiveMessages[index]
    guard message.status == .delivering,
          message.deliveryConversationId == conversationId else { return false }
    message.status = .delivered
    message.deliveryLeaseExpiresAtMillis = 0
    message.deliveredAtMillis = max(nowMillis, 0)
    message.deliveredConversationId = conversationId
    message.deliveryGroupId = deliveryGroupId
    message.deliveryBudgetCounted = message.deliveryBudgetCounted || countBudget
    message.lastDeliveryError = ""
    globalProactiveMessages[index] = message
    return true
  }

  private func resolveGlobalProactiveRoute(
    message: GlobalProactiveMessage,
    conversations: [AgentConversation],
    settings: GlobalAgentSettings
  ) -> GlobalProactiveDeliveryRoute? {
    let route = GlobalProactiveConversationRouter.resolve(
      message: message,
      conversations: conversations,
      autoCreateConversationsEnabled: settings.autoCreateConversationsEnabled
    )
    guard let route else { return nil }
    let resolved: GlobalProactiveDeliveryRoute
    if route.createConversation {
      let conversation = createAgentConversation(
        title: route.title,
        parentConversationId: route.parentConversationId,
        globalTopicKey: route.topicKey
      )
      resolved = GlobalProactiveDeliveryRoute(
        kind: route.kind,
        conversationId: conversation.id,
        createConversation: false,
        title: route.title,
        parentConversationId: route.parentConversationId,
        topicKey: route.topicKey,
        bindTopic: route.bindTopic
      )
    } else {
      resolved = route
    }

    if resolved.bindTopic, let destination = agentSession(id: resolved.conversationId),
       let notice = GlobalProactiveTopicNoticePolicy.create(message: message, destination: destination) {
      let richOutput = AgentRichContentCodec.encode([
        AgentRichBlock(id: "\(notice.taskId):text", type: .notice, text: notice.text),
        AgentRichBlock(
          id: "\(notice.taskId):actions",
          type: .actions,
          actions: [AgentRichAction(
            id: "\(notice.taskId):open",
            label: notice.actionLabel,
            verb: "open_conversation",
            value: notice.destinationConversationId,
            style: "primary"
          )]
        )
      ])
      let alreadyNotified = agentSessionMessages(notice.parentConversationId).contains {
        $0.remoteMessageId == notice.dedupeKey || $0.turnId == notice.taskId
      }
      if !alreadyNotified {
        _ = appendIncoming(
          notice.text,
          from: "hermes",
          remoteMessageId: notice.dedupeKey,
          traceStage: "global_agent_topic_notice",
          conversationId: notice.parentConversationId,
          turnId: notice.taskId,
          richOutputJson: richOutput
        )
      }
    }
    return resolved
  }

  private func globalProactiveTranscriptText(_ message: GlobalProactiveMessage) -> String {
    let title = message.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty { return content }
    if content.isEmpty { return title }
    return "\(title)\n\n\(content)"
  }

  private func globalProactiveInterventionHistory() -> GlobalInterventionHistory {
    var topicTimestamps: [String: Int64] = [:]
    var timestamps: [Int64] = []
    for message in globalProactiveMessages where message.status == .delivered {
      let timestamp = max(message.deliveredAtMillis, message.createdAtMillis)
      guard timestamp > 0 else { continue }
      timestamps.append(timestamp)
      let topic = GlobalAgentText.normalize(message.topic)
      if !topic.isEmpty {
        topicTimestamps[topic] = max(topicTimestamps[topic] ?? 0, timestamp)
      }
    }
    return GlobalInterventionHistory(
      notificationTimestamps: timestamps,
      lastTopicNotificationMillis: topicTimestamps,
      countedDeliveryGroupIds: globalProactiveMessages
        .filter { $0.deliveryBudgetCounted }
        .map(\.deliveryGroupId)
    )
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
