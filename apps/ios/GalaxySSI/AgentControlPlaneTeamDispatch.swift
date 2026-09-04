import Foundation

struct AgentControlPlaneTeamDispatchReceipt {
  var primaryRun: AgentRunHandle
  var memberRuns: [String: AgentRunHandle]
  var unavailableMembers: [String: String]
}

final class AgentControlPlaneTeamDispatchCoordinator {
  private let provider: ActionExecutorAgentProvider
  private let directory: AgentAdapterDirectory

  init(provider: ActionExecutorAgentProvider, directory: AgentAdapterDirectory) {
    self.provider = provider
    self.directory = directory
  }

  func dispatch(
    spec: AgentTeamDispatchSpec,
    action: AgentAction,
    screen: AgentScreenContext
  ) async throws -> AgentControlPlaneTeamDispatchReceipt {
    let members = spec.definition.members
    guard !spec.definition.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentControlPlaneAdapterError(message: "Team id must not be blank")
    }
    guard members.filter({ $0.deliveryMode == .respond }).count == 1,
      let primaryMember = members.first(where: {
        $0.memberId == spec.definition.primaryMemberId && $0.deliveryMode == .respond
      }) else {
      throw AgentControlPlaneAdapterError(message: "A team must expose exactly one responding primary Agent")
    }

    let conversationId = action.parameters[Self.conversationIdKey] ?? ""
    let turnId = action.parameters[Self.turnIdKey] ?? ""
    let baseGoal = (action.parameters["original_goal"] ?? "")
      .ifBlank(action.parameters["prompt"] ?? "")
      .ifBlank(action.description)
    let baseRequest = AgentRunRequest(
      conversationId: conversationId,
      messageId: turnId.ifBlank(action.id),
      taskId: turnId.ifBlank(spec.supervisorRunId),
      runId: spec.supervisorRunId,
      parentRunId: (action.parameters["parent_run_id"] ?? "").ifBlank(spec.supervisorRunId),
      goal: baseGoal,
      deliveryMode: .respond,
      requiredCapabilities: [],
      context: Self.baseContext(spec: spec, action: action),
      idempotencyKey: (action.parameters["idempotency_key"] ?? "").ifBlank(spec.supervisorRunId),
      createdAtMillis: AgentControlPlaneClock.nowMillis()
    )

    guard let primaryAdapter = try await directory.resolveAdapter(primaryMember.agentId) else {
      throw AgentControlPlaneAdapterError(message: "Primary Agent is unavailable: " + primaryMember.agentId)
    }
    let primaryCapabilities = Self.requiredCapabilities(
      request: baseRequest,
      member: primaryMember,
      definition: spec.definition
    )
    guard primaryCapabilities.isSubset(of: primaryAdapter.registration.capabilities) else {
      throw AgentControlPlaneAdapterError(message: "Primary Agent lacks required capabilities")
    }

    var primaryAction = action
    Self.prepareMemberAction(
      &primaryAction,
      member: primaryMember,
      teamRunId: baseRequest.runId,
      idempotencyKey: baseRequest.idempotencyKey,
      goal: baseRequest.goal
    )
    let primaryRequest = baseRequest.copyForTeam(
      runId: baseRequest.runId,
      parentRunId: baseRequest.parentRunId,
      deliveryMode: .respond,
      requiredCapabilities: primaryCapabilities,
      idempotencyKey: baseRequest.idempotencyKey,
      context: Self.memberContext(baseRequest.context, member: primaryMember)
    )
    provider.prepare(
      agentId: primaryMember.agentId,
      request: primaryRequest,
      action: primaryAction,
      screen: screen
    )
    let primaryRun: AgentRunHandle
    do {
      primaryRun = try await primaryAdapter.startRun(primaryRequest)
    } catch {
      provider.discardPrepared(agentId: primaryMember.agentId, runId: primaryRequest.runId)
      throw error
    }

