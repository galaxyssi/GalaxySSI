import CryptoKit
import Foundation

enum AgentCollaborationSavedToolTest {
  static let reportFormat = "galaxyssi.executable-tool-output.v1"
  private static let maximumReportBytes = 96 * 1_024

  struct Prepared {
    let runtimeInput: AgentMcpJSONObject
    let evidenceInput: AgentMcpJSONObject
    let originalSource: String
    fileprivate let cases: [AgentMcpJSONObject]

    func evaluate(_ result: AgentNativeToolResult) -> AgentMcpJSONObject {
      func failure(_ code: String, _ path: String) -> AgentMcpJSONObject {
        ["passed": .bool(false), "problems": .array([.object(["code": .string(code), "path": .string(path)])])]
      }
      guard result.provenance.toolId == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
            result.receipt.inputSha256 == AgentMcpJSONCodec.sha256(runtimeInput),
            result.receipt.outputSha256 == AgentMcpJSONCodec.sha256(result.output) else {
        return failure("runtime_receipt_mismatch", "/receipt")
      }
      guard result.status == .succeeded, result.receipt.status == .succeeded,
            result.output["exit_code"] == .int(0) else { return failure("runtime_not_successful", "/exit_code") }
      guard let stdout = result.output["stdout"]?.strictStringValue,
            stdout.utf8.count <= AgentCollaborationSavedToolTest.maximumReportBytes,
            result.output["output_truncated"] != .bool(true),
            (result.output["stdout_original_chars"]?.intValue ?? 0) <= Int64(stdout.utf16.count) else {
        return failure("report_stdout_truncated", "/stdout")
      }
      guard let report = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(stdout.utf8)),
            report["format"] == .string(AgentCollaborationSavedToolTest.reportFormat) else {
        return failure("report_format_mismatch", "/format")
      }
      guard report["environment_matches"] == .bool(true), let runtime = report["runtime"]?.objectValue,
            let version = runtime["python"]?.arrayValue, version.count == 3,
            version.allSatisfy({
              guard case .int(let n) = $0 else { return false }
              return n >= 0
            }),
            runtime["implementation"]?.strictStringValue?.isBlank == false,
            runtime["machine"]?.strictStringValue?.isBlank == false else {
        return failure("runtime_identity_missing", "/runtime")
      }
      guard let results = report["results"]?.arrayValue, results.count == cases.count else {
        return failure("case_coverage_mismatch", "/results")
      }
      var rows: [String: (AgentMcpJSONObject, Int)] = [:]
      for (index, value) in results.enumerated() {
        guard let row = value.objectValue, let id = row["id"]?.strictStringValue, !id.isBlank else {
          return failure("case_id_required", "/results/\(index)/id")
        }
        guard rows.updateValue((row, index), forKey: id) == nil else {
          return failure("duplicate_case_results", "/results/\(index)/id")
        }
      }
      var checks: [AgentMcpJSONValue] = []
      var problems: [AgentMcpJSONValue] = []
      for test in cases {
        let id = test.string("id")
        guard let (row, index) = rows[id], let expected = test["expected"] else {
          return failure("case_coverage_mismatch", "/results")
        }
        let path = "/results/\(index)"
        let actual = row["output"]
        let problem: (String, String)?
        if row["error"] != nil {
          problem = ("case_execution_error", path + "/error")
        } else if let actual {
          problem = AgentCollaborationSavedToolTest.difference(expected, actual, at: path + "/output")
            .map { ("case_value_mismatch", $0) }
        } else {
          problem = ("case_output_missing", path + "/output")
        }
        var check: AgentMcpJSONObject = ["id": .string(id), "purpose": test["purpose"] ?? .null,
          "passed": .bool(problem == nil), "expected": expected, "actual": actual ?? .null,
          "actual_present": .bool(actual != nil)]
        if let (code, pointer) = problem {
          let details: AgentMcpJSONValue = .object(["code": .string(code), "path": .string(pointer), "case_id": .string(id)])
          check["problem"] = details
          problems.append(details)
        }
        if let error = row["error"] { check["error"] = error }
        checks.append(.object(check))
      }
      return ["passed": .bool(problems.isEmpty), "runtime": .object(runtime),
        "checks": .array(checks), "problems": .array(problems), "replayed": .bool(result.receipt.replayed)]
    }
  }

  static func reference(_ value: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let object = value?.objectValue, Set(object.keys) == ["object_id", "revision", "sha256"],
          let id = object["object_id"]?.strictStringValue, let hash = object["sha256"]?.strictStringValue,
          isDigest(id), isDigest(hash), case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return .init(objectId: id, revision: revision, sha256: hash)
  }

  static func release(
    _ draft: AgentCollaborationResearchDraft,
    plan: AgentCollaborationResearchRevision,
    tool: AgentCollaborationResearchRevision,
    original: AgentCollaborationNativeToolObservation,
    authorResource: String,
    reviewerResource: String
  ) -> AgentMcpJSONObject? {
    guard draft.kind == .toolRelease,
          draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let spec = draft.body["tool_release"]?.objectValue,
          Set(spec.keys) == ["tool_test_plan", "observation", "review", "applies_when", "avoid_when",
                             "limitations", "authorization_boundary", "unresolved"],
          ["review", "applies_when", "avoid_when", "limitations", "authorization_boundary"].allSatisfy({
            guard let text = spec[$0]?.strictStringValue else { return false }
            return !text.isBlank && text.utf8.count <= 8_192
          }),
          spec["unresolved"] == .array([]),
          !authorResource.isBlank, !reviewerResource.isBlank, authorResource != reviewerResource,
          reference(spec["tool_test_plan"]) == plan.reference, draft.parents.contains(plan.reference),
          let observation = spec["observation"]?.objectValue,
          draft.observations == [observation],
          let registered = plan.registeredAtMillis,
          original.result.receipt.startedAtEpochMillis >= registered,
          original.result.receipt.finishedAtEpochMillis >= original.result.receipt.startedAtEpochMillis,
          !original.result.receipt.replayed,
          case .int(let timeout)? = original.input["timeout_ms"],
          let prepared = prepare(plan: plan, tool: tool, timeoutMillis: timeout),
          original.input == prepared.evidenceInput else { return nil }
    let evaluation = prepared.evaluate(original.result)
    guard evaluation["passed"] == .bool(true), let runtime = evaluation["runtime"]?.objectValue else { return nil }
    return [
      "state": .string("eligible_for_scoped_tool_execution"),
      "executable_tool": .object(fields(tool.reference)), "tool_test_plan": .object(fields(plan.reference)),
      "observation": .object(observation), "source_sha256": .string(digest(prepared.originalSource)),
      "tested_runtime": .object(runtime), "grants_permissions": .bool(false),
      "security_certified": .bool(false), "general_correctness_proven": .bool(false)
    ]
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

  private static func difference(_ a: AgentMcpJSONValue, _ b: AgentMcpJSONValue, at path: String) -> String? {
    switch (a, b) {
    case (.int(let n), .double(let d)), (.double(let d), .int(let n)):
      return Int64(exactly: d) == n ? nil : path
    case (.object(let lhs), .object(let rhs)):
      for key in Set(lhs.keys).union(rhs.keys).sorted() {
        let child = path + "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
        guard let x = lhs[key], let y = rhs[key] else { return child }
        if let mismatch = difference(x, y, at: child) { return mismatch }
      }
      return nil
    case (.array(let lhs), .array(let rhs)):
      guard lhs.count == rhs.count else { return path }
      for (index, pair) in zip(lhs, rhs).enumerated() {
        if let mismatch = difference(pair.0, pair.1, at: path + "/\(index)") { return mismatch }
      }
      return nil
    default:
      return a == b ? nil : path
    }
  }
}
