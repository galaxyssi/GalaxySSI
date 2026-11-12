import CryptoKit
import Foundation

enum AgentCollaborationExecutableAcceptance {
  static let id = "executable_tool_cases.v1"
  static let requirement = "Verify a saved executable tool on all preserved test cases in the declared environment; this does not establish general correctness, reference truth or physical validity."
  private static let metadata = ["environment", "purpose", "oracle_basis", "coverage_gaps"]
  static let guidance = """
    For finite executable tool acceptance use verification=computational, evidence_kind=observed and the exact requirement:
    "\(requirement)"
    Pin validator {id:"\(id)",environment,purpose,oracle_basis,coverage_gaps,cases:[{id,purpose,reason,input,expected}]}.
    Keep target and regression cases, and copy the contract into the registered tool_test_plan. Test with the existing iOS runtime.
    An independent reviewer reads the complete original test observation and publishes tool_release. Save delivery computation
    {validator_id:"\(id)",tool_release:{object_id,revision,sha256}}; both delivery and acceptance_review cite the original observation.
    The host rechecks the exact execution without running the tool again. This does not qualify Desktop shell prose, a prior
    goal's receipt, reference truth, generalization, or a physical experiment.
    """

  static func issue(_ spec: AgentMcpJSONObject) -> AgentCollaborationNumericTrial.ValidatorIssue? {
    typealias Issue = AgentCollaborationNumericTrial.ValidatorIssue
    guard spec["id"] == .string(id), Set(spec.keys) == Set(metadata + ["id", "cases"]) else {
      return Issue(path: "", expected: "exact executable test contract fields", actual: "missing or extra field")
    }
    for name in metadata {
      guard let value = spec[name]?.strictStringValue, !value.isBlank, value.utf8.count <= 8_192 else {
        return Issue(path: "." + name, expected: "nonblank text within 8192 bytes", actual: "invalid text")
      }
    }
    guard let cases = spec["cases"]?.arrayValue, (2...32).contains(cases.count) else {
      return Issue(path: ".cases", expected: "2 to 32 registered cases", actual: "invalid case count")
    }
    var ids = Set<String>(), purposes = Set<String>()
    for (index, raw) in cases.enumerated() {
      guard let row = raw.objectValue, Set(row.keys) == ["id", "purpose", "reason", "input", "expected"],
            let id = row["id"]?.strictStringValue, !id.isBlank, id.utf8.count <= 160, ids.insert(id).inserted,
            let reason = row["reason"]?.strictStringValue, !reason.isBlank, reason.utf8.count <= 8_192,
            let purpose = row["purpose"]?.strictStringValue, ["target", "edge", "regression"].contains(purpose),
            row["input"]?.objectValue != nil, row["expected"] != nil else {
        return Issue(path: ".cases[\(index)]", expected: "unique id, target/edge/regression purpose, reason, JSON object input and expected JSON",
          actual: "invalid preserved case")
      }
      purposes.insert(purpose)
    }
    guard purposes.isSuperset(of: ["target", "regression"]) else {
      return Issue(path: ".cases", expected: "target and regression cases", actual: "missing required case purpose")
    }
    return nil
  }

  static func matches(spec: AgentMcpJSONObject, plan: AgentCollaborationResearchRevision) -> Bool {
    guard issue(spec) == nil, plan.draft.kind == .toolTestPlan,
          let saved = plan.draft.body["tool_test_plan"]?.objectValue else { return false }
    return (metadata + ["cases"]).allSatisfy { name in
      guard let left = spec[name], let right = saved[name] else { return false }
      return AgentCollaborationSavedToolTest.difference(left, right, at: "") == nil
    }
  }

  static func releaseReference(_ computation: AgentMcpJSONObject) -> AgentCollaborationResearchReference? {
    guard computation["validator_id"] == .string(id), Set(computation.keys) == ["validator_id", "tool_release"]
    else { return nil }
    return AgentCollaborationSavedToolTest.reference(computation["tool_release"])
  }
}

enum AgentCollaborationSavedToolRelease {
  struct Review {
    let plan: AgentCollaborationResearchReference
    let observation: AgentMcpJSONObject

