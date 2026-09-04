import Foundation
import Combine

enum AgentRunRecoveryOutcome: String, Codable, CaseIterable, Identifiable {
  case restoredLocalWait = "RESTORED_LOCAL_WAIT"
  case reconnectedRemote = "RECONNECTED_REMOTE"
  case waitingForRemote = "WAITING_FOR_REMOTE"
  case failedNonReplayable = "FAILED_NON_REPLAYABLE"
  case ignoredTerminal = "IGNORED_TERMINAL"
  case alreadyCurrent = "ALREADY_CURRENT"

  var id: String { rawValue }
}

struct AgentRunRecoveryResult: Codable, Equatable {
  var runId: String
  var outcome: AgentRunRecoveryOutcome
  var lastRemoteEventSequence: Int64
  var reason: String

  init(
    runId: String,
    outcome: AgentRunRecoveryOutcome,
    lastRemoteEventSequence: Int64 = 0,
    reason: String
  ) {
    self.runId = runId
    self.outcome = outcome
    self.lastRemoteEventSequence = max(lastRemoteEventSequence, 0)
    self.reason = reason
  }

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case outcome
    case lastRemoteEventSequence = "last_remote_event_sequence"
    case reason
  }
}

struct AgentRunRecoveryCoordinatorError: LocalizedError, Equatable {
  var message: String
  var errorDescription: String? { message }
}

protocol AgentRunControlStore {
  func appendNext(_ event: AgentRunControlEvent) -> AgentRunControlEvent
  func recoverableRuns() -> [AgentRunControlSnapshot]
}

extension AgentRunRecoveryRegistration {
  init(_ registration: AgentRegistration) {
    self.init(
      agentId: registration.agentId,
      location: registration.location,
      connectionKind: registration.connectionKind
    )
  }
}

final class AgentRunRecoveryCoordinator {
  typealias RecordedRunResolver = (String) -> AgentRecordedRun?
  typealias RegistrationResolver = (String, String) -> AgentRunRecoveryRegistration?
  typealias AdapterResolver = (String) async throws -> AgentAdapter?

  private let runStore: AgentRunControlStore
  private let workspaceStore: AgentWorkspaceStore
  private let recordedRun: RecordedRunResolver
  private let registration: RegistrationResolver
  private let adapterResolver: AdapterResolver
  private let markInterrupted: (String, String) -> Void

  init(
    runStore: AgentRunControlStore,
    workspaceStore: AgentWorkspaceStore,
    recordedRun: @escaping RecordedRunResolver,
    registration: @escaping RegistrationResolver,
    adapterResolver: @escaping AdapterResolver,
    markInterrupted: @escaping (String, String) -> Void = { _, _ in }
  ) {
    self.runStore = runStore
    self.workspaceStore = workspaceStore
    self.recordedRun = recordedRun
    self.registration = registration
    self.adapterResolver = adapterResolver
    self.markInterrupted = markInterrupted
  }

  func recover() async throws -> [AgentRunRecoveryResult] {
    var results: [AgentRunRecoveryResult] = []
    for snapshot in runStore.recoverableRuns() {
      results.append(try await recover(snapshot))
    }
    return results
  }

