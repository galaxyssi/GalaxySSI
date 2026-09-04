import SwiftUI

struct GalaxySSIAgentHomeNavigationRoutesView: View {
  @Binding var recentTasksShortcutActive: Bool
  @Binding var agentSessionsShortcutActive: Bool
  @Binding var agentSettingsShortcutActive: Bool
  @Binding var agentPermissionsShortcutActive: Bool
  @Binding var agentModelSelectionShortcutActive: Bool
  @Binding var agentNativeToolsShortcutActive: Bool
  @Binding var agentMemoryShortcutActive: Bool
  @Binding var agentKnowledgeShortcutActive: Bool
  @Binding var agentScreenContextShortcutActive: Bool
  @Binding var agentInsightsShortcutActive: Bool
  @Binding var conversationHubShortcutActive: Bool
  @Binding var contactsShortcutActive: Bool
  @Binding var discoverShortcutActive: Bool

  var recentTaskForDetails: AgentTaskRecord?
  var screen: AgentScreenContext
  var screenSections: [GalaxySSIAgentScreenDetailSection]
  var onModelSelectionChanged: () -> Void
  var onScreenCommand: (String) -> Void
  var onRefreshScreen: () -> Void
  var t: (String, String) -> String

  var body: some View {
    Group {
      NavigationLink(
        destination: GalaxySSIAgentRecentTasksView(initialTask: recentTaskForDetails),
        isActive: $recentTasksShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIConversationHubView(),
        isActive: $agentSessionsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIControlCenterView(),
        isActive: $agentSettingsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: OnDeviceAgentPermissionsView(),
        isActive: $agentPermissionsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIAgentModelSelectionView(onSelectionChanged: onModelSelectionChanged),
        isActive: $agentModelSelectionShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSINativeToolCatalogView(),
        isActive: $agentNativeToolsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIAgentMemoryView(),
        isActive: $agentMemoryShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIAgentKnowledgeView(),
        isActive: $agentKnowledgeShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIAgentScreenContextDetailView(
            screen: screen,
            sections: screenSections,
            onCommand: onScreenCommand,
            t: t,
            onRefresh: onRefreshScreen
        ),
        isActive: $agentScreenContextShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIGlobalAgentInsightInboxView(),
        isActive: $agentInsightsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIConversationHubView(),
        isActive: $conversationHubShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: GalaxySSIConversationHubView(initialTab: .contacts),
        isActive: $contactsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: DiscoverView(),
        isActive: $discoverShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
    }
  }
}
