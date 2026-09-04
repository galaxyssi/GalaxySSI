import SwiftUI

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
