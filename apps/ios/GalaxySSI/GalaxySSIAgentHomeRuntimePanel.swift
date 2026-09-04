import SwiftUI

extension AgentHomeView {
  var agentRuntimePanel: some View {
    GalaxySSIAgentRuntimePanelView(
      safetySettings: store.agentSafetySettings,
      taskExecutionMode: store.agentSafetySettings.taskExecutionMode,
      modelPlannerSettings: store.modelPlannerSettings,
      taskBudget: store.agentTaskBudget,
      callableTargets: availableCallableTargetCount,
      currentGoal: draft,
      currentApp: agentScreenSnapshot.screen.foregroundApp
        .ifBlank(agentScreenSnapshot.screen.pageTitle)
        .ifBlank("GalaxySSI iOS"),
      memorySnapshot: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      knowledgeHitCount: store.agentKnowledgeAccessAudit.count,
      recentTasks: agentRuntimeTasks,
      nativeTools: AgentPhoneNativeToolCatalog.descriptors(),
      auditRecords: agentRuntimeAuditRecords,
      onCyclePermissionMode: cycleAgentPermissionMode,
      onCycleTaskExecutionMode: cycleAgentTaskExecutionMode,
      onToggleHighRiskGuard: {
        store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
      },
      onToggleMemoryCapture: {
        store.updateAgentSafetySettings { $0.memoryCapture.toggle() }
      },
      onToggleExecutionPaused: {
        store.updateAgentSafetySettings { $0.executionPaused.toggle() }
      },
      onUpdatePendingAction: { taskId, actionId, description, input in
        coordinator.updatePendingLocalNativeAction(
          taskId: taskId,
          actionId: actionId,
          description: description,
          input: input
        )
      },
      onMovePendingAction: { taskId, actionId, offset in
        coordinator.movePendingLocalNativeAction(
          taskId: taskId,
          actionId: actionId,
          offset: offset
        )
      },
      onRemovePendingAction: { taskId, actionId in
        coordinator.removePendingLocalNativeAction(
          taskId: taskId,
          actionId: actionId
        )
      },
      onTaskAction: handleAgentRuntimeTaskAction,
      onOpenRecentTasks: {
        recentTasksShortcutActive = true
      },
      t: t
    )
  }

  var agentRuntimeTasks: [AgentTaskRecord] {
    let sessionID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionID.isEmpty else {
      return store.recentAgentTasks(limit: 12).filter(taskBelongsToActiveSession)
    }
    let scopedTasks = store.agentTasks(forSession: sessionID, limit: 12)
    if !scopedTasks.isEmpty {
      return scopedTasks
    }
    // Legacy task records may not have a session ID yet.
    return store.recentAgentTasks(limit: 12).filter(taskBelongsToActiveSession)
  }

  var shouldShowAgentRuntimePanel: Bool {
    activeExecutionTask != nil ||
      activeRemoteAgentTask != nil ||
      !agentRuntimeTasks.isEmpty
  }

}
