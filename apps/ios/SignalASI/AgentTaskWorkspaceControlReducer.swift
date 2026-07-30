import Foundation

struct AgentTaskWorkspaceControlReduction: Codable, Equatable {
  var workspace: AgentWorkspace
  var changed: Bool
  var shouldCancelExecution: Bool
  var cancelExecutionReason: String

  init(
    workspace: AgentWorkspace,
    changed: Bool = false,
    shouldCancelExecution: Bool = false,
    cancelExecutionReason: String = ""
  ) {
    self.workspace = workspace
    self.changed = changed
    self.shouldCancelExecution = shouldCancelExecution
    self.cancelExecutionReason = Self.clean(cancelExecutionReason)
  }

  enum CodingKeys: String, CodingKey {
    case workspace
    case changed
    case shouldCancelExecution = "should_cancel_execution"
    case cancelExecutionReason = "cancel_execution_reason"
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum AgentTaskWorkspaceControlReducer {
  static let defaultCancelReason = "Task cancellation requested"
  static let defaultPermissionRevokedReason = "A required permission grant was revoked"
  static let defaultMaxEventCount = 100

  static func cancel(
    workspace: AgentWorkspace,
    reason rawReason: String = defaultCancelReason,
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount
  ) -> AgentTaskWorkspaceControlReduction {
    let reason = clean(rawReason).isEmpty ? defaultCancelReason : clean(rawReason)
    let shouldCancelExecution = !workspace.status.isTerminal || workspace.status == .cancelled
    let shouldMutate = !workspace.status.isTerminal ||
      (workspace.status == .cancelled && !workspace.cancellationRequested)
    guard shouldMutate else {
      return AgentTaskWorkspaceControlReduction(
        workspace: workspace,
        shouldCancelExecution: shouldCancelExecution,
        cancelExecutionReason: shouldCancelExecution ? reason : ""
      )
    }
    if workspace.status.isTerminal && workspace.cancellationRequested {
      return AgentTaskWorkspaceControlReduction(
        workspace: workspace,
        shouldCancelExecution: shouldCancelExecution,
        cancelExecutionReason: shouldCancelExecution ? reason : ""
      )
    }
    let updated = transition(
      workspace: workspace,
      status: .cancelled,
      eventKind: AgentTaskEventKinds.cancelled,
      message: reason,
      payloadJson: "",
      cancellationRequested: true,
      observedAtMillis: observedAtMillis,
      maxEventCount: maxEventCount
    )
    return AgentTaskWorkspaceControlReduction(
      workspace: updated,
      changed: true,
      shouldCancelExecution: shouldCancelExecution,
      cancelExecutionReason: shouldCancelExecution ? reason : ""
    )
  }

  static func pauseForPermissionRevocation(
    workspace: AgentWorkspace,
    reason rawReason: String = defaultPermissionRevokedReason,
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount
  ) -> AgentTaskWorkspaceControlReduction {
    guard !workspace.status.isTerminal,
      !workspace.cancellationRequested else {
      return AgentTaskWorkspaceControlReduction(workspace: workspace)
    }
    let reason = clean(rawReason).isEmpty ? defaultPermissionRevokedReason : clean(rawReason)
    let updated = transition(
      workspace: workspace,
      status: .paused,
      eventKind: AgentTaskEventKinds.permissionRevoked,
      message: reason,
      payloadJson: "",
      cancellationRequested: workspace.cancellationRequested,
      observedAtMillis: observedAtMillis,
      maxEventCount: maxEventCount
    )
    return AgentTaskWorkspaceControlReduction(
      workspace: updated,
      changed: true,
      shouldCancelExecution: true,
      cancelExecutionReason: reason
    )
  }

  private static func transition(
    workspace: AgentWorkspace,
    status: AgentWorkspaceStatus,
    eventKind: String,
    message: String,
    payloadJson: String,
    cancellationRequested: Bool,
    observedAtMillis: Int64,
    maxEventCount: Int
  ) -> AgentWorkspace {
    precondition(!workspace.status.isTerminal || workspace.status == status, "Terminal workspace cannot change status")
    var updated = appendEvent(
      to: workspace,
      kind: eventKind,
      message: message,
      payloadJson: payloadJson,
      timestampMillis: observedAtMillis,
      maxEventCount: maxEventCount
    )
    updated.status = status
    updated.cancellationRequested = cancellationRequested
    return updated
  }

  private static func appendEvent(
    to workspace: AgentWorkspace,
    kind: String,
    message: String,
    payloadJson: String,
    timestampMillis: Int64,
    maxEventCount: Int
  ) -> AgentWorkspace {
    let cleanKind = clean(kind)
    precondition(!cleanKind.isEmpty, "event kind must not be blank")
    precondition(workspace.eventSequence < Int64.max, "Agent workspace event sequence exhausted")
    let timestamp = max(timestampMillis, 0)
    let nextSequence = workspace.eventSequence + 1
    let event = AgentWorkspaceEvent(
      sequence: nextSequence,
      kind: cleanKind,
      message: message,
      payloadJson: payloadJson,
      timestampMillis: timestamp
    )
    var updated = workspace
    updated.eventSequence = nextSequence
    updated.eventJournal = Array((workspace.eventJournal + [event]).suffix(max(maxEventCount, 1)))
    updated.updatedAtMillis = max(workspace.updatedAtMillis, timestamp)
    return updated
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
