import Foundation

enum AgentTaskLivenessState: String, Codable, CaseIterable, Identifiable {
  case healthy = "HEALTHY"
  case stalled = "STALLED"
  case assessmentRequired = "ASSESSMENT_REQUIRED"

  var id: String { rawValue }
}

struct AgentTaskLivenessDecision: Codable, Equatable {
  var state: AgentTaskLivenessState
  var reason: String
  var idleMillis: Int64
  var lifetimeMillis: Int64

  init(
    state: AgentTaskLivenessState,
    reason: String = "",
    idleMillis: Int64 = 0,
    lifetimeMillis: Int64 = 0
  ) {
    self.state = state
    self.reason = reason
    self.idleMillis = idleMillis
    self.lifetimeMillis = lifetimeMillis
  }

  enum CodingKeys: String, CodingKey {
    case state
    case reason
    case idleMillis = "idle_millis"
    case lifetimeMillis = "lifetime_millis"
  }
}

enum AgentTaskLivenessSignalKind: String, Codable, CaseIterable, Identifiable {
  case stalled = "STALLED"
  case recovered = "RECOVERED"
  case assessmentRequired = "ASSESSMENT_REQUIRED"

  var id: String { rawValue }
}

struct AgentTaskLivenessSignal: Codable, Equatable {
  var kind: AgentTaskLivenessSignalKind
  var workspace: AgentWorkspace
  var reason: String
  var observedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case kind
    case workspace
    case reason
    case observedAtMillis = "observed_at_millis"
  }
}

enum AgentTaskTerminalReplyPolicy {
  static func hasTerminalReply(entries: [AgentTranscriptEntry], turnId: String) -> Bool {
    let cleanTurnId = turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanTurnId.isEmpty else {
      return false
    }
    return entries.contains { entry in
      (entry.turnId == cleanTurnId || entry.taskId == cleanTurnId) &&
        entry.role == .assistant &&
        terminalDedupePrefixes.contains(where: { entry.dedupeKey.hasPrefix($0) })
    }
  }

  private static let terminalDedupePrefixes = [
    "assistant-final:",
    "result:",
    "direct-system:",
    "fast-local:",
    "skill-command:",
    "skill-result:"
  ]
}

struct AgentTaskLivenessPolicy: Codable, Equatable {
  var queuedWarningMillis: Int64
  var queuedTimeoutMillis: Int64
  var runningWarningMillis: Int64
  var runningTimeoutMillis: Int64
  var waitingResponseWarningMillis: Int64
  var waitingResponseTimeoutMillis: Int64
  var absoluteTimeoutMillis: Int64
  var watchdogIntervalMillis: Int64
  var heartbeatWriteThrottleMillis: Int64

  init(
    queuedWarningMillis: Int64 = 15_000,
    queuedTimeoutMillis: Int64 = 90_000,
    runningWarningMillis: Int64 = 45_000,
    runningTimeoutMillis: Int64 = 10 * 60_000,
    waitingResponseWarningMillis: Int64 = 30_000,
    waitingResponseTimeoutMillis: Int64 = 6 * 60_000,
    absoluteTimeoutMillis: Int64 = 0,
    watchdogIntervalMillis: Int64 = 5_000,
    heartbeatWriteThrottleMillis: Int64 = 10_000
  ) {
    precondition(queuedWarningMillis > 0 && queuedTimeoutMillis > queuedWarningMillis)
    precondition(runningWarningMillis > 0 && runningTimeoutMillis > runningWarningMillis)
    precondition(waitingResponseWarningMillis > 0 && waitingResponseTimeoutMillis > waitingResponseWarningMillis)
    precondition(absoluteTimeoutMillis >= 0)
    precondition(watchdogIntervalMillis > 0)
    precondition(heartbeatWriteThrottleMillis >= 0)
    self.queuedWarningMillis = queuedWarningMillis
    self.queuedTimeoutMillis = queuedTimeoutMillis
    self.runningWarningMillis = runningWarningMillis
    self.runningTimeoutMillis = runningTimeoutMillis
    self.waitingResponseWarningMillis = waitingResponseWarningMillis
    self.waitingResponseTimeoutMillis = waitingResponseTimeoutMillis
    self.absoluteTimeoutMillis = absoluteTimeoutMillis
    self.watchdogIntervalMillis = watchdogIntervalMillis
    self.heartbeatWriteThrottleMillis = heartbeatWriteThrottleMillis
  }

