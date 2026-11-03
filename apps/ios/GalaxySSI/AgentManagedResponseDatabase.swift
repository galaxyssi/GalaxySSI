import CryptoKit
import Foundation
import SQLite3

final class AgentManagedResponseDatabase {
  enum Failure: Error { case unavailable, corrupt, ambiguous }
  private let namespace: String
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private var database: OpaquePointer?

  init(fileURL: URL, storageKey: String, secrets: GalaxySSISecretStore) throws {
    namespace = Self.digest(storageKey)
    cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets,
      keyAccount: "agent.managed.response.\(namespace).aes256.v1")
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    guard sqlite3_open_v2(fileURL.path, &database,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close_v2(database) }
      database = nil
      throw Failure.unavailable
    }
    sqlite3_busy_timeout(database, 5_000)
    var initialized = false
    defer {
      if !initialized, let database {
        sqlite3_close_v2(database)
        self.database = nil
      }
    }
    try execute("PRAGMA journal_mode = WAL")
    try execute("PRAGMA synchronous = FULL")
    try execute("PRAGMA fullfsync = ON")
    try execute("""
      CREATE TABLE IF NOT EXISTS managed_responses (
        namespace TEXT NOT NULL, owner_key TEXT NOT NULL, source_id INTEGER NOT NULL,
        generation INTEGER NOT NULL, supervisor_key TEXT NOT NULL, state TEXT NOT NULL,
        updated_at INTEGER NOT NULL, encrypted_payload BLOB NOT NULL,
        PRIMARY KEY(namespace, owner_key))
      """)
    try execute("CREATE INDEX IF NOT EXISTS managed_response_source ON managed_responses(namespace,source_id,generation)")
    try execute("CREATE INDEX IF NOT EXISTS managed_response_supervisor ON managed_responses(namespace,supervisor_key,state)")
    try execute("CREATE INDEX IF NOT EXISTS managed_response_retention ON managed_responses(namespace,state,updated_at,owner_key)")
    try execute("CREATE TABLE IF NOT EXISTS managed_response_migrations (namespace TEXT PRIMARY KEY)")
    initialized = true
  }

  deinit { if let database { sqlite3_close_v2(database) } }

  // The ledger serializes all callers; BEGIN IMMEDIATE also protects other database handles.
  func transaction<T>(_ operation: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute("ROLLBACK") } }
    let result = try operation()
    try execute("COMMIT")
    committed = true
    return result
  }

  func initialized() throws -> Bool {
    let statement = try prepare("SELECT namespace FROM managed_response_migrations WHERE namespace=?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    switch sqlite3_step(statement) {
    case SQLITE_ROW: return true
    case SQLITE_DONE: return false
    default: throw Failure.unavailable
    }
  }

  func markInitialized() throws {
    let statement = try prepare("INSERT OR IGNORE INTO managed_response_migrations(namespace) VALUES(?)")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    try finish(statement)
  }

  func records(supervisor: String? = nil) throws -> [AgentManagedResponseRecord] {
    try select(clause: supervisor == nil ? "" : " AND supervisor_key=?",
      strings: supervisor.map { [Self.digest($0)] } ?? [])
  }

  func owner(_ owner: String) throws -> AgentManagedResponseRecord? {
    try select(clause: " AND owner_key=?", strings: [Self.digest(owner)]).first
  }

  func pendingPage(after: String, limit: Int) throws -> (records: [AgentManagedResponseRecord], next: String?) {
    let size = min(32, max(1, limit))
    let records = try select(clause: " AND state='PENDING' AND owner_key>? ORDER BY owner_key LIMIT ?",
      strings: [after], numbers: [Int64(size + 1)])
    let retained = Array(records.prefix(size))
    return (retained, records.count > size ? retained.last.map { Self.digest($0.ownerRunId) } : nil)
  }

  func matching(_ response: AgentConnectorResponse) throws -> AgentManagedResponseRecord? {
    let records = try select(clause: " AND source_id=? AND generation=?",
      numbers: [response.sourceMessageId, response.executionGeneration]).filter { $0.correlates(response) }
    guard records.count <= 1 else { throw Failure.ambiguous }
    return records.first
  }

  func put(_ record: AgentManagedResponseRecord) throws {
    let owner = Self.digest(record.ownerRunId)
    let encrypted = try cipher.encrypt(JSONEncoder().encode(record), purpose: purpose(owner))
    let statement = try prepare("""
      INSERT INTO managed_responses(namespace,owner_key,source_id,generation,supervisor_key,state,updated_at,encrypted_payload)
      VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(namespace,owner_key) DO UPDATE SET
        source_id=excluded.source_id,generation=excluded.generation,supervisor_key=excluded.supervisor_key,
        state=excluded.state,updated_at=excluded.updated_at,encrypted_payload=excluded.encrypted_payload
      """)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(owner, at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, record.sourceMessageId)
    sqlite3_bind_int64(statement, 4, record.executionGeneration)
    bind(Self.digest(record.supervisorRunId), at: 5, to: statement)
    bind(record.state.rawValue, at: 6, to: statement)
    sqlite3_bind_int64(statement, 7, max(record.createdAtMillis, record.completedAtMillis))
    _ = encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 8, $0.baseAddress, Int32($0.count), Self.transient) }
    try finish(statement)
  }

  func remove(owner: String) throws {
    let statement = try prepare("DELETE FROM managed_responses WHERE namespace=? AND owner_key=?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    bind(Self.digest(owner), at: 2, to: statement)
    try finish(statement)
  }

  func clear() throws {
    let statement = try prepare("DELETE FROM managed_responses WHERE namespace=?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    try finish(statement)
    try markInitialized()
  }

  func pruneApplied(cutoff: Int64) throws {
    let statement = try prepare("DELETE FROM managed_responses WHERE namespace=? AND state='APPLIED' AND updated_at<?")
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    sqlite3_bind_int64(statement, 2, cutoff)
    try finish(statement)
    let excess = try prepare("""
      DELETE FROM managed_responses WHERE namespace=? AND owner_key IN
        (SELECT owner_key FROM managed_responses WHERE namespace=? AND state='APPLIED'
         ORDER BY updated_at DESC,owner_key DESC LIMIT -1 OFFSET 512)
      """)
    defer { sqlite3_finalize(excess) }
    bind(namespace, at: 1, to: excess)
    bind(namespace, at: 2, to: excess)
    try finish(excess)
  }

  private func select(clause: String, strings: [String] = [], numbers: [Int64] = []) throws -> [AgentManagedResponseRecord] {
    let statement = try prepare("SELECT owner_key,source_id,generation,supervisor_key,state,encrypted_payload FROM managed_responses WHERE namespace=?" + clause)
    defer { sqlite3_finalize(statement) }
    bind(namespace, at: 1, to: statement)
    for (offset, value) in strings.enumerated() { bind(value, at: Int32(offset + 2), to: statement) }
    for (offset, value) in numbers.enumerated() { sqlite3_bind_int64(statement, Int32(offset + strings.count + 2), value) }
    var records: [AgentManagedResponseRecord] = []
    while true {
      let status = sqlite3_step(statement)
      if status == SQLITE_DONE { return records }
      guard status == SQLITE_ROW else { throw Failure.unavailable }
      guard let owner = sqlite3_column_text(statement, 0),
            let supervisor = sqlite3_column_text(statement, 3), let state = sqlite3_column_text(statement, 4),
            let blob = sqlite3_column_blob(statement, 5) else { throw Failure.corrupt }
      let ownerKey = String(cString: owner)
      let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 5)))
      let plaintext = try cipher.decrypt(data, purpose: purpose(ownerKey))
      let record = try JSONDecoder().decode(AgentManagedResponseRecord.self, from: plaintext)
      guard Self.digest(record.ownerRunId) == ownerKey,
            record.sourceMessageId == sqlite3_column_int64(statement, 1),
            record.executionGeneration == sqlite3_column_int64(statement, 2),
            Self.digest(record.supervisorRunId) == String(cString: supervisor),
            record.state.rawValue == String(cString: state) else { throw Failure.corrupt }
      records.append(record)
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer {
    guard let database else { throw Failure.unavailable }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Failure.unavailable }
    return statement
  }
  private func execute(_ sql: String) throws {
    guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.unavailable }
  }
  private func finish(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.unavailable }
  }
  private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) {
    _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, Self.transient) }
  }
  private func purpose(_ owner: String) -> String { "managed-response:\(namespace):\(owner)" }
  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  static func defaultFileURL() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return root.appendingPathComponent("GalaxySSI/AgentRecovery/managed-responses.sqlite3")
  }
}
