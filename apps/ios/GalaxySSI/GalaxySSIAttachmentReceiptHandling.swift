import Foundation

/// Handles the receipt side of the Agent attachment protocol independently
/// from the main message and response coordinator.
extension MessageCoordinator {
  func handleInputAttachmentReceipt(_ payload: [String: Any], link: ServerLink?) {
    let transferId = payload.string("transfer_id").lowercased()
    guard let link,
          let transfer = attachmentTransferStore.find(transferId),
          transfer.scope.desktopId == link.desktopId,
          transfer.scope.clientRouteId == link.routes.clientRouteId,
          payload.string("client_route_id") == transfer.scope.clientRouteId else {
      return
    }
    if payload.string("status") == "stored" {
      Task { [weak self] in
        guard let self else { return }
        if await blobOutgoingCoordinator.owns(transfer.transferId) {
          guard (try? await blobOutgoingCoordinator.acceptStored(
            payload,
            link: link,
            attachment: transfer
          )) == true else { return }
        }
        completeStoredAttachment(payload, transfer: transfer)
      }
      return
    }
    if payload.string("status") == "failed" {
      Task { [weak self] in
        guard let self else { return }
        guard AgentAttachmentDeliveryFailureContract.matches(
          receipt: payload,
          attachment: transfer
        ) else { return }
        if await blobOutgoingCoordinator.owns(transfer.transferId) {
          try? await blobOutgoingCoordinator.cancel(Set([transfer.transferId]))
        }
        handleFailedAttachmentReceipt(payload, transfer: transfer)
      }
      return
    }
    if payload.string("status") == "missing" {
      Task { [weak self] in
        guard let self else { return }
        if await blobOutgoingCoordinator.owns(transfer.transferId) {
          await blobOutgoingCoordinator.wake()
          return
        }
        resendMissingAttachmentChunks(payload, transfer: transfer, link: link)
      }
    }
  }

  private func resendMissingAttachmentChunks(
    _ payload: [String: Any],
    transfer: AgentPreparedOutboundAttachment,
    link: ServerLink
  ) {
    guard let requested = try? AgentAttachmentTransferProtocol.expandMissingRanges(
      payload["missing_ranges"],
      chunkCount: transfer.chunkCount
    ), !requested.isEmpty else { return }
    for index in requested {
      guard let chunkPayload = try? transfer.chunkPayload(index: index) else { continue }
      try? enqueueLinkPayload(
        chunkPayload,
        link: link,
        topic: link.routes.upTopic,
        requiresValidatedNetwork: transfer.requiresValidatedNetwork,
        clientSourceMessageId: transfer.scope.clientMessageId ?? "",
        contactId: transfer.scope.contactId
      )
    }
    scheduleOutboxFlush(after: 0)
  }

  private func completeStoredAttachment(
    _ payload: [String: Any],
    transfer: AgentPreparedOutboundAttachment
  ) {
    if let contact = store.visibleContacts.first(where: {
      $0.isDesktopDeviceContact && $0.desktopId == transfer.scope.desktopId
    }) {
      var completion = payload
      completion["source_message_id"] = transfer.scope.clientMessageId ?? ""
      completion["attachment_ordinal"] = transfer.ordinal
      completion["name"] = transfer.originalName
      completion["mime_type"] = transfer.mimeType
      completion["size_bytes"] = transfer.originalSizeBytes
      completion["progress"] = 100
      completion["state"] = GalaxySSIPeerAttachmentTransferProgress.complete
      applyPeerAttachmentTransferProgress(completion, contact: contact)
    }
    guard attachmentTransferStore.acknowledgeStored(
      payload: payload,
      deliveryStore: deliveryStore
    ) != nil else { return }
    scheduleOutboxFlush(after: 0)
  }

  private func handleFailedAttachmentReceipt(
    _ payload: [String: Any],
    transfer: AgentPreparedOutboundAttachment
  ) {
    guard let observation = try? attachmentDeliveryFailureStore.record(
      receipt: payload,
      attachment: transfer
    ) else { return }
    _ = deliveryStore.discardAttachmentTransferMessages(transfer.transferId)
    attachmentTransferStore.discard([transfer.transferId], deliveryStore: deliveryStore)
    if let contact = store.visibleContacts.first(where: {
      $0.isDesktopDeviceContact && $0.desktopId == transfer.scope.desktopId
    }) {
      applyPeerAttachmentTransferProgress([
        "transfer_id": transfer.transferId,
        "source_message_id": observation.sourceMessageId,
        "attachment_ordinal": transfer.ordinal,
        "name": transfer.originalName,
        "mime_type": transfer.mimeType,
        "size_bytes": transfer.originalSizeBytes,
        "progress": 0,
        "state": GalaxySSIPeerAttachmentTransferProgress.failed,
        "error_code": observation.errorCode
      ], contact: contact)
    }
    guard let sourceMessageId = Int64(observation.sourceMessageId), sourceMessageId > 0 else {
      scheduleOutboxFlush(after: 0)
      return
    }
    _ = connectorResponseBus.publish(AgentConnectorResponse(
      sourceMessageId: sourceMessageId,
      contactId: observation.contactId,
      content: AgentAttachmentDeliveryFailureContract.observation(observation.errorCode),
      conversationId: observation.conversationId,
      turnId: observation.turnId,
      taskId: observation.taskId,
      success: false,
      receivedAtMillis: observation.observedAtMillis,
      deliveryFailureCode: observation.errorCode
    ))
    scheduleOutboxFlush(after: 0)
  }

  func handleDeliveryAck(_ payload: [String: Any]) {
    let acknowledgedIds = [
      GalaxySSILinkDeliveryAckPolicy.transportMessageId(payload: payload),
      GalaxySSILinkDeliveryAckPolicy.clientSourceMessageId(payload: payload)
    ].filter { !$0.isEmpty }
    acknowledgedIds.forEach { messageId in
      deliveryStore.acknowledge(messageId: messageId)
      if let uuid = UUID(uuidString: messageId) {
        store.appendDeliveryTrace(uuid, stage: "desktop_broker_ack", detail: "Delivery ACK", status: .delivered)
      }
    }
    scheduleOutboxFlushFromStore()
  }

  func publishInboundReceipt(link: ServerLink?, receivedMessageId: String) {
    guard let link, !receivedMessageId.isEmpty else { return }
    let ackPayload: [String: Any] = [
      "type": "delivery_ack",
      "transport_message_id": receivedMessageId,
      "source_message_id": receivedMessageId,
      "delivery_status": "accepted",
      "sender": "system",
      "time": Int64(Date().timeIntervalSince1970 * 1000)
    ]
    let wire: Data?
    if GalaxySSISignalEngine.isAvailable {
      if var encrypted = signalEngine.encrypt(ackPayload, remoteName: link.desktopId) {
        encrypted["message_id"] = receivedMessageId
        encrypted["_client_route_id"] = link.routes.clientRouteId
        wire = try? GalaxySSILinkProtocol.jsonData(encrypted)
      } else {
        wire = nil
      }
    } else if let envelope = try? GalaxySSILinkProtocol.makeEnvelope(
      payload: ackPayload,
      sourceId: store.profile.galaxySSIId,
      targetId: link.desktopId
    ) {
      wire = try? GalaxySSILinkProtocol.jsonData([
        "scheme": "galaxyssi-link-ios-preview",
        "from": store.profile.galaxySSIId,
        "to": link.desktopId,
        "envelope": envelope
      ])
    } else {
      wire = nil
    }
    guard let wire else { return }
    Task {
      _ = await mqttClient.publish(topic: link.routes.controlTopic, payload: wire)
    }
  }
}
