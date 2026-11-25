import Foundation

struct AgentManualCloudBinding: Codable, Equatable {
  let contactId: String
  let modelId: String
  let routeSha256: String
  let hadAttachments: Bool

  init?(contact: GalaxySSIContact, hadAttachments: Bool) {
    guard contact.deliveryMode == .cloudAPI, let model = contact.selectedCloudModel else { return nil }
    self.contactId = contact.id
    self.modelId = model.modelId
    self.routeSha256 = Self.routeFingerprint(contact: contact, model: model)
    self.hadAttachments = hadAttachments
  }

  func resolve(contact: GalaxySSIContact?, apiKey: (CloudModelConfig) -> String?) -> GalaxySSIContact? {
    guard let contact, contact.id == contactId, !contact.deleted, contact.deliveryMode == .cloudAPI,
          let model = CloudModelRequestRoutingPolicy.model(in: contact, modelId: modelId),
          Self.routeFingerprint(contact: contact, model: model) == routeSha256,
          AgentConnectorAvailability.cloudModelReady(model: model, apiKey: apiKey(model),
            provider: contact.cloudProvider, setupStatus: contact.setupStatus) else { return nil }
    var selected = contact
    selected.cloudModels = CloudModelRequestRoutingPolicy.models(for: contact)
    selected.selectedCloudModelId = modelId
    return selected
  }

  private static func routeFingerprint(contact: GalaxySSIContact, model: CloudModelConfig) -> String {
    AgentModelLoopRecoveryIdentity.sha256([
      "contact": contact.id, "provider": contact.cloudProvider, "model": model.modelId,
      "endpoint": model.endpoint, "api_style": model.apiStyle.rawValue
    ])
  }
}

enum CloudModelRequestRoutingPolicy {
  static let deepSeekV4Pro = "deepseek-v4-pro"
  static let deepSeekFlash = "deepseek-flash"
  static let deepSeekV4Flash = "deepseek-v4-flash"
  static let deepSeekV4FlashVision = "deepseek-v4-flash-vision-exp"
  private static let flashAliases = [
    deepSeekV4Flash: deepSeekFlash, deepSeekV4FlashVision: deepSeekFlash
  ]

  static func isDirectDeepSeek(endpoint: String) -> Bool {
    guard let url = URLComponents(string: endpoint) else { return false }
    return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "api.deepseek.com"
      && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
  }

  static func invocationProfile(_ contact: GalaxySSIContact) -> AgentInvocationProfile {
    let options = models(for: contact).map {
      AgentModelOption(id: $0.modelId, displayName: $0.displayName.ifBlank($0.modelId))
    }
    let aliases = isDirectDeepSeek(endpoint: contact.selectedCloudModel?.endpoint ?? "")
      && contact.selectedCloudModel?.apiStyle == .openAICompatible
      ? flashAliases : [:]
    let selected = aliases[contact.selectedCloudModelId] ?? contact.selectedCloudModelId
    return AgentInvocationProfile(
      defaultModelId: options.contains(where: { $0.id == selected }) ? selected : options.first?.id ?? "",
      models: options, modelAliases: aliases
    )
  }

