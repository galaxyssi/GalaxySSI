import Foundation

struct AgentCollaborationNativeToolObservation: Codable {
  var runId: String
  var conversationId: String
  var turnId: String
  var memberId: String
  var sourceId: String
  var input: AgentMcpJSONObject
  var result: AgentNativeToolResult
}

struct AgentCollaborationToolEvidenceScope: Codable, Equatable {
  var runId: String
  var conversationId: String
  var turnId: String
  var memberId: String
  var sourceId: String
}

struct AgentCollaborationCloudToolEvidence: Codable, Equatable {
  var scope: AgentCollaborationToolEvidenceScope
  var round: Int
  var call: AssembledToolCall
  var output: String
  var succeeded: Bool
  var startedAtMillis: Int64
  var finishedAtMillis: Int64
}

struct AgentCollaborationReadCoverage: Codable, Equatable {
  struct Span: Codable, Equatable {
    var start: Int64
    var end: Int64
  }

  var spans: [Span] = []

  mutating func include(start: Int64, end: Int64) {
    guard start < end else { return }
    var merged: [Span] = []
    for span in (spans + [.init(start: start, end: end)]).sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, last.end >= span.start {
        merged[merged.count - 1].end = max(last.end, span.end)
      } else {
        merged.append(span)
      }
    }
    spans = merged
  }

  var contiguousEnd: Int64 {
    spans.first.flatMap { $0.start == 0 ? $0.end : nil } ?? 0
  }
}

struct AgentCollaborationResearchReference: Codable, Equatable {
  var objectId: String
  var revision: Int64
  var sha256: String

  enum CodingKeys: String, CodingKey {
    case objectId = "object_id"
    case revision, sha256
  }
}

struct AgentCollaborationResearchDraft: Codable {
  enum Kind: String, Codable {
    case hypothesis, evidence, counterexample, proposal, experiment, artifact, decision, question
    case acceptanceReview = "acceptance_review"
    case candidate
    case environmentModel = "task_environment_model"
    case actionForecast = "action_forecast"
    case candidateEvent = "candidate_event"
  }
  var id: String
  var objectId: String?
  var baseRevision: Int64
  var kind: Kind
  var title: String
  var body: AgentMcpJSONObject
  var parents: [AgentCollaborationResearchReference]
  var resolves: [AgentCollaborationResearchReference]? = nil
  var observations: [AgentMcpJSONObject]? = nil

  enum CodingKeys: String, CodingKey {
    case id, kind, title, body, parents, resolves, observations
    case objectId = "object_id"
    case baseRevision = "base_revision"
  }
}

enum AgentCollaborationForecastIntake {
  static func actionIds(_ model: AgentMcpJSONObject) -> Set<String>? {
    guard let actions = model["actions"]?.arrayValue, (2...32).contains(actions.count) else { return nil }
    var ids = Set<String>()
    var canDefer = false
    for item in actions {
      guard let action = item.objectValue, hasText(action, ["id", "description", "preconditions",
        "expected_transition", "side_effects", "reversibility", "authorization"]),
        ids.insert(action.string("id")).inserted,
        ["act", "probe", "defer"].contains(action.string("mode")) else { return nil }
      canDefer = canDefer || action.string("mode") == "defer"
    }
    return canDefer ? ids : nil
  }

