import SwiftUI

struct SignalASIAgentExecutionOverviewView: View {
  var activeRemoteAgentTask: AgentRemoteTaskStatusSnapshot?
  var activeExecutionTask: AgentTaskRecord?
  var actionQueueItems: [SignalASIAgentActionQueueItem]
  var screen: AgentScreenContext
  var screenSections: [SignalASIAgentScreenDetailSection]
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
  var onEditAction: (SignalASIAgentActionQueueItem) -> Void
  var onScreenCommand: (String) -> Void
  var onRefreshScreen: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let activeRemoteAgentTask {
        let completed = AgentRemoteTaskStatusPolicy.isTerminal(activeRemoteAgentTask.status)
        SignalASIAgentExecutionStatusCard(
          completed: completed,
          duration: executionDuration(
            activeRemoteAgentTask.history.first?.updatedAtMillis
              ?? activeRemoteAgentTask.updatedAtMillis,
            activeRemoteAgentTask.updatedAtMillis
          ),
          liveDurationStartMillis: activeRemoteAgentTask.history.first?.updatedAtMillis
            ?? activeRemoteAgentTask.updatedAtMillis,
          liveDurationFormatter: completed ? nil : liveExecutionDuration,
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
        let completed = [.completed, .failed, .cancelled, .blocked].contains(
          activeExecutionTask.phase
        )
        SignalASIAgentExecutionStatusCard(
          completed: completed,
          duration: executionDuration(
            activeExecutionTask.createdAtMillis,
            activeExecutionTask.updatedAtMillis
          ),
          liveDurationStartMillis: activeExecutionTask.createdAtMillis,
          liveDurationFormatter: completed ? nil : liveExecutionDuration,
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
