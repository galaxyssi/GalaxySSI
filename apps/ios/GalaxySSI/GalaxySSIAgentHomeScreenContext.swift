import UIKit

extension AgentHomeView {
  var agentScreenSnapshot: GalaxySSIAgentScreenContextSnapshot {
    makeAgentScreenSnapshot(snapshotAgeMillis: agentScreenContextSnapshotAgeMillis)
  }

  var agentScreenContextSnapshotAgeMillis: Int64 {
    max(
      0,
      Int64((Date().timeIntervalSince1970 * 1_000).rounded()) -
        agentScreenContextCapturedAtMillis
    )
  }

  func makeAgentScreenSnapshot(
    snapshotAgeMillis: Int64
  ) -> GalaxySSIAgentScreenContextSnapshot {
    GalaxySSIAgentScreenContextSnapshotBuilder.make(
      messages: messages,
      draft: draft,
      attachments: attachments,
      unreadTotal: unreadTotal,
      screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
      snapshotAgeMillis: snapshotAgeMillis,
      t: t,
      clipboard: agentClipboardContext,
      notifications: agentNotificationContext,
      deviceStatus: agentDeviceStatusContext
    )
  }

  func refreshAgentScreenContext() {
    let capturedAtMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    agentScreenContextCapturedAtMillis = capturedAtMillis
    let source = AgentIOSOwnedNotificationStore.shared.snapshot(limit: 6)
    var sensitiveFlags: [String] = []
    for flag in source.items.flatMap(\.sensitiveFlags) where !sensitiveFlags.contains(flag) {
      sensitiveFlags.append(flag)
    }
    agentNotificationContext = AgentNotificationContext(
      hasAccess: source.hasAccess,
      items: source.items.map { item in
        AgentNotificationItem(
          key: item.key,
          packageName: item.packageName,
          title: item.title,
          textPreview: item.textPreview,
          category: item.category,
          postedAtMillis: item.postedAtMillis,
          canReply: item.canReply,
          sensitiveFlags: item.sensitiveFlags
        )
      },
      sensitiveFlags: sensitiveFlags,
      totalCount: source.totalCount
    )
    agentClipboardContext = store.agentSafetySettings.screenObservationAllowed
      ? AgentClipboardContext.fromText(UIPasteboard.general.string ?? "")
      : AgentClipboardContext()
    agentDeviceStatusContext = store.agentSafetySettings.screenObservationAllowed
      ? GalaxySSIAgentScreenContextSnapshotBuilder.currentDeviceStatus()
      : AgentDeviceStatusContext()
    coordinator.updateAgentScreenContext(makeAgentScreenSnapshot(snapshotAgeMillis: 0).screen)
  }

}
