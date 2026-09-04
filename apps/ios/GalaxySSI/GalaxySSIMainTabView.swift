import SwiftUI

struct GalaxySSIMainTabView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var selectedTab: GalaxySSIMainTab = .agent
  @State private var pendingContactId = ""

  var body: some View {
    selectedContent
      .onAppear(perform: consumePendingContact)
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIOpenContact)) { notification in
        let contactId = ((notification.userInfo?["contactId"] as? String) ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        routeToContact(contactId)
      }
      .task {
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        _ = await GalaxySSISettingsSummaryCache.prepare(store: store)
      }
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .voice:
      GalaxySSIVoiceTabView(
        onNavigateToMainTab: {
          selectedTab = $0
        },
        onBackToSettings: {
          selectedTab = .settings
        }
      )
    case .agent:
      AgentHomeView(onNavigateToMainTab: {
        selectedTab = $0
      })
    case .sessions:
      NavigationView {
        GalaxySSIConversationHubView(
          showsBackButton: false,
          initialContactId: pendingContactId,
          onInitialContactHandled: { pendingContactId = "" }
        )
      }
      .navigationViewStyle(.stack)
    case .discover:
      DiscoverView(
        showsBackButton: false,
        onBackToSettings: {
          selectedTab = .settings
        }
      )
    case .settings:
      SettingsView(
        showsBackButton: false,
        onBackToAgent: {
          selectedTab = .agent
        }
      )
    }
  }

  private func consumePendingContact() {
    let contactId = UserDefaults.standard.string(forKey: "galaxyssi.pending_open_contact") ?? ""
    routeToContact(contactId)
  }

  private func routeToContact(_ contactId: String) {
    guard !contactId.isEmpty else { return }
    UserDefaults.standard.removeObject(forKey: "galaxyssi.pending_open_contact")
    pendingContactId = contactId
    selectedTab = .sessions
  }
}

enum GalaxySSIMainTab: String, CaseIterable, Identifiable {
  case voice
  case agent
  case sessions
  case discover
  case settings

  var id: String { rawValue }
}
