import Foundation

@MainActor
enum AgentPersonalDataCommandRouter {
  struct Result {
    let text: String
    let actionId: String
  }

  static func handle(_ input: String, store: SignalASIStore) -> Result? {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = command.lowercased()
    guard !command.isEmpty else { return nil }

    if let enabled = AgentMemoryCommandParser.memoryCaptureValue(fromGoal: command) {
      store.updateAgentSafetySettings { $0.memoryCapture = enabled }
      return Result(
        text: enabled ? "Memory capture resumed" : "Memory capture paused",
        actionId: "memory_capture"
      )
    }
    if memoryOverviewCommands.contains(normalized) {
      return memoryOverview(store: store)
    }
    if knowledgeOverviewCommands.contains(normalized) {
      return knowledgeOverview(store: store)
    }
    if let value = AgentMemoryCommandParser.memoryValue(fromGoal: command) {
      return saveMemory(value, store: store)
    }
    if let query = prefixedValue(command, prefixes: ["forget memory ", "delete memory ", "remove memory ", "forget note "]) {
      return forgetMemory(query, store: store)
    }
    if let query = prefixedValue(command, prefixes: ["forget knowledge ", "delete knowledge ", "remove knowledge ", "forget document ", "delete document "]) {
      return forgetKnowledge(query, store: store)
    }
    if let query = prefixedValue(command, prefixes: ["search knowledge ", "find knowledge ", "search memory ", "find memory "]) {
      return searchKnowledge(query, store: store)
    }
    if isManagementCommand(normalized) {
      return Result(
        text: "Memory commands: memory status; remember <value>; forget memory <query>; pause memory; resume memory. Knowledge commands: knowledge status; search knowledge <query>; forget knowledge <query>.",
        actionId: "personal_data_syntax"
      )
    }
    return nil
  }

  private static let memoryOverviewCommands: Set<String> = [
    "memory status",
    "show memory",
    "list memories",
    "recent memories",
    "show recent memories",
    "what do you remember"
  ]

  private static let knowledgeOverviewCommands: Set<String> = [
    "knowledge status",
    "knowledge base status",
    "show knowledge",
    "list knowledge",
    "recent knowledge",
    "show recent knowledge"
  ]

  private static func memoryOverview(store: SignalASIStore) -> Result {
    let snapshot = store.agentMemorySnapshot()
    let recent = snapshot.activeItems
      .sorted { $0.timestampMillis > $1.timestampMillis }
      .prefix(10)
    var lines = [
      "Personal memory: \(snapshot.activeCount); conflicts=\(snapshot.conflicts.count); capture=\(store.agentSafetySettings.memoryCapture ? "on" : "paused")"
    ]
    if recent.isEmpty {
      lines.append("No saved memories")
    } else {
      lines.append(contentsOf: recent.map { item in
        "\(item.kind.rawValue.lowercased()): \(compact(item.value, limit: 120))"
      })
    }
    return Result(text: lines.joined(separator: "\n"), actionId: "memory_overview")
  }

  private static func knowledgeOverview(store: SignalASIStore) -> Result {
    let stats = store.agentKnowledgeStats
    let groups = store.agentKnowledgeSourceGroups().prefix(10)
    var lines = ["Knowledge base: \(stats.itemCount) items; sources=\(stats.sourceCount)"]
    if groups.isEmpty {
      lines.append("No knowledge items")
    } else {
      lines.append(contentsOf: groups.map { group in
        "\(group.title) [\(compact(group.source, limit: 48))]"
      })
    }
    return Result(text: lines.joined(separator: "\n"), actionId: "knowledge_overview")
  }

  private static func saveMemory(_ value: String, store: SignalASIStore) -> Result {
    guard store.agentSafetySettings.memoryCapture else {
      return Result(text: "Memory capture is paused", actionId: "memory_save")
    }
    let write = store.rememberAgentMemory(AgentMemoryCommandParser.item(fromCommand: value))
    if write.conflict != nil {
      return Result(text: "Memory conflict needs review", actionId: "memory_save")
    }
    if write.duplicate {
      return Result(text: "Memory already saved", actionId: "memory_save")
    }
    return Result(text: "Saved personal memory", actionId: "memory_save")
  }

  private static func forgetMemory(_ query: String, store: SignalASIStore) -> Result {
    let matches = store.agentMemorySnapshot().activeItems.filter { memoryMatches($0, query: query) }
    let deleted = matches.reduce(0) { count, item in
      count + (store.deleteAgentMemory(id: item.id) ? 1 : 0)
    }
    let text = deleted == 0
      ? "No matching memory for \"\(query)\""
      : "Deleted \(deleted) matching memory items"
    return Result(text: text, actionId: "memory_forget")
  }

  private static func forgetKnowledge(_ query: String, store: SignalASIStore) -> Result {
    let hits = store.searchAgentKnowledge(query, limit: 500)
    let deleted = store.deleteAgentKnowledgeSource(itemIds: hits.map { $0.item.id })
    let text = deleted == 0
      ? "No matching knowledge for \"\(query)\""
      : "Deleted \(deleted) matching knowledge items"
    return Result(text: text, actionId: "knowledge_forget")
  }

  private static func searchKnowledge(_ query: String, store: SignalASIStore) -> Result {
    let hits = store.searchAgentKnowledge(query, limit: 8)
    store.recordAgentKnowledgeSearch(query: query, hits: hits)
    guard !hits.isEmpty else {
      return Result(text: "No knowledge hits for \"\(query)\"", actionId: "knowledge_search")
    }
    let lines = hits.enumerated().flatMap { index, hit in
      [
        "[\(index + 1)] \(compact(hit.item.title, limit: 100))",
        "Source: \(sourceLabel(hit.item.source))",
        "Excerpt: \(compact(hit.excerpt, limit: 320))"
      ]
    }
    return Result(
      text: "Knowledge hits: \(hits.count)\n\(lines.joined(separator: "\n"))",
      actionId: "knowledge_search"
    )
  }

  private static func memoryMatches(_ item: AgentMemoryItem, query: String) -> Bool {
    let haystack = "\(item.kind.rawValue) \(item.key) \(item.value)".lowercased()
    let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace })
    return !tokens.isEmpty && tokens.allSatisfy { haystack.contains($0) }
  }

  private static func sourceLabel(_ source: String) -> String {
    let clean = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return "local" }
    if clean.hasPrefix("http://") || clean.hasPrefix("https://") { return String(clean.prefix(180)) }
    return compact(clean, limit: 140)
  }

  private static func compact(_ value: String, limit: Int) -> String {
    String(value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(limit))
  }

  private static func prefixedValue(_ value: String, prefixes: [String]) -> String? {
    let lower = value.lowercased()
    guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
    let clean = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
  }

  private static func isManagementCommand(_ normalized: String) -> Bool {
    [
      "remember",
      "save note",
      "save memory",
      "memorize",
      "forget memory",
      "delete memory",
      "remove memory",
      "forget note",
      "forget knowledge",
      "delete knowledge",
      "remove knowledge",
      "forget document",
      "delete document",
      "search knowledge",
      "find knowledge",
      "search memory",
      "find memory",
      "pause memory",
      "stop memory",
      "disable memory capture",
      "resume memory",
      "enable memory capture"
    ].contains { normalized == $0 || normalized.hasPrefix($0 + " ") }
  }
}
