import Combine
import CryptoKit
import Foundation
import Security

protocol SignalASISecretStore {
  func setString(_ value: String, account: String) throws
  func string(account: String) -> String?
  func delete(account: String)
}

final class KeychainSecretStore: SignalASISecretStore {
  static let shared = KeychainSecretStore()
  private let service = "com.signalasi.chat.ios"

  func setString(_ value: String, account: String) throws {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      attributes.forEach { item[$0.key] = $0.value }
      let addStatus = SecItemAdd(item as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw SignalASIError.invalidPayload("Unable to save secret in Keychain.")
      }
    } else if status != errSecSuccess {
      throw SignalASIError.invalidPayload("Unable to update secret in Keychain.")
    }
  }

  func string(account: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func delete(account: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
    SecItemDelete(query as CFDictionary)
  }
}

final class InMemorySecretStore: SignalASISecretStore {
  private var values: [String: String] = [:]

  func setString(_ value: String, account: String) throws {
    values[account] = value
  }

  func string(account: String) -> String? {
    values[account]
  }

  func delete(account: String) {
    values.removeValue(forKey: account)
  }
}

struct ContactConversationSummary: Equatable {
  var lastMessage: ChatMessage?
  var unreadCount: Int

  var hasUnreadMessages: Bool {
    unreadCount > 0
  }

  var previewText: String {
    guard let lastMessage else { return "" }
    let content = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if !content.isEmpty {
      return lastMessage.content
    }
    for block in AgentRichContentCodec.decode(lastMessage.richOutputJson) {
      let attachmentName = block.title
        .ifBlank(block.fallbackText)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !attachmentName.isEmpty {
        return attachmentName
      }
    }
    return AgentRichContentCodec.fallbackText(lastMessage.richOutputJson)
  }
}

@MainActor
final class SignalASIStore: ObservableObject {
  @Published private(set) var profile: SignalASIProfile
  @Published private(set) var contacts: [SignalASIContact]
  @Published private(set) var friendRequests: [SignalASIFriendRequest]
  @Published internal(set) var messagesByContact: [String: [ChatMessage]]
  @Published private(set) var readAtByContact: [String: Date]
  @Published private(set) var pinnedContactIds: Set<String>
  @Published private(set) var serverLinks: [ServerLink]
  @Published var voiceSettings: VoiceSettings {
    didSet { save() }
  }
  @Published var languagePolicy: LanguagePolicySettings {
    didSet { save() }
  }
  @Published var displaySettings: AppDisplaySettings {
    didSet { save() }
  }
  @Published var agentSafetySettings: AgentSafetySettings {
    didSet { save() }
  }
  @Published var agentPreferenceMode: AgentPreferenceMode {
    didSet {
      agentPreferenceModeStore.save(agentPreferenceMode)
      save()
    }
  }
  @Published var agentTaskBudget: AgentTaskBudget {
    didSet { save() }
  }
  @Published internal(set) var agentTaskRecords: [AgentTaskRecord] {
    didSet { save() }
  }
  @Published internal(set) var proactiveTasks: [AgentProactiveTask] {
    didSet { save() }
  }
  @Published internal(set) var proactiveRuns: [AgentProactiveRun] {
    didSet { save() }
  }
  @Published internal(set) var globalProactiveMessages: [GlobalProactiveMessage] {
    didSet { save() }
  }
  @Published internal(set) var globalAgentFeedback: [GlobalAgentFeedback] {
    didSet { save() }
  }
  @Published internal(set) var agentConversations: [AgentConversation] {
    didSet { save() }
  }
  @Published internal(set) var activeAgentConversationId: String {
    didSet { save() }
  }
  @Published internal(set) var agentMemoryItems: [AgentMemoryItem]
  @Published internal(set) var agentKnowledgeItems: [AgentKnowledgeItem] {
    didSet { save() }
  }
  @Published internal(set) var agentKnowledgeAccessAudit: [AgentKnowledgeAccessAuditEntry] {
    didSet { save() }
  }
  @Published private(set) var customDeviceConnectors: [CustomDeviceConnector] {
    didSet { save() }
  }
  @Published private(set) var homeAssistantSettings: HomeAssistantSettings {
    didSet { save() }
  }
  @Published var modelPlannerSettings: AgentModelPlannerSettings {
    didSet { save() }
  }
  @Published var globalAgentSettings: GlobalAgentSettings {
    didSet { save() }
  }

  private struct PersistedState: Codable {
    var profile: SignalASIProfile
    var contacts: [SignalASIContact]
    var friendRequests: [SignalASIFriendRequest]
    var messagesByContact: [String: [ChatMessage]]
    var readAtByContact: [String: Date]
    var pinnedContactIds: Set<String>
    var serverLinks: [ServerLink]
    var voiceSettings: VoiceSettings
    var languagePolicy: LanguagePolicySettings
    var displaySettings: AppDisplaySettings
    var agentSafetySettings: AgentSafetySettings
    var agentPreferenceMode: AgentPreferenceMode
    var agentTaskBudget: AgentTaskBudget
    var proactiveTasks: [AgentProactiveTask]
    var proactiveRuns: [AgentProactiveRun]
    var globalProactiveMessages: [GlobalProactiveMessage]
    var globalAgentFeedback: [GlobalAgentFeedback]
    var agentConversations: [AgentConversation]
    var activeAgentConversationId: String
    var agentKnowledgeItems: [AgentKnowledgeItem]
    var agentKnowledgeAccessAudit: [AgentKnowledgeAccessAuditEntry]
    var agentTaskRecords: [AgentTaskRecord]
    var customDeviceConnectors: [CustomDeviceConnector]
    var homeAssistantSettings: HomeAssistantSettings
    var modelPlannerSettings: AgentModelPlannerSettings
    var globalAgentSettings: GlobalAgentSettings

    init(
      profile: SignalASIProfile,
      contacts: [SignalASIContact],
      friendRequests: [SignalASIFriendRequest],
      messagesByContact: [String: [ChatMessage]],
      readAtByContact: [String: Date] = [:],
      pinnedContactIds: Set<String> = [],
      serverLinks: [ServerLink],
      voiceSettings: VoiceSettings,
      languagePolicy: LanguagePolicySettings = .default,
      displaySettings: AppDisplaySettings = .default,
      agentSafetySettings: AgentSafetySettings = .default,
      agentPreferenceMode: AgentPreferenceMode = .cautious,
      agentTaskBudget: AgentTaskBudget = .default,
      proactiveTasks: [AgentProactiveTask] = [],
      proactiveRuns: [AgentProactiveRun] = [],
      globalProactiveMessages: [GlobalProactiveMessage] = [],
      globalAgentFeedback: [GlobalAgentFeedback] = [],
      agentConversations: [AgentConversation] = [],
      activeAgentConversationId: String = "",
      agentKnowledgeItems: [AgentKnowledgeItem] = [],
      agentKnowledgeAccessAudit: [AgentKnowledgeAccessAuditEntry] = [],
      agentTaskRecords: [AgentTaskRecord] = [],
      customDeviceConnectors: [CustomDeviceConnector] = [],
      homeAssistantSettings: HomeAssistantSettings = .default,
      modelPlannerSettings: AgentModelPlannerSettings = .default,
      globalAgentSettings: GlobalAgentSettings = .default
    ) {
      self.profile = profile
      self.contacts = contacts
      self.friendRequests = friendRequests
      self.messagesByContact = messagesByContact
      self.readAtByContact = readAtByContact
      self.pinnedContactIds = pinnedContactIds
      self.serverLinks = serverLinks
      self.voiceSettings = voiceSettings
      self.languagePolicy = languagePolicy
      self.displaySettings = displaySettings
      self.agentSafetySettings = agentSafetySettings
      self.agentPreferenceMode = agentPreferenceMode
      self.agentTaskBudget = agentTaskBudget
      self.proactiveTasks = Array(proactiveTasks.suffix(200))
      self.proactiveRuns = Array(proactiveRuns.suffix(500))
      self.globalProactiveMessages = Array(globalProactiveMessages.suffix(500))
      self.globalAgentFeedback = Array(globalAgentFeedback.suffix(500))
      self.agentConversations = Array(agentConversations.suffix(200))
      self.activeAgentConversationId = activeAgentConversationId
      self.agentKnowledgeItems = Array(agentKnowledgeItems.suffix(500))
      self.agentKnowledgeAccessAudit = Array(agentKnowledgeAccessAudit.suffix(100))
      self.agentTaskRecords = Array(agentTaskRecords.suffix(200))
      self.customDeviceConnectors = customDeviceConnectors
      self.homeAssistantSettings = homeAssistantSettings
      self.modelPlannerSettings = modelPlannerSettings
      self.globalAgentSettings = globalAgentSettings.normalized
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      profile = try container.decode(SignalASIProfile.self, forKey: .profile)
      contacts = try container.decode([SignalASIContact].self, forKey: .contacts)
      friendRequests = try container.decodeIfPresent([SignalASIFriendRequest].self, forKey: .friendRequests) ?? []
      messagesByContact = try container.decode([String: [ChatMessage]].self, forKey: .messagesByContact)
      readAtByContact = try container.decodeIfPresent([String: Date].self, forKey: .readAtByContact) ?? [:]
      pinnedContactIds = try container.decodeIfPresent(Set<String>.self, forKey: .pinnedContactIds) ?? []
      serverLinks = try container.decode([ServerLink].self, forKey: .serverLinks)
      voiceSettings = try container.decode(VoiceSettings.self, forKey: .voiceSettings)
      languagePolicy = try container.decodeIfPresent(LanguagePolicySettings.self, forKey: .languagePolicy) ?? .default
      displaySettings = try container.decodeIfPresent(AppDisplaySettings.self, forKey: .displaySettings) ?? .default
      agentSafetySettings = try container.decodeIfPresent(AgentSafetySettings.self, forKey: .agentSafetySettings) ?? .default
      agentPreferenceMode = try container.decodeIfPresent(AgentPreferenceMode.self, forKey: .agentPreferenceMode) ?? .cautious
      agentTaskBudget = try container.decodeIfPresent(AgentTaskBudget.self, forKey: .agentTaskBudget) ?? .default
      proactiveTasks = Array(
        (try container.decodeIfPresent([AgentProactiveTask].self, forKey: .proactiveTasks) ?? [])
          .suffix(200)
      )
      proactiveRuns = Array(
        (try container.decodeIfPresent([AgentProactiveRun].self, forKey: .proactiveRuns) ?? [])
          .suffix(500)
      )
      globalProactiveMessages = Array(
        (try container.decodeIfPresent([GlobalProactiveMessage].self, forKey: .globalProactiveMessages) ?? [])
          .suffix(500)
      )
      globalAgentFeedback = Array(
        (try container.decodeIfPresent([GlobalAgentFeedback].self, forKey: .globalAgentFeedback) ?? [])
          .suffix(500)
      )
      agentConversations = Array(
        (try container.decodeIfPresent([AgentConversation].self, forKey: .agentConversations) ?? [])
          .suffix(200)
      )
      activeAgentConversationId = try container.decodeIfPresent(String.self, forKey: .activeAgentConversationId) ?? ""
      agentKnowledgeItems = Array(
        (try container.decodeIfPresent([AgentKnowledgeItem].self, forKey: .agentKnowledgeItems) ?? [])
          .suffix(500)
      )
      agentKnowledgeAccessAudit = Array(
        (try container.decodeIfPresent([AgentKnowledgeAccessAuditEntry].self, forKey: .agentKnowledgeAccessAudit) ?? [])
          .suffix(100)
      )
      agentTaskRecords = Array(
        (try container.decodeIfPresent([AgentTaskRecord].self, forKey: .agentTaskRecords) ?? [])
          .suffix(200)
      )
      customDeviceConnectors = try container.decodeIfPresent([CustomDeviceConnector].self, forKey: .customDeviceConnectors) ?? []
      homeAssistantSettings = try container.decodeIfPresent(HomeAssistantSettings.self, forKey: .homeAssistantSettings) ?? .default
      modelPlannerSettings = try container.decodeIfPresent(AgentModelPlannerSettings.self, forKey: .modelPlannerSettings) ?? .default
      globalAgentSettings = try container.decodeIfPresent(GlobalAgentSettings.self, forKey: .globalAgentSettings) ?? .default
    }
  }

  private let defaults: UserDefaults
  private let secrets: SignalASISecretStore
  let memoryDeletionIndex: UserDefaultsAgentMemoryDeletionIndex
  let agentMemoryStore: UserDefaultsAgentMemoryStore
  let agentWorkspaceStore: AgentWorkspaceStore
  private let agentPreferenceModeStore: AgentPreferenceModeStore
  let workflowExecutionHistoryStore: AgentWorkflowExecutionHistoryStore
  private let identityPrivateKeyAccount = "identity.p256.private"
  private let phonePairingSessionsKey = "signalasi.opaque_phone_pairing_v2.sessions"
  private let phoneAcceptedControlsKey = "signalasi.opaque_phone_pairing_v2.accepted_controls"
  private let phoneContactCardsKey = "signalasi.phone_contact_cards"
  private let homeAssistantAccessTokenAccount = "home_assistant.access_token"

