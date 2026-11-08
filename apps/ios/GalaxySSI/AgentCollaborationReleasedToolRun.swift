import CryptoKit
import Foundation

enum AgentCollaborationReleasedToolRun {
  static let format = "galaxyssi.executable-tool-run-output.v1"

  struct Prepared {
    let runtimeInput: AgentMcpJSONObject
    let evidenceInput: AgentMcpJSONObject
    let originalSource: String
    let runtime: AgentMcpJSONObject

    func evaluate(_ result: AgentNativeToolResult) -> AgentMcpJSONObject {
      func failed(_ reason: String) -> AgentMcpJSONObject { ["passed": .bool(false), "reason": .string(reason)] }
      guard result.provenance.toolId == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
            result.provenance.location == .application,
            result.provenance.executorId == AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId,
            result.receipt.inputSha256 == AgentMcpJSONCodec.sha256(runtimeInput),
            result.receipt.outputSha256 == AgentMcpJSONCodec.sha256(result.output) else { return failed("runtime_receipt_mismatch") }
      guard result.status == .succeeded, result.receipt.status == .succeeded, result.output["exit_code"] == .int(0)
      else { return failed("runtime_not_successful") }
      guard let stdout = result.output["stdout"]?.strictStringValue, stdout.utf8.count <= 96 * 1_024,
            result.output["output_truncated"] != .bool(true),
            (result.output["stdout_original_chars"]?.intValue ?? 0) <= Int64(stdout.utf16.count),
            let report = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(stdout.utf8)),
            report["format"] == .string(AgentCollaborationReleasedToolRun.format) else { return failed("invalid_run_report") }
      guard report["runtime"]?.objectValue == runtime, report["environment_matches"] == .bool(true)
      else { return failed("runtime_identity_changed") }
      guard Set(report.keys) == ["format", "runtime", "environment_matches", "output"], report["output"] != nil
      else { return failed("saved_tool_returned_no_result") }
      return ["passed": .bool(true), "replayed": .bool(result.receipt.replayed), "runtime": .object(runtime)]
    }
  }

  static func prepare(release: AgentCollaborationResearchRevision, plan: AgentCollaborationResearchRevision,
      tool: AgentCollaborationResearchRevision, channel: AgentCollaborationResearchReference?,
      parameters: AgentMcpJSONObject, timeoutMillis: Int64) -> Prepared? {
    guard release.draft.kind == .toolRelease, plan.draft.kind == .toolTestPlan, tool.draft.kind == .executableTool,
          (100...AgentIOSOnDeviceRuntimeNativeToolCatalog.maxTimeoutMillis).contains(timeoutMillis),
          let approval = release.testedToolRelease, approval["state"] == .string(AgentCollaborationCapabilityPage.releaseState),
          approval["grants_permissions"] == .bool(false),
          AgentCollaborationSavedToolTest.reference(approval["executable_tool"]) == tool.reference,
          AgentCollaborationSavedToolTest.reference(approval["tool_test_plan"]) == plan.reference,
          release.draft.parents.contains(plan.reference),
          AgentCollaborationCandidateRecall.linkedTool(plan) == tool.reference,
          let spec = tool.draft.body["executable_tool"]?.objectValue, let source = spec["source"]?.strictStringValue,
          let schema = AgentCollaborationToolRegistration.parameterSchema(spec),
          AgentSkillManifestValidator.validateParameters(schema, value: .object(parameters), path: "$.parameters").isEmpty,
          let runtime = approval["tested_runtime"]?.objectValue, validRuntime(runtime),
          let digest = approval["source_sha256"]?.strictStringValue,
          digest == hash(source) else { return nil }
    let payload: AgentMcpJSONObject = ["source": .string(source), "parameters": .object(parameters),
      "runtime": .object(runtime)]
    let encoded = Data(AgentMcpJSONCodec.stringify(payload).utf8).base64EncodedString()
    let program = """
      import base64, contextlib, io, json, platform, sys
      payload = json.loads(base64.b64decode('\(encoded)').decode('utf-8'))
      runtime = {'python': list(sys.version_info[:3]), 'implementation': sys.implementation.name, 'machine': platform.machine()}
      report = {'format': '\(format)', 'runtime': runtime, 'environment_matches': runtime == payload['runtime']}
      class Discard(io.TextIOBase):
          def write(self, value): return len(value)
      if report['environment_matches']:
          namespace = {'__name__': 'galaxyssi_released_tool'}
          try:
              with contextlib.redirect_stdout(Discard()):
                  exec(compile(payload['source'], '<released-tool>', 'exec'), namespace)
                  value = namespace['run'](payload['parameters'])
              report['output'] = json.loads(json.dumps(value, allow_nan=False))
          except Exception as error:
              report['error'] = type(error).__name__
      print(json.dumps(report, allow_nan=False))
      """
    guard program.utf8.count <= 256 * 1_024 else { return nil }
    var evidence: AgentMcpJSONObject = [
      "mode": .string("run"), "tool_release": .object(AgentCollaborationCandidateRecall.reference(release.reference)),
      "executable_tool": .object(AgentCollaborationCandidateRecall.reference(tool.reference)),
      "parameters": .object(parameters), "source_sha256": .string(digest), "execution_source_sha256": .string(hash(program)),
      "tested_runtime": .object(runtime), "grants_permissions": .bool(false)
    ]
    if let channel { evidence["capability_channel"] = .object(AgentCollaborationCandidateRecall.reference(channel)) }
    return .init(runtimeInput: ["language": .string("python"), "source": .string(program), "timeout_ms": .int(timeoutMillis),
      "network_enabled": .bool(false)], evidenceInput: evidence, originalSource: source, runtime: runtime)
  }

  private static func validRuntime(_ runtime: AgentMcpJSONObject) -> Bool {
    guard Set(runtime.keys) == ["python", "implementation", "machine"],
          runtime["implementation"]?.strictStringValue?.isBlank == false,
          runtime["machine"]?.strictStringValue?.isBlank == false,
          let version = runtime["python"]?.arrayValue, version.count == 3 else { return false }
    return version.allSatisfy { if case .int(let value) = $0 { return value >= 0 }; return false }
  }

  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