  static func utilities(_ forecast: AgentMcpJSONObject, actions: Set<String>) -> [String: Double]? {
    guard hasText(forecast, ["work_id", "executor", "horizon", "decision_rationale", "risk_tradeoff",
                            "information_value", "revalidate_before_action", "utility_unit"]),
          actions.contains(forecast.string("selected_action")),
          let events = forecast["events"]?.arrayValue, (1...32).contains(events.count),
          let choices = forecast["choices"]?.arrayValue, choices.count == actions.count else { return nil }
    var utilities: [String: (Double, Double)] = [:]
    for item in events {
      guard let event = item.objectValue, hasText(event, ["id", "meaning", "unit"]),
            event.string("pointer").hasPrefix("/"),
            let expected = event["expected"], expected.objectValue == nil, expected.arrayValue == nil,
            let yes = number(event["utility_if_true"]), let no = number(event["utility_if_false"]),
            utilities.updateValue((yes, no), forKey: event.string("id")) == nil else { return nil }
    }
    var result: [String: Double] = [:]
    for item in choices {
      guard let choice = item.objectValue, hasText(choice, ["reasoning", "uncertainty", "resources", "risk"]),
            choice["expectations"] == nil, actions.contains(choice.string("action_id")),
            let probabilities = choice["probabilities"]?.objectValue,
            Set(probabilities.keys) == Set(utilities.keys) else { return nil }
      var sum = 0.0
      for id in utilities.keys.sorted() {
        guard let outcomes = utilities[id], let p = number(probabilities[id]), (0...1).contains(p) else { return nil }
        sum += p * outcomes.0 + (1 - p) * outcomes.1
      }
      guard sum.isFinite, result.updateValue(sum, forKey: choice.string("action_id")) == nil else { return nil }
    }
    return result
  }

  static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }

  private static func number(_ value: AgentMcpJSONValue?) -> Double? {
    switch value {
    case .some(.int(let number)): return Double(number)
    case .some(.double(let number)) where number.isFinite: return number
    default: return nil
    }
  }
}

struct AgentCollaborationResearchEnvelope: Decodable {
  static let wireFormat = "galaxyssi.research-artifact.v1"
  var format: String
  var workspace: [AgentCollaborationResearchDraft]?

  static func publication(in raw: String) throws -> [AgentCollaborationResearchDraft]? {
    guard raw.utf8.count <= 256_000, raw.contains(wireFormat) else { return nil }
    let envelope = try JSONDecoder().decode(Self.self, from: Data(raw.utf8))
    guard envelope.format == wireFormat, let workspace = envelope.workspace, !workspace.isEmpty else { return nil }
    return workspace
  }
}

struct AgentCollaborationResearchRevision: Codable {
  var reference: AgentCollaborationResearchReference
  var previousHash: String?
  var runId: String
  var turnId: String
  var authorId: String
  var sourceId: String
  var draft: AgentCollaborationResearchDraft
  var frozenCloudReads: [AgentCollaborationFrozenCloudRead]? = nil
  var declaredExpectedUtilities: [String: Double]? = nil
}

struct AgentCollaborationFrozenCloudRead: Codable {
  var evidenceId: String
  var sha256: String
  var totalCharacters: Int64
}

struct AgentCollaborationResearchPublication: Codable {
  var requestHash: String
  var references: [AgentCollaborationResearchReference]
}

struct AgentCollaborationPublicationRejection: Codable, Equatable {
  enum Reason: String, Codable {
    case malformedEnvelope = "malformed_envelope"
    case invalidDraft = "invalid_draft"
    case staleBindingOrRevision = "stale_binding_or_revision"
  }

  var scope: AgentCollaborationToolEvidenceScope
  var replyHash: String
  var reason: Reason
}

enum AgentSubagentStatus: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case queued = "QUEUED"
  case running = "RUNNING"
  case succeeded = "SUCCEEDED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case skipped = "SKIPPED"
  case interrupted = "INTERRUPTED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.succeeded, .failed, .cancelled, .skipped, .interrupted].contains(self)
  }
}

enum AgentTeamExecutionState: String, Codable, CaseIterable, Identifiable {
  case queued = "QUEUED"
  case created = "CREATED"
  case running = "RUNNING"
  case waitingResponse = "WAITING_RESPONSE"
  case succeeded = "SUCCEEDED"
  case completedWithFailures = "COMPLETED_WITH_FAILURES"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case interrupted = "INTERRUPTED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.succeeded, .completedWithFailures, .failed, .cancelled, .interrupted].contains(self)
  }

  var deliverable: Bool {
    [.succeeded, .completedWithFailures, .failed, .cancelled].contains(self)
  }
}

