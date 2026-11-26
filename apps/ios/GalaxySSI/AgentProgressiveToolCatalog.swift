import Foundation

enum AgentProgressiveToolCatalog {
  struct Manifest {
    let header: String
    let rows: [String]
    var text: String { header + rows.joined() }
  }
  static let entryPoints = Set(AgentResearchCapabilityDiscovery.orderedTools).union(AgentToolInspectionCatalog.toolIds)

  static func recent(_ history: [AgentAction]) -> Set<String> {
    var result = Set<String>()
    for action in history.reversed() where action.kind == .callNativeTool && action.status == .completed {
      let id = (action.parameters["tool_id"] ?? "").ifBlank(action.target)
      let actual: String
      if id == AgentToolInspectionCatalog.describe {
        guard let data = action.parameters["input_json"]?.data(using: .utf8),
              let input = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else { continue }
        actual = input.string("tool_id")
      } else { actual = id }
      guard !actual.isBlank, !entryPoints.contains(actual) else { continue }
      result.insert(actual)
      if result.count == 4 { break }
    }
    return result
  }

  static func render(_ eligible: [AgentNativeToolDescriptor], recent: Set<String>) -> Manifest? {
    guard eligible.count > 12, AgentToolInspectionCatalog.toolIds.isSubset(of: Set(eligible.map(\.id))) else { return nil }
    let families = Set(eligible.map { tool in
      let name = tool.id.hasPrefix("galaxyssi.") ? String(tool.id.dropFirst("galaxyssi.".count)) : tool.id
      return String(name.split(separator: ".").first ?? "")
    }).sorted().joined(separator: ", ")
    let header = "Available families: \(families).\n" +
      "Answer directly when no tool is needed. For other operations use galaxyssi.tools.discover with a short capability or family; " +
      "zero matches: rephrase or browse with an empty query and cursor. Use galaxyssi.tools.describe for the exact contract. " +
      "Only invoke available tools from this catalog or its discovery receipts. ! marks a required argument.\n"
    let visible = eligible.filter { entryPoints.contains($0.id) } + eligible.filter { recent.contains($0.id) && !entryPoints.contains($0.id) }
    let rows = visible.map { tool -> String in
      var output = "- \(tool.id) | risk=\(tool.risk.rawValue)"
      if tool.concurrency == .parallelReadOnly { output += " | concurrency=parallel_read_only" }
      output += " | input=\(signature(tool.inputSchema))\n"
      return output
    }
    return Manifest(header: header, rows: rows)
  }

  static func signature(_ schema: AgentMcpJSONObject) -> String {
    let required = Set((schema["required"]?.arrayValue ?? []).compactMap(\.stringValue))
    let fields = schema["properties"]?.objectValue ?? [:]
    return "{" + fields.keys.sorted().map { key in
      let field = fields[key]?.objectValue ?? [:]
      let type: String
      if let choices = field["enum"]?.arrayValue, (1...5).contains(choices.count) {
        type = choices.map { $0.stringValue ?? AgentMcpJSONCodec.stringify($0) }.joined(separator: "|")
      } else if field.string("type") == "array" {
        type = "list<" + (field["items"]?.objectValue?.string("type") ?? "any") + ">"
      } else { type = field.string("type").ifBlank("any") }
      return key + (required.contains(key) ? "!" : "") + ":" + type
    }.joined(separator: ",") + "}"
  }
}
