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

  private struct PersistedState: Codable {
    var profile: SignalASIProfile
    var contacts: [SignalASIContact]
    var friendRequests: [SignalASIFriendRequest]
    var messagesByContact: [String: [ChatMessage]]
    var readAtByContact: [String: Date]
    var serverLinks: [ServerLink]
    var voiceSettings: VoiceSettings
    var languagePolicy: LanguagePolicySettings

    init(
      profile: SignalASIProfile,
      contacts: [SignalASIContact],
      friendRequests: [SignalASIFriendRequest],
      messagesByContact: [String: [ChatMessage]],
      readAtByContact: [String: Date] = [:],
      serverLinks: [ServerLink],
      voiceSettings: VoiceSettings,
      languagePolicy: LanguagePolicySettings = .default
    ) {
      self.profile = profile
      self.contacts = contacts
      self.friendRequests = friendRequests
      self.messagesByContact = messagesByContact
      self.readAtByContact = readAtByContact
      self.serverLinks = serverLinks
      self.voiceSettings = voiceSettings
      self.languagePolicy = languagePolicy
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
    }
  }

  private let defaults: UserDefaults
  private let secrets: SignalASISecretStore
  private let storageKey = "signalasi-ios-state-v1"
  private let identityPrivateKeyAccount = "identity.p256.private"

  init(defaults: UserDefaults = .standard, secrets: SignalASISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.secrets = secrets
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
      save()
    }
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
    secrets.delete(account: identityPrivateKeyAccount)
    defaults.removeObject(forKey: storageKey)
    resetToFreshState()
    save()
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
  }

  @discardableResult
  func appendOutgoing(_ content: String, to contactId: String, status: ChatDeliveryStatus = .queued) -> ChatMessage {
    var message = ChatMessage(
      contactId: contactId,
      content: content,
      isMine: true,
      deliveryStatus: status,
      deliveryTrace: [DeliveryTraceEvent(stage: status.rawValue)]
    )
    message.conversationId = "ios-\(contactId)"
    messagesByContact[contactId, default: []].append(message)
    save()
    return message
  }

  @discardableResult
  func appendIncoming(_ content: String, from contactId: String, remoteMessageId: String = "") -> ChatMessage {
    let message = ChatMessage(
      contactId: contactId,
      content: content,
      isMine: false,
      deliveryStatus: .delivered,
      deliveryTrace: [DeliveryTraceEvent(stage: "received")],
      conversationId: "ios-\(contactId)",
      remoteMessageId: remoteMessageId
    )
    messagesByContact[contactId, default: []].append(message)
    save()
    return message
  }

  @discardableResult
  func appendSystem(_ content: String, to contactId: String) -> ChatMessage {
    let message = ChatMessage(
      contactId: contactId,
      content: content,
      isMine: false,
      isSystem: true,
      deliveryStatus: .local
    )
    messagesByContact[contactId, default: []].append(message)
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
    var next = contact(id: contactId) ?? SignalASIContact(
      id: contactId,
      signalASIId: request.signalASIId,
      name: request.name,
      displayName: request.name,
      type: request.type.ifBlank("person"),
      agentKind: request.type == "hermes" ? "desktop-agent" : "person",
      deliveryMode: .link,
      trustState: .verified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: request.identityFingerprint,
      setupStatus: "ready",
      setupDetail: "Verified from contact QR",
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
    next.type = request.type.ifBlank("person")
    next.agentKind = request.type == "hermes" ? "desktop-agent" : "person"
    next.deliveryMode = .link
    next.trustState = .verified
    next.identityFingerprint = request.identityFingerprint
    next.mqttTopic = request.mqttTopic
    next.mqttInboxTopic = request.mqttInboxTopic
    next.signalBundleRef = request.signalBundleRef
    next.setupStatus = "ready"
    next.setupDetail = request.mqttInboxTopic.isEmpty ? "Verified from contact QR" : "SignalASI contact QR verified"
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
        includesCloudAPISecrets: !cloudSecrets.isEmpty
      ),
      agentData: SignalASIBackupAgentData(
        serverLinks: serverLinks,
        voiceSettings: voiceSettings,
        languagePolicy: languagePolicy,
        cloudAPISecrets: cloudSecrets
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
    let clientRouteId = (!rotateClientRoute ? existing?.routes.clientRouteId : nil) ?? (try SignalASILinkProtocol.newRouteId())
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
    save()
  }

  func removeServer(desktopId: String) {
    serverLinks.removeAll { $0.desktopId == desktopId }
    if var hermes = contact(id: "hermes") {
      hermes.trustState = .unverified
      hermes.setupStatus = "needs_pairing"
      hermes.setupDetail = "Waiting for SignalASI Desktop pairing"
      upsert(hermes)
    }
    save()
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

  private func save() {
    let state = PersistedState(
      profile: profile,
      contacts: contacts,
      friendRequests: friendRequests,
      messagesByContact: messagesByContact,
      readAtByContact: readAtByContact,
      serverLinks: serverLinks,
      voiceSettings: voiceSettings,
      languagePolicy: languagePolicy
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

private extension JSONDecoder {
  static var signalASI: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
