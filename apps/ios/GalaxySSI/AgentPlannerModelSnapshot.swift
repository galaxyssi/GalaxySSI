import Foundation

struct AgentPlannerModelSnapshot: Codable, Equatable {
  var settings: AgentModelPlannerSettings
  var route: AgentPlannerProviderRoute?
  var localProfileId: String?
  var selectedForPhoneTurn: Bool? = nil
  var pairedPhonePlanner: AgentPairedPhonePlannerRoute? = nil

  var configurationSha256: String {
    AgentModelLoopRecoveryIdentity.sha256(self)
  }
}

struct AgentPairedPhonePlannerRoute: Codable, Equatable {
  static let connectorMode = "phone_supervised_project_plan_v1"
  static let ownerPrefix = "ios-phone-planner-v1:"

  var contactId: String
  var desktopId: String
  var clientRouteId: String
  var modelId: String
  var reasoningEffort: AgentModelReasoningEffort

  func dispatchIdentity(
    ownerId: String, invocation: AgentModelPlanningInvocation
  ) -> (owner: String, source: Int64, task: AgentTaskIdentity) {
    let request = invocation.request
    let conversation = request.conversationContext.conversationId
    let turn = request.executionTurnId
    let digest = AgentModelLoopRecoveryIdentity.sha256([
      "owner": ownerId,
      "route": AgentModelLoopRecoveryIdentity.sha256(self),
      "conversation": conversation,
      "turn": turn,
      "reason": request.parsingContext.replanReason,
      "history": AgentModelLoopRecoveryIdentity.sha256(request.executionHistory),
      "requirements": AgentModelLoopRecoveryIdentity.sha256(request.planRequest.completionRequirements),
      "kind": invocation.completionShapeRepairOnly == true ? "shape-repair" : "plan"
    ])
    // Thirteen hex digits fit exactly in every JSON number implementation.
    let source = max(1, Int64(digest.prefix(13), radix: 16) ?? 0)
    let taskId = AgentTaskIdentityPolicy.taskId(ownerId: ownerId, contactId: contactId,
      sourceMessageId: source, conversationId: conversation, turnId: turn)
    return (Self.ownerPrefix + digest, source, AgentTaskIdentity(clientRouteId: clientRouteId,
      conversationId: conversation, taskId: taskId, turnId: turn))
  }

  func accepts(contact: GalaxySSIContact, link: ServerLink) -> Bool {
    !contact.deleted && contact.id == contactId && contact.desktopId == desktopId &&
      contact.trustState == .verified && contact.deliveryMode.isGalaxySSILinkFamily &&
      contact.connectorAgentId == "codex" && link.paired && link.desktopId == desktopId &&
      link.routes.clientRouteId == clientRouteId &&
      contact.connectorInvocationProfile.models.contains(where: { $0.id == modelId })
  }

  func requestPayload(
    identity: AgentTaskIdentity, source: String, sender: String, prompt: String,
    responseLanguage: String, now: Int64
  ) -> [String: Any]? {
    guard identity.isComplete, identity.clientRouteId == clientRouteId,
          !source.isBlank, !sender.isBlank, !prompt.isBlank,
          let parameters = AgentInvocationRequestJsonCodec.encode(modelId: modelId, reasoningEffort: reasoningEffort)
    else { return nil }
    return [
      "type": "text", "message_id": identity.taskId, "content": prompt,
      "contact_id": contactId, "desktop_id": desktopId, "agent_id": "codex",
      "sender": sender, "client_route_id": identity.clientRouteId,
      "conversation_id": identity.conversationId, "turn_id": identity.turnId, "task_id": identity.taskId,
      "source_message_id": source, "client_message_id": source, "time": now,
      "connector_task_mode": Self.connectorMode,
      "execution_mode": AgentTaskExecutionMode.planOnly.rawValue,
      "_galaxyssi_task_execution_mode": AgentTaskExecutionMode.planOnly.rawValue,
      "_galaxyssi_long_term_write_allowed": "false", "agent_invocation": parameters,
      "response_language": responseLanguage
    ]
  }
}

struct AgentPairedPhonePlanningProvider: AgentModelPlanningProviding {
  var send: @MainActor (AgentModelPlanningInvocation) async throws -> String

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    try await send(invocation)
  }
}

struct AgentPlannerProviderRoute: Codable, Equatable {
  var contactId: String
  var provider: String
  var endpoint: String
  var modelId: String
  var apiStyle: GalaxySSICloudAPIStyle

  init(resolution: AgentModelPlannerContactResolution) {
    contactId = resolution.contactId
    provider = resolution.contact.cloudProvider
    endpoint = resolution.selectedModel.endpoint
    modelId = resolution.selectedModel.modelId
    apiStyle = resolution.selectedModel.apiStyle
  }

  func resolve(
    contacts: [GalaxySSIContact],
    apiKey: (CloudModelConfig) -> String?
  ) throws -> AgentModelPlannerContactResolution {
    guard let contact = contacts.first(where: {
      $0.id == contactId || $0.galaxySSIId == contactId
    }), !contact.deleted else {
      throw AgentModelLoopRecoveryError(code: "planner_provider_contact_unavailable")
    }
    guard contact.deliveryMode == .cloudAPI,
          contact.cloudProvider == provider else {
      throw AgentModelLoopRecoveryError(code: "planner_provider_route_changed")
    }
    guard let model = contact.cloudModels.first(where: { $0.modelId == modelId }) else {
      throw AgentModelLoopRecoveryError(code: "planner_provider_model_unavailable")
    }
    guard model.endpoint == endpoint,
          model.apiStyle == apiStyle else {
      throw AgentModelLoopRecoveryError(code: "planner_provider_route_changed")
    }
    guard AgentConnectorAvailability.cloudModelReady(
      model: model,
      apiKey: apiKey(model),
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    ) else {
      throw AgentModelLoopRecoveryError(code: "planner_provider_credentials_unavailable")
    }
    var selected = contact
    selected.selectedCloudModelId = model.modelId
    return AgentModelPlannerContactResolution(
      contact: selected,
      selectedModel: model,
      contactId: contactId,
      modelProfile: String(model.modelId.prefix(80)).ifBlank("model")
    )
  }
}
