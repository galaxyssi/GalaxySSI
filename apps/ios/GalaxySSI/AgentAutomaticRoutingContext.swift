import Foundation

struct AgentAutomaticRoutingContext {
  let targets: [AgentCallableTarget]
  let decision: AgentRoutingDecision

  static func capture(goal: String, targets: [AgentCallableTarget], registrations: [AgentRegistration],
    budget: AgentTaskBudget, environment: AgentRuntimeEnvironment, connectorCallsAllowed: Bool,
    preferredTargetId: String = "", preserveHealthyPrimary: Bool = false, hasPairedDesktop: Bool = false,
    health: AgentRoutingHealthSnapshot? = nil, usage: AgentRoutingUsageSnapshot? = nil,
    requirements explicitRequirements: AgentTaskRequirements? = nil) -> Self {
    let goal = AgentUntrustedEvidenceBoundary.trustedInstructionPrefix(goal)
    let requirements = explicitRequirements ?? AgentTaskRequirementAnalyzer.analyze(goal)
    let catalog = AgentResourceCatalog.build(targets: targets, tools: [])
    let permitted = AgentAutomaticRouteAdmission.targets(targets, registrations: registrations,
      requirements: requirements, budget: budget,
      environment: AgentTaskBudgetEnvironment(batteryPercent: environment.batteryPercent,
        charging: environment.charging, powerSaveMode: environment.powerSaveMode,
        networkAvailable: environment.networkAvailable, networkValidated: environment.networkValidated,
        networkMetered: environment.networkMetered, appMemoryBytes: environment.appMemoryBytes,
        availableMemoryBytes: environment.availableMemoryBytes), connectorCallsAllowed: connectorCallsAllowed)
      .filter { target in
        !target.id.isBlank && target.kind != .device &&
          target.capabilities.contains { [.chat, .reasoning, .research].contains($0) } &&
          (health?.allows(targetId: target.id) ?? true)
      }
    func scored(_ candidates: [AgentCallableTarget], primary: String) -> AgentRoutingDecision {
      let scored = candidates.compactMap { target -> AgentResourceCandidate? in
        guard var resource = catalog.first(where: { $0.targetId == target.id }) else { return nil }
        if let registration = registrations.first(where: { $0.agentId == target.id }) {
          resource.location = registration.location
          resource.capabilities = registration.capabilities
          resource.cost = registration.cost
          resource.latency = registration.latency
          resource.trust = registration.trust
          resource.activeTasks = max(resource.activeTasks, registration.activeRuns)
          resource.maxParallelTasks = max(1, registration.maxParallelRuns)
          resource.failureDomain = registration.failureDomain.ifBlank(resource.failureDomain)
          resource.providerProfile = ProviderProfileCatalog.fromRegistration(registration,
            existing: registration.providerProfile ?? resource.providerProfile)
        }
        return AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements,
          environment: environment, hasPairedDesktop: hasPairedDesktop,
          health: health?.resources[target.id], observedUsage: usage?.resources[target.id])
      }
      let selected = scored.first(where: { $0.resource.targetId == primary }) ?? scored.first
      return AgentRoutingDecision(requirements: requirements, primary: selected,
        fallbacks: scored.filter { $0.resource.targetId != selected?.resource.targetId },
        environment: environment, catalog: catalog, taskBudget: budget)
    }
    if preserveHealthyPrimary, let preferred = permitted.first(where: {
      $0.id == preferredTargetId && $0.status == .available
    }) {
      // Score only the admitted primary; calibration and shadow observation happen after this boundary.
      var decision = scored([preferred], primary: preferred.id)
      decision.primary?.reasons.append("stable_auto_primary")
      return Self(targets: permitted, decision: decision)
    }
    // Keep all admitted candidates until the selector calibrates, bounds and optionally promotes them.
    return Self(targets: permitted, decision: scored(permitted, primary: ""))
  }
}
