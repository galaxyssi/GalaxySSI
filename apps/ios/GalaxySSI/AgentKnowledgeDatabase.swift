import CryptoKit
import Foundation
import SQLite3

enum AgentKnowledgeDatabaseError: Error, Equatable {
  case unavailable
  case corruptRecord
}

final class AgentKnowledgeDatabase {
  private let fileURL: URL
  private let secrets: GalaxySSISecretStore
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.fileURL = fileURL
    self.secrets = secrets
    cipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.knowledge.row.aes256.v1"
    )
    open()
  }

  deinit {
    if let database { sqlite3_close_v2(database) }
  }

  func all() throws -> [AgentKnowledgeItem] {
    try locked {
      guard let statement = prepare("""
        SELECT item_hash, encrypted_payload FROM knowledge_items
        ORDER BY updated_at ASC, item_hash ASC
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      var items: [AgentKnowledgeItem] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let hashText = sqlite3_column_text(statement, 0),
              let encrypted = blob(statement, column: 1) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let itemHash = String(cString: hashText)
        guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: purpose(itemHash)),
              let item = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeItem.self, from: plaintext),
              keyedHash(item.id) == itemHash else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        items.append(item)
      }
      return items
    }
  }

  @discardableResult
  func replaceAll(_ items: [AgentKnowledgeItem]) -> Bool {
    locked {
      guard validateIdentities(items), execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
      guard execute("DELETE FROM knowledge_items") else {
        _ = execute("ROLLBACK")
        return false
      }
      for item in items where !insert(item) {
        _ = execute("ROLLBACK")
        return false
      }
      guard execute("COMMIT") else {
        _ = execute("ROLLBACK")
        return false
      }
      return true
    }
  }

  private func insert(_ item: AgentKnowledgeItem) -> Bool {
    let itemHash = keyedHash(item.id)
    guard let plaintext = try? JSONEncoder.galaxySSI.encode(item),
          let encrypted = try? cipher.encrypt(plaintext, purpose: purpose(itemHash)),
          let statement = prepare("""
            INSERT INTO knowledge_items(item_hash, source_hash, updated_at, encrypted_payload)
            VALUES (?, ?, ?, ?)
            """) else { return false }
    defer { sqlite3_finalize(statement) }
    bind(itemHash, at: 1, to: statement)
    bind(keyedHash(item.source), at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, item.updatedAtMillis)
    encrypted.withUnsafeBytes { bytes in
      sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(encrypted.count), Self.transient)
    }
    return sqlite3_step(statement) == SQLITE_DONE
  }

  private func validateIdentities(_ items: [AgentKnowledgeItem]) -> Bool {
    var sourcesById: [String: String] = [:]
    for item in items {
      if let source = sourcesById[item.id], source != item.source { return false }
      if sourcesById[item.id] != nil { return false }
      sourcesById[item.id] = item.source
    }
    return true
  }

  private func open() {
    try? FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    guard sqlite3_open_v2(
      fileURL.path,
      &database,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK else { database = nil; return }
    sqlite3_busy_timeout(database, 5_000)
    _ = execute("PRAGMA journal_mode = WAL")
    _ = execute("PRAGMA synchronous = FULL")
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_items (
        item_hash TEXT PRIMARY KEY NOT NULL,
        source_hash TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        encrypted_payload BLOB NOT NULL
      )
      """)
    _ = execute("CREATE INDEX IF NOT EXISTS knowledge_source_idx ON knowledge_items(source_hash, updated_at)")
  }

  private func keyedHash(_ value: String) -> String {
    HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: indexKey())
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func indexKey() -> SymmetricKey {
    let account = "agent.knowledge.index.hmac256.v1"
    if let encoded = secrets.string(account: account),
       let data = Data(base64Encoded: encoded), data.count == 32 {
      return SymmetricKey(data: data)
    }
    let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
    try? secrets.setString(data.base64EncodedString(), account: account)
    return SymmetricKey(data: data)
  }

  private func purpose(_ itemHash: String) -> String { "agent-knowledge:\(itemHash)" }

  private func prepare(_ sql: String) -> OpaquePointer? {
    guard let database else { return nil }
    var statement: OpaquePointer?
    return sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK ? statement : nil
  }

  private func execute(_ sql: String) -> Bool {
    guard let database else { return false }
    return sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
  }

  private func bind(_ value: String, at index: Int32, to statement: OpaquePointer?) {
    value.withCString { sqlite3_bind_text(statement, index, $0, -1, Self.transient) }
  }

  private func blob(_ statement: OpaquePointer?, column: Int32) -> Data? {
    let count = Int(sqlite3_column_bytes(statement, column))
    guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return nil }
    return Data(bytes: bytes, count: count)
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
