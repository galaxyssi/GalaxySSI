import Foundation

enum AgentProviderResourceRanking {
  static func preferenceBonus(targetId: String, requirements: AgentTaskRequirements, hasPairedDesktop: Bool) -> Int {
    let remainder: [String]
    if requirements.capabilities.contains(.code) || requirements.capabilities.contains(.knowledgeSearch) {
      remainder = ["cloud-models", "local-llm"]
    } else if requirements.liveDataRequired || requirements.mode == .quality {
      remainder = ["cloud-models"]
    } else if requirements.mode == .fast || requirements.mode == .private {
      remainder = ["local-llm"]
    } else if requirements.mode == .economy {
      remainder = ["local-llm", "cloud-models"]
    } else {
      remainder = ["cloud-models", "local-llm"]
    }
    let desktop = hasPairedDesktop ? ["codex"] + (requirements.capabilities.contains(.code) ? ["claude-code"] : []) : []
    let order = desktop + remainder + (hasPairedDesktop ? ["hermes"] : [])
    guard let index = order.firstIndex(of: canonicalPreferenceId(targetId)) else { return 0 }
    switch index {
    case 0: return 180
    case 1: return 130
    case 2: return 90
    case 3: return 50
    default: return 20
    }
  }

  // Family names affect preference only; exact target/registration identity is never rewritten.
  private static func canonicalPreferenceId(_ value: String) -> String {
    let id = value.lowercased()
    if id == "claude" || id == "claude-code" { return "claude-code" }
    if id == "cloud-models" || id.hasPrefix("cloud-model:") { return "cloud-models" }
    if id == "codex" || id.contains(":codex") { return "codex" }
    if id == "hermes" || id.contains(":hermes") { return "hermes" }
    if id == "local-llm" || id.contains(":local-llm") { return "local-llm" }
    return id
  }

  static func fallbackCandidates(primary: AgentResourceDescriptor,
                                 candidates: [AgentResourceCandidate]) -> [AgentResourceCandidate] {
    let primaryResource = failoverResource(primary)
    var seen = Set<String>()
    let eligible = candidates.filter {
      !$0.resource.targetId.isBlank && $0.resource.targetId != primary.targetId &&
        seen.insert($0.resource.targetId).inserted
    }
    return Array(eligible.enumerated().sorted { left, right in
      let leftTier = AgentFailoverPolicy.fallbackTier(primary: primaryResource, candidate: failoverResource(left.element.resource))
      let rightTier = AgentFailoverPolicy.fallbackTier(primary: primaryResource, candidate: failoverResource(right.element.resource))
      return leftTier == rightTier ? left.offset < right.offset : leftTier < rightTier
    }.prefix(6).map(\.element))
  }

  private static func failoverResource(_ resource: AgentResourceDescriptor) -> AgentFailoverResource {
    let location: AgentFailoverResourceLocation
    switch resource.location {
    case .phone: location = .phone
    case .trustedDesktop: location = .trustedDesktop
    case .privateNetwork: location = .privateNetwork
    case .cloud: location = .cloud
    }
    return AgentFailoverResource(location: location, failureDomain: resource.failureDomain)
  }