    var memberRuns: [String: AgentRunHandle] = [primaryMember.memberId: primaryRun]
    var unavailableMembers: [String: String] = [:]
    for member in members where member.memberId != primaryMember.memberId && member.deliveryMode != .ignore {
      guard let adapter = try await directory.resolveAdapter(member.agentId) else {
        unavailableMembers[member.memberId] = "agent_unavailable"
        continue
      }
      let requiredCapabilities = Self.requiredCapabilities(
        request: baseRequest,
        member: member,
        definition: spec.definition
      )
      guard requiredCapabilities.isSubset(of: adapter.registration.capabilities) else {
        unavailableMembers[member.memberId] = "capability_mismatch"
        continue
      }

      let runId = AgentControlPlaneActionExecutor.stableRunId(
        conversationId: baseRequest.conversationId,
        turnId: baseRequest.taskId,
        actionId: action.id + ":team",
        agentId: member.memberId
      )
      let idempotencyKey = baseRequest.idempotencyKey + ":" + member.memberId
      let request = baseRequest.copyForTeam(
        runId: runId,
        parentRunId: primaryRun.runId,
        deliveryMode: member.deliveryMode,
        requiredCapabilities: requiredCapabilities,
        idempotencyKey: idempotencyKey,
        context: Self.memberContext(baseRequest.context, member: member)
      )
      var memberAction = action
      Self.prepareMemberAction(
        &memberAction,
        member: member,
        teamRunId: primaryRun.runId,
        idempotencyKey: idempotencyKey,
        goal: baseRequest.goal
      )
      provider.prepare(
        agentId: member.agentId,
        request: request,
        action: memberAction,
        screen: screen
      )
      do {
        memberRuns[member.memberId] = try await adapter.startRun(request)
      } catch {
        provider.discardPrepared(agentId: member.agentId, runId: request.runId)
        unavailableMembers[member.memberId] = error.localizedDescription.ifBlank("start_failed")
      }
    }

    return AgentControlPlaneTeamDispatchReceipt(
      primaryRun: primaryRun,
      memberRuns: memberRuns,
      unavailableMembers: unavailableMembers
    )
  }

  private static func baseContext(spec: AgentTeamDispatchSpec, action: AgentAction) -> AgentMcpJSONObject {
    let policyPrompt = AgentExecutionPolicyPrompt.bounded(
      (action.parameters[AgentExecutionPolicyPrompt.contextKey] ?? "")
        .ifBlank(action.parameters["original_goal"] ?? "")
        .ifBlank(action.parameters["prompt"] ?? "")
        .ifBlank(action.description)
    )
    return [
      "action_id": .string(action.id),
      "action_target": .string(action.target),
      "risk": .string(action.risk.rawValue.lowercased()),
      AgentExecutionPolicyPrompt.contextKey: .string(policyPrompt),
      "_galaxyssi_agent_team_id": .string(spec.definition.teamId),
      "_galaxyssi_agent_team_role": .string("supervisor"),
      "_galaxyssi_agent_team_visibility": .string(spec.definition.visibilityMode.rawValue)
    ]
  }

  private static func requiredCapabilities(
    request: AgentRunRequest,
    member: AgentTeamMember,
    definition: AgentTeamDefinition
  ) -> Set<AgentCapability> {
    if definition.collectiveCapabilities.isEmpty {
      return request.requiredCapabilities.union(member.requiredCapabilities)
    }
    return member.requiredCapabilities
  }

  private static func memberContext(
    _ base: AgentMcpJSONObject,
    member: AgentTeamMember
  ) -> AgentMcpJSONObject {
    var context = base
    context["_galaxyssi_agent_team_role"] = .string(member.role.ifBlank("member"))
    context["_galaxyssi_agent_team_delivery_mode"] = .string(member.deliveryMode.rawValue)
    context["_galaxyssi_agent_team_instance_id"] = .string(member.memberId)
    for item in member.context {
      context[item.key] = .string(item.value)
    }
    return context
  }

  private static func prepareMemberAction(
    _ action: inout AgentAction,
    member: AgentTeamMember,
    teamRunId: String,
    idempotencyKey: String,
    goal: String
  ) {
    action.id += "-team-" + member.memberId
    action.target = member.agentId
    action.description = member.objective.ifBlank(action.description)
    action.parameters.removeValue(forKey: agentTeamSpecParameter)
    action.parameters.removeValue(forKey: agentTeamRunParameter)
    action.parameters.removeValue(forKey: agentTeamSourceParameter)
    action.parameters["connector_id"] = member.agentId
    action.parameters["delivery_mode"] = member.deliveryMode.rawValue
    action.parameters["parent_run_id"] = teamRunId
    action.parameters["idempotency_key"] = idempotencyKey
    action.parameters["original_goal"] = goal
    action.parameters[AgentExecutionPolicyPrompt.contextKey] = goal
    for item in member.context {
      action.parameters[item.key] = item.value
    }
  }

  private static let conversationIdKey = "_galaxyssi_conversation_id"
  private static let turnIdKey = "_galaxyssi_turn_id"
}

private extension AgentRunRequest {
  func copyForTeam(
    runId: String,
    parentRunId: String,
    deliveryMode: AgentDeliveryMode,
    requiredCapabilities: Set<AgentCapability>,
    idempotencyKey: String,
    context: AgentMcpJSONObject
  ) -> AgentRunRequest {
    AgentRunRequest(
      conversationId: conversationId,
      messageId: messageId,
      taskId: taskId,
      runId: runId,
      parentRunId: parentRunId,
      goal: goal,
      deliveryMode: deliveryMode,
      requiredCapabilities: requiredCapabilities,
      context: context,
      idempotencyKey: idempotencyKey,
      createdAtMillis: createdAtMillis
    )
  }
}
