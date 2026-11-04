import SwiftUI

struct GalaxySSICollaborationRecallView: View {
  let conversationId: String
  let t: (String, String) -> String
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var query = ""
  @State private var submittedQuery = ""
  @State private var snapshots: [AgentTeamExecutionSnapshot] = []
  @State private var loading = true

  var body: some View {
    NavigationView {
      List {
        if loading {
          ProgressView()
        } else if snapshots.isEmpty {
          Text(t("galaxyssi.collaboration.history_empty", "No matching group records."))
            .foregroundColor(.secondary)
        }
        ForEach(snapshots, id: \.supervisorRunId) { snapshot in
          NavigationLink {
            GalaxySSIAgentTeamDetailView(snapshot: snapshot)
          } label: {
            Text(snapshot.goal.ifBlank(snapshot.teamId)).lineLimit(2)
          }
        }
      }
      .navigationTitle(t("galaxyssi.collaboration.history", "Search Group History"))
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $query, prompt: t("galaxyssi.collaboration.history_search", "Search past results"))
      .onSubmit(of: .search) { submittedQuery = String(query.prefix(250)) }
      .onChange(of: query) { if $0.isEmpty { submittedQuery = "" } }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.close", "Close")) { dismiss() }
        }
      }
      .task(id: submittedQuery) {
        guard allowed else { snapshots = []; loading = false; return }
        loading = true
        let id = conversationId
        let text = submittedQuery
        let result = await Task.detached(priority: .userInitiated) {
          AgentTeamExecutionHistoryStore.shared.recallCollaborationResults(
            conversationId: id, excludingTurnId: "", query: text, limit: 50)
        }.value
        guard !Task.isCancelled, allowed else { return }
        snapshots = result
        loading = false
      }
      .onChange(of: allowed) { if !$0 { snapshots = []; dismiss() } }
    }
    .navigationViewStyle(.stack)
  }

  private var allowed: Bool {
    guard let session = store.agentSession(id: conversationId), session.id == conversationId else { return false }
    return session.collaborationRoster != nil && session.mergedIntoConversationId.isBlank &&
      !session.privateMode && !session.trackingPaused
  }
}

struct GalaxySSICollaborationTeamPanel: View {
  let session: AgentConversation
  let roster: AgentCollaborationRoster
  let t: (String, String) -> String
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @State private var snapshot: AgentTeamExecutionSnapshot?
  @State private var expanded = false
  @State private var settingsPresented = false
  @State private var historyPresented = false
  @State private var refreshRevision = 0

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      LazyVStack(alignment: .leading, spacing: 8) {
        if let snapshot {
          ForEach(snapshot.members.filter { $0.deliveryMode != .ignore }, id: \.memberId) { member in
            VStack(alignment: .leading, spacing: 3) {
              Text((member.displayName ?? "").ifBlank(member.agentId)).font(.subheadline.weight(.semibold))
              if !member.role.isBlank { Text(member.role).font(.footnote) }
              Text(GalaxySSIAgentTeamPresentation.memberStatusLabel(member.status, language: language))
                .font(.footnote).foregroundColor(.secondary)
              if !member.errorMessage.isBlank {
                Text(member.errorMessage).font(.footnote).foregroundColor(.secondary).lineLimit(2)
              }
            }
            .accessibilityElement(children: .combine)
          }
        } else {
          ForEach(roster.members) { member in
            VStack(alignment: .leading, spacing: 3) {
              Text(member.name).font(.subheadline.weight(.semibold))
              if !member.role.isBlank { Text(member.role).font(.footnote).foregroundColor(.secondary) }
            }
          }
        }
        GalaxySSICollaborationResultsButton(conversationId: session.id, t: t)
        Button { historyPresented = true } label: {
          Label(t("galaxyssi.collaboration.history", "Search Group History"), systemImage: "magnifyingglass")
            .frame(minHeight: 44)
        }
        Button { settingsPresented = true } label: {
          Label(t("galaxyssi.collaboration.settings", "Collaboration Members"), systemImage: "gearshape")
            .frame(minHeight: 44)
        }
      }
      .padding(.vertical, 8)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Label(t("galaxyssi.collaboration.settings", "Collaboration Members"), systemImage: "person.3")
          Text(roster.members.count, format: .number).monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        if let snapshot {
          Text(GalaxySSIAgentTeamPresentation.stateLabel(snapshot.state, language: language))
            .font(.footnote).foregroundColor(.secondary)
        }
      }
      .frame(minHeight: 44)
    }
    .task(id: refreshRevision) {
      let id = session.id
      let current = await Task.detached(priority: .userInitiated) {
        AgentTeamExecutionHistoryStore.shared.latestCollaborationRun(conversationId: id)
      }.value
      if !Task.isCancelled { snapshot = current }
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentTeamExecutionHistoryDidUpdate)
      .receive(on: RunLoop.main)) { notification in
      guard let runId = notification.object as? String else { refreshRevision &+= 1; return }
      if runId == snapshot?.supervisorRunId ||
          AgentTeamExecutionHistoryStore.shared.snapshot(supervisorRunId: runId)?.conversationId == session.id {
        refreshRevision &+= 1
      }
    }
    .sheet(isPresented: $settingsPresented) {
      AgentCollaborationRosterEditor(session: session, t: t)
    }
    .sheet(isPresented: $historyPresented) {
      GalaxySSICollaborationRecallView(conversationId: session.id, t: t)
    }
  }

}

