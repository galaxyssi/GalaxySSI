import CryptoKit
import Foundation
import SQLite3

enum AgentKnowledgeDatabaseError: Error, Equatable {
  case unavailable
  case corruptRecord
  case staleCursor
  case sourceDirectoryNotReady(processedGroups: Int64)
}

enum AgentKnowledgeVectorChangeOperation: String, Codable, Equatable {
  case ready
  case removal
}

struct AgentKnowledgeVectorChange: Codable, Equatable {
  var sequence: Int64
  var previousSequence: Int64
  var epoch: String
  var operation: AgentKnowledgeVectorChangeOperation
  var itemHash: String
  var sourceRevisionHash: String
  var chunkCount: Int
  var updatedAtMillis: Int64
}

struct AgentKnowledgeVectorChangePage: Equatable {
  var epoch: String
  var headSequence: Int64
  var events: [AgentKnowledgeVectorChange]
}

struct AgentKnowledgeVectorCatalogPage: Equatable {
  var checkpoints: [AgentKnowledgeVectorCheckpoint]
  var nextVectorKey: String?
}

struct AgentKnowledgeVectorReplayPage: Equatable {
  var event: AgentKnowledgeVectorChange
  var checkpoints: [AgentKnowledgeVectorCheckpoint]
  var nextChunkIndex: Int?
}

struct AgentKnowledgeVectorCountSnapshot: Equatable {
  var chunks: Int64
  var pending: Int64
  var complete: Bool
}

struct AgentKnowledgeVectorFeedStamp: Equatable {
  var epoch: String
  var head: Int64
  var sourceRevision: Int64
}

struct AgentKnowledgeNativePublicationPage: Equatable {
  var events: [AgentKnowledgeVectorChange]
  var nextItemHash: String?
}

struct AgentKnowledgeNativeRootSeed {
  var vector: [Float]?
  var pending: Bool
}

