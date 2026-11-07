import Foundation
import CryptoKit

enum AgentCollaborationDecisionContext {
  static func dependencyLines(_ observations: [(String, String)], maximumBytes: Int = 12_000,
                              recallAvailable: Bool = true)
    -> (lines: [String], omitted: Bool) {
    guard recallAvailable else {
      let lines = observations.map { id, text in
        "[\(id) output_truncated=\(text.count > 8_000)] \(String(text.prefix(8_000)))"
      }
      return (lines, false)
    }
    let references = observations.map { id, _ in
      "[\(id) output_truncated=true archive_record_id=\(AgentDesktopCollaborationArchiveRecall.recordId(memberId: id))]"
    }
    var lines = references
    var budget = max(0, maximumBytes - references.reduce(0) { $0 + $1.utf8.count + 1 })
    for index in observations.indices.reversed() {
      let (id, text) = observations[index]
      let full = "[\(id) output_truncated=false] \(text)"
      let cost = max(0, full.utf8.count - references[index].utf8.count)
      guard text.count <= 8_000, cost <= budget else { continue }
      lines[index] = full
      budget -= cost
    }
    return (lines, lines.indices.contains { lines[$0] == references[$0] })
  }
}

enum AgentCollaborationInlineOriginals {
  static let contextSections = ["context:assignment", "context:resources", "context:peer_requests"]
  static let recallSections = ["goal", "criteria", "source"] + contextSections
  static let maximumContextSectionBytes = 128_000

  static func source(goal: String, criteria: Data) -> Data {
    let units = Array(goal.utf16)
    var segments: [String] = []
    var start = 0
    var substantive = false
    func whitespace(_ unit: UInt16) -> Bool {
      UnicodeScalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
    }
    for index in units.indices {
      let unit = units[index]
      let end = index + 1
      substantive = substantive || !whitespace(unit)
      if end < units.count, (0xD800...0xDBFF).contains(unit),
         (0xDC00...0xDFFF).contains(units[end]) { continue }
      let final = end == units.count
      let punctuation = [0x002E, 0x0021, 0x003F].contains(Int(unit)) && (final || whitespace(units[end]))
      let separator = [0x000A, 0x003B, 0xFF1B, 0x3002, 0xFF01, 0xFF1F].contains(Int(unit))
      if substantive && (final || punctuation || separator || end - start >= 1_024) {
        segments.append(String(decoding: units[start..<end], as: UTF16.self))
        start = end
        substantive = false
      }
    }
    if start < units.count, !segments.isEmpty {
      segments[segments.count - 1] += String(decoding: units[start...], as: UTF16.self)
    }
    func digest(_ bytes: Data) -> String {
      SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    return Data(AgentMcpJSONCodec.stringify([
      "format": .string("galaxyssi.ios-goal-coverage-source.v1"),
      "goal_sha256": .string(digest(Data(goal.utf8))),
      "criteria_sha256": .string(digest(criteria)),
      "segments": .array(segments.enumerated().map { index, value in
        .object(["id": .string("source-\(index + 1)"), "text": .string(value)])
      })
    ]).utf8)
  }

  static func prompt(originalGoalPrefix: String, maximumBytes: Int = 12_000,
                     read: (String) -> AgentMcpJSONObject?) -> String {
    var sections: [String: AgentMcpJSONValue] = [:]
    var originals: AgentMcpJSONObject = [:]
    for section in ["goal", "criteria", "source"] {
      sections[section] = .string("not_included")
      guard let page = read(section), page["next_offset"] == .null,
            page["offset"] == .int(0), page.string("section") == section,
            let bytes = Data(base64Encoded: page.string("data_b64")), !bytes.isEmpty,
            page["total_bytes"] == .int(Int64(bytes.count)),
            let original = String(data: bytes, encoding: .utf8) else { continue }
      if section == "goal", Data(originalGoalPrefix.utf8) == bytes {
        sections[section] = .string("complete_in_prompt_prefix")
        continue
      }
      var proposed = originals
      proposed[section] = .string(original)
      guard AgentMcpJSONCodec.stringify(proposed).utf8.count <= maximumBytes else { continue }
      originals = proposed
      sections[section] = .string("complete_in_originals")
    }
    return """
    Original context availability (host-reported, not evidence validation):
    \(AgentMcpJSONCodec.stringify(["availability": .object(sections), "originals": .object(originals)]))
    Use complete originals directly. Retrieve missing relevant sections with scoped goal recall when available.
    """
  }
}

enum AgentCollaborationRuleTopics {
  private struct Topic {
    let id: String
    let purpose: String
    let prerequisites: [String]
    let contract: String
  }

  private static let topics = [
    Topic(id: "foundation", purpose: "Publish and read scoped research originals", prerequisites: [], contract: """
    Publish galaxyssi.research-artifact.v1 with a workspace array. Each item has id, kind, title, body, base_revision and parents.
    Use base_revision 0 for new records and exact object_id, revision and sha256 for references. Cite original cloud observations
    with evidence_id and sha256 when the record supports citations. Read each page before citing it. Publication is not verification.
    For acceptance_review, cite exactly one current delivery in parents. In body.acceptance_review include criterion_id,
    requirement, target (the exact parent), verdict (supported, refuted, or not_tested), rationale and unresolved.
    The reviewer must be independent of the delivery author; cite completely read original observations in observations.
    For iOS native tool observations, use native_evidence with the exact evidence_id and sha256. After reading every page,
    cite {origin:"ios_native_tool",evidence_id,sha256}. Do not cite recall itself, failed actions or replay receipts as new evidence.
    For original-goal coverage, read the host goal source and copy its hashes and source IDs. Publish an artifact with
    body.semantic_goal_mapping containing format galaxyssi.semantic-goal-mapping.v1, goal_sha256, criteria_sha256 and
    segments (id, coverage_kind, criterion_ids, rationale). Map all outcome, constraint and context segments exactly once.
    Outcomes must reference pinned criteria. A separate reviewer publishes acceptance_review with body.semantic_coverage_review
    (target, verdict, rationale, unresolved, segments). Cite only that mapping in parents. Repeat each segment's exact id,
    kind and criterion IDs, adding verdict, rationale and unresolved. Do not hide objections or relabel requested outcomes.
    In an achieved assessment, supply goal_coverage as mapping/review references, non-overlapping parts of reference pairs,
    or a manifest reference. A manifest is an artifact with body.semantic_goal_manifest, format galaxyssi.semantic-goal-manifest.v1,
    both host hashes, and either parts or manifests. Include each referenced record in parents. Coverage is not final delivery.
    capability_gap records category, symptom, needed_capability, learning_options, chosen_option and rationale.
    innovation records origin, hypothesis, mechanism, difference, prior_art, falsifier, domain, applies_when, risks, alternatives
    and predictions (id, statement, test). Use novelty_scope not_checked. Transfer and combination require exact parent records.
    An action_forecast may declare hypothesis_test with hypotheses (id, claim, prior), event_ids, and likelihoods
    keyed by action, hypothesis, and event. Use a single report field and include every action, including defer.
    For a follow-up, use an exact prior_outcome parent and explain conditional_history. Keep the same
    question, hypothesis claims, and environment scope. Omit explicit priors; the host uses the saved posterior.
    A prediction_outcome binds an exact forecast parent and one fully recalled original cloud tool observation
    from its executor. The host computes any posterior; declared probabilities are assumptions, not calibration.
    A numeric_model_trial records local replay, not independent reference truth. Supply purpose, reference_basis, limitations,
    validator {id:"numeric_model_cases.v1",variables,cases:[{id,input,expected,absolute_tolerance}]}, and computation
    {validator_id:"numeric_model_cases.v1",model}. Expressions use {constant}, {variable}, or {op,args}.
    Operations: neg, abs, exp, expm1, log, log1p, sqrt, sin, cos, add, sub, mul, div, pow, min, max.
    Valid failed cases are saved. An exact previous_trial parent can compare the same preserved cases.
    experiment_plan binds exact innovation and baseline parents, prediction_id, method, environment, budget_unit, budget_limit,
    report_pointer, source and cases. experiment_result binds the plan and completely read original measurement observations.
    capability_lesson binds exact result and rollback parents; retain requires passing target and regression cases,
    an independent reviewer and full original evidence reads. Reject or revise can preserve historical findings.
    """),
    Topic(id: "learning", purpose: "Compare and record learning choices", prerequisites: ["foundation"], contract: """
    learning_agenda is immutable. Include goal_alignment, resource_reasoning, selection_reason, reconsider_when and options.
    Each option names id, exact gap parent, gap_option, unique positive priority, select or defer decision, member, stage and
    assignment. Include current_goal_value, future_transfer_value, information_gain, uncertainty, tradeoff, verification,
    reconsider_when and resource_estimates. Estimates name unit, status and basis; unknown estimates have no numeric value.
    A saved agenda does not execute work or grant resources.
    """),
    Topic(id: "procedures", purpose: "Preserve observed failure experience", prerequisites: ["foundation"], contract: """
    failure_experience is immutable and requires completely read original cloud observations, including at least one observed
    failure. Include observed_issue, interpretation, uncertainty, applies_when, avoid_repetition, reconsider_when and
    recovery_options. A recorded failure is not proof of a cause and is not a permanent prohibition.
    """),
    Topic(id: "transfer", purpose: "Register an unverified transfer study", prerequisites: ["procedures"], contract: """
    transfer_study binds a current failure_experience source and optional exact calibration_data artifact parents.
    Include source_domain, target_domain, mode (cross_task or cross_domain), target_task, abstract_strategy, proposed_method,
    rationale, risks, falsifier, limitations, alternatives and mappings (source_element, target_element, invariant, adaptation,
    breaks_when). Cross-domain studies require distinct domains. Registration does not validate transfer.
    """),
    Topic(id: "tools", purpose: "Register a Python tool candidate and tests", prerequisites: ["foundation"], contract: """
    executable_tool requires Python source, name, purpose, applies_when, avoid_when, environment, dependencies, side_effects
    and an object input_schema using the existing Skill parameter contract. tool_test_plan binds the exact executable_tool parent
    and matching environment. Include purpose, coverage_gaps, oracle_basis and distinct cases with id, purpose, reason, input
    and expected (explicit null is allowed). Include target and regression cases. Registration neither executes nor releases code.
    """),
    Topic(id: "workflows", purpose: "Register workflow roles, steps and review conditions", prerequisites: ["foundation"], contract: """
    workflow_method includes purpose, domain, bottleneck, change_rationale, applies_when, avoid_when, risks, expected_gain,
    falsifier, dimensions, roles, inputs and steps. Steps declare id, role, stage, assignment, depends_on, dependency_policy,
    independent_review and optional review_targets. Dependencies must be acyclic, review targets must be dependencies, and
    the reviewed role must differ from the reviewer. Steps cannot override tools, models or permissions.
    """)
  ]

