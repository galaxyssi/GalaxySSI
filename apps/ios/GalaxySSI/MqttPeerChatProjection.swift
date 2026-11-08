import Foundation

struct MqttDesktopPeerArtifact {
  let id: String
  let uri: String
  let taskID: String
  let digest: String
  let size: Int64
  let localID: String
  let localURI: String

  init(_ payload: [String: Any], source: String, identity: MqttBusinessIdentity) throws {
    id = payload.string("artifact_id")
    uri = payload.string("artifact_uri")
    digest = payload.string("sha256")
    size = try MqttRouteProtocol.integer(payload, "size_bytes")
    taskID = source
    guard let sourceUUID = UUID(uuidString: source), MqttRouteProtocol.hex(id, count: 64),
          MqttRouteProtocol.hex(digest, count: 64), (1...AgentDesktopArtifactStore.maximumMqttArtifactBytes).contains(size),
          uri.utf8.count <= 2_048, let remote = URLComponents(string: uri),
          remote.scheme == "galaxyssi-artifact", let host = remote.host, UUID(uuidString: host) == sourceUUID,
          remote.user == nil, remote.password == nil, remote.port == nil,
          remote.query == nil, remote.fragment == nil, !remote.path.isEmpty else { throw MqttRouteError.invalidPayload }
    let namespacedID = MqttRouteProtocol.digest(try GalaxySSILinkProtocol.jsonData([identity.binding, id, uri, digest]))
    localID = namespacedID
    var components = URLComponents()
    components.scheme = "galaxyssi-artifact"
    components.host = "peer-local"
    let name = AgentDesktopArtifactStore.safeFileName((remote.path as NSString).lastPathComponent)
    components.path = "/\(namespacedID)/\(name)"
    guard let local = components.string else { throw MqttRouteError.invalidPayload }
    localURI = local
  }