    init?(_ draft: AgentCollaborationResearchDraft) {
      let fields = ["review", "applies_when", "avoid_when", "limitations", "authorization_boundary"]
      guard draft.kind == .toolRelease, draft.objectId == nil, draft.baseRevision == 0,
            let spec = draft.body["tool_release"]?.objectValue,
            Set(spec.keys) == Set(fields + ["tool_test_plan", "observation", "unresolved"]),
            fields.allSatisfy({ key in
              guard let text = spec[key]?.strictStringValue else { return false }
              return !text.isBlank && text.utf8.count <= 8_192
            }),
            spec["unresolved"] == .array([]),
            let plan = AgentCollaborationSavedToolTest.reference(spec["tool_test_plan"]), draft.parents.contains(plan),
            var observation = spec["observation"]?.objectValue,
            observation.removeValue(forKey: "origin") == .string("ios_native_tool"),
            Set(observation.keys) == ["evidence_id", "sha256"],
            ["evidence_id", "sha256"].allSatisfy({ AgentCollaborationCandidateRecall.validDigest(observation.string($0)) })
      else { return nil }
      self.plan = plan
      self.observation = observation
    }
  }

  static func receipt(review: Review, plan: AgentCollaborationResearchRevision,
      tool: AgentCollaborationResearchRevision, original: AgentCollaborationNativeToolObservation,
      reviewerIdentity: String, authorIdentity: String) -> AgentMcpJSONObject? {
    guard !reviewerIdentity.isBlank, !authorIdentity.isBlank, reviewerIdentity != authorIdentity,
          plan.reference == review.plan,
          let evaluation = AgentCollaborationSavedToolTest.verifyOriginal(original, plan: plan, tool: tool),
          evaluation["passed"] == .bool(true),
          let runtime = evaluation["runtime"]?.objectValue,
          let digest = original.input["source_sha256"] else { return nil }
    return [
      "state": .string(AgentCollaborationCapabilityPage.releaseState), "tool_test_plan": .object(AgentCollaborationCandidateRecall.reference(plan.reference)),
      "executable_tool": .object(AgentCollaborationCandidateRecall.reference(tool.reference)),
      "source_sha256": digest, "tested_runtime": .object(runtime), "observation": .object(review.observation),
      "grants_permissions": .bool(false), "general_correctness_proven": .bool(false)
    ]
  }
}

enum AgentCollaborationSavedToolTest {
  static let reportFormat = "galaxyssi.executable-tool-output.v1"
  static let maximumReportBytes = 96 * 1_024

  static func firstProblem(_ evaluation: AgentMcpJSONObject?) -> AgentMcpJSONValue {
    guard let item = evaluation?["problems"]?.arrayValue?.first?.objectValue else { return .null }
    let fields = ["code", "path", "case_id"]
    return .object(item.filter { fields.contains($0.key) }.mapValues { value in
      .string(String((value.strictStringValue ?? "").prefix(200)))
    })
  }

  static func boundCapture(_ output: AgentMcpJSONObject, stdoutLimit: Int = maximumReportBytes,
                           stderrLimit: Int = 16 * 1_024) -> AgentMcpJSONObject {
    var result = output
    let previouslyTruncated = output["output_truncated"] == .bool(true)
    var truncated = previouslyTruncated
    for (stream, limit) in [("stdout", stdoutLimit), ("stderr", stderrLimit)] {
      guard let text = output[stream]?.strictStringValue else { continue }
      let count = Int64(text.utf16.count)
      let countKey = stream + "_original_chars"
      let flagKey = stream + "_truncated"
      let recorded: Int64?
      if case .int(let value)? = output[countKey], value >= 0 { recorded = value } else { recorded = nil }
      let knownTruncation = output[flagKey] == .bool(true) || (recorded.map { $0 > count } ?? false)
      if let recorded { result[countKey] = .int(max(recorded, count)) }
      else if !previouslyTruncated && !knownTruncation { result[countKey] = .int(count) }
      let bytes = text.utf8
      let clipped = bytes.count > limit
      if clipped {
        var end = bytes.index(bytes.startIndex, offsetBy: max(0, limit))
        while end != bytes.startIndex, (bytes[end] & 0xC0) == 0x80 { bytes.formIndex(before: &end) }
        result[stream] = .string(String(decoding: bytes[..<end], as: UTF8.self))
      }
      result[flagKey] = .bool(knownTruncation || clipped)
      truncated = truncated || knownTruncation || clipped
    }
    if result["output_truncated"] == nil || result["output_truncated"]?.boolValue != nil {
      result["output_truncated"] = .bool(truncated)
    }
    return result
  }

