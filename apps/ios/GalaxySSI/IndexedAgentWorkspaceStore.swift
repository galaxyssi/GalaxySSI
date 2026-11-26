import CryptoKit
import Foundation

final class IndexedAgentWorkspaceStore: AgentWorkspaceStore {
  private let legacyURL: URL
  private let secrets: GalaxySSISecretStore
  private let clock: () -> Int64
  private let timingClock: () -> Int64
  private let timingSink: AgentWorkspaceCreationTiming.Sink
  private let beforeCommit: () throws -> Void
  private let didDecodeBody: () -> Void
  private let lock: NSRecursiveLock
  private static let gatesLock = NSLock()
  private static var gates: [String: NSRecursiveLock] = [:]

  init(legacyURL: URL = FileAgentWorkspaceStore.defaultFileURL(),
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    clock: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    timingClock: @escaping () -> Int64 = AgentWorkspaceCreationTiming.monotonicMillis,
    timingSink: @escaping AgentWorkspaceCreationTiming.Sink = AgentWorkspaceCreationTiming.log,
    beforeCommit: @escaping () throws -> Void = {}, didDecodeBody: @escaping () -> Void = {}) {
    self.legacyURL = legacyURL
    self.secrets = secrets
    self.clock = clock
    self.timingClock = timingClock
    self.timingSink = timingSink
    self.beforeCommit = beforeCommit
    self.didDecodeBody = didDecodeBody
    Self.gatesLock.lock()
    let path = legacyURL.standardizedFileURL.path
    let gate = Self.gates[path] ?? NSRecursiveLock()
    Self.gates[path] = gate
    Self.gatesLock.unlock()
    lock = gate
  }

  static func databaseURL(for legacyURL: URL) -> URL {
    URL(fileURLWithPath: legacyURL.path + ".workspace-index", isDirectory: true).appendingPathComponent("workspaces.sqlite")
  }

