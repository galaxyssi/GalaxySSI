import CryptoKit
import Foundation
import SQLite3

struct AgentResultCheckpointIdentity: Codable, Equatable, Hashable {
  var desktopId: String
  var clientRouteId: String
  var conversationId: String
  var taskId: String
  var turnId: String
  var contactId: String
  var sourceMessageId: String
  var agentId: String
  var executionGeneration: Int64

  var isValid: Bool {
    executionGeneration > 0 &&
      [desktopId, clientRouteId, conversationId, taskId, turnId, contactId, sourceMessageId, agentId]
        .allSatisfy { !$0.isBlank && $0.count <= 200 }
  }
}

struct AgentResultPageCheckpoint: Equatable {
  var identity: AgentResultCheckpointIdentity
  var pageIndex: Int
  var pageCount: Int
  var totalBytes: Int
  var resultSHA256: String
  var pageSHA256: String
  var data: Data
}

final class AgentResultPageCheckpointStore {
  static let maximumPageBytes = 16 * 1_024
  static let maximumResultBytes = 128 * 1_024

  private let fileURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(
    fileURL: URL = AgentResultPageCheckpointStore.defaultFileURL(),
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.fileURL = fileURL
    cipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.result.checkpoint.row.aes256.v1"
    )
    open()
  }

  deinit {
    if let database { sqlite3_close_v2(database) }
  }

  @discardableResult
  func save(_ checkpoint: AgentResultPageCheckpoint) -> Bool {
    locked {
      guard validate(checkpoint),
            let encrypted = try? cipher.encrypt(
              checkpoint.data,
              purpose: purpose(checkpoint.identity, checkpoint.resultSHA256, checkpoint.pageIndex)
            ), let statement = prepare("""
              INSERT INTO result_page_checkpoints
                (identity_key, page_index, page_count, total_bytes, result_sha256, page_sha256,
                 encrypted_payload, updated_at, quarantined)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)
              ON CONFLICT(identity_key, result_sha256, page_index) DO UPDATE SET
                page_count = excluded.page_count,
                total_bytes = excluded.total_bytes,
                page_sha256 = excluded.page_sha256,
                encrypted_payload = excluded.encrypted_payload,
                updated_at = excluded.updated_at,
                quarantined = 0
              """) else { return false }
      defer { sqlite3_finalize(statement) }
      bind(identityKey(checkpoint.identity), at: 1, to: statement)
      sqlite3_bind_int(statement, 2, Int32(checkpoint.pageIndex))
      sqlite3_bind_int(statement, 3, Int32(checkpoint.pageCount))
      sqlite3_bind_int(statement, 4, Int32(checkpoint.totalBytes))
      bind(checkpoint.resultSHA256, at: 5, to: statement)
      bind(checkpoint.pageSHA256, at: 6, to: statement)
      encrypted.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 7, bytes.baseAddress, Int32(encrypted.count), Self.transient)
      }
      sqlite3_bind_int64(statement, 8, Int64(Date().timeIntervalSince1970 * 1_000))
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  func restoredPages(
    identity: AgentResultCheckpointIdentity,
    resultSHA256: String,
    pageCount: Int,
    totalBytes: Int
  ) -> [AgentResultPageCheckpoint] {
    locked {
      guard identity.isValid, validDigest(resultSHA256), pageCount > 0,
            totalBytes > 0, totalBytes <= Self.maximumResultBytes,
            let statement = prepare("""
              SELECT page_index, page_sha256, encrypted_payload
              FROM result_page_checkpoints
              WHERE identity_key = ? AND result_sha256 = ? AND page_count = ?
                AND total_bytes = ? AND quarantined = 0
              ORDER BY page_index ASC
              """) else { return [] }
      bind(identityKey(identity), at: 1, to: statement)
      bind(resultSHA256, at: 2, to: statement)
      sqlite3_bind_int(statement, 3, Int32(pageCount))
      sqlite3_bind_int(statement, 4, Int32(totalBytes))
      var pages: [AgentResultPageCheckpoint] = []
      var corrupt: [Int] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        let pageIndex = Int(sqlite3_column_int(statement, 0))
        guard let digestText = sqlite3_column_text(statement, 1) else {
          corrupt.append(pageIndex)
          continue
        }
        let pageDigest = String(cString: digestText)
        let count = Int(sqlite3_column_bytes(statement, 2))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 2) else {
          corrupt.append(pageIndex)
          continue
        }
        let encrypted = Data(bytes: bytes, count: count)
        guard let data = try? cipher.decrypt(
          encrypted,
          expectedPurpose: purpose(identity, resultSHA256, pageIndex)
        ), pageIndex >= 0, pageIndex < pageCount,
          data.count == expectedPageBytes(pageIndex: pageIndex, pageCount: pageCount, totalBytes: totalBytes),
          sha256(data) == pageDigest else {
          corrupt.append(pageIndex)
          continue
        }
        pages.append(AgentResultPageCheckpoint(
          identity: identity,
          pageIndex: pageIndex,
          pageCount: pageCount,
          totalBytes: totalBytes,
          resultSHA256: resultSHA256,
          pageSHA256: pageDigest,
          data: data
        ))
      }
      sqlite3_finalize(statement)
      corrupt.forEach { quarantine(identity: identity, digest: resultSHA256, pageIndex: $0) }
      return pages
    }
  }

  func missingPageIndices(
    identity: AgentResultCheckpointIdentity,
    resultSHA256: String,
    pageCount: Int,
    totalBytes: Int
  ) -> [Int] {
    let restored = Set(restoredPages(
      identity: identity,
      resultSHA256: resultSHA256,
      pageCount: pageCount,
      totalBytes: totalBytes
    ).map(\.pageIndex))
    return (0..<max(pageCount, 0)).filter { !restored.contains($0) }
  }

  func clear(identity: AgentResultCheckpointIdentity, resultSHA256: String) {
    locked {
      guard let statement = prepare(
        "DELETE FROM result_page_checkpoints WHERE identity_key = ? AND result_sha256 = ?"
      ) else { return }
      defer { sqlite3_finalize(statement) }
      bind(identityKey(identity), at: 1, to: statement)
      bind(resultSHA256, at: 2, to: statement)
      _ = sqlite3_step(statement)
    }
  }

  static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return root.appendingPathComponent("GalaxySSI/AgentRecovery/result-pages.sqlite3")
  }

  private func validate(_ checkpoint: AgentResultPageCheckpoint) -> Bool {
    checkpoint.identity.isValid && validDigest(checkpoint.resultSHA256) &&
      validDigest(checkpoint.pageSHA256) && checkpoint.totalBytes > 0 &&
      checkpoint.totalBytes <= Self.maximumResultBytes && checkpoint.pageCount > 0 &&
      checkpoint.pageIndex >= 0 && checkpoint.pageIndex < checkpoint.pageCount &&
      checkpoint.pageCount == (checkpoint.totalBytes + Self.maximumPageBytes - 1) / Self.maximumPageBytes &&
      checkpoint.data.count == expectedPageBytes(
        pageIndex: checkpoint.pageIndex,
        pageCount: checkpoint.pageCount,
        totalBytes: checkpoint.totalBytes
      ) && sha256(checkpoint.data) == checkpoint.pageSHA256
  }

  private func expectedPageBytes(pageIndex: Int, pageCount: Int, totalBytes: Int) -> Int {
    pageIndex == pageCount - 1
      ? totalBytes - pageIndex * Self.maximumPageBytes
      : Self.maximumPageBytes
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
      CREATE TABLE IF NOT EXISTS result_page_checkpoints (
        identity_key TEXT NOT NULL, page_index INTEGER NOT NULL, page_count INTEGER NOT NULL,
        total_bytes INTEGER NOT NULL, result_sha256 TEXT NOT NULL, page_sha256 TEXT NOT NULL,
        encrypted_payload BLOB NOT NULL, updated_at INTEGER NOT NULL, quarantined INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(identity_key, result_sha256, page_index)
      )
      """)
    _ = execute("CREATE INDEX IF NOT EXISTS result_page_active ON result_page_checkpoints(identity_key, result_sha256, quarantined, page_index)")
  }

  private func quarantine(identity: AgentResultCheckpointIdentity, digest: String, pageIndex: Int) {
    guard let statement = prepare("UPDATE result_page_checkpoints SET quarantined = 1 WHERE identity_key = ? AND result_sha256 = ? AND page_index = ?") else { return }
    defer { sqlite3_finalize(statement) }
    bind(identityKey(identity), at: 1, to: statement)
    bind(digest, at: 2, to: statement)
    sqlite3_bind_int(statement, 3, Int32(pageIndex))
    _ = sqlite3_step(statement)
  }

  private func identityKey(_ identity: AgentResultCheckpointIdentity) -> String {
    let data = (try? JSONEncoder().encode(identity)) ?? Data()
    return sha256(data)
  }

  private func purpose(_ identity: AgentResultCheckpointIdentity, _ digest: String, _ pageIndex: Int) -> String {
    "result-page:\(identityKey(identity)):\(digest):\(pageIndex)"
  }

  private func validDigest(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

struct AgentConnectorResponse: Codable, Equatable {
  var sourceMessageId: Int64
  var contactId: String
  var content: String
  var conversationId: String
  var turnId: String
  var taskId: String
  var success: Bool
  var inputTokens: Int64
  var outputTokens: Int64
  var costMicros: Int64
  var richOutputJson: String
  var receivedAtMillis: Int64
  var taskStatus: String
  var executionGeneration: Int64
  var statusSequence: Int64
  var deliveryFailureCode: String

  init(
    sourceMessageId: Int64,
    contactId: String = "",
    content: String = "",
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    success: Bool = true,
    inputTokens: Int64 = 0,
    outputTokens: Int64 = 0,
    costMicros: Int64 = 0,
    richOutputJson: String = "",
    receivedAtMillis: Int64 = 0,
    taskStatus: String = "",
    executionGeneration: Int64 = 1,
    statusSequence: Int64 = -1,
    deliveryFailureCode: String = ""
  ) {
    self.sourceMessageId = max(sourceMessageId, 0)
    self.contactId = contactId
    self.content = String(content.prefix(Self.maxContentCharacters))
    self.conversationId = conversationId
    self.turnId = turnId
    self.taskId = taskId
    let normalizedTaskStatus = AgentRemoteOutcomePolicy.normalizedStatus(taskStatus)
    self.success = normalizedTaskStatus.isEmpty ? success : normalizedTaskStatus == "completed"
    self.inputTokens = max(inputTokens, 0)
    self.outputTokens = max(outputTokens, 0)
    self.costMicros = max(costMicros, 0)
    self.richOutputJson = String(richOutputJson.prefix(Self.maxRichOutputCharacters))
    self.receivedAtMillis = max(receivedAtMillis, 0)
    self.taskStatus = normalizedTaskStatus
    self.executionGeneration = AgentRemoteOutcomePolicy.validGeneration(executionGeneration) ? executionGeneration : 1
    self.statusSequence = max(statusSequence, -1)
    self.deliveryFailureCode = AgentAttachmentDeliveryFailureContract.isTerminal(deliveryFailureCode)
      ? deliveryFailureCode
      : ""
  }

  enum CodingKeys: String, CodingKey {
    case sourceMessageId = "source_message_id"
    case contactId = "contact_id"
    case content
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case taskId = "task_id"
    case success
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case costMicros = "cost_micros"
    case richOutputJson = "rich_output"
    case receivedAtMillis = "received_at_millis"
    case taskStatus = "task_status"
    case executionGeneration = "execution_generation"
    case statusSequence = "status_sequence"
    case deliveryFailureCode = "delivery_failure_code"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      sourceMessageId: try container.decodeIfPresent(Int64.self, forKey: .sourceMessageId) ?? 0,
      contactId: try container.decodeIfPresent(String.self, forKey: .contactId) ?? "",
      content: try container.decodeIfPresent(String.self, forKey: .content) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      turnId: try container.decodeIfPresent(String.self, forKey: .turnId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      success: try container.decodeIfPresent(Bool.self, forKey: .success) ?? true,
      inputTokens: try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0,
      outputTokens: try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0,
      costMicros: try container.decodeIfPresent(Int64.self, forKey: .costMicros) ?? 0,
      richOutputJson: try container.decodeIfPresent(String.self, forKey: .richOutputJson) ?? "",
      receivedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .receivedAtMillis) ?? 0,
      taskStatus: try container.decodeIfPresent(String.self, forKey: .taskStatus) ?? "",
      executionGeneration: try container.decodeIfPresent(Int64.self, forKey: .executionGeneration) ?? 1,
      statusSequence: try container.decodeIfPresent(Int64.self, forKey: .statusSequence) ?? -1,
      deliveryFailureCode: try container.decodeIfPresent(String.self, forKey: .deliveryFailureCode) ?? ""
    )
  }

  static let maxContentCharacters = 24_000
  static let maxRichOutputCharacters = 48_000

  static func fromPayload(
    _ payload: [String: Any],
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentConnectorResponse? {
    let sourceMessageId = Int64(payload.string("source_message_id")) ?? Int64(payload.int("source_message_id"))
    guard sourceMessageId > 0 else { return nil }
    let taskStatus = AgentRemoteOutcomePolicy.normalizedStatus(payload.string("task_status"))
    guard payload.string("task_status").isBlank || AgentRemoteOutcomePolicy.isTerminal(taskStatus) else {
      return nil
    }
    let deliveryFailureCode = payload.string("delivery_failure_code")
    let suppliedSuccess = payloadBool(payload["success"], defaultValue: true)
    guard deliveryFailureCode.isEmpty ||
      (taskStatus.isEmpty && !suppliedSuccess &&
        AgentAttachmentDeliveryFailureContract.isTerminal(deliveryFailureCode)) else {
      return nil
    }
    let content = AgentRemoteOutcomePolicy.isFailure(taskStatus)
      ? payload.string("error").ifBlank(payload.string("content")).ifBlank(payload.string("text"))
      : payload.string("content").ifBlank(payload.string("text"))
    let richOutput = payload.string("rich_output")
      .ifBlank(payload.string("rich_output_json"))
    let resolvedContent = content.ifBlank(
      AgentAttachmentDeliveryFailureContract.observation(deliveryFailureCode)
    )
    guard !resolvedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !richOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      AgentRemoteOutcomePolicy.isFailure(taskStatus) else {
      return nil
    }
    let receivedAtMillis = Int64(
      payload.string("received_at_millis")
        .ifBlank(payload.string("received_at"))
        .ifBlank(payload.string("time"))
    ) ?? Int64(payload.int("received_at_millis"))
    let executionGeneration = Int64(payload.string("execution_generation"))
      ?? Int64(payload.int("execution_generation")).positiveOr(1)
    guard AgentRemoteOutcomePolicy.validGeneration(executionGeneration) else { return nil }
    let statusSequence = payload["status_sequence"] == nil && payload["status_seq"] == nil
      ? -1
      : Int64(payload.string("status_sequence").ifBlank(payload.string("status_seq")))
        ?? Int64(payload.int("status_sequence")).nonnegativeOr(-1)
    guard statusSequence >= -1 else { return nil }
    return AgentConnectorResponse(
      sourceMessageId: sourceMessageId,
      contactId: payload.string("contact_id"),
      content: resolvedContent,
      conversationId: payload.string("conversation_id"),
      turnId: payload.string("turn_id"),
      taskId: payload.string("task_id"),
      success: taskStatus.isEmpty
        ? suppliedSuccess
        : taskStatus == "completed",
      inputTokens: Int64(payload.string("input_tokens")) ?? Int64(payload.int("input_tokens")),
      outputTokens: Int64(payload.string("output_tokens")) ?? Int64(payload.int("output_tokens")),
      costMicros: Int64(payload.string("cost_micros")) ?? Int64(payload.int("cost_micros")),
      richOutputJson: richOutput,
      receivedAtMillis: receivedAtMillis > 0 ? receivedAtMillis : max(nowMillis, 0),
      taskStatus: taskStatus,
      executionGeneration: executionGeneration,
      statusSequence: statusSequence,
      deliveryFailureCode: deliveryFailureCode
    )
  }

  private static func payloadBool(_ value: Any?, defaultValue: Bool) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String {
      switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "true", "1", "yes": return true
      case "false", "0", "no": return false
      default: break
      }
    }
    return defaultValue
  }
}

enum AgentRemoteOutcomePolicy {
  static let terminalStatuses: Set<String> = ["completed", "failed", "timed_out", "cancelled"]
  static let failureStatuses: Set<String> = ["failed", "timed_out", "cancelled"]
  static let maximumGeneration: Int64 = 9_007_199_254_740_991

  static func normalizedStatus(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func isTerminal(_ value: String) -> Bool { terminalStatuses.contains(normalizedStatus(value)) }
  static func isFailure(_ value: String) -> Bool { failureStatuses.contains(normalizedStatus(value)) }
  static func validGeneration(_ value: Int64) -> Bool { (1...maximumGeneration).contains(value) }
}

private extension Int64 {
  func positiveOr(_ fallback: Int64) -> Int64 { self > 0 ? self : fallback }
  func nonnegativeOr(_ fallback: Int64) -> Int64 { self >= 0 ? self : fallback }
}

protocol AgentConnectorResponseSink: AnyObject {
  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool
  func pending() -> [AgentConnectorResponse]
  func remove(_ response: AgentConnectorResponse)
  func clear()
}

final class InMemoryAgentConnectorResponseStore: AgentConnectorResponseSink {
  private let lock = NSRecursiveLock()
  private var responses: [AgentConnectorResponse] = []

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    responses.append(response)
    return true
  }

  func pending() -> [AgentConnectorResponse] {
    lock.lock()
    defer { lock.unlock() }
    return responses
  }

  func remove(_ response: AgentConnectorResponse) {
    lock.lock()
    defer { lock.unlock() }
    responses.removeAll {
      $0.sourceMessageId == response.sourceMessageId &&
        $0.contactId == response.contactId &&
        $0.executionGeneration == response.executionGeneration
    }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    responses.removeAll()
  }
}

protocol AgentConnectorResponseListener: AnyObject {
  func onConnectorResponse(_ response: AgentConnectorResponse)
}

final class AgentManagedConnectorResponseRegistry {
  static let shared = AgentManagedConnectorResponseRegistry()

  private struct Interceptor {
    var ownerId: String
    var conversationId: String
    var turnId: String
    var taskId: String
    var executionGeneration: Int64
    var consume: (AgentConnectorResponse) -> Bool
  }

  private let lock = NSRecursiveLock()
  private var interceptors: [String: Interceptor] = [:]

  func register(
    sourceMessageId: Int64,
    contactId: String = "",
    ownerId: String,
    conversationId: String = "",
    turnId: String = "",
    taskId: String = "",
    executionGeneration: Int64 = 1,
    consume: @escaping (AgentConnectorResponse) -> Bool
  ) throws {
    guard sourceMessageId > 0 else {
      throw AgentRuntimeCapabilityError.invalid("Managed response source id must be positive")
    }
    let cleanOwner = ownerId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanOwner.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("Managed response owner id must not be blank")
    }
    lock.lock()
    defer { lock.unlock() }
    interceptors[key(sourceMessageId: sourceMessageId, contactId: contactId)] = Interceptor(
      ownerId: cleanOwner,
      conversationId: conversationId.trimmingCharacters(in: .whitespacesAndNewlines),
      turnId: turnId.trimmingCharacters(in: .whitespacesAndNewlines),
      taskId: taskId.trimmingCharacters(in: .whitespacesAndNewlines),
      executionGeneration: AgentRemoteOutcomePolicy.validGeneration(executionGeneration)
        ? executionGeneration
        : 1,
      consume: consume
    )
  }

  func consume(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    guard let entry = matchingEntry(response) else {
      lock.unlock()
      return false
    }
    guard interceptors.removeValue(forKey: entry.0) != nil else {
      lock.unlock()
      return false
    }
    lock.unlock()
    return entry.1.consume(response)
  }

  func contains(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return matchingEntry(response) != nil
  }

  func unregisterOwner(_ ownerId: String) {
    let cleanOwner = ownerId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanOwner.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    interceptors = interceptors.filter { $0.value.ownerId != cleanOwner }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    interceptors.removeAll()
  }

  private func key(sourceMessageId: Int64, contactId: String) -> String {
    "\(sourceMessageId):\(contactId.trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  private func matchingEntry(_ response: AgentConnectorResponse) -> (String, Interceptor)? {
    guard response.sourceMessageId > 0 else { return nil }
    let exactKey = key(sourceMessageId: response.sourceMessageId, contactId: response.contactId)
    let wildcardKey = key(sourceMessageId: response.sourceMessageId, contactId: "")
    if let exact = interceptors[exactKey], identityMatches(exact, response) {
      return (exactKey, exact)
    }
    if let wildcard = interceptors[wildcardKey], identityMatches(wildcard, response) {
      return (wildcardKey, wildcard)
    }
    let prefix = "\(response.sourceMessageId):"
    let aliases = interceptors.compactMap { item -> (String, Interceptor)? in
      guard item.key.hasPrefix(prefix), identityMatches(item.value, response) else { return nil }
      return (item.key, item.value)
    }.prefix(2)
    return aliases.count == 1 ? aliases.first : nil
  }

  private func identityMatches(_ interceptor: Interceptor, _ response: AgentConnectorResponse) -> Bool {
    interceptor.executionGeneration == response.executionGeneration &&
    AgentTaskIdentityPolicy.matchesResponseIdentity(
      expectedConversationId: interceptor.conversationId,
      expectedTurnId: interceptor.turnId,
      expectedTaskId: interceptor.taskId,
      actualConversationId: response.conversationId,
      actualTurnId: response.turnId,
      actualTaskId: response.taskId
    )
  }
}

final class AgentConnectorResponseStore: AgentConnectorResponseSink {
  static let maxResponses = 30
  static let maxResponseAgeMillis: Int64 = 24 * 60 * 60 * 1_000

  private let lock = NSRecursiveLock()
  private let nowMillis: () -> Int64
  private var responses: [AgentConnectorResponse]

  init(
    serialized: String = "[]",
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.nowMillis = nowMillis
    self.responses = AgentConnectorResponseStoreCodec.decode(serialized, nowMillis: nowMillis())
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    append(response)
  }

  @discardableResult
  func append(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let now = max(nowMillis(), 0)
    guard let normalized = AgentConnectorResponseNormalizer.normalized(response, nowMillis: now) else {
      responses = pendingLocked(nowMillis: now)
      return false
    }
    responses = (pendingLocked(nowMillis: now).filter {
      !($0.sourceMessageId == normalized.sourceMessageId &&
        $0.contactId == normalized.contactId &&
        $0.executionGeneration == normalized.executionGeneration)
    } + [normalized])
      .sorted { $0.receivedAtMillis < $1.receivedAtMillis }
      .suffix(Self.maxResponses)
      .map { $0 }
    return true
  }

  func pending() -> [AgentConnectorResponse] {
    pending(nowMillis: nowMillis())
  }

  func pending(nowMillis: Int64) -> [AgentConnectorResponse] {
    lock.lock()
    defer { lock.unlock() }
    responses = pendingLocked(nowMillis: max(nowMillis, 0))
    return responses
  }

  func remove(_ response: AgentConnectorResponse) {
    lock.lock()
    defer { lock.unlock() }
    responses = pendingLocked(nowMillis: nowMillis()).filter {
      !($0.sourceMessageId == response.sourceMessageId &&
        $0.contactId == response.contactId &&
        $0.executionGeneration == response.executionGeneration)
    }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    responses.removeAll()
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    responses = pendingLocked(nowMillis: nowMillis())
    return AgentConnectorResponseStoreCodec.encode(responses)
  }

  private func pendingLocked(nowMillis: Int64) -> [AgentConnectorResponse] {
    let cutoff = nowMillis - Self.maxResponseAgeMillis
    return responses.compactMap { response in
      guard response.receivedAtMillis >= cutoff else {
        return nil
      }
      return AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis)
    }
  }
}

final class AgentConnectorResponseBus {
  private let lock = NSRecursiveLock()
  private var listeners: [UUID: (AgentConnectorResponse) -> Void] = [:]
  private let registry: AgentManagedConnectorResponseRegistry
  private let managedLedger: AgentManagedResponseLedger?
  private let store: AgentConnectorResponseSink
  private let terminalStore: AgentTerminalDeliveryStoring
  private let globalRunSlots: AgentGlobalRunSlotStoring
  private let nowMillis: () -> Int64

  init(
    registry: AgentManagedConnectorResponseRegistry = .shared,
    managedLedger: AgentManagedResponseLedger? = UserDefaultsAgentManagedResponseLedger(),
    store: AgentConnectorResponseSink = UserDefaultsAgentConnectorResponseStore(),
    terminalStore: AgentTerminalDeliveryStoring = UserDefaultsAgentTerminalDeliveryStore(),
    globalRunSlots: AgentGlobalRunSlotStoring = InMemoryAgentGlobalRunSlotStore(),
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.registry = registry
    self.managedLedger = managedLedger
    self.store = store
    self.terminalStore = terminalStore
    self.globalRunSlots = globalRunSlots
    self.nowMillis = nowMillis
  }

  @discardableResult
  func addListener(_ listener: @escaping (AgentConnectorResponse) -> Void) -> UUID {
    lock.lock()
    defer { lock.unlock() }
    let token = UUID()
    listeners[token] = listener
    return token
  }

  func removeListener(_ token: UUID) {
    lock.lock()
    defer { lock.unlock() }
    listeners.removeValue(forKey: token)
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    guard let normalized = AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis()) else {
      return false
    }
    globalRunSlots.release(sourceMessageId: String(normalized.sourceMessageId))
    if terminalStore.isTerminal(normalized) {
      store.remove(normalized)
      return true
    }
    if registry.consume(normalized) {
      return true
    }
    if managedLedger?.complete(normalized) != nil {
      return true
    }
    store.publish(normalized)
    let callbacks: [(AgentConnectorResponse) -> Void]
    lock.lock()
    callbacks = Array(listeners.values)
    lock.unlock()
    callbacks.forEach { $0(normalized) }
    return false
  }

  func pending() -> [AgentConnectorResponse] {
    store.pending()
  }

  func remove(_ response: AgentConnectorResponse) {
    store.remove(response)
  }

  func isTerminal(_ response: AgentConnectorResponse) -> Bool {
    terminalStore.isTerminal(response)
  }

  func markTerminal(_ delivery: AgentTerminalDelivery) {
    terminalStore.mark(delivery)
  }

  func clear() {
    store.clear()
    registry.clear()
    managedLedger?.clear()
    lock.lock()
    defer { lock.unlock() }
    listeners.removeAll()
  }
}

enum AgentConnectorResponseStoreCodec {
  static func encode(_ responses: [AgentConnectorResponse]) -> String {
    AgentMcpJSONCodec.stringify(.array(responses.map(responseObject)))
  }

  static func decode(
    _ raw: String,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [AgentConnectorResponse] {
    guard let data = raw.data(using: .utf8),
          let values = try? JSONDecoder().decode([AgentMcpJSONValue].self, from: data) else {
      return []
    }
    let cutoff = max(nowMillis, 0) - AgentConnectorResponseStore.maxResponseAgeMillis
    return values.compactMap { value in
      guard case .object(let object) = value else {
        return nil
      }
      let receivedAt = object.int64("received_at") > 0
        ? object.int64("received_at")
        : object.int64("received_at_millis")
      let response = AgentConnectorResponse(
        sourceMessageId: object.int64("source_message_id"),
        contactId: object.string("contact_id"),
        content: object.string("content"),
        conversationId: object.string("conversation_id"),
        turnId: object.string("turn_id"),
        taskId: object.string("task_id"),
        success: object["success"] == nil ? true : object.bool("success"),
        inputTokens: object.int64("input_tokens"),
        outputTokens: object.int64("output_tokens"),
        costMicros: object.int64("cost_micros"),
        richOutputJson: object.string("rich_output"),
        receivedAtMillis: receivedAt,
        taskStatus: object.string("task_status"),
        executionGeneration: object.int64("execution_generation").positiveOr(1),
        statusSequence: object.int64("status_sequence").nonnegativeOr(-1),
        deliveryFailureCode: object.string("delivery_failure_code")
      )
      guard receivedAt >= cutoff else {
        return nil
      }
      return AgentConnectorResponseNormalizer.normalized(response, nowMillis: nowMillis)
    }
  }

  private static func responseObject(_ response: AgentConnectorResponse) -> AgentMcpJSONValue {
    .object([
      "source_message_id": .int(response.sourceMessageId),
      "contact_id": .string(response.contactId),
      "content": .string(String(response.content.prefix(AgentConnectorResponse.maxContentCharacters))),
      "conversation_id": .string(response.conversationId),
      "turn_id": .string(response.turnId),
      "task_id": .string(response.taskId),
      "success": .bool(response.success),
      "task_status": .string(response.taskStatus),
      "execution_generation": .int(response.executionGeneration),
      "status_sequence": .int(response.statusSequence),
      "delivery_failure_code": .string(response.deliveryFailureCode),
      "input_tokens": .int(response.inputTokens),
      "output_tokens": .int(response.outputTokens),
      "cost_micros": .int(response.costMicros),
      "rich_output": .string(AgentConnectorRichOutput.normalize(response.richOutputJson)),
      "received_at": .int(response.receivedAtMillis)
    ])
  }
}

enum AgentConnectorResponseNormalizer {
  static func normalized(
    _ response: AgentConnectorResponse,
    nowMillis: Int64
  ) -> AgentConnectorResponse? {
    guard response.sourceMessageId > 0 else {
      return nil
    }
    let richOutput = AgentConnectorRichOutput.normalize(response.richOutputJson)
    let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? AgentConnectorRichOutput.fallbackText(richOutput)
      : response.content
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      !richOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
      AgentRemoteOutcomePolicy.isFailure(response.taskStatus) else {
      return nil
    }
    guard response.taskStatus.isEmpty || AgentRemoteOutcomePolicy.isTerminal(response.taskStatus),
          response.deliveryFailureCode.isEmpty ||
            (response.taskStatus.isEmpty && !response.success &&
              AgentAttachmentDeliveryFailureContract.isTerminal(response.deliveryFailureCode)),
          AgentRemoteOutcomePolicy.validGeneration(response.executionGeneration) else { return nil }
    return AgentConnectorResponse(
      sourceMessageId: response.sourceMessageId,
      contactId: response.contactId,
      content: String(content.prefix(AgentConnectorResponse.maxContentCharacters)),
      conversationId: response.conversationId,
      turnId: response.turnId,
      taskId: response.taskId,
      success: response.taskStatus.isEmpty ? response.success : response.taskStatus == "completed",
      inputTokens: response.inputTokens,
      outputTokens: response.outputTokens,
      costMicros: response.costMicros,
      richOutputJson: richOutput,
      receivedAtMillis: response.receivedAtMillis > 0 ? response.receivedAtMillis : max(nowMillis, 0),
      taskStatus: response.taskStatus,
      executionGeneration: response.executionGeneration,
      statusSequence: response.statusSequence,
      deliveryFailureCode: response.deliveryFailureCode
    )
  }
}

enum AgentConnectorRichOutput {
  static func normalize(_ raw: String) -> String {
    let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty,
          clean.count <= maxSerializedCharacters,
          let data = clean.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          (object["version"] as? Int ?? 1) <= 1,
          renderableBlocks(in: object).isEmpty == false else {
      return ""
    }
    return clean
  }

  static func fallbackText(_ raw: String) -> String {
    guard let data = raw.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return ""
    }
    for block in renderableBlocks(in: object) {
      for key in ["text", "title", "fallback_text", "uri"] {
        if let value = block[key] as? String {
          let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if !clean.isEmpty {
            return String(clean.prefix(AgentConnectorResponse.maxContentCharacters))
          }
        }
      }
    }
    return ""
  }

  private static func renderableBlocks(in object: [String: Any]) -> [[String: Any]] {
    guard let blocks = object["blocks"] as? [[String: Any]] else {
      return []
    }
    return blocks.prefix(maxBlocks).filter { block in
      ["text", "title", "fallback_text", "uri", "data_b64"].contains { key in
        guard let value = block[key] as? String else {
          return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
    }
  }

  private static let maxBlocks = 100
  private static let maxSerializedCharacters = 640 * 1_024
}