final class AgentKnowledgeDatabase {
  let nativeFiles: AgentKnowledgeNativeFiles
  private let fileURL: URL
  private let secrets: GalaxySSISecretStore
  private let cipher: GalaxySSIAttachmentAtRestCipher
  private let vectorCipher: GalaxySSIAttachmentAtRestCipher
  private let sourcePreviewCipher: GalaxySSIAttachmentAtRestCipher
  private let sourcePreviewNamespace: String
  private let payloadDirectory: URL
  private let primaryPayloads: AgentKnowledgePrimaryPartitions
  private let lock = NSRecursiveLock()
  private var database: OpaquePointer?

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    nativeFiles = AgentKnowledgeNativeFiles(databaseURL: fileURL, secrets: secrets)
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
    sourcePreviewCipher = GalaxySSIAttachmentAtRestCipher(
      secrets: secrets,
      keyAccount: "agent.knowledge.source-preview.aes256.v1"
    )
    sourcePreviewNamespace = SHA256.hash(data: Data(fileURL.standardizedFileURL.path.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    payloadDirectory = URL(fileURLWithPath: fileURL.path + ".payloads", isDirectory: true)
    primaryPayloads = AgentKnowledgePrimaryPartitions(catalogURL: fileURL, secrets: secrets)
    open()
  }

  deinit {
    nativeFiles.invalidate()
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
        items.append(try decode(statement, hashColumn: 0, payloadColumn: 1))
      }
      return items
    }
  }

  func items(ids: [String]) throws -> [AgentKnowledgeItem] {
    guard ids.count <= 256 else { throw AgentKnowledgeDatabaseError.unavailable }
    return try locked {
      guard let statement = prepare("SELECT item_hash, encrypted_payload FROM knowledge_items WHERE item_hash = ? LIMIT 1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      defer { sqlite3_finalize(statement) }
      var seen = Set<String>(), items: [AgentKnowledgeItem] = []
      for id in ids where seen.insert(id).inserted {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        bind(keyedHash(id), at: 1, to: statement)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { continue }
        guard status == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
        let item = try decode(statement, hashColumn: 0, payloadColumn: 1)
        guard item.id == id else { throw AgentKnowledgeDatabaseError.corruptRecord }
        items.append(item)
      }
      return items
    }
  }

  func searchCandidates(query: String, limit: Int = 256) throws -> [AgentKnowledgeItem] {
    let tokens = searchTokens(query).map(keyedHash)
    guard !tokens.isEmpty else { return [] }
    let primarySnapshotLease = try primaryPayloads.snapshotLease()
    defer { withExtendedLifetime(primarySnapshotLease) {} }
    var snapshot: OpaquePointer?
    guard sqlite3_open_v2(
      fileURL.path,
      &snapshot,
      SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK, let snapshot else {
      if let snapshot { sqlite3_close_v2(snapshot) }
      throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { sqlite3_close_v2(snapshot) }
    sqlite3_busy_timeout(snapshot, 5_000)
    guard sqlite3_exec(snapshot, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK,
          sqlite3_exec(snapshot, "PRAGMA cache_size = -2048", nil, nil, nil) == SQLITE_OK,
          sqlite3_exec(snapshot, "PRAGMA mmap_size = 0", nil, nil, nil) == SQLITE_OK,
          sqlite3_exec(snapshot, "BEGIN", nil, nil, nil) == SQLITE_OK else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { sqlite3_exec(snapshot, "ROLLBACK", nil, nil, nil) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
      snapshot,
      """
        SELECT k.item_hash, k.encrypted_payload
        FROM knowledge_fts f
        JOIN knowledge_items k ON k.item_hash = f.item_hash
        WHERE knowledge_fts MATCH ?
        ORDER BY bm25(knowledge_fts), k.updated_at DESC
        LIMIT ?
        """,
      -1,
      &statement,
      nil
    ) == SQLITE_OK, let statement else { throw AgentKnowledgeDatabaseError.unavailable }
    defer { sqlite3_finalize(statement) }
    bind(tokens.joined(separator: " OR "), at: 1, to: statement)
    sqlite3_bind_int(statement, 2, Int32(min(max(limit, 1), 256)))
    var snapshotItems: [AgentKnowledgeItem] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      snapshotItems.append(try decode(statement, hashColumn: 0, payloadColumn: 1))
    }
    return try locked {
      try snapshotItems.filter { candidate in
        let itemHash = keyedHash(candidate.id)
        guard let current = prepare(
          "SELECT item_hash, encrypted_payload FROM knowledge_items WHERE item_hash = ? LIMIT 1"
        ) else { throw AgentKnowledgeDatabaseError.unavailable }
        defer { sqlite3_finalize(current) }
        bind(itemHash, at: 1, to: current)
        guard sqlite3_step(current) == SQLITE_ROW else { return false }
        return try decode(current, hashColumn: 0, payloadColumn: 1) == candidate
      }
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
      guard let plaintext = try? AgentKnowledgeVectorStorage.encode(checkpoint),
            let encrypted = try? vectorCipher.encrypt(plaintext, purpose: vectorPurpose(vectorKey)),
            execute("BEGIN IMMEDIATE TRANSACTION"),
            let statement = prepare("""
              INSERT INTO knowledge_vectors(
                vector_key, item_hash, model_hash, source_revision_hash, updated_at, encrypted_payload
              ) VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(vector_key) DO UPDATE SET
                source_revision_hash = excluded.source_revision_hash,
                updated_at = excluded.updated_at,
                encrypted_payload = excluded.encrypted_payload
            """) else {
        _ = execute("ROLLBACK")
        return false
      }
      if checkpoint.sourceStartUTF16 != nil {
        guard let current = try? items(ids: [checkpoint.itemId]).first,
          checkpoint.validatedSourceRange(in: current) != nil else {
          sqlite3_finalize(statement)
          _ = execute("ROLLBACK")
          return false
        }
      }
      bind(vectorKey, at: 1, to: statement)
      bind(keyedHash(checkpoint.itemId), at: 2, to: statement)
      bind(keyedHash(checkpoint.provenance.modelSHA256), at: 3, to: statement)
      bind(keyedHash(checkpoint.sourceRevision), at: 4, to: statement)
      sqlite3_bind_int64(statement, 5, checkpoint.updatedAtMillis)
      encrypted.withUnsafeBytes { bytes in
        sqlite3_bind_blob(statement, 6, bytes.baseAddress, Int32(encrypted.count), Self.transient)
      }
      let stored = sqlite3_step(statement) == SQLITE_DONE
      sqlite3_finalize(statement)
      guard stored, storeVectorReplayOrdinal(checkpoint, vectorKey: vectorKey) else {
        _ = execute("ROLLBACK")
        return false
      }
      let checkpoints = (try? vectorCheckpoints(
        itemId: checkpoint.itemId,
        modelSHA256: checkpoint.provenance.modelSHA256
      )) ?? []
      let complete = checkpoints.count == checkpoint.chunkCount &&
        Set(checkpoints.map(\.chunkIndex)) == Set(0..<checkpoint.chunkCount) &&
        checkpoints.allSatisfy { $0.sourceRevision == checkpoint.sourceRevision }
      if complete, !publishVectorChange(
        operation: .ready,
        itemId: checkpoint.itemId,
        modelSHA256: checkpoint.provenance.modelSHA256,
        sourceRevision: checkpoint.sourceRevision,
        chunkCount: checkpoint.chunkCount,
        updatedAtMillis: checkpoint.updatedAtMillis
      ) {
        _ = execute("ROLLBACK")
        return false
      }
      if complete, !removeVectorQueueItem(
        itemHash: keyedHash(checkpoint.itemId),
        modelHash: keyedHash(checkpoint.provenance.modelSHA256)
      ) {
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
              let checkpoint = try? AgentKnowledgeVectorStorage.decode(plaintext) else {
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
      let existing = (try? vectorCheckpoints(itemId: itemId, modelSHA256: modelSHA256)) ?? []
      guard execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
      guard let statement = prepare(
        "DELETE FROM knowledge_vectors WHERE item_hash = ? AND model_hash = ?"
      ) else {
        _ = execute("ROLLBACK")
        return false
      }
      bind(keyedHash(itemId), at: 1, to: statement)
      bind(keyedHash(modelSHA256.lowercased()), at: 2, to: statement)
      let deleted = sqlite3_step(statement) == SQLITE_DONE
      sqlite3_finalize(statement)
      guard deleted else {
        _ = execute("ROLLBACK")
        return false
      }
      if !existing.isEmpty, !publishVectorChange(
        operation: .removal,
        itemId: itemId,
        modelSHA256: modelSHA256,
        sourceRevision: existing[0].sourceRevision,
        chunkCount: 0,
        updatedAtMillis: AgentMemoryClock.nowMillis()
      ) {
        _ = execute("ROLLBACK")
        return false
      }
      if !enqueueVectorItemIfRegistered(
        itemHash: keyedHash(itemId),
        modelHash: keyedHash(modelSHA256.lowercased())
      ) {
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

  func vectorChangePage(
    modelSHA256: String,
    epoch expectedEpoch: String? = nil,
    afterSequence: Int64 = 0,
    limit: Int = 128
  ) throws -> AgentKnowledgeVectorChangePage {
    try locked {
      let modelHash = keyedHash(modelSHA256.lowercased())
      let state = try ensureVectorFeedModel(modelHash: modelHash)
      if let expectedEpoch, expectedEpoch != state.epoch {
        throw AgentKnowledgeDatabaseError.staleCursor
      }
      guard afterSequence >= 0, afterSequence <= state.head,
            let statement = prepare("""
              SELECT sequence, previous_sequence, epoch, operation, item_hash,
                     source_revision_hash, chunk_count, updated_at
              FROM knowledge_vector_changes
              WHERE model_hash = ? AND sequence > ?
              ORDER BY sequence ASC LIMIT ?
              """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(modelHash, at: 1, to: statement)
      sqlite3_bind_int64(statement, 2, afterSequence)
      sqlite3_bind_int(statement, 3, Int32(min(max(limit, 1), 512)))
      var expectedPrevious = afterSequence
      var events: [AgentKnowledgeVectorChange] = []
      var status = sqlite3_step(statement)
      while status == SQLITE_ROW {
        let event = try decodeVectorChange(statement)
        guard event.epoch == state.epoch, event.previousSequence == expectedPrevious,
          event.sequence > expectedPrevious, event.sequence <= state.head else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        expectedPrevious = event.sequence
        events.append(event)
        status = sqlite3_step(statement)
      }
      guard status == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      return AgentKnowledgeVectorChangePage(epoch: state.epoch, headSequence: state.head, events: events)
    }
  }

  func vectorFeedStamp(modelSHA256: String) throws -> AgentKnowledgeVectorFeedStamp {
    try locked {
      let modelHash = keyedHash(modelSHA256.lowercased())
      _ = try ensureVectorFeedModel(modelHash: modelHash)
      guard execute("BEGIN DEFERRED TRANSACTION") else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { _ = execute("ROLLBACK") }
      return try readVectorFeedStamp(modelHash: modelHash)
    }
  }

  func nativePublicationPage(modelSHA256: String, afterItemHash: String? = nil,
    limit: Int = 64) throws -> AgentKnowledgeNativePublicationPage {
    try locked {
      if let afterItemHash, !isOpaqueHash(afterItemHash) { throw AgentKnowledgeDatabaseError.staleCursor }
      let size = min(max(limit, 1), 64)
      guard let statement = prepare("""
        SELECT c.sequence, c.previous_sequence, c.epoch, c.operation, c.item_hash,
          c.source_revision_hash, c.chunk_count, c.updated_at
        FROM knowledge_vector_publications p
        JOIN knowledge_vector_changes c ON c.sequence = p.sequence AND c.model_hash = p.model_hash
          AND c.item_hash = p.item_hash AND c.epoch = p.epoch AND c.source_revision_hash = p.source_revision_hash
          AND c.chunk_count = p.chunk_count AND c.operation = p.operation
        WHERE p.model_hash = ? AND p.operation = 'ready' AND p.item_hash > ?
          AND p.sequence = (SELECT latest.sequence FROM knowledge_vector_changes latest
            WHERE latest.model_hash = p.model_hash AND latest.item_hash = p.item_hash ORDER BY latest.sequence DESC LIMIT 1)
        ORDER BY p.item_hash ASC LIMIT ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(keyedHash(modelSHA256.lowercased()), at: 1, to: statement)
      bind(afterItemHash ?? "", at: 2, to: statement)
      sqlite3_bind_int(statement, 3, Int32(size))
      var events: [AgentKnowledgeVectorChange] = []
      var status = sqlite3_step(statement)
      while status == SQLITE_ROW {
        let event = try decodeVectorChange(statement)
        guard event.operation == .ready, event.itemHash > (events.last?.itemHash ?? afterItemHash ?? "") else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        events.append(event)
        status = sqlite3_step(statement)
      }
      guard status == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      return AgentKnowledgeNativePublicationPage(events: events, nextItemHash: events.count == size ? events.last?.itemHash : nil)
    }
  }

  // The seed scan also resumes after process death; it never scans the whole
  // catalog in one query or substitutes invented vectors for a real source.
  func nativeRootSeed(provenance: AgentKnowledgeVectorProvenance,
    stamp: AgentKnowledgeVectorFeedStamp) throws -> AgentKnowledgeNativeRootSeed {
    try locked {
      let modelHash = keyedHash(provenance.modelSHA256.lowercased())
      let contractHash = try vectorProvenanceHash(provenance)
      guard try vectorFeedStamp(modelSHA256: provenance.modelSHA256) == stamp else { throw AgentKnowledgeDatabaseError.staleCursor }
      guard let update = prepare("""
        INSERT INTO knowledge_vector_native_root_seek(model_hash, contract_hash, epoch, head, source_revision)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(model_hash) DO UPDATE SET contract_hash = excluded.contract_hash,
          epoch = excluded.epoch, head = excluded.head, source_revision = excluded.source_revision, after_item_hash = ''
        WHERE contract_hash != excluded.contract_hash OR epoch != excluded.epoch OR head != excluded.head
          OR source_revision != excluded.source_revision
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      bind(modelHash, at: 1, to: update)
      bind(contractHash, at: 2, to: update)
      bind(stamp.epoch, at: 3, to: update)
      sqlite3_bind_int64(update, 4, stamp.head)
      sqlite3_bind_int64(update, 5, stamp.sourceRevision)
      let updated = sqlite3_step(update) == SQLITE_DONE
      sqlite3_finalize(update)
      guard updated, let cursor = prepare("SELECT after_item_hash FROM knowledge_vector_native_root_seek WHERE model_hash = ?") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(modelHash, at: 1, to: cursor)
      guard sqlite3_step(cursor) == SQLITE_ROW, let text = sqlite3_column_text(cursor, 0) else {
        sqlite3_finalize(cursor)
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      let after = String(cString: text)
      sqlite3_finalize(cursor)
      let page = try nativePublicationPage(modelSHA256: provenance.modelSHA256, afterItemHash: after.isEmpty ? nil : after)
      for event in page.events {
        if let vector = try vectorReplayPage(event: event, provenance: provenance, limit: 1)?.checkpoints.first?.vector {
          guard try vectorFeedStamp(modelSHA256: provenance.modelSHA256) == stamp else { throw AgentKnowledgeDatabaseError.staleCursor }
          return AgentKnowledgeNativeRootSeed(vector: vector, pending: false)
        }
      }
      guard try vectorFeedStamp(modelSHA256: provenance.modelSHA256) == stamp,
        let advance = prepare("""
          UPDATE knowledge_vector_native_root_seek SET after_item_hash = ?
          WHERE model_hash = ? AND contract_hash = ? AND epoch = ? AND head = ? AND source_revision = ?
          """) else { throw AgentKnowledgeDatabaseError.staleCursor }
      defer { sqlite3_finalize(advance) }
      bind(page.nextItemHash ?? "", at: 1, to: advance)
      bind(modelHash, at: 2, to: advance)
      bind(contractHash, at: 3, to: advance)
      bind(stamp.epoch, at: 4, to: advance)
      sqlite3_bind_int64(advance, 5, stamp.head)
      sqlite3_bind_int64(advance, 6, stamp.sourceRevision)
      guard sqlite3_step(advance) == SQLITE_DONE, sqlite3_changes(database) == 1 else { throw AgentKnowledgeDatabaseError.unavailable }
      return AgentKnowledgeNativeRootSeed(vector: nil, pending: page.nextItemHash != nil)
    }
  }

  func validatedLexicalHits(_ hits: [AgentKnowledgeHit], stamp: AgentKnowledgeVectorFeedStamp,
    modelSHA256: String) throws -> [AgentKnowledgeHit] {
    guard hits.count <= 256 else { throw AgentKnowledgeNativeError.invalidRecord }
    return try locked {
      guard execute("BEGIN DEFERRED TRANSACTION") else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { _ = execute("ROLLBACK") }
      guard try readVectorFeedStamp(modelHash: keyedHash(modelSHA256.lowercased())) == stamp else {
        throw AgentKnowledgeDatabaseError.staleCursor
      }
      let current = Dictionary(uniqueKeysWithValues: try items(ids: hits.map(\.item.id)).map { ($0.id, $0) })
      return hits.filter { current[$0.item.id] == $0.item }
    }
  }

  // A native node is not an authority to release text. Re-resolve publication,
  // encrypted vector provenance and the current encrypted source in one snapshot.
  func resolveNativeMatches(_ matches: [AgentKnowledgeNativeMatch], provenance: AgentKnowledgeVectorProvenance,
    stamp: AgentKnowledgeVectorFeedStamp) throws -> [AgentKnowledgeHit] {
    guard matches.count <= 256 else { throw AgentKnowledgeNativeError.invalidRecord }
    let hits: [AgentKnowledgeHit] = try locked {
      guard execute("BEGIN DEFERRED TRANSACTION") else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { _ = execute("ROLLBACK") }
      let modelHash = keyedHash(provenance.modelSHA256.lowercased())
      guard try readVectorFeedStamp(modelHash: modelHash) == stamp else { throw AgentKnowledgeDatabaseError.staleCursor }
      guard let row = prepare("""
        SELECT i.item_hash, i.encrypted_payload, v.vector_key, v.encrypted_payload, p.chunk_count
        FROM knowledge_vector_publications p
        JOIN knowledge_vector_changes c ON c.sequence = p.sequence AND c.model_hash = p.model_hash
          AND c.item_hash = p.item_hash AND c.epoch = p.epoch AND c.source_revision_hash = p.source_revision_hash
          AND c.chunk_count = p.chunk_count AND c.operation = p.operation
        JOIN knowledge_items i ON i.item_hash = p.item_hash
        JOIN knowledge_vector_replay_rows r ON r.model_hash = p.model_hash AND r.item_hash = p.item_hash
          AND r.source_revision_hash = p.source_revision_hash
        JOIN knowledge_vectors v ON v.vector_key = r.vector_key
        WHERE p.model_hash = ? AND p.item_hash = ? AND p.source_revision_hash = ?
          AND p.epoch = ? AND p.sequence = ? AND p.operation = 'ready' AND r.chunk_index = ?
          AND p.sequence = (SELECT latest.sequence FROM knowledge_vector_changes latest
            WHERE latest.model_hash = p.model_hash AND latest.item_hash = p.item_hash ORDER BY latest.sequence DESC LIMIT 1) LIMIT 1
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(row) }
      var output: [AgentKnowledgeHit] = [], seen = Set<String>()
      for match in matches {
        guard isOpaqueHash(match.key), isOpaqueHash(match.revision), match.sequence > 0, match.ordinal >= 0,
          match.startUTF16 >= 0, match.startUTF16 < match.endUTF16,
          match.similarity.isFinite, (-1...1).contains(match.similarity) else { throw AgentKnowledgeNativeError.invalidRecord }
        if seen.contains(match.key) { continue }
        sqlite3_reset(row)
        sqlite3_clear_bindings(row)
        bind(modelHash, at: 1, to: row)
        bind(match.key, at: 2, to: row)
        bind(match.revision, at: 3, to: row)
        bind(stamp.epoch, at: 4, to: row)
        sqlite3_bind_int64(row, 5, match.sequence)
        sqlite3_bind_int64(row, 6, match.ordinal)
        let status = sqlite3_step(row)
        if status == SQLITE_DONE { continue }
        guard status == SQLITE_ROW, let keyText = sqlite3_column_text(row, 2), let encrypted = blob(row, column: 3) else {
          throw AgentKnowledgeDatabaseError.unavailable
        }
        let item = try decode(row, hashColumn: 0, payloadColumn: 1)
        let vectorKey = String(cString: keyText)
        let checkpoint = try AgentKnowledgeVectorStorage.decode(vectorCipher.decrypt(encrypted, expectedPurpose: vectorPurpose(vectorKey)))
        guard checkpoint.provenance == provenance, checkpoint.itemId == item.id,
          Int64(checkpoint.chunkCount) == sqlite3_column_int64(row, 4),
          keyedHash(checkpoint.id) == vectorKey, keyedHash(checkpoint.sourceRevision) == match.revision,
          checkpoint.chunkIndex == Int(match.ordinal), checkpoint.sourceStartUTF16 == match.startUTF16,
          checkpoint.sourceEndUTF16 == match.endUTF16,
          let range = checkpoint.validatedSourceRange(in: item) else { continue }
        seen.insert(match.key)
        output.append(AgentKnowledgeHit(item: item, score: Double(max(0, match.similarity)),
          excerpt: String(item.content[range].prefix(360)), matchedTerms: []))
      }
      return output
    }
    // A feed append or source/policy mutation racing native search invalidates
    // the entire old result batch, even if the graph's checkpoint had caught up.
    guard try vectorFeedStamp(modelSHA256: provenance.modelSHA256) == stamp else { throw AgentKnowledgeDatabaseError.staleCursor }
    return hits
  }

  // All publication, source and ordinal checks share one SQLite read snapshot.
  func vectorReplayPage(
    event: AgentKnowledgeVectorChange,
    provenance: AgentKnowledgeVectorProvenance,
    afterChunkIndex: Int = 0,
    limit: Int = 64
  ) throws -> AgentKnowledgeVectorReplayPage? {
    try locked {
      guard event.operation == .ready, event.sequence > 0, event.chunkCount > 0,
        afterChunkIndex >= 0, afterChunkIndex < event.chunkCount,
        isOpaqueHash(event.itemHash), isOpaqueHash(event.sourceRevisionHash) else {
        throw AgentKnowledgeDatabaseError.staleCursor
      }
      guard execute("BEGIN DEFERRED TRANSACTION") else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { _ = execute("ROLLBACK") }
      let page = try vectorChangePage(modelSHA256: provenance.modelSHA256,
        epoch: event.epoch, afterSequence: event.previousSequence, limit: 1)
      guard page.events.first == event else { return nil }
      let modelHash = keyedHash(provenance.modelSHA256)
      guard let latest = prepare("""
        SELECT sequence FROM knowledge_vector_changes
        WHERE model_hash = ? AND item_hash = ? ORDER BY sequence DESC LIMIT 1
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      bind(modelHash, at: 1, to: latest)
      bind(event.itemHash, at: 2, to: latest)
      let latestStatus = sqlite3_step(latest)
      let latestSequence = sqlite3_column_int64(latest, 0)
      sqlite3_finalize(latest)
      guard latestStatus == SQLITE_ROW || latestStatus == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      guard latestStatus == SQLITE_ROW, latestSequence == event.sequence else { return nil }
      guard try hasNativePublication(modelHash: modelHash, itemHash: event.itemHash,
        revisionHash: event.sourceRevisionHash, chunkCount: event.chunkCount) else { return nil }
      guard let source = prepare("SELECT item_hash, encrypted_payload FROM knowledge_items WHERE item_hash = ? LIMIT 1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(event.itemHash, at: 1, to: source)
      let sourceStatus = sqlite3_step(source)
      let item: AgentKnowledgeItem?
      do { item = sourceStatus == SQLITE_ROW ? try decode(source, hashColumn: 0, payloadColumn: 1) : nil }
      catch { sqlite3_finalize(source); throw error }
      sqlite3_finalize(source)
      guard sourceStatus == SQLITE_ROW || sourceStatus == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      guard let item, keyedHash(item.id) == event.itemHash,
        keyedHash(AgentKnowledgeVectorCheckpoint.sourceRevision(for: item)) == event.sourceRevisionHash else { return nil }
      guard let count = prepare("""
        SELECT COUNT(*) FROM knowledge_vector_replay_rows
        WHERE model_hash = ? AND item_hash = ? AND source_revision_hash = ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      bind(modelHash, at: 1, to: count)
      bind(event.itemHash, at: 2, to: count)
      bind(event.sourceRevisionHash, at: 3, to: count)
      let countStatus = sqlite3_step(count)
      let available = sqlite3_column_int64(count, 0)
      sqlite3_finalize(count)
      guard countStatus == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
      guard available == Int64(event.chunkCount) else { return nil }
      guard let statement = prepare("""
        SELECT v.vector_key, v.encrypted_payload, r.chunk_index
        FROM knowledge_vector_replay_rows r JOIN knowledge_vectors v ON v.vector_key = r.vector_key
        WHERE r.model_hash = ? AND r.item_hash = ? AND r.source_revision_hash = ? AND r.chunk_index >= ?
        ORDER BY r.chunk_index ASC LIMIT ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(modelHash, at: 1, to: statement)
      bind(event.itemHash, at: 2, to: statement)
      bind(event.sourceRevisionHash, at: 3, to: statement)
      sqlite3_bind_int64(statement, 4, Int64(afterChunkIndex))
      let expected = min(min(max(limit, 1), 64), event.chunkCount - afterChunkIndex)
      sqlite3_bind_int(statement, 5, Int32(expected))
      var checkpoints: [AgentKnowledgeVectorCheckpoint] = []
      var status = sqlite3_step(statement)
      while status == SQLITE_ROW {
        guard let keyText = sqlite3_column_text(statement, 0), let encrypted = blob(statement, column: 1) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let key = String(cString: keyText)
        let plaintext = try vectorCipher.decrypt(encrypted, expectedPurpose: vectorPurpose(key))
        let checkpoint = try AgentKnowledgeVectorStorage.decode(plaintext)
        let ordinal = afterChunkIndex + checkpoints.count
        guard checkpoint.itemId == item.id, checkpoint.provenance == provenance,
          checkpoint.chunkCount == event.chunkCount, checkpoint.chunkIndex == ordinal,
          sqlite3_column_int64(statement, 2) == Int64(ordinal), keyedHash(checkpoint.id) == key,
          checkpoint.validatedSourceRange(in: item) != nil else { return nil }
        checkpoints.append(checkpoint)
        status = sqlite3_step(statement)
      }
      guard status == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      guard checkpoints.count == expected else { return nil }
      let next = afterChunkIndex + checkpoints.count
      return AgentKnowledgeVectorReplayPage(event: event, checkpoints: checkpoints,
        nextChunkIndex: next < event.chunkCount ? next : nil)
    }
  }

  func pendingVectorItems(modelSHA256: String, limit: Int = 32) throws -> [AgentKnowledgeItem] {
    try locked {
      let pageSize = min(max(limit, 1), 64)
      let modelHash = keyedHash(modelSHA256.lowercased())
      guard let migration = prepare("SELECT contract_hash FROM knowledge_vector_native_enrollment WHERE model_hash = ? LIMIT 1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(modelHash, at: 1, to: migration)
      let migrationStatus = sqlite3_step(migration)
      let nativeContract: String?
      if migrationStatus == SQLITE_ROW {
        guard let text = sqlite3_column_text(migration, 0) else {
          sqlite3_finalize(migration)
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        nativeContract = String(cString: text)
      } else { nativeContract = nil }
      sqlite3_finalize(migration)
      guard migrationStatus == SQLITE_ROW || migrationStatus == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      guard ensureVectorEnrollment(modelHash: modelHash) else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      if try vectorQueueIsEmpty(modelHash: modelHash),
         try vectorEnrollmentPending(modelSHA256: modelSHA256),
         !refillVectorEnrollment(modelHash: modelHash) {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      guard let statement = prepare("""
        SELECT q.item_hash, i.encrypted_payload
        FROM knowledge_vector_queue q
        JOIN knowledge_items i ON i.item_hash = q.item_hash
        WHERE q.model_hash = ? ORDER BY q.item_hash ASC LIMIT ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(modelHash, at: 1, to: statement)
      sqlite3_bind_int(statement, 2, 64)
      var pending: [AgentKnowledgeItem] = []
      var completedHashes: [String] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        let item = try decode(statement, hashColumn: 0, payloadColumn: 1)
        guard let hashText = sqlite3_column_text(statement, 0) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let itemHash = String(cString: hashText)
        let revision = AgentKnowledgeVectorCheckpoint.sourceRevision(for: item)
        let checkpoints = try vectorCheckpoints(itemId: item.id, modelSHA256: modelSHA256)
        let expectedCount = checkpoints.first?.chunkCount ?? 0
        let completeIndices = expectedCount > 0 && checkpoints.count == expectedCount &&
          Set(checkpoints.map(\.chunkIndex)) == Set(0..<expectedCount)
        var nativeReady = true
        if let nativeContract {
          let ordinalCount = try replayOrdinalCount(modelHash: modelHash, itemHash: itemHash, revisionHash: keyedHash(revision))
          nativeReady = try checkpoints.allSatisfy { checkpoint in
            guard checkpoint.validatedSourceRange(in: item) != nil else { return false }
            return try vectorProvenanceHash(checkpoint.provenance) == nativeContract
          }
          nativeReady = nativeReady && ordinalCount == Int64(expectedCount)
          if nativeReady {
            nativeReady = try hasNativePublication(modelHash: modelHash, itemHash: itemHash,
              revisionHash: keyedHash(revision), chunkCount: expectedCount)
          }
        }
        if !checkpoints.isEmpty && checkpoints.allSatisfy({ $0.sourceRevision == revision }) &&
           checkpoints.count == expectedCount && completeIndices && nativeReady {
          completedHashes.append(itemHash)
        } else {
          pending.append(item)
        }
      }
      for itemHash in completedHashes where !removeVectorQueueItem(itemHash: itemHash, modelHash: modelHash) {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      return Array(pending.prefix(pageSize))
    }
  }

  // Enroll legacy documents in bounded durable slices; the normal indexer performs
  // real tokenization/embedding and republishes complete, source-ranged vectors.
  func maintainNativeVectorEnrollment(provenance: AgentKnowledgeVectorProvenance, pageSize: Int = 64) throws -> Bool {
    try locked {
      guard (1...64).contains(pageSize), execute("BEGIN IMMEDIATE TRANSACTION") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      let modelHash = keyedHash(provenance.modelSHA256.lowercased())
      let contractHash = try vectorProvenanceHash(provenance)
      guard ensureVectorEnrollment(modelHash: modelHash) else { throw AgentKnowledgeDatabaseError.unavailable }
      guard let insert = prepare("""
        INSERT INTO knowledge_vector_native_enrollment(model_hash, contract_hash) VALUES (?, ?)
        ON CONFLICT(model_hash) DO UPDATE SET after_item_hash = '', complete = 0, contract_hash = excluded.contract_hash
        WHERE knowledge_vector_native_enrollment.contract_hash != excluded.contract_hash
        """) else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(modelHash, at: 1, to: insert)
      bind(contractHash, at: 2, to: insert)
      let inserted = sqlite3_step(insert) == SQLITE_DONE
      sqlite3_finalize(insert)
      guard inserted, let state = prepare("SELECT after_item_hash, complete FROM knowledge_vector_native_enrollment WHERE model_hash = ?") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(modelHash, at: 1, to: state)
      guard sqlite3_step(state) == SQLITE_ROW, let text = sqlite3_column_text(state, 0) else {
        sqlite3_finalize(state)
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      let cursor = String(cString: text), alreadyComplete = sqlite3_column_int(state, 1) != 0
      sqlite3_finalize(state)
      if alreadyComplete {
        guard execute("COMMIT") else { throw AgentKnowledgeDatabaseError.unavailable }
        committed = true
        return true
      }
      guard let source = prepare("SELECT item_hash FROM knowledge_items WHERE item_hash > ? ORDER BY item_hash ASC LIMIT ?") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(cursor, at: 1, to: source)
      sqlite3_bind_int(source, 2, Int32(pageSize))
      var hashes: [String] = []
      var status = sqlite3_step(source)
      while status == SQLITE_ROW {
        guard let hash = sqlite3_column_text(source, 0) else {
          sqlite3_finalize(source)
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        hashes.append(String(cString: hash))
        status = sqlite3_step(source)
      }
      sqlite3_finalize(source)
      guard status == SQLITE_DONE, let queue = prepare("INSERT OR IGNORE INTO knowledge_vector_queue(model_hash, item_hash) VALUES (?, ?)") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      for hash in hashes {
        sqlite3_reset(queue)
        sqlite3_clear_bindings(queue)
        bind(modelHash, at: 1, to: queue)
        bind(hash, at: 2, to: queue)
        guard sqlite3_step(queue) == SQLITE_DONE else {
          sqlite3_finalize(queue)
          throw AgentKnowledgeDatabaseError.unavailable
        }
      }
      sqlite3_finalize(queue)
      guard let update = prepare("UPDATE knowledge_vector_native_enrollment SET after_item_hash = ?, complete = ? WHERE model_hash = ?") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      let complete = hashes.count < pageSize
      bind(hashes.last ?? cursor, at: 1, to: update)
      sqlite3_bind_int(update, 2, complete ? 1 : 0)
      bind(modelHash, at: 3, to: update)
      let updated = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
      sqlite3_finalize(update)
      guard updated, execute("COMMIT") else { throw AgentKnowledgeDatabaseError.unavailable }
      committed = true
      return complete
    }
  }

  func vectorWorkPending(modelSHA256: String) throws -> Bool {
    try locked {
      let enrollment = try vectorEnrollmentPending(modelSHA256: modelSHA256)
      return try enrollment || !vectorQueueIsEmpty(modelHash: keyedHash(modelSHA256.lowercased()))
    }
  }

  func vectorEnrollmentPending(modelSHA256: String) throws -> Bool {
    try locked {
      let modelHash = keyedHash(modelSHA256.lowercased())
      guard ensureVectorEnrollment(modelHash: modelHash),
            let statement = prepare(
              "SELECT complete FROM knowledge_vector_enrollment WHERE model_hash = ? LIMIT 1"
            ) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(modelHash, at: 1, to: statement)
      guard sqlite3_step(statement) == SQLITE_ROW else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      return sqlite3_column_int(statement, 0) == 0
    }
  }

  func vectorCountSnapshot(modelSHA256: String) throws -> AgentKnowledgeVectorCountSnapshot {
    try locked {
      let modelHash = keyedHash(modelSHA256.lowercased())
      guard ensureVectorEnrollment(modelHash: modelHash),
            let statement = prepare(
              "SELECT chunks, pending, legacy FROM knowledge_vector_counts WHERE model_hash = ? LIMIT 1"
            ) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(modelHash, at: 1, to: statement)
      guard sqlite3_step(statement) == SQLITE_ROW else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      let chunks = sqlite3_column_int64(statement, 0)
      let pending = sqlite3_column_int64(statement, 1)
      let legacy = sqlite3_column_int(statement, 2)
      guard chunks >= 0, pending >= 0, (0...1).contains(legacy) else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      return AgentKnowledgeVectorCountSnapshot(
        chunks: chunks,
        pending: pending,
        complete: legacy == 0 && !countMaintenancePending()
      )
    }
  }

  @discardableResult
  func maintainVectorCounts(pageSize: Int = 64) throws -> Bool {
    try locked {
      guard (1...256).contains(pageSize), execute("BEGIN IMMEDIATE TRANSACTION") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      do {
        _ = try advanceVectorCountScan(kind: "vectors", pageSize: pageSize)
        _ = try advanceVectorCountScan(kind: "queue", pageSize: pageSize)
        let pending = countMaintenancePending()
        if !pending, !execute("UPDATE knowledge_vector_counts SET legacy = 0") {
          throw AgentKnowledgeDatabaseError.unavailable
        }
        guard execute("COMMIT") else { throw AgentKnowledgeDatabaseError.unavailable }
        return !pending
      } catch {
        _ = execute("ROLLBACK")
        throw error
      }
    }
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
              let checkpoint = try? AgentKnowledgeVectorStorage.decode(plaintext) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        checkpoints.append(checkpoint)
      }
      return checkpoints
    }
  }

  func vectorCatalogPage(modelSHA256: String, afterVectorKey: String? = nil, limit: Int = 256) throws -> AgentKnowledgeVectorCatalogPage {
    try locked {
      if let afterVectorKey, !isOpaqueHash(afterVectorKey) { throw AgentKnowledgeDatabaseError.staleCursor }
      let pageSize = min(max(limit, 1), 256)
      guard let statement = prepare("""
        SELECT vector_key, encrypted_payload FROM knowledge_vectors
        WHERE model_hash = ? AND vector_key > ?
        ORDER BY vector_key ASC LIMIT ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      bind(keyedHash(modelSHA256.lowercased()), at: 1, to: statement)
      bind(afterVectorKey ?? "", at: 2, to: statement)
      sqlite3_bind_int(statement, 3, Int32(pageSize))
      var checkpoints: [AgentKnowledgeVectorCheckpoint] = [], lastKey: String?
      var status = sqlite3_step(statement)
      while status == SQLITE_ROW {
        guard let text = sqlite3_column_text(statement, 0), let encrypted = blob(statement, column: 1) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let key = String(cString: text)
        guard isOpaqueHash(key), key > (lastKey ?? afterVectorKey ?? ""),
          let plaintext = try? vectorCipher.decrypt(encrypted, expectedPurpose: vectorPurpose(key)),
          let checkpoint = try? AgentKnowledgeVectorStorage.decode(plaintext) else { throw AgentKnowledgeDatabaseError.corruptRecord }
        checkpoints.append(checkpoint)
        lastKey = key
        status = sqlite3_step(statement)
      }
      guard status == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
      return AgentKnowledgeVectorCatalogPage(checkpoints: checkpoints,
        nextVectorKey: checkpoints.count == pageSize ? lastKey : nil)
    }
  }

  func sourcePage(cursor: AgentKnowledgeSourceCursor? = nil, limit: Int = 50) throws -> AgentKnowledgeSourcePage {
    try locked {
      let pageSize = min(max(limit, 1), 50)
      let directory = try sourceDirectoryState()
      guard directory.complete else {
        throw AgentKnowledgeDatabaseError.sourceDirectoryNotReady(processedGroups: directory.groups)
      }
      guard let revision = scalar("SELECT revision FROM knowledge_browse_revision WHERE id = 1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      if let cursor, cursor.revision != revision { throw AgentKnowledgeDatabaseError.staleCursor }
      let predicate = cursor == nil ? "" : "WHERE h.updated_at < ? OR (h.updated_at = ? AND h.source_hash > ?)"
      guard let statement = prepare("""
        SELECT h.source_hash, h.updated_at, h.encrypted_header,
          p.header_fingerprint, p.encrypted_preview
        FROM knowledge_source_headers h
        LEFT JOIN knowledge_source_previews p ON p.source_hash = h.source_hash
        \(predicate)
        ORDER BY h.updated_at DESC, h.source_hash ASC
        LIMIT ?
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      var bindIndex: Int32 = 1
      if let cursor {
        sqlite3_bind_int64(statement, bindIndex, cursor.updatedAtMillis)
        sqlite3_bind_int64(statement, bindIndex + 1, cursor.updatedAtMillis)
        bind(cursor.sourceHash, at: bindIndex + 2, to: statement)
        bindIndex += 3
      }
      sqlite3_bind_int(statement, bindIndex, Int32(pageSize + 1))
      var stored: [(String, Int64, Data, Data?, Data?)] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        guard let hashText = sqlite3_column_text(statement, 0),
              let encrypted = blob(statement, column: 2) else {
          sqlite3_finalize(statement)
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        stored.append((
          String(cString: hashText),
          sqlite3_column_int64(statement, 1),
          encrypted,
          blob(statement, column: 3),
          blob(statement, column: 4)
        ))
      }
      sqlite3_finalize(statement)
      let rows = try stored.map { row in
        (row.0, try decodeSourcePreview(
          sourceHash: row.0,
          updatedAtMillis: row.1,
          encryptedHeader: row.2,
          storedFingerprint: row.3,
          encryptedPreview: row.4
        ))
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
        total: Int(clamping: directory.groups),
        next: next,
        positions: shown.map {
          AgentKnowledgeSourceCursor(
            updatedAtMillis: $0.1.updatedAtMillis,
            sourceHash: $0.0,
            revision: revision
          )
        }
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

  func sourceSnapshotItems(_ group: AgentKnowledgeSourceGroup) throws -> [AgentKnowledgeItem] {
    var items: [AgentKnowledgeItem] = []
    try enumerateSourceSnapshotItems(group) { items.append($0) }
    guard AgentKnowledgeSourceRevision.digest(items) == group.sourceRevision else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return items.sorted { left, right in
      left.chunkIndex == right.chunkIndex ? left.id < right.id : left.chunkIndex < right.chunkIndex
    }
  }

  func enumerateSourceSnapshotItems(
    _ group: AgentKnowledgeSourceGroup,
    consume: (AgentKnowledgeItem) throws -> Void
  ) throws {
    guard !group.source.isBlank, group.chunkCount >= 0, !group.sourceRevision.isBlank else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    let primarySnapshotLease = try primaryPayloads.snapshotLease()
    defer { withExtendedLifetime(primarySnapshotLease) {} }
    var snapshot: OpaquePointer?
    guard sqlite3_open_v2(
      fileURL.path,
      &snapshot,
      SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK, let snapshot else {
      if let snapshot { sqlite3_close_v2(snapshot) }
      throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { sqlite3_close_v2(snapshot) }
    sqlite3_busy_timeout(snapshot, 5_000)
    guard sqlite3_exec(snapshot, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK,
          sqlite3_exec(snapshot, "PRAGMA cache_size = -2048", nil, nil, nil) == SQLITE_OK,
          sqlite3_exec(snapshot, "PRAGMA mmap_size = 0", nil, nil, nil) == SQLITE_OK,
          sqlite3_exec(snapshot, "BEGIN", nil, nil, nil) == SQLITE_OK else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { sqlite3_exec(snapshot, "ROLLBACK", nil, nil, nil) }

    let sourceHash = keyedHash(group.source)
    var header: OpaquePointer?
    guard sqlite3_prepare_v2(
      snapshot,
      "SELECT updated_at, encrypted_header FROM knowledge_source_headers WHERE source_hash = ? LIMIT 1",
      -1,
      &header,
      nil
    ) == SQLITE_OK, let header else { throw AgentKnowledgeDatabaseError.unavailable }
    bind(sourceHash, at: 1, to: header)
    guard sqlite3_step(header) == SQLITE_ROW,
          let encryptedHeader = blob(header, column: 1),
          let plaintext = try? cipher.decrypt(
            encryptedHeader,
            expectedPurpose: sourceHeaderPurpose(sourceHash)
          ),
          let current = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeSourceGroup.self, from: plaintext) else {
      sqlite3_finalize(header)
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    sqlite3_finalize(header)
    guard current.source == group.source,
          current.sourceRevision == group.sourceRevision,
          current.chunkCount == group.chunkCount else {
      throw AgentKnowledgeDatabaseError.staleCursor
    }

    var afterUpdatedAt = Int64.max
    var afterItemHash = ""
    var firstPage = true
    var emitted = 0
    while true {
      let predicate = firstPage ? "" : "AND (updated_at < ? OR (updated_at = ? AND item_hash > ?))"
      var page: OpaquePointer?
      guard sqlite3_prepare_v2(
        snapshot,
        """
        SELECT item_hash, updated_at, encrypted_payload FROM knowledge_items
        WHERE source_hash = ? \(predicate)
        ORDER BY updated_at DESC, item_hash ASC LIMIT 64
        """,
        -1,
        &page,
        nil
      ) == SQLITE_OK, let page else { throw AgentKnowledgeDatabaseError.unavailable }
      bind(sourceHash, at: 1, to: page)
      if !firstPage {
        sqlite3_bind_int64(page, 2, afterUpdatedAt)
        sqlite3_bind_int64(page, 3, afterUpdatedAt)
        bind(afterItemHash, at: 4, to: page)
      }
      var pageCount = 0
      while sqlite3_step(page) == SQLITE_ROW {
        guard let hashText = sqlite3_column_text(page, 0) else {
          sqlite3_finalize(page)
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        let itemHash = String(cString: hashText)
        let updatedAt = sqlite3_column_int64(page, 1)
        let item = try decode(page, hashColumn: 0, payloadColumn: 2)
        guard sourceIdentity(item) == group.source, item.updatedAtMillis == updatedAt else {
          sqlite3_finalize(page)
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        try consume(item)
        emitted += 1
        guard emitted <= group.chunkCount else {
          sqlite3_finalize(page)
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        afterUpdatedAt = updatedAt
        afterItemHash = itemHash
        pageCount += 1
      }
      sqlite3_finalize(page)
      if pageCount < 64 { break }
      firstPage = false
    }
    guard emitted == group.chunkCount else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
  }

  func sourceBrowseRevision() throws -> Int64 {
    try locked {
      guard let revision = scalar("SELECT revision FROM knowledge_browse_revision WHERE id = 1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      return revision
    }
  }

  func knowledgeStats() throws -> AgentKnowledgeStats {
    try locked {
      guard let statement = prepare("""
        SELECT i.items, d.groups, i.complete,
          COALESCE((SELECT updated_at FROM knowledge_items ORDER BY updated_at DESC, item_hash ASC LIMIT 1), 0)
        FROM knowledge_item_count_state i
        JOIN knowledge_source_directory_state d ON d.id = i.id
        WHERE i.id = 1 LIMIT 1
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.corruptRecord }
      let items = sqlite3_column_int64(statement, 0)
      let sources = sqlite3_column_int64(statement, 1)
      let itemComplete = sqlite3_column_int(statement, 2)
      let updatedAt = sqlite3_column_int64(statement, 3)
      let directory = try sourceDirectoryState()
      guard items >= 0, sources >= 0, (0...1).contains(itemComplete), updatedAt >= 0 else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      return AgentKnowledgeStats(
        itemCount: Int(clamping: items),
        sourceCount: Int(clamping: sources),
        lastUpdatedAtMillis: updatedAt,
        countsComplete: itemComplete == 1 && directory.complete
      )
    }
  }

  struct PrimaryMigrationPage: Equatable {
    var visited: Int
    var moved: Int
    var complete: Bool
  }

  func maintainPrimaryPayloads(pageSize: Int = 8, checkActive: () throws -> Void = {}) throws -> PrimaryMigrationPage {
    try locked {
      try checkActive()
      try primaryPayloads.checkSharedAccess()
      guard (1...32).contains(pageSize), let database, execute("BEGIN IMMEDIATE TRANSACTION") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      var committed = false
      defer { if !committed { _ = execute("ROLLBACK") } }
      guard let state = prepare("SELECT after_item_hash,complete FROM knowledge_primary_migration WHERE id=1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      guard sqlite3_step(state) == SQLITE_ROW, let cursorText = sqlite3_column_text(state, 0) else {
        sqlite3_finalize(state)
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      let cursor = String(cString: cursorText), complete = sqlite3_column_int(state, 1)
      sqlite3_finalize(state)
      guard (cursor.isEmpty || cursor.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil),
            (0...1).contains(complete) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      if complete == 1 {
        guard execute("COMMIT") else { throw AgentKnowledgeDatabaseError.unavailable }
        committed = true
        return PrimaryMigrationPage(visited: 0, moved: 0, complete: true)
      }
      guard let page = prepare("SELECT item_hash,encrypted_payload FROM knowledge_items WHERE item_hash>? ORDER BY item_hash LIMIT ?") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(cursor, at: 1, to: page)
      sqlite3_bind_int(page, 2, Int32(pageSize + 1))
      var rows: [(String, Data)] = []
      while true {
        let step = sqlite3_step(page)
        if step == SQLITE_DONE { break }
        guard step == SQLITE_ROW, let hash = sqlite3_column_text(page, 0), let encrypted = blob(page, column: 1) else {
          sqlite3_finalize(page)
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        rows.append((String(cString: hash), encrypted))
      }
      sqlite3_finalize(page)
      var moved = 0
      for (hash, encrypted) in rows.prefix(pageSize) {
        try Task.checkCancellation()
        try checkActive()
        guard let present = prepare("SELECT 1 FROM knowledge_primary_refs WHERE item_hash=?") else {
          throw AgentKnowledgeDatabaseError.unavailable
        }
        bind(hash, at: 1, to: present)
        let found = sqlite3_step(present)
        sqlite3_finalize(present)
        if found == SQLITE_ROW { continue }
        guard found == SQLITE_DONE,
              let plain = readExternalPayload(itemHash: hash, database: database) ?? (try? cipher.decrypt(encrypted, expectedPurpose: purpose(hash))),
              let item = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeItem.self, from: plain), keyedHash(item.id) == hash else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        try primaryPayloads.append(plain, itemHash: hash, catalog: database, checkActive: checkActive)
        guard try primaryPayloads.read(itemHash: hash, catalog: database, checkActive: checkActive) == plain,
              let update = prepare("UPDATE knowledge_items SET encrypted_payload=x'00' WHERE item_hash=?") else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        bind(hash, at: 1, to: update)
        let updated = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
        sqlite3_finalize(update)
        guard updated else { throw AgentKnowledgeDatabaseError.unavailable }
        moved += 1
      }
      let visited = min(rows.count, pageSize), finished = rows.count <= pageSize
      guard let stateUpdate = prepare("UPDATE knowledge_primary_migration SET after_item_hash=?,complete=? WHERE id=1") else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(visited > 0 ? rows[visited - 1].0 : cursor, at: 1, to: stateUpdate)
      sqlite3_bind_int(stateUpdate, 2, finished ? 1 : 0)
      let saved = sqlite3_step(stateUpdate) == SQLITE_DONE && sqlite3_changes(database) == 1
      sqlite3_finalize(stateUpdate)
      try checkActive()
      try Task.checkCancellation()
      guard saved, execute("COMMIT") else { throw AgentKnowledgeDatabaseError.unavailable }
      committed = true
      return PrimaryMigrationPage(visited: visited, moved: moved, complete: finished)
    }
  }

  func reclaimPrimaryPartitions(pageSize: Int = 8, checkActive: () throws -> Void = {}) throws -> AgentKnowledgePrimaryPartitions.ReclaimPage {
    try locked {
      guard let database else { throw AgentKnowledgeDatabaseError.unavailable }
      return try primaryPayloads.reclaim(catalog: database, pageSize: pageSize, checkActive: checkActive)
    }
  }

  func reclaimPrimaryLegacyCopies(pageSize: Int = 8, checkActive: () throws -> Void = {}) throws -> AgentKnowledgePrimaryPartitions.LegacyReclaimPage {
    try locked {
      guard let database else { throw AgentKnowledgeDatabaseError.unavailable }
      return try primaryPayloads.reclaimLegacyCopies(catalog: database, pageSize: pageSize, checkActive: checkActive)
    }
  }

  // One system-granted slice; true means durable work remains, including a busy snapshot lease.
  func maintainPrimaryStorageSlice(maximumPages: Int = 8, checkActive: () throws -> Void = {}) throws -> Bool {
    guard (1...32).contains(maximumPages) else { throw AgentKnowledgeDatabaseError.corruptRecord }
    for _ in 0..<maximumPages {
      try Task.checkCancellation()
      try checkActive()
      if try maintainPrimaryPayloads(pageSize: 8, checkActive: checkActive).complete == false { continue }
      try checkActive()
      let legacy = try reclaimPrimaryLegacyCopies(pageSize: 8, checkActive: checkActive)
      if legacy.deferred { return true }
      if !legacy.complete { continue }
      try checkActive()
      let primary = try reclaimPrimaryPartitions(pageSize: 8, checkActive: checkActive)
      if primary.deferred { return true }
      if !primary.complete { continue }
      try checkActive()
      let files = try reclaimExternalPayloadFiles(pageSize: 16, checkActive: checkActive)
      if files.deferred { return true }
      if files.complete { return false }
    }
    return true
  }

  @discardableResult
  func maintainExternalPayloads(pageSize: Int = 4) throws -> Bool {
    try locked {
      try primaryPayloads.checkSharedAccess()
      let limit = min(max(pageSize, 1), 32)
      guard let state = prepare("""
        SELECT after_item_hash, all_rows, complete
        FROM knowledge_external_payload_migration WHERE id = 1 LIMIT 1
        """) else { throw AgentKnowledgeDatabaseError.unavailable }
      guard sqlite3_step(state) == SQLITE_ROW,
            let cursorText = sqlite3_column_text(state, 0) else {
        sqlite3_finalize(state)
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      var cursor = String(cString: cursorText)
      var allRows = sqlite3_column_int(state, 1) == 1
      let complete = sqlite3_column_int(state, 2) == 1
      sqlite3_finalize(state)
      let shouldExternalizeAll = (scalar("SELECT items FROM knowledge_item_count_state WHERE id = 1") ?? 0) >= 16_384
      if shouldExternalizeAll, !allRows {
        cursor = ""
        allRows = true
      } else if complete {
        return true
      }
      guard execute("BEGIN IMMEDIATE TRANSACTION") else { throw AgentKnowledgeDatabaseError.unavailable }
      guard let page = prepare("""
        SELECT item_hash, encrypted_payload FROM knowledge_items
        WHERE item_hash > ? AND NOT EXISTS(SELECT 1 FROM knowledge_primary_refs p WHERE p.item_hash=knowledge_items.item_hash)
        ORDER BY item_hash ASC LIMIT ?
        """) else {
        _ = execute("ROLLBACK")
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(cursor, at: 1, to: page)
      sqlite3_bind_int(page, 2, Int32(limit + 1))
      var rows: [(String, Data)] = []
      while sqlite3_step(page) == SQLITE_ROW {
        guard let hashText = sqlite3_column_text(page, 0), let payload = blob(page, column: 1) else {
          sqlite3_finalize(page)
          _ = execute("ROLLBACK")
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        rows.append((String(cString: hashText), payload))
      }
      sqlite3_finalize(page)
      for (itemHash, encrypted) in rows.prefix(limit) {
        if readExternalPayload(itemHash: itemHash, database: database) != nil { continue }
        guard let plaintext = try? cipher.decrypt(encrypted, expectedPurpose: purpose(itemHash)) else {
          _ = execute("ROLLBACK")
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        if allRows || plaintext.count >= 8 * 1_024 {
          guard insertExternalPayload(plaintext, itemHash: itemHash),
                let update = prepare("UPDATE knowledge_items SET encrypted_payload = x'00' WHERE item_hash = ?") else {
            _ = execute("ROLLBACK")
            throw AgentKnowledgeDatabaseError.unavailable
          }
          bind(itemHash, at: 1, to: update)
          let updated = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
          sqlite3_finalize(update)
          guard updated else {
            _ = execute("ROLLBACK")
            throw AgentKnowledgeDatabaseError.unavailable
          }
        }
      }
      let visited = min(rows.count, limit)
      let next = visited > 0 ? rows[visited - 1].0 : cursor
      let finished = rows.count <= limit
      guard let updateState = prepare("""
        UPDATE knowledge_external_payload_migration
        SET after_item_hash = ?, all_rows = ?, complete = ? WHERE id = 1
        """) else {
        _ = execute("ROLLBACK")
        throw AgentKnowledgeDatabaseError.unavailable
      }
      bind(next, at: 1, to: updateState)
      sqlite3_bind_int(updateState, 2, allRows ? 1 : 0)
      sqlite3_bind_int(updateState, 3, finished ? 1 : 0)
      let stateUpdated = sqlite3_step(updateState) == SQLITE_DONE && sqlite3_changes(database) == 1
      sqlite3_finalize(updateState)
      guard stateUpdated, execute("COMMIT") else {
        _ = execute("ROLLBACK")
        throw AgentKnowledgeDatabaseError.unavailable
      }
      return finished
    }
  }

  struct ExternalPayloadReclamation: Equatable {
    var removedFiles: Int
    var removedBytes: Int64
    var complete: Bool
    var deferred: Bool = false
  }

  @discardableResult
  func reclaimExternalPayloadFiles(
    pageSize: Int = 32,
    minimumAge: TimeInterval = 3_600,
    checkActive: () throws -> Void = {}
  ) throws -> ExternalPayloadReclamation {
    try locked {
      guard let database else { throw AgentKnowledgeDatabaseError.unavailable }
      return try primaryPayloads.withExclusiveAccess(catalog: database) {
        try reclaimExternalPayloadFilesExclusively(pageSize: pageSize, minimumAge: minimumAge, checkActive: checkActive)
      } ?? ExternalPayloadReclamation(removedFiles: 0, removedBytes: 0, complete: false, deferred: true)
    }
  }

  private func reclaimExternalPayloadFilesExclusively(
    pageSize: Int,
    minimumAge: TimeInterval,
    checkActive: () throws -> Void
  ) throws -> ExternalPayloadReclamation {
    do {
      try Task.checkCancellation()
      try checkActive()
      let limit = min(max(pageSize, 1), 128)
      guard try FileManager.default.attributesOfItem(atPath: payloadDirectory.path)[.type] as? FileAttributeType == .typeDirectory else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      guard let state = prepare(
        "SELECT after_file_name FROM knowledge_external_payload_reclamation WHERE id = 1 LIMIT 1"
      ), sqlite3_step(state) == SQLITE_ROW, let cursorText = sqlite3_column_text(state, 0) else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      let cursor = String(cString: cursorText)
      sqlite3_finalize(state)
      let names = try FileManager.default.contentsOfDirectory(
        at: payloadDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )
        .filter { $0.lastPathComponent > cursor && $0.pathExtension == "saenc" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .prefix(limit + 1)
      let page = Array(names.prefix(limit))
      try checkActive()
      var removedFiles = 0
      var removedBytes: Int64 = 0
      let cutoff = Date().addingTimeInterval(-max(0, minimumAge))
      for url in page {
        try Task.checkCancellation()
        try checkActive()
        let fileName = url.lastPathComponent
        guard fileName.range(of: #"^[a-f0-9]{64}-[a-f0-9]{16}\.saenc$"#, options: .regularExpression) != nil,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink == false,
              (values.contentModificationDate ?? .distantFuture) <= cutoff,
              externalPayloadReferenceCount(fileName: fileName) == 0 else { continue }
        do {
          try FileManager.default.removeItem(at: url)
          removedFiles += 1
          removedBytes += Int64(values.fileSize ?? 0)
        } catch {
          if (error as NSError).domain == NSCocoaErrorDomain,
             (error as NSError).code == NSFileNoSuchFileError {
            continue
          }
          throw error
        }
      }
      let finished = names.count <= limit
      let next = finished ? "" : (page.last?.lastPathComponent ?? cursor)
      try checkActive()
      guard let update = prepare(
        "UPDATE knowledge_external_payload_reclamation SET after_file_name = ? WHERE id = 1"
      ) else { throw AgentKnowledgeDatabaseError.unavailable }
      bind(next, at: 1, to: update)
      let updated = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
      sqlite3_finalize(update)
      guard updated else { throw AgentKnowledgeDatabaseError.unavailable }
      return ExternalPayloadReclamation(
        removedFiles: removedFiles,
        removedBytes: removedBytes,
        complete: finished
      )
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
      guard execute("UPDATE knowledge_item_count_state SET items = 0, complete = 1 WHERE id = 1") else {
        _ = execute("ROLLBACK")
        return false
      }
      guard execute("""
        UPDATE knowledge_external_payload_migration
        SET after_item_hash = '', all_rows = 0, complete = 0 WHERE id = 1
        """) else {
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
      let removals = orphanedVectorDocuments()
      guard execute("DELETE FROM knowledge_vectors WHERE item_hash NOT IN (SELECT item_hash FROM knowledge_items)") else {
        _ = execute("ROLLBACK")
        return false
      }
      for checkpoint in removals where !publishVectorChange(
        operation: .removal,
        itemId: checkpoint.itemId,
        modelSHA256: checkpoint.provenance.modelSHA256,
        sourceRevision: checkpoint.sourceRevision,
        chunkCount: 0,
        updatedAtMillis: AgentMemoryClock.nowMillis()
      ) {
        _ = execute("ROLLBACK")
        return false
      }
      guard execute("UPDATE knowledge_metadata SET value = 2 WHERE key = 'source_header_schema'"),
            execute("UPDATE knowledge_source_directory_state SET complete = 1 WHERE id = 1"),
            execute("DELETE FROM knowledge_vector_queue"),
            execute("UPDATE knowledge_vector_enrollment SET after_item_hash = '', complete = 0"),
            execute("UPDATE knowledge_browse_revision SET revision = revision + 1 WHERE id = 1"),
            execute("COMMIT") else {
        _ = execute("ROLLBACK")
        return false
      }
      return true
    }
  }

  private func insert(_ item: AgentKnowledgeItem) -> Bool {
    let itemHash = keyedHash(item.id)
    guard let plaintext = try? JSONEncoder.galaxySSI.encode(item) else { return false }
    let encrypted = Data([0])
    guard let statement = prepare("""
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
    guard let database else { return false }
    do { try primaryPayloads.append(plaintext, itemHash: itemHash, catalog: database) }
    catch { return false }
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
      if item.id.isBlank { return false }
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
    guard sqlite3_step(statement) == SQLITE_DONE else { return false }
    return insertSourcePreview(
      group,
      sourceHash: sourceHash,
      updatedAtMillis: group.updatedAtMillis,
      encryptedHeader: encrypted
    )
  }

  private func decodeSourcePreview(
    sourceHash: String,
    updatedAtMillis: Int64,
    encryptedHeader: Data,
    storedFingerprint: Data?,
    encryptedPreview: Data?
  ) throws -> AgentKnowledgeSourceGroup {
    let fingerprint = sourceHeaderFingerprint(
      sourceHash: sourceHash,
      updatedAtMillis: updatedAtMillis,
      encryptedHeader: encryptedHeader
    )
    if storedFingerprint != nil || encryptedPreview != nil {
      guard storedFingerprint == fingerprint, let encryptedPreview,
            let plaintext = try? sourcePreviewCipher.decrypt(
              encryptedPreview,
              expectedPurpose: sourcePreviewPurpose(sourceHash: sourceHash, fingerprint: fingerprint)
            ),
            let group = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeSourceGroup.self, from: plaintext),
            group.updatedAtMillis == updatedAtMillis,
            keyedHash(group.source) == sourceHash else {
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      return group
    }
    guard let plaintext = try? cipher.decrypt(
            encryptedHeader,
            expectedPurpose: sourceHeaderPurpose(sourceHash)
          ),
          let group = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeSourceGroup.self, from: plaintext),
          group.updatedAtMillis == updatedAtMillis,
          keyedHash(group.source) == sourceHash,
          insertSourcePreview(
            group,
            sourceHash: sourceHash,
            updatedAtMillis: updatedAtMillis,
            encryptedHeader: encryptedHeader
          ) else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return group
  }

  private func insertSourcePreview(
    _ group: AgentKnowledgeSourceGroup,
    sourceHash: String,
    updatedAtMillis: Int64,
    encryptedHeader: Data
  ) -> Bool {
    guard group.updatedAtMillis == updatedAtMillis, keyedHash(group.source) == sourceHash else { return false }
    let fingerprint = sourceHeaderFingerprint(
      sourceHash: sourceHash,
      updatedAtMillis: updatedAtMillis,
      encryptedHeader: encryptedHeader
    )
    guard let plaintext = try? JSONEncoder.galaxySSI.encode(group),
          let encrypted = try? sourcePreviewCipher.encrypt(
            plaintext,
            purpose: sourcePreviewPurpose(sourceHash: sourceHash, fingerprint: fingerprint)
          ),
          let statement = prepare("""
            INSERT INTO knowledge_source_previews(source_hash, header_fingerprint, encrypted_preview)
            VALUES (?, ?, ?)
            ON CONFLICT(source_hash) DO UPDATE SET
              header_fingerprint = excluded.header_fingerprint,
              encrypted_preview = excluded.encrypted_preview
            """) else { return false }
    defer { sqlite3_finalize(statement) }
    bind(sourceHash, at: 1, to: statement)
    fingerprint.withUnsafeBytes { bytes in
      sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(fingerprint.count), Self.transient)
    }
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
    _ = execute("CREATE INDEX IF NOT EXISTS knowledge_item_recent ON knowledge_items(updated_at DESC, item_hash ASC)")
    setupExternalPayloads()
    guard let database else { return }
    do { try primaryPayloads.setup(catalog: database) }
    catch { sqlite3_close_v2(database); self.database = nil; return }
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
    _ = execute("CREATE TABLE IF NOT EXISTS knowledge_metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
    _ = execute("INSERT OR IGNORE INTO knowledge_metadata(key, value) VALUES ('source_header_schema', 0)")
    setupSourceDirectoryState()
    setupSourcePreviews()
    setupKnowledgeItemCounts()
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
    _ = execute("CREATE INDEX IF NOT EXISTS knowledge_vector_model_key ON knowledge_vectors(model_hash, vector_key)")
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_replay_rows (
        vector_key TEXT PRIMARY KEY NOT NULL,
        model_hash TEXT NOT NULL,
        item_hash TEXT NOT NULL,
        source_revision_hash TEXT NOT NULL,
        chunk_index INTEGER NOT NULL CHECK(chunk_index >= 0),
        UNIQUE(model_hash, item_hash, source_revision_hash, chunk_index)
      )
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_vector_replay_delete AFTER DELETE ON knowledge_vectors
      BEGIN DELETE FROM knowledge_vector_replay_rows WHERE vector_key = OLD.vector_key; END
      """)
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_feed_models (
        model_hash TEXT PRIMARY KEY NOT NULL,
        epoch TEXT NOT NULL,
        head_sequence INTEGER NOT NULL DEFAULT 0
      )
      """)
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_changes (
        sequence INTEGER PRIMARY KEY AUTOINCREMENT,
        model_hash TEXT NOT NULL,
        epoch TEXT NOT NULL,
        previous_sequence INTEGER NOT NULL,
        operation TEXT NOT NULL,
        item_hash TEXT NOT NULL,
        source_revision_hash TEXT NOT NULL,
        chunk_count INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
      """)
    _ = execute("CREATE INDEX IF NOT EXISTS knowledge_vector_change_replay ON knowledge_vector_changes(model_hash, sequence)")
    _ = execute("CREATE INDEX IF NOT EXISTS knowledge_vector_change_document ON knowledge_vector_changes(model_hash, item_hash, sequence)")
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_native_enrollment (
        model_hash TEXT PRIMARY KEY NOT NULL,
        contract_hash TEXT NOT NULL,
        after_item_hash TEXT NOT NULL DEFAULT '',
        complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0, 1))
      )
      """)
    _ = setupNativePublications()
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_enrollment (
        model_hash TEXT PRIMARY KEY NOT NULL,
        after_item_hash TEXT NOT NULL DEFAULT '',
        complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0, 1))
      )
      """)
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_queue (
        model_hash TEXT NOT NULL,
        item_hash TEXT NOT NULL,
        PRIMARY KEY(model_hash, item_hash)
      )
      """)
    _ = execute("INSERT OR IGNORE INTO knowledge_vector_enrollment(model_hash, complete) SELECT DISTINCT model_hash, 1 FROM knowledge_vectors")
    setupVectorCounts()
    rebuildIndexIfNeeded()
    _ = try? maintainExternalPayloads(pageSize: 4)
    _ = try? reclaimExternalPayloadFiles(pageSize: 16)
  }

  private func setupSourceDirectoryState() {
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_source_directory_state (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        complete INTEGER NOT NULL CHECK(complete IN (0, 1)),
        groups INTEGER NOT NULL DEFAULT 0 CHECK(typeof(groups) = 'integer' AND groups >= 0)
      )
      """)
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_source_directory_state(id, complete, groups)
      SELECT 1,
        CASE WHEN (SELECT value FROM knowledge_metadata WHERE key = 'source_header_schema') >= 2
          OR NOT EXISTS(SELECT 1 FROM knowledge_items LIMIT 1) THEN 1 ELSE 0 END,
        (SELECT COUNT(*) FROM knowledge_source_headers)
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_source_directory_insert
      AFTER INSERT ON knowledge_source_headers
      BEGIN
        UPDATE knowledge_source_directory_state SET groups = groups + 1 WHERE id = 1;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Source directory state is missing') END;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_source_directory_delete
      AFTER DELETE ON knowledge_source_headers
      BEGIN
        UPDATE knowledge_source_directory_state SET groups = groups - 1 WHERE id = 1;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Source directory state is missing') END;
      END
      """)
  }

  private func setupExternalPayloads() {
    try? FileManager.default.createDirectory(
      at: payloadDirectory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_external_payloads (
        item_hash TEXT PRIMARY KEY NOT NULL,
        file_name TEXT NOT NULL UNIQUE,
        plaintext_bytes INTEGER NOT NULL CHECK(plaintext_bytes > 0),
        plaintext_sha256 TEXT NOT NULL CHECK(length(plaintext_sha256) = 64)
      )
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_external_payload_delete
      AFTER DELETE ON knowledge_items
      BEGIN
        DELETE FROM knowledge_external_payloads WHERE item_hash = OLD.item_hash;
      END
      """)
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_external_payload_migration (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        after_item_hash TEXT NOT NULL DEFAULT '',
        all_rows INTEGER NOT NULL DEFAULT 0 CHECK(all_rows IN (0, 1)),
        complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0, 1))
      )
      """)
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_external_payload_migration(id) VALUES (1)
      """)
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_external_payload_reclamation (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        after_file_name TEXT NOT NULL DEFAULT ''
      )
      """)
    _ = execute("INSERT OR IGNORE INTO knowledge_external_payload_reclamation(id) VALUES (1)")
  }

  private func sourceDirectoryState() throws -> (complete: Bool, groups: Int64) {
    guard let statement = prepare(
      "SELECT complete, groups FROM knowledge_source_directory_state WHERE id = 1 LIMIT 1"
    ) else { throw AgentKnowledgeDatabaseError.unavailable }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    let complete = sqlite3_column_int(statement, 0)
    let groups = sqlite3_column_int64(statement, 1)
    guard (0...1).contains(complete), groups >= 0 else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return (complete == 1, groups)
  }

  private func setupSourcePreviews() {
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_source_previews (
        source_hash TEXT PRIMARY KEY NOT NULL,
        header_fingerprint BLOB NOT NULL CHECK(length(header_fingerprint) = 32),
        encrypted_preview BLOB NOT NULL
      )
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_source_preview_header_update
      AFTER UPDATE OF source_hash, updated_at, encrypted_header ON knowledge_source_headers
      BEGIN
        DELETE FROM knowledge_source_previews WHERE source_hash = OLD.source_hash;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_source_preview_header_delete
      AFTER DELETE ON knowledge_source_headers
      BEGIN
        DELETE FROM knowledge_source_previews WHERE source_hash = OLD.source_hash;
      END
      """)
  }

  private func setupKnowledgeItemCounts() {
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_item_count_state (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        items INTEGER NOT NULL DEFAULT 0 CHECK(typeof(items) = 'integer' AND items >= 0),
        complete INTEGER NOT NULL CHECK(complete IN (0, 1))
      )
      """)
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_item_count_state(id, items, complete)
      SELECT 1, 0, CASE WHEN EXISTS(SELECT 1 FROM knowledge_items LIMIT 1) THEN 0 ELSE 1 END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_item_count_insert
      AFTER INSERT ON knowledge_items
      WHEN (SELECT complete FROM knowledge_item_count_state WHERE id = 1) = 1
      BEGIN
        UPDATE knowledge_item_count_state SET items = items + 1 WHERE id = 1;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Knowledge item count state is missing') END;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_item_count_delete
      AFTER DELETE ON knowledge_items
      WHEN (SELECT complete FROM knowledge_item_count_state WHERE id = 1) = 1
      BEGIN
        UPDATE knowledge_item_count_state SET items = items - 1 WHERE id = 1;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Knowledge item count state is missing') END;
      END
      """)
  }

  private func setupVectorCounts() {
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_counts (
        model_hash TEXT PRIMARY KEY NOT NULL,
        chunks INTEGER NOT NULL DEFAULT 0 CHECK(typeof(chunks) = 'integer' AND chunks >= 0),
        pending INTEGER NOT NULL DEFAULT 0 CHECK(typeof(pending) = 'integer' AND pending >= 0),
        legacy INTEGER NOT NULL DEFAULT 0 CHECK(legacy IN (0, 1))
      )
      """)
    _ = execute("""
      CREATE TABLE IF NOT EXISTS knowledge_count_scan (
        kind TEXT PRIMARY KEY NOT NULL,
        after_primary TEXT NOT NULL DEFAULT '',
        after_secondary TEXT NOT NULL DEFAULT '',
        complete INTEGER NOT NULL DEFAULT 0 CHECK(complete IN (0, 1))
      )
      """)
    if !columnExists("count_tracked", in: "knowledge_vectors") {
      _ = execute("ALTER TABLE knowledge_vectors ADD COLUMN count_tracked INTEGER NOT NULL DEFAULT 0")
    }
    if !columnExists("count_tracked", in: "knowledge_vector_queue") {
      _ = execute("ALTER TABLE knowledge_vector_queue ADD COLUMN count_tracked INTEGER NOT NULL DEFAULT 0")
    }
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_vector_counts(model_hash, legacy)
      SELECT model_hash, 1 FROM knowledge_vector_enrollment
      """)
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_vector_counts(model_hash, legacy)
      SELECT DISTINCT model_hash, 1 FROM knowledge_vectors
      """)
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_vector_counts(model_hash, legacy)
      SELECT DISTINCT model_hash, 1 FROM knowledge_vector_queue
      """)
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_count_scan(kind, complete)
      VALUES ('vectors', CASE WHEN EXISTS(SELECT 1 FROM knowledge_vectors LIMIT 1) THEN 0 ELSE 1 END)
      """)
    _ = execute("""
      INSERT OR IGNORE INTO knowledge_count_scan(kind, complete)
      VALUES ('queue', CASE WHEN EXISTS(SELECT 1 FROM knowledge_vector_queue LIMIT 1) THEN 0 ELSE 1 END)
      """)
    installVectorCountTriggers()
  }

  private func installVectorCountTriggers() {
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_vector_insert_guard
      BEFORE INSERT ON knowledge_vectors
      WHEN typeof(NEW.count_tracked) != 'integer' OR NEW.count_tracked != 0
      BEGIN SELECT RAISE(ABORT, 'Invalid new vector count tracking state'); END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_vector_update_guard
      BEFORE UPDATE ON knowledge_vectors
      WHEN typeof(NEW.count_tracked) != 'integer' OR NEW.count_tracked NOT IN (0, 1)
        OR NEW.count_tracked < OLD.count_tracked
        OR NEW.vector_key IS NOT OLD.vector_key OR NEW.item_hash IS NOT OLD.item_hash
        OR NEW.model_hash IS NOT OLD.model_hash
      BEGIN SELECT RAISE(ABORT, 'Invalid vector count identity or transition'); END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_vector_insert
      AFTER INSERT ON knowledge_vectors
      BEGIN
        UPDATE knowledge_vectors SET count_tracked = 1 WHERE vector_key = NEW.vector_key;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Vector count tracking update was lost') END;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_vector_track
      AFTER UPDATE OF count_tracked ON knowledge_vectors
      WHEN OLD.count_tracked = 0 AND NEW.count_tracked = 1
      BEGIN
        UPDATE knowledge_vector_counts SET chunks = chunks + 1 WHERE model_hash = NEW.model_hash;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Vector count update was lost') END;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_vector_delete
      AFTER DELETE ON knowledge_vectors WHEN OLD.count_tracked = 1
      BEGIN
        UPDATE knowledge_vector_counts SET chunks = chunks - 1 WHERE model_hash = OLD.model_hash;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Vector count delete was lost') END;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_queue_insert_guard
      BEFORE INSERT ON knowledge_vector_queue
      WHEN typeof(NEW.count_tracked) != 'integer' OR NEW.count_tracked != 0
      BEGIN SELECT RAISE(ABORT, 'Invalid new queue count tracking state'); END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_queue_update_guard
      BEFORE UPDATE ON knowledge_vector_queue
      WHEN typeof(NEW.count_tracked) != 'integer' OR NEW.count_tracked NOT IN (0, 1)
        OR NEW.count_tracked < OLD.count_tracked
        OR NEW.model_hash IS NOT OLD.model_hash OR NEW.item_hash IS NOT OLD.item_hash
      BEGIN SELECT RAISE(ABORT, 'Invalid queue count identity or transition'); END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_queue_insert
      AFTER INSERT ON knowledge_vector_queue
      BEGIN
        UPDATE knowledge_vector_queue SET count_tracked = 1
        WHERE model_hash = NEW.model_hash AND item_hash = NEW.item_hash;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Queue count tracking update was lost') END;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_queue_track
      AFTER UPDATE OF count_tracked ON knowledge_vector_queue
      WHEN OLD.count_tracked = 0 AND NEW.count_tracked = 1
      BEGIN
        UPDATE knowledge_vector_counts SET pending = pending + 1 WHERE model_hash = NEW.model_hash;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Queue count update was lost') END;
      END
      """)
    _ = execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_count_queue_delete
      AFTER DELETE ON knowledge_vector_queue WHEN OLD.count_tracked = 1
      BEGIN
        UPDATE knowledge_vector_counts SET pending = pending - 1 WHERE model_hash = OLD.model_hash;
        SELECT CASE WHEN changes() != 1 THEN RAISE(ABORT, 'Queue count delete was lost') END;
      END
      """)
  }

  private func columnExists(_ column: String, in table: String) -> Bool {
    guard let statement = prepare("PRAGMA table_info(\(table))") else { return false }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW {
      if let name = sqlite3_column_text(statement, 1), String(cString: name) == column { return true }
    }
    return false
  }

  private func countMaintenancePending() -> Bool {
    guard let statement = prepare("SELECT 1 FROM knowledge_count_scan WHERE complete = 0 LIMIT 1") else {
      return true
    }
    defer { sqlite3_finalize(statement) }
    return sqlite3_step(statement) == SQLITE_ROW
  }

  private func advanceVectorCountScan(kind: String, pageSize: Int) throws -> Bool {
    guard ["vectors", "queue"].contains(kind),
          let state = prepare("""
            SELECT after_primary, after_secondary, complete
            FROM knowledge_count_scan WHERE kind = ? LIMIT 1
            """) else { throw AgentKnowledgeDatabaseError.unavailable }
    bind(kind, at: 1, to: state)
    guard sqlite3_step(state) == SQLITE_ROW,
          let primaryText = sqlite3_column_text(state, 0),
          let secondaryText = sqlite3_column_text(state, 1) else {
      sqlite3_finalize(state)
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    let primary = String(cString: primaryText)
    let secondary = String(cString: secondaryText)
    let complete = sqlite3_column_int(state, 2)
    sqlite3_finalize(state)
    guard (0...1).contains(complete),
          (primary.isEmpty || isOpaqueHash(primary)),
          (secondary.isEmpty || isOpaqueHash(secondary)) else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    if complete == 1 { return true }

    let sql = kind == "vectors"
      ? "SELECT vector_key, model_hash, count_tracked FROM knowledge_vectors WHERE vector_key > ? ORDER BY vector_key LIMIT ?"
      : """
        SELECT model_hash, item_hash, count_tracked FROM knowledge_vector_queue
        WHERE model_hash > ? OR (model_hash = ? AND item_hash > ?)
        ORDER BY model_hash, item_hash LIMIT ?
        """
    guard let page = prepare(sql) else { throw AgentKnowledgeDatabaseError.unavailable }
    if kind == "vectors" {
      bind(primary, at: 1, to: page)
      sqlite3_bind_int(page, 2, Int32(pageSize + 1))
    } else {
      bind(primary, at: 1, to: page)
      bind(primary, at: 2, to: page)
      bind(secondary, at: 3, to: page)
      sqlite3_bind_int(page, 4, Int32(pageSize + 1))
    }
    var rows: [(String, String, Bool)] = []
    while sqlite3_step(page) == SQLITE_ROW,
          let firstText = sqlite3_column_text(page, 0),
          let secondText = sqlite3_column_text(page, 1) {
      let first = String(cString: firstText)
      let second = String(cString: secondText)
      let tracked = sqlite3_column_int(page, 2)
      guard isOpaqueHash(first), isOpaqueHash(second), (0...1).contains(tracked) else {
        sqlite3_finalize(page)
        throw AgentKnowledgeDatabaseError.corruptRecord
      }
      rows.append((first, second, tracked == 1))
    }
    sqlite3_finalize(page)

    for row in rows.prefix(pageSize) where !row.2 {
      let updateSQL = kind == "vectors"
        ? "UPDATE knowledge_vectors SET count_tracked = 1 WHERE vector_key = ? AND count_tracked = 0"
        : "UPDATE knowledge_vector_queue SET count_tracked = 1 WHERE model_hash = ? AND item_hash = ? AND count_tracked = 0"
      guard let update = prepare(updateSQL) else { throw AgentKnowledgeDatabaseError.unavailable }
      bind(row.0, at: 1, to: update)
      if kind == "queue" { bind(row.1, at: 2, to: update) }
      let changed = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
      sqlite3_finalize(update)
      guard changed else { throw AgentKnowledgeDatabaseError.corruptRecord }
    }

    let last = rows.prefix(pageSize).last
    let nextPrimary = last?.0 ?? primary
    let nextSecondary = kind == "queue" ? (last?.1 ?? secondary) : ""
    guard let checkpoint = prepare("""
      UPDATE knowledge_count_scan
      SET after_primary = ?, after_secondary = ?, complete = ? WHERE kind = ?
      """) else { throw AgentKnowledgeDatabaseError.unavailable }
    bind(nextPrimary, at: 1, to: checkpoint)
    bind(nextSecondary, at: 2, to: checkpoint)
    sqlite3_bind_int(checkpoint, 3, rows.count <= pageSize ? 1 : 0)
    bind(kind, at: 4, to: checkpoint)
    let saved = sqlite3_step(checkpoint) == SQLITE_DONE && sqlite3_changes(database) == 1
    sqlite3_finalize(checkpoint)
    guard saved else { throw AgentKnowledgeDatabaseError.corruptRecord }
    return rows.count <= pageSize
  }

  private func isOpaqueHash(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy {
      ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
    }
  }

  private func ensureVectorEnrollment(modelHash: String) -> Bool {
    guard modelHash.count == 64,
          let statement = prepare("""
            INSERT OR IGNORE INTO knowledge_vector_enrollment(model_hash, after_item_hash, complete)
            VALUES (?, '', CASE WHEN EXISTS(
              SELECT 1 FROM knowledge_vectors WHERE model_hash = ? LIMIT 1
            ) THEN 1 ELSE 0 END)
            """) else { return false }
    defer { sqlite3_finalize(statement) }
    bind(modelHash, at: 1, to: statement)
    bind(modelHash, at: 2, to: statement)
    guard sqlite3_step(statement) == SQLITE_DONE else { return false }
    guard let counts = prepare("""
      INSERT OR IGNORE INTO knowledge_vector_counts(model_hash, legacy)
      VALUES (?, CASE WHEN EXISTS(
        SELECT 1 FROM knowledge_vectors WHERE model_hash = ? LIMIT 1
      ) OR EXISTS(
        SELECT 1 FROM knowledge_vector_queue WHERE model_hash = ? LIMIT 1
      ) THEN 1 ELSE 0 END)
      """) else { return false }
    defer { sqlite3_finalize(counts) }
    bind(modelHash, at: 1, to: counts)
    bind(modelHash, at: 2, to: counts)
    bind(modelHash, at: 3, to: counts)
    return sqlite3_step(counts) == SQLITE_DONE
  }

  private func refillVectorEnrollment(modelHash: String, pageSize: Int = 64) -> Bool {
    guard (1...256).contains(pageSize), execute("BEGIN IMMEDIATE TRANSACTION"),
          let state = prepare(
            "SELECT after_item_hash, complete FROM knowledge_vector_enrollment WHERE model_hash = ? LIMIT 1"
          ) else {
      _ = execute("ROLLBACK")
      return false
    }
    bind(modelHash, at: 1, to: state)
    guard sqlite3_step(state) == SQLITE_ROW,
          let cursorText = sqlite3_column_text(state, 0) else {
      sqlite3_finalize(state)
      _ = execute("ROLLBACK")
      return false
    }
    let cursor = String(cString: cursorText)
    let complete = sqlite3_column_int(state, 1) == 1
    sqlite3_finalize(state)
    guard cursor.isEmpty || (cursor.count == 64 && cursor.allSatisfy(\.isHexDigit)) else {
      _ = execute("ROLLBACK")
      return false
    }
    if complete {
      guard execute("COMMIT") else {
        _ = execute("ROLLBACK")
        return false
      }
      return true
    }
    guard let page = prepare("""
      SELECT item_hash FROM knowledge_items
      WHERE item_hash > ? ORDER BY item_hash ASC LIMIT ?
      """) else {
      _ = execute("ROLLBACK")
      return false
    }
    bind(cursor, at: 1, to: page)
    sqlite3_bind_int(page, 2, Int32(pageSize + 1))
    var keys: [String] = []
    while sqlite3_step(page) == SQLITE_ROW, let text = sqlite3_column_text(page, 0) {
      let key = String(cString: text)
      guard key.count == 64, key.allSatisfy(\.isHexDigit) else {
        sqlite3_finalize(page)
        _ = execute("ROLLBACK")
        return false
      }
      keys.append(key)
    }
    sqlite3_finalize(page)
    for itemHash in keys.prefix(pageSize) {
      guard let insert = prepare(
        "INSERT OR IGNORE INTO knowledge_vector_queue(model_hash, item_hash) VALUES (?, ?)"
      ) else {
        _ = execute("ROLLBACK")
        return false
      }
      bind(modelHash, at: 1, to: insert)
      bind(itemHash, at: 2, to: insert)
      let inserted = sqlite3_step(insert) == SQLITE_DONE
      sqlite3_finalize(insert)
      if !inserted {
        _ = execute("ROLLBACK")
        return false
      }
    }
    let nextCursor = keys.prefix(pageSize).last ?? cursor
    guard let update = prepare("""
      UPDATE knowledge_vector_enrollment SET after_item_hash = ?, complete = ?
      WHERE model_hash = ?
      """) else {
      _ = execute("ROLLBACK")
      return false
    }
    bind(nextCursor, at: 1, to: update)
    sqlite3_bind_int(update, 2, keys.count <= pageSize ? 1 : 0)
    bind(modelHash, at: 3, to: update)
    let updated = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
    sqlite3_finalize(update)
    guard updated, execute("COMMIT") else {
      _ = execute("ROLLBACK")
      return false
    }
    return true
  }

  private func removeVectorQueueItem(itemHash: String, modelHash: String) -> Bool {
    guard let statement = prepare(
      "DELETE FROM knowledge_vector_queue WHERE model_hash = ? AND item_hash = ?"
    ) else { return false }
    defer { sqlite3_finalize(statement) }
    bind(modelHash, at: 1, to: statement)
    bind(itemHash, at: 2, to: statement)
    return sqlite3_step(statement) == SQLITE_DONE
  }

  private func vectorQueueIsEmpty(modelHash: String) throws -> Bool {
    guard let statement = prepare(
      "SELECT 1 FROM knowledge_vector_queue WHERE model_hash = ? LIMIT 1"
    ) else { throw AgentKnowledgeDatabaseError.unavailable }
    defer { sqlite3_finalize(statement) }
    bind(modelHash, at: 1, to: statement)
    return sqlite3_step(statement) != SQLITE_ROW
  }

  private func enqueueVectorItemIfRegistered(itemHash: String, modelHash: String) -> Bool {
    guard let statement = prepare("""
      INSERT OR IGNORE INTO knowledge_vector_queue(model_hash, item_hash)
      SELECT ?, ? WHERE EXISTS(
        SELECT 1 FROM knowledge_vector_enrollment WHERE model_hash = ?
      )
      """) else { return false }
    defer { sqlite3_finalize(statement) }
    bind(modelHash, at: 1, to: statement)
    bind(itemHash, at: 2, to: statement)
    bind(modelHash, at: 3, to: statement)
    return sqlite3_step(statement) == SQLITE_DONE
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

  private func externalPayloadPurpose(_ itemHash: String) -> String {
    "agent-knowledge-external-payload:v1:\(sourcePreviewNamespace):\(itemHash)"
  }

  private func sourceIdentity(_ item: AgentKnowledgeItem) -> String {
    item.source.trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("local:\(item.id)")
  }

  private func sourceHeaderPurpose(_ sourceHash: String) -> String {
    "agent-knowledge-source:\(sourceHash)"
  }

  private func sourceHeaderFingerprint(
    sourceHash: String,
    updatedAtMillis: Int64,
    encryptedHeader: Data
  ) -> Data {
    var material = Data()
    func append(_ value: Data) {
      var length = UInt64(value.count).bigEndian
      withUnsafeBytes(of: &length) { material.append(contentsOf: $0) }
      material.append(value)
    }
    append(Data(sourceHash.utf8))
    var updated = updatedAtMillis.bigEndian
    append(withUnsafeBytes(of: &updated) { Data($0) })
    append(encryptedHeader)
    return Data(SHA256.hash(data: material))
  }

  private func sourcePreviewPurpose(sourceHash: String, fingerprint: Data) -> String {
    let digest = fingerprint.map { String(format: "%02x", $0) }.joined()
    return "agent-knowledge-source-preview:v1:\(sourcePreviewNamespace):\(sourceHash):\(digest)"
  }

  private func vectorPurpose(_ vectorKey: String) -> String { "agent-knowledge-vector:\(vectorKey)" }

  private func setupNativePublications() -> Bool {
    guard execute("BEGIN IMMEDIATE TRANSACTION") else { return false }
    var committed = false
    defer { if !committed { _ = execute("ROLLBACK") } }
    guard execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_publications (
        model_hash TEXT NOT NULL, item_hash TEXT NOT NULL, epoch TEXT NOT NULL,
        sequence INTEGER NOT NULL, operation TEXT NOT NULL, source_revision_hash TEXT NOT NULL,
        chunk_count INTEGER NOT NULL, PRIMARY KEY(model_hash, item_hash)
      )
      """), execute("""
      CREATE TABLE IF NOT EXISTS knowledge_vector_native_root_seek (
        model_hash TEXT PRIMARY KEY NOT NULL, contract_hash TEXT NOT NULL, epoch TEXT NOT NULL,
        head INTEGER NOT NULL, source_revision INTEGER NOT NULL, after_item_hash TEXT NOT NULL DEFAULT ''
      )
      """), execute("""
      CREATE INDEX IF NOT EXISTS knowledge_vector_publication_ready
      ON knowledge_vector_publications(model_hash, item_hash) WHERE operation = 'ready'
      """), execute("""
      CREATE TRIGGER IF NOT EXISTS knowledge_vector_publication_append AFTER INSERT ON knowledge_vector_changes
      BEGIN
        INSERT INTO knowledge_vector_publications(model_hash, item_hash, epoch, sequence, operation, source_revision_hash, chunk_count)
        VALUES (NEW.model_hash, NEW.item_hash, NEW.epoch, NEW.sequence, NEW.operation, NEW.source_revision_hash, NEW.chunk_count)
        ON CONFLICT(model_hash, item_hash) DO UPDATE SET epoch = excluded.epoch, sequence = excluded.sequence,
          operation = excluded.operation, source_revision_hash = excluded.source_revision_hash, chunk_count = excluded.chunk_count;
      END
      """), execute("INSERT OR IGNORE INTO knowledge_metadata(key, value) VALUES ('native_publications_schema', 0)"),
      execute("""
        UPDATE knowledge_vector_native_enrollment SET after_item_hash = '', complete = 0
        WHERE (SELECT value FROM knowledge_metadata WHERE key = 'native_publications_schema') < 1
        """), execute("UPDATE knowledge_metadata SET value = 1 WHERE key = 'native_publications_schema'"),
      execute("COMMIT") else { return false }
    committed = true
    return true
  }

  private func decodeVectorChange(_ statement: OpaquePointer?) throws -> AgentKnowledgeVectorChange {
    guard let epoch = sqlite3_column_text(statement, 2), let operation = sqlite3_column_text(statement, 3),
      let item = sqlite3_column_text(statement, 4), let revision = sqlite3_column_text(statement, 5),
      let kind = AgentKnowledgeVectorChangeOperation(rawValue: String(cString: operation)) else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    let event = AgentKnowledgeVectorChange(sequence: sqlite3_column_int64(statement, 0),
      previousSequence: sqlite3_column_int64(statement, 1), epoch: String(cString: epoch), operation: kind,
      itemHash: String(cString: item), sourceRevisionHash: String(cString: revision),
      chunkCount: Int(sqlite3_column_int64(statement, 6)), updatedAtMillis: sqlite3_column_int64(statement, 7))
    guard event.previousSequence >= 0, event.sequence > event.previousSequence,
      UUID(uuidString: event.epoch) != nil, isOpaqueHash(event.itemHash), isOpaqueHash(event.sourceRevisionHash),
      event.updatedAtMillis >= 0, (kind == .ready ? event.chunkCount > 0 : event.chunkCount == 0) else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return event
  }

  private func readVectorFeedStamp(modelHash: String) throws -> AgentKnowledgeVectorFeedStamp {
    guard let statement = prepare("""
      SELECT m.epoch, m.head_sequence, r.revision FROM knowledge_vector_feed_models m
      CROSS JOIN knowledge_browse_revision r WHERE m.model_hash = ? AND r.id = 1
        AND (SELECT value FROM knowledge_metadata WHERE key = 'native_publications_schema') = 1 LIMIT 1
      """) else { throw AgentKnowledgeDatabaseError.unavailable }
    defer { sqlite3_finalize(statement) }
    bind(modelHash, at: 1, to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW, let epoch = sqlite3_column_text(statement, 0) else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    let stamp = AgentKnowledgeVectorFeedStamp(epoch: String(cString: epoch), head: sqlite3_column_int64(statement, 1),
      sourceRevision: sqlite3_column_int64(statement, 2))
    guard UUID(uuidString: stamp.epoch) != nil, stamp.head >= 0, stamp.sourceRevision >= 0 else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return stamp
  }

  private func hasNativePublication(modelHash: String, itemHash: String, revisionHash: String, chunkCount: Int) throws -> Bool {
    guard let statement = prepare("""
      SELECT 1 FROM knowledge_vector_publications p WHERE p.model_hash = ? AND p.item_hash = ?
        AND p.source_revision_hash = ? AND p.chunk_count = ? AND p.operation = 'ready'
        AND p.sequence = (SELECT c.sequence FROM knowledge_vector_changes c
          WHERE c.model_hash = p.model_hash AND c.item_hash = p.item_hash ORDER BY c.sequence DESC LIMIT 1)
      """) else { throw AgentKnowledgeDatabaseError.unavailable }
    defer { sqlite3_finalize(statement) }
    bind(modelHash, at: 1, to: statement)
    bind(itemHash, at: 2, to: statement)
    bind(revisionHash, at: 3, to: statement)
    sqlite3_bind_int64(statement, 4, Int64(chunkCount))
    let status = sqlite3_step(statement)
    guard status == SQLITE_ROW || status == SQLITE_DONE else { throw AgentKnowledgeDatabaseError.unavailable }
    return status == SQLITE_ROW
  }

  private func ensureVectorFeedModel(modelHash: String) throws -> (epoch: String, head: Int64) {
    if let statement = prepare(
      "SELECT epoch, head_sequence FROM knowledge_vector_feed_models WHERE model_hash = ? LIMIT 1"
    ) {
      bind(modelHash, at: 1, to: statement)
      if sqlite3_step(statement) == SQLITE_ROW,
         let epochText = sqlite3_column_text(statement, 0) {
        let state = (String(cString: epochText), sqlite3_column_int64(statement, 1))
        sqlite3_finalize(statement)
        return state
      }
      sqlite3_finalize(statement)
    }
    let epoch = UUID().uuidString.lowercased()
    guard let insert = prepare(
      "INSERT OR IGNORE INTO knowledge_vector_feed_models(model_hash, epoch, head_sequence) VALUES (?, ?, 0)"
    ) else { throw AgentKnowledgeDatabaseError.unavailable }
    bind(modelHash, at: 1, to: insert)
    bind(epoch, at: 2, to: insert)
    let inserted = sqlite3_step(insert) == SQLITE_DONE
    sqlite3_finalize(insert)
    guard inserted, let state = prepare("SELECT epoch, head_sequence FROM knowledge_vector_feed_models WHERE model_hash = ? LIMIT 1") else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { sqlite3_finalize(state) }
    bind(modelHash, at: 1, to: state)
    guard sqlite3_step(state) == SQLITE_ROW, let text = sqlite3_column_text(state, 0) else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    return (String(cString: text), sqlite3_column_int64(state, 1))
  }

  private func publishVectorChange(
    operation: AgentKnowledgeVectorChangeOperation,
    itemId: String,
    modelSHA256: String,
    sourceRevision: String,
    chunkCount: Int,
    updatedAtMillis: Int64
  ) -> Bool {
    let modelHash = keyedHash(modelSHA256.lowercased())
    let itemHash = keyedHash(itemId)
    let revisionHash = keyedHash(sourceRevision)
    guard let state = try? ensureVectorFeedModel(modelHash: modelHash) else { return false }
    if let latest = prepare("""
      SELECT operation, item_hash, source_revision_hash, chunk_count FROM knowledge_vector_changes
      WHERE model_hash = ? ORDER BY sequence DESC LIMIT 1
      """) {
      bind(modelHash, at: 1, to: latest)
      if sqlite3_step(latest) == SQLITE_ROW,
         let operationText = sqlite3_column_text(latest, 0),
         let itemText = sqlite3_column_text(latest, 1),
         let revisionText = sqlite3_column_text(latest, 2),
         String(cString: operationText) == operation.rawValue,
         String(cString: itemText) == itemHash,
         String(cString: revisionText) == revisionHash,
         sqlite3_column_int64(latest, 3) == Int64(max(chunkCount, 0)) {
        sqlite3_finalize(latest)
        return true
      }
      sqlite3_finalize(latest)
    }
    guard let insert = prepare("""
      INSERT INTO knowledge_vector_changes(
        model_hash, epoch, previous_sequence, operation, item_hash,
        source_revision_hash, chunk_count, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      """) else { return false }
    bind(modelHash, at: 1, to: insert)
    bind(state.epoch, at: 2, to: insert)
    sqlite3_bind_int64(insert, 3, state.head)
    bind(operation.rawValue, at: 4, to: insert)
    bind(itemHash, at: 5, to: insert)
    bind(revisionHash, at: 6, to: insert)
    sqlite3_bind_int64(insert, 7, Int64(max(chunkCount, 0)))
    sqlite3_bind_int64(insert, 8, max(updatedAtMillis, 0))
    let inserted = sqlite3_step(insert) == SQLITE_DONE
    sqlite3_finalize(insert)
    guard inserted else { return false }
    let sequence = sqlite3_last_insert_rowid(database)
    guard let update = prepare(
      "UPDATE knowledge_vector_feed_models SET head_sequence = ? WHERE model_hash = ? AND epoch = ? AND head_sequence = ?"
    ) else { return false }
    sqlite3_bind_int64(update, 1, sequence)
    bind(modelHash, at: 2, to: update)
    bind(state.epoch, at: 3, to: update)
    sqlite3_bind_int64(update, 4, state.head)
    let updated = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
    sqlite3_finalize(update)
    return updated
  }

  private func vectorProvenanceHash(_ provenance: AgentKnowledgeVectorProvenance) throws -> String {
    keyedHash(String(decoding: try JSONEncoder.galaxySSI.encode(provenance), as: UTF8.self))
  }

  private func replayOrdinalCount(modelHash: String, itemHash: String, revisionHash: String) throws -> Int64 {
    guard let statement = prepare("SELECT COUNT(*) FROM knowledge_vector_replay_rows WHERE model_hash = ? AND item_hash = ? AND source_revision_hash = ?") else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    defer { sqlite3_finalize(statement) }
    bind(modelHash, at: 1, to: statement)
    bind(itemHash, at: 2, to: statement)
    bind(revisionHash, at: 3, to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
    return sqlite3_column_int64(statement, 0)
  }

  private func storeVectorReplayOrdinal(_ checkpoint: AgentKnowledgeVectorCheckpoint, vectorKey: String) -> Bool {
    guard let delete = prepare("DELETE FROM knowledge_vector_replay_rows WHERE vector_key = ?") else { return false }
    bind(vectorKey, at: 1, to: delete)
    let deleted = sqlite3_step(delete) == SQLITE_DONE
    sqlite3_finalize(delete)
    guard deleted else { return false }
    guard checkpoint.sourceStartUTF16 != nil else { return true }
    guard let insert = prepare("""
      INSERT INTO knowledge_vector_replay_rows(vector_key, model_hash, item_hash, source_revision_hash, chunk_index)
      VALUES (?, ?, ?, ?, ?)
      """) else { return false }
    defer { sqlite3_finalize(insert) }
    bind(vectorKey, at: 1, to: insert)
    bind(keyedHash(checkpoint.provenance.modelSHA256), at: 2, to: insert)
    bind(keyedHash(checkpoint.itemId), at: 3, to: insert)
    bind(keyedHash(checkpoint.sourceRevision), at: 4, to: insert)
    sqlite3_bind_int64(insert, 5, Int64(checkpoint.chunkIndex))
    return sqlite3_step(insert) == SQLITE_DONE
  }

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
    return try? AgentKnowledgeVectorStorage.decode(plaintext)
  }

  private func orphanedVectorDocuments() -> [AgentKnowledgeVectorCheckpoint] {
    guard let statement = prepare("""
      SELECT v.vector_key, v.encrypted_payload FROM knowledge_vectors v
      LEFT JOIN knowledge_items k ON k.item_hash = v.item_hash
      WHERE k.item_hash IS NULL ORDER BY v.vector_key ASC
      """) else { return [] }
    defer { sqlite3_finalize(statement) }
    var seen = Set<String>()
    var documents: [AgentKnowledgeVectorCheckpoint] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let keyText = sqlite3_column_text(statement, 0),
            let encrypted = blob(statement, column: 1) else { continue }
      let key = String(cString: keyText)
      guard let plaintext = try? vectorCipher.decrypt(encrypted, expectedPurpose: vectorPurpose(key)),
            let checkpoint = try? AgentKnowledgeVectorStorage.decode(plaintext) else { continue }
      let identity = "\(checkpoint.itemId):\(checkpoint.provenance.modelSHA256)"
      if seen.insert(identity).inserted { documents.append(checkpoint) }
    }
    return documents
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
    guard let catalog = sqlite3_db_handle(statement) else { throw AgentKnowledgeDatabaseError.unavailable }
    let plaintext: Data
    if let primary = try primaryPayloads.read(itemHash: itemHash, catalog: catalog) {
      plaintext = primary
    } else {
      guard let legacy = readExternalPayload(itemHash: itemHash, database: catalog) ??
        (try? cipher.decrypt(encrypted, expectedPurpose: purpose(itemHash))) else { throw AgentKnowledgeDatabaseError.corruptRecord }
      plaintext = legacy
    }
    guard let item = try? JSONDecoder.galaxySSI.decode(AgentKnowledgeItem.self, from: plaintext),
          keyedHash(item.id) == itemHash else {
      throw AgentKnowledgeDatabaseError.corruptRecord
    }
    return item
  }

  private func insertExternalPayload(_ plaintext: Data, itemHash: String) -> Bool {
    let digest = SHA256.hash(data: plaintext).map { String(format: "%02x", $0) }.joined()
    let fileName = "\(itemHash)-\(digest.prefix(16)).saenc"
    let url = payloadDirectory.appendingPathComponent(fileName)
    do {
      try cipher.write(plaintext, to: url, purpose: externalPayloadPurpose(itemHash))
    } catch {
      return false
    }
    guard let statement = prepare("""
      INSERT INTO knowledge_external_payloads(item_hash, file_name, plaintext_bytes, plaintext_sha256)
      VALUES (?, ?, ?, ?)
      """) else { return false }
    defer { sqlite3_finalize(statement) }
    bind(itemHash, at: 1, to: statement)
    bind(fileName, at: 2, to: statement)
    sqlite3_bind_int64(statement, 3, Int64(plaintext.count))
    bind(digest, at: 4, to: statement)
    return sqlite3_step(statement) == SQLITE_DONE
  }

  private func readExternalPayload(itemHash: String, database: OpaquePointer?) -> Data? {
    guard let database else { return nil }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
      database,
      "SELECT file_name, plaintext_bytes, plaintext_sha256 FROM knowledge_external_payloads WHERE item_hash = ? LIMIT 1",
      -1,
      &statement,
      nil
    ) == SQLITE_OK, let statement else { return nil }
    defer { sqlite3_finalize(statement) }
    bind(itemHash, at: 1, to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
          let fileText = sqlite3_column_text(statement, 0),
          let digestText = sqlite3_column_text(statement, 2) else { return nil }
    let fileName = String(cString: fileText)
    let expectedBytes = sqlite3_column_int64(statement, 1)
    let expectedDigest = String(cString: digestText)
    guard fileName.range(of: #"^[a-f0-9]{64}-[a-f0-9]{16}\.saenc$"#, options: .regularExpression) != nil,
          expectedBytes > 0,
          expectedDigest.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
          let plaintext = try? cipher.read(
            from: payloadDirectory.appendingPathComponent(fileName),
            purpose: externalPayloadPurpose(itemHash)
          ),
          Int64(plaintext.count) == expectedBytes,
          SHA256.hash(data: plaintext).map({ String(format: "%02x", $0) }).joined() == expectedDigest else {
      return nil
    }
    return plaintext
  }

  private func externalPayloadReferenceCount(fileName: String) -> Int64 {
    guard let statement = prepare(
      "SELECT COUNT(*) FROM knowledge_external_payloads WHERE file_name = ?"
    ) else { return -1 }
    defer { sqlite3_finalize(statement) }
    bind(fileName, at: 1, to: statement)
    return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : -1
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
