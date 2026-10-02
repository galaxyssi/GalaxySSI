import Foundation
import SQLite3

enum MqttChunkStorageError: Error {
  case databaseFailure
  case corruptState
  case capacityExceeded
}

// Shared storage for MQTT chunk and business delivery journals. Existing chunk key/schema names
// stay unchanged for compatibility. Rows contain encrypted payloads;
// only bounded quota/expiry indexes and hashed identities remain outside AEAD.
final class MqttChunkDatabase {
  enum Value { case text(String), number(Int64), blob(Data) }

  struct Row {
    fileprivate let statement: OpaquePointer

    func text(_ index: Int32) throws -> String {
      guard sqlite3_column_type(statement, index) == SQLITE_TEXT,
            let value = sqlite3_column_text(statement, index) else { throw MqttChunkStorageError.corruptState }
      return String(cString: value)
    }

    func number(_ index: Int32) throws -> Int64 {
      guard sqlite3_column_type(statement, index) == SQLITE_INTEGER else { throw MqttChunkStorageError.corruptState }
      return sqlite3_column_int64(statement, index)
    }

    func data(_ index: Int32, maximum: Int, allowEmpty: Bool = false) throws -> Data {
      let count = Int(sqlite3_column_bytes(statement, index))
      guard sqlite3_column_type(statement, index) == SQLITE_BLOB, count <= maximum else { throw MqttChunkStorageError.corruptState }
      if count == 0, allowEmpty { return Data() }
      guard count > 0, let bytes = sqlite3_column_blob(statement, index) else { throw MqttChunkStorageError.corruptState }
      return Data(bytes: bytes, count: count)
    }
  }

  private let lock = NSRecursiveLock()
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private var handle: OpaquePointer?
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private static let canary = Data("GalaxySSI/MqttChunkStore/v1".utf8)

