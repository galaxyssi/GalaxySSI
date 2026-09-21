import Foundation
import SQLite3

final class UserDefaultsAgentTerminalDeliveryStore: AgentTerminalDeliveryStoring {
  static let defaultStorageKey = "galaxyssi_agent_terminal_deliveries"

  private let defaults: UserDefaults
  private let storageKey: String
  private let secrets: GalaxySSISecretStore
  private static let persistenceLock = NSRecursiveLock()
  private var store: InMemoryAgentTerminalDeliveryStore

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentTerminalDeliveryStore.defaultStorageKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.secrets = secrets
    store = InMemoryAgentTerminalDeliveryStore(records: Self.loadRecords(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ))
  }

  func mark(_ delivery: AgentTerminalDelivery) {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    store.mark(delivery)
    persistLocked()
  }

  func find(sourceMessageId: Int64) -> AgentTerminalDelivery? {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    return store.find(sourceMessageId: sourceMessageId)
  }

  func isTerminal(_ response: AgentConnectorResponse) -> Bool {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    return store.isTerminal(response)
  }

  func records() -> [AgentTerminalDelivery] {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    return store.records()
  }

  func clear() {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    store.clear()
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: storageKey, secrets: secrets)
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentTerminalDeliveryStore.defaultStorageKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    persistenceLock.lock()
    defer { persistenceLock.unlock() }
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  private func persistLocked() {
    guard let data = try? JSONEncoder().encode(store.records()) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  private func reloadLocked() {
    store = InMemoryAgentTerminalDeliveryStore(records: Self.loadRecords(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ))
  }

  private static func loadRecords(
    defaults: UserDefaults,
    storageKey: String,
    secrets: GalaxySSISecretStore
  ) -> [AgentTerminalDelivery] {
    GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    ).flatMap { try? JSONDecoder().decode([AgentTerminalDelivery].self, from: $0) } ?? []
  }
}

final class UserDefaultsAgentConnectorResponseStore: AgentConnectorResponseSink {
  static let defaultStorageKey = "galaxyssi_agent_connector_responses"

  private let defaults: UserDefaults
  private let storageKey: String
  private let nowMillis: () -> Int64
  private let secrets: GalaxySSISecretStore
  private let lock = NSRecursiveLock()
  private let store: AgentConnectorResponseStore

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentConnectorResponseStore.defaultStorageKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.nowMillis = nowMillis
    self.secrets = secrets
    let encrypted = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    ).map { String(decoding: $0, as: UTF8.self) }
    let legacy = defaults.string(forKey: storageKey)
    self.store = AgentConnectorResponseStore(
      serialized: encrypted ?? legacy ?? "[]",
      nowMillis: nowMillis
    )
    if legacy != nil {
      persistLocked()
    }
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let accepted = store.publish(response)
    persistLocked()
    return accepted
  }

  func pending() -> [AgentConnectorResponse] {
    lock.lock()
    defer { lock.unlock() }
    let responses = store.pending(nowMillis: nowMillis())
    persistLocked()
    return responses
  }

  func remove(_ response: AgentConnectorResponse) {
    lock.lock()
    defer { lock.unlock() }
    store.remove(response)
    persistLocked()
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    store.clear()
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    persistLocked()
    return store.serializedSnapshot()
  }

  private func persistLocked() {
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      Data(store.serializedSnapshot().utf8),
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }
}

final class SQLiteAgentConnectorResponseStore: AgentConnectorResponseSink {
  static let pageSize = 32

