import Foundation

struct AgentWorkspaceCheckpointReduction: Codable, Equatable {
  var workspace: AgentWorkspace
  var checkpoint: AgentWorkspaceCheckpoint?
  var changed: Bool

  init(
    workspace: AgentWorkspace,
    checkpoint: AgentWorkspaceCheckpoint? = nil,
    changed: Bool = false
  ) {
    self.workspace = workspace
    self.checkpoint = checkpoint
    self.changed = changed
  }
}

enum AgentWorkspaceCheckpointReducer {
  static let defaultMaxEventCount = 100
  static let defaultMaxCheckpointCount = 10

  static func checkpoint(
    workspace: AgentWorkspace,
    checkpointId: String,
    planSnapshot: String = "",
    stateJson: String = "",
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount,
    maxCheckpointCount: Int = defaultMaxCheckpointCount
  ) -> AgentWorkspaceCheckpointReduction {
    let cleanCheckpointId = checkpointId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanCheckpointId.isEmpty else {
      return AgentWorkspaceCheckpointReduction(workspace: workspace)
    }
    let now = max(observedAtMillis, 0)
    var updated = appendEvent(
      to: workspace,
      kind: AgentTaskEventKinds.checkpoint,
      message: cleanCheckpointId,
      payloadJson: "",
      timestampMillis: now,
      maxEventCount: maxEventCount
    )
    let checkpoint = AgentWorkspaceCheckpoint(
      id: cleanCheckpointId,
      eventSequence: updated.eventSequence,
      planSnapshot: planSnapshot.isBlank ? workspace.currentPlanSnapshot : planSnapshot,
      stateJson: stateJson,
      createdAtMillis: now
    )
    updated.currentPlanSnapshot = checkpoint.planSnapshot
    updated.checkpoints = (workspace.checkpoints
      .filter { $0.id != cleanCheckpointId } + [checkpoint])
      .sorted {
        if $0.eventSequence != $1.eventSequence {
          return $0.eventSequence < $1.eventSequence
        }
        if $0.createdAtMillis != $1.createdAtMillis {
          return $0.createdAtMillis < $1.createdAtMillis
        }
        return $0.id < $1.id
      }
      .suffixArray(maxCheckpointCount)
    updated.updatedAtMillis = max(updated.updatedAtMillis, now)
    return AgentWorkspaceCheckpointReduction(
      workspace: updated,
      checkpoint: checkpoint,
      changed: true
    )
  }

  private static func appendEvent(
    to workspace: AgentWorkspace,
    kind: String,
    message: String,
    payloadJson: String,
    timestampMillis: Int64,
    maxEventCount: Int
  ) -> AgentWorkspace {
    let cleanKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
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
}

private extension Array {
  func suffixArray(_ limit: Int) -> [Element] {
    Array(suffix(Swift.max(limit, 0)))
  }
}
