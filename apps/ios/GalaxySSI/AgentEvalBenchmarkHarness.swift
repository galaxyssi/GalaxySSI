import Foundation

struct AgentBenchmarkPlannedTool: Equatable {
  var id: String
  var input: AgentMcpJSONObject = [:]
}

enum AgentBenchmarkHarnessProtocol {
  static func tools(for benchmarkCase: AgentBenchmarkCase, trialId: String) -> [AgentBenchmarkPlannedTool] {
    switch benchmarkCase.id {
    case "plan-tool-01": return [tool(AgentSystemEvidenceNativeToolCatalog.deviceInfo)]
    case "plan-tool-02": return [tool(AgentSystemEvidenceNativeToolCatalog.appInfo)]
    case "plan-tool-03": return [tool(AgentIOSHardwareNativeToolCatalog.networkStatus)]
    case "plan-tool-04": return [tool(AgentIOSHardwareNativeToolCatalog.batteryStatus)]
    case "plan-tool-05": return [tool(AgentIOSHardwareNativeToolCatalog.storageStatus)]
    case "plan-tool-06": return [tool(AgentSystemEvidenceNativeToolCatalog.localTime)]
    case "plan-tool-07":
      let path = "evalops/\(safe(trialId)).txt"
      return [
        tool(AgentPhoneNativeToolCatalog.workspaceCreateText, ["path": .string(path), "text": .string("GalaxySSI EvalOps integrity fixture")]),
        tool(AgentPhoneNativeToolCatalog.workspaceReadText, ["path": .string(path)]),
        tool(AgentPhoneNativeToolCatalog.workspaceSha256, ["path": .string(path)])
      ]
    case "plan-tool-08": return [tool(AgentIOSHardwareNativeToolCatalog.memoryStatus)]
    case "plan-tool-09":
      return [tool(AgentIOSWebIntelligenceNativeToolCatalog.research, [
        "query": .string("iOS application lifecycle and background execution official documentation"),
        "evidence_limit": .int(4),
        "profile": .string("balanced")
      ])]
    case "plan-tool-10":
      return [tool(AgentSystemEvidenceNativeToolCatalog.jsonValidate, [
        "json": .string(#"{"status":"ready","count":3}"#)
      ])]
    default: return []
    }
  }

  static func executionPrompt(for benchmarkCase: AgentBenchmarkCase, trialId: String) -> String {
    let tools = tools(for: benchmarkCase, trialId: trialId)
    guard !tools.isEmpty else { return benchmarkCase.taggedPrompt }
    let list = tools.enumerated().map { "\($0.offset + 1). \($0.element.id)" }.joined(separator: "\n")
    return """
    \(benchmarkCase.taggedPrompt)

    This is an evidence-backed Agent harness run. Plan first, execute the selected real tools below, and base the final answer only on immutable receipts:
    \(list)
    Do not invent observed values. Name the tools and cite their receipt values in the final answer.
    """
  }

  private static func tool(_ id: String, _ input: AgentMcpJSONObject = [:]) -> AgentBenchmarkPlannedTool {
    AgentBenchmarkPlannedTool(id: id, input: input)
  }

  private static func safe(_ value: String) -> String {
    String(value.filter { $0.isLetter || $0.isNumber || $0 == "-" }.prefix(80)).ifBlank("preflight")
  }
}
