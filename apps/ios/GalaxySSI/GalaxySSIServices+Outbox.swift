import Foundation

@MainActor
extension MessageCoordinator {
  private func flushPendingOutbox() async {
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
      } else {
        scheduleOutboxFlushFromStore()
      }
    }
    let discardedTransfers = attachmentTransferStore.prune()
    if !discardedTransfers.isEmpty {
      _ = deliveryStore.discardBlockedByAttachmentTransfers(discardedTransfers)
    }
    var activeMessageIds = await mqttClient.outstandingDurableMessageIds()
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
    for item in pending {
      if activeMessageIds.contains(item.messageId) { continue }
      let sourceId = item.clientSourceMessageId.ifBlank(item.messageId)
      if rejectedSourceIds.contains(sourceId) { continue }
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
      deliveryStore.markAttempt(messageId: item.messageId)
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
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
      await self?.flushPendingOutbox()
    }
  }
}
