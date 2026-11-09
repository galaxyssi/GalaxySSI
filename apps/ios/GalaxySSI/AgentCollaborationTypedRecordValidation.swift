import Foundation

struct AgentCollaborationTypedRecordValidation: Error {
  let problem: AgentMcpJSONObject

  static let kinds: Set<String> = [
    "capability_gap", "innovation", "experiment_plan", "experiment_result", "capability_lesson",
    "learning_agenda", "transfer_study", "executable_tool", "tool_test_plan", "tool_release", "tool_test_comparison",
    "environment_model", "task_environment_model",
    "action_forecast", "numeric_model_trial", "prediction_outcome", "workflow_method", "workflow_selection_rule",
    "team_exchange", "failure_experience", "innovation_opportunity"
  ]

  static let guidance = "Typed research records keep their substantive data in body.<kind>. " +
    "body.content is optional for these records; when supplied it must be a nonempty string. " +
    "Do not duplicate source, tests or structured review in prose. This does not relax documentary or final-delivery requirements."

  private static let toolKinds = ["executable_tool", "tool_test_plan", "tool_release", "tool_test_comparison"]
  static let toolGuidance = "Publish workspace.kind=executable_tool with body.executable_tool, then kind=tool_test_plan with body.tool_test_plan and its exact executable_tool parent. Generic artifact or experiment_plan records do not register a tool. Inspect record_validation and recall evolution_rules topic=tools before retrying; do not rerun effects."

  static func notice(_ draft: AgentCollaborationResearchDraft) -> AgentMcpJSONObject? {
    let fields = toolKinds.filter { $0 != draft.kind.rawValue && draft.body[$0] != nil }
    guard !fields.isEmpty else { return nil }
    return ["code": .string("typed_payload_not_registered"), "payload_fields": .array(fields.map(AgentMcpJSONValue.string)),
      "actual_kind": .string(draft.kind.rawValue), "executable_registration": .bool(false), "guidance": .string(toolGuidance)]
  }

  static func toolIssue(_ code: String, path: String, expected: AgentMcpJSONValue, actual: AgentMcpJSONValue,
      reference: AgentCollaborationResearchReference? = nil) -> Self {
    var detail: AgentMcpJSONObject = ["code": .string(code), "path": .string(path),
      "component": .string("WorkspaceRecordValidator"), "expected": expected, "actual": actual,
      "guidance": .string(toolGuidance)]
    if let reference {
      detail["reference"] = .object(["object_id": .string(String(reference.objectId.prefix(64))),
        "revision": .int(reference.revision), "sha256": .string(String(reference.sha256.prefix(64)))])
    }
    return Self(problem: detail)
  }

  static func toolReference(_ value: AgentMcpJSONValue?, path: String) throws -> AgentCollaborationResearchReference {
    if let ref = AgentCollaborationSavedToolTest.reference(value) { return ref }
    let input = value?.objectValue
    if let input, Set(input.keys) == ["object_id", "revision", "sha256"] {
      if case .int(let revision)? = input["revision"], revision > 0 {
        for field in ["object_id", "sha256"] {
          guard let digest = input[field]?.strictStringValue, AgentCollaborationCandidateRecall.validDigest(digest) else {
            throw toolIssue(field == "object_id" ? "record_object_id_invalid" : "record_digest_invalid",
              path: path + "/" + field, expected: .string("64 lowercase hexadecimal characters"),
              actual: .string("invalid digest"))
          }
        }
      } else {
        throw toolIssue("record_revision_invalid", path: path + "/revision", expected: .string("positive integer"),
          actual: .string("missing or invalid integer"))
      }
    }
    throw toolIssue("record_reference_invalid", path: path, expected: .string("only object_id, revision and sha256"),
      actual: .string(input == nil ? shape(value) : "unexpected fields"))
  }

  static func requireToolRecord(_ ref: AgentCollaborationResearchReference,
      kind: AgentCollaborationResearchDraft.Kind? = nil, path: String,
      read: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?,
      isCurrent: ((AgentCollaborationResearchReference) throws -> Bool)? = nil) throws -> AgentCollaborationResearchRevision {
    guard let record = try read(ref) else {
      throw toolIssue("record_unavailable", path: path, expected: .string("accessible saved record"),
        actual: .string("missing or isolated"), reference: ref)
    }
    guard record.reference.objectId == ref.objectId, record.reference.revision == ref.revision else {
      throw toolIssue("record_identity_mismatch", path: path, expected: .string("exact requested identity"),
        actual: .string("different identity"), reference: ref)
    }
    guard record.reference.sha256 == ref.sha256 else {
      throw toolIssue("record_digest_mismatch", path: path + "/sha256", expected: .string(record.reference.sha256),
        actual: .string(ref.sha256), reference: ref)
    }
    if let kind, record.draft.kind != kind {
      throw toolIssue("record_kind_mismatch", path: path + "/kind", expected: .string(kind.rawValue),
        actual: .string(record.draft.kind.rawValue), reference: ref)
    }
    if let isCurrent, try !isCurrent(ref) {
      throw toolIssue("record_not_current", path: path + "/revision", expected: .string("current version not being changed"),
        actual: .int(ref.revision), reference: ref)
    }
    return record
  }

  static func validate(_ draft: AgentCollaborationResearchDraft) throws {
    let kind = draft.kind.rawValue
    guard kinds.contains(kind) else { return }
    guard draft.body[kind]?.objectValue != nil else {
      throw issue("typed_body_required", path: "/body/" + kind,
        expected: "object matching workspace.kind=" + kind, actual: shape(draft.body[kind]), draft: draft)
    }
    guard let content = draft.body["content"] else { return }
    guard let text = content.strictStringValue, !text.isBlank else {
      throw issue("record_content_invalid", path: "/body/content",
        expected: "nonempty string when supplied; omit redundant prose for typed evolution records",
        actual: content == .null ? "null" : content.strictStringValue == nil ? "not a string" : "blank", draft: draft)
    }
  }

  private static func shape(_ value: AgentMcpJSONValue?) -> String {
    guard let value else { return "absent" }
    return value == .null ? "null" : "not an object"
  }

  private static func issue(_ code: String, path: String, expected: String, actual: String,
                            draft: AgentCollaborationResearchDraft) -> Self {
    Self(problem: [
      "code": .string(code), "path": .string(path), "component": .string("WorkspaceRecordValidator"),
      "draft_id": .string(String(draft.id.prefix(160))), "expected": .string(expected), "actual": .string(actual),
      "record_contract": .object(["kind": .string(draft.kind.rawValue), "rules_topic": .string("foundation"),
        "body_preserved": .bool(true), "automatic_conversion": .bool(false), "guidance": .string(guidance)])
    ])
  }
}