  private func recover(_ snapshot: AgentRunControlSnapshot) async throws -> AgentRunRecoveryResult {
    let run = recordedRun(snapshot.runId)
    let decision = AgentRunRecoveryPolicy.decide(
      snapshot: snapshot,
      recordedRun: run,
      registration: registration(snapshot.agentId, snapshot.deviceId)
    )
    switch decision.disposition {
    case .ignoreTerminal:
      let result = AgentRunRecoveryResult(
        runId: snapshot.runId,
        outcome: .ignoredTerminal,
        lastRemoteEventSequence: snapshot.lastSequence,
        reason: decision.reason
      )
      if let status = terminalWorkspaceStatus(run?.status) {
        try restoreWorkspace(
          snapshot: snapshot,
          status: status,
          eventKind: "task.reconciled_terminal",
          checkpoint: "",
          remoteHandle: nil,
          remoteSequence: snapshot.lastSequence,
          reason: decision.reason
        )
        appendRecordedTerminal(snapshot, status: run?.status)
      }
      return result

    case .restoreLocalWait:
      let current = workspaceFor(snapshot)
      let status: AgentWorkspaceStatus = {
        if let currentStatus = current?.status,
          currentStatus == .waitingConfirmation || currentStatus == .paused {
          return currentStatus
        }
        return .paused
      }()
      try restoreWorkspace(
        snapshot: snapshot,
        status: status,
        eventKind: "task.recovered_local_wait",
        checkpoint: current?.checkpoints.last?.stateJson ?? "",
        remoteHandle: nil,
        remoteSequence: snapshot.lastSequence,
        reason: decision.reason
      )
      appendLocalWaitRecoveryEvent(snapshot, reason: decision.reason)
      return AgentRunRecoveryResult(
        runId: snapshot.runId,
        outcome: .restoredLocalWait,
        lastRemoteEventSequence: snapshot.lastSequence,
        reason: decision.reason
      )

    case .reconnectDurableRemote:
      return try await recoverRemote(snapshot, decision: decision)

    case .failNonReplayable:
      markInterrupted(snapshot.runId, decision.reason)
      try restoreWorkspace(
        snapshot: snapshot,
        status: .failed,
        eventKind: AgentTaskEventKinds.failed,
        checkpoint: "",
        remoteHandle: nil,
        remoteSequence: snapshot.lastSequence,
        reason: decision.reason
      )
      appendTerminalFailure(snapshot, reason: decision.reason)
      return AgentRunRecoveryResult(
        runId: snapshot.runId,
        outcome: .failedNonReplayable,
        lastRemoteEventSequence: snapshot.lastSequence,
        reason: decision.reason
      )
    }
  }

  private func recoverRemote(
    _ snapshot: AgentRunControlSnapshot,
    decision: AgentRunRecoveryDecision
  ) async throws -> AgentRunRecoveryResult {
    let adapter = try? await adapterResolver(snapshot.agentId)
    let workspace = workspaceFor(snapshot)
    let recoverable: [AgentRecoverableRun]
    if let adapter = adapter {
      recoverable = (try? await adapter.recoverRuns()) ?? []
    } else {
      recoverable = []
    }
    let remote = recoverable.first { candidate in
      candidate.handle.runId == snapshot.runId ||
        candidate.handle.taskId == snapshot.taskId ||
        candidate.handle.remoteRunId == workspace?.remoteRunId
    }

    guard let remote else {
      try restoreWorkspace(
        snapshot: snapshot,
        status: .waitingResponse,
        eventKind: AgentTaskEventKinds.waitingResponse,
        checkpoint: workspace?.checkpoints.last?.stateJson ?? "",
        remoteHandle: nil,
        remoteSequence: snapshot.lastSequence,
        reason: Self.remoteUnavailableReason
      )
      appendWaitingForDevice(snapshot)
      return AgentRunRecoveryResult(
        runId: snapshot.runId,
        outcome: .waitingForRemote,
        lastRemoteEventSequence: snapshot.lastSequence,
        reason: Self.remoteUnavailableReason
      )
    }

    let priorWorkspace = workspaceFor(snapshot)
    if snapshot.lastEvent.type == .runRecovered,
      let priorWorkspace,
      priorWorkspace.lastRemoteEventSequence >= remote.lastEventSequence {
      return AgentRunRecoveryResult(
        runId: snapshot.runId,
        outcome: .alreadyCurrent,
        lastRemoteEventSequence: remote.lastEventSequence,
        reason: "remote_cursor_already_current"
      )
    }

    try restoreWorkspace(
      snapshot: snapshot,
      status: .running,
      eventKind: "task.reconnected_remote",
      checkpoint: AgentMcpJSONCodec.stringify(remote.checkpoint),
      remoteHandle: remote.handle,
      remoteSequence: remote.lastEventSequence,
      reason: decision.reason
    )
    appendRecoveryEvent(
      snapshot,
      reason: decision.reason,
      remoteSequence: remote.lastEventSequence,
      source: "durable_remote"
    )
    return AgentRunRecoveryResult(
      runId: snapshot.runId,
      outcome: .reconnectedRemote,
      lastRemoteEventSequence: remote.lastEventSequence,
      reason: decision.reason
    )
  }

  private func workspaceFor(_ snapshot: AgentRunControlSnapshot) -> AgentWorkspace? {
    workspaceStore.find(snapshot.runId) ?? workspaceStore.list().first { $0.taskId == snapshot.taskId }
  }

