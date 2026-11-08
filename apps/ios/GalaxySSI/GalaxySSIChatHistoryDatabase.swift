import Foundation
import SQLite3

struct GalaxySSIChatHistoryCursor: Codable, Comparable, Sendable {
  var createdAtMillis: Int64
  var messageId: String

  init(_ message: ChatMessage) {
    self.init(createdAtMillis: Int64((message.createdAt.timeIntervalSince1970 * 1_000).rounded()),
              messageId: message.id.uuidString)
  }

  init(createdAtMillis: Int64, messageId: String) {
    self.createdAtMillis = createdAtMillis
    self.messageId = messageId
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.createdAtMillis, lhs.messageId) < (rhs.createdAtMillis, rhs.messageId)
  }
}

struct GalaxySSIChatHistoryPage: Equatable {
  var messages: [ChatMessage]
  var nextCursor: GalaxySSIChatHistoryCursor?
  var hasMore: Bool
  var turnStartMillis: [String: Int64] = [:]
}

enum GalaxySSIChatHistoryError: Error, Equatable {
  case locallyDeleted
}

// The SQLite connection, row cache and cipher access are serialized by lock.
final class GalaxySSIChatHistoryDatabase: AgentDesktopReplyRecoveryPersisting, GalaxySSILinkDeliveryPersisting, @unchecked Sendable {
  static let defaultPageSize = 100
  static let maximumPageSize = 500

  private let fileURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?
  private let rowCache = RowCache()
  private var rowCachingEnabled = true
  private var agentOwnerBackfillFinished = false

  struct RowCache {
    private struct Entry {
      let ciphertext: Data
      let message: ChatMessage
    }
    private let cache: GalaxySSIRuntimeCache<String, Entry>

    init(maximumRows: Int = 32, maximumBytes: Int = 512 * 1024,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
      cache = GalaxySSIRuntimeCache(maxCount: maximumRows, maxCost: maximumBytes, now: now)
    }

    func read(id: String, ciphertext: Data,
              decode: () -> (message: ChatMessage, plaintextBytes: Int)?) -> ChatMessage? {
      let revision = cache.revision
      if let entry = cache.value(for: id), entry.ciphertext == ciphertext {
        return entry.message
      }
      remove(id)
      guard let decoded = decode() else { return nil }
      cache.insert(Entry(ciphertext: ciphertext, message: decoded.message), for: id,
        cost: ciphertext.count + decoded.plaintextBytes, revision: revision)
      return decoded.message
    }

    func remove(_ id: String) { cache.remove(id) }
    func clear() { cache.clear() }
  }

