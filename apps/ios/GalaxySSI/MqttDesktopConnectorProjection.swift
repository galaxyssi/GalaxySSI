import Foundation

@MainActor
struct MqttDesktopConnectorProjection {
  let store: GalaxySSIStore
  let identities: AgentTaskIdentityStore
  let commitResponse: (AgentConnectorResponse, [String: Any]) throws -> Void
  var completedResult: (([String: Any], AgentResultReceipt) throws -> Void)? = nil
  var resultRecovery: (() -> AgentDesktopResultRecovery?)? = nil
  var receiveRecoveryControl: (([String: Any], String) throws -> Void)? = nil
  var recoveryQueries: (((AgentDesktopReplyBinding) -> Bool) -> [[String: Any]])? = nil

  static func handles(_ payload: [String: Any]) -> Bool {
    payload["peer_chat"] as? Bool != true &&
      ["agent_task_event", "text", "agent_response", "agent_task_result_receipt_confirmed",
       "agent_task_recovery_result", "agent_task_result_page"].contains(payload.string("type"))
  }

  private func contact(_ payload: [String: Any], target: MqttPeerChatProjection.Destination) throws -> GalaxySSIContact {
    let desktop = target.peer.remoteSignalName
    guard target.desktop, let contact = store.contact(id: payload.string("contact_id")),
          contact.id == payload.string("contact_id"), contact.isCommunicable, !contact.isDesktopDeviceContact,
          contact.deliveryMode.isGalaxySSILinkFamily, contact.desktopId == desktop, !contact.connectorAgentId.isBlank,
          payload.string("desktop_id").ifBlank(desktop) == desktop,
          payload.string("agent_id").ifBlank(payload.string("connector_id")) == contact.connectorAgentId,
          payload.string("client_route_id") == target.routeId, identities.matchesRegistered(payload: payload),
          !GalaxySSITransportPrivacyPolicy.isLocalOnly(payload) else { throw MqttRouteError.identityChanged }
    return contact
  }

  func outgoingRequest(_ payload: [String: Any], target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    let contact = try contact(payload, target: target)
    guard payload.string("type") == "text", Self.handles(payload),
          payload["attachments"] == nil || (payload["attachments"] as? [Any])?.isEmpty == true else {
      throw MqttRouteError.invalidPayload
    }
    var application = payload
    let source = payload.string("source_message_id").ifBlank(payload.string("client_message_id"))
    let messageID = payload.string("message_id")
    guard let uuid = UUID(uuidString: messageID), !source.isBlank else { throw MqttRouteError.invalidPayload }
    if let sourceID = UUID(uuidString: source) {
      guard let saved = store.persistedMessage(id: sourceID, contactId: contact.id), saved.isMine,
            saved.turnId.ifBlank(source) == payload.string("turn_id"),
            AgentTaskIdentityPolicy.conversationId(contactId: contact.id, requested: saved.conversationId) ==
              payload.string("conversation_id") else { throw MqttRouteError.identityChanged }
    } else if (Int64(source) ?? 0) <= 0 {
      throw MqttRouteError.invalidPayload
    }
    application["message_id"] = uuid.uuidString
    return try MqttSignalSendRequest(identity: MqttBusinessIdentity(target.peer.binding), payload: application,
      remoteName: target.peer.remoteSignalName, topic: target.peer.binding.sendTopic, clientRouteID: target.routeId,
      sourceMessageID: source, contactID: contact.id)
  }

