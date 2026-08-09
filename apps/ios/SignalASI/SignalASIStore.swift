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
}

@MainActor
final class SignalASIStore: ObservableObject {
  @Published private(set) var profile: SignalASIProfile
  @Published private(set) var contacts: [SignalASIContact]
  @Published private(set) var friendRequests: [SignalASIFriendRequest]
  @Published private(set) var messagesByContact: [String: [ChatMessage]]
  @Published private(set) var readAtByContact: [String: Date]
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
  @Published private(set) var agentTaskRecords: [AgentTaskRecord] {
    didSet { save() }
  }
  @Published private(set) var proactiveTasks: [AgentProactiveTask] {
    didSet { save() }
  }
  @Published private(set) var proactiveRuns: [AgentProactiveRun] {
    didSet { save() }
  }
  @Published private(set) var globalProactiveMessages: [GlobalProactiveMessage] {
    didSet { save() }
  }
  @Published private(set) var globalAgentFeedback: [GlobalAgentFeedback] {
    didSet { save() }
  }
  @Published private(set) var agentConversations: [AgentConversation] {
    didSet { save() }
  }
  @Published private(set) var activeAgentConversationId: String {
    didSet { save() }
  }
  @Published private(set) var agentMemoryItems: [AgentMemoryItem]
  @Published private(set) var agentKnowledgeItems: [AgentKnowledgeItem] {
    didSet { save() }
  }
  @Published private(set) var agentKnowledgeAccessAudit: [AgentKnowledgeAccessAuditEntry] {
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
      self.globalAgentSettings = globalAgentSettings
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      profile = try container.decode(SignalASIProfile.self, forKey: .profile)
      contacts = try container.decode([SignalASIContact].self, forKey: .contacts)
      friendRequests = try container.decodeIfPresent([SignalASIFriendRequest].self, forKey: .friendRequests) ?? []
      messagesByContact = try container.decode([String: [ChatMessage]].self, forKey: .messagesByContact)
      readAtByContact = try container.decodeIfPresent([String: Date].self, forKey: .readAtByContact) ?? [:]
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
  private let memoryDeletionIndex: UserDefaultsAgentMemoryDeletionIndex
  private let agentMemoryStore: UserDefaultsAgentMemoryStore
  private let agentWorkspaceStore: AgentWorkspaceStore
  private let agentPreferenceModeStore: AgentPreferenceModeStore
  private let storageKey = "signalasi-ios-state-v1"
  private let identityPrivateKeyAccount = "identity.p256.private"
  private let homeAssistantAccessTokenAccount = "home_assistant.access_token"

  init(defaults: UserDefaults = .standard, secrets: SignalASISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.secrets = secrets
    let deletionIndex = UserDefaultsAgentMemoryDeletionIndex(defaults: defaults)
    let memoryStore = UserDefaultsAgentMemoryStore(defaults: defaults, deletionIndex: deletionIndex)
    let preferenceModeStore = AgentPreferenceModeStore(defaults: defaults)
    self.memoryDeletionIndex = deletionIndex
    self.agentMemoryStore = memoryStore
    self.agentWorkspaceStore = FileAgentWorkspaceStore()
    self.agentPreferenceModeStore = preferenceModeStore
    if let data = defaults.data(forKey: storageKey),
       let state = try? JSONDecoder.signalASI.decode(PersistedState.self, from: data) {
      profile = state.profile
      contacts = state.contacts
      friendRequests = state.friendRequests
      messagesByContact = state.messagesByContact
      readAtByContact = state.readAtByContact
      serverLinks = state.serverLinks
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
      globalAgentSettings = state.globalAgentSettings
    } else {
      let generatedProfile = SignalASIStore.makeProfile(secrets: secrets, account: identityPrivateKeyAccount)
      profile = generatedProfile
      contacts = [SignalASIContact.hermes(), SignalASIContact.system()]
      friendRequests = []
      messagesByContact = SignalASIStore.defaultMessages()
      readAtByContact = [:]
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

  func visibleContacts(matching query: String) -> [SignalASIContact] {
    visibleContacts.filter { contactMatchesSearch($0, query: query) }
  }

  func contactList(matching query: String) -> [SignalASIContact] {
    contacts
      .filter { !$0.deleted && $0.id != "system" }
      .filter { contactMatchesSearch($0, query: query) }
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
    guard unreadBefore > 0 || readAt > previousReadAt else {
      return unreadBefore
    }
    readAtByContact[contactId] = max(previousReadAt, readAt)
    save()
    return unreadBefore
  }

  func friendRequest(id: String) -> SignalASIFriendRequest? {
    friendRequests.first { $0.id == id }
  }

  func updateProfileName(_ name: String) {
    profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("Me")
    save()
  }

  @discardableResult
  func renameContact(id: String, displayName: String) -> Bool {
    let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty,
          let index = contacts.firstIndex(where: { $0.id == id || $0.signalASIId == id }) else {
      return false
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
    defaults.removeObject(forKey: storageKey)
    defaults.removeObject(forKey: UserDefaultsAgentLearningProposalStore.defaultKey)
    defaults.removeObject(forKey: UserDefaultsAgentSkillStore.defaultKey)
    agentMemoryStore.clear()
    memoryDeletionIndex.clear()
    agentWorkspaceStore.clear()
    FileAgentDataDisclosureStore.destroyPersistentStore()
    resetToFreshState()
    save()
  }

  func exportAgentMemoryItems() -> [AgentMemoryItem] {
    agentMemoryStore.exportItems()
  }

  func agentMemorySnapshot() -> AgentMemorySnapshot {
    agentMemoryStore.snapshot()
  }

  func agentMemoryDeletionTombstones() -> [AgentMemoryDeletionTombstone] {
    memoryDeletionIndex.snapshot()
  }

  func automationTasks() -> [AgentProactiveTask] {
    Self.sortedAutomationTasks(proactiveTasks)
  }

  func automationTask(id taskId: String) -> AgentProactiveTask? {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return proactiveTasks.first { $0.taskId == clean }
  }

  func automationRuns(taskId: String, limit: Int = 50) -> [AgentProactiveRun] {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return proactiveRuns
      .filter { $0.taskId == clean }
      .sorted { $0.scheduledForMillis > $1.scheduledForMillis }
      .prefix(max(0, limit))
      .map { $0 }
  }

  func recentAutomationRuns(limit: Int = 30) -> [AgentProactiveRun] {
    proactiveRuns
      .sorted { $0.scheduledForMillis > $1.scheduledForMillis }
      .prefix(max(0, limit))
      .map { $0 }
  }

  func queuedAutomationRuns(limit: Int = 8) -> [AgentProactiveRun] {
    proactiveRuns
      .filter { $0.status == .queued }
      .sorted { $0.scheduledForMillis < $1.scheduledForMillis }
      .prefix(max(0, limit))
      .map { $0 }
  }

  @discardableResult
  func claimDueAutomationTasks(nowMillis: Int64? = nil) -> Int {
    let now = max(nowMillis ?? Self.nowMillis(), 0)
    var claimed = 0
    for task in automationTasks() {
      guard task.enabled,
            task.nextRunAtMillis > 0,
            task.nextRunAtMillis <= now else {
        continue
      }
      if AgentProactiveTaskScheduler.shouldDisable(task: task, nowMillis: now) {
        guard let disabled = try? AgentProactiveTask(
          taskId: task.taskId,
          name: task.name,
          trigger: task.trigger,
          action: task.action,
          policy: task.policy,
          enabled: false,
          nextRunAtMillis: 0,
          lastRunAtMillis: task.lastRunAtMillis,
          lastStatus: task.lastStatus,
          runCount: task.runCount,
          consecutiveFailures: task.consecutiveFailures,
          revision: task.revision + 1,
          createdAtMillis: task.createdAtMillis,
          updatedAtMillis: now
        ) else {
          continue
        }
        replaceAutomationTask(disabled)
        continue
      }
      guard let due = try? AgentProactiveTaskScheduler.dueOccurrences(task: task, nowMillis: now),
            let scheduledTask = try? AgentProactiveTask(
              taskId: task.taskId,
              name: task.name,
              trigger: task.trigger,
              action: task.action,
              policy: task.policy,
              enabled: task.enabled,
              nextRunAtMillis: due.nextRunAtMillis,
              lastRunAtMillis: task.lastRunAtMillis,
              lastStatus: task.lastStatus,
              runCount: task.runCount,
              consecutiveFailures: task.consecutiveFailures,
              revision: task.revision,
              createdAtMillis: task.createdAtMillis,
              updatedAtMillis: now
            ) else {
        continue
      }

      var updatedTask = scheduledTask
      for occurrence in due.occurrences {
        let isSkipped = occurrence.status == .skipped
        guard let run = try? AgentProactiveRun(
          runId: "ios-proactive-run-\(UUID().uuidString.lowercased())",
          taskId: task.taskId,
          scheduledForMillis: occurrence.scheduledForMillis,
          status: occurrence.status,
          causeJson: "{\"source\":\"scheduler\",\"scheduled_for_millis\":\(occurrence.scheduledForMillis)}",
          startedAtMillis: isSkipped ? now : 0,
          completedAtMillis: isSkipped ? now : 0,
          resultSummary: isSkipped ? "Occurrence skipped by misfire policy." : "Run queued by iOS scheduler."
        ) else {
          continue
        }
        proactiveRuns = Array((proactiveRuns + [run]).suffix(500))
        claimed += 1
        if isSkipped {
          updatedTask = (try? AgentProactiveTaskScheduler.recordOutcome(
            task: updatedTask,
            status: .skipped,
            completedAtMillis: now
          )) ?? updatedTask
        }
      }
      replaceAutomationTask(updatedTask)
    }
    return claimed
  }

  @discardableResult
  func beginAutomationRun(id runId: String, nowMillis: Int64? = nil) -> AgentProactiveRun? {
    let clean = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = proactiveRuns.firstIndex(where: { $0.runId == clean }),
          proactiveRuns[index].status == .queued,
          let task = automationTask(id: proactiveRuns[index].taskId) else {
      return nil
    }
    let active = proactiveRuns.filter {
      $0.taskId == task.taskId && [.running, .waiting, .retrying].contains($0.status)
    }.count
    guard active < task.policy.maxConcurrency else { return nil }
    let now = max(nowMillis ?? Self.nowMillis(), 0)
    guard let running = try? AgentProactiveRun(
      runId: proactiveRuns[index].runId,
      taskId: proactiveRuns[index].taskId,
      scheduledForMillis: proactiveRuns[index].scheduledForMillis,
      status: .running,
      attempt: proactiveRuns[index].attempt,
      causeJson: proactiveRuns[index].causeJson,
      startedAtMillis: now,
      resultSummary: "Run started on iOS."
    ) else {
      return nil
    }
    proactiveRuns[index] = running
    return running
  }

  @discardableResult
  func finishAutomationRun(
    id runId: String,
    status: AgentProactiveRunStatus,
    resultSummary: String,
    errorCode: String = "",
    nowMillis: Int64? = nil
  ) -> Bool {
    let clean = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = proactiveRuns.firstIndex(where: { $0.runId == clean }),
          !proactiveRuns[index].status.terminal,
          let task = automationTask(id: proactiveRuns[index].taskId) else {
      return false
    }
    let now = max(nowMillis ?? Self.nowMillis(), 0)
    guard let finished = try? AgentProactiveRun(
      runId: proactiveRuns[index].runId,
      taskId: proactiveRuns[index].taskId,
      scheduledForMillis: proactiveRuns[index].scheduledForMillis,
      status: status,
      attempt: proactiveRuns[index].attempt,
      causeJson: proactiveRuns[index].causeJson,
      startedAtMillis: proactiveRuns[index].startedAtMillis,
      completedAtMillis: now,
      resultSummary: resultSummary,
      errorCode: errorCode
    ),
    let updatedTask = try? AgentProactiveTaskScheduler.recordOutcome(
      task: task,
      status: status,
      completedAtMillis: now
    ) else {
      return false
    }
    proactiveRuns[index] = finished
    replaceAutomationTask(updatedTask)
    return true
  }

  func makeAutomationTaskDraft(name: String = "", prompt: String = "") -> AgentProactiveTask {
    let now = Self.nowMillis()
    let taskId = "ios-proactive-\(UUID().uuidString.lowercased())"
    return try! AgentProactiveTask(
      taskId: taskId,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("New proactive task"),
      trigger: AgentProactiveTrigger(
        kind: .manual,
        timeZone: TimeZone.autoupdatingCurrent.identifier
      ),
      action: AgentProactiveAction(
        kind: .agent,
        targetId: defaultAutomationAgentTargetId(),
        prompt: prompt
      ),
      createdAtMillis: now,
      updatedAtMillis: now
    )
  }

  @discardableResult
  func saveAutomationTask(_ task: AgentProactiveTask) throws -> AgentProactiveTask {
    let now = Self.nowMillis()
    let existing = automationTask(id: task.taskId)
    var stored = try AgentProactiveTask(
      taskId: task.taskId,
      name: task.name,
      trigger: task.trigger,
      action: task.action,
      policy: task.policy,
      enabled: task.enabled,
      nextRunAtMillis: task.nextRunAtMillis,
      lastRunAtMillis: task.lastRunAtMillis,
      lastStatus: task.lastStatus,
      runCount: task.runCount,
      consecutiveFailures: task.consecutiveFailures,
      revision: existing == nil ? max(task.revision, 1) : max(existing?.revision ?? task.revision, task.revision) + 1,
      createdAtMillis: existing?.createdAtMillis ?? (task.createdAtMillis > 0 ? task.createdAtMillis : now),
      updatedAtMillis: now
    )
    let nextRun = stored.enabled ? (try AgentProactiveTaskScheduler.initialNextRun(task: stored, nowMillis: now)) : 0
    stored = try AgentProactiveTask(
      taskId: stored.taskId,
      name: stored.name,
      trigger: stored.trigger,
      action: stored.action,
      policy: stored.policy,
      enabled: stored.enabled,
      nextRunAtMillis: nextRun,
      lastRunAtMillis: stored.lastRunAtMillis,
      lastStatus: stored.lastStatus,
      runCount: stored.runCount,
      consecutiveFailures: stored.consecutiveFailures,
      revision: stored.revision,
      createdAtMillis: stored.createdAtMillis,
      updatedAtMillis: stored.updatedAtMillis
    )
    proactiveTasks.removeAll { $0.taskId == stored.taskId }
    proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [stored]).prefix(200))
    return stored
  }

  @discardableResult
  func setAutomationTaskEnabled(id taskId: String, enabled: Bool) throws -> Bool {
    guard var task = automationTask(id: taskId) else { return false }
    task = try AgentProactiveTask(
      taskId: task.taskId,
      name: task.name,
      trigger: task.trigger,
      action: task.action,
      policy: task.policy,
      enabled: enabled,
      nextRunAtMillis: enabled ? try AgentProactiveTaskScheduler.initialNextRun(task: task, nowMillis: Self.nowMillis()) : 0,
      lastRunAtMillis: task.lastRunAtMillis,
      lastStatus: task.lastStatus,
      runCount: task.runCount,
      consecutiveFailures: task.consecutiveFailures,
      revision: task.revision + 1,
      createdAtMillis: task.createdAtMillis,
      updatedAtMillis: Self.nowMillis()
    )
    proactiveTasks.removeAll { $0.taskId == task.taskId }
    proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [task]).prefix(200))
    return true
  }

