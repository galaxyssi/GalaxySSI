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

@MainActor
final class SignalASIStore: ObservableObject {
  @Published private(set) var profile: SignalASIProfile
  @Published private(set) var contacts: [SignalASIContact]
  @Published private(set) var messagesByContact: [String: [ChatMessage]]
  @Published private(set) var serverLinks: [ServerLink]
  @Published var voiceSettings: VoiceSettings {
    didSet { save() }
  }

  private struct PersistedState: Codable {
    var profile: SignalASIProfile
    var contacts: [SignalASIContact]
    var messagesByContact: [String: [ChatMessage]]
    var serverLinks: [ServerLink]
    var voiceSettings: VoiceSettings
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
      messagesByContact = state.messagesByContact
      serverLinks = state.serverLinks
      voiceSettings = state.voiceSettings
    } else {
      let generatedProfile = SignalASIStore.makeProfile(secrets: secrets, account: identityPrivateKeyAccount)
      profile = generatedProfile
      contacts = [SignalASIContact.hermes(), SignalASIContact.system()]
      messagesByContact = [
        "hermes": [
          ChatMessage(
            contactId: "hermes",
            content: "Pair SignalASI Desktop to start a trusted Link conversation.",
            isMine: false,
            isSystem: true
          )
        ]
      ]
      serverLinks = []
      voiceSettings = .default
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

  func contact(id: String) -> SignalASIContact? {
    contacts.first { $0.id == id || $0.signalASIId == id }
  }

  func messages(for contactId: String) -> [ChatMessage] {
    messagesByContact[contactId] ?? []
  }

  func updateProfileName(_ name: String) {
    profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("Me")
    save()
  }

  func updateVoiceSettings(_ mutate: (inout VoiceSettings) -> Void) {
    var next = voiceSettings
    mutate(&next)
    voiceSettings = next
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
  func addCloudModelContact(
    displayName: String,
    provider: String,
    modelId: String,
    endpoint: String,
    apiKey: String,
    apiStyle: SignalASICloudAPIStyle
  ) throws -> SignalASIContact {
    let providerName = provider.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("Custom")
    let providerSlug = SignalASIStore.slug(providerName)
    let contactId = "cloud:\(providerSlug)"
    let account = "cloud.\(providerSlug).\(SignalASIStore.slug(modelId))"
    if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      try secrets.setString(apiKey, account: account)
    }
    let model = CloudModelConfig(
      id: "\(providerSlug):\(modelId)",
      displayName: displayName.ifBlank(modelId),
      provider: providerName,
      modelId: modelId,
      endpoint: endpoint,
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
    if let existingIndex = contact.cloudModels.firstIndex(where: { $0.modelId == modelId }) {
      contact.cloudModels[existingIndex] = model
    } else {
      contact.cloudModels.append(model)
    }
    if contact.selectedCloudModelId.isEmpty {
      contact.selectedCloudModelId = model.modelId
    }
    contact.updatedAt = now
    upsert(contact)
    save()
    return contact
  }

  func apiKey(for model: CloudModelConfig) -> String? {
    secrets.string(account: model.keychainAccount)
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
        cloudAPISecrets: cloudSecrets
      ),
      contacts: includeContacts ? contacts : [],
      messagesByContact: includeMessages ? messagesByContact : [:]
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
    }
    if includeMessages, payload.includesMessages {
      messagesByContact = payload.messagesByContact
    }
    if payload.includesAgentData {
      serverLinks = payload.agentData.serverLinks
      voiceSettings = payload.agentData.voiceSettings
    }
    save()
  }

  func setSelectedCloudModel(contactId: String, modelId: String) {
    guard var contact = contact(id: contactId),
          contact.cloudModels.contains(where: { $0.modelId == modelId }) else {
      return
    }
    contact.selectedCloudModelId = modelId
    contact.updatedAt = Date()
    upsert(contact)
    save()
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
      messagesByContact: messagesByContact,
      serverLinks: serverLinks,
      voiceSettings: voiceSettings
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
