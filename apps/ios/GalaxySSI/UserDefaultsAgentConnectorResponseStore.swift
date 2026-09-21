import CryptoKit
import Foundation
import SQLite3

struct AgentResultReceipt: Codable, Equatable {
  var desktopId: String
  var clientRouteId: String
  var conversationId: String
  var taskId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: String
  var agentId: String
  var executionGeneration: Int64
  var resultSHA256: String

  var id: String {
    let values: [Any] = [
      desktopId, String(executionGeneration), resultSHA256, clientRouteId,
      conversationId, taskId, turnId, contactId, sourceMessageId, agentId
    ]
    let data = (try? JSONSerialization.data(withJSONObject: values)) ?? Data()
    return Self.sha256(data)
  }

  var payload: [String: Any] {
    [
      "type": "agent_task_result_received",
      "desktop_id": desktopId,
      "client_route_id": clientRouteId,
      "conversation_id": conversationId,
      "task_id": taskId,
      "turn_id": turnId,
      "contact_id": contactId,
      "source_message_id": sourceMessageId,
      "agent_id": agentId,
      "execution_generation": executionGeneration,
      "sha256": resultSHA256,
      "receipt_id": id
    ]
  }

  static func fromPayload(_ payload: [String: Any], desktopId: String) -> AgentResultReceipt? {
    let receipt = AgentResultReceipt(
      desktopId: desktopId,
      clientRouteId: payload.string("client_route_id"),
      conversationId: payload.string("conversation_id"),
      taskId: payload.string("task_id"),
      turnId: payload.string("turn_id"),
      contactId: payload.string("contact_id"),
      sourceMessageId: payload.string("source_message_id").ifBlank(String(payload.int("source_message_id"))),
      agentId: payload.string("agent_id").ifBlank(payload.string("connector_id")),
      executionGeneration: Int64(payload.string("execution_generation"))
        ?? Int64(payload.int("execution_generation")),
      resultSHA256: payload.string("sha256")
        .ifBlank(payload.dictionary("result_recovery")?.string("sha256") ?? "")
    )
    guard receipt.isValid else { return nil }
    return receipt
  }

  static func confirmedPayload(_ payload: [String: Any], desktopId: String) -> AgentResultReceipt? {
    guard payload.string("type") == "agent_task_result_receipt_confirmed",
          let receipt = fromPayload(payload, desktopId: desktopId),
          receipt.id == payload.string("receipt_id") else { return nil }
    return receipt
  }

