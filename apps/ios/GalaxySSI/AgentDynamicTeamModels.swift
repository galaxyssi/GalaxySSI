import Foundation

struct AgentCollaborationGoalCheckpoint: Codable, Equatable {
  enum Phase: String, Codable { case planning, working, waiting }
  var runId: String
  var conversationId: String
  var turnId: String
  var revision: Int64
  var phase: Phase
  var contract: [AgentCollaborationGoalAssessmentPolicy.Criterion]
  var completedWorkIds: Set<String>
  var liveGraph: AgentCollaborationLiveGraph? = nil
}

struct AgentCollaborationLiveGraph: Codable, Equatable {
  enum DependencyPolicy: String, Codable { case success, terminal }
  enum Settlement: String, Codable { case succeeded, failed, cancelled, skipped }

  struct Work: Codable, Equatable {
    let id: String
    let member: String
    let assignment: String
    let depends_on: [String]
    let dependency_policy: DependencyPolicy?
    let independent_review: Bool?
  }

  struct Expansion: Decodable {
    let format: String
    let work: [Work]
  }

  private(set) var work: [Work] = []

  func appending(_ raw: String, authorizedMembers: Set<String>,
                 historicalAuthors: [String: String], settled: [String: Settlement]) -> Self? {
    guard raw.utf8.count <= 256_000,
          let expansion = try? JSONDecoder().decode(Expansion.self, from: Data(raw.utf8)),
          expansion.format == "galaxyssi.work-expansion.v1", !expansion.work.isEmpty else { return nil }
    var byId = Dictionary(work.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard byId.count == work.count else { return nil }
    for item in expansion.work {
      guard !item.id.isBlank, item.id.utf8.count <= 160, !item.assignment.isBlank,
            item.assignment.utf8.count <= 16_000, authorizedMembers.contains(item.member),
            byId[item.id] == nil, settled[item.id] == nil, historicalAuthors[item.id] == nil,
            Set(item.depends_on).count == item.depends_on.count,
            !item.depends_on.contains(item.id) else { return nil }
      byId[item.id] = item
    }
    for item in expansion.work {
      for dependency in item.depends_on {
        guard byId[dependency] != nil || settled[dependency] != nil else { return nil }
        if item.independent_review == true {
          guard let author = byId[dependency]?.member ?? historicalAuthors[dependency],
                !author.isBlank, author != item.member else { return nil }
        }
      }
    }
    var resolved = Set(settled.keys)
    var remaining = work + expansion.work
    while !remaining.isEmpty {
      let ready = remaining.filter { Set($0.depends_on).isSubset(of: resolved) }
      guard !ready.isEmpty else { return nil }
      let ids = Set(ready.map(\.id))
      resolved.formUnion(ids)
      remaining.removeAll { ids.contains($0.id) }
    }
    var next = self
    next.work.append(contentsOf: expansion.work)
    return next
  }

  func ready(settled: [String: Settlement], active: Set<String>) -> [Work] {
    work.filter { item in
      settled[item.id] == nil && !active.contains(item.id) && item.depends_on.allSatisfy { dependency in
        guard let state = settled[dependency] else { return false }
        return item.dependency_policy == .terminal || state == .succeeded
      }
    }
  }
}

enum AgentCollaborationGoalAssessmentPolicy {
  enum Verification: String, Codable { case documentary, computational, physical }
  enum Decision: String, Codable { case `continue`, achieved, blocked }
  enum EvidenceKind: String, Codable { case observed, simulation, proposal }

  struct Criterion: Codable, Equatable {
    enum Status: String, Codable { case met, open }
    var id: String
    var requirement: String
    var verification: Verification
    var status: Status
    var evidence_kind: EvidenceKind?
    var evidence: [String]
    var delivery: AgentCollaborationDocumentaryAcceptance.Reference? = nil
    var review: AgentCollaborationDocumentaryAcceptance.Reference? = nil
    var required_observations: [RequiredObservation]? = nil
  }

  struct RequiredObservation: Codable, Hashable {
    var origin: String
    var tool: String

    var isValid: Bool {
      ["ios_cloud_tool", "ios_native_tool", "desktop_codex_tool",
       "android_cloud_tool", "android_native_tool"].contains(origin) && !tool.isBlank
    }
  }

  struct Work: Codable {
    var id: String
    var member: String
    var assignment: String
  }

  struct Blocker: Codable {
    enum Kind: String, Codable { case resource, permission, connectivity, provider, capacity }
    struct Alternative: Codable {
      enum Status: String, Codable { case unavailable, needs_approval, not_applicable }
      var option: String
      var status: Status
      var result: String
      var evidence: [String]
    }
    var id: String
    var kind: Kind
    var reason: String
    var resume_when: String
    var alternatives: [Alternative]?
  }

