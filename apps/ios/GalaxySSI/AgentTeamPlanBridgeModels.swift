import CryptoKit
import Foundation

let agentTeamSpecParameter = "_galaxyssi_agent_team_spec"
let agentTeamRunParameter = "_galaxyssi_agent_team_run_id"
let agentTeamSourceParameter = "_galaxyssi_agent_team_source_id"

struct AgentTeamDispatchSpec: Codable, Equatable {
  var definition: AgentTeamDefinition
  var supervisorRunId: String

  var sourceMessageId: Int64 {
    AgentTeamDispatchIds.sourceMessageId(supervisorRunId: supervisorRunId)
  }

  var responseContactId: String {
    AgentTeamDispatchIds.responseContactId(teamId: definition.teamId)
  }
}

struct AgentOutboundTeamContext: Equatable {
  var teamId: String
  var supervisorRunId: String
  var primaryInstanceId: String
  var member: AgentTeamMember
  var sourceMessageId: String
  var executionPolicyPrompt: String

  init(
    teamId: String,
    supervisorRunId: String,
    primaryInstanceId: String,
    member: AgentTeamMember,
    sourceMessageId: String,
    executionPolicyPrompt: String = ""
  ) {
    self.teamId = teamId
    self.supervisorRunId = supervisorRunId
    self.primaryInstanceId = primaryInstanceId
    self.member = member
    self.sourceMessageId = sourceMessageId
    self.executionPolicyPrompt = AgentExecutionPolicyPrompt.bounded(executionPolicyPrompt)
  }

  var runId: String {
    member.deliveryMode == .respond
      ? supervisorRunId
      : AgentControlPlaneActionExecutor.stableRunId(
        conversationId: teamId,
        turnId: supervisorRunId,
        actionId: "agent-team-member",
        agentId: member.memberId
      )
  }

  func apply(to payload: inout [String: Any]) {
    payload["agent_instance_id"] = member.memberId
    payload["team_id"] = teamId
    payload["agent_team_message"] = true
    payload["delivery_mode"] = member.deliveryMode.rawValue
    payload["run_id"] = runId
    if !executionPolicyPrompt.isEmpty {
      payload[AgentExecutionPolicyPrompt.wireKey] = executionPolicyPrompt
    }
  }
}

enum AgentTeamDispatchSpecCodec {
  static let version = 2

  static func encode(_ spec: AgentTeamDispatchSpec) -> String {
    AgentMcpJSONCodec.stringify([
      "version": .int(Int64(version)),
      "supervisor_run_id": .string(spec.supervisorRunId),
      "team_id": .string(spec.definition.teamId),
      "primary_agent_id": .string(spec.definition.primaryAgentId),
      "primary_instance_id": .string(spec.definition.primaryMemberId),
      "visibility": .string(spec.definition.visibilityMode.rawValue),
      "collective_capabilities": .array(spec.definition.collectiveCapabilities.map(\.rawValue).sorted().map(AgentMcpJSONValue.string)),
      "members": .array(spec.definition.members.map { member in
        .object([
          "agent_id": .string(member.agentId),
          "instance_id": .string(member.memberId),
          "delivery_mode": .string(member.deliveryMode.rawValue),
          "capabilities": .array(member.requiredCapabilities.map(\.rawValue).sorted().map(AgentMcpJSONValue.string)),
          "role": .string(member.role),
          "objective": .string(member.objective),
          "depends_on": .array(member.dependsOnAgentIds.sorted().map(AgentMcpJSONValue.string)),
          "context": .object(member.context.reduce(into: AgentMcpJSONObject()) { result, item in
            result[item.key] = .string(String(item.value.prefix(8_000)))
          })
        ])
      })
    ])
  }