  static func captureProblem(_ output: AgentMcpJSONObject) -> AgentMcpJSONObject? {
    guard let stdout = output["stdout"]?.strictStringValue else {
      return problem("report_stdout_required", "/stdout", expected: .string("text"), actual: describe(output["stdout"]))
    }
    for stream in ["stdout", "stderr"] {
      let text = output[stream]?.strictStringValue ?? ""
      let count = Int64(text.utf16.count)
      let field = stream + "_original_chars"
      if let original = output[field] {
        guard case .int(let known) = original, known >= 0 else {
          return problem("invalid_capture_count", "/" + field, expected: .string("nonnegative UTF-16 count"), actual: describe(original))
        }
        if known > count {
          return problem("report_" + stream + "_truncated", "/" + stream, expected: .int(known), actual: .int(count))
        }
      }
      if output[stream + "_truncated"] == .bool(true) {
        return problem("report_" + stream + "_truncated", "/" + stream,
          expected: .string("complete capture"), actual: .int(count))
      }
    }
    if output["output_truncated"] != nil && output["output_truncated"] != .bool(false) {
      return problem("report_capture_truncated", "/output_truncated", expected: .bool(false),
        actual: describe(output["output_truncated"]))
    }
    if stdout.utf8.count > maximumReportBytes {
      return problem("report_stdout_too_large", "/stdout", expected: .int(Int64(maximumReportBytes)), actual: .int(Int64(stdout.utf8.count)))
    }
    return nil
  }

  private static func problem(_ code: String, _ path: String, expected: AgentMcpJSONValue,
                              actual: AgentMcpJSONValue) -> AgentMcpJSONObject {
    ["code": .string(code), "path": .string(path), "expected": expected, "actual": actual, "cause": .string("not_diagnosed")]
  }

  private static func describe(_ value: AgentMcpJSONValue?) -> AgentMcpJSONValue {
    guard let value else { return .string("missing") }
    switch value {
    case .string(let text): return .string(String(text.prefix(160)))
    case .object, .array: return .string(type(value))
    default: return value
    }
  }

  private static func type(_ value: AgentMcpJSONValue) -> String {
    switch value {
    case .null: return "null"
    case .string: return "string"
    case .int, .double: return "number"
    case .bool: return "boolean"
    case .object: return "object"
    case .array: return "array"
    }
  }

  static func boundPrepared(_ original: AgentCollaborationNativeToolObservation,
      plan: AgentCollaborationResearchRevision, tool: AgentCollaborationResearchRevision) -> Prepared? {
    let result = original.result
    guard result.provenance.location == .application,
          result.provenance.executorId == AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId,
          case .int(let timeout)? = original.input["timeout_ms"],
          let prepared = prepare(plan: plan, tool: tool, timeoutMillis: timeout),
          original.input == prepared.evidenceInput, prepared.matchesReceipt(result) else { return nil }
    return prepared
  }

  static func verifyOriginal(_ original: AgentCollaborationNativeToolObservation,
      plan: AgentCollaborationResearchRevision, tool: AgentCollaborationResearchRevision) -> AgentMcpJSONObject? {
    let result = original.result
    guard let registered = plan.registeredAtMillis, registered > 0,
          result.receipt.startedAtEpochMillis >= registered,
          result.receipt.finishedAtEpochMillis >= result.receipt.startedAtEpochMillis,
          !result.receipt.replayed, result.receipt.originalInvocationId == nil,
          let prepared = boundPrepared(original, plan: plan, tool: tool) else { return nil }
    let version = original.evaluation?["diagnostics_version"]
    guard version == nil || version == .int(2) else { return nil }
    let evaluation = prepared.evaluate(result, detailed: version != nil)
    guard evaluation["runtime"] != nil, evaluation["checks"] != nil, evaluation == original.evaluation else { return nil }
    return evaluation
  }

  struct Comparison {
    struct Side {
      let plan: AgentCollaborationResearchReference
      let observation: AgentMcpJSONObject

      init?(_ value: AgentMcpJSONValue?) {
        guard let spec = value?.objectValue, Set(spec.keys) == ["tool_test_plan", "observation"],
              let plan = reference(spec["tool_test_plan"]),
              let observation = spec["observation"]?.objectValue, Set(observation.keys) == ["evidence_id", "sha256"],
              ["evidence_id", "sha256"].allSatisfy({
                guard let value = observation[$0]?.strictStringValue else { return false }
                return isDigest(value)
              }) else { return nil }
        self.plan = plan
        self.observation = observation
      }
    }