  @discardableResult
  func deleteAutomationTask(id taskId: String) -> Bool {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let before = proactiveTasks.count
    proactiveTasks.removeAll { $0.taskId == clean }
    proactiveRuns.removeAll { $0.taskId == clean }
    return before != proactiveTasks.count
  }

  @discardableResult
  func triggerAutomationTaskNow(id taskId: String) throws -> AgentProactiveRun {
    guard let task = automationTask(id: taskId) else {
      throw AgentProactiveTaskError.invalid("Proactive task not found")
    }
    let now = Self.nowMillis()
    let run = try AgentProactiveRun(
      runId: "ios-proactive-run-\(UUID().uuidString.lowercased())",
      taskId: task.taskId,
      scheduledForMillis: now,
      status: .queued,
      causeJson: "{\"source\":\"manual\"}",
      resultSummary: "Run queued on iOS scheduler."
    )
    let updatedTask = try AgentProactiveTask(
      taskId: task.taskId,
      name: task.name,
      trigger: task.trigger,
      action: task.action,
      policy: task.policy,
      enabled: task.enabled,
      nextRunAtMillis: task.nextRunAtMillis,
      lastRunAtMillis: task.lastRunAtMillis,
      lastStatus: .queued,
      runCount: task.runCount,
      consecutiveFailures: task.consecutiveFailures,
      revision: task.revision,
      createdAtMillis: task.createdAtMillis,
      updatedAtMillis: now
    )
    proactiveRuns = Array((proactiveRuns + [run]).suffix(500))
    replaceAutomationTask(updatedTask)
    return run
  }

