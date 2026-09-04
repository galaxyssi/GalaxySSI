import Foundation
import SQLite3

struct AgentConversationPageCursor: Equatable {
  var pinned: Bool
  var updatedAt: Int64
  var id: String
}

struct AgentConversationPage: Equatable {
  var items: [AgentConversation]
  var nextCursor: AgentConversationPageCursor?
  var hasMore: Bool
}

final class AgentConversationDatabase {
  static let defaultPageSize = 24
  static let maximumPageSize = 200

  private let fileURL: URL
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(
    fileURL: URL = AgentConversationDatabase.defaultFileURL(),
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.fileURL = fileURL
    cipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.conversations.row.aes256.v1"
    )
    open()
  }

  deinit {
    if let database {
      sqlite3_close_v2(database)
    }
  }

  static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return root
      .appendingPathComponent("GalaxySSI/History", isDirectory: true)
      .appendingPathComponent("agent-conversations-v1.sqlite", isDirectory: false)
  }

  @discardableResult
  func upsert(_ conversation: AgentConversation) -> Bool {
    locked {
      guard let payload = encryptedPayload(conversation) else { return false }
      let sql = """
        INSERT INTO agent_conversations
          (conversation_id, status, pinned, created_at, updated_at, encrypted_payload)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(conversation_id) DO UPDATE SET
          status = excluded.status,
          pinned = excluded.pinned,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          encrypted_payload = excluded.encrypted_payload
        """
      guard let statement = prepare(sql) else { return false }
      defer { sqlite3_finalize(statement) }
      bind(conversation.id, at: 1, to: statement)
      bind(conversation.status.rawValue, at: 2, to: statement)
      sqlite3_bind_int(statement, 3, conversation.pinned ? 1 : 0)
      sqlite3_bind_int64(statement, 4, conversation.createdAt)
      sqlite3_bind_int64(statement, 5, conversation.updatedAt)
      payload.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 6, bytes.baseAddress, Int32(payload.count), Self.transient)
      }
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  @discardableResult
  func upsertAll(_ conversations: [AgentConversation]) -> Bool {
    locked {
      guard execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
      for conversation in conversations where !conversation.id.isBlank {
        guard upsert(conversation) else {
          _ = execute("ROLLBACK")
          return false
        }
      }
      return execute("COMMIT")
    }
  }

  func read(_ conversationId: String) -> AgentConversation? {
    locked {
      let sql = "SELECT encrypted_payload FROM agent_conversations WHERE conversation_id = ? LIMIT 1"
      guard let statement = prepare(sql) else { return nil }
      defer { sqlite3_finalize(statement) }
      bind(conversationId, at: 1, to: statement)
      guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
      return decode(statement, payloadColumn: 0, conversationId: conversationId)
    }
  }

  func firstActive() -> AgentConversation? {
    page(status: .active, cursor: nil, pageSize: 1).items.first
  }

  func readAll() -> [AgentConversation] {
    locked {
      query(
        sql: "SELECT conversation_id, encrypted_payload FROM agent_conversations ORDER BY pinned DESC, updated_at DESC, conversation_id DESC",
        bindValues: []
      )
    }
  }

  func page(
    status: AgentConversationStatus?,
    cursor: AgentConversationPageCursor?,
    pageSize: Int = AgentConversationDatabase.defaultPageSize
  ) -> AgentConversationPage {
    locked {
      let safeSize = min(max(1, pageSize), Self.maximumPageSize)
      var clauses: [String] = []
      var values: [SQLiteValue] = []
      if let status {
        clauses.append("status = ?")
        values.append(.text(status.rawValue))
      }
      if let cursor {
        clauses.append("(pinned < ? OR (pinned = ? AND updated_at < ?) OR (pinned = ? AND updated_at = ? AND conversation_id < ?))")
        let pinned: Int32 = cursor.pinned ? 1 : 0
        values += [
          .int(pinned), .int(pinned), .int64(cursor.updatedAt),
          .int(pinned), .int64(cursor.updatedAt), .text(cursor.id)
        ]
      }
      let predicate = clauses.isEmpty ? "" : " WHERE \(clauses.joined(separator: " AND "))"
      values.append(.int(Int32(safeSize + 1)))
      let rows = query(
        sql: "SELECT conversation_id, encrypted_payload FROM agent_conversations\(predicate) ORDER BY pinned DESC, updated_at DESC, conversation_id DESC LIMIT ?",
        bindValues: values
      )
      let hasMore = rows.count > safeSize
      let items = Array(rows.prefix(safeSize))
      let next = hasMore ? items.last.map {
        AgentConversationPageCursor(pinned: $0.pinned, updatedAt: $0.updatedAt, id: $0.id)
      } : nil
      return AgentConversationPage(items: items, nextCursor: next, hasMore: hasMore)
    }
  }

  func count(status: AgentConversationStatus? = nil) -> Int {
    locked {
      let predicate = status == nil ? "" : " WHERE status = ?"
      guard let statement = prepare("SELECT COUNT(*) FROM agent_conversations\(predicate)") else { return 0 }
      defer { sqlite3_finalize(statement) }
      if let status { bind(status.rawValue, at: 1, to: statement) }
      return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }
  }

  @discardableResult
  func delete(_ conversationId: String) -> AgentConversation? {
    locked {
      guard let current = read(conversationId),
            let statement = prepare("DELETE FROM agent_conversations WHERE conversation_id = ?") else {
        return nil
      }
      defer { sqlite3_finalize(statement) }
      bind(conversationId, at: 1, to: statement)
      return sqlite3_step(statement) == SQLITE_DONE ? current : nil
    }
  }

  @discardableResult
  func delete(_ conversationIds: Set<String>) -> Int {
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
        guard let statement = prepare("DELETE FROM agent_conversations WHERE conversation_id IN (\(placeholders))") else {
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
      if ids.contains(activeConversationId) {
        setActiveConversationId("")
      }
      return deleted
    }
  }

  @discardableResult
  func replaceAll(_ conversations: [AgentConversation]) -> Bool {
    locked {
      guard execute("BEGIN IMMEDIATE TRANSACTION"), execute("DELETE FROM agent_conversations") else {
        _ = execute("ROLLBACK")
        return false
      }
      for conversation in conversations where !conversation.id.isBlank {
        guard upsert(conversation) else {
          _ = execute("ROLLBACK")
          return false
        }
      }
      return execute("COMMIT")
    }
  }

  var activeConversationId: String {
    locked {
      guard let statement = prepare("SELECT state_value FROM agent_conversation_state WHERE state_key = 'active' LIMIT 1") else {
        return ""
      }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW,
            let text = sqlite3_column_text(statement, 0) else { return "" }
      return String(cString: text)
    }
  }

  func setActiveConversationId(_ conversationId: String) {
    locked {
      let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
      if clean.isEmpty {
        _ = execute("DELETE FROM agent_conversation_state WHERE state_key = 'active'")
        return
      }
      guard let statement = prepare("INSERT OR REPLACE INTO agent_conversation_state (state_key, state_value) VALUES ('active', ?)") else {
        return
      }
      defer { sqlite3_finalize(statement) }
      bind(clean, at: 1, to: statement)
      sqlite3_step(statement)
    }
  }

  func clear() {
    locked {
      _ = execute("DELETE FROM agent_conversations")
      _ = execute("DELETE FROM agent_conversation_state")
    }
  }

  func destroyAllData() {
    clear()
    cipher.destroyEncryptionKey()
  }

  private func open() {
    lock.lock()
    defer { lock.unlock() }
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
    _ = execute("PRAGMA foreign_keys = ON")
    _ = execute("CREATE TABLE IF NOT EXISTS agent_conversations (conversation_id TEXT PRIMARY KEY NOT NULL, status TEXT NOT NULL, pinned INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, encrypted_payload BLOB NOT NULL)")
    _ = execute("CREATE INDEX IF NOT EXISTS agent_conversations_order ON agent_conversations(status, pinned DESC, updated_at DESC, conversation_id DESC)")
    _ = execute("CREATE TABLE IF NOT EXISTS agent_conversation_state (state_key TEXT PRIMARY KEY NOT NULL, state_value TEXT NOT NULL)")
  }

  private func encryptedPayload(_ conversation: AgentConversation) -> Data? {
    guard let encoded = try? JSONEncoder().encode(conversation) else { return nil }
    return try? cipher.encrypt(encoded, purpose: purpose(conversation.id))
  }

  private func decode(
    _ statement: OpaquePointer?,
    payloadColumn: Int32,
    conversationId: String
  ) -> AgentConversation? {
    let count = Int(sqlite3_column_bytes(statement, payloadColumn))
    guard count > 0, let bytes = sqlite3_column_blob(statement, payloadColumn) else { return nil }
    let encrypted = Data(bytes: bytes, count: count)
    guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: purpose(conversationId)) else {
      return nil
    }
    return try? JSONDecoder().decode(AgentConversation.self, from: plaintext)
  }

  private func purpose(_ conversationId: String) -> String {
    "agent-conversation:\(conversationId)"
  }

  private enum SQLiteValue {
    case text(String)
    case int(Int32)
    case int64(Int64)
  }

  private func query(sql: String, bindValues: [SQLiteValue]) -> [AgentConversation] {
    guard let statement = prepare(sql) else { return [] }
    defer { sqlite3_finalize(statement) }
    for (offset, value) in bindValues.enumerated() {
      let index = Int32(offset + 1)
      switch value {
      case .text(let value): bind(value, at: index, to: statement)
      case .int(let value): sqlite3_bind_int(statement, index, value)
      case .int64(let value): sqlite3_bind_int64(statement, index, value)
      }
    }
    var rows: [AgentConversation] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let idText = sqlite3_column_text(statement, 0) else { continue }
      let id = String(cString: idText)
      if let conversation = decode(statement, payloadColumn: 1, conversationId: id) {
        rows.append(conversation)
      }
    }
    return rows
  }

  private func prepare(_ sql: String) -> OpaquePointer? {
    guard let database else { return nil }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    return statement
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
  private static let deleteBatchSize = 400
}