  private var isValid: Bool {
    executionGeneration > 0 && (Int64(sourceMessageId) ?? 0) > 0 &&
      [desktopId, clientRouteId, conversationId, taskId, turnId, contactId, sourceMessageId, agentId]
        .allSatisfy { !$0.isBlank && $0.count <= 200 } &&
      resultSHA256.count == 64 &&
      resultSHA256.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

enum AgentResultReceiptState: Int, Codable {
  case pending = 0
  case confirmed = 1
  case corrupt = 2
  case cleaned = 3
}

struct AgentResultReceiptWork: Equatable {
  var receipt: AgentResultReceipt
  var state: AgentResultReceiptState
  var attempts: Int
  var dueAtMillis: Int64
}

final class AgentResultReceiptJournal {
  static let maximumPageSize = 32

  private let fileURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(
    fileURL: URL = AgentResultReceiptJournal.defaultFileURL(),
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.fileURL = fileURL
    cipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.result.receipt.row.aes256.v1"
    )
    open()
  }

  deinit {
    if let database { sqlite3_close_v2(database) }
  }

  @discardableResult
  func insert(_ receipt: AgentResultReceipt) -> Bool {
    locked {
      guard let plaintext = try? JSONEncoder().encode(receipt),
            let encrypted = try? cipher.encrypt(plaintext, purpose: purpose(receipt.id)),
            let statement = prepare("""
              INSERT INTO result_receipts
                (receipt_id, encrypted_payload, state, attempts, next_attempt_at)
              VALUES (?, ?, 0, 0, 0)
              ON CONFLICT(receipt_id) DO UPDATE SET
                encrypted_payload = CASE WHEN result_receipts.state = 3 THEN excluded.encrypted_payload ELSE result_receipts.encrypted_payload END,
                state = CASE WHEN result_receipts.state = 3 THEN 0 ELSE result_receipts.state END,
                attempts = CASE WHEN result_receipts.state = 3 THEN 0 ELSE result_receipts.attempts END,
                next_attempt_at = CASE WHEN result_receipts.state = 3 THEN 0 ELSE result_receipts.next_attempt_at END
              """) else { return false }
      defer { sqlite3_finalize(statement) }
      bind(receipt.id, at: 1, to: statement)
      encrypted.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(encrypted.count), Self.transient)
      }
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  func due(nowMillis: Int64, limit: Int = maximumPageSize) -> [AgentResultReceiptWork] {
    locked {
      let bound = min(max(limit, 1), Self.maximumPageSize)
      guard let statement = prepare("""
        SELECT receipt_id, encrypted_payload, state, attempts, next_attempt_at
        FROM result_receipts
        WHERE state IN (0, 1) AND next_attempt_at <= ?
        ORDER BY next_attempt_at ASC, receipt_id ASC
        LIMIT ?
        """) else { return [] }
      sqlite3_bind_int64(statement, 1, nowMillis)
      sqlite3_bind_int(statement, 2, Int32(bound))
      var work: [AgentResultReceiptWork] = []
      var corrupt: [(String, Data)] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let idText = sqlite3_column_text(statement, 0) else { continue }
        let id = String(cString: idText)
        let count = Int(sqlite3_column_bytes(statement, 1))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 1) else { continue }
        let encrypted = Data(bytes: bytes, count: count)
        let state = AgentResultReceiptState(rawValue: Int(sqlite3_column_int(statement, 2))) ?? .corrupt
        let attempts = Int(sqlite3_column_int(statement, 3))
        let due = sqlite3_column_int64(statement, 4)
        guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: purpose(id)),
              let receipt = try? JSONDecoder().decode(AgentResultReceipt.self, from: plaintext),
              receipt.id == id else {
          corrupt.append((id, encrypted))
          continue
        }
        work.append(AgentResultReceiptWork(
          receipt: receipt,
          state: state,
          attempts: attempts,
          dueAtMillis: due
        ))
      }
      sqlite3_finalize(statement)
      corrupt.forEach { quarantine(id: $0.0, encrypted: $0.1) }
      return work
    }
  }

  @discardableResult
  func claim(_ work: AgentResultReceiptWork, nowMillis: Int64) -> Bool {
    locked {
      guard let statement = prepare("""
        UPDATE result_receipts SET attempts = ?, next_attempt_at = ?
        WHERE receipt_id = ? AND state = ? AND attempts = ? AND next_attempt_at = ?
        """) else { return false }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_int(statement, 1, Int32(min(work.attempts + 1, 30)))
      sqlite3_bind_int64(statement, 2, nowMillis + Self.retryDelay(attempt: work.attempts))
      bind(work.receipt.id, at: 3, to: statement)
      sqlite3_bind_int(statement, 4, Int32(work.state.rawValue))
      sqlite3_bind_int(statement, 5, Int32(work.attempts))
      sqlite3_bind_int64(statement, 6, work.dueAtMillis)
      return sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(database) == 1
    }
  }

  @discardableResult
  func confirm(_ receipt: AgentResultReceipt) -> Bool {
    transition(receipt.id, from: .pending, to: .confirmed, clearPayload: false)
  }

  @discardableResult
  func markCleaned(_ receipt: AgentResultReceipt) -> Bool {
    transition(receipt.id, from: .confirmed, to: .cleaned, clearPayload: true)
  }

  var nextWakeMillis: Int64? {
    locked {
      guard let statement = prepare(
        "SELECT MIN(next_attempt_at) FROM result_receipts WHERE state IN (0, 1)"
      ) else { return nil }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW,
            sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
      return sqlite3_column_int64(statement, 0)
    }
  }

  static func retryDelay(attempt: Int) -> Int64 {
    min(300_000, 5_000 << min(max(attempt, 0), 6))
  }

  static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return root.appendingPathComponent("GalaxySSI/AgentRecovery/result-receipts.sqlite3")
  }

  private func transition(
    _ id: String,
    from: AgentResultReceiptState,
    to: AgentResultReceiptState,
    clearPayload: Bool
  ) -> Bool {
    locked {
      let payload = clearPayload ? ", encrypted_payload = NULL" : ""
      guard let statement = prepare(
        "UPDATE result_receipts SET state = ?, next_attempt_at = 0\(payload) WHERE receipt_id = ? AND state = ?"
      ) else { return false }
      defer { sqlite3_finalize(statement) }
      sqlite3_bind_int(statement, 1, Int32(to.rawValue))
      bind(id, at: 2, to: statement)
      sqlite3_bind_int(statement, 3, Int32(from.rawValue))
      return sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(database) == 1
    }
  }

  private func quarantine(id: String, encrypted: Data) {
    guard let statement = prepare(
      "UPDATE result_receipts SET state = 2 WHERE receipt_id = ? AND encrypted_payload = ?"
    ) else { return }
    defer { sqlite3_finalize(statement) }
    bind(id, at: 1, to: statement)
    encrypted.withUnsafeBytes { bytes in
      sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(encrypted.count), Self.transient)
    }
    _ = sqlite3_step(statement)
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
      CREATE TABLE IF NOT EXISTS result_receipts (
        receipt_id TEXT PRIMARY KEY NOT NULL,
        encrypted_payload BLOB,
        state INTEGER NOT NULL DEFAULT 0,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL DEFAULT 0
      )
      """)
    _ = execute("CREATE INDEX IF NOT EXISTS result_receipts_due ON result_receipts(state, next_attempt_at, receipt_id)")
  }

  private func purpose(_ id: String) -> String { "result-receipt:\(id)" }

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
  private let lock = NSRecursiveLock()
  private static let persistenceLock = NSRecursiveLock()
  private var store: AgentConnectorResponseStore
  private var receivedDeliveryStorageKey: String { "\(storageKey).received_deliveries" }

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentConnectorResponseStore.defaultStorageKey,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.nowMillis = nowMillis
    self.store = AgentConnectorResponseStore(
      serialized: defaults.string(forKey: storageKey) ?? "[]",
      receivedDeliveries: Self.loadReceivedDeliveries(
        defaults: defaults,
        key: "\(storageKey).received_deliveries"
      ),
      nowMillis: nowMillis
    )
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    Self.persistenceLock.lock()
    lock.lock()
    defer {
      lock.unlock()
      Self.persistenceLock.unlock()
    }
    reloadLocked()
    let accepted = store.publish(response)
    persistLocked()
    return accepted
  }

  func pending() -> [AgentConnectorResponse] {
    Self.persistenceLock.lock()
    lock.lock()
    defer {
      lock.unlock()
      Self.persistenceLock.unlock()
    }
    reloadLocked()
    let responses = store.pending(nowMillis: nowMillis())
    persistLocked()
    return responses
  }

  func remove(_ response: AgentConnectorResponse) {
    Self.persistenceLock.lock()
    lock.lock()
    defer {
      lock.unlock()
      Self.persistenceLock.unlock()
    }
    reloadLocked()
    store.remove(response)
    persistLocked()
  }

  func hasReceivedDelivery(_ delivery: AgentTerminalDelivery) -> Bool {
    Self.persistenceLock.lock()
    lock.lock()
    defer {
      lock.unlock()
      Self.persistenceLock.unlock()
    }
    reloadLocked()
    return store.hasReceivedDelivery(delivery)
  }

  func clear() {
    Self.persistenceLock.lock()
    lock.lock()
    defer {
      lock.unlock()
      Self.persistenceLock.unlock()
    }
    store.clear()
    defaults.removeObject(forKey: storageKey)
    defaults.removeObject(forKey: receivedDeliveryStorageKey)
  }

  func serializedSnapshot() -> String {
    Self.persistenceLock.lock()
    lock.lock()
    defer {
      lock.unlock()
      Self.persistenceLock.unlock()
    }
    reloadLocked()
    persistLocked()
    return store.serializedSnapshot()
  }

  private func persistLocked() {
    defaults.set(store.serializedSnapshot(), forKey: storageKey)
    if let data = try? JSONEncoder().encode(store.receivedDeliverySnapshot()) {
      defaults.set(data, forKey: receivedDeliveryStorageKey)
    }
  }

  private func reloadLocked() {
    store = AgentConnectorResponseStore(
      serialized: defaults.string(forKey: storageKey) ?? "[]",
      receivedDeliveries: Self.loadReceivedDeliveries(
        defaults: defaults,
        key: receivedDeliveryStorageKey
      ),
      nowMillis: nowMillis
    )
  }

  private static func loadReceivedDeliveries(
    defaults: UserDefaults,
    key: String
  ) -> [AgentReceivedDeliveryProof] {
    guard let data = defaults.data(forKey: key) else { return [] }
    return (try? JSONDecoder().decode([AgentReceivedDeliveryProof].self, from: data)) ?? []
  }
}
