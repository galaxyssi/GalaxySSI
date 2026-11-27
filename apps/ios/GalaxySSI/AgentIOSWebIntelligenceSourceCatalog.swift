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
  var skipped: [AgentIOSWebSourceHealth] = []
}

enum AgentIOSWebIntelligenceQueryRouting {
  static func select(
    query: String,
    requestedVerticals: Set<AgentIOSWebIntelligenceVertical>,
    requestedEngineIds: Set<String>,
    requestedCategories: Set<String> = [],
    learnedSources: [AgentIOSLearnedWebSource] = [],
    requestedEngineOrder: [String] = [],
    health: [String: AgentIOSWebSourceHealth] = [:],
    fanout: Int = 32,
    nowMillis: Int64 = 0,
    braveImageKeyAvailable: Bool = false
  ) -> AgentIOSWebIntelligenceSourceSelection {
    let learned = learnedSources.filter(\.isSearchEligible).sorted { $0.sourceID < $1.sourceID }
      .enumerated().compactMap { $0.element.searchSpec(index: $0.offset + AgentIOSWebIntelligenceSourceCatalog.sourceCount) }
    let catalog = orderedSources + learned
    let categories = Set(requestedCategories.compactMap(AgentIOSWebResearchPlanCodec.normalizedCategory))
    let limit = min(32, max(1, fanout))
    if !requestedEngineIds.isEmpty {
      var seen = Set<String>()
      let requested = requestedEngineOrder.isEmpty ? requestedEngineIds.sorted() : requestedEngineOrder
      let selected = requested.compactMap { id -> AgentIOSWebIntelligenceSourceSpec? in
        guard requestedEngineIds.contains(id), seen.insert(id).inserted else { return nil }
        return catalog.first { $0.id == id }
      }
      return .init(selected: Array(selected.prefix(limit)), inferredVerticals: [], strategy: "explicit_sources")
    }
    let language = queryLanguage(query)
    let general: Set<AgentIOSWebIntelligenceVertical> = [.general, .regional]
    let imageOnly = requestedVerticals == [.image]
    let eligible = catalog.filter {
      $0.enabledByDefault && (imageOnly ||
        (AgentIOSWebIntelligenceSourceCatalog.baseSearchEngineIDs.contains($0.id) && general.contains($0.vertical)) ||
        requestedVerticals.contains($0.vertical) || !categories.isDisjoint(with: $0.categoryTags))
    }.filter { !imageOnly || AgentIOSImageSearchRequestPolicy.supported.contains($0.id) }
      .filter { $0.id != "brave_image" || braveImageKeyAvailable }
    let skipped = eligible.compactMap { health[$0.id] }.filter { $0.circuitState(now: nowMillis) == "open" }
      .sorted { $0.circuitOpenUntilMillis < $1.circuitOpenUntilMillis }
    let blocked = Set(skipped.map(\.sourceID))
    func score(_ source: AgentIOSWebIntelligenceSourceSpec) -> Double {
      let languageMatch = source.languages.contains(language) ? 2.0 : (source.languages.contains("*") ? 0.8 : -1.5)
      let weight = source.id == "sogou_image" ? 1.2 :
        (["bing", "baidu", "duckduckgo"].contains(source.id) ? 1.05 : (source.id == "bing_news" ? 1.1 : 1))
      return weight + (requestedVerticals.contains(source.vertical) ? 2.5 : 0) +
        (!categories.isDisjoint(with: source.categoryTags) ? 2.0 : 0) +
        (general.contains(source.vertical) ? 1.0 : 0) + languageMatch + source.authority * 0.5 +
        (health[source.id] ?? AgentIOSWebSourceHealth(sourceID: source.id)).routingScore
    }
    let ranked = eligible.enumerated().filter { !blocked.contains($0.element.id) }.map {
      (source: $0.element, ordinal: $0.offset, score: score($0.element))
    }.sorted {
      $0.score == $1.score ? $0.ordinal < $1.ordinal : $0.score > $1.score
    }.map { $0.source }
    var selected: [AgentIOSWebIntelligenceSourceSpec] = []
    var seen = Set<String>()
    for category in categories.sorted() {
      if selected.count >= limit { break }
      if let source = ranked.first(where: { $0.categoryTags.contains(category) && !seen.contains($0.id) }),
        seen.insert(source.id).inserted { selected.append(source) }
    }
    for vertical in requestedVerticals.sorted(by: { $0.rawValue < $1.rawValue }) {
      if selected.count >= limit { break }
      if let source = ranked.first(where: { $0.vertical == vertical && !seen.contains($0.id) }),
        seen.insert(source.id).inserted { selected.append(source) }
    }
    for source in ranked where selected.count < limit && seen.insert(source.id).inserted { selected.append(source) }
    return .init(selected: selected, inferredVerticals: [],
      strategy: !requestedVerticals.isEmpty || !categories.isEmpty ? "model_selected_topics" : "broad_unscoped",
      skipped: skipped)
  }

  // Preserve Android's immutable base-catalog tie order, followed by indexed and learned sources.
  static let baseSourceOrder = [
    "bing", "duckduckgo", "baidu", "brave", "mojeek", "qwant", "yahoo", "yandex", "ecosia", "startpage",
    "sogou", "naver", "google", "bing_news", "brave_news", "sogou_image", "brave_image", "duckduckgo_image",
    "marginalia", "wikipedia", "wikipedia_zh", "github", "github_code", "gitlab", "stackoverflow",
    "hacker_news", "lobsters", "x_public", "wechat_public", "zhihu_public", "xiaohongshu_public", "reddit",
    "crossref", "semantic_scholar", "arxiv", "pubmed", "crates_io", "npm", "mdn", "devdocs", "pypi"
  ]

  private static let orderedSources: [AgentIOSWebIntelligenceSourceSpec] = {
    let roots: [AgentIOSWebIntelligenceSourceSpec] = [
      .init(id: "bing", title: "Bing", vertical: .general, allowedHosts: [], authority: 0.5),
      .init(id: "duckduckgo", title: "DuckDuckGo", vertical: .general, allowedHosts: [], authority: 0.5),
      .init(id: "baidu", title: "Baidu", vertical: .regional, allowedHosts: [], authority: 0.5, languages: ["zh"]),
      .init(id: "sogou_image", title: "Sogou Images", vertical: .image, allowedHosts: [], authority: 0.75),
      .init(id: "brave_image", title: "Brave Image", vertical: .image, allowedHosts: [], authority: 0.8),
      .init(id: "duckduckgo_image", title: "DuckDuckGo Image", vertical: .image, allowedHosts: [], authority: 0.75)
    ]
    let adapters = roots + AgentIOSJSONWebSearchAdapter.entries.map(\.spec) + AgentIOSHTMLWebSearchAdapter.entries.map(\.spec) +
      [AgentIOSArxivSearchAdapter.entry.spec, AgentIOSDevDocsSearchAdapter.entry.spec]
    let base = baseSourceOrder.compactMap { id in adapters.first { $0.id == id } }
    return base + AgentIOSWebIntelligenceSourceCatalog.indexedSources
  }()

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
