import Foundation

@MainActor
extension MessageCoordinator {
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
    handleExhaustedDeliveries(
      deliveryStore.discardExhausted(
        maxAttempts: Self.maximumOutboxDeliveryAttempts,
        attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts,
        activeMessageIds: activeMessageIds
      )
    )
    let mediaProfile = mediaNetworkProfileProvider()
    let pending = deliveryStore.pending(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts,
      attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts
    )
    guard !pending.isEmpty else { return }
    var rejectedSourceIds = Set<String>()
    for var item in pending {
      guard !Task.isCancelled else { return }
      if activeMessageIds.contains(item.messageId) { continue }
      let sourceId = item.clientSourceMessageId.ifBlank(item.messageId)
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
        _ = deliveryStore.deferUnadmittedAttempt(messageId: item.messageId,
          reservedAttempts: item.attempts + 1, reservedAt: reservedAt)
      }
    }
  }

  func scheduleOutboxFlushFromStore() {
    let mediaProfile = mediaNetworkProfileProvider()
    if let delay = deliveryStore.nextRetryDelay(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts,
      attachmentMaxAttempts: Self.maximumAttachmentOutboxDeliveryAttempts
    ) {
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