  static func page(topic: String, offset: Int) -> AgentMcpJSONObject? {
    let selected = topic.isEmpty ? "all" : topic
    let payload: AgentMcpJSONObject
    if selected == "catalog" {
      payload = ["topics": .array(topics.map { item in
        .object(["id": .string(item.id), "purpose": .string(item.purpose),
          "prerequisites": .array(item.prerequisites.map(AgentMcpJSONValue.string))])
      }), "required_execution_sequence": .bool(false)]
    } else if selected == "all" {
      payload = ["contract": .string(topics.map { $0.contract }.joined(separator: "\n\n"))]
    } else if let match = topics.first(where: { $0.id == selected }) {
      payload = ["contract": .string(match.contract), "prerequisites": .array(match.prerequisites.map(AgentMcpJSONValue.string))]
    } else {
      return ["error": .string("unknown_evolution_topic"), "guidance": .string("Use topic=catalog to list iOS rule topics.")]
    }
    let content = AgentMcpJSONCodec.stringify(payload.merging([
      "format": .string("galaxyssi.collaborative-evolution.v1"), "grants_permissions": .bool(false)
    ]) { original, _ in original })
    guard (0...content.count).contains(offset) else { return nil }
    let part = String(content.dropFirst(offset).prefix(8_000))
    let next = offset + part.count
    return ["topic": .string(selected), "content": .string(part), "total_characters": .int(Int64(content.count)),
      "next_offset": next < content.count ? .int(Int64(next)) : .null, "trust": .string("host_schema_not_execution_authority")]
  }
}

struct AgentCollaborationGoalCheckpoint: Codable, Equatable {
  enum Phase: String, Codable { case planning, working, waiting, accepted }
  var runId: String
  var conversationId: String
  var turnId: String
  var revision: Int64
  var phase: Phase
  var contract: [AgentCollaborationGoalAssessmentPolicy.Criterion]
  var completedWorkIds: Set<String>
  var liveGraph: AgentCollaborationLiveGraph? = nil
}

struct AgentCollaborationAcceptedDelivery: Codable, Equatable {
  struct Source: Codable, Equatable {
    let profileID: String
    let messageID: UUID
    let contactID: String
    let rosterDigest: String

    static func rosterDigest(_ roster: AgentCollaborationRoster) -> String? {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      guard let bytes = try? encoder.encode(roster) else { return nil }
      return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
  }

  let owner: AgentCollaborationToolEvidenceScope
  let assessmentDigest: String
  let goalDigest: String
  let criteriaDigest: String
  let reference: AgentCollaborationResearchReference
  let content: String
  var source: Source? = nil
}

struct AgentCollaborationCoordinatorRecovery: Codable, Equatable {
  let owner: AgentCollaborationToolEvidenceScope
  let source: AgentCollaborationAcceptedDelivery.Source
  let route: AgentManualCloudBinding
  let originalPrompt: String
  let process: String
  var attachments: CloudCoordinatorAttachmentRecovery? = nil
}

struct AgentCollaborationGoalWorkRun: Codable {
  enum State: String, Codable { case running, succeeded, failed, interrupted }
  struct Target: Codable, Equatable {
    enum Kind: String, Codable { case cloud, local, desktop }
    let kind: Kind
    let resourceID: String
    let modelID: String

    var fields: AgentMcpJSONObject {
      ["kind": .string(kind.rawValue), "resource_id": .string(resourceID), "model_id": .string(modelID)]
    }
  }
  struct DesktopBinding: Codable, Equatable {
    let owner: AgentCollaborationToolEvidenceScope
    let workID: String
    let dispatchID: String
    let profileID: String
    let desktopID: String
    let desktopFingerprint: String
    let routeID: String
    let contactID: String
    let agentID: String

    var recoveryBinding: AgentDesktopReplyBinding? {
      guard let source = UUID(uuidString: dispatchID), source.uuidString == dispatchID else { return nil }
      return AgentDesktopReplyBinding(desktopId: desktopID, displayContactId: contactID, sourceId: source,
        contactId: contactID, agentId: agentID, identity: .init(clientRouteId: routeID,
          conversationId: owner.conversationId, taskId: dispatchID, turnId: owner.turnId), goalWork: true)
    }

    func matches(_ payload: [String: Any], desktop: String, fingerprint: String, route: String, profile: String) -> Bool {
      let observed = AgentTeamReplyObservation(payload: payload)
      return desktop == desktopID && fingerprint == desktopFingerprint && route == routeID && profile == profileID &&
        payload.string("client_route_id") == routeID && payload.string("contact_id") == contactID &&
        payload.string("agent_id") == agentID && payload.string("source_message_id") == dispatchID &&
        payload.string("task_id") == dispatchID && payload.string("conversation_id") == owner.conversationId &&
        payload.string("turn_id") == owner.turnId && observed.valid && observed.generation == 1
    }
  }
  static let processID = UUID().uuidString
  static let leaseMillis: Int64 = 300_000

  let workID: String
  let dispatchID: String
  let owner: AgentCollaborationToolEvidenceScope
  let memberID: String
  let process: String
  let startedAt: Int64
  var target: Target? = nil
  var state: State
  var finishedAt: Int64? = nil
  var output: String? = nil
  var outputHash: String? = nil
  var truncated: Bool? = nil
  var desktopArchiveDigest: String? = nil
  var templateMemberID: String? = nil

  func visibleState(now: Int64) -> State {
    guard state == .running, process != Self.processID || now >= startedAt + Self.leaseMillis
    else { return state }
    return .interrupted
  }

