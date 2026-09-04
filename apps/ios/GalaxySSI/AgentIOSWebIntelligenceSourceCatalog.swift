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
    requestedEngineIds: Set<String>
  ) -> AgentIOSWebIntelligenceSourceSelection {
    let inferred = requestedVerticals.isEmpty ? inferredVerticals(query) : []
    let desired = requestedVerticals.isEmpty ? inferred : requestedVerticals
    let explicit = AgentIOSWebIntelligenceSourceCatalog.officialDocumentationSources.filter {
      requestedEngineIds.contains($0.id)
    }
    let candidates = explicit.isEmpty
      ? AgentIOSWebIntelligenceSourceCatalog.officialDocumentationSources.filter {
        desired.contains($0.vertical) && sourceAffinity(query: query, source: $0) > 0
      }
      : explicit
    let selected = candidates.sorted { left, right in
      let leftScore = sourceAffinity(query: query, source: left) + left.authority * 0.5
      let rightScore = sourceAffinity(query: query, source: right) + right.authority * 0.5
      return leftScore == rightScore ? left.id < right.id : leftScore > rightScore
    }
    return AgentIOSWebIntelligenceSourceSelection(
      selected: selected,
      inferredVerticals: inferred,
      strategy: !inferred.isEmpty
        ? "semantic_query_topics"
        : (!desired.isEmpty || !requestedEngineIds.isEmpty ? "model_selected_topics" : "broad_unscoped")
    )
  }

  static func inferredVerticals(_ query: String) -> Set<AgentIOSWebIntelligenceVertical> {
    let value = query.lowercased()
    let latin = value.range(
      of: #"\b(documentation|docs|reference|manual|official\s+(docs?|documentation)|developer\s+guide)\b"#,
      options: .regularExpression
    ) != nil
    let chinese = [
      "\u{5B98}\u{65B9}\u{6587}\u{6863}",
      "\u{5F00}\u{53D1}\u{6587}\u{6863}",
      "\u{53C2}\u{8003}\u{6587}\u{6863}",
      "\u{5F00}\u{53D1}\u{624B}\u{518C}",
      "\u{6280}\u{672F}\u{624B}\u{518C}"
    ].contains {
      value.contains($0)
    }
    return latin || chinese ? [.docs] : []
  }

  static func sourceAffinity(query: String, source: AgentIOSWebIntelligenceSourceSpec) -> Double {
    let queryTokens = Set(tokens(query).filter { $0.count >= 3 && !genericSourceTokens.contains($0) })
    guard !queryTokens.isEmpty else { return 0 }
    let sourceTokens = Set(tokens(
      ([source.id.replacingOccurrences(of: "_", with: " "), source.title] + source.allowedHosts)
        .joined(separator: " ")
    ))
    switch queryTokens.intersection(sourceTokens).count {
    case 0: return 0
    case 1: return 3.5
    default: return 5
    }
  }

  private static func tokens(_ value: String) -> [String] {
    value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
  }

  private static let genericSourceTokens: Set<String> = [
    "app", "application", "developer", "developers", "documentation", "docs", "official",
    "reference", "manual", "guide", "process", "source", "sources"
  ]
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
  private static let learnedSourceCountKey = "galaxyssi.web_intelligence.learned_source_count"
  private static let verifiedLearnedSourceCountKey = "galaxyssi.web_intelligence.verified_learned_source_count"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func stats() -> AgentIOSWebIntelligenceSourceLearningStats {
    AgentIOSWebIntelligenceSourceLearningStats(
      learnedSourceCount: max(0, defaults.integer(forKey: Self.learnedSourceCountKey)),
      verifiedLearnedSourceCount: max(0, defaults.integer(forKey: Self.verifiedLearnedSourceCountKey))
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
