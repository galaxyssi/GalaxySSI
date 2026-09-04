import Foundation

enum AgentWorkspaceBoundsPolicy {
  static let maxWorkspaces = 64
  static let maxEvents = 100
  static let maxToolCalls = 50
  static let maxCheckpoints = 10
  static let maxArtifacts = 50

  static let maxIdentifierCharacters = 160
  static let maxEventKindCharacters = 80
  static let maxEventMessageCharacters = 1_024
  static let maxEventPayloadCharacters = 4_096
  static let maxPlanCharacters = 32 * 1_024
  static let maxGoalCharacters = 32 * 1_024
  static let maxResultJsonCharacters = 128 * 1_024
  static let maxErrorMessageCharacters = 4 * 1_024
  static let maxPermissionBindings = 128
  static let maxHandoffIds = 128
  static let maxToolNameCharacters = 160
  static let maxToolArgumentsCharacters = 4_096
  static let maxToolResultCharacters = 8_192
  static let maxToolErrorCharacters = 1_024
  static let maxCheckpointStateCharacters = 8 * 1_024
  static let maxArtifactUriCharacters = 2_048
  static let maxArtifactNameCharacters = 512
  static let maxMimeTypeCharacters = 160
  static let maxArtifactMetadataCharacters = 2_048

  static func normalizeOrNil(_ workspace: AgentWorkspace) -> AgentWorkspace? {
    guard let workspaceId = identifier(workspace.workspaceId),
      let sessionId = identifier(workspace.sessionId),
      let conversationId = identifier(workspace.conversationId),
      let taskId = identifier(workspace.taskId),
      workspace.eventSequence >= 0,
      workspace.lastRemoteEventSequence >= 0,
      workspace.createdAtMillis >= 0,
      workspace.updatedAtMillis >= 0,
      workspace.revision >= 0 else {
      return nil
    }

    let events = dedupeEvents(workspace.eventJournal.compactMap { normalizeEventOrNil($0) })
    let eventSequence = max(workspace.eventSequence, events.map(\.sequence).max() ?? 0)
    let toolCalls = dedupeToolCalls(workspace.toolCalls.compactMap { normalizeToolCallOrNil($0) })
    let checkpoints = dedupeCheckpoints(
      workspace.checkpoints
        .compactMap { normalizeCheckpointOrNil($0) }
        .filter { $0.eventSequence <= eventSequence }
    )
    let artifacts = dedupeArtifacts(workspace.artifacts.compactMap { normalizeArtifactOrNil($0) })

    var normalized = workspace
    normalized.workspaceId = workspaceId
    normalized.sessionId = sessionId
    normalized.conversationId = conversationId
    normalized.taskId = taskId
    normalized.goal = bounded(workspace.goal, maxGoalCharacters)
    normalized.parentRunId = optionalIdentifier(workspace.parentRunId)
    normalized.agentId = optionalIdentifier(workspace.agentId)
    normalized.deviceId = optionalIdentifier(workspace.deviceId)
    normalized.remoteRunId = optionalIdentifier(workspace.remoteRunId)
    normalized.deliveryMode = bounded(clean(workspace.deliveryMode), maxIdentifierCharacters)
      .ifBlank(AgentDeliveryMode.respond.rawValue)
    normalized.currentPlanSnapshot = bounded(workspace.currentPlanSnapshot, maxPlanCharacters)
    normalized.resultJson = bounded(workspace.resultJson, maxResultJsonCharacters).ifBlank("{}")
    normalized.errorMessage = bounded(workspace.errorMessage, maxErrorMessageCharacters)
    normalized.permissionGrantIds = normalizeBindings(workspace.permissionGrantIds, limit: maxPermissionBindings)
    normalized.permissionScopes = normalizeBindings(workspace.permissionScopes, limit: maxPermissionBindings)
    normalized.handoffIds = normalizeBindings(workspace.handoffIds, limit: maxHandoffIds)
    normalized.eventSequence = eventSequence
    normalized.eventJournal = events
    normalized.toolCalls = toolCalls
    normalized.checkpoints = checkpoints
    normalized.artifacts = artifacts
    return normalized
  }

