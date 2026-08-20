import SwiftUI

struct SignalASIAgentHomeNavigationRoutesView: View {
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
  @Binding var chatListShortcutActive: Bool
  @Binding var contactsShortcutActive: Bool
  @Binding var discoverShortcutActive: Bool

  var recentTaskForDetails: AgentTaskRecord?
  var screen: AgentScreenContext
  var screenSections: [SignalASIAgentScreenDetailSection]
  var onModelSelectionChanged: () -> Void
  var onScreenCommand: (String) -> Void
  var onRefreshScreen: () -> Void
  var t: (String, String) -> String

  var body: some View {
    Group {
      NavigationLink(
        destination: SignalASIAgentRecentTasksView(initialTask: recentTaskForDetails),
        isActive: $recentTasksShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: SignalASIConversationHubView(),
        isActive: $agentSessionsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: SignalASIControlCenterView(),
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
        destination: SignalASIAgentModelSelectionView(onSelectionChanged: onModelSelectionChanged),
        isActive: $agentModelSelectionShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: SignalASINativeToolCatalogView(),
        isActive: $agentNativeToolsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: SignalASIAgentMemoryView(),
        isActive: $agentMemoryShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: SignalASIAgentKnowledgeView(),
        isActive: $agentKnowledgeShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: SignalASIAgentScreenContextDetailView(
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
        destination: SignalASIGlobalAgentInsightInboxView(),
        isActive: $agentInsightsShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: ChatListView(),
        isActive: $chatListShortcutActive
      ) {
        EmptyView()
      }
      .hidden()
      NavigationLink(
        destination: ContactsView(),
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
