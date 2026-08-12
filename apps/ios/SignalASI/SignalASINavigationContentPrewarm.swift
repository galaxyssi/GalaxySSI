import Foundation

@MainActor
enum SignalASINavigationContentPrewarm {
  private static var cached: Snapshot?

  struct Snapshot {
    var key: String
    var hub: SignalASIConversationHubPreparedContent
    var modelSelection: SignalASIAgentModelSelectionPreparedContent
  }

  static func prepare(store: SignalASIStore) async {
    let key = sourceKey(for: store)
    if cached?.key == key { return }

    let conversations = store.agentSessions(includeArchived: true)
    let contacts = store.contactList(matching: "")
    let cloudContacts = store.cloudModelContacts
    let visibleContacts = store.visibleContacts
    let activeConversationID = store.activeAgentConversationId
    let apiKeys = cloudContacts.reduce(into: [String: String]()) { result, contact in
      for model in contact.cloudModels {
        if let key = store.apiKey(for: model), !key.isEmpty {
          result[model.keychainAccount] = key
        }
      }
    }
    _ = await SignalASISettingsSummaryCache.prepare(store: store)
    let prepared = await Task.detached(priority: .utility) {
      let hub = SignalASIConversationHubPreparedContent(
        conversations: SignalASIConversationHubModels.conversations(
          conversations,
          query: "",
          archived: false
        ),
        archivedCount: conversations.filter { $0.status == .archived }.count,
        contacts: SignalASIConversationHubModels.contacts(contacts, query: "")
      )
      let localProfiles = LocalModelRuntimeSettings.activeProfiles()
      let callableTargets = AgentCallableTargetCatalog.build(
        contacts: visibleContacts,
        apiKey: { apiKeys[$0.keychainAccount] }
      )
      let readyCloudContacts = cloudContacts.filter { contact in
        AgentConnectorAvailability.cloudModelReady(
          contact: contact,
          apiKey: contact.selectedCloudModel.flatMap { apiKeys[$0.keychainAccount] }
        )
      }
      return (
        hub,
        SignalASIAgentModelSelectionPreparedContent(
          localProfiles: localProfiles,
          cloudContacts: readyCloudContacts,
          callableTargets: callableTargets
        )
      )
    }.value

    guard sourceKey(for: store) == key else { return }
    cached = Snapshot(
      key: key,
      hub: prepared.0,
      modelSelection: prepared.1
    )
  }

  static func snapshot(for store: SignalASIStore) -> Snapshot? {
    guard let cached, cached.key == sourceKey(for: store) else { return nil }
    return cached
  }

  private static func sourceKey(for store: SignalASIStore) -> String {
    let conversations = store.agentConversations.map {
      "\($0.id):\($0.updatedAt):\($0.status):\($0.pinned):\($0.mergedIntoConversationId)"
    }.joined(separator: "|")
    let contacts = store.contacts.map {
      "\($0.id):\($0.updatedAt.timeIntervalSince1970):\($0.deleted):\($0.displayName):\($0.selectedCloudModelId)"
    }.joined(separator: "|")
    return "\(store.activeAgentConversationId)|\(conversations)|\(contacts)"
  }
}
