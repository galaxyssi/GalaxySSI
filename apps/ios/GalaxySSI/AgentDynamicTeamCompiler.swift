import Foundation

final class AgentDynamicTeamCompiler {
  func compile(
    request: AgentDynamicTeamRequest,
    registrations: [AgentRegistration],
    reputations: [String: AgentReputationSnapshot] = [:],
    reputationRevision: Int64 = 0,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) -> AgentDynamicTeamCompilation {
    let goal = request.goal.trimmingCharacters(in: .whitespacesAndNewlines)
    precondition(!goal.isEmpty, "Dynamic Agent team goal must not be blank")
    precondition(!request.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Dynamic Agent team id must not be blank")

    let policy = request.policy
    let budget = normalized(policy.budget)
    let requirements = AgentTaskRequirementAnalyzer.analyze(goal)
    let index = AgentNetworkIndex(registrations, reputations: reputations, reputationRevision: reputationRevision)
    var warnings: [String] = []
    var unfilledRoles = Set<AgentDynamicTeamRole>()
    var assignments: [AgentDynamicTeamAssignment] = []

    let leadSpec = RoleSpec(
      role: .lead,
      requiredAny: Self.leadCapabilities,
      preferred: requirements.capabilities.union([.chat, .reasoning]),
      objective: "Own the task, synthesize specialist evidence, and return one final result.",
      priority: 1_000
    )
    guard let lead = select(
      role: leadSpec,
      goal: goal,
      index: index,
      requirements: requirements,
      policy: policy,
      budget: budget,
      selected: assignments,
      reservedSlots: 0,
      nowMillis: nowMillis
    ) else {
      return unavailable(request, requirements: requirements, warnings: ["No trusted and routable lead Agent satisfies the task boundary."], unfilledRoles: [.lead])
    }
    let collectiveCapabilities = mandatoryCapabilities(requirements)
    assignments.append(lead.withRequiredCapabilities(collectiveCapabilities.intersection(lead.registration.capabilities)))

    let verificationWanted = verificationWanted(goal: goal, requirements: requirements, mode: policy.verificationMode)
    let reserveVerifier = verificationWanted && budget.maxMembers > 1 ? 1 : 0
    addPinnedAssignments(
      policy: policy,
      index: index,
      goal: goal,
      requirements: requirements,
      budget: budget,
      assignments: &assignments,
      warnings: &warnings,
      reservedSlots: reserveVerifier,
      nowMillis: nowMillis
    )

    for role in roleSpecs(goal: goal, requirements: requirements) {
      let leadCoversRole = assignments.first?.registration.satisfies(role) == true
      let independentSpecialistWanted = policy.forceTeam || requirements.mode == .quality
      if leadCoversRole && !independentSpecialistWanted {
        continue
      }
      if let selected = select(
        role: role,
        goal: goal,
        index: index,
        requirements: requirements,
        policy: policy,
        budget: budget,
        selected: assignments,
        reservedSlots: reserveVerifier,
        nowMillis: nowMillis
      ) {
        assignments.append(selected)
      } else if !leadCoversRole {
        unfilledRoles.insert(role.role)
      }
    }

    if verificationWanted && assignments.count < budget.maxMembers {
      if let verifier = select(
        role: verifierSpec(goal: goal, requirements: requirements),
        goal: "\(goal) independent verification",
        index: index,
        requirements: requirements,
        policy: policy,
        budget: budget,
        selected: assignments,
        reservedSlots: 0,
        nowMillis: nowMillis,
        requireIndependentFailureDomain: policy.verificationMode == .required
      ) {
        assignments.append(verifier)
      } else {
        unfilledRoles.insert(.verifier)
        warnings.append("No independent verifier is currently available.")
      }
    }

    let coveredCapabilities = assignments.reduce(into: Set<AgentCapability>()) {
      $0.formUnion($1.registration.capabilities)
    }
    let missingCapabilities = collectiveCapabilities.subtracting(coveredCapabilities)
    if !missingCapabilities.isEmpty {
      warnings.append("Missing task capabilities: \(missingCapabilities.map(\.rawValue).sorted().joined(separator: ","))")
      return unavailable(request, requirements: requirements, warnings: warnings, unfilledRoles: unfilledRoles, assignments: assignments)
    }
    if policy.verificationMode == .required && !assignments.contains(where: { $0.role == .verifier }) {
      return blocked(request, requirements: requirements, warnings: warnings, unfilledRoles: unfilledRoles, assignments: assignments)
    }
    if policy.forceTeam && assignments.count < 2 {
      warnings.append("The requested team cannot be formed within the current trust and budget boundary.")
      return blocked(request, requirements: requirements, warnings: warnings, unfilledRoles: unfilledRoles, assignments: assignments)
    }

    let uniqueAssignments = assignments.distinctByAgentId()
    let shouldUseTeam = uniqueAssignments.count >= 2 &&
      (policy.forceTeam || uniqueAssignments.contains { $0.role == .verifier } || uniqueAssignments.contains { $0.role != .lead })
    if !shouldUseTeam {
      return result(
        outcome: .singleAgent,
        request: request,
        requirements: requirements,
        definition: nil,
        assignments: uniqueAssignments,
        unfilledRoles: unfilledRoles,
        warnings: warnings,
        collectiveCapabilities: collectiveCapabilities
      )
    }
    return result(
      outcome: .team,
      request: request,
      requirements: requirements,
      definition: buildDefinition(request: request, assignments: uniqueAssignments, collectiveCapabilities: collectiveCapabilities),
      assignments: uniqueAssignments,
      unfilledRoles: unfilledRoles,
      warnings: warnings,
      collectiveCapabilities: collectiveCapabilities
    )
  }

  private func addPinnedAssignments(
    policy: AgentDynamicTeamPolicy,
    index: AgentNetworkIndex,
    goal: String,
    requirements: AgentTaskRequirements,
    budget: AgentTeamCompilationBudget,
    assignments: inout [AgentDynamicTeamAssignment],
    warnings: inout [String],
    reservedSlots: Int,
    nowMillis: Int64
  ) {
    for agentId in policy.pinnedAgentIds.sorted() where !assignments.contains(where: { $0.registration.agentId == agentId }) {
      guard assignments.count < budget.maxMembers - reservedSlots else {
        warnings.append("Pinned Agent \(agentId) exceeds the team member budget.")
        continue
      }
      guard let registration = index.get(agentId, nowMillis: nowMillis),
        isEligible(registration, requirements: requirements, policy: policy, budget: budget, selected: assignments) else {
        warnings.append("Pinned Agent \(agentId) is unavailable or outside the task boundary.")
        continue
      }
      assignments.append(AgentDynamicTeamAssignment(
        role: .requestedSpecialist,
        registration: registration,
        score: Self.pinnedAgentScore,
        requiredCapabilities: mandatoryCapabilities(requirements).intersection(registration.capabilities),
        objective: "Contribute the explicitly requested Agent expertise to: \(String(goal.prefix(Self.maxObjectiveCharacters)))",
        reasons: ["user_pinned", "identity:\(registration.agentId)"]
      ))
    }
  }

  private func select(
    role: RoleSpec,
    goal: String,
    index: AgentNetworkIndex,
    requirements: AgentTaskRequirements,
    policy: AgentDynamicTeamPolicy,
    budget: AgentTeamCompilationBudget,
    selected: [AgentDynamicTeamAssignment],
    reservedSlots: Int,
    nowMillis: Int64,
    requireIndependentFailureDomain: Bool = false
  ) -> AgentDynamicTeamAssignment? {
    guard selected.count < budget.maxMembers - reservedSlots else {
      return nil
    }
    let usedAgentIds = Set(selected.map { $0.registration.agentId })
    var searchHits = index.search(
      AgentNetworkSearchQuery(
        text: goal,
        requiredCapabilities: role.requiredAll,
        preferredCapabilities: role.preferred.union(role.requiredAny),
        kinds: role.allowedKinds,
        excludedAgentIds: policy.excludedAgentIds.union(usedAgentIds),
        trustedOnly: policy.trustedOnly,
        routableOnly: true,
        includeAtCapacity: false,
        maximumCost: budget.maximumMemberCost,
        maximumLatency: budget.maximumMemberLatency,
        pageSize: AgentNetworkSearchQuery.maxPageSize
      ),
      nowMillis: nowMillis
    ).hits

    for agentId in policy.pinnedAgentIds.sorted() where !searchHits.contains(where: { $0.registration.agentId == agentId }) {
      if let registration = index.get(agentId, nowMillis: nowMillis) {
        searchHits.append(AgentNetworkSearchHit(
          registration: registration,
          score: 0,
          matchedCapabilities: registration.capabilities.intersection(role.preferred),
          reasons: ["pinned_agent"],
          reputation: .neutral(registration.agentId)
        ))
      }
    }

    let selectedDomains = Set(selected.map(\.failureDomain))
    let candidates = searchHits
      .filter { $0.registration.satisfies(role) }
      .filter { isEligible($0.registration, requirements: requirements, policy: policy, budget: budget, selected: selected) }
      .map { hit -> RankedRoleCandidate in
        let domain = hit.registration.effectiveTeamFailureDomain()
        let independent = !selectedDomains.contains(domain)
        let diversityBonus = policy.preferFailureDomainDiversity && independent ? 180 : 0
        let pinnedBonus = policy.pinnedAgentIds.contains(hit.registration.agentId) ? Self.pinnedAgentScore : 0
        let leadExecutionBonus = role.role == .lead && requirements.capabilities.contains(.code) && hit.registration.capabilities.contains(.code) ? 300 : 0
        let taskExecutionBonus = role.role == .lead && hit.registration.capabilities.contains(.taskExecution) ? 120 : 0
        return RankedRoleCandidate(
          hit: hit,
          score: hit.score +
            role.priority +
            role.preferred.intersection(hit.registration.capabilities).count * 120 +
            diversityBonus +
            pinnedBonus +
            leadExecutionBonus +
            taskExecutionBonus,
          independent: independent
        )
      }
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        let lhsName = $0.hit.registration.displayName.lowercased()
        let rhsName = $1.hit.registration.displayName.lowercased()
        if lhsName != rhsName { return lhsName < rhsName }
        return $0.hit.registration.agentId < $1.hit.registration.agentId
      }

    let selectedCandidate: RankedRoleCandidate?
    if requireIndependentFailureDomain || role.role == .verifier {
      selectedCandidate = candidates.first { $0.independent } ?? (requireIndependentFailureDomain ? nil : candidates.first)
    } else {
      selectedCandidate = candidates.first
    }
    guard let selectedCandidate else {
      return nil
    }
    let registration = selectedCandidate.hit.registration
    let anyCapability = role.requiredAny.intersection(registration.capabilities).sorted { $0.rawValue < $1.rawValue }.first
    let requiredCapabilities = role.requiredAll.union(anyCapability.map { Set([$0]) } ?? Set<AgentCapability>())
    return AgentDynamicTeamAssignment(
      role: role.role,
      registration: registration,
      score: selectedCandidate.score,
      requiredCapabilities: requiredCapabilities,
      objective: role.objective,
      reasons: stableDistinctStrings(selectedCandidate.hit.reasons +
        ["role:\(role.role.rawValue.lowercased())", "failure_domain:\(registration.effectiveTeamFailureDomain())"] +
        (selectedCandidate.independent ? ["independent_failure_domain"] : []))
    )
  }