  func receipt(now: Int64) -> AgentMcpJSONObject {
    let status = visibleState(now: now)
    var result: AgentMcpJSONObject = ["success": .bool(true), "status": .string(status.rawValue), "work_id": .string(workID),
      "dispatch_id": .string(dispatchID), "member_id": .string(memberID),
      "target": target.map { .object($0.fields) } ?? .null,
      "started_at": .int(startedAt), "finished_at": finishedAt.map(AgentMcpJSONValue.int) ?? .null,
      "output": output.map(AgentMcpJSONValue.string) ?? .null, "output_sha256": outputHash.map(AgentMcpJSONValue.string) ?? .null,
      "output_truncated": .bool(truncated ?? false), "goal_accepted": .bool(false), "automatically_reexecuted": .bool(false)]
    if let templateMemberID { result["template_member_id"] = .string(templateMemberID) }
    return result
  }
}

struct AgentCollaborationLiveGraph: Codable, Equatable {
  enum DependencyPolicy: String, Codable { case success, terminal }
  enum Settlement: String, Codable { case succeeded, failed, cancelled, skipped }

  struct Work: Codable, Equatable {
    let id: String
    var member: String
    let assignment: String
    let depends_on: [String]
    let dependency_policy: DependencyPolicy?
    let independent_review: Bool?
    var stage: String? = nil
    var learning: LearningBinding? = nil
    var review_targets: [String]? = nil
    var workflowExecutionId: String? = nil
    var recruitment: Recruitment? = nil
    var blockerResolution: AgentCollaborationGoalAssessmentPolicy.Resolution? = nil

    func hasIndependentReviewAuthors(_ author: (String) -> String?,
      identity: (String) -> String = AgentTeamProgressPolicy.stableCollaborationMemberId) -> Bool {
      if let review_targets {
        guard independent_review == true, !review_targets.isEmpty,
              Set(review_targets).count == review_targets.count,
              Set(review_targets).isSubset(of: Set(depends_on)) else { return false }
      }
      guard independent_review == true else { return true }
      let targets = review_targets ?? depends_on
      return !targets.isEmpty && targets.allSatisfy { target in
        guard let origin = author(target), !origin.isBlank else { return false }
        return identity(origin) != identity(member)
      }
    }
  }

  struct RecruitmentRequest: Decodable {
    let id: String
    let template_member: String
    let role: String
    let scope: String
    let reason: String
  }

  struct Recruitment: Codable, Equatable {
    let identity: String
    let template: String
    let templateDigest: String
    var directoryID: UUID? = nil
    var reusedMember: String? = nil
    let role: String
    let scope: String
    let reason: String

    init?(_ request: RecruitmentRequest, owner: String, templateDigest: String, directoryOwner: String) {
      let role = request.role.trimmingCharacters(in: .whitespacesAndNewlines)
      let scope = request.scope.trimmingCharacters(in: .whitespacesAndNewlines)
      let reason = request.reason.trimmingCharacters(in: .whitespacesAndNewlines)
      guard request.id.range(of: #"\A[A-Za-z0-9_-]{1,80}\z"#, options: .regularExpression) != nil,
            !role.isEmpty, role.utf8.count <= 240, !scope.isEmpty, scope.utf8.count <= 2_000,
            !reason.isEmpty, reason.utf8.count <= 2_000 else { return nil }
      self.identity = "recruit-" + AgentMcpJSONCodec.sha256(["owner": .string(owner),
        "template": .string(request.template_member), "template_sha256": .string(templateDigest),
        "role": .string(Self.normalized(role)), "scope": .string(Self.normalized(scope))])
      self.template = request.template_member
      self.templateDigest = templateDigest
      self.role = role
      self.scope = scope
      self.reason = reason
      if !directoryOwner.isBlank {
        let digest = AgentMcpJSONCodec.sha256(["conversation": .string(directoryOwner),
          "template": .string(AgentTeamProgressPolicy.stableCollaborationMemberId(request.template_member)),
          "template_sha256": .string(templateDigest), "role": .string(Self.normalized(role)), "scope": .string(Self.normalized(scope))])
        let token = Array(digest.prefix(32))
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
        self.directoryID = UUID(uuidString: groups.map { String(token[$0]) }.joined(separator: "-"))
      }
    }

    private static func normalized(_ value: String) -> String {
      value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var executionMember: String { reusedMember ?? template }

    var executionIdentity: String {
      if reusedMember != nil, let directoryID { return directoryID.uuidString.lowercased() }
      return identity
    }

    func accepts(_ member: AgentCollaborationRoster.Member, roster: AgentCollaborationRoster) -> Bool {
      guard !member.mentionOnly, Self.templateDigest(member) == templateDigest,
            let templateID = UUID(uuidString: AgentTeamProgressPolicy.stableCollaborationMemberId(template)),
            let original = roster.members.first(where: { $0.id == templateID && !$0.mentionOnly && $0.recruitmentTemplateID == nil }),
            Self.templateDigest(original) == templateDigest else { return false }
      if reusedMember == nil { return member.id == templateID }
      return isReusable(member, originalTemplateID: templateID)
    }

    func isReusable(_ member: AgentCollaborationRoster.Member, originalTemplateID: UUID) -> Bool {
      member.id == directoryID && member.recruitmentTemplateID == originalTemplateID && !member.mentionOnly &&
        Self.templateDigest(member) == templateDigest && Self.normalized(member.role) == Self.normalized(role)
    }

    static func templateDigest(_ member: AgentCollaborationRoster.Member) -> String {
      AgentMcpJSONCodec.sha256(["resource": .string(member.resourceId), "model": .string(member.modelId),
        "reasoning": .string(member.reasoningEffort ?? ""), "mention_only": .bool(member.mentionOnly)])
    }
  }

  struct DirectoryProjection {
    let source: AgentCollaborationAcceptedDelivery.Source
    let recruits: [Recruitment]

    func applying(to roster: AgentCollaborationRoster) -> AgentCollaborationRoster {
      var updated = roster
      var handled = Set(roster.handledRecruitmentIDs ?? [])
      var names = Set(roster.members.map { $0.name.lowercased() })
      for recruit in recruits {
        guard handled.count < AgentCollaborationRoster.maximumMembers, let id = recruit.directoryID,
              handled.insert(id).inserted else { continue }
        guard updated.members.count < AgentCollaborationRoster.maximumMembers,
              !updated.members.contains(where: { $0.id == id }),
              let templateID = UUID(uuidString: AgentTeamProgressPolicy.stableCollaborationMemberId(recruit.template)),
              let template = roster.members.first(where: { $0.id == templateID && !$0.mentionOnly && $0.recruitmentTemplateID == nil }),
              Recruitment.templateDigest(template) == recruit.templateDigest else { continue }
        let base = String(recruit.role.prefix(48))
        var name = base, suffix = 2
        while !names.insert(name.lowercased()).inserted { name = "\(base) \(suffix)"; suffix += 1 }
        updated.members.append(.init(id: id, name: name, role: recruit.role, resourceId: template.resourceId,
          modelId: template.modelId, mentionOnly: true, reasoningEffort: template.reasoningEffort,
          recruitmentTemplateID: templateID))
      }
      updated.handledRecruitmentIDs = handled.isEmpty ? nil : handled.sorted { $0.uuidString < $1.uuidString }
      return updated
    }
  }

  struct LearningBinding: Codable, Equatable {
    let agenda: AgentCollaborationResearchReference
    let option_id: String
  }

  struct Expansion: Decodable {
    let format: String
    let work: [Work]
  }

  struct WorkflowExpansion: Decodable {
    enum Entry: Decodable {
      case work(Work)
      case workflow(AgentCollaborationWorkflowInstance)

      init(from decoder: Decoder) throws {
        let object = try AgentMcpJSONObject(from: decoder)
        if let raw = object["workflow_instance"] {
          guard object.count == 1, let instance = raw.objectValue,
                Set(instance.keys) == Set(["execution_id", "method", "inputs", "roles"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
              debugDescription: "Invalid workflow instance wrapper"))
          }
          self = .workflow(try JSONDecoder().decode(AgentCollaborationWorkflowInstance.self,
            from: Data(AgentMcpJSONCodec.stringify(instance).utf8)))
        } else {
          let item = try Work(from: decoder)
          guard item.workflowExecutionId == nil, item.recruitment == nil, item.blockerResolution == nil,
                !item.id.hasPrefix(AgentCollaborationGoalAssessmentPolicy.resolutionPrefix) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
              debugDescription: "Workflow bindings must come from a saved method"))
          }
          self = .work(item)
        }
      }
    }

