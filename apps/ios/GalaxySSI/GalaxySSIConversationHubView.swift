import SwiftUI
import UIKit

private enum GalaxySSIAddContactPresentation: String, Identifiable, Equatable {
  case normal
  case scanner

  var id: String { rawValue }
}

private struct GalaxySSIConversationHubRowPositionPreference: PreferenceKey {
  static var defaultValue: [String: CGFloat] = [:]

  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

private final class GalaxySSIConversationHubScrollViewReference {
  weak var value: UIScrollView?
}

private struct GalaxySSIConversationHubScrollViewResolver: UIViewRepresentable {
  var onResolve: (UIScrollView) -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    resolve(from: view)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    resolve(from: uiView)
  }

  private func resolve(from view: UIView) {
    DispatchQueue.main.async {
      var ancestor = view.superview
      while let current = ancestor {
        if let scrollView = current as? UIScrollView {
          onResolve(scrollView)
          return
        }
        ancestor = current.superview
      }
    }
  }
}

struct GalaxySSIConversationHubPreparedContent {
  var conversations: GalaxySSIConversationHubSections
  var archivedCount: Int
  var contacts: [GalaxySSIContact]
}

struct GalaxySSIConversationHubView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var selectedTab: GalaxySSIConversationHubTab
  @State private var searchText = ""
  @State private var searchExpanded = false
  @FocusState private var searchFocused: Bool
  @State private var showingArchived = false
  @State private var addContactPresentation: GalaxySSIAddContactPresentation?
  @State private var cloudModelOnboardingPresented = false
  @State private var hubRefreshToken = UUID()
  @State private var pendingFriendRequestsPresented = false
  @State private var smartDeviceOnboardingPresented = false
  @State private var groupsPresented = false
  @State private var openedContactId = ""
  private let showsBackButton: Bool
  private let onBackToSettings: (() -> Void)?
  private let initialContactId: String
  private let onInitialContactHandled: (() -> Void)?
  @State private var editingSession: AgentConversation?
  @State private var deletingSession: AgentConversation?
  @State private var mergingSession: AgentConversation?
  @State private var multiDeleteMode = false
  @State private var selectedSessionIDs: Set<String> = []
  @State private var bulkDeletePresented = false
  @State private var sessionNotice = ""
  @State private var navigationContentGate = GalaxySSINavigationContentGate()
  @State private var sessionEditDraft: AgentSessionEditDraft?
  @State private var contextPolicySession: AgentConversation?
  @State private var detailsSession: AgentConversation?
  @State private var hubContentLoading = true
  @State private var preparedHubContent = GalaxySSIConversationHubPreparedContent(
    conversations: GalaxySSIConversationHubSections(pinned: [], recent: []),
    archivedCount: 0,
    contacts: []
  )
  @State private var loadedAgentConversations: [AgentConversation] = []
  @State private var conversationPageCursor: AgentConversationPageCursor?
  @State private var conversationPageHasMore = false
  @State private var conversationPageLoading = false
  @SceneStorage("galaxyssi.conversation_hub.scroll_anchor") private var savedScrollAnchorId = ""
  @SceneStorage("galaxyssi.conversation_hub.scroll_anchor_offset") private var savedScrollAnchorOffset = 0.0
  @SceneStorage("galaxyssi.conversation_hub.scroll_anchor_archived") private var savedScrollAnchorArchived = false
  @State private var restoredScrollAnchor = false
  @State private var restoringScrollAnchor = false
  @State private var scrollViewReference = GalaxySSIConversationHubScrollViewReference()

  init(
    initialTab: GalaxySSIConversationHubTab = .conversations,
    showsBackButton: Bool = true,
    onBackToSettings: (() -> Void)? = nil,
    initialContactId: String = "",
    onInitialContactHandled: (() -> Void)? = nil
  ) {
    _selectedTab = State(initialValue: initialTab)
    self.showsBackButton = showsBackButton
    self.onBackToSettings = onBackToSettings
    self.initialContactId = initialContactId
    self.onInitialContactHandled = onInitialContactHandled
  }
  @State private var pendingContactDeletion: GalaxySSIContact?
  @State private var pendingChatDeletion: GalaxySSIContact?

  var body: some View {
    VStack(spacing: 0) {
      NavigationLink(
        destination: GalaxySSIContactMessagingDestination(contactId: openedContactId),
        isActive: Binding(
          get: { !openedContactId.isEmpty },
          set: { active in
            if !active { openedContactId = "" }
          }
        )
      ) {
        EmptyView()
      }
      .frame(width: 0, height: 0)
      .hidden()

      GalaxySSITopBar(
        title: t("galaxyssi.agent_sessions.title", "Sessions"),
        leading: {
          if showsBackButton {
            Button(action: handleHubBack) {
              Image(systemName: "chevron.left")
                .font(.system(size: 19.8, weight: .semibold))
                .foregroundColor(.galaxySSITextPrimary)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("galaxyssi.common.back", "Back")))
          } else if onBackToSettings != nil {
            Button(action: handleHubBack) {
              Image(systemName: "chevron.left")
                .font(.system(size: 19.8, weight: .semibold))
                .foregroundColor(.galaxySSITextPrimary)
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("galaxyssi.common.back", "Back")))
          } else {
            Color.clear
          }
        },
        trailing: {
          HStack(spacing: 0) {
            hubHeaderButton(
              systemImage: searchExpanded ? "xmark" : "magnifyingglass",
              accessibilityLabel: searchPlaceholder,
              action: toggleSearch
            )
            hubHeaderButton(
              systemImage: "person.2",
              accessibilityLabel: t("galaxyssi.conversation_hub.tab_contacts", "Contacts")
            ) {
              closeSearch()
              showingArchived = false
              selectedTab = .contacts
            }
            hubHeaderButton(
              systemImage: "square.and.pencil",
              accessibilityLabel: t("galaxyssi.agent_session.new", "New session")
            ) {
              _ = store.createAgentSession(title: t("galaxyssi.agent_session.new", "New session"))
              dismiss()
            }
          }
        }
      )

      if searchExpanded {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.galaxySSITextSecondary)
            .frame(width: 20, height: 20)
          TextField(searchPlaceholder, text: $searchText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.search)
            .focused($searchFocused)
        }
        .font(.system(size: 14))
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 40)
        .background(Color.galaxySSIButtonSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if !sessionNotice.isEmpty {
        Text(sessionNotice)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.bottom, 4)
      }

      ScrollViewReader { proxy in
        ScrollView {
          hubContent
            .padding(.horizontal, selectedTab == .conversations ? 0 : 12)
            .padding(.bottom, 18)
        }
        .coordinateSpace(name: "galaxyssi-conversation-hub-scroll")
        .background(
          GalaxySSIConversationHubScrollViewResolver { scrollView in
            scrollViewReference.value = scrollView
          }
        )
        .onPreferenceChange(GalaxySSIConversationHubRowPositionPreference.self) { positions in
          guard selectedTab == .conversations,
                !hubContentLoading,
                !restoringScrollAnchor,
                let anchor = GalaxySSIConversationHubScrollPolicy.anchorId(positions: positions) else {
            return
          }
          savedScrollAnchorId = anchor
          savedScrollAnchorOffset = Double(positions[anchor] ?? 0)
          savedScrollAnchorArchived = showingArchived
        }
        .onChange(of: hubContentLoading) { loading in
          guard !loading else {
            restoredScrollAnchor = false
            return
          }
          restoreConversationScroll(with: proxy)
        }
        .onAppear {
          restoreConversationScroll(with: proxy)
        }
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(item: $addContactPresentation) { presentation in
      // Carry the route in the sheet item so SwiftUI cannot capture a stale
      // Boolean while the Hub presents the Add flow.
      AddContactView(
        autoOpenScanner: presentation == .scanner,
        onAgentAdded: { _ in
          refreshAfterContactImport()
          addContactPresentation = nil
          selectedTab = .contacts
        },
        onImportCompleted: {
          // Keep the Add flow visible so a scanned friend request or pairing
          // can be reviewed and approved before the user leaves this route.
          refreshAfterContactImport()
        },
        onCloudModelAdded: { _ in
          refreshAfterContactImport()
          addContactPresentation = nil
          selectedTab = .contacts
        }
      )
    }
    .sheet(isPresented: $cloudModelOnboardingPresented) {
      NavigationView {
        CloudModelProviderSelectionView { _ in
          refreshAfterContactImport()
          selectedTab = .contacts
          cloudModelOnboardingPresented = false
        }
      }
      .navigationViewStyle(.stack)
    }
    .sheet(isPresented: $pendingFriendRequestsPresented) {
      if store.visibleFriendRequests.count == 1,
         let request = store.visibleFriendRequests.first {
        FriendRequestDetailView(
          requestId: request.id,
          onContactAccepted: finishFriendAcceptance
        )
      } else {
        GalaxySSINewFriendsView(onContactAccepted: finishFriendAcceptance)
      }
    }
    .sheet(isPresented: $smartDeviceOnboardingPresented) {
      NavigationView {
        GalaxySSISmartSpacesView()
      }
      .navigationViewStyle(.stack)
    }
    .sheet(isPresented: $groupsPresented) {
      VStack(spacing: 0) {
        GalaxySSITopBar(
          title: t("galaxyssi.conversation_hub.tab_groups", "Groups"),
          leading: {
            Button {
              groupsPresented = false
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.galaxySSITextPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("galaxyssi.common.close", "Close")))
          },
          trailing: { Color.clear }
        )
        groupsContent
          .frame(maxHeight: .infinity, alignment: .top)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    }
    .sheet(item: $editingSession) { session in
      GalaxySSIConversationHubRenameSheet(
        title: t("galaxyssi.agent_session.rename", "Rename"),
        initialValue: session.title
      ) { value in
        let changed = store.renameAgentSession(id: session.id, title: value)
        if changed {
          refreshAfterSessionMutation()
        }
        sessionNotice = changed
          ? t("galaxyssi.agent_sessions.updated", "Session updated")
          : t("galaxyssi.agent_sessions.update_failed", "Session was not changed")
      }
    }
    .alert(
      t("galaxyssi.conversation_hub.delete_contact", "Delete contact"),
      isPresented: Binding(
        get: { pendingContactDeletion != nil },
        set: { if !$0 { pendingContactDeletion = nil } }
      )
    ) {
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        pendingContactDeletion = nil
      }
      Button(t("galaxyssi.common.delete", "Delete"), role: .destructive) {
        if let contact = pendingContactDeletion {
          if contact.type == "device", let desktopId = contact.desktopId.nonEmpty {
            Task { @MainActor in
              _ = await coordinator.revokeDesktopPairing(desktopId: desktopId)
              refreshAfterContactRemoval()
              pendingContactDeletion = nil
            }
          } else {
            _ = store.deleteContact(id: contact.id)
            refreshAfterContactRemoval()
            pendingContactDeletion = nil
          }
          return
        }
        pendingContactDeletion = nil
      }
    } message: {
      Text(contactDeletionMessage)
    }
    .alert(
      t("delete_chat_title", "Delete Chat"),
      isPresented: Binding(
        get: { pendingChatDeletion != nil },
        set: { if !$0 { pendingChatDeletion = nil } }
      )
    ) {
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        pendingChatDeletion = nil
      }
      Button(t("galaxyssi.common.delete", "Delete"), role: .destructive) {
        if let contact = pendingChatDeletion {
          store.deleteMessages(for: contact.id)
          refreshAfterChatRemoval()
        }
        pendingChatDeletion = nil
      }
    } message: {
      Text(t("galaxyssi.chat.delete.message", "Only local chat history is deleted. Contacts are not affected."))
    }
    .alert(
      t("galaxyssi.agent_session.delete", "Delete session"),
      isPresented: Binding(
        get: { deletingSession != nil },
        set: { if !$0 { deletingSession = nil } }
      )
    ) {
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        deletingSession = nil
      }
      Button(t("galaxyssi.common.delete", "Delete"), role: .destructive) {
        confirmDeleteSession()
      }
    } message: {
      Text(t("galaxyssi.agent_session.delete_confirm", "Delete this session and all of its messages?"))
    }
    .alert(
      t("galaxyssi.agent_session.merge_into_original", "Merge into original session"),
      isPresented: Binding(
        get: { mergingSession != nil },
        set: { if !$0 { mergingSession = nil } }
      )
    ) {
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        mergingSession = nil
      }
      Button(t("galaxyssi.agent_session.merge_confirm_action", "Merge"), role: .destructive) {
        confirmMergeSession()
      }
    } message: {
      if let session = mergingSession,
         let target = store.agentSession(id: session.parentConversationId) {
        Text(
          String(
            format: t(
              "galaxyssi.agent_session.merge_confirm",
              "Merge %@ into %@? Messages and running task history will continue in the original session."
            ),
            session.title,
            target.title
          )
        )
      }
    }
    .alert(
      t("galaxyssi.agent_sessions.delete_selected", "Delete selected sessions"),
      isPresented: $bulkDeletePresented
    ) {
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {}
      Button(t("galaxyssi.common.delete", "Delete"), role: .destructive) {
        confirmBulkDelete()
      }
    } message: {
      Text(
        String(
          format: t(
            "galaxyssi.agent_sessions.delete_selected_confirm",
            "Delete %d selected sessions and their messages?"
          ),
          selectedSessionIDs.count
        )
      )
    }
    .onChange(of: selectedTab) { _ in
      closeSearch()
      showingArchived = false
      multiDeleteMode = false
      selectedSessionIDs.removeAll()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: .galaxySSIDesktopPairingDidComplete)
    ) { _ in
      refreshAfterDesktopPairing()
    }
    .onDisappear {
      navigationContentGate.invalidate()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
    ) { _ in
      refreshAfterAppActivation()
    }
    .onChange(of: coordinator.pairingRevocationRevision) { _ in
      refreshAfterRemotePairingRevocation()
      if coordinator.lastRevokedContactIds.contains(openedContactId) {
        openedContactId = ""
      }
    }
    .onAppear {
      openInitialContactIfNeeded()
    }
    .onChange(of: initialContactId) { _ in
      openInitialContactIfNeeded()
    }
    .task(id: hubContentTaskID) {
      await prepareHubContent()
    }
  }

  private func openInitialContactIfNeeded() {
    guard openedContactId.isEmpty,
          !initialContactId.isBlank,
          store.contact(id: initialContactId) != nil else {
      return
    }
    openedContactId = initialContactId
    onInitialContactHandled?()
  }

  @ViewBuilder
  private var hubContent: some View {
    if hubContentLoading {
      hubLoadingContent
    } else {
      switch selectedTab {
      case .conversations:
        conversationContent
      case .contacts:
        contactsContent
      }
    }
  }

  private var conversationContent: some View {
    let visible = preparedHubContent.conversations

    return LazyVStack(alignment: .leading, spacing: 8) {
      if showingArchived {
        hubActionRow(
          title: t("galaxyssi.conversation_hub.back_to_conversations", "Back to conversations"),
          subtitle: t("galaxyssi.conversation_hub.archived_subtitle", "Return to active Agent conversations"),
          systemImage: "clock.arrow.circlepath",
          tint: .blue
        ) {
          showingArchived = false
        }
      }

      if multiDeleteMode {
        bulkDeleteToolbar(
          visible: (visible.pinned + visible.recent)
            .compactMap { store.agentSession(id: $0.id) }
        )
      }

      ForEach(visible.pinned) { item in
        unifiedConversationRow(item)
      }
      if visible.pinned.isEmpty && visible.recent.isEmpty {
        hubEmptyRow(t("galaxyssi.agent_session.no_results", "No matching sessions"))
      } else {
        ForEach(visible.recent) { item in
          unifiedConversationRow(item)
        }
      }

      if !showingArchived {
        hubActionRow(
          title: t("galaxyssi.agent_session.archived", "Archived sessions"),
          subtitle: String(format: t("galaxyssi.conversation_hub.archived_count", "%d archived"), preparedHubContent.archivedCount),
          systemImage: "clock.arrow.circlepath",
          tint: .blue,
          badge: preparedHubContent.archivedCount > 0 ? "\(preparedHubContent.archivedCount)" : ""
        ) {
          showingArchived = true
        }
      }

      if conversationPageHasMore {
        ProgressView()
          .tint(.galaxySSIAccent)
          .frame(maxWidth: .infinity, minHeight: 44)
          .onAppear {
            Task { await loadNextConversationPage() }
          }
      }
    }
    .sheet(item: $sessionEditDraft) { draft in
      AgentSessionTextEditSheet(
        title: draft.sheetTitle,
        initialText: draft.text,
        multiline: draft.mode == .summary
      ) { value in
        saveSessionDraft(draft, value: value)
      }
      .environment(\.galaxySSIInterfaceLanguage, interfaceLanguage)
    }
    .sheet(item: $contextPolicySession) { session in
      AgentSessionContextPolicySheet(
        session: session,
        selectedPolicy: session.contextPolicy,
        onSelect: { policy in
          if store.setAgentSessionContextPolicy(id: session.id, policy: policy) {
            sessionNotice = t("galaxyssi.agent_sessions.context_updated", "Context policy updated")
            refreshAfterSessionMutation()
          }
          contextPolicySession = nil
        }
      )
      .environment(\.galaxySSIInterfaceLanguage, interfaceLanguage)
    }
    .sheet(item: $detailsSession) { session in
      AgentSessionDetailsSheet(
        session: store.agentSession(id: session.id) ?? session,
        metrics: store.agentSessionMetrics(session.id),
        messages: Array(store.agentSessionMessages(session.id).suffix(8))
      )
      .environment(\.galaxySSIInterfaceLanguage, interfaceLanguage)
    }
  }

  private var contactsContent: some View {
    let contacts = preparedHubContent.contacts
    let sections = Dictionary(grouping: contacts) { contactSection($0.displayName) }
      .keys
      .sorted(by: contactSectionSort)

    return VStack(alignment: .leading, spacing: 8) {
      hubActionRow(
        title: t("galaxyssi.new_friends", "New Friends"),
        subtitle: t("galaxyssi.conversation_hub.new_friends_subtitle", "Review pending contact requests"),
        systemImage: "person.badge.plus",
        tint: .galaxySSIAccent,
        unreadCount: store.unreadFriendRequestCount
      ) {
        _ = store.markIncomingFriendRequestsRead()
        pendingFriendRequestsPresented = true
      }
      hubActionRow(
        title: t("galaxyssi.conversation_hub.tab_groups", "Groups"),
        subtitle: t(
          "galaxyssi.conversation_hub.groups_subtitle",
          "View and manage secure group conversations"
        ),
        systemImage: "person.3.fill",
        tint: .purple
      ) {
        groupsPresented = true
      }
      hubActionRow(
        title: t("galaxyssi.conversation_hub.add_cloud_model", "Add Cloud Model"),
        subtitle: t(
          "galaxyssi.conversation_hub.add_cloud_model_subtitle",
          "Configure a provider, model, and API key on this phone"
        ),
        systemImage: "icloud.and.arrow.up.fill",
        tint: .indigo
      ) {
        cloudModelOnboardingPresented = true
      }
      hubActionRow(
        title: t("galaxyssi.conversation_hub.add_smart_device", "Add Smart Device"),
        subtitle: t(
          "galaxyssi.conversation_hub.add_smart_device_subtitle",
          "Connect Home Assistant or a custom device endpoint"
        ),
        systemImage: "sensor.tag.radiowaves.forward",
        tint: .orange
      ) {
        smartDeviceOnboardingPresented = true
      }
      hubActionRow(
        title: t("galaxyssi.conversation_hub.scan_add", "Scan to add"),
        subtitle: t("galaxyssi.conversation_hub.scan_add_subtitle", "Add an Agent, trusted contact, or device"),
        systemImage: "qrcode.viewfinder",
        tint: .cyan
      ) {
        addContactPresentation = .scanner
      }

      if sections.isEmpty {
        hubEmptyRow(t("galaxyssi.empty.contacts", "No matching contacts"))
      } else {
        ForEach(sections, id: \.self) { section in
          hubSectionTitle(section)
          ForEach(sectionsContacts(section: section)) { contact in
            contactRow(contact)
          }
        }
      }
    }
  }

  private var hubLoadingContent: some View {
    HStack(spacing: 10) {
      ProgressView()
        .tint(.galaxySSIAccent)
      Text(t("cc_loading", "Loading..."))
        .font(.system(size: 14))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 120)
  }

  private var hubContentTaskID: String {
    let conversationKey = store.agentConversations.map {
      "\($0.id):\($0.updatedAt):\($0.status):\($0.pinned):\($0.mergedIntoConversationId)"
    }.joined(separator: "|")
    let contactKey = store.contacts.map {
      let summary = store.conversationSummary(for: $0.id)
      return "\($0.id):\($0.updatedAt):\($0.deleted):\($0.displayName):\(summary.lastMessage?.createdAt.timeIntervalSince1970 ?? 0):\(summary.unreadCount):\(store.isContactPinned($0.id))"
    }.joined(separator: "|")
    return [
      selectedTab.rawValue,
      searchText,
      showingArchived ? "archived" : "active",
      hubRefreshToken.uuidString,
      conversationKey,
      contactKey,
      "friend-unread:\(store.unreadFriendRequestCount)"
    ].joined(separator: "\u{001F}")
  }

  private func refreshAfterContactImport() {
    _ = coordinator.requestCapabilityManifestRefresh(force: true)
    hubRefreshToken = UUID()
  }

  private func finishFriendAcceptance() {
    pendingFriendRequestsPresented = false
    selectedTab = .contacts
    refreshAfterContactImport()
  }

  private func refreshAfterDesktopPairing() {
    _ = coordinator.requestCapabilityManifestRefresh(force: true)
    navigationContentGate.invalidate()
    hubContentLoading = true
    hubRefreshToken = UUID()
  }

  private func refreshAfterRemotePairingRevocation() {
    _ = coordinator.requestCapabilityManifestRefresh(force: true)
    navigationContentGate.invalidate()
    hubContentLoading = true
    hubRefreshToken = UUID()
  }

  private func refreshAfterContactRemoval() {
    _ = coordinator.requestCapabilityManifestRefresh(force: true)
    hubRefreshToken = UUID()
  }

  private func refreshAfterChatRemoval() {
    navigationContentGate.invalidate()
    hubContentLoading = true
    hubRefreshToken = UUID()
  }

  private func refreshAfterSessionMutation() {
    navigationContentGate.invalidate()
    hubContentLoading = true
    hubRefreshToken = UUID()
  }

  private func refreshAfterAppActivation() {
    _ = coordinator.requestCapabilityManifestRefresh()
    navigationContentGate.invalidate()
    hubContentLoading = true
    hubRefreshToken = UUID()
  }

  private func prepareHubContent() async {
    let generation = navigationContentGate.begin()
    hubContentLoading = true
    conversationPageLoading = true
    let requestedStatus: AgentConversationStatus = showingArchived ? .archived : .active
    var page = store.agentSessionPage(
      status: requestedStatus,
      cursor: nil,
      pageSize: AgentConversationDatabase.defaultPageSize
    )
    var sourceConversations = page.items
    let sourceContacts = store.contactList(matching: "")
    let sourceChatContacts = store.chatContacts(matching: "")
    let query = searchText
    let archived = showingArchived
    let restorationConversationId = savedScrollAnchorArchived == archived
      ? GalaxySSIConversationHubScrollPolicy.agentConversationId(from: savedScrollAnchorId)
      : nil
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let restorationConversationId {
      while page.hasMore && !sourceConversations.contains(where: { $0.id == restorationConversationId }) {
        page = store.agentSessionPage(
          status: requestedStatus,
          cursor: page.nextCursor,
          pageSize: AgentConversationDatabase.maximumPageSize
        )
        sourceConversations += page.items
      }
    }
    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      while page.hasMore && sourceConversations.count < 500 {
        page = store.agentSessionPage(
          status: requestedStatus,
          cursor: page.nextCursor,
          pageSize: AgentConversationDatabase.maximumPageSize
        )
        sourceConversations += page.items
      }
    }
    let agentItems = sourceConversations.map { agentHubItem($0) }
    let archivedCount = store.agentSessionCount(status: .archived)
    let contactSummaries = GalaxySSIConversationHubModels.contactSummaries(
      contacts: sourceChatContacts,
      summary: store.conversationSummary(for:),
      isPinned: store.isContactPinned
    )
    let prepared = await Task.detached(priority: .userInitiated) {
      GalaxySSIConversationHubPreparedContent(
        conversations: GalaxySSIConversationHubModels.unifiedConversations(
          agents: agentItems,
          contacts: contactSummaries,
          query: query,
          archived: archived
        ),
        archivedCount: archivedCount,
        contacts: GalaxySSIConversationHubModels.contacts(sourceContacts, query: query)
      )
    }.value
    guard !Task.isCancelled, navigationContentGate.isCurrent(generation) else { return }
    loadedAgentConversations = sourceConversations
    conversationPageCursor = page.nextCursor
    conversationPageHasMore = page.hasMore
    conversationPageLoading = false
    preparedHubContent = prepared
    hubContentLoading = false
  }

  private func loadNextConversationPage() async {
    guard selectedTab == .conversations,
          conversationPageHasMore,
          !conversationPageLoading else { return }
    conversationPageLoading = true
    let requestedStatus: AgentConversationStatus = showingArchived ? .archived : .active
    let page = store.agentSessionPage(
      status: requestedStatus,
      cursor: conversationPageCursor,
      pageSize: AgentConversationDatabase.defaultPageSize
    )
    guard !Task.isCancelled,
          requestedStatus == (showingArchived ? .archived : .active) else {
      conversationPageLoading = false
      return
    }
    let existingIDs = Set(loadedAgentConversations.map(\.id))
    loadedAgentConversations += page.items.filter { !existingIDs.contains($0.id) }
    conversationPageCursor = page.nextCursor
    conversationPageHasMore = page.hasMore
    let contactSummaries = GalaxySSIConversationHubModels.contactSummaries(
      contacts: store.chatContacts(matching: ""),
      summary: store.conversationSummary(for:),
      isPinned: store.isContactPinned
    )
    preparedHubContent.conversations = GalaxySSIConversationHubModels.unifiedConversations(
      agents: loadedAgentConversations.map { agentHubItem($0) },
      contacts: contactSummaries,
      query: searchText,
      archived: showingArchived
    )
    conversationPageLoading = false
  }

  private func agentHubItem(_ conversation: AgentConversation) -> GalaxySSIConversationHubItem {
    let latest = store.latestAgentSessionMessage(conversation.id)
    let preview = latest.map { ContactConversationSummary(lastMessage: $0, unreadCount: 0).previewText } ?? ""
    return GalaxySSIConversationHubItem(
      id: conversation.id,
      kind: .agent,
      title: GalaxySSIConversationHubModels.agentDisplayTitle(
        conversation,
        language: interfaceLanguage
      ),
      subtitle: preview,
      preview: preview,
      updatedAt: latest?.createdAt ?? Date(timeIntervalSince1970: TimeInterval(conversation.updatedAt) / 1_000),
      pinned: conversation.pinned,
      archived: conversation.status == .archived,
      searchableMetadata: conversation.selectedModelOrAgent
    )
  }

  private var groupsContent: some View {
    VStack(spacing: 8) {
      Image(systemName: "person.3.fill")
        .font(.system(size: 42, weight: .semibold))
        .foregroundColor(.galaxySSIAccent)
        .padding(.top, 54)
      Text(t("galaxyssi.conversation_hub.groups_empty", "No groups yet"))
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
      Text(t("galaxyssi.conversation_hub.groups_empty_subtitle", "Group conversations will appear here when available."))
        .font(.system(size: 13))
        .foregroundColor(.galaxySSITextSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func unifiedConversationRow(_ item: GalaxySSIConversationHubItem) -> some View {
    if item.kind == .agent, let session = store.agentSession(id: item.id) {
      conversationRow(session, preview: item.preview, updatedAt: item.updatedAt)
        .id(scrollRowId(item))
        .background { scrollRowPosition(item) }
    } else if let contact = store.contact(id: item.id) {
      NavigationLink(destination: GalaxySSIContactMessagingDestination(contactId: contact.id)) {
        hubRowContent(
          title: item.title,
          subtitle: item.preview.ifBlank(t("chat_no_messages", "No messages yet")),
          systemImage: contact.type == "device" ? "iphone" : "person.crop.circle",
          tint: contact.type == "device" ? .blue : .galaxySSITextSecondary,
          trailing: "",
          updatedAt: item.updatedAt,
          leadingView: AnyView(AvatarView(contact: contact, size: 34)),
          unreadCount: item.unreadCount
        )
      }
      .buttonStyle(.plain)
      .contextMenu {
        if contact.id != "system" {
          Button(store.isContactPinned(contact.id)
            ? t("galaxyssi.agent_session.unpin", "Unpin")
            : t("galaxyssi.agent_session.pin", "Pin")) {
            if store.setContactPinned(contact.id, pinned: !store.isContactPinned(contact.id)) {
              refreshAfterSessionMutation()
            }
          }
          Button(t("delete_chat_title", "Delete Chat"), role: .destructive) {
            pendingChatDeletion = contact
          }
        }
      }
      .id(scrollRowId(item))
      .background { scrollRowPosition(item) }
    }
  }

  private func scrollRowId(_ item: GalaxySSIConversationHubItem) -> String {
    "conversation:\(item.kind.rawValue):\(item.id)"
  }

  private func scrollRowPosition(_ item: GalaxySSIConversationHubItem) -> some View {
    GeometryReader { geometry in
      Color.clear.preference(
        key: GalaxySSIConversationHubRowPositionPreference.self,
        value: [
          scrollRowId(item): geometry.frame(
            in: .named("galaxyssi-conversation-hub-scroll")
          ).minY
        ]
      )
    }
  }

  private func restoreConversationScroll(with proxy: ScrollViewProxy) {
    guard selectedTab == .conversations,
          !hubContentLoading,
          !restoredScrollAnchor,
          !savedScrollAnchorId.isEmpty,
          savedScrollAnchorArchived == showingArchived else { return }
    restoredScrollAnchor = true
    restoringScrollAnchor = true
    DispatchQueue.main.async {
      proxy.scrollTo(savedScrollAnchorId, anchor: .top)
      DispatchQueue.main.async {
        guard let scrollView = scrollViewReference.value else {
          restoringScrollAnchor = false
          return
        }
        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
          minimumY,
          scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        )
        let targetY = GalaxySSIConversationHubScrollPolicy.restoredContentOffsetY(
          alignedContentOffsetY: scrollView.contentOffset.y,
          savedRowOffset: CGFloat(savedScrollAnchorOffset),
          minimumContentOffsetY: minimumY,
          maximumContentOffsetY: maximumY
        )
        scrollView.setContentOffset(
          CGPoint(x: scrollView.contentOffset.x, y: targetY),
          animated: false
        )
        DispatchQueue.main.async {
          restoringScrollAnchor = false
        }
      }
    }
  }

  private func conversationRow(
    _ session: AgentConversation,
    preview: String = "",
    updatedAt: Date
  ) -> some View {
    Button {
      if multiDeleteMode {
        toggleSelectedSession(session.id)
      } else {
        openConversation(session)
      }
    } label: {
      hubRowContent(
        title: GalaxySSIConversationHubModels.agentDisplayTitle(
          session,
          language: interfaceLanguage
        ),
        subtitle: preview,
        systemImage: "clock.arrow.circlepath",
        tint: .galaxySSIAccent,
        trailing: multiDeleteMode
          ? (selectedSessionIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
          : "",
        updatedAt: updatedAt
      )
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(session.pinned
        ? t("galaxyssi.agent_session.unpin", "Unpin")
        : t("galaxyssi.agent_session.pin", "Pin")) {
        if store.setAgentSessionPinned(id: session.id, pinned: !session.pinned) {
          refreshAfterSessionMutation()
        }
      }
      Button(t("galaxyssi.agent_session.delete", "Delete session"), role: .destructive) {
        deletingSession = session
      }
      Divider()
      Button(t("galaxyssi.agent_sessions.select", "Select session")) {
        openConversation(session)
      }
      Button(t("galaxyssi.agent_session.rename", "Rename")) {
        editingSession = session
      }
      if canMerge(session) {
        Button(t("galaxyssi.agent_session.merge_into_original", "Merge into original session")) {
          mergingSession = session
        }
      }
      if session.mergedIntoConversationId.isBlank {
        Button(session.privateMode
          ? t("galaxyssi.agent_session.standard", "Standard session")
          : t("galaxyssi.agent_session.private", "Private session")) {
          if store.setAgentSessionPrivateMode(id: session.id, privateMode: !session.privateMode) {
            refreshAfterSessionMutation()
          }
        }
        Button(session.trackingPaused
          ? t("galaxyssi.agent_session.resume_tracking", "Resume global tracking")
          : t("galaxyssi.agent_session.pause_tracking", "Pause global tracking")) {
          if store.setAgentSessionTrackingPaused(id: session.id, paused: !session.trackingPaused) {
            refreshAfterSessionMutation()
          }
        }
        Button(session.status == .archived
          ? t("galaxyssi.agent_session.restore", "Restore session")
          : t("galaxyssi.agent_session.archive", "Archive")) {
          if session.status == .archived {
            if store.restoreAgentSession(id: session.id) {
              showingArchived = false
              refreshAfterSessionMutation()
            }
          } else {
            if store.archiveAgentSession(id: session.id) {
              refreshAfterSessionMutation()
            }
          }
        }
      }
      Button(t("galaxyssi.agent_session.context_policy", "Context policy")) {
        contextPolicySession = session
      }
      Button(t("galaxyssi.agent_session.summary", "View or edit summary")) {
        sessionEditDraft = AgentSessionEditDraft(
          id: session.id,
          mode: .summary,
          sheetTitle: t("galaxyssi.agent_session.summary", "View or edit summary"),
          text: session.summary
        )
      }
      Button(t("galaxyssi.agent_session.details", "Session details")) {
        detailsSession = session
      }
      Button(t("galaxyssi.agent_session.delete_more", "Delete more")) {
        multiDeleteMode = true
        selectedSessionIDs.removeAll()
      }
    }
  }

  private func bulkDeleteToolbar(visible sessions: [AgentConversation]) -> some View {
    HStack(spacing: 8) {
      Text(
        String(
          format: t("galaxyssi.agent_sessions.selected_count", "%d selected"),
          selectedSessionIDs.count
        )
      )
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      Spacer(minLength: 0)
      Button {
        let visibleIDs = Set(sessions.map(\.id))
        selectedSessionIDs = selectedSessionIDs == visibleIDs ? [] : visibleIDs
      } label: {
        Image(systemName: selectedSessionIDs == Set(sessions.map(\.id)) ? "checkmark.circle" : "checklist")
          .font(.system(size: 15, weight: .semibold))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(
        selectedSessionIDs == Set(sessions.map(\.id))
          ? t("galaxyssi.agent_sessions.clear_selection", "Clear")
          : t("galaxyssi.agent_sessions.select_all", "Select all")
      ))
      Button {
        bulkDeletePresented = true
      } label: {
        Image(systemName: "trash")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.red)
      }
      .buttonStyle(.plain)
      .disabled(selectedSessionIDs.isEmpty)
      .accessibilityLabel(Text(t("galaxyssi.common.delete", "Delete")))
      Button {
        multiDeleteMode = false
        selectedSessionIDs.removeAll()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("galaxyssi.common.cancel", "Cancel")))
    }
    .padding(.horizontal, 4)
  }

  private func openConversation(_ session: AgentConversation) {
    let destination = store.agentSessionDestination(id: session.id) ?? session.id
    if destination == session.id && session.status == .archived {
      _ = store.restoreAgentSession(id: session.id)
    }
    _ = store.switchAgentSession(destination)
    dismiss()
  }

  private func toggleSelectedSession(_ sessionId: String) {
    if selectedSessionIDs.contains(sessionId) {
      selectedSessionIDs.remove(sessionId)
    } else {
      selectedSessionIDs.insert(sessionId)
    }
  }

  private func canMerge(_ session: AgentConversation) -> Bool {
    guard session.createdByAgent,
          !session.parentConversationId.isBlank,
          session.mergedIntoConversationId.isBlank,
          let parent = store.agentSession(id: session.parentConversationId) else {
      return false
    }
    return parent.privateMode == session.privateMode
  }

  private func confirmMergeSession() {
    guard let session = mergingSession else { return }
    let result = store.mergeAgentSessionIntoParent(id: session.id)
    mergingSession = nil
    guard result.merged else {
      sessionNotice = mergeFailureMessage(result.failure)
      return
    }
    let targetTitle = result.targetConversation?.title.ifBlank(
      t("galaxyssi.agent_session.new", "New session")
    ) ?? t("galaxyssi.agent_session.new", "New session")
    sessionNotice = String(
      format: t("galaxyssi.agent_sessions.merge_success", "Merged %d messages into %@"),
      result.copiedEntryCount,
      targetTitle
    )
    showingArchived = false
    refreshAfterSessionMutation()
  }

  private func mergeFailureMessage(_ failure: AgentConversationMergeFailure) -> String {
    switch failure {
    case .sourceNotFound:
      return t("galaxyssi.agent_session.merge_source_missing", "The Agent-created session no longer exists")
    case .targetNotFound:
      return t("galaxyssi.agent_session.merge_target_missing", "The original session no longer exists")
    case .notAgentCreated:
      return t("galaxyssi.agent_session.merge_unavailable", "Only Agent-created sessions can be merged")
    case .alreadyMerged:
      return t("galaxyssi.agent_session.merge_already_done", "This session has already been merged")
    case .sameConversation, .privacyMismatch, .none:
      return t("galaxyssi.agent_session.merge_unavailable", "This session cannot be merged")
    }
  }

  private func confirmDeleteSession() {
    guard let session = deletingSession else { return }
    let shouldNotifyRemote = session.mergedIntoConversationId.isBlank
    let taskIds = shouldNotifyRemote
      ? store.agentTasks(forSession: session.id, limit: 256).map(\.taskId)
      : []
    let deleted = store.deleteAgentSession(id: session.id)
    deletingSession = nil
    guard deleted, shouldNotifyRemote else {
      sessionNotice = deleted
        ? t("galaxyssi.agent_sessions.deleted", "Session deleted")
        : t("galaxyssi.agent_sessions.delete_failed", "Session was not deleted")
      if deleted {
        refreshAfterSessionMutation()
      }
      return
    }
    refreshAfterSessionMutation()
    sessionNotice = t(
      "galaxyssi.agent_sessions.deleted_remote_pending",
      "Session deleted; cleaning up the paired Desktop..."
    )
    Task { @MainActor in
      let sent = await coordinator.publishRemoteAgentConversationDelete(
        conversationId: session.id,
        taskIds: taskIds
      )
      sessionNotice = sent
        ? t("galaxyssi.agent_sessions.deleted_remote_sent", "Remote cleanup request sent")
        : t("galaxyssi.agent_sessions.deleted_remote_failed", "Session deleted; remote cleanup could not be sent")
    }
  }

  private func confirmBulkDelete() {
    let sessions = store.agentSessions(includeArchived: true).filter {
      selectedSessionIDs.contains($0.id)
    }
    guard !sessions.isEmpty else { return }
    let cleanupRequests = sessions
      .filter { $0.mergedIntoConversationId.isBlank }
      .map { session in
        (
          conversationId: session.id,
          taskIds: store.agentTasks(forSession: session.id, limit: 256).map(\.taskId)
        )
      }
    let deletedCount = sessions.reduce(into: 0) { count, session in
      if store.deleteAgentSession(id: session.id) { count += 1 }
    }
    multiDeleteMode = false
    selectedSessionIDs.removeAll()
    bulkDeletePresented = false
    guard deletedCount > 0 else {
      sessionNotice = t("galaxyssi.agent_sessions.delete_failed", "Session was not deleted")
      return
    }
    refreshAfterSessionMutation()
    sessionNotice = String(
      format: t(
        "galaxyssi.agent_sessions.deleted_selected_pending",
        "%d sessions deleted; cleaning up the paired Desktop..."
      ),
      deletedCount
    )
    guard !cleanupRequests.isEmpty else {
      sessionNotice = String(
        format: t("galaxyssi.agent_sessions.deleted_selected", "%d sessions deleted"),
        deletedCount
      )
      return
    }
    Task { @MainActor in
      var failed = 0
      for request in cleanupRequests {
        if !(await coordinator.publishRemoteAgentConversationDelete(
          conversationId: request.conversationId,
          taskIds: request.taskIds
        )) {
          failed += 1
        }
      }
      sessionNotice = failed == 0
        ? t("galaxyssi.agent_sessions.deleted_selected_sent", "Selected sessions deleted and remote cleanup sent")
        : t("galaxyssi.agent_sessions.deleted_selected_failed", "Sessions deleted; some remote cleanup requests failed")
    }
  }

  private func saveSessionDraft(_ draft: AgentSessionEditDraft, value: String) {
    let changed: Bool
    switch draft.mode {
    case .rename:
      changed = store.renameAgentSession(id: draft.id, title: value)
    case .summary:
      changed = store.updateAgentSessionSummary(id: draft.id, summary: value)
    }
    if changed {
      refreshAfterSessionMutation()
    }
    sessionNotice = changed
      ? t("galaxyssi.agent_sessions.updated", "Session updated")
      : t("galaxyssi.agent_sessions.update_failed", "Session was not changed")
  }

  private func contactRow(_ contact: GalaxySSIContact) -> some View {
    let kindPresentation = GalaxySSIContactKindPresentation.forContact(contact, t: t)
    return NavigationLink(destination: ContactDetailView(contactId: contact.id)) {
      hubRowContent(
        title: contact.displayName,
        subtitle: "",
        systemImage: contact.type == "device"
          ? "iphone"
          : (contact.type == "agent" ? "cpu" : "person.fill"),
        tint: contact.type == "device"
          ? .blue
          : (contact.type == "agent" ? .galaxySSIAccent : .galaxySSITextSecondary),
        trailing: "",
        leadingView: AnyView(AvatarView(contact: contact, size: 34)),
        titleAccessory: kindPresentation.map {
          AnyView(GalaxySSIContactKindBadge(presentation: $0))
        }
      )
    }
    .buttonStyle(.plain)
    .onLongPressGesture {
      if contact.id != "system" {
        pendingContactDeletion = contact
      }
    }
    .accessibilityAction(named: Text(t("galaxyssi.conversation_hub.delete_contact", "Delete contact"))) {
      if contact.id != "system" {
        pendingContactDeletion = contact
      }
    }
  }

  private var contactDeletionMessage: String {
    let detail = t(
      "delete_contact_subtitle",
      "Add and verify this contact again before communicating. Local chat history is kept."
    )
    guard let contact = pendingContactDeletion else { return detail }
    return "\(contact.displayName)\n\n\(detail)"
  }

  private func hubActionRow(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String = "",
    unreadCount: Int = 0,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      hubRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        trailing: badge,
        unreadCount: unreadCount
      )
    }
    .buttonStyle(.plain)
  }

  private func hubRowContent(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    trailing: String,
    updatedAt: Date? = nil,
    leadingView: AnyView? = nil,
    titleAccessory: AnyView? = nil,
    unreadCount: Int = 0,
    showsDisclosure: Bool = true
  ) -> some View {
    HStack(spacing: 10) {
      if let leadingView {
        leadingView
          .overlay(
            Circle()
              .stroke(Color.galaxySSISeparator, lineWidth: 0.5)
          )
      } else {
        Image(systemName: systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(tint)
          .frame(width: 34, height: 34)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          if let titleAccessory {
            titleAccessory
          }
        }
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if let updatedAt, updatedAt.timeIntervalSince1970 > 0 {
        Text(
          GalaxySSIChatListTimeFormatter.string(
            for: updatedAt,
            language: interfaceLanguage
          )
        )
        .font(.system(size: 11.5, weight: .regular))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(1)
      }
      if unreadCount > 0 {
        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
          .foregroundColor(.white)
          .padding(.horizontal, 6)
          .frame(minWidth: 22, minHeight: 20)
          .background(Capsule().fill(Color.galaxySSIUnreadRed))
      } else if trailing == "chevron.right" {
        Image(systemName: trailing)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      } else if trailing == "pin.fill" || trailing == "checkmark.circle.fill" || trailing == "circle" {
        Image(systemName: trailing)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      } else if !trailing.isEmpty {
        Text(trailing)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(width: 20, height: 36)
          .accessibilityHidden(true)
      }
    }
    .padding(.leading, 10)
    .padding(.trailing, 14)
    .padding(.vertical, 8)
    .frame(minHeight: subtitle.isEmpty ? 56 : 64)
    .background(Color.galaxySSISurface)
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSISeparator, lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func hubSectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 8)
  }

  private func hubEmptyRow(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 14))
      .foregroundColor(.galaxySSITextSecondary)
      .frame(maxWidth: .infinity, minHeight: 72)
  }

  private var searchPlaceholder: String {
    t(
      "galaxyssi.conversation_hub.search_hint",
      "Search chats, contacts, or groups"
    )
  }

  private func hubHeaderButton(
    systemImage: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
        .frame(width: 36, height: 36)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(accessibilityLabel))
  }

  private func handleHubBack() {
    switch GalaxySSIConversationHubBackPolicy.action(
      searchExpanded: searchExpanded,
      tab: selectedTab,
      archived: showingArchived
    ) {
    case .closeSearch:
      closeSearch()
    case .showConversations:
      closeSearch()
      showingArchived = false
      selectedTab = .conversations
    case .dismiss:
      if let onBackToSettings {
        onBackToSettings()
      } else {
        dismiss()
      }
    }
  }

  private func toggleSearch() {
    if searchExpanded {
      closeSearch()
      return
    }
    withAnimation(.easeInOut(duration: 0.16)) {
      searchExpanded = true
    }
    DispatchQueue.main.async {
      searchFocused = true
    }
  }

  private func closeSearch() {
    if searchExpanded {
      withAnimation(.easeInOut(duration: 0.16)) {
        searchExpanded = false
      }
    }
    searchFocused = false
    searchText = ""
  }

  private func sectionsContacts(section: String) -> [GalaxySSIContact] {
    GalaxySSIConversationHubModels.contacts(
      store.contactList(matching: ""),
      query: searchText
    ).filter { contactSection($0.displayName) == section }
  }

  private func contactSection(_ name: String) -> String {
    GalaxySSIConversationHubModels.contactSection(name)
  }

  private func contactSectionSort(_ left: String, _ right: String) -> Bool {
    if left == "#" { return false }
    if right == "#" { return true }
    return left < right
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIConversationHubRenameSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var value: String
  let title: String
  let onSave: (String) -> Void

  init(title: String, initialValue: String, onSave: @escaping (String) -> Void) {
    self.title = title
    self.onSave = onSave
    _value = State(initialValue: initialValue)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: title,
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t("galaxyssi.common.cancel", "Cancel")))
        },
        trailing: {
          Button {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            onSave(trimmed)
            dismiss()
          } label: {
            Image(systemName: "checkmark")
              .font(.system(size: 17, weight: .bold))
              .foregroundColor(.galaxySSIAccent)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t("galaxyssi.common.save", "Save")))
          .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      )
      TextField(t("galaxyssi.agent_session.name_placeholder", "Session name"), text: $value)
        .textInputAutocapitalization(.sentences)
        .autocorrectionDisabled(false)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(16)
      Spacer()
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