  func storagePayload(_ original: [String: Any]) -> [String: Any] {
    var payload = original
    payload["artifact_id"] = localID
    payload["artifact_uri"] = localURI
    payload["task_id"] = taskID
    return payload
  }
}

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
    currentDestinations().map(\.peer)
  }

  func currentDestinations() -> [Destination] { store.contacts.compactMap { destination(for: $0) } }

  func outgoingRequest(for messageId: UUID, contactId: String, messageKind: String = "",
                       durationMillis: Int64 = 0) throws -> MqttSignalSendRequest {
    guard let request = try outgoingRequests(for: messageId, contactId: contactId, attachments: [],
      messageKind: messageKind, durationMillis: durationMillis).last else {
      throw MqttRouteError.invalidPayload
    }
    return request
  }

  func outgoingRequests(for messageId: UUID, contactId: String,
                        attachments: [AgentPreparedOutboundAttachment], messageKind: String = "",
                        durationMillis: Int64 = 0, blobTransfers: Set<String> = []) throws -> [MqttSignalSendRequest] {
    guard let contact = store.contact(id: contactId), contact.id == contactId, let target = destination(for: contact),
          let message = store.persistedMessage(id: messageId, contactId: contactId), message.isMine, !message.isSystem,
          [.queued, .failed].contains(message.deliveryStatus),
          !attachments.isEmpty || (!message.content.isBlank && message.richOutputJson.isBlank),
          attachments.count <= 10, Set(attachments.map(\.transferId)).count == attachments.count
    else { throw MqttRouteError.invalidPayload }
    guard blobTransfers.isEmpty || (target.desktop && blobTransfers.isSubset(of: Set(attachments.map(\.transferId))))
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
    let kind = String(messageKind.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
    if !kind.isEmpty { payload["message_kind"] = kind }
    if durationMillis > 0 { payload["duration_ms"] = min(durationMillis, 3_600_000) }
    guard attachments.allSatisfy({ matches($0, target: target, source: source) }) else { throw MqttRouteError.identityChanged }
    let manifests = try attachments.filter { !blobTransfers.contains($0.transferId) }.map { transfer in
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
      sourceMessageID: source, contactID: target.contactId, blobAttachmentDependencies: Array(blobTransfers))
    return manifests + [body]
  }

  func matches(_ transfer: AgentPreparedOutboundAttachment, target: Destination, source: String) -> Bool {
    transfer.scope.clientMessageId == source && transfer.scope.clientRouteId == target.routeId &&
      transfer.scope.contactId == target.peer.remoteSignalName && transfer.scope.desktopId == target.peer.remoteSignalName &&
      transfer.scope.conversationId == target.conversationId &&
      transfer.scope.taskId == AgentPeerChatTransport.taskId(for: source) &&
      transfer.scope.turnId == AgentPeerChatTransport.turnId(for: source)
  }

  func desktopPeerSource(_ payload: [String: Any], target: Destination) throws -> String {
    let source = payload.string("source_message_id")
    guard target.desktop, payload.string("desktop_id") == target.peer.remoteSignalName,
          payload.string("contact_id") == target.peer.remoteSignalName,
          payload.string("client_route_id") == target.routeId,
          payload.string("conversation_id") == target.conversationId, UUID(uuidString: source) != nil
    else { throw MqttRouteError.identityChanged }
    return source
  }

  static func desktopBlobReceiptRequest(_ receipt: [String: Any], target: Destination) throws -> MqttSignalSendRequest {
    let fields = ["type", "version", "status", "transfer_id", "client_route_id", "artifact_id", "sha256",
      "size_bytes", "conversation_id", "task_id", "turn_id", "contact_id", "execution_generation"]
    guard target.desktop, receipt.string("client_route_id") == target.routeId else { throw MqttRouteError.identityChanged }
    guard Set(receipt.keys) == Set(fields), receipt.string("type") == AgentBlobArtifactContract.receiptType,
          receipt.string("status") == "stored", try MqttRouteProtocol.integer(receipt, "version") == 1,
          (1...AgentBlobProtocol.maximumFileBytes).contains(try MqttRouteProtocol.integer(receipt, "size_bytes")),
          try MqttRouteProtocol.integer(receipt, "execution_generation") > 0,
          ["transfer_id", "artifact_id", "sha256"].allSatisfy({ MqttRouteProtocol.hex(receipt.string($0), count: 64) })
    else { throw MqttRouteError.invalidPayload }
    for key in ["conversation_id", "task_id", "turn_id", "contact_id"] {
      _ = try MqttDeliveryEnvelope.checkedText(receipt[key], maximum: 256)
    }
    return try desktopBlobControlRequest(receipt, target: target)
  }

  static func desktopBlobCapabilityRequest(_ payload: [String: Any], target: Destination) throws -> MqttSignalSendRequest {
    guard target.desktop, payload.string("client_route_id") == target.routeId,
          payload.string("desktop_id") == target.peer.remoteSignalName,
          payload.string("desktop_fingerprint") == target.routes.remoteFingerprint else { throw MqttRouteError.identityChanged }
    guard Set(payload.keys) == ["type", "version", "revision", "enabled", "desktop_id", "client_route_id", "desktop_fingerprint"],
          payload.string("type") == "artifact_blob_capability", try MqttRouteProtocol.integer(payload, "version") == 1,
          try MqttRouteProtocol.integer(payload, "revision") > 0, payload["enabled"] is Bool else {
      throw MqttRouteError.invalidPayload
    }
    return try desktopBlobControlRequest(payload, target: target)
  }

  private static func desktopBlobControlRequest(_ original: [String: Any], target: Destination) throws -> MqttSignalSendRequest {
    let identity = try MqttBusinessIdentity(target.peer.binding)
    let digest = MqttRouteProtocol.digest(try MqttBusinessStorage.payload(original))
    var payload = original
    let discriminator = original.string("type") == AgentBlobArtifactContract.receiptType
      ? "desktop-blob-stored" : "desktop-blob-capability"
    payload["message_id"] = try stableID([identity.binding, discriminator, digest])
    return try MqttSignalSendRequest(identity: identity, payload: payload, remoteName: target.peer.remoteSignalName,
      topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control, contactID: target.contactId)
  }

  static func desktopBlobOfferRequest(_ payload: [String: Any], attachment: AgentPreparedOutboundAttachment,
                                      target: Destination, peerChat: Bool = true) throws -> MqttSignalSendRequest {
    let scope = attachment.scope
    guard target.desktop, scope.desktopId == target.peer.remoteSignalName, scope.clientRouteId == target.routeId,
          (scope.contactId == target.peer.remoteSignalName) == peerChat,
          !peerChat || scope.conversationId == target.conversationId,
          payload.string("type") == "input_attachment_blob_offer",
          let offer = payload["blob_offer"] as? [String: Any],
          let raw = offer["private"] as? [String: Any] else { throw MqttRouteError.identityChanged }
    let descriptor = try AgentBlobArtifactContract.descriptor(raw)
    let expected = try AgentBlobProtocol.offerPayload(attachment: attachment, offer: offer)
    guard try AgentBlobProtocol.canonicalJSON(payload) == AgentBlobProtocol.canonicalJSON(expected),
          descriptor.size == attachment.sizeBytes, descriptor.sha256 == attachment.sha256,
          descriptor.bindingSHA256 == (try AgentBlobProtocol.bindingHash(AgentBlobProtocol.binding(for: attachment))),
          AgentBlobProtocol.validHex(offer.string("read_token"), bytes: 32) else { throw MqttRouteError.invalidPayload }
    let identity = try MqttBusinessIdentity(target.peer.binding)
    let digest = MqttRouteProtocol.digest(try MqttBusinessStorage.payload(expected))
    var wire = payload
    if peerChat { wire["peer_chat"] = true }
    wire["message_id"] = try stableID([identity.binding, attachment.transferId, "desktop-blob-offer", digest])
    return try MqttSignalSendRequest(identity: identity, payload: wire, remoteName: target.peer.remoteSignalName,
      topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control,
      requiresValidatedNetwork: attachment.requiresValidatedNetwork, attachmentTransferID: attachment.transferId,
      sourceMessageID: peerChat ? "" : (scope.clientMessageId ?? ""),
      contactID: peerChat ? target.contactId : scope.contactId)
  }

  func desktopPeerBlobDescriptors(_ descriptors: [[String: Any]], payload: [String: Any],
                                  item: MqttBusinessInbox.Pending, target: Destination) throws -> [AgentBlobPeerStorage] {
    let source = try desktopPeerSource(payload, target: target)
    guard payload.string("type") == "peer_message", payload["peer_chat"] as? Bool == true,
          payload.string("task_id") == source, UUID(uuidString: source) == UUID(uuidString: item.messageID),
          try MqttRouteProtocol.integer(payload, "execution_generation") == 1,
          (1...12).contains(descriptors.count) else { throw MqttRouteError.invalidPayload }
    let artifacts = try descriptors.map { try AgentBlobPeerStorage(descriptor: $0, sourceID: source, binding: item.identity.binding) }
    guard Set(artifacts.map(\.localID)).count == artifacts.count,
          Set(artifacts.map(\.transferID)).count == artifacts.count else { throw MqttRouteError.invalidPayload }
    return artifacts
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
      "task_id": target.desktop ? source : AgentPeerChatTransport.taskId(for: source), "turn_id": turn
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