    let format: String
    let work: [Entry]
    var recruit: [RecruitmentRequest]? = nil
  }

  private(set) var work: [Work] = []
  private(set) var workflowInstances: [String: AgentCollaborationWorkflowInstance]? = nil
  private(set) var learningPriorities: [String: Int64]? = nil
  private(set) var recruitments: [String: Recruitment]? = nil

  func pinningLearningPriorities(_ ranks: [String: Int64]) -> Self {
    var next = self
    next.learningPriorities = ranks.isEmpty ? nil : ranks
    return next
  }

  func appending(_ raw: String, authorizedMembers: Set<String>,
                 historicalAuthors: [String: String], settled: [String: Settlement]) -> Self? {
    guard raw.utf8.count <= 256_000,
          let expansion = try? JSONDecoder().decode(Expansion.self, from: Data(raw.utf8)),
          expansion.format == "galaxyssi.work-expansion.v1", !expansion.work.isEmpty,
          expansion.work.allSatisfy({ $0.workflowExecutionId == nil && $0.recruitment == nil &&
            $0.blockerResolution == nil && !$0.id.hasPrefix(AgentCollaborationGoalAssessmentPolicy.resolutionPrefix) }) else { return nil }
    return appendingWork(expansion.work, authorizedMembers: authorizedMembers, historicalAuthors: historicalAuthors, settled: settled)
  }

  func appendingWorkflow(_ instance: AgentCollaborationWorkflowInstance, compiled: [Work],
                         authorizedMembers: Set<String>, historicalAuthors: [String: String],
                         settled: [String: Settlement]) -> Self? {
    guard workflowInstances?[instance.execution_id] == nil,
          compiled.allSatisfy({ !$0.id.hasPrefix(AgentCollaborationGoalAssessmentPolicy.resolutionPrefix) }),
          var next = appendingWork(compiled, authorizedMembers: authorizedMembers,
            historicalAuthors: historicalAuthors, settled: settled) else { return nil }
    var instances = workflowInstances ?? [:]
    instances[instance.execution_id] = instance
    next.workflowInstances = instances
    return next
  }

  func appending(_ expansion: WorkflowExpansion, authorizedMembers: Set<String>,
                 historicalAuthors: [String: String], settled: [String: Settlement],
                 recruitmentTemplates: [String: String] = [:], recruitmentOwner: String = "",
                 recruitmentDirectory: String = "", authorIdentity: (String) -> String = AgentTeamProgressPolicy.stableCollaborationMemberId,
                 resolveHistorical: (Recruitment, Bool) -> String? = { _, _ in nil },
                 resolve: (AgentCollaborationWorkflowInstance) throws -> [Work]?) rethrows -> Self? {
    guard expansion.format == "galaxyssi.work-expansion.v1", !expansion.work.isEmpty else { return nil }
    var instances = workflowInstances ?? [:]
    var directory = recruitments ?? [:]
    let requests = expansion.recruit ?? []
    guard requests.count <= 64, Set(requests.map(\.id)).count == requests.count else { return nil }
    for request in requests {
      let alias = "recruit:" + request.id
      guard !recruitmentOwner.isBlank, let digest = recruitmentTemplates[request.template_member],
            authorizedMembers.contains(request.template_member),
            expansion.work.contains(where: {
              if case .work(let item) = $0 { return item.member == alias }; return false
            }),
            var requested = Recruitment(request, owner: recruitmentOwner, templateDigest: digest, directoryOwner: recruitmentDirectory),
            directory[alias] == nil || directory[alias]?.identity == requested.identity else { return nil }
      if directory[alias] == nil {
        requested.reusedMember = resolveHistorical(requested, true)
        directory[alias] = directory.values.first(where: { $0.identity == requested.identity }) ?? requested
      }
    }
    guard directory.count <= AgentCollaborationRoster.maximumMembers else { return nil }
    var additions: [Work] = []
    for entry in expansion.work {
      switch entry {
      case .work(var item):
        if item.member.hasPrefix("recruit:") {
          guard let binding = directory[item.member], recruitmentTemplates[binding.template] == binding.templateDigest
          else { return nil }
          if let reused = binding.reusedMember, resolveHistorical(binding, false) != reused { return nil }
          item.member = binding.executionMember
          item.recruitment = binding
        }
        additions.append(item)
      case .workflow(let instance):
        if let existing = instances[instance.execution_id] {
          guard existing == instance else { return nil }
          continue
        }
        guard let work = try resolve(instance), !work.isEmpty,
              work.allSatisfy({ !$0.id.hasPrefix(AgentCollaborationGoalAssessmentPolicy.resolutionPrefix) }) else { return nil }
        additions.append(contentsOf: work)
        instances[instance.execution_id] = instance
      }
    }
    if additions.isEmpty { return self }
    guard var next = appendingWork(additions, authorizedMembers: authorizedMembers,
      historicalAuthors: historicalAuthors, settled: settled, authorIdentity: authorIdentity) else { return nil }
    next.workflowInstances = instances.isEmpty ? nil : instances
    next.recruitments = directory.isEmpty ? nil : directory
    return next
  }

  func appendingResolutionWork(_ additions: [Work], authorizedMembers: Set<String>) -> Self? {
    guard additions.allSatisfy({ $0.blockerResolution?.workID == $0.id }) else { return nil }
    return appendingWork(additions, authorizedMembers: authorizedMembers, historicalAuthors: [:], settled: [:])
  }

  private func appendingWork(_ additions: [Work], authorizedMembers: Set<String>,
                             historicalAuthors: [String: String], settled: [String: Settlement],
                             authorIdentity: (String) -> String = AgentTeamProgressPolicy.stableCollaborationMemberId) -> Self? {
    var byId = Dictionary(work.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard byId.count == work.count else { return nil }
    for item in additions {
      guard !item.id.isBlank, item.id.utf8.count <= 160, !item.assignment.isBlank,
            item.assignment.utf8.count <= 16_000, authorizedMembers.contains(item.member),
            byId[item.id] == nil, settled[item.id] == nil, historicalAuthors[item.id] == nil,
            Set(item.depends_on).count == item.depends_on.count,
            !item.depends_on.contains(item.id) else { return nil }
      byId[item.id] = item
    }
    for item in additions {
      guard item.depends_on.allSatisfy({ byId[$0] != nil || settled[$0] != nil }),
            item.hasIndependentReviewAuthors({ byId[$0]?.member ?? historicalAuthors[$0] }, identity: authorIdentity) else { return nil }
    }
    var resolved = Set(settled.keys)
    var remaining = work + additions
    while !remaining.isEmpty {
      let ready = remaining.filter { Set($0.depends_on).isSubset(of: resolved) }
      guard !ready.isEmpty else { return nil }
      let ids = Set(ready.map(\.id))
      resolved.formUnion(ids)
      remaining.removeAll { ids.contains($0.id) }
    }
    var next = self
    next.work.append(contentsOf: additions)
    return next
  }

  func ready(settled: [String: Settlement], active: Set<String>) -> [Work] {
    prioritizeReady(work.filter { item in
      settled[item.id] == nil && !active.contains(item.id) && item.depends_on.allSatisfy { dependency in
        guard let state = settled[dependency] else { return false }
        return item.dependency_policy == .terminal || state == .succeeded
      }
    })
  }

  func prioritizeReady(_ candidates: [Work]) -> [Work] {
    var ready = candidates
    guard let learningPriorities else { return ready }
    var slots: [String: [Int]] = [:]
    for (index, item) in ready.enumerated() {
      if let binding = item.learning, learningPriorities[item.id] != nil {
        slots[binding.agenda.objectId, default: []].append(index)
      }
    }
    for indices in slots.values {
      let ordered = indices.map { ($0, ready[$0]) }.sorted { left, right in
        let a = learningPriorities[left.1.id] ?? Int64.max
        let b = learningPriorities[right.1.id] ?? Int64.max
        return a == b ? left.0 < right.0 : a < b
      }
      for (index, entry) in zip(indices, ordered) { ready[index] = entry.1 }
    }
    return ready
  }
}

struct AgentCollaborationWorkflowInstance: Codable, Equatable {
  let execution_id: String
  let method: AgentCollaborationResearchReference
  let inputs: [String: AgentCollaborationResearchReference]
  let roles: [String: String]