  init(fileURL: URL, secrets: GalaxySSISecretStore) {
    self.fileURL = fileURL
    cipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "chat.history.row.aes256.v1"
    )
    open()
  }

  deinit {
    if let database { sqlite3_close_v2(database) }
  }

  func loadLinkDeliveryState() throws -> Data? {
    try locked {
      guard let statement = prepare("SELECT encrypted_payload FROM link_delivery_state WHERE singleton = 1") else { throw MqttChunkStorageError.databaseFailure }
      defer { sqlite3_finalize(statement) }
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return nil }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw MqttChunkStorageError.databaseFailure }
      let count = Int(sqlite3_column_bytes(statement, 0))
      guard count > 0 else { throw MqttChunkStorageError.databaseFailure }
      return try cipher.decrypt(Data(bytes: bytes, count: count), expectedPurpose: "link-delivery-state-v1")
    }
  }

  func registerCloudDispatch(_ receipt: AgentCloudDispatchReceipt) -> Bool {
    locked {
      let id = receipt.sourceId.uuidString
      guard let source = message(id: receipt.sourceId), receipt.matchesSource(source),
            let data = try? JSONEncoder().encode(receipt),
            let encrypted = try? cipher.encrypt(data, purpose: "cloud-dispatch-v1:\(id)"),
            encrypted.count < 8_192,
            execute("PRAGMA synchronous = FULL"), execute("PRAGMA fullfsync = ON"),
            let statement = prepare("""
              INSERT INTO cloud_dispatch_pending(source_id, encrypted_payload)
              SELECT ?, ? WHERE (SELECT COUNT(*) FROM cloud_dispatch_pending) < 512
              """) else { return false }
      defer { sqlite3_finalize(statement) }
      bind(id, at: 1, to: statement)
      encrypted.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(encrypted.count), Self.transient)
      }
      return sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(database) == 1
    }
  }

  func pendingCloudDispatches(sourceId: UUID? = nil) -> [AgentCloudDispatchReceipt] {
    locked {
      let condition = sourceId == nil ? "" : " WHERE source_id = ?"
      guard let statement = prepare("SELECT source_id, encrypted_payload FROM cloud_dispatch_pending" + condition) else {
        return []
      }
      defer { sqlite3_finalize(statement) }
      if let sourceId { bind(sourceId.uuidString, at: 1, to: statement) }
      var pending: [AgentCloudDispatchReceipt] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let rawId = sqlite3_column_text(statement, 0), let bytes = sqlite3_column_blob(statement, 1) else { continue }
        let id = String(cString: rawId)
        let size = Int(sqlite3_column_bytes(statement, 1))
        guard size > 0, size < 8_192,
              let payload = try? cipher.decrypt(Data(bytes: bytes, count: size), expectedPurpose: "cloud-dispatch-v1:\(id)"),
              let receipt = try? JSONDecoder().decode(AgentCloudDispatchReceipt.self, from: payload),
              receipt.sourceId.uuidString == id else { continue }
        pending.append(receipt)
      }
      return pending
    }
  }

  func cloudDispatchReplies(_ receipt: AgentCloudDispatchReceipt) -> [ChatMessage]? {
    locked {
      guard let statement = prepare("""
        SELECT message_id, encrypted_payload FROM chat_messages
        WHERE contact_id = ? AND remote_message_id IN (?, ?) AND is_mine = 0 AND is_system = 0
        AND conversation_id = ?
        """) else { return nil }
      defer { sqlite3_finalize(statement) }
      bind(receipt.contactId, at: 1, to: statement)
      bind(receipt.requestId, at: 2, to: statement)
      bind(receipt.previewId, at: 3, to: statement)
      bind(receipt.conversationId, at: 4, to: statement)
      var replies: [ChatMessage] = []
      while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return replies }
        guard step == SQLITE_ROW, let id = sqlite3_column_text(statement, 0),
              let message = decode(statement, id: String(cString: id), payloadColumn: 1) else { return nil }
        if receipt.matchesReply(message) { replies.append(message) }
      }
    }
  }

  func isDeletedCloudDispatchSource(_ receipt: AgentCloudDispatchReceipt) -> Bool {
    locked {
      (try? isLocallyDeleted(contactId: receipt.contactId, messageId: receipt.sourceId.uuidString, isMine: true)) == true
    }
  }

  func retireCloudDispatch(_ receipt: AgentCloudDispatchReceipt) -> Bool {
    locked {
      guard let statement = prepare("DELETE FROM cloud_dispatch_pending WHERE source_id = ?") else { return false }
      defer { sqlite3_finalize(statement) }
      bind(receipt.sourceId.uuidString, at: 1, to: statement)
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  func writeLinkDeliveryState(_ data: Data) -> Bool {
    locked {
      guard let encrypted = try? cipher.encrypt(data, purpose: "link-delivery-state-v1"), encrypted.count <= Int(Int32.max),
            execute("PRAGMA synchronous = FULL"), execute("PRAGMA fullfsync = ON"), execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      guard let statement = prepare("INSERT INTO link_delivery_state(singleton,encrypted_payload) VALUES(1,?) ON CONFLICT(singleton) DO UPDATE SET encrypted_payload=excluded.encrypted_payload") else { return false }
      defer { sqlite3_finalize(statement) }
      encrypted.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(encrypted.count), Self.transient) }
      guard sqlite3_step(statement) == SQLITE_DONE, execute("COMMIT") else { return false }
      committed = true
      return true
    }
  }

  func loadDesktopReplyRecoveryState() throws -> Data? {
    try locked {
      guard let statement = prepare("SELECT encrypted_payload FROM desktop_reply_recovery WHERE singleton = 1") else {
        throw MqttChunkStorageError.databaseFailure
      }
      defer { sqlite3_finalize(statement) }
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return nil }
      guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
        throw MqttChunkStorageError.databaseFailure
      }
      let count = Int(sqlite3_column_bytes(statement, 0))
      guard count > 0 else { throw MqttChunkStorageError.databaseFailure }
      return try cipher.decrypt(Data(bytes: bytes, count: count), expectedPurpose: "desktop-reply-recovery-v1")
    }
  }

  func writeDesktopReplyRecoveryState(_ data: Data) -> Bool {
    locked {
      guard let encrypted = try? cipher.encrypt(data, purpose: "desktop-reply-recovery-v1"),
            encrypted.count <= Int(Int32.max), execute("PRAGMA synchronous = FULL"),
            execute("PRAGMA fullfsync = ON"), execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      guard let statement = prepare("""
        INSERT INTO desktop_reply_recovery(singleton, encrypted_payload) VALUES(1, ?)
        ON CONFLICT(singleton) DO UPDATE SET encrypted_payload = excluded.encrypted_payload
        """) else { return false }
      defer { sqlite3_finalize(statement) }
      encrypted.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(encrypted.count), Self.transient)
      }
      guard sqlite3_step(statement) == SQLITE_DONE, execute("COMMIT") else { return false }
      committed = true
      return true
    }
  }

  func desktopReplySources(before cursor: GalaxySSIChatHistoryCursor?, pageSize: Int = 16) throws -> GalaxySSIChatHistoryPage {
    try locked {
      let limit = min(max(1, pageSize), Self.maximumPageSize)
      let boundary = cursor == nil ? "" : " AND (created_at < ? OR (created_at = ? AND message_id < ?))"
      guard let statement = prepare("""
        SELECT message_id, encrypted_payload FROM chat_messages
        WHERE is_mine = 1 AND is_system = 0\(boundary)
        ORDER BY created_at DESC, message_id DESC LIMIT ?
        """) else { throw MqttChunkStorageError.databaseFailure }
      defer { sqlite3_finalize(statement) }
      var parameter: Int32 = 1
      if let cursor {
        sqlite3_bind_int64(statement, 1, cursor.createdAtMillis)
        sqlite3_bind_int64(statement, 2, cursor.createdAtMillis)
        bind(cursor.messageId, at: 3, to: statement)
        parameter = 4
      }
      sqlite3_bind_int(statement, parameter, Int32(limit + 1))
      var rows: [ChatMessage] = []
      while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { break }
        guard step == SQLITE_ROW, let id = sqlite3_column_text(statement, 0),
              let message = decode(statement, id: String(cString: id), payloadColumn: 1),
              message.isMine, !message.isSystem else { throw MqttChunkStorageError.databaseFailure }
        rows.append(message)
      }
      let retained = Array(rows.prefix(limit))
      let hasMore = rows.count > limit
      let next = hasMore ? retained.last.map {
        GalaxySSIChatHistoryCursor(createdAtMillis: Self.millis($0.createdAt), messageId: $0.id.uuidString)
      } : nil
      return GalaxySSIChatHistoryPage(messages: retained, nextCursor: next, hasMore: hasMore)
    }
  }

  func deliveredDesktopReplyTurns(contactId: String, conversationId: String) throws -> Set<String> {
    var turns: Set<String> = []
    var cursor: GalaxySSIChatHistoryCursor?
    repeat {
      let page = try deliveredDesktopReplyTurnPage(contactId: contactId, conversationId: conversationId, before: cursor)
      turns.formUnion(page.turns)
      cursor = page.next
    } while cursor != nil
    return turns
  }

  func deliveredDesktopReplyTurnPage(contactId: String, conversationId: String,
                                     before cursor: GalaxySSIChatHistoryCursor?, pageSize: Int = 16) throws
    -> (turns: Set<String>, next: GalaxySSIChatHistoryCursor?) {
    try locked {
      let limit = min(max(1, pageSize), Self.maximumPageSize)
      let boundary = cursor == nil ? "" : " AND (created_at < ? OR (created_at = ? AND message_id < ?))"
      guard let statement = prepare("""
        SELECT message_id, encrypted_payload, created_at FROM chat_messages
        WHERE contact_id = ? AND conversation_id = ? AND is_mine = 0 AND is_system = 0\(boundary)
        ORDER BY created_at DESC, message_id DESC LIMIT ?
        """) else { throw MqttChunkStorageError.databaseFailure }
      defer { sqlite3_finalize(statement) }
      bind(contactId, at: 1, to: statement)
      bind(conversationId, at: 2, to: statement)
      var parameter: Int32 = 3
      if let cursor {
        sqlite3_bind_int64(statement, 3, cursor.createdAtMillis)
        sqlite3_bind_int64(statement, 4, cursor.createdAtMillis)
        bind(cursor.messageId, at: 5, to: statement)
        parameter = 6
      }
      sqlite3_bind_int(statement, parameter, Int32(limit + 1))
      var turns: Set<String> = []
      var last: GalaxySSIChatHistoryCursor?
      for index in 0...limit {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return (turns, nil) }
        guard step == SQLITE_ROW else { throw MqttChunkStorageError.databaseFailure }
        if index == limit { return (turns, last) }
        guard let id = sqlite3_column_text(statement, 0),
              let message = decode(statement, id: String(cString: id), payloadColumn: 1),
              message.contactId == contactId, message.conversationId == conversationId,
              !message.isMine, !message.isSystem else { throw MqttChunkStorageError.databaseFailure }
        if [ChatDeliveryStatus.delivered, .read].contains(message.deliveryStatus), !message.turnId.isBlank { turns.insert(message.turnId) }
        last = GalaxySSIChatHistoryCursor(createdAtMillis: sqlite3_column_int64(statement, 2), messageId: String(cString: id))
      }
      return (turns, nil)
    }
  }

  func commitDesktopReplyDisposition(contactId: String, remoteMessageId: String,
                                     conversationId: String, turnId: String) -> Bool {
    commitDesktopReply(contactId: contactId, remoteMessageId: remoteMessageId,
      conversationId: conversationId, turnId: turnId) != nil
  }

  enum DesktopReplyDisposition {
    case message(ChatMessage)
    case locallyDeleted
  }

  func commitDesktopReply(contactId: String, remoteMessageId: String,
                          conversationId: String, turnId: String) -> DesktopReplyDisposition? {
    locked {
      guard !remoteMessageId.isBlank, execute("PRAGMA synchronous = FULL"),
            execute("PRAGMA fullfsync = ON"), execute("BEGIN IMMEDIATE TRANSACTION") else { return nil }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      do {
        if try isLocallyDeleted(contactId: contactId, remoteMessageId: remoteMessageId, isMine: false) {
          committed = execute("COMMIT")
          return committed ? .locallyDeleted : nil
        }
      } catch { return nil }
      guard let statement = prepare("""
        SELECT message_id, encrypted_payload FROM chat_messages
        WHERE contact_id = ? AND remote_message_id = ? AND is_mine = 0 AND is_system = 0
        """) else { return nil }
      defer { sqlite3_finalize(statement) }
      bind(contactId, at: 1, to: statement)
      bind(remoteMessageId, at: 2, to: statement)
      guard sqlite3_step(statement) == SQLITE_ROW, let id = sqlite3_column_text(statement, 0),
            let message = decode(statement, id: String(cString: id), payloadColumn: 1),
            message.contactId == contactId, message.remoteMessageId == remoteMessageId,
            message.conversationId == conversationId, message.turnId == turnId,
            !message.isMine, !message.isSystem,
            [ChatDeliveryStatus.delivered, .read].contains(message.deliveryStatus),
            sqlite3_step(statement) == SQLITE_DONE, upsert(message), execute("COMMIT") else { return nil }
      committed = true
      return .message(message)
    }
  }

  @discardableResult
  func upsert(_ message: ChatMessage) -> Bool {
    locked {
      guard admitsAgentTurn(message) else { return false }
      if Self.agentTurnScoped(message), let prior = self.message(id: message.id) {
        guard prior.conversationId == message.conversationId,
              !prior.isMine || prior.turnId.isBlank ||
                Self.ownershipTurn(prior.turnId) == Self.ownershipTurn(message.turnId) else { return false }
      }
      guard !message.contactId.isBlank,
            let deleted = try? isLocallyDeleted(contactId: message.contactId, messageId: message.id.uuidString,
              remoteMessageId: message.remoteMessageId, isMine: message.isMine), !deleted,
            let payload = encryptedPayload(message),
            let statement = prepare("""
              INSERT INTO chat_messages
                (message_id, contact_id, conversation_id, created_at, is_mine, is_system, remote_message_id, encrypted_payload,
                 agent_turn_key, agent_unread_key, agent_owner_key)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(message_id) DO UPDATE SET
                contact_id = excluded.contact_id,
                conversation_id = excluded.conversation_id,
                created_at = excluded.created_at,
                is_mine = excluded.is_mine,
                is_system = excluded.is_system,
                remote_message_id = excluded.remote_message_id,
                encrypted_payload = excluded.encrypted_payload,
                agent_turn_key = excluded.agent_turn_key,
                agent_unread_key = excluded.agent_unread_key,
                agent_owner_key = excluded.agent_owner_key
              """) else { return false }
      defer { sqlite3_finalize(statement) }
      bind(message.id.uuidString, at: 1, to: statement)
      bind(message.contactId, at: 2, to: statement)
      bind(message.conversationId, at: 3, to: statement)
      sqlite3_bind_int64(statement, 4, Self.millis(message.createdAt))
      sqlite3_bind_int(statement, 5, message.isMine ? 1 : 0)
      sqlite3_bind_int(statement, 6, message.isSystem ? 1 : 0)
      bind(message.remoteMessageId, at: 7, to: statement)
      payload.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 8, bytes.baseAddress, Int32(payload.count), Self.transient)
      }
      if let key = turnTimingKey(message) { bind(key, at: 9, to: statement) }
      if let key = unreadReplyKey(message) { bind(key, at: 10, to: statement) }
      if let key = ownershipIndex(message) { bind(key, at: 11, to: statement) }
      guard sqlite3_step(statement) == SQLITE_DONE else { return false }
      rowCache.remove(message.id.uuidString)
      return true
    }
  }

  @discardableResult
  func upsertAll(_ messages: [ChatMessage]) -> Bool {
    locked {
      guard execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
      for message in messages {
        guard upsert(message) else {
          _ = execute("ROLLBACK")
          return false
        }
      }
      return execute("COMMIT")
    }
  }

  // Only chat-message completions belong here. Task and attachment receipts need their own
  // durable writers; never silently consume them as a successful chat update.
  func persistTransportDelivery(_ event: MqttDeliveryCompletions.Event) throws -> ChatMessage {
    let source = event.sourceMessageID.isEmpty ? event.messageID : event.sourceMessageID
    guard let id = UUID(uuidString: source), !event.contactID.isBlank,
          event.attachmentTransferID.isEmpty, event.traffic == MqttMultipathPolicy.Traffic.message.rawValue else {
      throw MqttRouteError.invalidPayload
    }
    let key = try event.identity.key(messageID: event.messageID)
    let traceID = UUID(uuidString: "\(key.prefix(8))-\(key.dropFirst(8).prefix(4))-\(key.dropFirst(12).prefix(4))-\(key.dropFirst(16).prefix(4))-\(key.dropFirst(20).prefix(12))")!
    _ = try MqttBusinessStorage.timestamp(event.receivedAt)
    return try locked {
      // This commit precedes consumption in another database; NORMAL is insufficient for that handoff.
      guard execute("PRAGMA synchronous = FULL"), execute("PRAGMA fullfsync = ON"),
            execute("BEGIN IMMEDIATE TRANSACTION") else { throw MqttChunkStorageError.databaseFailure }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      guard var saved = message(id: id), saved.contactId == event.contactID, saved.isMine else {
        throw MqttRouteError.invalidPayload
      }
      if saved.deliveryStatus != .read { saved.deliveryStatus = .delivered }
      if !saved.deliveryTrace.contains(where: { $0.id == traceID }) {
        saved.deliveryTrace.append(DeliveryTraceEvent(id: traceID, stage: "delivered",
          createdAt: Date(timeIntervalSince1970: Double(event.receivedAt) / 1000)))
      }
      guard upsert(saved), execute("COMMIT") else { throw MqttChunkStorageError.databaseFailure }
      committed = true
      return saved
    }
  }

  // Commit before the transport inbox is consumed. Deduplicate on disk, not in the paged UI cache.
  func persistTransportIncoming(_ message: ChatMessage, replacing pendingID: UUID? = nil,
                                allowAgentStreamReplacement: Bool = false) throws -> ChatMessage {
    guard !message.isMine, !message.isSystem, !message.contactId.isBlank,
          !message.remoteMessageId.isBlank, pendingID == nil || pendingID == message.id else {
      throw MqttRouteError.invalidPayload
    }
    return try locked {
      guard execute("PRAGMA synchronous = FULL"), execute("PRAGMA fullfsync = ON"),
            execute("BEGIN IMMEDIATE TRANSACTION") else { throw MqttChunkStorageError.databaseFailure }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      if try isLocallyDeleted(contactId: message.contactId, messageId: message.id.uuidString,
        remoteMessageId: message.remoteMessageId, isMine: false) {
        throw GalaxySSIChatHistoryError.locallyDeleted
      }
      guard let statement = prepare("""
        SELECT message_id, encrypted_payload FROM chat_messages
        WHERE (contact_id = ? AND remote_message_id = ? AND is_mine = 0) OR message_id = ?
        """) else { throw MqttChunkStorageError.databaseFailure }
      defer { sqlite3_finalize(statement) }
      bind(message.contactId, at: 1, to: statement)
      bind(message.remoteMessageId, at: 2, to: statement)
      bind(message.id.uuidString, at: 3, to: statement)
      var replay: ChatMessage?
      while true {
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { break }
        guard step == SQLITE_ROW, let rawID = sqlite3_column_text(statement, 0),
              let saved = decode(statement, id: String(cString: rawID), payloadColumn: 1) else {
          throw MqttChunkStorageError.databaseFailure
        }
        guard !saved.isMine, !saved.isSystem, saved.contactId == message.contactId else {
          throw MqttRouteError.invalidPayload
        }
        if saved.id != message.id, !admitsAgentTurn(saved) { continue }
        if saved.id == pendingID, saved.remoteMessageId != message.remoteMessageId {
          guard saved.remoteMessageId.hasPrefix("pending-peer:") ||
            (allowAgentStreamReplacement && saved.remoteMessageId.hasPrefix("agent-stream-")) else { throw MqttRouteError.invalidPayload }
          continue
        }
        guard saved.remoteMessageId == message.remoteMessageId, saved.content == message.content,
              saved.turnId == message.turnId, saved.conversationId == message.conversationId,
              replay == nil else { throw MqttRouteError.invalidPayload }
        replay = saved
      }
      let saved = replay ?? message
      guard upsert(saved), execute("COMMIT") else { throw MqttChunkStorageError.databaseFailure }
      committed = true
      return saved
    }
  }

  func page(
    contactId: String?,
    conversationId: String? = nil,
    before cursor: GalaxySSIChatHistoryCursor? = nil,
    after newerCursor: GalaxySSIChatHistoryCursor? = nil,
    pageSize: Int = GalaxySSIChatHistoryDatabase.defaultPageSize
  ) -> GalaxySSIChatHistoryPage {
    locked {
      let safeSize = min(max(1, pageSize), Self.maximumPageSize)
      guard (contactId != nil || conversationId?.isBlank == false),
            cursor == nil || newerCursor == nil else {
        return GalaxySSIChatHistoryPage(messages: [], nextCursor: nil, hasMore: false)
      }
      var clauses: [String] = []
      var values: [SQLiteValue] = []
      if let contactId {
        clauses.append("contact_id = ?")
        values.append(.text(contactId))
      }
      if let conversationId, !conversationId.isBlank {
        clauses.append("conversation_id = ?")
        values.append(.text(conversationId))
      }
      if let boundary = cursor ?? newerCursor {
        let comparison = newerCursor == nil ? "<" : ">"
        clauses.append("(created_at \(comparison) ? OR (created_at = ? AND message_id \(comparison) ?))")
        values += [.int64(boundary.createdAtMillis), .int64(boundary.createdAtMillis), .text(boundary.messageId)]
      }
      values.append(.int(Int32(safeSize + 1)))
      let direction = newerCursor == nil ? "DESC" : "ASC"
      let rows = query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages WHERE \(clauses.joined(separator: " AND ")) ORDER BY created_at \(direction), message_id \(direction) LIMIT ?",
        values: values
      )
      let hasMore = rows.count > safeSize
      if newerCursor != nil {
        let ascending = Array(rows.prefix(safeSize))
        let next = hasMore ? ascending.last.map(GalaxySSIChatHistoryCursor.init) : nil
        return GalaxySSIChatHistoryPage(messages: ascending.filter(admitsAgentTurn), nextCursor: next, hasMore: hasMore)
      }
      let descending = Array(rows.prefix(safeSize))
      let retained = descending.reversed()
      let oldest = descending.last
      let next = hasMore ? oldest.map(GalaxySSIChatHistoryCursor.init) : nil
      return GalaxySSIChatHistoryPage(messages: retained.filter(admitsAgentTurn), nextCursor: next, hasMore: hasMore)
    }
  }

  func agentTranscriptWindow(conversationId: String, limit: Int) async -> GalaxySSIChatHistoryPage? {
    guard !conversationId.isBlank, limit > 0 else { return nil }
    let read = Task.detached(priority: .userInitiated) { [self] () -> GalaxySSIChatHistoryPage? in
      var pages: [[ChatMessage]] = []
      var cursor: GalaxySSIChatHistoryCursor?
      var remaining = limit
      var hasMore = false
      repeat {
        guard !Task.isCancelled else { return nil }
        let next: GalaxySSIChatHistoryPage? = locked {
          guard rowCachingEnabled else { return nil }
          return page(contactId: nil, conversationId: conversationId, before: cursor,
                      pageSize: min(remaining, Self.defaultPageSize))
        }
        guard let next else { return nil }
        pages.append(next.messages)
        remaining -= next.messages.count
        cursor = next.nextCursor
        hasMore = next.hasMore
      } while remaining > 0 && hasMore && cursor != nil
      guard !Task.isCancelled else { return nil }
      var seen = Set<UUID>()
      let messages = pages.reversed().flatMap { $0 }.filter { seen.insert($0.id).inserted }
      var starts = AgentProcessClockPolicy.visibleRequestStarts(messages, conversationId: conversationId)
      if hasMore {
        let missing = Set(messages.lazy.filter { !$0.isMine && !$0.isSystem && !$0.turnId.isBlank }
          .map { AgentReplyWaitingIndicatorPolicy.turnKey(for: $0) }).subtracting(starts.keys)
        if !missing.isEmpty {
          guard let persisted = turnTimingStarts(conversationId: conversationId, turnIds: missing) else { return nil }
          starts.merge(persisted, uniquingKeysWith: min)
        }
      }
      guard !Task.isCancelled, locked({ rowCachingEnabled }) else { return nil }
      return GalaxySSIChatHistoryPage(messages: messages, nextCursor: cursor, hasMore: hasMore, turnStartMillis: starts)
    }
    return await withTaskCancellationHandler(operation: { await read.value }, onCancel: { read.cancel() })
  }

  private func turnTimingKey(_ message: ChatMessage) -> String? {
    guard message.isMine, !message.isSystem, !message.conversationId.isBlank else { return "" }
    return try? cipher.chatTurnTimingIndex(conversationId: message.conversationId,
      turnId: AgentReplyWaitingIndicatorPolicy.turnKey(for: message))
  }

  private static func agentTurnScoped(_ message: ChatMessage) -> Bool {
    message.contactId == "hermes" || message.conversationId.hasPrefix("ios-agent-")
  }

  private func ownershipIndex(_ message: ChatMessage) -> String? {
    guard Self.agentTurnScoped(message), message.isMine, !message.isSystem, message.sourceConversationId.isBlank,
          !message.conversationId.isBlank else { return "" }
    return try? cipher.chatTurnOwnershipIndex(Self.ownershipTurn(message.turnId.ifBlank(message.id.uuidString)))
  }

  private static func ownershipTurn(_ turn: String) -> String {
    UUID(uuidString: turn)?.uuidString ?? turn
  }

  private func backfillAgentTurnOwners() {
    guard !agentOwnerBackfillFinished, let database,
          (try? cipher.chatTurnOwnershipIndex("migration")) != nil else { return }
    let ownsTransaction = sqlite3_get_autocommit(database) != 0
    if ownsTransaction, !execute("BEGIN IMMEDIATE TRANSACTION") { return }
    var complete = false
    defer {
      if ownsTransaction {
        if complete, execute("COMMIT") { agentOwnerBackfillFinished = true }
        else { _ = execute("ROLLBACK") }
      }
    }
    // Legacy originals are indexed on demand. The sentinel leaves unrelated or unreadable rows untouched.
    while let select = prepare("""
      SELECT message_id,encrypted_payload FROM chat_messages
      WHERE agent_owner_key IS NULL AND is_mine=1 AND is_system=0
        AND (contact_id='hermes' OR conversation_id GLOB 'ios-agent-*') LIMIT 128
      """) {
      var batch: [(String, String)] = []
      var step = sqlite3_step(select)
      while step == SQLITE_ROW {
        defer { step = sqlite3_step(select) }
        guard let raw = sqlite3_column_text(select, 0) else { continue }
        let id = String(cString: raw)
        if let message = decode(select, id: id, payloadColumn: 1), let key = ownershipIndex(message) {
          batch.append((id, key))
        } else { batch.append((id, "")) }
      }
      sqlite3_finalize(select)
      guard step == SQLITE_DONE else { return }
      if batch.isEmpty { complete = true; return }
      guard let update = prepare("UPDATE chat_messages SET agent_owner_key=? WHERE message_id=? AND agent_owner_key IS NULL") else { return }
      var changed = true
      for (id, key) in batch {
        sqlite3_reset(update)
        bind(key, at: 1, to: update)
        bind(id, at: 2, to: update)
        if sqlite3_step(update) != SQLITE_DONE { changed = false; break }
      }
      sqlite3_finalize(update)
      if !changed { return }
      if batch.count < 128 { complete = true; return }
    }
  }

  func originalAgentTurnConversation(_ turn: String) -> String? {
    guard !turn.isBlank else { return nil }
    let turn = Self.ownershipTurn(turn)
    return locked {
      if let id = UUID(uuidString: turn), let original = message(id: id),
         Self.agentTurnScoped(original), original.isMine, !original.isSystem, original.sourceConversationId.isBlank,
         !original.conversationId.isBlank, Self.ownershipTurn(original.turnId.ifBlank(original.id.uuidString)) == turn {
        return original.conversationId
      }
      backfillAgentTurnOwners()
      guard let key = try? cipher.chatTurnOwnershipIndex(turn),
            let lookup = prepare("""
              SELECT message_id,encrypted_payload FROM chat_messages
              WHERE is_mine=1 AND is_system=0 AND agent_owner_key=?
              ORDER BY created_at,message_id LIMIT 1
              """) else { return nil }
      defer { sqlite3_finalize(lookup) }
      bind(key, at: 1, to: lookup)
      guard sqlite3_step(lookup) == SQLITE_ROW, let id = sqlite3_column_text(lookup, 0),
            let original = decode(lookup, id: String(cString: id), payloadColumn: 1),
            ownershipIndex(original) == key else { return nil }
      return original.conversationId
    }
  }

  func admitsAgentTurn(_ message: ChatMessage) -> Bool {
    guard Self.agentTurnScoped(message), !message.isSystem, !message.turnId.isBlank,
          let owner = originalAgentTurnConversation(message.turnId) else { return true }
    return message.conversationId == owner || message.sourceConversationId == owner
  }

  private func unreadReplyKey(_ message: ChatMessage) -> String? {
    guard let token = AgentReplyUnreadPolicy.token(message) else { return "" }
    return try? cipher.chatUnreadReplyIndex(conversationId: message.conversationId, token: token)
  }

  // Older rows have no unread index. Upgrade small batches separately from identifier-only probes.
  func prepareLegacyUnreadIndex(conversationId: String) {
    for _ in 0..<4 {
      guard !Task.isCancelled, locked({ indexUnreadPage(conversationId: conversationId) }) else { return }
    }
  }

  private func indexUnreadPage(conversationId: String) -> Bool {
    guard rowCachingEnabled, let read = prepare("""
      SELECT message_id, encrypted_payload FROM chat_messages WHERE conversation_id = ?
        AND contact_id = 'hermes' AND is_mine = 0 AND is_system = 0 AND agent_unread_key IS NULL LIMIT 64
      """) else { return false }
    bind(conversationId, at: 1, to: read)
    var rows: [(id: String, key: String)] = []
    while !Task.isCancelled, sqlite3_step(read) == SQLITE_ROW {
      guard let text = sqlite3_column_text(read, 0) else { continue }
      let id = String(cString: text)
      guard let message = decode(read, id: id, payloadColumn: 1), message.conversationId == conversationId,
            let key = unreadReplyKey(message) else { continue }
      rows.append((id, key))
    }
    sqlite3_finalize(read)
    guard !Task.isCancelled, !rows.isEmpty,
          let update = prepare("UPDATE chat_messages SET agent_unread_key = ? WHERE message_id = ? AND agent_unread_key IS NULL")
    else { return false }
    defer { sqlite3_finalize(update) }
    guard execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
    for row in rows {
      sqlite3_reset(update)
      bind(row.key, at: 1, to: update)
      bind(row.id, at: 2, to: update)
      guard sqlite3_step(update) == SQLITE_DONE else { _ = execute("ROLLBACK"); return false }
    }
    guard execute("COMMIT") else { _ = execute("ROLLBACK"); return false }
    return rows.count == 64
  }

  func missingUnreadTokens(conversationId: String, candidates: Set<String>) -> Set<String>? {
    locked {
      guard rowCachingEnabled, !Task.isCancelled,
            let legacy = prepare("""
              SELECT 1 FROM chat_messages WHERE conversation_id = ?
                AND contact_id = 'hermes' AND is_mine = 0 AND is_system = 0 AND agent_unread_key IS NULL LIMIT 1
              """) else { return nil }
      defer { sqlite3_finalize(legacy) }
      bind(conversationId, at: 1, to: legacy)
      // Absence is only authoritative once every eligible legacy row has an index value.
      guard sqlite3_step(legacy) == SQLITE_DONE,
            let lookup = prepare("""
              SELECT 1 FROM chat_messages WHERE conversation_id = ?
                AND contact_id = 'hermes' AND is_mine = 0 AND is_system = 0 AND agent_unread_key = ? LIMIT 1
              """) else { return nil }
      defer { sqlite3_finalize(lookup) }
      var missing = Set<String>()
      for token in candidates {
        guard !Task.isCancelled,
              let key = try? cipher.chatUnreadReplyIndex(conversationId: conversationId, token: token) else { return nil }
        sqlite3_reset(lookup)
        bind(conversationId, at: 1, to: lookup)
        bind(key, at: 2, to: lookup)
        switch sqlite3_step(lookup) {
        case SQLITE_DONE: missing.insert(token)
        case SQLITE_ROW: break
        default: return nil
        }
      }
      return missing
    }
  }

  private func turnTimingStarts(conversationId: String, turnIds: Set<String>) -> [String: Int64]? {
    var cursor: GalaxySSIChatHistoryCursor?
    while !Task.isCancelled {
      let legacy: (allowed: Bool, cursor: GalaxySSIChatHistoryCursor?) = locked {
        guard rowCachingEnabled else { return (false, nil) }
        return (true, indexLegacyTurnTimingRows(conversationId: conversationId, after: cursor))
      }
      guard legacy.allowed else { return nil }
      guard let next = legacy.cursor else { break }
      cursor = next
    }
    guard !Task.isCancelled else { return nil }
    var starts: [String: Int64] = [:]
    for turn in turnIds {
      guard !Task.isCancelled else { return nil }
      let result: (allowed: Bool, start: Int64?) = locked {
        guard rowCachingEnabled else { return (false, nil) }
        guard let key = try? cipher.chatTurnTimingIndex(conversationId: conversationId, turnId: turn),
              let statement = prepare("""
                SELECT created_at FROM chat_messages
                WHERE conversation_id = ? AND agent_turn_key = ? AND is_mine = 1 AND is_system = 0 AND created_at > 0
                ORDER BY created_at ASC, message_id ASC LIMIT 1
                """) else { return (true, nil) }
        defer { sqlite3_finalize(statement) }
        bind(conversationId, at: 1, to: statement)
        bind(key, at: 2, to: statement)
        return (true, sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : nil)
      }
      guard result.allowed else { return nil }
      starts[turn] = result.start
    }
    return starts
  }

  // Older builds left the timing index empty. Hydrate only the selected conversation,
  // off the UI thread and in bounded chunks; never store the decrypted turn identifier.
  private func indexLegacyTurnTimingRows(
    conversationId: String, after cursor: GalaxySSIChatHistoryCursor?
  ) -> GalaxySSIChatHistoryCursor? {
    let boundary = cursor == nil ? "" : "AND (created_at > ? OR (created_at = ? AND message_id > ?))"
    guard let read = prepare("""
      SELECT message_id, encrypted_payload, created_at FROM chat_messages
      WHERE conversation_id = ? AND agent_turn_key IS NULL AND is_mine = 1 AND is_system = 0 \(boundary)
      ORDER BY created_at ASC, message_id ASC LIMIT 64
      """) else { return nil }
    bind(conversationId, at: 1, to: read)
    if let cursor {
      sqlite3_bind_int64(read, 2, cursor.createdAtMillis)
      sqlite3_bind_int64(read, 3, cursor.createdAtMillis)
      bind(cursor.messageId, at: 4, to: read)
    }
    var last: GalaxySSIChatHistoryCursor?
    var indexed: [(id: String, key: String)] = []
    while !Task.isCancelled, sqlite3_step(read) == SQLITE_ROW {
      guard let idText = sqlite3_column_text(read, 0) else { continue }
      let id = String(cString: idText)
      last = GalaxySSIChatHistoryCursor(createdAtMillis: sqlite3_column_int64(read, 2), messageId: id)
      if let message = decode(read, id: id, payloadColumn: 1), message.conversationId == conversationId,
         let key = turnTimingKey(message) {
        indexed.append((id, key))
      }
    }
    sqlite3_finalize(read)
    guard !Task.isCancelled, !indexed.isEmpty,
          let update = prepare("UPDATE chat_messages SET agent_turn_key = ? WHERE message_id = ? AND agent_turn_key IS NULL")
    else { return last }
    defer { sqlite3_finalize(update) }
    guard execute("BEGIN IMMEDIATE TRANSACTION") else { return last }
    for (id, key) in indexed {
      guard !Task.isCancelled else { _ = execute("ROLLBACK"); return last }
      sqlite3_reset(update)
      bind(key, at: 1, to: update)
      bind(id, at: 2, to: update)
      guard sqlite3_step(update) == SQLITE_DONE else { _ = execute("ROLLBACK"); return last }
    }
    if !execute("COMMIT") { _ = execute("ROLLBACK") }
    return last
  }

  func messages(conversationId: String) -> [ChatMessage] {
    locked {
      query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages WHERE conversation_id = ? ORDER BY created_at ASC, message_id ASC",
        values: [.text(conversationId)]
      ).filter(admitsAgentTurn)
    }
  }

  func recentMessagesByContact(
    limitPerContact: Int = GalaxySSIChatHistoryDatabase.defaultPageSize
  ) -> [String: [ChatMessage]] {
    locked {
      guard let statement = prepare("SELECT DISTINCT contact_id FROM chat_messages") else { return [:] }
      defer { sqlite3_finalize(statement) }
      var contactIds: [String] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        if let value = sqlite3_column_text(statement, 0) {
          contactIds.append(String(cString: value))
        }
      }
      return Dictionary(uniqueKeysWithValues: contactIds.map { contactId in
        (contactId, page(contactId: contactId, pageSize: limitPerContact).messages)
      })
    }
  }

  func allMessagesByContact() -> [String: [ChatMessage]] {
    locked {
      Dictionary(grouping: query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages ORDER BY contact_id ASC, created_at ASC, message_id ASC",
        values: []
      ), by: \.contactId)
    }
  }

  func messages(contactId: String) -> [ChatMessage] {
    locked {
      query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages WHERE contact_id = ? ORDER BY created_at ASC, message_id ASC",
        values: [.text(contactId)]
      ).filter(admitsAgentTurn)
    }
  }

  func latestMessage(contactId: String) -> ChatMessage? {
    page(contactId: contactId, pageSize: 1).messages.last
  }

  func latestMessage(conversationId: String) -> ChatMessage? {
    var cursor: GalaxySSIChatHistoryCursor?
    repeat {
      let next = page(contactId: nil, conversationId: conversationId, before: cursor)
      if let last = next.messages.last { return last }
      cursor = next.nextCursor
    } while cursor != nil
    return nil
  }

  func unreadCount(contactId: String, after date: Date) -> Int {
    locked {
      guard let statement = prepare("SELECT COUNT(*) FROM chat_messages WHERE contact_id = ? AND is_mine = 0 AND is_system = 0 AND created_at > ?") else {
        return 0
      }
      defer { sqlite3_finalize(statement) }
      bind(contactId, at: 1, to: statement)
      sqlite3_bind_int64(statement, 2, Self.millis(date))
      return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }
  }

  func message(id: UUID) -> ChatMessage? {
    locked {
      query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages WHERE message_id = ? LIMIT 1",
        values: [.text(id.uuidString)]
      ).first
    }
  }

  func containsIncoming(contactId: String, remoteMessageId: String) -> Bool {
    locked {
      if (try? isLocallyDeleted(contactId: contactId, remoteMessageId: remoteMessageId, isMine: false)) == true {
        return true
      }
      guard !remoteMessageId.isBlank else { return false }
      return query(sql: """
        SELECT message_id,encrypted_payload FROM chat_messages WHERE contact_id=? AND remote_message_id=? AND is_mine=0
        """, values: [.text(contactId), .text(remoteMessageId)]).contains(where: admitsAgentTurn)
    }
  }

  @discardableResult
  func deleteMessage(id: UUID, contactId: String? = nil) -> ChatMessage? {
    locked {
      guard execute("PRAGMA synchronous = FULL"), execute("PRAGMA fullfsync = ON"),
            execute("BEGIN IMMEDIATE TRANSACTION") else { return nil }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      guard let current = message(id: id), contactId == nil || contactId == current.contactId,
            let tombstone = prepare("""
        INSERT OR IGNORE INTO chat_message_deletions (contact_id, message_id, remote_message_id, is_mine)
        VALUES (?, ?, ?, ?)
        """) else { return nil }
      defer { sqlite3_finalize(tombstone) }
      bind(current.contactId, at: 1, to: tombstone)
      bind(current.id.uuidString, at: 2, to: tombstone)
      bind(current.remoteMessageId, at: 3, to: tombstone)
      sqlite3_bind_int(tombstone, 4, current.isMine ? 1 : 0)
      guard sqlite3_step(tombstone) == SQLITE_DONE,
            let statement = prepare("DELETE FROM chat_messages WHERE message_id = ? AND contact_id = ?") else { return nil }
      defer { sqlite3_finalize(statement) }
      bind(id.uuidString, at: 1, to: statement)
      bind(current.contactId, at: 2, to: statement)
      guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database) == 1,
            execute("COMMIT") else { return nil }
      committed = true
      rowCache.remove(id.uuidString)
      return current
    }
  }

  private func isLocallyDeleted(contactId: String, messageId: String = "",
                                remoteMessageId: String, isMine: Bool) throws -> Bool {
    guard let statement = prepare("""
      SELECT 1 FROM chat_message_deletions WHERE contact_id = ? AND message_id = ?
      UNION ALL
      SELECT 1 FROM chat_message_deletions WHERE contact_id = ? AND ? <> ''
        AND remote_message_id = ? AND is_mine = ? LIMIT 1
      """) else { throw MqttChunkStorageError.databaseFailure }
    defer { sqlite3_finalize(statement) }
    bind(contactId, at: 1, to: statement)
    bind(messageId, at: 2, to: statement)
    bind(contactId, at: 3, to: statement)
    bind(remoteMessageId, at: 4, to: statement)
    bind(remoteMessageId, at: 5, to: statement)
    sqlite3_bind_int(statement, 6, isMine ? 1 : 0)
    let step = sqlite3_step(statement)
    guard step == SQLITE_ROW || step == SQLITE_DONE else { throw MqttChunkStorageError.databaseFailure }
    return step == SQLITE_ROW
  }

  func deleteContact(_ contactId: String) {
    delete(whereClause: "contact_id = ?", value: contactId)
  }

  func deleteConversation(_ conversationId: String) {
    delete(whereClause: "conversation_id = ?", value: conversationId)
  }

  @discardableResult
  func deleteConversations(_ conversationIds: Set<String>) -> Int {
    locked {
      let ids = conversationIds
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .sorted()
      guard !ids.isEmpty, execute("BEGIN IMMEDIATE TRANSACTION") else { return 0 }
      var deleted = 0
      for start in stride(from: 0, to: ids.count, by: Self.deleteBatchSize) {
        let batch = Array(ids[start..<min(start + Self.deleteBatchSize, ids.count)])
        let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
        guard let statement = prepare("DELETE FROM chat_messages WHERE conversation_id IN (\(placeholders))") else {
          _ = execute("ROLLBACK")
          return 0
        }
        for (offset, id) in batch.enumerated() {
          bind(id, at: Int32(offset + 1), to: statement)
        }
        let succeeded = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        guard succeeded else {
          _ = execute("ROLLBACK")
          return 0
        }
        deleted += Int(sqlite3_changes(database))
      }
      guard execute("COMMIT") else {
        _ = execute("ROLLBACK")
        return 0
      }
      rowCache.clear()
      return deleted
    }
  }

  @discardableResult
  func replaceAll(_ messagesByContact: [String: [ChatMessage]]) -> Bool {
    locked {
      rowCache.clear()
      // Explicit backup restoration is distinct from automatic replay or cache synchronization.
      guard execute("BEGIN IMMEDIATE TRANSACTION"), execute("DELETE FROM chat_messages"),
            execute("DELETE FROM chat_message_deletions") else {
        _ = execute("ROLLBACK")
        return false
      }
      for message in messagesByContact.values.flatMap({ $0 }) {
        guard upsert(message) else {
          _ = execute("ROLLBACK")
          return false
        }
      }
      return execute("COMMIT")
    }
  }

  func clear() {
    locked {
      rowCache.clear()
      _ = execute("DELETE FROM chat_messages")
    }
  }

  func setRowCachingEnabled(_ enabled: Bool) {
    locked {
      rowCachingEnabled = enabled
      if !enabled { rowCache.clear() }
    }
  }

  func destroyAllData() {
    clear()
    locked { _ = execute("DELETE FROM chat_message_deletions") }
    locked { _ = execute("DELETE FROM desktop_reply_recovery") }
    locked { _ = execute("DELETE FROM link_delivery_state") }
    locked { _ = execute("DELETE FROM cloud_dispatch_pending") }
    cipher.destroyEncryptionKey()
  }

  var count: Int {
    locked {
      guard let statement = prepare("SELECT COUNT(*) FROM chat_messages") else { return 0 }
      defer { sqlite3_finalize(statement) }
      return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }
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
    _ = execute("PRAGMA synchronous = NORMAL")
    _ = execute("CREATE TABLE IF NOT EXISTS chat_messages (message_id TEXT PRIMARY KEY NOT NULL, contact_id TEXT NOT NULL, conversation_id TEXT NOT NULL, created_at INTEGER NOT NULL, is_mine INTEGER NOT NULL, is_system INTEGER NOT NULL, remote_message_id TEXT NOT NULL, encrypted_payload BLOB NOT NULL, agent_turn_key TEXT, agent_unread_key TEXT)")
    if let column = prepare("SELECT agent_turn_key FROM chat_messages LIMIT 0") {
      sqlite3_finalize(column)
    } else {
      _ = execute("ALTER TABLE chat_messages ADD COLUMN agent_turn_key TEXT")
    }
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_agent_turn_start ON chat_messages(conversation_id, agent_turn_key, created_at, message_id) WHERE is_mine = 1 AND is_system = 0")
    if let column = prepare("SELECT agent_unread_key FROM chat_messages LIMIT 0") {
      sqlite3_finalize(column)
    } else {
      _ = execute("ALTER TABLE chat_messages ADD COLUMN agent_unread_key TEXT")
    }
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_agent_unread ON chat_messages(conversation_id, agent_unread_key) WHERE contact_id = 'hermes' AND is_mine = 0 AND is_system = 0")
    if let column = prepare("SELECT agent_owner_key FROM chat_messages LIMIT 0") {
      sqlite3_finalize(column)
    } else {
      _ = execute("ALTER TABLE chat_messages ADD COLUMN agent_owner_key TEXT")
    }
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_agent_owner ON chat_messages(agent_owner_key,created_at,message_id) WHERE is_mine=1 AND is_system=0")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_contact_order ON chat_messages(contact_id, created_at DESC, message_id DESC)")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_conversation_order ON chat_messages(conversation_id, created_at ASC, message_id ASC)")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_remote_dedupe ON chat_messages(contact_id, remote_message_id, is_mine)")
    _ = execute("CREATE TABLE IF NOT EXISTS chat_message_deletions (contact_id TEXT NOT NULL, message_id TEXT NOT NULL, remote_message_id TEXT NOT NULL, is_mine INTEGER NOT NULL, PRIMARY KEY(contact_id, message_id))")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_message_deletions_remote ON chat_message_deletions(contact_id, remote_message_id, is_mine)")
    _ = execute("CREATE TABLE IF NOT EXISTS desktop_reply_recovery (singleton INTEGER PRIMARY KEY CHECK(singleton = 1), encrypted_payload BLOB NOT NULL)")
    _ = execute("CREATE TABLE IF NOT EXISTS link_delivery_state (singleton INTEGER PRIMARY KEY CHECK(singleton = 1), encrypted_payload BLOB NOT NULL)")
    _ = execute("CREATE TABLE IF NOT EXISTS cloud_dispatch_pending (source_id TEXT PRIMARY KEY NOT NULL, encrypted_payload BLOB NOT NULL)")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_outgoing_discovery ON chat_messages(created_at DESC, message_id DESC) WHERE is_mine = 1 AND is_system = 0")
  }

  private func encryptedPayload(_ message: ChatMessage) -> Data? {
    guard let data = try? JSONEncoder().encode(message) else { return nil }
    return try? cipher.encrypt(data, purpose: purpose(message.id.uuidString))
  }

  private func decode(_ statement: OpaquePointer?, id: String, payloadColumn: Int32) -> ChatMessage? {
    let count = Int(sqlite3_column_bytes(statement, payloadColumn))
    guard count > 0, let bytes = sqlite3_column_blob(statement, payloadColumn) else { return nil }
    let encrypted = Data(bytes: bytes, count: count)
    let cipher = self.cipher
    let associatedPurpose = purpose(id)
    let decrypt = { () -> (message: ChatMessage, plaintextBytes: Int)? in
      guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: associatedPurpose),
            let message = try? JSONDecoder().decode(ChatMessage.self, from: plaintext) else { return nil }
      return (message, plaintext.count)
    }
    // Reads within a write transaction may observe rows that later roll back.
    guard rowCachingEnabled, let database, sqlite3_get_autocommit(database) != 0 else { return decrypt()?.message }
    return rowCache.read(id: id, ciphertext: encrypted, decode: decrypt)
  }

  private func purpose(_ id: String) -> String { "chat-message:\(id)" }

  private enum SQLiteValue {
    case text(String)
    case int(Int32)
    case int64(Int64)
  }

  private func query(sql: String, values: [SQLiteValue]) -> [ChatMessage] {
    guard let statement = prepare(sql) else { return [] }
    defer { sqlite3_finalize(statement) }
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      switch value {
      case .text(let text): bind(text, at: index, to: statement)
      case .int(let number): sqlite3_bind_int(statement, index, number)
      case .int64(let number): sqlite3_bind_int64(statement, index, number)
      }
    }
    var messages: [ChatMessage] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = sqlite3_column_text(statement, 0) else { continue }
      let id = String(cString: idText)
      if let message = decode(statement, id: id, payloadColumn: 1) {
        messages.append(message)
      }
    }
    return messages
  }

  private func delete(whereClause: String, value: String) {
    locked {
      rowCache.clear()
      guard let statement = prepare("DELETE FROM chat_messages WHERE \(whereClause)") else { return }
      defer { sqlite3_finalize(statement) }
      bind(value, at: 1, to: statement)
      _ = sqlite3_step(statement)
    }
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

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private static let deleteBatchSize = 400
}
