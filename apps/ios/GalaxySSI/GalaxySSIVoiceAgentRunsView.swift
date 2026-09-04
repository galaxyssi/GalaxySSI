import SwiftUI

struct GalaxySSIVoiceAgentRunsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @ObservedObject private var recovery = VoiceAgentRunRecoveryCoordinator.shared
  @State private var selectedRun: VoiceAgentRunSnapshot?

  private var runs: [VoiceAgentRunSnapshot] {
    recovery.snapshots.sorted {
      if $0.updatedAtMillis != $1.updatedAtMillis {
        return $0.updatedAtMillis > $1.updatedAtMillis
      }
      return $0.runId < $1.runId
    }
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        GalaxySSITopBar(
          title: t("galaxyssi.voice_agent_runs.title", "Voice Agent runs"),
          leading: { GalaxySSIBackButton() },
          trailing: {
            Button {
              recovery.refresh()
            } label: {
              Image(systemName: "arrow.clockwise")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.galaxySSITextPrimary)
            }
            .accessibilityLabel(t("galaxyssi.voice_agent_runs.refresh", "Refresh runs"))
          }
        )

        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            Text(
              String(
                format: t(
                  "galaxyssi.voice_agent_runs.summary",
                  "%d active / %d saved"
                ),
                recovery.activeSnapshots.count,
                runs.count
              )
            )
            .font(.caption)
            .foregroundColor(.galaxySSITextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if runs.isEmpty {
              VoiceAgentRunEmptyView(
                title: t("galaxyssi.voice_agent_runs.empty", "No voice Agent runs"),
                subtitle: t(
                  "galaxyssi.voice_agent_runs.empty_subtitle",
                  "Voice tasks started from the Voice page will remain available here while they complete."
                )
              )
            } else {
              ForEach(runs) { run in
                Button {
                  selectedRun = run
                } label: {
                  VoiceAgentRunRow(
                    run: run,
                    stateLabel: stateLabel(run.state),
                    stateTint: stateTint(run.state),
                    updatedLabel: formattedDate(run.updatedAtMillis)
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }
          .padding(12)
        }
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
    }
    .navigationViewStyle(StackNavigationViewStyle())
    .sheet(item: $selectedRun) { run in
      VoiceAgentRunDetailView(
        run: run,
        stateLabel: stateLabel(run.state),
        updatedLabel: formattedDate(run.updatedAtMillis),
        createdLabel: formattedDate(run.createdAtMillis)
      )
    }
    .onAppear {
      recovery.start()
      recovery.refresh()
    }
  }

  private func stateLabel(_ state: VoiceAgentRunState) -> String {
    switch state {
    case .created: return t("galaxyssi.voice_agent_runs.state.created", "Created")
    case .accepted: return t("galaxyssi.voice_agent_runs.state.accepted", "Accepted")
    case .queued: return t("galaxyssi.voice_agent_runs.state.queued", "Queued")
    case .starting: return t("galaxyssi.voice_agent_runs.state.starting", "Starting")
    case .running: return t("galaxyssi.voice_agent_runs.state.running", "Running")
    case .waitingInput: return t("galaxyssi.voice_agent_runs.state.waiting_input", "Waiting for input")
    case .waitingApproval: return t("galaxyssi.voice_agent_runs.state.waiting_approval", "Waiting for approval")
    case .cancelling: return t("galaxyssi.voice_agent_runs.state.cancelling", "Cancelling")
    case .completed: return t("galaxyssi.voice_agent_runs.state.completed", "Completed")
    case .failed: return t("galaxyssi.voice_agent_runs.state.failed", "Failed")
    case .cancelled: return t("galaxyssi.voice_agent_runs.state.cancelled", "Cancelled")
    case .timedOut: return t("galaxyssi.voice_agent_runs.state.timed_out", "Timed out")
    }
  }

  private func stateTint(_ state: VoiceAgentRunState) -> Color {
    if state.isTerminal {
      return state == .completed ? .galaxySSIAccent : .orange
    }
    if state == .waitingApproval || state == .waitingInput || state == .cancelling {
      return .orange
    }
    return .blue
  }

  private func formattedDate(_ millis: Int64) -> String {
    guard millis > 0 else { return "-" }
    return Date(timeIntervalSince1970: Double(millis) / 1_000)
      .formatted(date: .abbreviated, time: .shortened)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIAgentVoiceRunSummaryCard: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var runs: [VoiceAgentRunSnapshot]

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.galaxySSIAccent)
          .frame(width: 24, height: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(t("galaxyssi.voice_agent_runs.title", "Voice Agent runs"))
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(
            String(
              format: t(
                "galaxyssi.voice_agent_runs.active_summary",
                "%d active voice task(s)"
              ),
              runs.count
            )
          )
          .font(.system(size: 11))
          .foregroundColor(.galaxySSITextSecondary)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.galaxySSITextSecondary)
      }

      ForEach(Array(runs.prefix(3))) { run in
        HStack(alignment: .top, spacing: 8) {
          Circle()
            .fill(stateTint(run.state))
            .frame(width: 8, height: 8)
            .padding(.top, 5)
          VStack(alignment: .leading, spacing: 2) {
            Text(run.goal.ifBlank(t("galaxyssi.voice_agent_runs.detail.goal", "Voice Agent task")))
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
            Text(run.progressMessage.ifBlank(run.stage).ifBlank(stateLabel(run.state)))
              .font(.system(size: 10.5))
              .foregroundColor(.galaxySSITextSecondary)
              .lineLimit(1)
          }
          Spacer(minLength: 6)
          Text(stateLabel(run.state))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(stateTint(run.state))
            .lineLimit(1)
        }
      }

      HStack(spacing: 4) {
        Text(t("galaxyssi.voice_agent_runs.open", "Open voice runs"))
          .font(.system(size: 11, weight: .semibold))
        Image(systemName: "arrow.up.right")
          .font(.system(size: 10, weight: .bold))
      }
      .foregroundColor(.galaxySSIAccent)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func stateLabel(_ state: VoiceAgentRunState) -> String {
    switch state {
    case .created: return t("galaxyssi.voice_agent_runs.state.created", "Created")
    case .accepted: return t("galaxyssi.voice_agent_runs.state.accepted", "Accepted")
    case .queued: return t("galaxyssi.voice_agent_runs.state.queued", "Queued")
    case .starting: return t("galaxyssi.voice_agent_runs.state.starting", "Starting")
    case .running: return t("galaxyssi.voice_agent_runs.state.running", "Running")
    case .waitingInput: return t("galaxyssi.voice_agent_runs.state.waiting_input", "Waiting for input")
    case .waitingApproval: return t("galaxyssi.voice_agent_runs.state.waiting_approval", "Waiting for approval")
    case .cancelling: return t("galaxyssi.voice_agent_runs.state.cancelling", "Cancelling")
    case .completed: return t("galaxyssi.voice_agent_runs.state.completed", "Completed")
    case .failed: return t("galaxyssi.voice_agent_runs.state.failed", "Failed")
    case .cancelled: return t("galaxyssi.voice_agent_runs.state.cancelled", "Cancelled")
    case .timedOut: return t("galaxyssi.voice_agent_runs.state.timed_out", "Timed out")
    }
  }

  private func stateTint(_ state: VoiceAgentRunState) -> Color {
    if state == .waitingApproval || state == .waitingInput || state == .cancelling {
      return .orange
    }
    return .galaxySSIAccent
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct VoiceAgentRunEmptyView: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "waveform")
        .font(.title2)
        .foregroundColor(.galaxySSIAccent)
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundColor(.galaxySSITextPrimary)
      Text(subtitle)
        .font(.caption)
        .foregroundColor(.galaxySSITextSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
    .padding(.horizontal, 16)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct VoiceAgentRunRow: View {
  var run: VoiceAgentRunSnapshot
  var stateLabel: String
  var stateTint: Color
  var updatedLabel: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "waveform.badge.mic")
          .foregroundColor(stateTint)
          .frame(width: 24, height: 24)
        VStack(alignment: .leading, spacing: 3) {
          Text(run.goal.ifBlank("Voice Agent task"))
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(2)
          Text(run.agentName.ifBlank(run.agentId).ifBlank("GalaxySSI Agent"))
            .font(.caption)
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Text(stateLabel)
          .font(.caption2.weight(.semibold))
          .foregroundColor(stateTint)
          .multilineTextAlignment(.trailing)
      }
      if !run.progressMessage.isEmpty {
        Text(run.progressMessage)
          .font(.caption)
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      } else if !run.partialResult.isEmpty {
        Text(run.partialResult)
          .font(.caption)
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      HStack {
        Text(run.stage.ifBlank(stateLabel))
        Spacer()
        Text(updatedLabel)
      }
      .font(.caption2)
      .foregroundColor(.galaxySSITextSecondary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSISeparator, lineWidth: 0.5)
    )
  }
}