  private func buildDefinition(
    request: AgentDynamicTeamRequest,
    assignments: [AgentDynamicTeamAssignment],
    collectiveCapabilities: Set<AgentCapability>
  ) -> AgentTeamDefinition {
    let lead = assignments.first { $0.role == .lead } ?? assignments[0]
    let observers = assignments.filter { $0.registration.agentId != lead.registration.agentId }
    let observerIds = Set(observers.map { $0.registration.agentId })
    let nonVerifierObserverIds = Set(observers.filter { $0.role != .verifier }.map { $0.registration.agentId })
    let members = assignments.map { assignment -> AgentTeamMember in
      let dependencies: Set<String>
      if assignment.role == .lead {
        dependencies = observerIds
      } else if assignment.role == .verifier {
        dependencies = nonVerifierObserverIds
      } else {
        dependencies = []
      }
      return AgentTeamMember(
        agentId: assignment.registration.agentId,
        deliveryMode: assignment.role == .lead ? .respond : .observe,
        requiredCapabilities: assignment.requiredCapabilities,
        role: roleName(assignment.role),
        objective: String(assignment.objective.prefix(Self.maxObjectiveCharacters)),
        dependsOnAgentIds: dependencies,
        context: [
          "compiled_role": assignment.role.rawValue.lowercased(),
          "agent_display_name": assignment.registration.displayName,
          "agent_failure_domain": assignment.failureDomain
        ]
      )
    }
    return AgentTeamDefinition(
      teamId: request.teamId,
      primaryAgentId: lead.registration.agentId,
      members: members,
      visibilityMode: request.policy.visibilityMode,
      collectiveCapabilities: collectiveCapabilities
    )
  }

