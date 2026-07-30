import Foundation

struct AgentModelPlannerContactResolution: Equatable {
  var contact: SignalASIContact
  var selectedModel: CloudModelConfig
  var contactId: String
  var modelProfile: String
}

struct AgentModelPlannerContactResolver {
  private let store: SignalASIStore

  init(store: SignalASIStore) {
    self.store = store
  }

  @MainActor
  func resolve(settings: AgentModelPlannerSettings) -> AgentModelPlannerContactResolution? {
    Self.resolve(
      preferredContactId: settings.normalized.cloudContactId,
      contacts: store.contacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  @MainActor
  func makePlanningProvider(
    settings: AgentModelPlannerSettings,
    sender: CloudModelStructuredSending = CloudModelClient()
  ) -> CloudModelAgentPlanningProvider? {
    guard let resolution = resolve(settings: settings) else {
      return nil
    }
    return CloudModelAgentPlanningProvider(contact: resolution.contact, store: store, sender: sender)
  }

  @MainActor
  func makeToolLoopPlanningProvider(
    settings: AgentModelPlannerSettings,
    toolRegistry: AgentNativeToolRegistry,
    structuredSender: CloudModelStructuredSending = CloudModelClient(),
    nativeToolSender: CloudModelNativeToolSending = CloudModelClient()
  ) -> CloudModelToolLoopAgentPlanningProvider? {
    guard let resolution = resolve(settings: settings) else {
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
    sender: CloudModelStructuredSending = CloudModelClient()
  ) -> GuardedModelAgentPlanner? {
    guard let resolution = resolve(settings: settings) else {
      return nil
    }
    let provider = CloudModelAgentPlanningProvider(contact: resolution.contact, store: store, sender: sender)
    return GuardedModelAgentPlanner(provider: provider, modelProfile: resolution.modelProfile)
  }

  @MainActor
  func makeToolLoopPlanner(
    settings: AgentModelPlannerSettings,
    toolRegistry: AgentNativeToolRegistry,
    structuredSender: CloudModelStructuredSending = CloudModelClient(),
    nativeToolSender: CloudModelNativeToolSending = CloudModelClient()
  ) -> GuardedModelAgentPlanner? {
    guard let resolution = resolve(settings: settings) else {
      return nil
    }
    let provider = CloudModelToolLoopAgentPlanningProvider(
      contact: resolution.contact,
      store: store,
      toolRegistry: toolRegistry,
      structuredSender: structuredSender,
      nativeToolSender: nativeToolSender
    )
    return GuardedModelAgentPlanner(provider: provider, modelProfile: resolution.modelProfile)
  }

  static func resolve(
    preferredContactId: String = "",
    contacts: [SignalASIContact],
    apiKey: (CloudModelConfig) -> String?
  ) -> AgentModelPlannerContactResolution? {
    let preferred = normalizedIdentifier(preferredContactId)
    let candidates = contacts.compactMap { contact in
      candidate(for: contact, apiKey: apiKey)
    }

    if !preferred.isEmpty,
       let configured = candidates.first(where: { $0.matches(preferred) }) {
      return configured.resolution
    }
    return candidates.first?.resolution
  }

  private static func candidate(
    for contact: SignalASIContact,
    apiKey: (CloudModelConfig) -> String?
  ) -> Candidate? {
    guard !contact.deleted,
          contact.deliveryMode == .cloudAPI,
          let selectedModel = contact.selectedCloudModel else {
      return nil
    }
    guard AgentConnectorAvailability.cloudModelReady(
      model: selectedModel,
      apiKey: apiKey(selectedModel),
      provider: contact.cloudProvider,
      setupStatus: contact.setupStatus
    ) else {
      return nil
    }

    let contactId = normalizedIdentifier(contact.id).ifEmpty(normalizedIdentifier(contact.signalASIId))
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
        normalizedIdentifier(contact.signalASIId)
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