private struct VoiceAgentRunDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var run: VoiceAgentRunSnapshot
  var stateLabel: String
  var updatedLabel: String
  var createdLabel: String

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          detail(t("galaxyssi.voice_agent_runs.detail.state", "State"), stateLabel)
          detail(t("galaxyssi.voice_agent_runs.detail.agent", "Agent"), run.agentName.ifBlank(run.agentId).ifBlank("-"))
          detail(t("galaxyssi.voice_agent_runs.detail.goal", "Goal"), run.goal.ifBlank("-"))
          detail(t("galaxyssi.voice_agent_runs.detail.stage", "Stage"), run.stage.ifBlank("-"))
          detail(t("galaxyssi.voice_agent_runs.detail.progress", "Progress"), run.progressMessage.ifBlank("-"))
          detail(t("galaxyssi.voice_agent_runs.detail.partial", "Partial result"), run.partialResult.ifBlank("-"))
          detail(t("galaxyssi.voice_agent_runs.detail.result", "Result"), run.resultSummary.ifBlank("-"))
          detail(t("galaxyssi.voice_agent_runs.detail.created", "Created"), createdLabel)
          detail(t("galaxyssi.voice_agent_runs.detail.updated", "Updated"), updatedLabel)
          detail(t("galaxyssi.voice_agent_runs.detail.run_id", "Run ID"), run.runId)
        }
        .padding(16)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationTitle(t("galaxyssi.voice_agent_runs.detail.title", "Voice Agent run"))
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.done", "Done")) {
            dismiss()
          }
        }
      }
    }
  }

  private func detail(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundColor(.galaxySSITextSecondary)
      Text(value)
        .font(.body)
        .foregroundColor(.galaxySSITextPrimary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