  private func restoreWorkspace(
    snapshot: AgentRunControlSnapshot,
    status: AgentWorkspaceStatus,
    eventKind: String,
    checkpoint: String,
    remoteHandle: AgentRunHandle?,
    remoteSequence: Int64,
    reason: String
  ) throws {
    guard let workspaceId = workspaceFor(snapshot)?.workspaceId else {
      return
    }
    for _ in 0..<Self.maxWriteAttempts {
      guard let current = workspaceStore.find(workspaceId) else {
        return
      }
      let alreadyCurrent = current.status == status &&
        current.eventJournal.last?.kind == eventKind &&
        current.lastRemoteEventSequence >= remoteSequence &&
        (remoteHandle == nil || current.remoteRunId == remoteHandle?.remoteRunId) &&
        (checkpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
          current.checkpoints.last?.stateJson == checkpoint)
      if alreadyCurrent {
        return
      }
      do {
        let evented = try workspaceStore.appendEvent(
          workspaceId: workspaceId,
          kind: eventKind,
          message: reason,
          payloadJson: Self.recoveryPayload(
            runId: snapshot.runId,
            remoteRunId: remoteHandle?.remoteRunId ?? "",
            remoteSequence: remoteSequence
          ),
          expectedRevision: current.revision
        )
        guard let evented else {
          return
        }
        let checkpointed: AgentWorkspace
        if checkpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          checkpointed = evented
        } else {
          checkpointed = try workspaceStore.checkpoint(
            workspaceId: workspaceId,
            checkpointId: "recovery-\(String(snapshot.runId.prefix(48)))-\(remoteSequence)",
            planSnapshot: evented.currentPlanSnapshot,
            stateJson: checkpoint,
            expectedRevision: evented.revision
          ) ?? evented
        }
        var updated = checkpointed
        updated.status = status
        updated.agentId = (remoteHandle?.agentId ?? "").ifBlank(checkpointed.agentId)
        updated.remoteRunId = (remoteHandle?.remoteRunId ?? "").ifBlank(checkpointed.remoteRunId)
        updated.lastRemoteEventSequence = max(checkpointed.lastRemoteEventSequence, remoteSequence)
        if status == .failed {
          updated.errorMessage = reason
        }
        updated.revision = checkpointed.revision
        _ = try workspaceStore.upsert(updated, expectedRevision: checkpointed.revision)
        return
      } catch is AgentWorkspaceRevisionConflictError {
        continue
      }
    }
    throw AgentRunRecoveryCoordinatorError(message: "Run recovery could not update workspace \(workspaceId)")
  }

  private func appendRecoveryEvent(
    _ snapshot: AgentRunControlSnapshot,
    reason: String,
    remoteSequence: Int64,
    source: String
  ) {
    _ = runStore.appendNext(event(
      from: snapshot,
      type: .runRecovered,
      payload: snapshot.lastEvent.payload.adding([
        "recovery_source": .string(source),
        "reason": .string(reason),
        "last_remote_event_sequence": .int(remoteSequence)
      ])
    ))
  }

  private func appendLocalWaitRecoveryEvent(_ snapshot: AgentRunControlSnapshot, reason: String) {
    let type: AgentRunControlEventType = snapshot.state == .paused ? .paused : .waitingForUser
    if snapshot.lastEvent.type == type,
      snapshot.lastEvent.payload["recovery_source"]?.stringValue == "local_wait" {
      return
    }
    _ = runStore.appendNext(event(
      from: snapshot,
      type: type,
      payload: snapshot.lastEvent.payload.adding([
        "recovery_source": .string("local_wait"),
        "reason": .string(reason),
        "last_local_event_sequence": .int(snapshot.lastSequence)
      ])
    ))
  }

  private func appendWaitingForDevice(_ snapshot: AgentRunControlSnapshot) {
    guard snapshot.lastEvent.type != .waitingForDevice else {
      return
    }
    _ = runStore.appendNext(event(
      from: snapshot,
      type: .waitingForDevice,
      payload: snapshot.lastEvent.payload.adding(["reason": .string(Self.remoteUnavailableReason)])
    ))
  }

  private func appendTerminalFailure(_ snapshot: AgentRunControlSnapshot, reason: String) {
    _ = runStore.appendNext(event(
      from: snapshot,
      type: .runFailed,
      payload: snapshot.lastEvent.payload.adding([
        "reason": .string(reason),
        "replay_safe": .bool(false)
      ])
    ))
  }

  private func appendRecordedTerminal(_ snapshot: AgentRunControlSnapshot, status: AgentRecordedRunStatus?) {
    guard let status else { return }
    let type: AgentRunControlEventType
    switch status {
    case .completed:
      type = .runCompleted
    case .cancelled:
      type = .runCancelled
    case .failed:
      type = .runFailed
    case .running:
      return
    }
    _ = runStore.appendNext(event(
      from: snapshot,
      type: type,
      payload: snapshot.lastEvent.payload.adding(["reason": .string("recorded_run_is_terminal")])
    ))
  }

  private func event(
    from snapshot: AgentRunControlSnapshot,
    type: AgentRunControlEventType,
    payload: AgentRunControlPayload
  ) -> AgentRunControlEvent {
    AgentRunControlEvent(
      eventId: UUID().uuidString,
      conversationId: snapshot.lastEvent.conversationId,
      messageId: snapshot.lastEvent.messageId,
      taskId: snapshot.lastEvent.taskId,
      runId: snapshot.lastEvent.runId,
      stepId: snapshot.lastEvent.stepId,
      toolCallId: snapshot.lastEvent.toolCallId,
      agentId: snapshot.lastEvent.agentId,
      deviceId: snapshot.lastEvent.deviceId,
      type: type,
      sequence: 0,
      timestampMillis: snapshot.lastEvent.timestampMillis,
      payload: payload
    )
  }

  private func terminalWorkspaceStatus(_ status: AgentRecordedRunStatus?) -> AgentWorkspaceStatus? {
    switch status {
    case .completed:
      return .completed
    case .cancelled:
      return .cancelled
    case .failed:
      return .failed
    case .running, nil:
      return nil
    }
  }

  private static func recoveryPayload(runId: String, remoteRunId: String, remoteSequence: Int64) -> String {
    AgentMcpJSONCodec.stringify([
      "run_id": .string(runId),
      "remote_run_id": .string(remoteRunId),
      "last_remote_event_sequence": .int(remoteSequence)
    ])
  }

  private static let remoteUnavailableReason = "remote_run_temporarily_unavailable"
  private static let maxWriteAttempts = 4
}

