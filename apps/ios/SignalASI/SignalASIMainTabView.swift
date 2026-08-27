import SwiftUI

struct SignalASIMainTabView: View {
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedTab: SignalASIMainTab = .agent
  @State private var pendingContactId = ""

  var body: some View {
    selectedContent
      .onAppear(perform: consumePendingContact)
      .onReceive(NotificationCenter.default.publisher(for: .signalASIOpenContact)) { notification in
        let contactId = ((notification.userInfo?["contactId"] as? String) ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        routeToContact(contactId)
      }
      .task {
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        _ = await SignalASISettingsSummaryCache.prepare(store: store)
      }
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .voice:
      SignalASIVoiceTabView(
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
    case .messages:
      ChatListView(
        showsBackButton: false,
        onNavigateToMainTab: {
          selectedTab = $0
        },
        onBackToMainTab: nil,
        initialContactId: pendingContactId,
        onInitialContactHandled: { pendingContactId = "" }
      )
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
    let contactId = UserDefaults.standard.string(forKey: "signalasi.pending_open_contact") ?? ""
    routeToContact(contactId)
  }

  private func routeToContact(_ contactId: String) {
    guard !contactId.isEmpty else { return }
    UserDefaults.standard.removeObject(forKey: "signalasi.pending_open_contact")
    pendingContactId = contactId
    selectedTab = .messages
  }
}

enum SignalASIMainTab: String, CaseIterable, Identifiable {
  case voice
  case agent
  case messages
  case discover
  case settings

  var id: String { rawValue }
}