  init(fileURL: URL, secrets: GalaxySSISecretStore) throws {
    cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "mqtt.chunks.aes256.v1")
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    guard sqlite3_open_v2(fileURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let handle { sqlite3_close_v2(handle) }
      handle = nil
      throw MqttChunkStorageError.databaseFailure
    }
    do {
      guard sqlite3_busy_timeout(handle, 5_000) == SQLITE_OK else { throw MqttChunkStorageError.databaseFailure }
      try execute("PRAGMA journal_mode = WAL")
      try execute("PRAGMA synchronous = FULL")
      try execute("PRAGMA fullfsync = ON")
      try execute("PRAGMA secure_delete = ON")
      try execute("CREATE TABLE IF NOT EXISTS mqtt_chunk_key (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
      try execute("""
        CREATE TABLE IF NOT EXISTS mqtt_wire_transfers (
          scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, total_bytes INTEGER NOT NULL,
          expires_at INTEGER NOT NULL, completed INTEGER NOT NULL, encrypted_metadata BLOB NOT NULL,
          PRIMARY KEY(scope_digest, transfer_id))
        """)
      try execute("CREATE INDEX IF NOT EXISTS mqtt_chunk_expiry ON mqtt_wire_transfers(expires_at)")
      try execute("""
        CREATE TABLE IF NOT EXISTS mqtt_wire_parts (
          scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, chunk_index INTEGER NOT NULL,
          chunk_hash TEXT NOT NULL, encrypted_data BLOB NOT NULL,
          PRIMARY KEY(scope_digest, transfer_id, chunk_index))
        """)
      try execute("""
        CREATE TABLE IF NOT EXISTS mqtt_outgoing_chunks (
          scope_digest TEXT NOT NULL, transfer_id TEXT NOT NULL, expires_at INTEGER NOT NULL,
          encrypted_metadata BLOB NOT NULL, PRIMARY KEY(scope_digest, transfer_id))
        """)
      try execute("CREATE INDEX IF NOT EXISTS mqtt_outgoing_chunk_expiry ON mqtt_outgoing_chunks(expires_at)")
      try execute("""
        CREATE TABLE IF NOT EXISTS mqtt_business_inbox (
          record_key TEXT PRIMARY KEY NOT NULL, binding_digest TEXT NOT NULL,
          completed INTEGER NOT NULL, retain_until INTEGER NOT NULL, payload_bytes INTEGER NOT NULL,
          encrypted_metadata BLOB NOT NULL)
        """)
      try execute("CREATE INDEX IF NOT EXISTS mqtt_business_inbox_pending ON mqtt_business_inbox(completed,record_key)")
      try execute("CREATE INDEX IF NOT EXISTS mqtt_business_inbox_scope ON mqtt_business_inbox(binding_digest)")
      try execute("""
        CREATE TABLE IF NOT EXISTS mqtt_business_ciphertexts (
          binding_digest TEXT NOT NULL, ciphertext_digest TEXT NOT NULL, record_key TEXT NOT NULL,
          PRIMARY KEY(binding_digest,ciphertext_digest))
        """)
      try execute("CREATE INDEX IF NOT EXISTS mqtt_business_cipher_record ON mqtt_business_ciphertexts(record_key)")
      try execute("""
        CREATE TABLE IF NOT EXISTS mqtt_business_outbox (
          record_key TEXT PRIMARY KEY NOT NULL, binding_digest TEXT NOT NULL, next_attempt_at INTEGER NOT NULL,
          payload_bytes INTEGER NOT NULL, encrypted_metadata BLOB NOT NULL)
        """)
      try execute("CREATE INDEX IF NOT EXISTS mqtt_business_outbox_schedule ON mqtt_business_outbox(binding_digest,next_attempt_at)")
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: fileURL.path)
      try transaction { () }
    } catch {
      if let handle { sqlite3_close_v2(handle) }
      handle = nil
      throw error
    }
  }

  deinit { if let handle { sqlite3_close_v2(handle) } }

  func transaction<T>(_ body: () throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }
    try execute("BEGIN IMMEDIATE")
    do {
      try verifyKey()
      let result = try body()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  func seal(_ data: Data, purpose: String) throws -> Data { try cipher.encrypt(data, purpose: purpose) }
  func open(_ data: Data, purpose: String) throws -> Data { try cipher.decrypt(data, expectedPurpose: purpose) }

  func run(_ sql: String, _ values: [Value] = []) throws {
    let statement = try prepare(sql, values)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_DONE else { throw MqttChunkStorageError.databaseFailure }
  }

  func query<T>(_ sql: String, _ values: [Value] = [], maximumRows: Int,
                read: (Row) throws -> T) throws -> [T] {
    let statement = try prepare(sql, values)
    defer { sqlite3_finalize(statement) }
    var rows: [T] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_DONE: return rows
      case SQLITE_ROW:
        guard rows.count < maximumRows else { throw MqttChunkStorageError.corruptState }
        rows.append(try read(Row(statement: statement)))
      default: throw MqttChunkStorageError.databaseFailure
      }
    }
  }

  private func verifyKey() throws {
    let saved = try query("SELECT payload FROM mqtt_chunk_key WHERE id=1", maximumRows: 1) { try $0.data(0, maximum: 8192) }.first
    if let saved {
      guard try open(saved, purpose: "mqtt-chunk-store-key") == Self.canary else { throw MqttChunkStorageError.corruptState }
    } else {
      let count = try query("SELECT (SELECT COUNT(*) FROM mqtt_wire_transfers) + (SELECT COUNT(*) FROM mqtt_wire_parts) + (SELECT COUNT(*) FROM mqtt_outgoing_chunks) + (SELECT COUNT(*) FROM mqtt_business_inbox) + (SELECT COUNT(*) FROM mqtt_business_ciphertexts) + (SELECT COUNT(*) FROM mqtt_business_outbox)",
                            maximumRows: 1) { try $0.number(0) }.first
      guard count == 0 else { throw MqttChunkStorageError.corruptState }
      let encrypted = try seal(Self.canary, purpose: "mqtt-chunk-store-key")
      try run("INSERT INTO mqtt_chunk_key(id,payload) VALUES(1,?)", [.blob(encrypted)])
    }
  }

  private func execute(_ sql: String) throws {
    guard let handle, sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw MqttChunkStorageError.databaseFailure }
  }

  private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
    guard let handle else { throw MqttChunkStorageError.databaseFailure }
    var output: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &output, nil) == SQLITE_OK, let statement = output else {
      if let output { sqlite3_finalize(output) }
      throw MqttChunkStorageError.databaseFailure
    }
    do {
      for (offset, value) in values.enumerated() {
        let index = Int32(offset + 1)
        let code: Int32
        switch value {
        case .text(let text): code = text.withCString { sqlite3_bind_text(statement, index, $0, -1, Self.transient) }
        case .number(let number): code = sqlite3_bind_int64(statement, index, number)
        case .blob(let data): code = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), Self.transient) }
        }
        guard code == SQLITE_OK else { throw MqttChunkStorageError.databaseFailure }
      }
      return statement
    } catch {
      sqlite3_finalize(statement)
      throw error
    }
  }
}