struct AgentTeamProgressProjection: Codable, Equatable {
  var state: AgentTeamExecutionState
  var primaryAgentId: String
  var finalOutput: String
  var members: [AgentTeamMemberSnapshot]
  var memberDetailsVisible: Bool
}

enum AgentTeamProgressPolicy {
  static func currentCollaborationMembers(_ snapshot: AgentTeamExecutionSnapshot) -> [AgentTeamMemberSnapshot] {
    var keys: [String] = []
    var current: [String: AgentTeamMemberSnapshot] = [:]
    for member in snapshot.members where member.deliveryMode != .ignore {
      let parts = member.memberId.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      let key: String
      if let first = parts.first, let rosterId = UUID(uuidString: String(first)),
         parts.count == 1 || ["revise", "recheck"].contains(String(parts[1])) {
        key = rosterId.uuidString.lowercased()
      } else {
        key = member.memberId
      }
      if let previous = current[key] {
        let candidateRank = collaborationStatusRank(member)
        let previousRank = collaborationStatusRank(previous)
        guard candidateRank > previousRank ||
          (candidateRank == previousRank && member.updatedAtMillis >= previous.updatedAtMillis) else { continue }
      } else {
        keys.append(key)
      }
      current[key] = member
    }
    return keys.compactMap { current[$0] }
  }

  private static func collaborationStatusRank(_ member: AgentTeamMemberSnapshot) -> Int {
    if member.status.isTerminal { return 0 }
    if member.status == .running || member.dispatchCheckpoint == .dispatching || member.dispatchCheckpoint == .accepted {
      return 2
    }
    return 1
  }

  static func project(_ snapshot: AgentTeamExecutionSnapshot, expanded: Bool) -> AgentTeamProgressProjection {
    let showMembers = expanded || snapshot.visibilityMode == .visible
    return AgentTeamProgressProjection(
      state: snapshot.state,
      primaryAgentId: snapshot.primaryAgentId,
      finalOutput: snapshot.finalOutput,
      members: showMembers ? snapshot.members : [],
      memberDetailsVisible: showMembers
    )
  }
}

enum AgentTeamMemberDispatchCheckpoint: String, Codable {
  case notStarted = "not_started"
  case dispatching
  case accepted
}

struct AgentTeamMemberSnapshot: Codable, Equatable {
  static let maxErrorCharacters = 1_000

  var agentId: String
  var role: String
  var deliveryMode: AgentDeliveryMode
  var status: AgentSubagentStatus
  var output: String
  var errorMessage: String
  var updatedAtMillis: Int64
  var instanceId: String
  var sourceMessageId: String
  var richOutputJson: String
  var replyContent: String?
  var dispatchCheckpoint: AgentTeamMemberDispatchCheckpoint?
  var displayName: String?
  var researchStage: String?
  var executionStartedAtMillis: Int64?

  var memberId: String { instanceId.ifBlank(agentId) }

