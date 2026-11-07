import Foundation

struct AgentCollaborationExperimentResultFeedback: Error {
  static let planPath = "/body/experiment_result/plan"
  static let guidance = "experiment_result records a preregistered baseline/candidate comparison, not any tool or search result. " +
    "Use an existing applicable experiment_plan and its original measurements. An ordinary artifact may preserve " +
    "observations without claiming measured improvement. If the assignment requires an incompatible record, request " +
    "coordinator assistance to correct the work specification while preserving the goal and verification criteria. " +
    "Do not invent or backdate a plan, repeat completed operations just to fill this type, or lower acceptance requirements. " +
    "An observational artifact does not qualify as experiment_result or authorize capability retention."

  let problem: AgentMcpJSONObject

  // Keep plan lookup failures out of the legacy invalid-draft catch paths.
  struct StorageFailure: Error { let underlying: Error }

  static func registeredPlan(in draft: AgentCollaborationResearchDraft, scope: AgentCollaborationToolEvidenceScope,
                             load: (String) throws -> AgentCollaborationResearchRevision?)
    throws -> AgentCollaborationResearchRevision {
    guard let result = draft.body["experiment_result"]?.objectValue else {
      throw issue("experiment_result_body_invalid", path: "/body/experiment_result", expected: .string("object"),
        actual: shape(draft.body["experiment_result"]), draft: draft)
    }
    let raw = result["plan"]
    guard let object = raw?.objectValue else {
      throw issue(raw == nil ? "experiment_plan_reference_required" : "experiment_plan_reference_invalid",
        expected: .string("exact saved experiment_plan reference: object_id, integer revision, sha256"),
        actual: shape(raw), draft: draft)
    }
    let referenceFacts = Dictionary(uniqueKeysWithValues: ["object_id", "revision", "sha256"].map {
      ($0, fieldFact(object[$0]))
    })
    let digest = AgentMcpJSONValue.string("64 lowercase hexadecimal characters")
    for field in ["object_id", "sha256"] {
      guard let value = object[field]?.strictStringValue, validDigest(value) else {
        throw issue(field == "object_id" ? "record_object_id_invalid" : "record_digest_invalid",
          path: planPath + "/" + field, expected: digest, actual: fieldFact(object[field]), draft: draft,
          reference: referenceFacts, component: "WorkspaceRecordValidator")
      }
    }
    guard case .int(let version)? = object["revision"], version > 0 else {
      throw issue("record_revision_invalid", path: planPath + "/revision", expected: .string("positive integer"),
        actual: fieldFact(object["revision"]), draft: draft, reference: referenceFacts, component: "WorkspaceRecordValidator")
    }
    guard let ref = AgentCollaborationExperimentPlanIntake.reference(raw) else {
      throw issue("experiment_plan_reference_invalid", expected: .string("only object_id, revision and sha256"),
        actual: .string("unexpected fields"), draft: draft)
    }
    guard let plan = try load(ref.objectId), plan.reference.objectId == ref.objectId,
          plan.turnId != scope.turnId || (plan.runId == scope.runId && plan.authorId == scope.memberId) else {
      throw issue("record_unavailable", expected: .string("visible saved experiment_plan"),
        actual: .string("missing or isolated"), draft: draft, reference: object, component: "WorkspaceRecordValidator")
    }
    guard plan.reference.revision == ref.revision else {
      throw issue("record_revision_mismatch", path: planPath + "/revision", expected: .int(plan.reference.revision),
        actual: .int(ref.revision), draft: draft, reference: object, component: "WorkspaceRecordValidator")
    }
    guard plan.reference.sha256 == ref.sha256 else {
      throw issue("record_digest_mismatch", path: planPath + "/sha256", expected: .string(plan.reference.sha256),
        actual: .string(ref.sha256), draft: draft, reference: object, component: "WorkspaceRecordValidator")
    }
    guard plan.draft.kind == .experimentPlan else {
      throw issue("record_kind_mismatch", path: planPath + "/kind", expected: .array([.string("experiment_plan")]),
        actual: .string(plan.draft.kind.rawValue), draft: draft, reference: object, component: "WorkspaceRecordValidator")
    }
    guard draft.parents.contains(ref) else {
      throw issue("experiment_plan_parent_required", path: "/parents", expected: .object(object),
        actual: .string("exact plan parent absent"), draft: draft, reference: object)
    }
    return plan
  }

  private static func issue(_ code: String, path: String = AgentCollaborationExperimentResultFeedback.planPath,
                            expected: AgentMcpJSONValue,
                            actual: AgentMcpJSONValue, draft: AgentCollaborationResearchDraft,
                            reference: AgentMcpJSONObject? = nil, component: String = "ExperimentResultValidator") -> Self {
    var detail: AgentMcpJSONObject = [
      "code": .string(code), "path": .string(path), "component": .string(component),
      "draft_id": .string(draft.id), "expected": expected, "actual": actual,
      "record_contract": .object([
        "kind": .string("experiment_result"), "purpose": .string("preregistered_baseline_candidate_comparison"),
        "required_dependency_kind": .string("experiment_plan"), "registration_before_measurements_required": .bool(true),
        "rules_topic": .string("foundation"), "automatic_conversion": .bool(false), "guidance": .string(guidance)
      ])
    ]
    if let reference { detail["reference"] = .object(reference) }
    return Self(problem: detail)
  }

  private static func validDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func shape(_ value: AgentMcpJSONValue?) -> AgentMcpJSONValue {
    switch value {
    case nil: return .string("absent")
    case .some(.null): return .string("null")
    case .some(.object): return .string("object")
    default: return .string("not an object")
    }
  }

  private static func fieldFact(_ value: AgentMcpJSONValue?) -> AgentMcpJSONValue {
    switch value {
    case .some(.string(let string)) where string.utf8.count <= 80: return .string(string)
    case .some(.int), .some(.double), .some(.bool): return value ?? .null
    default: return shape(value)
    }
  }
}
