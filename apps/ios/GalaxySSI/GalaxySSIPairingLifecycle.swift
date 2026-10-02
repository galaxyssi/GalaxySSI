import Foundation

struct GalaxySSIMqttApplicationPeer {
  let remoteName: String
  let binding: MqttPeerBinding
}

@MainActor
enum GalaxySSIPairingLifecycle {
  // Subscriptions include pending approvals. Only saved paired/verified relationships may
  // authorize business traffic; a peer's wire payload cannot promote itself to an enabled binding.
  static func mqttPeers(localFingerprint: String, serverLinks: [ServerLink], contacts: [GalaxySSIContact],
                        requests: [GalaxySSIFriendRequest]) throws -> [GalaxySSIMqttApplicationPeer] {
    guard MqttRouteProtocol.hex(localFingerprint, count: 64) else { throw MqttRouteError.identityChanged }
    var result: [GalaxySSIMqttApplicationPeer] = []
    func append(name: String, routes: GalaxySSILinkRoutes, fingerprint: String, enabled: Bool) throws {
      guard routes.isOpaqueV2Valid, routes.localFingerprint == localFingerprint,
            routes.remoteFingerprint == fingerprint else { throw MqttRouteError.identityChanged }
      _ = try MqttDeliveryEnvelope.checkedText(name, maximum: 512)
      let topic = routes.upTopic
      let binding = MqttPeerBinding(scope: routes.clientRouteId, sender: localFingerprint,
        receiver: fingerprint, secret: routes.linkSecret, sendTopic: topic,
        sendTopics: routes.sendWindow.union([topic]), receiveTopics: routes.receiveWindow, enabled: enabled)
      try binding.validate()
      result.append(GalaxySSIMqttApplicationPeer(remoteName: name, binding: binding))
    }
    for link in serverLinks {
      try append(name: link.desktopId, routes: link.routes, fingerprint: link.desktopFingerprint, enabled: link.paired)
    }
    let knownContacts = Set(contacts.map(\.galaxySSIId))
    for contact in contacts where !contact.deleted && contact.trustState != .deleted &&
      contact.type.caseInsensitiveCompare("person") == .orderedSame &&
      contact.desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      guard let routes = contact.opaquePhoneRoutes else { continue }
      try append(name: contact.galaxySSIId, routes: routes, fingerprint: contact.identityFingerprint,
        enabled: contact.isCommunicable)
    }
    for request in requests where !knownContacts.contains(request.galaxySSIId) &&
      (request.status == .pending || request.status == .approved) &&
      request.type.caseInsensitiveCompare("person") == .orderedSame && request.desktopId.isEmpty {
      guard let routes = request.opaquePhoneRoutes else { continue }
      try append(name: request.galaxySSIId, routes: routes, fingerprint: request.identityFingerprint, enabled: false)
    }
    guard result.count <= 10_000, Set(result.map { $0.binding.scope }).count == result.count else {
      throw MqttRouteError.invalidPayload
    }
    let topics = result.flatMap { $0.binding.sendTopics }
    guard Set(topics).count == topics.count else { throw MqttRouteError.invalidPayload }
    return result
  }

  @discardableResult
  static func remove(
    desktopId: String,
    deleteMessages: Bool = true,
    store: GalaxySSIStore,
    mqttClient: GalaxySSIMqttClient,
    deliveryStore: GalaxySSILinkDeliveryStore,
    attachmentTransferStore: AgentOutboundAttachmentTransferStore,
    signalEngine: GalaxySSISignalEngine,
    desktopMarketplaceStore: AgentDesktopMarketplaceStore,
    desktopControlSnapshots: inout [String: AgentDesktopRemoteControlSnapshot],
    desktopControlPendingRequests: inout [String: AgentDesktopControlPendingRequest]
  ) -> Set<String> {
    let cleanDesktopId = desktopId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanDesktopId.isEmpty else { return [] }
    let link = store.serverLinks.first { $0.desktopId == cleanDesktopId }
    if let link {
      mqttClient.unsubscribe(topics: Array(link.routes.receiveWindow))
      _ = deliveryStore.discardRoutes(link.routes)
    }
    let removedContactIds = store.removeDesktopPairing(
      desktopId: cleanDesktopId,
      deleteMessages: deleteMessages
    )
    _ = attachmentTransferStore.discard(
      desktopId: cleanDesktopId,
      deliveryStore: deliveryStore
    )
    signalEngine.forgetRemote(remoteName: cleanDesktopId)
    desktopMarketplaceStore.remove(desktopId: cleanDesktopId)
    desktopControlSnapshots.removeValue(forKey: cleanDesktopId)
    desktopControlPendingRequests = Dictionary(
      desktopControlPendingRequests.filter { $0.value.desktopId != cleanDesktopId },
      uniquingKeysWith: { first, _ in first }
    )
    mqttClient.updateSubscriptions(
      serverLinks: store.serverLinks,
      phoneRoutes: store.phoneOpaqueRoutes()
    )
    return removedContactIds
  }
}