  init(
    agentId: String,
    role: String = "",
    deliveryMode: AgentDeliveryMode = .observe,
    status: AgentSubagentStatus = .pending,
    output: String = "",
    errorMessage: String = "",
    updatedAtMillis: Int64 = 0,
    instanceId: String = "",
    sourceMessageId: String = "",
    richOutputJson: String = "",
    replyContent: String? = nil,
    dispatchCheckpoint: AgentTeamMemberDispatchCheckpoint? = nil,
    displayName: String? = nil,
    researchStage: String? = nil,
    executionStartedAtMillis: Int64? = nil
  ) {
    self.agentId = agentId
    self.role = role
    self.deliveryMode = deliveryMode
    self.status = status
    self.output = String(output.prefix(AgentConnectorResponse.maxContentCharacters))
    self.errorMessage = String(errorMessage.prefix(Self.maxErrorCharacters))
    self.updatedAtMillis = max(updatedAtMillis, 0)
    self.instanceId = instanceId.ifBlank(agentId)
    self.sourceMessageId = sourceMessageId
    self.richOutputJson = richOutputJson
    self.replyContent = replyContent
    self.dispatchCheckpoint = dispatchCheckpoint
    self.displayName = displayName.map { String($0.prefix(256)) }
    self.researchStage = researchStage
    self.executionStartedAtMillis = executionStartedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case role
    case deliveryMode = "delivery_mode"
    case status
    case output
    case errorMessage = "error_message"
    case updatedAtMillis = "updated_at_millis"
    case instanceId = "instance_id"
    case sourceMessageId = "source_message_id"
    case richOutputJson = "rich_output_json"
    case replyContent = "reply_content"
    case dispatchCheckpoint = "dispatch_checkpoint"
    case displayName = "display_name"
    case researchStage = "research_stage"
    case executionStartedAtMillis = "execution_started_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? ""
    self.init(
      agentId: agentId,
      role: try container.decodeIfPresent(String.self, forKey: .role) ?? "",
      deliveryMode: try container.decodeIfPresent(AgentDeliveryMode.self, forKey: .deliveryMode) ?? .observe,
      status: try container.decodeIfPresent(AgentSubagentStatus.self, forKey: .status) ?? .pending,
      output: try container.decodeIfPresent(String.self, forKey: .output) ?? "",
      errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? "",
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
      instanceId: try container.decodeIfPresent(String.self, forKey: .instanceId) ?? agentId,
      sourceMessageId: try container.decodeIfPresent(String.self, forKey: .sourceMessageId) ?? "",
      richOutputJson: try container.decodeIfPresent(String.self, forKey: .richOutputJson) ?? "",
      replyContent: try container.decodeIfPresent(String.self, forKey: .replyContent),
      dispatchCheckpoint: try container.decodeIfPresent(AgentTeamMemberDispatchCheckpoint.self, forKey: .dispatchCheckpoint),
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
      researchStage: try container.decodeIfPresent(String.self, forKey: .researchStage),
      executionStartedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .executionStartedAtMillis)
    )
  }

  func elapsedExecutionMillis(now: Int64, team: AgentTeamExecutionSnapshot) -> Int64? {
    guard let start = executionStartedAtMillis, start > 0 else { return nil }
    let end: Int64? = status.isTerminal ? updatedAtMillis :
      (team.state == .interrupted ? team.interruptedAtMillis : (team.state.isTerminal ? team.executionEndedAtMillis : now))
    guard let end, end >= start else { return nil }
    return end - start
  }
}

struct AgentTeamExecutionSnapshot: Codable, Equatable {
  var supervisorRunId: String
  var teamId: String
  var conversationId: String
  var taskId: String
  var primaryAgentId: String
  var goal: String
  var visibilityMode: AgentTeamVisibilityMode
  var state: AgentTeamExecutionState
  var members: [AgentTeamMemberSnapshot]
  var finalOutput: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
  var interruptedAtMillis: Int64
  var primaryInstanceId: String
  var executionStartedAtMillis: Int64?
  var executionEndedAtMillis: Int64?

  var primaryMemberId: String { primaryInstanceId.ifBlank(primaryAgentId) }

