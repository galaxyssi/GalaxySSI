import Foundation

struct AgentConnectorLateResponseReduction: Codable, Equatable {
  var workspace: AgentWorkspace?
  var changed: Bool
  var accepted: Bool
  var sourceMessageId: Int64

  init(
    workspace: AgentWorkspace?,
    changed: Bool = false,
    accepted: Bool = false,
    sourceMessageId: Int64
  ) {
    self.workspace = workspace
    self.changed = changed
    self.accepted = accepted
    self.sourceMessageId = max(sourceMessageId, 0)
  }

  enum CodingKeys: String, CodingKey {
    case workspace
    case changed
    case accepted
    case sourceMessageId = "source_message_id"
  }
}

enum AgentConnectorLateResponseReducer {
  static let defaultMessage = "Authenticated connector response received after local timeout"
  static let defaultMaxEventCount = 100

  static func reconcile(
    workspace: AgentWorkspace,
    sourceMessageId: Int64,
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount
  ) -> AgentConnectorLateResponseReduction {
    guard sourceMessageId > 0 else {
      return AgentConnectorLateResponseReduction(workspace: nil, sourceMessageId: sourceMessageId)
    }
    guard workspace.status == .failed,
      !workspace.cancellationRequested else {
      return AgentConnectorLateResponseReduction(
        workspace: workspace.cancellationRequested ? nil : workspace,
        sourceMessageId: sourceMessageId
      )
    }
    guard handoffMatches(workspace: workspace, sourceMessageId: sourceMessageId) else {
      return AgentConnectorLateResponseReduction(workspace: nil, sourceMessageId: sourceMessageId)
    }
    var updated = appendEvent(
      to: workspace,
      kind: AgentTaskEventKinds.lateResponse,
      message: defaultMessage,
      payloadJson: AgentMcpJSONCodec.stringify(["source_message_id": .int(sourceMessageId)]),
      timestampMillis: observedAtMillis,
      maxEventCount: maxEventCount
    )
    updated.status = .waitingResponse
    updated.errorMessage = ""
    return AgentConnectorLateResponseReduction(
      workspace: updated,
      changed: true,
      accepted: true,
      sourceMessageId: sourceMessageId
    )
  }

  private static func handoffMatches(
    workspace: AgentWorkspace,
    sourceMessageId: Int64
  ) -> Bool {
    let source = String(sourceMessageId)
    let sourceSuffix = ":\(source)"
    return workspace.handoffIds.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(sourceSuffix) } ||
      workspace.remoteRunId.trimmingCharacters(in: .whitespacesAndNewlines) == source
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
