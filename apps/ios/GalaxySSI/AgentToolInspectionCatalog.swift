import Foundation

enum AgentToolInspectionCatalog {
  static let discover = "galaxyssi.tools.discover"
  static let describe = "galaxyssi.tools.describe"
  static let toolIds: Set<String> = [discover, describe]

  static func definitions() -> [AgentPhoneNativeToolDefinition] {
    let string: (Int) -> AgentMcpJSONValue = { .object(["type": .string("string"), "maxLength": .int(Int64($0))]) }
    return [
      definition(discover, "Discover registered capabilities and setup blockers",
        "Search registered tool IDs, titles and descriptions, including unavailable tools. Follow next_cursor with the same query. Discovery does not install dependencies, grant permissions or execute target tools.",
        properties: ["query": string(256), "cursor": string(1024),
          "limit": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(50)])]),
      definition(describe, "Inspect a native tool contract",
        "Read a registered tool contract, including setup blockers. Default schema_path is /input_schema; use /description or /availability for metadata. Inspection does not execute or enable the target.",
        properties: ["tool_id": .object(["type": .string("string"), "minLength": .int(1), "maxLength": .int(160)]),
          "schema_path": string(1024)], required: ["tool_id"])
    ]
  }

  private static func definition(_ id: String, _ title: String, _ description: String,
                                 properties: AgentMcpJSONObject, required: [String] = []) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(id: id, version: "1.0.0", title: title, description: description,
      location: .application, inputSchema: ["type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(AgentMcpJSONValue.string)), "additionalProperties": .bool(false)],
      risk: .low, idempotency: .idempotent, concurrency: .parallelReadOnly, effect: .readOnly)
    return .init(descriptor: descriptor, executorId: "ios.tool_catalog_inspection")
  }

  static func executableDefinitions() -> [AgentNativeToolExecutableDefinition] {
    definitions().map { definition in
      .init(definition: definition, executor: { invocation in
        try invocation.checkpoint()
        guard let catalog = invocation.toolCatalog?(), let tools = catalog["tools"]?.arrayValue else {
          return .failure(code: "catalog_unavailable", message: "The invoking registry catalog is unavailable.")
        }
        let rows = tools.compactMap(\.objectValue)
        if definition.id == discover { return page(rows, input: invocation.input) }
        let id = invocation.input.string("tool_id")
        guard let tool = rows.first(where: { $0.string("id") == id }) else {
          return .failure(code: "tool_not_disclosed", message: "This tool is not in the current registry view.")
        }
        let path = invocation.input["schema_path"]?.stringValue ?? "/input_schema"
        guard let selected = select(.object(tool), path: path) else {
          return .failure(code: "schema_path_not_found", message: "Inspect a valid JSON Pointer in the disclosed tool contract.")
        }
        return .success(output: ["tool_id": .string(id), "version": tool["version"] ?? .null,
          "schema_path": .string(path), "definition": selected, "availability": tool["availability"] ?? .null,
          "target_executed": .bool(false)])
      })
    }
  }

  static func select(_ root: AgentMcpJSONValue, path: String) -> AgentMcpJSONValue? {
    if path.isEmpty { return root }
    guard path.hasPrefix("/"), path.utf16.count <= 1024 else { return nil }
    var current = root
    for raw in path.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
      let token = String(raw)
      guard token.range(of: #"~(?![01])"#, options: .regularExpression) == nil else { return nil }
      let key = token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
      if let object = current.objectValue, let next = object[key] { current = next }
      else if let array = current.arrayValue, let index = Int(key), index >= 0, String(index) == key,
              array.indices.contains(index) { current = array[index] }
      else { return nil }
    }
    return current
  }

  static func page(_ catalog: [AgentMcpJSONObject], input: AgentMcpJSONObject) -> AgentNativeToolExecutionResult {
    let query = input.string("query").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let queryHash = AgentMcpJSONCodec.sha256(["query": .string(query)])
    let tools = catalog.sorted { $0.string("id") < $1.string("id") }
    let stable = tools.map { tool -> AgentMcpJSONValue in
      var copy = tool
      if var availability = copy["availability"]?.objectValue {
        availability.removeValue(forKey: "checked_at_epoch_ms")
        copy["availability"] = .object(availability)
      }
      return .object(copy)
    }
    let revision = AgentMcpJSONCodec.sha256(["tools": .array(stable)])
    var after = ""
    let cursor = input.string("cursor")
    if !cursor.isBlank {
      var encoded = cursor.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
      encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
      guard cursor.utf8.count <= 1024, let data = Data(base64Encoded: encoded),
            let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data),
            object.string("query_sha256") == queryHash, !object.string("after_id").isBlank,
            object.string("revision").range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
        return .failure(code: "tool_discovery_cursor_invalid", message: "Use the returned cursor with its original query.")
      }
      guard object.string("revision") == revision else {
        return .failure(code: "tool_catalog_changed", message: "Registered capability metadata changed. Restart discovery without a cursor.")
      }
      after = object.string("after_id")
    }
    let matches = tools.filter { tool in
      Self.matches(query, tool: tool)
    }
    guard after.isEmpty || matches.contains(where: { $0.string("id") == after }) else {
      return .failure(code: "tool_discovery_cursor_invalid", message: "The cursor does not refer to this capability search.")
    }
    let limit = Int(min(50, max(1, input["limit"]?.intValue ?? 20)))
    let remaining = matches.filter { $0.string("id") > after }, selected = Array(remaining.prefix(limit))
    var output: AgentMcpJSONObject = ["catalog_sha256": .string(revision), "query": .string(query),
      "total_matches": .int(Int64(matches.count)), "contract_tool_id": .string(describe), "target_executed": .bool(false),
      "tools": .array(selected.map { tool in .object([
        "id": tool["id"] ?? .null, "version": tool["version"] ?? .null, "title": tool["title"] ?? .null,
        "description": .string(String(tool.string("description").prefix(400))),
        "description_truncated": .bool(tool.string("description").count > 400), "availability": tool["availability"] ?? .null]) })]
    if matches.isEmpty {
      output["capability_absent"] = .bool(false)
      output["search_guidance"] = .string("No metadata match, not proof of missing capability. Retry with short capability terms or an empty query to browse registered tools and their availability.")
    }
    if remaining.count > selected.count, let last = selected.last {
      let next: AgentMcpJSONObject = ["revision": .string(revision), "query_sha256": .string(queryHash), "after_id": last["id"] ?? .null]
      output["next_cursor"] = .string(Data(AgentMcpJSONCodec.stringify(next).utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""))
    }
    return .success(output: output)
  }

  private static func matches(_ query: String, tool: AgentMcpJSONObject) -> Bool {
    guard !query.isBlank else { return true }
    let text = [tool.string("id"), tool.string("title"), tool.string("description"),
      (tool["capabilities"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: " ")].joined(separator: " ").lowercased()
    let translated = Set(aliases.filter { query.contains($0.key) }.values)
    if !translated.isEmpty { return translated.allSatisfy { text.contains($0) } }
    let pattern = try! NSRegularExpression(pattern: #"[a-z0-9_.-]+|\p{Han}+"#)
    let words = pattern.matches(in: query, range: NSRange(query.startIndex..., in: query))
      .compactMap { Range($0.range, in: query).map { String(query[$0]) } }
    return !words.isEmpty && words.allSatisfy { word in
      if text.contains(word) { return true }
      let characters = Array(word)
      guard characters.count >= 2, word.unicodeScalars.allSatisfy({ !$0.isASCII }) else { return false }
      return zip(characters, characters.dropFirst()).contains { text.contains(String([$0.0, $0.1])) }
    }
  }

  private static let aliases = [
    "\u{641c}\u{7d22}": "search", "\u{67e5}\u{8be2}": "search", "\u{67e5}\u{627e}": "search",
    "\u{7f51}\u{9875}": "web", "\u{7f51}\u{7ad9}": "web", "\u{56fe}\u{7247}": "image", "\u{7167}\u{7247}": "image",
    "\u{65b0}\u{95fb}": "news", "\u{8d44}\u{6599}": "research", "\u{6d4f}\u{89c8}\u{5668}": "browser",
    "\u{6587}\u{4ef6}": "file", "\u{4e0b}\u{8f7d}": "download", "\u{8bfb}\u{53d6}": "read", "\u{5b89}\u{88c5}": "install"
  ]
}