  private func result(
    outcome: AgentDynamicTeamOutcome,
    request: AgentDynamicTeamRequest,
    requirements: AgentTaskRequirements,
    definition: AgentTeamDefinition?,
    assignments: [AgentDynamicTeamAssignment],
    unfilledRoles: Set<AgentDynamicTeamRole>,
    warnings: [String],
    collectiveCapabilities: Set<AgentCapability>
  ) -> AgentDynamicTeamCompilation {
    let domains = Set(assignments.map(\.failureDomain))
    return AgentDynamicTeamCompilation(
      outcome: outcome,
      goal: request.goal.trimmingCharacters(in: .whitespacesAndNewlines),
      requirements: requirements,
      definition: definition,
      primaryAgentId: assignments.first { $0.role == .lead }?.registration.agentId,
      assignments: assignments,
      unfilledRoles: unfilledRoles,
      warnings: stableDistinctStrings(warnings),
      estimatedCostUnits: assignments.reduce(0) { $0 + costUnits($1.registration.cost) },
      failureDomains: domains,
      rationale: [
        "outcome:\(outcome.rawValue.lowercased())",
        "members:\(assignments.count)",
        "collective_capabilities:\(collectiveCapabilities.map(\.rawValue).sorted().joined(separator: ","))",
        "failure_domains:\(domains.count)",
        "verification:\(request.policy.verificationMode.rawValue.lowercased())"
      ]
    )
  }

