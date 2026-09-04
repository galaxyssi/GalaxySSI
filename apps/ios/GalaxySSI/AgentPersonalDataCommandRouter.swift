import Foundation

@MainActor
enum AgentPersonalDataCommandRouter {
  struct Result {
    let text: String
    let actionId: String
  }

  static func handle(_ input: String, store: GalaxySSIStore) -> Result? {
    let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = command.lowercased()
    guard !command.isEmpty else { return nil }

    if let enabled = AgentMemoryCommandParser.memoryCaptureValue(fromGoal: command) {
      store.updateAgentSafetySettings { $0.memoryCapture = enabled }
      return Result(
        text: localized(
          store: store,
          english: enabled ? "Memory capture resumed" : "Memory capture paused",
          chinese: enabled ? "\u{8bb0}\u{5fc6}\u{6355}\u{83b7}\u{5df2}\u{6062}\u{590d}" : "\u{8bb0}\u{5fc6}\u{6355}\u{83b7}\u{5df2}\u{6682}\u{505c}"
        ),
        actionId: "memory_capture"
      )
    }
    if memoryOverviewCommands.contains(normalized) {
      return memoryOverview(store: store)
    }
    if knowledgeOverviewCommands.contains(normalized) {
      return knowledgeOverview(store: store)
    }
    if let query = prefixedValue(command, prefixes: knowledgeAnswerPrefixes) {
      return answerKnowledge(query, store: store)
    }
    if let value = AgentMemoryCommandParser.memoryValue(fromGoal: command) {
      return saveMemory(value, store: store)
    }
    if let query = prefixedValue(command, prefixes: [
      "forget memory ", "delete memory ", "remove memory ", "forget note ",
      "\u{5fd8}\u{8bb0}\u{8bb0}\u{5fc6} ", "\u{5220}\u{9664}\u{8bb0}\u{5fc6} ", "\u{5220}\u{9664}\u{7b14}\u{8bb0} "
    ]) {
      return forgetMemory(query, store: store)
    }
    if let query = prefixedValue(command, prefixes: [
      "forget knowledge ", "delete knowledge ", "remove knowledge ", "forget document ", "delete document ",
      "\u{5fd8}\u{8bb0}\u{77e5}\u{8bc6} ", "\u{5220}\u{9664}\u{77e5}\u{8bc6} ", "\u{5220}\u{9664}\u{6587}\u{6863} "
    ]) {
      return forgetKnowledge(query, store: store)
    }
    if let query = prefixedValue(command, prefixes: [
      "search knowledge ", "find knowledge ", "search memory ", "find memory ",
      "\u{641c}\u{7d22}\u{77e5}\u{8bc6} ", "\u{67e5}\u{627e}\u{77e5}\u{8bc6} ",
      "\u{641c}\u{7d22}\u{8bb0}\u{5fc6} ", "\u{67e5}\u{627e}\u{8bb0}\u{5fc6} "
    ]) {
      return searchKnowledge(query, store: store)
    }
    if isManagementCommand(normalized) {
      return Result(
        text: localized(
          store: store,
          english: "Memory commands: memory status; remember <value>; forget memory <query>; pause memory; resume memory. Knowledge commands: knowledge status; search knowledge <query>; ask knowledge <query>; forget knowledge <query>.",
          chinese: "\u{8bb0}\u{5fc6}\u{547d}\u{4ee4}\u{ff1a}\u{8bb0}\u{5fc6}\u{72b6}\u{6001}\u{ff1b}\u{8bb0}\u{4f4f} <\u{5185}\u{5bb9}>\u{ff1b}\u{5220}\u{9664}\u{8bb0}\u{5fc6} <\u{5173}\u{952e}\u{8bcd}>\u{ff1b}\u{6682}\u{505c}\u{8bb0}\u{5fc6}\u{ff1b}\u{6062}\u{590d}\u{8bb0}\u{5fc6}\u{3002}\u{77e5}\u{8bc6}\u{5e93}\u{547d}\u{4ee4}\u{ff1a}\u{77e5}\u{8bc6}\u{5e93}\u{72b6}\u{6001}\u{ff1b}\u{641c}\u{7d22}\u{77e5}\u{8bc6} <\u{5173}\u{952e}\u{8bcd}>\u{ff1b}\u{8be2}\u{95ee}\u{77e5}\u{8bc6} <\u{95ee}\u{9898}>\u{ff1b}\u{5220}\u{9664}\u{77e5}\u{8bc6} <\u{5173}\u{952e}\u{8bcd}>\u{3002}"
        ),
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
    "what do you remember",
    "\u{8bb0}\u{5fc6}\u{72b6}\u{6001}",
    "\u{67e5}\u{770b}\u{8bb0}\u{5fc6}",
    "\u{663e}\u{793a}\u{8bb0}\u{5fc6}",
    "\u{5217}\u{51fa}\u{8bb0}\u{5fc6}",
    "\u{6700}\u{8fd1}\u{8bb0}\u{5fc6}",
    "\u{4f60}\u{8bb0}\u{5f97}\u{4ec0}\u{4e48}"
  ]

  private static let knowledgeOverviewCommands: Set<String> = [
    "knowledge status",
    "knowledge base status",
    "show knowledge",
    "list knowledge",
    "recent knowledge",
    "show recent knowledge",
    "\u{77e5}\u{8bc6}\u{72b6}\u{6001}",
    "\u{77e5}\u{8bc6}\u{5e93}\u{72b6}\u{6001}",
    "\u{67e5}\u{770b}\u{77e5}\u{8bc6}",
    "\u{663e}\u{793a}\u{77e5}\u{8bc6}",
    "\u{5217}\u{51fa}\u{77e5}\u{8bc6}",
    "\u{6700}\u{8fd1}\u{77e5}\u{8bc6}"
  ]

  private static let knowledgeAnswerPrefixes: [String] = [
    "ask knowledge ",
    "answer from knowledge ",
    "use knowledge to answer ",
    "ask my knowledge ",
    "\u{8be2}\u{95ee}\u{77e5}\u{8bc6} ",
    "\u{7528}\u{77e5}\u{8bc6}\u{56de}\u{7b54} ",
    "\u{8bf7}\u{56de}\u{7b54}\u{77e5}\u{8bc6} "
  ]

  private static func memoryOverview(store: GalaxySSIStore) -> Result {
    let snapshot = store.agentMemorySnapshot()
    let recent = snapshot.activeItems
      .sorted { $0.timestampMillis > $1.timestampMillis }
      .prefix(10)
    var lines = [localized(
      store: store,
      english: "Personal memory: \(snapshot.activeCount); conflicts=\(snapshot.conflicts.count); capture=\(store.agentSafetySettings.memoryCapture ? "on" : "paused")",
      chinese: "\u{4e2a}\u{4eba}\u{8bb0}\u{5fc6}\u{ff1a}\(snapshot.activeCount) \u{6761}\u{ff1b}\u{51b2}\u{7a81}=\(snapshot.conflicts.count)\u{ff1b}\u{6355}\u{83b7}=\(store.agentSafetySettings.memoryCapture ? "\u{5f00}\u{542f}" : "\u{6682}\u{505c}")"
    )]
    if recent.isEmpty {
      lines.append(localized(store: store, english: "No saved memories", chinese: "\u{6ca1}\u{6709}\u{5df2}\u{4fdd}\u{5b58}\u{7684}\u{8bb0}\u{5fc6}"))
    } else {
      lines.append(contentsOf: recent.map { item in
        "\(memoryKindLabel(item.kind, store: store)): \(compact(item.value, limit: 120))"
      })
    }
    return Result(text: lines.joined(separator: "\n"), actionId: "memory_overview")
  }

  private static func knowledgeOverview(store: GalaxySSIStore) -> Result {
    let stats = store.agentKnowledgeStats
    let groups = store.agentKnowledgeSourceGroups().prefix(10)
    var lines = [localized(
      store: store,
      english: "Knowledge base: \(stats.itemCount) items; sources=\(stats.sourceCount)",
      chinese: "\u{77e5}\u{8bc6}\u{5e93}\u{ff1a}\(stats.itemCount) \u{6761}\u{ff1b}\u{6765}\u{6e90}=\(stats.sourceCount)"
    )]
    if groups.isEmpty {
      lines.append(localized(store: store, english: "No knowledge items", chinese: "\u{6ca1}\u{6709}\u{77e5}\u{8bc6}\u{6761}\u{76ee}"))
    } else {
      lines.append(contentsOf: groups.map { group in
        "\(group.title) [\(compact(group.source, limit: 48))]"
      })
    }
    return Result(text: lines.joined(separator: "\n"), actionId: "knowledge_overview")
  }

  private static func saveMemory(_ value: String, store: GalaxySSIStore) -> Result {
    guard store.agentSafetySettings.memoryCapture else {
      return Result(text: localized(store: store, english: "Memory capture is paused", chinese: "\u{8bb0}\u{5fc6}\u{6355}\u{83b7}\u{5df2}\u{6682}\u{505c}"), actionId: "memory_save")
    }
    let write = store.rememberAgentMemory(AgentMemoryCommandParser.item(fromCommand: value))
    if write.conflict != nil {
      return Result(text: localized(store: store, english: "Memory conflict needs review", chinese: "\u{8bb0}\u{5fc6}\u{51b2}\u{7a81}\u{9700}\u{8981}\u{5ba1}\u{67e5}"), actionId: "memory_save")
    }
    if write.duplicate {
      return Result(text: localized(store: store, english: "Memory already saved", chinese: "\u{8bb0}\u{5fc6}\u{5df2}\u{4fdd}\u{5b58}"), actionId: "memory_save")
    }
    return Result(text: localized(store: store, english: "Saved personal memory", chinese: "\u{5df2}\u{4fdd}\u{5b58}\u{4e2a}\u{4eba}\u{8bb0}\u{5fc6}"), actionId: "memory_save")
  }

  private static func forgetMemory(_ query: String, store: GalaxySSIStore) -> Result {
    let matches = store.agentMemorySnapshot().activeItems.filter { memoryMatches($0, query: query) }
    let deleted = matches.reduce(0) { count, item in
      count + (store.deleteAgentMemory(id: item.id) ? 1 : 0)
    }
    let text = localized(
      store: store,
      english: deleted == 0 ? "No matching memory for \"\(query)\"" : "Deleted \(deleted) matching memory items",
      chinese: deleted == 0 ? "\u{6ca1}\u{6709}\u{5339}\u{914d}\u{201c}\(query)\u{201d}\u{7684}\u{8bb0}\u{5fc6}" : "\u{5df2}\u{5220}\u{9664} \(deleted) \u{6761}\u{5339}\u{914d}\u{7684}\u{8bb0}\u{5fc6}"
    )
    return Result(text: text, actionId: "memory_forget")
  }

  private static func forgetKnowledge(_ query: String, store: GalaxySSIStore) -> Result {
    let hits = store.searchAgentKnowledge(query, limit: 500)
    let deleted = store.deleteAgentKnowledgeSource(itemIds: hits.map { $0.item.id })
    let text = localized(
      store: store,
      english: deleted == 0 ? "No matching knowledge for \"\(query)\"" : "Deleted \(deleted) matching knowledge items",
      chinese: deleted == 0 ? "\u{6ca1}\u{6709}\u{5339}\u{914d}\u{201c}\(query)\u{201d}\u{7684}\u{77e5}\u{8bc6}" : "\u{5df2}\u{5220}\u{9664} \(deleted) \u{6761}\u{5339}\u{914d}\u{7684}\u{77e5}\u{8bc6}"
    )
    return Result(text: text, actionId: "knowledge_forget")
  }

  private static func searchKnowledge(_ query: String, store: GalaxySSIStore) -> Result {
    let hits = store.searchAgentKnowledge(query, limit: 8)
    store.recordAgentKnowledgeSearch(query: query, hits: hits)
    guard !hits.isEmpty else {
      return Result(
        text: localized(store: store, english: "No knowledge hits for \"\(query)\"", chinese: "\u{6ca1}\u{6709}\u{5339}\u{914d}\u{201c}\(query)\u{201d}\u{7684}\u{77e5}\u{8bc6}"),
        actionId: "knowledge_search"
      )
    }
    let lines = hits.enumerated().flatMap { index, hit in
      let sourceTitle = localized(store: store, english: "Source", chinese: "\u{6765}\u{6e90}")
      let excerptTitle = localized(store: store, english: "Excerpt", chinese: "\u{6458}\u{8981}")
      return [
        "[\(index + 1)] \(compact(hit.item.title, limit: 100))",
        "\(sourceTitle): \(sourceLabel(hit.item.source))",
        "\(excerptTitle): \(compact(hit.excerpt, limit: 320))"
      ]
    }
    return Result(
      text: localized(
        store: store,
        english: "Knowledge hits: \(hits.count)\n\(lines.joined(separator: "\n"))",
        chinese: "\u{77e5}\u{8bc6}\u{5339}\u{914d}\u{ff1a}\(hits.count)\n\(lines.joined(separator: "\n"))"
      ),
      actionId: "knowledge_search"
    )
  }

  private static func answerKnowledge(_ query: String, store: GalaxySSIStore) -> Result {
    let rankedHits = store.searchAgentKnowledge(query, limit: 24)
    let rag = AgentKnowledgeRetriever.retrieve(
      hits: rankedHits,
      query: query,
      targetId: "agent-knowledge-local",
      limit: 6
    )
    var modes: [AgentKnowledgeEvidenceMode] = []
    rag.citations.forEach { citation in
      if !modes.contains(citation.evidenceMode) { modes.append(citation.evidenceMode) }
    }
    store.recordAgentKnowledgeSearch(
      query: query,
      hits: rag.matchedHits,
      targetId: rag.targetId,
      evidenceModes: modes,
      blockedMatchCount: rag.blockedMatchCount
    )
    guard !rag.citations.isEmpty else {
      let text = localized(
        store: store,
        english: rag.blockedMatchCount > 0
          ? "Matching knowledge exists, but its access policy does not allow this local answer."
          : "No knowledge evidence for \"\(query)\"",
        chinese: rag.blockedMatchCount > 0
          ? "\u{5b58}\u{5728}\u{5339}\u{914d}\u{7684}\u{77e5}\u{8bc6}\u{ff0c}\u{4f46}\u{5176}\u{8bbf}\u{95ee}\u{7b56}\u{7565}\u{4e0d}\u{5141}\u{8bb8}\u{672c}\u{5730}\u{56de}\u{7b54}\u{3002}"
          : "\u{6ca1}\u{6709}\u{5173}\u{4e8e}\u{201c}\(query)\u{201d}\u{7684}\u{77e5}\u{8bc6}\u{8bc1}\u{636e}"
      )
      return Result(
        text: text,
        actionId: "knowledge_answer"
      )
    }
    let lines = rag.citations.flatMap { citation in
      let sourceTitle = localized(store: store, english: "Source", chinese: "\u{6765}\u{6e90}")
      let evidenceTitle = localized(store: store, english: "Evidence", chinese: "\u{8bc1}\u{636e}")
      let evidenceMode = evidenceModeLabel(citation.evidenceMode, store: store)
      return [
        "[\(citation.index)] \(compact(citation.title, limit: 100))",
        "\(sourceTitle): \(citation.source)",
        "\(evidenceTitle) (\(evidenceMode)): \(compact(citation.excerpt, limit: 420))"
      ]
    }
    return Result(
      text: localized(
        store: store,
        english: "Knowledge answer from local evidence for \"\(compact(query, limit: 160))\":\n\(lines.joined(separator: "\n"))",
        chinese: "\u{57fa}\u{4e8e}\u{672c}\u{5730}\u{77e5}\u{8bc6}\u{5bf9}\u{201c}\(compact(query, limit: 160))\u{201d}\u{7684}\u{56de}\u{7b54}\u{ff1a}\n\(lines.joined(separator: "\n"))"
      ),
      actionId: "knowledge_answer"
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

  private static func memoryKindLabel(_ kind: AgentMemoryKind, store: GalaxySSIStore) -> String {
    let chinese: String
    switch kind {
    case .identity: chinese = "\u{8eab}\u{4efd}"
    case .contact: chinese = "\u{8054}\u{7cfb}\u{4eba}"
    case .task: chinese = "\u{4efb}\u{52a1}"
    case .preference: chinese = "\u{504f}\u{597d}"
    case .workflow: chinese = "\u{5de5}\u{4f5c}\u{6d41}"
    case .safety: chinese = "\u{5b89}\u{5168}"
    case .knowledge: chinese = "\u{77e5}\u{8bc6}"
    }
    return localized(store: store, english: kind.rawValue.lowercased(), chinese: chinese)
  }

  private static func evidenceModeLabel(_ mode: AgentKnowledgeEvidenceMode, store: GalaxySSIStore) -> String {
    let chinese: String
    switch mode {
    case .full: chinese = "\u{5b8c}\u{6574}"
    case .summary: chinese = "\u{6458}\u{8981}"
    }
    return localized(store: store, english: mode.rawValue.lowercased(), chinese: chinese)
  }

  private static func localized(store: GalaxySSIStore, english: String, chinese: String) -> String {
    LanguagePolicySettings.resolve(store.languagePolicy.responseLanguage).hasPrefix("zh") ? chinese : english
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
      "ask knowledge",
      "answer from knowledge",
      "use knowledge to answer",
      "ask my knowledge",
      "pause memory",
      "stop memory",
      "disable memory capture",
      "resume memory",
      "enable memory capture",
      "\u{8bb0}\u{5fc6}",
      "\u{4fdd}\u{5b58}\u{8bb0}\u{5fc6}",
      "\u{4fdd}\u{5b58}\u{7b14}\u{8bb0}",
      "\u{5fd8}\u{8bb0}\u{8bb0}\u{5fc6}",
      "\u{5220}\u{9664}\u{8bb0}\u{5fc6}",
      "\u{5220}\u{9664}\u{7b14}\u{8bb0}",
      "\u{5fd8}\u{8bb0}\u{77e5}\u{8bc6}",
      "\u{5220}\u{9664}\u{77e5}\u{8bc6}",
      "\u{5220}\u{9664}\u{6587}\u{6863}",
      "\u{641c}\u{7d22}\u{77e5}\u{8bc6}",
      "\u{67e5}\u{627e}\u{77e5}\u{8bc6}",
      "\u{641c}\u{7d22}\u{8bb0}\u{5fc6}",
      "\u{67e5}\u{627e}\u{8bb0}\u{5fc6}",
      "\u{8be2}\u{95ee}\u{77e5}\u{8bc6}",
      "\u{7528}\u{77e5}\u{8bc6}\u{56de}\u{7b54}",
      "\u{8bf7}\u{56de}\u{7b54}\u{77e5}\u{8bc6}",
      "\u{6682}\u{505c}\u{8bb0}\u{5fc6}",
      "\u{505c}\u{6b62}\u{8bb0}\u{5fc6}",
      "\u{5173}\u{95ed}\u{8bb0}\u{5fc6}\u{6355}\u{83b7}",
      "\u{6062}\u{590d}\u{8bb0}\u{5fc6}",
      "\u{5f00}\u{542f}\u{8bb0}\u{5fc6}\u{6355}\u{83b7}"
    ].contains { normalized == $0 || normalized.hasPrefix($0 + " ") }
  }
}