  static func normalizeEventOrNil(_ event: AgentWorkspaceEvent) -> AgentWorkspaceEvent? {
    let kind = bounded(clean(event.kind), maxEventKindCharacters)
    guard event.sequence > 0,
      !kind.isEmpty,
      event.timestampMillis >= 0 else {
      return nil
    }
    return AgentWorkspaceEvent(
      sequence: event.sequence,
      kind: kind,
      message: bounded(event.message, maxEventMessageCharacters),
      payloadJson: bounded(event.payloadJson, maxEventPayloadCharacters),
      timestampMillis: event.timestampMillis
    )
  }

  static func normalizeToolCallOrNil(_ toolCall: AgentWorkspaceToolCallRecord) -> AgentWorkspaceToolCallRecord? {
    guard let id = identifier(toolCall.id) else { return nil }
    let toolName = bounded(clean(toolCall.toolName), maxToolNameCharacters)
    guard !toolName.isEmpty,
      toolCall.startedAtMillis >= 0,
      toolCall.completedAtMillis >= 0,
      toolCall.completedAtMillis == 0 || toolCall.completedAtMillis >= toolCall.startedAtMillis else {
      return nil
    }
    return AgentWorkspaceToolCallRecord(
      id: id,
      toolName: toolName,
      status: toolCall.status,
      argumentsJson: bounded(toolCall.argumentsJson, maxToolArgumentsCharacters),
      resultJson: bounded(toolCall.resultJson, maxToolResultCharacters),
      errorMessage: bounded(toolCall.errorMessage, maxToolErrorCharacters),
      startedAtMillis: toolCall.startedAtMillis,
      completedAtMillis: toolCall.completedAtMillis
    )
  }

  static func normalizeCheckpointOrNil(_ checkpoint: AgentWorkspaceCheckpoint) -> AgentWorkspaceCheckpoint? {
    guard let id = identifier(checkpoint.id),
      checkpoint.eventSequence >= 0,
      checkpoint.createdAtMillis >= 0 else {
      return nil
    }
    return AgentWorkspaceCheckpoint(
      id: id,
      eventSequence: checkpoint.eventSequence,
      planSnapshot: bounded(checkpoint.planSnapshot, maxPlanCharacters),
      stateJson: bounded(checkpoint.stateJson, maxCheckpointStateCharacters),
      createdAtMillis: checkpoint.createdAtMillis
    )
  }

  static func normalizeArtifactOrNil(_ artifact: AgentWorkspaceArtifactReference) -> AgentWorkspaceArtifactReference? {
    guard let id = identifier(artifact.id) else { return nil }
    let uri = bounded(clean(artifact.uri), maxArtifactUriCharacters)
    guard !uri.isEmpty, artifact.createdAtMillis >= 0 else { return nil }
    return AgentWorkspaceArtifactReference(
      id: id,
      uri: uri,
      name: bounded(artifact.name, maxArtifactNameCharacters),
      mimeType: bounded(clean(artifact.mimeType), maxMimeTypeCharacters),
      metadataJson: bounded(artifact.metadataJson, maxArtifactMetadataCharacters),
      createdAtMillis: artifact.createdAtMillis
    )
  }

  static func boundWorkspaces(_ workspaces: [AgentWorkspace]) -> [AgentWorkspace] {
    var bestById: [String: AgentWorkspace] = [:]
    for workspace in workspaces.compactMap(normalizeOrNil) {
      let previous = bestById[workspace.workspaceId]
      if previous == nil ||
        workspace.revision > previous!.revision ||
        (workspace.revision == previous!.revision && workspace.updatedAtMillis >= previous!.updatedAtMillis) {
        bestById[workspace.workspaceId] = workspace
      }
    }
    return bestById.values
      .sorted {
        if $0.updatedAtMillis != $1.updatedAtMillis {
          return $0.updatedAtMillis < $1.updatedAtMillis
        }
        if $0.createdAtMillis != $1.createdAtMillis {
          return $0.createdAtMillis < $1.createdAtMillis
        }
        return $0.workspaceId < $1.workspaceId
      }
      .suffixArray(maxWorkspaces)
  }