  struct Assessment: Codable {
    var format: String
    var summary: String
    var decision: Decision
    var criteria: [Criterion]
    var work: [Work]
    var blockers: [Blocker]
    var recruit: [Work]?
  }

  struct VerifiedCriterion {
    var requirement: String
    var verification: Verification
    var evidence: Set<String>
    var originalObservations: Set<RequiredObservation> = []
  }

  enum Outcome: Equatable {
    case needsAssessment
    case schedule([String])
    case waiting([String])
    case achieved
  }

  static func evaluate(_ raw: String, preserving contract: [Criterion],
                       authorizedMembers: Set<String>, completedWork: Set<String>,
                       checkedBlockers: Set<String> = [],
                       verified: [String: VerifiedCriterion] = [:]) -> Outcome {
    guard raw.utf8.count <= 256_000,
          let assessment = try? JSONDecoder().decode(Assessment.self, from: Data(raw.utf8)),
          assessment.format == "galaxyssi.goal-assessment.v1",
          !assessment.summary.isBlank, !assessment.criteria.isEmpty,
          Set(assessment.criteria.map(\.id)).count == assessment.criteria.count,
          assessment.criteria.allSatisfy({ !$0.id.isBlank && !$0.requirement.isBlank &&
            ($0.required_observations ?? []).allSatisfy(\.isValid) }) else {
      return .needsAssessment
    }
    let criteria = Dictionary(uniqueKeysWithValues: assessment.criteria.map { ($0.id, $0) })
    guard contract.allSatisfy({ original in
      guard let current = criteria[original.id] else { return false }
      return current.requirement == original.requirement && current.verification == original.verification &&
        Set(original.required_observations ?? []).isSubset(of: Set(current.required_observations ?? []))
    }) else { return .needsAssessment }
    guard assessment.recruit?.isEmpty != false else { return .needsAssessment }

    if !assessment.work.isEmpty {
      let ids = assessment.work.map(\.id)
      guard assessment.decision == .continue, Set(ids).count == ids.count,
            completedWork.isDisjoint(with: ids), assessment.work.allSatisfy({
              !$0.id.isBlank && !$0.assignment.isBlank && authorizedMembers.contains($0.member)
            }) else { return .needsAssessment }
      return .schedule(ids)
    }
    switch assessment.decision {
    case .continue:
      return .needsAssessment
    case .blocked:
      let ids = assessment.blockers.map(\.id)
      guard !ids.isEmpty, Set(ids).count == ids.count,
            assessment.blockers.allSatisfy({ blocker in
              guard !blocker.id.isBlank, !blocker.reason.isBlank, !blocker.resume_when.isBlank else { return false }
              guard blocker.kind == .resource || blocker.kind == .permission else { return true }
              guard checkedBlockers.contains(blocker.id), let alternatives = blocker.alternatives,
                    !alternatives.isEmpty else { return false }
              return alternatives.allSatisfy {
                !$0.option.isBlank && !$0.result.isBlank && !$0.evidence.isEmpty &&
                  $0.evidence.allSatisfy { !$0.isBlank }
              }
            }) else { return .needsAssessment }
      return .waiting(ids)
    case .achieved:
      guard !contract.isEmpty, assessment.blockers.isEmpty,
            assessment.criteria.allSatisfy({ item in
              guard item.status == .met, let kind = item.evidence_kind, kind != .proposal,
                    item.verification != .physical || kind == .observed,
                    !item.evidence.isEmpty, item.evidence.allSatisfy({ !$0.isBlank }),
                    let receipt = verified[item.id], receipt.requirement == item.requirement,
                    receipt.verification == item.verification else { return false }
              return Set(item.evidence).isSubset(of: receipt.evidence) &&
                Set(item.required_observations ?? []).isSubset(of: receipt.originalObservations)
            }) else { return .needsAssessment }
      return .achieved
    }
  }
}

enum AgentCollaborationDocumentaryAcceptance {
  struct OriginalObservation {
    var origin: String
    var tool: String
    var status: String
    var kind: String
  }
  struct Reference: Codable, Equatable {
    var objectId: String
    var revision: Int64
    var sha256: String

    enum CodingKeys: String, CodingKey {
      case objectId = "object_id"
      case revision, sha256
    }
  }

  struct Revision {
    var reference: Reference
    var conversationId: String
    var runId: String
    var turnId: String
    var authorId: String
    var kind: String
    var body: AgentMcpJSONObject
    var parents: [Reference]
    var hostObservationIds: Set<String>
  }

