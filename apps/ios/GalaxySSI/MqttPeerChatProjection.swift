import Foundation

@MainActor
struct MqttPeerChatProjection {
  struct Destination {
    let contactId: String
    let conversationId: String
    let peer: MqttBusinessTransportRuntime.Peer
    let routeId: String
    let desktop: Bool
    let routes: GalaxySSILinkRoutes
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
      desktop: contact.isDesktopDeviceContact, routes: route)
  }

  func currentPeers() -> [MqttBusinessTransportRuntime.Peer] {
    store.contacts.compactMap { destination(for: $0)?.peer }
  }

  func outgoingRequest(for messageId: UUID, contactId: String) throws -> MqttSignalSendRequest {
    guard let request = try outgoingRequests(for: messageId, contactId: contactId, attachments: []).last else {
      throw MqttRouteError.invalidPayload
    }
    return request
  }

  func outgoingRequests(for messageId: UUID, contactId: String,
                        attachments: [AgentPreparedOutboundAttachment]) throws -> [MqttSignalSendRequest] {
    guard let contact = store.contact(id: contactId), contact.id == contactId, let target = destination(for: contact),
          let message = store.persistedMessage(id: messageId, contactId: contactId), message.isMine, !message.isSystem,
          [.queued, .failed].contains(message.deliveryStatus),
          attachments.isEmpty ? (!message.content.isBlank && message.richOutputJson.isBlank) : !target.desktop,
          attachments.count <= 10, Set(attachments.map(\.transferId)).count == attachments.count
    else { throw MqttRouteError.invalidPayload }
    let source = message.id.uuidString
    let timestamp = message.createdAt.timeIntervalSince1970 * 1_000
    guard timestamp.isFinite, timestamp >= 0, timestamp <= Double(MqttRouteProtocol.maximumInteger) else {
      throw MqttRouteError.invalidPayload
    }
    let wireId = GalaxySSILinkProtocol.normalizedMessageId(source)
    let sender = "galaxyssi:\(localFingerprint.prefix(16))"
    var payload: [String: Any] = [
      "type": "peer_message", "peer_chat": true, "message_id": wireId, "source_message_id": source,
      "client_message_id": source, "sender": sender, "contact_id": target.desktop ? target.peer.remoteSignalName : sender,
      "client_route_id": target.routeId, "conversation_id": target.conversationId,
      "task_id": AgentPeerChatTransport.taskId(for: source), "turn_id": AgentPeerChatTransport.turnId(for: source),
      "content": message.content, "time": Int64(timestamp)
    ]
    let identity = try MqttBusinessIdentity(target.peer.binding)
    let manifests = try attachments.map { transfer in
      guard matches(transfer, target: target, source: source) else { throw MqttRouteError.identityChanged }
      var manifest = transfer.manifestPayload(resume: false, nowMillis: Int64(timestamp))
      manifest["message_id"] = try Self.stableID([identity.binding, source, transfer.transferId, "manifest"])
      manifest["peer_chat"] = true
      return try MqttSignalSendRequest(identity: identity, payload: manifest, remoteName: target.peer.remoteSignalName,
        topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control,
        requiresValidatedNetwork: transfer.requiresValidatedNetwork, attachmentTransferID: transfer.transferId,
        contactID: target.contactId)
    }
    if !attachments.isEmpty { payload["attachments"] = attachments.map { $0.descriptor() } }
    let body = try MqttSignalSendRequest(identity: identity, payload: payload,
      remoteName: target.peer.remoteSignalName, topic: target.peer.binding.sendTopic, clientRouteID: target.routeId,
      requiresValidatedNetwork: attachments.contains { $0.requiresValidatedNetwork },
      attachmentDependencies: attachments.map(\.transferId),
      sourceMessageID: source, contactID: target.contactId)
    return manifests + [body]
  }

  func matches(_ transfer: AgentPreparedOutboundAttachment, target: Destination, source: String) -> Bool {
    !target.desktop && transfer.scope.clientMessageId == source && transfer.scope.clientRouteId == target.routeId &&
      transfer.scope.contactId == target.peer.remoteSignalName && transfer.scope.desktopId == target.peer.remoteSignalName &&
      transfer.scope.conversationId == target.conversationId &&
      transfer.scope.taskId == AgentPeerChatTransport.taskId(for: source) &&
      transfer.scope.turnId == AgentPeerChatTransport.turnId(for: source)
  }

  @discardableResult
  func projectInbound(_ item: MqttBusinessInbox.Pending, resolvedAttachments: [[String: Any]]? = nil) throws -> ChatMessage? {
    guard let target = try currentDestination(item.identity),
          item.key == (try item.identity.key(messageID: item.messageID)),
          let payload = try JSONSerialization.jsonObject(with: item.payload) as? [String: Any],
          payload["message_id"] as? String == item.messageID,
          payload["type"] as? String == "peer_message" ||
            (payload["type"] as? String == "text" && payload["peer_chat"] as? Bool == true),
          payload["attachments"] == nil || (payload["attachments"] as? [Any])?.isEmpty == true ||
            (resolvedAttachments != nil && (payload["attachments"] as? [[String: Any]])?.count == resolvedAttachments?.count)
    else { throw MqttRouteError.invalidPayload }
    let attachments = resolvedAttachments ?? []
    let content = AgentPeerChatTransport.incomingContent(from: payload).ifBlank(attachments.first?.string("name") ?? "")
    guard !content.isBlank, payload["rich_output"] == nil, payload["rich_output_json"] == nil else {
      throw MqttRouteError.invalidPayload
    }
    let rawSource = payload.string("source_message_id").ifBlank(item.messageID)
    let source = try MqttDeliveryEnvelope.checkedText(rawSource)
    let turn = AgentPeerChatTransport.turnId(for: source)
    let richOutput = attachments.isEmpty ? "" : AgentPeerChatTransport.richOutput(for: attachments, context: [
      "client_route_id": target.routeId, "conversation_id": target.conversationId, "contact_id": target.contactId,
      "task_id": AgentPeerChatTransport.taskId(for: source), "turn_id": turn
    ])
    do {
      return try store.persistTransportIncoming(content, from: target.contactId, remoteMessageId: item.messageID,
        conversationId: target.conversationId, turnId: turn,
        richOutputJson: richOutput, tracePrefix: "peer_transport")
    } catch GalaxySSIChatHistoryError.locallyDeleted {
      return nil
    }
  }

  func projectCompletion(_ event: MqttDeliveryCompletions.Event) throws {
    guard let target = try currentDestination(event.identity), target.contactId == event.contactID else {
      throw MqttRouteError.invalidPayload
    }
    if [MqttMultipathPolicy.Traffic.control.rawValue, MqttMultipathPolicy.Traffic.chunk.rawValue].contains(event.traffic),
       !event.attachmentTransferID.isEmpty, event.sourceMessageID.isEmpty { return }
    guard event.traffic == MqttMultipathPolicy.Traffic.message.rawValue, event.attachmentTransferID.isEmpty else {
      throw MqttRouteError.invalidPayload
    }
    do { try store.persistTransportDelivery(event) }
    catch GalaxySSIChatHistoryError.locallyDeleted { return }
  }

  func attachmentReceiptRequest(_ receipt: [String: Any], for item: MqttBusinessInbox.Pending) throws -> MqttSignalSendRequest {
    guard let target = try currentDestination(item.identity), !target.desktop,
          receipt.string("type") == "input_attachment_receipt", receipt.string("client_route_id") == target.routeId
    else { throw MqttRouteError.identityChanged }
    var payload = receipt
    payload["time"] = item.createdAt
    payload["message_id"] = try Self.stableID([item.key, MqttRouteProtocol.digest(GalaxySSILinkProtocol.jsonData(payload))])
    return try MqttSignalSendRequest(identity: item.identity, payload: payload, remoteName: target.peer.remoteSignalName,
      topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control,
      attachmentTransferID: receipt.string("transfer_id"), contactID: target.contactId)
  }

  static func stableID(_ components: [String]) throws -> String {
    let digest = MqttRouteProtocol.digest(try GalaxySSILinkProtocol.jsonData(components))
    let hex = Array(digest.prefix(32))
    let raw = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(hex[$0]) }.joined(separator: "-")
    guard let id = UUID(uuidString: raw) else { throw MqttRouteError.invalidPayload }
    return id.uuidString
  }

  func currentDestination(_ identity: MqttBusinessIdentity) throws -> Destination? {
    try identity.validate()
    guard identity.scope.hasPrefix("direct:"),
          let contact = store.contact(id: String(identity.scope.dropFirst("direct:".count))),
          let target = destination(for: contact),
          try MqttBusinessIdentity(target.peer.binding) == identity else { return nil }
    return target
  }
}
