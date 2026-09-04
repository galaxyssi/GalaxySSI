import Foundation

struct AgentTaskWatchdogTimeoutResult: Equatable {
  var result: AgentActionResult
  var eventPayload: AgentRunControlPayload
}

enum AgentTaskWatchdogTimeoutResolver {
  static let timeoutStage = "TASK_WATCHDOG"

  static func resolve(
    pending: AgentActionResult,
    message: String,
    nowMillis: Int64 = AgentControlPlaneClock.nowMillis()
  ) -> AgentTaskWatchdogTimeoutResult {
    let reason = clean(message).isEmpty ? "The task timed out." : clean(message)
    let now = nowMillis > 0 ? nowMillis : AgentControlPlaneClock.nowMillis()
    var metadata = pending.metadata
    metadata["awaiting_response"] = "false"
    metadata["timeout_stage"] = timeoutStage
    metadata["remote_task_status"] = "timed_out"
    metadata["remote_task_terminal_at"] = String(now)
    let failed = AgentActionResult(
      actionId: pending.actionId.isEmpty ? "agent-task-timeout" : pending.actionId,
      success: false,
      message: reason,
      metadata: metadata
    )
    return AgentTaskWatchdogTimeoutResult(
      result: failed,
      eventPayload: [
        "message": .string(reason),
        "timeout_stage": .string(timeoutStage),
        "remote_task_status": .string("timed_out"),
        "remote_task_terminal_at": .int(now)
      ]
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
