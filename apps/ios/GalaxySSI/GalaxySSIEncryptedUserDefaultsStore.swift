import CryptoKit
import Foundation

enum GalaxySSIEncryptedUserDefaultsStore {
  static func load(
    defaults: UserDefaults,
    key: String,
    secrets: GalaxySSISecretStore
  ) -> Data? {
    guard let serialized = defaults.data(forKey: encryptedKey(for: key)),
          let encryptionKey = encryptionKey(for: key, secrets: secrets, createIfMissing: false),
          let sealed = try? AES.GCM.SealedBox(combined: serialized),
          let plaintext = try? AES.GCM.open(sealed, using: encryptionKey, authenticating: associatedData(for: key)) else {
      return nil
    }
    return plaintext
  }

  @discardableResult
  static func write(
    _ plaintext: Data,
    defaults: UserDefaults,
    key: String,
    secrets: GalaxySSISecretStore
  ) -> Bool {
    guard let encryptionKey = encryptionKey(for: key, secrets: secrets, createIfMissing: true),
          let sealed = try? AES.GCM.seal(
            plaintext,
            using: encryptionKey,
            authenticating: associatedData(for: key)
          ),
          let serialized = sealed.combined else {
      return false
    }
    defaults.set(serialized, forKey: encryptedKey(for: key))
    defaults.removeObject(forKey: key)
    return true
  }

  static func destroy(
    defaults: UserDefaults,
    key: String,
    secrets: GalaxySSISecretStore
  ) {
    defaults.removeObject(forKey: encryptedKey(for: key))
    defaults.removeObject(forKey: key)
    secrets.delete(account: keychainAccount(for: key))
  }

  private static func encryptedKey(for key: String) -> String {
    "\(key).encrypted.v1"
  }

  private static func associatedData(for key: String) -> Data {
    Data("com.galaxyssi.chat.ios.userdefaults.\(key).v1".utf8)
  }

  private static func keychainAccount(for key: String) -> String {
    let digest = Data(SHA256.hash(data: Data(key.utf8)))
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "_")
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: "=", with: "")
    return "encrypted.defaults.\(digest)"
  }

  private static func encryptionKey(
    for key: String,
    secrets: GalaxySSISecretStore,
    createIfMissing: Bool
  ) -> SymmetricKey? {
    let account = keychainAccount(for: key)
    if let encoded = secrets.string(account: account),
       let data = Data(base64Encoded: encoded),
       data.count == 32 {
      return SymmetricKey(data: data)
    }
    guard createIfMissing else { return nil }
    let generated = SymmetricKey(size: .bits256)
    let data = generated.withUnsafeBytes { Data($0) }
    guard (try? secrets.setString(data.base64EncodedString(), account: account)) != nil else {
      return nil
    }
    return generated
  }
}