  private func unavailable(
    _ request: AgentDynamicTeamRequest,
    requirements: AgentTaskRequirements,
    warnings: [String],
    unfilledRoles: Set<AgentDynamicTeamRole>,
    assignments: [AgentDynamicTeamAssignment] = []
  ) -> AgentDynamicTeamCompilation {
    result(
      outcome: .unavailable,
      request: request,
      requirements: requirements,
      definition: nil,
      assignments: assignments,
      unfilledRoles: unfilledRoles,
      warnings: warnings,
      collectiveCapabilities: mandatoryCapabilities(requirements)
    )
  }

  private func blocked(
    _ request: AgentDynamicTeamRequest,
    requirements: AgentTaskRequirements,
    warnings: [String],
    unfilledRoles: Set<AgentDynamicTeamRole>,
    assignments: [AgentDynamicTeamAssignment]
  ) -> AgentDynamicTeamCompilation {
    result(
      outcome: .blocked,
      request: request,
      requirements: requirements,
      definition: nil,
      assignments: assignments,
      unfilledRoles: unfilledRoles,
      warnings: warnings,
      collectiveCapabilities: mandatoryCapabilities(requirements)
    )
  }

  private func roleSpecs(goal: String, requirements: AgentTaskRequirements) -> [RoleSpec] {
    var specs: [RoleSpec] = []
    if requirements.capabilities.contains(.liveData) {
      specs.append(RoleSpec(
        role: .researcher,
        requiredAll: [.liveData],
        preferred: [.research, .toolUse],
        objective: "Collect current, attributable evidence needed for: \(String(goal.prefix(Self.maxObjectiveCharacters)))",
        priority: 760
      ))
    }
    if requirements.capabilities.contains(.code) {
      specs.append(RoleSpec(
        role: .implementer,
        requiredAll: [.code],
        preferred: [.taskExecution, .toolUse],
        objective: "Implement and validate the technical work required for: \(String(goal.prefix(Self.maxObjectiveCharacters)))",
        priority: 800
      ))
    }
    if requirements.capabilities.contains(.knowledgeSearch) {
      specs.append(RoleSpec(
        role: .knowledgeSpecialist,
        requiredAll: [.knowledgeSearch],
        preferred: [.reasoning],
        objective: "Retrieve relevant private knowledge with evidence for: \(String(goal.prefix(Self.maxObjectiveCharacters)))",
        priority: 720
      ))
    }
    let deviceCapabilities = requirements.capabilities.intersection([.deviceControl, .appNavigation])
    if !deviceCapabilities.isEmpty {
      specs.append(RoleSpec(
        role: .deviceOperator,
        requiredAll: deviceCapabilities,
        preferred: [.toolUse],
        allowedKinds: [.agent, .device],
        objective: "Plan and perform the authorized device actions required for: \(String(goal.prefix(Self.maxObjectiveCharacters)))",
        priority: 820
      ))
    }
    if specs.isEmpty && requirements.complexReasoning {
      specs.append(RoleSpec(
        role: .analyst,
        requiredAny: [.reasoning, .research],
        preferred: [.reasoning],
        objective: "Independently analyze assumptions and solution paths for: \(String(goal.prefix(Self.maxObjectiveCharacters)))",
        priority: 680
      ))
    }
    return specs
  }

