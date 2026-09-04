import SwiftUI
import UIKit

struct GalaxySSIAgentScreenUnderstandingView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var refreshToken = 0

  private var snapshot: GalaxySSIAgentScreenContextSnapshot {
    _ = refreshToken
    let observationAllowed = store.agentSafetySettings.screenObservationAllowed
    let notificationSource = AgentIOSOwnedNotificationStore.shared.snapshot(limit: 6)
    let notificationContext = AgentNotificationContext(
      hasAccess: notificationSource.hasAccess,
      items: notificationSource.items.map { item in
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
      sensitiveFlags: notificationSource.items.flatMap(\.sensitiveFlags),
      totalCount: notificationSource.totalCount
    )
    let clipboard = observationAllowed
      ? AgentClipboardContext.fromText(UIPasteboard.general.string ?? "")
      : AgentClipboardContext()
    let deviceStatus = observationAllowed
      ? GalaxySSIAgentScreenContextSnapshotBuilder.currentDeviceStatus()
      : AgentDeviceStatusContext()
    return GalaxySSIAgentScreenContextSnapshotBuilder.make(
      messages: [],
      draft: "",
      attachments: [],
      unreadTotal: 0,
      screenObservationAllowed: observationAllowed,
      snapshotAgeMillis: 0,
      t: localized,
      clipboard: clipboard,
      notifications: notificationContext,
      deviceStatus: deviceStatus
    )
  }

  var body: some View {
    GalaxySSIAgentScreenContextDetailView(
      screen: snapshot.screen,
      sections: snapshot.sections,
      onCommand: copyCommand,
      t: localized,
      onRefresh: refresh
    )
    .id(refreshToken)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: refresh) {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel(Text(localized("agent_screen_refresh", "Refresh context")))
      }
    }
  }

  private func refresh() {
    refreshToken &+= 1
  }

  private func copyCommand(_ command: String) {
    UIPasteboard.general.string = command
  }

  private func localized(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