  private let fileURL: URL
  private let defaults: UserDefaults
  private let legacyStorageKey: String
  private let nowMillis: () -> Int64
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(
    fileURL: URL = SQLiteAgentConnectorResponseStore.defaultFileURL(),
    defaults: UserDefaults = .standard,
    legacyStorageKey: String = UserDefaultsAgentConnectorResponseStore.defaultStorageKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.fileURL = fileURL
    self.defaults = defaults
    self.legacyStorageKey = legacyStorageKey
    self.nowMillis = nowMillis
    cipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.pending.reply.row.aes256.v1"
    )
    open()
    migrateLegacyBatch()
  }

  deinit {
    if let database { sqlite3_close_v2(database) }
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    locked {
      guard let normalized = AgentConnectorResponseNormalizer.normalized(
        response,
        nowMillis: nowMillis()
      ), let payload = encryptedPayload(normalized), execute("BEGIN IMMEDIATE TRANSACTION") else {
        return false
      }
      let succeeded = upsert(normalized, payload: payload, state: 0)
      return finishTransaction(succeeded)
    }
  }

  func pending() -> [AgentConnectorResponse] {
    locked {
      let cutoff = nowMillis() - AgentConnectorResponseStore.maxResponseAgeMillis
      guard let statement = prepare("""
        SELECT source_message_id, contact_id, encrypted_payload
        FROM pending_replies
        WHERE state = 0 AND received_at >= ?
        ORDER BY source_message_id ASC, contact_id ASC
        LIMIT ?
        """) else { return [] }
      sqlite3_bind_int64(statement, 1, cutoff)
      sqlite3_bind_int(statement, 2, Int32(Self.pageSize))
      var responses: [AgentConnectorResponse] = []
      var corruptKeys: [(Int64, String)] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        let sourceMessageId = sqlite3_column_int64(statement, 0)
        guard let contactText = sqlite3_column_text(statement, 1) else { continue }
        let contactId = String(cString: contactText)
        if let response = decode(
          statement,
          sourceMessageId: sourceMessageId,
          contactId: contactId,
          payloadColumn: 2
        ) {
          responses.append(response)
        } else {
          corruptKeys.append((sourceMessageId, contactId))
        }
      }
      sqlite3_finalize(statement)
      corruptKeys.forEach { markCorrupt(sourceMessageId: $0.0, contactId: $0.1) }
      migrateLegacyBatch()
      return responses
    }
  }

  func remove(_ response: AgentConnectorResponse) {
    locked {
      guard execute("BEGIN IMMEDIATE TRANSACTION") else { return }
      let succeeded = upsert(response, payload: nil, state: 1)
      _ = finishTransaction(succeeded)
    }
  }

  func clear() {
    locked {
      _ = execute("DELETE FROM pending_replies")
      defaults.removeObject(forKey: legacyStorageKey)
    }
  }

  static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return root
      .appendingPathComponent("GalaxySSI", isDirectory: true)
      .appendingPathComponent("AgentRecovery", isDirectory: true)
      .appendingPathComponent("pending-replies.sqlite3", isDirectory: false)
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
    ) == SQLITE_OK else {
      database = nil
      return
    }
    sqlite3_busy_timeout(database, 5_000)
    _ = execute("PRAGMA journal_mode = WAL")
    _ = execute("PRAGMA synchronous = FULL")
    _ = execute("""
      CREATE TABLE IF NOT EXISTS pending_replies (
        source_message_id INTEGER NOT NULL,
        contact_id TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        state INTEGER NOT NULL DEFAULT 0,
        encrypted_payload BLOB,
        PRIMARY KEY(source_message_id, contact_id)
      )
      """)
    _ = execute("CREATE INDEX IF NOT EXISTS pending_replies_active ON pending_replies(state, source_message_id, contact_id)")
  }

  private func migrateLegacyBatch() {
    guard let serialized = defaults.string(forKey: legacyStorageKey) else { return }
    let legacy = AgentConnectorResponseStoreCodec.decode(serialized, nowMillis: nowMillis())
    guard !legacy.isEmpty else {
      defaults.removeObject(forKey: legacyStorageKey)
      return
    }
    let batch = Array(legacy.prefix(Self.pageSize))
    guard execute("BEGIN IMMEDIATE TRANSACTION") else { return }
    var succeeded = true
    for response in batch where !contains(response) {
      guard let payload = encryptedPayload(response), upsert(response, payload: payload, state: 0) else {
        succeeded = false
        break
      }
    }
    guard finishTransaction(succeeded) else { return }
    let remaining = Array(legacy.dropFirst(batch.count))
    if remaining.isEmpty {
      defaults.removeObject(forKey: legacyStorageKey)
    } else {
      defaults.set(AgentConnectorResponseStoreCodec.encode(remaining), forKey: legacyStorageKey)
    }
  }

  private func contains(_ response: AgentConnectorResponse) -> Bool {
    guard let statement = prepare(
      "SELECT 1 FROM pending_replies WHERE source_message_id = ? AND contact_id = ? LIMIT 1"
    ) else { return false }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, response.sourceMessageId)
    bind(response.contactId, at: 2, to: statement)
    return sqlite3_step(statement) == SQLITE_ROW
  }

  private func upsert(_ response: AgentConnectorResponse, payload: Data?, state: Int32) -> Bool {
    guard let statement = prepare("""
      INSERT INTO pending_replies
        (source_message_id, contact_id, received_at, state, encrypted_payload)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(source_message_id, contact_id) DO UPDATE SET
        received_at = excluded.received_at,
        state = excluded.state,
        encrypted_payload = excluded.encrypted_payload
      """) else { return false }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, response.sourceMessageId)
    bind(response.contactId, at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, response.receivedAtMillis)
    sqlite3_bind_int(statement, 4, state)
    if let payload {
      payload.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(payload.count), Self.transient)
      }
    } else {
      sqlite3_bind_null(statement, 5)
    }
    return sqlite3_step(statement) == SQLITE_DONE
  }

  private func markCorrupt(sourceMessageId: Int64, contactId: String) {
    guard let statement = prepare(
      "UPDATE pending_replies SET state = 2 WHERE source_message_id = ? AND contact_id = ?"
    ) else { return }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int64(statement, 1, sourceMessageId)
    bind(contactId, at: 2, to: statement)
    _ = sqlite3_step(statement)
  }

  private func encryptedPayload(_ response: AgentConnectorResponse) -> Data? {
    guard let data = try? JSONEncoder().encode(response) else { return nil }
    return try? cipher.encrypt(data, purpose: purpose(response.sourceMessageId, response.contactId))
  }

  private func decode(
    _ statement: OpaquePointer?,
    sourceMessageId: Int64,
    contactId: String,
    payloadColumn: Int32
  ) -> AgentConnectorResponse? {
    let count = Int(sqlite3_column_bytes(statement, payloadColumn))
    guard count > 0, let bytes = sqlite3_column_blob(statement, payloadColumn) else { return nil }
    let encrypted = Data(bytes: bytes, count: count)
    guard let plaintext = try? cipher.decrypt(
      encrypted,
      expectedPurpose: purpose(sourceMessageId, contactId)
    ), let response = try? JSONDecoder().decode(AgentConnectorResponse.self, from: plaintext),
      response.sourceMessageId == sourceMessageId, response.contactId == contactId else { return nil }
    return AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis())
  }

  private func purpose(_ sourceMessageId: Int64, _ contactId: String) -> String {
    "pending-reply:\(sourceMessageId):\(contactId)"
  }

  private func finishTransaction(_ succeeded: Bool) -> Bool {
    guard succeeded else {
      _ = execute("ROLLBACK")
      return false
    }
    guard execute("COMMIT") else {
      _ = execute("ROLLBACK")
      return false
    }
    return true
  }

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

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
