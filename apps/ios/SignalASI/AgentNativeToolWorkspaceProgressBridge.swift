import Foundation

enum AgentNativeToolWorkspaceProgressBridge {
  static func workspaceId(for event: AgentNativeToolLifecycleEvent) -> String {
    clean(event.turnId)
  }

  static func record(
    event: AgentNativeToolLifecycleEvent,
    in workspace: AgentWorkspace,
    policy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy(),
    maxEventCount: Int = AgentTaskLivenessWorkspaceReducer.defaultMaxEventCount
  ) -> AgentTaskLivenessWorkspaceReduction {
    AgentTaskLivenessWorkspaceReducer.recordActivity(
      workspace: workspace,
      eventKind: AgentTaskEventKinds.progress,
      stage: progressStage(event.stage),
      message: progressMessage(event),
      policy: policy,
      observedAtMillis: event.timestampMillis,
      maxEventCount: maxEventCount
    )
  }

  static func progressStage(_ stage: AgentNativeToolLifecycleStage) -> String {
    "tool.\(stage.rawValue.lowercased())"
  }

  static func progressMessage(_ event: AgentNativeToolLifecycleEvent) -> String {
    clean(event.message).isEmpty ? clean(event.toolId) : clean(event.message)
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
