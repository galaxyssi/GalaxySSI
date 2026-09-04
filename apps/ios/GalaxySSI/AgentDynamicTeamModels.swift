import Foundation

enum AgentDynamicTeamOutcome: String, Codable, CaseIterable, Identifiable {
  case singleAgent = "SINGLE_AGENT"
  case team = "TEAM"
  case unavailable = "UNAVAILABLE"
  case blocked = "BLOCKED"

  var id: String { rawValue }
}

enum AgentDynamicTeamRole: String, Codable, CaseIterable, Identifiable {
  case lead = "LEAD"
  case researcher = "RESEARCHER"
  case implementer = "IMPLEMENTER"
  case knowledgeSpecialist = "KNOWLEDGE_SPECIALIST"
  case deviceOperator = "DEVICE_OPERATOR"
  case toolSpecialist = "TOOL_SPECIALIST"
  case analyst = "ANALYST"
  case verifier = "VERIFIER"
  case requestedSpecialist = "REQUESTED_SPECIALIST"

  var id: String { rawValue }
}

enum AgentTeamVerificationMode: String, Codable, CaseIterable, Identifiable {
  case disabled = "DISABLED"
  case auto = "AUTO"
  case required = "REQUIRED"

  var id: String { rawValue }
}

enum AgentTeamVisibilityMode: String, Codable, CaseIterable, Identifiable {
  case background = "BACKGROUND"
  case visible = "VISIBLE"

  var id: String { rawValue }
}

struct AgentRequestedMember: Codable, Equatable, Identifiable {
  var agentId: String
  var displayName: String
  var occurrence: Int
  var roleHint: String

  var instanceId: String {
    String("\(agentId):mention-\(max(occurrence, 1))".prefix(96))
  }

  var id: String { instanceId }

  init(
    agentId: String,
    displayName: String,
    occurrence: Int = 1,
    roleHint: String = ""
  ) {
    self.agentId = agentId
    self.displayName = displayName
    self.occurrence = max(occurrence, 1)
    self.roleHint = String(roleHint.prefix(240))
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case displayName = "display_name"
    case occurrence
    case roleHint = "role_hint"
  }
}

struct AgentTeamCompilationBudget: Codable, Equatable {
  var maxMembers: Int
  var maxCloudMembers: Int
  var maximumMemberCost: AgentResourceCost
  var maximumMemberLatency: AgentResourceLatency
  var maxEstimatedCostUnits: Int

  init(
    maxMembers: Int = 5,
    maxCloudMembers: Int = 1,
    maximumMemberCost: AgentResourceCost = .high,
    maximumMemberLatency: AgentResourceLatency = .slow,
    maxEstimatedCostUnits: Int = 16
  ) {
    self.maxMembers = maxMembers
    self.maxCloudMembers = maxCloudMembers
    self.maximumMemberCost = maximumMemberCost
    self.maximumMemberLatency = maximumMemberLatency
    self.maxEstimatedCostUnits = maxEstimatedCostUnits
  }

  enum CodingKeys: String, CodingKey {
    case maxMembers = "max_members"
    case maxCloudMembers = "max_cloud_members"
    case maximumMemberCost = "maximum_member_cost"
    case maximumMemberLatency = "maximum_member_latency"
    case maxEstimatedCostUnits = "max_estimated_cost_units"
  }
}

struct AgentDynamicTeamPolicy: Codable, Equatable {
  var forceTeam: Bool
  var trustedOnly: Bool
  var preferFailureDomainDiversity: Bool
  var verificationMode: AgentTeamVerificationMode
  var visibilityMode: AgentTeamVisibilityMode
  var pinnedAgentIds: Set<String>
  var excludedAgentIds: Set<String>
  var budget: AgentTeamCompilationBudget

  init(
    forceTeam: Bool = false,
    trustedOnly: Bool = true,
    preferFailureDomainDiversity: Bool = true,
    verificationMode: AgentTeamVerificationMode = .auto,
    visibilityMode: AgentTeamVisibilityMode = .background,
    pinnedAgentIds: Set<String> = [],
    excludedAgentIds: Set<String> = [],
    budget: AgentTeamCompilationBudget = AgentTeamCompilationBudget()
  ) {
    self.forceTeam = forceTeam
    self.trustedOnly = trustedOnly
    self.preferFailureDomainDiversity = preferFailureDomainDiversity
    self.verificationMode = verificationMode
    self.visibilityMode = visibilityMode
    self.pinnedAgentIds = pinnedAgentIds
    self.excludedAgentIds = excludedAgentIds
    self.budget = budget
  }

  enum CodingKeys: String, CodingKey {
    case forceTeam = "force_team"
    case trustedOnly = "trusted_only"
    case preferFailureDomainDiversity = "prefer_failure_domain_diversity"
    case verificationMode = "verification_mode"
    case visibilityMode = "visibility_mode"
    case pinnedAgentIds = "pinned_agent_ids"
    case excludedAgentIds = "excluded_agent_ids"
    case budget
  }
}

struct AgentDynamicTeamRequest: Codable, Equatable {
  var goal: String
  var teamId: String
  var policy: AgentDynamicTeamPolicy

  init(
    goal: String,
    teamId: String = UUID().uuidString,
    policy: AgentDynamicTeamPolicy = AgentDynamicTeamPolicy()
  ) {
    self.goal = goal
    self.teamId = teamId
    self.policy = policy
  }

