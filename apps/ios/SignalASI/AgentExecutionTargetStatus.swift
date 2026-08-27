import Foundation

enum AgentExecutionTargetStatusPolicy {
  static func resolveLabel(
    connectorId: String = "",
    contactId: String = "",
    runtimeTarget: String = "",
    fallbackTarget: String = "",
    activeLocalModelName: String = "",
    contacts: [SignalASIContact]
  ) -> String {
    let identities = [connectorId, contactId]
      .map(clean)
      .filter { !$0.isEmpty }

    for identity in identities {
      if isLocalModelAlias(identity) {
        let activeName = clean(activeLocalModelName)
        if !activeName.isEmpty { return activeName }
        continue
      }
      if let contact = contacts.first(where: { matches(identity, contact: $0) }),
         !contact.deleted,
         contact.id != "hermes" {
        if contact.deliveryMode == .cloudAPI,
           let model = contact.selectedCloudModel {
          let modelLabel = model.displayName
            .ifBlank(model.modelId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          if !modelLabel.isEmpty {
            return modelLabel
          }
        }
        return contact.displayName.ifBlank(contact.name).ifBlank(identity)
      }
    }

    for candidate in [runtimeTarget, fallbackTarget].map(clean) {
      if isLocalModelAlias(candidate) {
        let activeName = clean(activeLocalModelName)
        if !activeName.isEmpty { return activeName }
        continue
      }
      if !isGeneric(candidate) { return candidate }
    }
    return ""
  }

  private static func matches(_ identity: String, contact: SignalASIContact) -> Bool {
    let candidateIds = [
      contact.id,
      contact.signalASIId,
      contact.agentId ?? "",
      contact.connectorAgentId
    ]
      .map(clean)
      .filter { !$0.isEmpty }

    return candidateIds.contains { candidate in
      identity == candidate ||
        identity.hasSuffix(":\(candidate)") ||
        candidate.hasSuffix(":\(identity)")
    }
  }

  private static func isGeneric(_ value: String) -> Bool {
    genericLabels.contains(value.lowercased())
  }

  private static func isLocalModelAlias(_ value: String) -> Bool {
    localModelAliases.contains(value.lowercased())
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static let genericLabels: Set<String> = [
    "agent or model",
    "cloud models",
    "local llm",
    "local model",
    "local-llm",
    "signalasi",
    "mobile executor",
    "selected resource",
    "agent"
  ]
  private static let localModelAliases: Set<String> = ["local llm", "local model", "local-llm"]
}
