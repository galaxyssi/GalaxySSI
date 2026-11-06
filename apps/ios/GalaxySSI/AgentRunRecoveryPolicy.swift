import CryptoKit
import Foundation

struct AgentRunRecoveryRegistration: Codable, Equatable {
  var agentId: String
  var location: AgentResourceLocation
  var connectionKind: AgentConnectionKind

  init(
    agentId: String,
    location: AgentResourceLocation,
    connectionKind: AgentConnectionKind
  ) {
    self.agentId = agentId
    self.location = location
    self.connectionKind = connectionKind
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case location
    case connectionKind = "connection_kind"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      agentId: try container.decodeIfPresent(String.self, forKey: .agentId) ?? "",
      location: try container.decodeIfPresent(AgentResourceLocation.self, forKey: .location) ?? .cloud,
      connectionKind: try container.decodeIfPresent(AgentConnectionKind.self, forKey: .connectionKind) ?? .http
    )
  }
}

enum AgentRunRecoveryDisposition: String, Codable, CaseIterable, Identifiable {
  case restoreLocalWait = "RESTORE_LOCAL_WAIT"
  case reconnectDurableRemote = "RECONNECT_DURABLE_REMOTE"
  case failNonReplayable = "FAIL_NON_REPLAYABLE"
  case ignoreTerminal = "IGNORE_TERMINAL"

  var id: String { rawValue }
}

struct AgentRunRecoveryDecision: Codable, Equatable {
  var disposition: AgentRunRecoveryDisposition
  var reason: String
}

struct AgentRunRootIdentity: Equatable {
  var clientRouteId: String
  var conversationId: String
  var goalId: String
  var taskId: String
  var runId: String
}

enum AgentRunKernelContract {
  static let protocolId = "galaxyssi.agent-run-event.v1"
  static let schemaVersion = 1

  static func canonical(_ event: AgentRunControlEvent) -> AgentRunControlEvent? {
    guard event.protocolId == protocolId,
          event.schemaVersion == schemaVersion else { return nil }
    let eventId = clean(event.eventId)
    let taskId = clean(event.taskId)
    let runId = clean(event.runId)
    let agentId = clean(event.agentId)
    guard !eventId.isEmpty, !taskId.isEmpty, !runId.isEmpty, !agentId.isEmpty else {
      return nil
    }
    let deviceId = fallback(clean(event.deviceId), "local")
    let messageId = clean(event.messageId)
    let stepId = clean(event.stepId)
    let toolCallId = clean(event.toolCallId)
    var canonical = event
    canonical.eventId = eventId
    canonical.taskId = taskId
    canonical.runId = runId
    canonical.agentId = agentId
    canonical.deviceId = deviceId
    canonical.messageId = messageId
    canonical.stepId = stepId
    canonical.toolCallId = toolCallId
    canonical.idempotencyKey = fallback(clean(event.idempotencyKey), eventId)
    canonical.clientRouteId = fallback(clean(event.clientRouteId), deviceId)
    canonical.conversationId = fallback(clean(event.conversationId), "conversation:\(taskId)")
    canonical.goalId = fallback(clean(event.goalId), taskId)
    canonical.turnId = fallback(clean(event.turnId), fallback(messageId, "turn:\(taskId)"))
    canonical.actionId = fallback(
      clean(event.actionId),
      fallback(toolCallId, fallback(stepId, eventId))
    )
    return canonical
  }

  static func rootIdentity(_ event: AgentRunControlEvent) -> AgentRunRootIdentity? {
    guard let canonical = canonical(event) else { return nil }
    return AgentRunRootIdentity(
      clientRouteId: canonical.clientRouteId,
      conversationId: canonical.conversationId,
      goalId: canonical.goalId,
      taskId: canonical.taskId,
      runId: canonical.runId
    )
  }

  static func hasSameRoot(_ first: AgentRunControlEvent, _ second: AgentRunControlEvent) -> Bool {
    guard let firstRoot = rootIdentity(first), let secondRoot = rootIdentity(second) else {
      return false
    }
    return firstRoot == secondRoot
  }

  static func isIdempotentReplay(
    _ firstEvent: AgentRunControlEvent,
    _ replayEvent: AgentRunControlEvent
  ) -> Bool {
    guard let first = canonical(firstEvent), let replay = canonical(replayEvent) else {
      return false
    }
    return first.idempotencyKey == replay.idempotencyKey
      && hasSameRoot(first, replay)
      && first.turnId == replay.turnId
      && first.actionId == replay.actionId
      && first.messageId == replay.messageId
      && first.stepId == replay.stepId
      && first.toolCallId == replay.toolCallId
      && first.agentId == replay.agentId
      && first.deviceId == replay.deviceId
      && first.type == replay.type
      && first.payload == replay.payload
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func fallback(_ value: String, _ fallback: String) -> String {
    value.isEmpty ? fallback : value
  }
}

enum AgentRunEventStore {
  static func reduce(
    current: AgentRunControlState,
    event: AgentRunControlEventType
  ) -> AgentRunControlState {
    let next: AgentRunControlState
    switch event {
    case .runCreated:
      next = .created
    case .runQueued:
      next = .queued
    case .runStarted,
         .planning,
         .thinking,
         .agentConnected,
         .stepStarted,
         .toolStarted,
         .toolProgress,
         .toolCompleted,
         .retrying,
         .handoff,
         .stepCompleted,
         .runRecovered:
      next = .running
    case .checkpointSaved:
      next = current
    case .toolPermissionRequired,
         .waitingForUser:
      next = .waitingForUser
    case .permissionRevoked,
         .paused,
         .runInterrupted:
      next = .paused
    case .waitingForDevice:
      next = .waitingForDevice
    case .runCompleted:
      next = .completed
    case .runFailed:
      next = .failed
    case .runCancelled:
      next = .cancelled
    }
    if current.isTerminal && event != .runRecovered {
      return current
    }
    return next
  }