  func list() -> [AgentWorkspace] { locked { (try? index().records()) ?? [] } }
  func recoverable() -> [AgentWorkspace] { locked { (try? index().records(recoverableOnly: true)) ?? [] } }
  func find(_ workspaceId: String) -> AgentWorkspace? {
    let id = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return nil }
    return locked { try? index().workspace(id) }
  }

  func upsert(_ workspace: AgentWorkspace, expectedRevision: Int64) throws -> AgentWorkspace {
    guard let value = try change(workspaceId: workspace.workspaceId, mayCreate: true, operation: {
      try $0.upsert(workspace, expectedRevision: expectedRevision)
    }) else { throw AgentWorkspaceIndexDatabase.Failure.corrupt }
    return value
  }
  func appendEvent(workspaceId: String, event: AgentWorkspaceEvent, expectedRevision: Int64?) throws -> AgentWorkspace? {
    try change(workspaceId: workspaceId) {
      try $0.appendEvent(workspaceId: workspaceId, event: event, expectedRevision: expectedRevision)
    }
  }
  func checkpoint(workspaceId: String, checkpoint: AgentWorkspaceCheckpoint, expectedRevision: Int64?) throws -> AgentWorkspace? {
    try change(workspaceId: workspaceId) {
      try $0.checkpoint(workspaceId: workspaceId, checkpoint: checkpoint, expectedRevision: expectedRevision)
    }
  }
  func requestCancel(_ workspaceId: String, expectedRevision: Int64?, timestampMillis: Int64) throws -> AgentWorkspace? {
    try change(workspaceId: workspaceId) {
      try $0.requestCancel(workspaceId, expectedRevision: expectedRevision, timestampMillis: timestampMillis)
    }
  }
  func delete(_ workspaceId: String, expectedRevision: Int64?) throws -> Bool {
    try locked {
      let db = try index(), id = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
      var changed = false
      try db.transaction(willWrite: { changed }) {
        guard let current = try db.workspace(id) else { return }
        let reducer = InMemoryAgentWorkspaceStore(initialWorkspaces: [current], clock: clock)
        changed = try reducer.delete(id, expectedRevision: expectedRevision)
        if changed { try db.remove(id) }
      }
      if changed { notify() }
      return changed
    }
  }
  func clear() {
    locked {
      do {
        let db = try index()
        var changed = false
        try db.transaction(willWrite: { changed }) {
          changed = try db.count() > 0
          if changed { try db.clear() }
        }
        if changed { notify() }
      } catch { /* Retain committed records if clearing fails. */ }
    }
  }

  var legacyCleanupPending: Bool { FileManager.default.fileExists(atPath: legacyURL.path) }

  private func change(workspaceId: String, mayCreate: Bool = false,
    operation: (InMemoryAgentWorkspaceStore) throws -> AgentWorkspace?) throws -> AgentWorkspace? {
    try locked {
      let started = timingClock(), db = try index()
      let id = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
      var changed = false
      var creation: (taskId: String, commitStarted: Int64)?
      let result = try db.transaction(willWrite: { changed }) {
        let current = try db.workspace(id)
        let reducer = InMemoryAgentWorkspaceStore(initialWorkspaces: current.map { [$0] } ?? [], clock: clock)
        guard let updated = try operation(reducer) else { return nil as AgentWorkspace? }
        if !mayCreate && current == updated { return updated }
        if mayCreate && current == nil { creation = (updated.taskId, timingClock()) }
        try db.persist(updated)
        changed = true
        return updated
      }
      if let creation {
        timingSink(AgentWorkspaceCreationTiming.sample(taskId: creation.taskId, started: started,
          commitStarted: creation.commitStarted, committed: timingClock(), storage: .indexedTransaction))
      }
      if changed { notify() }
      return result
    }
  }

  private func index() throws -> AgentWorkspaceIndexDatabase {
    guard legacyURL.isFileURL else { throw AgentWorkspaceIndexDatabase.Failure.unavailable }
    let url = Self.databaseURL(for: legacyURL), identity = Self.storageIdentity(for: legacyURL)
    let accounts = Self.accounts(for: identity), receipt = secrets.string(account: accounts.receipt)
    let exists = FileManager.default.fileExists(atPath: url.path)
    guard receipt == nil || receipt == "pending" || receipt == "1", receipt == nil || exists else {
      throw AgentWorkspaceIndexDatabase.Failure.corrupt
    }
    let master: SymmetricKey
    if let encoded = secrets.string(account: accounts.key) {
      guard let data = Data(base64Encoded: encoded), data.count == 32 else { throw AgentWorkspaceIndexDatabase.Failure.corrupt }
      master = SymmetricKey(data: data)
    } else {
      guard !exists, receipt == nil else { throw AgentWorkspaceIndexDatabase.Failure.unavailable }
      master = SymmetricKey(size: .bits256)
      try secrets.setString(master.withUnsafeBytes { Data($0) }.base64EncodedString(), account: accounts.key)
    }
    let db = try AgentWorkspaceIndexDatabase(url: url, master: master, identity: identity,
      beforeCommit: beforeCommit, didDecodeBody: didDecodeBody)
    if receipt == nil { try secrets.setString("pending", account: accounts.receipt) }
    try db.initialize(allowImport: receipt != "1") {
      try AgentWorkspaceIndexDatabase.rejectLink(legacyURL)
      guard FileManager.default.fileExists(atPath: legacyURL.path) else { return [] }
      let attributes = try FileManager.default.attributesOfItem(atPath: legacyURL.path)
      guard let size = attributes[.size] as? NSNumber,
        size.int64Value <= Int64(AgentWorkspaceJsonCodec.maxSerializedCharacters) * 4 else { throw AgentWorkspaceIndexDatabase.Failure.corrupt }
      let data = try Data(contentsOf: legacyURL)
      guard data.count <= AgentWorkspaceJsonCodec.maxSerializedCharacters * 4,
        let raw = String(data: data, encoding: .utf8) else { throw AgentWorkspaceIndexDatabase.Failure.corrupt }
      return try AgentWorkspaceJsonCodec.decodePersistedList(raw)
    }
    if receipt != "1" { try secrets.setString("1", account: accounts.receipt) }
    // The committed marker owns migration. Never resurrect this plaintext after
    // clear or index loss; retry an unsuccessful legacy unlink on later access.
    if FileManager.default.fileExists(atPath: legacyURL.path) { try? FileManager.default.removeItem(at: legacyURL) }
    return db
  }

  static func storageIdentity(for url: URL) -> String {
    let path = url.standardizedFileURL.pathComponents
    let roots: [(String, URL?)] = [
      ("app-support", FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first),
      ("temporary", FileManager.default.temporaryDirectory)
    ]
    for (name, root) in roots {
      guard let components = root?.standardizedFileURL.pathComponents, path.count > components.count,
        path.prefix(components.count).elementsEqual(components) else { continue }
      return name + ":" + path.dropFirst(components.count).joined(separator: "/")
    }
    return "explicit-path:" + url.standardizedFileURL.path
  }
  static func accounts(for identity: String) -> (key: String, receipt: String) {
    let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    return ("workspace.index.master.v1." + digest, "workspace.index.import.v1." + digest)
  }
  private func notify() { NotificationCenter.default.post(name: .galaxySSIWorkspaceDidPersist, object: self) }
  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock(); defer { lock.unlock() }; return try body()
  }
}