  init(
    supervisorRunId: String,
    teamId: String,
    conversationId: String = "",
    taskId: String = "",
    primaryAgentId: String,
    goal: String = "",
    visibilityMode: AgentTeamVisibilityMode = .background,
    state: AgentTeamExecutionState,
    members: [AgentTeamMemberSnapshot] = [],
    finalOutput: String = "",
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0,
    interruptedAtMillis: Int64 = 0,
    primaryInstanceId: String = "",
    executionStartedAtMillis: Int64? = nil,
    executionEndedAtMillis: Int64? = nil
  ) {
    self.supervisorRunId = supervisorRunId
    self.teamId = teamId
    self.conversationId = conversationId
    self.taskId = taskId
    self.primaryAgentId = primaryAgentId
    self.goal = goal
    self.visibilityMode = visibilityMode
    self.state = state
    self.members = members
    self.finalOutput = String(finalOutput.prefix(AgentConnectorResponse.maxContentCharacters))
    self.createdAtMillis = max(createdAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis, 0)
    self.interruptedAtMillis = max(interruptedAtMillis, 0)
    self.primaryInstanceId = primaryInstanceId.ifBlank(primaryAgentId)
    self.executionStartedAtMillis = executionStartedAtMillis
    self.executionEndedAtMillis = executionEndedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case supervisorRunId = "supervisor_run_id"
    case teamId = "team_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case primaryAgentId = "primary_agent_id"
    case goal
    case visibilityMode = "visibility_mode"
    case state
    case members
    case finalOutput = "final_output"
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
    case interruptedAtMillis = "interrupted_at_millis"
    case primaryInstanceId = "primary_instance_id"
    case executionStartedAtMillis = "execution_started_at_millis"
    case executionEndedAtMillis = "execution_ended_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      supervisorRunId: try container.decodeIfPresent(String.self, forKey: .supervisorRunId) ?? "",
      teamId: try container.decodeIfPresent(String.self, forKey: .teamId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      primaryAgentId: try container.decodeIfPresent(String.self, forKey: .primaryAgentId) ?? "",
      goal: try container.decodeIfPresent(String.self, forKey: .goal) ?? "",
      visibilityMode: try container.decodeIfPresent(AgentTeamVisibilityMode.self, forKey: .visibilityMode) ?? .background,
      state: try container.decodeIfPresent(AgentTeamExecutionState.self, forKey: .state) ?? .queued,
      members: try container.decodeIfPresent([AgentTeamMemberSnapshot].self, forKey: .members) ?? [],
      finalOutput: try container.decodeIfPresent(String.self, forKey: .finalOutput) ?? "",
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
      interruptedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .interruptedAtMillis) ?? 0,
      primaryInstanceId: try container.decodeIfPresent(String.self, forKey: .primaryInstanceId) ??
        (try container.decodeIfPresent(String.self, forKey: .primaryAgentId) ?? ""),
      executionStartedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .executionStartedAtMillis),
      executionEndedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .executionEndedAtMillis)
    )
  }

  func elapsedExecutionMillis(now: Int64) -> Int64? {
    guard let start = executionStartedAtMillis, start > 0 else { return nil }
    let end: Int64
    if let recordedEnd = executionEndedAtMillis {
      end = recordedEnd
    } else if state == .interrupted {
      end = interruptedAtMillis
    } else if state == .running || state == .waitingResponse {
      end = now
    } else {
      return nil
    }
    return end >= start ? end - start : nil
  }
}

enum AgentSavedTeamReplyPolicy {
  static func reconcileRecoveryWait(_ task: AgentTaskRecord, runId: String, cancelled: Bool,
                                    verification: String, now: Int64) -> AgentTaskRecord? {
    guard !runId.isBlank,
          (task.phase == .executing && (task.teamRecoveryRunId == nil || task.teamRecoveryRunId == runId)) ||
            (task.phase == .paused && task.teamRecoveryRunId == runId) else { return nil }
    var recovered = task
    recovered.phase = cancelled ? .cancelled : .waitingResponse
    recovered.blocked = false
    recovered.teamRecoveryRunId = cancelled ? nil : runId
    recovered.verification = verification
    recovered.executionLog.append("Agent team recovery: retained original team " + runId)
    recovered.updatedAtMillis = max(task.updatedAtMillis, now)
    return recovered
  }

  static func canContinueAutomatically(_ task: AgentTaskRecord) -> Bool {
    guard task.phase == .paused, task.teamRecoveryRunId == nil,
          let plan = task.activePlan, plan.executionMode == .autoComplete,
          !plan.confirmationRequired else { return false }
    let runnable = AgentToolCoordination.runnableActions(plan)
    return !runnable.isEmpty && runnable.allSatisfy { $0.status == .proposed }
  }

