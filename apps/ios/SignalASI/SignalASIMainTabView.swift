import SwiftUI

struct SignalASIMainTabView: View {
  @State private var selectedTab: SignalASIMainTab = .agent

  var body: some View {
    selectedContent
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .voice:
      SignalASIVoiceTabView(
        onNavigateToMainTab: { selectedTab = $0 },
        onBackToSettings: { selectedTab = .settings }
      )
    case .agent:
      AgentHomeView(onNavigateToMainTab: { selectedTab = $0 })
    case .messages:
      NavigationView {
        SignalASIConversationHubView(
          initialTab: .conversations,
          showsBackButton: false,
          onBackToSettings: { selectedTab = .settings }
        )
      }
      .navigationViewStyle(StackNavigationViewStyle())
    case .contacts:
      NavigationView {
        SignalASIConversationHubView(
          initialTab: .contacts,
          showsBackButton: false,
          onBackToSettings: { selectedTab = .settings }
        )
      }
      .navigationViewStyle(StackNavigationViewStyle())
    case .discover:
      DiscoverView(
        showsBackButton: false,
        onBackToSettings: { selectedTab = .settings }
      )
    case .settings:
      SettingsView(
        navigateToMainTab: { tab in
          selectedTab = tab
        },
        showsBackButton: false,
        onBackToAgent: {
          selectedTab = .agent
        }
      )
    }
  }
}

enum SignalASIMainTab: String, CaseIterable, Identifiable {
  case voice
  case agent
  case messages
  case contacts
  case discover
  case settings

  var id: String { rawValue }
}
