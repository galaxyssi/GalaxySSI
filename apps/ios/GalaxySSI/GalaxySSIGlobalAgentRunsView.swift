import SwiftUI

struct GalaxySSIGlobalAgentRunsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var runs: [GlobalAutonomousRun] = []

  private let deliberationStore = GlobalAgentDeliberationStore()

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_global_runs_title", "Autonomous work"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          GalaxySSIAndroidIconButton(systemName: "arrow.clockwise", action: refresh)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if runs.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("cc_global_empty_title", "Nothing queued"),
              subtitle: t("cc_global_runs_empty_subtitle", "Autonomous work will appear here when the Agent prepares a durable next step."),
              systemImage: "checkmark.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
            )
          } else {
            ForEach(runs) { run in
              runCard(run)
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
  }

  private func runCard(_ run: GlobalAutonomousRun) -> some View {
    let waiting = run.actions.filter { $0.status == .waitingConfirmation }
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: waiting.isEmpty ? "play.circle" : "exclamationmark.shield")
          .font(.system(size: 20, weight: .semibold))
          .foregroundColor(waiting.isEmpty ? .galaxySSIAccent : .orange)
          .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 4) {
          Text(run.topic.ifBlank(run.goal))
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Text(run.outcomeSummary.ifBlank(run.lastError).ifBlank("\(run.actions.count) actions"))
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        GalaxySSIGlobalAgentBadge(text: run.status.rawValue, tint: waiting.isEmpty ? .galaxySSIAccent : .orange)
      }

      if !waiting.isEmpty {
        Text(t("cc_global_run_confirmation_subtitle", "This run is waiting for approval before an external effect can occur."))
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
          Button {
            approve(run.id)
          } label: {
            Label(t("cc_global_run_approve", "Approve"), systemImage: "checkmark.circle")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.galaxySSIAccent)
              .cornerRadius(7)
          }
          Button {
            reject(run.id)
          } label: {
            Label(t("cc_global_run_reject", "Reject"), systemImage: "xmark.circle")
              .font(.system(size: 13, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(Color.galaxySSIButtonSoft)
              .cornerRadius(7)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSISeparator, lineWidth: 0.5)
    )
    .cornerRadius(8)
  }

  private func approve(_ runId: String) {
    guard deliberationStore.approveAutonomousRun(runId: runId) else { return }
    coordinator.refreshAgentHomeState()
    refresh()
  }

  private func reject(_ runId: String) {
    guard deliberationStore.rejectAutonomousRun(runId: runId) else { return }
    coordinator.refreshAgentHomeState()
    refresh()
  }

  private func refresh() {
    runs = deliberationStore.autonomousRuns()
  }

  private func t(_ key: String, _ fallback: String) -> String {
    return GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
