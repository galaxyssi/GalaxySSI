import SwiftUI

enum SignalASIAgentTeamPresentation {
  static func stateLabel(_ state: AgentTeamExecutionState, language: String) -> String {
    let key: String
    let fallback: String
    switch state {
    case .queued:
      key = "signalasi.agent_team.state_queued"
      fallback = "Queued"
    case .created:
      key = "signalasi.agent_team.state_created"
      fallback = "Created"
    case .running:
      key = "signalasi.agent_team.state_running"
      fallback = "Running"
    case .waitingResponse:
      key = "signalasi.agent_team.state_waiting_response"
      fallback = "Waiting for response"
    case .succeeded:
      key = "signalasi.agent_team.state_succeeded"
      fallback = "Completed"
    case .completedWithFailures:
      key = "signalasi.agent_team.state_completed_with_failures"
      fallback = "Completed with failures"
    case .failed:
      key = "signalasi.agent_team.state_failed"
      fallback = "Failed"
    case .cancelled:
      key = "signalasi.agent_team.state_cancelled"
      fallback = "Cancelled"
    case .interrupted:
      key = "signalasi.agent_team.state_interrupted"
      fallback = "Interrupted"
    }
    return SignalASILocalization.string(key, fallback: fallback, language: language)
  }

  static func memberStatusLabel(_ status: AgentSubagentStatus, language: String) -> String {
    let key: String
    let fallback: String
    switch status {
    case .pending:
      key = "signalasi.agent_team.member_pending"
      fallback = "Pending"
    case .queued:
      key = "signalasi.agent_team.state_queued"
      fallback = "Queued"
    case .running:
      key = "signalasi.agent_team.state_running"
      fallback = "Running"
    case .succeeded:
      key = "signalasi.agent_team.state_succeeded"
      fallback = "Completed"
    case .failed:
      key = "signalasi.agent_team.state_failed"
      fallback = "Failed"
    case .cancelled:
      key = "signalasi.agent_team.state_cancelled"
      fallback = "Cancelled"
    case .skipped:
      key = "signalasi.agent_team.member_skipped"
      fallback = "Skipped"
    case .interrupted:
      key = "signalasi.agent_team.state_interrupted"
      fallback = "Interrupted"
    }
    return SignalASILocalization.string(key, fallback: fallback, language: language)
  }

  static func stateTint(_ state: AgentTeamExecutionState) -> Color {
    switch state {
    case .succeeded:
      return .signalASIAccent
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
      return SignalASILocalization.string(
        "signalasi.agent_team.unknown_time",
        fallback: "Unknown time",
        language: language
      )
    }
    return SignalASISecurityFormatter.time(
      Date(timeIntervalSince1970: TimeInterval(millis) / 1_000),
      unknown: SignalASILocalization.string(
        "signalasi.agent_team.unknown_time",
        fallback: "Unknown time",
        language: language
      ),
      language: language
    )
  }
}

struct SignalASIAgentTeamSummaryRow: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var snapshot: AgentTeamExecutionSnapshot

  var body: some View {
    SignalASISecurityNavigationRow(
      title: snapshot.goal.ifBlank(snapshot.teamId),
      subtitle: String(
        format: t("signalasi.agent_team.summary", "%d members - %@"),
        SignalASIAgentTeamPresentation.memberCount(snapshot),
        SignalASIAgentTeamPresentation.stateLabel(snapshot.state, language: interfaceLanguage)
      ),
      systemImage: "person.3",
      tint: SignalASIAgentTeamPresentation.stateTint(snapshot.state),
      badge: SignalASIAgentTeamPresentation.stateLabel(snapshot.state, language: interfaceLanguage)
    ) {
      SignalASIAgentTeamDetailView(snapshot: snapshot)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIAgentTeamDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var snapshot: AgentTeamExecutionSnapshot

  private var visibleMembers: [AgentTeamMemberSnapshot] {
    snapshot.members.filter { $0.deliveryMode != .ignore }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.agent_team.details_title", "Agent Team"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: snapshot.goal.ifBlank(t("signalasi.agent_team.details_title", "Agent Team")),
            subtitle: snapshot.teamId,
            systemImage: "person.3",
            tint: SignalASIAgentTeamPresentation.stateTint(snapshot.state),
            badge: SignalASIAgentTeamPresentation.stateLabel(snapshot.state, language: interfaceLanguage)
          )
          overview
          membersSection
          if !snapshot.finalOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detailBlock(
              t("signalasi.agent_team.result", "Final result"),
              snapshot.finalOutput
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var overview: some View {
    VStack(alignment: .leading, spacing: 8) {
      detailBlock(
        t("signalasi.agent_team.primary", "Primary Agent"),
        snapshot.primaryAgentId.ifBlank("-")
      )
      detailBlock(
        t("signalasi.agent_team.updated", "Updated"),
        SignalASIAgentTeamPresentation.time(snapshot.updatedAtMillis, language: interfaceLanguage)
      )
      if !snapshot.taskId.isEmpty {
        detailBlock(t("signalasi.agent_team.task", "Task"), snapshot.taskId)
      }
    }
  }

  private var membersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.agent_team.members", "Members"))
      if visibleMembers.isEmpty {
        SignalASISecurityStatusRow(
          title: t("signalasi.agent_team.no_members", "No member details"),
          subtitle: t("signalasi.agent_team.no_members_subtitle", "The team did not publish member progress."),
          systemImage: "person.2.slash",
          tint: .orange,
          badge: t("signalasi.agent_team.unknown", "Unknown")
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
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Text(SignalASIAgentTeamPresentation.memberStatusLabel(member.status, language: interfaceLanguage))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      if !member.role.isEmpty {
        Text(member.role)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
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
          .foregroundColor(.signalASITextPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func detailBlock(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
      Text(value.ifBlank("-"))
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
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