  enum CodingKeys: String, CodingKey {
    case goal
    case teamId = "team_id"
    case policy
  }
}

struct AgentDynamicTeamAssignment: Codable, Equatable {
  var role: AgentDynamicTeamRole
  var registration: AgentRegistration
  var score: Int
  var requiredCapabilities: Set<AgentCapability>
  var objective: String
  var reasons: [String]

  var failureDomain: String {
    registration.effectiveTeamFailureDomain()
  }

  enum CodingKeys: String, CodingKey {
    case role
    case registration
    case score
    case requiredCapabilities = "required_capabilities"
    case objective
    case reasons
  }
}

struct AgentTeamMember: Codable, Equatable {
  var agentId: String
  var deliveryMode: AgentDeliveryMode
  var requiredCapabilities: Set<AgentCapability>
  var role: String
  var objective: String
  var dependsOnAgentIds: Set<String>
  var context: [String: String]
  var instanceId: String

  var memberId: String {
    instanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? agentId : instanceId
  }

  init(
    agentId: String,
    deliveryMode: AgentDeliveryMode,
    requiredCapabilities: Set<AgentCapability>,
    role: String,
    objective: String,
    dependsOnAgentIds: Set<String>,
    context: [String: String],
    instanceId: String = ""
  ) {
    self.agentId = agentId
    self.deliveryMode = deliveryMode
    self.requiredCapabilities = requiredCapabilities
    self.role = role
    self.objective = objective
    self.dependsOnAgentIds = dependsOnAgentIds
    self.context = context
    self.instanceId = instanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? agentId : instanceId
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case deliveryMode = "delivery_mode"
    case requiredCapabilities = "required_capabilities"
    case role
    case objective
    case dependsOnAgentIds = "depends_on_agent_ids"
    case context
    case instanceId = "instance_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let agentId = try container.decode(String.self, forKey: .agentId)
    self.init(
      agentId: agentId,
      deliveryMode: try container.decode(AgentDeliveryMode.self, forKey: .deliveryMode),
      requiredCapabilities: try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .requiredCapabilities) ?? [],
      role: try container.decodeIfPresent(String.self, forKey: .role) ?? "",
      objective: try container.decodeIfPresent(String.self, forKey: .objective) ?? "",
      dependsOnAgentIds: try container.decodeIfPresent(Set<String>.self, forKey: .dependsOnAgentIds) ?? [],
      context: try container.decodeIfPresent([String: String].self, forKey: .context) ?? [:],
      instanceId: try container.decodeIfPresent(String.self, forKey: .instanceId) ?? agentId
    )
  }
}

struct AgentTeamDefinition: Codable, Equatable {
  var teamId: String
  var primaryAgentId: String
  var members: [AgentTeamMember]
  var visibilityMode: AgentTeamVisibilityMode
  var collectiveCapabilities: Set<AgentCapability>
  var primaryInstanceId: String

  var primaryMemberId: String {
    primaryInstanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? primaryAgentId
      : primaryInstanceId
  }

  init(
    teamId: String,
    primaryAgentId: String,
    members: [AgentTeamMember],
    visibilityMode: AgentTeamVisibilityMode,
    collectiveCapabilities: Set<AgentCapability>,
    primaryInstanceId: String = ""
  ) {
    self.teamId = teamId
    self.primaryAgentId = primaryAgentId
    self.members = members
    self.visibilityMode = visibilityMode
    self.collectiveCapabilities = collectiveCapabilities
    self.primaryInstanceId = primaryInstanceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? primaryAgentId
      : primaryInstanceId
  }

  enum CodingKeys: String, CodingKey {
    case teamId = "team_id"
    case primaryAgentId = "primary_agent_id"
    case members
    case visibilityMode = "visibility_mode"
    case collectiveCapabilities = "collective_capabilities"
    case primaryInstanceId = "primary_instance_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let primaryAgentId = try container.decode(String.self, forKey: .primaryAgentId)
    self.init(
      teamId: try container.decode(String.self, forKey: .teamId),
      primaryAgentId: primaryAgentId,
      members: try container.decode([AgentTeamMember].self, forKey: .members),
      visibilityMode: try container.decodeIfPresent(AgentTeamVisibilityMode.self, forKey: .visibilityMode) ?? .background,
      collectiveCapabilities: try container.decodeIfPresent(Set<AgentCapability>.self, forKey: .collectiveCapabilities) ?? [],
      primaryInstanceId: try container.decodeIfPresent(String.self, forKey: .primaryInstanceId) ?? primaryAgentId
    )
  }
}

struct AgentDynamicTeamCompilation: Codable, Equatable {
  var outcome: AgentDynamicTeamOutcome
  var goal: String
  var requirements: AgentTaskRequirements
  var definition: AgentTeamDefinition?
  var primaryAgentId: String?
  var assignments: [AgentDynamicTeamAssignment]
  var unfilledRoles: Set<AgentDynamicTeamRole>
  var warnings: [String]
  var estimatedCostUnits: Int
  var failureDomains: Set<String>
  var rationale: [String]

  enum CodingKeys: String, CodingKey {
    case outcome
    case goal
    case requirements
    case definition
    case primaryAgentId = "primary_agent_id"
    case assignments
    case unfilledRoles = "unfilled_roles"
    case warnings
    case estimatedCostUnits = "estimated_cost_units"
    case failureDomains = "failure_domains"
    case rationale
  }
}
