import CryptoKit
import Foundation
import Security
import SwiftUI
import UniformTypeIdentifiers

struct SignalASIBackupIdentity: Codable, Equatable {
  var kind: String
  var identityPrivateKey: String
  var identityPublicKey: String
  var identityFingerprint: String

  init(
    kind: String = "ios-p256-signing",
    identityPrivateKey: String,
    identityPublicKey: String,
    identityFingerprint: String
  ) {
    self.kind = kind
    self.identityPrivateKey = identityPrivateKey
    self.identityPublicKey = identityPublicKey
    self.identityFingerprint = identityFingerprint
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case identityPrivateKey = "identity_private_key"
    case identityPublicKey = "identity_public_key"
    case identityFingerprint = "identity_fingerprint"
  }
}

struct SignalASIBackupPrivacyManifest: Codable, Equatable {
  var includesIdentity: Bool
  var includesContacts: Bool
  var includesMessages: Bool
  var includesServerLinks: Bool
  var includesVoiceSettings: Bool
  var includesCloudAPISecrets: Bool

  static let empty = SignalASIBackupPrivacyManifest(
    includesIdentity: false,
    includesContacts: false,
    includesMessages: false,
    includesServerLinks: false,
    includesVoiceSettings: false,
    includesCloudAPISecrets: false
  )

  enum CodingKeys: String, CodingKey {
    case includesIdentity = "includes_identity"
    case includesContacts = "includes_contacts"
    case includesMessages = "includes_messages"
    case includesServerLinks = "includes_server_links"
    case includesVoiceSettings = "includes_voice_settings"
    case includesCloudAPISecrets = "includes_cloud_api_secrets"
  }
}

struct SignalASIBackupAgentData: Codable, Equatable {
  var serverLinks: [ServerLink]
  var voiceSettings: VoiceSettings
  var cloudAPISecrets: [String: String]

  static let empty = SignalASIBackupAgentData(
    serverLinks: [],
    voiceSettings: .default,
    cloudAPISecrets: [:]
  )

  enum CodingKeys: String, CodingKey {
    case serverLinks = "server_links"
    case voiceSettings = "voice_settings"
    case cloudAPISecrets = "cloud_api_secrets"
  }
}

struct SignalASIBackupPayload: Codable, Equatable {
  var platform: String
  var exportedAt: Int64
  var identity: SignalASIBackupIdentity?
  var profile: SignalASIProfile
  var includesContacts: Bool
  var includesMessages: Bool
  var includesAgentData: Bool
  var privacyManifest: SignalASIBackupPrivacyManifest
  var agentData: SignalASIBackupAgentData
  var contacts: [SignalASIContact]
  var friendRequests: [SignalASIFriendRequest]
  var messagesByContact: [String: [ChatMessage]]

  init(
    platform: String = "ios",
    exportedAt: Int64 = SignalASIBackupManager.currentTimestampMilliseconds(),
    identity: SignalASIBackupIdentity?,
    profile: SignalASIProfile,
    includesContacts: Bool,
    includesMessages: Bool,
    includesAgentData: Bool = true,
    privacyManifest: SignalASIBackupPrivacyManifest,
    agentData: SignalASIBackupAgentData,
    contacts: [SignalASIContact],
    friendRequests: [SignalASIFriendRequest] = [],
    messagesByContact: [String: [ChatMessage]]
  ) {
    self.platform = platform
    self.exportedAt = exportedAt
    self.identity = identity
    self.profile = profile
    self.includesContacts = includesContacts
    self.includesMessages = includesMessages
    self.includesAgentData = includesAgentData
    self.privacyManifest = privacyManifest
    self.agentData = agentData
    self.contacts = contacts
    self.friendRequests = friendRequests
    self.messagesByContact = messagesByContact
  }

  enum CodingKeys: String, CodingKey {
    case platform
    case exportedAt = "exported_at"
    case identity
    case profile
    case includesContacts = "includes_contacts"
    case includesMessages = "includes_messages"
    case includesAgentData = "includes_agent_data"
    case privacyManifest = "privacy_manifest"
    case agentData = "agent_data"
    case contacts
    case friendRequests = "friend_requests"
    case messagesByContact = "messages"
  }
}

struct SignalASIBackupRoot: Codable, Equatable {
  var version: Int
  var type: String
  var kdf: String
  var iterations: Int
  var cipher: String
  var salt: String
  var iv: String
  var ciphertext: String
  var createdAt: Int64

  enum CodingKeys: String, CodingKey {
    case version
    case type
    case kdf
    case iterations
    case cipher
    case salt
    case iv
    case ciphertext
    case createdAt = "created_at"
  }
}

enum SignalASIBackupManager {
  static let version = 1
  static let type = "signalasi_backup"
  static let kdf = "pbkdf2-hmac-sha256"
  static let cipher = "aes-256-gcm"
  static let iterations = 180_000
  static let minimumPasswordLength = 8

  private static let keyByteCount = 32
  private static let saltByteCount = 16
  private static let nonceByteCount = 12
  private static let gcmTagByteCount = 16

  @MainActor
  static func exportBackup(
    store: SignalASIStore,
    password: String,
    includeContacts: Bool = true,
    includeMessages: Bool = true,
    iterations: Int = SignalASIBackupManager.iterations
  ) throws -> Data {
    let payload = store.exportBackupPayload(
      includeContacts: includeContacts,
      includeMessages: includeMessages
    )
    return try encryptPayload(payload, password: password, iterations: iterations)
  }

