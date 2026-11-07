import CryptoKit
import Foundation

extension AgentCollaborationGoalAssessmentPolicy {
  struct AssessmentIssue: Error {
    let path: String
    let code: String
    let expected: String
    let actual: String
    var syntaxValid: Bool = true
    var allowed: [String] = []

    var wire: AgentMcpJSONValue {
      .object(["path": .string(path), "code": .string(code), "expected": .string(expected),
        "actual": .string(actual), "detail": .string("")])
    }
  }

  static func parseAssessment(_ raw: String, limit: Int = 256_000) -> Result<Assessment, AssessmentIssue> {
    let data = Data(raw.utf8)
    func fail(_ path: String, _ code: String, _ expected: String, _ actual: String, syntax: Bool = true,
              allowed: [String] = []) -> Result<Assessment, AssessmentIssue> {
      .failure(.init(path: path, code: code, expected: expected, actual: actual, syntaxValid: syntax, allowed: allowed))
    }
    guard data.count <= limit else {
      return fail("$", "assessment_size_exceeded", "at most \(limit) UTF-8 bytes", "\(data.count) bytes", syntax: false)
    }
    guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
      return fail("$", "invalid_json", "one complete JSON object", "unparseable input", syntax: false)
    }
    guard json is [String: Any] else {
      return fail("$", "invalid_type", "assessment object", json is [Any] ? "array" : "JSON scalar")
    }
    func path(_ keys: [CodingKey]) -> String {
      keys.reduce("$") { value, key in
        if let index = key.intValue { return value + "[\(index)]" }
        return value + "." + key.stringValue
      }
    }
    let draft: Assessment
    do { draft = try JSONDecoder().decode(Assessment.self, from: data) }
    catch let DecodingError.keyNotFound(key, context) {
      return fail(path(context.codingPath + [key]), "required_field", "required assessment field", "missing")
    } catch let DecodingError.typeMismatch(type, context) {
      return fail(path(context.codingPath), "wrong_type", String(describing: type), "incompatible JSON type")
    } catch let DecodingError.valueNotFound(type, context) {
      return fail(path(context.codingPath), "required_value", String(describing: type), "null")
    } catch let DecodingError.dataCorrupted(context) {
      return fail(path(context.codingPath), "invalid_value", "value allowed by the assessment schema", "unsupported value")
    } catch {
      return fail("$", "invalid_assessment", "assessment object", "unable to decode")
    }
    let format = "galaxyssi.goal-assessment.v1"
    guard draft.format == format else {
      return fail("$.format", "unexpected_format", format, "different format", allowed: [format])
    }
    guard !draft.summary.isBlank else { return fail("$.summary", "expected_nonblank_text", "nonblank string", "blank") }
    guard !draft.criteria.isEmpty else { return fail("$.criteria", "expected_nonempty_criteria", "at least one criterion", "0 items") }
    var ids = Set<String>()
    for (index, criterion) in draft.criteria.enumerated() {
      let root = "$.criteria[\(index)]"
      guard !criterion.id.isBlank, ids.insert(criterion.id).inserted else {
        return fail(root + ".id", "expected_unique_id", "unique nonblank criterion ID", "blank or duplicate")
      }
      guard !criterion.requirement.isBlank else {
        return fail(root + ".requirement", "expected_nonblank_text", "nonblank string", "blank")
      }
      for (sourceIndex, source) in (criterion.required_observations ?? []).enumerated() {
        let sourcePath = root + ".required_observations[\(sourceIndex)]"
        guard RequiredObservation.allowedOrigins.contains(source.origin) else {
          return fail(sourcePath + ".origin", "unsupported_origin", "supported observation origin", "unsupported origin",
            allowed: RequiredObservation.allowedOrigins)
        }
        guard !source.tool.isBlank else {
          return fail(sourcePath + ".tool", "expected_nonblank_text", "nonblank tool ID", "blank")
        }
      }
      if let issue = criterion.validatorSchemaIssue {
        return fail(root + ".validator" + issue.path, "invalid_validator", issue.expected, issue.actual)
      }
    }
    return .success(draft)
  }

  static func preflight(_ raw: String, establishedContract: Bool) -> AgentMcpJSONObject {
    let checked = parseAssessment(raw, limit: 131_072)
    let issue: AssessmentIssue?
    switch checked {
    case .success: issue = nil
    case .failure(let failure): issue = failure
    }
    let valid = issue == nil
    let syntaxValid = issue?.syntaxValid ?? true
    let digest = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    var response: AgentMcpJSONObject = [
      "success": .bool(true), "status": .string("returned"), "schema_valid": .bool(valid),
      "json_syntax": .string(syntaxValid ? "valid" : (issue?.code == "assessment_size_exceeded" ? "unverified" : "invalid")),
      "json_valid": .bool(syntaxValid), "draft_sha256": .string(digest), "failure": issue?.wire ?? .null,
      "acceptance_contract_state": .string(establishedContract ? "established" : "not_established"),
      "validation_scope": .string("structure_only_not_admission_or_acceptance"),
      "checked": .array(["assessment_fields", "qualified_validator_specification"].map(AgentMcpJSONValue.string)),
      "not_checked": .array(["preserved_contract", "work_graph", "permissions", "evidence", "goal_acceptance"].map(AgentMcpJSONValue.string)),
      "committed": .bool(false), "goal_accepted": .bool(false), "assignment_completed": .bool(false),
      "next_action": .string(valid ? "Return the required assessment when ready; final admission and evidence checks still apply." :
        "Repair the reported field in the draft and check again; no plan or artifact was submitted.")
    ]
    if let issue {
      response["field_path"] = .string(issue.path)
      response["reason"] = .string(issue.code)
      if !issue.allowed.isEmpty { response["allowed_values"] = .array(issue.allowed.map(AgentMcpJSONValue.string)) }
    }
    return response
  }
}
