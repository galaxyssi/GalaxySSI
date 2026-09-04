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
      ) != nil else {
        return
      }
      scheduleOutboxFlush(after: 0)
      return
    }
    guard payload.string("status") == "missing",
          let requested = try? AgentAttachmentTransferProtocol.expandMissingRanges(
            payload["missing_ranges"],
            chunkCount: transfer.chunkCount
          ),
          !requested.isEmpty else {
      return
    }
    for index in requested {
      guard let chunkPayload = try? transfer.chunkPayload(index: index) else {
        continue
      }
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
