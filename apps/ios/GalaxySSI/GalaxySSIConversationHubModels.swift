import Foundation

enum GalaxySSIConversationExecutionStatus: String, CaseIterable {
  case queued, running, waitingResponse, reconnecting, delivering
  case completeUnread, read, waitingConfirmation, paused, blocked, failed, cancelled

  var animated: Bool {
    switch self {
    case .queued, .running, .waitingResponse, .reconnecting, .delivering: return true
    default: return false
    }
  }

  var systemImage: String {
    if animated { return "arrow.triangle.2.circlepath" }
    switch self {
    case .completeUnread: return "checkmark.circle"
    case .waitingConfirmation, .paused: return "pause.circle"
    case .failed, .blocked: return "exclamationmark.circle"
    default: return "bubble.left"
    }
  }

  var foregroundRGB: UInt32 {
    if animated { return 0x1677FF }
    switch self {
    case .completeUnread: return 0x12BD76
    case .waitingConfirmation, .paused: return 0xE59100
    case .failed, .blocked: return 0xE53E46
    default: return 0x74777D
    }
  }

  var backgroundRGB: UInt32 {
    if animated { return 0xEAF3FF }
    switch self {
    case .completeUnread: return 0xECF9F2
    case .waitingConfirmation, .paused: return 0xFFF5E2
    case .failed, .blocked: return 0xFDECEE
    default: return 0xEFF0F3
    }
  }

  var label: String {
    switch self {
    case .queued: return "Queued"
    case .running: return "Running"
    case .waitingResponse: return "Waiting for response"
    case .reconnecting: return "Reconnecting"
    case .delivering: return "Delivering reply"
    case .completeUnread: return "Completed, unread"
    case .read: return "Read"
    case .waitingConfirmation: return "Waiting for confirmation"
    case .paused: return "Paused"
    case .blocked: return "Blocked"
    case .failed: return "Failed"
    case .cancelled: return "Cancelled"
    }
  }
}

enum GalaxySSIConversationExecutionPolicy {
  struct Snapshot {
    let workspaceID: String
    let conversationID: String
    let taskID: String
    let phase: AgentPhase
    let createdAt: Int64
    let updatedAt: Int64
    let recovering: Bool
    let canReconcileDeliveredReply: Bool
    let cancellationRequested: Bool
    let latestResumeAt: Int64?

    init(_ workspace: AgentWorkspace) {
      workspaceID = workspace.workspaceId
      conversationID = workspace.conversationId
      taskID = workspace.taskId
      phase = GalaxySSIConversationExecutionPolicy.phase(workspace.status)
      createdAt = workspace.createdAtMillis
      updatedAt = workspace.updatedAtMillis
      recovering = GalaxySSIConversationExecutionPolicy.isRecovering(workspace)
      canReconcileDeliveredReply = [.created, .queued, .running, .waitingResponse].contains(workspace.status)
      cancellationRequested = workspace.cancellationRequested
      latestResumeAt = workspace.eventJournal.filter { $0.kind == AgentTaskEventKinds.resumed }
        .map(\.timestampMillis).max()
    }
  }

  static func resolve(conversationID: String, message: ChatMessage?, tasks: [AgentTaskRecord], unread: Bool,
                      workspaces: [Snapshot] = []) -> GalaxySSIConversationExecutionStatus {
    if let message, message.conversationId == conversationID, message.deliveryStatus == .failed { return .failed }
    let latest = message.flatMap { message -> AgentTranscriptEntry? in
      guard message.conversationId == conversationID else { return nil }
      let role: AgentTranscriptRole = message.isMine ? .user : (AgentReplyUnreadPolicy.token(message) == nil ? .process : .assistant)
      return AgentTranscriptEntry(id: message.remoteMessageId.ifBlank(message.id.uuidString), role: role,
        text: "", timestampMillis: Int64(message.createdAt.timeIntervalSince1970 * 1000),
        dedupeKey: message.remoteMessageId, conversationId: message.conversationId, turnId: message.turnId)
    }
    let selected = task(conversationID: conversationID, latest: latest, tasks: tasks)
    let workspace = workspaces.filter { workspace in
      guard workspace.conversationID == conversationID else { return false }
      guard let turn = latest?.turnId, !turn.isEmpty else { return true }
      return workspace.workspaceID == turn || workspace.taskID == turn
    }.max {
      if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
      return $0.updatedAt < $1.updatedAt
    }
    if let workspace, workspace.updatedAt >= (selected?.updatedAtMillis ?? Int64.min) {
      return resolve(workspace: workspace, latest: latest, unread: unread)
    }
    return resolve(phase: selected?.phase, latest: latest, unread: unread)
  }

