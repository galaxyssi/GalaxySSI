import SwiftUI

struct GalaxySSIAgentHomeEmptyStatePanel: View {
  var title: String
  var subtitle: String
  var runningTasks: Int
  var callableTargets: Int
  var nativeToolSummary: (total: Int, available: Int)
  var nativeTools: [AgentNativeToolDescriptor]
  var screenObservationAllowed: Bool
  var executionPaused: Bool
  var currentApp: String
  var memorySnapshot: AgentMemorySnapshot
  var knowledgeStats: AgentKnowledgeStats
  var knowledgeHitCount: Int
  var screen: AgentScreenContext
  var screenSections: [GalaxySSIAgentScreenDetailSection]
  var recentTaskCount: Int
  var recentTasks: [AgentTaskRecord]
  var permissionMode: AgentPermissionMode
  var highRiskGuard: Bool
  var memoryCapture: Bool
  var taskExecutionMode: AgentTaskExecutionMode
  var routeTitle: String
  var routeSubtitle: String
  var routeStatus: String
  var routeReady: Bool
  var t: (String, String) -> String
  var onNewSession: () -> Void
  var onOpenSessions: () -> Void
  var onScan: () -> Void
  var onTakePhoto: () -> Void
  var onAddFile: () -> Void
  var onCyclePermissionMode: () -> Void
  var onToggleHighRiskGuard: () -> Void
  var onToggleMemoryCapture: () -> Void
  var onCycleTaskExecutionMode: () -> Void
  var onToggleExecutionPaused: () -> Void
  var onOpenRecentTasks: () -> Void
  var onOpenRecentTask: (AgentTaskRecord) -> Void
  var onTaskAction: (AgentTaskCenterAction, AgentTaskRecord) -> Void
  var onModelSelectionChanged: () -> Void
  var onOpenRouteSelection: () -> Void
  var onScreenCommand: (String) -> Void
  var onRefreshScreenContext: () -> Void

  var body: some View {
    GalaxySSIAgentEmptyStateView(title: title, subtitle: subtitle)
    GalaxySSIAgentHomeQuickActionsView(
      t: t,
      onNewSession: onNewSession,
      onOpenSessions: onOpenSessions,
      onScan: onScan,
      onTakePhoto: onTakePhoto,
      onAddFile: onAddFile
    )
    GalaxySSIAgentHomeReadinessView(
      runningTasks: runningTasks,
      callableTargets: callableTargets,
      nativeToolSummary: nativeToolSummary,
      nativeTools: nativeTools,
      screenObservationAllowed: screenObservationAllowed,
      executionPaused: executionPaused,
      currentApp: currentApp,
      memorySnapshot: memorySnapshot,
      knowledgeStats: knowledgeStats,
      knowledgeHitCount: knowledgeHitCount,
      screen: screen,
      screenSections: screenSections,
      recentTaskCount: recentTaskCount,
      recentTasks: recentTasks,
      permissionMode: permissionMode,
      highRiskGuard: highRiskGuard,
      memoryCapture: memoryCapture,
      taskExecutionMode: taskExecutionMode,
      onCyclePermissionMode: onCyclePermissionMode,
      onToggleHighRiskGuard: onToggleHighRiskGuard,
      onToggleMemoryCapture: onToggleMemoryCapture,
      onCycleTaskExecutionMode: onCycleTaskExecutionMode,
      onToggleExecutionPaused: onToggleExecutionPaused,
      onOpenRecentTasks: onOpenRecentTasks,
      onOpenRecentTask: onOpenRecentTask,
      onTaskAction: onTaskAction,
      onModelSelectionChanged: onModelSelectionChanged,
      routeTitle: routeTitle,
      routeSubtitle: routeSubtitle,
      routeStatus: routeStatus,
      routeReady: routeReady,
      onOpenRouteSelection: onOpenRouteSelection,
      onScreenCommand: onScreenCommand,
      t: t,
      onRefreshScreenContext: onRefreshScreenContext
    )
  }
}
