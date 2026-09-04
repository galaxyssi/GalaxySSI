import Foundation

struct AgentTaskLivenessWorkspaceReduction: Codable, Equatable {
  var workspace: AgentWorkspace
  var signal: AgentTaskLivenessSignal?
  var changed: Bool
  var cancelExecutionReason: String

  init(
    workspace: AgentWorkspace,
    signal: AgentTaskLivenessSignal? = nil,
    changed: Bool = false,
    cancelExecutionReason: String = ""
  ) {
    self.workspace = workspace
    self.signal = signal
    self.changed = changed
    self.cancelExecutionReason = cancelExecutionReason.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  enum CodingKeys: String, CodingKey {
    case workspace
    case signal
    case changed
    case cancelExecutionReason = "cancel_execution_reason"
  }
}

enum AgentTaskLivenessWorkspaceReducer {
  static let defaultMaxEventCount = 100
  static let defaultRecoveredReason = "progress_resumed"

  static func sweep(
    workspace: AgentWorkspace,
    policy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy(),
    nowMillis: Int64,
    volatileActivityAtMillis: Int64 = 0,
    maxEventCount: Int = defaultMaxEventCount
  ) -> AgentTaskLivenessWorkspaceReduction {
    let decision = policy.evaluate(
      workspace: workspace,
      nowMillis: nowMillis,
      volatileActivityAtMillis: volatileActivityAtMillis
    )
    return apply(
      decision: decision,
      to: workspace,
      policy: policy,
      observedAtMillis: nowMillis,
      maxEventCount: maxEventCount
    )
  }

  static func apply(
    decision: AgentTaskLivenessDecision,
    to workspace: AgentWorkspace,
    policy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy(),
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount
  ) -> AgentTaskLivenessWorkspaceReduction {
    switch decision.state {
    case .healthy:
      return AgentTaskLivenessWorkspaceReduction(workspace: workspace)
    case .stalled:
      guard !workspace.status.isTerminal,
        !workspace.cancellationRequested,
        !policy.hasUnresolvedStall(workspace: workspace) else {
        return AgentTaskLivenessWorkspaceReduction(workspace: workspace)
      }
      let updated = appendEvent(
        to: workspace,
        kind: AgentTaskEventKinds.stalled,
        message: message(decision: decision, fallback: "progress_stalled"),
        payloadJson: decisionPayload(decision),
        timestampMillis: observedAtMillis,
        maxEventCount: maxEventCount
      )
      return AgentTaskLivenessWorkspaceReduction(
        workspace: updated,
        signal: AgentTaskLivenessSignal(
          kind: .stalled,
          workspace: updated,
          reason: message(decision: decision, fallback: "progress_stalled"),
          observedAtMillis: max(observedAtMillis, 0)
        ),
        changed: true
      )
    case .assessmentRequired:
      guard !workspace.status.isTerminal,
        !workspace.cancellationRequested,
        !policy.hasPendingAssessment(workspace: workspace) else {
        return AgentTaskLivenessWorkspaceReduction(workspace: workspace)
      }
      let reason = message(decision: decision, fallback: "progress_assessment_due")
      let updated = appendEvent(
        to: workspace,
        kind: AgentTaskEventKinds.livenessAssessmentRequested,
        message: reason,
        payloadJson: assessmentPayload(decision),
        timestampMillis: observedAtMillis,
        maxEventCount: maxEventCount
      )
      return AgentTaskLivenessWorkspaceReduction(
        workspace: updated,
        signal: AgentTaskLivenessSignal(
          kind: .assessmentRequired,
          workspace: updated,
          reason: reason,
          observedAtMillis: max(observedAtMillis, 0)
        ),
        changed: true,
        cancelExecutionReason: "Yielding the current execution lease for model liveness assessment"
      )
    }
  }

  static func recordActivity(
    workspace: AgentWorkspace,
    eventKind: String,
    stage: String,
    message rawMessage: String = "",
    policy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy(),
    observedAtMillis: Int64,
    maxEventCount: Int = defaultMaxEventCount
  ) -> AgentTaskLivenessWorkspaceReduction {
    guard !workspace.status.isTerminal,
      !workspace.cancellationRequested else {
      return AgentTaskLivenessWorkspaceReduction(workspace: workspace)
    }
    let kind = clean(eventKind)
    guard !kind.isEmpty else {
      return AgentTaskLivenessWorkspaceReduction(workspace: workspace)
    }
    let cleanStage = clean(stage).isEmpty ? "running" : clean(stage)
    let cleanMessage = clean(rawMessage).isEmpty ? cleanStage : clean(rawMessage)
    let recovered = policy.hasUnresolvedStall(workspace: workspace) ||
      policy.hasPendingAssessment(workspace: workspace)
    let observedAt = max(observedAtMillis, 0)
    if !recovered,
      let previous = workspace.eventJournal.last,
      previous.kind == kind,
      previous.message == cleanMessage,
      observedAt - previous.timestampMillis < policy.heartbeatWriteThrottleMillis {
      return AgentTaskLivenessWorkspaceReduction(workspace: workspace)
    }
    let updated = appendEvent(
      to: workspace,
      kind: kind,
      message: cleanMessage,
      payloadJson: AgentMcpJSONCodec.stringify(["stage": .string(cleanStage)]),
      timestampMillis: observedAt,
      maxEventCount: maxEventCount
    )
    return AgentTaskLivenessWorkspaceReduction(
      workspace: updated,
      signal: recovered
        ? AgentTaskLivenessSignal(
          kind: .recovered,
          workspace: updated,
          reason: defaultRecoveredReason,
          observedAtMillis: observedAt
        )
        : nil,
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

  private static func decisionPayload(_ decision: AgentTaskLivenessDecision) -> String {
    AgentMcpJSONCodec.stringify([
      "idle_ms": .int(max(decision.idleMillis, 0)),
      "lifetime_ms": .int(max(decision.lifetimeMillis, 0))
    ])
  }

  private static func assessmentPayload(_ decision: AgentTaskLivenessDecision) -> String {
    AgentMcpJSONCodec.stringify([
      "idle_ms": .int(max(decision.idleMillis, 0)),
      "lifetime_ms": .int(max(decision.lifetimeMillis, 0)),
      "decision_owner": .string("model")
    ])
  }

  private static func message(
    decision: AgentTaskLivenessDecision,
    fallback: String
  ) -> String {
    let reason = clean(decision.reason)
    return reason.isEmpty ? fallback : reason
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