  private struct Review: Decodable {
    var criterion_id: String
    var requirement: String
    var target: Reference
    var verdict: String
    var rationale: String
    var unresolved: [String]
  }

  static func validReviewPublication(body: AgentMcpJSONObject, parents: [Reference]) -> Bool {
    guard let raw = body["acceptance_review"]?.objectValue,
          let review = try? JSONDecoder().decode(Review.self, from: Data(AgentMcpJSONCodec.stringify(raw).utf8)),
          !review.criterion_id.isBlank, !review.requirement.isBlank, !review.rationale.isBlank,
          review.target.revision > 0, parents.contains(review.target),
          ["supported", "refuted", "not_tested"].contains(review.verdict),
          review.unresolved.allSatisfy({ !$0.isBlank }),
          review.verdict != "supported" || review.unresolved.isEmpty else { return false }
    return [review.target.objectId, review.target.sha256].allSatisfy { value in
      value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
  }

  static func evaluate(_ raw: String, preserving contract: [AgentCollaborationGoalAssessmentPolicy.Criterion],
                       conversationId: String, runId: String, turnId: String,
                       readRevision: (String, Int64?) throws -> Revision?,
                       observationIsSupporting: (String) throws -> Bool,
                       originalObservation: (String) throws -> OriginalObservation? = { _ in nil })
    -> AgentCollaborationGoalAssessmentPolicy.Outcome {
    typealias Policy = AgentCollaborationGoalAssessmentPolicy
    guard !conversationId.isBlank, !runId.isBlank, !turnId.isBlank, raw.utf8.count <= 256_000,
          let assessment = try? JSONDecoder().decode(Policy.Assessment.self, from: Data(raw.utf8)),
          assessment.decision == .achieved else { return .needsAssessment }

    func current(_ reference: Reference) throws -> Revision? {
      guard reference.revision > 0, !reference.objectId.isBlank,
            reference.sha256.utf8.count == 64,
            let record = try readRevision(reference.objectId, nil),
            record.reference == reference, record.conversationId == conversationId,
            record.runId == runId, record.turnId == turnId,
            !record.authorId.isBlank else { return nil }
      return record
    }

    var verified: [String: Policy.VerifiedCriterion] = [:]
    do {
      for criterion in assessment.criteria {
        guard criterion.verification == .documentary, criterion.evidence_kind == .observed,
              let deliveryRef = criterion.delivery, let reviewRef = criterion.review,
              let delivery = try current(deliveryRef), let review = try current(reviewRef),
              ["artifact", "proposal", "decision"].contains(delivery.kind),
              !delivery.body.string("content").isBlank,
              ["acceptance_review", "decision"].contains(review.kind),
              delivery.authorId != review.authorId,
              review.parents.contains(deliveryRef),
              let rawReview = review.body["acceptance_review"]?.objectValue,
              let check = try? JSONDecoder().decode(Review.self, from: Data(AgentMcpJSONCodec.stringify(rawReview).utf8)),
              check.criterion_id == criterion.id, check.requirement == criterion.requirement,
              check.target == deliveryRef, check.verdict == "supported",
              !check.rationale.isBlank, check.unresolved.isEmpty else { return .needsAssessment }
        var number: Int64 = 1
        while number < deliveryRef.revision {
          guard let previous = try readRevision(deliveryRef.objectId, number),
                previous.reference.objectId == deliveryRef.objectId,
                previous.reference.revision == number, previous.conversationId == conversationId,
                !previous.authorId.isBlank, previous.authorId != review.authorId else { return .needsAssessment }
          number += 1
        }
        let observations = delivery.hostObservationIds.union(review.hostObservationIds)
        guard try observations.allSatisfy(observationIsSupporting) else { return .needsAssessment }
        if let required = criterion.required_observations, !required.isEmpty {
          let originals = try review.hostObservationIds.compactMap(originalObservation)
          guard required.allSatisfy({ source in
            source.isValid && originals.contains {
              $0.origin == source.origin && $0.tool == source.tool &&
                $0.status == "returned" && $0.kind == "tool_output_recorded"
            }
          }) else { return .needsAssessment }
        }
        let receipts = observations.union([deliveryRef.objectId, reviewRef.objectId, deliveryRef.sha256, reviewRef.sha256])
        verified[criterion.id] = Policy.VerifiedCriterion(requirement: criterion.requirement,
          verification: .documentary, evidence: receipts,
          originalObservations: Set(criterion.required_observations ?? []))
      }
    } catch { return .needsAssessment }
    return Policy.evaluate(raw, preserving: contract, authorizedMembers: [], completedWork: [], verified: verified)
  }
}

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
