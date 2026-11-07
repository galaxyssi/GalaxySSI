import Foundation

struct AgentCollaborationTypedRecordValidation: Error {
  let problem: AgentMcpJSONObject

  static let kinds: Set<String> = [
    "capability_gap", "innovation", "experiment_plan", "experiment_result", "capability_lesson",
    "learning_agenda", "transfer_study", "executable_tool", "tool_test_plan", "environment_model", "task_environment_model",
    "action_forecast", "numeric_model_trial", "prediction_outcome", "workflow_method", "workflow_selection_rule",
    "team_exchange", "failure_experience", "innovation_opportunity"
  ]

  static let guidance = "Typed research records keep their substantive data in body.<kind>. " +
    "body.content is optional for these records; when supplied it must be a nonempty string. " +
    "Do not duplicate source, tests or structured review in prose. This does not relax documentary or final-delivery requirements."

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
