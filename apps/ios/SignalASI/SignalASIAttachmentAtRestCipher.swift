import CryptoKit
import Foundation

enum SignalASIAttachmentAtRestError: Error, Equatable {
  case invalidContainer
  case unsupportedVersion
  case keyUnavailable
  case authenticationFailed
  case integrityFailed
  case writeFailed
}

final class SignalASIAttachmentAtRestCipher {
  static let shared = SignalASIAttachmentAtRestCipher()
  static let containerExtension = "saenc"

  static func removeLegacyPlaintextRoots(
    fileManager: FileManager = .default,
    roots: [URL]? = nil
  ) {
    let cleanupRoots = roots ?? fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )
    for root in cleanupRoots {
      for name in legacyPlaintextRootNames {
        try? fileManager.removeItem(at: root.appendingPathComponent(name, isDirectory: true))
      }
    }
  }

  private struct Header: Codable {
    var version: Int
    var purpose: String
    var plaintextSize: Int64
    var plaintextSHA256: String
  }

  private let secrets: SignalASISecretStore
  private let fileManager: FileManager
  private let keyAccount: String
  private let lock = NSRecursiveLock()
  private var cachedKey: SymmetricKey?

  init(
    secrets: SignalASISecretStore = KeychainSecretStore.shared,
    fileManager: FileManager = .default,
    keyAccount: String = "attachment.at-rest.aes256.v1"
  ) {
    self.secrets = secrets
    self.fileManager = fileManager
    self.keyAccount = keyAccount
  }

  func isEncryptedFile(_ url: URL) -> Bool {
    guard let input = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? input.close() }
    return (try? input.read(upToCount: Self.magic.count)) == Self.magic
  }

  func encrypt(_ plaintext: Data, purpose: String) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    let cleanPurpose = normalizedPurpose(purpose)
    let header = Header(
      version: Self.version,
      purpose: cleanPurpose,
      plaintextSize: Int64(plaintext.count),
      plaintextSHA256: sha256(plaintext)
    )
    let headerData = try JSONEncoder.signalASIAttachment.encode(header)
    guard headerData.count <= Self.maximumHeaderBytes else {
      throw SignalASIAttachmentAtRestError.invalidContainer
    }
    let authenticatedPrefix = Self.magic + Self.uint32Data(UInt32(headerData.count)) + headerData
    let sealed = try AES.GCM.seal(
      plaintext,
      using: try encryptionKey(createIfMissing: true),
      authenticating: authenticatedPrefix
    )
    guard let combined = sealed.combined else {
      throw SignalASIAttachmentAtRestError.writeFailed
    }
    return authenticatedPrefix + combined
  }

  func decrypt(_ container: Data, expectedPurpose: String? = nil) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    let parsed = try parse(container)
    if let expectedPurpose,
       parsed.header.purpose != normalizedPurpose(expectedPurpose) {
      throw SignalASIAttachmentAtRestError.authenticationFailed
    }
    let plaintext: Data
    do {
      let box = try AES.GCM.SealedBox(combined: parsed.sealed)
      plaintext = try AES.GCM.open(
        box,
        using: try encryptionKey(createIfMissing: false),
        authenticating: parsed.authenticatedPrefix
      )
    } catch let error as SignalASIAttachmentAtRestError {
      throw error
    } catch {
      throw SignalASIAttachmentAtRestError.authenticationFailed
    }
    guard Int64(plaintext.count) == parsed.header.plaintextSize,
          sha256(plaintext) == parsed.header.plaintextSHA256 else {
      throw SignalASIAttachmentAtRestError.integrityFailed
    }
    return plaintext
  }

  func write(_ plaintext: Data, to url: URL, purpose: String) throws {
    let container = try encrypt(plaintext, purpose: purpose)
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
      isDirectory: false
    )
    defer { try? fileManager.removeItem(at: temporary) }
    do {
      try container.write(to: temporary, options: [.atomic])
      try protectFile(at: temporary)
      if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
      }
      try fileManager.moveItem(at: temporary, to: url)
      try protectFile(at: url)
    } catch {
      throw SignalASIAttachmentAtRestError.writeFailed
    }
  }

  func read(from url: URL, purpose: String) throws -> Data {
    let stored = try Data(contentsOf: url, options: [.mappedIfSafe])
    return try decrypt(stored, expectedPurpose: purpose)
  }

  @discardableResult
  func readMigratingPlaintext(from url: URL, purpose: String) throws -> Data {
    let stored = try Data(contentsOf: url, options: [.mappedIfSafe])
    if stored.starts(with: Self.magic) {
      return try decrypt(stored, expectedPurpose: purpose)
    }
    try write(stored, to: url, purpose: purpose)
    return stored
  }

  func plaintextSize(of url: URL, purpose: String) -> Int64? {
    (try? readMigratingPlaintext(from: url, purpose: purpose)).map { Int64($0.count) }
  }

  func materializeTemporaryFile(
    from encryptedURL: URL,
    purpose: String,
    displayName: String,
    rootURL: URL? = nil
  ) throws -> URL {
    let data = try readMigratingPlaintext(from: encryptedURL, purpose: purpose)
    let root = (rootURL ?? defaultDecryptionRoot()).standardizedFileURL
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let name = safeFileName(displayName)
    let identity = Data(SHA256.hash(data: Data(encryptedURL.standardizedFileURL.path.utf8)))
      .hexString()
    let destination = root.appendingPathComponent(
      "\(identity.prefix(24))-\(name)",
      isDirectory: false
    )
    try data.write(to: destination, options: [.atomic])
    try protectFile(at: destination, complete: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var mutableDestination = destination
    try? mutableDestination.setResourceValues(values)
    return destination
  }

  func removeTemporaryMaterializations(rootURL: URL? = nil) {
    try? fileManager.removeItem(at: rootURL ?? defaultDecryptionRoot())
  }

  func destroyEncryptionKey() {
    lock.lock()
    defer { lock.unlock() }
    cachedKey = nil
    secrets.delete(account: keyAccount)
  }

  private func parse(_ container: Data) throws -> (
    header: Header,
    authenticatedPrefix: Data,
    sealed: Data
  ) {
    let fixedBytes = Self.magic.count + MemoryLayout<UInt32>.size
    guard container.count > fixedBytes + Self.minimumSealedBytes,
          container.starts(with: Self.magic) else {
      throw SignalASIAttachmentAtRestError.invalidContainer
    }
    let lengthOffset = Self.magic.count
    let headerLength = Int(Self.readUInt32(container, offset: lengthOffset))
    guard (1...Self.maximumHeaderBytes).contains(headerLength) else {
      throw SignalASIAttachmentAtRestError.invalidContainer
    }
    let headerStart = fixedBytes
    let headerEnd = headerStart + headerLength
    guard headerEnd + Self.minimumSealedBytes <= container.count else {
      throw SignalASIAttachmentAtRestError.invalidContainer
    }
    let headerData = Data(container[headerStart..<headerEnd])
    guard let header = try? JSONDecoder().decode(Header.self, from: headerData),
          header.version == Self.version,
          header.plaintextSize >= 0,
          header.plaintextSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
          header.purpose == normalizedPurpose(header.purpose) else {
      throw SignalASIAttachmentAtRestError.unsupportedVersion
    }
    return (
      header,
      Data(container[..<headerEnd]),
      Data(container[headerEnd...])
    )
  }

  private func encryptionKey(createIfMissing: Bool) throws -> SymmetricKey {
    if let cachedKey {
      return cachedKey
    }
    if let encoded = secrets.string(account: keyAccount),
       let data = Data(base64Encoded: encoded),
       data.count == 32 {
      let key = SymmetricKey(data: data)
      cachedKey = key
      return key
    }
    guard createIfMissing else {
      throw SignalASIAttachmentAtRestError.keyUnavailable
    }
    let generated = SymmetricKey(size: .bits256)
    let bytes = generated.withUnsafeBytes { Data($0) }
    do {
      try secrets.setString(bytes.base64EncodedString(), account: keyAccount)
      cachedKey = generated
    } catch {
      throw SignalASIAttachmentAtRestError.keyUnavailable
    }
    return generated
  }

  private func normalizedPurpose(_ value: String) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
  }

  private func safeFileName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
    return value.unicodeScalars
      .map { invalid.contains($0) ? "_" : String($0) }
      .joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(120)
      .description
      .ifBlank("attachment.bin")
  }

  private func defaultDecryptionRoot() -> URL {
    (fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory)
      .appendingPathComponent("decrypted/attachments-v1", isDirectory: true)
  }

  private func protectFile(at url: URL, complete: Bool = false) throws {
    try fileManager.setAttributes(
      [.protectionKey: complete
        ? FileProtectionType.complete
        : FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
  }

  private func sha256(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString()
  }

  private static func uint32Data(_ value: UInt32) -> Data {
    Data([
      UInt8((value >> 24) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8(value & 0xff)
    ])
  }

  private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
    data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
  }

  private static let version = 1
  private static let magic = Data([0x53, 0x41, 0x41, 0x54, 0x54, 0x30, 0x30, 0x31])
  private static let maximumHeaderBytes = 4 * 1_024
  private static let minimumSealedBytes = 12 + 16
  private static let legacyPlaintextRootNames = [
    "peer-incoming-attachments-v1",
    "peer-message-attachments-v1",
    "agent-link-outgoing-attachments-v1",
    "agent-rich-output",
    "desktop-artifacts"
  ]
}

private extension JSONEncoder {
  static var signalASIAttachment: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}
