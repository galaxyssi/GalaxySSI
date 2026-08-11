import SwiftUI

/// The transient execution states that sit above the Agent transcript.
/// Keeping these states together makes the home screen easier to scan and
/// keeps its long-lived transcript content independent from task alerts.
struct SignalASIAgentHomeExecutionAlertsView: View {
  let scanStatus: String
  let scanStatusIsError: Bool
  let activeVoiceAgentRuns: [VoiceAgentRunSnapshot]
  let cancellableVoiceAgentRuns: [VoiceAgentRunSnapshot]
  let cancellingVoiceRunIDs: Set<String>
  let manualRouteWarning: (title: String, subtitle: String)?
  let automaticRouteWarning: (title: String, subtitle: String)?
  let hasOlderTranscriptMessages: Bool
  let pendingConfirmationTask: AgentTaskRecord?
  let blockedAgentTask: AgentTaskRecord?
  let retryingAgentTaskIDs: Set<String>
  let t: (String, String) -> String
  let onRetryScan: () -> Void
  let onDismissScan: () -> Void
  let onCancelVoiceRun: (VoiceAgentRunSnapshot) -> Void
  let onOpenModelSelection: () -> Void
  let onLoadOlderTranscriptMessages: () -> Void
  let onApproveOnce: (AgentTaskRecord) -> Void
  let onApproveAlways: (AgentTaskRecord) -> Void
  let onDeny: (AgentTaskRecord) -> Void
  let onRetryBlockedTask: (AgentTaskRecord) -> Void
  let onReplanBlockedTask: (AgentTaskRecord) -> Void

  @ViewBuilder
  var body: some View {
    if !scanStatus.isEmpty {
      SignalASIAgentScanStatusView(
        message: scanStatus,
        isError: scanStatusIsError,
        dismissTitle: t("signalasi.agent.scan.dismiss", "Dismiss"),
        retryTitle: t("signalasi.agent.scan.retry", "Scan again"),
        onRetry: onRetryScan,
        onDismiss: onDismissScan
      )
    }
    if !activeVoiceAgentRuns.isEmpty {
      NavigationLink(destination: SignalASIVoiceAgentRunsView()) {
        SignalASIAgentVoiceRunSummaryCard(runs: activeVoiceAgentRuns)
      }
      .buttonStyle(.plain)
      ForEach(cancellableVoiceAgentRuns) { run in
        Button(role: .destructive) {
          onCancelVoiceRun(run)
        } label: {
          Label(
            cancellingVoiceRunIDs.contains(run.runId)
              ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
              : t("signalasi.agent.remote_status.cancel", "Cancel task"),
            systemImage: "xmark.circle"
          )
          .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.bordered)
        .disabled(cancellingVoiceRunIDs.contains(run.runId))
      }
    }
    if let routeWarning = manualRouteWarning {
      routeWarningView(routeWarning)
    }
    if let routeWarning = automaticRouteWarning {
      routeWarningView(routeWarning)
    }
    if hasOlderTranscriptMessages {
      SignalASIAgentLoadOlderButton(
        title: t("signalasi.agent.load_older", "Load earlier messages"),
        action: onLoadOlderTranscriptMessages
      )
    }
    if let pendingConfirmationTask {
      SignalASIAgentConfirmationCard(
        task: pendingConfirmationTask,
        onApproveOnce: { onApproveOnce(pendingConfirmationTask) },
        onApproveAlways: { onApproveAlways(pendingConfirmationTask) },
        onDeny: { onDeny(pendingConfirmationTask) }
      )
    }
    if let blockedAgentTask {
      SignalASIAgentBlockedTaskCard(
        title: t("signalasi.agent.blocked.title", "Agent task blocked"),
        goal: blockedAgentTask.goal,
        subtitle: t(
          "signalasi.agent.blocked.subtitle",
          "This task could not continue. Retry or re-plan the original goal."
        ),
        retryTitle: t("signalasi.common.retry", "Retry"),
        replanTitle: t("signalasi.agent.task_control.replan", "Re-plan task"),
        retryingTitle: t("signalasi.agent_tasks.retrying", "Retrying task..."),
        isRetrying: retryingAgentTaskIDs.contains(blockedAgentTask.taskId),
        onRetry: { onRetryBlockedTask(blockedAgentTask) },
        onReplan: { onReplanBlockedTask(blockedAgentTask) }
      )
    }
  }

  private func routeWarningView(
    _ warning: (title: String, subtitle: String)
  ) -> some View {
    SignalASISecurityNavigationRow(
      title: warning.title,
      subtitle: warning.subtitle,
      systemImage: "exclamationmark.triangle.fill",
      tint: .orange,
      badge: t("signalasi.agent.model_selection.choose", "Choose")
    ) {
      SignalASIAgentModelSelectionView(onSelectionChanged: onOpenModelSelection)
    }
  }
}