@MainActor
final class AgentStartupRecoveryCoordinator: ObservableObject {
  @Published private(set) var isRecovering = false
  @Published private(set) var recoveredRunCount = 0
  @Published private(set) var lastError = ""

  private var hasStarted = false

  func start(store: GalaxySSIStore) {
    guard !hasStarted else { return }
    hasStarted = true
    isRecovering = true
    lastError = ""

    let contacts = store.contacts
    Task { @MainActor [weak self] in
      let runStore = UserDefaultsAgentRunEventStore()
      let workspaceStore = FileAgentWorkspaceStore()
      let recordedStore = UserDefaultsAgentRecordedRunStore()
      let recovery = AgentRunRecoveryCoordinator(
        runStore: runStore,
        workspaceStore: workspaceStore,
        recordedRun: { runId in
          recordedStore.runs().first { $0.runId == runId }
        },
        registration: { agentId, deviceId in
          Self.recoveryRegistration(
            agentId: agentId,
            deviceId: deviceId,
            contacts: contacts
          )
        },
        adapterResolver: { _ in nil }
      )

      do {
        let results = try await recovery.recover()
        guard let self else { return }
        self.recoveredRunCount = results.count
        store.refreshAgentRuntimeState()
      } catch {
        self?.lastError = error.localizedDescription
      }
      self?.isRecovering = false
    }
  }

  private static func recoveryRegistration(
    agentId: String,
    deviceId: String,
    contacts: [GalaxySSIContact]
  ) -> AgentRunRecoveryRegistration? {
    let cleanAgentId = agentId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanDeviceId = deviceId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let contact = contacts.first(where: { contact in
      !contact.deleted && (
        contact.id == cleanAgentId ||
          contact.connectorAgentId == cleanAgentId ||
          (!cleanDeviceId.isEmpty && contact.desktopId == cleanDeviceId && contact.type == "agent")
      )
    }) else {
      return nil
    }

    let location: AgentResourceLocation
    let connectionKind: AgentConnectionKind
    switch contact.deliveryMode {
    case .local:
      location = .phone
      connectionKind = .inProcess
    case .cloudAPI:
      location = .cloud
      connectionKind = .http
    case .link, .pcConnector:
      location = .trustedDesktop
      connectionKind = .galaxyssiLink
    }
    return AgentRunRecoveryRegistration(
      agentId: contact.connectorAgentId.ifBlank(contact.id),
      location: location,
      connectionKind: connectionKind
    )
  }
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
