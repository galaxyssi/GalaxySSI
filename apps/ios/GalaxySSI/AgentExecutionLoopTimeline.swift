import Foundation

enum AgentExecutionLoopTimelineLabel: String, Codable, CaseIterable, Identifiable {
  case plan = "PLAN"
  case act = "ACT"
  case observe = "OBSERVE"
  case replan = "REPLAN"
  case verify = "VERIFY"
  case finalize = "FINALIZE"
  case learn = "LEARN"
  case waitingConfirmation = "WAITING_CONFIRMATION"
  case waitingResponse = "WAITING_RESPONSE"
  case paused = "PAUSED"
  case blocked = "BLOCKED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  init?(phase: AgentExecutionLoopPhase) {
    guard phase != .completed else {
      return nil
    }
    self.init(rawValue: phase.rawValue)
  }
}

enum AgentExecutionLoopTimelineAction: String, Codable, CaseIterable, Identifiable {
  case pause = "PAUSE"
  case resume = "RESUME"
  case retry = "RETRY"
  case replan = "REPLAN"
  case cancel = "CANCEL"

  var id: String { rawValue }
}

struct AgentExecutionLoopTimelineProjection: Codable, Equatable {
  var controlEventType: AgentRunControlEventType
  var label: AgentExecutionLoopTimelineLabel?
  var stepId: String
  var toolCallId: String
  var payload: AgentRunControlPayload

  enum CodingKeys: String, CodingKey {
    case controlEventType = "control_event_type"
    case label
    case stepId = "step_id"
    case toolCallId = "tool_call_id"
    case payload
  }
}

enum AgentRunTimelineKind: String, Codable, CaseIterable, Identifiable {
  case plan = "PLAN"
  case tool = "TOOL"
  case result = "RESULT"
  case failure = "FAILURE"
  case retry = "RETRY"
  case act = "ACT"
  case observe = "OBSERVE"
  case verify = "VERIFY"
  case learn = "LEARN"
  case other = "OTHER"

  var id: String { rawValue }

  var payloadValue: String {
    rawValue.lowercased()
  }

  static func fromPayload(_ value: String?) -> AgentRunTimelineKind? {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized }
  }
}

struct AgentRunTimelineCoverage: Codable, Equatable {
  var hasPlan: Bool
  var toolEventCount: Int
  var hasResult: Bool
  var hasFailure: Bool
  var retryEventCount: Int

  var terminal: Bool {
    hasResult || hasFailure
  }

  var complete: Bool {
    hasPlan && terminal
  }

  enum CodingKeys: String, CodingKey {
    case hasPlan = "has_plan"
    case toolEventCount = "tool_event_count"
    case hasResult = "has_result"
    case hasFailure = "has_failure"
    case retryEventCount = "retry_event_count"
  }
}

enum AgentRunTimelineContract {
  static let version = "galaxyssi.run-timeline/1.0"

  static func kind(_ event: AgentRunControlEvent) -> AgentRunTimelineKind {
    if let declared = AgentRunTimelineKind.fromPayload(event.payload["timeline_kind"]?.stringValue) {
      return declared
    }
    switch event.type {
    case .planning:
      return .plan
    case .toolStarted, .toolProgress, .toolCompleted, .toolPermissionRequired:
      return .tool
    case .retrying, .runRecovered:
      return .retry
    case .runCompleted:
      return .result
    case .runFailed, .runCancelled:
      return .failure
    default:
      return .other
    }
  }

  static func coverage(_ events: [AgentRunControlEvent]) -> AgentRunTimelineCoverage {
    let kinds = events.map(kind)
    return AgentRunTimelineCoverage(
      hasPlan: kinds.contains(.plan),
      toolEventCount: kinds.filter { $0 == .tool }.count,
      hasResult: kinds.contains(.result),
      hasFailure: kinds.contains(.failure),
      retryEventCount: kinds.filter { $0 == .retry }.count
    )
  }
}

enum AgentExecutionLoopTimelinePolicy {
  static func actionsForPhase(_ phase: AgentPhase) -> [AgentExecutionLoopTimelineAction] {
    switch phase {
    case .planning, .waitingConfirmation, .executing, .verifying:
      return [.pause, .cancel]
    case .observing, .waitingResponse:
      return [.cancel]
    case .paused:
      return [.resume, .cancel]
    case .blocked:
      return [.replan, .cancel]
    case .failed:
      return [.retry, .replan]
    case .cancelled, .completed:
      return []
    }
  }