  @discardableResult
  func cancelAutomationRun(id runId: String) -> Bool {
    let clean = runId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let index = proactiveRuns.firstIndex(where: { $0.runId == clean }),
          !proactiveRuns[index].status.terminal else {
      return false
    }
    let run = proactiveRuns[index]
    let cancelled = try? AgentProactiveRun(
      runId: run.runId,
      taskId: run.taskId,
      scheduledForMillis: run.scheduledForMillis,
      status: .cancelled,
      attempt: run.attempt,
      causeJson: run.causeJson,
      startedAtMillis: run.startedAtMillis,
      completedAtMillis: Self.nowMillis(),
      resultSummary: run.resultSummary,
      errorCode: run.errorCode,
      linkedExecutionId: run.linkedExecutionId,
      teamRunId: run.teamRunId
    )
    guard let cancelled else { return false }
    var runs = proactiveRuns
    runs[index] = cancelled
    proactiveRuns = runs
    return true
  }

  func globalProactiveInboxItems(limit: Int = 50) -> [GlobalProactiveInboxItem] {
    GlobalProactiveInboxPolicy.project(
      messages: globalProactiveMessages,
      feedback: globalAgentFeedback,
      limit: limit
    )
  }

  func globalProactiveInboxNewCount(limit: Int = 100) -> Int {
    GlobalProactiveInboxPolicy.newCount(globalProactiveInboxItems(limit: limit))
  }

  @discardableResult
  func appendGlobalProactiveMessage(_ message: GlobalProactiveMessage) -> GlobalProactiveMessage {
    let now = Self.nowMillis()
    var stored = message
    if stored.createdAtMillis <= 0 {
      stored.createdAtMillis = now
    }
    if stored.status == .delivered && stored.deliveredAtMillis <= 0 {
      stored.deliveredAtMillis = now
    }
    globalProactiveMessages.removeAll { $0.id == stored.id }
    globalProactiveMessages = Array((globalProactiveMessages + [stored]).suffix(500))
    return stored
  }

  @discardableResult
  func markGlobalProactiveInboxViewed(_ item: GlobalProactiveInboxItem) -> Bool {
    let updated = GlobalProactiveInboxPolicy.markViewed(
      messages: globalProactiveMessages,
      messageIds: item.messageIds,
      nowMillis: Self.nowMillis()
    )
    guard updated != globalProactiveMessages else { return false }
    globalProactiveMessages = Array(updated.suffix(500))
    return true
  }

  @discardableResult
  func recordGlobalInsightFeedback(
    inboxItem: GlobalProactiveInboxItem,
    kind: GlobalAgentFeedbackKind
  ) -> Bool {
    let targetIds = inboxItem.messageIds
    guard !targetIds.isEmpty else { return false }
    let now = Self.nowMillis()
    var matched = 0
    var updatedMessages = globalProactiveMessages
    var updatedFeedback = globalAgentFeedback.filter { !targetIds.contains($0.proactiveMessageId) }

    for index in updatedMessages.indices where targetIds.contains(updatedMessages[index].id) {
      matched += 1
      var message = updatedMessages[index]
      message.viewedAtMillis = max(message.viewedAtMillis, now)
      switch kind {
      case .helpful:
        if message.status == .pending || message.status == .notified || message.status == .delivering {
          message.status = .delivered
          message.deliveredAtMillis = max(message.deliveredAtMillis, now)
        }
      case .notRelevant, .tooFrequent:
        message.status = .dismissed
      }
      updatedMessages[index] = message
      updatedFeedback.append(
        GlobalAgentFeedback(
          proactiveMessageId: message.id,
          deliveryGroupId: message.deliveryGroupId.ifBlank(inboxItem.key),
          conversationId: message.deliveredConversationId
            .ifBlank(inboxItem.destinationConversationId)
            .ifBlank(message.sourceConversationId),
          topic: message.topic.ifBlank(inboxItem.topic),
          target: message.target,
          kind: kind,
          createdAtMillis: now
        )
      )
    }

    guard matched > 0 else { return false }
    globalProactiveMessages = Array(updatedMessages.suffix(500))
    globalAgentFeedback = Array(updatedFeedback.suffix(500))
    return true
  }

  func agentSessions(includeArchived: Bool = false) -> [AgentConversation] {
    mergedAgentConversations()
      .filter { includeArchived || $0.status == .active }
  }

