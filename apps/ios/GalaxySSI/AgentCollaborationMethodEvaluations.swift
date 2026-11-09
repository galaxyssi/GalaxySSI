import Foundation

enum AgentCollaborationMethodExperience {
  static let mode = "method_history"
  static let trust = "host_observed_method_use_not_measured_effectiveness"
  static let instructions = "Use method_history with exact method identity and no view for execution experience. Read a returned record_id with offset for original conditions. History is not proof of quality or current applicability."

  struct Binding: Codable, Equatable {
    let method: AgentCollaborationResearchReference
    let kind: String
    let inputs: AgentMcpJSONObject
    let assignment: String
    let goal: String
    let stage: String?
    let detail: AgentMcpJSONObject
  }

  struct Observation: Codable, Equatable {
    let owner: AgentCollaborationToolEvidenceScope
    let memberID: String
    let workID: String
    let dispatchID: String
    let binding: Binding
    let selectedTarget: AgentCollaborationGoalWorkRun.Target?
    let state: AgentCollaborationGoalWorkRun.State
    let startedAt: Int64
    let finishedAt: Int64
    let outputHash: String?
    let outputTruncated: Bool
    let desktopArchiveDigest: String?

    var id: String {
      AgentMcpJSONCodec.sha256(["owner": .string(owner.ownershipDigest), "dispatch": .string(dispatchID),
        "status": .string(state.rawValue)])
    }

    var summary: AgentMcpJSONObject {
      ["record_id": .string(id), "status": .string(state.rawValue), "work_id": .string(workID),
       "dispatch_id": .string(dispatchID), "started_at": .int(startedAt), "finished_at": .int(finishedAt),
       "read": .object(["mode": .string(AgentCollaborationMethodExperience.mode), "record_id": .string(id), "offset": .int(0)])]
    }

    func original() throws -> Data {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let payload = try JSONDecoder().decode(AgentMcpJSONObject.self, from: encoder.encode(self))
      return Data(AgentMcpJSONCodec.stringify(payload.merging(["record_id": .string(id), "quality_effect": .null,
        "causal_contribution": .null, "user_delivery": .string("not_observed")]) { _, new in new }).utf8)
    }
  }

  static func selector(_ ref: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    AgentCollaborationSourceAccess.workspaceReference(ref).merging(["mode": .string(mode)]) { _, new in new }
  }

  static func prefix(_ ref: AgentCollaborationResearchReference) -> String {
    "method-use-index:" + AgentMcpJSONCodec.sha256(AgentCollaborationSourceAccess.workspaceReference(ref)) + ":"
  }

  static func key(_ id: String) -> String { "method-use:" + id }

  static func record(_ run: AgentCollaborationGoalWorkRun, state: AgentCollaborationGoalWorkRun.State,
                     now: Int64, database: AgentTeamHistoryDatabase) throws {
    guard let binding = run.methodUse, state != .running else { return }
    let value = Observation(owner: run.owner, memberID: run.memberID, workID: run.workID, dispatchID: run.dispatchID,
      binding: binding, selectedTarget: run.target, state: state, startedAt: run.startedAt,
      finishedAt: max(run.startedAt, run.finishedAt ?? now), outputHash: run.outputHash,
      outputTruncated: run.truncated ?? false, desktopArchiveDigest: run.desktopArchiveDigest)
    let key = Self.key(value.id), group = run.owner.conversationId
    if let prior = try database.researchRecord(Observation.self, conversationId: group, key: key, revision: 0) {
      guard prior.owner == value.owner, prior.dispatchID == value.dispatchID, prior.binding == value.binding
      else { throw AgentTeamHistoryDatabase.Failure.stale }
      return
    }
    try database.insertResearchRecord(value, conversationId: group, key: key, revision: 0)
    try database.insertResearchRecord(value.id, conversationId: group, key: prefix(binding.method) + value.id, revision: 0)
  }
}

struct AgentCollaborationWorkflowComparison: Codable, Equatable {
  let baseline: AgentCollaborationResearchReference
  let candidate: AgentCollaborationResearchReference
  let dataset: AgentCollaborationResearchReference

