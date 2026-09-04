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
    case .toolPermissionRequired,
         .waitingForUser:
      next = .waitingForUser
    case .permissionRevoked,
         .paused:
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
