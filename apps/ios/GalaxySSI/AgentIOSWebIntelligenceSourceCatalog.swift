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
  var wigoloAdapterCount: Int
  var wigoloSupportedCount: Int
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
}

struct AgentIOSWebIntelligenceSourceSelection: Equatable {
  var selected: [AgentIOSWebIntelligenceSourceSpec]
  var inferredVerticals: Set<AgentIOSWebIntelligenceVertical>
  var strategy: String
}

enum AgentIOSWebIntelligenceQueryRouting {
  static func select(
    query _: String,
    requestedVerticals: Set<AgentIOSWebIntelligenceVertical>,
    requestedEngineIds: Set<String>,
    requestedCategories: Set<String> = [],
    learnedSources: [AgentIOSLearnedWebSource] = []
  ) -> AgentIOSWebIntelligenceSourceSelection {
    let learned = learnedSources.filter(\.isSearchEligible).sorted { $0.sourceID < $1.sourceID }
      .enumerated().compactMap { $0.element.searchSpec(index: $0.offset + AgentIOSWebIntelligenceSourceCatalog.sourceCount) }
    let catalog = AgentIOSWebIntelligenceSourceCatalog.officialDocumentationSources + learned
    let categories = Set(requestedCategories.compactMap(AgentIOSWebResearchPlanCodec.normalizedCategory))
    let explicit = catalog.filter {
      requestedEngineIds.contains($0.id)
    }
    let candidates = explicit.isEmpty
      ? catalog.filter {
        requestedVerticals.contains($0.vertical) || categories.contains($0.vertical.rawValue) ||
          !categories.isDisjoint(with: $0.categoryTags)
      }
      : explicit
    let selected = candidates.indices.sorted { left, right in
      let leftAuthority = candidates[left].authority
      let rightAuthority = candidates[right].authority
      return leftAuthority == rightAuthority ? left < right : leftAuthority > rightAuthority
    }.map { candidates[$0] }
    return AgentIOSWebIntelligenceSourceSelection(
      selected: selected,
      inferredVerticals: [],
      strategy: !requestedVerticals.isEmpty || !requestedEngineIds.isEmpty || !categories.isEmpty
        ? "model_selected_topics"
        : "broad_unscoped"
    )
  }
}

enum AgentIOSWebIntelligenceSourceCatalog {
  static let baseSearchEngineCount = 40
  static let indexedSourceCount = 247
  static let sourceCount = baseSearchEngineCount + indexedSourceCount
  static let wigoloAdapterCount = 18
  static let wigoloSupportedCount = 18
  static let officialDocumentationSources: [AgentIOSWebIntelligenceSourceSpec] = [
    AgentIOSWebIntelligenceSourceSpec(
      id: "microsoft_learn", title: "Microsoft Learn", vertical: .docs,
      allowedHosts: ["learn.microsoft.com"], authority: 0.95
    ),
    AgentIOSWebIntelligenceSourceSpec(
      id: "android_developers", title: "Android Developers", vertical: .docs,
      allowedHosts: ["developer.android.com"], authority: 0.95
    ),
    AgentIOSWebIntelligenceSourceSpec(
      id: "apple_developer", title: "Apple Developer", vertical: .docs,
      allowedHosts: ["developer.apple.com"], authority: 0.95
    ),
    AgentIOSWebIntelligenceSourceSpec(
      id: "python_docs", title: "Python Documentation", vertical: .docs,
      allowedHosts: ["docs.python.org"], authority: 0.95
    ),
    AgentIOSWebIntelligenceSourceSpec(
      id: "rust_docs", title: "Rust Documentation", vertical: .docs,
      allowedHosts: ["doc.rust-lang.org"], authority: 0.95
    )
  ]

  static var domainCategoryCount: Int {
    AgentIOSWebIntelligenceVertical.allCases.filter { $0 != .local }.count
  }

  static func summary(
    learningStats: AgentIOSWebIntelligenceSourceLearningStats = AgentIOSWebIntelligenceLearningStore().stats()
  ) -> AgentIOSWebIntelligenceSourceSummary {
    AgentIOSWebIntelligenceSourceSummary(
      sourceCount: sourceCount,
      baseSearchEngineCount: baseSearchEngineCount,
      indexedSourceCount: indexedSourceCount,
      domainCategoryCount: domainCategoryCount,
      wigoloAdapterCount: wigoloAdapterCount,
      wigoloSupportedCount: wigoloSupportedCount,
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
