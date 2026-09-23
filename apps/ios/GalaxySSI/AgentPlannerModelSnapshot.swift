import Foundation

struct AgentPlannerModelSnapshot: Codable, Equatable {
  var settings: AgentModelPlannerSettings
  var route: AgentPlannerProviderRoute?
  var localProfileId: String?

  var configurationSha256: String {
    AgentModelLoopRecoveryIdentity.sha256(self)
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
