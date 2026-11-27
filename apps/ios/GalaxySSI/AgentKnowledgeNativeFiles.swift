import CryptoKit
import Foundation
import UIKit

// The database owns one file store. Native index work uses its serial utility queue;
// privacy invalidation may run concurrently and fences late opens by generation.
final class AgentKnowledgeNativeFiles {
  final class BackgroundLease {
    fileprivate weak var owner: AgentKnowledgeNativeFiles?
    fileprivate let id = UUID()
    let token: UInt64
    fileprivate init(owner: AgentKnowledgeNativeFiles, token: UInt64) { self.owner = owner; self.token = token }
    var isValid: Bool { owner?.validBackgroundLease(self) == true }
    func end() { owner?.endBackgroundLease(self) }
    deinit { end() }
  }
  private struct Identity: Codable {
    var schema = 1
    var database: String
    var provenance: AgentKnowledgeVectorProvenance
    var epoch: String
  }
  private final class WeakBridge {
    weak var bridge: AgentKnowledgeNativeBridge?
    let leaseID: UUID?
    init(_ bridge: AgentKnowledgeNativeBridge, leaseID: UUID?) { self.bridge = bridge; self.leaseID = leaseID }
  }

  private static let keyLock = NSRecursiveLock()
  let rootDirectory: URL
  let masterKeyAccount: String
  private let namespace: String
  private let secrets: GalaxySSISecretStore
  private let notifications: NotificationCenter
  private var generation: UInt64 = 0
  private var destroying = false
  private var suspended = false
  private var protectedUnavailable = false
  private var bridges: [WeakBridge] = []
  private var backgroundLeases = Set<UUID>()
  private var observers: [NSObjectProtocol] = []

  init(databaseURL: URL, secrets: GalaxySSISecretStore, notifications: NotificationCenter = .default) {
    self.notifications = notifications
    let path = databaseURL.standardizedFileURL.path
    namespace = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    rootDirectory = URL(fileURLWithPath: path + ".native", isDirectory: true)
    masterKeyAccount = "agent.knowledge.native.master.v1.\(namespace)"
    self.secrets = secrets
    for name in [UIApplication.willResignActiveNotification, UIApplication.protectedDataWillBecomeUnavailableNotification,
      UIApplication.didBecomeActiveNotification, UIApplication.protectedDataDidBecomeAvailableNotification] {
      observers.append(notifications.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
        self?.transition(name)
      })
    }
  }

  deinit {
    for observer in observers { notifications.removeObserver(observer) }
    invalidate()
  }

  func token() -> UInt64 {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    return generation
  }

  func activeToken() -> UInt64? {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    return destroying || suspended || protectedUnavailable ? nil : generation
  }

  func readToken(backgroundLease: BackgroundLease? = nil) -> UInt64? {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    if let backgroundLease { return validBackgroundLease(backgroundLease) ? generation : nil }
    return destroying || suspended || protectedUnavailable ? nil : generation
  }

  // Only the authorized system task asks for this capability after checking
  // opt-in and UIKit protected-data availability. It never enables UI queries.
  func beginBackgroundLease() throws -> BackgroundLease {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    guard !destroying, !protectedUnavailable else { throw CancellationError() }
    let lease = BackgroundLease(owner: self, token: generation)
    backgroundLeases.insert(lease.id)
    return lease
  }

  private func validBackgroundLease(_ lease: BackgroundLease) -> Bool {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    return !destroying && !protectedUnavailable && lease.owner === self && lease.token == generation && backgroundLeases.contains(lease.id)
  }

  private func endBackgroundLease(_ lease: BackgroundLease) {
    Self.keyLock.lock()
    backgroundLeases.remove(lease.id)
    let active = bridges.filter { $0.leaseID == lease.id }.compactMap(\.bridge)
    bridges.removeAll { $0.leaseID == lease.id }
    Self.keyLock.unlock()
    for bridge in active { bridge.cancel(); bridge.close() }
  }

  private func allows(_ expected: UInt64, lease: BackgroundLease?) -> Bool {
    guard !destroying, !protectedUnavailable, generation == expected else { return false }
    if let lease { return validBackgroundLease(lease) }
    return !suspended
  }

  private func transition(_ name: Notification.Name) {
    Self.keyLock.lock()
    var retired: [AgentKnowledgeNativeBridge] = []
    if name == UIApplication.willResignActiveNotification { suspended = true }
    if name == UIApplication.didBecomeActiveNotification {
      suspended = false
      retired = bridges.filter { $0.leaseID != nil }.compactMap(\.bridge)
      bridges.removeAll { $0.leaseID != nil }
      backgroundLeases.removeAll()
    }
    if name == UIApplication.protectedDataWillBecomeUnavailableNotification { protectedUnavailable = true }
    if name == UIApplication.protectedDataDidBecomeAvailableNotification { protectedUnavailable = false }
    let cancel = suspended || protectedUnavailable
    Self.keyLock.unlock()
    for bridge in retired { bridge.cancel(); bridge.close() }
    if cancel { invalidate() }
  }

  func identity(provenance: AgentKnowledgeVectorProvenance, epoch: String) throws -> Data {
    let normalized = try AgentKnowledgeNativeWire.epoch(epoch).map { String(format: "%02x", $0) }.joined()
    return Data(SHA256.hash(data: try JSONEncoder.galaxySSI.encode(Identity(
      database: namespace, provenance: provenance, epoch: normalized))))
  }

  func open(provenance: AgentKnowledgeVectorProvenance, epoch: String, token expected: UInt64,
    cacheBytes: Int = 16 * 1_024 * 1_024, root: [Float]? = nil,
    backgroundLease: BackgroundLease? = nil) throws -> AgentKnowledgeNativeBridge? {
    let identity = try identity(provenance: provenance, epoch: epoch)
    var directory = rootDirectory
    var key = Data()
    defer { key.wipeSensitive() }
    let exists: Bool
    Self.keyLock.lock()
    do {
      guard allows(expected, lease: backgroundLease) else { throw CancellationError() }
      try rejectSymbolicLink(rootDirectory)
      if root == nil && !FileManager.default.fileExists(atPath: rootDirectory.path) {
        Self.keyLock.unlock()
        return nil
      }
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
    guard exists || root != nil else { return nil }
    let bridge = try AgentKnowledgeNativeBridge(directory: directory, key: key, identity: identity, epoch: epoch,
      dimensions: provenance.dimensions, cacheBytes: cacheBytes, root: exists ? nil : root)
    Self.keyLock.lock()
    guard allows(expected, lease: backgroundLease) else {
      Self.keyLock.unlock()
      bridge.close()
      throw CancellationError()
    }
    bridges.removeAll { $0.bridge == nil }
    bridges.append(WeakBridge(bridge, leaseID: backgroundLease?.id))
    Self.keyLock.unlock()
    return bridge
  }

  func invalidate() {
    Self.keyLock.lock()
    generation &+= 1
    backgroundLeases.removeAll()
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
