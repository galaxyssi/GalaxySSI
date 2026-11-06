import SwiftUI

struct GalaxySSIAgentTranscriptMessagesView: View {
  @State private var expandedProgress = Set<UUID>()
  var messages: [ChatMessage]
  var waitingMessageIDs: Set<UUID>
  var retryingMessageIDs: Set<UUID>
  var replySpeech: AgentReplySpeechRuntime
  var completedSpeech: AgentCompletedReplyPlayback
  var playCompletedReply: (ChatMessage, AgentReplyParagraphSpeechSelection?) -> Bool
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
    let latest = latestSpeechTarget
    let deliveredTimes = AgentTranscriptExecutionProgress.finalDeliveryTimes(messages)
    ForEach(messages) { message in
      let turn = AgentTranscriptExecutionProgress.TurnKey(message)
      messageRow(message, latestSpeechEntryId: latest?.entryId, deliveredAt: deliveredTimes[turn])
    }
    .onAppear { observeLatestReply(latest) }
    .onChange(of: latest) { target in
      observeLatestReply(target)
    }
    .onTapGesture(count: 2) {
      replySpeech.stopPlaybackIfActive()
    }
    .onDisappear {
      replySpeech.stop()
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in
      replySpeech.stop()
    }
  }

  @ViewBuilder
  private func messageRow(
    _ message: ChatMessage, latestSpeechEntryId: String?, deliveredAt: Int64?
  ) -> some View {
    let task = agentTask(message)
    let remote = remoteAgentTask(message).flatMap {
      $0.conversationId == message.conversationId &&
        (message.turnId.isBlank || $0.turnId == message.turnId || $0.taskId == message.turnId) ? $0 : nil
    }
    let voice = voiceAgentRun(message).flatMap {
      $0.conversationId.ifBlank($0.sessionId) == message.conversationId &&
        (message.turnId.isBlank || $0.turnId == message.turnId || $0.taskId == message.turnId) ? $0 : nil
    }
    let execution = executionProgress(message, task: task, remote: remote, voice: voice, deliveredAt: deliveredAt)
    let plan = message.isMine ? task.map {
      AgentInteractiveProgressPolicy.project(task: $0, status: execution?.status)
    } : nil
    VStack(alignment: .leading, spacing: 4) {
      if let mergedSource = mergedSourceLabel(message) {
        Text(mergedSource)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
          .accessibilityLabel(mergedSource)
      }
      if !message.isMine, !message.isSystem {
        if let execution { messageExecutionFooter(execution, task: task, remote: remote, voice: voice) }
      }
      agentMessageContent(message)
      if message.isMine {
        if let task, let plan, plan.visible {
          let sameState = plan.status == AgentInteractiveProgressStatus(task.phase)
          GalaxySSIAgentInteractiveProgressView(
            presentation: plan,
            timelineActions: sameState ? timelineActions(task) : [],
            timelineActionTitle: timelineActionTitle,
            timelineActionIcon: timelineActionIcon,
            t: t,
            canCancel: sameState && AgentTaskCenterPolicy.cancellable(task),
            onTimelineAction: { onTimelineAction($0, task) },
            onCancel: { onCancelAgentTask(task) }
          )
        } else if let execution, !hasReply(for: message) {
          messageExecutionFooter(execution, task: task, remote: remote, voice: voice)
        }
        let progress = message.deliveryTrace.filter { $0.stage.hasPrefix(AgentConnectorPublicProgress.tracePrefix) &&
          !AgentPublicProgressPolicy.isInternal($0.detail) }
        if !progress.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Button {
              if !expandedProgress.insert(message.id).inserted { expandedProgress.remove(message.id) }
            } label: {
              HStack(alignment: .top, spacing: 6) {
                Image(systemName: expandedProgress.contains(message.id) ? "chevron.up" : "chevron.down")
                Text(progress.last?.detail ?? "")
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
      if let target = AgentReplySpeechPresentationPolicy.target(message) {
        GalaxySSIAgentReplySpeechFooter(runtime: replySpeech, entryId: target.entryId,
          isLatest: latestSpeechEntryId == target.entryId,
          additionalUpdates: completedSpeech.footerUpdates(messageId: message.id)) {
          if playCompletedReply(message, nil) { return }
          completedSpeech.stop()
          replySpeech.toggle(target, settings: voiceSettings, languagePolicy: languagePolicy)
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
    if waitingMessageIDs.contains(message.id), execution == nil {
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

  private var latestSpeechTarget: AgentReplySpeechTarget? {
    AgentReplySpeechPresentationPolicy.latestTarget(messages)
  }

  private func observeLatestReply(_ target: AgentReplySpeechTarget?) {
    replySpeech.observe(
      target,
      settings: voiceSettings,
      languagePolicy: languagePolicy
    )
  }

  private func paragraphSpeechAction(
    _ message: ChatMessage
  ) -> ((AgentReplyParagraphSpeechSelection) -> Void)? {
    guard let target = AgentReplySpeechPresentationPolicy.target(message) else { return nil }
    return { selection in
      if playCompletedReply(message, selection) { return }
      completedSpeech.stop()
      replySpeech.readFromParagraph(
        selection,
        target: target,
        settings: voiceSettings,
        languagePolicy: languagePolicy
      )
    }
  }

  private func executionProgress(
    _ message: ChatMessage, task: AgentTaskRecord?, remote: AgentRemoteTaskStatusSnapshot?,
    voice: VoiceAgentRunSnapshot?, deliveredAt: Int64?
  ) -> AgentTranscriptExecutionProgress? {
    let committed = committedProgress(message).map(AgentTranscriptExecutionProgress.committed)
    let remoteProgress = remote.map {
      AgentTranscriptExecutionProgress(status: AgentTranscriptExecutionProgress.remoteStatus($0.status),
        startedAt: $0.history.first?.updatedAtMillis ?? $0.updatedAtMillis,
        updatedAt: AgentProcessClockPolicy.pausesRemoteClock($0.status)
          ? AgentProcessClockPolicy.remotePauseTimestamp($0) : $0.updatedAtMillis)
    }
    let voiceProgress = voice.map {
      AgentTranscriptExecutionProgress(status: AgentTranscriptExecutionProgress.voiceStatus($0.state),
        startedAt: $0.acceptedAtMillis > 0 ? $0.acceptedAtMillis : $0.createdAtMillis, updatedAt: $0.updatedAtMillis)
    }
    let owned = [committed, remoteProgress, voiceProgress].compactMap { $0 }
      .reduce(nil as AgentTranscriptExecutionProgress?) { current, candidate in
        guard let current else { return candidate }
        return current.updatedAt >= candidate.updatedAt ? current : candidate
      }
    let cached = task.map {
      AgentTranscriptExecutionProgress(status: AgentInteractiveProgressStatus($0.phase),
        startedAt: $0.createdAtMillis, updatedAt: $0.updatedAtMillis)
    }
    return AgentTranscriptExecutionProgress.resolve(owned: owned, cached: cached, deliveredAt: deliveredAt)
  }

  private func messageExecutionFooter(
    _ progress: AgentTranscriptExecutionProgress, task: AgentTaskRecord?,
    remote: AgentRemoteTaskStatusSnapshot?, voice: VoiceAgentRunSnapshot?
  ) -> some View {
    let local = task.flatMap { AgentInteractiveProgressStatus($0.phase) == progress.status ? $0 : nil }
    let remoteCanCancel = remote.map {
      AgentTranscriptExecutionProgress.remoteStatus($0.status) == progress.status &&
        $0.isCancellable && !isRemoteTaskCancelling($0.id)
    } ?? false
    let voiceCanCancel = voice.map {
      AgentTranscriptExecutionProgress.voiceStatus($0.state) == progress.status &&
        $0.cancellable && !isVoiceRunCancelling($0.runId)
    } ?? false
    let canCancel = local.map(AgentTaskCenterPolicy.cancellable) ?? (remoteCanCancel || voiceCanCancel)
    return GalaxySSIAgentExecutionFooterView(
      status: progress.status,
      duration: executionDuration(progress.startedAt, progress.updatedAt),
      details: task?.executionLog ?? remote?.history.map(remoteAgentTimelineLine) ??
        voice.map { [$0.progressMessage, $0.partialResult, $0.resultSummary] } ?? [],
      detailsTitle: t("galaxyssi.agent.execution.timeline", "Execution timeline"),
      timelineActions: local.map(timelineActions) ?? [],
      timelineActionTitle: timelineActionTitle,
      timelineActionIcon: timelineActionIcon,
      timelineActionMenuTitle: t("galaxyssi.agent.task_control.title", "Task controls"),
      onTimelineAction: { action in
        if let local { onTimelineAction(action, local) }
      },
      canCancel: canCancel,
      onCancel: {
        if let local { onCancelAgentTask(local) }
        else if remoteCanCancel, let remote { onCancelRemoteTask(remote) }
        else if voiceCanCancel, let voice { onCancelVoiceRun(voice) }
      },
      liveStartedAt: progress.startedAt,
      liveDuration: elapsedDuration
    )
  }
}
