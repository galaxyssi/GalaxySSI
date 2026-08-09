import SwiftUI

struct AgentSessionMetrics: Equatable {
  var turnCount: Int
  var messageCount: Int
  var taskCount: Int
  var estimatedContextTokens: Int
  var inputTokens: Int64
  var outputTokens: Int64
  var costMicros: Int64
  var lastResponseLatencyMillis: Int64
}

struct SignalASIAgentSessionsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var searchText = ""
  @State private var showArchived = false
  @State private var editDraft: AgentSessionEditDraft?
  @State private var contextSession: AgentConversation?
  @State private var detailsSession: AgentConversation?
  @State private var deletingSession: AgentConversation?
  @State private var mergingSession: AgentConversation?
  @State private var multiDeleteMode = false
  @State private var selectedSessionIDs: Set<String> = []
  @State private var bulkDeletePresented = false
  @State private var statusText = ""

  private var visibleSessions: [AgentConversation] {
    let sessions = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? store.agentSessions(includeArchived: true)
      : store.searchAgentSessions(searchText, includeArchived: true)
    return sessions.filter { showArchived ? $0.status == .archived : $0.status == .active }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.agent_sessions.title", "Sessions"),
        leading: { SignalASIBackButton() },
        trailing: {
          Button {
            createSession()
          } label: {
            Image(systemName: "plus")
              .font(.system(size: 21, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
          }
        }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AgentSessionHeroView(
            title: t("signalasi.agent_sessions.hero_title", "Agent sessions"),
            subtitle: t("signalasi.agent_sessions.hero_subtitle", "Switch, archive, rename, pin, and inspect Agent conversations"),
            badge: String(
              format: t("signalasi.agent_sessions.badge", "%d sessions"),
              store.agentSessions(includeArchived: true).count
            )
          )

          VStack(spacing: 8) {
            AgentSessionSearchRow(
              searchText: $searchText,
              placeholder: t("signalasi.agent_session.search", "Search sessions")
            )
            Picker("", selection: $showArchived) {
              Text(t("signalasi.agent_sessions.active", "Active")).tag(false)
              Text(t("signalasi.agent_session.archived", "Archived")).tag(true)
            }
            .pickerStyle(.segmented)
          }

          if !statusText.isEmpty {
            Text(statusText)
              .font(.system(size: 12))
              .foregroundColor(.signalASITextSecondary)
              .padding(.horizontal, 4)
          }

          if multiDeleteMode {
            bulkDeleteToolbar
          }

          AgentSessionActionRow(
            title: t("signalasi.agent_session.new", "New session"),
            subtitle: t("signalasi.agent_sessions.new_subtitle", "Start a fresh Agent context for the next request"),
            systemImage: "plus.circle",
            tint: .signalASIAccent,
            badge: "+"
          ) {
            createSession()
          }

          if !showArchived {
            AgentSessionActionRow(
              title: t("signalasi.agent_session.archived", "Archived sessions"),
              subtitle: String(
                format: t("signalasi.agent_sessions.archived_count", "%d archived"),
                store.agentSessions(includeArchived: true).filter { $0.status == .archived }.count
              ),
              systemImage: "archivebox",
              tint: .blue,
              badge: t("signalasi.common.view", "View")
            ) {
              showArchived = true
            }
          }

          ForEach(groupedSessions, id: \.title) { group in
            sectionTitle(group.title)
            VStack(spacing: 8) {
              ForEach(group.sessions) { session in
                AgentSessionRow(
                  session: session,
                  selected: !multiDeleteMode && session.id == store.activeAgentConversationId,
                  selectionMode: multiDeleteMode,
                  marked: selectedSessionIDs.contains(session.id),
                  metrics: store.agentSessionMetrics(session.id),
                  subtitle: sessionSubtitle(session),
                  badge: rowBadge(session),
                  onOpen: {
                    if multiDeleteMode {
                      toggleSelectedSession(session.id)
                    } else {
                      selectSession(session)
                    }
                  },
                  actions: {
                    sessionMenu(session)
                  }
                )
              }
            }
          }

          if visibleSessions.isEmpty {
            AgentSessionActionRow(
              title: t("signalasi.agent_session.no_results", "No matching sessions"),
              subtitle: showArchived
                ? t("signalasi.agent_sessions.no_archived_subtitle", "Archived conversations will appear here")
                : t("signalasi.agent_sessions.no_active_subtitle", "Create a session or send a message to an Agent"),
              systemImage: "clock.arrow.circlepath",
              tint: .signalASIAccent,
              badge: ""
            ) {}
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(item: $editDraft) { draft in
      AgentSessionTextEditSheet(
        title: draft.sheetTitle,
        initialText: draft.text,
        multiline: draft.mode == .summary
      ) { value in
        saveDraft(draft, value: value)
      }
    }
    .sheet(item: $contextSession) { session in
      AgentSessionContextPolicySheet(
        session: session,
        selectedPolicy: session.contextPolicy,
        onSelect: { policy in
          if store.setAgentSessionContextPolicy(id: session.id, policy: policy) {
            statusText = t("signalasi.agent_sessions.context_updated", "Context policy updated")
          }
          contextSession = nil
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
    }
    .alert(t("signalasi.agent_session.delete", "Delete session"), isPresented: deleteAlertPresented) {
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        deletingSession = nil
      }
      Button(t("signalasi.common.delete", "Delete"), role: .destructive) {
        confirmDelete()
      }
    } message: {
      Text(t("signalasi.agent_session.delete_confirm", "Delete this session and all of its messages?"))
    }
    .alert(t("signalasi.agent_session.merge_into_original", "Merge into original session"), isPresented: mergeAlertPresented) {
      Button(t("signalasi.common.cancel", "Cancel"), role: .cancel) {
        mergingSession = nil
      }
      Button(t("signalasi.agent_session.merge_confirm_action", "Merge"), role: .destructive) {
        confirmMerge()
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
    .onChange(of: showArchived) { _ in
      selectedSessionIDs.removeAll()
    }
  }

  private var groupedSessions: [(title: String, sessions: [AgentConversation])] {
    let sessions = visibleSessions
    guard !sessions.isEmpty else { return [] }
    if showArchived {
      return [(t("signalasi.agent_session.archived", "Archived sessions"), sessions)]
    }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
    return [
      (t("signalasi.agent_session.today", "Today"), sessions.filter { date($0.updatedAt) >= today }),
      (t("signalasi.agent_session.yesterday", "Yesterday"), sessions.filter { date($0.updatedAt) >= yesterday && date($0.updatedAt) < today }),
      (t("signalasi.agent_session.earlier", "Earlier"), sessions.filter { date($0.updatedAt) < yesterday })
    ].filter { !$0.sessions.isEmpty }
  }

  private var deleteAlertPresented: Binding<Bool> {
    Binding(
      get: { deletingSession != nil },
      set: { value in
        if !value {
          deletingSession = nil
        }
      }
    )
  }

  private var mergeAlertPresented: Binding<Bool> {
    Binding(
      get: { mergingSession != nil },
      set: { value in
        if !value {
          mergingSession = nil
        }
      }
    )
  }

  private var bulkDeleteToolbar: some View {
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
        let visibleIDs = Set(visibleSessions.map(\.id))
        selectedSessionIDs = selectedSessionIDs == visibleIDs ? [] : visibleIDs
      } label: {
        Label(
          selectedSessionIDs == Set(visibleSessions.map(\.id))
            ? t("signalasi.agent_sessions.clear_selection", "Clear")
            : t("signalasi.agent_sessions.select_all", "Select all"),
          systemImage: "checklist"
        )
        .font(.system(size: 12, weight: .semibold))
      }
      .buttonStyle(.bordered)
      Button {
        bulkDeletePresented = true
      } label: {
        Label(t("signalasi.common.delete", "Delete"), systemImage: "trash")
          .font(.system(size: 12, weight: .semibold))
      }
      .buttonStyle(.bordered)
      .tint(.red)
      .disabled(selectedSessionIDs.isEmpty)
      Button {
        multiDeleteMode = false
        selectedSessionIDs.removeAll()
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 14, weight: .bold))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("signalasi.common.cancel", "Cancel")))
    }
    .padding(.horizontal, 4)
  }

  @ViewBuilder
  private func sessionMenu(_ session: AgentConversation) -> some View {
    Menu {
      Button(t("signalasi.agent_sessions.select", "Select session")) {
        selectSession(session)
      }
      Button(t("signalasi.agent_session.rename", "Rename")) {
        editDraft = AgentSessionEditDraft(
          id: session.id,
          mode: .rename,
          sheetTitle: t("signalasi.agent_session.rename", "Rename"),
          text: session.title
        )
      }
      Button(session.pinned ? t("signalasi.agent_session.unpin", "Unpin") : t("signalasi.agent_session.pin", "Pin")) {
        _ = store.setAgentSessionPinned(id: session.id, pinned: !session.pinned)
      }
      if canMerge(session) {
        Button(t("signalasi.agent_session.merge_into_original", "Merge into original session")) {
          mergingSession = session
        }
      }
      if session.mergedIntoConversationId.isBlank {
        Button(session.privateMode ? t("signalasi.agent_session.standard", "Standard session") : t("signalasi.agent_session.private", "Private session")) {
          _ = store.setAgentSessionPrivateMode(id: session.id, privateMode: !session.privateMode)
        }
        Button(session.trackingPaused ? t("signalasi.agent_session.resume_tracking", "Resume global tracking") : t("signalasi.agent_session.pause_tracking", "Pause global tracking")) {
          _ = store.setAgentSessionTrackingPaused(id: session.id, paused: !session.trackingPaused)
        }
      }
      Button(t("signalasi.agent_session.context_policy", "Context policy")) {
        contextSession = session
      }
      Button(t("signalasi.agent_session.summary", "View or edit summary")) {
        editDraft = AgentSessionEditDraft(
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
        beginMultiDelete()
      }
      if session.mergedIntoConversationId.isBlank {
        Button(session.status == .archived ? t("signalasi.agent_session.restore", "Restore session") : t("signalasi.agent_session.archive", "Archive")) {
          if session.status == .archived {
            _ = store.restoreAgentSession(id: session.id)
            showArchived = false
          } else {
            _ = store.archiveAgentSession(id: session.id)
          }
        }
      }
      Button(t("signalasi.agent_session.delete", "Delete session"), role: .destructive) {
        deletingSession = session
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(.signalASITextSecondary)
        .frame(width: 36, height: 36)
    }
  }

  private func createSession() {
    multiDeleteMode = false
    selectedSessionIDs.removeAll()
    let session = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
    statusText = String(format: t("signalasi.agent_sessions.created", "Selected %@"), session.title)
    showArchived = false
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

  private func confirmMerge() {
    guard let session = mergingSession else { return }
    let result = store.mergeAgentSessionIntoParent(id: session.id)
    mergingSession = nil
    guard result.merged else {
      statusText = mergeFailureMessage(result.failure)
      return
    }
    let targetTitle = result.targetConversation?.title.ifBlank(
      t("signalasi.agent_session.new", "New session")
    ) ?? t("signalasi.agent_session.new", "New session")
    statusText = String(
      format: t("signalasi.agent_sessions.merge_success", "Merged %d messages into %@"),
      result.copiedEntryCount,
      targetTitle
    )
    showArchived = false
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

  private func beginMultiDelete() {
    multiDeleteMode = true
    selectedSessionIDs.removeAll()
  }

  private func toggleSelectedSession(_ sessionId: String) {
    if selectedSessionIDs.contains(sessionId) {
      selectedSessionIDs.remove(sessionId)
    } else {
      selectedSessionIDs.insert(sessionId)
    }
  }

  private func confirmBulkDelete() {
    let sessions = visibleSessions.filter { selectedSessionIDs.contains($0.id) }
    guard !sessions.isEmpty else { return }
    let cleanupRequests: [(conversationId: String, taskIds: [String])] = sessions
      .filter { $0.mergedIntoConversationId.isBlank }
      .map { session in
        (
          conversationId: session.id,
          taskIds: store.agentTasks(forSession: session.id, limit: 256).map(\.taskId)
        )
      }
    let deletedCount = sessions.reduce(into: 0) { count, session in
      if store.deleteAgentSession(id: session.id) {
        count += 1
      }
    }
    multiDeleteMode = false
    selectedSessionIDs.removeAll()
    bulkDeletePresented = false
    guard deletedCount > 0 else {
      statusText = t("signalasi.agent_sessions.delete_failed", "Session was not deleted")
      return
    }
    guard !cleanupRequests.isEmpty else {
      statusText = String(
        format: t("signalasi.agent_sessions.deleted_selected", "%d sessions deleted"),
        deletedCount
      )
      return
    }
    statusText = String(
      format: t(
        "signalasi.agent_sessions.deleted_selected_pending",
        "%d sessions deleted; cleaning up the paired Desktop..."
      ),
      deletedCount
    )
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
      statusText = failed == 0
        ? t("signalasi.agent_sessions.deleted_selected_sent", "Selected sessions deleted and remote cleanup sent")
        : t("signalasi.agent_sessions.deleted_selected_failed", "Sessions deleted; some remote cleanup requests failed")
    }
  }

  private func selectSession(_ session: AgentConversation) {
    if store.switchAgentSession(session.id) {
      statusText = String(format: t("signalasi.agent_sessions.selected", "Selected %@"), session.title)
      showArchived = false
    }
  }

  private func saveDraft(_ draft: AgentSessionEditDraft, value: String) {
    let changed: Bool
    switch draft.mode {
    case .rename:
      changed = store.renameAgentSession(id: draft.id, title: value)
    case .summary:
      changed = store.updateAgentSessionSummary(id: draft.id, summary: value)
    }
    statusText = changed
      ? t("signalasi.agent_sessions.updated", "Session updated")
      : t("signalasi.agent_sessions.update_failed", "Session was not changed")
  }

  private func confirmDelete() {
    guard let session = deletingSession else { return }
    let shouldNotifyRemote = session.mergedIntoConversationId.isBlank
    let taskIds = shouldNotifyRemote
      ? store.agentTasks(forSession: session.id, limit: 256).map(\.taskId)
      : []
    let deleted = store.deleteAgentSession(id: session.id)
    if deleted && shouldNotifyRemote {
      statusText = t(
        "signalasi.agent_sessions.deleted_remote_pending",
        "Session deleted; cleaning up the paired Desktop..."
      )
      Task { @MainActor in
        let sent = await coordinator.publishRemoteAgentConversationDelete(
          conversationId: session.id,
          taskIds: taskIds
        )
        statusText = sent
          ? t("signalasi.agent_sessions.deleted_remote_sent", "Remote cleanup request sent")
          : t("signalasi.agent_sessions.deleted_remote_failed", "Session deleted; remote cleanup could not be sent")
      }
    } else {
      statusText = deleted
        ? t("signalasi.agent_sessions.deleted", "Session deleted")
        : t("signalasi.agent_sessions.delete_failed", "Session was not deleted")
    }
    deletingSession = nil
  }

  private func sessionSubtitle(_ session: AgentConversation) -> String {
    let metrics = store.agentSessionMetrics(session.id)
    return String(
      format: t("signalasi.agent_session.message_count", "%@ / %d messages / %@"),
      session.selectedModelOrAgent,
      metrics.messageCount,
      listTime(session.updatedAt)
    )
  }

  private func rowBadge(_ session: AgentConversation) -> String {
    if !session.mergedIntoConversationId.isBlank {
      return t("signalasi.agent_session.merged", "Merged")
    }
    if session.trackingPaused {
      return t("signalasi.agent_session.tracking_paused", "Tracking paused")
    }
    if session.privateMode {
      return t("signalasi.agent_session.private", "Private session")
    }
    if session.id == store.activeAgentConversationId {
      return t("signalasi.agent_sessions.selected_badge", "Selected")
    }
    return ""
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func date(_ millis: Int64) -> Date {
    Date(timeIntervalSince1970: Double(max(millis, 0)) / 1_000)
  }

  private func listTime(_ millis: Int64) -> String {
    guard millis > 0 else { return "-" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date(millis))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private enum AgentSessionEditMode {
  case rename
  case summary
}

private struct AgentSessionEditDraft: Identifiable {
  var id: String
  var mode: AgentSessionEditMode
  var sheetTitle: String
  var text: String
}

private struct AgentSessionHeroView: View {
  var title: String
  var subtitle: String
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.signalASIAccent.opacity(0.14))
        Image(systemName: "clock.arrow.circlepath")
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(.signalASIAccent)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.signalASIAccent)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.signalASIAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct AgentSessionSearchRow: View {
  @Binding var searchText: String
  var placeholder: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      TextField(placeholder, text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
    .background(Color.signalASISearchBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentSessionRow<Actions: View>: View {
  var session: AgentConversation
  var selected: Bool
  var selectionMode: Bool
  var marked: Bool
  var metrics: AgentSessionMetrics
  var subtitle: String
  var badge: String
  var onOpen: () -> Void
  let actions: Actions

  init(
    session: AgentConversation,
    selected: Bool,
    selectionMode: Bool,
    marked: Bool,
    metrics: AgentSessionMetrics,
    subtitle: String,
    badge: String,
    onOpen: @escaping () -> Void,
    @ViewBuilder actions: () -> Actions
  ) {
    self.session = session
    self.selected = selected
    self.selectionMode = selectionMode
    self.marked = marked
    self.metrics = metrics
    self.subtitle = subtitle
    self.badge = badge
    self.onOpen = onOpen
    self.actions = actions()
  }

  var body: some View {
    HStack(spacing: 10) {
      Button(action: onOpen) {
        HStack(spacing: 12) {
          ZStack {
            if selectionMode {
              Image(systemName: marked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(marked ? .signalASIAccent : .signalASITextSecondary)
            } else {
              Circle()
                .fill(selected ? Color.signalASIAccent : Color.blue)
              if session.pinned {
                Image(systemName: "pin.fill")
                  .font(.system(size: 9, weight: .bold))
                  .foregroundColor(.white)
              }
            }
          }
          .frame(width: 14, height: 14)
          VStack(alignment: .leading, spacing: 4) {
            Text(session.title.ifBlank(session.id))
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .lineLimit(2)
            Text(subtitle)
              .font(.system(size: 12))
              .foregroundColor(.signalASITextSecondary)
              .lineLimit(2)
          }
          Spacer(minLength: 8)
          VStack(alignment: .trailing, spacing: 4) {
            Text("\(metrics.turnCount)")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .monospacedDigit()
            Text(badge.ifBlank(" "))
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(selected ? .signalASIAccent : .signalASITextSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          .frame(minWidth: 54, alignment: .trailing)
        }
      }
      .buttonStyle(.plain)
      actions
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentSessionActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.14))
          Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 44, height: 44)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(3)
        }
        Spacer(minLength: 8)
        if !badge.isEmpty {
          Text(badge)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

private struct AgentSessionTextEditSheet: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  var title: String
  var initialText: String
  var multiline: Bool
  var onSave: (String) -> Void
  @State private var text: String

  init(title: String, initialText: String, multiline: Bool, onSave: @escaping (String) -> Void) {
    self.title = title
    self.initialText = initialText
    self.multiline = multiline
    self.onSave = onSave
    _text = State(initialValue: initialText)
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 12) {
        if multiline {
          TextEditor(text: $text)
            .frame(minHeight: 180)
            .padding(8)
            .background(Color.signalASISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
          TextField(title, text: $text)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color.signalASISearchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("signalasi.common.cancel", "Cancel")) { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(t("signalasi.common.done", "Done")) {
            onSave(text)
            dismiss()
          }
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentSessionContextPolicySheet: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  var session: AgentConversation
  var selectedPolicy: String
  var onSelect: (String) -> Void

  private let policies = ["minimal", "balanced", "extended"]

  var body: some View {
    NavigationView {
      VStack(spacing: 8) {
        ForEach(policies, id: \.self) { policy in
          Button {
            onSelect(policy)
            dismiss()
          } label: {
            HStack {
              Text(policyTitle(policy))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.signalASITextPrimary)
              Spacer()
              if policy == selectedPolicy {
                Image(systemName: "checkmark")
                  .foregroundColor(.signalASIAccent)
              }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(Color.signalASISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationTitle(t("signalasi.agent_session.context_policy", "Context policy"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("signalasi.common.cancel", "Cancel")) { dismiss() }
        }
      }
    }
  }

  private func policyTitle(_ value: String) -> String {
    switch value {
    case "minimal":
      return t("signalasi.agent_session.context_minimal", "Minimal / 16K token window")
    case "extended":
      return t("signalasi.agent_session.context_extended", "Extended / 64K token window")
    default:
      return t("signalasi.agent_session.context_balanced", "Balanced / 32K token window")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentSessionDetailsSheet: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  var session: AgentConversation
  var metrics: AgentSessionMetrics
  var messages: [ChatMessage]

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AgentSessionActionRow(
            title: session.title.ifBlank(t("signalasi.agent_session.details", "Session details")),
            subtitle: session.summary.ifBlank(t("signalasi.agent_session.summary_empty", "No summary yet")),
            systemImage: "clock.arrow.circlepath",
            tint: .signalASIAccent,
            badge: session.privateMode ? t("signalasi.agent_session.private", "Private session") : t("signalasi.agent_session.standard", "Standard session")
          ) {}

          detailRow(t("signalasi.agent_session.turns", "Turns"), "\(metrics.turnCount)")
          detailRow(t("signalasi.agent_session.message_total", "Messages"), "\(metrics.messageCount)")
          detailRow(t("signalasi.agent_session.tasks", "Tasks"), "\(metrics.taskCount)")
          detailRow(t("signalasi.agent_session.context_tokens", "Estimated context tokens"), "\(metrics.estimatedContextTokens)")
          detailRow(t("signalasi.agent_session.input_tokens", "Cloud input tokens"), metrics.inputTokens > 0 ? "\(metrics.inputTokens)" : "-")
          detailRow(t("signalasi.agent_session.output_tokens", "Cloud output tokens"), metrics.outputTokens > 0 ? "\(metrics.outputTokens)" : "-")
          detailRow(
            t("signalasi.agent_session.latency", "Last response latency"),
            metrics.lastResponseLatencyMillis > 0
              ? String(format: "%.1fs", Double(metrics.lastResponseLatencyMillis) / 1_000)
              : "-"
          )
          detailRow(
            t("signalasi.agent_session.cost", "Reported cost"),
            metrics.costMicros > 0
              ? String(format: "$%.6f", Double(metrics.costMicros) / 1_000_000)
              : t("signalasi.agent_session.cost_unavailable", "Unavailable for mixed/local routes")
          )

          Text(t("signalasi.agent_session.recent_context", "Model context preview"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.signalASITextSecondary)
            .padding(.horizontal, 4)
            .padding(.top, 2)

          if messages.isEmpty {
            detailRow(t("signalasi.agent_session.context_preview", "Context"), t("signalasi.agent_session.summary_empty", "No summary yet"))
          } else {
            ForEach(messages) { message in
              detailRow(message.isMine ? "Me" : message.contactId, message.content)
            }
          }
        }
        .padding(12)
      }
      .background(Color.signalASIPageBackground.ignoresSafeArea())
      .navigationTitle(t("signalasi.agent_session.details", "Session details"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("signalasi.common.done", "Done")) { dismiss() }
        }
      }
    }
  }

  private func detailRow(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      Text(value.ifBlank("-"))
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
