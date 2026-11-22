import CryptoKit
import Foundation

enum GalaxySSIEncryptedStateStore {
  static let stateKey = "galaxyssi-ios-state-v2"
  static let legacyStateKey = "galaxyssi-ios-state-v1"

  private static let keychainAccount = "state.encryption.aes256"
  private static let associatedData = Data("com.galaxyssi.chat.ios.state.v2".utf8)

  // Owned encrypted bytes/key only. No store, UserDefaults or Keychain client enters the worker.
  struct ContactRenameInput: @unchecked Sendable {
    let original: Data
    let key: SymmetricKey
    let owner: String
    let contact: GalaxySSIContact
    let name: String
    let at: Date
    func prepare() throws -> Data {
      try Task.checkCancellation()
      var plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: original), using: key, authenticating: GalaxySSIEncryptedStateStore.associatedData)
      defer { plaintext.wipeSensitive() }
      guard var root = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any],
            (root["profile"] as? [String: Any])?["identityFingerprint"] as? String == owner,
            var contacts = root["contacts"] as? [[String: Any]],
            let index = contacts.firstIndex(where: { $0["id"] as? String == contact.id }),
            contacts[index]["name"] as? String == contact.name,
            contacts[index]["displayName"] as? String == contact.displayName,
            contacts[index]["deleted"] as? Bool != true,
            contacts[index]["trustState"] as? String != "deleted" else { throw GalaxySSIError.invalidPayload("Contact changed") }
      contacts[index]["name"] = name; contacts[index]["displayName"] = name
      contacts[index]["updatedAt"] = ISO8601DateFormatter().string(from: at)
      root["contacts"] = contacts
      var updated = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
      defer { updated.wipeSensitive() }
      try Task.checkCancellation()
      guard let result = try AES.GCM.seal(updated, using: key, authenticating: GalaxySSIEncryptedStateStore.associatedData).combined else {
        throw GalaxySSIError.invalidPayload("Contact encryption failed")
      }
      return result
    }
  }

  static func contactRenameInput(defaults: UserDefaults, secrets: GalaxySSISecretStore, owner: String,
                                 contact: GalaxySSIContact, name: String) -> ContactRenameInput? {
    guard contact.id != "system", !contact.deleted, contact.trustState != .deleted,
          GalaxySSIConversationRenamePolicy.normalize(name) == name,
          let original = defaults.data(forKey: stateKey), let key = key(secrets: secrets, createIfMissing: false) else { return nil }
    return .init(original: original, key: key, owner: owner, contact: contact, name: name, at: Date())
  }
  @MainActor static func commitContactRename(_ prepared: Data, input: ContactRenameInput, defaults: UserDefaults) -> Bool {
    guard defaults.data(forKey: stateKey) == input.original else { return false }
    defaults.set(prepared, forKey: stateKey)
    defaults.removeObject(forKey: legacyStateKey)
    return defaults.data(forKey: stateKey) == prepared
  }

  static func load(
    defaults: UserDefaults,
    secrets: GalaxySSISecretStore
  ) -> Data? {
    guard let serialized = defaults.data(forKey: stateKey),
          let key = key(secrets: secrets, createIfMissing: false),
          let sealed = try? AES.GCM.SealedBox(combined: serialized),
          let plaintext = try? AES.GCM.open(
            sealed,
            using: key,
            authenticating: associatedData
          ) else {
      return nil
    }
    return plaintext
  }

  @discardableResult
  static func write(
    _ plaintext: Data,
    defaults: UserDefaults,
    secrets: GalaxySSISecretStore
  ) -> Bool {
    guard let key = key(secrets: secrets, createIfMissing: true),
          let sealed = try? AES.GCM.seal(
            plaintext,
            using: key,
            authenticating: associatedData
          ),
          let serialized = sealed.combined else {
      return false
    }
    defaults.set(serialized, forKey: stateKey)
    defaults.removeObject(forKey: legacyStateKey)
    return true
  }

  static func destroy(defaults: UserDefaults, secrets: GalaxySSISecretStore) {
    defaults.removeObject(forKey: stateKey)
    defaults.removeObject(forKey: legacyStateKey)
    secrets.delete(account: keychainAccount)
  }

  private static func key(
    secrets: GalaxySSISecretStore,
    createIfMissing: Bool
  ) -> SymmetricKey? {
    if let encoded = secrets.string(account: keychainAccount),
       let data = Data(base64Encoded: encoded),
       data.count == 32 {
      return SymmetricKey(data: data)
    }
    guard createIfMissing else { return nil }
    let generated = SymmetricKey(size: .bits256)
    let data = generated.withUnsafeBytes { Data($0) }
    guard (try? secrets.setString(data.base64EncodedString(), account: keychainAccount)) != nil else {
      return nil
    }
    return generated
  }
}
