import Foundation

struct LinkOutboxReceiptWindow {
  private struct Entry {
    let topic: String
    let expiresAt: TimeInterval
  }

  private var entries: [String: Entry] = [:]

  func delay(topic: String, messageId: String, now: TimeInterval) -> TimeInterval {
    if let entry = entries[messageId], entry.expiresAt > now {
      return entry.expiresAt - now
    }
    let lane = entries.values.filter { $0.topic == topic && $0.expiresAt > now }
    guard lane.count >= 8, let first = lane.map(\.expiresAt).min() else { return 0 }
    return first - now
  }

  mutating func acquire(topic: String, messageId: String, now: TimeInterval) -> Bool {
    guard delay(topic: topic, messageId: messageId, now: now) == 0 else { return false }
    entries[messageId] = Entry(topic: topic, expiresAt: now + 30)
    return true
  }

  mutating func release(_ messageId: String) {
    entries.removeValue(forKey: messageId)
  }

  mutating func reconcile(now: TimeInterval, isPending: (String) -> Bool) {
    entries = entries.filter { $0.value.expiresAt > now && isPending($0.key) }
  }

  var messageIds: Set<String> { Set(entries.keys) }

  func nextExpiryDelay(now: TimeInterval) -> TimeInterval? {
    entries.values.map { max(0, $0.expiresAt - now) }.min()
  }
}

@MainActor
extension MessageCoordinator {
  func learningOutboxEligibility() -> (PendingLinkMessage) -> Bool {
    let enabled = store.globalAgentSettings.enabled
    if !enabled && pausedLegacyLearningSourceIDs == nil {
      pausedLegacyLearningSourceIDs = Set(backgroundLearningLeases().keys)
    }
    let legacy = pausedLegacyLearningSourceIDs ?? []
    return { AgentIOSCognitionSchedulePolicy.allowsTransport($0, learningEnabled: enabled, legacySources: legacy) }
  }

  private func backgroundLearningLeases() -> [String: Int64] {
    var leases: [String: Int64] = [:]
    func add(_ id: Int64, _ expires: Int64) {
      guard id > 0 else { return }
      let key = String(id)
      leases[key] = max(expires, leases[key] ?? 0)
    }
    let deliberation = GlobalAgentDeliberationStore()
    for task in deliberation.cognitionTasks() { add(task.sourceMessageId, task.leaseExpiresAtMillis) }
    for run in deliberation.autonomousRuns() {
      add(run.review.sourceMessageId, run.review.leaseExpiresAtMillis)
      for action in run.actions { add(action.sourceMessageId, action.leaseExpiresAtMillis) }
    }
    let research = GalaxySSIGlobalAgentRuntimeBridge.researchState()
    for task in research.tasks {
      add(task.sourceMessageId, task.leaseExpiresAtMillis)
      add(task.researchPlan.synthesisSourceMessageId, task.researchPlan.synthesisLeaseExpiresAtMillis)
      for unit in task.researchPlan.units { add(unit.sourceMessageId, unit.leaseExpiresAtMillis) }
    }
    return leases
  }