  static func isRecovering(_ workspace: AgentWorkspace) -> Bool {
    let recovery: Set<String> = [AgentTaskEventKinds.recoveryWaitingResponse,
      AgentTaskEventKinds.recoveredInterrupted, AgentTaskEventKinds.interrupted]
    let relevant = recovery.union([AgentTaskEventKinds.progress, AgentTaskEventKinds.running, AgentTaskEventKinds.waitingResponse])
    guard workspace.status == .waitingResponse,
          let last = workspace.eventJournal.last(where: { relevant.contains($0.kind) }) else { return false }
    return recovery.contains(last.kind)
  }

  static func resolve(workspace: Snapshot, latest: AgentTranscriptEntry?, unread: Bool)
    -> GalaxySSIConversationExecutionStatus {
    if workspace.canReconcileDeliveredReply, let latest, hasDeliveredReply(workspace: workspace, reply: latest) {
      return unread ? .completeUnread : .read
    }
    return resolve(phase: workspace.phase, latest: latest, unread: unread, recovering: workspace.recovering)
  }

  private static func hasDeliveredReply(workspace: Snapshot, reply: AgentTranscriptEntry) -> Bool {
    guard !workspace.cancellationRequested, AgentTaskTerminalReplyPolicy.isTerminalReply(reply),
          !AgentTranscriptRenderPolicy.isLiveStream(reply),
          !reply.conversationId.isEmpty, reply.conversationId == workspace.conversationID,
          reply.timestampMillis >= workspace.createdAt,
          workspace.latestResumeAt.map({ $0 <= reply.timestampMillis }) ?? true else { return false }
    let sameTask = !reply.taskId.isEmpty ? reply.taskId == workspace.taskID :
      (!reply.turnId.isEmpty && (reply.turnId == workspace.workspaceID || reply.turnId == workspace.taskID))
    let canonicalTurnFinal = !reply.turnId.isEmpty && reply.turnId == workspace.workspaceID &&
      reply.turnId == workspace.taskID && reply.dedupeKey == AgentFinalResponseIdentity.dedupeKey(turnId: reply.turnId)
    return sameTask || canonicalTurnFinal
  }

  private static func phase(_ status: AgentWorkspaceStatus) -> AgentPhase {
    switch status {
    case .created, .queued: return .planning
    case .running: return .executing
    case .waitingResponse: return .waitingResponse
    case .waitingConfirmation: return .waitingConfirmation
    case .paused: return .paused
    case .blocked: return .blocked
    case .failed: return .failed
    case .cancelled: return .cancelled
    case .completed: return .completed
    }
  }

  static func task(conversationID: String, latest: AgentTranscriptEntry?, tasks: [AgentTaskRecord]) -> AgentTaskRecord? {
    tasks.filter { task in
      guard task.sessionId == conversationID else { return false }
      guard let latest else { return true }
      guard latest.conversationId.isEmpty || latest.conversationId == conversationID else { return false }
      if !latest.taskId.isEmpty { return task.taskId == latest.taskId }
      return latest.turnId.isEmpty || task.taskId == latest.turnId
    }.max {
      if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
      return $0.updatedAtMillis < $1.updatedAtMillis
    }
  }

