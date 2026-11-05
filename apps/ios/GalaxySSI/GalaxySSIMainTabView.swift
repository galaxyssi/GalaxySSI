import Combine
import SwiftUI

struct GalaxySSIMainTabView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @SceneStorage("galaxyssi.agent.activeConversationID") private var sceneConversationID = ""
  @State private var selectedTab: GalaxySSIMainTab
  @State private var pendingContactId = ""

  init(initialTab: GalaxySSIMainTab = .agent) {
    _selectedTab = State(initialValue: initialTab)
  }

  var body: some View {
    selectedContent
      .safeAreaInset(edge: .bottom, spacing: 0) {
        GalaxySSICompletedReplyReturnBar(visibleConversationId: selectedTab == .agent ? store.activeAgentConversationId : nil) {
          if store.switchAgentSession($0) {
            sceneConversationID = store.activeAgentConversationId
            selectedTab = .agent
          }
        }
      }
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
      NavigationView {
        GalaxySSIControlCenterView(onBackToAgent: {
          selectedTab = .agent
        })
      }
      .navigationViewStyle(.stack)
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

private struct GalaxySSICompletedReplyReturnBar: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var selection: AgentCompletedReplyPlaybackSelection?
  var visibleConversationId: String?
  var open: (String) -> Void

  var body: some View {
    Group {
      if let selection, visibleConversationId != selection.conversationID {
        HStack {
          Button { open(selection.conversationID) } label: {
            Label(GalaxySSILocalization.string("galaxyssi.agent.reply_speech.return",
              fallback: "Return to reply", language: language), systemImage: "waveform")
              .frame(minHeight: 44)
          }
          Spacer()
          Button { AgentCompletedReplyPlayback.shared.stop() } label: {
            Image(systemName: "stop.fill").frame(width: 44, height: 44)
          }
          .accessibilityLabel(Text(GalaxySSILocalization.string("galaxyssi.common.stop",
            fallback: "Stop", language: language)))
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .background(Color.galaxySSIBarBackground)
      }
    }
    .onReceive(AgentCompletedReplyPlayback.shared.$selection.removeDuplicates()) { selection = $0 }
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