  private func verifierSpec(goal: String, requirements: AgentTaskRequirements) -> RoleSpec {
    var preferred: Set<AgentCapability> = [.reasoning, .research]
    if requirements.capabilities.contains(.code) { preferred.insert(.code) }
    if requirements.capabilities.contains(.liveData) { preferred.insert(.liveData) }
    return RoleSpec(
      role: .verifier,
      requiredAny: preferred,
      preferred: preferred,
      objective: "Independently verify the team evidence, execution, and claims for: \(String(goal.prefix(Self.maxObjectiveCharacters)))",
      priority: 900
    )
  }

  private func verificationWanted(
    goal: String,
    requirements: AgentTaskRequirements,
    mode: AgentTeamVerificationMode
  ) -> Bool {
    switch mode {
    case .disabled:
      return false
    case .required:
      return true
    case .auto:
      let normalized = normalizeSearchText(goal)
      return requirements.capabilities.contains(.code) ||
        requirements.mode == .quality ||
        requirements.dataSensitivity == .restricted ||
        ["verify", "validate", "audit", "double check", "critical", "security"].contains { normalized.contains($0) }
    }
  }

  private func mandatoryCapabilities(_ requirements: AgentTaskRequirements) -> Set<AgentCapability> {
    requirements.capabilities.intersection(Self.mandatoryCollectiveCapabilities)
  }

  private func isEligible(
    _ registration: AgentRegistration,
    requirements: AgentTaskRequirements,
    policy: AgentDynamicTeamPolicy,
    budget: AgentTeamCompilationBudget,
    selected: [AgentDynamicTeamAssignment]
  ) -> Bool {
    if policy.excludedAgentIds.contains(registration.agentId) { return false }
    if !Self.teamRoutableStates.contains(registration.status) || !registration.hasCapacity { return false }
    if policy.trustedOnly && registration.trust == .unknown { return false }
    if requirements.localOnly && registration.location == .cloud { return false }
    if requirements.dataSensitivity == .restricted &&
      registration.trust != .phoneSystem &&
      registration.trust != .verifiedPaired {
      return false
    }
    if selected.contains(where: { $0.registration.effectiveTeamRuntimeIdentity() == registration.effectiveTeamRuntimeIdentity() }) {
      return false
    }
    if registration.cost > budget.maximumMemberCost { return false }
    if registration.latency > budget.maximumMemberLatency { return false }
    if registration.location == .cloud && selected.filter({ $0.registration.location == .cloud }).count >= budget.maxCloudMembers {
      return false
    }
    let projectedCost = selected.reduce(0) { $0 + costUnits($1.registration.cost) } + costUnits(registration.cost)
    return projectedCost <= budget.maxEstimatedCostUnits
  }

