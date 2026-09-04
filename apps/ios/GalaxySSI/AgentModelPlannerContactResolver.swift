import Foundation

struct AgentModelPlannerContactResolution: Equatable {
  var contact: GalaxySSIContact
  var selectedModel: CloudModelConfig
  var contactId: String
  var modelProfile: String
}

struct AgentModelPlannerContactResolver {
  private let store: GalaxySSIStore
  private let voiceCorrectionJournal: VoiceCorrectionJournal

  init(
    store: GalaxySSIStore,
    voiceCorrectionJournal: VoiceCorrectionJournal = .shared
  ) {
    self.store = store
    self.voiceCorrectionJournal = voiceCorrectionJournal
  }

  @MainActor
  func resolve(settings: AgentModelPlannerSettings, modelId: String = "") -> AgentModelPlannerContactResolution? {
    Self.resolve(
      preferredContactId: settings.normalized.cloudContactId,
      contacts: store.contacts,
      apiKey: { store.apiKey(for: $0) },
      preferredModelId: modelId
    )
  }

  @MainActor
  func makePlanningProvider(
    settings: AgentModelPlannerSettings,
    modelId: String = "",
    sender: CloudModelStructuredSending = CloudModelClient()
  ) -> CloudModelAgentPlanningProvider? {
    guard let resolution = resolve(settings: settings, modelId: modelId) else {
      return nil
    }
    return CloudModelAgentPlanningProvider(contact: resolution.contact, store: store, sender: sender)
  }

  @MainActor
  func makeToolLoopPlanningProvider(
    settings: AgentModelPlannerSettings,
    toolRegistry: AgentNativeToolRegistry,
    modelId: String = "",
    structuredSender: CloudModelStructuredSending = CloudModelClient(),
    nativeToolSender: CloudModelNativeToolSending = CloudModelClient()
  ) -> CloudModelToolLoopAgentPlanningProvider? {
    guard let resolution = resolve(settings: settings, modelId: modelId) else {
      return nil
    }
    return CloudModelToolLoopAgentPlanningProvider(
      contact: resolution.contact,
      store: store,
      toolRegistry: toolRegistry,
      structuredSender: structuredSender,
      nativeToolSender: nativeToolSender
    )
  }

  @MainActor
  func makePlanner(
    settings: AgentModelPlannerSettings,
    modelId: String = "",
    sender: CloudModelStructuredSending = CloudModelClient()
  ) -> GuardedModelAgentPlanner? {
    if let localProfile = localProfile(for: settings) {
      return GuardedModelAgentPlanner(
        provider: LocalModelAgentPlanningProvider(profile: localProfile),
        modelProfile: localProfile.id,
        voiceCorrectionJournal: voiceCorrectionJournal
      )
    }
    guard let resolution = resolve(settings: settings, modelId: modelId) else {
      return nil
    }
    let provider = CloudModelAgentPlanningProvider(contact: resolution.contact, store: store, sender: sender)
    return GuardedModelAgentPlanner(
      provider: provider,
      modelProfile: resolution.modelProfile,
      voiceCorrectionJournal: voiceCorrectionJournal
    )
  }

  @MainActor
  func makeToolLoopPlanner(
    settings: AgentModelPlannerSettings,
    toolRegistry: AgentNativeToolRegistry,
    modelId: String = "",
    structuredSender: CloudModelStructuredSending = CloudModelClient(),
    nativeToolSender: CloudModelNativeToolSending = CloudModelClient()
  ) -> GuardedModelAgentPlanner? {
    if let localProfile = localProfile(for: settings) {
      return GuardedModelAgentPlanner(
        provider: LocalModelAgentPlanningProvider(profile: localProfile),
        modelProfile: localProfile.id,
        voiceCorrectionJournal: voiceCorrectionJournal
      )
    }
    guard let resolution = resolve(settings: settings, modelId: modelId) else {
      return nil
    }
    let provider = CloudModelToolLoopAgentPlanningProvider(
      contact: resolution.contact,
      store: store,
      toolRegistry: toolRegistry,
      structuredSender: structuredSender,
      nativeToolSender: nativeToolSender
    )
    return GuardedModelAgentPlanner(
      provider: provider,
      modelProfile: resolution.modelProfile,
      voiceCorrectionJournal: voiceCorrectionJournal
    )
  }

  @MainActor
  private func makeLocalPlanningProvider(
    settings: AgentModelPlannerSettings
  ) -> LocalModelAgentPlanningProvider? {
    guard let profile = localProfile(for: settings) else { return nil }
    return LocalModelAgentPlanningProvider(profile: profile)
  }

  private func localProfile(for settings: AgentModelPlannerSettings) -> LocalModelRuntimeProfile? {
    guard settings.normalized.cloudContactId == "local-llm" else { return nil }
    return LocalModelRuntimeSettings.selectedProfile()
  }

  static func resolve(
    preferredContactId: String = "",
    contacts: [GalaxySSIContact],
    apiKey: (CloudModelConfig) -> String?,
    preferredModelId: String = ""
  ) -> AgentModelPlannerContactResolution? {
    let preferred = normalizedIdentifier(preferredContactId)
    let candidates = contacts.compactMap { contact in
      candidate(for: contact, apiKey: apiKey, preferredModelId: preferredModelId)
    }

    if !preferred.isEmpty,
       let configured = candidates.first(where: { $0.matches(preferred) }) {
      return configured.resolution
    }
    return candidates.first?.resolution
  }

  private static func candidate(
    for contact: GalaxySSIContact,
    apiKey: (CloudModelConfig) -> String?,
    preferredModelId: String
  ) -> Candidate? {
    guard !contact.deleted, contact.deliveryMode == .cloudAPI else {
      return nil
    }
    let cleanPreferredModelId = preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedModel = cleanPreferredModelId.isEmpty
      ? contact.selectedCloudModel
      : contact.cloudModels.first { $0.modelId == cleanPreferredModelId }
    guard let selectedModel else { return nil }
    guard AgentConnectorAvailability.cloudModelReady(
      model: selectedModel,
      apiKey: apiKey(selectedModel),
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    ) else {
      return nil
    }

    let contactId = normalizedIdentifier(contact.id).ifEmpty(normalizedIdentifier(contact.galaxySSIId))
    guard !contactId.isEmpty else {
      return nil
    }

    var selectedContact = contact
    selectedContact.selectedCloudModelId = selectedModel.modelId
    return Candidate(
      resolution: AgentModelPlannerContactResolution(
        contact: selectedContact,
        selectedModel: selectedModel,
        contactId: contactId,
        modelProfile: modelProfile(for: selectedModel)
      ),
      matchIds: [
        contactId,
        normalizedIdentifier(contact.id),
        normalizedIdentifier(contact.galaxySSIId)
      ]
    )
  }

  private static func normalizedIdentifier(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func modelProfile(for model: CloudModelConfig) -> String {
    let value = model.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(value.prefix(80)).ifEmpty("model")
  }

  private struct Candidate {
    var resolution: AgentModelPlannerContactResolution
    var matchIds: [String]

    func matches(_ preferredContactId: String) -> Bool {
      matchIds.contains(preferredContactId)
    }
  }
}

private extension String {
  func ifEmpty(_ fallback: String) -> String {
    isEmpty ? fallback : self
  }
}