  enum CodingKeys: String, CodingKey {
    case queuedWarningMillis = "queued_warning_millis"
    case queuedTimeoutMillis = "queued_timeout_millis"
    case runningWarningMillis = "running_warning_millis"
    case runningTimeoutMillis = "running_timeout_millis"
    case waitingResponseWarningMillis = "waiting_response_warning_millis"
    case waitingResponseTimeoutMillis = "waiting_response_timeout_millis"
    case absoluteTimeoutMillis = "absolute_timeout_millis"
    case watchdogIntervalMillis = "watchdog_interval_millis"
    case heartbeatWriteThrottleMillis = "heartbeat_write_throttle_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      queuedWarningMillis: try container.decodeIfPresent(Int64.self, forKey: .queuedWarningMillis) ?? 15_000,
      queuedTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .queuedTimeoutMillis) ?? 90_000,
      runningWarningMillis: try container.decodeIfPresent(Int64.self, forKey: .runningWarningMillis) ?? 45_000,
      runningTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .runningTimeoutMillis) ?? 10 * 60_000,
      waitingResponseWarningMillis: try container.decodeIfPresent(Int64.self, forKey: .waitingResponseWarningMillis) ?? 30_000,
      waitingResponseTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .waitingResponseTimeoutMillis) ?? 6 * 60_000,
      absoluteTimeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .absoluteTimeoutMillis) ?? 0,
      watchdogIntervalMillis: try container.decodeIfPresent(Int64.self, forKey: .watchdogIntervalMillis) ?? 5_000,
      heartbeatWriteThrottleMillis: try container.decodeIfPresent(Int64.self, forKey: .heartbeatWriteThrottleMillis) ?? 10_000
    )
  }

  func evaluate(
    workspace: AgentWorkspace,
    nowMillis: Int64,
    volatileActivityAtMillis: Int64 = 0
  ) -> AgentTaskLivenessDecision {
    if workspace.status.isTerminal ||
      workspace.cancellationRequested ||
      Self.userControlledStatuses.contains(workspace.status) {
      return AgentTaskLivenessDecision(state: .healthy)
    }
    let now = max(nowMillis, 0)
    let lastActivity = max(
      meaningfulActivityAt(workspace),
      max(volatileActivityAtMillis, 0)
    )
    let startedAt = workspace.createdAtMillis > 0
      ? workspace.createdAtMillis
      : (lastActivity > 0 ? lastActivity : now)
    let idleMillis = max(now - min(lastActivity, now), 0)
    let lifetimeMillis = max(now - min(startedAt, now), 0)
    if absoluteTimeoutMillis > 0 && lifetimeMillis >= absoluteTimeoutMillis {
      return AgentTaskLivenessDecision(
        state: .assessmentRequired,
        reason: "absolute_deadline_assessment_due",
        idleMillis: idleMillis,
        lifetimeMillis: lifetimeMillis
      )
    }
    guard let thresholds = thresholds(for: workspace.status) else {
      return AgentTaskLivenessDecision(state: .healthy)
    }
    if idleMillis >= thresholds.timeout {
      return AgentTaskLivenessDecision(
        state: .assessmentRequired,
        reason: "\(workspace.status.rawValue.lowercased())_progress_assessment_due",
        idleMillis: idleMillis,
        lifetimeMillis: lifetimeMillis
      )
    }
    if idleMillis >= thresholds.warning {
      return AgentTaskLivenessDecision(
        state: .stalled,
        reason: "\(workspace.status.rawValue.lowercased())_progress_stalled",
        idleMillis: idleMillis,
        lifetimeMillis: lifetimeMillis
      )
    }
    return AgentTaskLivenessDecision(
      state: .healthy,
      idleMillis: idleMillis,
      lifetimeMillis: lifetimeMillis
    )
  }

  func hasUnresolvedStall(workspace: AgentWorkspace) -> Bool {
    guard let stalledSequence = workspace.eventJournal
      .reversed()
      .first(where: { $0.kind == AgentTaskEventKinds.stalled })?.sequence else {
      return false
    }
    return !workspace.eventJournal.contains { event in
      event.sequence > stalledSequence && !Self.supervisorObservationEvents.contains(event.kind)
    }
  }

  func hasPendingAssessment(workspace: AgentWorkspace) -> Bool {
    guard let assessmentSequence = workspace.eventJournal
      .reversed()
      .first(where: { $0.kind == AgentTaskEventKinds.livenessAssessmentRequested })?.sequence else {
      return false
    }
    return !workspace.eventJournal.contains { event in
      event.sequence > assessmentSequence && !Self.supervisorObservationEvents.contains(event.kind)
    }
  }

  func meaningfulActivityAt(_ workspace: AgentWorkspace) -> Int64 {
    let eventAt = workspace.eventJournal
      .filter { !Self.supervisorObservationEvents.contains($0.kind) }
      .map(\.timestampMillis)
      .max() ?? 0
    return max(
      workspace.createdAtMillis,
      eventAt,
      workspace.eventJournal.isEmpty ? workspace.updatedAtMillis : 0
    )
  }

  private func thresholds(for status: AgentWorkspaceStatus) -> (warning: Int64, timeout: Int64)? {
    switch status {
    case .created, .queued:
      return (queuedWarningMillis, queuedTimeoutMillis)
    case .running:
      return (runningWarningMillis, runningTimeoutMillis)
    case .waitingResponse:
      return (waitingResponseWarningMillis, waitingResponseTimeoutMillis)
    case .waitingConfirmation, .paused, .blocked, .completed, .failed, .cancelled:
      return nil
    }
  }

  private static let userControlledStatuses: Set<AgentWorkspaceStatus> = [
    .waitingConfirmation,
    .paused,
    .blocked
  ]
  private static let supervisorObservationEvents: Set<String> = [
    AgentTaskEventKinds.stalled,
    AgentTaskEventKinds.timedOut,
    AgentTaskEventKinds.livenessAssessmentRequested,
    AgentTaskEventKinds.recoveryWaitingResponse,
    AgentTaskEventKinds.interrupted
  ]
}