  static func resolve(phase: AgentPhase?, latest: AgentTranscriptEntry?, unread: Bool,
                      recovering: Bool = false) -> GalaxySSIConversationExecutionStatus {
    let finalReply = latest.map {
      $0.role == .assistant && !AgentTranscriptRenderPolicy.isLiveStream($0) &&
        !$0.dedupeKey.hasPrefix("approval:") && !$0.dedupeKey.hasPrefix("remote-approval:")
    } ?? false
    switch phase {
    case .observing, .planning: return .queued
    case .executing, .verifying: return .running
    case .waitingResponse: return recovering ? .reconnecting : .waitingResponse
    case .waitingConfirmation: return .waitingConfirmation
    case .paused: return .paused
    case .blocked: return .blocked
    case .failed: return .failed
    case .cancelled: return .cancelled
    case .completed: return finalReply ? (unread ? .completeUnread : .read) : .delivering
    case nil:
      if latest?.role == .user { return .waitingResponse }
      return finalReply && unread ? .completeUnread : .read
    }
  }
}

enum GalaxySSIConversationHubTab: String, CaseIterable, Identifiable {
  case conversations
  case contacts

  var id: String { rawValue }
}

enum GalaxySSIConversationHubBackAction: Equatable {
  case closeSearch
  case showConversations
  case dismiss
}

enum GalaxySSIConversationHubBackPolicy {
  static func action(
    searchExpanded: Bool,
    tab: GalaxySSIConversationHubTab,
    archived: Bool
  ) -> GalaxySSIConversationHubBackAction {
    if searchExpanded { return .closeSearch }
    if archived || tab == .contacts { return .showConversations }
    return .dismiss
  }
}

enum GalaxySSIConversationHubScrollPolicy {
  static func anchorId(positions: [String: CGFloat]) -> String? {
    let partiallyVisible = positions.filter { $0.value < 0 }
    if let nearestAboveTop = partiallyVisible.max(by: { left, right in
      left.value == right.value ? left.key < right.key : left.value < right.value
    }) {
      return nearestAboveTop.key
    }
    return positions.min(by: { left, right in
      left.value == right.value ? left.key < right.key : left.value < right.value
    })?.key
  }

  static func agentConversationId(from anchorId: String) -> String? {
    let prefix = "conversation:\(GalaxySSIConversationHubItemKind.agent.rawValue):"
    guard anchorId.hasPrefix(prefix) else { return nil }
    let conversationId = String(anchorId.dropFirst(prefix.count))
    return conversationId.isEmpty ? nil : conversationId
  }

  static func restoredContentOffsetY(
    alignedContentOffsetY: CGFloat,
    savedRowOffset: CGFloat,
    minimumContentOffsetY: CGFloat,
    maximumContentOffsetY: CGFloat
  ) -> CGFloat {
    min(
      max(alignedContentOffsetY - savedRowOffset, minimumContentOffsetY),
      maximumContentOffsetY
    )
  }
}

struct GalaxySSIConversationHubSections {
  var pinned: [GalaxySSIConversationHubItem]
  var recent: [GalaxySSIConversationHubItem]
}

enum GalaxySSIConversationHubItemKind: String, Equatable {
  case agent
  case contact
}

struct GalaxySSIConversationHubContactSummary: Equatable {
  var contactId: String
  var title: String
  var preview: String
  var updatedAt: Date
  var pinned: Bool = false
  var unreadCount: Int = 0
}

struct GalaxySSIConversationHubItem: Identifiable, Equatable {
  var id: String
  var kind: GalaxySSIConversationHubItemKind
  var title: String
  var subtitle: String
  var preview: String
  var updatedAt: Date
  var pinned: Bool
  var archived: Bool
  var searchableMetadata: String
  var unreadCount: Int = 0
}

enum GalaxySSIConversationHubContactHistoryPolicy {
  static func includes(_ contact: GalaxySSIContact?) -> Bool {
    !ScannedAgentConversationPolicy.opensAgentConversation(contact)
  }
}