  func compile(_ body: AgentMcpJSONObject) -> [AgentCollaborationLiveGraph.Work]? {
    guard !execution_id.isBlank, execution_id.utf8.count <= 160,
          AgentCollaborationWorkflowIntake.validates(body),
          let declaredRoles = body["roles"]?.arrayValue,
          Set(declaredRoles.compactMap(\.stringValue)) == Set(roles.keys),
          let declaredInputs = body["inputs"]?.arrayValue,
          Set(declaredInputs.compactMap(\.stringValue)) == Set(inputs.keys),
          let steps = body["steps"]?.arrayValue else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    var ids: [String: String] = [:]
    for raw in steps {
      guard let step = raw.objectValue, let bytes = try? encoder.encode([execution_id, step.string("id")]) else { return nil }
      ids[step.string("id")] = "workflow:" + AgentTeamDispatchIds.nameBasedUUID(String(decoding: bytes, as: UTF8.self))
        .uuidString.lowercased()
    }
    let compiled: [AgentCollaborationLiveGraph.Work] = steps.compactMap { raw in
      guard let step = raw.objectValue, let member = roles[step.string("role")],
            let id = ids[step.string("id")] else { return nil }
      return AgentCollaborationLiveGraph.Work(id: id, member: member,
        assignment: step.string("assignment"),
        depends_on: (step["depends_on"]?.arrayValue ?? []).compactMap(\.stringValue).compactMap { ids[$0] },
        dependency_policy: AgentCollaborationLiveGraph.DependencyPolicy(rawValue: step.string("dependency_policy")),
        independent_review: step["independent_review"] == .bool(true), stage: step.string("stage"),
        review_targets: step["review_targets"]?.arrayValue?.compactMap(\.stringValue).compactMap { ids[$0] },
        workflowExecutionId: execution_id)
    }
    guard compiled.count == steps.count else { return nil }
    let members = Dictionary(uniqueKeysWithValues: compiled.map { ($0.id, $0.member) })
    guard compiled.allSatisfy({ $0.hasIndependentReviewAuthors({ members[$0] }) }) else { return nil }
    return compiled
  }
}

enum AgentCollaborationGoalAssessmentPolicy {
  enum Verification: String, Codable { case documentary, computational, physical }
  enum Decision: String, Codable { case `continue`, achieved, blocked }
  enum EvidenceKind: String, Codable { case observed, simulation, proposal }

  struct Criterion: Codable, Equatable {
    enum Status: String, Codable { case met, open }
    var id: String
    var requirement: String
    var verification: Verification
    var status: Status
    var evidence_kind: EvidenceKind?
    var evidence: [String]
    var delivery: AgentCollaborationDocumentaryAcceptance.Reference? = nil
    var review: AgentCollaborationDocumentaryAcceptance.Reference? = nil
    var required_observations: [RequiredObservation]? = nil
    var validator: AgentMcpJSONObject? = nil

    var hasValidValidatorBinding: Bool {
      guard let validator else { return true }
      return verification == .computational && requirement == AgentCollaborationNumericTrial.requirement &&
        validator["id"] == .string(AgentCollaborationNumericTrial.validatorId)
    }
  }

  struct RequiredObservation: Codable, Hashable {
    static let allowedOrigins = ["ios_cloud_tool", "ios_native_tool", "desktop_codex_tool",
      "android_cloud_tool", "android_native_tool"]
    var origin: String
    var tool: String

    var isValid: Bool {
      Self.allowedOrigins.contains(origin) && !tool.isBlank
    }
  }

  struct Work: Codable {
    var id: String
    var member: String
    var assignment: String
  }

  struct Blocker: Codable {
    enum Kind: String, Codable { case resource, permission, connectivity, provider, capacity }
    struct Alternative: Codable {
      enum Status: String, Codable { case unavailable, needs_approval, not_applicable }
      var option: String
      var status: Status
      var result: String
      var evidence: [String]
    }
    var id: String
    var kind: Kind
    var reason: String
    var resume_when: String
    var alternatives: [Alternative]?
  }

  static let resolutionPrefix = "resource-resolution:"

  struct Resolution: Codable, Equatable {
    let blockerID: String
    let workID: String
    let binding: String

    init?(_ blocker: Blocker) {
      guard blocker.kind == .resource || blocker.kind == .permission,
            blocker.id.range(of: #"\A[A-Za-z0-9._-]{1,128}\z"#, options: .regularExpression) != nil,
            !blocker.reason.isBlank, blocker.reason.utf8.count <= 2_048,
            !blocker.resume_when.isBlank, blocker.resume_when.utf8.count <= 2_048 else { return nil }
      blockerID = blocker.id
      workID = AgentCollaborationGoalAssessmentPolicy.resolutionPrefix + AgentMcpJSONCodec.sha256([
        "id": .string(blocker.id), "kind": .string(blocker.kind.rawValue)])
      binding = AgentMcpJSONCodec.sha256(["work": .string(workID),
        "reason": .string(blocker.reason), "resume_when": .string(blocker.resume_when)])
    }
  }

  struct ResolutionReport: Decodable {
    struct Alternative: Decodable {
      enum Status: String, Decodable { case available, unavailable, needs_approval, not_applicable }
      let option: String
      let status: Status
      let result: String
      let evidence: [String]
    }
    let format: String
    let alternatives: [Alternative]

    static func checked(_ raw: String) -> Self? {
      guard raw.utf8.count <= 24 * 1_024, let report = try? JSONDecoder().decode(Self.self, from: Data(raw.utf8)),
            report.format == "galaxyssi.resource-resolution-result.v1", (1...16).contains(report.alternatives.count),
            report.alternatives.allSatisfy({ !$0.option.isBlank && !$0.result.isBlank && !$0.evidence.isEmpty &&
              $0.evidence.allSatisfy { !$0.isBlank } }),
            Set(report.alternatives.map(\.option)).count == report.alternatives.count else { return nil }
      return report
    }

    func supportsWaiting(_ blocker: Blocker, workID: String, digest: String) -> Bool {
      guard let proposed = blocker.alternatives, proposed.count == alternatives.count,
            Set(proposed.map(\.option)).count == proposed.count else { return false }
      return alternatives.allSatisfy { original in
        original.status != .available && proposed.contains { candidate in
          candidate.option == original.option && candidate.status.rawValue == original.status.rawValue &&
            candidate.result == original.result &&
            Set(original.evidence + [workID, digest]).isSubset(of: Set(candidate.evidence))
        }
      }
    }
  }

  struct Assessment: Codable {
    var format: String
    var summary: String
    var decision: Decision
    var criteria: [Criterion]
    var work: [Work]
    var blockers: [Blocker]
    var recruit: [Work]?
  }

  static func blockerAssessment(_ raw: String, preserving contract: [Criterion]) -> Assessment? {
    guard !contract.isEmpty, raw.utf8.count <= 131_072,
          let draft = try? JSONDecoder().decode(Assessment.self, from: Data(raw.utf8)),
          draft.format == "galaxyssi.goal-assessment.v1", draft.decision == .blocked, !draft.summary.isBlank,
          draft.work.isEmpty, draft.recruit?.isEmpty != false, (1...16).contains(draft.blockers.count),
          Set(draft.blockers.map(\.id)).count == draft.blockers.count,
          draft.blockers.allSatisfy({ !$0.id.isBlank && !$0.reason.isBlank && !$0.resume_when.isBlank &&
            (($0.kind != .resource && $0.kind != .permission) || Resolution($0) != nil) }),
          draft.criteria.count == contract.count, Set(draft.criteria.map(\.id)).count == draft.criteria.count,
          contract.allSatisfy({ original in
            guard let current = draft.criteria.first(where: { $0.id == original.id }) else { return false }
            return current.requirement == original.requirement && current.verification == original.verification &&
              current.validator == original.validator &&
              Set(original.required_observations ?? []).isSubset(of: Set(current.required_observations ?? []))
          }) else { return nil }
    return draft
  }

  static let establishContractMode = "establish_contract"
  static let appendWorkMode = "append_work"
  static let runWorkMode = "run_work"
  static let runReadyWorkMode = "run_ready_work"
  static let checkGoalEvidenceMode = "check_goal_evidence"