enum AgentLongTaskRecoveryMode: String, Codable {
  case interruptedExecution = "INTERRUPTED_EXECUTION"
  case livenessAssessment = "LIVENESS_ASSESSMENT"
}

struct AgentLongTaskRecoveryDecision: Codable, Equatable {
  var mode: AgentLongTaskRecoveryMode
  var reason: String
}

enum AgentLongTaskRecoveryPolicy {
  static func decide(
    workspace: AgentWorkspace,
    session: AgentSessionSnapshot?,
    activeWorkspaceIds: Set<String> = []
  ) -> AgentLongTaskRecoveryDecision? {
    guard !activeWorkspaceIds.contains(workspace.workspaceId),
          !workspace.status.isTerminal,
          !workspace.cancellationRequested,
          let session,
          let plan = session.currentPlan else {
      return nil
    }
    let liveness = AgentTaskLivenessPolicy()
    if liveness.hasPendingAssessment(workspace: workspace) {
      let recordedReason = workspace.eventJournal.reversed()
        .first(where: { $0.kind == AgentTaskEventKinds.livenessAssessmentRequested })?
        .message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return AgentLongTaskRecoveryDecision(
        mode: .livenessAssessment,
        reason: recordedReason.isEmpty ? "The task stopped reporting progress" : recordedReason
      )
    }
    let interrupted = session.lastActionResult?.actionId == "agent-interrupted" ||
      plan.hasInterruptedExecutionEvidence
    guard interrupted,
          [.created, .queued, .running, .paused].contains(workspace.status) else {
      return nil
    }
    return AgentLongTaskRecoveryDecision(
      mode: .interruptedExecution,
      reason: "The app process ended before the active action produced a verified outcome"
    )
  }
}

extension AgentPlan {
  var hasInterruptedExecutionEvidence: Bool {
    (actionHistory + actions).contains {
      $0.evidence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "interrupted"
    }
  }
}

enum AgentLongTaskRecoveryClaims {
  private static let lock = NSRecursiveLock()
  private static var workspaceIds: Set<String> = []

  static func tryAcquire(workspaceId: String) -> Claim? {
    let clean = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return synchronized {
      guard workspaceIds.insert(clean).inserted else { return nil }
      return Claim(workspaceId: clean)
    }
  }

  final class Claim {
    private let workspaceId: String
    private var closed = false

    fileprivate init(workspaceId: String) {
      self.workspaceId = workspaceId
    }

    func close() {
      AgentLongTaskRecoveryClaims.synchronized {
        guard !closed else { return }
        closed = true
        AgentLongTaskRecoveryClaims.workspaceIds.remove(workspaceId)
      }
    }

    deinit { close() }
  }

  private static func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
