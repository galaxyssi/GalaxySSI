import Foundation

struct AgentConnectorTaskStatusRecord: Equatable {
  var result: AgentActionResult
  var didApplyStatus: Bool
}

enum AgentConnectorTaskStatusRecorder {
  static func record(
    pending: AgentActionResult,
    envelope: AgentConnectorTerminalStatusEnvelope
  ) -> AgentConnectorTaskStatusRecord? {
    let normalizedStatus = AgentRemoteTaskStatusPolicy.normalize(envelope.taskStatus)
    guard !envelope.taskId.isEmpty, !normalizedStatus.isEmpty else {
      return nil
    }
    let previousSeq = Int64(pending.metadata["remote_task_status_seq"] ?? "") ?? -1
    if envelope.statusSeq > 0 && envelope.statusSeq < previousSeq {
      return AgentConnectorTaskStatusRecord(result: pending, didApplyStatus: false)
    }
    let now = envelope.nowMillis > 0 ? envelope.nowMillis : AgentControlPlaneClock.nowMillis()
    var metadata = pending.metadata
    metadata["remote_task_id"] = envelope.taskId
    metadata["remote_task_status"] = normalizedStatus
    metadata["remote_task_status_seq"] = String(max(previousSeq, envelope.statusSeq))
    metadata["remote_task_status_updated_at"] = String(now)
    return AgentConnectorTaskStatusRecord(
      result: AgentActionResult(
        actionId: pending.actionId,
        success: pending.success,
        message: pending.message,
        metadata: metadata
      ),
      didApplyStatus: true
    )
  }
}