  static func requiresCoordinator(_ mode: String) -> Bool {
    isCoordinatorMutation(mode) || mode == checkGoalEvidenceMode
  }

  static func dispatchesWork(_ mode: String) -> Bool {
    mode == runWorkMode || mode == runReadyWorkMode || mode == appendWorkMode
  }

  static func isCoordinatorMutation(_ mode: String) -> Bool {
    mode == establishContractMode || mode == appendWorkMode
  }

  static func initialContract(_ raw: String) -> [Criterion]? {
    guard raw.utf8.count <= 131_072,
          let draft = try? JSONDecoder().decode(Assessment.self, from: Data(raw.utf8)),
          draft.format == "galaxyssi.goal-assessment.v1", !draft.summary.isBlank,
          draft.decision == .continue, draft.work.isEmpty, draft.blockers.isEmpty, draft.recruit?.isEmpty != false,
          (1...64).contains(draft.criteria.count),
          Set(draft.criteria.map(\.id)).count == draft.criteria.count,
          draft.criteria.allSatisfy({ criterion in
            let observations = criterion.required_observations ?? []
            return !criterion.id.isBlank && criterion.id.utf8.count <= 160 &&
              !criterion.requirement.isBlank && criterion.requirement.utf8.count <= 8_192 &&
              criterion.status == .open && criterion.evidence.isEmpty && criterion.evidence_kind == nil &&
              criterion.delivery == nil && criterion.review == nil && criterion.hasValidValidatorBinding &&
              observations.count <= 16 && Set(observations).count == observations.count &&
              observations.allSatisfy { $0.isValid && $0.tool.utf8.count <= 160 }
          }) else { return nil }
    return draft.criteria
  }

  struct VerifiedCriterion {
    var requirement: String
    var verification: Verification
    var evidence: Set<String>
    var originalObservations: Set<RequiredObservation> = []
  }

  enum Outcome: Equatable {
    case needsAssessment
    case schedule([String])
    case waiting([String])
    case achieved
  }

  static func preflight(_ raw: String, establishedContract: Bool) -> AgentMcpJSONObject {
    var response: AgentMcpJSONObject = [
      "success": .bool(false), "status": .string("invalid_assessment"),
      "json_valid": .bool(false),
      "acceptance_contract_state": .string(establishedContract ? "established" : "not_established"),
      "validation_scope": .string("structure_only_not_admission_or_acceptance")
    ]
    func fail(_ path: String, _ reason: String, allowed: [String] = []) -> AgentMcpJSONObject {
      response["field_path"] = .string(path)
      response["reason"] = .string(reason)
      if !allowed.isEmpty { response["allowed_values"] = .array(allowed.map(AgentMcpJSONValue.string)) }
      return response
    }
    let data = Data(raw.utf8)
    guard data.count <= 131_072, (try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data)) != nil else {
      return fail("$", "expected_bounded_json_object")
    }
    response["json_valid"] = .bool(true)
    func path(_ keys: [CodingKey]) -> String {
      keys.reduce("$") { value, key in
        if let index = key.intValue { return value + "[\(index)]" }
        return value + "." + key.stringValue
      }
    }
    let draft: Assessment
    do { draft = try JSONDecoder().decode(Assessment.self, from: data) }
    catch let DecodingError.keyNotFound(key, context) { return fail(path(context.codingPath + [key]), "required_field") }
    catch let DecodingError.typeMismatch(_, context) { return fail(path(context.codingPath), "wrong_type") }
    catch let DecodingError.valueNotFound(_, context) { return fail(path(context.codingPath), "required_value") }
    catch let DecodingError.dataCorrupted(context) { return fail(path(context.codingPath), "invalid_value") }
    catch { return fail("$", "invalid_assessment") }
    guard draft.format == "galaxyssi.goal-assessment.v1" else {
      return fail("$.format", "unexpected_format", allowed: ["galaxyssi.goal-assessment.v1"])
    }
    guard !draft.summary.isBlank else { return fail("$.summary", "expected_nonblank_text") }
    guard !draft.criteria.isEmpty else { return fail("$.criteria", "expected_nonempty_criteria") }
    var ids = Set<String>()
    for (index, criterion) in draft.criteria.enumerated() {
      let root = "$.criteria[\(index)]"
      guard !criterion.id.isBlank, ids.insert(criterion.id).inserted else { return fail(root + ".id", "expected_unique_id") }
      guard !criterion.requirement.isBlank else { return fail(root + ".requirement", "expected_nonblank_text") }
      for (sourceIndex, source) in (criterion.required_observations ?? []).enumerated() {
        let sourcePath = root + ".required_observations[\(sourceIndex)]"
        guard RequiredObservation.allowedOrigins.contains(source.origin) else {
          return fail(sourcePath + ".origin", "unsupported_origin", allowed: RequiredObservation.allowedOrigins)
        }
        guard !source.tool.isBlank else { return fail(sourcePath + ".tool", "expected_nonblank_text") }
      }
    }
    response["success"] = .bool(true)
    response["status"] = .string("valid_structure")
    return response
  }

  static func evaluate(_ raw: String, preserving contract: [Criterion],
                       authorizedMembers: Set<String>, completedWork: Set<String>,
                       checkedBlockers: Set<String> = [],
                       verified: [String: VerifiedCriterion] = [:]) -> Outcome {
    guard raw.utf8.count <= 256_000,
          let assessment = try? JSONDecoder().decode(Assessment.self, from: Data(raw.utf8)),
          assessment.format == "galaxyssi.goal-assessment.v1",
          !assessment.summary.isBlank, !assessment.criteria.isEmpty,
          Set(assessment.criteria.map(\.id)).count == assessment.criteria.count,
          assessment.criteria.allSatisfy({ !$0.id.isBlank && !$0.requirement.isBlank && $0.hasValidValidatorBinding &&
            ($0.required_observations ?? []).allSatisfy(\.isValid) }) else {
      return .needsAssessment
    }
    let criteria = Dictionary(uniqueKeysWithValues: assessment.criteria.map { ($0.id, $0) })
    guard contract.allSatisfy({ original in
      guard let current = criteria[original.id] else { return false }
      return current.requirement == original.requirement && current.verification == original.verification &&
        current.validator == original.validator &&
        Set(original.required_observations ?? []).isSubset(of: Set(current.required_observations ?? []))
    }) else { return .needsAssessment }
    guard assessment.recruit?.isEmpty != false else { return .needsAssessment }

    if !assessment.work.isEmpty {
      let ids = assessment.work.map(\.id)
      guard assessment.decision == .continue, Set(ids).count == ids.count,
            completedWork.isDisjoint(with: ids), assessment.work.allSatisfy({
              !$0.id.isBlank && !$0.assignment.isBlank && authorizedMembers.contains($0.member)
            }) else { return .needsAssessment }
      return .schedule(ids)
    }
    switch assessment.decision {
    case .continue:
      return .needsAssessment
    case .blocked:
      let ids = assessment.blockers.map(\.id)
      guard !ids.isEmpty, Set(ids).count == ids.count,
            assessment.blockers.allSatisfy({ blocker in
              guard !blocker.id.isBlank, !blocker.reason.isBlank, !blocker.resume_when.isBlank else { return false }
              guard blocker.kind == .resource || blocker.kind == .permission else { return true }
              guard checkedBlockers.contains(blocker.id), let alternatives = blocker.alternatives,
                    !alternatives.isEmpty else { return false }
              return alternatives.allSatisfy {
                !$0.option.isBlank && !$0.result.isBlank && !$0.evidence.isEmpty &&
                  $0.evidence.allSatisfy { !$0.isBlank }
              }
            }) else { return .needsAssessment }
      return .waiting(ids)
    case .achieved:
      guard !contract.isEmpty, assessment.blockers.isEmpty,
            assessment.criteria.allSatisfy({ item in
              guard item.status == .met, let kind = item.evidence_kind, kind != .proposal,
                    item.verification != .physical || kind == .observed,
                    !item.evidence.isEmpty, item.evidence.allSatisfy({ !$0.isBlank }),
                    let receipt = verified[item.id], receipt.requirement == item.requirement,
                    receipt.verification == item.verification else { return false }
              return Set(item.evidence).isSubset(of: receipt.evidence) &&
                Set(item.required_observations ?? []).isSubset(of: receipt.originalObservations)
            }) else { return .needsAssessment }
      return .achieved
    }
  }
}

enum AgentCollaborationDocumentaryAcceptance {
  struct OriginalObservation {
    var origin: String
    var tool: String
    var status: String
    var kind: String
  }
  struct Reference: Codable, Equatable {
    var objectId: String
    var revision: Int64
    var sha256: String

