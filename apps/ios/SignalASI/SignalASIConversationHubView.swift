import SwiftUI

enum SignalASIConversationHubTab: String, CaseIterable, Identifiable {
  case conversations
  case contacts
  case groups

  var id: String { rawValue }
}

struct SignalASIConversationHubView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var selectedTab: SignalASIConversationHubTab
  @State private var searchText = ""
  @State private var showingArchived = false
  @State private var addContactPresented = false
  @State private var openScannerOnAdd = false
  @State private var cloudModelPresented = false
  @State private var pendingFriendRequestsPresented = false
  private let showsBackButton: Bool

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
        trailing: {
          if selectedTab == .groups {
            Color.clear
          } else {
            Button {
              if selectedTab == .contacts {
                openScannerOnAdd = false
                addContactPresented = true
              } else {
                _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
              }
            } label: {
              Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("signalasi.common.add", "Add")))
          }
        }
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

      ScrollView {
        hubContent
          .padding(.horizontal, 12)
          .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $addContactPresented) {
      AddContactView(autoOpenScanner: openScannerOnAdd)
    }
    .sheet(isPresented: $cloudModelPresented) {
      CloudModelProviderSelectionView()
    }
    .sheet(isPresented: $pendingFriendRequestsPresented) {
      ContactsView(showsBackButton: false)
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
    .onChange(of: selectedTab) { _ in
      searchText = ""
      showingArchived = false
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
        title: t("signalasi.conversation_hub.scan_add", "Scan to add"),
        subtitle: t("signalasi.conversation_hub.scan_add_subtitle", "Add an Agent, trusted contact, or device"),
        systemImage: "qrcode.viewfinder",
        tint: .signalASIAccent
      ) {
        openScannerOnAdd = true
        addContactPresented = true
      }
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
      _ = store.switchAgentSession(session.id)
      dismiss()
    } label: {
      hubRowContent(
        title: sessionTitle(session),
        subtitle: sessionSubtitle(session),
        systemImage: "bubble.left.and.bubble.right.fill",
        tint: .signalASIAccent,
        trailing: session.pinned ? "pin.fill" : ""
      )
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button(session.pinned
        ? t("signalasi.agent_session.unpin", "Unpin")
        : t("signalasi.agent_session.pin", "Pin")) {
        _ = store.setAgentSessionPinned(id: session.id, pinned: !session.pinned)
      }
      if session.status == .archived {
        Button(t("signalasi.agent_session.restore", "Restore session")) {
          _ = store.restoreAgentSession(id: session.id)
          showingArchived = false
        }
      } else {
        Button(t("signalasi.agent_session.archive", "Archive")) {
          _ = store.archiveAgentSession(id: session.id)
        }
      }
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
      } else if trailing == "pin.fill" {
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
