import Foundation

enum AgentIOSWebIntelligenceVertical: String, CaseIterable, Identifiable {
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

enum AgentIOSWebIntelligenceSourceCatalog {
  static let baseSearchEngineCount = 40
  static let indexedSourceCount = 247
  static let sourceCount = baseSearchEngineCount + indexedSourceCount
  static let wigoloAdapterCount = 18
  static let wigoloSupportedCount = 18

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