  private static func dedupeEvents(_ events: [AgentWorkspaceEvent]) -> [AgentWorkspaceEvent] {
    let sorted = events.sorted {
      if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
      return $0.timestampMillis < $1.timestampMillis
    }
    var bySequence: [Int64: AgentWorkspaceEvent] = [:]
    for event in sorted {
      bySequence[event.sequence] = event
    }
    return bySequence.values
      .sorted {
        if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
        return $0.timestampMillis < $1.timestampMillis
      }
      .suffixArray(maxEvents)
  }

  private static func dedupeToolCalls(_ calls: [AgentWorkspaceToolCallRecord]) -> [AgentWorkspaceToolCallRecord] {
    let sorted = calls.sorted {
      if $0.startedAtMillis != $1.startedAtMillis { return $0.startedAtMillis < $1.startedAtMillis }
      if $0.completedAtMillis != $1.completedAtMillis { return $0.completedAtMillis < $1.completedAtMillis }
      return $0.id < $1.id
    }
    var byId: [String: AgentWorkspaceToolCallRecord] = [:]
    for call in sorted {
      byId[call.id] = call
    }
    return byId.values
      .sorted {
        if $0.startedAtMillis != $1.startedAtMillis { return $0.startedAtMillis < $1.startedAtMillis }
        if $0.completedAtMillis != $1.completedAtMillis { return $0.completedAtMillis < $1.completedAtMillis }
        return $0.id < $1.id
      }
      .suffixArray(maxToolCalls)
  }

  private static func dedupeCheckpoints(_ checkpoints: [AgentWorkspaceCheckpoint]) -> [AgentWorkspaceCheckpoint] {
    let sorted = checkpoints.sorted {
      if $0.eventSequence != $1.eventSequence { return $0.eventSequence < $1.eventSequence }
      if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
      return $0.id < $1.id
    }
    var byId: [String: AgentWorkspaceCheckpoint] = [:]
    for checkpoint in sorted {
      byId[checkpoint.id] = checkpoint
    }
    return byId.values
      .sorted {
        if $0.eventSequence != $1.eventSequence { return $0.eventSequence < $1.eventSequence }
        if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
        return $0.id < $1.id
      }
      .suffixArray(maxCheckpoints)
  }

  private static func dedupeArtifacts(_ artifacts: [AgentWorkspaceArtifactReference]) -> [AgentWorkspaceArtifactReference] {
    let sorted = artifacts.sorted {
      if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
      return $0.id < $1.id
    }
    var byId: [String: AgentWorkspaceArtifactReference] = [:]
    for artifact in sorted {
      byId[artifact.id] = artifact
    }
    return byId.values
      .sorted {
        if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis < $1.createdAtMillis }
        return $0.id < $1.id
      }
      .suffixArray(maxArtifacts)
  }

  private static func identifier(_ value: String) -> String? {
    let cleanValue = clean(value)
    return !cleanValue.isEmpty && cleanValue.count <= maxIdentifierCharacters ? cleanValue : nil
  }

  private static func optionalIdentifier(_ value: String) -> String {
    bounded(clean(value), maxIdentifierCharacters)
  }

  private static func normalizeBindings(_ values: [String], limit: Int) -> [String] {
    var seen = Set<String>()
    return values
      .map { bounded(clean($0), maxIdentifierCharacters) }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
      .prefixArray(limit)
  }

  private static func bounded(_ value: String, _ limit: Int) -> String {
    String(value.prefix(max(limit, 0)))
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}


private extension Array {
  func suffixArray(_ limit: Int) -> [Element] {
    Array(suffix(Swift.max(limit, 0)))
  }

  func prefixArray(_ limit: Int) -> [Element] {
    Array(prefix(Swift.max(limit, 0)))
  }
}