  func matches(_ sample: AgentMcpJSONObject) -> Bool {
    let method = sample.string("variant") == "baseline" ? baseline : candidate
    return sample["workflow_sha256"] == .string(method.sha256) && sample["dataset_sha256"] == .string(dataset.sha256)
  }

  static func resolve(_ draft: AgentCollaborationResearchDraft,
                      current: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?) throws -> Self? {
    let ref = AgentCollaborationExperimentPlanIntake.reference
    guard let spec = draft.body["experiment_plan"]?.objectValue,
          let details = spec["workflow_comparison"]?.objectValue,
          Set(details.keys) == ["dataset", "controlled_conditions", "quality_oracle", "cost_accounting", "selection_bias"],
          ["controlled_conditions", "quality_oracle", "cost_accounting", "selection_bias"].allSatisfy({
            details[$0]?.stringValue?.isBlank == false
          }),
          let dataset = ref(details["dataset"]), draft.parents.contains(dataset),
          try current(dataset)?.draft.kind == .artifact,
          let cases = spec["cases"]?.arrayValue, AgentCollaborationExperimentPlanIntake.validatesCases(cases),
          cases.contains(where: { $0.objectValue?.string("purpose") == "target" }),
          cases.contains(where: { $0.objectValue?.string("purpose") == "regression" }),
          cases.allSatisfy({ item in
            guard let fields = item.objectValue else { return false }
            return fields["dataset"] == nil || ref(fields["dataset"]) == dataset
          }) else { return nil }
    func method(_ innovation: AgentMcpJSONValue?) throws -> (AgentCollaborationResearchReference, String)? {
      guard let idea = ref(innovation), let record = try current(idea), record.draft.kind == .innovation,
            let fields = record.draft.body["innovation"]?.objectValue,
            let method = ref(fields["workflow_method"]), record.draft.parents.contains(method),
            let saved = try current(method), saved.draft.kind == .workflowMethod,
            let workflow = saved.draft.body["workflow_method"]?.objectValue,
            !fields.string("domain").isBlank, fields.string("domain") == workflow.string("domain") else { return nil }
      return (method, workflow.string("domain"))
    }
    guard let baseline = try method(spec["baseline"]), let candidate = try method(spec["innovation"]),
          baseline.0 != candidate.0, baseline.1 == candidate.1 else { return nil }
    return Self(baseline: baseline.0, candidate: candidate.0, dataset: dataset)
  }
}

enum AgentCollaborationMethodEvaluations {
  static let view = "evaluations"
  static let trust = "host_registered_method_evaluations_not_current_applicability"
  static let scanLimit = 32
  static let resultLimit = 8
  static let guidance = "Follow next_cursor even after empty pages. Read original conditions and counterevidence before reuse. Multiple records can describe one experiment. No results means unknown evaluation history. This is not a snapshot; restart to include concurrent publications. This scan does not adopt a method or establish causality."

  struct Cursor {
    let scope: String
    let objectID: String
    let revision: Int64

    init(scope: String, objectID: String, revision: Int64) {
      self.scope = scope
      self.objectID = objectID
      self.revision = revision
    }

    init?(_ value: String) {
      let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
      guard value.utf8.count <= 160, parts.count == 3, Self.validDigest(parts[0]), Self.validDigest(parts[1]),
            let revision = Int64(parts[2]), revision > 0, parts[2] == String(revision) else { return nil }
      self.init(scope: parts[0], objectID: parts[1], revision: revision)
    }

    var encoded: String { "\(scope).\(objectID).\(revision)" }
    var position: (String, Int64) { (objectID, revision) }

    static func validDigest(_ value: String) -> Bool {
      value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
  }

  static func reference(_ ref: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    ["object_id": .string(ref.objectId), "revision": .int(ref.revision), "sha256": .string(ref.sha256)]
  }

  static func reference(from value: AgentMcpJSONObject) -> AgentCollaborationResearchReference? {
    guard case .int(let revision)? = value["revision"], revision > 0,
          Cursor.validDigest(value.string("object_id")), Cursor.validDigest(value.string("sha256")) else { return nil }
    return .init(objectId: value.string("object_id"), revision: revision, sha256: value.string("sha256"))
  }

  static func selector(_ ref: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    var query = reference(ref)
    query["mode"] = .string("method_history")
    query["view"] = .string(view)
    return query
  }

