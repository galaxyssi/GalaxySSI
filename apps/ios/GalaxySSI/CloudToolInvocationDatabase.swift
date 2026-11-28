import Darwin
import Foundation
import SQLite3

final class CloudToolInvocationDatabase: AgentModelLoopJournal {
  private final class WeakDatabase {
    weak var value: CloudToolInvocationDatabase?
    init(_ value: CloudToolInvocationDatabase) { self.value = value }
  }
  private static let stateLock = NSRecursiveLock()
  private static var generation: UInt64 = 0
  private static var instances: [WeakDatabase] = []
  private let fileURL: URL?
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(fileURL: URL? = nil, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.fileURL = fileURL
    cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: Self.keyAccount(fileURL))
    Self.stateLock.lock()
    Self.instances.removeAll { $0.value == nil }
    Self.instances.append(WeakDatabase(self))
    Self.stateLock.unlock()
  }

  deinit { if let database { sqlite3_close_v2(database) } }

  func hasRecords(scope: AgentModelLoopScope) throws -> Bool {
    try read(scope.digest, operation: "cloud-tool-input") != nil
  }

  func withLease<T>(scope: AgentModelLoopScope, _ operation: (AgentModelLoopRecords) async throws -> T) async throws -> T {
    let lease = try acquireLease(scope: scope)
    defer { _ = Darwin.flock(lease.fd, LOCK_UN); Darwin.close(lease.fd) }
    return try await operation(Records(owner: self, scope: scope.digest, generation: lease.generation))
  }

  private func acquireLease(scope: AgentModelLoopScope) throws -> (fd: Int32, generation: UInt64) {
    Self.stateLock.lock(); defer { Self.stateLock.unlock() }
    let directory = try location().deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
    let leaseURL = directory.appendingPathComponent(try location().lastPathComponent + "." + scope.digest + ".lock")
    let fd = Darwin.open(leaseURL.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable") }
    guard Darwin.flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(fd)
      throw AgentModelLoopRecoveryError(code: "model_loop_busy")
    }
    return (fd, Self.generation)
  }

  static func destroyPersistentStore(fileURL: URL? = nil, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    stateLock.lock(); defer { stateLock.unlock() }
    generation &+= 1
    for instance in instances.compactMap(\.value) where instance.fileURL == fileURL {
      instance.lock.lock()
      if let database = instance.database { sqlite3_close_v2(database); instance.database = nil }
      instance.cipher.destroyEncryptionKey()
      instance.lock.unlock()
    }
    GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: keyAccount(fileURL)).destroyEncryptionKey()
    if let fileURL {
      for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: fileURL.path + suffix) }
    } else if let root = try? defaultLocation().deletingLastPathComponent() {
      try? FileManager.default.removeItem(at: root)
    }
  }

  private static func keyAccount(_ fileURL: URL?) -> String {
    "cloud.tool-invocations.aes256.v1." + (fileURL.map { AgentModelLoopRecoveryIdentity.sha256($0.standardizedFileURL.path) } ?? "default")
  }

  private static func defaultLocation() throws -> URL {
    try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true).appendingPathComponent("GalaxySSI/CloudToolInvocations/journal.sqlite")
  }

  private func location() throws -> URL {
    if let fileURL { return fileURL }
    return try Self.defaultLocation()
  }

  private func connection() throws -> OpaquePointer {
    if let database { return database }
    let url = try location()
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    var opened: OpaquePointer?
    guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
      let opened else {
      if let opened { sqlite3_close_v2(opened) }
      throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable")
    }
    var ready = false
    defer { if !ready { sqlite3_close_v2(opened) } }
    sqlite3_busy_timeout(opened, 5_000)
    try execute("PRAGMA journal_mode = WAL", database: opened)
    try execute("PRAGMA synchronous = FULL", database: opened)
    try execute("PRAGMA fullfsync = ON", database: opened)
    try execute("CREATE TABLE IF NOT EXISTS cloud_tool_records (scope TEXT NOT NULL, operation TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(scope, operation))", database: opened)
    for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path + suffix)
    }
    database = opened
    ready = true
    return opened
  }

  private func execute(_ sql: String, database: OpaquePointer) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable")
    }
  }

  private func purpose(_ scope: String, _ operation: String) -> String {
    "galaxyssi.cloud-tool-invocation.v1." + scope + "." + AgentModelLoopRecoveryIdentity.sha256(operation)
  }

  private func read(_ scope: String, operation: String, generation: UInt64? = nil) throws -> Data? {
    Self.stateLock.lock(); defer { Self.stateLock.unlock() }
    if let generation, generation != Self.generation { throw AgentModelLoopRecoveryError(code: "cloud_tool_store_reset") }
    lock.lock(); defer { lock.unlock() }
    let database = try connection()
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "SELECT payload FROM cloud_tool_records WHERE scope=? AND operation=?", -1, &statement, nil) == SQLITE_OK,
      let statement else { throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable") }
    defer { sqlite3_finalize(statement) }
    try bind(scope, index: 1, statement: statement)
    try bind(operation, index: 2, statement: statement)
    switch sqlite3_step(statement) {
    case SQLITE_DONE: return nil
    case SQLITE_ROW:
      guard let bytes = sqlite3_column_blob(statement, 0), sqlite3_column_bytes(statement, 0) > 0 else {
        throw AgentModelLoopRecoveryError(code: "cloud_tool_record_unreadable")
      }
      return try cipher.decrypt(Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))),
        expectedPurpose: purpose(scope, operation))
    default: throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable")
    }
  }

  private func bind(_ value: String, index: Int32, statement: OpaquePointer) throws {
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
      throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable")
    }
  }

  private func write(_ scope: String, operation: String, data: Data, generation: UInt64) throws {
    Self.stateLock.lock(); defer { Self.stateLock.unlock() }
    guard generation == Self.generation else { throw AgentModelLoopRecoveryError(code: "cloud_tool_store_reset") }
    lock.lock(); defer { lock.unlock() }
    let database = try connection()
    try execute("BEGIN IMMEDIATE TRANSACTION", database: database)
    var committed = false
    defer { if !committed { try? execute("ROLLBACK", database: database) } }
    if let existing = try read(scope, operation: operation) {
      guard existing == data else { throw AgentModelLoopRecoveryError(code: "model_loop_record_changed") }
    } else {
      let encrypted = try cipher.encrypt(data, purpose: purpose(scope, operation))
      guard encrypted.count <= Int(Int32.max) else { throw AgentModelLoopRecoveryError(code: "cloud_tool_record_too_large") }
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(database, "INSERT INTO cloud_tool_records(scope,operation,payload) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK,
        let statement else { throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable") }
      defer { sqlite3_finalize(statement) }
      try bind(scope, index: 1, statement: statement)
      try bind(operation, index: 2, statement: statement)
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      let bound = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), transient) }
      guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
        throw AgentModelLoopRecoveryError(code: "cloud_tool_journal_unavailable")
      }
    }
    try execute("COMMIT", database: database)
    committed = true
  }

  private final class Records: AgentModelLoopRecords {
    let owner: CloudToolInvocationDatabase
    let scope: String
    let generation: UInt64
    init(owner: CloudToolInvocationDatabase, scope: String, generation: UInt64) {
      self.owner = owner; self.scope = scope; self.generation = generation
    }
    func read(_ operation: String) throws -> Data? { try owner.read(scope, operation: operation, generation: generation) }
    func write(_ operation: String, data: Data) throws { try owner.write(scope, operation: operation, data: data, generation: generation) }
  }
}
