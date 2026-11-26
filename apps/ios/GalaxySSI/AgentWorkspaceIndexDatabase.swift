import CryptoKit
import Foundation
import SQLite3

// The owner holds a same-path gate. Revision reads and writes additionally share
// one SQLite transaction so other handles cannot compare against a stale revision.
final class AgentWorkspaceIndexDatabase {
  enum Failure: Error { case unavailable, corrupt }
  private struct Metadata: Codable, Equatable {
    var id: String
    var updated: Int64
    var created: Int64
    var revision: Int64
    var terminal: Bool
    var recoverable: Bool
    var characters: Int
  }
  private var database: OpaquePointer?
  private let key: SymmetricKey
  private let indexKey: SymmetricKey
  private let namespace: String
  private let beforeCommit: () throws -> Void
  private let didDecodeBody: () -> Void

  init(url: URL, master: SymmetricKey, identity: String, beforeCommit: @escaping () throws -> Void = {},
    didDecodeBody: @escaping () -> Void = {}) throws {
    guard url.isFileURL else { throw Failure.unavailable }
    let salt = Data(identity.utf8)
    namespace = SHA256.hash(data: salt).map { String(format: "%02x", $0) }.joined()
    key = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt,
      info: Data("galaxyssi.workspace.rows.v1".utf8), outputByteCount: 32)
    indexKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: master, salt: salt,
      info: Data("galaxyssi.workspace.keys.v1".utf8), outputByteCount: 32)
    self.beforeCommit = beforeCommit
    self.didDecodeBody = didDecodeBody
    let directory = url.deletingLastPathComponent()
    for candidate in [directory, url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
      try Self.rejectLink(candidate)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
      .posixPermissions: 0o700], ofItemAtPath: directory.path)
    var folder = directory, resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try folder.setResourceValues(resources)
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let database { sqlite3_close_v2(database) }; database = nil; throw Failure.unavailable
    }
    var ready = false
    defer { if !ready, let database { sqlite3_close_v2(database); self.database = nil } }
    sqlite3_busy_timeout(database, 5_000)
    for sql in ["PRAGMA journal_mode=WAL", "PRAGMA synchronous=FULL", "PRAGMA fullfsync=ON",
      "PRAGMA cache_size=-512", "PRAGMA mmap_size=0",
      "CREATE TABLE IF NOT EXISTS workspace_rows(workspace_key TEXT PRIMARY KEY,updated INTEGER NOT NULL,created INTEGER NOT NULL,revision INTEGER NOT NULL,terminal INTEGER NOT NULL,recoverable INTEGER NOT NULL,characters INTEGER NOT NULL,metadata BLOB NOT NULL,payload BLOB NOT NULL)",
      "CREATE INDEX IF NOT EXISTS workspace_recency ON workspace_rows(updated,created,workspace_key)",
      "CREATE INDEX IF NOT EXISTS workspace_recovery ON workspace_rows(recoverable,updated DESC)",
      "CREATE TABLE IF NOT EXISTS workspace_migration(id INTEGER PRIMARY KEY CHECK(id=1),payload BLOB NOT NULL)"] { try execute(sql) }
    for path in [url.path, url.path + "-wal", url.path + "-shm"] where FileManager.default.fileExists(atPath: path) {
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
        .posixPermissions: 0o600], ofItemAtPath: path)
    }
    ready = true
  }
  deinit { if let database { sqlite3_close_v2(database) } }

  static func rejectLink(_ url: URL) throws {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { throw Failure.corrupt }
    } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return }
  }

  func initialize(allowImport: Bool, legacy: () throws -> [AgentWorkspace]) throws {
    if try initialized() { return }
    guard allowImport else { throw Failure.corrupt }
    try transaction {
      if try initialized() { return }
      guard try scalar("SELECT COUNT(*) FROM workspace_rows") == 0 else { throw Failure.corrupt }
      let values = try legacy()
      guard values.count <= AgentWorkspaceBoundsPolicy.maxWorkspaces,
        Set(values.map(\.workspaceId)).count == values.count else { throw Failure.corrupt }
      for value in try AgentWorkspaceStoreBounds.fitSerializedLimit(values) { try put(value) }
      let statement = try prepare("INSERT INTO workspace_migration(id,payload) VALUES(1,?)")
      defer { sqlite3_finalize(statement) }
      try bind(seal(Data(namespace.utf8), purpose: "migration"), 1, statement)
      try finish(statement)
    }
  }

  func transaction<T>(willWrite: () -> Bool = { true }, _ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    var committed = false
    defer { if !committed { try? execute("ROLLBACK") } }
    let result = try body()
    if willWrite() { try beforeCommit() }
    try execute("COMMIT")
    committed = true
    return result
  }

  func workspace(_ id: String) throws -> AgentWorkspace? {
    try select(id: id).first
  }
  func records(recoverableOnly: Bool = false) throws -> [AgentWorkspace] {
    try select(recoverableOnly: recoverableOnly).sorted {
      if $0.updatedAtMillis != $1.updatedAtMillis { return $0.updatedAtMillis > $1.updatedAtMillis }
      if $0.createdAtMillis != $1.createdAtMillis { return $0.createdAtMillis > $1.createdAtMillis }
      return $0.workspaceId < $1.workspaceId
    }
  }

  // Retention needs only small authenticated metadata, not every plan/event/body.
  func persist(_ workspace: AgentWorkspace) throws {
    let added = try metadata(workspace)
    var retained = try metadataRows().filter { $0.id != workspace.workspaceId } + [added]
    retained.sort(by: oldestFirst)
    let count = AgentWorkspaceBoundsPolicy.maxWorkspaces
    if retained.count > count { retained.removeFirst(retained.count - count) }
    let envelope = AgentWorkspaceJsonCodec.emptyDocument().count
    func serializedCharacters() -> Int { envelope + retained.reduce(0) { $0 + $1.characters } + max(0, retained.count - 1) }
    while retained.count > 1 && serializedCharacters() > AgentWorkspaceJsonCodec.maxSerializedCharacters {
      retained.remove(at: retained.firstIndex(where: { $0.terminal }) ?? 0)
    }
    var persisted = workspace
    if retained.count == 1 && serializedCharacters() > AgentWorkspaceJsonCodec.maxSerializedCharacters {
      guard retained[0].id == workspace.workspaceId,
        let fitted = try AgentWorkspaceStoreBounds.fitSerializedLimit([workspace]).first else { throw Failure.corrupt }
      persisted = fitted
      retained[0] = try metadata(fitted)
    }
    guard serializedCharacters() <= AgentWorkspaceJsonCodec.maxSerializedCharacters else { throw Failure.corrupt }
    let ids = Set(retained.map(\.id))
    for old in try metadataRows() where !ids.contains(old.id) { try remove(old.id) }
    if ids.contains(workspace.workspaceId) { try put(persisted) }
    else { try remove(workspace.workspaceId) }
  }
  func remove(_ id: String) throws {
    let s = try prepare("DELETE FROM workspace_rows WHERE workspace_key=?")
    defer { sqlite3_finalize(s) }
    try bind(opaque(id), 1, s); try finish(s)
  }
  func clear() throws { try execute("DELETE FROM workspace_rows") }
  func count() throws -> Int64 { try scalar("SELECT COUNT(*) FROM workspace_rows") }

  private func initialized() throws -> Bool {
    let s = try prepare("SELECT payload FROM workspace_migration WHERE id=1")
    defer { sqlite3_finalize(s) }
    switch sqlite3_step(s) {
    case SQLITE_DONE: return false
    case SQLITE_ROW:
      guard try open(blob(s, 0), purpose: "migration") == Data(namespace.utf8) else { throw Failure.corrupt }
      return true
    default: throw Failure.unavailable
    }
  }
  private func oldestFirst(_ a: Metadata, _ b: Metadata) -> Bool {
    if a.updated != b.updated { return a.updated < b.updated }
    if a.created != b.created { return a.created < b.created }
    return a.id < b.id
  }
  private func metadata(_ value: AgentWorkspace) throws -> Metadata {
    guard AgentWorkspaceBoundsPolicy.normalizeOrNil(value) == value else { throw Failure.corrupt }
    return Metadata(id: value.workspaceId, updated: value.updatedAtMillis, created: value.createdAtMillis,
      revision: value.revision, terminal: value.status.isTerminal,
      recoverable: !value.status.isTerminal && !value.cancellationRequested,
      characters: AgentWorkspaceJsonCodec.encodeList([value]).count - AgentWorkspaceJsonCodec.emptyDocument().count)
  }
  private func metadataRows() throws -> [Metadata] {
    let s = try prepare("SELECT workspace_key,updated,created,revision,terminal,recoverable,characters,metadata FROM workspace_rows LIMIT 65")
    defer { sqlite3_finalize(s) }
    var values: [Metadata] = []
    while true {
      let status = sqlite3_step(s)
      if status == SQLITE_DONE { return values }
      guard status == SQLITE_ROW, values.count < AgentWorkspaceBoundsPolicy.maxWorkspaces else { throw Failure.corrupt }
      values.append(try readMetadata(s))
    }
  }
  private func readMetadata(_ s: OpaquePointer) throws -> Metadata {
    guard let text = sqlite3_column_text(s, 0) else { throw Failure.corrupt }
    let id = String(cString: text)
    let value = try JSONDecoder().decode(Metadata.self, from: open(blob(s, 7, maximum: 16_384), purpose: "metadata:" + id))
    guard opaque(value.id) == id, !value.id.isEmpty,
      value.id.count <= AgentWorkspaceBoundsPolicy.maxIdentifierCharacters,
      value.updated >= 0, value.created >= 0, value.revision >= 0,
      value.characters >= 0, value.characters <= AgentWorkspaceJsonCodec.maxSerializedCharacters,
      !value.recoverable || !value.terminal,
      value.updated == sqlite3_column_int64(s, 1), value.created == sqlite3_column_int64(s, 2),
      value.revision == sqlite3_column_int64(s, 3), (value.terminal ? 1 : 0) == sqlite3_column_int(s, 4),
      (value.recoverable ? 1 : 0) == sqlite3_column_int(s, 5), Int64(value.characters) == sqlite3_column_int64(s, 6) else { throw Failure.corrupt }
    return value
  }
  private func select(id: String? = nil, recoverableOnly: Bool = false) throws -> [AgentWorkspace] {
    let clause = id == nil ? (recoverableOnly ? " WHERE recoverable=1" : "") : " WHERE workspace_key=?"
    let s = try prepare("SELECT workspace_key,updated,created,revision,terminal,recoverable,characters,metadata,payload FROM workspace_rows" + clause + " LIMIT 65")
    defer { sqlite3_finalize(s) }
    if let id { try bind(opaque(id), 1, s) }
    var values: [AgentWorkspace] = []
    while true {
      let status = sqlite3_step(s)
      if status == SQLITE_DONE { return values }
      guard status == SQLITE_ROW, values.count < AgentWorkspaceBoundsPolicy.maxWorkspaces else { throw Failure.corrupt }
      let meta = try readMetadata(s)
      guard id == nil || meta.id == id, !recoverableOnly || meta.recoverable,
        let raw = String(data: try open(blob(s, 8), purpose: "workspace:" + opaque(meta.id)), encoding: .utf8),
        let value = AgentWorkspaceJsonCodec.decode(raw), try metadata(value) == meta else { throw Failure.corrupt }
      didDecodeBody()
      values.append(value)
    }
  }
  private func put(_ value: AgentWorkspace) throws {
    let meta = try metadata(value), id = opaque(value.workspaceId)
    let payload = Data(try AgentWorkspaceJsonCodec.encode(value).utf8)
    guard payload.count <= 17_000_000 else { throw Failure.corrupt }
    let s = try prepare("INSERT OR REPLACE INTO workspace_rows(workspace_key,updated,created,revision,terminal,recoverable,characters,metadata,payload) VALUES(?,?,?,?,?,?,?,?,?)")
    defer { sqlite3_finalize(s) }
    try bind(id, 1, s); sqlite3_bind_int64(s, 2, meta.updated); sqlite3_bind_int64(s, 3, meta.created)
    sqlite3_bind_int64(s, 4, meta.revision); sqlite3_bind_int(s, 5, meta.terminal ? 1 : 0)
    sqlite3_bind_int(s, 6, meta.recoverable ? 1 : 0); sqlite3_bind_int64(s, 7, Int64(meta.characters))
    try bind(seal(JSONEncoder().encode(meta), purpose: "metadata:" + id), 8, s)
    try bind(seal(payload, purpose: "workspace:" + id), 9, s); try finish(s)
  }
  private func opaque(_ id: String) -> String {
    HMAC<SHA256>.authenticationCode(for: Data(id.utf8), using: indexKey).map { String(format: "%02x", $0) }.joined()
  }
  private func aad(_ purpose: String) -> Data { Data("galaxyssi.workspace-index.v1:\(namespace):\(purpose)".utf8) }
  private func seal(_ data: Data, purpose: String) throws -> Data {
    guard let value = try AES.GCM.seal(data, using: key, authenticating: aad(purpose)).combined else { throw Failure.corrupt }
    return value
  }
  private func open(_ data: Data, purpose: String) throws -> Data {
    try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad(purpose))
  }
  private func blob(_ s: OpaquePointer, _ column: Int32, maximum: Int = 17_001_000) throws -> Data {
    let count = Int(sqlite3_column_bytes(s, column))
    guard (1...maximum).contains(count), let bytes = sqlite3_column_blob(s, column) else { throw Failure.corrupt }
    return Data(bytes: bytes, count: count)
  }
  private func prepare(_ sql: String) throws -> OpaquePointer {
    var s: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &s, nil) == SQLITE_OK, let s else { throw Failure.unavailable }
    return s
  }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Failure.unavailable }
  }
  private func scalar(_ sql: String) throws -> Int64 {
    let s = try prepare(sql); defer { sqlite3_finalize(s) }
    guard sqlite3_step(s) == SQLITE_ROW else { throw Failure.unavailable }
    return sqlite3_column_int64(s, 0)
  }
  private func finish(_ s: OpaquePointer) throws {
    guard sqlite3_step(s) == SQLITE_DONE else { throw Failure.unavailable }
  }
  private func bind(_ text: String, _ index: Int32, _ s: OpaquePointer) throws {
    guard text.withCString({ sqlite3_bind_text(s, index, $0, -1, Self.transient) }) == SQLITE_OK else { throw Failure.unavailable }
  }
  private func bind(_ data: Data, _ index: Int32, _ s: OpaquePointer) throws {
    guard data.withUnsafeBytes({ sqlite3_bind_blob(s, index, $0.baseAddress, Int32($0.count), Self.transient) }) == SQLITE_OK else { throw Failure.unavailable }
  }
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
