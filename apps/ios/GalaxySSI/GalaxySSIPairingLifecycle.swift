import Foundation

@MainActor
enum GalaxySSIPairingLifecycle {
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