  static func settleParent(_ parent: AgentTaskRecord, saved: AgentTeamExecutionSnapshot,
                           failureText: String, now: Int64) -> AgentTaskRecord? {
    guard saved.state.deliverable, parent.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          (parent.phase == .waitingResponse && (parent.teamRecoveryRunId == nil || parent.teamRecoveryRunId == saved.supervisorRunId)) ||
            (parent.phase == .paused && parent.teamRecoveryRunId == saved.supervisorRunId),
          parent.taskId == saved.taskId, parent.sessionId == saved.conversationId,
          saved.createdAtMillis >= parent.createdAtMillis,
          var plan = parent.activePlan else { return nil }
    let matchingIndices = plan.actions.indices.filter { index in
      plan.actions[index].kind == .callConnector &&
        AgentTeamDispatchSpecCodec.decode(plan.actions[index].parameters[agentTeamSpecParameter] ?? "")?.supervisorRunId == saved.supervisorRunId
    }
    guard matchingIndices.count == 1, let index = matchingIndices.first,
          plan.actions[index].status != .completed,
          let spec = AgentTeamDispatchSpecCodec.decode(plan.actions[index].parameters[agentTeamSpecParameter] ?? ""),
          spec.supervisorRunId == saved.supervisorRunId, spec.definition.teamId == saved.teamId,
          spec.definition.primaryMemberId == saved.primaryMemberId,
          spec.definition.members.count == saved.members.count,
          spec.definition.members.allSatisfy({ expected in
            saved.members.contains { $0.memberId == expected.memberId && $0.agentId == expected.agentId }
          }) else { return nil }
    let success = [.succeeded, .completedWithFailures].contains(saved.state) && !saved.finalOutput.isEmpty
    var result = parent
    result.phase = saved.state == .cancelled ? .cancelled : (success ? .completed : .failed)
    result.result = success ? saved.finalOutput : failureText
    result.blocked = false
    result.teamRecoveryRunId = nil
    result.pendingAction = nil
    result.pendingActions = []
    plan.actions[index].status = success ? .completed : .failed
    plan.actions[index].result = result.result
    if success && !plan.actions.allSatisfy({ $0.status == .completed }) {
      result.nativeActionResults = Array((result.nativeActionResults + [String(saved.finalOutput.prefix(600))]).suffix(8))
      result.phase = .paused
      result.pendingActions = AgentToolCoordination.runnableActions(plan)
      result.pendingAction = result.pendingActions.first
    }
    result.activePlan = plan
    result.planContext = AgentTaskPlanContext(plan: plan)
    result.updatedAtMillis = max(now, parent.updatedAtMillis)
    return result
  }

  static func apply(to saved: AgentTeamExecutionSnapshot, source: String, conversation: String,
                    turn: String, task: String, contact: String, content: String, richOutputJson: String = "",
                    success: Bool, now: Int64) -> AgentTeamExecutionSnapshot? {
    guard (!saved.state.isTerminal || saved.state == .interrupted), !source.isEmpty,
          saved.conversationId == conversation, saved.taskId == turn, task == source,
          let index = saved.members.firstIndex(where: {
            $0.sourceMessageId == source && $0.agentId == contact &&
              (!$0.status.isTerminal || (saved.state == .interrupted && $0.status == .interrupted))
          }),
          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (success && saved.members[index].deliveryMode == .observe) else { return nil }
    var result = saved
    result.members[index].status = success ? .succeeded : .failed
    result.members[index].output = success ? String(content.prefix(AgentConnectorResponse.maxContentCharacters)) : ""
    result.members[index].errorMessage = success ? "" : String(content.prefix(AgentTeamMemberSnapshot.maxErrorCharacters))
    result.members[index].updatedAtMillis = now
    result.members[index].richOutputJson = richOutputJson
    result.members[index].replyContent = content
    result.updatedAtMillis = max(saved.updatedAtMillis, now)
    if result.members[index].memberId == saved.primaryMemberId && !success {
      result.state = .failed
    } else if result.members.allSatisfy({ $0.status.isTerminal && $0.status != .interrupted }),
       let primary = result.members.first(where: { $0.memberId == saved.primaryMemberId }) {
      result.finalOutput = primary.output
      if primary.status == .succeeded && !primary.output.isEmpty {
        result.state = result.members.contains(where: { $0.status != .succeeded }) ? .completedWithFailures : .succeeded
      } else { result.state = .failed }
    }
    return result
  }
}

