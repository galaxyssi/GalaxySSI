import Foundation

protocol CloudModelStructuredSending {
  func sendStructured(
    contact: SignalASIContact,
    store: SignalASIStore,
    systemPrompt: String,
    prompt: String
  ) async throws -> String
}

extension CloudModelClient: CloudModelStructuredSending {}

struct CloudModelAgentPlanningProvider: AgentModelPlanningProviding {
  var contact: SignalASIContact
  var store: SignalASIStore
  var sender: CloudModelStructuredSending

  init(
    contact: SignalASIContact,
    store: SignalASIStore,
    sender: CloudModelStructuredSending = CloudModelClient()
  ) {
    self.contact = contact
    self.store = store
    self.sender = sender
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    try await sender.sendStructured(
      contact: contact,
      store: store,
      systemPrompt: invocation.systemPrompt,
      prompt: invocation.prompt
    )
  }
}