private struct GalaxySSICollaborationResultsButton: View {
  let conversationId: String
  let t: (String, String) -> String
  @State private var presented = false

  var body: some View {
    Button {
      presented = true
    } label: {
      Label(t("galaxyssi.collaboration.results", "Member Results"), systemImage: "person.3")
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 44)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sheet(isPresented: $presented) {
      GalaxySSICollaborationResultsView(conversationId: conversationId, t: t)
    }
  }
}

private struct GalaxySSICollaborationResultsView: View {
  let conversationId: String
  let t: (String, String) -> String
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var snapshots: [AgentTeamExecutionSnapshot] = []
  @State private var limit = 20

  var body: some View {
    NavigationView {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          if snapshots.isEmpty {
            Text(t("galaxyssi.collaboration.no_results", "No member results yet."))
              .foregroundColor(.secondary)
          }
          ForEach(snapshots, id: \.supervisorRunId) { snapshot in
            DisclosureGroup {
              VStack(alignment: .leading, spacing: 16) {
                ForEach(snapshot.members.filter { $0.deliveryMode != .ignore }, id: \.memberId) { member in
                  memberResult(member, snapshot: snapshot)
                }
              }
              .padding(.vertical, 8)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.goal.ifBlank(t("galaxyssi.collaboration.results", "Member Results")))
                  .lineLimit(2)
                Text(GalaxySSIAgentTeamPresentation.stateLabel(snapshot.state, language: interfaceLanguage))
                  .font(.footnote).foregroundColor(.secondary)
              }
            }
          }
          if snapshots.count == limit && limit < AgentTeamExecutionHistoryStore.maxSnapshots {
            Button(t("galaxyssi.collaboration.older_results", "Older Results")) {
              limit += 20
              refresh()
            }
          }
        }
        .padding(16)
      }
      .navigationTitle(t("galaxyssi.collaboration.results", "Member Results"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.close", "Close")) { dismiss() }
        }
      }
    }
    .navigationViewStyle(.stack)
    .onAppear(perform: refresh)
    .onChange(of: store.activeAgentConversationId) { _ in refresh() }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentTeamExecutionHistoryDidUpdate)
      .receive(on: RunLoop.main)) { notification in
        if let runId = notification.object as? String,
           !snapshots.contains(where: { $0.supervisorRunId == runId }),
           AgentTeamExecutionHistoryStore.shared.snapshot(supervisorRunId: runId)?.conversationId != conversationId {
          return
        }
        refresh()
      }
  }

  private func refresh() {
    guard store.activeAgentConversationId == conversationId,
          let session = store.agentSession(id: conversationId), session.collaborationRoster != nil,
          !session.privateMode, !session.trackingPaused else {
      snapshots = []
      dismiss()
      return
    }
    snapshots = AgentTeamExecutionHistoryStore.shared.collaborationResults(conversationId: conversationId, limit: limit)
  }

  private func memberResult(_ member: AgentTeamMemberSnapshot, snapshot: AgentTeamExecutionSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text((member.displayName ?? "").ifBlank(member.agentId)).font(.subheadline.weight(.semibold))
      if !member.role.isBlank {
        Text(member.role).font(.footnote).foregroundColor(.secondary)
      }
      if member.status != .succeeded {
        Text(GalaxySSIAgentTeamPresentation.memberStatusLabel(member.status, language: interfaceLanguage))
          .font(.footnote).foregroundColor(.secondary)
      }
      if !member.errorMessage.isBlank {
        Text(member.errorMessage).foregroundColor(.red)
      }
      if member.deliveryMode == .observe && (!member.output.isBlank || !member.richOutputJson.isBlank) {
        GalaxySSIRichContentView(content: member.output, richOutputJson: member.richOutputJson,
          expansionStorageKey: "collaboration:\(snapshot.supervisorRunId):\(member.memberId)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }
}

enum GalaxySSIAgentTeamPresentation {
  static func stateLabel(_ state: AgentTeamExecutionState, language: String) -> String {
    let key: String
    let fallback: String
    switch state {
    case .queued:
      key = "galaxyssi.agent_team.state_queued"
      fallback = "Queued"
    case .created:
      key = "galaxyssi.agent_team.state_created"
      fallback = "Created"
    case .running:
      key = "galaxyssi.agent_team.state_running"
      fallback = "Running"
    case .waitingResponse:
      key = "galaxyssi.agent_team.state_waiting_response"
      fallback = "Waiting for response"
    case .succeeded:
      key = "galaxyssi.agent_team.state_succeeded"
      fallback = "Completed"
    case .completedWithFailures:
      key = "galaxyssi.agent_team.state_completed_with_failures"
      fallback = "Completed with failures"
    case .failed:
      key = "galaxyssi.agent_team.state_failed"
      fallback = "Failed"
    case .cancelled:
      key = "galaxyssi.agent_team.state_cancelled"
      fallback = "Cancelled"
    case .interrupted:
      key = "galaxyssi.agent_team.state_interrupted"
      fallback = "Interrupted"
    }
    return GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }

  static func memberStatusLabel(_ status: AgentSubagentStatus, language: String) -> String {
    let key: String
    let fallback: String
    switch status {
    case .pending:
      key = "galaxyssi.agent_team.member_pending"
      fallback = "Pending"
    case .queued:
      key = "galaxyssi.agent_team.state_queued"
      fallback = "Queued"
    case .running:
      key = "galaxyssi.agent_team.state_running"
      fallback = "Running"
    case .succeeded:
      key = "galaxyssi.agent_team.state_succeeded"
      fallback = "Completed"
    case .failed:
      key = "galaxyssi.agent_team.state_failed"
      fallback = "Failed"
    case .cancelled:
      key = "galaxyssi.agent_team.state_cancelled"
      fallback = "Cancelled"
    case .skipped:
      key = "galaxyssi.agent_team.member_skipped"
      fallback = "Skipped"
    case .interrupted:
      key = "galaxyssi.agent_team.state_interrupted"
      fallback = "Interrupted"
    }
    return GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }

  static func stateTint(_ state: AgentTeamExecutionState) -> Color {
    switch state {
    case .succeeded:
      return .galaxySSIAccent
    case .completedWithFailures, .waitingResponse, .interrupted:
      return .orange
    case .failed, .cancelled:
      return .red
    case .queued, .created, .running:
      return .blue
    }
  }

  static func memberCount(_ snapshot: AgentTeamExecutionSnapshot) -> Int {
    snapshot.members.filter { $0.deliveryMode != .ignore }.count
  }

  static func time(_ millis: Int64, language: String) -> String {
    guard millis > 0 else {
      return GalaxySSILocalization.string(
        "galaxyssi.agent_team.unknown_time",
        fallback: "Unknown time",
        language: language
      )
    }
    return GalaxySSISecurityFormatter.time(
      Date(timeIntervalSince1970: TimeInterval(millis) / 1_000),
      unknown: GalaxySSILocalization.string(
        "galaxyssi.agent_team.unknown_time",
        fallback: "Unknown time",
        language: language
      ),
      language: language
    )
  }
}

struct GalaxySSIAgentTeamSummaryRow: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var snapshot: AgentTeamExecutionSnapshot

  var body: some View {
    GalaxySSISecurityNavigationRow(
      title: snapshot.goal.ifBlank(snapshot.teamId),
      subtitle: String(
        format: t("galaxyssi.agent_team.summary", "%d members - %@"),
        GalaxySSIAgentTeamPresentation.memberCount(snapshot),
        GalaxySSIAgentTeamPresentation.stateLabel(snapshot.state, language: interfaceLanguage)
      ),
      systemImage: "person.3",
      tint: GalaxySSIAgentTeamPresentation.stateTint(snapshot.state),
      badge: GalaxySSIAgentTeamPresentation.stateLabel(snapshot.state, language: interfaceLanguage)
    ) {
      GalaxySSIAgentTeamDetailView(snapshot: snapshot)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIAgentTeamDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var snapshot: AgentTeamExecutionSnapshot
  @State private var messageDraft = ""
  @State private var selectedInstanceId = ""
  @State private var messageStatus = ""

  private var visibleMembers: [AgentTeamMemberSnapshot] {
    snapshot.members.filter { $0.deliveryMode != .ignore }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.agent_team.details_title", "Agent Team"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: snapshot.goal.ifBlank(t("galaxyssi.agent_team.details_title", "Agent Team")),
            subtitle: snapshot.teamId,
            systemImage: "person.3",
            tint: GalaxySSIAgentTeamPresentation.stateTint(snapshot.state),
            badge: GalaxySSIAgentTeamPresentation.stateLabel(snapshot.state, language: interfaceLanguage)
          )
          overview
          membersSection
          if !snapshot.state.isTerminal {
            messageComposer
          }
          if !snapshot.finalOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detailBlock(
              t("galaxyssi.agent_team.result", "Final result"),
              snapshot.finalOutput
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var overview: some View {
    VStack(alignment: .leading, spacing: 8) {
      detailBlock(
        t("galaxyssi.agent_team.primary", "Primary Agent"),
        snapshot.primaryAgentId.ifBlank("-")
      )
      detailBlock(
        t("galaxyssi.agent_team.updated", "Updated"),
        GalaxySSIAgentTeamPresentation.time(snapshot.updatedAtMillis, language: interfaceLanguage)
      )
      if !snapshot.taskId.isEmpty {
        detailBlock(t("galaxyssi.agent_team.task", "Task"), snapshot.taskId)
      }
    }
  }

  private var membersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.agent_team.members", "Members"))
      if visibleMembers.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.agent_team.no_members", "No member details"),
          subtitle: t("galaxyssi.agent_team.no_members_subtitle", "The team did not publish member progress."),
          systemImage: "person.2.slash",
          tint: .orange,
          badge: t("galaxyssi.agent_team.unknown", "Unknown")
        )
      } else {
        ForEach(Array(visibleMembers.enumerated()), id: \.offset) { _, member in
          memberRow(member)
        }
      }
    }
  }

  private func memberRow(_ member: AgentTeamMemberSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(member.agentId)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Text(GalaxySSIAgentTeamPresentation.memberStatusLabel(member.status, language: interfaceLanguage))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
      if !member.role.isEmpty {
        Text(member.role)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
      }
      if !snapshot.state.isTerminal && !member.status.isTerminal {
        Button {
          selectedInstanceId = member.memberId
        } label: {
          Label(
            t("galaxyssi.agent_team.message_member", "Message member"),
            systemImage: "message"
          )
          .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundColor(.galaxySSIAccent)
      }
      if !member.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(member.errorMessage)
          .font(.system(size: 12))
          .foregroundColor(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !member.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(member.output)
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var messageComposer: some View {
    VStack(alignment: .leading, spacing: 10) {
      GalaxySSISecuritySectionTitle(
        title: t("galaxyssi.agent_team.send_message", "Send team message")
      )
      Menu {
        Button(t("galaxyssi.agent_team.broadcast", "All members")) {
          selectedInstanceId = ""
        }
        ForEach(visibleMembers.filter { !$0.status.isTerminal }, id: \.memberId) { member in
          Button(member.memberId) {
            selectedInstanceId = member.memberId
          }
        }
      } label: {
        HStack {
          Image(systemName: selectedInstanceId.isEmpty ? "person.3" : "person")
          Text(selectedInstanceId.ifBlank(
            t("galaxyssi.agent_team.broadcast", "All members")
          ))
            .lineLimit(1)
          Spacer(minLength: 8)
          Image(systemName: "chevron.up.chevron.down")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      HStack(alignment: .bottom, spacing: 8) {
        TextField(
          t("galaxyssi.agent_team.message_hint", "Message the active team"),
          text: $messageDraft
        )
        .lineLimit(1)
        .textFieldStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        Button(action: queueTeamMessage) {
          Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 42, height: 42)
            .background(messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? Color.galaxySSITextSecondary
              : Color.galaxySSIAccent)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(Text(t("galaxyssi.agent_team.send", "Send message")))
      }
      if !messageStatus.isEmpty {
        Text(messageStatus)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
  }

  private func queueTeamMessage() {
    let text = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    do {
      _ = try UserDefaultsAgentTeamMailbox().append(AgentTeamMessageEnvelope(
        teamId: snapshot.teamId,
        conversationId: snapshot.conversationId,
        supervisorRunId: snapshot.supervisorRunId,
        fromInstanceId: "user",
        toInstanceId: selectedInstanceId,
        kind: .userDirective,
        text: text
      ))
      messageDraft = ""
      messageStatus = t("galaxyssi.agent_team.message_queued", "Message queued")
    } catch {
      messageStatus = error.localizedDescription.ifBlank(
        t("galaxyssi.agent_team.message_failed", "Message could not be queued")
      )
    }
  }

  private func detailBlock(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
      Text(value.ifBlank("-"))
        .font(.system(size: 13))
        .foregroundColor(.galaxySSITextPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
