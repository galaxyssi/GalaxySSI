import Foundation

struct AgentIOSWebResearchQueryPlanItem: Equatable {
  var query: String
  var purpose: String = ""
  var verticals: Set<String> = []
  var categories: Set<String> = []
  var engines: [String] = []

  var publicValue: AgentMcpJSONObject {
    [
      "query": .string(query),
      "purpose": .string(purpose),
      "verticals": .array(verticals.sorted().map(AgentMcpJSONValue.string)),
      "categories": .array(categories.sorted().map(AgentMcpJSONValue.string)),
      "engines": .array(engines.map(AgentMcpJSONValue.string))
    ]
  }
}

struct AgentIOSWebResearchQueryCoverage: Equatable {
  var item: AgentIOSWebResearchQueryPlanItem
  var candidateURLs: Set<String>
  var retrievedURLs: Set<String>
  var sourceIDs: Set<String>
  var completedSources: Int
  var failedSources: Int

  var status: String {
    if !retrievedURLs.isEmpty { return "covered" }
    if !candidateURLs.isEmpty { return "discovered_only" }
    return "unresolved"
  }

  var publicValue: AgentMcpJSONObject {
    let domains = Set(retrievedURLs.compactMap { url in
      URL(string: url)?.host?.lowercased().replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    })
    return [
      "query": .string(item.query),
      "purpose": .string(item.purpose),
      "status": .string(status),
      "candidate_count": .int(Int64(candidateURLs.count)),
      "retrieved_document_count": .int(Int64(retrievedURLs.count)),
      "independent_domain_count": .int(Int64(domains.count)),
      "source_ids": .array(sourceIDs.sorted().map(AgentMcpJSONValue.string)),
      "sources_completed": .int(Int64(max(0, completedSources))),
      "sources_failed": .int(Int64(max(0, failedSources)))
    ]
  }
}

enum AgentIOSWebResearchPlanCodec {
  static let maximumItems = 32
  static let maximumQueryCharacters = 4_096
  static let maximumPurposeCharacters = 512
  static let maximumCategories = 32
  static let maximumEngines = 32

  static func decode(
    primaryQuery: String,
    rawPlan: AgentMcpJSONValue?,
    allowedVerticals: Set<String>
  ) -> [AgentIOSWebResearchQueryPlanItem] {
    var seen = Set<String>()
    let explicit = (rawPlan?.arrayValue ?? []).prefix(maximumItems).compactMap { value -> AgentIOSWebResearchQueryPlanItem? in
      let item: AgentIOSWebResearchQueryPlanItem?
      if let query = value.stringValue {
        let cleaned = clean(query, limit: maximumQueryCharacters)
        item = cleaned.isEmpty ? nil : AgentIOSWebResearchQueryPlanItem(query: cleaned)
      } else if let object = value.objectValue {
        item = decodeItem(object, allowedVerticals: allowedVerticals)
      } else {
        item = nil
      }
      guard let item else { return nil }
      let key = clean(item.query.lowercased(), limit: maximumQueryCharacters)
      return seen.insert(key).inserted ? item : nil
    }
    if !explicit.isEmpty { return explicit }
    return [AgentIOSWebResearchQueryPlanItem(query: clean(primaryQuery, limit: maximumQueryCharacters))]
  }

  static func roundRobinResults(
    _ groups: [[AgentMcpJSONObject]]
  ) -> [AgentMcpJSONObject] {
    let maximum = groups.map(\.count).max() ?? 0
    var merged: [AgentMcpJSONObject] = []
    var seen = Set<String>()
    for index in 0..<maximum {
      for group in groups where index < group.count {
        let item = group[index]
        let url = AgentIOSWebEvidencePack.canonicalURL(item["url"]?.stringValue ?? "")
        if !url.isEmpty, seen.insert(url).inserted {
          merged.append(item)
        }
      }
    }
    return merged
  }

  static func normalizedCategory(_ value: String) -> String? {
    let normalized = clean(value.lowercased(), limit: 64)
    guard !normalized.isEmpty,
          normalized.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else {
      return nil
    }
    return normalized
  }

  private static func decodeItem(
    _ value: AgentMcpJSONObject,
    allowedVerticals: Set<String>
  ) -> AgentIOSWebResearchQueryPlanItem? {
    let query = clean(value["query"]?.stringValue ?? "", limit: maximumQueryCharacters)
    guard !query.isEmpty else { return nil }
    let verticals = Set(strings(value["verticals"], maximum: allowedVerticals.count).compactMap { raw -> String? in
      let normalized = raw.lowercased()
      return allowedVerticals.contains(normalized) ? normalized : nil
    })
    let categories = Set(strings(value["categories"], maximum: maximumCategories).compactMap(normalizedCategory))
    let engines = strings(value["engines"], maximum: maximumEngines).compactMap { raw -> String? in
      let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return normalized.range(of: #"^[a-z0-9][a-z0-9_-]{0,63}$"#, options: .regularExpression) == nil
        ? nil
        : normalized
    }.reduce(into: [String]()) { values, engine in
      if !values.contains(engine) { values.append(engine) }
    }
    return AgentIOSWebResearchQueryPlanItem(
      query: query,
      purpose: clean(value["purpose"]?.stringValue ?? "", limit: maximumPurposeCharacters),
      verticals: verticals,
      categories: categories,
      engines: engines
    )
  }

  private static func strings(_ value: AgentMcpJSONValue?, maximum: Int) -> [String] {
    Array((value?.arrayValue ?? []).compactMap(\.stringValue).prefix(max(0, maximum)))
  }

  private static func clean(_ value: String, limit: Int) -> String {
    String(
      value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(max(0, limit))
    )
  }
}
