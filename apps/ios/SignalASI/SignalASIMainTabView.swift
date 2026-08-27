import SwiftUI

struct SignalASIMainTabView: View {
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedTab: SignalASIMainTab = .agent
  @State private var pendingContactId = ""
  @State private var pageReturnTarget: SignalASIMainTab?

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
          pageReturnTarget = nil
          selectedTab = $0
        },
        onBackToSettings: {
          pageReturnTarget = nil
          selectedTab = .settings
        }
      )
    case .agent:
      AgentHomeView(onNavigateToMainTab: {
        pageReturnTarget = nil
        selectedTab = $0
      })
    case .messages:
      ChatListView(
        showsBackButton: false,
        onNavigateToMainTab: {
          pageReturnTarget = nil
          selectedTab = $0
        },
        onBackToMainTab: backToSettingsAction,
        initialContactId: pendingContactId,
        onInitialContactHandled: { pendingContactId = "" }
      )
    case .discover:
      DiscoverView(
        showsBackButton: false,
        onBackToSettings: {
          pageReturnTarget = nil
          selectedTab = .settings
        }
      )
    case .settings:
      SettingsView(
        navigateToMainTab: { tab in
          pageReturnTarget = (tab == .agent || tab == .settings) ? nil : .settings
          selectedTab = tab
        },
        showsBackButton: false,
        onBackToAgent: {
          pageReturnTarget = nil
          selectedTab = .agent
        }
      )
    }
  }

  private func consumePendingContact() {
    let contactId = UserDefaults.standard.string(forKey: "signalasi.pending_open_contact") ?? ""
    routeToContact(contactId)
  }

  private var backToSettingsAction: (() -> Void)? {
    guard pageReturnTarget == .settings else { return nil }
    return {
      pageReturnTarget = nil
      selectedTab = .settings
    }
  }

  private func routeToContact(_ contactId: String) {
    guard !contactId.isEmpty else { return }
    UserDefaults.standard.removeObject(forKey: "signalasi.pending_open_contact")
    pageReturnTarget = nil
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
