import SwiftUI

enum ScannedAgentConversationPolicy {
  static func opensAgentConversation(_ contact: SignalASIContact?) -> Bool {
    guard let contact else { return false }
    return contact.type.caseInsensitiveCompare("agent") == .orderedSame &&
      contact.deliveryMode == .pcConnector &&
      !contact.deleted
  }

  static func contact(
    for requestedID: String,
    contacts: [SignalASIContact]
  ) -> SignalASIContact? {
    let normalizedID = clean(requestedID)
    guard !normalizedID.isEmpty else { return nil }
    if let direct = contacts.first(where: { $0.id == normalizedID }),
       opensAgentConversation(direct) {
      return direct
    }

    let parts = normalizedID.split(separator: ":", omittingEmptySubsequences: true)
    let requestedAgentID = parts.last.map(String.init) ?? normalizedID
    let requestedDesktopID = parts.count > 1
      ? parts.dropLast().map(String.init).joined(separator: ":")
      : ""
    return contacts.first { contact in
      guard opensAgentConversation(contact) else { return false }
      let identities = [
        contact.id,
        contact.signalASIId,
        contact.agentId ?? "",
        contact.connectorAgentId
      ]
        .map(clean)
        .filter { !$0.isEmpty }
      if identities.contains(normalizedID) {
        return true
      }
      let agentIDs = [contact.agentId ?? "", contact.connectorAgentId]
        .map(clean)
        .filter { !$0.isEmpty }
      guard !requestedDesktopID.isEmpty else {
        return agentIDs.contains(requestedAgentID)
      }
      return contact.desktopId == requestedDesktopID && agentIDs.contains(requestedAgentID)
    }
  }

  static func resolveTarget(
    contact: SignalASIContact,
    targets: [AgentCallableTarget]
  ) -> AgentCallableTarget? {
    guard opensAgentConversation(contact) else { return nil }
    guard let target = AgentExecutionTargetStatusPolicy.resolveTarget(
      connectorId: contact.connectorAgentId,
      contactId: contact.id,
      targets: targets
    ), target.kind == .agent else { return nil }
    return target
  }

  static func selection(
    for target: AgentCallableTarget,
    remembered: AgentTargetConfiguration?
  ) -> AgentModelSelection {
    let rememberedEffort = remembered?.reasoningEffort
    let effort = rememberedEffort.flatMap { value in
      target.invocationProfile.reasoningEfforts.contains(value) ? value : nil
    } ?? target.invocationProfile.reasoningEfforts.first ?? .automatic
    return AgentModelSelection(
      mode: .manual,
      targetId: target.id,
      modelId: target.invocationProfile.normalizedModelId(remembered?.modelId ?? ""),
      displayName: target.title,
      reasoningEffort: effort
    )
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

@MainActor
enum ScannedAgentConversationRouter {
  @discardableResult
  static func open(
    targetIDs: [String],
    store: SignalASIStore,
    title: String,
    defaults: UserDefaults = .standard
  ) -> AgentConversation? {
    let contact = targetIDs.compactMap {
      ScannedAgentConversationPolicy.contact(for: $0, contacts: store.contacts)
    }.first
    guard let contact else { return nil }

    let targets = AgentCallableTargetCatalog.build(
      contacts: store.contacts,
      apiKey: { store.apiKey(for: $0) }
    )
    guard let target = ScannedAgentConversationPolicy.resolveTarget(
      contact: contact,
      targets: targets
    ) else { return nil }

    let conversation = store.createAgentSession(title: title)
    let remembered = AgentModelSelectionSettings.configurationForTarget(
      conversationId: conversation.id,
      targetId: target.id,
      defaults: defaults
    )
    let selection = ScannedAgentConversationPolicy.selection(
      for: target,
      remembered: remembered
    )
    AgentModelSelectionSettings.selectManual(
      for: conversation.id,
      targetId: selection.targetId,
      modelId: selection.modelId,
      displayName: selection.displayName,
      reasoningEffort: selection.reasoningEffort,
      rememberAsDefault: false,
      defaults: defaults
    )
    store.setAgentSessionSelectedModelOrAgent(
      id: conversation.id,
      label: selection.displayName
    )
    return store.agentSession(id: conversation.id)
  }
}

struct SignalASIContactMessagingDestination: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var openedAgentConversation = false

  var contactId: String

  var body: some View {
    Group {
      if ScannedAgentConversationPolicy.opensAgentConversation(store.contact(id: contactId)) {
        AgentHomeView()
          .onAppear(perform: openAgentConversationOnce)
      } else {
        ConversationView(contactId: contactId)
      }
    }
  }

  private func openAgentConversationOnce() {
    guard !openedAgentConversation else { return }
    openedAgentConversation = true
    _ = ScannedAgentConversationRouter.open(
      targetIDs: [contactId],
      store: store,
      title: SignalASILocalization.string(
        "signalasi.agent_session.new",
        fallback: "New session",
        language: interfaceLanguage
      )
    )
  }
}