  init(defaults: UserDefaults = .standard, secrets: SignalASISecretStore = KeychainSecretStore.shared) {
    defaults.removeObject(forKey: "signalasi.phone_contact_cards")
    defaults.removeObject(forKey: "signalasi.phone_contact_inbox_route")
    self.defaults = defaults
    self.secrets = secrets
    let deletionIndex = UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    let memoryStore = UserDefaultsAgentMemoryStore(defaults: defaults, deletionIndex: deletionIndex)
    let preferenceModeStore = AgentPreferenceModeStore(defaults: defaults)
    self.memoryDeletionIndex = deletionIndex
    self.agentMemoryStore = memoryStore
    self.agentWorkspaceStore = FileAgentWorkspaceStore()
    self.agentPreferenceModeStore = preferenceModeStore
    self.workflowExecutionHistoryStore = AgentWorkflowExecutionHistoryStore(defaults: defaults)
    let encryptedState = SignalASIEncryptedStateStore.load(defaults: defaults, secrets: secrets)
    let legacyState = defaults.data(forKey: SignalASIEncryptedStateStore.legacyStateKey)
    let stateData = encryptedState ?? legacyState
    let shouldMigrateLegacyState = encryptedState == nil && legacyState != nil
    if let data = stateData,
       let state = try? JSONDecoder.signalASI.decode(PersistedState.self, from: data) {
      let historyMigration = AgentPeerChatTransport.migrateStoredHistory(state.messagesByContact)
      profile = state.profile
      let shouldMigrateProfileName = SignalASIDeviceIdentityName.isLegacyDefault(profile.name)
      if shouldMigrateProfileName {
        profile.name = SignalASIDeviceIdentityName.current(profile: profile)
      }
      contacts = state.contacts
      for index in contacts.indices where
        contacts[index].type.caseInsensitiveCompare("person") == .orderedSame &&
        contacts[index].opaquePhoneRoutes == nil {
        contacts[index].mqttTopic = nil
        contacts[index].mqttInboxTopic = nil
      }
      friendRequests = state.friendRequests.filter { request in
        request.type.caseInsensitiveCompare("person") != .orderedSame ||
          request.opaquePhoneRoutes != nil
      }
      messagesByContact = historyMigration.messages
      readAtByContact = state.readAtByContact
      pinnedContactIds = state.pinnedContactIds
      serverLinks = state.serverLinks.filter { $0.routes.isOpaqueV2Valid }
      voiceSettings = state.voiceSettings
      languagePolicy = state.languagePolicy
      displaySettings = state.displaySettings
      agentSafetySettings = state.agentSafetySettings
      agentPreferenceMode = state.agentPreferenceMode
      agentTaskBudget = state.agentTaskBudget
      proactiveTasks = state.proactiveTasks
      proactiveRuns = state.proactiveRuns
      globalProactiveMessages = state.globalProactiveMessages
      globalAgentFeedback = state.globalAgentFeedback
      agentTaskRecords = state.agentTaskRecords
      agentConversations = state.agentConversations
      activeAgentConversationId = state.activeAgentConversationId
      agentMemoryItems = memoryStore.exportItems()
      agentKnowledgeItems = state.agentKnowledgeItems
      agentKnowledgeAccessAudit = state.agentKnowledgeAccessAudit
      customDeviceConnectors = state.customDeviceConnectors.map { connector in
        CustomDeviceConnector(
          id: connector.id,
          name: connector.name,
          transport: connector.transport,
          endpoint: connector.endpoint,
          commandTarget: connector.commandTarget,
          username: connector.username,
          authToken: secrets.string(account: "custom_device_connector.\(connector.id).auth_token") ?? "",
          risk: connector.risk,
          enabled: connector.enabled
        )
      }
      let storedHomeAssistantAccessToken = secrets.string(account: "home_assistant.access_token") ?? ""
      homeAssistantSettings = HomeAssistantSettings(
        enabled: state.homeAssistantSettings.enabled,
        baseUrl: state.homeAssistantSettings.baseUrl,
        accessToken: storedHomeAssistantAccessToken,
        defaultEntityId: state.homeAssistantSettings.defaultEntityId
      )
      modelPlannerSettings = state.modelPlannerSettings
      globalAgentSettings = state.globalAgentSettings.normalized
      if shouldMigrateLegacyState || historyMigration.changed || shouldMigrateProfileName {
        save()
      }
    } else {
      let generatedProfile = SignalASIStore.makeProfile(secrets: secrets, account: identityPrivateKeyAccount)
      profile = generatedProfile
      contacts = [SignalASIContact.hermes(), SignalASIContact.system()]
      friendRequests = []
      messagesByContact = SignalASIStore.defaultMessages()
      readAtByContact = [:]
      pinnedContactIds = []
      serverLinks = []
      voiceSettings = .default
      languagePolicy = .default
      displaySettings = .default
      agentSafetySettings = .default
      agentPreferenceMode = preferenceModeStore.load()
      agentTaskBudget = .default
      proactiveTasks = []
      proactiveRuns = []
      globalProactiveMessages = []
      globalAgentFeedback = []
      agentTaskRecords = []
      agentConversations = []
      activeAgentConversationId = ""
      agentMemoryItems = memoryStore.exportItems()
      agentKnowledgeItems = []
      agentKnowledgeAccessAudit = []
      customDeviceConnectors = []
      homeAssistantSettings = .default
      modelPlannerSettings = .default
      globalAgentSettings = .default
      save()
    }
    agentPreferenceModeStore.save(agentPreferenceMode)
  }

  var visibleContacts: [SignalASIContact] {
    contacts
      .filter { !$0.deleted && $0.id != "system" }
      .sorted { left, right in
        lastMessageDate(for: left.id) > lastMessageDate(for: right.id)
      }
  }

  var chatContacts: [SignalASIContact] {
    let contactsForChat = contacts
      .filter { !$0.deleted && $0.id != "system" }
      .sorted { left, right in
        let leftPriority = chatContactPriority(left.id)
        let rightPriority = chatContactPriority(right.id)
        if leftPriority != rightPriority {
          return leftPriority < rightPriority
        }
        return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
      }
    guard let systemContact = contacts.first(where: { !$0.deleted && $0.id == "system" }) else {
      return contactsForChat
    }
    return contactsForChat + [systemContact]
  }

  func visibleContacts(matching query: String) -> [SignalASIContact] {
    visibleContacts.filter { contactMatchesSearch($0, query: query) }
  }

  func chatContacts(matching query: String) -> [SignalASIContact] {
    chatContacts.filter { contactMatchesSearch($0, query: query) }
  }

  func contactList(matching query: String) -> [SignalASIContact] {
    contacts
      .filter { !$0.deleted && $0.id != "system" }
      .filter { contactMatchesSearch($0, query: query) }
  }

  private func chatContactPriority(_ id: String) -> Int {
    switch id {
    case "hermes": return 0
    case "codex": return 1
    case "claude": return 2
    case "openclaw": return 3
    case "local-llm": return 4
    case "custom-agent": return 6
    default:
      return id.hasPrefix("cloud:") ? 5 : 20
    }
  }

  var cloudModelContacts: [SignalASIContact] {
    contacts
      .filter { !$0.deleted && $0.deliveryMode == .cloudAPI }
      .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
  }

  var pendingFriendRequests: [SignalASIFriendRequest] {
    friendRequests
      .filter { $0.status == .pending }
      .sorted { $0.createdAt > $1.createdAt }
  }

  func hasPendingFriendRequest(for signalASIId: String) -> Bool {
    friendRequests.contains {
      $0.signalASIId == signalASIId && $0.status == .pending
    }
  }

  func approvedIncomingPhoneContactIds() -> [String] {
    var seen = Set<String>()
    return friendRequests.compactMap { request in
      guard request.status == .approved,
            request.direction == .incoming,
            request.opaquePhoneRoutes != nil,
            !request.signalASIId.isEmpty,
            seen.insert(request.signalASIId).inserted else {
        return nil
      }
      return request.signalASIId
    }
  }

  var visibleFriendRequests: [SignalASIFriendRequest] {
    friendRequests
      .filter { request in
        let verified = contact(id: request.signalASIId)?.isCommunicable == true
        return SignalASIFriendRequestPresentationPolicy.isVisible(
          request,
          contactIsVerified: verified
        )
      }
      .sorted { $0.createdAt > $1.createdAt }
  }

  var unreadFriendRequestCount: Int {
    SignalASIFriendRequestUnreadPolicy.unreadCount(friendRequests)
  }

  @discardableResult
  func markIncomingFriendRequestsRead() -> Int {
    var changed = 0
    for index in friendRequests.indices where
      friendRequests[index].status == .pending &&
      friendRequests[index].direction == .incoming &&
      !friendRequests[index].isRead {
      friendRequests[index].isRead = true
      changed += 1
    }
    if changed > 0 { save() }
    return changed
  }

  func isContactPinned(_ contactId: String) -> Bool {
    !contactId.isEmpty && pinnedContactIds.contains(contactId)
  }

  @discardableResult
  func setContactPinned(_ contactId: String, pinned: Bool) -> Bool {
    guard !contactId.isEmpty, contact(id: contactId) != nil else { return false }
    let changed: Bool
    if pinned {
      changed = pinnedContactIds.insert(contactId).inserted
    } else {
      changed = pinnedContactIds.remove(contactId) != nil
    }
    if changed { save() }
    return changed
  }

  func contact(id: String) -> SignalASIContact? {
    contacts.first { $0.id == id || $0.signalASIId == id }
  }

  func messages(for contactId: String) -> [ChatMessage] {
    messagesByContact[contactId] ?? []
  }

  func conversationSummary(for contactId: String) -> ContactConversationSummary {
    let messages = messages(for: contactId)
    let readAt = readAtByContact[contactId] ?? .distantPast
    let unreadCount = messages.filter { message in
      !message.isMine && !message.isSystem && message.createdAt > readAt
    }.count
    return ContactConversationSummary(lastMessage: messages.last, unreadCount: unreadCount)
  }

  @discardableResult
  func markContactRead(_ contactId: String, at readAt: Date = Date()) -> Int {
    let unreadBefore = conversationSummary(for: contactId).unreadCount
    let previousReadAt = readAtByContact[contactId] ?? .distantPast
    guard var messages = messagesByContact[contactId] else {
      return unreadBefore
    }
    var changedMessages = false
    for index in messages.indices where !messages[index].isMine && !messages[index].isSystem {
      if messages[index].deliveryStatus != .read {
        messages[index].deliveryStatus = .read
        changedMessages = true
      }
      if !messages[index].deliveryTrace.contains(where: { $0.stage == "read" }) {
        messages[index].deliveryTrace.append(DeliveryTraceEvent(stage: "read", detail: "chat_opened", createdAt: readAt))
        changedMessages = true
      }
    }
    guard unreadBefore > 0 || changedMessages else {
      return unreadBefore
    }
    if changedMessages {
      messagesByContact[contactId] = messages
    }
    readAtByContact[contactId] = max(previousReadAt, readAt)
    save()
    return unreadBefore
  }

  func friendRequest(id: String) -> SignalASIFriendRequest? {
    friendRequests.first { $0.id == id }
  }

  func updateProfileName(_ name: String) {
    profile.name = name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(SignalASIDeviceIdentityName.current(profile: profile))
    save()
  }

  @discardableResult
  func updateProfileAvatar(data: Data?) -> Bool {
    guard let data, !data.isEmpty else {
      profile.avatarData = nil
      save()
      return true
    }
    guard data.count <= 2 * 1024 * 1024 else { return false }
    profile.avatarData = data
    save()
    return true
  }