extension GalaxySSIStore {
  func agentSessions(includeArchived: Bool = false) -> [AgentConversation] {
    mergedAgentConversations()
      .filter { includeArchived || $0.status == .active }
  }

  func agentSessionPage(
    status: AgentConversationStatus?,
    cursor: AgentConversationPageCursor?,
    pageSize: Int = AgentConversationDatabase.defaultPageSize
  ) -> AgentConversationPage {
    agentConversationDatabase.page(status: status, cursor: cursor, pageSize: pageSize)
  }

  func agentSessionCount(status: AgentConversationStatus? = nil) -> Int {
    agentConversationDatabase.count(status: status)
  }

  func searchAgentSessions(_ query: String, includeArchived: Bool = false) -> [AgentConversation] {
    let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return agentSessions(includeArchived: includeArchived)
    }
    return agentSessions(includeArchived: includeArchived)
      .filter { conversation in
        [
          conversation.title,
          conversation.summary,
          conversation.selectedModelOrAgent,
          conversation.contextPolicy,
          conversation.id
        ].contains {
          $0.range(of: clean, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
  }

  func agentSession(id conversationId: String) -> AgentConversation? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    if let stored = agentConversationDatabase.read(clean) {
      return stored
    }
    return mergedAgentConversations().first { $0.id == clean }
  }

  func agentSessionDestination(id conversationId: String) -> String? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }

    var currentID = clean
    var visited: Set<String> = []
    while visited.insert(currentID).inserted,
          let conversation = agentConversationDatabase.read(currentID),
          !conversation.mergedIntoConversationId.isBlank {
      currentID = conversation.mergedIntoConversationId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !currentID.isEmpty else { return nil }
    }

    return agentSession(id: currentID)?.id
  }

  @discardableResult
  func createAgentSession(title: String = "", privateMode: Bool = false) -> AgentConversation {
    createAgentSession(
      title: title,
      createdByAgent: false,
      parentConversationId: "",
      globalTopicKey: "",
      privateMode: privateMode
    )
  }

  @discardableResult
  func createAgentConversation(
    title: String,
    parentConversationId: String = "",
    globalTopicKey: String = "",
    privateMode: Bool = false
  ) -> AgentConversation {
    createAgentSession(
      title: title,
      createdByAgent: true,
      parentConversationId: parentConversationId,
      globalTopicKey: globalTopicKey,
      privateMode: privateMode
    )
  }

  private func createAgentSession(
    title: String,
    createdByAgent: Bool,
    parentConversationId: String,
    globalTopicKey: String,
    privateMode: Bool
  ) -> AgentConversation {
    let now = Self.nowMillis()
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("New session")
    let conversationId = "ios-agent-\(UUID().uuidString.lowercased())"
    AgentModelSelectionSettings.inheritDefault(for: conversationId, defaults: defaults)
    let inheritedSelection = AgentModelSelectionSettings.selection(for: conversationId, defaults: defaults)
    let inheritedLabel = inheritedSelection.mode == .manual
      ? inheritedSelection.displayName.ifBlank(inheritedSelection.modelId).ifBlank("Automatic")
      : "Automatic"
    let session = AgentConversation(
      id: conversationId,
      title: cleanTitle,
      createdAt: now,
      updatedAt: now,
      selectedModelOrAgent: inheritedLabel,
      privateMode: privateMode,
      createdByAgent: createdByAgent,
      parentConversationId: parentConversationId.trimmingCharacters(in: .whitespacesAndNewlines),
      globalTopicKey: globalTopicKey.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    persistAgentConversation(session)
    if !createdByAgent {
      activeAgentConversationId = session.id
    }
    return session
  }

  @discardableResult
  func switchAgentSession(_ conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let destination = agentSessionDestination(id: clean),
          var session = agentSession(id: destination) else { return false }
    if session.status == .archived {
      session.status = .active
      session.updatedAt = Self.nowMillis()
      persistAgentConversation(session)
    }
    activeAgentConversationId = session.id
    return true
  }

  @discardableResult
  func renameAgentSession(id conversationId: String, title: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank(conversation.title)
    }
  }

  @discardableResult
  func setAgentSessionPinned(id conversationId: String, pinned: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.pinned = pinned }
  }

  @discardableResult
  func setAgentSessionPrivateMode(id conversationId: String, privateMode: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.privateMode = privateMode }
  }

  @discardableResult
  func setAgentSessionTrackingPaused(id conversationId: String, paused: Bool) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.trackingPaused = paused }
  }

  @discardableResult
  func setAgentSessionContextPolicy(id conversationId: String, policy: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.contextPolicy = ["minimal", "balanced", "extended"].contains(policy) ? policy : "balanced"
    }
  }

  @discardableResult
  func setAgentSessionSelectedModelOrAgent(id conversationId: String, label: String) -> Bool {
    mutateAgentConversation(id: conversationId) { conversation in
      conversation.selectedModelOrAgent = label.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank("Automatic")
    }
  }

  @discardableResult
  func updateAgentSessionSummary(id conversationId: String, summary: String) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines) }
  }

  @discardableResult
  func recordAgentSessionUsage(
    id conversationId: String,
    inputTokens: Int64,
    outputTokens: Int64,
    costMicros: Int64 = 0
  ) -> Bool {
    let input = max(inputTokens, 0)
    let output = max(outputTokens, 0)
    let cost = max(costMicros, 0)
    guard input > 0 || output > 0 || cost > 0 else { return false }
    return mutateAgentConversation(id: conversationId) { conversation in
      conversation.inputTokens = saturatingAdd(conversation.inputTokens, input)
      conversation.outputTokens = saturatingAdd(conversation.outputTokens, output)
      conversation.costMicros = saturatingAdd(conversation.costMicros, cost)
    }
  }

  @discardableResult
  func mergeAgentSessionIntoParent(id conversationId: String) -> AgentConversationMergeResult {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let source = agentSession(id: clean) else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: nil, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .sourceNotFound
      )
    }
    guard source.createdByAgent else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .notAgentCreated
      )
    }
    guard source.mergedIntoConversationId.isBlank else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .alreadyMerged
      )
    }
    guard let target = agentSession(id: source.parentConversationId) else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: nil,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .targetNotFound
      )
    }
    guard source.id != target.id else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: target,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .sameConversation
      )
    }
    guard source.privateMode == target.privateMode else {
      return AgentConversationMergeResult(
        merged: false, sourceConversation: source, targetConversation: target,
        copiedEntryCount: 0, skippedEntryCount: 0, failure: .privacyMismatch
      )
    }

    let sourceMessages = agentSessionMessages(source.id)
      .filter { !$0.isSystem }
      .sorted { left, right in
        if left.createdAt == right.createdAt {
          return left.id.uuidString < right.id.uuidString
        }
        return left.createdAt < right.createdAt
      }
    var targetMessageIDs = Set(
      chatHistoryDatabase.messages(conversationId: target.id).map(\.id)
    )
    var copiedMessageCount = 0
    var skippedMessageCount = 0
    for message in sourceMessages {
      let originConversationId = message.sourceConversationId.ifBlank(source.id)
      guard let stableID = AgentConversationMergePolicy.stableMergedMessageID(
        targetId: target.id,
        sourceId: originConversationId,
        messageId: message.id
      ) else {
        skippedMessageCount += 1
        continue
      }
      guard targetMessageIDs.insert(stableID).inserted else {
        skippedMessageCount += 1
        continue
      }
      var copy = message
      copy.id = stableID
      copy.conversationId = target.id
      copy.remoteMessageId = ""
      copy.sourceConversationId = originConversationId
      copy.sourceConversationTitle = message.sourceConversationTitle.ifBlank(source.title)
      messagesByContact[copy.contactId, default: []].append(copy)
      copiedMessageCount += 1
    }

    let now = Self.nowMillis()
    var mergedSource = source
    mergedSource.status = .archived
    mergedSource.trackingPaused = true
    mergedSource.mergedIntoConversationId = target.id
    mergedSource.mergedAtMillis = now
    mergedSource.updatedAt = now

    var mergedTarget = target
    mergedTarget.status = .active
    mergedTarget.summary = mergedSessionSummary(target.summary, source.summary)
    mergedTarget.inputTokens = saturatingAdd(target.inputTokens, source.inputTokens)
    mergedTarget.outputTokens = saturatingAdd(target.outputTokens, source.outputTokens)
    mergedTarget.costMicros = saturatingAdd(target.costMicros, source.costMicros)
    mergedTarget.updatedAt = max(target.updatedAt, source.updatedAt, now)

    agentTaskRecords = agentTaskRecords.map { task in
      guard task.sessionId == source.id else { return task }
      var rebound = task
      rebound.sessionId = target.id
      return rebound
    }
    persistAgentConversation(mergedSource)
    persistAgentConversation(mergedTarget)
    if activeAgentConversationId == source.id {
      activeAgentConversationId = target.id
    }
    save()
    return AgentConversationMergeResult(
      merged: true,
      sourceConversation: mergedSource,
      targetConversation: mergedTarget,
      copiedEntryCount: copiedMessageCount,
      skippedEntryCount: skippedMessageCount,
      failure: .none
    )
  }

  @discardableResult
  func archiveAgentSession(id conversationId: String) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let shouldClearActive = activeAgentConversationId == clean
    let changed = mutateAgentConversation(id: clean) { conversation in
      conversation.status = .archived
    }
    if changed && shouldClearActive {
      ensureActiveAgentSession()
    }
    return changed
  }

  @discardableResult
  func restoreAgentSession(id conversationId: String) -> Bool {
    mutateAgentConversation(id: conversationId) { $0.status = .active }
  }

  @discardableResult
  func deleteAgentSession(id conversationId: String) -> Bool {
    deleteAgentSessions(ids: [conversationId]) > 0
  }

  @discardableResult
  func deleteAgentSessions(ids conversationIds: Set<String>) -> Int {
    let ids = Set(conversationIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    guard !ids.isEmpty else { return 0 }
    let knownConversations = ids.compactMap { agentConversationDatabase.read($0) }
    let removedConversations = agentConversationDatabase.delete(ids)
    let removedChatMessages = chatHistoryDatabase.deleteConversations(ids)
    let removedTranscripts = UserDefaultsAgentTranscriptEntryStore(defaults: defaults, secrets: secrets)
      .deleteConversations(ids)
    agentConversations.removeAll { ids.contains($0.id) }
    var removedMessages = 0
    for contactId in Array(messagesByContact.keys) {
      guard var messages = messagesByContact[contactId] else { continue }
      let before = messages.count
      messages.removeAll { ids.contains($0.conversationId) }
      removedMessages += before - messages.count
      if messages.isEmpty {
        messagesByContact.removeValue(forKey: contactId)
      } else {
        messagesByContact[contactId] = messages
      }
    }
    let removedAnything = removedConversations > 0 || removedChatMessages > 0 ||
      removedTranscripts > 0 || removedMessages > 0 || !knownConversations.isEmpty
    guard removedAnything else { return 0 }
    if ids.contains(activeAgentConversationId) {
      ensureActiveAgentSession()
    }
    AgentModelSelectionSettings.clearConversations(ids, defaults: defaults)
    save()
    return max(max(removedConversations, knownConversations.count), removedAnything ? 1 : 0)
  }

  private func ensureActiveAgentSession() {
    if let active = agentSession(id: activeAgentConversationId), active.status == .active {
      return
    }
    if let next = agentConversationDatabase.firstActive() {
      activeAgentConversationId = next.id
      return
    }
    _ = createAgentSession(title: "New session")
  }

  func agentSessionMessages(_ conversationId: String) -> [ChatMessage] {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    return chatHistoryDatabase.messages(conversationId: clean)
  }

  func latestAgentSessionMessage(_ conversationId: String) -> ChatMessage? {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    return chatHistoryDatabase.latestMessage(conversationId: clean)
  }

  func agentSessionMetrics(_ conversationId: String) -> AgentSessionMetrics {
    let messages = agentSessionMessages(conversationId)
    let turnIds = Set(messages.map(\.turnId).filter { !$0.isBlank })
    let userTurns = messages.filter { $0.isMine && !$0.isSystem }.count
    let estimatedTokens = messages.reduce(0) { partial, message in
      partial + max(1, message.content.count / 4)
    }
    return AgentSessionMetrics(
      turnCount: max(turnIds.count, userTurns),
      messageCount: messages.count,
      taskCount: messages.filter { message in
        message.deliveryTrace.contains { $0.stage == "agent_started" || $0.stage == "agent_replied" }
      }.count,
      estimatedContextTokens: estimatedTokens,
      inputTokens: agentSession(id: conversationId)?.inputTokens ?? 0,
      outputTokens: agentSession(id: conversationId)?.outputTokens ?? 0,
      costMicros: agentSession(id: conversationId)?.costMicros ?? 0,
      lastResponseLatencyMillis: lastAgentResponseLatencyMillis(messages)
    )
  }
  @discardableResult
  private func mutateAgentConversation(
    id conversationId: String,
    mutate: (inout AgentConversation) -> Void
  ) -> Bool {
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var conversation = agentSession(id: clean) else { return false }
    mutate(&conversation)
    conversation.updatedAt = Self.nowMillis()
    persistAgentConversation(conversation)
    return true
  }

  private func mergedSessionSummary(_ target: String, _ source: String) -> String {
    let targetSummary = target.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceSummary = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if targetSummary.isEmpty { return sourceSummary }
    if sourceSummary.isEmpty || targetSummary == sourceSummary { return targetSummary }
    return "\(targetSummary)\n\n\(sourceSummary)"
  }

  private func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
    let (value, overflow) = left.addingReportingOverflow(right)
    return overflow ? Int64.max : value
  }

  private func persistAgentConversation(_ conversation: AgentConversation) {
    let clean = conversation.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    var updated = conversation
    updated.id = clean
    guard agentConversationDatabase.upsert(updated) else { return }
    let items = agentConversations.filter { $0.id != clean } + [updated]
    agentConversations = Array(
      Self.sortedAgentConversations(items).prefix(AgentConversationDatabase.maximumPageSize)
    )
  }

  private func mergedAgentConversations() -> [AgentConversation] {
    var byId: [String: AgentConversation] = [:]
    for conversation in agentConversationDatabase.readAll() where !conversation.id.isBlank {
      byId[conversation.id] = conversation
    }
    for contact in contacts where isAgentSessionContact(contact) {
      let conversationId = defaultAgentConversationId(for: contact.id)
      let messages = agentSessionMessages(conversationId)
      guard !messages.isEmpty || contact.id == "hermes" else { continue }
      let createdAt = messages.map { Self.millis($0.createdAt) }.min() ?? Self.nowMillis()
      let updatedAt = messages.map { Self.millis($0.createdAt) }.max() ?? createdAt
      var conversation = byId[conversationId] ?? AgentConversation(
        id: conversationId,
        title: contact.displayName,
        createdAt: createdAt,
        updatedAt: updatedAt,
        selectedModelOrAgent: contact.displayName
      )
      conversation.title = conversation.title.ifBlank(contact.displayName)
      conversation.selectedModelOrAgent = conversation.selectedModelOrAgent.ifBlank(contact.displayName)
      conversation.updatedAt = max(conversation.updatedAt, updatedAt)
      byId[conversationId] = conversation
    }
    return Self.sortedAgentConversations(Array(byId.values))
  }

  private func isAgentSessionContact(_ contact: GalaxySSIContact) -> Bool {
    contact.id == "hermes" || contact.type == "agent" || contact.deliveryMode == .cloudAPI
  }

  private func defaultAgentConversationId(for contactId: String) -> String {
    "ios-\(contactId)"
  }

  func activeConversationId(for contactId: String) -> String {
    if let contact = contact(id: contactId),
       isAgentSessionContact(contact),
       let active = agentSession(id: activeAgentConversationId),
       active.status == .active,
       active.mergedIntoConversationId.isBlank {
      return active.id
    }
    return defaultAgentConversationId(for: contactId)
  }

  func recordAgentConversationActivity(
    conversationId: String,
    contactId: String,
    content: String,
    at date: Date
  ) {
    guard let contact = contact(id: contactId), isAgentSessionContact(contact) else { return }
    let clean = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    let timestamp = Self.millis(date)
    var conversation = agentSession(id: clean) ?? AgentConversation(
      id: clean,
      title: inferredAgentSessionTitle(content: content, fallback: contact.displayName),
      createdAt: timestamp,
      updatedAt: timestamp,
      selectedModelOrAgent: contact.displayName
    )
    if conversation.title.isBlank || conversation.title == "New session" {
      conversation.title = inferredAgentSessionTitle(content: content, fallback: contact.displayName)
    }
    if conversation.selectedModelOrAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      conversation.selectedModelOrAgent = contact.displayName.ifBlank("Automatic")
    }
    conversation.updatedAt = max(conversation.updatedAt, timestamp)
    persistAgentConversation(conversation)
  }

  private func inferredAgentSessionTitle(content: String, fallback: String) -> String {
    let clean = content
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return fallback.ifBlank("New session") }
    return String(clean.prefix(48))
  }

  private static func sortedAgentConversations(_ conversations: [AgentConversation]) -> [AgentConversation] {
    conversations.sorted { left, right in
      if left.pinned != right.pinned {
        return left.pinned && !right.pinned
      }
      if left.updatedAt != right.updatedAt {
        return left.updatedAt > right.updatedAt
      }
      return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
  }

  private func lastAgentResponseLatencyMillis(_ messages: [ChatMessage]) -> Int64 {
    let ordered = messages.sorted { $0.createdAt < $1.createdAt }
    var lastUserAt: Date?
    var latestLatency: Int64 = 0
    for message in ordered {
      if message.isMine && !message.isSystem {
        lastUserAt = message.createdAt
      } else if !message.isMine && !message.isSystem, let start = lastUserAt {
        latestLatency = max(0, Self.millis(message.createdAt) - Self.millis(start))
      }
    }
    return latestLatency
  }

  static func millis(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }
}