  private func flushPendingOutbox() async {
    guard !Task.isCancelled else { return }
    guard !outboxFlushInProgress else {
      outboxFlushRequested = true
      return
    }
    outboxFlushInProgress = true
    defer {
      outboxFlushInProgress = false
      if outboxFlushRequested {
        outboxFlushRequested = false
        scheduleOutboxFlush(after: 0)
      } else if !Task.isCancelled {
        scheduleOutboxFlushFromStore()
      }
    }
    let discardedTransfers = attachmentTransferStore.prune()
    if !discardedTransfers.isEmpty {
      _ = deliveryStore.discardBlockedByAttachmentTransfers(discardedTransfers)
    }
    var activeMessageIds = await mqttClient.outstandingDurableMessageIds()
    guard !Task.isCancelled else { return }
    reconcileOutboxReceiptWindow()
    deliveryStore.holdStaleUnclassified(activeMessageIds: activeMessageIds.union(outboxReceiptWindow.messageIds))
    let eligible = learningOutboxEligibility()
    handleExhaustedDeliveries(
      deliveryStore.discardExhausted(
        maxAttempts: Self.maximumOutboxDeliveryAttempts,
        attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
        activeMessageIds: activeMessageIds.union(outboxReceiptWindow.messageIds),
        eligible: eligible
      )
    )
    let mediaProfile = mediaNetworkProfileProvider()
    let pending = deliveryStore.pending(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts,
      attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
      eligible: eligible
    )
    guard !pending.isEmpty else { return }
    var rejectedSourceIds = Set<String>()
    for var item in pending {
      guard !Task.isCancelled else { return }
      guard learningOutboxEligibility()(item) else { continue }
      if activeMessageIds.contains(item.messageId) || !deliveryStore.containsOutboxMessage(item.messageId) {
        continue
      }
      if item.clientSourceMessageId.hasPrefix(PublicAttentionResearchPolicy.outboxPrefix) {
        let source = Int64(item.clientSourceMessageId.dropFirst(PublicAttentionResearchPolicy.outboxPrefix.count))
        let research = GalaxySSIGlobalAgentRuntimeBridge.researchState()
        guard let source, let request = research.dispatchRequests.first(where: {
          $0.sourceMessageId == source && $0.contactId == item.contactId && $0.transport == .pairedAgent
        }), PublicAttentionResearchPolicy.allows(request, settings: store.globalAgentSettings),
           let contact = store.contact(id: item.contactId), publicAttentionLink(contact)?.routes.upTopic == item.topic,
           let task = research.task(id: request.taskId), task.leaseExpiresAtMillis > GlobalRealtimeClock.nowMillis()
        else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      } else if item.clientSourceMessageId.hasPrefix(PublicNewsPairedHeadlineBatch.outboxPrefix) {
        guard allowsPairedHeadlineDelivery(item) else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      } else if AgentIOSCognitionSchedulePolicy.isLearningTransport(item, legacySources: pausedLegacyLearningSourceIDs ?? []) {
        // Expired reservations belong to the learning journal, not transport replay.
        let expiry = backgroundLearningLeases()[item.clientSourceMessageId] ?? 0
        guard expiry > GlobalRealtimeClock.nowMillis() else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      }
      let sourceId = item.clientSourceMessageId.ifBlank(item.messageId)
      if GalaxySSIContactReminderOutbox.containsReminder(sourceId) {
        guard !GalaxySSIContactReminderOutbox.isExpired(sourceId, now: AgentControlPlaneClock.nowMillis()),
              let contact = store.contact(id: item.contactId), canSendContactReminder(to: contact) else {
          deliveryStore.discard(messageId: item.messageId)
          continue
        }
      }
      if rejectedSourceIds.contains(sourceId) { continue }
      if let deferred = item.deferredTaskPayload {
        guard deliveryStore.canPrepareDeferredTask(item),
              let link = store.serverLinks.first(where: { $0.paired && $0.routes.upTopic == item.topic }),
              let payload = (try? JSONSerialization.jsonObject(with: Data(deferred.utf8))) as? [String: Any],
              payload.string("message_id") == item.messageId,
              let wire = try? linkWirePayload(payload, link: link), wire.messageId == item.messageId,
              deliveryStore.commitDeferredTaskCiphertext(item, wirePayload: wire.wireText) else {
          deliveryStore.postponeDeferredTask(item)
          continue
        }
        item.wirePayload = wire.wireText
        item.deferredTaskPayload = nil
      }
      if let reason = GalaxySSIMqttWireChunking.permanentRejectionReason(
        wirePayload: item.wirePayload
      ) {
        rejectedSourceIds.insert(sourceId)
        _ = deliveryStore.discardClientSourceMessage(sourceId)
        handlePermanentlyRejectedDeliveries([
          PermanentlyRejectedLinkMessage(
            messageId: item.messageId,
            clientSourceMessageId: item.clientSourceMessageId,
            contactId: item.contactId,
            reason: reason
          )
        ])
        continue
      }
      reconcileOutboxReceiptWindow()
      guard outboxReceiptWindow.acquire(
        topic: item.topic, messageId: item.messageId, now: ProcessInfo.processInfo.systemUptime
      ) else { continue }
      let reservedAt = Date()
      deliveryStore.markAttempt(messageId: item.messageId, now: reservedAt)
      let result = await mqttClient.publishDurable(
        topic: item.topic,
        payload: Data(item.wirePayload.utf8),
        messageId: item.messageId
      ) { [weak self] persisted in
        Task { @MainActor [weak self] in
          guard let self else {
            persisted()
            return
          }
          self.deliveryStore.markPublished(messageId: item.messageId)
          self.scheduleOutboxFlushFromStore()
          persisted()
        }
      }
      if result.accepted {
        activeMessageIds.insert(item.messageId)
      } else if result == .deferred {
        outboxReceiptWindow.release(item.messageId)
        _ = deliveryStore.deferUnadmittedAttempt(messageId: item.messageId,
          reservedAttempts: item.attempts + 1, reservedAt: reservedAt)
      }
    }
  }

  private func reconcileOutboxReceiptWindow() {
    outboxReceiptWindow.reconcile(
      now: ProcessInfo.processInfo.systemUptime,
      isPending: deliveryStore.containsOutboxMessage
    )
  }

  func scheduleOutboxFlushFromStore() {
    let mediaProfile = mediaNetworkProfileProvider()
    let now = ProcessInfo.processInfo.systemUptime
    let receiptWindow = outboxReceiptWindow
    let retryDelay = deliveryStore.nextRetryDelay(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts,
      attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
      eligible: learningOutboxEligibility(),
      minimumDelay: { item in
        receiptWindow.delay(topic: item.topic, messageId: item.messageId, now: now)
      }
    )
    if let delay = [retryDelay, receiptWindow.nextExpiryDelay(now: now)].compactMap({ $0 }).min() {
      scheduleOutboxFlush(after: delay)
    }
  }

  func scheduleOutboxFlush(after delay: TimeInterval) {
    outboxRetryTask?.cancel()
    outboxRetryTask = Task { [weak self] in
      if delay > 0 {
        do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        catch { return }
      }
      guard !Task.isCancelled else { return }
      await self?.flushPendingOutbox()
    }
  }
}
