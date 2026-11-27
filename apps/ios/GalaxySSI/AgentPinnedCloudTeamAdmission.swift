import Foundation

enum AgentPinnedCloudTeamDelivery {
  @TaskLocal static var runtime: UUID?
}

@MainActor
enum AgentPinnedCloudTeamAdmission {
  @MainActor struct Invitation {
    let owner: String
    let conversation: String
    let turn: String
    let route: AgentConversationGoal.Route
    let ticket: UUID
    let runtime: UUID
    func current(_ store: GalaxySSIStore) -> Bool {
      AgentPinnedCloudTeamDelivery.runtime == runtime && owner == store.profile.identityFingerprint &&
        AgentPinnedCloudTeamAdmission.current(route, store: store, conversation: conversation) &&
        AgentLocalTeamReviewWindow.ownsCloud(owner: owner, conversation: conversation, turn: turn, ticket: ticket, route: route)
    }
    func accept(_ answer: String, store: GalaxySSIStore) -> Bool {
      guard !Task.isCancelled, current(store) else { return false }
      return AgentLocalTeamReviewWindow.markCloud(owner: owner, conversation: conversation, turn: turn,
        ticket: ticket, answer: answer)
    }
  }
  static func permits(_ budget: AgentTaskBudget) -> Bool {
    budget.profile != .privateMode && budget == AgentTaskBudget(profile: budget.profile)
  }
  static func selectedRoute(store: GalaxySSIStore, conversation: String) -> AgentConversationGoal.Route? {
    let selection = AgentModelSelectionSettings.selection(for: conversation, defaults: store.defaults)
    guard selection.mode == .manual, !selection.targetId.isBlank, !selection.modelId.isBlank,
      permits(store.agentTaskBudget), let contact = store.contact(id: selection.targetId), contact.deliveryMode == .cloudAPI,
      let model = contact.cloudModels.first(where: { $0.modelId == selection.modelId }), model.apiStyle == .openAICompatible,
      let url = URLComponents(string: model.endpoint), !((url.host ?? "").isBlank), url.user == nil, url.password == nil else { return nil }
    return AgentConversationGoalInference.routes(store: store, conversation: conversation).first {
      $0.kind == .cloud && $0.target == selection.targetId && $0.model == selection.modelId
    }
  }
  static func current(_ route: AgentConversationGoal.Route, store: GalaxySSIStore, conversation: String) -> Bool {
    route == selectedRoute(store: store, conversation: conversation) && AgentConversationGoalInference.isCurrent(route, store: store)
  }
  static func invitation(store: GalaxySSIStore, contact: GalaxySSIContact, conversation: String, turn: String,
    objective: String? = nil) -> Invitation? {
    guard let runtime = AgentPinnedCloudTeamDelivery.runtime, store.canReadAgentTranscript,
      AgentConversationGoalRuntime.eligible(store.agentSession(id: conversation)),
      let route = selectedRoute(store: store, conversation: conversation), route.target == contact.id,
      let model = contact.selectedCloudModel, model.modelId == route.model,
      AgentConversationGoalInference.fingerprint(contact: contact, model: model) == route.endpointSHA,
      let ticket = AgentLocalTeamReviewWindow.requestCloud(owner: store.profile.identityFingerprint,
        conversation: conversation, turn: turn, route: route, objective: objective) else { return nil }
    return Invitation(owner: store.profile.identityFingerprint, conversation: conversation, turn: turn, route: route, ticket: ticket, runtime: runtime)
  }
}