  func project(_ item: MqttBusinessInbox.Pending, payload: [String: Any],
               target: MqttPeerChatProjection.Destination) throws {
    guard try MqttBusinessIdentity(target.peer.binding) == item.identity,
          item.key == (try item.identity.key(messageID: item.messageID)),
          payload.string("message_id") == item.messageID, Self.handles(payload) else {
      throw MqttRouteError.invalidPayload
    }
    if ["agent_task_recovery_result", "agent_task_result_page"].contains(payload.string("type")) {
      guard target.desktop, payload.string("client_route_id") == target.routeId,
            payload.string("desktop_id").ifBlank(target.peer.remoteSignalName) == target.peer.remoteSignalName,
            let receiveRecoveryControl else { throw MqttRouteError.identityChanged }
      let fields: [String: Any]
      if payload.string("type") == "agent_task_recovery_result" {
        guard let items = payload["items"] as? [[String: Any]], items.count == 1,
              let item = items.first else { throw MqttRouteError.invalidPayload }
        fields = item
      } else { fields = payload }
      _ = try contact(fields, target: target)
      try receiveRecoveryControl(payload, target.peer.remoteSignalName)
      return
    }
    let contact = try contact(payload, target: target)
    if payload.string("type") == "agent_task_result_receipt_confirmed" {
      guard let recovery = resultRecovery?(),
            let receipt = AgentResultReceipt.confirmedPayload(payload, desktopId: target.peer.remoteSignalName),
            let state = recovery.receipts.recordedState(receipt) else { throw MqttRouteError.unsolicitedAcknowledgement }
      if state == .pending, !recovery.receipts.confirm(receipt) { throw MqttChunkStorageError.databaseFailure }
      return
    }
    if payload.string("type") == "agent_task_event" {
      guard let source = UUID(uuidString: payload.string("source_message_id")),
            let saved = store.persistedMessage(id: source, contactId: contact.id), saved.isMine,
            saved.conversationId == payload.string("conversation_id"),
            saved.turnId.ifBlank(source.uuidString) == payload.string("turn_id"),
            let session = store.agentSession(id: saved.conversationId),
            !session.privateMode, !session.trackingPaused else { throw MqttRouteError.invalidPayload }
      let updates = AgentConnectorPublicProgress.entries(payload) { key, fallback in
        GalaxySSILocalization.string(key, fallback: fallback, language: store.languagePolicy.interfaceLanguage)
      }
      guard !updates.isEmpty else { throw MqttRouteError.invalidPayload }
      guard store.persistConnectorProgress(sourceId: source, conversationId: saved.conversationId,
        turnId: payload.string("turn_id"), updates: updates) == true else { throw MqttChunkStorageError.databaseFailure }
      return
    }
    if payload.string("type") == "text", payload.string("task_status") == "completed",
       UUID(uuidString: payload.string("source_message_id")) != nil,
       let receipt = AgentResultReceipt.fromPayload(payload, desktopId: target.peer.remoteSignalName),
       let completedResult {
      try completedResult(payload, receipt)
      return
    }
    guard payload["result_recovery"] == nil,
          AgentResultReceipt.fromPayload(payload, desktopId: target.peer.remoteSignalName) == nil,
          let response = AgentConnectorResponse.fromPayload(payload, nowMillis: item.createdAt) else {
      throw MqttRouteError.invalidPayload
    }
    try commitResponse(response, payload)
  }

  func validateResultReceipt(_ receipt: AgentResultReceipt, target: MqttPeerChatProjection.Destination) throws {
    guard receipt.desktopId == target.peer.remoteSignalName else { throw MqttRouteError.identityChanged }
    _ = try contact(receipt.payload, target: target)
  }

  func recoveryQueryRequest(_ payload: [String: Any], target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    guard target.desktop, payload.string("desktop_id") == target.peer.remoteSignalName,
          payload.string("client_route_id") == target.routeId,
          let id = UUID(uuidString: payload.string("request_id")), id.uuidString == payload.string("request_id") else {
      throw MqttRouteError.identityChanged
    }
    switch payload.string("type") {
    case "agent_task_recovery_request":
      guard let items = payload["items"] as? [[String: Any]], items.count == 1, let item = items.first else {
        throw MqttRouteError.invalidPayload
      }
      _ = try contact(item, target: target)
    case "agent_task_result_page_request":
      _ = try contact(payload, target: target)
    default: throw MqttRouteError.invalidPayload
    }
    var application = payload
    application["message_id"] = id.uuidString
    return try MqttSignalSendRequest(identity: MqttBusinessIdentity(target.peer.binding), payload: application,
      remoteName: target.peer.remoteSignalName, topic: target.peer.binding.sendTopic, clientRouteID: target.routeId,
      traffic: .control, contactID: target.contactId)
  }

  func resultReceiptRequest(_ work: AgentResultReceiptWork, target: MqttPeerChatProjection.Destination) throws -> MqttSignalSendRequest {
    let receipt = work.receipt
    guard work.state == .pending, (0...30).contains(work.attempts) else { throw MqttRouteError.invalidPayload }
    try validateResultReceipt(receipt, target: target)
    let identity = try MqttBusinessIdentity(target.peer.binding)
    var payload = receipt.payload
    payload["message_id"] = try MqttPeerChatProjection.stableID(
      [identity.binding, receipt.id, String(work.attempts), String(work.dueAtMillis), "result-receipt"])
    return try MqttSignalSendRequest(identity: identity, payload: payload, remoteName: target.peer.remoteSignalName,
      topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control, contactID: target.contactId)
  }

  func projectCompletion(_ event: MqttDeliveryCompletions.Event, target: MqttPeerChatProjection.Destination) throws {
    guard target.desktop, let contact = store.contact(id: event.contactID), contact.id == event.contactID,
          contact.isCommunicable, !contact.isDesktopDeviceContact,
          contact.desktopId == target.peer.remoteSignalName, contact.deliveryMode.isGalaxySSILinkFamily,
          event.traffic == MqttMultipathPolicy.Traffic.message.rawValue, event.attachmentTransferID.isEmpty,
          let identity = identities.identity(contactId: contact.id, sourceMessageId: event.sourceMessageID),
          identity.clientRouteId == target.routeId else { throw MqttRouteError.identityChanged }
    guard UUID(uuidString: event.sourceMessageID) != nil else { return }
    do { try store.persistTransportDelivery(event) }
    catch GalaxySSIChatHistoryError.locallyDeleted { }
  }
}
