import Foundation

struct AgentPermissionRevocationReport: Codable, Equatable {
  var revocation: AgentPermissionRevocation
  var pausedWorkspaceIds: Set<String>
  var pausedRunIds: Set<String>
  var failedWorkspaceIds: Set<String>

  init(
    revocation: AgentPermissionRevocation,
    pausedWorkspaceIds: Set<String> = [],
    pausedRunIds: Set<String> = [],
    failedWorkspaceIds: Set<String> = []
  ) {
    self.revocation = revocation
    self.pausedWorkspaceIds = pausedWorkspaceIds
    self.pausedRunIds = pausedRunIds
    self.failedWorkspaceIds = failedWorkspaceIds
  }

  enum CodingKeys: String, CodingKey {
    case revocation
    case pausedWorkspaceIds = "paused_workspace_ids"
    case pausedRunIds = "paused_run_ids"
    case failedWorkspaceIds = "failed_workspace_ids"
  }
}

struct AgentPermissionRevocationCoordinatorError: LocalizedError, Equatable {
  var message: String
  var errorDescription: String? { message }
}

protocol AgentPermissionGrantRevoking {
  func revokeGrant(grantId: String, reason: String) -> AgentPermissionRevocation
  func revokeScope(scope: String, reason: String) -> AgentPermissionRevocation
}

extension InMemoryAgentPermissionGrantStore: AgentPermissionGrantRevoking {}

final class AgentPermissionRevocationCoordinator {
  private let grantStore: AgentPermissionGrantRevoking
  private let workspaceStore: AgentWorkspaceStore
  private let runEventStore: AgentRunControlStore
  private let pauseActiveWorkspace: (String, String) -> Bool

  init(
    grantStore: AgentPermissionGrantRevoking,
    workspaceStore: AgentWorkspaceStore,
    runEventStore: AgentRunControlStore,
    pauseActiveWorkspace: @escaping (String, String) -> Bool = { _, _ in false }
  ) {
    self.grantStore = grantStore
    self.workspaceStore = workspaceStore
    self.runEventStore = runEventStore
    self.pauseActiveWorkspace = pauseActiveWorkspace
  }

  func revokeGrant(grantId: String, reason: String) -> AgentPermissionRevocationReport {
    propagate(grantStore.revokeGrant(grantId: grantId, reason: reason))
  }

  func revokeScope(scope: String, reason: String) -> AgentPermissionRevocationReport {
    propagate(grantStore.revokeScope(scope: scope, reason: reason))
  }

  func propagate(_ revocation: AgentPermissionRevocation) -> AgentPermissionRevocationReport {
    guard !revocation.revokedGrantIds.isEmpty else {
      return AgentPermissionRevocationReport(revocation: revocation)
    }

    let affected = workspaceStore.recoverable().filter { workspace in
      workspace.permissionGrantIds.contains { revocation.revokedGrantIds.contains($0) } ||
        workspace.permissionScopes.contains { revocation.scopes.contains($0) }
    }
    var pausedWorkspaceIds = Set<String>()
    var failedWorkspaceIds = Set<String>()

    for workspace in affected {
      do {
        _ = pauseActiveWorkspace(workspace.workspaceId, revocation.reason)
        try persistRevocation(workspaceId: workspace.workspaceId, revocation: revocation)
        pausedWorkspaceIds.insert(workspace.workspaceId)
      } catch {
        failedWorkspaceIds.insert(workspace.workspaceId)
      }
    }

    let affectedTaskIds = Set(affected.map(\.taskId))
    let affectedWorkspaceIds = Set(affected.map(\.workspaceId))
    var pausedRunIds = Set<String>()
    for snapshot in runEventStore.recoverableRuns()
      where affectedTaskIds.contains(snapshot.taskId) || affectedWorkspaceIds.contains(snapshot.runId) {
      let appended = runEventStore.appendNext(AgentRunControlEvent(
        eventId: UUID().uuidString,
        conversationId: snapshot.lastEvent.conversationId,
        messageId: snapshot.lastEvent.messageId,
        taskId: snapshot.lastEvent.taskId,
        runId: snapshot.lastEvent.runId,
        stepId: snapshot.lastEvent.stepId,
        toolCallId: snapshot.lastEvent.toolCallId,
        agentId: snapshot.lastEvent.agentId,
        deviceId: snapshot.lastEvent.deviceId,
        type: .permissionRevoked,
        sequence: 0,
        timestampMillis: revocation.revokedAtMillis,
        payload: snapshot.lastEvent.payload.adding(Self.runPayload(revocation))
      ))
      pausedRunIds.insert(appended.runId)
    }

    return AgentPermissionRevocationReport(
      revocation: revocation,
      pausedWorkspaceIds: pausedWorkspaceIds,
      pausedRunIds: pausedRunIds,
      failedWorkspaceIds: failedWorkspaceIds
    )
  }