enum GalaxySSIConversationHubModels {
  static func contactSummaries(
    contacts: [GalaxySSIContact],
    summary: (String) -> ContactConversationSummary,
    isPinned: (String) -> Bool
  ) -> [GalaxySSIConversationHubContactSummary] {
    contacts.compactMap { contact in
      guard GalaxySSIConversationHubContactHistoryPolicy.includes(contact) else { return nil }
      let conversation = summary(contact.id)
      guard let latest = conversation.lastMessage else { return nil }
      return GalaxySSIConversationHubContactSummary(
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
    let fallbackTitle = GalaxySSILocalization.string(
      "galaxyssi.agent_session.new",
      fallback: "New session",
      language: language
    )
    let rawTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = rawTitle == "New session" ? fallbackTitle : rawTitle.ifBlank(session.id)
    let sourceTitle = session.createdByAgent
      ? String(
        format: GalaxySSILocalization.string(
          "galaxyssi.agent_session.created_by_agent",
          fallback: "GalaxySSI · %@",
          language: language
        ),
        title
      )
      : title
    if !session.mergedIntoConversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return sourceTitle + " · " + GalaxySSILocalization.string(
        "galaxyssi.agent_session.merged",
        fallback: "Merged",
        language: language
      )
    }
    if session.trackingPaused {
      return sourceTitle + " · " + GalaxySSILocalization.string(
        "galaxyssi.agent_session.tracking_paused",
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
  ) -> GalaxySSIConversationHubSections {
    unifiedConversations(
      agents: source.map { conversation in
        GalaxySSIConversationHubItem(
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
    agents: [GalaxySSIConversationHubItem],
    contacts: [GalaxySSIConversationHubContactSummary],
    query: String,
    archived: Bool
  ) -> GalaxySSIConversationHubSections {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let contactItems = archived ? [] : contacts.map { contact in
      GalaxySSIConversationHubItem(
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
      ? GalaxySSIConversationHubSections(pinned: [], recent: matching)
      : GalaxySSIConversationHubSections(
        pinned: matching.filter(\.pinned),
        recent: matching.filter { !$0.pinned }
      )
  }

  static func contacts(_ source: [GalaxySSIContact], query: String) -> [GalaxySSIContact] {
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

enum GalaxySSIFriendRequestPresentationPolicy {
  static func isAdded(_ request: GalaxySSIFriendRequest, contactIsVerified: Bool) -> Bool {
    request.status == .approved || contactIsVerified
  }

  static func isVisible(_ request: GalaxySSIFriendRequest, contactIsVerified: Bool) -> Bool {
    if request.status == .pending { return true }
    return request.direction == .outgoing && isAdded(request, contactIsVerified: contactIsVerified)
  }
}

enum GalaxySSIFriendRequestUnreadPolicy {
  static func isReadForPendingRequest(
    previous: GalaxySSIFriendRequest?,
    direction: GalaxySSIFriendRequestDirection
  ) -> Bool {
    if direction == .outgoing { return true }
    guard let previous, previous.status == .pending else { return false }
    return previous.isRead
  }

  static func unreadCount(_ requests: [GalaxySSIFriendRequest]) -> Int {
    requests.filter {
      $0.status == .pending && $0.direction == .incoming && !$0.isRead
    }.count
  }
}

enum GalaxySSIConnectorControlMessagePolicy {
  private static let silentControlTypes: Set<String> = [
    "connector_status",
    "desktop_control_authorizations",
    "desktop_control_authorization_changed",
    "desktop_executor_event",
    "desktop_action_receipt"
  ]

  static func isSilentStatus(type: String) -> Bool {
    silentControlTypes.contains(type)
  }
}

enum GalaxySSIPairingConfirmationDeliveryPolicy {
  static func messageId(suppliedId: String, desktopId: String, clientRouteId: String) -> String {
    suppliedId.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("pairing-confirmed:\(desktopId):\(clientRouteId)")
  }

  static func needsSessionBootstrap(hasExistingSession: Bool, routePaired: Bool = true) -> Bool {
    !hasExistingSession || !routePaired
  }

  static func isFirstDelivery(_ stage: IncomingStageResult) -> Bool {
    stage == .staged
  }
}
