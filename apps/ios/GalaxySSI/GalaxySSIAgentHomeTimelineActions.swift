import Foundation

extension AgentHomeView {
  func retryAgentMessage(_ message: ChatMessage) {
    guard message.isMine,
          message.deliveryStatus == .failed,
          !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          retryingAgentMessageIDs.insert(message.id).inserted else {
      return
    }
    Task { @MainActor in
      _ = await coordinator.send(message.content, to: contact, requestKind: message.requestKind, researchRetrySource: message)
      retryingAgentMessageIDs.remove(message.id)
    }
  }

  func resumeActiveAgentTask(_ task: AgentTaskRecord) {
    richActionStatus = coordinator.resumeLocalNativeAction(taskId: task.taskId)
      ? t("galaxyssi.agent.task_control.resumed", "Task resumed")
      : t("galaxyssi.agent.task_control.resume_failed", "This task could not be resumed")
    resumePendingAgentDeliveryAfterTaskAction()
  }

  func resumePendingAgentDeliveryAfterTaskAction() {
    coordinator.resumePendingAgentDelivery()
    coordinator.refreshAgentHomeState()
  }

  func agentTimelineActions(for task: AgentTaskRecord) -> [AgentExecutionLoopTimelineAction] {
    if AgentBlockedOutcomePolicy.isWaiting(task) {
      var actions: [AgentExecutionLoopTimelineAction] = []
      if AgentBlockedOutcomePolicy.canResume(task) { actions.append(.resume) }
      if AgentTaskCenterPolicy.cancellable(task) { actions.append(.cancel) }
      return actions
    }
    let actions: [AgentExecutionLoopTimelineAction] = task.capturePermission != nil && task.phase == .waitingResponse
      ? [.pause, .cancel] : AgentExecutionLoopTimelinePolicy.actionsForPhase(task.phase)
    return actions.filter { action in
      switch action {
      case .pause:
        return AgentTaskCenterPolicy.pauseable(task)
      case .resume:
        return AgentTaskCenterPolicy.resumable(task)
      case .cancel:
        return AgentTaskCenterPolicy.cancellable(task)
      case .retry:
        return (task.effectRecovery ?? []).isEmpty && AgentTaskCenterPolicy.isReusableGoal(task.goal)
      case .replan:
        return AgentTaskCenterPolicy.isReusableGoal(task.goal)
      }
    }
  }

  func runAgentTimelineAction(
    _ action: AgentExecutionLoopTimelineAction,
    task: AgentTaskRecord
  ) {
    guard timelineActionTaskIDsInFlight.insert(task.taskId).inserted else { return }
    defer { timelineActionTaskIDsInFlight.remove(task.taskId) }

    let currentTask = store.agentTask(id: task.taskId) ?? task
    guard agentTimelineActions(for: currentTask).contains(where: { $0.rawValue == action.rawValue }) else {
      richActionStatus = t(
        "galaxyssi.agent.task_control.unavailable",
        "This task action is no longer available"
      )
      return
    }

    switch action {
    case .pause:
      richActionStatus = coordinator.pauseLocalNativeAction(taskId: task.taskId)
        ? t("galaxyssi.agent.task_control.paused", "Task paused")
        : t("galaxyssi.agent.task_control.pause_failed", "This task could not be paused")
      resumePendingAgentDeliveryAfterTaskAction()
    case .resume:
      if AgentBlockedOutcomePolicy.isWaiting(currentTask) {
        retryAgentTask(currentTask, mode: .replan)
      } else {
        resumeActiveAgentTask(currentTask)
      }
    case .cancel:
      cancelActiveAgentTask(task)
    case .retry:
      retryAgentTask(task, mode: .retry)
    case .replan:
      retryAgentTask(task, mode: .replan)
    }
  }

  func agentTimelineActionTitle(_ action: AgentExecutionLoopTimelineAction) -> String {
    switch action {
    case .pause:
      return t("galaxyssi.agent.task_control.pause", "Pause task")
    case .resume:
      return t("galaxyssi.agent.resume_task", "Resume task")
    case .retry:
      return t("galaxyssi.common.retry", "Retry")
    case .replan:
      return t("galaxyssi.agent.task_control.replan", "Re-plan task")
    case .cancel:
      return t("galaxyssi.common.cancel_task", "Cancel task")
    }
  }

  func agentTimelineActionIcon(_ action: AgentExecutionLoopTimelineAction) -> String {
    switch action {
    case .pause:
      return "pause.fill"
    case .resume:
      return "play.fill"
    case .retry:
      return "arrow.clockwise"
    case .replan:
      return "arrow.triangle.2.circlepath"
    case .cancel:
      return "xmark.circle"
    }
  }

  func cancelActiveAgentTask(_ task: AgentTaskRecord) {
    richActionStatus = coordinator.cancelLocalAgentTask(taskId: task.taskId)
      ? t("galaxyssi.agent.task_control.cancelled", "Task cancelled")
      : t("galaxyssi.agent.task_control.cancel_failed", "This task could not be cancelled")
    resumePendingAgentDeliveryAfterTaskAction()
  }

}