  static func decode(_ raw: String) -> AgentTeamDispatchSpec? {
    guard let data = raw.data(using: .utf8),
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data),
      object.int64("version") == Int64(version) else {
      return nil
    }
    let runId = object.string("supervisor_run_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let teamId = object.string("team_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let primaryAgentId = object.string("primary_agent_id").trimmingCharacters(in: .whitespacesAndNewlines)
    let primaryInstanceId = object.string("primary_instance_id")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(primaryAgentId)
    guard !runId.isEmpty, !teamId.isEmpty, !primaryAgentId.isEmpty,
      case .array(let rawMembers)? = object["members"],
      rawMembers.count >= 2,
      rawMembers.count <= 12 else {
      return nil
    }
    var members: [AgentTeamMember] = []
    for value in rawMembers {
      guard case .object(let item) = value else {
        return nil
      }
      let agentId = item.string("agent_id").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !agentId.isEmpty,
        let deliveryMode = AgentDeliveryMode(rawValue: item.string("delivery_mode")) else {
        return nil
      }
      members.append(AgentTeamMember(
        agentId: agentId,
        deliveryMode: deliveryMode,
        requiredCapabilities: capabilities(from: item["capabilities"]),
        role: String(item.string("role").prefix(80)),
        objective: String(item.string("objective").prefix(4_000)),
        dependsOnAgentIds: Set(strings(from: item["depends_on"])),
        context: context(from: item["context"]),
        instanceId: item.string("instance_id")
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .ifBlank(agentId)
      ))
    }
    let memberIds = Set(members.map(\.memberId))
    guard memberIds.count == members.count,
      members.filter({ $0.deliveryMode == .respond }).count == 1,
      members.contains(where: { $0.memberId == primaryInstanceId && $0.deliveryMode == .respond }),
      members.allSatisfy({ !$0.dependsOnAgentIds.contains($0.memberId) && $0.dependsOnAgentIds.isSubset(of: memberIds) }) else {
      return nil
    }
    return AgentTeamDispatchSpec(
      definition: AgentTeamDefinition(
        teamId: teamId,
        primaryAgentId: primaryAgentId,
        members: members,
        visibilityMode: AgentTeamVisibilityMode(rawValue: object.string("visibility")) ?? .background,
        collectiveCapabilities: capabilities(from: object["collective_capabilities"]),
        primaryInstanceId: primaryInstanceId
      ),
      supervisorRunId: runId
    )
  }

  private static func strings(from value: AgentMcpJSONValue?) -> [String] {
    guard case .array(let values) = value else {
      return []
    }
    return values.compactMap { item -> String? in
      let text = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return text.isEmpty ? nil : text
    }
  }

  private static func capabilities(from value: AgentMcpJSONValue?) -> Set<AgentCapability> {
    Set(strings(from: value).compactMap(AgentCapability.fromWireValue))
  }

  private static func context(from value: AgentMcpJSONValue?) -> [String: String] {
    guard case .object(let object) = value else {
      return [:]
    }
    return object.reduce(into: [String: String]()) { result, item in
      guard item.key.hasPrefix("_galaxyssi_") else { return }
      result[item.key] = String((item.value.stringValue ?? "").prefix(8_000))
    }
  }
}

enum AgentTeamDispatchIds {
  static func teamId(plan: AgentPlan, actions: [AgentAction]) -> String {
    let conversationId = actions.compactMap { nonBlank($0.parameters["_galaxyssi_conversation_id"] ?? "") }.first ?? ""
    let turnId = actions.compactMap { nonBlank($0.parameters["_galaxyssi_turn_id"] ?? "") }.first ?? ""
    var source = "galaxyssi-agent-team\u{001f}\(conversationId)\u{001f}\(turnId)\u{001f}\(plan.planId)\u{001f}"
    for action in actions {
      source += "\(action.id):\(action.parameters["connector_id"] ?? "")\u{001f}"
    }
    return nameBasedUUID(source).uuidString.lowercased()
  }

  static func supervisorRunId(teamId: String) -> String {
    nameBasedUUID("galaxyssi-agent-team-run\u{001f}\(teamId)").uuidString.lowercased()
  }

  static func responseContactId(teamId: String) -> String {
    "agent-team:\(teamId)"
  }

  static func sourceMessageId(supervisorRunId: String) -> Int64 {
    let uuid = nameBasedUUID("galaxyssi-agent-team-response\u{001f}\(supervisorRunId)").uuid
    let bytes = [
      uuid.0, uuid.1, uuid.2, uuid.3,
      uuid.4, uuid.5, uuid.6, uuid.7,
      uuid.8, uuid.9, uuid.10, uuid.11,
      uuid.12, uuid.13, uuid.14, uuid.15
    ]
    let mostSignificantBits = int64Bits(bytes.prefix(8))
    let leastSignificantBits = int64Bits(bytes.suffix(8))
    let value = (mostSignificantBits ^ leastSignificantBits) & sourceIdPayloadMask
    return Int64(value | sourceIdNamespaceBit)
  }

