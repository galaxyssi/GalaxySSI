import CryptoKit
import Foundation
import UIKit

// The database owns one file store. Native index work uses its serial utility queue;
// privacy invalidation may run concurrently and fences late opens by generation.
final class AgentKnowledgeNativeFiles {
  private struct Identity: Codable {
    var schema = 1
    var database: String
    var provenance: AgentKnowledgeVectorProvenance
    var epoch: String
  }
  private final class WeakBridge {
    weak var bridge: AgentKnowledgeNativeBridge?
    init(_ bridge: AgentKnowledgeNativeBridge) { self.bridge = bridge }
  }

  private static let keyLock = NSRecursiveLock()
  let rootDirectory: URL
  let masterKeyAccount: String
  private let namespace: String
  private let secrets: GalaxySSISecretStore
  private var generation: UInt64 = 0
  private var destroying = false
  private var bridges: [WeakBridge] = []
  private var observers: [NSObjectProtocol] = []

  init(databaseURL: URL, secrets: GalaxySSISecretStore) {
    let path = databaseURL.standardizedFileURL.path
    namespace = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    rootDirectory = URL(fileURLWithPath: path + ".native", isDirectory: true)
    masterKeyAccount = "agent.knowledge.native.master.v1.\(namespace)"
    self.secrets = secrets
    for name in [UIApplication.willResignActiveNotification, UIApplication.protectedDataWillBecomeUnavailableNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
        self?.invalidate()
      })
    }
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    invalidate()
  }

  func token() -> UInt64 {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    return generation
  }

  func identity(provenance: AgentKnowledgeVectorProvenance, epoch: String) throws -> Data {
    let normalized = try AgentKnowledgeNativeWire.epoch(epoch).map { String(format: "%02x", $0) }.joined()
    return Data(SHA256.hash(data: try JSONEncoder.galaxySSI.encode(Identity(
      database: namespace, provenance: provenance, epoch: normalized))))
  }

  func open(provenance: AgentKnowledgeVectorProvenance, epoch: String, token expected: UInt64,
    cacheBytes: Int = 16 * 1_024 * 1_024, root: [Float]? = nil) throws -> AgentKnowledgeNativeBridge {
    let identity = try identity(provenance: provenance, epoch: epoch)
    var directory = rootDirectory
    var key = Data()
    defer { key.wipeSensitive() }
    let exists: Bool
    Self.keyLock.lock()
    do {
      guard !destroying, generation == expected else { throw CancellationError() }
      try rejectSymbolicLink(rootDirectory)
      var master = try masterKey()
      defer { master.wipeSensitive() }
      let folder = HMAC<SHA256>.authenticationCode(for: identity, using: SymmetricKey(data: master))
        .map { String(format: "%02x", $0) }.joined()
      directory = rootDirectory.appendingPathComponent(folder, isDirectory: true)
      let derived = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: master), salt: identity,
        info: Data("galaxyssi.knowledge.native.index.v1".utf8), outputByteCount: 32)
      key = derived.withUnsafeBytes { Data($0) }
      try prepareRoot()
      try rejectSymbolicLink(directory)
      exists = FileManager.default.fileExists(atPath: directory.path)
      Self.keyLock.unlock()
    } catch {
      Self.keyLock.unlock()
      throw error
    }
    guard exists || root != nil else { throw AgentKnowledgeNativeError.invalidRecord }
    let bridge = try AgentKnowledgeNativeBridge(directory: directory, key: key, identity: identity, epoch: epoch,
      dimensions: provenance.dimensions, cacheBytes: cacheBytes, root: exists ? nil : root)
    Self.keyLock.lock()
    guard !destroying, generation == expected else {
      Self.keyLock.unlock()
      bridge.close()
      throw CancellationError()
    }
    bridges.removeAll { $0.bridge == nil }
    bridges.append(WeakBridge(bridge))
    Self.keyLock.unlock()
    return bridge
  }

  func invalidate() {
    Self.keyLock.lock()
    generation &+= 1
    let active = bridges.compactMap(\.bridge)
    bridges.removeAll()
    Self.keyLock.unlock()
    for bridge in active { bridge.cancel(); bridge.close() }
  }

  func destroy() throws {
    Self.keyLock.lock()
    destroying = true
    Self.keyLock.unlock()
    invalidate()
    Self.keyLock.lock()
    defer { destroying = false; Self.keyLock.unlock() }
    // Deleting this ThisDeviceOnly Keychain root invalidates every derived index key.
    secrets.delete(account: masterKeyAccount)
    try rejectSymbolicLink(rootDirectory)
    if FileManager.default.fileExists(atPath: rootDirectory.path) {
      try FileManager.default.removeItem(at: rootDirectory)
    }
  }

  private func masterKey() throws -> Data {
    if let encoded = secrets.string(account: masterKeyAccount) {
      guard let key = Data(base64Encoded: encoded), key.count == 32 else { throw AgentKnowledgeNativeError.invalidRecord }
      return key
    }
    // Never overwrite a missing/locked key while an existing derived index remains.
    guard !FileManager.default.fileExists(atPath: rootDirectory.path) else { throw AgentKnowledgeNativeError.invalidRecord }
    var key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    do { try secrets.setString(key.base64EncodedString(), account: masterKeyAccount) }
    catch { key.wipeSensitive(); throw error }
    return key
  }

  private func prepareRoot() throws {
    try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700],
      ofItemAtPath: rootDirectory.path)
    var root = rootDirectory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try root.setResourceValues(values)
  }

  private func rejectSymbolicLink(_ url: URL) throws {
    let attributes: [FileAttributeKey: Any]
    do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
    catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return }
    guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw AgentKnowledgeNativeError.invalidRecord }
  }
}
