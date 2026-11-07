import Foundation

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
