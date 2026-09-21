import Foundation

protocol GalaxySSILocalAttachmentStoring: AnyObject {
  func isEncryptedFile(_ url: URL) -> Bool
  func write(_ plaintext: Data, to url: URL, purpose: String) throws
  func read(from url: URL, purpose: String) throws -> Data
  func readMigratingPlaintext(from url: URL, purpose: String) throws -> Data
  func plaintextSize(of url: URL, purpose: String) -> Int64?
  func materializeTemporaryFile(
    from encryptedURL: URL,
    purpose: String,
    displayName: String,
    rootURL: URL?
  ) throws -> URL
}

extension GalaxySSILocalAttachmentStoring {
  func materializeTemporaryFile(
    from encryptedURL: URL,
    purpose: String,
    displayName: String
  ) throws -> URL {
    try materializeTemporaryFile(
      from: encryptedURL,
      purpose: purpose,
      displayName: displayName,
      rootURL: nil
    )
  }
}

extension GalaxySSIAttachmentAtRestCipher: GalaxySSILocalAttachmentStoring {}

/// Stores attachment content byte-for-byte in the app sandbox. iOS Data Protection
/// supplies device-lock encryption; protocol secrets continue using the AES store.
final class GalaxySSILocalAttachmentStore: GalaxySSILocalAttachmentStoring {
  static let shared = GalaxySSILocalAttachmentStore()

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func isEncryptedFile(_ url: URL) -> Bool {
    fileManager.fileExists(atPath: url.path)
  }

  func write(_ plaintext: Data, to url: URL, purpose: String) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".\(url.lastPathComponent).\(UUID().uuidString).storing"
    )
    defer { try? fileManager.removeItem(at: temporary) }
    try plaintext.write(to: temporary, options: [.atomic, .completeFileProtectionUnlessOpen])
    if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    try fileManager.moveItem(at: temporary, to: url)
    try (url as NSURL).setResourceValue(
      FileProtectionType.completeUntilFirstUserAuthentication,
      forKey: .fileProtectionKey
    )
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var protectedURL = url
    try? protectedURL.setResourceValues(values)
  }

  func read(from url: URL, purpose: String) throws -> Data {
    try Data(contentsOf: url, options: [.mappedIfSafe])
  }

  func readMigratingPlaintext(from url: URL, purpose: String) throws -> Data {
    try read(from: url, purpose: purpose)
  }

  func plaintextSize(of url: URL, purpose: String) -> Int64? {
    guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
    return Int64(value)
  }

  func materializeTemporaryFile(
    from encryptedURL: URL,
    purpose: String,
    displayName: String,
    rootURL: URL? = nil
  ) throws -> URL {
    guard fileManager.fileExists(atPath: encryptedURL.path) else {
      throw CocoaError(.fileNoSuchFile)
    }
    return encryptedURL
  }
}
