import SwiftUI
import UIKit

private enum SignalASIAddContactPresentation: String, Identifiable, Equatable {
  case normal
  case scanner

  var id: String { rawValue }
}

struct SignalASIConversationHubPreparedContent {
  var conversations: SignalASIConversationHubSections
  var archivedCount: Int
  var contacts: [SignalASIContact]
}

struct SignalASIConversationHubView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var selectedTab: SignalASIConversationHubTab
  @State private var searchText = ""
  @State private var searchExpanded = false
  @FocusState private var searchFocused: Bool
  @State private var showingArchived = false
  @State private var addContactPresentation: SignalASIAddContactPresentation?
  @State private var cloudModelOnboardingPresented = false
  @State private var hubRefreshToken = UUID()
  @State private var pendingFriendRequestsPresented = false
  @State private var smartDeviceOnboardingPresented = false
  @State private var groupsPresented = false
  private let showsBackButton: Bool
  private let onBackToSettings: (() -> Void)?
  @State private var editingSession: AgentConversation?
  @State private var deletingSession: AgentConversation?
  @State private var mergingSession: AgentConversation?
  @State private var multiDeleteMode = false
  @State private var selectedSessionIDs: Set<String> = []
  @State private var bulkDeletePresented = false
  @State private var sessionNotice = ""
  @State private var navigationContentGate = SignalASINavigationContentGate()
  @State private var sessionEditDraft: AgentSessionEditDraft?
  @State private var contextPolicySession: AgentConversation?
  @State private var detailsSession: AgentConversation?
  @State private var hubContentLoading = true
  @State private var preparedHubContent = SignalASIConversationHubPreparedContent(
    conversations: SignalASIConversationHubSections(pinned: [], recent: []),
    archivedCount: 0,
    contacts: []
  )

  init(
    initialTab: SignalASIConversationHubTab = .conversations,
    showsBackButton: Bool = true,
    onBackToSettings: (() -> Void)? = nil
  ) {
    _selectedTab = State(initialValue: initialTab)
    self.showsBackButton = showsBackButton
    self.onBackToSettings = onBackToSettings
  }
  @State private var pendingContactDeletion: SignalASIContact?
  @State private var pendingChatDeletion: SignalASIContact?

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.agent_sessions.title", "Sessions"),
        leading: {
          if showsBackButton {
            SignalASIBackButton()
          } else if let onBackToSettings {
            Button(action: onBackToSettings) {
              Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("signalasi.common.back", "Back")))
          } else {
            Color.clear
          }
        },
        trailing: {
          Button(action: toggleSearch) {
            Image(systemName: searchExpanded ? "xmark" : "magnifyingglass")
              .font(.system(size: 17, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(searchPlaceholder))
        }
      )

      conversationHubTabStrip

      if searchExpanded {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.signalASITextSecondary)
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
        .background(Color.signalASIButtonSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if !sessionNotice.isEmpty {
        Text(sessionNotice)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.bottom, 4)
      }

      ScrollView {
        hubContent
          .padding(.horizontal, 12)
          .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
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
        SignalASINewFriendsView(onContactAccepted: finishFriendAcceptance)
      }
    }
    .sheet(isPresented: $smartDeviceOnboardingPresented) {
      NavigationView {
        SignalASISmartSpacesView()
      }
      .navigationViewStyle(.stack)
    }
    .sheet(isPresented: $groupsPresented) {
      VStack(spacing: 0) {
        SignalASITopBar(
          title: t("signalasi.conversation_hub.tab_groups", "Groups"),
          leading: {
            Button {
              groupsPresented = false
            } label: {
              Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("signalasi.common.close", "Close")))
          },
          trailing: { Color.clear }
        )
        groupsContent
          .frame(maxHeight: .infinity, alignment: .top)
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
    }
    .sheet(item: $editingSession) { session in
      SignalASIConversationHubRenameSheet(
        title: t("signalasi.agent_session.rename", "Rename"),
        initialValue: session.title
      ) { value in
        let changed = store.renameAgentSession(id: session.id, title: value)
        if changed {
          refreshAfterSessionMutation()
        }
        sessionNotice = changed
          ? t("signalasi.agent_sessions.updated", "Session updated")
          : t("signalasi.agent_sessions.update_failed", "Session was not changed")
      }
    }
    .alert(
      t("signalasi.conversation_hub.delete_contact", "Delete contact"),
      isPresented: Binding(
        get: { pendingContactDeletion != nil },
        set: { if !$0 { pendingContactDeletion = nil } }
      )
    ) {
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        pendingContactDeletion = nil
      }
      Button(t("signalasi.common.delete", "Delete"), role: .destructive) {
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
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        pendingChatDeletion = nil
      }
      Button(t("signalasi.common.delete", "Delete"), role: .destructive) {
        if let contact = pendingChatDeletion {
          store.deleteMessages(for: contact.id)
          refreshAfterChatRemoval()
        }
        pendingChatDeletion = nil
      }
    } message: {
      Text(t("signalasi.chat.delete.message", "Only local chat history is deleted. Contacts are not affected."))
    }
    .alert(
      t("signalasi.agent_session.delete", "Delete session"),
      isPresented: Binding(
        get: { deletingSession != nil },
        set: { if !$0 { deletingSession = nil } }
      )
    ) {
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        deletingSession = nil
      }
      Button(t("signalasi.common.delete", "Delete"), role: .destructive) {
        confirmDeleteSession()
      }
    } message: {
      Text(t("signalasi.agent_session.delete_confirm", "Delete this session and all of its messages?"))
    }
    .alert(
      t("signalasi.agent_session.merge_into_original", "Merge into original session"),
      isPresented: Binding(
        get: { mergingSession != nil },
        set: { if !$0 { mergingSession = nil } }
      )
    ) {
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        mergingSession = nil
      }
      Button(t("signalasi.agent_session.merge_confirm_action", "Merge"), role: .destructive) {
        confirmMergeSession()
      }
    } message: {
      if let session = mergingSession,
         let target = store.agentSession(id: session.parentConversationId) {
        Text(
          String(
            format: t(
              "signalasi.agent_session.merge_confirm",
              "Merge %@ into %@? Messages and running task history will continue in the original session."
            ),
            session.title,
            target.title
          )
        )
      }
    }
    .alert(
      t("signalasi.agent_sessions.delete_selected", "Delete selected sessions"),
      isPresented: $bulkDeletePresented
    ) {
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {}
      Button(t("signalasi.common.delete", "Delete"), role: .destructive) {
        confirmBulkDelete()
      }
    } message: {
      Text(
        String(
          format: t(
            "signalasi.agent_sessions.delete_selected_confirm",
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
      NotificationCenter.default.publisher(for: .signalASIDesktopPairingDidComplete)
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
    }
    .task(id: hubContentTaskID) {
      await prepareHubContent()
    }
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

  private var conversationHubTabStrip: some View {
    HStack(spacing: 0) {
      conversationHubTabButton(
        .conversations,
        title: t("signalasi.conversation_hub.tab_conversations", "Chats")
      )
      conversationHubTabButton(
        .contacts,
        title: t("signalasi.conversation_hub.tab_contacts", "Contacts")
      )
    }
    .padding(2)
    .frame(height: 40)
    .background(Color.signalASIButtonSoft)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .padding(.horizontal, 12)
    .padding(.top, 2)
  }

  private func conversationHubTabButton(
    _ tab: SignalASIConversationHubTab,
    title: String
  ) -> some View {
    let selected = selectedTab == tab
    return Button {
      closeSearch()
      selectedTab = tab
    } label: {
      Text(title)
        .font(.system(size: 14, weight: selected ? .bold : .regular))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(selected ? Color.signalASISurface : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
    .accessibilityLabel(Text(title))
  }

  private var conversationContent: some View {
    let visible = preparedHubContent.conversations

    return VStack(alignment: .leading, spacing: 8) {
      hubActionRow(
        title: showingArchived
          ? t("signalasi.conversation_hub.back_to_conversations", "Back to conversations")
          : t("signalasi.agent_session.new", "New session"),
        subtitle: showingArchived
          ? t("signalasi.conversation_hub.archived_subtitle", "Return to active Agent conversations")
          : t("signalasi.conversation_hub.new_subtitle", "Start a fresh Agent context for the next request"),
        systemImage: showingArchived ? "clock.arrow.circlepath" : "plus.circle",
        tint: showingArchived ? .blue : .signalASIAccent
      ) {
        if showingArchived {
          showingArchived = false
        } else {
          _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
          dismiss()
        }
      }

      if !showingArchived {
        hubActionRow(
          title: t("signalasi.agent_session.archived", "Archived sessions"),
          subtitle: String(format: t("signalasi.conversation_hub.archived_count", "%d archived"), preparedHubContent.archivedCount),
          systemImage: "clock.arrow.circlepath",
          tint: .blue,
          badge: preparedHubContent.archivedCount > 0 ? "\(preparedHubContent.archivedCount)" : ""
        ) {
          showingArchived = true
        }
      }

      if multiDeleteMode {
        bulkDeleteToolbar(
          visible: (visible.pinned + visible.recent)
            .compactMap { store.agentSession(id: $0.id) }
        )
      }

      if !visible.pinned.isEmpty {
        hubSectionTitle(t("signalasi.conversation_hub.pinned", "Pinned"))
        ForEach(visible.pinned) { item in
          unifiedConversationRow(item)
        }
      }

      hubSectionTitle(
        showingArchived
          ? t("signalasi.agent_session.archived", "Archived sessions")
          : t("signalasi.conversation_hub.recent", "Recent")
      )
      if visible.recent.isEmpty {
        hubEmptyRow(t("signalasi.agent_session.no_results", "No matching sessions"))
      } else {
        ForEach(visible.recent) { item in
          unifiedConversationRow(item)
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
      .environment(\.signalASIInterfaceLanguage, interfaceLanguage)
    }
    .sheet(item: $contextPolicySession) { session in
      AgentSessionContextPolicySheet(
        session: session,
        selectedPolicy: session.contextPolicy,
        onSelect: { policy in
          if store.setAgentSessionContextPolicy(id: session.id, policy: policy) {
            sessionNotice = t("signalasi.agent_sessions.context_updated", "Context policy updated")
            refreshAfterSessionMutation()
          }
          contextPolicySession = nil
        }
      )
      .environment(\.signalASIInterfaceLanguage, interfaceLanguage)
    }
    .sheet(item: $detailsSession) { session in
      AgentSessionDetailsSheet(
        session: store.agentSession(id: session.id) ?? session,
        metrics: store.agentSessionMetrics(session.id),
        messages: Array(store.agentSessionMessages(session.id).suffix(8))
      )
      .environment(\.signalASIInterfaceLanguage, interfaceLanguage)
    }
  }

  private var contactsContent: some View {
    let contacts = preparedHubContent.contacts
    let sections = Dictionary(grouping: contacts) { contactSection($0.displayName) }
      .keys
      .sorted(by: contactSectionSort)

    return VStack(alignment: .leading, spacing: 8) {
      hubActionRow(
        title: t("signalasi.new_friends", "New Friends"),
        subtitle: t("signalasi.conversation_hub.new_friends_subtitle", "Review pending contact requests"),
        systemImage: "person.badge.plus",
        tint: .signalASIAccent,
        unreadCount: store.unreadFriendRequestCount
      ) {
        _ = store.markIncomingFriendRequestsRead()
        pendingFriendRequestsPresented = true
      }
      hubActionRow(
        title: t("signalasi.conversation_hub.tab_groups", "Groups"),
        subtitle: t(
          "signalasi.conversation_hub.groups_subtitle",
          "View and manage secure group conversations"
        ),
        systemImage: "person.3.fill",
        tint: .purple
      ) {
        groupsPresented = true
      }
      hubActionRow(
        title: t("signalasi.conversation_hub.add_cloud_model", "Add Cloud Model"),
        subtitle: t(
          "signalasi.conversation_hub.add_cloud_model_subtitle",
          "Configure a provider, model, and API key on this phone"
        ),
        systemImage: "icloud.and.arrow.up.fill",
        tint: .indigo
      ) {
        cloudModelOnboardingPresented = true
      }
      hubActionRow(
        title: t("signalasi.conversation_hub.add_smart_device", "Add Smart Device"),
        subtitle: t(
          "signalasi.conversation_hub.add_smart_device_subtitle",
          "Connect Home Assistant or a custom device endpoint"
        ),
        systemImage: "sensor.tag.radiowaves.forward",
        tint: .orange
      ) {
        smartDeviceOnboardingPresented = true
      }
      hubActionRow(
        title: t("signalasi.conversation_hub.scan_add", "Scan to add"),
        subtitle: t("signalasi.conversation_hub.scan_add_subtitle", "Add an Agent, trusted contact, or device"),
        systemImage: "qrcode.viewfinder",
        tint: .cyan
      ) {
        addContactPresentation = .scanner
      }

      if sections.isEmpty {
        hubEmptyRow(t("signalasi.empty.contacts", "No matching contacts"))
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
        .tint(.signalASIAccent)
      Text(t("cc_loading", "Loading..."))
        .font(.system(size: 14))
        .foregroundColor(.signalASITextSecondary)
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
    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       !showingArchived,
       let cached = SignalASINavigationContentPrewarm.snapshot(for: store)?.hub {
      preparedHubContent = cached
      hubContentLoading = false
      return
    }
    hubContentLoading = true
    let sourceConversations = store.agentSessions(includeArchived: true)
    let sourceContacts = store.contactList(matching: "")
    let sourceChatContacts = store.chatContacts(matching: "")
    let query = searchText
    let archived = showingArchived
    let agentItems = sourceConversations.map { conversation in
      let latest = store.agentSessionMessages(conversation.id).last
      let preview = latest.map { ContactConversationSummary(lastMessage: $0, unreadCount: 0).previewText } ?? ""
      return SignalASIConversationHubItem(
        id: conversation.id,
        kind: .agent,
        title: SignalASIConversationHubModels.agentDisplayTitle(
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
    let contactSummaries = SignalASIConversationHubModels.contactSummaries(
      contacts: sourceChatContacts,
      summary: store.conversationSummary(for:),
      isPinned: store.isContactPinned
    )
    let prepared = await Task.detached(priority: .userInitiated) {
      SignalASIConversationHubPreparedContent(
        conversations: SignalASIConversationHubModels.unifiedConversations(
          agents: agentItems,
          contacts: contactSummaries,
          query: query,
          archived: archived
        ),
        archivedCount: sourceConversations.filter { $0.status == .archived }.count,
        contacts: SignalASIConversationHubModels.contacts(sourceContacts, query: query)
      )
    }.value
    guard !Task.isCancelled, navigationContentGate.isCurrent(generation) else { return }
    preparedHubContent = prepared
    hubContentLoading = false
  }

  private var groupsContent: some View {
    VStack(spacing: 8) {
      Image(systemName: "person.3.fill")
        .font(.system(size: 42, weight: .semibold))
        .foregroundColor(.signalASIAccent)
        .padding(.top, 54)
      Text(t("signalasi.conversation_hub.groups_empty", "No groups yet"))
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
      Text(t("signalasi.conversation_hub.groups_empty_subtitle", "Group conversations will appear here when available."))
        .font(.system(size: 13))
        .foregroundColor(.signalASITextSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func unifiedConversationRow(_ item: SignalASIConversationHubItem) -> some View {
    if item.kind == .agent, let session = store.agentSession(id: item.id) {
      conversationRow(session, preview: item.preview, updatedAt: item.updatedAt)
    } else if let contact = store.contact(id: item.id) {
      NavigationLink(destination: ConversationView(contactId: contact.id)) {
        hubRowContent(
          title: item.title,
          subtitle: item.preview.ifBlank(t("chat_no_messages", "No messages yet")),
          systemImage: contact.type == "device" ? "iphone" : "person.crop.circle",
          tint: contact.type == "device" ? .blue : .signalASITextSecondary,
          trailing: item.pinned ? "pin.fill" : "",
          updatedAt: item.updatedAt,
          leadingView: AnyView(AvatarView(contact: contact, size: 34)),
          unreadCount: item.unreadCount
        )
      }
      .buttonStyle(.plain)
      .contextMenu {
        if contact.id != "system" {
          Button(store.isContactPinned(contact.id)
            ? t("signalasi.agent_session.unpin", "Unpin")
            : t("signalasi.agent_session.pin", "Pin")) {
            if store.setContactPinned(contact.id, pinned: !store.isContactPinned(contact.id)) {
              refreshAfterSessionMutation()
            }
          }
          Button(t("delete_chat_title", "Delete Chat"), role: .destructive) {
            pendingChatDeletion = contact
          }
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
        title: SignalASIConversationHubModels.agentDisplayTitle(
          session,
          language: interfaceLanguage
        ),
        subtitle: preview,
        systemImage: "clock.arrow.circlepath",
        tint: .signalASIAccent,
        trailing: multiDeleteMode
          ? (selectedSessionIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
          : (session.pinned ? "pin.fill" : ""),
        updatedAt: updatedAt
      )
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(session.pinned
        ? t("signalasi.agent_session.unpin", "Unpin")
        : t("signalasi.agent_session.pin", "Pin")) {
        if store.setAgentSessionPinned(id: session.id, pinned: !session.pinned) {
          refreshAfterSessionMutation()
        }
      }
      Button(t("signalasi.agent_session.delete", "Delete session"), role: .destructive) {
        deletingSession = session
      }
      Divider()
      Button(t("signalasi.agent_sessions.select", "Select session")) {
        openConversation(session)
      }
      Button(t("signalasi.agent_session.rename", "Rename")) {
        editingSession = session
      }
      if canMerge(session) {
        Button(t("signalasi.agent_session.merge_into_original", "Merge into original session")) {
          mergingSession = session
        }
      }
      if session.mergedIntoConversationId.isBlank {
        Button(session.privateMode
          ? t("signalasi.agent_session.standard", "Standard session")
          : t("signalasi.agent_session.private", "Private session")) {
          if store.setAgentSessionPrivateMode(id: session.id, privateMode: !session.privateMode) {
            refreshAfterSessionMutation()
          }
        }
        Button(session.trackingPaused
          ? t("signalasi.agent_session.resume_tracking", "Resume global tracking")
          : t("signalasi.agent_session.pause_tracking", "Pause global tracking")) {
          if store.setAgentSessionTrackingPaused(id: session.id, paused: !session.trackingPaused) {
            refreshAfterSessionMutation()
          }
        }
        Button(session.status == .archived
          ? t("signalasi.agent_session.restore", "Restore session")
          : t("signalasi.agent_session.archive", "Archive")) {
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
      Button(t("signalasi.agent_session.context_policy", "Context policy")) {
        contextPolicySession = session
      }
      Button(t("signalasi.agent_session.summary", "View or edit summary")) {
        sessionEditDraft = AgentSessionEditDraft(
          id: session.id,
          mode: .summary,
          sheetTitle: t("signalasi.agent_session.summary", "View or edit summary"),
          text: session.summary
        )
      }
      Button(t("signalasi.agent_session.details", "Session details")) {
        detailsSession = session
      }
      Button(t("signalasi.agent_session.delete_more", "Delete more")) {
        multiDeleteMode = true
        selectedSessionIDs.removeAll()
      }
    }
  }

  private func bulkDeleteToolbar(visible sessions: [AgentConversation]) -> some View {
    HStack(spacing: 8) {
      Text(
        String(
          format: t("signalasi.agent_sessions.selected_count", "%d selected"),
          selectedSessionIDs.count
        )
      )
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
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
          ? t("signalasi.agent_sessions.clear_selection", "Clear")
          : t("signalasi.agent_sessions.select_all", "Select all")
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
      .accessibilityLabel(Text(t("signalasi.common.delete", "Delete")))
      Button {
        multiDeleteMode = false
        selectedSessionIDs.removeAll()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("signalasi.common.cancel", "Cancel")))
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
      t("signalasi.agent_session.new", "New session")
    ) ?? t("signalasi.agent_session.new", "New session")
    sessionNotice = String(
      format: t("signalasi.agent_sessions.merge_success", "Merged %d messages into %@"),
      result.copiedEntryCount,
      targetTitle
    )
    showingArchived = false
    refreshAfterSessionMutation()
  }

  private func mergeFailureMessage(_ failure: AgentConversationMergeFailure) -> String {
    switch failure {
    case .sourceNotFound:
      return t("signalasi.agent_session.merge_source_missing", "The Agent-created session no longer exists")
    case .targetNotFound:
      return t("signalasi.agent_session.merge_target_missing", "The original session no longer exists")
    case .notAgentCreated:
      return t("signalasi.agent_session.merge_unavailable", "Only Agent-created sessions can be merged")
    case .alreadyMerged:
      return t("signalasi.agent_session.merge_already_done", "This session has already been merged")
    case .sameConversation, .privacyMismatch, .none:
      return t("signalasi.agent_session.merge_unavailable", "This session cannot be merged")
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
        ? t("signalasi.agent_sessions.deleted", "Session deleted")
        : t("signalasi.agent_sessions.delete_failed", "Session was not deleted")
      if deleted {
        refreshAfterSessionMutation()
      }
      return
    }
    refreshAfterSessionMutation()
    sessionNotice = t(
      "signalasi.agent_sessions.deleted_remote_pending",
      "Session deleted; cleaning up the paired Desktop..."
    )
    Task { @MainActor in
      let sent = await coordinator.publishRemoteAgentConversationDelete(
        conversationId: session.id,
        taskIds: taskIds
      )
      sessionNotice = sent
        ? t("signalasi.agent_sessions.deleted_remote_sent", "Remote cleanup request sent")
        : t("signalasi.agent_sessions.deleted_remote_failed", "Session deleted; remote cleanup could not be sent")
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
      sessionNotice = t("signalasi.agent_sessions.delete_failed", "Session was not deleted")
      return
    }
    refreshAfterSessionMutation()
    sessionNotice = String(
      format: t(
        "signalasi.agent_sessions.deleted_selected_pending",
        "%d sessions deleted; cleaning up the paired Desktop..."
      ),
      deletedCount
    )
    guard !cleanupRequests.isEmpty else {
      sessionNotice = String(
        format: t("signalasi.agent_sessions.deleted_selected", "%d sessions deleted"),
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
        ? t("signalasi.agent_sessions.deleted_selected_sent", "Selected sessions deleted and remote cleanup sent")
        : t("signalasi.agent_sessions.deleted_selected_failed", "Sessions deleted; some remote cleanup requests failed")
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
      ? t("signalasi.agent_sessions.updated", "Session updated")
      : t("signalasi.agent_sessions.update_failed", "Session was not changed")
  }

  private func contactRow(_ contact: SignalASIContact) -> some View {
    let kindPresentation = SignalASIContactKindPresentation.forContact(contact, t: t)
    return NavigationLink(destination: ContactDetailView(contactId: contact.id)) {
      hubRowContent(
        title: contact.displayName,
        subtitle: "",
        systemImage: contact.type == "device"
          ? "iphone"
          : (contact.type == "agent" ? "cpu" : "person.fill"),
        tint: contact.type == "device"
          ? .blue
          : (contact.type == "agent" ? .signalASIAccent : .signalASITextSecondary),
        trailing: "",
        leadingView: AnyView(AvatarView(contact: contact, size: 34)),
        titleAccessory: kindPresentation.map {
          AnyView(SignalASIContactKindBadge(presentation: $0))
        }
      )
    }
    .buttonStyle(.plain)
    .onLongPressGesture {
      if contact.id != "system" {
        pendingContactDeletion = contact
      }
    }
    .accessibilityAction(named: Text(t("signalasi.conversation_hub.delete_contact", "Delete contact"))) {
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
              .stroke(Color.signalASISeparator, lineWidth: 0.5)
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
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          if let titleAccessory {
            titleAccessory
          }
        }
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if let updatedAt, updatedAt.timeIntervalSince1970 > 0 {
        Text(
          SignalASIChatListTimeFormatter.string(
            for: updatedAt,
            language: interfaceLanguage
          )
        )
        .font(.system(size: 11.5, weight: .regular))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(1)
      }
      if unreadCount > 0 {
        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
          .foregroundColor(.white)
          .padding(.horizontal, 6)
          .frame(minWidth: 22, minHeight: 20)
          .background(Capsule().fill(Color.signalASIUnreadRed))
      } else if trailing == "chevron.right" {
        Image(systemName: trailing)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      } else if trailing == "pin.fill" || trailing == "checkmark.circle.fill" || trailing == "circle" {
        Image(systemName: trailing)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      } else if !trailing.isEmpty {
        Text(trailing)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
          .frame(width: 20, height: 36)
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(minHeight: subtitle.isEmpty ? 56 : 64)
    .background(Color.signalASISurface)
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASISeparator, lineWidth: 0.5)
    }
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func hubSectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 8)
  }

  private func hubEmptyRow(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 14))
      .foregroundColor(.signalASITextSecondary)
      .frame(maxWidth: .infinity, minHeight: 72)
  }

  private var searchPlaceholder: String {
    t(
      "signalasi.conversation_hub.search_hint",
      "Search chats, contacts, or groups"
    )
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

  private func sectionsContacts(section: String) -> [SignalASIContact] {
    SignalASIConversationHubModels.contacts(
      store.contactList(matching: ""),
      query: searchText
    ).filter { contactSection($0.displayName) == section }
  }

  private func contactSection(_ name: String) -> String {
    SignalASIConversationHubModels.contactSection(name)
  }

  private func contactSectionSort(_ left: String, _ right: String) -> Bool {
    if left == "#" { return false }
    if right == "#" { return true }
    return left < right
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIConversationHubRenameSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
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
      SignalASITopBar(
        title: title,
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t("signalasi.common.cancel", "Cancel")))
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
              .foregroundColor(.signalASIAccent)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(t("signalasi.common.save", "Save")))
          .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      )
      TextField(t("signalasi.agent_session.name_placeholder", "Session name"), text: $value)
        .textInputAutocapitalization(.sentences)
        .autocorrectionDisabled(false)
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(16)
      Spacer()
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
