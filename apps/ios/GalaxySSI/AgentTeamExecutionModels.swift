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

  var observedFailure: Bool {
    !succeeded || Self.reportsFailure(output)
  }

  static func reportsFailure(_ output: String) -> Bool {
    guard let fields = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(output.utf8)) else { return false }
    if fields["success"] == .bool(false) || fields["ok"] == .bool(false) || fields["isError"] == .bool(true) {
      return true
    }
    if ["failed", "error", "cancelled", "timed_out", "unavailable", "rejected",
        "verification_failed"].contains(fields.string("status")) { return true }
    switch fields["error"] {
    case .some(.bool(let value)): return value
    case .some(.int(let value)): return value != 0
    case .some(.double(let value)): return value != 0
    case .some(.string(let value)): return !value.isBlank
    case .some(.object(let value)): return !value.isEmpty
    case .some(.array(let value)): return !value.isEmpty
    default: return false
    }
  }
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
    case failureExperience = "failure_experience"
    case learningAgenda = "learning_agenda"
    case candidate
    case transferStudy = "transfer_study"
    case candidateEvent = "candidate_event"
    case capabilityGap = "capability_gap"
    case innovation
  }

  var validFailureExperience: Bool {
    guard kind == .failureExperience, objectId?.isBlank != false, baseRevision == 0,
          let value = body["failure_experience"]?.objectValue,
          ["observed_issue", "interpretation", "uncertainty", "applies_when", "avoid_repetition", "reconsider_when"]
            .allSatisfy({ value[$0]?.stringValue?.isBlank == false }),
          let options = value["recovery_options"]?.arrayValue, (1...32).contains(options.count)
    else { return false }
    return options.allSatisfy { $0.stringValue?.isBlank == false }
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

enum AgentCollaborationLearningAgendaIntake {
  static func matchesSelection(_ option: AgentMcpJSONObject, work: AgentCollaborationLiveGraph.Work) -> Bool {
    option.string("decision") == "select" && option.string("member") == work.member &&
      option["assignment"]?.stringValue.map { Data($0.utf8) == Data(work.assignment.utf8) } == true &&
      option.string("stage") == work.stage
  }

  static func validates(_ draft: AgentCollaborationResearchDraft, members: Set<String>,
                        gapOptions: (AgentCollaborationResearchReference) throws -> Set<String>?) rethrows -> Bool {
    guard draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let agenda = draft.body["learning_agenda"]?.objectValue,
          hasText(agenda, ["goal_alignment", "resource_reasoning", "selection_reason", "reconsider_when"]),
          let options = agenda["options"]?.arrayValue, (1...32).contains(options.count) else { return false }
    var ranks = Set<Int64>()
    var ids = Set<String>()
    var choices: [String: Set<String>] = [:]
    for entry in options {
      guard let option = entry.objectValue,
            hasText(option, ["id", "gap_option", "current_goal_value", "future_transfer_value", "information_gain",
                             "uncertainty", "tradeoff", "verification", "reconsider_when", "member", "assignment"]),
            ids.insert(option.string("id")).inserted,
            case .int(let rank)? = option["priority"], rank > 0, ranks.insert(rank).inserted,
            members.contains(option.string("member")), option.string("assignment").utf8.count <= 8_000,
            ["select", "defer"].contains(option.string("decision")),
            ["EXECUTE", "EXPLORE", "CHALLENGE", "VERIFY", "REVISE"].contains(option.string("stage")),
            let gap = option["gap"]?.objectValue, Set(gap.keys) == Set(["object_id", "revision", "sha256"]),
            case .int(let revision)? = gap["revision"], revision > 0,
            let estimates = option["resource_estimates"]?.arrayValue, (1...5).contains(estimates.count)
      else { return false }
      let reference = AgentCollaborationResearchReference(objectId: gap.string("object_id"), revision: revision,
        sha256: gap.string("sha256"))
      let choice = option.string("gap_option")
      guard draft.parents.contains(reference), try gapOptions(reference)?.contains(choice) == true,
            choices[reference.sha256, default: []].insert(choice).inserted else { return false }
      var units = Set<String>()
      for estimate in estimates {
        guard let value = estimate.objectValue, hasText(value, ["basis"]),
              ["elapsed_ms", "tokens", "cost_micros", "network_bytes", "tool_calls"].contains(value.string("unit")),
              units.insert(value.string("unit")).inserted else { return false }
        switch (value.string("status"), value["value"]) {
        case ("unknown", nil), ("unknown", .some(.null)): break
        case ("estimated", .some(.int(let number))) where number >= 0: break
        case ("estimated", .some(.double(let number))) where number.isFinite && number >= 0: break
        default: return false
        }
      }
    }
    return true
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }
}

enum AgentCollaborationEvolutionIntake {
  static func validates(_ draft: AgentCollaborationResearchDraft) -> Bool {
    guard let value = draft.body[draft.kind.rawValue]?.objectValue,
          draft.body["content"] == nil || !draft.body.string("content").isBlank else { return false }
    switch draft.kind {
    case .capabilityGap:
      guard ["knowledge", "tool", "method", "verification", "coordination", "environment",
             "authorization", "unknown"].contains(value.string("category")),
            hasText(value, ["symptom", "needed_capability", "chosen_option", "rationale"]),
            let options = records(value, field: "learning_options",
              required: ["action", "expected_gain", "cost", "goal_relevance", "verification"])
      else { return false }
      return options.contains { $0.string("id") == value.string("chosen_option") }
    case .innovation:
      let origin = value.string("origin")
      guard ["gap", "contradiction", "limitation", "transfer", "combination"].contains(origin),
            value.string("novelty_scope") == "not_checked",
            hasText(value, ["hypothesis", "mechanism", "difference", "prior_art", "falsifier", "domain",
                            "applies_when", "risks"]),
            let alternatives = value["alternatives"]?.arrayValue, (1...32).contains(alternatives.count),
            alternatives.allSatisfy({ $0.stringValue?.isBlank == false }),
            records(value, field: "predictions", required: ["statement", "test"]) != nil else { return false }
      let parents = Set(draft.parents.map(\.objectId)).count
      return origin == "combination" ? parents >= 2 : (origin != "transfer" || parents >= 1)
    default:
      return false
    }
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { !object.string($0).isBlank }
  }

  private static func records(_ object: AgentMcpJSONObject, field: String, required: [String]) -> [AgentMcpJSONObject]? {
    guard let items = object[field]?.arrayValue, (1...32).contains(items.count) else { return nil }
    let values = items.compactMap(\.objectValue)
    guard values.count == items.count, values.allSatisfy({ hasText($0, ["id"] + required) }),
          Set(values.map { $0.string("id") }).count == values.count else { return nil }
    return values
  }
}

enum AgentCollaborationTransferIntake {
  static func validates(_ draft: AgentCollaborationResearchDraft,
                        exactCurrentKind: (AgentCollaborationResearchReference) throws -> String?) rethrows -> Bool {
    guard draft.kind == .transferStudy, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let study = draft.body["transfer_study"]?.objectValue,
          hasText(study, ["source_domain", "target_domain", "target_task", "abstract_strategy",
                          "proposed_method", "rationale", "risks", "falsifier", "limitations"]),
          ["cross_task", "cross_domain"].contains(study.string("mode")),
          study.string("mode") != "cross_domain" || study.string("source_domain") != study.string("target_domain"),
          let source = reference(study["source"]), draft.parents.contains(source),
          try exactCurrentKind(source) == "failure_experience",
          let alternatives = study["alternatives"]?.arrayValue, (1...32).contains(alternatives.count),
          alternatives.allSatisfy({ $0.stringValue?.isBlank == false }),
          let mappings = study["mappings"]?.arrayValue, (1...32).contains(mappings.count),
          mappings.allSatisfy({ item in
            item.objectValue.map { hasText($0, ["source_element", "target_element", "invariant", "adaptation", "breaks_when"]) } == true
          }),
          let calibration = study["calibration_data"]?.arrayValue, calibration.count <= 32 else { return false }
    var seen = Set<String>()
    for item in calibration {
      guard let artifact = reference(item), draft.parents.contains(artifact), seen.insert(artifact.objectId).inserted,
            try exactCurrentKind(artifact) == "artifact" else { return false }
    }
    return true
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }

  private static func reference(_ raw: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let object = raw?.objectValue, Set(object.keys) == Set(["object_id", "revision", "sha256"]),
          case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return AgentCollaborationResearchReference(objectId: object.string("object_id"),
      revision: revision, sha256: object.string("sha256"))
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
