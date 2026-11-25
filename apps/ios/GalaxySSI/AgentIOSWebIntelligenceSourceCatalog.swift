import Foundation

enum AgentIOSWebIntelligenceVertical: String, CaseIterable, Identifiable, Hashable {
  case general
  case regional
  case news
  case knowledge
  case publishing
  case code
  case docs
  case packages
  case qa
  case community
  case social
  case academic
  case researchIndex = "research_index"
  case medical
  case healthcare
  case biology
  case technology
  case agents
  case hardware
  case image
  case video
  case travel
  case lifestyle
  case games
  case shopping
  case finance
  case business
  case sports
  case weather
  case mapsLocal = "maps_local"
  case food
  case education
  case jobs
  case government
  case legal
  case patents
  case books
  case audio
  case entertainment
  case cybersecurity
  case aiModels = "ai_models"
  case datasets
  case automotive
  case realEstate = "real_estate"
  case events
  case smartHome = "smart_home"
  case local

  var id: String { rawValue }
}

struct AgentIOSWebIntelligenceSourceLearningStats: Equatable {
  var learnedSourceCount: Int
  var verifiedLearnedSourceCount: Int
  var available = true

  var candidateSourceCount: Int {
    max(0, learnedSourceCount - verifiedLearnedSourceCount)
  }
}

struct AgentIOSWebIntelligenceSourceSummary: Equatable {
  var sourceCount: Int
  var baseSearchEngineCount: Int
  var indexedSourceCount: Int
  var domainCategoryCount: Int
  var learningStats: AgentIOSWebIntelligenceSourceLearningStats
}

struct AgentIOSWebIntelligenceSourceSpec: Equatable {
  var id: String
  var title: String
  var vertical: AgentIOSWebIntelligenceVertical
  var allowedHosts: [String]
  var authority: Double
  var categoryTags: Set<String> = []
  var indexEngine = "bing"
  var scope: String? = nil
  var languages: Set<String> = ["*"]
  var enabledByDefault = true
}

struct AgentIOSWebIntelligenceSourceSelection: Equatable {
  var selected: [AgentIOSWebIntelligenceSourceSpec]
  var inferredVerticals: Set<AgentIOSWebIntelligenceVertical>
  var strategy: String
}

enum AgentIOSWebIntelligenceQueryRouting {
  static func select(
    query: String,
    requestedVerticals: Set<AgentIOSWebIntelligenceVertical>,
    requestedEngineIds: Set<String>,
    requestedCategories: Set<String> = [],
    learnedSources: [AgentIOSLearnedWebSource] = []
  ) -> AgentIOSWebIntelligenceSourceSelection {
    let learned = learnedSources.filter(\.isSearchEligible).sorted { $0.sourceID < $1.sourceID }
      .enumerated().compactMap { $0.element.searchSpec(index: $0.offset + AgentIOSWebIntelligenceSourceCatalog.sourceCount) }
    let catalog = AgentIOSJSONWebSearchAdapter.entries.map(\.spec) + AgentIOSHTMLWebSearchAdapter.entries.map(\.spec) +
      [AgentIOSArxivSearchAdapter.entry.spec, AgentIOSDevDocsSearchAdapter.entry.spec] +
      AgentIOSWebIntelligenceSourceCatalog.indexedSources + learned
    let categories = Set(requestedCategories.compactMap(AgentIOSWebResearchPlanCodec.normalizedCategory))
    let explicit = catalog.filter {
      requestedEngineIds.contains($0.id)
    }
    let candidates = explicit.isEmpty
      ? catalog.filter {
        $0.enabledByDefault && (requestedVerticals.contains($0.vertical) || categories.contains($0.vertical.rawValue) ||
          !categories.isDisjoint(with: $0.categoryTags))
      }
      : explicit
    let language = queryLanguage(query)
    func score(_ source: AgentIOSWebIntelligenceSourceSpec) -> Double {
      let languageMatch = source.languages.contains(language) ? 2.0 : (source.languages.contains("*") ? 0.8 : -1.5)
      return (requestedVerticals.contains(source.vertical) ? 2.5 : 0) +
        (!categories.isDisjoint(with: source.categoryTags) ? 2.0 : 0) + languageMatch + source.authority * 0.5
    }
    let ranked = candidates.indices.sorted { left, right in
      let leftScore = score(candidates[left]), rightScore = score(candidates[right])
      return leftScore == rightScore ? left < right : leftScore > rightScore
    }.map { candidates[$0] }
    var selected: [AgentIOSWebIntelligenceSourceSpec] = []
    var seen = Set<String>()
    if requestedEngineIds.isEmpty {
      for category in categories.sorted() {
        if let source = ranked.first(where: { $0.categoryTags.contains(category) }), seen.insert(source.id).inserted {
          selected.append(source)
        }
      }
      for vertical in requestedVerticals.sorted(by: { $0.rawValue < $1.rawValue }) {
        if let source = ranked.first(where: { $0.vertical == vertical }), seen.insert(source.id).inserted {
          selected.append(source)
        }
      }
    }
    for source in ranked where seen.insert(source.id).inserted { selected.append(source) }
    return AgentIOSWebIntelligenceSourceSelection(
      selected: selected,
      inferredVerticals: [],
      strategy: !requestedVerticals.isEmpty || !requestedEngineIds.isEmpty || !categories.isEmpty
        ? "model_selected_topics"
        : "broad_unscoped"
    )
  }