  static func encryptPayload(
    _ payload: SignalASIBackupPayload,
    password: String,
    iterations: Int = SignalASIBackupManager.iterations
  ) throws -> Data {
    try validatePassword(password)
    guard iterations > 0 else {
      throw SignalASIError.invalidPayload("Backup KDF iterations must be positive.")
    }
    let payloadData = try backupEncoder.encode(payload)
    let salt = try randomData(count: saltByteCount)
    let iv = try randomData(count: nonceByteCount)
    let key = SymmetricKey(data: try pbkdf2SHA256(
      password: password,
      salt: salt,
      iterations: iterations,
      keyByteCount: keyByteCount
    ))
    let sealed = try AES.GCM.seal(
      payloadData,
      using: key,
      nonce: try AES.GCM.Nonce(data: iv)
    )
    var androidCompatibleCiphertext = sealed.ciphertext
    androidCompatibleCiphertext.append(sealed.tag)
    let root = SignalASIBackupRoot(
      version: version,
      type: type,
      kdf: kdf,
      iterations: iterations,
      cipher: cipher,
      salt: salt.base64EncodedString(),
      iv: iv.base64EncodedString(),
      ciphertext: androidCompatibleCiphertext.base64EncodedString(),
      createdAt: currentTimestampMilliseconds()
    )
    return try backupEncoder.encode(root)
  }

  static func importBackup(data: Data, password: String) throws -> SignalASIBackupPayload {
    try validatePassword(password)
    let root = try decodeRoot(from: data)
    let payloadData = try decryptRoot(root, password: password)
    return try backupDecoder.decode(SignalASIBackupPayload.self, from: payloadData)
  }

  static func decodeRoot(from data: Data) throws -> SignalASIBackupRoot {
    try backupDecoder.decode(SignalASIBackupRoot.self, from: data)
  }

  static func pbkdf2SHA256(
    password: String,
    salt: Data,
    iterations: Int,
    keyByteCount: Int
  ) throws -> Data {
    guard iterations > 0, keyByteCount > 0 else {
      throw SignalASIError.invalidPayload("Backup KDF parameters are invalid.")
    }
    let passwordKey = SymmetricKey(data: Data(password.utf8))
    var derived = Data()
    var blockIndex: UInt32 = 1

    while derived.count < keyByteCount {
      var blockSalt = salt
      blockSalt.append(contentsOf: [
        UInt8((blockIndex >> 24) & 0xff),
        UInt8((blockIndex >> 16) & 0xff),
        UInt8((blockIndex >> 8) & 0xff),
        UInt8(blockIndex & 0xff)
      ])

      var previous = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: passwordKey))
      var block = [UInt8](previous)
      if iterations > 1 {
        for _ in 1..<iterations {
          previous = Data(HMAC<SHA256>.authenticationCode(for: previous, using: passwordKey))
          let previousBytes = [UInt8](previous)
          for offset in block.indices {
            block[offset] ^= previousBytes[offset]
          }
        }
      }
      derived.append(contentsOf: block)
      blockIndex += 1
    }
    return Data(derived.prefix(keyByteCount))
  }

  static func currentTimestampMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  static func defaultFilename() -> String {
    "signalasi_backup_\(currentTimestampMilliseconds()).hcbak"
  }

  private static func decryptRoot(_ root: SignalASIBackupRoot, password: String) throws -> Data {
    guard root.version == version,
          root.type == type,
          root.kdf == kdf,
          root.cipher == cipher else {
      throw SignalASIError.invalidPayload("Backup file format is not supported.")
    }
    guard let salt = Data(base64Encoded: root.salt),
          let iv = Data(base64Encoded: root.iv),
          let combined = Data(base64Encoded: root.ciphertext),
          salt.count == saltByteCount,
          iv.count == nonceByteCount,
          combined.count > gcmTagByteCount else {
      throw SignalASIError.invalidPayload("Backup envelope is malformed.")
    }
    let key = SymmetricKey(data: try pbkdf2SHA256(
      password: password,
      salt: salt,
      iterations: root.iterations,
      keyByteCount: keyByteCount
    ))
    let ciphertext = combined.prefix(combined.count - gcmTagByteCount)
    let tag = combined.suffix(gcmTagByteCount)
    do {
      let sealed = try AES.GCM.SealedBox(
        nonce: try AES.GCM.Nonce(data: iv),
        ciphertext: Data(ciphertext),
        tag: Data(tag)
      )
      return try AES.GCM.open(sealed, using: key)
    } catch {
      throw SignalASIError.invalidPayload("Backup password is incorrect or the file is damaged.")
    }
  }

  private static func validatePassword(_ password: String) throws {
    guard password.count >= minimumPasswordLength else {
      throw SignalASIError.invalidPayload("Backup password must be at least 8 characters.")
    }
  }

  private static func randomData(count: Int) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw SignalASIError.invalidPayload("Unable to create secure backup randomness.")
    }
    return Data(bytes)
  }

  private static var backupEncoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static var backupDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

struct SignalASIBackupDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  static var writableContentTypes: [UTType] { [.data] }

  var data: Data

  init(data: Data = Data()) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