  private func persistRevocation(
    workspaceId: String,
    revocation: AgentPermissionRevocation
  ) throws {
    for _ in 0..<Self.maxWriteAttempts {
      guard let current = workspaceStore.find(workspaceId) else {
        return
      }
      if current.status.isTerminal || current.cancellationRequested {
        return
      }
      let alreadyRecorded = current.eventJournal.last.map { event in
        event.kind == AgentTaskEventKinds.permissionRevoked &&
          event.timestampMillis == revocation.revokedAtMillis
      } ?? false
      do {
        let withEvent: AgentWorkspace
        if alreadyRecorded {
          withEvent = current
        } else {
          guard let appended = try workspaceStore.appendEvent(
            workspaceId: workspaceId,
            kind: AgentTaskEventKinds.permissionRevoked,
            message: revocation.reason,
            payloadJson: Self.workspaceEventPayload(revocation),
            expectedRevision: current.revision,
            timestampMillis: revocation.revokedAtMillis
          ) else {
            return
          }
          withEvent = appended
        }
        guard let checkpoint = try workspaceStore.checkpoint(
          workspaceId: workspaceId,
          checkpointId: "permission-revoked-\(revocation.revokedAtMillis)",
          planSnapshot: withEvent.currentPlanSnapshot,
          stateJson: Self.checkpointPayload(revocation),
          expectedRevision: withEvent.revision,
          createdAtMillis: revocation.revokedAtMillis
        ) else {
          return
        }
        var updated = checkpoint
        updated.status = .paused
        updated.toolCalls = checkpoint.toolCalls.map { call in
          guard call.status == .pending || call.status == .running else {
            return call
          }
          var cancelled = call
          cancelled.status = .cancelled
          cancelled.errorMessage = revocation.reason
          cancelled.completedAtMillis = revocation.revokedAtMillis
          return cancelled
        }
        updated.errorMessage = revocation.reason
        updated.revision = checkpoint.revision
        _ = try workspaceStore.upsert(updated, expectedRevision: checkpoint.revision)
        return
      } catch is AgentWorkspaceRevisionConflictError {
        continue
      }
    }
    throw AgentPermissionRevocationCoordinatorError(
      message: "Permission revocation could not update workspace \(workspaceId)"
    )
  }

  private static func workspaceEventPayload(_ revocation: AgentPermissionRevocation) -> String {
    AgentMcpJSONCodec.stringify([
      "grant_ids": .array(revocation.revokedGrantIds.sorted().map { .string($0) }),
      "scopes": .array(revocation.scopes.sorted().map { .string($0) }),
      "revoked_at_millis": .int(revocation.revokedAtMillis)
    ])
  }

  private static func checkpointPayload(_ revocation: AgentPermissionRevocation) -> String {
    AgentMcpJSONCodec.stringify([
      "status": .string(AgentWorkspaceStatus.paused.rawValue),
      "revoked_grant_ids": .array(revocation.revokedGrantIds.sorted().map { .string($0) }),
      "revoked_scopes": .array(revocation.scopes.sorted().map { .string($0) }),
      "reason": .string(revocation.reason)
    ])
  }

  private static func runPayload(_ revocation: AgentPermissionRevocation) -> AgentRunControlPayload {
    [
      "revoked_grant_ids": .string(AgentMcpJSONCodec.stringify(.array(revocation.revokedGrantIds.sorted().map { .string($0) }))),
      "revoked_scopes": .string(AgentMcpJSONCodec.stringify(.array(revocation.scopes.sorted().map { .string($0) }))),
      "revocation_reason": .string(revocation.reason),
      "revoked_at_millis": .int(revocation.revokedAtMillis)
    ]
  }

  private static let maxWriteAttempts = 4
}

private extension Dictionary where Key == String, Value == AgentRunControlPayloadValue {
  func adding(_ updates: [String: AgentRunControlPayloadValue]) -> [String: AgentRunControlPayloadValue] {
    var merged = self
    for (key, value) in updates {
      merged[key] = value
    }
    return merged
  }
}
