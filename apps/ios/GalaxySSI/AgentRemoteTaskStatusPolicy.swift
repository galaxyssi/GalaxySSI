import Foundation

struct AgentRemoteTaskStatusEvent: Equatable, Identifiable {
  let status: String
  let currentStep: String
  let detail: String
  let updatedAtMillis: Int64

  var id: String {
    "\(status):\(updatedAtMillis):\(currentStep):\(detail)"
  }
}

struct AgentRemoteTaskStatusSnapshot: Equatable, Identifiable {
  let taskId: String
  let clientRouteId: String
  let contactId: String
  let conversationId: String
  let turnId: String
  let sourceMessageId: Int64
  let status: String
  let target: String
  let location: String
  let currentStep: String
  let advertisedCancellable: Bool
  let detail: String
  let updatedAtMillis: Int64
  let history: [AgentRemoteTaskStatusEvent]

  var id: String {
    "\(conversationId):\(taskId.ifBlank(turnId))"
  }

  var isCancellable: Bool {
    advertisedCancellable && !AgentRemoteTaskStatusPolicy.isTerminal(status)
  }
}

enum AgentCodexSilenceRecoveryPolicy {
  static let silenceMillis: Int64 = 180_000

  static func isCodex(adapter: String, agentId: String) -> Bool {
    ["codex-app-server-or-cli", "codex"].contains(adapter.lowercased()) || agentId.lowercased() == "codex"
  }

  static func confirmedTimeout(status: String, failureCode: String, error: String) -> Bool {
    guard ["failed", "timed_out"].contains(AgentRemoteTaskStatusPolicy.normalize(status)) else { return false }
    if !failureCode.isBlank { return failureCode == "codex_no_progress_timeout" }
    return error.trimmingCharacters(in: .whitespacesAndNewlines)
      .caseInsensitiveCompare("Codex task stalled") == .orderedSame
  }

  static func isSilent(status: String, since lastProgress: Int64, now: Int64) -> Bool {
    ["accepted", "queued", "starting", "running", "recovering"].contains(status) &&
      lastProgress > 0 && now >= lastProgress && now - lastProgress >= silenceMillis
  }

  struct Budget: Codable, Equatable {
    let origin: String
    private(set) var failedOriginAttempts = 0
    private(set) var failedAlternatives: Set<String> = []
    private(set) var finalOriginAttempt = false
    private(set) var exhausted = false
    private(set) var expectedTarget: String
    private var settledAttemptIds: Set<String> = []

    init(origin: String) {
      self.origin = origin
      expectedTarget = origin
    }

    mutating func next(failed target: String, attemptId: String, confirmedTimeout: Bool,
                       alternatives: [String]) -> String? {
      guard !exhausted, !origin.isBlank, target == expectedTarget,
            !attemptId.isBlank, attemptId.count <= 200, settledAttemptIds.count < 12,
            settledAttemptIds.insert(attemptId).inserted else { return nil }
      if target == origin {
        guard confirmedTimeout, !finalOriginAttempt else { exhausted = true; return nil }
        failedOriginAttempts += 1
        if failedOriginAttempts == 1 { return origin }
      } else {
        guard failedOriginAttempts >= 2, !finalOriginAttempt,
              failedAlternatives.insert(target).inserted else { exhausted = true; return nil }
      }
      if failedAlternatives.count < 8, let alternative = alternatives.first(where: {
        !$0.isBlank && $0 != origin && !failedAlternatives.contains($0)
      }) {
        expectedTarget = alternative
        return alternative
      }
      finalOriginAttempt = true
      expectedTarget = origin
      return origin
    }
  }
}

enum AgentRemoteTaskStatusPolicy {
  static let remoteTimeoutStage = "REMOTE_TASK"

  private static let terminalStatuses: Set<String> = [
    "completed",
    "failed",
    "cancelled",
    "timed_out",
    "not_found"
  ]

  private static let terminalStatusesWithoutResponse: Set<String> = [
    "failed",
    "cancelled",
    "timed_out",
    "not_found"
  ]

  private static let healthyStatuses: Set<String> = [
    "accepted",
    "queued",
    "starting",
    "recovering",
    "running",
    "waiting_input",
    "waiting_approval",
    "completed"
  ]

  static func normalize(_ status: String) -> String {
    status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func isTerminal(_ status: String) -> Bool {
    terminalStatuses.contains(normalize(status))
  }

  static func finalResponseSuccess(_ status: String) -> Bool? {
    switch normalize(status) {
    case "completed": return true
    case "failed", "cancelled", "timed_out", "not_found": return false
    default: return nil
    }
  }

  static func settlesWithoutResponse(_ status: String) -> Bool {
    terminalStatusesWithoutResponse.contains(normalize(status))
  }

  static func keepsResourceHealthy(_ status: String) -> Bool {
    healthyStatuses.contains(normalize(status))
  }

  static func phase(_ status: String) -> AgentPhase {
    switch normalize(status) {
    case "completed":
      return .completed
    case "cancelled":
      return .cancelled
    case "failed", "timed_out", "not_found":
      return .failed
    case "waiting_input", "waiting_approval":
      return .paused
    default:
      return .executing
    }
  }

  static func workspaceStatus(_ status: String) -> AgentWorkspaceStatus? {
    switch normalize(status) {
    case "completed":
      return .completed
    case "cancelled":
      return .cancelled
    case "failed", "timed_out", "not_found":
      return .failed
    default:
      return nil
    }
  }

  static func completionTimestamp(
    status: String,
    declaredCompletedAtMillis: Int64,
    updatedAtMillis: Int64,
    observedAtMillis: Int64
  ) -> Int64 {
    guard isTerminal(status) else {
      return 0
    }
    return [declaredCompletedAtMillis, updatedAtMillis, observedAtMillis]
      .first { $0 > 0 } ?? 1
  }

  static func timeoutStage(_ status: String) -> String {
    normalize(status) == "timed_out" ? remoteTimeoutStage : ""
  }

  static func remainingDeadlineMillis(
    deadlineMillis: Int64,
    startedAtMillis: Int64,
    nowMillis: Int64
  ) -> Int64 {
    let safeDeadline = max(0, deadlineMillis)
    guard startedAtMillis > 0, nowMillis > startedAtMillis else {
      return safeDeadline
    }
    return max(0, safeDeadline - (nowMillis - startedAtMillis))
  }
}
