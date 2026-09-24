import Foundation

struct GalaxySSITransportReceiptRecord: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var peerId: String
  var phonePeer: Bool
  var binding: String
  var receivedMessageId: String
  var wirePayload: String
  var nextAttemptAtMillis: Int64
  var attemptToken: String
}

@MainActor
final class GalaxySSITransportReceiptJournal {
  private let fileURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private var records: [GalaxySSITransportReceiptRecord]

  init(
    applicationSupportDirectory: URL? = nil,
    cipher: GalaxySSIAttachmentAtRestCipher = .shared
  ) {
    let support = applicationSupportDirectory ?? FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    fileURL = support
      .appendingPathComponent("transport-receipts-v1", isDirectory: true)
      .appendingPathComponent("journal.saenc", isDirectory: false)
    self.cipher = cipher
    records = (try? cipher.read(from: fileURL, purpose: Self.purpose))
      .flatMap { try? JSONDecoder().decode([GalaxySSITransportReceiptRecord].self, from: $0) } ?? []
  }

  func enqueue(
    peerId: String,
    phonePeer: Bool,
    binding: String,
    receivedMessageId: String,
    wirePayload: String,
    nowMillis: Int64? = nil
  ) throws {
    let nowMillis = nowMillis ?? Self.nowMillis()
    let id = Self.receiptId(
      peerId: peerId,
      phonePeer: phonePeer,
      binding: binding,
      receivedMessageId: receivedMessageId
    )
    guard !records.contains(where: { $0.id == id }) else { return }
    records.append(GalaxySSITransportReceiptRecord(
      id: id,
      peerId: peerId,
      phonePeer: phonePeer,
      binding: binding,
      receivedMessageId: receivedMessageId,
      wirePayload: wirePayload,
      nextAttemptAtMillis: nowMillis,
      attemptToken: ""
    ))
    try save()
  }

  func due(nowMillis: Int64? = nil, limit: Int = 4) -> [GalaxySSITransportReceiptRecord] {
    let nowMillis = nowMillis ?? Self.nowMillis()
    return Array(records
      .filter { $0.nextAttemptAtMillis <= nowMillis }
      .sorted { $0.nextAttemptAtMillis < $1.nextAttemptAtMillis }
      .prefix(max(1, min(32, limit))))
  }

  func claim(id: String, nowMillis: Int64? = nil) throws -> GalaxySSITransportReceiptRecord? {
    let nowMillis = nowMillis ?? Self.nowMillis()
    guard let index = records.firstIndex(where: { $0.id == id && $0.nextAttemptAtMillis <= nowMillis }) else {
      return nil
    }
    records[index].attemptToken = UUID().uuidString
    records[index].nextAttemptAtMillis = nowMillis + 12_000
    try save()
    return records[index]
  }

  func acknowledge(id: String, attemptToken: String) throws {
    let before = records.count
    records.removeAll { $0.id == id && $0.attemptToken == attemptToken }
    if records.count != before { try save() }
  }

  func discard(id: String) throws {
    let before = records.count
    records.removeAll { $0.id == id }
    if records.count != before { try save() }
  }

  func reconnect(nowMillis: Int64? = nil) throws {
    let nowMillis = nowMillis ?? Self.nowMillis()
    for index in records.indices {
      records[index].attemptToken = ""
      records[index].nextAttemptAtMillis = min(records[index].nextAttemptAtMillis, nowMillis)
    }
    try save()
  }

  var nextDueMillis: Int64? { records.map(\.nextAttemptAtMillis).min() }

  static func binding(peerId: String, routes: GalaxySSILinkRoutes) -> String {
    AgentBlobProtocol.sha256(Data([
      peerId, routes.clientRouteId, routes.localFingerprint,
      routes.remoteFingerprint, routes.linkSecret
    ].joined(separator: "\u{001f}").utf8))
  }

  private func save() throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try cipher.write(try JSONEncoder().encode(records), to: fileURL, purpose: Self.purpose)
  }

  private static func receiptId(
    peerId: String,
    phonePeer: Bool,
    binding: String,
    receivedMessageId: String
  ) -> String {
    AgentBlobProtocol.sha256(Data(
      "\(phonePeer ? "phone" : "desktop")\u{001f}\(peerId)\u{001f}\(binding)\u{001f}\(receivedMessageId)".utf8
    ))
  }

  private static func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private static let purpose = "transport-receipt-journal-v1"
}

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
    do {
      try transportReceiptJournal.enqueue(
        peerId: link.desktopId,
        phonePeer: false,
        binding: GalaxySSITransportReceiptJournal.binding(peerId: link.desktopId, routes: link.routes),
        receivedMessageId: receivedMessageId,
        wirePayload: String(decoding: wire, as: UTF8.self)
      )
      wakeTransportReceiptDrain()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func transportReceiptReadinessChanged(_ ready: Bool) {
    if ready {
      try? transportReceiptJournal.reconnect()
      wakeTransportReceiptDrain()
    } else {
      transportReceiptDrainTask?.cancel()
      transportReceiptDrainTask = nil
    }
  }

  func wakeTransportReceiptDrain() {
    guard mqttClient.relationshipSubscriptionsReady, transportReceiptDrainTask == nil else { return }
    transportReceiptDrainTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { transportReceiptDrainTask = nil }
      while !Task.isCancelled, mqttClient.relationshipSubscriptionsReady {
        for record in transportReceiptJournal.due(limit: 2) {
          guard let work = try? transportReceiptJournal.claim(id: record.id) else { continue }
          guard let (topic, routes) = currentTransportReceiptRoute(work),
                GalaxySSITransportReceiptJournal.binding(peerId: work.peerId, routes: routes) == work.binding,
                let wire = work.wirePayload.data(using: .utf8) else {
            try? transportReceiptJournal.discard(id: work.id)
            continue
          }
          let result = await mqttClient.publishTransportReceipt(topic: topic, payload: wire) {
            Task { @MainActor [weak self] in
              guard let self else { return }
              try? transportReceiptJournal.acknowledge(
                id: work.id,
                attemptToken: work.attemptToken
              )
              wakeTransportReceiptDrain()
            }
          }
          if !result.accepted { break }
        }
        guard let next = transportReceiptJournal.nextDueMillis else { return }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        try? await Task.sleep(nanoseconds: UInt64(max(250, next - now)) * 1_000_000)
      }
    }
  }

  private func currentTransportReceiptRoute(
    _ record: GalaxySSITransportReceiptRecord
  ) -> (String, GalaxySSILinkRoutes)? {
    if record.phonePeer {
      guard let contact = store.contact(id: record.peerId),
            contact.isCommunicable,
            let routes = contact.opaquePhoneRoutes else { return nil }
      return (routes.upTopic, routes)
    }
    guard let link = store.serverLinks.first(where: { $0.paired && $0.desktopId == record.peerId }) else {
      return nil
    }
    return (link.routes.controlTopic, link.routes)
  }
}
