import Foundation

@MainActor
struct MqttPeerChatProjection {
  struct Destination {
    let contactId: String
    let conversationId: String
    let peer: MqttBusinessTransportRuntime.Peer
    let routeId: String
    let desktop: Bool
  }

  let store: GalaxySSIStore
  let localFingerprint: String

  func destination(for contact: GalaxySSIContact) -> Destination? {
    guard contact.isCommunicable, !contact.id.isBlank else { return nil }
    let route: GalaxySSILinkRoutes
    let remoteName: String
    let conversation: String
    if contact.isDesktopDeviceContact {
      let matches = store.serverLinks.filter { $0.paired && $0.desktopId == contact.desktopId }
      guard matches.count == 1, let link = matches.first else { return nil }
      route = link.routes
      remoteName = link.desktopId
      conversation = AgentPeerChatTransport.conversationId(for: link)
    } else if contact.type.caseInsensitiveCompare("person") == .orderedSame, contact.desktopId.isBlank,
              let phoneRoute = contact.opaquePhoneRoutes {
      route = phoneRoute
      remoteName = contact.galaxySSIId
      conversation = "peer:" + ["galaxyssi:\(localFingerprint.prefix(16))", remoteName].sorted().joined(separator: ":")
    } else { return nil }
    guard !remoteName.isBlank, route.isOpaqueV2Valid, route.localFingerprint == localFingerprint else { return nil }
    let binding = MqttPeerBinding(scope: "direct:\(contact.id)", sender: route.localFingerprint,
      receiver: route.remoteFingerprint, secret: route.linkSecret, sendTopic: route.upTopic,
      sendTopics: route.sendWindow, receiveTopics: route.receiveWindow)
    guard (try? binding.validate()) != nil else { return nil }
    return Destination(contactId: contact.id, conversationId: conversation,
      peer: .init(binding: binding, remoteSignalName: remoteName), routeId: route.clientRouteId,
      desktop: contact.isDesktopDeviceContact)
  }

  func currentPeers() -> [MqttBusinessTransportRuntime.Peer] {
    store.contacts.compactMap { destination(for: $0)?.peer }
  }

  func outgoingRequest(for messageId: UUID, contactId: String) throws -> MqttSignalSendRequest {
    guard let contact = store.contact(id: contactId), contact.id == contactId, let target = destination(for: contact),
          let message = store.persistedMessage(id: messageId, contactId: contactId), message.isMine, !message.isSystem,
          [.queued, .failed].contains(message.deliveryStatus), !message.content.isBlank, message.richOutputJson.isBlank
    else { throw MqttRouteError.invalidPayload }
    let source = message.id.uuidString
    let timestamp = message.createdAt.timeIntervalSince1970 * 1_000
    guard timestamp.isFinite, timestamp >= 0, timestamp <= Double(MqttRouteProtocol.maximumInteger) else {
      throw MqttRouteError.invalidPayload
    }
    let wireId = GalaxySSILinkProtocol.normalizedMessageId(source)
    let sender = "galaxyssi:\(localFingerprint.prefix(16))"
    let payload: [String: Any] = [
      "type": "peer_message", "peer_chat": true, "message_id": wireId, "source_message_id": source,
      "client_message_id": source, "sender": sender, "contact_id": target.desktop ? target.peer.remoteSignalName : sender,
      "client_route_id": target.routeId, "conversation_id": target.conversationId,
      "task_id": AgentPeerChatTransport.taskId(for: source), "turn_id": AgentPeerChatTransport.turnId(for: source),
      "content": message.content, "time": Int64(timestamp)
    ]
    return try MqttSignalSendRequest(identity: MqttBusinessIdentity(target.peer.binding), payload: payload,
      remoteName: target.peer.remoteSignalName, topic: target.peer.binding.sendTopic, clientRouteID: target.routeId,
      sourceMessageID: source, contactID: target.contactId)
  }

  @discardableResult
  func projectInbound(_ item: MqttBusinessInbox.Pending) throws -> ChatMessage? {
    guard let target = try currentDestination(item.identity),
          item.key == (try item.identity.key(messageID: item.messageID)),
          let payload = try JSONSerialization.jsonObject(with: item.payload) as? [String: Any],
          payload["message_id"] as? String == item.messageID,
          payload["type"] as? String == "peer_message" ||
            (payload["type"] as? String == "text" && payload["peer_chat"] as? Bool == true),
          payload["attachments"] == nil || (payload["attachments"] as? [Any])?.isEmpty == true
    else { throw MqttRouteError.invalidPayload }
    let content = AgentPeerChatTransport.incomingContent(from: payload)
    guard !content.isBlank, payload["rich_output"] == nil, payload["rich_output_json"] == nil else {
      throw MqttRouteError.invalidPayload
    }
    let rawSource = payload.string("source_message_id").ifBlank(item.messageID)
    let source = try MqttDeliveryEnvelope.checkedText(rawSource)
    do {
      return try store.persistTransportIncoming(content, from: target.contactId, remoteMessageId: item.messageID,
        conversationId: target.conversationId, turnId: AgentPeerChatTransport.turnId(for: source),
        richOutputJson: "", tracePrefix: "peer_transport")
    } catch GalaxySSIChatHistoryError.locallyDeleted {
      return nil
    }
  }

  func projectCompletion(_ event: MqttDeliveryCompletions.Event) throws {
    guard let target = try currentDestination(event.identity), target.contactId == event.contactID,
          event.traffic == MqttMultipathPolicy.Traffic.message.rawValue, event.attachmentTransferID.isEmpty
    else { throw MqttRouteError.invalidPayload }
    do { try store.persistTransportDelivery(event) }
    catch GalaxySSIChatHistoryError.locallyDeleted { return }
  }

  private func currentDestination(_ identity: MqttBusinessIdentity) throws -> Destination? {
    try identity.validate()
    guard identity.scope.hasPrefix("direct:"),
          let contact = store.contact(id: String(identity.scope.dropFirst("direct:".count))),
          let target = destination(for: contact),
          try MqttBusinessIdentity(target.peer.binding) == identity else { return nil }
    return target
  }
}