  private func normalized(_ budget: AgentTeamCompilationBudget) -> AgentTeamCompilationBudget {
    AgentTeamCompilationBudget(
      maxMembers: min(max(budget.maxMembers, 1), Self.maxTeamMembers),
      maxCloudMembers: min(max(budget.maxCloudMembers, 0), Self.maxTeamMembers),
      maximumMemberCost: budget.maximumMemberCost,
      maximumMemberLatency: budget.maximumMemberLatency,
      maxEstimatedCostUnits: max(budget.maxEstimatedCostUnits, 0)
    )
  }

  private func costUnits(_ cost: AgentResourceCost) -> Int {
    switch cost {
    case .free: return 0
    case .low: return 1
    case .medium: return 3
    case .high: return 8
    }
  }

  private func roleName(_ role: AgentDynamicTeamRole) -> String {
    switch role {
    case .lead: return "lead synthesizer"
    case .researcher: return "research specialist"
    case .implementer: return "implementation specialist"
    case .knowledgeSpecialist: return "knowledge specialist"
    case .deviceOperator: return "device operator"
    case .toolSpecialist: return "tool specialist"
    case .analyst: return "analysis specialist"
    case .verifier: return "independent verifier"
    case .requestedSpecialist: return "requested specialist"
    }
  }

  private func stableDistinctStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  private struct RankedRoleCandidate {
    var hit: AgentNetworkSearchHit
    var score: Int
    var independent: Bool
  }

  struct RoleSpec {
    var role: AgentDynamicTeamRole
    var requiredAll: Set<AgentCapability> = []
    var requiredAny: Set<AgentCapability> = []
    var preferred: Set<AgentCapability> = []
    var allowedKinds: Set<AgentConnectorKind> = [.agent]
    var objective: String
    var priority: Int
  }

  private static let maxTeamMembers = 12
  private static let maxObjectiveCharacters = 4_000
  private static let pinnedAgentScore = 4_000
  private static let leadCapabilities: Set<AgentCapability> = [
    .chat, .reasoning, .research, .code, .taskExecution, .toolUse
  ]
  private static let mandatoryCollectiveCapabilities: Set<AgentCapability> = [
    .liveData, .code, .deviceControl, .appNavigation, .knowledgeSearch, .mcp, .skill
  ]
  private static let teamRoutableStates: Set<AgentEndpointStatus> = [.online, .idle, .busy]
}

private extension AgentDynamicTeamAssignment {
  func withRequiredCapabilities(_ capabilities: Set<AgentCapability>) -> AgentDynamicTeamAssignment {
    var copy = self
    copy.requiredCapabilities = capabilities
    return copy
  }
}

extension AgentRegistration {
  func effectiveTeamFailureDomain() -> String {
    if !failureDomain.isEmpty { return failureDomain }
    if !runtimeFailureDomain.isEmpty { return runtimeFailureDomain }
    return "\(location.rawValue.lowercased()):\(deviceId.isEmpty ? installationId : deviceId)"
  }

  func effectiveTeamRuntimeIdentity() -> String {
    if !runtimeFailureDomain.isEmpty { return runtimeFailureDomain }
    return "\(effectiveTeamFailureDomain()):\(adapterType.isEmpty ? agentId : adapterType)"
  }

  func satisfies(_ role: AgentDynamicTeamCompiler.RoleSpec) -> Bool {
    capabilities.isSuperset(of: role.requiredAll) &&
      (role.requiredAny.isEmpty || !capabilities.isDisjoint(with: role.requiredAny))
  }
}

private extension Array where Element == AgentDynamicTeamAssignment {
  func distinctByAgentId() -> [AgentDynamicTeamAssignment] {
    var seen = Set<String>()
    return filter { seen.insert($0.registration.agentId).inserted }
  }
}
