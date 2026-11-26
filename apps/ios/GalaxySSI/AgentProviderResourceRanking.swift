import Foundation

enum AgentProviderResourceRanking {
  static func candidate(
    resource: AgentResourceDescriptor,
    requirements: AgentTaskRequirements,
    environment: AgentRuntimeEnvironment
  ) -> AgentResourceCandidate {
    var score = AgentCapabilityRoutingPolicy.fitScore(requirements, available: resource.capabilities)
    var reasons = ["available_reasoning_resource"] +
      AgentCapabilityRoutingPolicy.evidence(requirements, available: resource.capabilities)
    score += resource.quality.rank * (requirements.complexReasoning || requirements.mode == .quality ? 55 : 22)
    score -= resource.latency.rank * (requirements.mode == .fast ? 75 : 25)
    score -= resource.cost.rank * (requirements.mode == .economy ? 80 : 20)
    if let performance = resource.providerProfile?.performance, performance.attempts > 0 {
      let failurePenalty = penalty(performance.failureRate * 220, maximum: 220)
      let latencyPenalty = penalty(performance.ewmaLatencyMs / (requirements.mode == .fast ? 40 : 120), maximum: 180)
      score -= failurePenalty + latencyPenalty
      reasons += ["provider_failure_penalty:\(failurePenalty)", "provider_latency_penalty:\(latencyPenalty)"]
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
    reasons += ["quality:\(resource.quality.rawValue.lowercased())", "latency:\(resource.latency.rawValue.lowercased())",
      "cost:\(resource.cost.rawValue.lowercased())", "trust:\(resource.trust.rawValue.lowercased())",
      "sensitivity:\(requirements.dataSensitivity.rawValue.lowercased())", "ranking:provider_resource_attributes"]
    return AgentResourceCandidate(resource: resource, score: score, reasons: reasons)
  }

  // Persisted provider telemetry may be non-finite; clamp before converting to Int.
  private static func penalty(_ value: Double, maximum: Int) -> Int {
    guard !value.isNaN, value > 0 else { return 0 }
    return value >= Double(maximum) ? maximum : Int(value)
  }
}