  static func queryLanguage(_ query: String) -> String {
    let scalars = query.unicodeScalars.map(\.value)
    if scalars.contains(where: { (0x3400...0x9fff).contains($0) }) { return "zh" }
    if scalars.contains(where: { (0x3040...0x30ff).contains($0) }) { return "ja" }
    if scalars.contains(where: { (0xac00...0xd7af).contains($0) }) { return "ko" }
    return "en"
  }
}

enum AgentIOSWebIntelligenceSourceCatalog {
  static let baseSearchEngineIDs: Set<String> = Set(["bing", "baidu", "duckduckgo", "sogou_image", "brave_image", "duckduckgo_image"])
    .union(AgentIOSJSONWebSearchAdapter.entries.map(\.id))
    .union(AgentIOSHTMLWebSearchAdapter.entries.map(\.id))
    .union([AgentIOSArxivSearchAdapter.entry.id, AgentIOSDevDocsSearchAdapter.entry.id])
  static let indexedSources = AgentIOSIndexedWebSourceCatalog.sources
  static var baseSearchEngineCount: Int { baseSearchEngineIDs.count }
  static var indexedSourceCount: Int { indexedSources.count }
  static var sourceCount: Int { baseSearchEngineCount + indexedSourceCount }
  static var officialDocumentationSources: [AgentIOSWebIntelligenceSourceSpec] { indexedSources.filter { $0.vertical == .docs } }

  static var domainCategoryCount: Int {
    Set(indexedSources.map(\.vertical)).union([.general, .regional, .image]).count
  }

  static func summary(
    learningStats: AgentIOSWebIntelligenceSourceLearningStats = AgentIOSWebIntelligenceLearningStore().stats()
  ) -> AgentIOSWebIntelligenceSourceSummary {
    AgentIOSWebIntelligenceSourceSummary(
      sourceCount: sourceCount,
      baseSearchEngineCount: baseSearchEngineCount,
      indexedSourceCount: indexedSourceCount,
      domainCategoryCount: domainCategoryCount,
      learningStats: learningStats
    )
  }
}

final class AgentIOSWebIntelligenceLearningStore {
  private let cacheStore: AgentIOSWebIntelligenceCacheStore

  init(cacheStore: AgentIOSWebIntelligenceCacheStore = .shared) {
    self.cacheStore = cacheStore
  }

  func stats() -> AgentIOSWebIntelligenceSourceLearningStats {
    guard let sources = cacheStore.learnedSources() else {
      return AgentIOSWebIntelligenceSourceLearningStats(learnedSourceCount: 0, verifiedLearnedSourceCount: 0, available: false)
    }
    return AgentIOSWebIntelligenceSourceLearningStats(
      learnedSourceCount: sources.count,
      verifiedLearnedSourceCount: sources.filter { $0.status == "verified" }.count
    )
  }
}

enum AgentIOSWebIntelligenceCredentialKey: String, CaseIterable, Identifiable {
  case braveAPIKey = "brave_api_key"
  case githubToken = "github_token"

  var id: String { rawValue }

  var account: String {
    "web_intelligence.\(rawValue)"
  }

  var titleKey: String {
    switch self {
    case .braveAPIKey:
      return "web_sources_brave_key"
    case .githubToken:
      return "web_sources_github_token"
    }
  }

  var titleFallback: String {
    switch self {
    case .braveAPIKey:
      return "Brave Search API key"
    case .githubToken:
      return "GitHub token"
    }
  }

  var subtitleKey: String {
    switch self {
    case .braveAPIKey:
      return "web_sources_brave_key_subtitle"
    case .githubToken:
      return "web_sources_github_token_subtitle"
    }
  }

  var subtitleFallback: String {
    switch self {
    case .braveAPIKey:
      return "Optional; enables Brave Image search"
    case .githubToken:
      return "Optional; raises repository and code-search rate limits"
    }
  }

  var systemImage: String {
    switch self {
    case .braveAPIKey:
      return "photo.on.rectangle.angled"
    case .githubToken:
      return "chevron.left.forwardslash.chevron.right"
    }
  }
}

struct AgentIOSWebIntelligenceCredentials {
  var secrets: GalaxySSISecretStore = KeychainSecretStore.shared

  func credential(_ key: AgentIOSWebIntelligenceCredentialKey) -> String {
    secrets.string(account: key.account)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  func configured(_ key: AgentIOSWebIntelligenceCredentialKey) -> Bool {
    !credential(key).isEmpty
  }

  func setCredential(_ key: AgentIOSWebIntelligenceCredentialKey, value: String) throws {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty {
      secrets.delete(account: key.account)
    } else {
      try secrets.setString(clean, account: key.account)
    }
  }
}