    enum CodingKeys: String, CodingKey {
      case objectId = "object_id"
      case revision, sha256
    }
  }

  struct Revision {
    var reference: Reference
    var conversationId: String
    var runId: String
    var turnId: String
    var authorId: String
    var kind: String
    var body: AgentMcpJSONObject
    var parents: [Reference]
    var hostObservationIds: Set<String>
  }

  private struct Review: Decodable {
    var criterion_id: String
    var requirement: String
    var target: Reference
    var verdict: String
    var rationale: String
    var unresolved: [String]
  }

  static func validReviewPublication(body: AgentMcpJSONObject, parents: [Reference]) -> Bool {
    guard let raw = body["acceptance_review"]?.objectValue,
          let review = try? JSONDecoder().decode(Review.self, from: Data(AgentMcpJSONCodec.stringify(raw).utf8)),
          !review.criterion_id.isBlank, !review.requirement.isBlank, !review.rationale.isBlank,
          review.target.revision > 0, parents.contains(review.target),
          ["supported", "refuted", "not_tested"].contains(review.verdict),
          review.unresolved.allSatisfy({ !$0.isBlank }),
          review.verdict != "supported" || review.unresolved.isEmpty else { return false }
    return [review.target.objectId, review.target.sha256].allSatisfy { value in
      value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
  }

  static func evaluate(_ raw: String, preserving contract: [AgentCollaborationGoalAssessmentPolicy.Criterion],
                       conversationId: String, runId: String, turnId: String,
                       readRevision: (String, Int64?) throws -> Revision?,
                       observationIsSupporting: (String) throws -> Bool,
                       originalObservation: (String) throws -> OriginalObservation? = { _ in nil })
    -> AgentCollaborationGoalAssessmentPolicy.Outcome {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    guard !conversationId.isBlank, !runId.isBlank, !turnId.isBlank, raw.utf8.count <= 256_000,
          let assessment = try? JSONDecoder().decode(Policy.Assessment.self, from: Data(raw.utf8)),
          assessment.decision == .achieved else { return .needsAssessment }

    func current(_ reference: Reference) throws -> Revision? {
      guard reference.revision > 0, !reference.objectId.isBlank,
            reference.sha256.utf8.count == 64,
            let record = try readRevision(reference.objectId, nil),
            record.reference == reference, record.conversationId == conversationId,
            record.runId == runId, record.turnId == turnId,
            !record.authorId.isBlank else { return nil }
      return record
    }

    var verified: [String: Policy.VerifiedCriterion] = [:]
    do {
      for criterion in assessment.criteria {
        guard criterion.evidence_kind == .observed,
              let deliveryRef = criterion.delivery, let reviewRef = criterion.review,
              let delivery = try current(deliveryRef), let review = try current(reviewRef),
              ["artifact", "proposal", "decision"].contains(delivery.kind),
              !delivery.body.string("content").isBlank,
              ["acceptance_review", "decision"].contains(review.kind),
              AgentTeamProgressPolicy.stableCollaborationMemberId(delivery.authorId) !=
                AgentTeamProgressPolicy.stableCollaborationMemberId(review.authorId),
              review.parents.contains(deliveryRef),
              let rawReview = review.body["acceptance_review"]?.objectValue,
              let check = try? JSONDecoder().decode(Review.self, from: Data(AgentMcpJSONCodec.stringify(rawReview).utf8)),
              check.criterion_id == criterion.id, check.requirement == criterion.requirement,
              check.target == deliveryRef, check.verdict == "supported",
              !check.rationale.isBlank, check.unresolved.isEmpty else { return .needsAssessment }
        switch criterion.verification {
        case .documentary:
          guard criterion.validator == nil else { return .needsAssessment }
        case .computational:
          guard let pinned = contract.first(where: { $0.id == criterion.id }), pinned.hasValidValidatorBinding,
                let validator = pinned.validator, criterion.validator == validator,
                let computation = delivery.body["computation"]?.objectValue,
                AgentCollaborationNumericTrial.passes(spec: validator, computation: computation)
          else { return .needsAssessment }
        case .physical:
          return .needsAssessment
        }
        var number: Int64 = 1
        while number < deliveryRef.revision {
          guard let previous = try readRevision(deliveryRef.objectId, number),
                previous.reference.objectId == deliveryRef.objectId,
                previous.reference.revision == number, previous.conversationId == conversationId,
                !previous.authorId.isBlank, AgentTeamProgressPolicy.stableCollaborationMemberId(previous.authorId) !=
                  AgentTeamProgressPolicy.stableCollaborationMemberId(review.authorId) else { return .needsAssessment }
          number += 1
        }
        let observations = delivery.hostObservationIds.union(review.hostObservationIds)
        guard try observations.allSatisfy(observationIsSupporting) else { return .needsAssessment }
        if let required = criterion.required_observations, !required.isEmpty {
          let originals = try review.hostObservationIds.compactMap(originalObservation)
          guard required.allSatisfy({ source in
            source.isValid && originals.contains {
              $0.origin == source.origin && $0.tool == source.tool &&
                $0.status == "returned" && $0.kind == "tool_output_recorded"
            }
          }) else { return .needsAssessment }
        }
        let receipts = observations.union([deliveryRef.objectId, reviewRef.objectId, deliveryRef.sha256, reviewRef.sha256])
        verified[criterion.id] = Policy.VerifiedCriterion(requirement: criterion.requirement,
          verification: criterion.verification, evidence: receipts,
          originalObservations: Set(criterion.required_observations ?? []))
      }
    } catch { return .needsAssessment }
    return Policy.evaluate(raw, preserving: contract, authorizedMembers: [], completedWork: [], verified: verified)
  }
}

enum AgentDynamicTeamOutcome: String, Codable, CaseIterable, Identifiable {
  case singleAgent = "SINGLE_AGENT"
  case team = "TEAM"
  case unavailable = "UNAVAILABLE"
  case blocked = "BLOCKED"

  var id: String { rawValue }
}

enum AgentDynamicTeamRole: String, Codable, CaseIterable, Identifiable {
  case lead = "LEAD"
  case researcher = "RESEARCHER"
  case implementer = "IMPLEMENTER"
  case knowledgeSpecialist = "KNOWLEDGE_SPECIALIST"
  case deviceOperator = "DEVICE_OPERATOR"
  case toolSpecialist = "TOOL_SPECIALIST"
  case analyst = "ANALYST"
  case verifier = "VERIFIER"
  case requestedSpecialist = "REQUESTED_SPECIALIST"

  var id: String { rawValue }
}

enum AgentTeamVerificationMode: String, Codable, CaseIterable, Identifiable {
  case disabled = "DISABLED"
  case auto = "AUTO"
  case required = "REQUIRED"

  var id: String { rawValue }
}

enum AgentTeamVisibilityMode: String, Codable, CaseIterable, Identifiable {
  case background = "BACKGROUND"
  case visible = "VISIBLE"

  var id: String { rawValue }
}

struct AgentRequestedMember: Codable, Equatable, Identifiable {
  var agentId: String
  var displayName: String
  var occurrence: Int
  var roleHint: String

  var instanceId: String {
    String("\(agentId):mention-\(max(occurrence, 1))".prefix(96))
  }

  var id: String { instanceId }

  init(
    agentId: String,
    displayName: String,
    occurrence: Int = 1,
    roleHint: String = ""
  ) {
    self.agentId = agentId
    self.displayName = displayName
    self.occurrence = max(occurrence, 1)
    self.roleHint = String(roleHint.prefix(240))
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case displayName = "display_name"
    case occurrence
    case roleHint = "role_hint"
  }
}

struct AgentTeamCompilationBudget: Codable, Equatable {
  var maxMembers: Int
  var maxCloudMembers: Int
  var maximumMemberCost: AgentResourceCost
  var maximumMemberLatency: AgentResourceLatency
  var maxEstimatedCostUnits: Int

