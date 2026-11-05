import SwiftUI

struct GalaxySSIAgentTranscriptMessagesView: View {
  @State private var expandedProgress = Set<UUID>()
  var messages: [ChatMessage]
  var waitingMessageIDs: Set<UUID>
  var retryingMessageIDs: Set<UUID>
  @ObservedObject var replySpeech: AgentReplySpeechRuntime
  var voiceSettings: VoiceSettings
  var languagePolicy: LanguagePolicySettings
  var t: (String, String) -> String

  var mergedSourceLabel: (ChatMessage) -> String?
  var agentTask: (ChatMessage) -> AgentTaskRecord?
  var committedProgress: (ChatMessage) -> AgentCommittedTurnProgress.Turn?
  var remoteAgentTask: (ChatMessage) -> AgentRemoteTaskStatusSnapshot?
  var voiceAgentRun: (ChatMessage) -> VoiceAgentRunSnapshot?
  var remoteAgentTimelineLine: (AgentRemoteTaskStatusEvent) -> String
  var executionDuration: (Int64, Int64) -> String
  var elapsedDuration: (Int64) -> String
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
  var onMessageVisible: (ChatMessage) -> Void

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
      if !message.isMine, !message.isSystem {
        messageExecutionFooter(message)
      }
      agentMessageContent(message)
      if message.isMine {
        let progress = message.deliveryTrace.filter { $0.stage.hasPrefix(AgentConnectorPublicProgress.tracePrefix) &&
          !AgentPublicProgressPolicy.isInternal($0.detail) }
        if !progress.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            if let committed = committedProgress(message), !hasReply(for: message) {
              committedFooter(committed, message: message)
            }
            Button {
              if !expandedProgress.insert(message.id).inserted { expandedProgress.remove(message.id) }
            } label: {
              HStack(alignment: .top, spacing: 6) {
                Image(systemName: expandedProgress.contains(message.id) ? "chevron.up" : "chevron.down")
                Text(progressHeadline(progress.last, for: message))
                  .multilineTextAlignment(.leading)
              }
              .font(.system(size: 13))
              .foregroundColor(.galaxySSITextSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ios.agent.public-progress.\(message.id.uuidString)")
            if expandedProgress.contains(message.id) {
              ForEach(progress) { event in
                Text(event.detail)
                  .font(.system(size: 13))
                  .foregroundColor(.galaxySSITextSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
        }
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
    .onAppear {
      onMessageVisible(message)
    }
    .onChange(of: message.content) { _ in
      onMessageVisible(message)
    }
    .onChange(of: message.deliveryStatus) { _ in
      onMessageVisible(message)
    }
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

  @ViewBuilder
  private func agentMessageContent(_ message: ChatMessage) -> some View {
    if message.isSystem {
      Text(message.content)
        .font(.caption)
        .foregroundColor(.galaxySSITextSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    } else if message.isMine {
      VStack(alignment: .trailing, spacing: 4) {
        richContent(message)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .background(Color.galaxySSISentBubble)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        if !message.voiceTranscript.isBlank {
          Text(message.voiceTranscript)
            .font(.system(size: 14))
            .foregroundColor(.galaxySSITextSecondary)
            .multilineTextAlignment(.trailing)
        }
      }
      .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: .trailing)
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.vertical, 3)
    } else {
      richContent(message)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, hasExecutionFooter(message) ? 9 : 3)
        .padding(.bottom, 4)
    }
  }

  private func richContent(_ message: ChatMessage) -> some View {
    GalaxySSIRichContentView(
      content: message.content,
      richOutputJson: message.richOutputJson,
      isOutgoing: message.isMine,
      expansionStorageKey: "agent-message:\(message.id.uuidString)",
      onAction: { action in
        onRichAction(message, action)
      },
      onFormSubmit: onFormSubmit
    )
    .environment(\.agentReplyParagraphSpeechAction, paragraphSpeechAction(message))
    .foregroundColor(.galaxySSITextPrimary)
  }

  private func hasExecutionFooter(_ message: ChatMessage) -> Bool {
    committedProgress(message) != nil || agentTask(message) != nil ||
      remoteAgentTask(message) != nil || voiceAgentRun(message) != nil
  }

  private func hasReply(for message: ChatMessage) -> Bool {
    let turn = AgentReplyWaitingIndicatorPolicy.turnKey(for: message)
    return messages.contains {
      !$0.isMine && !$0.isSystem && $0.conversationId == message.conversationId &&
        AgentReplyWaitingIndicatorPolicy.turnKey(for: $0) == turn
    }
  }

  private func progressHeadline(_ event: DeliveryTraceEvent?, for message: ChatMessage) -> String {
    if let task = remoteAgentTask(message), task.checkingOtherSources {
      let turn = AgentReplyWaitingIndicatorPolicy.turnKey(for: message)
      let settled = messages.contains {
        !$0.isMine && !$0.isSystem && $0.deliveryStatus == .delivered && $0.conversationId == message.conversationId &&
          AgentReplyWaitingIndicatorPolicy.turnKey(for: $0) == turn
      }
      if !settled { return t("galaxyssi.agent.progress.research.checking", "Checking other sources") }
    }
    return event?.compactDetail ?? event?.detail ?? ""
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
    if let committed = committedProgress(message) {
      committedFooter(committed, message: message, task: agentTask(message), remote: remoteAgentTask(message))
    } else if let task = agentTask(message) {
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

  @ViewBuilder
  private func committedFooter(
    _ committed: AgentCommittedTurnProgress.Turn,
    message: ChatMessage,
    task: AgentTaskRecord? = nil,
    remote: AgentRemoteTaskStatusSnapshot? = nil
  ) -> some View {
    let fallbackStart = Int64(message.createdAt.timeIntervalSince1970 * 1_000)
    if committed.isRunning {
      TimelineView(.periodic(from: Date(), by: 1)) { context in
        committedFooterContent(committed, fallbackStart: fallbackStart, task: task, remote: remote,
          now: Int64(context.date.timeIntervalSince1970 * 1_000))
      }
    } else {
      committedFooterContent(committed, fallbackStart: fallbackStart, task: task, remote: remote, now: committed.updatedAt)
    }
  }

  private func committedFooterContent(
    _ committed: AgentCommittedTurnProgress.Turn,
    fallbackStart: Int64,
    task: AgentTaskRecord?,
    remote: AgentRemoteTaskStatusSnapshot?,
    now: Int64
  ) -> some View {
    let canCancel = committed.isRunning && (task.map(AgentTaskCenterPolicy.cancellable) ??
      remote.map { $0.isCancellable && !isRemoteTaskCancelling($0.id) } ?? false)
    return GalaxySSIAgentExecutionFooterView(
      completed: !committed.isRunning,
      duration: elapsedDuration(committed.elapsed(at: now, fallbackStart: fallbackStart)),
      details: task?.executionLog ?? remote?.history.map(remoteAgentTimelineLine) ?? [],
      detailsTitle: t("galaxyssi.agent.execution.timeline", "Execution timeline"),
      timelineActions: committed.status.isTerminal ? [] : task.map(timelineActions) ?? [],
      timelineActionTitle: timelineActionTitle,
      timelineActionIcon: timelineActionIcon,
      timelineActionMenuTitle: t("galaxyssi.agent.task_control.title", "Task controls"),
      onTimelineAction: { action in
        if let task { onTimelineAction(action, task) }
      },
      canCancel: canCancel,
      onCancel: {
        if let task { onCancelAgentTask(task) }
        else if let remote { onCancelRemoteTask(remote) }
      }
    )
  }
}
