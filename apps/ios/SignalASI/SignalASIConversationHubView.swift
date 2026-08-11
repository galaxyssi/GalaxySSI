import SwiftUI

enum SignalASIConversationHubTab: String, CaseIterable, Identifiable {
  case conversations
  case contacts
  case groups

  var id: String { rawValue }
}

private enum SignalASIAddContactPresentation: String, Identifiable, Equatable {
  case normal
  case scanner

  var id: String { rawValue }
}

struct SignalASIConversationHubView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var selectedTab: SignalASIConversationHubTab
  @State private var searchText = ""
  @State private var showingArchived = false
  @State private var addContactPresentation: SignalASIAddContactPresentation?
  @State private var cloudModelPresented = false
  @State private var pendingFriendRequestsPresented = false
  private let showsBackButton: Bool
  @State private var editingSession: AgentConversation?
  @State private var deletingSession: AgentConversation?
  @State private var mergingSession: AgentConversation?
  @State private var multiDeleteMode = false
  @State private var selectedSessionIDs: Set<String> = []
  @State private var bulkDeletePresented = false
  @State private var sessionNotice = ""

  init(
    initialTab: SignalASIConversationHubTab = .conversations,
    showsBackButton: Bool = true
  ) {
    _selectedTab = State(initialValue: initialTab)
    self.showsBackButton = showsBackButton
  }
  @State private var pendingContactDeletion: SignalASIContact?

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: hubTitle,
        leading: {
          if showsBackButton {
            SignalASIBackButton()
          } else {
            Color.clear
          }
        },
        trailing: { Color.clear }
      )

      Picker("", selection: $selectedTab) {
        Text(t("signalasi.conversation_hub.tab_conversations", "Conversations"))
          .tag(SignalASIConversationHubTab.conversations)
        Text(t("signalasi.conversation_hub.tab_contacts", "Contacts"))
          .tag(SignalASIConversationHubTab.contacts)
        Text(t("signalasi.conversation_hub.tab_groups", "Groups"))
          .tag(SignalASIConversationHubTab.groups)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 12)
      .padding(.top, 2)

      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.signalASITextSecondary)
        TextField(searchPlaceholder, text: $searchText)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
          .submitLabel(.search)
      }
      .font(.system(size: 15))
      .padding(.horizontal, 12)
      .frame(height: 36)
      .background(Color.signalASISearchBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .padding(.horizontal, 12)
      .padding(.top, 10)
      .padding(.bottom, 5)

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
      AddContactView(autoOpenScanner: presentation == .scanner)
    }
    .sheet(isPresented: $cloudModelPresented) {
      CloudModelProviderSelectionView()
    }
    .sheet(isPresented: $pendingFriendRequestsPresented) {
      ContactsView(showsBackButton: false)
    }
    .sheet(item: $editingSession) { session in
      SignalASIConversationHubRenameSheet(
        title: t("signalasi.agent_session.rename", "Rename"),
        initialValue: session.title
      ) { value in
        sessionNotice = store.renameAgentSession(id: session.id, title: value)
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
          _ = store.deleteContact(id: contact.id)
        }
        pendingContactDeletion = nil
      }
    } message: {
      Text(t("signalasi.conversation_hub.delete_contact_message", "Only this contact and its local history will be removed."))
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
      searchText = ""
      showingArchived = false
      multiDeleteMode = false
      selectedSessionIDs.removeAll()
    }
  }

  @ViewBuilder
  private var hubContent: some View {
    switch selectedTab {
    case .conversations:
      conversationContent
    case .contacts:
      contactsContent
    case .groups:
      groupsContent
    }
  }

  private var conversationContent: some View {
    let all = store.agentSessions(includeArchived: true)
    let visible = SignalASIConversationHubModels.conversations(
      all,
      query: searchText,
      archived: showingArchived
    )

    return VStack(alignment: .leading, spacing: 8) {
      hubActionRow(
        title: showingArchived
          ? t("signalasi.conversation_hub.back_to_conversations", "Back to conversations")
          : t("signalasi.agent_session.new", "New session"),
        subtitle: showingArchived
          ? t("signalasi.conversation_hub.archived_subtitle", "Return to active Agent conversations")
          : t("signalasi.conversation_hub.new_subtitle", "Start a fresh Agent context for the next request"),
        systemImage: showingArchived ? "arrow.left" : "plus.circle",
        tint: .signalASIAccent
      ) {
        if showingArchived {
          showingArchived = false
        } else {
          _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
        }
      }

      if !showingArchived {
        let archivedCount = all.filter { $0.status == .archived }.count
        hubActionRow(
          title: t("signalasi.agent_session.archived", "Archived sessions"),
          subtitle: String(format: t("signalasi.conversation_hub.archived_count", "%d archived"), archivedCount),
          systemImage: "archivebox",
          tint: .blue,
          badge: archivedCount > 0 ? "\(archivedCount)" : ""
        ) {
          showingArchived = true
        }
      }

      if multiDeleteMode {
        bulkDeleteToolbar(visible: visible.pinned + visible.recent)
      }

      if !visible.pinned.isEmpty {
        hubSectionTitle(t("signalasi.conversation_hub.pinned", "Pinned"))
        ForEach(visible.pinned) { session in
          conversationRow(session)
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
        ForEach(visible.recent) { session in
          conversationRow(session)
        }
      }
    }
  }

  private var contactsContent: some View {
    let contacts = SignalASIConversationHubModels.contacts(
      store.contactList(matching: ""),
      query: searchText
    )
    let sections = Dictionary(grouping: contacts) { contactSection($0.displayName) }
      .keys
      .sorted(by: contactSectionSort)

    return VStack(alignment: .leading, spacing: 8) {
      hubActionRow(
        title: t("signalasi.new_friends", "New Friends"),
        subtitle: t("signalasi.conversation_hub.new_friends_subtitle", "Review pending contact requests"),
        systemImage: "person.badge.plus",
        tint: .blue,
        badge: store.pendingFriendRequests.isEmpty ? "" : "\(store.pendingFriendRequests.count)"
      ) {
        pendingFriendRequestsPresented = true
      }
      hubActionRow(
        title: t("signalasi.add_contact.cloud_title", "Add Cloud Model"),
        subtitle: t(
          "signalasi.add_contact.cloud_subtitle",
          "Provider, model, and API key are configured directly on the phone."
        ),
        systemImage: "cloud.fill",
        tint: .signalASIInsightText
      ) {
        cloudModelPresented = true
      }
      hubActionRow(
        title: t("signalasi.conversation_hub.scan_add", "Scan to add"),
        subtitle: t("signalasi.conversation_hub.scan_add_subtitle", "Add an Agent, trusted contact, or device"),
        systemImage: "qrcode.viewfinder",
        tint: .signalASIAccent
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

  private func conversationRow(_ session: AgentConversation) -> some View {
    Button {
      if multiDeleteMode {
        toggleSelectedSession(session.id)
      } else {
        _ = store.switchAgentSession(session.id)
        dismiss()
      }
    } label: {
      hubRowContent(
        title: sessionTitle(session),
        subtitle: sessionSubtitle(session),
        systemImage: "bubble.left.and.bubble.right.fill",
        tint: .signalASIAccent,
        trailing: multiDeleteMode
          ? (selectedSessionIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
          : (session.pinned ? "pin.fill" : "")
      )
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(t("signalasi.agent_sessions.select", "Select session")) {
        _ = store.switchAgentSession(session.id)
        dismiss()
      }
      Button(t("signalasi.agent_session.rename", "Rename")) {
        editingSession = session
      }
      Button(session.pinned
        ? t("signalasi.agent_session.unpin", "Unpin")
        : t("signalasi.agent_session.pin", "Pin")) {
        _ = store.setAgentSessionPinned(id: session.id, pinned: !session.pinned)
      }
      if canMerge(session) {
        Button(t("signalasi.agent_session.merge_into_original", "Merge into original session")) {
          mergingSession = session
        }
      }
      if session.mergedIntoConversationId.isBlank {
        Button(session.trackingPaused
          ? t("signalasi.agent_session.resume_tracking", "Resume global tracking")
          : t("signalasi.agent_session.pause_tracking", "Pause global tracking")) {
          _ = store.setAgentSessionTrackingPaused(id: session.id, paused: !session.trackingPaused)
        }
        Button(session.status == .archived
          ? t("signalasi.agent_session.restore", "Restore session")
          : t("signalasi.agent_session.archive", "Archive")) {
          if session.status == .archived {
            _ = store.restoreAgentSession(id: session.id)
            showingArchived = false
          } else {
            _ = store.archiveAgentSession(id: session.id)
          }
        }
      }
      Button(t("signalasi.agent_session.delete_more", "Delete more")) {
        multiDeleteMode = true
        selectedSessionIDs.removeAll()
      }
      Button(t("signalasi.agent_session.delete", "Delete session"), role: .destructive) {
        deletingSession = session
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
      return
    }
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
        if !await coordinator.publishRemoteAgentConversationDelete(
          conversationId: request.conversationId,
          taskIds: request.taskIds
        ) {
          failed += 1
        }
      }
      sessionNotice = failed == 0
        ? t("signalasi.agent_sessions.deleted_selected_sent", "Selected sessions deleted and remote cleanup sent")
        : t("signalasi.agent_sessions.deleted_selected_failed", "Sessions deleted; some remote cleanup requests failed")
    }
  }

  private func contactRow(_ contact: SignalASIContact) -> some View {
    NavigationLink(destination: ContactDetailView(contactId: contact.id)) {
      hubRowContent(
        title: contact.displayName,
        subtitle: contact.id,
        systemImage: contact.type == "agent" ? "cpu" : "person.fill",
        tint: contact.type == "agent" ? .signalASIAccent : .signalASITextSecondary,
        trailing: "chevron.right"
      )
    }
    .buttonStyle(.plain)
    .contextMenu {
      if contact.id != "system" {
        Button(t("signalasi.conversation_hub.delete_contact", "Delete contact"), role: .destructive) {
          pendingContactDeletion = contact
        }
      }
    }
  }

  private func hubActionRow(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String = "",
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      hubRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        trailing: badge
      )
    }
    .buttonStyle(.plain)
  }

  private func hubRowContent(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    trailing: String
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(tint)
        .frame(width: 34, height: 34)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if trailing == "chevron.right" {
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
    selectedTab == .contacts
      ? t("signalasi.conversation_hub.search_contacts", "Search contacts")
      : t("signalasi.conversation_hub.search_conversations", "Search conversations")
  }

  private var hubTitle: String {
    switch selectedTab {
    case .conversations:
      return t("signalasi.conversation_hub.title", "Conversations")
    case .contacts:
      return t("signalasi.conversation_hub.tab_contacts", "Contacts")
    case .groups:
      return t("signalasi.conversation_hub.tab_groups", "Groups")
    }
  }

  private func sessionTitle(_ session: AgentConversation) -> String {
    let title = session.title.ifBlank(session.id)
    return session.createdByAgent
      ? String(format: t("signalasi.agent_session.created_by_agent", "SignalASI · %@"), title)
      : title
  }

  private func sessionSubtitle(_ session: AgentConversation) -> String {
    let route = session.selectedModelOrAgent.ifBlank(
      t("signalasi.agent.model_selection.automatic", "Automatic")
    )
    let count = store.agentSessionMetrics(session.id).messageCount
    return String(
      format: t("signalasi.conversation_hub.session_subtitle", "%@ · %d messages"),
      route,
      count
    )
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

struct SignalASIConversationHubSections {
  var pinned: [AgentConversation]
  var recent: [AgentConversation]
}

enum SignalASIConversationHubModels {
  static func conversations(
    _ source: [AgentConversation],
    query: String,
    archived: Bool
  ) -> SignalASIConversationHubSections {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let matching = source
      .filter { $0.status == (archived ? .archived : .active) }
      .filter { conversation in
        cleanQuery.isEmpty || [
          conversation.title,
          conversation.summary,
          conversation.selectedModelOrAgent,
          conversation.id
        ].contains { $0.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
      }
      .sorted { $0.updatedAt > $1.updatedAt }
    return archived
      ? SignalASIConversationHubSections(pinned: [], recent: matching)
      : SignalASIConversationHubSections(
        pinned: matching.filter(\.pinned),
        recent: matching.filter { !$0.pinned }
      )
  }

  static func contacts(_ source: [SignalASIContact], query: String) -> [SignalASIContact] {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return source
      .filter { contact in
        cleanQuery.isEmpty || [contact.displayName, contact.id].contains {
          $0.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
      .sorted {
        let leftSection = contactSection($0.displayName)
        let rightSection = contactSection($1.displayName)
        if leftSection != rightSection {
          if leftSection == "#" { return false }
          if rightSection == "#" { return true }
          return leftSection < rightSection
        }
        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
  }

  static func contactSection(_ name: String) -> String {
    guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first else {
      return "#"
    }
    return first.isASCII && first.isLetter ? String(first).uppercased() : "#"
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
