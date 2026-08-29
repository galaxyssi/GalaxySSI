import SwiftUI

struct SignalASIAgentTranscriptMessagesView: View {
  var messages: [ChatMessage]
  var waitingMessageIDs: Set<UUID>
  var retryingMessageIDs: Set<UUID>
  var t: (String, String) -> String

  var mergedSourceLabel: (ChatMessage) -> String?
  var agentTask: (ChatMessage) -> AgentTaskRecord?
  var remoteAgentTask: (ChatMessage) -> AgentRemoteTaskStatusSnapshot?
  var voiceAgentRun: (ChatMessage) -> VoiceAgentRunSnapshot?
  var agentPhaseLabel: (AgentPhase) -> String
  var agentExecutionLocationSummary: (AgentTaskRecord) -> String
  var agentExecutionStep: (AgentTaskRecord) -> String
  var remoteAgentStatusLabel: (String) -> String
  var remoteAgentStep: (AgentRemoteTaskStatusSnapshot) -> String
  var remoteAgentTimelineLine: (AgentRemoteTaskStatusEvent) -> String
  var executionDuration: (Int64, Int64) -> String
  var timelineActions: (AgentTaskRecord) -> [AgentExecutionLoopTimelineAction]
  var timelineActionTitle: (AgentExecutionLoopTimelineAction) -> String
  var timelineActionIcon: (AgentExecutionLoopTimelineAction) -> String
  var isRemoteTaskCancelling: (String) -> Bool
  var isVoiceRunCancelling: (String) -> Bool

  var onRichAction: (ChatMessage, AgentRichAction) -> Void
  var onFormSubmit: (AgentRichBlock, [String: String]) -> Void
  var onCancelAgentTask: (AgentTaskRecord) -> Void
  var onCancelRemoteTask: (AgentRemoteTaskStatusSnapshot) -> Void
  var onCancelVoiceRun: (VoiceAgentRunSnapshot) -> Void
  var onTimelineAction: (AgentExecutionLoopTimelineAction, AgentTaskRecord) -> Void
  var onCopyMessage: (ChatMessage) -> Void
  var onDeleteMessage: (ChatMessage) -> Void
  var onRetryMessage: (ChatMessage) -> Void

  var body: some View {
    ForEach(messages) { message in
      messageRow(message)
    }
  }

  @ViewBuilder
  private func messageRow(_ message: ChatMessage) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let mergedSource = mergedSourceLabel(message) {
        Text(mergedSource)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.signalASITextSecondary)
          .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
          .accessibilityLabel(mergedSource)
      }
      MessageBubble(
        message: message,
        onActionWithMessage: { message, action in
          onRichAction(message, action)
        },
        onFormSubmit: onFormSubmit
      )
      if !message.isMine, !message.isSystem {
        messageExecutionFooter(message)
      }
    }
    .id(message.id)
    .contextMenu {
      Button {
        onCopyMessage(message)
      } label: {
        Label(t("signalasi.common.copy", "Copy"), systemImage: "doc.on.doc")
      }
      Button(role: .destructive) {
        onDeleteMessage(message)
      } label: {
        Label(t("signalasi.message.delete", "Delete Message"), systemImage: "trash")
      }
    }
    if waitingMessageIDs.contains(message.id) {
      AgentReplyWaitingIndicatorView(bubbleBackground: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(AgentReplyWaitingIndicatorPolicy.viewID(for: message))
    }
    if message.isMine && message.deliveryStatus == .failed {
      SignalASIAgentRetryCard(
        title: t("signalasi.agent.retry.title", "Agent request failed"),
        subtitle: t(
          "signalasi.agent.retry.subtitle",
          "Retry the most recent Agent request."
        ),
        retryTitle: t("signalasi.common.retry", "Retry"),
        retryingTitle: t("signalasi.agent_tasks.retrying", "Retrying task..."),
        isRetrying: retryingMessageIDs.contains(message.id)
      ) {
        onRetryMessage(message)
      }
    }
  }

  @ViewBuilder
  private func messageExecutionFooter(_ message: ChatMessage) -> some View {
    if let task = agentTask(message) {
      SignalASIAgentExecutionFooterView(
        executor: task.targetTitle.ifBlank(t("signalasi.agent.status", "Agent")),
        status: agentPhaseLabel(task.phase),
        location: agentExecutionLocationSummary(task),
        step: agentExecutionStep(task),
        duration: executionDuration(task.createdAtMillis, task.updatedAtMillis),
        details: task.executionLog,
        detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
        timelineActions: timelineActions(task),
        timelineActionTitle: timelineActionTitle,
        timelineActionIcon: timelineActionIcon,
        timelineActionMenuTitle: t("signalasi.agent.task_control.title", "Task controls"),
        onTimelineAction: { action in
          onTimelineAction(action, task)
        },
        canCancel: AgentTaskCenterPolicy.cancellable(task),
        cancelTitle: t("signalasi.agent.task_control.cancel", "Cancel task"),
        onCancel: {
          onCancelAgentTask(task)
        }
      )
    } else if let remoteTask = remoteAgentTask(message) {
      SignalASIAgentExecutionFooterView(
        executor: remoteTask.target.ifBlank(t("signalasi.agent.status", "Agent")),
        status: remoteAgentStatusLabel(remoteTask.status),
        location: remoteTask.location.ifBlank(
          t("signalasi.agent_execution.location.desktop", "Desktop")
        ),
        step: remoteAgentStep(remoteTask),
        duration: executionDuration(
          remoteTask.history.first?.updatedAtMillis ?? remoteTask.updatedAtMillis,
          remoteTask.updatedAtMillis
        ),
        details: remoteTask.history.map(remoteAgentTimelineLine),
        detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
        canCancel: remoteTask.isCancellable && !isRemoteTaskCancelling(remoteTask.id),
        cancelTitle: isRemoteTaskCancelling(remoteTask.id)
          ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
          : t("signalasi.agent.remote_status.cancel", "Cancel task"),
        onCancel: {
          onCancelRemoteTask(remoteTask)
        }
      )
    } else if let run = voiceAgentRun(message) {
      let runStatus = remoteAgentStatusLabel(run.state.rawValue.lowercased())
      SignalASIAgentExecutionFooterView(
        executor: run.agentName.ifBlank(run.agentId).ifBlank(
          t("signalasi.agent.status", "Agent")
        ),
        status: runStatus,
        location: t("signalasi.agent_execution.runtime.desktop_agent", "Desktop Agent"),
        step: run.progressMessage.ifBlank(run.stage).ifBlank(runStatus),
        duration: executionDuration(
          run.acceptedAtMillis > 0 ? run.acceptedAtMillis : run.createdAtMillis,
          run.updatedAtMillis
        ),
        details: [run.progressMessage, run.partialResult, run.resultSummary]
          .filter { !$0.isBlank },
        detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
        canCancel: run.cancellable && !isVoiceRunCancelling(run.runId),
        cancelTitle: isVoiceRunCancelling(run.runId)
          ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
          : t("signalasi.agent.remote_status.cancel", "Cancel task"),
        onCancel: {
          onCancelVoiceRun(run)
        }
      )
    }
  }
}
