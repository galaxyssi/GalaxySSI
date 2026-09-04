import SwiftUI

struct GalaxySSIAgentTranscriptMessagesView: View {
  var messages: [ChatMessage]
  var waitingMessageIDs: Set<UUID>
  var retryingMessageIDs: Set<UUID>
  @ObservedObject var replySpeech: AgentReplySpeechRuntime
  var voiceSettings: VoiceSettings
  var languagePolicy: LanguagePolicySettings
  var t: (String, String) -> String

  var mergedSourceLabel: (ChatMessage) -> String?
  var agentTask: (ChatMessage) -> AgentTaskRecord?
  var remoteAgentTask: (ChatMessage) -> AgentRemoteTaskStatusSnapshot?
  var voiceAgentRun: (ChatMessage) -> VoiceAgentRunSnapshot?
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
    .onAppear(perform: observeLatestReply)
    .onChange(of: latestSpeechTarget) { _ in
      observeLatestReply()
    }
    .onTapGesture(count: 2) {
      replySpeech.stopPlaybackIfActive()
    }
    .onDisappear {
      replySpeech.stop()
    }
  }

  @ViewBuilder
  private func messageRow(_ message: ChatMessage) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let mergedSource = mergedSourceLabel(message) {
        Text(mergedSource)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
          .accessibilityLabel(mergedSource)
      }
      MessageBubble(
        message: message,
        onActionWithMessage: { message, action in
          onRichAction(message, action)
        },
        onFormSubmit: onFormSubmit,
        onParagraphDoubleTap: paragraphSpeechAction(message)
      )
      if !message.isMine, !message.isSystem {
        messageExecutionFooter(message)
      }
      if let target = AgentReplySpeechPresentationPolicy.target(message),
         latestSpeechTarget?.responseId == target.responseId || replySpeech.isActive(target) {
        HStack {
          Spacer()
          GalaxySSIAgentReplySpeechButton(enabled: replySpeech.isEnabled(target)) {
            replySpeech.toggle(
              target,
              settings: voiceSettings,
              languagePolicy: languagePolicy
            )
          }
        }
        if latestSpeechTarget?.responseId == target.responseId,
           !replySpeech.lastErrorDescription.isEmpty {
          Text(replySpeech.lastErrorDescription)
            .font(.caption2)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      }
    }
    .id(message.id)
    .contextMenu {
      Button {
        onCopyMessage(message)
      } label: {
        Label(t("galaxyssi.common.copy", "Copy"), systemImage: "doc.on.doc")
      }
      Button(role: .destructive) {
        onDeleteMessage(message)
      } label: {
        Label(t("galaxyssi.message.delete", "Delete Message"), systemImage: "trash")
      }
    }
    if waitingMessageIDs.contains(message.id) {
      AgentReplyWaitingIndicatorView(bubbleBackground: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(AgentReplyWaitingIndicatorPolicy.viewID(for: message))
    }
    if message.isMine && message.deliveryStatus == .failed {
      GalaxySSIAgentRetryCard(
        title: t("galaxyssi.agent.retry.title", "Agent request failed"),
        subtitle: t(
          "galaxyssi.agent.retry.subtitle",
          "Retry the most recent Agent request."
        ),
        retryTitle: t("galaxyssi.common.retry", "Retry"),
        retryingTitle: t("galaxyssi.agent_tasks.retrying", "Retrying task..."),
        isRetrying: retryingMessageIDs.contains(message.id)
      ) {
        onRetryMessage(message)
      }
    }
  }

  private var latestSpeechTarget: AgentReplySpeechTarget? {
    AgentReplySpeechPresentationPolicy.latestTarget(messages)
  }

  private func observeLatestReply() {
    replySpeech.observe(
      latestSpeechTarget,
      settings: voiceSettings,
      languagePolicy: languagePolicy
    )
  }

  private func paragraphSpeechAction(
    _ message: ChatMessage
  ) -> ((AgentReplyParagraphSpeechSelection) -> Void)? {
    guard let target = AgentReplySpeechPresentationPolicy.target(message) else { return nil }
    return { selection in
      replySpeech.readFromParagraph(
        selection,
        target: target,
        settings: voiceSettings,
        languagePolicy: languagePolicy
      )
    }
  }

  @ViewBuilder
  private func messageExecutionFooter(_ message: ChatMessage) -> some View {
    if let task = agentTask(message) {
      GalaxySSIAgentExecutionFooterView(
        completed: [.completed, .failed, .cancelled, .blocked].contains(task.phase),
        duration: executionDuration(task.createdAtMillis, task.updatedAtMillis),
        details: task.executionLog,
        detailsTitle: t("galaxyssi.agent.execution.timeline", "Execution timeline"),
        timelineActions: timelineActions(task),
        timelineActionTitle: timelineActionTitle,
        timelineActionIcon: timelineActionIcon,
        timelineActionMenuTitle: t("galaxyssi.agent.task_control.title", "Task controls"),
        onTimelineAction: { action in
          onTimelineAction(action, task)
        },
        canCancel: AgentTaskCenterPolicy.cancellable(task),
        cancelTitle: t("galaxyssi.agent.task_control.cancel", "Cancel task"),
        onCancel: {
          onCancelAgentTask(task)
        }
      )
    } else if let remoteTask = remoteAgentTask(message) {
      GalaxySSIAgentExecutionFooterView(
        completed: AgentRemoteTaskStatusPolicy.isTerminal(remoteTask.status),
        duration: executionDuration(
          remoteTask.history.first?.updatedAtMillis ?? remoteTask.updatedAtMillis,
          remoteTask.updatedAtMillis
        ),
        details: remoteTask.history.map(remoteAgentTimelineLine),
        detailsTitle: t("galaxyssi.agent.execution.timeline", "Execution timeline"),
        canCancel: remoteTask.isCancellable && !isRemoteTaskCancelling(remoteTask.id),
        cancelTitle: isRemoteTaskCancelling(remoteTask.id)
          ? t("galaxyssi.agent.remote_status.cancelling", "Cancelling...")
          : t("galaxyssi.agent.remote_status.cancel", "Cancel task"),
        onCancel: {
          onCancelRemoteTask(remoteTask)
        }
      )
    } else if let run = voiceAgentRun(message) {
      GalaxySSIAgentExecutionFooterView(
        completed: run.state.isTerminal,
        duration: executionDuration(
          run.acceptedAtMillis > 0 ? run.acceptedAtMillis : run.createdAtMillis,
          run.updatedAtMillis
        ),
        details: [run.progressMessage, run.partialResult, run.resultSummary]
          .filter { !$0.isBlank },
        detailsTitle: t("galaxyssi.agent.execution.timeline", "Execution timeline"),
        canCancel: run.cancellable && !isVoiceRunCancelling(run.runId),
        cancelTitle: isVoiceRunCancelling(run.runId)
          ? t("galaxyssi.agent.remote_status.cancelling", "Cancelling...")
          : t("galaxyssi.agent.remote_status.cancel", "Cancel task"),
        onCancel: {
          onCancelVoiceRun(run)
        }
      )
    }
  }
}
