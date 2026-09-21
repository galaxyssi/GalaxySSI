import CryptoKit
import Foundation
import SQLite3

enum AgentKnowledgeDatabaseError: Error, Equatable {
  case unavailable
  case corruptRecord
  case staleCursor
}

final class AgentKnowledgeDatabase {
  private let fileURL: URL
  private let secrets: GalaxySSISecretStore
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let vectorCipher: GalaxySSIAttachmentAtRestCipher
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.fileURL = fileURL
    self.secrets = secrets
    cipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.knowledge.row.aes256.v1"
    )
    vectorCipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.knowledge.vector.aes256.v1"
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

  func searchCandidates(query: String, limit: Int = 256) throws -> [AgentKnowledgeItem] {
    try locked {
      let tokens = searchTokens(query).map(keyedHash)
      guard !tokens.isEmpty else { return [] }
      guard let statement = prepare("""
        SELECT k.item_hash, k.encrypted_payload
        FROM knowledge_fts f
        JOIN knowledge_items k ON k.item_hash = f.item_hash
        WHERE knowledge_fts MATCH ?
        ORDER BY bm25(knowledge_fts), k.updated_at DESC
        LIMIT ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(tokens.joined(separator: " OR "), at: 1, to: statement)
      sqlite3_bind_int(statement, 2, Int32(min(max(limit, 1), 256)))
      var items: [AgentKnowledgeItem] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        items.append(try decode(statement, hashColumn: 0, payloadColumn: 1))
      }
      return items
    }
  }

  @discardableResult
  func storeVectorCheckpoint(_ checkpoint: AgentKnowledgeVectorCheckpoint) -> Bool {
    locked {
      guard checkpoint.isValid else { return false }
      let vectorKey = keyedHash(checkpoint.id)
      if let existing = vectorCheckpoint(vectorKey: vectorKey),
         existing.sourceRevision == checkpoint.sourceRevision,
         existing.updatedAtMillis >= checkpoint.updatedAtMillis {
        return false
      }
      guard let plaintext = try? JSONEncoder.galaxySSI.encode(checkpoint),
            let encrypted = try? vectorCipher.encrypt(plaintext, purpose: vectorPurpose(vectorKey)),
            let statement = prepare("""
              INSERT INTO knowledge_vectors(
                vector_key, item_hash, model_hash, source_revision_hash, updated_at, encrypted_payload
              ) VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(vector_key) DO UPDATE SET
                source_revision_hash = excluded.source_revision_hash,
                updated_at = excluded.updated_at,
                encrypted_payload = excluded.encrypted_payload
              """) else { return false }
      defer { sqlite3_finalize(statement) }
      bind(vectorKey, at: 1, to: statement)
      bind(keyedHash(checkpoint.itemId), at: 2, to: statement)
      bind(keyedHash(checkpoint.provenance.modelSHA256), at: 3, to: statement)
      bind(keyedHash(checkpoint.sourceRevision), at: 4, to: statement)
      sqlite3_bind_int64(statement, 5, checkpoint.updatedAtMillis)
      encrypted.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 6, bytes.baseAddress, Int32(encrypted.count), Self.transient)
      }
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  func vectorCheckpoints(itemId: String, modelSHA256: String) throws -> [AgentKnowledgeVectorCheckpoint] {
    try locked {
      guard let statement = prepare("""
        SELECT vector_key, encrypted_payload FROM knowledge_vectors
        WHERE item_hash = ? AND model_hash = ?
        ORDER BY vector_key ASC
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(keyedHash(itemId), at: 1, to: statement)
      bind(keyedHash(modelSHA256.lowercased()), at: 2, to: statement)
      var checkpoints: [AgentKnowledgeVectorCheckpoint] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let keyText = sqlite3_column_text(statement, 0),
              let encrypted = blob(statement, column: 1) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let key = String(cString: keyText)
        guard let plaintext = try? vectorCipher.decrypt(encrypted, expectedPurpose: vectorPurpose(key)),
              let checkpoint = try? JSONDecoder.galaxySSI.decode(
                AgentKnowledgeVectorCheckpoint.self,
                from: plaintext
              ), checkpoint.isValid else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        checkpoints.append(checkpoint)
      }
      return checkpoints.sorted { $0.chunkIndex < $1.chunkIndex }
    }
  }

  @discardableResult
  func clearVectorCheckpoints(itemId: String, modelSHA256: String) -> Bool {
    locked {
      guard let statement = prepare(
        "DELETE FROM knowledge_vectors WHERE item_hash = ? AND model_hash = ?"
      ) else { return false }
      defer { sqlite3_finalize(statement) }
      bind(keyedHash(itemId), at: 1, to: statement)
      bind(keyedHash(modelSHA256.lowercased()), at: 2, to: statement)
      return sqlite3_step(statement) == SQLITE_DONE
    }
  }

  func pendingVectorItems(modelSHA256: String, limit: Int = 32) throws -> [AgentKnowledgeItem] {
    let items = try all()
    var pending: [AgentKnowledgeItem] = []
    for item in items {
      let revision = AgentKnowledgeVectorCheckpoint.sourceRevision(for: item)
      let checkpoints = try vectorCheckpoints(itemId: item.id, modelSHA256: modelSHA256)
      let expectedCount = checkpoints.first?.chunkCount ?? 0
      let completeIndices = Set(checkpoints.map(\.chunkIndex)) == Set(0..<expectedCount)
      if checkpoints.isEmpty || checkpoints.contains(where: { $0.sourceRevision != revision }) ||
         checkpoints.count != expectedCount || !completeIndices {
        pending.append(item)
        if pending.count >= min(max(limit, 1), 64) { break }
      }
    }
    return pending
  }

  func vectorCatalog(
    modelSHA256: String,
    offset: Int = 0,
    limit: Int = 256
  ) throws -> [AgentKnowledgeVectorCheckpoint] {
    try locked {
      guard let statement = prepare("""
        SELECT vector_key, encrypted_payload FROM knowledge_vectors
        WHERE model_hash = ?
        ORDER BY vector_key ASC
        LIMIT ? OFFSET ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(keyedHash(modelSHA256.lowercased()), at: 1, to: statement)
      sqlite3_bind_int(statement, 2, Int32(min(max(limit, 1), 512)))
      sqlite3_bind_int(statement, 3, Int32(max(offset, 0)))
      var checkpoints: [AgentKnowledgeVectorCheckpoint] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let keyText = sqlite3_column_text(statement, 0),
              let encrypted = blob(statement, column: 1) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let key = String(cString: keyText)
        guard let plaintext = try? vectorCipher.decrypt(encrypted, expectedPurpose: vectorPurpose(key)),
              let checkpoint = try? JSONDecoder.galaxySSI.decode(
                AgentKnowledgeVectorCheckpoint.self,
                from: plaintext
              ), checkpoint.isValid else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        checkpoints.append(checkpoint)
      }
      return checkpoints
    }
  }

  func sourcePage(cursor: AgentKnowledgeSourceCursor? = nil, limit: Int = 50) throws -> AgentKnowledgeSourcePage {
    try locked {
      let pageSize = min(max(limit, 1), 50)
      guard let revision = scalar("SELECT revision FROM knowledge_browse_revision WHERE id = 1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      if let cursor, cursor.revision != revision { throw AgentKnowledgeDatabaseError.staleCursor }
      let predicate = cursor == nil ? "" : "WHERE updated_at < ? OR (updated_at = ? AND source_hash > ?)"
      guard let statement = prepare("""
        SELECT source_hash, updated_at, encrypted_header FROM knowledge_source_headers
        \(predicate)
        ORDER BY updated_at DESC, source_hash ASC
        LIMIT ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      var bindIndex: Int32 = 1
      if let cursor {
        sqlite3_bind_int64(statement, bindIndex, cursor.updatedAtMillis)
        sqlite3_bind_int64(statement, bindIndex + 1, cursor.updatedAtMillis)
        bind(cursor.sourceHash, at: bindIndex + 2, to: statement)
        bindIndex += 3
      }
      sqlite3_bind_int(statement, bindIndex, Int32(pageSize + 1))
      var rows: [(String, AgentKnowledgeSourceGroup)] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let hashText = sqlite3_column_text(statement, 0),
              let encrypted = blob(statement, column: 2) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let sourceHash = String(cString: hashText)
        guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: sourceHeaderPurpose(sourceHash)),
              let group = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeSourceGroup.self, from: plaintext) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        rows.append((sourceHash, group))
      }
      let shown = Array(rows.prefix(pageSize))
      let next = rows.count > pageSize ? shown.last.map {
        AgentKnowledgeSourceCursor(
          updatedAtMillis: $0.1.updatedAtMillis,
          sourceHash: $0.0,
          revision: revision
        )
      } : nil
      return AgentKnowledgeSourcePage(
        groups: shown.map { $0.1 },
        total: Int(scalar("SELECT COUNT(*) FROM knowledge_source_headers") ?? 0),
        next: next
      )
    }
  }

  func sourceItemIds(sourceIdentity: String) throws -> [String] {
    try locked {
      guard !sourceIdentity.isBlank,
            let statement = prepare("""
              SELECT item_hash, encrypted_payload FROM knowledge_items
              WHERE source_hash = ? ORDER BY item_hash ASC
              """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(keyedHash(sourceIdentity), at: 1, to: statement)
      var ids: [String] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        ids.append(try decode(statement, hashColumn: 0, payloadColumn: 1).id)
      }
      return ids
    }
  }

  @discardableResult
  func replaceAll(_ items: [AgentKnowledgeItem]) -> Bool {
    locked {
      guard validateIdentities(items), execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
      guard execute("DELETE FROM knowledge_fts"), execute("DELETE FROM knowledge_items"),
            execute("DELETE FROM knowledge_source_headers") else {
        _ = execute("ROLLBACK")
        return false
      }
      for item in items where !insert(item) {
        _ = execute("ROLLBACK")
        return false
      }
      for group in sourceGroups(items) where !insertSourceHeader(group) {
        _ = execute("ROLLBACK")
        return false
      }
      guard execute("DELETE FROM knowledge_vectors WHERE item_hash NOT IN (SELECT item_hash FROM knowledge_items)") else {
        _ = execute("ROLLBACK")
        return false
      }
      guard execute("UPDATE knowledge_browse_revision SET revision = revision + 1 WHERE id = 1"),
            execute("COMMIT") else {
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
    bind(keyedHash(sourceIdentity(item)), at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, item.updatedAtMillis)
    encrypted.withUnsafeBytes { bytes in
      sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(encrypted.count), Self.transient)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else { return false }
    guard let indexStatement = prepare(
      "INSERT INTO knowledge_fts(item_hash, tokens) VALUES (?, ?)"
    ) else { return false }
    defer { sqlite3_finalize(indexStatement) }
    bind(itemHash, at: 1, to: indexStatement)
    let searchable = [item.title, item.summary, item.content, item.source, item.tags.joined(separator: " ")]
      .joined(separator: " ")
    bind(searchTokens(searchable).map(keyedHash).joined(separator: " "), at: 2, to: indexStatement)
    return sqlite3_step(indexStatement) == SQLITE_DONE
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

  private func sourceGroups(_ items: [AgentKnowledgeItem]) -> [AgentKnowledgeSourceGroup] {
    Dictionary(grouping: items, by: sourceIdentity)
      .map { source, members in
        let sorted = members.sorted { $0.updatedAtMillis > $1.updatedAtMillis }
        let latest = sorted[0]
        return AgentKnowledgeSourceGroup(
          source: source,
          title: latest.title.replacingOccurrences(
            of: "\\s+\\[[0-9]+/[0-9]+\\]$",
            with: "",
            options: .regularExpression
          ),
          itemIds: [],
          chunkCount: members.count,
          cloudAccess: latest.cloudAccess,
          agentAccess: latest.agentAccess,
          allowedAgentIds: latest.allowedAgentIds,
          updatedAtMillis: latest.updatedAtMillis
        )
      }
  }

  private func insertSourceHeader(_ group: AgentKnowledgeSourceGroup) -> Bool {
    let sourceHash = keyedHash(group.source)
    guard let plaintext = try? JSONEncoder.galaxySSI.encode(group),
          let encrypted = try? cipher.encrypt(plaintext, purpose: sourceHeaderPurpose(sourceHash)),
          let statement = prepare("""
            INSERT INTO knowledge_source_headers(source_hash, updated_at, encrypted_header)
            VALUES (?, ?, ?)
            """) else { return false }
    defer { sqlite3_finalize(statement) }
    bind(sourceHash, at: 1, to: statement)
    sqlite3_bind_int64(statement, 2, group.updatedAtMillis)
    encrypted.withUnsafeBytes { bytes in
      sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(encrypted.count), Self.transient)
    }
    return sqlite3_step(statement) == SQLITE_DONE
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
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_source_headers (
        source_hash TEXT PRIMARY KEY NOT NULL,
        updated_at INTEGER NOT NULL,
        encrypted_header BLOB NOT NULL
      )
      """)
    _ = execute("CREATE INDEX IF NOT EXISTS knowledge_source_header_recent ON knowledge_source_headers(updated_at DESC, source_hash ASC)")
    _ = execute("CREATE TABLE IF NOT EXISTS knowledge_browse_revision (id INTEGER PRIMARY KEY, revision INTEGER NOT NULL)")
    _ = execute("INSERT OR IGNORE INTO knowledge_browse_revision(id, revision) VALUES (1, 0)")
    _ = execute("""
      CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(
        item_hash UNINDEXED,
        tokens,
        tokenize = 'unicode61'
      )
      """)
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vectors (
        vector_key TEXT PRIMARY KEY NOT NULL,
        item_hash TEXT NOT NULL,
        model_hash TEXT NOT NULL,
        source_revision_hash TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        encrypted_payload BLOB NOT NULL
      )
      """)
    _ = execute("CREATE INDEX IF NOT EXISTS knowledge_vector_lookup ON knowledge_vectors(item_hash, model_hash)")
    rebuildIndexIfNeeded()
  }

  private func rebuildIndexIfNeeded() {
    let itemCount = scalar("SELECT COUNT(*) FROM knowledge_items") ?? 0
    let indexCount = scalar("SELECT COUNT(*) FROM knowledge_fts") ?? 0
    let headerCount = scalar("SELECT COUNT(*) FROM knowledge_source_headers") ?? 0
    guard itemCount != indexCount || (itemCount > 0 && headerCount == 0),
          let items = try? all() else { return }
    _ = replaceAll(items)
  }

  private func searchTokens(_ value: String) -> [String] {
    let normalized = value.lowercased()
    var seen = Set<String>()
    var output: [String] = []
    func append(_ token: String) {
      let clean = String(token.prefix(64))
      guard !clean.isEmpty, seen.insert(clean).inserted, output.count < 512 else { return }
      output.append(clean)
    }
    let words = normalized.unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) && !Self.isCJK(scalar) ? Character(String(scalar)) : " "
    }
    for word in String(words).split(whereSeparator: \.isWhitespace) { append(String(word)) }
    var run: [Character] = []
    func flushRun() {
      guard !run.isEmpty else { return }
      if run.count == 1 { append(String(run[0])) }
      if run.count >= 2 {
        for index in 0..<(run.count - 1) { append(String(run[index...(index + 1)])) }
      }
      run.removeAll(keepingCapacity: true)
    }
    for scalar in normalized.unicodeScalars {
      if Self.isCJK(scalar) { run.append(Character(String(scalar))) } else { flushRun() }
    }
    flushRun()
    return output
  }

  private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    (0x3400...0x4DBF).contains(scalar.value) ||
      (0x4E00...0x9FFF).contains(scalar.value) ||
      (0xF900...0xFAFF).contains(scalar.value)
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

  private func sourceIdentity(_ item: AgentKnowledgeItem) -> String {
    item.source.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("local:\(item.id)")
  }

  private func sourceHeaderPurpose(_ sourceHash: String) -> String {
    "agent-knowledge-source:\(sourceHash)"
  }

  private func vectorPurpose(_ vectorKey: String) -> String { "agent-knowledge-vector:\(vectorKey)" }

  private func vectorCheckpoint(vectorKey: String) -> AgentKnowledgeVectorCheckpoint? {
    guard let statement = prepare(
      "SELECT encrypted_payload FROM knowledge_vectors WHERE vector_key = ?"
    ) else { return nil }
    defer { sqlite3_finalize(statement) }
    bind(vectorKey, at: 1, to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
          let encrypted = blob(statement, column: 0),
          let plaintext = try? vectorCipher.decrypt(encrypted, expectedPurpose: vectorPurpose(vectorKey)) else {
      return nil
    }
    return try? JSONDecoder.galaxySSI.decode(AgentKnowledgeVectorCheckpoint.self, from: plaintext)
  }

  private func decode(
    _ statement: OpaquePointer?,
    hashColumn: Int32,
    payloadColumn: Int32
  ) throws -> AgentKnowledgeItem {
    guard let hashText = sqlite3_column_text(statement, hashColumn),
          let encrypted = blob(statement, column: payloadColumn) else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    let itemHash = String(cString: hashText)
    guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: purpose(itemHash)),
          let item = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeItem.self, from: plaintext),
          keyedHash(item.id) == itemHash else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return item
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

  private func scalar(_ sql: String) -> Int64? {
    guard let statement = prepare(sql) else { return nil }
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : nil
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