  private static func nameBasedUUID(_ value: String) -> UUID {
    var bytes = Array(Insecure.MD5.hash(data: Data(value.utf8)))
    bytes[6] = (bytes[6] & 0x0f) | 0x30
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3],
      bytes[4], bytes[5],
      bytes[6], bytes[7],
      bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }

  private static func nonBlank(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func int64Bits(_ bytes: ArraySlice<UInt8>) -> UInt64 {
    bytes.reduce(UInt64(0)) { result, byte in
      (result << 8) | UInt64(byte)
    }
  }

  private static let sourceIdNamespaceBit: UInt64 = 1 << 62
  private static let sourceIdPayloadMask: UInt64 = sourceIdNamespaceBit - 1
}

enum AgentTeamPlanCompiler {
  static func compile(
    plan: AgentPlan,
    targets: [AgentCallableTarget],
    enabled: Bool,
    registrations: [AgentRegistration] = [],
    requestedMembers: [AgentRequestedMember] = [],
    reputations: [String: AgentReputationSnapshot] = [:],
    reputationRevision: Int64 = 0
  ) -> AgentPlan {
    guard plan.validation.valid else {
      return plan
    }
    var availableAgents: [String: AgentCallableTarget] = [:]
    for target in targets where [.agent, .model].contains(target.kind) && target.status == .available {
      availableAgents[target.id] = target
    }
    if !requestedMembers.isEmpty {
      return compileRequestedSelection(
        plan: plan,
        requestedMembers: requestedMembers,
        availableAgents: availableAgents,
        registrations: registrations
      )
    }
    guard enabled else { return plan }
    let candidates = plan.actions.compactMap { action -> Candidate? in
      guard action.kind == .callConnector,
        let connectorId = nonBlank(action.parameters["connector_id"] ?? ""),
        let target = availableAgents[connectorId] else {
        return nil
      }
      return Candidate(action: action, target: target)
    }
    if candidates.count == 1,
      plan.actions.filter({ $0.kind == .callConnector }).count == 1,
      !registrations.isEmpty,
      let dynamic = compileDynamicTeam(
        plan: plan,
        candidate: candidates[0],
        availableAgents: availableAgents,
        registrations: registrations,
        reputations: reputations,
        reputationRevision: reputationRevision,
        forceTeam: AgentExplicitMultiAgentIntentPolicy.matches(plan.goal)
      ) {
      return dynamic
    }
    if candidates.count == 1,
      AgentExplicitMultiAgentIntentPolicy.matches(plan.goal) {
      let eligible = registrations
        .filter { registration in
          availableAgents[registration.agentId] != nil &&
            [.online, .idle, .busy].contains(registration.status) &&
            registration.hasCapacity &&
            registration.trust != .unknown
        }
        .sorted { lhs, rhs in
          if lhs.agentId == candidates[0].target.id { return true }
          if rhs.agentId == candidates[0].target.id { return false }
          return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
      let requested = eligible.prefix(min(maxTeamMembers, 4)).enumerated().map {
        AgentRequestedMember(
          agentId: $0.element.agentId,
          displayName: $0.element.displayName,
          occurrence: 1
        )
      }
      if requested.count >= minTeamMembers {
        return compileRequestedSelection(
          plan: plan,
          requestedMembers: requested,
          availableAgents: availableAgents,
          registrations: registrations
        )
      }
    }
    guard candidates.count >= minTeamMembers,
      candidates.count <= maxTeamMembers else {
      return plan
    }
    let candidateCounts = Dictionary(grouping: candidates, by: { $0.target.id }).mapValues(\.count)
    if candidateCounts.contains(where: { $0.value > 1 }) {
      let registrationById = Dictionary(uniqueKeysWithValues: registrations.map { ($0.agentId, $0) })
      guard candidateCounts.allSatisfy({ entry in
        guard entry.value > 1 else { return true }
        guard let registration = registrationById[entry.key] else { return false }
        return entry.value <= max(registration.maxParallelRuns - registration.activeRuns, 0)
      }) else {
        return plan
      }
    }
    let candidateActionIds = Set(candidates.map { $0.action.id })
    guard candidates.allSatisfy({ candidate in
      candidate.action.dependencyIds().isSubset(of: candidateActionIds) &&
        candidate.action.outputSourceIds().isSubset(of: candidate.action.dependencyIds())
    }) else {
      return plan
    }
    let dependencyTargets = Set(candidates.flatMap { $0.action.dependencyIds() })
    let sinks = candidates.filter { !dependencyTargets.contains($0.action.id) }
    guard sinks.count == 1 else {
      return plan
    }
    let primary = sinks[0]
    guard transitiveDependencies(actionId: primary.action.id, candidates: candidates).union([primary.action.id]) == candidateActionIds else {
      return plan
    }

    let memberIdByAction = Dictionary(uniqueKeysWithValues: candidates.map { candidate in
      let repeated = candidateCounts[candidate.target.id, default: 0] > 1
      return (candidate.action.id, repeated ? instanceId(agentId: candidate.target.id, actionId: candidate.action.id) : candidate.target.id)
    })
    let members = candidates.map { candidate -> AgentTeamMember in
      let isPrimary = candidate.action.id == primary.action.id
      return AgentTeamMember(
        agentId: candidate.target.id,
        deliveryMode: isPrimary ? .respond : .observe,
        requiredCapabilities: Set(candidate.target.capabilities),
        role: role(for: candidate.target, primary: isPrimary),
        objective: String(nonBlank(candidate.action.parameters["prompt"] ?? "") ?? candidate.action.description).clamped(to: maxMemberObjectiveCharacters),
        dependsOnAgentIds: Set(candidate.action.dependencyIds().compactMap { memberIdByAction[$0] }),
        context: [
          agentKnowledgeContextKey: String((candidate.action.parameters[agentKnowledgeContextKey] ?? "").prefix(maxMemberKnowledgeCharacters))
        ].filter { !$0.value.isEmpty },
        instanceId: memberIdByAction[candidate.action.id] ?? candidate.target.id
      )
    }
    let teamId = AgentTeamDispatchIds.teamId(plan: plan, actions: candidates.map(\.action))
    let runId = AgentTeamDispatchIds.supervisorRunId(teamId: teamId)
    let definition = AgentTeamDefinition(
      teamId: teamId,
      primaryAgentId: primary.target.id,
      members: members,
      visibilityMode: .background,
      collectiveCapabilities: Set(members.flatMap(\.requiredCapabilities)),
      primaryInstanceId: memberIdByAction[primary.action.id] ?? primary.target.id
    )
    return compile(
      plan: plan,
      candidateActions: candidates.map(\.action),
      primaryTarget: primary.target,
      primaryAction: primary.action,
      definition: definition,
      runId: runId,
      risk: candidates.map(\.action.risk).max(by: { $0.weight < $1.weight }) ?? .medium,
      requiresConfirmation: candidates.contains { $0.action.requiresConfirmation },
      targets: targets
    )
  }

  private static func compileRequestedSelection(
    plan: AgentPlan,
    requestedMembers: [AgentRequestedMember],
    availableAgents: [String: AgentCallableTarget],
    registrations: [AgentRegistration]
  ) -> AgentPlan {
    let requested = Array(requestedMembers.prefix(maxTeamMembers))
    guard !requested.isEmpty else { return plan }
    let registrationById = Dictionary(uniqueKeysWithValues: registrations.map { ($0.agentId, $0) })
    let requestedCounts = Dictionary(grouping: requested, by: \.agentId).mapValues(\.count)
    guard requestedCounts.allSatisfy({ entry in
      guard availableAgents[entry.key] != nil,
        let registration = registrationById[entry.key],
        [.online, .idle, .busy].contains(registration.status) else {
        return false
      }
      return entry.value <= max(registration.maxParallelRuns - registration.activeRuns, 0)
    }) else {
      return plan
    }
    if requested.count == 1,
      let member = requested.first,
      let target = availableAgents[member.agentId] {
      return compileRequestedSingle(plan: plan, member: member, target: target)
    }
    guard let primaryRequest = requested.first,
      let primaryTarget = availableAgents[primaryRequest.agentId] else {
      return plan
    }
    let memberIds = requested.map(\.instanceId)
    let members = requested.enumerated().compactMap { index, requestedMember -> AgentTeamMember? in
      guard let target = availableAgents[requestedMember.agentId] else { return nil }
      let isPrimary = index == 0
      let explicitRole = requestedMember.roleHint.trimmingCharacters(in: .whitespacesAndNewlines)
      let objectivePrefix = isPrimary
        ? "Lead the selected Agent team, use every member result, and produce one final answer."
        : "Contribute as \(role(for: target, primary: false))."
      let objective = [
        objectivePrefix,
        explicitRole.isEmpty ? "" : "Explicit role: \(explicitRole).",
        "User goal: \(plan.goal)"
      ].filter { !$0.isEmpty }.joined(separator: " ")
      return AgentTeamMember(
        agentId: requestedMember.agentId,
        deliveryMode: isPrimary ? .respond : .observe,
        requiredCapabilities: Set(target.capabilities),
        role: role(for: target, primary: isPrimary),
        objective: String(objective.prefix(maxMemberObjectiveCharacters)),
        dependsOnAgentIds: isPrimary ? Set(memberIds.dropFirst()) : [],
        context: [
          "_galaxyssi_selection_source": "user_mention",
          "_galaxyssi_role_hint": explicitRole
        ],
        instanceId: requestedMember.instanceId
      )
    }
    guard members.count == requested.count else { return plan }
    let memberActions = requested.enumerated().map { index, member in
      AgentAction(
        id: "mention-\(index)-\(member.occurrence)",
        kind: .callConnector,
        target: availableAgents[member.agentId]?.title ?? member.displayName,
        risk: .low,
        status: .pendingConfirmation,
        description: "Selected Agent team member \(member.displayName)",
        parameters: ["connector_id": member.agentId, "prompt": plan.goal],
        requiresConfirmation: false
      )
    }
    let teamId = AgentTeamDispatchIds.teamId(plan: plan, actions: memberActions)
    let runId = AgentTeamDispatchIds.supervisorRunId(teamId: teamId)
    let definition = AgentTeamDefinition(
      teamId: teamId,
      primaryAgentId: primaryRequest.agentId,
      members: members,
      visibilityMode: .background,
      collectiveCapabilities: Set(members.flatMap(\.requiredCapabilities)),
      primaryInstanceId: primaryRequest.instanceId
    )
    let template = plan.actions.first ?? memberActions[0]
    return compileRequestedTeam(
      plan: plan,
      primaryTarget: primaryTarget,
      template: template,
      definition: definition,
      runId: runId,
      targets: Array(availableAgents.values)
    )
  }

  private static func compileRequestedSingle(
    plan: AgentPlan,
    member: AgentRequestedMember,
    target: AgentCallableTarget
  ) -> AgentPlan {
    guard var action = plan.actions.first else { return plan }
    action.id = "agent-mention-\(member.occurrence)"
    action.kind = .callConnector
    action.target = target.title
    action.status = .pendingConfirmation
    action.description = "Run with selected Agent \(target.title)"
    action.parameters["connector_id"] = member.agentId
    action.parameters["prompt"] = plan.goal
    action.parameters["original_goal"] = plan.goal
    action.parameters["manual_target_locked"] = "true"
    action.parameters["agent_selection_source"] = "user_mention"
    var compiled = plan
    compiled.actions = [action]
    compiled.selectedAgentOrModel = target.title
    compiled.expectedResult = action.description
    compiled.route = route(for: target)
    compiled.plannerProfile += "+user-mention"
    compiled.routeRationale = "The user explicitly selected \(target.title)."
    compiled.validation = AgentPlanValidator.validate(compiled)
    return compiled.validation.valid ? compiled : plan
  }

  private static func compileRequestedTeam(
    plan: AgentPlan,
    primaryTarget: AgentCallableTarget,
    template: AgentAction,
    definition: AgentTeamDefinition,
    runId: String,
    targets: [AgentCallableTarget]
  ) -> AgentPlan {
    let spec = AgentTeamDispatchSpec(definition: definition, supervisorRunId: runId)
    var action = template
    action.id = "agent-team-\(definition.teamId.prefix(12))"
    action.kind = .callConnector
    action.target = "Agent team: \(primaryTarget.title)"
    action.status = .pendingConfirmation
    action.description = "Coordinate \(definition.members.count) user-selected Agents"
    action.parameters = template.parameters.merging([
      "connector_id": definition.primaryAgentId,
      "prompt": plan.goal,
      "original_goal": plan.goal,
      "node_ref": "agent_team",
      "agent_selection_source": "user_mention",
      "manual_target_locked": "true",
      agentTeamSpecParameter: AgentTeamDispatchSpecCodec.encode(spec),
      agentTeamRunParameter: runId,
      agentTeamSourceParameter: String(spec.sourceMessageId)
    ]) { _, new in new }
    var compiled = plan
    compiled.actions = [action]
    compiled.selectedAgentOrModel = action.target
    compiled.expectedResult = action.description
    compiled.timeoutSeconds = min(max(plan.timeoutSeconds, teamTimeoutSeconds), 240)
    compiled.route = route(for: primaryTarget)
    compiled.plannerProfile += "+user-mention-team"
    compiled.routeRationale = "The user explicitly selected \(definition.members.count) Agent instances."
    compiled.validation = AgentPlanValidator.validate(compiled)
    return compiled.validation.valid ? compiled : plan
  }

  static func rekeyAgentTeamForRetry(_ action: AgentAction) -> AgentAction {
    guard let spec = AgentTeamDispatchSpecCodec.decode(action.parameters[agentTeamSpecParameter] ?? "") else {
      return action
    }
    let nextTeamId = UUID().uuidString.lowercased()
    let nextRunId = AgentTeamDispatchIds.supervisorRunId(teamId: nextTeamId)
    var nextDefinition = spec.definition
    nextDefinition.teamId = nextTeamId
    let nextSpec = AgentTeamDispatchSpec(definition: nextDefinition, supervisorRunId: nextRunId)
    var retry = action
    retry.parameters[agentTeamSpecParameter] = AgentTeamDispatchSpecCodec.encode(nextSpec)
    retry.parameters[agentTeamRunParameter] = nextRunId
    retry.parameters[agentTeamSourceParameter] = String(nextSpec.sourceMessageId)
    return retry
  }

  private static func compileDynamicTeam(
    plan: AgentPlan,
    candidate: Candidate,
    availableAgents: [String: AgentCallableTarget],
    registrations: [AgentRegistration],
    reputations: [String: AgentReputationSnapshot],
    reputationRevision: Int64,
    forceTeam: Bool = false
  ) -> AgentPlan? {
    let eligibleRegistrations = registrations.filter {
      $0.kind == .agent && availableAgents[$0.agentId] != nil
    }
    guard eligibleRegistrations.count >= minTeamMembers else {
      return nil
    }
    let teamId = AgentTeamDispatchIds.teamId(plan: plan, actions: [candidate.action])
    let compilation = AgentDynamicTeamCompiler().compile(
      request: AgentDynamicTeamRequest(
        goal: plan.goal,
        teamId: teamId,
        policy: AgentDynamicTeamPolicy(
          forceTeam: forceTeam,
          pinnedAgentIds: [candidate.target.id]
        )
      ),
      registrations: eligibleRegistrations,
      reputations: reputations,
      reputationRevision: reputationRevision
    )
    guard compilation.outcome == .team,
      let definition = compilation.definition,
      definition.members.allSatisfy({ availableAgents[$0.agentId] != nil }),
      let primary = availableAgents[definition.primaryAgentId] else {
      return nil
    }
    let runId = AgentTeamDispatchIds.supervisorRunId(teamId: teamId)
    return compile(
      plan: plan,
      candidateActions: [candidate.action],
      primaryTarget: primary,
      primaryAction: candidate.action,
      definition: definition,
      runId: runId,
      risk: candidate.action.risk,
      requiresConfirmation: candidate.action.requiresConfirmation,
      targets: Array(availableAgents.values)
    )
  }

  private static func compile(
    plan: AgentPlan,
    candidateActions: [AgentAction],
    primaryTarget: AgentCallableTarget,
    primaryAction: AgentAction,
    definition: AgentTeamDefinition,
    runId: String,
    risk: AgentRisk,
    requiresConfirmation: Bool,
    targets: [AgentCallableTarget]
  ) -> AgentPlan {
    let spec = AgentTeamDispatchSpec(definition: definition, supervisorRunId: runId)
    let syntheticId = "agent-team-\(definition.teamId.prefix(12))"
    var synthetic = primaryAction
    synthetic.id = syntheticId
    synthetic.target = "Agent team: \(primaryTarget.title)"
    synthetic.risk = risk
    synthetic.status = .pendingConfirmation
    synthetic.description = "Coordinate \(definition.members.count) specialist Agents"
    synthetic.parameters = primaryAction.parameters.merging([
      "connector_id": definition.primaryAgentId,
      "original_goal": plan.goal,
      "node_ref": "agent_team",
      "depends_on": "",
      "use_outputs_from": "",
      agentTeamSpecParameter: AgentTeamDispatchSpecCodec.encode(spec),
      agentTeamRunParameter: runId,
      agentTeamSourceParameter: String(spec.sourceMessageId)
    ]) { _, new in new }
    synthetic.requiresConfirmation = requiresConfirmation

    let candidateIds = Set(candidateActions.map(\.id))
    let idMap = Dictionary(uniqueKeysWithValues: plan.actions.map { ($0.id, candidateIds.contains($0.id) ? syntheticId : $0.id) })
    var inserted = false
    var actions: [AgentAction] = []
    for action in plan.actions {
      if candidateIds.contains(action.id) {
        if !inserted {
          actions.append(synthetic)
          inserted = true
        }
      } else {
        actions.append(action.remappingToolGraphIds(idMap: idMap))
      }
    }
    var compiled = plan
    compiled.actions = actions
    compiled.selectedAgentOrModel = "Agent team: \(primaryTarget.title)"
    compiled.timeoutSeconds = min(max(plan.timeoutSeconds, teamTimeoutSeconds), 240)
    compiled.route = route(for: primaryTarget)
    compiled.validation = AgentPlanValidator.validate(compiled)
    return compiled.validation.valid ? compiled : plan
  }

  private static func transitiveDependencies(actionId: String, candidates: [Candidate]) -> Set<String> {
    let byId = Dictionary(uniqueKeysWithValues: candidates.map { ($0.action.id, $0.action) })
    var visited = Set<String>()
    func visit(_ id: String) {
      for dependencyId in byId[id]?.dependencyIds() ?? [] where visited.insert(dependencyId).inserted {
        visit(dependencyId)
      }
    }
    visit(actionId)
    return visited
  }

  private static func role(for target: AgentCallableTarget, primary: Bool) -> String {
    if primary { return "lead synthesizer" }
    let capabilities = Set(target.capabilities)
    if capabilities.contains(.code) { return "software specialist" }
    if capabilities.contains(.research) || capabilities.contains(.liveData) { return "research specialist" }
    if capabilities.contains(.knowledgeSearch) { return "knowledge specialist" }
    if capabilities.contains(.deviceControl) || capabilities.contains(.smartHome) { return "device specialist" }
    if capabilities.contains(.taskExecution) { return "execution specialist" }
    return "reasoning specialist"
  }

  private static func route(for target: AgentCallableTarget) -> AgentRoute {
    let kind: AgentRouteKind
    switch target.kind {
    case .agent:
      kind = .desktopAgent
    case .model:
      kind = .cloudModel
    case .device:
      kind = .deviceConnector
    case .knowledge:
      kind = .knowledge
    }
    return AgentRoute(
      routeId: "connector:\(target.id)",
      kind: kind,
      targetId: target.id,
      targetTitle: target.title,
      status: target.status.rawValue,
      deliveryMode: "team",
      capabilities: target.capabilities.map(\.rawValue).sorted()
    )
  }

  private static func instanceId(agentId: String, actionId: String) -> String {
    String("\(agentId):\(actionId)".prefix(160))
  }

  private static func nonBlank(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private struct Candidate {
    var action: AgentAction
    var target: AgentCallableTarget
  }

  private static let minTeamMembers = 2
  private static let maxTeamMembers = 12
  private static let maxMemberObjectiveCharacters = 4_000
  private static let maxMemberKnowledgeCharacters = 8_000
  private static let teamTimeoutSeconds = 180
  private static let agentKnowledgeContextKey = "_galaxyssi_agent_knowledge_context"
}

private extension AgentAction {
  func dependencyIds() -> Set<String> {
    Set(listParameter("depends_on"))
  }

  func outputSourceIds() -> Set<String> {
    Set(listParameter("use_outputs_from"))
  }

  func remappingToolGraphIds(idMap: [String: String]) -> AgentAction {
    var copy = self
    copy.parameters["depends_on"] = stableDistinctStrings(listParameter("depends_on").map { idMap[$0] ?? $0 }).joined(separator: ",")
    copy.parameters["use_outputs_from"] = stableDistinctStrings(listParameter("use_outputs_from").map { idMap[$0] ?? $0 }).joined(separator: ",")
    return copy
  }

  private func listParameter(_ key: String) -> [String] {
    (parameters[key] ?? "")
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }
}

private func stableDistinctStrings(_ values: [String]) -> [String] {
  var seen = Set<String>()
  return values.filter { seen.insert($0).inserted }
}

private extension String {
  func clamped(to limit: Int) -> String {
    String(prefix(max(limit, 0)))
  }
}
