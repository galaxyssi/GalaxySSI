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
  var progressVersion: AgentConnectorResearchProgress.Version? = nil
  var checkingOtherSources = false

  var id: String {
    "\(conversationId):\(taskId.ifBlank(turnId))"
  }

  var isCancellable: Bool {
    advertisedCancellable && !AgentRemoteTaskStatusPolicy.isTerminal(status)
  }
}

struct AgentCodexReplaySeed: Codable, Equatable {
  let sourceContentSha256: String
  let lockedToOrigin: Bool
  let invocation: [String: String]?
  let transportContext: String
  var budget: AgentCodexSilenceRecoveryPolicy.Budget

  init?(source: ChatMessage, text: String, targetId: String, executionMode: AgentTaskExecutionMode,
        hasAttachments: Bool, voiceSessionId: String, lockedToOrigin: Bool, invocation: [String: String]?,
        transportContext: String) {
    guard source.isMine, !source.isSystem, source.requestKind == .conversation, !source.readOnlyAnalysis,
          !source.conversationId.isBlank, source.content == text, source.richOutputJson.isBlank,
          !text.isBlank, text.utf8.count <= 12_000, !targetId.isBlank,
          executionMode == .planOnly, !hasAttachments, voiceSessionId.isBlank, transportContext.utf8.count <= 32_768,
          (invocation ?? [:]).allSatisfy({ ["model_id", "reasoning_effort"].contains($0.key) && $0.value.count <= 256 })
    else { return nil }
    sourceContentSha256 = AgentModelLoopRecoveryIdentity.sha256(text)
    self.lockedToOrigin = lockedToOrigin
    self.invocation = invocation
    self.transportContext = transportContext
    budget = AgentCodexSilenceRecoveryPolicy.Budget(origin: targetId)
  }

  func matches(_ source: ChatMessage) -> Bool {
    source.isMine && !source.isSystem && source.requestKind == .conversation && !source.readOnlyAnalysis &&
      source.richOutputJson.isBlank && AgentModelLoopRecoveryIdentity.sha256(source.content) == sourceContentSha256
  }
}

enum AgentJournalCodexReplayPolicy {
  static func matchesRequest(_ payload: [String: Any], record: AgentDesktopReplyRecoveryRecord, source: ChatMessage) -> Bool {
    let binding = record.binding
    guard binding.isValid, binding.attemptSourceId != nil, binding.managedSource == nil,
          binding.teamSource == nil, binding.goalWork != true, !record.isManualTargetLocked,
          record.terminalObservedAt == 0, record.acceptedReply == nil, record.pinnedTeamReply == nil,
          !AgentDesktopReplyRecovery.terminalStatuses.contains(record.status),
          let replay = record.codexReplay, !replay.budget.exhausted, replay.matches(source),
          replay.budget.expectedTarget == binding.contactId, source.id == binding.sourceId,
          source.contactId == binding.displayContactId, source.conversationId == binding.identity.conversationId,
          source.turnId.ifBlank(source.id.uuidString) == binding.identity.turnId,
          payload.string("type") == "text", payload["peer_chat"] as? Bool != true,
          payload["agent_team_message"] as? Bool != true,
          payload.string("message_id") == binding.sourceIdentity,
          payload.string("source_message_id").ifBlank(payload.string("client_message_id")) == binding.sourceIdentity,
          payload.string("client_message_id") == binding.sourceIdentity,
          binding.fields.filter({ $0.key != "source_message_id" }).allSatisfy({ payload.string($0.key) == $0.value }),
          payload.string("_galaxyssi_conversation_id") == binding.identity.conversationId,
          payload.string("_galaxyssi_turn_id") == binding.identity.turnId,
          payload.string("_galaxyssi_task_id") == binding.identity.taskId,
          payload.string("desktop_id") == binding.desktopId, payload.string("content") == source.content,
          payload.string("execution_mode") == AgentTaskExecutionMode.planOnly.rawValue,
          payload.string("_galaxyssi_task_execution_mode") == AgentTaskExecutionMode.planOnly.rawValue,
          payload.string("_galaxyssi_conversation_context") == replay.transportContext,
          payload.string("_galaxyssi_long_term_write_allowed") == "false",
          payload.string("_galaxyssi_conversation_has_attachments") == "false",
          payload["attachments"] == nil, payload["voice_session_id"] == nil,
          payload["run_id"] == nil else { return false }
    let expected = replay.budget.origin == binding.contactId ? replay.invocation : nil
    if let expected { return payload["agent_invocation"] as? [String: String] == expected }
    return payload["agent_invocation"] == nil
  }

  static func presentationEvent(_ event: MqttDeliveryCompletions.Event, record: AgentDesktopReplyRecoveryRecord,
                                source: ChatMessage) -> MqttDeliveryCompletions.Event? {
    guard record.binding.isValid, record.binding.attemptSourceId != nil,
          event.sourceMessageID == record.binding.sourceIdentity, event.messageID == record.binding.sourceIdentity,
          event.contactID == record.binding.contactId, event.attachmentTransferID.isEmpty,
          event.traffic == MqttMultipathPolicy.Traffic.message.rawValue,
          source.id == record.binding.sourceId, source.contactId == record.binding.displayContactId,
          source.conversationId == record.binding.identity.conversationId,
          source.turnId.ifBlank(source.id.uuidString) == record.binding.identity.turnId,
          record.codexReplay?.matches(source) == true else { return nil }
    // Map only the local UI write; keep the real attempt ID/hash for receipt trace deduplication.
    return MqttDeliveryCompletions.Event(identity: event.identity, messageID: event.messageID, wireHash: event.wireHash,
      traffic: event.traffic, requestHash: event.requestHash, sourceMessageID: source.id.uuidString,
      contactID: event.contactID, attachmentTransferID: event.attachmentTransferID, receivedAt: event.receivedAt,
      consumedAt: event.consumedAt, topic: event.topic)
  }
}

enum AgentCodexSilenceRecoveryPolicy {
  static let silenceMillis: Int64 = 180_000

  static func rankedAlternatives(targets: [AgentCallableTarget], eligibleIds: Set<String>, goal: String,
                                 hasPairedDesktop: Bool = false,
                                 routingHealth: AgentRoutingHealthSnapshot? = nil,
                                 routingUsage: AgentRoutingUsageSnapshot? = nil) -> [String] {
    let current = targets.filter { eligibleIds.contains($0.id) && $0.kind == .agent }
    guard let selected = AgentConnectorRouteSelector.select(targets: current, decision: nil, goal: goal,
      hasPairedDesktop: hasPairedDesktop, routingHealth: routingHealth, routingUsage: routingUsage) else { return [] }
    var seen = Set<String>()
    return (selected.decision?.orderedTargetIds ?? [selected.target.id])
      .filter { !$0.isBlank && seen.insert($0).inserted }
  }

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
