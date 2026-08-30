import Foundation

enum SignalASIConversationHubTab: String, CaseIterable, Identifiable {
  case conversations
  case contacts

  var id: String { rawValue }
}

enum SignalASIConversationHubBackAction: Equatable {
  case closeSearch
  case showConversations
  case dismiss
}

enum SignalASIConversationHubBackPolicy {
  static func action(
    searchExpanded: Bool,
    tab: SignalASIConversationHubTab,
    archived: Bool
  ) -> SignalASIConversationHubBackAction {
    if searchExpanded { return .closeSearch }
    if archived || tab == .contacts { return .showConversations }
    return .dismiss
  }
}

enum SignalASIConversationHubScrollPolicy {
  static func anchorId(positions: [String: CGFloat]) -> String? {
    let visible = positions.filter { $0.value >= 0 }
    if let nearestVisible = visible.min(by: { left, right in
      left.value == right.value ? left.key < right.key : left.value < right.value
    }) {
      return nearestVisible.key
    }
    return positions.max(by: { left, right in
      left.value == right.value ? left.key > right.key : left.value < right.value
    })?.key
  }
}

struct SignalASIConversationHubSections {
  var pinned: [SignalASIConversationHubItem]
  var recent: [SignalASIConversationHubItem]
}

enum SignalASIConversationHubItemKind: String, Equatable {
  case agent
  case contact
}

struct SignalASIConversationHubContactSummary: Equatable {
  var contactId: String
  var title: String
  var preview: String
  var updatedAt: Date
  var pinned: Bool = false
  var unreadCount: Int = 0
}

struct SignalASIConversationHubItem: Identifiable, Equatable {
  var id: String
  var kind: SignalASIConversationHubItemKind
  var title: String
  var subtitle: String
  var preview: String
  var updatedAt: Date
  var pinned: Bool
  var archived: Bool
  var searchableMetadata: String
  var unreadCount: Int = 0
}

enum SignalASIConversationHubModels {
  static func contactSummaries(
    contacts: [SignalASIContact],
    summary: (String) -> ContactConversationSummary,
    isPinned: (String) -> Bool
  ) -> [SignalASIConversationHubContactSummary] {
    contacts.compactMap { contact in
      let conversation = summary(contact.id)
      guard let latest = conversation.lastMessage else { return nil }
      return SignalASIConversationHubContactSummary(
        contactId: contact.id,
        title: contact.displayName.ifBlank(contact.name).ifBlank(contact.id),
        preview: conversation.previewText,
        updatedAt: latest.createdAt,
        pinned: isPinned(contact.id),
        unreadCount: conversation.unreadCount
      )
    }
  }

  static func agentDisplayTitle(_ session: AgentConversation, language: String) -> String {
    let fallbackTitle = SignalASILocalization.string(
      "signalasi.agent_session.new",
      fallback: "New session",
      language: language
    )
    let rawTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = rawTitle == "New session" ? fallbackTitle : rawTitle.ifBlank(session.id)
    let sourceTitle = session.createdByAgent
      ? String(
        format: SignalASILocalization.string(
          "signalasi.agent_session.created_by_agent",
          fallback: "SignalASI · %@",
          language: language
        ),
        title
      )
      : title
    if !session.mergedIntoConversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return sourceTitle + " · " + SignalASILocalization.string(
        "signalasi.agent_session.merged",
        fallback: "Merged",
        language: language
      )
    }
    if session.trackingPaused {
      return sourceTitle + " · " + SignalASILocalization.string(
        "signalasi.agent_session.tracking_paused",
        fallback: "Tracking paused",
        language: language
      )
    }
    return sourceTitle
  }

  static func conversations(
    _ source: [AgentConversation],
    query: String,
    archived: Bool
  ) -> SignalASIConversationHubSections {
    unifiedConversations(
      agents: source.map { conversation in
        SignalASIConversationHubItem(
          id: conversation.id,
          kind: .agent,
          title: agentDisplayTitle(conversation, language: LanguagePolicySettings.auto),
          subtitle: conversation.summary,
          preview: conversation.summary,
          updatedAt: Date(timeIntervalSince1970: TimeInterval(conversation.updatedAt) / 1_000),
          pinned: conversation.pinned,
          archived: conversation.status == .archived,
          searchableMetadata: conversation.selectedModelOrAgent
        )
      },
      contacts: [],
      query: query,
      archived: archived
    )
  }

  static func unifiedConversations(
    agents: [SignalASIConversationHubItem],
    contacts: [SignalASIConversationHubContactSummary],
    query: String,
    archived: Bool
  ) -> SignalASIConversationHubSections {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let contactItems = archived ? [] : contacts.map { contact in
      SignalASIConversationHubItem(
        id: contact.contactId,
        kind: .contact,
        title: contact.title,
        subtitle: contact.preview,
        preview: contact.preview,
        updatedAt: contact.updatedAt,
        pinned: contact.pinned,
        archived: false,
        searchableMetadata: contact.contactId,
        unreadCount: contact.unreadCount
      )
    }
    let matching = (agents + contactItems)
      .filter { $0.archived == archived }
      .filter { item in
        cleanQuery.isEmpty || [item.title, item.subtitle, item.preview, item.searchableMetadata]
          .contains { $0.range(of: cleanQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
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

enum SignalASIFriendRequestPresentationPolicy {
  static func isAdded(_ request: SignalASIFriendRequest, contactIsVerified: Bool) -> Bool {
    request.status == .approved || contactIsVerified
  }

  static func isVisible(_ request: SignalASIFriendRequest, contactIsVerified: Bool) -> Bool {
    if request.status == .pending { return true }
    return request.direction == .outgoing && isAdded(request, contactIsVerified: contactIsVerified)
  }
}

enum SignalASIFriendRequestUnreadPolicy {
  static func isReadForPendingRequest(
    previous: SignalASIFriendRequest?,
    direction: SignalASIFriendRequestDirection
  ) -> Bool {
    if direction == .outgoing { return true }
    guard let previous, previous.status == .pending else { return false }
    return previous.isRead
  }

  static func unreadCount(_ requests: [SignalASIFriendRequest]) -> Int {
    requests.filter {
      $0.status == .pending && $0.direction == .incoming && !$0.isRead
    }.count
  }
}

enum SignalASIConnectorControlMessagePolicy {
  static func isSilentStatus(type: String) -> Bool {
    type == "connector_status"
  }
}
