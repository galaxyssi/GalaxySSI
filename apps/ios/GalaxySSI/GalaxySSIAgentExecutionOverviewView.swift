import SwiftUI

struct GalaxySSIAgentExecutionOverviewView: View {
  var activeRemoteAgentTask: AgentRemoteTaskStatusSnapshot?
  var activeExecutionTask: AgentTaskRecord?
  var actionQueueItems: [GalaxySSIAgentActionQueueItem]
  var screen: AgentScreenContext
  var screenSections: [GalaxySSIAgentScreenDetailSection]
  var t: (String, String) -> String

  var remoteTimelineLine: (AgentRemoteTaskStatusEvent) -> String
  var executionDuration: (Int64, Int64) -> String
  var liveExecutionDuration: (Int64) -> String
  var timelineActions: (AgentTaskRecord) -> [AgentExecutionLoopTimelineAction]
  var timelineActionTitle: (AgentExecutionLoopTimelineAction) -> String
  var timelineActionIcon: (AgentExecutionLoopTimelineAction) -> String
  var isRemoteTaskCancelling: (String) -> Bool
  var remoteCancellationTitle: (Bool) -> String

  var onCancelRemoteTask: (AgentRemoteTaskStatusSnapshot) -> Void
  var onCancelExecutionTask: (AgentTaskRecord) -> Void
  var onTimelineAction: (AgentExecutionLoopTimelineAction, AgentTaskRecord) -> Void
  var onEditAction: (GalaxySSIAgentActionQueueItem) -> Void
  var onScreenCommand: (String) -> Void
  var onRefreshScreen: () -> Void
  var onChangeAgent: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let activeRemoteAgentTask {
        let completed = AgentRemoteTaskStatusPolicy.isTerminal(activeRemoteAgentTask.status)
        let paused = AgentProcessClockPolicy.pausesRemoteClock(activeRemoteAgentTask.status)
        let status = AgentTranscriptExecutionProgress.remoteStatus(activeRemoteAgentTask.status)
        GalaxySSIAgentExecutionStatusCard(
          completed: completed,
          duration: executionDuration(
            activeRemoteAgentTask.history.first?.updatedAtMillis
              ?? activeRemoteAgentTask.updatedAtMillis,
            paused ? AgentProcessClockPolicy.remotePauseTimestamp(activeRemoteAgentTask) : activeRemoteAgentTask.updatedAtMillis
          ),
          liveDurationStartMillis: activeRemoteAgentTask.history.first?.updatedAtMillis
            ?? activeRemoteAgentTask.updatedAtMillis,
          liveDurationFormatter: completed || paused ? nil : liveExecutionDuration,
          inactiveTitle: status == .running || status == .completed ? "" : status.title(t),
          detailsTitle: t("galaxyssi.agent.execution.timeline", "Execution timeline"),
          details: activeRemoteAgentTask.history.map(remoteTimelineLine),
          canResume: false,
          resumeTitle: "",
          canCancel: activeRemoteAgentTask.isCancellable &&
            !isRemoteTaskCancelling(activeRemoteAgentTask.id),
          cancelTitle: remoteCancellationTitle(
            isRemoteTaskCancelling(activeRemoteAgentTask.id)
          ),
          onResume: {},
          onCancel: {
            onCancelRemoteTask(activeRemoteAgentTask)
          }
        )
      }

      if let activeExecutionTask {
        let completed = [.completed, .failed, .cancelled].contains(
          activeExecutionTask.phase
        )
        let paused = AgentProcessClockPolicy.pausesLocalClock(activeExecutionTask.phase)
        let progress = AgentInteractiveProgressPolicy.project(task: activeExecutionTask)
        if progress.visible {
          GalaxySSIAgentInteractiveProgressView(
            presentation: progress,
            timelineActions: timelineActions(activeExecutionTask),
            timelineActionTitle: timelineActionTitle,
            timelineActionIcon: timelineActionIcon,
            t: t,
            canCancel: AgentTaskCenterPolicy.cancellable(activeExecutionTask),
            onTimelineAction: { action in
              onTimelineAction(action, activeExecutionTask)
            },
            onCancel: {
              onCancelExecutionTask(activeExecutionTask)
            },
            onChangeAgent: onChangeAgent
          )
        } else {
          GalaxySSIAgentExecutionStatusCard(
            completed: completed,
            duration: executionDuration(
              activeExecutionTask.createdAtMillis,
              activeExecutionTask.updatedAtMillis
            ),
            liveDurationStartMillis: activeExecutionTask.createdAtMillis,
            liveDurationFormatter: completed || paused ? nil : liveExecutionDuration,
            inactiveTitle: localInactiveTitle(activeExecutionTask.phase),
            detailsTitle: t("galaxyssi.agent.execution.timeline", "Execution timeline"),
            details: activeExecutionTask.executionLog,
            canResume: false,
            resumeTitle: "",
            canCancel: AgentTaskCenterPolicy.cancellable(activeExecutionTask),
            cancelTitle: t("galaxyssi.agent.task_control.cancel", "Cancel task"),
            onResume: {},
            onCancel: {
              onCancelExecutionTask(activeExecutionTask)
            },
            timelineActions: timelineActions(activeExecutionTask),
            timelineActionTitle: timelineActionTitle,
            timelineActionIcon: timelineActionIcon,
            onTimelineAction: { action in
              onTimelineAction(action, activeExecutionTask)
            }
          )
        }
      }

      if !actionQueueItems.isEmpty {
        GalaxySSIAgentActionQueueCard(
          items: actionQueueItems,
          onEditAction: onEditAction,
          t: t
        )
      }

      GalaxySSIAgentScreenContextCard(
        screen: screen,
        sections: screenSections,
        onCommand: onScreenCommand,
        t: t,
        onRefresh: onRefreshScreen
      )
    }
  }

  private func localInactiveTitle(_ phase: AgentPhase) -> String {
    let status = AgentInteractiveProgressStatus(phase)
    return status == .running || status == .completed ? "" : status.title(t)
  }
}
