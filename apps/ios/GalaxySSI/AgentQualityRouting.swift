import Foundation

struct AgentShadowRoutingScore: Codable, Equatable, Identifiable {
  var id: String { resourceId }
  var resourceId: String
  var score: Double
  var verifiedSamples: Int
  var passAt1: Double
  var averageLatencyMillis: Int64
  var averageCostMicros: Int64
  var recoveryRate: Double
  var reasons: [String]
}

struct AgentShadowRoutingRecommendation: Codable, Equatable, Identifiable {
  var id: String
  var scenarioId: String
  var taskClass: AgentEvalTaskClass
  var actualResourceId: String
  var recommendedResourceId: String
  var scores: [AgentShadowRoutingScore]
  var shouldAutoSwitch: Bool
  var confidence: Double
  var createdAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    scenarioId: String,
    taskClass: AgentEvalTaskClass,
    actualResourceId: String,
    recommendedResourceId: String,
    scores: [AgentShadowRoutingScore],
    shouldAutoSwitch: Bool,
    confidence: Double,
    createdAtMillis: Int64 = AgentEvalClock.nowMillis()
  ) {
    self.id = id
    self.scenarioId = scenarioId
    self.taskClass = taskClass
    self.actualResourceId = actualResourceId
    self.recommendedResourceId = recommendedResourceId
    self.scores = scores
    self.shouldAutoSwitch = shouldAutoSwitch
    self.confidence = min(max(confidence, 0), 1)
    self.createdAtMillis = max(0, createdAtMillis)
  }
}

enum AgentQualityAwareRoutingPolicy {
  static func recommend(
    goal: String,
    requirements: AgentTaskRequirements,
    candidates: [AgentResourceCandidate],
    samples: [AgentEvalSample],
    actualResourceId: String,
    settings: AgentEvalOpsSettings
  ) -> AgentShadowRoutingRecommendation? {
    let settings = settings.normalized
    guard settings.shadowRoutingEnabled, !candidates.isEmpty else { return nil }
    let taskClass = AgentOutcomeContractCompiler.classify(goal: goal, requirements: requirements)
    let relevantSamples = samples.filter { $0.taskClass == taskClass && $0.verified }
    let scores = candidates.map { score(candidate: $0, samples: relevantSamples) }
      .sorted { $0.score > $1.score }
    guard let recommended = scores.first else { return nil }
    let actual = scores.first { sameResource($0.resourceId, actualResourceId) }
    let margin = recommended.score - (actual?.score ?? 0)
    let enoughEvidence = recommended.verifiedSamples >= settings.minimumAutomaticRoutingSamples
    return AgentShadowRoutingRecommendation(
      scenarioId: AgentLearningAnalyzer.stableKey(goal),
      taskClass: taskClass,
      actualResourceId: actualResourceId,
      recommendedResourceId: recommended.resourceId,
      scores: scores,
      shouldAutoSwitch: settings.automaticQualityRoutingEnabled &&
        enoughEvidence &&
        !sameResource(recommended.resourceId, actualResourceId) &&
        margin >= automaticSwitchMargin,
      confidence: Double(recommended.verifiedSamples) / Double(max(settings.minimumAutomaticRoutingSamples, 1))
    )
  }

  static func apply(
    recommendation: AgentShadowRoutingRecommendation?,
    to decision: AgentRoutingDecision
  ) -> AgentRoutingDecision {
    guard recommendation?.shouldAutoSwitch == true,
          let resourceId = recommendation?.recommendedResourceId else {
      return decision
    }
    let ordered = [decision.primary].compactMap { $0 } + decision.fallbacks
    guard var promoted = ordered.first(where: {
      sameResource($0.resource.targetId.ifBlank($0.resource.id), resourceId)
    }) else {
      return decision
    }
    let maximumScore = ordered.map(\.score).max() ?? promoted.score
    promoted.score = min(maximumScore, Int.max - qualityPromotionMargin) + qualityPromotionMargin
    promoted.reasons = Array((promoted.reasons + ["quality_eval_promoted"]).suffix(32))
    return AgentRoutingDecision(
      requirements: decision.requirements,
      primary: promoted,
      fallbacks: ordered.filter { $0.resource.id != promoted.resource.id },
      environment: decision.environment,
      catalog: decision.catalog,
      taskBudget: decision.taskBudget
    )
  }

  static func sameResource(_ left: String, _ right: String) -> Bool {
    canonical(left) == canonical(right)
  }

