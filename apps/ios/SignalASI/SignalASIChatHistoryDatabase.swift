import Foundation
import SQLite3

struct SignalASIChatHistoryCursor: Equatable {
  var createdAtMillis: Int64
  var messageId: String
}

struct SignalASIChatHistoryPage: Equatable {
  var messages: [ChatMessage]
  var nextCursor: SignalASIChatHistoryCursor?
  var hasMore: Bool
}

final class SignalASIChatHistoryDatabase {
  static let defaultPageSize = 100
  static let maximumPageSize = 500

  private let fileURL: URL
  private let cipher: SignalASIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(fileURL: URL, secrets: SignalASISecretStore) {
    self.fileURL = fileURL
    cipher = SignalASIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "chat.history.row.aes256.v1"
    )
    open()
  }

  deinit {
    if let database { sqlite3_close_v2(database) }
  }

  @discardableResult
  func upsert(_ message: ChatMessage) -> Bool {
    locked {
      guard !message.contactId.isBlank,
            let payload = encryptedPayload(message),
            let statement = prepare("""
              INSERT INTO chat_messages
                (message_id, contact_id, conversation_id, created_at, is_mine, is_system, remote_message_id, encrypted_payload)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(message_id) DO UPDATE SET
                contact_id = excluded.contact_id,
                conversation_id = excluded.conversation_id,
                created_at = excluded.created_at,
                is_mine = excluded.is_mine,
                is_system = excluded.is_system,
                remote_message_id = excluded.remote_message_id,
                encrypted_payload = excluded.encrypted_payload
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
      return sqlite3_step(statement) == SQLITE_DONE
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

  func page(
    contactId: String,
    conversationId: String? = nil,
    before cursor: SignalASIChatHistoryCursor? = nil,
    pageSize: Int = SignalASIChatHistoryDatabase.defaultPageSize
  ) -> SignalASIChatHistoryPage {
    locked {
      let safeSize = min(max(1, pageSize), Self.maximumPageSize)
      var clauses = ["contact_id = ?"]
      var values: [SQLiteValue] = [.text(contactId)]
      if let conversationId, !conversationId.isBlank {
        clauses.append("conversation_id = ?")
        values.append(.text(conversationId))
      }
      if let cursor {
        clauses.append("(created_at < ? OR (created_at = ? AND message_id < ?))")
        values += [.int64(cursor.createdAtMillis), .int64(cursor.createdAtMillis), .text(cursor.messageId)]
      }
      values.append(.int(Int32(safeSize + 1)))
      let rows = query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages WHERE \(clauses.joined(separator: " AND ")) ORDER BY created_at DESC, message_id DESC LIMIT ?",
        values: values
      )
      let hasMore = rows.count > safeSize
      let descending = Array(rows.prefix(safeSize))
      let retained = descending.reversed()
      let oldest = descending.last
      let next = hasMore ? oldest.map {
        SignalASIChatHistoryCursor(createdAtMillis: Self.millis($0.createdAt), messageId: $0.id.uuidString)
      } : nil
      return SignalASIChatHistoryPage(messages: Array(retained), nextCursor: next, hasMore: hasMore)
    }
  }

  func messages(conversationId: String) -> [ChatMessage] {
    locked {
      query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages WHERE conversation_id = ? ORDER BY created_at ASC, message_id ASC",
        values: [.text(conversationId)]
      )
    }
  }

  func recentMessagesByContact(
    limitPerContact: Int = SignalASIChatHistoryDatabase.defaultPageSize
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
      )
    }
  }

  func latestMessage(contactId: String) -> ChatMessage? {
    page(contactId: contactId, pageSize: 1).messages.last
  }

  func latestMessage(conversationId: String) -> ChatMessage? {
    locked {
      query(
        sql: "SELECT message_id, encrypted_payload FROM chat_messages WHERE conversation_id = ? ORDER BY created_at DESC, message_id DESC LIMIT 1",
        values: [.text(conversationId)]
      ).first
    }
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
      guard !remoteMessageId.isBlank,
            let statement = prepare("SELECT 1 FROM chat_messages WHERE contact_id = ? AND remote_message_id = ? AND is_mine = 0 LIMIT 1") else {
        return false
      }
      defer { sqlite3_finalize(statement) }
      bind(contactId, at: 1, to: statement)
      bind(remoteMessageId, at: 2, to: statement)
      return sqlite3_step(statement) == SQLITE_ROW
    }
  }

  @discardableResult
  func deleteMessage(id: UUID) -> ChatMessage? {
    locked {
      guard let current = message(id: id),
            let statement = prepare("DELETE FROM chat_messages WHERE message_id = ?") else { return nil }
      defer { sqlite3_finalize(statement) }
      bind(id.uuidString, at: 1, to: statement)
      return sqlite3_step(statement) == SQLITE_DONE ? current : nil
    }
  }

  func deleteContact(_ contactId: String) {
    delete(whereClause: "contact_id = ?", value: contactId)
  }

  func deleteConversation(_ conversationId: String) {
    delete(whereClause: "conversation_id = ?", value: conversationId)
  }

  @discardableResult
  func replaceAll(_ messagesByContact: [String: [ChatMessage]]) -> Bool {
    locked {
      guard execute("BEGIN IMMEDIATE TRANSACTION"), execute("DELETE FROM chat_messages") else {
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
    locked { _ = execute("DELETE FROM chat_messages") }
  }

  func destroyAllData() {
    clear()
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
    _ = execute("CREATE TABLE IF NOT EXISTS chat_messages (message_id TEXT PRIMARY KEY NOT NULL, contact_id TEXT NOT NULL, conversation_id TEXT NOT NULL, created_at INTEGER NOT NULL, is_mine INTEGER NOT NULL, is_system INTEGER NOT NULL, remote_message_id TEXT NOT NULL, encrypted_payload BLOB NOT NULL)")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_contact_order ON chat_messages(contact_id, created_at DESC, message_id DESC)")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_conversation_order ON chat_messages(conversation_id, created_at ASC, message_id ASC)")
    _ = execute("CREATE INDEX IF NOT EXISTS chat_messages_remote_dedupe ON chat_messages(contact_id, remote_message_id, is_mine)")
  }

  private func encryptedPayload(_ message: ChatMessage) -> Data? {
    guard let data = try? JSONEncoder().encode(message) else { return nil }
    return try? cipher.encrypt(data, purpose: purpose(message.id.uuidString))
  }

  private func decode(_ statement: OpaquePointer?, id: String, payloadColumn: Int32) -> ChatMessage? {
    let count = Int(sqlite3_column_bytes(statement, payloadColumn))
    guard count > 0, let bytes = sqlite3_column_blob(statement, payloadColumn) else { return nil }
    let encrypted = Data(bytes: bytes, count: count)
    guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: purpose(id)) else { return nil }
    return try? JSONDecoder().decode(ChatMessage.self, from: plaintext)
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

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
