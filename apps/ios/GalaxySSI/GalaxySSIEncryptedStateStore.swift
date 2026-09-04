import CryptoKit
import Foundation

enum GalaxySSIEncryptedStateStore {
  static let stateKey = "galaxyssi-ios-state-v2"
  static let legacyStateKey = "galaxyssi-ios-state-v1"

  private static let keychainAccount = "state.encryption.aes256"
  private static let associatedData = Data("com.galaxyssi.chat.ios.state.v2".utf8)

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
