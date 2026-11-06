import Combine
import SwiftUI

struct GalaxySSIMainTabView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var selectedTab: GalaxySSIMainTab
  @State private var pendingContactId = ""
  @State private var navigationOwner = UUID()
  @State private var canRouteVoice = false
  @State private var voiceEntry: VoiceAppEntryContext?
  @State private var voiceEntryRevision = UUID()
  @State private var voicePage: VoicePage?

  private enum VoicePage: Identifiable {
    case phone
    case news(articleID: String?)
    var id: String {
      switch self {
      case .phone: return "phone"
      case .news(let id): return "news:" + (id ?? "")
      }
    }
  }

  init(initialTab: GalaxySSIMainTab = .agent) {
    _selectedTab = State(initialValue: initialTab)
  }

  var body: some View {
    selectedContent
      .safeAreaInset(edge: .bottom, spacing: 0) {
        GalaxySSISpokenMediaBar(
          visibleConversationId: selectedTab == .agent ? store.activeAgentConversationId : nil,
          showNews: selectedTab != .discover
        ) {
          if store.switchAgentSession($0) {
            selectedTab = .agent
          }
        }
      }
      .onAppear(perform: consumePendingContact)
      .onAppear {
        canRouteVoice = scenePhase == .active
        coordinator.voiceAppContexts.installNavigation(owner: navigationOwner,
          handle: routeFromVoice, openVoice: openVoiceEntry)
      }
      .onDisappear {
        canRouteVoice = false
        coordinator.voiceAppContexts.removeNavigation(owner: navigationOwner)
      }
      .onChange(of: scenePhase) { canRouteVoice = $0 == .active }
      .onChange(of: selectedTab) { tab in
        if tab != .voice { voiceEntry = nil }
      }
      .sheet(item: $voicePage) { page in
        NavigationView {
          switch page {
          case .phone: GalaxySSIPhoneAssistantView()
          case .news(let id): GalaxySSIPublicNewsView(initialArticleKey: id)
          }
        }
        .navigationViewStyle(.stack)
      }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIOpenContact)) { notification in
        let contactId = ((notification.userInfo?["contactId"] as? String) ?? "")
          .trimmingCharacters(in: .whitespacesAndNewlines)
        routeToContact(contactId)
      }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIOpenPublicNewsDiscussion, object: store)) { notification in
        guard scenePhase == .active, let conversation = notification.userInfo?["conversationId"] as? String,
              conversation == store.activeAgentConversationId else { return }
        voicePage = nil
        selectedTab = .agent
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
          closeVoiceEntry()
        },
        entryContext: voiceEntry
      )
      .id(voiceEntryRevision)
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

  private func openVoiceEntry(_ entry: VoiceAppEntryContext) {
    guard canRouteVoice else { return }
    voicePage = nil
    voiceEntry = entry
    voiceEntryRevision = UUID()
    selectedTab = .voice
  }

  private func closeVoiceEntry() {
    switch voiceEntry?.surface {
    case .contact: routeToContact(voiceEntry?.contactID ?? "")
    case .news:
      selectedTab = .discover
      voicePage = .news(articleID: voiceEntry?.articleID)
    default: selectedTab = .settings
    }
  }

  private func routeFromVoice(_ request: VoiceAppNavigationRequest) -> AgentNativeToolExecutionResult {
    guard canRouteVoice, store.activeAgentConversationId == request.conversationID else {
      return .failure(code: "navigation_unavailable", message: "The original voice window is no longer active.")
    }
    var output: AgentMcpJSONObject = ["destination": .string(request.destination.rawValue), "state": .string("scheduled")]
    switch request.destination {
    case .agent:
      selectedTab = .agent
      output["conversation_id"] = .string(request.conversationID)
    case .contact:
      guard let contact = store.visibleContacts.first(where: { $0.id == request.contactID }), contact.isCommunicable,
            ["person", "device"].contains(contact.type.lowercased()),
            contact.opaquePhoneRoutes != nil || contact.isDesktopDeviceContact else {
        return .failure(code: "contact_unavailable", message: "The exact paired contact is no longer available.")
      }
      routeToContact(contact.id)
      output["contact_id"] = .string(contact.id)
    case .news: voicePage = .news(articleID: nil)
    case .phone: voicePage = .phone
    case .newConversation:
      let session = store.createAgentSession(title: GalaxySSILocalization.string(
        "galaxyssi.agent_session.new", fallback: "New session", language: language))
      guard store.agentConversationDatabase.readDraft(session.id) != nil ||
              store.agentConversationDatabase.read(session.id) != nil else {
        return .failure(code: "conversation_not_saved", message: "The new conversation could not be saved.")
      }
      selectedTab = .agent
      output["conversation_id"] = .string(session.id)
      if !request.message.isBlank {
        let contact = store.contact(id: "hermes") ?? GalaxySSIContact.hermes()
        Task { @MainActor in
          _ = await coordinator.send(request.message, to: contact, requiredAgentConversationID: session.id)
        }
        output["message_status"] = .string("scheduled")
      }
    }
    return .success(output: output)
  }
}

private struct GalaxySSISpokenMediaBar: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject private var newsSpeech = PublicNewsSpeechPlayback.shared
  @State private var selection: AgentCompletedReplyPlaybackSelection?
  var visibleConversationId: String?
  var showNews: Bool
  var open: (String) -> Void

  var body: some View {
    Group {
      if showNews, selection == nil, newsSpeech.controlsVisible, newsSpeech.queue.current != nil {
        GalaxySSIPublicNewsSpeechControls(playback: newsSpeech, showTitle: true)
          .padding(.horizontal, 12)
          .background(Color.galaxySSIBarBackground)
      } else if let selection, visibleConversationId != selection.conversationID {
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