  static func cursorScope(_ scope: AgentCollaborationToolEvidenceScope, method: AgentCollaborationResearchReference) -> String {
    AgentMcpJSONCodec.sha256(["view": .string(view), "owner": .string(scope.ownershipDigest), "method": .object(reference(method))])
  }

  static func match(method: AgentCollaborationResearchReference, saved: AgentCollaborationResearchRevision,
                    read: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?) throws -> AgentMcpJSONObject? {
    let ref = AgentCollaborationExperimentPlanIntake.reference
    let plan: AgentCollaborationResearchRevision
    var result: AgentCollaborationResearchRevision? = nil
    switch saved.draft.kind {
    case .experimentPlan: plan = saved
    case .experimentResult, .capabilityLesson:
      if saved.draft.kind == .experimentResult {
        result = saved
      } else {
        guard let link = ref(saved.draft.body["capability_lesson"]?.objectValue?["result"]),
              saved.draft.parents.contains(link) else { return nil }
        result = try read(link)
      }
      guard let measured = result, measured.draft.kind == .experimentResult,
            let planRef = ref(measured.draft.body["experiment_result"]?.objectValue?["plan"]),
            measured.draft.parents.contains(planRef), let original = try read(planRef),
            original.draft.kind == .experimentPlan else { return nil }
      plan = original
    default: return nil
    }
    guard let comparison = plan.workflowComparison, method == comparison.baseline || method == comparison.candidate,
          try read(comparison.baseline)?.draft.kind == .workflowMethod,
          try read(comparison.candidate)?.draft.kind == .workflowMethod,
          try read(comparison.dataset)?.draft.kind == .artifact,
          let spec = plan.draft.body["experiment_plan"]?.objectValue,
          let details = spec["workflow_comparison"]?.objectValue else { return nil }
    var original = reference(saved.reference)
    original["mode"] = .string("workspace")
    var row = reference(saved.reference)
    row["kind"] = .string(saved.draft.kind.rawValue)
    row["title"] = .string(String(saved.draft.title.prefix(160)))
    row["method_variant"] = .string(method == comparison.baseline ? "baseline" : "candidate")
    row["plan"] = .object(reference(plan.reference))
    row["dataset"] = .object(reference(comparison.dataset))
    row["baseline_method"] = .object(reference(comparison.baseline))
    row["candidate_method"] = .object(reference(comparison.candidate))
    row["read_original"] = .object(original)
    row["complete_read"] = .bool(false)
    row["current_applicability_verified"] = .bool(false)
    var excerpts: AgentMcpJSONObject = [:]
    var truncated: [AgentMcpJSONValue] = []
    func addExcerpt(_ key: String, _ value: String) {
      excerpts[key] = .string(String(value.prefix(240)))
      if value.count > 240 { truncated.append(.string(key)) }
    }
    addExcerpt("environment", spec.string("environment"))
    for key in ["controlled_conditions", "quality_oracle", "cost_accounting", "selection_bias"] {
      addExcerpt(key, details.string(key))
    }
    if let result, let cases = result.measuredCases, !cases.isEmpty {
      row["result"] = .object(reference(result.reference))
      row["measured_state"] = .string(
        cases.contains { $0.purpose == "regression" && $0.state == "not_met" } ? "regressed" :
        cases.contains { $0.state == "incomplete" } ? "incomplete" :
        AgentCollaborationMeasuredCase.supportsRetention(cases) ? "passed" : "inconclusive")
      row["case_count"] = .int(Int64(cases.count))
      row["case_states"] = .object(Dictionary(grouping: cases, by: \.state).mapValues { .int(Int64($0.count)) })
      row["measurement_meaning"] = .string("arithmetic_on_observed_reports_not_independent_scientific_validation")
    } else if result != nil { return nil }
    if saved.draft.kind == .capabilityLesson, let lesson = saved.draft.body["capability_lesson"]?.objectValue {
      row["review_decision"] = .string(lesson.string("decision"))
      for key in ["rationale", "applies_when", "avoid_when"] { addExcerpt(key, lesson.string(key)) }
    }
    row["excerpts"] = .object(excerpts)
    row["truncated_fields"] = .array(truncated)
    return row
  }
}