    let baseline: Side
    let candidate: Side
    var sides: [Side] { [baseline, candidate] }

    init?(_ draft: AgentCollaborationResearchDraft) {
      let fields = ["purpose", "interpretation", "limitations"]
      guard draft.kind == .toolTestComparison, draft.objectId == nil, draft.baseRevision == 0,
            draft.resolves?.isEmpty != false,
            let spec = draft.body["tool_test_comparison"]?.objectValue,
            Set(spec.keys) == Set(fields + ["baseline", "candidate"]),
            fields.allSatisfy({
              guard let value = spec[$0]?.strictStringValue else { return false }
              return !value.isBlank && value.utf8.count <= 8_192
            }),
            let before = Side(spec["baseline"]), let after = Side(spec["candidate"]),
            before.observation["evidence_id"] != after.observation["evidence_id"],
            Set(draft.parents) == Set([before.plan, after.plan]) else { return nil }
      baseline = before
      candidate = after
    }

    struct Observed {
      let plan: AgentCollaborationResearchRevision
      let tool: AgentCollaborationResearchRevision
      let original: AgentCollaborationNativeToolObservation
    }

    struct LineageSide {
      let name: String
      let plan: AgentCollaborationResearchReference
      let tool: AgentCollaborationResearchReference
    }

    func lineage(_ receipt: AgentMcpJSONObject) -> [LineageSide]? {
      guard receipt["state"] == .string("observed_paired_case_outcomes") else { return nil }
      var output: [LineageSide] = []
      for (name, declared) in zip(["baseline", "candidate"], sides) {
        guard let saved = receipt[name]?.objectValue,
              reference(saved["tool_test_plan"]) == declared.plan,
              saved["observation"]?.objectValue == declared.observation,
              let tool = reference(saved["executable_tool"]) else { return nil }
        output.append(.init(name: name, plan: declared.plan, tool: tool))
      }
      return output
    }

    func preservesFrozenObservations(_ record: AgentCollaborationResearchRevision) -> Bool {
      guard let receipt = record.toolTestComparison, lineage(receipt) != nil,
            let citations = record.draft.observations, citations.count == sides.count,
            let reads = record.frozenNativeReads, reads.count == sides.count else { return false }
      return sides.allSatisfy { side in
        let id = side.observation.string("evidence_id"), hash = side.observation.string("sha256")
        return citations.contains { $0["origin"] == .string("ios_native_tool") &&
          $0.string("evidence_id") == id && $0.string("sha256") == hash } &&
          reads.contains { $0.evidenceId == id && $0.sha256 == hash && $0.totalCharacters > 0 }
      }
    }

    func evaluate(baseline before: Observed, candidate after: Observed) -> AgentMcpJSONObject? {
      guard before.plan.reference == baseline.plan, after.plan.reference == candidate.plan,
            before.original.conversationId == after.original.conversationId,
            before.original.runId == after.original.runId, before.original.turnId == after.original.turnId,
            let oldSpec = before.plan.draft.body["tool_test_plan"]?.objectValue,
            let newSpec = after.plan.draft.body["tool_test_plan"]?.objectValue,
            ["environment", "purpose", "oracle_basis", "coverage_gaps", "cases"].allSatisfy({ key in
              guard let lhs = oldSpec[key], let rhs = newSpec[key] else { return false }
              return difference(lhs, rhs, at: "") == nil
            }),
            let old = verifyOriginal(before.original, plan: before.plan, tool: before.tool),
            let new = verifyOriginal(after.original, plan: after.plan, tool: after.tool),
            old["runtime"] == new["runtime"],
            let oldChecks = old["checks"]?.arrayValue, let newChecks = new["checks"]?.arrayValue,
            oldChecks.count == newChecks.count else { return nil }
      var counts: [String: Int64] = ["improved": 0, "regressed": 0, "both_passed": 0, "both_failed": 0]
      var cases: [AgentMcpJSONValue] = []
      for (lhs, rhs) in zip(oldChecks, newChecks) {
        guard let previous = lhs.objectValue, let current = rhs.objectValue,
              let id = previous["id"], current["id"] == id,
              let purpose = previous["purpose"],
              case .bool(let wasPassing)? = previous["passed"], case .bool(let isPassing)? = current["passed"]
        else { return nil }
        let outcome = wasPassing ? (isPassing ? "both_passed" : "regressed") : (isPassing ? "improved" : "both_failed")
        counts[outcome, default: 0] += 1
        cases.append(.object(["id": id, "purpose": purpose, "outcome": .string(outcome), "baseline": lhs, "candidate": rhs]))
      }
      func binding(_ observed: Observed, _ side: Side, _ evaluation: AgentMcpJSONObject) -> AgentMcpJSONValue {
        .object(["tool_test_plan": .object(fields(observed.plan.reference)),
          "executable_tool": .object(fields(observed.tool.reference)), "observation": .object(side.observation),
          "source_sha256": observed.original.input["source_sha256"] ?? .null,
          "execution_source_sha256": observed.original.input["execution_source_sha256"] ?? .null,
          "passed": evaluation["passed"] ?? .bool(false)])
      }
      return ["state": .string("observed_paired_case_outcomes"), "case_count": .int(Int64(cases.count)),
        "counts": .object(counts.mapValues(AgentMcpJSONValue.int)), "cases": .array(cases),
        "baseline": binding(before, baseline, old), "candidate": binding(after, candidate, new),
        "source_changed": .bool(before.original.input["source_sha256"] != after.original.input["source_sha256"]),
        "candidate_all_passed": new["passed"] ?? .bool(false),
        "oracle_truth_verified": .bool(false), "unseen_cases_verified": .bool(false),
        "environment_equivalence_proven": .bool(false), "independent_attempts_verified": .bool(false),
        "causal_contribution": .null, "capability_gain_verified": .bool(false),
        "automatically_adopted": .bool(false), "grants_permissions": .bool(false)]
    }
  }