  static func recoverableRuns(_ snapshots: [AgentRunControlSnapshot]) -> [AgentRunControlSnapshot] {
    snapshots.filter { !$0.state.isTerminal }
  }
}

enum AgentRunRecoveryPolicy {
  static func isObservationOnly(_ event: AgentRunControlEvent) -> Bool {
    event.payload["recovery_mode"] == .string("observation_only") ||
      event.payload["observation_only"]?.boolValue == true ||
      AgentDeviceOperationCheckpoint.isSnapshot(event)
  }

  static func decide(
    snapshot: AgentRunControlSnapshot,
    recordedRun: AgentRecordedRun?,
    registration: AgentRunRecoveryRegistration?
  ) -> AgentRunRecoveryDecision {
    if let recordedRun, recordedRun.status != .running {
      return AgentRunRecoveryDecision(
        disposition: .ignoreTerminal,
        reason: "recorded_run_is_terminal"
      )
    }
    if snapshot.state == .waitingForUser || snapshot.state == .paused {
      return AgentRunRecoveryDecision(
        disposition: .restoreLocalWait,
        reason: "user_resumable_checkpoint"
      )
    }
    if let registration,
      registration.location == .trustedDesktop,
      durableRemoteConnectionKinds.contains(registration.connectionKind) {
      return AgentRunRecoveryDecision(
        disposition: .reconnectDurableRemote,
        reason: "durable_remote_run_can_reconnect"
      )
    }
    return AgentRunRecoveryDecision(
      disposition: .failNonReplayable,
      reason: "interrupted_run_cannot_be_replayed_safely"
    )
  }

  private static let durableRemoteConnectionKinds: Set<AgentConnectionKind> = [
    .galaxyssiLink,
    .websocket,
    .cliJson,
    .stdio
  ]
}

enum AgentDeviceOperationCheckpoint {
  static let runPrefix = "device-operation:"

  static func runId(conversationId: String) -> String {
    let bytes = Data(AgentMcpJSONCodec.stringify(.string(conversationId)).utf8)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    return runPrefix + digest
  }

  static func isSnapshot(_ event: AgentRunControlEvent) -> Bool {
    guard event.payload["snapshot_kind"] == .string("device_operation"),
          case .string(let operationId)? = event.payload["operation_id"], !operationId.isBlank
    else { return false }
    return ownsRun(event)
  }

  static func ownsRun(_ event: AgentRunControlEvent) -> Bool {
    event.agentId == "phone-operation" && event.deviceId == "local" && !event.conversationId.isBlank &&
      event.taskId == event.runId && event.messageId.isBlank &&
      event.runId == runId(conversationId: event.conversationId)
  }

  static func isMisclassifiedFailure(_ event: AgentRunControlEvent) -> Bool {
    isSnapshot(event) && event.type == .runFailed && event.payload["replay_safe"] == .bool(false) &&
      event.payload["reason"] == .string("interrupted_run_cannot_be_replayed_safely") &&
      event.payload["status"] != .string("cancelled")
  }

  static func preparingForAppend(
    _ event: AgentRunControlEvent, after previous: AgentRunControlEvent?
  ) -> AgentRunControlEvent? {
    let deviceSnapshot = isSnapshot(event)
    if event.type == .runRecovered && (ownsRun(event) || previous.map(ownsRun) == true) { return nil }
    guard deviceSnapshot, event.type == .checkpointSaved else { return event }
    if let previous, isSnapshot(previous) {
      if previous.payload["operation_id"] == event.payload["operation_id"],
         previous.payload["status"] == .string("cancelled"), event.payload["status"] != .string("cancelled") {
        return nil
      }
      if let recordedAt = previous.payload["updated_at"]?.intValue,
         let candidateAt = event.payload["updated_at"]?.intValue, candidateAt < recordedAt { return nil }
    }
    var checkpoint = event
    checkpoint.payload["recovery_mode"] = .string("observation_only")
    // Only a new checkpoint can repair the old synthetic failure; no operation is reissued.
    if let previous, isMisclassifiedFailure(previous) {
      guard event.payload["status"] != .string("cancelled") else { return nil }
      checkpoint.type = .runRecovered
    }
    return checkpoint
  }

  static func replayMatches(_ existing: AgentRunControlEvent, _ checkpoint: AgentRunControlEvent) -> Bool {
    var replay = checkpoint
    if checkpoint.type == .checkpointSaved && isSnapshot(checkpoint) {
      replay.payload["recovery_mode"] = .string("observation_only")
      if existing.type == .runRecovered && isSnapshot(existing) { replay.type = .runRecovered }
    }
    return AgentRunKernelContract.isIdempotentReplay(existing, replay)
  }
}