protocol AgentTeamCompletionSink: AnyObject {
  @discardableResult
  func publish(_ snapshot: AgentTeamExecutionSnapshot) -> Bool
  func remove(supervisorRunId: String)
  func clear()
}

extension AgentTeamCompletionSink {
  func remove(supervisorRunId: String) {}
  func clear() {}
}

final class AgentConnectorTeamCompletionSink: AgentTeamCompletionSink {
  static let maxErrorCharacters = AgentTeamMemberSnapshot.maxErrorCharacters

  private let responseStore: AgentConnectorResponseSink
  private let ledger: AgentTeamCompletionDeliveryLedger
  private let historyStore: AgentTeamExecutionHistoryStore
  private let nowMillis: () -> Int64

  init(
    responseStore: AgentConnectorResponseSink,
    ledger: AgentTeamCompletionDeliveryLedger = AgentTeamCompletionDeliveryLedger(),
    historyStore: AgentTeamExecutionHistoryStore = .shared,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.responseStore = responseStore
    self.ledger = ledger
    self.historyStore = historyStore
    self.nowMillis = nowMillis
  }

  @discardableResult
  func publish(_ snapshot: AgentTeamExecutionSnapshot) -> Bool {
    guard historyStore.upsert(snapshot) else { return false }
    guard snapshot.state.deliverable,
      !ledger.contains(snapshot.supervisorRunId) else {
      return false
    }
    let output = snapshot.finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    let successful = !output.isEmpty && [.succeeded, .completedWithFailures].contains(snapshot.state)
    let content: String
    if successful {
      content = output
    } else if let error = snapshot.members.map(\.errorMessage).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
      content = "Agent team failed: \(String(error.prefix(Self.maxErrorCharacters)))"
    } else {
      content = "Agent team failed."
    }
    responseStore.publish(AgentConnectorResponse(
      sourceMessageId: AgentTeamDispatchIds.sourceMessageId(supervisorRunId: snapshot.supervisorRunId),
      contactId: AgentTeamDispatchIds.responseContactId(teamId: snapshot.teamId),
      content: content,
      conversationId: snapshot.conversationId,
      turnId: snapshot.taskId,
      taskId: snapshot.taskId,
      success: successful,
      receivedAtMillis: max(snapshot.updatedAtMillis, nowMillis())
    ))
    ledger.mark(snapshot.supervisorRunId)
    return true
  }

  func remove(supervisorRunId: String) {
    ledger.remove(supervisorRunId)
    historyStore.remove(supervisorRunId: supervisorRunId)
  }

  func clear() {
    ledger.clear()
    historyStore.clear()
  }
}

final class AgentTeamCompletionDeliveryLedger {
  private let lock = NSRecursiveLock()
  private var delivered: [String]
  private let maximumRecords: Int

  init(delivered: [String] = [], maxRecords: Int = 512) {
    let limit = Swift.max(maxRecords, 1)
    let cleaned = delivered
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.delivered = Self.stableDistinct(cleaned)
      .suffix(limit)
      .map { $0 }
    self.maximumRecords = limit
  }

  private static func stableDistinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  func contains(_ supervisorRunId: String) -> Bool {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    lock.lock()
    defer { lock.unlock() }
    return delivered.contains(clean)
  }

  func mark(_ supervisorRunId: String) {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    delivered = delivered.filter { $0 != clean } + [clean]
    if delivered.count > maximumRecords {
      delivered = Array(delivered.suffix(maximumRecords))
    }
  }

  func remove(_ supervisorRunId: String) {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    delivered.removeAll { $0 == clean }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    delivered.removeAll()
  }

  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return delivered
  }
}