  static func project(_ event: AgentExecutionLoopEvent) -> AgentExecutionLoopTimelineProjection {
    let recovered = event.previousPhase.map { [.blocked, .failed].contains($0) } == true && event.phase.isActive
    let phaseType: AgentRunControlEventType
    switch event.phase {
    case .plan:
      phaseType = .planning
    case .act:
      phaseType = event.toolCall ? .toolStarted : .stepStarted
    case .observe:
      phaseType = .toolProgress
    case .replan:
      phaseType = .retrying
    case .verify:
      phaseType = .toolProgress
    case .finalize, .learn:
      phaseType = .stepCompleted
    case .waitingConfirmation:
      phaseType = .waitingForUser
    case .waitingResponse:
      phaseType = .waitingForDevice
    case .paused:
      phaseType = .paused
    case .blocked, .failed:
      phaseType = .runFailed
    case .cancelled:
      phaseType = .runCancelled
    case .completed:
      phaseType = .runCompleted
    }
    let timelineKind: AgentRunTimelineKind
    switch event.phase {
    case .plan:
      timelineKind = .plan
    case .act:
      timelineKind = event.toolCall ? .tool : .act
    case .observe:
      timelineKind = .observe
    case .replan:
      timelineKind = .retry
    case .verify:
      timelineKind = .verify
    case .finalize, .completed:
      timelineKind = .result
    case .learn:
      timelineKind = .learn
    case .blocked, .failed, .cancelled:
      timelineKind = .failure
    case .waitingConfirmation, .waitingResponse, .paused:
      timelineKind = .other
    }
    let actionId = event.snapshot.lastActionId
    return AgentExecutionLoopTimelineProjection(
      controlEventType: recovered ? .runRecovered : phaseType,
      label: AgentExecutionLoopTimelineLabel(phase: event.phase),
      stepId: actionId,
      toolCallId: event.toolCall ? actionId : "",
      payload: [
        "timeline_contract": .string(AgentRunTimelineContract.version),
        "timeline_kind": .string(timelineKind.payloadValue),
        "loop_phase": .string(event.phase.rawValue.lowercased()),
        "previous_loop_phase": .string(event.previousPhase?.rawValue.lowercased() ?? ""),
        "loop_revision": .int(event.snapshot.revision),
        "loop_reason": .string(event.reason),
        "loop_task_id": .string(event.snapshot.taskId),
        "loop_action_id": .string(actionId),
        "loop_retry": .bool(event.retry),
        "loop_tool_call": .bool(event.toolCall),
        "loop_iterations": .int(Int64(event.snapshot.usage.iterations)),
        "loop_actions": .int(Int64(event.snapshot.usage.actions)),
        "loop_replans": .int(Int64(event.snapshot.usage.replans)),
        "loop_tool_calls": .int(Int64(event.snapshot.usage.toolCalls)),
        "loop_retries": .int(Int64(event.snapshot.usage.retries)),
        "loop_active_ms": .int(event.snapshot.usage.activeDurationMillis),
        "loop_budget_failure": .string(event.snapshot.budgetFailure)
      ]
    )
  }

  static func isSameRevision(event: AgentRunControlEvent?, revision: Int64) -> Bool {
    event?.payload["loop_revision"]?.intValue == revision
  }

  static func transcriptDedupeKey(turnId: String, event: AgentExecutionLoopEvent) -> String {
    "agent-loop:\(turnId):\(event.phase.rawValue):\(event.snapshot.revision)"
  }

  static func phaseFromTranscriptDedupeKey(_ value: String) -> AgentExecutionLoopPhase? {
    guard value.hasPrefix("agent-loop:") else {
      return nil
    }
    let parts = value.split(separator: ":").map(String.init)
    guard parts.count > 2 else {
      return nil
    }
    let phaseName = parts[2].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    return AgentExecutionLoopPhase.allCases.first { $0.rawValue == phaseName }
  }

  static func suppressSupersededPlaceholders(_ entries: [AgentTranscriptEntry]) -> [AgentTranscriptEntry] {
    let hasToolStart = entries.contains { $0.dedupeKey.contains(":TOOL_STARTED:") }
    let hasToolCompletion = entries.contains { $0.dedupeKey.contains(":TOOL_COMPLETED:") }
    return entries.filter { entry in
      let phase = phaseFromTranscriptDedupeKey(entry.dedupeKey)
      if phase == .act {
        return !hasToolStart
      }
      if phase == .observe {
        return !hasToolCompletion
      }
      return true
    }
  }
}
