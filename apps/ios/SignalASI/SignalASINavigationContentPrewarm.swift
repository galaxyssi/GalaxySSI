import Foundation

@MainActor
enum SignalASINavigationContentPrewarm {
  private static var cached: Snapshot?

  struct Snapshot {
    var key: String
    var hub: SignalASIConversationHubPreparedContent
    var modelSelection: SignalASIAgentModelSelectionPreparedContent
    var settings: SignalASISettingsSummarySnapshot
  }

  static func prepare(store: SignalASIStore) async {
    let key = sourceKey(for: store)
    if cached?.key == key { return }

    let conversations = store.agentSessions(includeArchived: true)
    let contacts = store.contactList(matching: "")
    let chatContacts = store.chatContacts(matching: "")
    let cloudContacts = store.cloudModelContacts
    let visibleContacts = store.visibleContacts
    let activeConversationID = store.activeAgentConversationId
    let agentItems = conversations.map { conversation in
      let latest = store.agentSessionMessages(conversation.id).last
      let preview = latest.map { ContactConversationSummary(lastMessage: $0, unreadCount: 0).previewText } ?? ""
      return SignalASIConversationHubItem(
        id: conversation.id,
        kind: .agent,
        title: SignalASIConversationHubModels.agentDisplayTitle(
          conversation,
          language: store.languagePolicy.interfaceLanguage
        ),
        subtitle: preview,
        preview: preview,
        updatedAt: latest?.createdAt ?? Date(timeIntervalSince1970: TimeInterval(conversation.updatedAt) / 1_000),
        pinned: conversation.pinned,
        archived: conversation.status == .archived,
        searchableMetadata: conversation.selectedModelOrAgent
      )
    }
    let contactSummaries = chatContacts.compactMap { contact -> SignalASIConversationHubContactSummary? in
      let summary = store.conversationSummary(for: contact.id)
      guard let latest = summary.lastMessage else { return nil }
      return SignalASIConversationHubContactSummary(
        contactId: contact.id,
        title: contact.displayName.ifBlank(contact.name).ifBlank(contact.id),
        preview: summary.previewText,
        updatedAt: latest.createdAt,
        pinned: store.isContactPinned(contact.id),
        unreadCount: summary.unreadCount
      )
    }
    let apiKeys = cloudContacts.reduce(into: [String: String]()) { result, contact in
      for model in contact.cloudModels {
        if let key = store.apiKey(for: model), !key.isEmpty {
          result[model.keychainAccount] = key
        }
      }
    }
    let settings = await SignalASISettingsSummaryCache.prepare(store: store)
    let prepared = await Task.detached(priority: .utility) {
      let hub = SignalASIConversationHubPreparedContent(
        conversations: SignalASIConversationHubModels.unifiedConversations(
          agents: agentItems,
          contacts: contactSummaries,
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
        contact.cloudModels.contains { model in
          AgentConnectorAvailability.cloudModelReady(
            model: model,
            apiKey: apiKeys[model.keychainAccount],
            provider: contact.cloudProvider,
            setupStatus: contact.setupStatus
          )
        }
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
      modelSelection: prepared.1,
      settings: settings
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
      let summary = store.conversationSummary(for: $0.id)
      return "\($0.id):\($0.updatedAt.timeIntervalSince1970):\($0.deleted):\($0.displayName):\($0.selectedCloudModelId):\(summary.lastMessage?.createdAt.timeIntervalSince1970 ?? 0):\(summary.unreadCount):\(store.isContactPinned($0.id))"
    }.joined(separator: "|")
    let localProfiles = LocalModelRuntimeSettings.activeProfiles().map { profile in
      "\(profile.id):\(LocalModelRuntimeSettings.isProfileEnabled(profile))"
    }.joined(separator: "|")
    let cloudModels = store.cloudModelContacts.map { contact in
      let models = contact.cloudModels.map { model in
        let keyAvailable = !(store.apiKey(for: model) ?? "").isEmpty
        return "\(model.provider):\(model.modelId):\(keyAvailable)"
      }.joined(separator: ",")
      return "\(contact.id):\(contact.selectedCloudModelId):\(models)"
    }.joined(separator: "|")
    let callableTargets = AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    ).map { target in
      "\(target.id):\(target.kind.rawValue):\(target.capabilities.map(\.rawValue).sorted().joined(separator: ","))"
    }.joined(separator: "|")
    return "\(store.activeAgentConversationId)|\(conversations)|\(contacts)|\(localProfiles)|\(cloudModels)|\(callableTargets)|\(SignalASISettingsSummaryCache.key(for: store))"
  }
}
