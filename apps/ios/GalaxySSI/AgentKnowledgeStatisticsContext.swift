import Foundation

enum AgentKnowledgeStatisticsContext {
  static func resolve(_ indexed: AgentKnowledgeStats?) -> AgentKnowledgeStats {
    indexed ?? AgentKnowledgeStats(countsComplete: false, countsUnavailable: true)
  }
  static func capture(for request: AgentModelPlanningPromptRequest, read: () -> AgentKnowledgeStats) -> AgentKnowledgeStats? {
    guard !request.conversationContext.privateMode, request.requirements.capabilities.contains(.knowledgeSearch) else { return nil }
    return read()
  }
  static func parameters(_ stats: AgentKnowledgeStats) -> [String: String] {
    var values = ["counts_complete": String(stats.countsComplete),
      "knowledge_count_status": stats.countsUnavailable ? "unavailable" : (stats.countsComplete ? "complete" : "partial_indexing")]
    if !stats.countsUnavailable {
      values["item_count"] = String(stats.itemCount)
      values["source_count"] = String(stats.sourceCount)
      values["last_updated_at_millis"] = String(stats.lastUpdatedAtMillis)
    }
    return values
  }
  static func summary(_ stats: AgentKnowledgeStats, language: String) -> String {
    if stats.countsUnavailable { return text("knowledge_stats_unavailable", fallback: "Knowledge statistics are unavailable", language: language) }
    let key = stats.countsComplete ? "knowledge_stats_complete" : "knowledge_stats_partial"
    let fallback = stats.countsComplete ? "Knowledge base: %lld items; sources=%lld" :
      "Knowledge base: at least %lld items; at least %lld sources; counts are still indexing"
    return String(format: text(key, fallback: fallback, language: language), Int64(stats.itemCount), Int64(stats.sourceCount))
  }
  static func text(_ key: String, fallback: String, language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: LanguagePolicySettings.resolve(language))
  }
}
