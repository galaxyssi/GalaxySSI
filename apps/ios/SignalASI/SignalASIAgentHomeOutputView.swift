import SwiftUI

extension AgentHomeView {
  var agentOutput: some View {
    SignalASIAgentHomeTranscriptView(
      visibleMessageLimit: $visibleAgentMessageLimit,
      olderTranscriptAnchor: $olderTranscriptAnchor,
      transcriptTopLoadTriggered: $transcriptTopLoadTriggered,
      transcriptAutoFollow: $transcriptAutoFollow,
      transcriptShowLatestButton: $transcriptShowLatestButton,
      transcriptContentMinY: $transcriptContentMinY,
      agentSwipeRequest: agentSwipeRequest,
      pendingAgentSwipeDirection: $pendingAgentSwipeDirection,
      activeAgentConversationID: store.activeAgentConversationId,
      messages: messages,
      transcriptMessages: transcriptMessages,
      hasOlderTranscriptMessages: hasOlderTranscriptMessages,
      latestWaitingIndicatorID: latestWaitingIndicatorID,
      waitingIndicatorCount: waitingIndicatorCount,
      voiceTranscriptionPending: voiceTranscriptionPending,
      voicePendingAttachments: voicePendingAttachments,
      waitingForAgentReply: waitingForAgentReply,
      activeAgentPhase: activeAgentPhase,
      activeAgentTasks: activeAgentTasks,
      pageSize: Self.agentTranscriptPageSize,
      reduceMotion: deviceInputPolicy.reduceMotion,
      voiceTranscriptionPendingViewID: Self.voiceTranscriptionPendingViewId,
      replyWaitingViewID: Self.replyWaitingViewId,
      latestButtonTitle: t("signalasi.agent.latest", "Back to latest"),
      onLoadOlderTranscriptMessages: loadOlderTranscriptMessages,
      onMessagesChanged: {
        if voiceTranscriptionPending && !messages.isEmpty {
          voiceTranscriptionPending = false
        }
        store.markContactRead(contact.id)
        refreshAgentRuntimeAuditRecords()
      },
      onExecutionStateChanged: refreshAgentRuntimeAuditRecords
    ) {
      LazyVStack(spacing: 5) {
          SignalASIAgentHomeExecutionAlertsView(
            scanStatus: scanStatus,
            scanStatusIsError: scanStatusIsError,
            activeVoiceAgentRuns: activeVoiceAgentRuns,
            cancellableVoiceAgentRuns: activeVoiceAgentRuns.filter {
              voiceRunRemoteTask($0)?.isCancellable == true
            },
            cancellingVoiceRunIDs: cancellingVoiceRunIDs,
            manualRouteWarning: manualRouteWarning,
            automaticRouteWarning: automaticRouteWarning,
            hasOlderTranscriptMessages: hasOlderTranscriptMessages,
            pendingConfirmationTask: pendingConfirmationTask,
            blockedAgentTask: blockedAgentTask,
            retryingAgentTaskIDs: retryingAgentTaskIDs,
            t: t,
            onRetryScan: {
              scanStatus = ""
              scanShortcutActive = true
            },
            onDismissScan: { scanStatus = "" },
            onCancelVoiceRun: cancelVoiceAgentRun,
            onOpenModelSelection: {
              modelSelection = AgentModelSelectionSettings.selection(
                for: store.activeAgentConversationId
              )
            },
            onLoadOlderTranscriptMessages: loadOlderTranscriptMessages,
            onApproveOnce: { task in
              requestAgentTaskApproval(task)
            },
            onApproveSession: { task in
              requestAgentTaskApproval(task, sessionScoped: true)
            },
            onApproveAlways: { task in
              requestAgentTaskApproval(task, remember: true)
            },
            onDeny: { task in
              coordinator.denyLocalNativeAction(taskId: task.taskId)
            },
            onRetryBlockedTask: retryBlockedAgentTask,
            onReplanBlockedTask: { task in
              retryAgentTask(task, mode: .replan)
            }
          )
          if let recoverableAgentTask = recoverableAgentTasksFromOtherSessions.first {
            recoverableAgentTaskBanner(recoverableAgentTask)
          }
          if !messages.isEmpty ||
              voiceTranscriptionPending ||
              pendingConfirmationTask != nil ||
              blockedAgentTask != nil ||
              activeExecutionTask != nil ||
              activeRemoteAgentTask != nil ||
              !activeVoiceAgentRuns.isEmpty ||
              !recoverableAgentTasksFromOtherSessions.isEmpty {
            SignalASIAgentExecutionOverviewView(
              activeRemoteAgentTask: activeRemoteAgentTask,
              activeExecutionTask: activeExecutionTask,
              actionQueueItems: agentActionQueueItems,
              activePhase: activeAgentPhase,
              executionPaused: store.agentSafetySettings.executionPaused,
              screen: agentScreenSnapshot.screen,
              screenSections: agentScreenSnapshot.sections,
              t: t,
              remoteStatusLabel: remoteAgentStatusLabel,
              remoteStep: remoteAgentStep,
              remoteTimelineLine: remoteAgentTimelineLine,
              phaseLabel: agentPhaseLabel,
              executionLocationSummary: agentExecutionLocationSummary,
              executionStep: agentExecutionStep,
              executionDuration: { startedAtMillis, updatedAtMillis in
                executionDuration(
                  startedAtMillis: startedAtMillis,
                  updatedAtMillis: updatedAtMillis
                )
              },
              liveExecutionDuration: { elapsedMillis in
                executionDuration(elapsedMillis: elapsedMillis)
              },
              timelineActions: { task in agentTimelineActions(for: task) },
              timelineActionTitle: agentTimelineActionTitle,
              timelineActionIcon: agentTimelineActionIcon,
              isRemoteTaskCancelling: { taskID in
                cancellingRemoteTaskIDs.contains(taskID)
              },
              remoteCancellationTitle: { isCancelling in
                isCancelling
                  ? t("signalasi.agent.remote_status.cancelling", "Cancelling...")
                  : t("signalasi.agent.remote_status.cancel", "Cancel task")
              },
              onCancelRemoteTask: cancelRemoteAgentTask,
              onCancelExecutionTask: cancelActiveAgentTask,
              onTimelineAction: { action, task in
                runAgentTimelineAction(action, task: task)
              },
              onEditAction: { item in
                homeActionEditorSelection = SignalASIAgentRuntimeActionSelection(
                  task: item.task,
                  action: item.action
                )
              },
              onScreenCommand: prefillAgentScreenCommand,
              onRefreshScreen: refreshAgentScreenContext
            )
            SignalASIAgentTranscriptMessagesView(
              messages: transcriptMessages,
              waitingMessageIDs: waitingMessageIDs,
              retryingMessageIDs: retryingAgentMessageIDs,
              t: t,
              mergedSourceLabel: { mergedSourceLabel(for: $0) },
              agentTask: { agentTask(for: $0) },
              remoteAgentTask: { remoteAgentTask(for: $0) },
              voiceAgentRun: { voiceAgentRun(for: $0) },
              agentPhaseLabel: agentPhaseLabel,
              agentExecutionLocationSummary: agentExecutionLocationSummary,
              agentExecutionStep: agentExecutionStep,
              remoteAgentStatusLabel: remoteAgentStatusLabel,
              remoteAgentStep: remoteAgentStep,
              remoteAgentTimelineLine: remoteAgentTimelineLine,
              executionDuration: { startedAtMillis, updatedAtMillis in
                executionDuration(
                  startedAtMillis: startedAtMillis,
                  updatedAtMillis: updatedAtMillis
                )
              },
              timelineActions: { task in agentTimelineActions(for: task) },
              timelineActionTitle: agentTimelineActionTitle,
              timelineActionIcon: agentTimelineActionIcon,
              isRemoteTaskCancelling: { taskID in
                cancellingRemoteTaskIDs.contains(taskID)
              },
              isVoiceRunCancelling: { runID in
                cancellingVoiceRunIDs.contains(runID)
              },
              onRichAction: { message, action in
                handleRichAction(action, from: message)
              },
              onFormSubmit: handleAgentRichForm,
              onCancelAgentTask: cancelActiveAgentTask,
              onCancelRemoteTask: cancelRemoteAgentTask,
              onCancelVoiceRun: cancelVoiceAgentRun,
              onTimelineAction: { action, task in
                runAgentTimelineAction(action, task: task)
              },
              onCopyMessage: { message in
                UIPasteboard.general.string = message.content
              },
              onDeleteMessage: { message in
                store.deleteMessage(message.id, contactId: contact.id)
              },
              onRetryMessage: retryAgentMessage
            )
            ForEach(unboundWaitingTurnIDs, id: \.self) { turnID in
              AgentReplyWaitingIndicatorView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(AgentReplyWaitingIndicatorPolicy.viewID(forTurnID: turnID))
            }
            if voiceTranscriptionPending {
              if !voicePendingAttachments.isEmpty {
                SignalASIAgentVoiceAttachmentSummaryView(
                  attachments: voicePendingAttachments,
                  t: t
                )
              }
              SignalASIVoiceTranscriptionPendingView()
                .id(Self.voiceTranscriptionPendingViewId)
            }
            if waitingForAgentReply {
              AgentReplyWaitingIndicatorView()
                .id(Self.replyWaitingViewId)
            }
            if shouldShowAgentRuntimePanel {
              agentRuntimePanel
                .padding(.top, 2)
                .transition(.opacity)
            }
          }
        }
      }
  }

}
