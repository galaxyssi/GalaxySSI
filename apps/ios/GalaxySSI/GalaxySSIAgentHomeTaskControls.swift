import UIKit

extension AgentHomeView {
  func handlePendingAgentTaskAction() {
    guard let task = primaryAgentTask else { return }
    guard pendingPrimaryActionTaskID != task.taskId else { return }
    pendingPrimaryActionTaskID = task.taskId
    defer {
      let taskID = task.taskId
      DispatchQueue.main.async {
        if pendingPrimaryActionTaskID == taskID {
          pendingPrimaryActionTaskID = nil
        }
      }
    }
    if task.phase == .waitingResponse {
      richActionStatus = t(
        "agent_status_waiting_response",
        "Waiting for an Agent response."
      )
    } else if task.phase == .waitingConfirmation {
      if requestAgentTaskApproval(task) {
        richActionStatus = t(
          "galaxyssi.agent.approval_status.approved",
          "The Agent action was approved."
        )
      }
    } else if task.phase == .paused {
      _ = coordinator.resumeLocalNativeAction(taskId: task.taskId)
    } else {
      coordinator.cancelLocalNativeAction(taskId: task.taskId)
    }
  }

  @discardableResult
  func requestAgentTaskApproval(
    _ task: AgentTaskRecord,
    remember: Bool = false,
    sessionScoped: Bool = false
  ) -> Bool {
    guard let action = task.pendingAction else { return false }
    if action.risk.weight >= AgentRisk.high.weight {
      pendingHighRiskApprovalTask = task
      return false
    }
    coordinator.approveLocalNativeAction(
      taskId: task.taskId,
      remember: remember,
      sessionScoped: sessionScoped
    )
    resumePendingAgentDeliveryAfterTaskAction()
    return true
  }

  func approveHighRiskTask(_ task: AgentTaskRecord) {
    guard taskBelongsToActiveSession(task),
          let current = store.agentTask(id: task.taskId),
          current.phase == .waitingConfirmation,
          let action = current.pendingAction,
          action.risk.weight >= AgentRisk.high.weight else {
      pendingHighRiskApprovalTask = nil
      return
    }
    coordinator.approveLocalNativeAction(
      taskId: current.taskId,
      highRiskConfirmed: true
    )
    resumePendingAgentDeliveryAfterTaskAction()
    pendingHighRiskApprovalTask = nil
  }

  func handleAgentRuntimeTaskAction(
    _ action: AgentTaskCenterAction,
    task: AgentTaskRecord
  ) {
    switch action {
    case .cancel:
      richActionStatus = coordinator.cancelLocalAgentTask(taskId: task.taskId)
        ? t("galaxyssi.agent.task_control.cancelled", "Task cancelled")
        : t("galaxyssi.agent.task_control.cancel_failed", "This task could not be cancelled")
      resumePendingAgentDeliveryAfterTaskAction()
    case .resume:
      richActionStatus = coordinator.resumeLocalNativeAction(taskId: task.taskId)
        ? t("galaxyssi.agent.task_control.resumed", "Task resumed")
        : t("galaxyssi.agent.task_control.resume_failed", "This task could not be resumed")
      resumePendingAgentDeliveryAfterTaskAction()
    case .retry:
      retryAgentTask(task, mode: .retry)
    case .rollback:
      richActionStatus = coordinator.rollbackLastLocalNativeAction(taskId: task.taskId)
        ? t("galaxyssi.agent.task_control.rollback_requested", "Rollback requested")
        : t("galaxyssi.agent.task_control.rollback_failed", "This action cannot be rolled back")
      resumePendingAgentDeliveryAfterTaskAction()
    case .copy:
      copyAgentRuntimeTask(task)
    case .viewLog:
      richActionStatus = task.executionLog.isEmpty
        ? t("galaxyssi.agent_task_center.log_empty", "No execution log yet")
        : t("galaxyssi.agent_task_center.log_ready", "Execution log is shown below")
    case .delete:
      let deleted = store.deleteAgentTask(id: task.taskId)
      richActionStatus = t(
        deleted ? "galaxyssi.agent_task_center.deleted" : "galaxyssi.agent_task_center.delete_failed",
        deleted ? "Task deleted" : "The task could not be deleted"
      )
    }
  }

  func handleHomeTaskAction(
    _ action: AgentTaskCenterAction,
    task: AgentTaskRecord
  ) {
    if action == .viewLog {
      recentTaskForDetails = task
      recentTasksShortcutActive = true
    } else if action == .delete {
      homeTaskPendingDeletion = task
    } else {
      handleAgentRuntimeTaskAction(action, task: task)
    }
  }

  func copyAgentRuntimeTask(_ task: AgentTaskRecord) {
    let execution = AgentExecutionPresentationPolicy.location(record: task)
    var lines = [
      task.goal.ifBlank(task.taskId),
      "",
      "\(t("galaxyssi.agent_task_detail.status", "Status")): \(agentPhaseLabel(task.phase))",
      "\(t("galaxyssi.agent_task_detail.execution", "Execution")): \(execution.locationName.ifBlank("-"))",
      "\(t("galaxyssi.agent_task_detail.route", "Route")): \(task.routeKind.rawValue.lowercased().replacingOccurrences(of: "_", with: " "))",
      "\(t("galaxyssi.agent_task_detail.target", "Agent or model")): \(task.targetTitle.ifBlank("-"))",
      "\(t("galaxyssi.agent_task_detail.risk", "Risk")): \(task.risk.rawValue.lowercased())"
    ]
    if let context = task.planContext {
      let route = [
        context.routeKind.rawValue.lowercased().replacingOccurrences(of: "_", with: " "),
        context.routeTargetTitle,
        context.routeStatus
      ]
        .filter { !$0.isBlank }
        .joined(separator: " / ")
      lines += ["", t("agent_section_plan_context", "Plan context")]
      lines += [
        String(format: t("agent_plan_context_planner", "Planner") + ": %@", context.plannerProfile.ifBlank("-")),
        String(format: t("agent_plan_context_route", "Route") + ": %@", route.ifBlank("-")),
        String(format: t("agent_plan_context_reason", "Route rationale") + ": %@", context.routeRationale.ifBlank("-")),
        String(format: t("agent_plan_context_expected", "Expected result") + ": %@", context.expectedResult.ifBlank("-")),
        String(format: t("agent_plan_context_rollback", "Rollback strategy") + ": %@", context.rollbackStrategy.ifBlank("-")),
        String(format: t("galaxyssi.agent_runtime.plan_revision_detail", "Revision %d / %d replans"), context.revision, context.replanCount),
        String(format: t("galaxyssi.agent_runtime.plan_checkpoint_detail", "%d active / %d history actions"), context.activeCheckpointCount, context.actionHistoryCount),
        String(format: t("galaxyssi.agent_runtime.plan_tool_graph_timeout_detail", "Depth %d / %d permissions / %ds timeout"), context.toolGraphDepth, context.requiredPermissionCount, context.timeoutSeconds)
      ]
    }
    if !task.result.isBlank {
      lines += ["", t("galaxyssi.agent_task_detail.result", "Result"), task.result]
    }
    if !task.verification.isBlank {
      lines += ["", t("galaxyssi.agent_task_detail.verification", "Verification"), task.verification]
    }
    if !task.executionLog.isEmpty {
      lines += ["", t("galaxyssi.agent_task_detail.timeline", "Execution timeline")]
      lines += task.executionLog
    }
    UIPasteboard.general.string = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    richActionStatus = t("galaxyssi.agent_task_center.copied", "Task details copied")
  }

}
