import SwiftUI

struct SignalASIAgentExecutionOverviewView: View {
  var activeRemoteAgentTask: AgentRemoteTaskStatusSnapshot?
  var activeExecutionTask: AgentTaskRecord?
  var actionQueueItems: [SignalASIAgentActionQueueItem]
  var activePhase: AgentPhase?
  var executionPaused: Bool
  var screen: AgentScreenContext
  var screenSections: [SignalASIAgentScreenDetailSection]
  var t: (String, String) -> String

  var remoteStatusLabel: (String) -> String
  var remoteStep: (AgentRemoteTaskStatusSnapshot) -> String
  var remoteTimelineLine: (AgentRemoteTaskStatusEvent) -> String
  var phaseLabel: (AgentPhase) -> String
  var executionLocationSummary: (AgentTaskRecord) -> String
  var executionStep: (AgentTaskRecord) -> String
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
  var onEditAction: (SignalASIAgentActionQueueItem) -> Void
  var onScreenCommand: (String) -> Void
  var onRefreshScreen: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let activeRemoteAgentTask {
        SignalASIAgentExecutionStatusCard(
          executor: activeRemoteAgentTask.target,
          status: remoteStatusLabel(activeRemoteAgentTask.status),
          location: activeRemoteAgentTask.location,
          step: remoteStep(activeRemoteAgentTask),
          duration: executionDuration(
            activeRemoteAgentTask.history.first?.updatedAtMillis
              ?? activeRemoteAgentTask.updatedAtMillis,
            activeRemoteAgentTask.updatedAtMillis
          ),
          liveDurationStartMillis: activeRemoteAgentTask.history.first?.updatedAtMillis
            ?? activeRemoteAgentTask.updatedAtMillis,
          liveDurationFormatter: liveExecutionDuration,
          detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
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
        SignalASIAgentExecutionStatusCard(
          executor: activeExecutionTask.targetTitle.ifBlank(t("signalasi.agent.status", "Agent")),
          status: phaseLabel(activeExecutionTask.phase),
          location: executionLocationSummary(activeExecutionTask),
          step: executionStep(activeExecutionTask),
          duration: executionDuration(
            activeExecutionTask.createdAtMillis,
            activeExecutionTask.updatedAtMillis
          ),
          liveDurationStartMillis: activeExecutionTask.createdAtMillis,
          liveDurationFormatter: liveExecutionDuration,
          detailsTitle: t("signalasi.agent.execution.timeline", "Execution timeline"),
          details: activeExecutionTask.executionLog,
          canResume: false,
          resumeTitle: "",
          canCancel: AgentTaskCenterPolicy.cancellable(activeExecutionTask),
          cancelTitle: t("signalasi.agent.task_control.cancel", "Cancel task"),
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

      if !actionQueueItems.isEmpty {
        SignalASIAgentActionQueueCard(
          items: actionQueueItems,
          onEditAction: onEditAction,
          t: t
        )
      }

      AgentProcessCard(
        activePhase: activePhase,
        executionPaused: executionPaused
      )
      SignalASIAgentScreenContextCard(
        screen: screen,
        sections: screenSections,
        onCommand: onScreenCommand,
        t: t,
        onRefresh: onRefreshScreen
      )
    }
  }
}
