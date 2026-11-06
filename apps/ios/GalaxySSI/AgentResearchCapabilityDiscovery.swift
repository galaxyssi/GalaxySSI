import Foundation

enum AgentResearchCapabilityDiscovery {
  static let orderedTools = [
    AgentIOSWebIntelligenceNativeToolCatalog.search,
    AgentIOSWebMediaNativeToolCatalog.webSearch,
    AgentIOSWebIntelligenceNativeToolCatalog.fetch,
    AgentIOSWebIntelligenceNativeToolCatalog.extract
  ]

  static func isResearchRequest(_ request: AgentModelPlanningPromptRequest) -> Bool {
    let goal = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(request.planRequest.goal)
    let tags = terms(goal)
    return AgentExecutionProfile.forGoal(goal, executionMode: request.planRequest.executionMode).taskKind == .research ||
      (tags.contains("search") && !tags.isDisjoint(with: ["image", "images", "photo", "photos"]))
  }

  static func isResearchTool(_ descriptor: AgentNativeToolDescriptor) -> Bool {
    orderedTools.contains(descriptor.id) && AgentScreenAnalysisToolPolicy.allows(descriptor)
  }

  static func hasOnlyResearchConsent(_ descriptor: AgentNativeToolDescriptor) -> Bool {
    guard isResearchTool(descriptor) else { return false }
    return descriptor.requiredConsents.filter(\.required).allSatisfy {
      [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent,
       AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent].contains($0.id)
    }
  }

  static func matches(_ query: String, metadata: [String]) -> Bool {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return true }
    let searchable = metadata.joined(separator: " ").lowercased()
    let words = terms(clean)
    return !words.isEmpty && words.allSatisfy { word in
      if searchable.contains(word) { return true }
      guard word.count >= 2, word.unicodeScalars.allSatisfy({ !$0.isASCII }) else { return false }
      let characters = Array(word)
      return zip(characters, characters.dropFirst()).contains { left, right in
        searchable.contains(String([left, right]))
      }
    }
  }

  static func matches(_ query: String, tool: AgentNativeToolDescriptor) -> Bool {
    let verticals = tool.id == AgentIOSWebIntelligenceNativeToolCatalog.search ? "image photo news search" : ""
    return matches(query, metadata: [tool.id, tool.title, tool.description, tool.risk.rawValue,
                                    tool.capabilities.sorted().joined(separator: " "), verticals])
  }

  private static func terms(_ query: String) -> Set<String> {
    let lower = query.lowercased()
    let translated = aliases.compactMap { lower.contains($0.key) ? $0.value : nil }
    let pattern = translated.isEmpty ? #"[a-z0-9_.-]+|\p{Han}+"# : #"[a-z0-9_.-]+"#
    let words = (try? NSRegularExpression(pattern: pattern))?
      .matches(in: lower, range: NSRange(lower.startIndex..., in: lower))
      .compactMap { Range($0.range, in: lower).map { String(lower[$0]) } } ?? []
    return Set((words + translated).filter { !ignoredWords.contains($0) })
  }

  private static let ignoredWords: Set<String> = [
    "a", "an", "the", "for", "can", "i", "which", "find", "tool", "tools", "capability", "capabilities"
  ]
  private static let aliases = [
    "\u{641c}\u{7d22}": "search", "\u{67e5}\u{8be2}": "search", "\u{67e5}\u{627e}": "search",
    "\u{7f51}\u{9875}": "web", "\u{7f51}\u{7ad9}": "web", "\u{56fe}\u{7247}": "image",
    "\u{7167}\u{7247}": "image", "\u{65b0}\u{95fb}": "news", "\u{8d44}\u{6599}": "research",
    "\u{6d4f}\u{89c8}\u{5668}": "browser", "\u{6587}\u{4ef6}": "file", "\u{4e0b}\u{8f7d}": "download",
    "\u{8bfb}\u{53d6}": "read", "\u{5b89}\u{88c5}": "install", "\u{63d0}\u{53d6}": "extract"
  ]
}

enum AgentSearchResponseQuality {
  static func signals(_ value: String) -> Set<String> {
    let normalized = (value.removingPercentEncoding ?? value).lowercased()
    guard let regex = try? NSRegularExpression(pattern: #"[a-z0-9]+|\p{Han}+"#) else { return [] }
    let words = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap {
      Range($0.range, in: normalized).map { String(normalized[$0]) }
    }
    return Set(words.flatMap { word -> [String] in
      guard word.count > 1, !stopWords.contains(word) else { return [] }
      if word.unicodeScalars.allSatisfy(\.isASCII) { return [word] }
      return zip(word, word.dropFirst()).map { String([$0.0, $0.1]) }
    })
  }

  static func isDisjoint(querySignals: Set<String>, candidates: [String]) -> Bool {
    querySignals.count >= 2 && !candidates.isEmpty &&
      candidates.allSatisfy { querySignals.isDisjoint(with: signals($0)) }
  }

  private static let stopWords: Set<String> = ["https", "http", "www", "com", "org", "and", "the", "for", "with"]
}
