import Foundation

enum CloudModelRequestRoutingPolicy {
  static let deepSeekV4Pro = "deepseek-v4-pro"
  static let deepSeekV4Flash = "deepseek-v4-flash"
  static let deepSeekV4FlashVision = "deepseek-v4-flash-vision-exp"

  static func invocationProfile(_ contact: SignalASIContact) -> AgentInvocationProfile {
    let options = models(for: contact).map {
      AgentModelOption(id: $0.modelId, displayName: $0.displayName.ifBlank($0.modelId))
    }
    let selected = contact.selectedCloudModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    return AgentInvocationProfile(
      defaultModelId: options.contains(where: { $0.id == selected })
        ? selected
        : options.first?.id ?? "",
      models: options
    )
  }

  static func models(for contact: SignalASIContact) -> [CloudModelConfig] {
    guard isDeepSeek(contact), let template = contact.selectedCloudModel ?? contact.cloudModels.first else {
      return contact.cloudModels
    }
    let required = [deepSeekV4Pro, deepSeekV4Flash, deepSeekV4FlashVision]
    var models = required.map { modelId in
      contact.cloudModels.first(where: { $0.modelId == modelId })
        ?? derivedModel(modelId, template: template, contactId: contact.id)
    }
    for model in contact.cloudModels where !models.contains(where: { $0.modelId == model.modelId }) {
      models.append(model)
    }
    return models
  }

  static func model(in contact: SignalASIContact, modelId: String) -> CloudModelConfig? {
    let requested = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    if requested.isEmpty {
      return contact.selectedCloudModel
    }
    return models(for: contact).first { $0.modelId == requested }
  }

  static func resolve(
    contact: SignalASIContact,
    requestedModelId: String,
    hasImageInput: Bool
  ) -> SignalASIContact {
    let profile = invocationProfile(contact)
    let requested = requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedModelId = profile.models.contains(where: { $0.id == requested })
      ? requested
      : contact.selectedCloudModelId.ifBlank(profile.defaultModelId)
    let effectiveModelId = effectiveModelId(
      selectedModelId: selectedModelId,
      hasImageInput: hasImageInput
    )
    let availableModels = models(for: contact)
    guard let effective = availableModels.first(where: { $0.modelId == effectiveModelId })
      ?? availableModels.first(where: { $0.modelId == selectedModelId }) else {
      return contact
    }
    var resolved = contact
    resolved.cloudModels = availableModels
    resolved.selectedCloudModelId = effective.modelId
    return resolved
  }

  static func effectiveModelId(selectedModelId: String, hasImageInput: Bool) -> String {
    guard hasImageInput,
          [deepSeekV4Pro, deepSeekV4Flash].contains(selectedModelId) else {
      return selectedModelId
    }
    return deepSeekV4FlashVision
  }

  private static func isDeepSeek(_ contact: SignalASIContact) -> Bool {
    [
      contact.cloudProvider,
      contact.name,
      contact.displayName,
      contact.selectedCloudModel?.endpoint ?? "",
      contact.selectedCloudModelId
    ]
      .joined(separator: " ")
      .lowercased()
      .contains("deepseek")
  }

  private static func derivedModel(
    _ modelId: String,
    template: CloudModelConfig,
    contactId: String
  ) -> CloudModelConfig {
    let preset = CloudModelPreset.androidParity.first { $0.modelId == modelId }
    return CloudModelConfig(
      id: "\(contactId):\(modelId)",
      displayName: preset?.name ?? modelId,
      provider: template.provider.ifBlank("DeepSeek"),
      modelId: modelId,
      endpoint: preset?.endpoint ?? template.endpoint,
      apiStyle: preset?.apiStyle ?? template.apiStyle,
      keychainAccount: template.keychainAccount,
      updatedAt: template.updatedAt
    )
  }
}