  struct Prepared {
    let runtimeInput: AgentMcpJSONObject
    let evidenceInput: AgentMcpJSONObject
    let originalSource: String
    fileprivate let cases: [AgentMcpJSONObject]

    func matchesReceipt(_ result: AgentNativeToolResult) -> Bool {
      result.provenance.toolId == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute &&
        result.receipt.inputSha256 == AgentMcpJSONCodec.sha256(runtimeInput) &&
        result.receipt.outputSha256 == AgentMcpJSONCodec.sha256(result.output)
    }

    func evaluate(_ result: AgentNativeToolResult, detailed: Bool = true) -> AgentMcpJSONObject {
      func failure(_ code: String, _ path: String, expected: AgentMcpJSONValue = .null,
                   actual: AgentMcpJSONValue = .null) -> AgentMcpJSONObject {
        let item = detailed ? problem(code, path, expected: expected, actual: actual) :
          ["code": .string(code), "path": .string(path)]
        var failed: AgentMcpJSONObject = ["passed": .bool(false), "problems": .array([.object(item)])]
        if detailed { failed["diagnostics_version"] = .int(2) }
        return failed
      }
      guard matchesReceipt(result) else {
        return failure("runtime_receipt_mismatch", "/receipt", expected: .string("matching tool, input and output hashes"),
          actual: .string("unbound receipt"))
      }
      guard result.status == .succeeded, result.receipt.status == .succeeded,
            result.output["exit_code"] == .int(0) else {
        return failure("runtime_not_successful", "/exit_code", expected: .int(0),
          actual: result.output["exit_code"].map { describe($0) } ?? .string(result.error?.code ?? result.status.rawValue))
      }
      if detailed, let capture = captureProblem(result.output) {
        return ["passed": .bool(false), "diagnostics_version": .int(2), "problems": .array([.object(capture)])]
      }
      guard let stdout = result.output["stdout"]?.strictStringValue,
            stdout.utf8.count <= AgentCollaborationSavedToolTest.maximumReportBytes,
            result.output["output_truncated"] != .bool(true),
            (result.output["stdout_original_chars"]?.intValue ?? 0) <= Int64(stdout.utf16.count) else {
        return failure("report_stdout_truncated", "/stdout")
      }
      let bytes = Data(stdout.utf8)
      if detailed {
        guard let parsed = try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed]) else {
          return failure("report_json_unparseable", "/stdout", expected: .string("one complete JSON object"),
            actual: .string("invalid JSON"))
        }
        guard parsed is [String: Any] else {
          return failure("report_object_required", "/stdout", expected: .string("object"),
            actual: .string(parsed is [Any] ? "array" : "scalar"))
        }
      }
      guard let report = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: bytes),
            report["format"] == .string(reportFormat) else {
        let received = (try? JSONDecoder().decode(AgentMcpJSONObject.self, from: bytes))?["format"]
        return failure("report_format_mismatch", "/format", expected: .string(reportFormat), actual: describe(received))
      }
      if detailed, report["environment_matches"] != .bool(true) {
        return failure("runtime_environment_mismatch", "/environment_matches", expected: .bool(true),
          actual: describe(report["environment_matches"]))
      }
      guard report["environment_matches"] == .bool(true), let runtime = report["runtime"]?.objectValue,
            let version = runtime["python"]?.arrayValue, version.count == 3,
            version.allSatisfy({
              guard case .int(let n) = $0 else { return false }
              return n >= 0
            }),
            runtime["implementation"]?.strictStringValue?.isBlank == false,
            runtime["machine"]?.strictStringValue?.isBlank == false else {
        return failure("runtime_identity_missing", "/runtime",
          expected: .string("Python version, implementation and machine"), actual: describe(report["runtime"]))
      }
      guard let results = report["results"]?.arrayValue, results.count == cases.count else {
        return failure("case_coverage_mismatch", "/results", expected: .int(Int64(cases.count)),
          actual: report["results"]?.arrayValue.map { .int(Int64($0.count)) } ?? describe(report["results"]))
      }
      var rows: [String: (AgentMcpJSONObject, Int)] = [:]
      for (index, value) in results.enumerated() {
        guard let row = value.objectValue, let id = row["id"]?.strictStringValue, !id.isBlank else {
          return failure("case_id_required", "/results/\(index)/id", expected: .string("nonblank registered case ID"),
            actual: describe(value.objectValue?["id"]))
        }
        guard rows.updateValue((row, index), forKey: id) == nil else {
          return failure("duplicate_case_results", "/results/\(index)/id", expected: .string("unique case ID"),
            actual: .string(String(id.prefix(160))))
        }
      }
      var checks: [AgentMcpJSONValue] = []
      var problems: [AgentMcpJSONValue] = []
      for test in cases {
        let id = test.string("id")
        guard let (row, index) = rows[id], let expected = test["expected"] else {
          return failure("case_coverage_mismatch", "/results", expected: .string(id), actual: .string("missing registered result"))
        }
        let path = "/results/\(index)"
        let actual = row["output"]
        let mismatch: AgentMcpJSONObject?
        if row["error"] != nil {
          mismatch = problem("case_execution_error", path + "/error", expected: .string("case output"), actual: describe(row["error"]))
        } else if let actual {
          mismatch = difference(expected, actual, at: path + "/output")
        } else {
          mismatch = problem("case_output_missing", path + "/output", expected: .string("present"), actual: .string("missing"))
        }
        var check: AgentMcpJSONObject = ["id": .string(id), "purpose": test["purpose"] ?? .null,
          "passed": .bool(mismatch == nil), "expected": expected, "actual": actual ?? .null,
          "actual_present": .bool(actual != nil)]
        if var mismatch {
          if !detailed {
            let oldCode = row["error"] != nil ? "case_execution_error" : (actual == nil ? "case_output_missing" : "case_value_mismatch")
            mismatch = ["code": .string(oldCode), "path": mismatch["path"] ?? .string(path)]
          }
          mismatch["case_id"] = .string(id)
          let details = AgentMcpJSONValue.object(mismatch)
          check["problem"] = details
          problems.append(details)
        }
        if let error = row["error"] { check["error"] = error }
        checks.append(.object(check))
      }
      var evaluation: AgentMcpJSONObject = ["passed": .bool(problems.isEmpty), "runtime": .object(runtime),
        "checks": .array(checks), "problems": .array(problems), "replayed": .bool(result.receipt.replayed)]
      if detailed { evaluation["diagnostics_version"] = .int(2) }
      return evaluation
    }
  }

  static func reference(_ value: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let object = value?.objectValue, Set(object.keys) == ["object_id", "revision", "sha256"],
          let id = object["object_id"]?.strictStringValue, let hash = object["sha256"]?.strictStringValue,
          isDigest(id), isDigest(hash), case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return .init(objectId: id, revision: revision, sha256: hash)
  }

  static func prepare(plan: AgentCollaborationResearchRevision, tool: AgentCollaborationResearchRevision,
                      timeoutMillis: Int64) -> Prepared? {
    guard (100...AgentIOSOnDeviceRuntimeNativeToolCatalog.maxTimeoutMillis).contains(timeoutMillis),
          plan.draft.kind == .toolTestPlan, tool.draft.kind == .executableTool,
          let test = plan.draft.body["tool_test_plan"]?.objectValue,
          let spec = tool.draft.body["executable_tool"]?.objectValue,
          let source = spec["source"]?.strictStringValue,
          reference(test["executable_tool"]) == tool.reference, plan.draft.parents.contains(tool.reference),
          AgentCollaborationToolRegistration.validatesTestPlan(test, tool: spec),
          let cases = test["cases"]?.arrayValue?.compactMap(\.objectValue),
          cases.allSatisfy({ ($0["id"]?.strictStringValue?.utf8.count ?? 0) > 0 &&
            ($0["id"]?.strictStringValue?.utf8.count ?? 0) <= 160 }) else { return nil }
    let input: AgentMcpJSONObject = ["source": .string(source), "cases": .array(cases.map {
      .object(["id": $0["id"] ?? .null, "input": $0["input"] ?? .null])
    })]
    let encoded = Data(AgentMcpJSONCodec.stringify(input).utf8).base64EncodedString()
    // This isolates Python namespaces, not the guest OS. The existing runtime policy still applies.
    let program = """
      import base64, contextlib, io, json, platform, sys
      payload = json.loads(base64.b64decode('\(encoded)').decode('utf-8'))
      runtime = {'python': list(sys.version_info[:3]), 'implementation': sys.implementation.name, 'machine': platform.machine()}
      results = []
      class Discard(io.TextIOBase):
          def write(self, value): return len(value)
      for case in payload['cases']:
          row = {'id': case['id']}
          try:
              namespace = {'__name__': 'galaxyssi_generated_tool'}
              with contextlib.redirect_stdout(Discard()):
                  exec(compile(payload['source'], '<saved-tool>', 'exec'), namespace)
                  value = namespace['run'](case['input'])
              row['output'] = json.loads(json.dumps(value, allow_nan=False))
          except Exception as error:
              row['error'] = (type(error).__name__ + ': ' + str(error))[:1024]
          results.append(row)
      print(json.dumps({'format': '\(reportFormat)', 'runtime': runtime, 'environment_matches': True, 'results': results}, allow_nan=False))
      """
    guard program.utf8.count <= 256 * 1_024 else { return nil }
    return Prepared(runtimeInput: ["language": .string("python"), "source": .string(program),
      "timeout_ms": .int(timeoutMillis), "network_enabled": .bool(false)], evidenceInput: [
        "mode": .string("test"), "tool_test_plan": .object(fields(plan.reference)),
        "executable_tool": .object(fields(tool.reference)), "execution_source_sha256": .string(digest(program)),
        "source_sha256": .string(digest(source)), "timeout_ms": .int(timeoutMillis), "grants_permissions": .bool(false)
      ], originalSource: source, cases: cases)
  }

  private static func fields(_ ref: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    ["object_id": .string(ref.objectId), "revision": .int(ref.revision), "sha256": .string(ref.sha256)]
  }

  private static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  fileprivate static func difference(_ a: AgentMcpJSONValue, _ b: AgentMcpJSONValue, at path: String) -> AgentMcpJSONObject? {
    switch (a, b) {
    case (.int(let n), .double(let d)), (.double(let d), .int(let n)):
      return Int64(exactly: d) == n ? nil : problem("value_mismatch", path, expected: describe(a), actual: describe(b))
    case (.object(let lhs), .object(let rhs)):
      for key in Set(lhs.keys).union(rhs.keys).sorted() {
        let child = path + "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
        guard let x = lhs[key] else { return problem("unexpected_key", child, expected: .string("absent"), actual: .string("present")) }
        guard let y = rhs[key] else { return problem("missing_key", child, expected: .string("present"), actual: .string("absent")) }
        if let mismatch = difference(x, y, at: child) { return mismatch }
      }
      return nil
    case (.array(let lhs), .array(let rhs)):
      guard lhs.count == rhs.count else {
        return problem("array_length_mismatch", path, expected: .int(Int64(lhs.count)), actual: .int(Int64(rhs.count)))
      }
      for (index, pair) in zip(lhs, rhs).enumerated() {
        if let mismatch = difference(pair.0, pair.1, at: path + "/\(index)") { return mismatch }
      }
      return nil
    default:
      return a == b ? nil : problem(type(a) == type(b) ? "value_mismatch" : "type_mismatch", path,
        expected: .string(type(a)), actual: .string(type(b)))
    }
  }
}
