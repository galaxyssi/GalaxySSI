import CryptoKit
import Foundation

enum GalaxySSIPrivateChatFiles {
  static func directory(_ category: String, applicationSupport: URL? = nil) -> URL {
    let root = applicationSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
    return root.appendingPathComponent("GalaxySSIChatFiles", isDirectory: true)
      .appendingPathComponent(category, isDirectory: true)
  }

  static func contains(_ file: URL, in directory: URL) -> Bool {
    guard file.isFileURL, directory.isFileURL else { return false }
    let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
    let path = file.resolvingSymlinksInPath().standardizedFileURL.path
    return path.hasPrefix(root + "/")
  }
}

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

  final class BlobStaging {
    private let fileManager: FileManager
    let url: URL
    private var output: FileHandle?
    private var hash = SHA256()
    private(set) var count: Int64 = 0

    fileprivate init(directory: URL, fileManager: FileManager) throws {
      self.fileManager = fileManager
      url = directory.appendingPathComponent(".blob-\(UUID().uuidString).storing")
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      guard fileManager.createFile(atPath: url.path, contents: nil, attributes: [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
      ]) else { throw GalaxySSIAttachmentAtRestError.writeFailed }
      do {
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
        output = try FileHandle(forWritingTo: url)
      } catch {
        try? fileManager.removeItem(at: url)
        throw error
      }
    }

    deinit {
      try? output?.close()
      try? fileManager.removeItem(at: url)
    }

    func append(_ bytes: Data, maximum: Int64) throws {
      guard let output, count <= maximum, Int64(bytes.count) <= maximum - count else {
        throw AgentBlobFailure.invalid("plaintext_hash_mismatch")
      }
      try output.write(contentsOf: bytes)
      hash.update(data: bytes)
      count += Int64(bytes.count)
    }

    func finish(size: Int64, sha256: String) throws {
      guard let output, count == size,
            hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256 else {
        throw AgentBlobFailure.invalid("plaintext_hash_mismatch")
      }
      try output.synchronize()
      try output.close()
      self.output = nil
    }
  }

  func stageBlob(in directory: URL) throws -> BlobStaging {
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
    if let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) {
      let cutoff = Date().addingTimeInterval(-86_400)
      for entry in entries where entry.lastPathComponent.hasPrefix(".blob-") && entry.pathExtension == "storing" {
        if let values = try? entry.resourceValues(forKeys: keys), values.isRegularFile == true,
           let modified = values.contentModificationDate, modified < cutoff {
          try? fileManager.removeItem(at: entry)
        }
      }
    }
    return try BlobStaging(directory: directory, fileManager: fileManager)
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
