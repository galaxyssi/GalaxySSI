import Foundation

struct AgentTaskLivenessActiveRun: Codable, Equatable, Identifiable {
  var runId: String
  var workspaceId: String
  var sourceMessageId: Int64
  var agentId: String

  var id: String {
    runId.isEmpty ? "\(workspaceId):\(sourceMessageId)" : runId
  }

  init(
    runId: String,
    workspaceId: String,
    sourceMessageId: Int64 = 0,
    agentId: String = ""
  ) {
    self.runId = Self.clean(runId)
    self.workspaceId = Self.clean(workspaceId)
    self.sourceMessageId = max(sourceMessageId, 0)
    self.agentId = Self.clean(agentId)
  }

  enum CodingKeys: String, CodingKey {
    case runId = "run_id"
    case workspaceId = "workspace_id"
    case sourceMessageId = "source_message_id"
    case agentId = "agent_id"
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct AgentTaskLivenessSignalActionPlan: Codable, Equatable {
  var transcriptOperations: [AgentTaskLivenessTranscriptOperation]
  var consumePendingConnectorResponses: Bool
  var requestRecoverableRunReconciliation: Bool
  var reconciliationReason: String
  var cancelConnectorTimeoutSourceMessageIds: [Int64]
  var removeActiveRunIds: [String]
  var forceTimeoutRunIds: [String]
  var timeoutMessage: String

  init(
    transcriptOperations: [AgentTaskLivenessTranscriptOperation] = [],
    consumePendingConnectorResponses: Bool = false,
    requestRecoverableRunReconciliation: Bool = false,
    reconciliationReason: String = "",
    cancelConnectorTimeoutSourceMessageIds: [Int64] = [],
    removeActiveRunIds: [String] = [],
    forceTimeoutRunIds: [String] = [],
    timeoutMessage: String = ""
  ) {
    self.transcriptOperations = transcriptOperations
    self.consumePendingConnectorResponses = consumePendingConnectorResponses
    self.requestRecoverableRunReconciliation = requestRecoverableRunReconciliation
    self.reconciliationReason = Self.clean(reconciliationReason)
    self.cancelConnectorTimeoutSourceMessageIds = Self.distinct(cancelConnectorTimeoutSourceMessageIds.filter { $0 > 0 })
    self.removeActiveRunIds = Self.distinct(removeActiveRunIds.map { Self.clean($0) }.filter { !$0.isEmpty })
    self.forceTimeoutRunIds = Self.distinct(forceTimeoutRunIds.map { Self.clean($0) }.filter { !$0.isEmpty })
    self.timeoutMessage = Self.clean(timeoutMessage)
  }

  enum CodingKeys: String, CodingKey {
    case transcriptOperations = "transcript_operations"
    case consumePendingConnectorResponses = "consume_pending_connector_responses"
    case requestRecoverableRunReconciliation = "request_recoverable_run_reconciliation"
    case reconciliationReason = "reconciliation_reason"
    case cancelConnectorTimeoutSourceMessageIds = "cancel_connector_timeout_source_message_ids"
    case removeActiveRunIds = "remove_active_run_ids"
    case forceTimeoutRunIds = "force_timeout_run_ids"
    case timeoutMessage = "timeout_message"
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func distinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  private static func distinct(_ values: [Int64]) -> [Int64] {
    var seen = Set<Int64>()
    return values.filter { seen.insert($0).inserted }
  }
}

enum AgentTaskLivenessSignalActionPolicy {
  static let defaultMobileAgentId = "galaxyssi-mobile"
  static let defaultReconciliationReason = "stall"
  static let defaultTimedOutText = "The task timed out."

  static func plan(
    for signal: AgentTaskLivenessSignal,
    existingEntries: [AgentTranscriptEntry],
    activeRuns: [AgentTaskLivenessActiveRun] = [],
    agentId: String = "",
    mobileAgentId: String = defaultMobileAgentId,
    stalledText: String = "The task has not reported progress recently.",
    timedOutText: String = defaultTimedOutText
  ) -> AgentTaskLivenessSignalActionPlan {
    let transcriptOperations = AgentTaskLivenessTranscriptPolicy.operations(
      for: signal,
      existingEntries: existingEntries,
      stalledText: stalledText,
      timedOutText: timedOutText
    )
    let workspace = signal.workspace
    let conversationId = clean(workspace.conversationId)
    let taskId = clean(workspace.taskId)
    if conversationId.isEmpty ||
      taskId.isEmpty ||
      AgentTaskTerminalReplyPolicy.hasTerminalReply(entries: existingEntries, turnId: taskId) {
      return AgentTaskLivenessSignalActionPlan(transcriptOperations: transcriptOperations)
    }

    switch signal.kind {
    case .stalled:
      let cleanAgentId = clean(agentId)
      let cleanMobileAgentId = clean(mobileAgentId)
      let shouldReconcile = workspace.status == .waitingResponse &&
        !cleanAgentId.isEmpty &&
        cleanAgentId != cleanMobileAgentId
      return AgentTaskLivenessSignalActionPlan(
        transcriptOperations: transcriptOperations,
        consumePendingConnectorResponses: true,
        requestRecoverableRunReconciliation: shouldReconcile,
        reconciliationReason: shouldReconcile ? defaultReconciliationReason : ""
      )
    case .recovered:
      return AgentTaskLivenessSignalActionPlan(transcriptOperations: transcriptOperations)
    case .timedOut:
      let matchingRuns = runs(for: workspace.workspaceId, activeRuns: activeRuns)
      let runIds = distinct(matchingRuns.map(\.runId).map { clean($0) }.filter { !$0.isEmpty })
      return AgentTaskLivenessSignalActionPlan(
        transcriptOperations: transcriptOperations,
        cancelConnectorTimeoutSourceMessageIds: distinct(matchingRuns.map(\.sourceMessageId).filter { $0 > 0 }),
        removeActiveRunIds: runIds,
        forceTimeoutRunIds: runIds,
        timeoutMessage: clean(timedOutText).isEmpty ? defaultTimedOutText : timedOutText
      )
    }
  }

  private static func runs(
    for workspaceId: String,
    activeRuns: [AgentTaskLivenessActiveRun]
  ) -> [AgentTaskLivenessActiveRun] {
    let cleanWorkspaceId = clean(workspaceId)
    guard !cleanWorkspaceId.isEmpty else { return [] }
    return activeRuns.filter { clean($0.workspaceId) == cleanWorkspaceId }
  }

  private static func distinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  private static func distinct(_ values: [Int64]) -> [Int64] {
    var seen = Set<Int64>()
    return values.filter { seen.insert($0).inserted }
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