  init(
    maxMembers: Int = 5,
    maxCloudMembers: Int = 1,
    maximumMemberCost: AgentResourceCost = .high,
    maximumMemberLatency: AgentResourceLatency = .slow,
    maxEstimatedCostUnits: Int = 16
  ) {
    self.maxMembers = maxMembers
    self.maxCloudMembers = maxCloudMembers
    self.maximumMemberCost = maximumMemberCost
    self.maximumMemberLatency = maximumMemberLatency
    self.maxEstimatedCostUnits = maxEstimatedCostUnits
  }

  enum CodingKeys: String, CodingKey {
    case maxMembers = "max_members"
    case maxCloudMembers = "max_cloud_members"
    case maximumMemberCost = "maximum_member_cost"
    case maximumMemberLatency = "maximum_member_latency"
    case maxEstimatedCostUnits = "max_estimated_cost_units"
  }
}

struct AgentDynamicTeamPolicy: Codable, Equatable {
  var forceTeam: Bool
  var trustedOnly: Bool
  var preferFailureDomainDiversity: Bool
  var verificationMode: AgentTeamVerificationMode
  var visibilityMode: AgentTeamVisibilityMode
  var pinnedAgentIds: Set<String>
  var excludedAgentIds: Set<String>
  var budget: AgentTeamCompilationBudget

  init(
    forceTeam: Bool = false,
    trustedOnly: Bool = true,
    preferFailureDomainDiversity: Bool = true,
    verificationMode: AgentTeamVerificationMode = .auto,
    visibilityMode: AgentTeamVisibilityMode = .background,
    pinnedAgentIds: Set<String> = [],
    excludedAgentIds: Set<String> = [],
    budget: AgentTeamCompilationBudget = AgentTeamCompilationBudget()
  ) {
    self.forceTeam = forceTeam
    self.trustedOnly = trustedOnly
    self.preferFailureDomainDiversity = preferFailureDomainDiversity
    self.verificationMode = verificationMode
    self.visibilityMode = visibilityMode
    self.pinnedAgentIds = pinnedAgentIds
    self.excludedAgentIds = excludedAgentIds
    self.budget = budget
  }

  enum CodingKeys: String, CodingKey {
    case forceTeam = "force_team"
    case trustedOnly = "trusted_only"
    case preferFailureDomainDiversity = "prefer_failure_domain_diversity"
    case verificationMode = "verification_mode"
    case visibilityMode = "visibility_mode"
    case pinnedAgentIds = "pinned_agent_ids"
    case excludedAgentIds = "excluded_agent_ids"
    case budget
  }
}

struct AgentDynamicTeamRequest: Codable, Equatable {
  var goal: String
  var teamId: String
  var policy: AgentDynamicTeamPolicy

  init(
    goal: String,
    teamId: String = UUID().uuidString,
    policy: AgentDynamicTeamPolicy = AgentDynamicTeamPolicy()
  ) {
    self.goal = goal
    self.teamId = teamId
    self.policy = policy
  }

  enum CodingKeys: String, CodingKey {
    case goal
    case teamId = "team_id"
    case policy
  }
}

struct AgentDynamicTeamAssignment: Codable, Equatable {
  var role: AgentDynamicTeamRole
  var registration: AgentRegistration
  var score: Int
  var requiredCapabilities: Set<AgentCapability>
  var objective: String
  var reasons: [String]

  var failureDomain: String {
    registration.effectiveTeamFailureDomain()
  }

  enum CodingKeys: String, CodingKey {
    case role
    case registration
    case score
    case requiredCapabilities = "required_capabilities"
    case objective
    case reasons
  }
}

struct AgentTeamMember: Codable, Equatable {
  var agentId: String
  var deliveryMode: AgentDeliveryMode
  var requiredCapabilities: Set<AgentCapability>
  var role: String
  var objective: String
  var dependsOnAgentIds: Set<String>
  var context: [String: String]
  var instanceId: String

  var memberId: String {
    instanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? agentId : instanceId
  }

  init(
    agentId: String,
    deliveryMode: AgentDeliveryMode,
    requiredCapabilities: Set<AgentCapability>,
    role: String,
    objective: String,
    dependsOnAgentIds: Set<String>,
    context: [String: String],
    instanceId: String = ""
  ) {
    self.agentId = agentId
    self.deliveryMode = deliveryMode
    self.requiredCapabilities = requiredCapabilities
    self.role = role
    self.objective = objective
    self.dependsOnAgentIds = dependsOnAgentIds
    self.context = context
    self.instanceId = instanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? agentId : instanceId
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case deliveryMode = "delivery_mode"
    case requiredCapabilities = "required_capabilities"
    case role
    case objective
    case dependsOnAgentIds = "depends_on_agent_ids"
    case context
    case instanceId = "instance_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let agentId = try container.decode(String.self, forKey: .agentId)
    self.init(
      agentId: agentId,
      deliveryMode: try container.decode(AgentDeliveryMode.self, forKey: .deliveryMode),
      requiredCapabilities: try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .requiredCapabilities) ?? [],
      role: try container.decodeIfPresent(String.self, forKey: .role) ?? "",
      objective: try container.decodeIfPresent(String.self, forKey: .objective) ?? "",
      dependsOnAgentIds: try container.decodeIfPresent(Set<String>.self, forKey: .dependsOnAgentIds) ?? [],
      context: try container.decodeIfPresent([String: String].self, forKey: .context) ?? [:],
      instanceId: try container.decodeIfPresent(String.self, forKey: .instanceId) ?? agentId
    )
  }
}

struct AgentTeamDefinition: Codable, Equatable {
  var teamId: String
  var primaryAgentId: String
  var members: [AgentTeamMember]
  var visibilityMode: AgentTeamVisibilityMode
  var collectiveCapabilities: Set<AgentCapability>
  var primaryInstanceId: String

  var primaryMemberId: String {
    primaryInstanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? primaryAgentId
      : primaryInstanceId
  }

  init(
    teamId: String,
    primaryAgentId: String,
    members: [AgentTeamMember],
    visibilityMode: AgentTeamVisibilityMode,
    collectiveCapabilities: Set<AgentCapability>,
    primaryInstanceId: String = ""
  ) {
    self.teamId = teamId
    self.primaryAgentId = primaryAgentId
    self.members = members
    self.visibilityMode = visibilityMode
    self.collectiveCapabilities = collectiveCapabilities
    self.primaryInstanceId = primaryInstanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? primaryAgentId
      : primaryInstanceId
  }

  enum CodingKeys: String, CodingKey {
    case teamId = "team_id"
    case primaryAgentId = "primary_agent_id"
    case members
    case visibilityMode = "visibility_mode"
    case collectiveCapabilities = "collective_capabilities"
    case primaryInstanceId = "primary_instance_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let primaryAgentId = try container.decode(String.self, forKey: .primaryAgentId)
    self.init(
      teamId: try container.decode(String.self, forKey: .teamId),
      primaryAgentId: primaryAgentId,
      members: try container.decode([AgentTeamMember].self, forKey: .members),
      visibilityMode: try container.decodeIfPresent(AgentTeamVisibilityMode.self, forKey: .visibilityMode) ?? .background,
      collectiveCapabilities: try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .collectiveCapabilities) ?? [],
      primaryInstanceId: try container.decodeIfPresent(String.self, forKey: .primaryInstanceId) ?? primaryAgentId
    )
  }
}

struct AgentDynamicTeamCompilation: Codable, Equatable {
  var outcome: AgentDynamicTeamOutcome
  var goal: String
  var requirements: AgentTaskRequirements
  var definition: AgentTeamDefinition?
  var primaryAgentId: String?
  var assignments: [AgentDynamicTeamAssignment]
  var unfilledRoles: Set<AgentDynamicTeamRole>
  var warnings: [String]
  var estimatedCostUnits: Int
  var failureDomains: Set<String>
  var rationale: [String]

  enum CodingKeys: String, CodingKey {
    case outcome
    case goal
    case requirements
    case definition
    case primaryAgentId = "primary_agent_id"
    case assignments
    case unfilledRoles = "unfilled_roles"
    case warnings
    case estimatedCostUnits = "estimated_cost_units"
    case failureDomains = "failure_domains"
    case rationale
  }
}