  func searchAgentSessions(_ query: String, includeArchived: Bool = false) -> [AgentConversation] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return agentSessions(includeArchived: includeArchived)
    }
    return agentSessions(includeArchived: includeArchived)
      .filter { conversation in
        [
          conversation.title,
          conversation.summary,
          conversation.selectedModelOrAgent,
          conversation.contextPolicy,
          conversation.id
        ].contains {
          $0.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
  }

  func agentSession(id conversationId: String) -> AgentConversation? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return mergedAgentConversations().first { $0.id == clean }
  }

  @discardableResult
  func createAgentSession(title: String = "") -> AgentConversation {
    let now = Self.nowMillis()
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("New session")
    let session = AgentConversation(
      id: "ios-agent-\(UUID().uuidString.lowercased())",
      title: cleanTitle,
      createdAt: now,
      updatedAt: now,
      selectedModelOrAgent: contact(id: "hermes")?.displayName ?? "Automatic"
    )
    persistAgentConversation(session)
    activeAgentConversationId = session.id
    return session
  }

  @discardableResult
  func switchAgentSession(_ conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var session = agentSession(id: clean) else { return false }
    if session.status == .archived {
      session.status = .active
      session.updatedAt = Self.nowMillis()
      persistAgentConversation(session)
    }
    activeAgentConversationId = session.id
    return true
  }

  @discardableResult
  func renameAgentSession(id conversationId: String, title: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank(conversation.title)
    }
  }

  @discardableResult
  func setAgentSessionPinned(id conversationId: String, pinned: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.pinned = pinned }
  }

  @discardableResult
  func setAgentSessionPrivateMode(id conversationId: String, privateMode: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.privateMode = privateMode }
  }

  @discardableResult
  func setAgentSessionTrackingPaused(id conversationId: String, paused: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.trackingPaused = paused }
  }

  @discardableResult
  func setAgentSessionContextPolicy(id conversationId: String, policy: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.contextPolicy = ["minimal", "balanced", "extended"].contains(policy) ? policy : "balanced"
    }
  }

  @discardableResult
  func setAgentSessionSelectedModelOrAgent(id conversationId: String, label: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.selectedModelOrAgent = label.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank("Automatic")
    }
  }

  @discardableResult
  func updateAgentSessionSummary(id conversationId: String, summary: String) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  @discardableResult
  func archiveAgentSession(id conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let shouldClearActive = activeAgentConversationId == clean
    let changed = mutateAgentConversation(id: clean) { conversation in
      conversation.status = .archived
    }
    if changed && shouldClearActive {
      activeAgentConversationId = ""
    }
    return changed
  }

  @discardableResult
  func restoreAgentSession(id conversationId: String) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.status = .active }
  }

  @discardableResult
  func deleteAgentSession(id conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let beforeConversations = agentConversations.count
    agentConversations.removeAll { $0.id == clean }
    var removedMessages = 0
    for contactId in Array(messagesByContact.keys) {
      guard var messages = messagesByContact[contactId] else { continue }
      let before = messages.count
      messages.removeAll { $0.conversationId == clean }
      removedMessages += before - messages.count
      if messages.isEmpty {
        messagesByContact.removeValue(forKey: contactId)
      } else {
        messagesByContact[contactId] = messages
      }
    }
    if activeAgentConversationId == clean {
      activeAgentConversationId = agentSessions().first?.id ?? ""
    }
    guard beforeConversations != agentConversations.count || removedMessages > 0 else { return false }
    save()
    return true
  }

  func agentSessionMessages(_ conversationId: String) -> [ChatMessage] {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return messagesByContact.values
      .flatMap { $0 }
      .filter { $0.conversationId == clean }
      .sorted { $0.createdAt < $1.createdAt }
  }

  func agentSessionMetrics(_ conversationId: String) -> AgentSessionMetrics {
    let messages = agentSessionMessages(conversationId)
    let turnIds = Set(messages.map(\.turnId).filter { !$0.isBlank })
    let userTurns = messages.filter { $0.isMine && !$0.isSystem }.count
    let estimatedTokens = messages.reduce(0) { partial, message in
      partial + max(1, message.content.count / 4)
    }
    return AgentSessionMetrics(
      turnCount: max(turnIds.count, userTurns),
      messageCount: messages.count,
      taskCount: messages.filter { message in
        message.deliveryTrace.contains { $0.stage == "agent_started" || $0.stage == "agent_replied" }
      }.count,
      estimatedContextTokens: estimatedTokens,
      inputTokens: agentSession(id: conversationId)?.inputTokens ?? 0,
      outputTokens: agentSession(id: conversationId)?.outputTokens ?? 0,
      costMicros: agentSession(id: conversationId)?.costMicros ?? 0,
      lastResponseLatencyMillis: lastAgentResponseLatencyMillis(messages)
    )
  }

  var agentKnowledgeStats: AgentKnowledgeStats {
    let sources = Set(agentKnowledgeItems.map(agentKnowledgeSourceKey))
    return AgentKnowledgeStats(
      itemCount: agentKnowledgeItems.count,
      sourceCount: sources.count,
      lastUpdatedAtMillis: agentKnowledgeItems.map(\.updatedAtMillis).max() ?? 0
    )
  }

  func agentKnowledgeSourceGroups() -> [AgentKnowledgeSourceGroup] {
    Dictionary(grouping: agentKnowledgeItems, by: agentKnowledgeSourceKey)
      .values
      .map { items in
        let sorted = items.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        let latest = sorted.first ?? items[0]
        return AgentKnowledgeSourceGroup(
          source: agentKnowledgeSourceKey(latest),
          title: latest.title.replacingOccurrences(of: "\\s+\\[[0-9]+/[0-9]+\\]$", with: "", options: .regularExpression),
          itemIds: sorted.map(\.id),
          chunkCount: sorted.count,
          cloudAccess: latest.cloudAccess,
          agentAccess: latest.agentAccess,
          allowedAgentIds: latest.allowedAgentIds,
          updatedAtMillis: sorted.map(\.updatedAtMillis).max() ?? latest.updatedAtMillis
        )
      }
      .sorted { $0.updatedAtMillis > $1.updatedAtMillis }
  }

  @discardableResult
  func importAgentKnowledge(
    title: String,
    content: String,
    source: String = "",
    kind: AgentKnowledgeKind = .document,
    tags: [String] = []
  ) -> [AgentKnowledgeItem] {
    let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanContent.isEmpty else { return [] }
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("Private knowledge")
    let sourceKey = source.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("local:\(UUID().uuidString)")
    let chunks = chunkKnowledgeContent(cleanContent)
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    let items = chunks.enumerated().map { index, chunk in
      AgentKnowledgeItem(
        kind: kind,
        title: chunks.count > 1 ? "\(cleanTitle) [\(index + 1)/\(chunks.count)]" : cleanTitle,
        content: chunk,
        source: sourceKey,
        tags: tags,
        summary: String(chunk.prefix(700)),
        cloudAccess: .summaryOnly,
        agentAccess: .localOnly,
        chunkIndex: index,
        chunkCount: chunks.count,
        updatedAtMillis: now
      )
    }
    agentKnowledgeItems = Array((agentKnowledgeItems + items).suffix(500))
    return items
  }

  @discardableResult
  func replaceAgentKnowledgeSource(
    title: String,
    content: String,
    source: String,
    kind: AgentKnowledgeKind = .document,
    tags: [String] = []
  ) -> [AgentKnowledgeItem] {
    let sourceKey = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if !sourceKey.isEmpty {
      let existingIds = agentKnowledgeItems.filter { $0.source == sourceKey }.map(\.id)
      if !existingIds.isEmpty {
        _ = deleteAgentKnowledgeSource(itemIds: existingIds)
      }
    }
    return importAgentKnowledge(title: title, content: content, source: sourceKey, kind: kind, tags: tags)
  }

  @discardableResult
  func upsertAgentKnowledge(_ item: AgentKnowledgeItem) -> AgentKnowledgeItem {
    agentKnowledgeItems.removeAll { $0.id == item.id }
    agentKnowledgeItems = Array((agentKnowledgeItems + [item]).suffix(500))
    return item
  }

  @discardableResult
  func updateAgentKnowledgeSourceAccess(
    itemIds: [String],
    cloudAccess: AgentKnowledgeCloudAccess,
    agentAccess: AgentKnowledgeAgentAccess,
    allowedAgentIds: [String] = []
  ) -> Int {
    let ids = Set(itemIds)
    var changed = 0
    agentKnowledgeItems = agentKnowledgeItems.map { item in
      guard ids.contains(item.id) else { return item }
      changed += 1
      return AgentKnowledgeItem(
        id: item.id,
        kind: item.kind,
        title: item.title,
        content: item.content,
        source: item.source,
        tags: item.tags,
        summary: item.summary,
        cloudAccess: cloudAccess,
        agentAccess: agentAccess,
        allowedAgentIds: allowedAgentIds,
        chunkIndex: item.chunkIndex,
        chunkCount: item.chunkCount,
        updatedAtMillis: Int64(Date().timeIntervalSince1970 * 1_000)
      )
    }
    return changed
  }

  @discardableResult
  func deleteAgentKnowledgeSource(itemIds: [String]) -> Int {
    let ids = Set(itemIds)
    let before = agentKnowledgeItems.count
    agentKnowledgeItems.removeAll { ids.contains($0.id) }
    return before - agentKnowledgeItems.count
  }

  func searchAgentKnowledge(_ query: String, limit: Int = 24) -> [AgentKnowledgeHit] {
    let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanQuery.isEmpty else { return [] }
    let tokens = knowledgeTokens(cleanQuery)
    return agentKnowledgeItems
      .compactMap { item -> AgentKnowledgeHit? in
        let score = knowledgeScore(item, query: cleanQuery, tokens: tokens)
        guard score > 0 else { return nil }
        let matchedTerms = knowledgeMatchedTerms(item, query: cleanQuery, tokens: tokens)
        return AgentKnowledgeHit(
          item: item,
          score: min(score / 24.0, 1.0),
          excerpt: knowledgeExcerpt(item.content, query: cleanQuery, tokens: tokens),
          matchedTerms: matchedTerms
        )
      }
      .sorted {
        if $0.score != $1.score { return $0.score > $1.score }
        return $0.item.updatedAtMillis > $1.item.updatedAtMillis
      }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func recordAgentKnowledgeSearch(query: String, hits: [AgentKnowledgeHit], targetId: String = "agent-knowledge-local") {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let sourceCount = Set(hits.map { agentKnowledgeSourceKey($0.item) }).count
    let entry = AgentKnowledgeAccessAuditEntry(
      queryHash: deterministicHash(query),
      targetId: targetId,
      itemIdHashes: hits.map { deterministicHash($0.item.id) },
      sourceCount: sourceCount,
      evidenceModes: hits.isEmpty ? [] : [.full],
      blockedMatchCount: 0
    )
    agentKnowledgeAccessAudit = Array((agentKnowledgeAccessAudit + [entry]).suffix(100))
  }

  func recentAgentTasks(limit: Int = 20) -> [AgentTaskRecord] {
    mergedAgentTaskRecords()
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func searchAgentTasks(_ query: String, limit: Int = 50) -> [AgentTaskRecord] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return recentAgentTasks(limit: limit)
    }
    return mergedAgentTaskRecords()
      .filter { task in
        [
          task.goal,
          task.taskId,
          task.sessionId,
          task.targetTitle,
          task.routeKind.rawValue,
          task.phase.rawValue,
          task.result,
          task.verification,
          task.outputFiles.joined(separator: " "),
          task.executionLog.joined(separator: " ")
        ].contains {
          $0.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func agentTasks(forSession sessionId: String, limit: Int = 50) -> [AgentTaskRecord] {
    let clean = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return mergedAgentTaskRecords()
      .filter { $0.sessionId == clean }
      .prefix(max(limit, 0))
      .map { $0 }
  }

  func agentTask(id taskId: String) -> AgentTaskRecord? {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return mergedAgentTaskRecords().first { $0.taskId == clean }
  }

  @discardableResult
  func upsertAgentTask(_ record: AgentTaskRecord) -> AgentTaskRecord {
    let clean = record.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return record }
    var updated = record
    updated.taskId = clean
    var items = agentTaskRecords.filter { $0.taskId != clean }
    items.append(updated)
    agentTaskRecords = Array(Self.sortedAgentTasks(items).prefix(200))
    return updated
  }

  @discardableResult
  func deleteAgentTask(id taskId: String) -> Bool {
    let clean = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return false }
    let before = agentTaskRecords.count
    agentTaskRecords.removeAll { $0.taskId == clean }
    var deletedWorkspace = false
    for workspace in agentWorkspaceStore.list() where workspace.taskId == clean {
      if (try? agentWorkspaceStore.delete(workspace.workspaceId, expectedRevision: nil)) == true {
        deletedWorkspace = true
      }
    }
    if before == agentTaskRecords.count && !deletedWorkspace {
      return false
    }
    save()
    return true
  }

  @discardableResult
  func deleteAgentTasks(ids taskIds: Set<String>) -> Int {
    let cleanIds = Set(taskIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    guard !cleanIds.isEmpty else { return 0 }
    let before = agentTaskRecords.count
    agentTaskRecords.removeAll { cleanIds.contains($0.taskId) }
    var deleted = before - agentTaskRecords.count
    for workspace in agentWorkspaceStore.list() where cleanIds.contains(workspace.taskId) {
      if (try? agentWorkspaceStore.delete(workspace.workspaceId, expectedRevision: nil)) == true {
        deleted += 1
      }
    }
    if deleted > 0 {
      save()
    }
    return deleted
  }

  @discardableResult
  func rebindAgentTasks(sourceSessionId: String, targetSessionId: String) -> Int {
    let source = sourceSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    let target = targetSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, !target.isEmpty, source != target else { return 0 }
    var changed = 0
    agentTaskRecords = agentTaskRecords.map { record in
      guard record.sessionId == source else { return record }
      changed += 1
      var updated = record
      updated.sessionId = target
      return updated
    }
    return changed
  }

  @discardableResult
  func rememberAgentMemory(_ item: AgentMemoryItem) -> AgentMemoryWriteResult {
    let result = agentMemoryStore.remember(item)
    agentMemoryItems = agentMemoryStore.exportItems()
    return result
  }

  @discardableResult
  func updateAgentMemory(id itemId: String, value: String, key: String) -> AgentMemoryWriteResult? {
    let result = agentMemoryStore.update(itemId: itemId, value: value, key: key)
    if result != nil {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return result
  }

  @discardableResult
  func setAgentMemoryImportant(id itemId: String, important: Bool) -> Bool {
    let changed = agentMemoryStore.setImportant(itemId: itemId, important: important)
    if changed {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return changed
  }

  @discardableResult
  func resolveAgentMemoryConflict(groupId: String, selectedItemId: String, mergedValue: String?) -> AgentMemoryItem? {
    let resolved = agentMemoryStore.resolveConflict(
      groupId: groupId,
      selectedItemId: selectedItemId,
      mergedValue: mergedValue
    )
    if resolved != nil {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return resolved
  }

  @discardableResult
  func replaceAgentMemoryItems(_ items: [AgentMemoryItem]) -> Int {
    let count = agentMemoryStore.replaceAll(items)
    agentMemoryItems = agentMemoryStore.exportItems()
    return count
  }

  @discardableResult
  func deleteAgentMemory(id itemId: String, deletedAtMillis: Int64 = AgentMemoryClock.nowMillis()) -> Bool {
    let deleted = agentMemoryStore.deleteById(itemId, deletedAtMillis: deletedAtMillis)
    if deleted {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return deleted
  }

  func updateVoiceSettings(_ mutate: (inout VoiceSettings) -> Void) {
    var next = voiceSettings
    mutate(&next)
    voiceSettings = next.normalized
  }

  func updateLanguagePolicy(_ mutate: (inout LanguagePolicySettings) -> Void) {
    var next = languagePolicy
    mutate(&next)
    next = LanguagePolicySettings(
      interfaceLanguage: next.interfaceLanguage,
      responseLanguage: next.responseLanguage,
      asrLanguage: next.asrLanguage,
      ttsLanguage: next.ttsLanguage
    )
    languagePolicy = next
    if voiceSettings.preferredLocaleIdentifier != next.asrLocaleIdentifier {
      updateVoiceSettings {
        $0.preferredLocaleIdentifier = next.asrLocaleIdentifier
      }
    }
    let matchingVoice = LanguagePolicySettings.microsoftVoice(
      languageTag: next.ttsLanguage,
      configuredVoice: voiceSettings.microsoftVoice
    )
    if voiceSettings.microsoftVoice != matchingVoice {
      updateVoiceSettings {
        $0.microsoftVoice = matchingVoice
      }
    }
  }

  func updateDisplaySettings(_ mutate: (inout AppDisplaySettings) -> Void) {
    var next = displaySettings
    mutate(&next)
    displaySettings = AppDisplaySettings(textScale: next.textScale)
  }

  func updateAgentSafetySettings(_ mutate: (inout AgentSafetySettings) -> Void) {
    var next = agentSafetySettings
    mutate(&next)
    agentSafetySettings = next
  }

  func updateAgentPreferenceMode(_ mode: AgentPreferenceMode) {
    let profile = AgentPreferenceModePolicy.profile(mode)
    agentPreferenceMode = mode
    updateAgentSafetySettings {
      $0.taskExecutionMode = profile.taskExecutionMode
      $0.permissionMode = profile.permissionMode
      $0.highRiskGuard = profile.highRiskGuard
    }
  }

  func selectAgentTaskBudgetProfile(_ profile: AgentTaskBudgetProfile) {
    agentTaskBudget = AgentTaskBudget.forProfile(profile)
  }

  func updateAgentTaskBudget(_ mutate: (inout AgentTaskBudget) -> Void) {
    var next = agentTaskBudget
    mutate(&next)
    next.profile = .custom
    agentTaskBudget = next.normalized
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
  func updateModelPlannerSettings(_ mutate: (inout AgentModelPlannerSettings) -> Void) {
    var next = modelPlannerSettings
    mutate(&next)
    modelPlannerSettings = next.normalized
  }

  func updateGlobalAgentSettings(_ mutate: (inout GlobalAgentSettings) -> Void) {
    var next = globalAgentSettings
    mutate(&next)
    globalAgentSettings = next.normalized
  }

  @discardableResult
  func appendOutgoing(_ content: String, to contactId: String, status: ChatDeliveryStatus = .queued) -> ChatMessage {
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
      turnId: messageId.uuidString
    )
    messagesByContact[contactId, default: []].append(message)
    recordAgentConversationActivity(conversationId: conversationId, contactId: contactId, content: content, at: createdAt)
    save()
    return message
  }

  @discardableResult
  func appendIncoming(
    _ content: String,
    from contactId: String,
    remoteMessageId: String = "",
    status: ChatDeliveryStatus = .delivered,
    traceStage: String = "received",
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
      deliveryTrace: [DeliveryTraceEvent(stage: traceStage)],
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
    detail: String = ""
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
      updatedAt: Date()
    )
    let now = Date()
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
    if contact.selectedCloudModelId.isEmpty ||
       !contact.cloudModels.contains(where: { $0.modelId == contact.selectedCloudModelId }) {
      contact.selectedCloudModelId = contact.cloudModels.first?.modelId ?? model.modelId
    }
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

  @discardableResult
  func importContactQRCodeAsFriendRequest(_ contents: String, now: Date = Date()) throws -> SignalASIFriendRequest {
    let request = try SignalASIContactExchange.importContactQRCode(contents, now: now)
    return addFriendRequest(request, now: now)
  }

  @discardableResult
  func addFriendRequest(_ request: SignalASIFriendRequest, now: Date = Date()) -> SignalASIFriendRequest {
    let existingContact = contact(id: request.signalASIId)
    let wasDeleted = existingContact?.deleted == true || existingContact?.trustState == .deleted
    var stored = request
    stored.id = stored.id.ifBlank("req_\(Int64(now.timeIntervalSince1970 * 1000))")
    stored.status = .pending
    stored.createdAt = now
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
    var next = contact(id: contactId) ?? SignalASIContact(
      id: contactId,
      signalASIId: request.signalASIId,
      name: request.name,
      displayName: request.name,
      type: requestType,
      agentKind: requestAgentKind,
      deliveryMode: .link,
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
    next.deliveryMode = .link
    next.trustState = .verified
    next.desktopId = requestDesktopId
    next.desktopName = request.desktopName
    next.identityFingerprint = request.identityFingerprint
    next.mqttTopic = request.mqttTopic
    next.mqttInboxTopic = request.mqttInboxTopic
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
    return true
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

  func exportBackupPayload(includeContacts: Bool = true, includeMessages: Bool = true) -> SignalASIBackupPayload {
    let cloudSecrets = exportCloudAPISecrets()
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
        includesAutomationTasks: !proactiveTasks.isEmpty || !proactiveRuns.isEmpty || !globalProactiveMessages.isEmpty,
        includesAgentConversations: !agentSessions(includeArchived: true).isEmpty,
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
        proactiveTasks: automationTasks(),
        proactiveRuns: Array(proactiveRuns.suffix(500)),
        globalProactiveMessages: Array(globalProactiveMessages.suffix(500)),
        globalAgentFeedback: Array(globalAgentFeedback.suffix(500)),
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
      messagesByContact = payload.messagesByContact
      readAtByContact = payload.readAtByContact
    }
    if payload.includesAgentData {
      serverLinks = payload.agentData.serverLinks
      voiceSettings = payload.agentData.voiceSettings
      languagePolicy = payload.agentData.languagePolicy
      displaySettings = payload.agentData.displaySettings
      agentSafetySettings = payload.agentData.agentSafetySettings
      agentPreferenceMode = payload.agentData.agentPreferenceMode
      agentTaskBudget = payload.agentData.taskBudget
      try applyCustomDeviceConnectors(payload.agentData.customDeviceConnectors)
      try applyHomeAssistantSettings(payload.agentData.homeAssistantSettings)
      modelPlannerSettings = payload.agentData.modelPlannerSettings
      globalAgentSettings = payload.agentData.globalAgentSettings
      agentMemoryItems = agentMemoryStore.restoreBackupItems(
        payload.agentData.memory,
        tombstones: payload.agentData.memoryDeletionIndex
      )
      agentKnowledgeItems = Array((payload.agentData.knowledge ?? []).suffix(500))
      agentKnowledgeAccessAudit = Array((payload.agentData.knowledgeAccessAudit ?? []).suffix(100))
      agentTaskRecords = Array((payload.agentData.taskHistory ?? []).suffix(200))
      proactiveTasks = Array((payload.agentData.proactiveTasks ?? []).suffix(200))
      proactiveRuns = Array((payload.agentData.proactiveRuns ?? []).suffix(500))
      globalProactiveMessages = Array((payload.agentData.globalProactiveMessages ?? []).suffix(500))
      globalAgentFeedback = Array((payload.agentData.globalAgentFeedback ?? []).suffix(500))
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
  func addServerLink(from pairing: PairingQRCode, rotateClientRoute: Bool = true) throws -> ServerLink {
    let existing = serverLinks.first { $0.desktopId == pairing.desktopId }
    let clientRouteId: String
    if !rotateClientRoute, let existingRouteId = existing?.routes.clientRouteId {
      clientRouteId = existingRouteId
    } else {
      clientRouteId = try SignalASILinkProtocol.newRouteId()
    }
    let routes = SignalASILinkRoutes(serverRouteId: pairing.serverRouteId, clientRouteId: clientRouteId)
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
      guard contacts[contactIndex].desktopId == desktopId,
            contacts[contactIndex].type == "agent" else {
        continue
      }
      contacts[contactIndex].trustState = .unverified
      contacts[contactIndex].setupStatus = "needs_pairing"
      contacts[contactIndex].setupDetail = "Desktop pairing revoked"
      contacts[contactIndex].updatedAt = Date()
    }
    save()
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
        deliveryMode: .link,
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
      contact.deliveryMode = .link
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
    let serverRouteId = payload.string("server_route_id")
    if !serverRouteId.isEmpty, let link = serverLinks.first(where: { $0.routes.serverRouteId == serverRouteId }) {
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

  private func defaultAutomationAgentTargetId() -> String {
    if contacts.contains(where: { !$0.deleted && ($0.id == "codex" || $0.signalASIId == "codex") }) {
      return "codex"
    }
    if contacts.contains(where: { !$0.deleted && ($0.id == "hermes" || $0.signalASIId == "hermes") }) {
      return "hermes"
    }
    return contacts.first(where: { !$0.deleted })?.id ?? "codex"
  }

  private static func sortedAutomationTasks(_ tasks: [AgentProactiveTask]) -> [AgentProactiveTask] {
    tasks.sorted { left, right in
      if left.enabled != right.enabled {
        return left.enabled && !right.enabled
      }
      let leftTime = left.nextRunAtMillis > 0 ? left.nextRunAtMillis : left.updatedAtMillis
      let rightTime = right.nextRunAtMillis > 0 ? right.nextRunAtMillis : right.updatedAtMillis
      if leftTime != rightTime {
        return leftTime > rightTime
      }
      return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }
  }

  private func replaceAutomationTask(_ task: AgentProactiveTask) {
    proactiveTasks.removeAll { $0.taskId == task.taskId }
    proactiveTasks = Array(Self.sortedAutomationTasks(proactiveTasks + [task]).prefix(200))
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

  @discardableResult
  private func mutateAgentConversation(
    id conversationId: String,
    mutate: (inout AgentConversation) -> Void
  ) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var conversation = agentSession(id: clean) else { return false }
    mutate(&conversation)
    conversation.updatedAt = Self.nowMillis()
    persistAgentConversation(conversation)
    return true
  }

  private func persistAgentConversation(_ conversation: AgentConversation) {
    let clean = conversation.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    var updated = conversation
    updated.id = clean
    let items = agentConversations.filter { $0.id != clean } + [updated]
    agentConversations = Array(Self.sortedAgentConversations(items).prefix(200))
  }

  private func mergedAgentConversations() -> [AgentConversation] {
    var byId: [String: AgentConversation] = [:]
    for conversation in agentConversations where !conversation.id.isBlank {
      byId[conversation.id] = conversation
    }
    for contact in contacts where isAgentSessionContact(contact) {
      let conversationId = defaultAgentConversationId(for: contact.id)
      let messages = agentSessionMessages(conversationId)
      guard !messages.isEmpty || contact.id == "hermes" else { continue }
      let createdAt = messages.map { Self.millis($0.createdAt) }.min() ?? Self.nowMillis()
      let updatedAt = messages.map { Self.millis($0.createdAt) }.max() ?? createdAt
      var conversation = byId[conversationId] ?? AgentConversation(
        id: conversationId,
        title: contact.displayName,
        createdAt: createdAt,
        updatedAt: updatedAt,
        selectedModelOrAgent: contact.displayName
      )
      conversation.title = conversation.title.ifBlank(contact.displayName)
      conversation.selectedModelOrAgent = conversation.selectedModelOrAgent.ifBlank(contact.displayName)
      conversation.updatedAt = max(conversation.updatedAt, updatedAt)
      byId[conversationId] = conversation
    }
    return Self.sortedAgentConversations(Array(byId.values))
  }

  private func isAgentSessionContact(_ contact: SignalASIContact) -> Bool {
    contact.id == "hermes" || contact.type == "agent" || contact.deliveryMode == .cloudAPI
  }

  private func defaultAgentConversationId(for contactId: String) -> String {
    "ios-\(contactId)"
  }

  private func activeConversationId(for contactId: String) -> String {
    if let contact = contact(id: contactId),
       isAgentSessionContact(contact),
       let active = agentSession(id: activeAgentConversationId),
       active.status == .active,
       active.mergedIntoConversationId.isBlank {
      return active.id
    }
    return defaultAgentConversationId(for: contactId)
  }

  private func recordAgentConversationActivity(
    conversationId: String,
    contactId: String,
    content: String,
    at date: Date
  ) {
    guard let contact = contact(id: contactId), isAgentSessionContact(contact) else { return }
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    let timestamp = Self.millis(date)
    var conversation = agentSession(id: clean) ?? AgentConversation(
      id: clean,
      title: inferredAgentSessionTitle(content: content, fallback: contact.displayName),
      createdAt: timestamp,
      updatedAt: timestamp,
      selectedModelOrAgent: contact.displayName
    )
    if conversation.title.isBlank || conversation.title == "New session" {
      conversation.title = inferredAgentSessionTitle(content: content, fallback: contact.displayName)
    }
    conversation.selectedModelOrAgent = contact.displayName.ifBlank(conversation.selectedModelOrAgent)
    conversation.updatedAt = max(conversation.updatedAt, timestamp)
    persistAgentConversation(conversation)
  }

  private func inferredAgentSessionTitle(content: String, fallback: String) -> String {
    let clean = content
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return fallback.ifBlank("New session") }
    return String(clean.prefix(48))
  }

  private static func sortedAgentConversations(_ conversations: [AgentConversation]) -> [AgentConversation] {
    conversations.sorted { left, right in
      if left.pinned != right.pinned {
        return left.pinned && !right.pinned
      }
      if left.updatedAt != right.updatedAt {
        return left.updatedAt > right.updatedAt
      }
      return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
  }

  private func lastAgentResponseLatencyMillis(_ messages: [ChatMessage]) -> Int64 {
    let ordered = messages.sorted { $0.createdAt < $1.createdAt }
    var lastUserAt: Date?
    var latestLatency: Int64 = 0
    for message in ordered {
      if message.isMine && !message.isSystem {
        lastUserAt = message.createdAt
      } else if !message.isMine && !message.isSystem, let start = lastUserAt {
        latestLatency = max(0, Self.millis(message.createdAt) - Self.millis(start))
      }
    }
    return latestLatency
  }

  private static func nowMillis() -> Int64 {
    millis(Date())
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private func agentKnowledgeSourceKey(_ item: AgentKnowledgeItem) -> String {
    item.source.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("local:\(item.kind.rawValue.lowercased()):\(item.title)")
  }

  private func chunkKnowledgeContent(_ content: String) -> [String] {
    let clean = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    let limit = 12_000
    guard clean.count > limit else { return [clean] }

    var chunks: [String] = []
    var current = ""
    for paragraph in clean.components(separatedBy: "\n\n") {
      let part = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !part.isEmpty else { continue }
      if part.count > limit {
        if !current.isEmpty {
          chunks.append(current)
          current = ""
        }
        var start = part.startIndex
        while start < part.endIndex {
          let end = part.index(start, offsetBy: limit, limitedBy: part.endIndex) ?? part.endIndex
          chunks.append(String(part[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
          start = end
        }
      } else if current.count + part.count + 2 > limit {
        chunks.append(current)
        current = part
      } else {
        current = current.isEmpty ? part : "\(current)\n\n\(part)"
      }
    }
    if !current.isEmpty {
      chunks.append(current)
    }
    return chunks.isEmpty ? [clean] : chunks
  }

  private func knowledgeTokens(_ query: String) -> [String] {
    let normalized = query.lowercased().unicodeScalars.map { scalar -> String in
      CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
    }.joined()
    var seen = Set<String>()
    var values: [String] = []
    for token in normalized.split(whereSeparator: \.isWhitespace).map(String.init) {
      let clean = String(token.prefix(64))
      guard clean.count >= 2, seen.insert(clean).inserted else { continue }
      values.append(clean)
      if values.count >= 24 { break }
    }
    return values
  }

  private func knowledgeMatchedTerms(_ item: AgentKnowledgeItem, query: String, tokens: [String]) -> [String] {
    let haystack = [
      item.title,
      item.summary,
      item.content,
      item.source,
      item.tags.joined(separator: " ")
    ].joined(separator: " ").lowercased()
    var values: [String] = []
    let cleanQuery = query.lowercased()
    if !cleanQuery.isEmpty && haystack.localizedCaseInsensitiveContains(cleanQuery) {
      values.append(String(cleanQuery.prefix(64)))
    }
    for token in tokens where haystack.localizedCaseInsensitiveContains(token) && !values.contains(token) {
      values.append(token)
    }
    return values
  }

  private func knowledgeScore(_ item: AgentKnowledgeItem, query: String, tokens: [String]) -> Double {
    let cleanQuery = query.lowercased()
    let title = item.title.lowercased()
    let summary = item.summary.lowercased()
    let content = item.content.lowercased()
    let source = item.source.lowercased()
    let tags = item.tags.map { $0.lowercased() }
    var score = 0.0

    if title.localizedCaseInsensitiveContains(cleanQuery) { score += 10 }
    if summary.localizedCaseInsensitiveContains(cleanQuery) { score += 6 }
    if content.localizedCaseInsensitiveContains(cleanQuery) { score += 8 }
    if source.localizedCaseInsensitiveContains(cleanQuery) { score += 2 }
    if tags.contains(where: { $0.localizedCaseInsensitiveContains(cleanQuery) }) { score += 4 }

    for token in tokens {
      if title.localizedCaseInsensitiveContains(token) { score += 4 }
      if summary.localizedCaseInsensitiveContains(token) { score += 2 }
      if content.localizedCaseInsensitiveContains(token) { score += 1 }
      if source.localizedCaseInsensitiveContains(token) { score += 0.5 }
      if tags.contains(where: { $0.localizedCaseInsensitiveContains(token) }) { score += 3 }
    }
    return score
  }

  private func knowledgeExcerpt(_ content: String, query: String, tokens: [String]) -> String {
    let normalized = content
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "" }
    let needles = ([query] + tokens)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let firstRange = needles.compactMap {
      normalized.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])
    }.first
    guard let range = firstRange else {
      return String(normalized.prefix(260))
    }
    let start = normalized.index(range.lowerBound, offsetBy: -120, limitedBy: normalized.startIndex) ?? normalized.startIndex
    let end = normalized.index(range.upperBound, offsetBy: 220, limitedBy: normalized.endIndex) ?? normalized.endIndex
    let prefix = start == normalized.startIndex ? "" : "..."
    let suffix = end == normalized.endIndex ? "" : "..."
    return prefix + String(normalized[start..<end]) + suffix
  }

  private func deterministicHash(_ value: String) -> Int {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return Int(hash & 0x7fff_ffff)
  }

  private func mergedAgentTaskRecords() -> [AgentTaskRecord] {
    var byId: [String: AgentTaskRecord] = [:]
    for record in agentTaskRecords + workspaceAgentTaskRecords() where !record.taskId.isBlank {
      if let existing = byId[record.taskId],
         existing.updatedAtMillis >= record.updatedAtMillis {
        continue
      }
      byId[record.taskId] = record
    }
    return Self.sortedAgentTasks(Array(byId.values))
  }

  private func workspaceAgentTaskRecords() -> [AgentTaskRecord] {
    agentWorkspaceStore.list().compactMap { workspace in
      let taskId = workspace.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !taskId.isEmpty else { return nil }
      let routeKind = workspaceRouteKind(workspace)
      let locationKind = workspaceLocationKind(workspace, routeKind: routeKind)
      let runtimeKind = workspaceRuntimeKind(workspace, routeKind: routeKind, locationKind: locationKind)
      return AgentTaskRecord(
        taskId: taskId,
        sessionId: workspace.sessionId,
        goal: workspace.goal.ifBlank(workspace.workspaceId),
        phase: workspacePhase(workspace.status),
        routeKind: routeKind,
        targetTitle: workspaceTargetTitle(workspace, routeKind: routeKind),
        risk: workspace.status == .blocked ? .blocked : .medium,
        blocked: workspace.status == .blocked,
        executionLocationKind: locationKind,
        executionRuntimeKind: runtimeKind,
        executionLocationId: workspace.deviceId.ifBlank(workspace.agentId),
        executionLocationName: workspace.deviceId.ifBlank(workspace.agentId),
        executionRuntimeId: workspace.remoteRunId,
        executionLocationTrusted: true,
        result: workspaceResultText(workspace),
        verification: workspace.currentPlanSnapshot,
        outputFiles: workspace.artifacts.map(\.uri),
        executionLog: workspace.eventJournal.map { event in
          [Self.formatMillis(event.timestampMillis), event.kind, event.message]
            .filter { !$0.isBlank }
            .joined(separator: " / ")
        },
        createdAtMillis: workspace.createdAtMillis,
        updatedAtMillis: workspace.updatedAtMillis
      )
    }
  }

  private func workspacePhase(_ status: AgentWorkspaceStatus) -> AgentPhase {
    switch status {
    case .created, .queued:
      return .planning
    case .running:
      return .executing
    case .waitingConfirmation:
      return .waitingConfirmation
    case .waitingResponse:
      return .waitingResponse
    case .paused:
      return .paused
    case .blocked:
      return .blocked
    case .completed:
      return .completed
    case .failed:
      return .failed
    case .cancelled:
      return .cancelled
    }
  }

  private func workspaceRouteKind(_ workspace: AgentWorkspace) -> AgentRouteKind {
    if !workspace.remoteRunId.isBlank || !workspace.agentId.isBlank {
      return .desktopAgent
    }
    return .localSystem
  }

  private func workspaceLocationKind(_ workspace: AgentWorkspace, routeKind: AgentRouteKind) -> AgentExecutionLocationKind {
    if !workspace.deviceId.isBlank || routeKind == .desktopAgent {
      return .desktop
    }
    return .phone
  }

  private func workspaceRuntimeKind(
    _ workspace: AgentWorkspace,
    routeKind: AgentRouteKind,
    locationKind: AgentExecutionLocationKind
  ) -> AgentExecutionRuntimeKind {
    if routeKind == .desktopAgent || locationKind == .desktop {
      return .desktopAgent
    }
    return .phoneNative
  }

  private func workspaceTargetTitle(_ workspace: AgentWorkspace, routeKind: AgentRouteKind) -> String {
    if routeKind == .desktopAgent {
      return workspace.agentId.ifBlank(workspace.deviceId).ifBlank("Desktop Agent")
    }
    return workspace.agentId.ifBlank("SignalASI")
  }

  private func workspaceResultText(_ workspace: AgentWorkspace) -> String {
    if !workspace.errorMessage.isBlank {
      return workspace.errorMessage
    }
    let clean = workspace.resultJson.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean == "{}" ? "" : clean
  }

  private static func sortedAgentTasks(_ records: [AgentTaskRecord]) -> [AgentTaskRecord] {
    records.sorted { left, right in
      let leftTime = max(left.updatedAtMillis, left.createdAtMillis)
      let rightTime = max(right.updatedAtMillis, right.createdAtMillis)
      if leftTime != rightTime {
        return leftTime > rightTime
      }
      return left.taskId > right.taskId
    }
  }

  private static func formatMillis(_ value: Int64) -> String {
    guard value > 0 else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "MM-dd HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: Double(value) / 1_000))
  }

  private func save() {
    let state = PersistedState(
      profile: profile,
      contacts: contacts,
      friendRequests: friendRequests,
      messagesByContact: messagesByContact,
      readAtByContact: readAtByContact,
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
      defaults.set(data, forKey: storageKey)
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
      name: "Me",
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
