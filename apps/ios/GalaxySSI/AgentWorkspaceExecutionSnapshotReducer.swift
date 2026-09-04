import Foundation

struct AgentWorkspaceExecutionSnapshotReduction: Codable, Equatable {
  var workspace: AgentWorkspace
  var changed: Bool
  var statusChanged: Bool

  init(
    workspace: AgentWorkspace,
    changed: Bool = false,
    statusChanged: Bool = false
  ) {
    self.workspace = workspace
    self.changed = changed
    self.statusChanged = statusChanged
  }

  enum CodingKeys: String, CodingKey {
    case workspace
    case changed
    case statusChanged = "status_changed"
  }
}

enum AgentWorkspaceExecutionSnapshotReducer {
  static let defaultMaxEventCount = 100
  static let defaultMaxToolCallCount = 50
  static let defaultMaxArtifactCount = 50
  static let defaultMaxPermissionBindingCount = 128
  static let defaultMaxHandoffIdCount = 128

  static func apply(
    snapshot: AgentWorkspaceExecutionSnapshot,
    to workspace: AgentWorkspace,
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount,
    maxToolCallCount: Int = defaultMaxToolCallCount,
    maxArtifactCount: Int = defaultMaxArtifactCount,
    maxPermissionBindingCount: Int = defaultMaxPermissionBindingCount,
    maxHandoffIdCount: Int = defaultMaxHandoffIdCount
  ) -> AgentWorkspaceExecutionSnapshotReduction {
    let nextStatus = snapshot.status ?? workspace.status
    guard !workspace.status.isTerminal || nextStatus == workspace.status else {
      return AgentWorkspaceExecutionSnapshotReduction(workspace: workspace)
    }
    var updated = appendEvent(
      to: workspace,
      kind: AgentTaskEventKinds.snapshot,
      message: nextStatus.rawValue.lowercased(),
      payloadJson: "",
      timestampMillis: observedAtMillis,
      maxEventCount: maxEventCount
    )
    let statusChanged = nextStatus != workspace.status
    updated.status = nextStatus
    updated.currentPlanSnapshot = fallback(snapshot.planSnapshot, workspace.currentPlanSnapshot)
    updated.resultJson = fallback(snapshot.resultJson, workspace.resultJson)
    updated.errorMessage = fallback(snapshot.errorMessage, workspace.errorMessage)
    updated.toolCalls = distinctById(workspace.toolCalls + snapshot.toolCalls).suffixArray(maxToolCallCount)
    updated.artifacts = distinctById(workspace.artifacts + snapshot.artifacts).suffixArray(maxArtifactCount)
    updated.permissionGrantIds = distinctClean(workspace.permissionGrantIds + snapshot.permissionGrantIds)
      .suffixArray(maxPermissionBindingCount)
    updated.permissionScopes = distinctClean(workspace.permissionScopes + snapshot.permissionScopes)
      .suffixArray(maxPermissionBindingCount)
    updated.handoffIds = distinctClean(workspace.handoffIds + snapshot.handoffIds)
      .suffixArray(maxHandoffIdCount)
    updated.agentId = fallback(snapshot.agentId, workspace.agentId)
    updated.deviceId = fallback(snapshot.deviceId, workspace.deviceId)
    updated.remoteRunId = fallback(snapshot.remoteRunId, workspace.remoteRunId)
    updated.lastRemoteEventSequence = max(workspace.lastRemoteEventSequence, snapshot.lastRemoteEventSequence)
    return AgentWorkspaceExecutionSnapshotReduction(
      workspace: updated,
      changed: true,
      statusChanged: statusChanged
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

  private static func fallback(_ incoming: String, _ current: String) -> String {
    incoming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? current : incoming
  }

  private static func distinctById<T: Identifiable>(_ values: [T]) -> [T] where T.ID == String {
    var seen = Set<String>()
    return values.filter { seen.insert($0.id).inserted }
  }

  private static func distinctClean(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }
}

private extension Array {
  func suffixArray(_ limit: Int) -> [Element] {
    Array(suffix(Swift.max(limit, 0)))
  }
}
