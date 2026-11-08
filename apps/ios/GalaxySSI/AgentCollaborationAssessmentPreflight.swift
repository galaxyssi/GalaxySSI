import CryptoKit
import Foundation

extension AgentCollaborationGoalAssessmentPolicy {
  static let assessmentRepairMode = "assessment_repair"
  static let assessmentDraftLimit = 131_072

  struct RejectedAssessment: Codable, Equatable {
    let bytes: Data
    let contractSubmission: Bool

    var sha256: String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    var text: String { String(decoding: bytes, as: UTF8.self) }

    func feedback(contract: [Criterion]) -> AgentMcpJSONObject {
      var result = repairFeedback(text, contract: contract, contractSubmission: contractSubmission)
      result["draft_retained"] = .bool(true)
      result["draft_read"] = .object(["mode": .string(assessmentRepairMode), "draft_sha256": .string(sha256)])
      if bytes.count <= 2_000 { result["draft"] = .string(text) }
      return result
    }
  }

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
    func received(_ keys: [CodingKey]) -> String {
      var current: Any? = json
      for key in keys {
        if let index = key.intValue, let array = current as? [Any], array.indices.contains(index) {
          current = array[index]
        } else {
          current = (current as? [String: Any])?[key.stringValue]
        }
      }
      guard let current else { return "missing" }
      if current is NSNull { return "null" }
      if current is [String: Any] { return "object" }
      if let array = current as? [Any] { return "array(\(array.count) items)" }
      return String(String(describing: current).prefix(160))
    }
    func allowed(_ field: String) -> [String] {
      switch field {
      case "$.decision": return ["continue", "achieved", "blocked"]
      default:
        guard field.hasPrefix("$.criteria[") else { return [] }
        if field.hasSuffix("].status") { return ["met", "open"] }
        if field.hasSuffix("].verification") { return ["documentary", "computational", "physical"] }
        if field.hasSuffix("].evidence_kind") { return ["observed", "simulation", "proposal"] }
        return []
      }
    }
    let draft: Assessment
    do { draft = try JSONDecoder().decode(Assessment.self, from: data) }
    catch let DecodingError.keyNotFound(key, context) {
      return fail(path(context.codingPath + [key]), "required_field", "required assessment field", "missing")
    } catch let DecodingError.typeMismatch(type, context) {
      return fail(path(context.codingPath), "wrong_type", String(describing: type), received(context.codingPath))
    } catch let DecodingError.valueNotFound(type, context) {
      return fail(path(context.codingPath), "required_value", String(describing: type), "null")
    } catch let DecodingError.dataCorrupted(context) {
      let field = path(context.codingPath)
      let values = allowed(field)
      return fail(field, "invalid_value", values.isEmpty ? "value allowed by the assessment schema" : values.joined(separator: ", "),
        received(context.codingPath), allowed: values)
    } catch {
      return fail("$", "invalid_assessment", "assessment object", "unable to decode")
    }
    let format = "galaxyssi.goal-assessment.v1"
    guard draft.format == format else {
      return fail("$.format", "unexpected_format", format, String(draft.format.prefix(160)), allowed: [format])
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
          return fail(sourcePath + ".origin", "unsupported_origin", "supported observation origin", String(source.origin.prefix(160)),
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

  static func newDesktopBindingIssue(_ proposed: [Criterion], preserving contract: [Criterion]) -> AssessmentIssue? {
    let allowed = AgentDesktopToolEvidenceWire.RecordedEvent.acceptanceTools
    let saved = Dictionary(contract.map { ($0.id, Set($0.required_observations ?? [])) },
      uniquingKeysWith: { first, _ in first })
    for (index, criterion) in proposed.enumerated() {
      for (sourceIndex, binding) in (criterion.required_observations ?? []).enumerated()
      where binding.origin == "desktop_codex_tool" && saved[criterion.id]?.contains(binding) != true {
        if !allowed.contains(binding.tool) {
          return .init(path: "$.criteria[\(index)].required_observations[\(sourceIndex)].tool",
            code: "unknown_recorded_tool", expected: "a recorded Desktop output family, not a callable tool name",
            actual: String(decoding: binding.tool.utf8.prefix(160), as: UTF8.self), allowed: allowed)
        }
      }
    }
    return nil
  }

  static func preflight(_ raw: String, establishedContract: Bool,
                        preserving contract: [Criterion]? = nil) -> AgentMcpJSONObject {
    let checked = parseAssessment(raw, limit: 131_072)
    let issue: AssessmentIssue?
    switch checked {
    case .success(let assessment):
      issue = (contract != nil || !establishedContract)
        ? newDesktopBindingIssue(assessment.criteria, preserving: contract ?? []) : nil
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
      "checked": .array((["assessment_fields", "qualified_validator_specification"] +
        (contract != nil || !establishedContract ? ["new_desktop_recorded_event_bindings"] : [])).map(AgentMcpJSONValue.string)),
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

  static func repairFeedback(_ raw: String, contract: [Criterion], contractSubmission: Bool) -> AgentMcpJSONObject {
    var result = preflight(raw, establishedContract: !contract.isEmpty, preserving: contract)
    result["contract_state"] = .string(contract.isEmpty ? "initial_criteria_pending" : "established")
    result["established_criteria_count"] = .int(Int64(contract.count))
    result["next_action"] = .string(contract.isEmpty
      ? "No criteria have been established yet; an empty contract is not corruption. Repair the draft, define criteria from the pinned goal and establish them before dispatch. Rejected assignments must not run."
      : "Preserve every established requirement, validator and required source. Read the pinned criteria and repair the draft; rejected assignments must not run.")
    if case .success(let draft) = parseAssessment(raw, limit: assessmentDraftLimit) {
      var issue = newDesktopBindingIssue(draft.criteria, preserving: contract)
      if issue == nil, !contract.isEmpty {
        let byID = Dictionary(uniqueKeysWithValues: draft.criteria.enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        for original in contract {
          guard let (index, current) = byID[original.id] else {
            issue = .init(path: "$.criteria", code: "established_criterion_missing", expected: "include the pinned criterion",
              actual: "missing " + original.id)
            break
          }
          let root = "$.criteria[\(index)]"
          if current.requirement != original.requirement {
            issue = .init(path: root + ".requirement", code: "established_criterion_changed",
              expected: "preserve the pinned requirement", actual: String(current.requirement.prefix(160)))
          } else if current.verification != original.verification {
            issue = .init(path: root + ".verification", code: "established_verification_changed",
              expected: original.verification.rawValue, actual: current.verification.rawValue)
          } else if current.validator != original.validator {
            issue = .init(path: root + ".validator", code: "established_validator_changed",
              expected: "preserve the pinned validator", actual: current.validator == nil ? "missing" : "different validator")
          } else if !Set(original.required_observations ?? []).isSubset(of: Set(current.required_observations ?? [])) {
            issue = .init(path: root + ".required_observations", code: "established_sources_missing",
              expected: "preserve every pinned observation origin and tool", actual: "one or more bindings removed",
              allowed: RequiredObservation.allowedOrigins)
          }
          if issue != nil { break }
        }
      }
      if issue == nil, contractSubmission, initialContract(raw) == nil {
        if draft.decision != .continue {
          issue = .init(path: "$.decision", code: "initial_decision", expected: "continue", actual: draft.decision.rawValue)
        } else if !draft.work.isEmpty || !draft.blockers.isEmpty || draft.recruit?.isEmpty == false {
          let field = !draft.work.isEmpty ? "work" : (!draft.blockers.isEmpty ? "blockers" : "recruit")
          issue = .init(path: "$." + field, code: "initial_contract_only", expected: "no assignments, blockers or recruitment", actual: "nonempty array")
        } else if let index = draft.criteria.firstIndex(where: { $0.status != .open }) {
          issue = .init(path: "$.criteria[\(index)].status", code: "initial_criterion_open", expected: "open", actual: "met")
        } else {
          issue = .init(path: "$.criteria", code: "initial_contract_only", expected: "bounded open criteria without evidence or reviews", actual: "criterion is not eligible for initial registration")
        }
      }
      if issue == nil, contractSubmission, !contract.isEmpty, initialContract(raw) != contract {
        issue = .init(path: "$.criteria", code: "established_contract_changed",
          expected: "the exact pinned contract, without additions or reordering", actual: "different criterion list or bindings")
      }
      if let issue {
        result["failure"] = issue.wire
        result["field_path"] = .string(issue.path)
        result["reason"] = .string(issue.code)
        if !issue.allowed.isEmpty { result["allowed_values"] = .array(issue.allowed.map(AgentMcpJSONValue.string)) }
        if issue.code == "unknown_recorded_tool" {
          result["next_action"] = .string("Use a supported recorded Desktop event family, not a callable name. No contract or work was admitted. Do not execute a command to discover its receipt name or rewrite an existing binding.")
        }
      }
    }
    return result
  }
}