  static func candidate(
    resource: AgentResourceDescriptor,
    requirements: AgentTaskRequirements,
    environment: AgentRuntimeEnvironment,
    hasPairedDesktop: Bool = false,
    health: AgentRoutingResourceHealth? = nil
  ) -> AgentResourceCandidate {
    var score = AgentCapabilityRoutingPolicy.fitScore(requirements, available: resource.capabilities)
    var reasons = ["available_reasoning_resource"] +
      AgentCapabilityRoutingPolicy.evidence(requirements, available: resource.capabilities)
    score += resource.quality.rank * (requirements.complexReasoning || requirements.mode == .quality ? 55 : 22)
    score -= resource.latency.rank * (requirements.mode == .fast ? 75 : 25)
    score -= resource.cost.rank * (requirements.mode == .economy ? 80 : 20)
    if let performance = resource.providerProfile?.performance, performance.attempts > 0 {
      let failurePenalty = penalty(performance.failureRate * 220, maximum: 220)
      let latencyPenalty = (health?.targetLatencyMillis ?? 0) > 0 ? 0 :
        penalty(performance.ewmaLatencyMs / (requirements.mode == .fast ? 40 : 120), maximum: 180)
      score -= failurePenalty + latencyPenalty
      reasons += ["provider_failure_penalty:\(failurePenalty)", "provider_latency_penalty:\(latencyPenalty)"]
    }
    if let reliability = AgentRoutingResourceHealth.reliability(health?.target) {
      score += reliability
      reasons.append("observed_adapter_reliability:\(reliability)")
    }
    if let reliability = AgentRoutingResourceHealth.reliability(health?.domain) {
      score += reliability / 2
      reasons.append("observed_domain_reliability:\(reliability)")
    }
    if let latency = health?.targetLatencyMillis, latency > 0 {
      score -= Int(min(latency / (requirements.mode == .fast ? 40 : 120), 180))
      reasons.append("observed_adapter_latency_ms:\(latency)")
    }
    if let latency = health?.domainLatencyMillis, latency > 0 {
      score -= Int(min(latency / 180, 120))
      reasons.append("observed_domain_latency_ms:\(latency)")
    }
    if requirements.dataSensitivity == .confidential {
      switch resource.trust {
      case .phoneSystem: score += 220
      case .verifiedPaired: score += 100
      case .privateConfigured: score += 40
      case .cloudConfigured: score -= 160
      case .unknown: score -= 240
      }
    }
    if requirements.executionHorizon != .interactive {
      score += resource.supportsBackground ? 140 : -120
      reasons.append("background:\(resource.supportsBackground)")
    }
    if environment.networkMetered, resource.location == .cloud {
      score -= 70
      reasons.append("metered_network")
    }
    if environment.networkAvailable, !environment.networkValidated, resource.location != .phone {
      score -= 180
      reasons.append("network_unvalidated")
    }
    if resource.contextWindowTokens > 0, resource.contextWindowTokens < requirements.estimatedInputTokens {
      score -= 300
      reasons.append("context_window_shortfall")
    }
    if requirements.estimatedInputTokens > 1_000, resource.cost > .low {
      score -= min(requirements.estimatedInputTokens / 100, 120)
    }
    if resource.location != .cloud { score += 35 }
    if requirements.liveDataRequired, resource.supportsTools { score += 120 }
    if requirements.mode == .private, resource.location == .phone { score += 180 }
    if requirements.mode == .fast, resource.latency <= .fast { score += 120 }
    if requirements.mode == .economy, resource.cost <= .low { score += 120 }
    if requirements.mode == .quality, resource.quality == .frontier { score += 160 }
    let preference = preferenceBonus(targetId: resource.targetId, requirements: requirements, hasPairedDesktop: hasPairedDesktop)
    score += preference
    reasons.append("preference_bonus:\(preference)")
    reasons += ["quality:\(resource.quality.rawValue.lowercased())", "latency:\(resource.latency.rawValue.lowercased())",
      "cost:\(resource.cost.rawValue.lowercased())", "trust:\(resource.trust.rawValue.lowercased())",
      "sensitivity:\(requirements.dataSensitivity.rawValue.lowercased())", "ranking:provider_resource_attributes"]
    return AgentResourceCandidate(resource: resource, score: score, reasons: reasons)
  }

  static func prepareForQuality(decision: AgentRoutingDecision, eligibleTargetIds: Set<String>,
                                preferredTargetId: String, calibration: (String) -> Int) -> AgentRoutingDecision {
    var seen = Set<String>()
    let candidates = ([decision.primary].compactMap { $0 } + decision.fallbacks).filter {
      !$0.resource.targetId.isBlank && eligibleTargetIds.contains($0.resource.targetId) &&
        seen.insert($0.resource.targetId).inserted
    }
    let ranked = candidates.enumerated().map { index, original -> (index: Int, candidate: AgentResourceCandidate) in
      var candidate = original
      let adjustment = calibration(candidate.resource.targetId)
      let sum = candidate.score.addingReportingOverflow(adjustment)
      candidate.score = sum.overflow ? (adjustment < 0 ? Int.min : Int.max) : sum.partialValue
      candidate.reasons.removeAll { $0.hasPrefix("routing_self_calibration_adjustment:") }
      candidate.reasons.append("routing_self_calibration_adjustment:\(adjustment)")
      return (index, candidate)
    }.sorted { left, right in
      left.candidate.score == right.candidate.score ? left.index < right.index : left.candidate.score > right.candidate.score
    }.map(\.candidate)
    let primary = ranked.first { $0.resource.targetId == preferredTargetId } ?? ranked.first
    var prepared = decision
    prepared.primary = primary
    prepared.fallbacks = primary.map { fallbackCandidates(primary: $0.resource, candidates: ranked) } ?? []
    return prepared
  }

  // Persisted provider telemetry may be non-finite; clamp before converting to Int.
  private static func penalty(_ value: Double, maximum: Int) -> Int {
    guard !value.isNaN, value > 0 else { return 0 }
    return value >= Double(maximum) ? maximum : Int(value)
  }
}