  @discardableResult
  func renameContact(id: String, displayName: String) -> Bool {
    let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty,
          let index = contacts.firstIndex(where: { $0.id == id || $0.signalASIId == id }) else {
      return false
    }
    if contacts[index].type == "device",
       !contacts[index].desktopId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      rememberDeviceDefaultDisplayName(
        contacts[index].desktopId,
        fallback: contacts[index].desktopName.ifBlank(contacts[index].displayName)
      )
    }
    contacts[index].name = cleaned
    contacts[index].displayName = cleaned
    contacts[index].updatedAt = Date()
    save()
    return true
  }

  @discardableResult
  func deleteContact(id: String, deleteMessages: Bool = false, now: Date = Date()) -> Bool {
    guard id != "system" else { return false }
    let deviceDesktopId = contacts.first { contact in
      (contact.id == id || contact.signalASIId == id) && contact.type == "device"
    }?.desktopId.trimmingCharacters(in: .whitespacesAndNewlines)
    if let deviceDesktopId, !deviceDesktopId.isEmpty {
      let removedContactIds = removeDesktopPairing(
        desktopId: deviceDesktopId,
        deleteMessages: deleteMessages,
        now: now
      )
      return !removedContactIds.isEmpty
    }
    var deletedIds = Set([id])
    var changed = false

    for index in contacts.indices {
      let contact = contacts[index]
      guard contact.id == id || contact.signalASIId == id else { continue }
      deletedIds.insert(contact.id)
      deletedIds.insert(contact.signalASIId)
      for model in contact.cloudModels {
        secrets.delete(account: model.keychainAccount)
      }
      contacts[index].deleted = true
      contacts[index].deletedAt = now
      contacts[index].trustState = .deleted
      contacts[index].updatedAt = now
      contacts[index].setupStatus = "deleted"
      contacts[index].setupDetail = contact.id == "hermes"
        ? "Scan and pair again before communicating."
        : "Add and verify this contact again before communicating."
      if contact.id == "hermes" {
        contacts[index].desktopId = ""
        contacts[index].desktopName = ""
        contacts[index].identityFingerprint = ""
      }
      changed = true
    }

    pinnedContactIds.subtract(deletedIds)

    if deletedIds.contains("hermes") {
      serverLinks.removeAll()
    }

    for index in friendRequests.indices {
      let request = friendRequests[index]
      guard deletedIds.contains(request.id) || deletedIds.contains(request.signalASIId) else { continue }
      friendRequests[index].status = .deleted
      friendRequests[index].deletedAt = now
      friendRequests[index].readdRequired = true
      changed = true
    }

    if deleteMessages {
      for contactId in deletedIds {
        messagesByContact.removeValue(forKey: contactId)
        readAtByContact.removeValue(forKey: contactId)
      }
    }

    if changed {
      save()
    }
    return changed
  }

  func deleteMessages(for contactId: String) {
    messagesByContact.removeValue(forKey: contactId)
    readAtByContact.removeValue(forKey: contactId)
    save()
  }

  @discardableResult
  func deleteMessage(_ messageId: UUID, contactId: String? = nil) -> Bool {
    let contactIds = contactId.map { [$0] } ?? Array(messagesByContact.keys)
    for id in contactIds {
      guard var messages = messagesByContact[id],
            let index = messages.firstIndex(where: { $0.id == messageId }) else {
        continue
      }
      messages.remove(at: index)
      if messages.isEmpty {
        messagesByContact.removeValue(forKey: id)
      } else {
        messagesByContact[id] = messages
      }
      save()
      return true
    }
    return false
  }

  func destroyAllPrivateData() {
    let accounts = Set(contacts.flatMap { contact in
      contact.cloudModels.map(\.keychainAccount)
    })
    for account in accounts {
      secrets.delete(account: account)
    }
    for connector in customDeviceConnectors {
      secrets.delete(account: customDeviceAuthTokenAccount(id: connector.id))
    }
    secrets.delete(account: identityPrivateKeyAccount)
    secrets.delete(account: homeAssistantAccessTokenAccount)
    SignalASIEncryptedStateStore.destroy(defaults: defaults, secrets: secrets)
    UserDefaultsAgentTeamExecutionStore.destroy(defaults: defaults, secrets: secrets)
    VoiceExecutionLedger.shared.clear()
    UserDefaultsVoiceExecutionRecordStore.destroyPersistentStore(defaults: defaults)
    VoiceCorrectionJournal.destroyPersistentStore(defaults: defaults)
    defaults.removeObject(forKey: UserDefaultsAgentLearningProposalStore.defaultKey)
    defaults.removeObject(forKey: UserDefaultsAgentSkillStore.defaultKey)
    destroyGlobalAgentBackupData()
    UserDefaultsAgentTranscriptEntryStore.destroyPersistentStore(defaults: defaults, secrets: secrets)
    UserDefaultsAgentSelfModelStore(defaults: defaults, secrets: secrets).clear()
    AgentTeamExecutionHistoryStore.destroyPersistentStore(defaults: defaults, secrets: secrets)
    agentMemoryStore.clear()
    memoryDeletionIndex.clear()
    agentWorkspaceStore.clear()
    FileAgentDataDisclosureStore.destroyPersistentStore()
    resetToFreshState()
    save()
  }










  func upsertCustomDeviceConnector(_ connector: CustomDeviceConnector) {
    let clean = connector.normalized
    let next = Array((customDeviceConnectors.filter { $0.id != clean.id } + [clean]).suffix(CustomDeviceConnector.maximumConnectors))
    try? applyCustomDeviceConnectors(next)
  }

  @discardableResult
  func deleteCustomDeviceConnector(id: String) -> Bool {
    let next = customDeviceConnectors.filter { $0.id != id }
    guard next.count != customDeviceConnectors.count else { return false }
    try? applyCustomDeviceConnectors(next)
    return true
  }
  func updateHomeAssistantSettings(_ mutate: (inout HomeAssistantSettings) -> Void) {
    var next = homeAssistantSettings
    mutate(&next)
    try? applyHomeAssistantSettings(next)
  }

  @discardableResult
  func appendOutgoing(
    _ content: String,
    to contactId: String,
    status: ChatDeliveryStatus = .queued,
    turnId: String = "",
    richOutputJson: String = ""
  ) -> ChatMessage {
    let messageId = UUID()
    let conversationId = activeConversationId(for: contactId)
    let createdAt = Date()
    let message = ChatMessage(
      id: messageId,
      contactId: contactId,
      content: content,
      isMine: true,
      createdAt: createdAt,
      deliveryStatus: status,
      deliveryTrace: [DeliveryTraceEvent(stage: status.rawValue)],
      conversationId: conversationId,
      turnId: turnId.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(messageId.uuidString),
      richOutputJson: richOutputJson
    )
    messagesByContact[contactId, default: []].append(message)
    recordAgentConversationActivity(
      conversationId: conversationId,
      contactId: contactId,
      content: AgentSessionTitlePolicy.titleSource(content),
      at: createdAt
    )
    save()
    return message
  }

  func hasIncomingDuplicate(
    _ content: String,
    from contactId: String,
    remoteMessageId: String = "",
    turnId: String = ""
  ) -> Bool {
    let existing = messagesByContact[contactId] ?? []
    let normalizedRemoteMessageId = remoteMessageId.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedRemoteMessageId.isEmpty,
       existing.contains(where: { !$0.isMine && $0.remoteMessageId == normalizedRemoteMessageId }) {
      return true
    }
    let normalizedTurnId = turnId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTurnId.isEmpty else { return false }
    return existing.contains {
      !$0.isMine && $0.turnId == normalizedTurnId && $0.content == content
    }
  }

  @discardableResult
  func appendIncoming(
    _ content: String,
    from contactId: String,
    remoteMessageId: String = "",
    status: ChatDeliveryStatus = .delivered,
    traceStage: String = "received",
    detail: String = "",
    conversationId: String = "",
    turnId: String = "",
    richOutputJson: String = ""
  ) -> ChatMessage {
    let resolvedConversationId = conversationId.ifBlank(activeConversationId(for: contactId))
    let createdAt = Date()
    let message = ChatMessage(
      contactId: contactId,
      content: content,
      isMine: false,
      createdAt: createdAt,
      deliveryStatus: status,
      deliveryTrace: [DeliveryTraceEvent(stage: traceStage, detail: detail)],
      conversationId: resolvedConversationId,
      turnId: turnId,
      remoteMessageId: remoteMessageId,
      richOutputJson: richOutputJson
    )
    messagesByContact[contactId, default: []].append(message)
    recordAgentConversationActivity(conversationId: resolvedConversationId, contactId: contactId, content: content, at: createdAt)
    save()
    return message
  }

  @discardableResult
  func appendSystem(_ content: String, to contactId: String, conversationId: String = "") -> ChatMessage {
    let resolvedConversationId = conversationId.ifBlank(activeConversationId(for: contactId))
    let createdAt = Date()
    let message = ChatMessage(
      contactId: contactId,
      content: content,
      isMine: false,
      isSystem: true,
      createdAt: createdAt,
      deliveryStatus: .local,
      conversationId: resolvedConversationId
    )
    messagesByContact[contactId, default: []].append(message)
    recordAgentConversationActivity(conversationId: resolvedConversationId, contactId: contactId, content: content, at: createdAt)
    save()
    return message
  }

  @discardableResult
  func appendSystemNotification(_ content: String, eventId: String) -> ChatMessage? {
    let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanEventId = eventId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanContent.isEmpty,
          !hasIncomingDuplicate(cleanContent, from: "system", remoteMessageId: cleanEventId) else {
      return nil
    }
    return appendIncoming(
      cleanContent,
      from: "system",
      remoteMessageId: cleanEventId,
      traceStage: "system_notice"
    )
  }

  func markMessage(_ messageId: UUID, contactId: String, status: ChatDeliveryStatus, detail: String = "") {
    guard var messages = messagesByContact[contactId],
          let index = messages.firstIndex(where: { $0.id == messageId }) else {
      return
    }
    messages[index].deliveryStatus = status
    messages[index].deliveryTrace.append(DeliveryTraceEvent(stage: status.rawValue, detail: detail))
    messagesByContact[contactId] = messages
    save()
  }

  func markMessage(_ messageId: UUID, status: ChatDeliveryStatus, detail: String = "") {
    for contactId in Array(messagesByContact.keys) {
      guard var messages = messagesByContact[contactId],
            let index = messages.firstIndex(where: { $0.id == messageId }) else {
        continue
      }
      messages[index].deliveryStatus = status
      messages[index].deliveryTrace.append(DeliveryTraceEvent(stage: status.rawValue, detail: detail))
      messagesByContact[contactId] = messages
      save()
      return
    }
  }

  @discardableResult
  func updateMessageContent(
    _ messageId: UUID,
    contactId: String,
    content: String,
    status: ChatDeliveryStatus? = nil,
    traceStage: String? = nil,
    detail: String = "",
    richOutputJson: String? = nil
  ) -> ChatMessage? {
    guard var messages = messagesByContact[contactId],
          let index = messages.firstIndex(where: { $0.id == messageId }) else {
      return nil
    }
    messages[index].content = content
    if let status {
      messages[index].deliveryStatus = status
    }
    if let traceStage {
      messages[index].deliveryTrace.append(DeliveryTraceEvent(stage: traceStage, detail: detail))
    }
    if let richOutputJson {
      messages[index].richOutputJson = richOutputJson
    }
    messagesByContact[contactId] = messages
    save()
    return messages[index]
  }

  @discardableResult
  func appendDeliveryTrace(
    _ messageId: UUID,
    contactId: String? = nil,
    stage: String,
    detail: String = "",
    status: ChatDeliveryStatus? = nil
  ) -> Bool {
    let contactIds = contactId.map { [$0] } ?? Array(messagesByContact.keys)
    for id in contactIds {
      guard var messages = messagesByContact[id],
            let index = messages.firstIndex(where: { $0.id == messageId }) else {
        continue
      }
      if let status {
        messages[index].deliveryStatus = status
      }
      messages[index].deliveryTrace.append(DeliveryTraceEvent(stage: stage, detail: detail))
      messagesByContact[id] = messages
      save()
      return true
    }
    return false
  }

  @discardableResult
  func addCloudModelContact(
    displayName: String,
    provider: String,
    modelId: String,
    endpoint: String,
    apiKey: String,
    apiStyle: SignalASICloudAPIStyle
  ) throws -> SignalASIContact {
    let providerName = provider.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("Custom")
    let cleanDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanModelId.isEmpty else {
      throw SignalASIError.invalidPayload("Cloud model ID is required.")
    }
    guard !cleanEndpoint.isEmpty else {
      throw SignalASIError.invalidPayload("Cloud endpoint is required.")
    }
    guard CloudModelCredentialPolicy.isStoredCredential(cleanAPIKey) else {
      throw SignalASIError.missingAPIKey
    }
    let now = Date()
    let providerSlug = SignalASIStore.slug(providerName)
    let contactId = "cloud:\(providerSlug)"
    let account = "cloud.\(providerSlug).\(SignalASIStore.slug(cleanModelId))"
    try secrets.setString(cleanAPIKey, account: account)
    let model = CloudModelConfig(
      id: "\(providerSlug):\(cleanModelId)",
      displayName: cleanDisplayName.ifBlank(cleanModelId),
      provider: providerName,
      modelId: cleanModelId,
      endpoint: cleanEndpoint,
      apiStyle: apiStyle,
      keychainAccount: account,
      updatedAt: now
    )
    var contact = contacts.first { $0.id == contactId } ?? SignalASIContact(
      id: contactId,
      signalASIId: contactId,
      name: providerName,
      displayName: providerName,
      type: "agent",
      agentKind: "cloud-api",
      deliveryMode: .cloudAPI,
      trustState: .verified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: "ready",
      setupDetail: "Mobile direct cloud model API",
      cloudProvider: providerName,
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: now,
      updatedAt: now
    )
    if let existingIndex = contact.cloudModels.firstIndex(where: { $0.modelId == cleanModelId }) {
      contact.cloudModels[existingIndex] = model
    } else {
      contact.cloudModels.append(model)
    }
    for index in contact.cloudModels.indices {
      let existingModel = contact.cloudModels[index]
      try secrets.setString(cleanAPIKey, account: existingModel.keychainAccount)
      contact.cloudModels[index].updatedAt = now
    }
    contact.selectedCloudModelId = model.modelId
    contact.deleted = false
    contact.deletedAt = nil
    contact.trustState = .verified
    contact.setupStatus = "ready"
    contact.setupDetail = "Mobile direct cloud model API"
    contact.updatedAt = now
    upsert(contact)
    save()
    return contact
  }

  func apiKey(for model: CloudModelConfig) -> String? {
    secrets.string(account: model.keychainAccount)
  }

  func myContactQRText(now: Date = Date()) throws -> String {
    try SignalASIContactExchange.makeContactQRText(profile: profile, serverLinks: serverLinks, now: now)
  }

  func createPhonePairingSession(now: Date = Date()) throws -> [String: String] {
    let token = try SignalASILinkProtocol.newLinkSecret()
    let secret = try SignalASILinkProtocol.newLinkSecret()
    let topic = SignalASILinkProtocol.pairingTopic(secret: secret)
    var sessions = activePhonePairingSessions(now: now)
    sessions.append([
      "token": token,
      "secret": secret,
      "topic": topic,
      "created_at": String(Int64(now.timeIntervalSince1970 * 1_000)),
      "expires_at": String(Int64(now.addingTimeInterval(10 * 60).timeIntervalSince1970 * 1_000))
    ])
    let encoded = try JSONEncoder().encode(Array(sessions.suffix(8)))
    try secrets.setString(encoded.base64EncodedString(), account: phonePairingSessionsKey)
    return sessions.last!
  }

  func activePhonePairingSessions(now: Date = Date()) -> [[String: String]] {
    let nowMillis = Int64(now.timeIntervalSince1970 * 1_000)
    let stored = secrets.string(account: phonePairingSessionsKey)
      .flatMap { Data(base64Encoded: $0) }
      .flatMap { try? JSONDecoder().decode([[String: String]].self, from: $0) } ?? []
    let active = stored.filter { session in
      (Int64(session["expires_at"] ?? "") ?? 0) >= nowMillis &&
        SignalASILinkProtocol.validLinkSecret(session["secret"] ?? "") &&
        session["topic"] == SignalASILinkProtocol.pairingTopic(secret: session["secret"] ?? "")
    }
    if active.count != stored.count {
      if let encoded = try? JSONEncoder().encode(active) {
        try? secrets.setString(encoded.base64EncodedString(), account: phonePairingSessionsKey)
      }
    }
    return active
  }

  func claimPhonePairingSession(
    topic: String,
    token: String,
    remoteFingerprint: String,
    now: Date = Date()
  ) -> [String: String]? {
    var sessions = activePhonePairingSessions(now: now)
    guard let index = sessions.firstIndex(where: {
      $0["topic"] == topic && $0["token"] == token
    }) else { return nil }
    let claimed = sessions[index]["claimed_fingerprint"] ?? ""
    guard claimed.isEmpty || claimed.caseInsensitiveCompare(remoteFingerprint) == .orderedSame else {
      return nil
    }
    if claimed.isEmpty {
      sessions[index]["claimed_fingerprint"] = remoteFingerprint
      sessions[index]["claimed_at"] = String(Int64(now.timeIntervalSince1970 * 1_000))
      if let encoded = try? JSONEncoder().encode(sessions) {
        try? secrets.setString(encoded.base64EncodedString(), account: phonePairingSessionsKey)
      }
    }
    return sessions[index]
  }

  func acceptPhoneControl(_ controlId: String, now: Date = Date()) -> Bool {
    guard UUID(uuidString: controlId) != nil else { return false }
    let nowMillis = now.timeIntervalSince1970 * 1_000
    var accepted = secrets.string(account: phoneAcceptedControlsKey)
      .flatMap { Data(base64Encoded: $0) }
      .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
    accepted = accepted.filter { $0.value >= nowMillis }
    guard accepted[controlId] == nil else { return false }
    accepted[controlId] = nowMillis + Double(SignalASIPhoneContactControl.maximumAgeMillis)
    if accepted.count > 256 {
      accepted = Dictionary(uniqueKeysWithValues: accepted.sorted { $0.value > $1.value }.prefix(256))
    }
    if let encoded = try? JSONEncoder().encode(accepted) {
      try? secrets.setString(encoded.base64EncodedString(), account: phoneAcceptedControlsKey)
    }
    return true
  }

  func phoneOpaqueRoutes() -> [SignalASILinkRoutes] {
    let contactRoutes = contacts.compactMap(\.opaquePhoneRoutes)
    let requestRoutes = friendRequests.compactMap(\.opaquePhoneRoutes)
    return Array(Set(contactRoutes + requestRoutes))
  }

  func phoneOpaqueRoutes(for signalASIId: String) -> SignalASILinkRoutes? {
    contacts.first { $0.signalASIId == signalASIId }?.opaquePhoneRoutes
      ?? friendRequests.first { $0.signalASIId == signalASIId }?.opaquePhoneRoutes
  }

  @discardableResult
  func upsertOpaquePhoneRequest(
    card: [String: Any],
    linkSecret: String,
    localFingerprint: String,
    clientRouteId: String? = nil,
    direction: SignalASIFriendRequestDirection = .incoming,
    now: Date = Date()
  ) throws -> SignalASIFriendRequest {
    let data = try SignalASILinkProtocol.jsonData(card)
    guard let text = String(data: data, encoding: .utf8) else {
      throw SignalASIError.invalidPayload("Phone identity card is not UTF-8.")
    }
    var request = try SignalASIContactExchange.importContactQRCode(text, now: now)
    if let clientRouteId {
      request.linkClientRouteId = clientRouteId
    } else {
      request.linkClientRouteId = try SignalASILinkProtocol.newRouteId()
    }
    request.linkSecret = linkSecret
    request.linkLocalFingerprint = localFingerprint
    request.direction = direction
    rememberVerifiedPhoneContactCard(card)
    return addFriendRequest(request, now: now)
  }

  func rememberVerifiedPhoneContactCard(_ card: [String: Any]) {
    let signalASIId = card.string("signalasi_id")
    guard !signalASIId.isEmpty,
          !card.string("signature").isEmpty,
          (try? SignalASIContactExchange.validateSignedPhoneContactCard(card)) != nil,
          let data = try? SignalASILinkProtocol.jsonData(card),
          let text = String(data: data, encoding: .utf8) else {
      return
    }
    var cards = secrets.string(account: phoneContactCardsKey)
      .flatMap { Data(base64Encoded: $0) }
      .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    cards[signalASIId] = text
    if let encoded = try? JSONEncoder().encode(cards) {
      try? secrets.setString(encoded.base64EncodedString(), account: phoneContactCardsKey)
    }
  }

  func verifiedPhoneContactCard(for signalASIId: String) -> [String: Any]? {
    guard let cards = secrets.string(account: phoneContactCardsKey)
            .flatMap({ Data(base64Encoded: $0) })
            .flatMap({ try? JSONDecoder().decode([String: String].self, from: $0) }),
          let text = cards[signalASIId],
          let card = try? SignalASIQRCodePayload.decodeObject(from: text, label: "Contact QR"),
          card.string("signalasi_id") == signalASIId,
          !card.string("signature").isEmpty,
          (try? SignalASIContactExchange.validateSignedPhoneContactCard(card)) != nil else {
      return nil
    }
    return card
  }

  @discardableResult
  func importContactQRCodeAsFriendRequest(
    _ contents: String,
    now: Date = Date(),
    localFingerprint: String? = nil,
    identityBoundRoutes: SignalASILinkRoutes? = nil
  ) throws -> SignalASIFriendRequest {
    let rawCard = try SignalASIQRCodePayload.decodeObject(from: contents, label: "Contact QR")
    let card = SignalASIContactExchange.normalizeCompactPhoneContactQR(rawCard) ?? rawCard
    var request = try SignalASIContactExchange.importContactQRCode(contents, now: now)
    request.direction = .outgoing
    request.isRead = true
    if card.string("type") == SignalASIContactExchange.opaqueContactType {
      let localFingerprint = localFingerprint ?? profile.identityFingerprint
      if let identityBoundRoutes, identityBoundRoutes.isOpaqueV2Valid {
        request.linkClientRouteId = identityBoundRoutes.clientRouteId
        request.linkSecret = identityBoundRoutes.linkSecret
        request.linkLocalFingerprint = identityBoundRoutes.localFingerprint
      } else {
        request.linkClientRouteId = try SignalASILinkProtocol.newRouteId()
        request.linkSecret = try SignalASILinkProtocol.deriveLinkSecret(
          pairingSecret: card.string("pairing_secret"),
          firstFingerprint: localFingerprint,
          secondFingerprint: request.identityFingerprint
        )
        request.linkLocalFingerprint = localFingerprint
      }
      rememberVerifiedPhoneContactCard(card)
    }
    return addFriendRequest(request, now: now)
  }

  @discardableResult
  func refreshTrustedPhoneRelationship(
    remoteCard: [String: Any],
    routes: SignalASILinkRoutes,
    now: Date = Date()
  ) -> Bool {
    let remoteId = remoteCard.string("signalasi_id")
    guard routes.isOpaqueV2Valid,
          routes.remoteFingerprint.caseInsensitiveCompare(remoteCard.string("identity_fingerprint")) == .orderedSame,
          let index = contacts.firstIndex(where: {
            ($0.id == remoteId || $0.signalASIId == remoteId) &&
              !$0.deleted && $0.trustState == .verified
          }),
          contacts[index].identityFingerprint.caseInsensitiveCompare(routes.remoteFingerprint) == .orderedSame else {
      return false
    }
    contacts[index].linkClientRouteId = routes.clientRouteId
    contacts[index].linkSecret = routes.linkSecret
    contacts[index].linkLocalFingerprint = routes.localFingerprint
    contacts[index].identityFingerprint = routes.remoteFingerprint
    contacts[index].updatedAt = now
    rememberVerifiedPhoneContactCard(remoteCard)
    save()
    return true
  }

  @discardableResult
  func addFriendRequest(_ request: SignalASIFriendRequest, now: Date = Date()) -> SignalASIFriendRequest {
    let existingContact = contact(id: request.signalASIId)
    let wasDeleted = existingContact?.deleted == true || existingContact?.trustState == .deleted
    var stored = request
    let previous = friendRequests.first { $0.signalASIId == stored.signalASIId }
    stored.id = previous?.id.ifBlank(stored.id)
      ?? stored.id.ifBlank("req_\(Int64(now.timeIntervalSince1970 * 1000))")
    stored.status = .pending
    stored.createdAt = previous?.createdAt ?? now
    stored.isRead = SignalASIFriendRequestUnreadPolicy.isReadForPendingRequest(
      previous: previous,
      direction: stored.direction
    )
    stored.previouslyDeleted = wasDeleted
    stored.readdRequired = wasDeleted
    if stored.mqttInboxTopic.isEmpty {
      stored.mqttInboxTopic = stored.mqttTopic
    }
    if let index = friendRequests.firstIndex(where: { $0.signalASIId == stored.signalASIId }) {
      friendRequests[index] = stored
    } else {
      friendRequests.append(stored)
    }
    save()
    return stored
  }

  @discardableResult
  func approveFriendRequest(id: String, now: Date = Date()) -> Bool {
    guard let index = friendRequests.firstIndex(where: { $0.id == id }) else {
      return false
    }
    var request = friendRequests[index]
    request.status = .approved
    request.approvedAt = now
    request.deletedAt = nil
    request.readdRequired = false
    friendRequests[index] = request
    let contactId = request.type == "hermes" ? "hermes" : request.signalASIId
    let requestType = request.type.ifBlank("person")
    let requestAgentKind = request.agentKind.ifBlank(agentKind(forFriendRequestType: requestType))
    let requestDesktopId = request.desktopId.ifBlank(request.deviceId)
    let setupDetail = approvedContactSetupDetail(for: request)
    let deliveryMode = approvedDeliveryMode(for: request, type: requestType)
    var next = contact(id: contactId) ?? SignalASIContact(
      id: contactId,
      signalASIId: request.signalASIId,
      name: request.name,
      displayName: request.name,
      type: requestType,
      agentKind: requestAgentKind,
      deliveryMode: deliveryMode,
      trustState: .verified,
      desktopId: requestDesktopId,
      desktopName: request.desktopName,
      identityFingerprint: request.identityFingerprint,
      setupStatus: "ready",
      setupDetail: setupDetail,
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: now,
      updatedAt: now
    )
    next.signalASIId = request.signalASIId
    next.name = request.name
    next.displayName = request.name
    next.type = requestType
    next.agentKind = requestAgentKind
    next.deliveryMode = deliveryMode
    next.trustState = .verified
    next.desktopId = requestDesktopId
    next.desktopName = request.desktopName
    next.identityFingerprint = request.identityFingerprint
    next.deviceName = request.deviceName.nonEmpty
    next.deviceManufacturer = request.deviceManufacturer.nonEmpty
    next.deviceModel = request.deviceModel.nonEmpty
    next.devicePlatform = request.devicePlatform.nonEmpty
    next.devicePlatformVersion = request.devicePlatformVersion.nonEmpty
    next.deviceProfileName = request.deviceProfileName.nonEmpty
    next.deviceHostName = request.deviceHostName.nonEmpty
    next.mqttTopic = request.mqttTopic
    next.mqttInboxTopic = request.mqttInboxTopic
    next.linkClientRouteId = request.linkClientRouteId.nonEmpty
    next.linkSecret = request.linkSecret.nonEmpty
    next.linkLocalFingerprint = request.linkLocalFingerprint.nonEmpty
    next.signalBundleRef = request.signalBundleRef
    next.setupStatus = "ready"
    next.setupDetail = setupDetail
    next.agentId = nil
    next.agentId = requestType == "agent" ? next.connectorAgentId : nil
    next.setupNextStep = request.setupNextStep.nonEmpty
    next.desktopAccessProfile = request.desktopAccessProfile.nonEmpty
    next.desktopAccessScopes = request.desktopAccessScopes.isEmpty ? nil : request.desktopAccessScopes
    next.connectorCapabilities = request.connectorCapabilities.isEmpty ? nil : request.connectorCapabilities
    next.connectorCapabilitiesHash = request.connectorCapabilitiesHash.nonEmpty
    next.connectorProtocols = request.connectorProtocols.isEmpty ? nil : request.connectorProtocols
    next.connectorProtocolFeatures = request.connectorProtocolFeatures.isEmpty ? nil : request.connectorProtocolFeatures
    next.connectorAdapterType = request.connectorAdapterType.nonEmpty
    next.connectorProviderProfileJSON = request.connectorProviderProfileJSON
    next.deleted = false
    next.deletedAt = nil
    next.updatedAt = now
    upsert(next)
    save()
    if request.opaquePhoneRoutes != nil {
      let language = LanguagePolicySettings.resolveInterface(languagePolicy.interfaceLanguage)
      let content = String(
        format: SignalASILocalization.string(
          "signalasi.phone_contact.added_notice",
          fallback: "You and %@ are now contacts.",
          language: language
        ),
        request.name
      )
      _ = appendSystemNotification(
        content,
        eventId: "phone-contact-approved:\(request.id)"
      )
    }
    return true
  }

  @discardableResult
  func approveFriendRequest(signalASIId: String, now: Date = Date()) -> Bool {
    guard let request = friendRequests.first(where: {
      $0.signalASIId == signalASIId && $0.status == .pending
    }) else { return false }
    return approveFriendRequest(id: request.id, now: now)
  }

  private func approvedDeliveryMode(
    for request: SignalASIFriendRequest,
    type: String
  ) -> SignalASIDeliveryMode {
    guard type == "agent" else { return .link }
    let hasDesktopContext = !request.desktopId.isEmpty ||
      !request.desktopName.isEmpty ||
      !request.desktopAccessProfile.isEmpty ||
      !request.connectorAdapterType.isEmpty ||
      !request.connectorCapabilities.isEmpty
    return hasDesktopContext ? .pcConnector : .link
  }

  @discardableResult
  func rejectFriendRequest(id: String, now: Date = Date()) -> Bool {
    guard let index = friendRequests.firstIndex(where: { $0.id == id }) else {
      return false
    }
    friendRequests[index].status = .rejected
    friendRequests[index].rejectedAt = now
    save()
    return true
  }

  @discardableResult
  func rejectFriendRequest(signalASIId: String, now: Date = Date()) -> Bool {
    guard let request = friendRequests.first(where: {
      $0.signalASIId == signalASIId && $0.status == .pending
    }) else { return false }
    return rejectFriendRequest(id: request.id, now: now)
  }

  func exportBackupPayload(includeContacts: Bool = true, includeMessages: Bool = true) -> SignalASIBackupPayload {
    let cloudSecrets = exportCloudAPISecrets()
    let globalAgentState = exportGlobalAgentBackupData()
    let transcriptEntries = UserDefaultsAgentTranscriptEntryStore(defaults: defaults, secrets: secrets)
      .listAll(limit: 500)
    let identity = secrets.string(account: identityPrivateKeyAccount).map {
      SignalASIBackupIdentity(
        identityPrivateKey: $0,
        identityPublicKey: profile.identityPublicKey,
        identityFingerprint: profile.identityFingerprint
      )
    }
    return SignalASIBackupPayload(
      identity: identity,
      profile: profile,
      includesContacts: includeContacts,
      includesMessages: includeMessages,
      privacyManifest: SignalASIBackupPrivacyManifest(
        includesIdentity: identity != nil,
        includesContacts: includeContacts,
        includesMessages: includeMessages,
        includesServerLinks: true,
        includesVoiceSettings: true,
        includesDisplaySettings: true,
        includesAgentSafetySettings: true,
        includesAgentTaskBudget: true,
        includesAgentKnowledge: !agentKnowledgeItems.isEmpty || !agentKnowledgeAccessAudit.isEmpty,
        includesAgentTaskHistory: !recentAgentTasks(limit: 1).isEmpty,
        includesAutomationTasks: !proactiveTasks.isEmpty || !proactiveRuns.isEmpty ||
          !UserDefaultsAgentWorkflowTriggerStore.shared.list().isEmpty ||
          !workflowExecutionHistoryStore.listAll().isEmpty || !globalProactiveMessages.isEmpty,
        includesAgentConversations: !agentSessions(includeArchived: true).isEmpty,
        includesGlobalAgentState: true,
        includesAgentTranscript: !transcriptEntries.isEmpty,
        includesCustomDeviceConnectors: true,
        includesHomeAssistantSettings: true,
        includesModelPlannerSettings: true,
        includesGlobalAgentSettings: true,
        includesCloudAPISecrets: !cloudSecrets.isEmpty
      ),
      agentData: SignalASIBackupAgentData(
        serverLinks: serverLinks,
        memory: exportAgentMemoryItems(),
        memoryDeletionIndex: memoryDeletionIndex.exportTombstones(),
        knowledge: agentKnowledgeItems,
        knowledgeAccessAudit: agentKnowledgeAccessAudit,
        taskHistory: recentAgentTasks(limit: 200),
        transcript: transcriptEntries,
        proactiveTasks: automationTasks(),
        proactiveRuns: Array(proactiveRuns.suffix(500)),
        workflowExecutions: workflowExecutionHistoryStore.exportRecords(),
        workflowTriggers: UserDefaultsAgentWorkflowTriggerStore.shared.list(),
        globalProactiveMessages: Array(globalProactiveMessages.suffix(500)),
        globalAgentFeedback: Array(globalAgentFeedback.suffix(500)),
        globalAgentState: globalAgentState,
        agentConversations: agentSessions(includeArchived: true),
        activeAgentConversationId: activeAgentConversationId,
        voiceSettings: voiceSettings,
        languagePolicy: languagePolicy,
        displaySettings: displaySettings,
        agentSafetySettings: agentSafetySettings,
        agentPreferenceMode: agentPreferenceMode,
        cloudAPISecrets: cloudSecrets,
        taskBudget: agentTaskBudget,
        customDeviceConnectors: customDeviceConnectors,
        homeAssistantSettings: homeAssistantSettings,
        modelPlannerSettings: modelPlannerSettings,
        globalAgentSettings: globalAgentSettings
      ),
      contacts: includeContacts ? contacts : [],
      friendRequests: includeContacts ? friendRequests : [],
      messagesByContact: includeMessages ? messagesByContact : [:],
      readAtByContact: includeMessages ? readAtByContact : [:]
    )
  }

  func restoreBackupPayload(_ payload: SignalASIBackupPayload, includeMessages: Bool = true) throws {
    if let identity = payload.identity, !identity.identityPrivateKey.isEmpty {
      try secrets.setString(identity.identityPrivateKey, account: identityPrivateKeyAccount)
    }
    if payload.includesAgentData {
      try importCloudAPISecrets(payload.agentData.cloudAPISecrets)
    }
    profile = payload.profile
    if payload.includesContacts {
      contacts = payload.contacts
      friendRequests = payload.friendRequests
    }
    if includeMessages, payload.includesMessages {
      messagesByContact = AgentPeerChatTransport
        .migrateStoredHistory(payload.messagesByContact)
        .messages
      readAtByContact = payload.readAtByContact
    }
    if payload.includesAgentData {
      serverLinks = payload.agentData.serverLinks.filter { $0.routes.isOpaqueV2Valid }
      voiceSettings = payload.agentData.voiceSettings
      languagePolicy = payload.agentData.languagePolicy
      displaySettings = payload.agentData.displaySettings
      agentSafetySettings = payload.agentData.agentSafetySettings
      agentPreferenceMode = payload.agentData.agentPreferenceMode
      agentTaskBudget = payload.agentData.taskBudget
      try applyCustomDeviceConnectors(payload.agentData.customDeviceConnectors)
      try applyHomeAssistantSettings(payload.agentData.homeAssistantSettings)
      modelPlannerSettings = payload.agentData.modelPlannerSettings
      globalAgentSettings = payload.agentData.globalAgentSettings.normalized
      agentMemoryItems = agentMemoryStore.restoreBackupItems(
        payload.agentData.memory,
        tombstones: payload.agentData.memoryDeletionIndex
      )
      agentKnowledgeItems = Array((payload.agentData.knowledge ?? []).suffix(500))
      agentKnowledgeAccessAudit = Array((payload.agentData.knowledgeAccessAudit ?? []).suffix(100))
      agentTaskRecords = Array((payload.agentData.taskHistory ?? []).suffix(200))
      if let transcript = payload.agentData.transcript {
        UserDefaultsAgentTranscriptEntryStore(defaults: defaults, secrets: secrets).replaceAll(transcript)
      }
      proactiveTasks = Array((payload.agentData.proactiveTasks ?? []).suffix(200))
      proactiveRuns = Array((payload.agentData.proactiveRuns ?? []).suffix(500))
      if let workflowExecutions = payload.agentData.workflowExecutions {
        try workflowExecutionHistoryStore.replaceAll(workflowExecutions)
      }
      if let workflowTriggers = payload.agentData.workflowTriggers {
        try UserDefaultsAgentWorkflowTriggerStore.shared.replaceAll(workflowTriggers)
      }
      globalProactiveMessages = Array((payload.agentData.globalProactiveMessages ?? []).suffix(500))
      globalAgentFeedback = Array((payload.agentData.globalAgentFeedback ?? []).suffix(500))
      if let globalAgentState = payload.agentData.globalAgentState {
        restoreGlobalAgentBackupData(globalAgentState)
      }
      agentConversations = Array((payload.agentData.agentConversations ?? []).suffix(200))
      activeAgentConversationId = payload.agentData.activeAgentConversationId
      if !agentConversations.contains(where: { $0.id == activeAgentConversationId }) {
        activeAgentConversationId = agentConversations.first(where: { $0.status == .active })?.id ?? ""
      }
    }
    save()
  }

  @discardableResult
  func setSelectedCloudModel(contactId: String, modelId: String) -> Bool {
    guard var contact = contact(id: contactId),
          contact.cloudModels.contains(where: { $0.modelId == modelId }) else {
      return false
    }
    contact.selectedCloudModelId = modelId
    contact.updatedAt = Date()
    upsert(contact)
    save()
    return true
  }

  @discardableResult
  func deleteCloudModel(contactId: String, modelId: String) -> Bool {
    guard let index = contacts.firstIndex(where: { $0.id == contactId || $0.signalASIId == contactId }),
          contacts[index].deliveryMode == .cloudAPI,
          let modelIndex = contacts[index].cloudModels.firstIndex(where: { $0.modelId == modelId }) else {
      return false
    }
    let removed = contacts[index].cloudModels.remove(at: modelIndex)
    secrets.delete(account: removed.keychainAccount)
    if contacts[index].selectedCloudModelId == modelId {
      contacts[index].selectedCloudModelId = contacts[index].cloudModels.first?.modelId ?? ""
    }
    contacts[index].updatedAt = Date()
    if contacts[index].cloudModels.isEmpty {
      contacts[index].deleted = true
      contacts[index].trustState = .deleted
      contacts[index].setupStatus = "needs_setup"
      contacts[index].setupDetail = "Add a cloud model before chatting."
    }
    save()
    return true
  }

  @discardableResult
  func addServerLink(
    from pairing: PairingQRCode,
    rotateClientRoute: Bool = true,
    localFingerprint: String? = nil
  ) throws -> ServerLink {
    let existing = serverLinks.first { $0.desktopId == pairing.desktopId }
    let clientRouteId: String
    if !rotateClientRoute, let existingRouteId = existing?.routes.clientRouteId {
      clientRouteId = existingRouteId
    } else {
      clientRouteId = try SignalASILinkProtocol.newRouteId()
    }
    let localFingerprint = localFingerprint ?? profile.identityFingerprint
    let linkSecret = try SignalASILinkProtocol.deriveLinkSecret(
      pairingSecret: pairing.pairingSecret.base64URLEncodedString(),
      firstFingerprint: localFingerprint,
      secondFingerprint: pairing.desktopFingerprint
    )
    let routes = SignalASILinkRoutes(
      clientRouteId: clientRouteId,
      linkSecret: linkSecret,
      localFingerprint: localFingerprint,
      remoteFingerprint: pairing.desktopFingerprint
    )
    let link = ServerLink(
      desktopId: pairing.desktopId,
      desktopName: pairing.desktopName,
      desktopFingerprint: pairing.desktopFingerprint,
      signalName: pairing.desktopId,
      routes: routes,
      paired: existing?.paired ?? false,
      accessProfile: pairing.access.profile,
      accessScopes: pairing.access.scopes,
      capabilityManifestVersion: existing?.capabilityManifestVersion ?? 0,
      updatedAt: Date()
    )
    serverLinks.removeAll { $0.desktopId == link.desktopId }
    serverLinks.append(link)

    var hermes = contact(id: "hermes") ?? SignalASIContact.hermes()
    hermes.trustState = link.paired ? .verified : .unverified
    hermes.deleted = false
    hermes.deletedAt = nil
    hermes.identityFingerprint = link.desktopFingerprint
    hermes.desktopId = link.desktopId
    hermes.desktopName = link.desktopName
    hermes.setupStatus = link.paired ? "ready" : "pairing"
    hermes.setupDetail = link.paired ? "SignalASI Link is paired" : "Waiting for desktop confirmation"
    hermes.updatedAt = Date()
    upsert(hermes)
    upsertDesktopAgentContacts(from: pairing, link: link)
    save()
    return link
  }

  func markServerPaired(desktopId: String, access: PairingAccess? = nil) {
    guard let index = serverLinks.firstIndex(where: { $0.desktopId == desktopId }) else { return }
    serverLinks[index].paired = true
    serverLinks[index].updatedAt = Date()
    if let access {
      serverLinks[index].accessProfile = access.profile
      serverLinks[index].accessScopes = access.scopes
    }
    if var hermes = contact(id: "hermes") {
      hermes.trustState = .verified
      hermes.setupStatus = "ready"
      hermes.setupDetail = "SignalASI Link is paired"
      hermes.updatedAt = Date()
      upsert(hermes)
    }
    for contactIndex in contacts.indices {
      guard contacts[contactIndex].desktopId == desktopId,
            contacts[contactIndex].type == "agent" else {
        continue
      }
      contacts[contactIndex].trustState = .verified
      contacts[contactIndex].setupStatus = "ready"
      contacts[contactIndex].setupDetail = "SignalASI Link is paired"
      contacts[contactIndex].updatedAt = Date()
    }
    save()
  }

  @discardableResult
  func updateDesktopDeviceMetadata(
    desktopId: String,
    payload: [String: Any],
    now: Date = Date()
  ) -> Bool {
    let cleanDesktopId = desktopId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanDesktopId.isEmpty,
          let metadata = SignalASIDesktopDeviceMetadata.from(payload: payload, now: now),
          let index = serverLinks.firstIndex(where: { $0.desktopId == cleanDesktopId }) else {
      return false
    }
    let merged = (serverLinks[index].deviceMetadata ?? SignalASIDesktopDeviceMetadata(lastSeenAt: now))
      .merged(with: metadata)
    serverLinks[index].deviceMetadata = merged
    serverLinks[index].updatedAt = now
    save()
    return true
  }

  @discardableResult
  func updatePairedDesktopDevice(from payload: [String: Any], link: ServerLink? = nil) -> Bool {
    let desktopId = payload.string("desktop_id").ifBlank(link?.desktopId ?? "")
    guard !desktopId.isEmpty else { return false }
    let device = payload.dictionary("desktop_device") ?? [:]
    let defaultName = payload.string("desktop_display_name")
      .ifBlank(device.string("display_name"))
      .ifBlank(payload.string("desktop_name"))
      .ifBlank(link?.desktopName ?? "SignalASI Desktop")
    let fingerprint = payload.string("desktop_fingerprint")
      .ifBlank(device.string("identity_fingerprint"))
      .ifBlank(payload.string("identity_fingerprint"))
      .ifBlank(payload.string("identity_key_sha256"))
      .ifBlank(link?.desktopFingerprint ?? "")
    let now = Date()
    let existingContact = contact(id: desktopId)
    let storedDefaultName = deviceDefaultDisplayName(for: desktopId)
    let previousDefaultName = storedDefaultName
      .ifBlank(existingContact?.desktopName ?? "")
      .ifBlank(defaultName)
    let existingDisplayName = existingContact?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let userRenamed = existingContact?.type == "device" &&
      !existingDisplayName.isEmpty &&
      existingDisplayName != previousDefaultName
    rememberDeviceDefaultDisplayName(desktopId, fallback: previousDefaultName)

    var contact = existingContact ?? SignalASIContact(
      id: desktopId,
      signalASIId: desktopId,
      name: defaultName,
      displayName: defaultName,
      type: "device",
      agentKind: "device",
      deliveryMode: .pcConnector,
      trustState: .verified,
      desktopId: desktopId,
      desktopName: defaultName,
      identityFingerprint: fingerprint,
      setupStatus: "ready",
      setupDetail: "SignalASI Link is paired",
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: now,
      updatedAt: now
    )
    if !userRenamed {
      contact.name = defaultName
      contact.displayName = defaultName
    }
    contact.signalASIId = desktopId
    contact.type = "device"
    contact.agentKind = "device"
    contact.agentId = "desktop"
    contact.deliveryMode = .pcConnector
    contact.trustState = .verified
    contact.desktopId = desktopId
    contact.desktopName = defaultName
    contact.identityFingerprint = fingerprint
    contact.deviceName = device.string("device_name")
      .ifBlank(payload.string("device_name"))
      .ifBlank(defaultName).nonEmpty
    contact.deviceManufacturer = device.string("device_manufacturer")
      .ifBlank(device.string("manufacturer"))
      .ifBlank(payload.string("device_manufacturer"))
      .ifBlank(payload.string("manufacturer")).nonEmpty
    contact.deviceModel = device.string("device_model")
      .ifBlank(device.string("model"))
      .ifBlank(payload.string("device_model"))
      .ifBlank(payload.string("model")).nonEmpty
    contact.devicePlatform = SignalASIDesktopDeviceMetadata.from(payload: payload)?.platform.nonEmpty
      ?? device.string("platform").ifBlank(payload.string("platform")).nonEmpty
    contact.devicePlatformVersion = device.string("platform_version")
      .ifBlank(payload.string("platform_version")).nonEmpty
    contact.deviceProfileName = device.string("profile_name")
      .ifBlank(payload.string("profile_name")).nonEmpty
    contact.deviceHostName = SignalASIDesktopDeviceMetadata.from(payload: payload)?.hostName.nonEmpty
    contact.setupStatus = "ready"
    contact.setupDetail = "SignalASI Link is paired"
    contact.desktopAccessProfile = payload.string("desktop_access_profile")
      .ifBlank(link?.accessProfile ?? "").nonEmpty
    let scopes = payload.stringArray("desktop_access_scopes")
      .ifEmpty(Array(link?.accessScopes ?? []).sorted())
    contact.desktopAccessScopes = scopes.isEmpty ? nil : scopes
    contact.mqttTopic = link?.routes.upTopic
    contact.mqttInboxTopic = link?.routes.downTopic
    contact.deleted = false
    contact.deletedAt = nil
    contact.updatedAt = now
    upsert(contact)
    save()
    return true
  }

  private func deviceDefaultDisplayName(for desktopId: String) -> String {
    UserDefaults.standard.string(forKey: deviceDefaultDisplayNameKey(desktopId)) ?? ""
  }

  private func rememberDeviceDefaultDisplayName(_ desktopId: String, fallback: String) {
    let cleanDesktopId = desktopId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanDesktopId.isEmpty,
          !cleanFallback.isEmpty,
          deviceDefaultDisplayName(for: cleanDesktopId).isEmpty else {
      return
    }
    UserDefaults.standard.set(cleanFallback, forKey: deviceDefaultDisplayNameKey(cleanDesktopId))
  }

  private func deviceDefaultDisplayNameKey(_ desktopId: String) -> String {
    "signalasi.device.default_display_name.\(desktopId)"
  }

  @discardableResult
  func markCapabilityManifestReceived(desktopId: String, version: Int) -> ServerLink? {
    guard let index = serverLinks.firstIndex(where: { $0.desktopId == desktopId }) else {
      return nil
    }
    let normalizedVersion = max(version, 0)
    guard normalizedVersion > serverLinks[index].capabilityManifestVersion else {
      return serverLinks[index]
    }
    serverLinks[index].capabilityManifestVersion = normalizedVersion
    serverLinks[index].updatedAt = Date()
    save()
    return serverLinks[index]
  }

  func removeServer(desktopId: String) {
    serverLinks.removeAll { $0.desktopId == desktopId }
    if var hermes = contact(id: "hermes") {
      if let activeLink = serverLinks.first(where: \.paired) ?? serverLinks.first {
        hermes.trustState = activeLink.paired ? .verified : .unverified
        hermes.identityFingerprint = activeLink.desktopFingerprint
        hermes.desktopId = activeLink.desktopId
        hermes.desktopName = activeLink.desktopName
        hermes.setupStatus = activeLink.paired ? "ready" : "pairing"
        hermes.setupDetail = activeLink.paired ? "SignalASI Link is paired" : "Waiting for desktop confirmation"
      } else {
        hermes.trustState = .unverified
        hermes.desktopId = ""
        hermes.desktopName = ""
        hermes.setupStatus = "needs_pairing"
        hermes.setupDetail = "Waiting for SignalASI Desktop pairing"
      }
      hermes.updatedAt = Date()
      upsert(hermes)
    }
    for contactIndex in contacts.indices {
      guard contacts[contactIndex].desktopId == desktopId else {
        continue
      }
      if contacts[contactIndex].type == "device" {
        contacts[contactIndex].deleted = true
        contacts[contactIndex].deletedAt = Date()
        contacts[contactIndex].trustState = .deleted
      } else if contacts[contactIndex].type == "agent" {
        contacts[contactIndex].trustState = .unverified
        contacts[contactIndex].setupStatus = "needs_pairing"
        contacts[contactIndex].setupDetail = "Desktop pairing revoked"
      } else {
        continue
      }
      contacts[contactIndex].updatedAt = Date()
    }
    save()
  }

  @discardableResult
  func removeDesktopPairing(
    desktopId: String,
    deleteMessages: Bool = true,
    now: Date = Date()
  ) -> Set<String> {
    let cleanDesktopId = desktopId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanDesktopId.isEmpty else { return [] }
    let prefix = "\(cleanDesktopId):"
    let matchingContacts = contacts.filter { contact in
      contact.id != "system" && contact.id != "hermes" && (
        contact.desktopId == cleanDesktopId ||
        contact.id == cleanDesktopId ||
        contact.id.hasPrefix(prefix) ||
        contact.signalASIId == cleanDesktopId ||
        contact.signalASIId.hasPrefix(prefix)
      )
    }
    var removedIds = Set(
      matchingContacts
        .flatMap { [$0.id, $0.signalASIId] }
        .filter { !$0.isEmpty }
    )
    messagesByContact.keys
      .filter { $0 == cleanDesktopId || $0.hasPrefix(prefix) }
      .forEach { removedIds.insert($0) }

    matchingContacts.flatMap(\.cloudModels).forEach { secrets.delete(account: $0.keychainAccount) }
    let matchingContactIds = Set(matchingContacts.map(\.id))
    contacts.removeAll { matchingContactIds.contains($0.id) }
    for index in friendRequests.indices where removedIds.contains(friendRequests[index].id) ||
      removedIds.contains(friendRequests[index].signalASIId) {
      friendRequests[index].status = .deleted
      friendRequests[index].deletedAt = now
      friendRequests[index].readdRequired = true
    }
    if deleteMessages {
      removedIds.forEach {
        messagesByContact.removeValue(forKey: $0)
        readAtByContact.removeValue(forKey: $0)
      }
    }
    serverLinks.removeAll { $0.desktopId == cleanDesktopId }
    if var hermes = contact(id: "hermes") {
      if let activeLink = serverLinks.first(where: \.paired) ?? serverLinks.first {
        hermes.trustState = activeLink.paired ? .verified : .unverified
        hermes.identityFingerprint = activeLink.desktopFingerprint
        hermes.desktopId = activeLink.desktopId
        hermes.desktopName = activeLink.desktopName
        hermes.setupStatus = activeLink.paired ? "ready" : "pairing"
        hermes.setupDetail = activeLink.paired ? "SignalASI Link is paired" : "Waiting for desktop confirmation"
      } else {
        hermes.trustState = .unverified
        hermes.identityFingerprint = ""
        hermes.desktopId = ""
        hermes.desktopName = ""
        hermes.setupStatus = "needs_pairing"
        hermes.setupDetail = "Waiting for SignalASI Desktop pairing"
      }
      hermes.updatedAt = now
      upsert(hermes)
    }
    save()
    return removedIds
  }

  @discardableResult
  func updateDesktopAgentContacts(from payload: [String: Any], link incomingLink: ServerLink? = nil) -> Int {
    guard let source = SignalASIContactExchange.connectorAgentSource(from: payload) else {
      return 0
    }
    let link = incomingLink ?? serverLink(forConnectorPayload: source.parentPayload)
    let updated = upsertDesktopAgentContacts(
      payloads: desktopAgentPayloads(from: source.agents, parentPayload: source.parentPayload, link: link),
      link: link
    )
    if updated > 0 {
      save()
    }
    return updated
  }

  @discardableResult
  func importDesktopAgentQRCodeAsContacts(_ contents: String) throws -> Int {
    let object = try SignalASIQRCodePayload.decodeObject(from: contents, label: "Agent QR")
    if let source = SignalASIContactExchange.connectorAgentSource(from: object) {
      let link = serverLink(forConnectorPayload: source.parentPayload) ??
        singleDesktopFallbackLink(for: source.parentPayload)
      let updated = upsertDesktopAgentContacts(
        payloads: desktopAgentPayloads(from: source.agents, parentPayload: source.parentPayload, link: link),
        link: link
      )
      if updated > 0 {
        save()
      }
      return updated
    }
    let link = serverLink(forConnectorPayload: object) ?? singleDesktopFallbackLink(for: object)
    guard let payload = singleDesktopAgentPayload(from: object, link: link) else {
      throw SignalASIError.invalidPayload("Unsupported Agent QR code.")
    }
    let updated = upsertDesktopAgentContacts(payloads: [payload], link: link)
    if updated > 0 {
      save()
    }
    return updated
  }

  private func upsertDesktopAgentContacts(from pairing: PairingQRCode, link: ServerLink) {
    _ = upsertDesktopAgentContacts(payloads: desktopAgentPayloads(from: pairing, link: link), link: link)
  }

  @discardableResult
  private func upsertDesktopAgentContacts(payloads: [[String: Any]], link incomingLink: ServerLink?) -> Int {
    var updated = 0
    payloads.forEach { payload in
      let link = incomingLink ?? serverLink(forConnectorPayload: payload)
      let agentId = desktopAgentId(from: payload)
      guard !agentId.isEmpty, agentId != "cloud-model",
            payload.string("kind") != "cloud-model",
            payload.string("agent_kind") != "cloud-model" else {
        return
      }
      let desktopId = desktopId(from: payload, link: link)
      guard !desktopId.isEmpty else { return }
      let desktopName = payload.string("desktop_name").ifBlank(link?.desktopName ?? "SignalASI Desktop")
      let desktopFingerprint = desktopFingerprint(from: payload, link: link)
      let isPaired = link?.paired == true
      let rawId = payload.string("id")
      let contactId: String
      if rawId.contains(":"), rawId.hasPrefix(desktopId) || rawId.hasPrefix("desktop_") {
        contactId = rawId
      } else {
        contactId = "\(desktopId):\(agentId)"
      }
      let agentName = payload.string("name").ifBlank(agentId)
      let displayName = payload.string("display_name")
        .ifBlank(payload.string("label"))
        .ifBlank("\(agentName) · \(desktopName)")
      let kind = payload.string("kind").ifBlank(payload.string("agent_kind")).ifBlank("custom-cli")
      let setupStatus = payload.string("status")
        .ifBlank(payload.string("setup_status"))
        .ifBlank(isPaired ? "ready" : "unknown")
      let setupDetail = payload.string("detail")
        .ifBlank(payload.string("setup_detail"))
        .ifBlank(payload.string("setup"))
        .ifBlank(
          isPaired ? "SignalASI Link is paired" : "Waiting for SignalASI Desktop status"
        )
      let setupNextStep = payload.string("setup_next_step")
        .ifBlank(payload.string("setup"))
      let desktopAccessProfile = payload.string("desktop_access_profile")
        .ifBlank((link?.accessProfile ?? "").ifBlank(SignalASILinkProtocol.accessRestricted))
      let payloadAccessScopes = payload.stringArray("desktop_access_scopes")
      let desktopAccessScopes = (payloadAccessScopes.isEmpty
        ? Array(link?.accessScopes ?? []).sorted()
        : payloadAccessScopes
      )
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      let connectorCapabilities = connectorCapabilities(from: payload)
      let connectorProtocols = connectorProtocols(from: payload)
      let connectorProtocolFeatures = connectorProtocolFeatures(from: payload)
      let connectorAdapterType = connectorAdapterType(from: payload)
      let now = Date()
      var contact = contact(id: contactId) ?? SignalASIContact(
        id: contactId,
        signalASIId: contactId,
        name: displayName,
        displayName: displayName,
        type: "agent",
        agentKind: kind,
        deliveryMode: .pcConnector,
        trustState: isPaired ? .verified : .unverified,
        desktopId: desktopId,
        desktopName: desktopName,
        identityFingerprint: desktopFingerprint,
        setupStatus: setupStatus,
        setupDetail: setupDetail,
        cloudProvider: "",
        cloudModels: [],
        selectedCloudModelId: "",
        deleted: false,
        createdAt: now,
        updatedAt: now
      )
      contact.signalASIId = contactId
      contact.name = displayName
      contact.displayName = displayName
      contact.type = "agent"
      contact.agentKind = kind
      contact.agentId = agentId
      contact.deliveryMode = .pcConnector
      contact.trustState = isPaired ? .verified : .unverified
      contact.desktopId = desktopId
      contact.desktopName = desktopName
      contact.identityFingerprint = desktopFingerprint
      contact.setupStatus = setupStatus
      contact.setupDetail = setupDetail
      contact.setupNextStep = setupNextStep.nonEmpty
      contact.desktopAccessProfile = desktopAccessProfile.nonEmpty
      contact.desktopAccessScopes = desktopAccessScopes.isEmpty ? nil : desktopAccessScopes
      contact.mqttTopic = payload.string("mqtt_topic").ifBlank(link?.routes.upTopic ?? "")
      contact.mqttInboxTopic = payload.string("mqtt_inbox_topic").ifBlank(link?.routes.downTopic ?? "")
      contact.connectorCapabilities = connectorCapabilities.isEmpty ? nil : connectorCapabilities
      contact.connectorCapabilitiesHash = payload.string("capabilities_hash")
        .ifBlank(capabilitiesHash(for: connectorCapabilities))
        .nonEmpty
      contact.connectorProtocols = connectorProtocols.isEmpty ? nil : connectorProtocols
      contact.connectorProtocolFeatures = connectorProtocolFeatures.isEmpty ? nil : connectorProtocolFeatures
      contact.connectorAdapterType = connectorAdapterType.nonEmpty
      contact.connectorProviderProfileJSON = providerProfileJSON(from: payload)
      contact.deleted = false
      contact.deletedAt = nil
      contact.updatedAt = now
      upsert(contact)
      updated += 1
    }
    return updated
  }

  private func desktopAgentPayloads(from pairing: PairingQRCode, link: ServerLink) -> [[String: Any]] {
    if let source = SignalASIContactExchange.connectorAgentSource(from: pairing.raw) {
      return desktopAgentPayloads(from: source.agents, parentPayload: source.parentPayload, link: link)
    }
    let fallbackAgents = [
      ("hermes", "Hermes Agent", "local-cli"),
      ("codex", "Codex Agent", "local-cli"),
      ("claude", "Claude Code", "local-cli"),
      ("openclaw", "OpenClaw", "local-cli"),
      ("local-llm", "Local LLM", "local-model"),
      ("custom-agent", "Custom Agent", "custom-cli")
    ]
    return fallbackAgents.map { agent in
      let (agentId, name, kind) = agent
      let payload: [String: Any] = [
        "id": "\(link.desktopId):\(agentId)",
        "agent_id": agentId,
        "name": name,
        "display_name": "\(name) · \(link.desktopName)",
        "kind": kind,
        "desktop_id": link.desktopId,
        "desktop_name": link.desktopName,
        "desktop_fingerprint": link.desktopFingerprint,
        "desktop_access_profile": link.accessProfile,
        "desktop_access_scopes": Array(link.accessScopes).sorted(),
        "status": link.paired ? "ready" : "unknown",
        "detail": link.paired ? "SignalASI Link is paired" : "Waiting for SignalASI Desktop status",
        "setup": "",
        "mqtt_topic": link.routes.upTopic,
        "updated_at": Int64(Date().timeIntervalSince1970 * 1000)
      ]
      return payload
    }
  }

  private func desktopAgentPayloads(
    from agents: [[String: Any]],
    parentPayload: [String: Any],
    link: ServerLink?
  ) -> [[String: Any]] {
    let access = SignalASILinkProtocol.pairingAccess(from: parentPayload.dictionary("pairing_access"))
    let server = parentPayload.dictionary("server") ??
      parentPayload.dictionary("desktop") ??
      parentPayload.dictionary("desktop_identity")
    return agents.map { agent in
      var payload = agent
      inheritConnectorValue(
        "desktop_id",
        into: &payload,
        value: parentPayload.string("desktop_id")
          .ifBlank(server?.string("desktop_id") ?? "")
          .ifBlank(server?.string("id") ?? "")
          .ifBlank(link?.desktopId ?? "")
      )
      inheritConnectorValue(
        "desktop_name",
        into: &payload,
        value: parentPayload.string("desktop_name")
          .ifBlank(server?.string("desktop_name") ?? "")
          .ifBlank(server?.string("name") ?? "")
          .ifBlank(link?.desktopName ?? "SignalASI Desktop")
      )
      inheritConnectorValue(
        "desktop_fingerprint",
        into: &payload,
        value: parentPayload.string("desktop_fingerprint")
          .ifBlank(parentPayload.string("identity_key_sha256"))
          .ifBlank(parentPayload.string("identity_fingerprint"))
          .ifBlank(server?.string("desktop_fingerprint") ?? "")
          .ifBlank(server?.string("identity_key_sha256") ?? "")
          .ifBlank(server?.string("identity_fingerprint") ?? "")
          .ifBlank(server?.string("fingerprint") ?? "")
          .ifBlank(link?.desktopFingerprint ?? "")
      )
      inheritConnectorValue(
        "desktop_access_profile",
        into: &payload,
        value: parentPayload.string("desktop_access_profile")
          .ifBlank(access?.profile ?? "")
          .ifBlank(link?.accessProfile ?? "")
      )
      inheritConnectorValue(
        "mqtt_topic",
        into: &payload,
        value: parentPayload.string("mqtt_topic").ifBlank(link?.routes.upTopic ?? "")
      )
      if payload.stringArray("desktop_access_scopes").isEmpty {
        let inheritedScopes = parentPayload.stringArray("desktop_access_scopes")
        let fallbackScopes = Array(access?.scopes ?? link?.accessScopes ?? []).sorted()
        let scopes = inheritedScopes.isEmpty ? fallbackScopes : inheritedScopes
        if !scopes.isEmpty {
          payload["desktop_access_scopes"] = scopes
        }
      }
      [
        "capabilities",
        "capabilities_hash",
        "protocols",
        "protocol_features",
        "provider_profile",
        "adapter",
        "reputation"
      ].forEach { key in
        if payload[key] == nil, let value = parentPayload[key] {
          payload[key] = value
        }
      }
      if payload.string("status").isEmpty {
        inheritConnectorValue("status", into: &payload, value: parentPayload.string("status"))
      }
      if payload.string("detail").isEmpty {
        inheritConnectorValue(
          "detail",
          into: &payload,
          value: parentPayload.string("detail")
            .ifBlank(parentPayload.string("setup_detail"))
            .ifBlank(parentPayload.string("setup"))
        )
      }
      if payload.string("setup_next_step").isEmpty {
        inheritConnectorValue(
          "setup_next_step",
          into: &payload,
          value: parentPayload.string("setup_next_step").ifBlank(parentPayload.string("setup"))
        )
      }
      return payload
    }
  }

  private func singleDesktopAgentPayload(from object: [String: Any], link: ServerLink?) -> [String: Any]? {
    let type = normalizedAgentQRCodeValue(object.string("type"))
    let contactType = normalizedAgentQRCodeValue(object.string("contact_type"))
    let kind = normalizedAgentQRCodeValue(object.string("kind").ifBlank(object.string("agent_kind")))
    let agentId = desktopAgentId(from: object)
    let hasAgentType = [
      "agent",
      "agent_contact",
      "signalasi_agent",
      "signalasi_agent_contact"
    ].contains(type) ||
      contactType == "agent" ||
      !object.string("agent_id").isEmpty ||
      !object.string("mobile_contact_id").isEmpty ||
      kind.contains("agent") ||
      kind.contains("model") ||
      kind.contains("cli")
    let rawDesktopId = object.string("desktop_id").ifBlank(desktopId(fromRawAgentId: object.string("id")))
    let hasDesktopContext = !rawDesktopId.isEmpty ||
      !object.string("desktop_fingerprint").isEmpty ||
      !object.string("identity_key_sha256").isEmpty ||
      !object.string("identity_fingerprint").isEmpty ||
      link != nil
    guard !agentId.isEmpty, hasAgentType, hasDesktopContext else {
      return nil
    }

    var payload = object
    inheritConnectorValue("desktop_id", into: &payload, value: rawDesktopId.ifBlank(link?.desktopId ?? ""))
    inheritConnectorValue("desktop_name", into: &payload, value: link?.desktopName ?? "SignalASI Desktop")
    inheritConnectorValue("desktop_fingerprint", into: &payload, value: link?.desktopFingerprint ?? "")
    inheritConnectorValue("desktop_access_profile", into: &payload, value: link?.accessProfile ?? "")
    inheritConnectorValue("mqtt_topic", into: &payload, value: link?.routes.upTopic ?? "")
    inheritConnectorValue("mqtt_inbox_topic", into: &payload, value: link?.routes.downTopic ?? "")
    if payload.stringArray("desktop_access_scopes").isEmpty {
      let scopes = Array(link?.accessScopes ?? []).sorted()
      if !scopes.isEmpty {
        payload["desktop_access_scopes"] = scopes
      }
    }
    return payload
  }

  private func serverLink(forConnectorPayload payload: [String: Any]) -> ServerLink? {
    let desktopId = payload.string("desktop_id")
    if !desktopId.isEmpty, let link = serverLinks.first(where: { $0.desktopId == desktopId }) {
      return link
    }
    let fingerprint = desktopFingerprint(from: payload, link: nil).lowercased()
    if !fingerprint.isEmpty,
       let link = serverLinks.first(where: { $0.desktopFingerprint.lowercased() == fingerprint }) {
      return link
    }
    return nil
  }

  private func singleDesktopFallbackLink(for payload: [String: Any]) -> ServerLink? {
    guard desktopId(from: payload, link: nil).isEmpty,
          desktopFingerprint(from: payload, link: nil).isEmpty,
          payload.string("server_route_id").isEmpty else {
      return nil
    }
    let pairedLinks = serverLinks.filter(\.paired)
    if pairedLinks.count == 1 {
      return pairedLinks[0]
    }
    if serverLinks.count == 1 {
      return serverLinks[0]
    }
    return nil
  }

  private func desktopId(from payload: [String: Any], link: ServerLink?) -> String {
    payload.string("desktop_id")
      .ifBlank(desktopId(fromRawAgentId: payload.string("id")))
      .ifBlank(link?.desktopId ?? "")
      .ifBlank(desktopId(fromFingerprint: desktopFingerprint(from: payload, link: link)))
  }

  private func desktopId(fromRawAgentId rawId: String) -> String {
    guard rawId.hasPrefix("desktop_"), let separator = rawId.firstIndex(of: ":") else { return "" }
    return String(rawId[..<separator])
  }

  private func desktopId(fromFingerprint fingerprint: String) -> String {
    let normalized = fingerprint
      .replacingOccurrences(of: ":", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalized.isEmpty else { return "" }
    return "desktop_\(String(normalized.prefix(16)))"
  }

  private func desktopFingerprint(from payload: [String: Any], link: ServerLink?) -> String {
    payload.string("desktop_fingerprint")
      .ifBlank(payload.string("identity_key_sha256"))
      .ifBlank(payload.string("identity_fingerprint"))
      .ifBlank(link?.desktopFingerprint ?? "")
  }

  private func inheritConnectorValue(_ key: String, into payload: inout [String: Any], value: String) {
    guard payload.string(key).isEmpty, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }
    payload[key] = value
  }

  private func desktopAgentId(from payload: [String: Any]) -> String {
    payload.string("agent_id")
      .ifBlank(payload.string("mobile_contact_id"))
      .ifBlank(payload.string("id").split(separator: ":").last.map(String.init) ?? "")
  }

  private func normalizedAgentQRCodeValue(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func connectorCapabilities(from payload: [String: Any]) -> [String] {
    let adapter = payload.dictionary("adapter")
    return normalizedStrings(
      payload.stringArray("capabilities").ifEmpty(adapter?.stringArray("capabilities") ?? [])
    )
  }

  private func connectorProtocols(from payload: [String: Any]) -> [String] {
    let adapter = payload.dictionary("adapter")
    return normalizedStrings(
      payload.stringArray("protocols").ifEmpty(adapter?.stringArray("protocols") ?? [])
    )
  }

  private func connectorProtocolFeatures(from payload: [String: Any]) -> [String] {
    let adapter = payload.dictionary("adapter")
    return normalizedStrings(
      payload.stringArray("protocol_features").ifEmpty(adapter?.stringArray("features") ?? [])
    )
  }

  private func connectorAdapterType(from payload: [String: Any]) -> String {
    let adapter = payload.dictionary("adapter")
    return payload.string("adapter_type")
      .ifBlank(adapter?.string("adapter_type") ?? "")
      .ifBlank(adapter?.string("type") ?? "")
      .ifBlank(payload.string("kind"))
      .ifBlank(payload.string("agent_kind"))
  }

  private func providerProfileJSON(from payload: [String: Any]) -> Data? {
    guard let profile = payload.dictionary("provider_profile"),
          JSONSerialization.isValidJSONObject(profile) else {
      return nil
    }
    return try? JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys])
  }

  private func capabilitiesHash(for capabilities: [String]) -> String {
    guard !capabilities.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: capabilities, options: []),
          let encoded = String(data: data, encoding: .utf8) else {
      return ""
    }
    return javaHashHex(encoded)
  }

  private func javaHashHex(_ value: String) -> String {
    var hash: Int32 = 0
    for scalar in value.unicodeScalars {
      hash = hash &* 31 &+ Int32(bitPattern: UInt32(scalar.value))
    }
    return String(UInt32(bitPattern: hash), radix: 16)
  }

  private func normalizedStrings(_ values: [String]) -> [String] {
    values
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func agentKind(forFriendRequestType type: String) -> String {
    switch type {
    case "hermes":
      return "desktop-agent"
    case "agent":
      return "contact-agent"
    case "device":
      return "device"
    default:
      return "person"
    }
  }

  private func approvedContactSetupDetail(for request: SignalASIFriendRequest) -> String {
    if !request.setupDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return request.setupDetail
    }
    switch request.type {
    case "agent":
      return request.mqttInboxTopic.isEmpty ? "Verified from Agent QR" : "SignalASI Agent QR verified"
    case "device":
      return request.mqttInboxTopic.isEmpty ? "Verified from device QR" : "SignalASI device QR verified"
    case "hermes":
      return "Hermes identity verified from QR"
    default:
      return request.mqttInboxTopic.isEmpty ? "Verified from contact QR" : "SignalASI contact QR verified"
    }
  }

  private func resetToFreshState() {
    UserDefaultsAgentWorkflowStore.shared.clear()
    UserDefaultsAgentRemoteProactiveEventStore.shared.clear()
    UserDefaultsAgentWorkflowTriggerStore.shared.clear()
    UserDefaultsAgentRemoteProactiveWebhookStore.shared.clear()
    workflowExecutionHistoryStore.clear()
    UserDefaultsAgentSelfModelStore(defaults: defaults, secrets: secrets).clear()
    profile = SignalASIStore.makeProfile(secrets: secrets, account: identityPrivateKeyAccount)
    contacts = [SignalASIContact.hermes(), SignalASIContact.system()]
    friendRequests = []
    messagesByContact = SignalASIStore.defaultMessages()
    readAtByContact = [:]
    serverLinks = []
    voiceSettings = .default
    languagePolicy = .default
    displaySettings = .default
    agentSafetySettings = .default
    agentTaskBudget = .default
    proactiveTasks = []
    proactiveRuns = []
    globalProactiveMessages = []
    globalAgentFeedback = []
    agentTaskRecords = []
    agentConversations = []
    activeAgentConversationId = ""
    agentMemoryItems = []
    agentKnowledgeItems = []
    agentKnowledgeAccessAudit = []
    customDeviceConnectors = []
    homeAssistantSettings = .default
    modelPlannerSettings = .default
    globalAgentSettings = .default
  }


  private func upsert(_ contact: SignalASIContact) {
    if let index = contacts.firstIndex(where: { $0.id == contact.id || $0.signalASIId == contact.signalASIId }) {
      contacts[index] = contact
    } else {
      contacts.append(contact)
    }
  }

  private func lastMessageDate(for contactId: String) -> Date {
    messagesByContact[contactId]?.last?.createdAt ?? .distantPast
  }

  private func contactMatchesSearch(_ contact: SignalASIContact, query: String) -> Bool {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return true }
    let fields = [
      contact.displayName,
      contact.name,
      contact.id,
      contact.signalASIId,
      contact.desktopName,
      contact.cloudProvider,
      contact.setupDetail,
      contact.selectedCloudModel?.modelId ?? ""
    ]
    return fields.contains {
      $0.range(of: normalized, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  private func exportCloudAPISecrets() -> [String: String] {
    var exported: [String: String] = [:]
    for contact in contacts {
      for model in contact.cloudModels {
        if let value = secrets.string(account: model.keychainAccount), !value.isEmpty {
          exported[model.keychainAccount] = value
        }
      }
    }
    return exported
  }

  private func importCloudAPISecrets(_ values: [String: String]) throws {
    for (account, value) in values {
      if value.isEmpty {
        secrets.delete(account: account)
      } else {
        try secrets.setString(value, account: account)
      }
    }
  }

  private func applyCustomDeviceConnectors(_ connectors: [CustomDeviceConnector]) throws {
    var unique: [CustomDeviceConnector] = []
    for connector in connectors.map(\.normalized) {
      unique.removeAll { $0.id == connector.id }
      unique.append(connector)
    }
    let normalized = Array(unique.suffix(CustomDeviceConnector.maximumConnectors))
    let nextIds = Set(normalized.map(\.id))
    for connector in customDeviceConnectors where !nextIds.contains(connector.id) {
      secrets.delete(account: customDeviceAuthTokenAccount(id: connector.id))
    }
    for connector in normalized {
      let account = customDeviceAuthTokenAccount(id: connector.id)
      if connector.authToken.isEmpty {
        secrets.delete(account: account)
      } else {
        try secrets.setString(connector.authToken, account: account)
      }
    }
    customDeviceConnectors = normalized
  }

  private func customDeviceAuthTokenAccount(id: String) -> String {
    "custom_device_connector.\(id).auth_token"
  }
  private func applyHomeAssistantSettings(_ settings: HomeAssistantSettings) throws {
    let next = settings.normalized
    if next.accessToken.isEmpty {
      secrets.delete(account: homeAssistantAccessTokenAccount)
    } else {
      try secrets.setString(next.accessToken, account: homeAssistantAccessTokenAccount)
    }
    homeAssistantSettings = next
  }


  static func nowMillis() -> Int64 {
    millis(Date())
  }




  func save() {
    let state = PersistedState(
      profile: profile,
      contacts: contacts,
      friendRequests: friendRequests,
      messagesByContact: messagesByContact,
      readAtByContact: readAtByContact,
      pinnedContactIds: pinnedContactIds,
      serverLinks: serverLinks,
      voiceSettings: voiceSettings,
      languagePolicy: languagePolicy,
      displaySettings: displaySettings,
      agentSafetySettings: agentSafetySettings,
      agentPreferenceMode: agentPreferenceMode,
      agentTaskBudget: agentTaskBudget,
      proactiveTasks: proactiveTasks,
      proactiveRuns: proactiveRuns,
      globalProactiveMessages: globalProactiveMessages,
      globalAgentFeedback: globalAgentFeedback,
      agentConversations: agentConversations,
      activeAgentConversationId: activeAgentConversationId,
      agentKnowledgeItems: agentKnowledgeItems,
      agentKnowledgeAccessAudit: agentKnowledgeAccessAudit,
      agentTaskRecords: agentTaskRecords,
      customDeviceConnectors: customDeviceConnectors.map(\.withoutAuthToken),
      homeAssistantSettings: homeAssistantSettings.withoutAccessToken,
      modelPlannerSettings: modelPlannerSettings,
      globalAgentSettings: globalAgentSettings
    )
    if let data = try? JSONEncoder.signalASI.encode(state) {
      _ = SignalASIEncryptedStateStore.write(data, defaults: defaults, secrets: secrets)
    }
  }

  private static func makeProfile(secrets: SignalASISecretStore, account: String) -> SignalASIProfile {
    let privateKey: P256.Signing.PrivateKey
    if let saved = secrets.string(account: account),
       let data = Data(base64Encoded: saved),
       let restored = try? P256.Signing.PrivateKey(rawRepresentation: data) {
      privateKey = restored
    } else {
      privateKey = P256.Signing.PrivateKey()
      try? secrets.setString(privateKey.rawRepresentation.base64EncodedString(), account: account)
    }
    let publicData = privateKey.publicKey.rawRepresentation
    let digest = Data(SHA256.hash(data: publicData))
    let signalId = "ios_\(digest.prefix(12).base64URLEncodedString())"
    return SignalASIProfile(
      signalASIId: signalId,
      name: SignalASIDeviceIdentityName.current(signalASIId: signalId),
      identityFingerprint: digest.hexString(),
      identityPublicKey: publicData.base64URLEncodedString()
    )
  }

  private static func defaultMessages() -> [String: [ChatMessage]] {
    [
      "hermes": [
        ChatMessage(
          contactId: "hermes",
          content: "Pair SignalASI Desktop to start a trusted Link conversation.",
          isMine: false,
          isSystem: true
        )
      ]
    ]
  }

  private static func slug(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics
    let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let collapsed = String(scalars)
      .split(separator: "-")
      .joined(separator: "-")
    return collapsed.isEmpty ? "custom" : collapsed
  }
}

private extension JSONEncoder {
  static var signalASI: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }
}

private extension Array where Element == String {
  func ifEmpty(_ fallback: [String]) -> [String] {
    isEmpty ? fallback : self
  }
}

private extension JSONDecoder {
  static var signalASI: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