  private static func score(
    candidate: AgentResourceCandidate,
    samples: [AgentEvalSample]
  ) -> AgentShadowRoutingScore {
    let resourceId = candidate.resource.targetId.ifBlank(candidate.resource.id)
    let relevant = samples.filter { sameResource($0.resourceId, resourceId) }
    let passAt1 = relevant.isEmpty ? 0.5 : Double(relevant.filter(\.passed).count) / Double(relevant.count)
    let latency = positiveAverage(relevant.map(\.durationMillis))
    let cost = positiveAverage(relevant.map(\.reportedCostMicros))
    let recoveries = relevant.filter(\.recoveryAttempted)
    let recoveryRate = recoveries.isEmpty ? 0.5 : Double(recoveries.filter(\.recovered).count) / Double(recoveries.count)
    let capacity = 1 - Double(candidate.resource.activeTasks) / Double(max(candidate.resource.maxParallelTasks, 1))
    let privacy: Double
    switch candidate.resource.trust {
    case .phoneSystem: privacy = 1
    case .verifiedPaired: privacy = 0.90
    case .privateConfigured: privacy = 0.75
    case .cloudConfigured: privacy = 0.45
    case .unknown: privacy = 0.20
    }
    let latencyScore: Double
    switch latency {
    case ...0: latencyScore = 0.5
    case ...2_000: latencyScore = 1
    case 120_000...: latencyScore = 0
    default: latencyScore = 1 - Double(latency - 2_000) / 118_000
    }
    let costScore: Double
    switch cost {
    case ...0: costScore = 1
    case 2_000_000...: costScore = 0
    default: costScore = 1 - Double(cost) / 2_000_000
    }
    let historicalConfidence = min(max(Double(relevant.count) / 12, 0), 1)
    let observedQuality = passAt1 * 0.45 + latencyScore * 0.15 + costScore * 0.10 +
      privacy * 0.12 + min(max(capacity, 0), 1) * 0.08 + recoveryRate * 0.10
    let baseline = min(max(Double(candidate.score + 1_000) / 2_000, 0), 1)
    let finalScore = observedQuality * historicalConfidence + baseline * (1 - historicalConfidence)
    return AgentShadowRoutingScore(
      resourceId: resourceId,
      score: finalScore,
      verifiedSamples: relevant.count,
      passAt1: passAt1,
      averageLatencyMillis: latency,
      averageCostMicros: cost,
      recoveryRate: recoveryRate,
      reasons: [
        "verified_samples:\(relevant.count)",
        "pass_at_1:\(format(passAt1))",
        "latency_ms:\(latency)",
        "reported_cost_micros:\(cost)",
        "privacy:\(format(privacy))",
        "capacity:\(format(capacity))",
        "recovery:\(format(recoveryRate))"
      ]
    )
  }

  private static func canonical(_ value: String) -> String {
    let id = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if id.contains(":codex") || id == "codex" { return "codex" }
    if id.contains(":claude") || ["claude", "claude-code"].contains(id) { return "claude-code" }
    if id.contains(":hermes") || id == "hermes" { return "hermes" }
    if id.hasPrefix("cloud-model:") { return String(id.dropFirst("cloud-model:".count)) }
    if id.hasPrefix("skill:") { return String(id.dropFirst("skill:".count)) }
    return id
  }

  private static func positiveAverage(_ values: [Int64]) -> Int64 {
    let positive = values.filter { $0 > 0 }
    return positive.isEmpty ? 0 : positive.reduce(0, +) / Int64(positive.count)
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.4f", value)
  }

  private static let automaticSwitchMargin = 0.08
  private static let qualityPromotionMargin = 400
}

final class AgentShadowRoutingStore {
  private struct State: Codable { var recommendations: [AgentShadowRoutingRecommendation] = [] }

  static let defaultKey = "galaxyssi-ios-agent-shadow-routing-v1"
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let key: String
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    key: String = AgentShadowRoutingStore.defaultKey
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.key = key
  }

  func save(_ recommendation: AgentShadowRoutingRecommendation) {
    locked {
      var state = load()
      state.recommendations.removeAll { $0.id == recommendation.id }
      state.recommendations.append(recommendation)
      state.recommendations = Array(state.recommendations.sorted { $0.createdAtMillis > $1.createdAtMillis }.prefix(Self.maximumItems))
      persist(state)
    }
  }

  func recent(limit: Int = AgentShadowRoutingStore.maximumItems) -> [AgentShadowRoutingRecommendation] {
    locked {
      Array(load().recommendations.sorted { $0.createdAtMillis > $1.createdAtMillis }.prefix(min(max(limit, 1), Self.maximumItems)))
    }
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
    return state
  }

  private func persist(_ state: State) {
    guard let data = try? JSONEncoder().encode(state) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: key, secrets: secrets)
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }

  static let maximumItems = 500
}

enum AgentQualityRoutingService {
  static func baselineDecision(
    goal: String,
    targets: [AgentCallableTarget],
    primaryTargetId: String
  ) -> AgentRoutingDecision? {
    let catalog = AgentResourceCatalog.build(targets: targets, tools: [])
      .filter { !$0.targetId.isBlank }
    let candidates = catalog.map { resource in
      AgentResourceCandidate(
        resource: resource,
        score: 0,
        reasons: ["available_reasoning_resource"]
      )
    }
    guard !candidates.isEmpty else { return nil }
    let primary = candidates.first { $0.resource.targetId == primaryTargetId } ?? candidates[0]
    return AgentRoutingDecision(
      requirements: AgentTaskRequirementAnalyzer.analyze(goal),
      primary: primary,
      fallbacks: candidates.filter { $0.resource.id != primary.resource.id },
      catalog: catalog
    )
  }

  @discardableResult
  static func observe(
    goal: String,
    decision: AgentRoutingDecision,
    evalStore: AgentEvalOpsStore = AgentEvalOpsStore(),
    shadowStore: AgentShadowRoutingStore = AgentShadowRoutingStore()
  ) -> AgentShadowRoutingRecommendation? {
    let candidates = [decision.primary].compactMap { $0 } + decision.fallbacks
    guard let recommendation = AgentQualityAwareRoutingPolicy.recommend(
      goal: goal,
      requirements: decision.requirements,
      candidates: candidates,
      samples: evalStore.samples(),
      actualResourceId: decision.primary?.resource.targetId ?? "",
      settings: evalStore.settings()
    ) else { return nil }
    shadowStore.save(recommendation)
    return recommendation
  }

  static func adjustedDecision(
    goal: String,
    decision: AgentRoutingDecision,
    evalStore: AgentEvalOpsStore = AgentEvalOpsStore(),
    shadowStore: AgentShadowRoutingStore = AgentShadowRoutingStore()
  ) -> AgentRoutingDecision {
    AgentQualityAwareRoutingPolicy.apply(
      recommendation: observe(goal: goal, decision: decision, evalStore: evalStore, shadowStore: shadowStore),
      to: decision
    )
  }

}