  static func models(for contact: GalaxySSIContact, requestedModelId: String = "") -> [CloudModelConfig] {
    guard let template = contact.selectedCloudModel else { return contact.cloudModels }
    let direct = isDirectDeepSeek(endpoint: template.endpoint) && template.apiStyle == .openAICompatible
    let presets = direct
      ? CloudModelPreset.androidParity.filter { $0.provider == "DeepSeek" }
      : providerPresets(template: template, provider: contact.cloudProvider)
    guard !presets.isEmpty else { return contact.cloudModels }
    var result = presets.map { preset -> CloudModelConfig in
      if let configured = contact.cloudModels.first(where: {
        $0.modelId == preset.modelId && sameEndpoint($0.endpoint, preset.endpoint)
          && $0.apiStyle == preset.apiStyle
      }) { return configured }
      var source = template
      if direct && preset.modelId == deepSeekFlash {
        // Prefer the selected legacy key, then the historical vision/Flash key.
        let legacyIds = [requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines),
          template.modelId, deepSeekV4FlashVision, deepSeekV4Flash]
        if let legacy = legacyIds.compactMap({ id in
          contact.cloudModels.first {
            $0.modelId == id && flashAliases[id] != nil
              && isDirectDeepSeek(endpoint: $0.endpoint) && $0.apiStyle == preset.apiStyle
          }
        }).first { source = legacy }
      }
      return CloudModelConfig(
        id: "\(contact.id):\(preset.modelId)", displayName: preset.name, provider: preset.provider,
        modelId: preset.modelId, endpoint: preset.endpoint, apiStyle: preset.apiStyle,
        keychainAccount: source.keychainAccount, updatedAt: source.updatedAt)
    }
    for model in contact.cloudModels {
      if direct && flashAliases[model.modelId] != nil { continue }
      if !result.contains(where: { $0.modelId == model.modelId }) { result.append(model) }
    }
    return result
  }

  static func model(in contact: GalaxySSIContact, modelId: String) -> CloudModelConfig? {
    let profile = invocationProfile(contact)
    let requested = profile.canonicalModelId(modelId.ifBlank(contact.selectedCloudModelId))
    return models(for: contact, requestedModelId: modelId).first { $0.modelId == requested }
  }

  static func resolve(
    contact: GalaxySSIContact, requestedModelId: String, hasImageInput: Bool
  ) -> GalaxySSIContact {
    let profile = invocationProfile(contact)
    let selectedId = profile.normalizedModelId(requestedModelId.ifBlank(contact.selectedCloudModelId))
    let available = models(for: contact, requestedModelId: requestedModelId)
    guard let selected = available.first(where: { $0.modelId == selectedId }) else { return contact }
    let effectiveId = effectiveModelId(
      selectedModelId: selectedId, hasImageInput: hasImageInput, endpoint: selected.endpoint)
    guard let effective = available.first(where: { $0.modelId == effectiveId }) else { return contact }
    var resolved = contact
    resolved.cloudModels = available
    resolved.selectedCloudModelId = effective.modelId
    return resolved
  }

  static func effectiveModelId(
    selectedModelId: String, hasImageInput: Bool, endpoint: String
  ) -> String {
    guard isDirectDeepSeek(endpoint: endpoint) else { return selectedModelId }
    let canonical = flashAliases[selectedModelId] ?? selectedModelId
    return hasImageInput && canonical == deepSeekV4Pro ? deepSeekFlash : canonical
  }

  // Keychain accounts are inherited only across an exact official endpoint/protocol.
  // Gemini's model-bearing path is checked against the *current* model before substitution.
  private static func providerPresets(template: CloudModelConfig, provider: String) -> [CloudModelPreset] {
    guard !provider.isEmpty, provider.lowercased() != "custom" else { return [] }
    let presets = CloudModelPreset.androidParity.filter {
      $0.provider.caseInsensitiveCompare(provider) == .orderedSame && $0.apiStyle == template.apiStyle
    }
    let currentEndpoint = template.apiStyle == .gemini
      ? "https://generativelanguage.googleapis.com/v1beta/models/\(template.modelId):generateContent"
      : presets.first?.endpoint ?? ""
    return sameEndpoint(template.endpoint, currentEndpoint) ? presets : []
  }

  private static func sameEndpoint(_ lhs: String, _ rhs: String) -> Bool {
    guard let a = URLComponents(string: lhs), let b = URLComponents(string: rhs),
          a.scheme?.lowercased() == "https", b.scheme?.lowercased() == "https",
          a.user == nil, a.password == nil, a.query == nil, a.fragment == nil,
          b.user == nil, b.password == nil, b.query == nil, b.fragment == nil else { return false }
    return a.host?.lowercased() == b.host?.lowercased()
      && (a.port ?? 443) == (b.port ?? 443) && a.percentEncodedPath == b.percentEncodedPath
  }
}
