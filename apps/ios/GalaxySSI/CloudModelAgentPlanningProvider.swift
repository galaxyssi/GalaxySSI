import Foundation

protocol CloudModelStructuredSending {
  func sendStructured(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    systemPrompt: String,
    prompt: String
  ) async throws -> String
}

extension CloudModelClient: CloudModelStructuredSending {}

struct CloudModelAgentPlanningProvider: AgentModelPlanningProviding {
  var contact: GalaxySSIContact
  var store: GalaxySSIStore
  var sender: CloudModelStructuredSending
  var disclosureStore: AgentDataDisclosureStore

  init(
    contact: GalaxySSIContact,
    store: GalaxySSIStore,
    sender: CloudModelStructuredSending = CloudModelClient(),
    disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
      fileURL: AgentDataDisclosureStorePaths.ledgerURL()
    )
  ) {
    self.contact = contact
    self.store = store
    self.sender = sender
    self.disclosureStore = disclosureStore
  }

  func rawPlan(invocation: AgentModelPlanningInvocation) async throws -> String {
    let ticket = AgentDataDisclosureLedger.beginCloudRequest(
      store: disclosureStore,
      destination: AgentDataDisclosureCloudDestination(contact: contact),
      text: invocation.prompt,
      historyCount: invocation.request.conversationContext.turns.count,
      systemInstructions: true,
      toolOutput: !invocation.request.executionHistory.isEmpty,
      purpose: "Agent planning request",
      conversationId: invocation.request.conversationContext.conversationId,
      taskId: invocation.request.planRequest.contextDigest
    )
    guard ticket.allowed else {
      throw AgentDataDisclosureBlockedError(destination: contact.displayName)
    }

    do {
      let raw = try await sender.sendStructured(
        contact: contact,
        store: store,
        systemPrompt: invocation.systemPrompt,
        prompt: invocation.prompt
      )
      AgentDataDisclosureLedger.update(store: disclosureStore, ticket: ticket, status: .sent)
      return raw
    } catch {
      AgentDataDisclosureLedger.update(
        store: disclosureStore,
        ticket: ticket,
        status: .failed,
        failureReason: error.localizedDescription
      )
      throw error
    }
  }
}
