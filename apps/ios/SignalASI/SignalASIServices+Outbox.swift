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
    handleExhaustedDeliveries(
      deliveryStore.discardExhausted(maxAttempts: Self.maximumOutboxDeliveryAttempts)
    )
    let mediaProfile = mediaNetworkProfileProvider()
    let pending = deliveryStore.pending(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts
    )
    guard !pending.isEmpty else { return }
    var rejectedSourceIds = Set<String>()
    for item in pending {
      let sourceId = item.clientSourceMessageId.ifBlank(item.messageId)
      if rejectedSourceIds.contains(sourceId) { continue }
      if let reason = SignalASIMqttWireChunking.permanentRejectionReason(
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
      let result = await mqttClient.publish(topic: item.topic, payload: Data(item.wirePayload.utf8))
      if result == .published {
        deliveryStore.markPublished(messageId: item.messageId)
      }
    }
  }

  func scheduleOutboxFlushFromStore() {
    let mediaProfile = mediaNetworkProfileProvider()
    if let delay = deliveryStore.nextRetryDelay(
      allowValidatedNetworkMessages: mediaProfile.canUploadDeferredMedia,
      maxAttempts: Self.maximumOutboxDeliveryAttempts
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
