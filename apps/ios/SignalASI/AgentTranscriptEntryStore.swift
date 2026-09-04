import Foundation

struct AgentTranscriptPage: Codable, Equatable {
  var entries: [AgentTranscriptEntry]
  var nextBeforeSequence: Int64?
  var hasMore: Bool
  var newestSequence: Int64?

  enum CodingKeys: String, CodingKey {
    case entries
    case nextBeforeSequence = "next_before_sequence"
    case hasMore = "has_more"
    case newestSequence = "newest_sequence"
  }
}

struct AgentTranscriptDelta: Codable, Equatable {
  var entries: [AgentTranscriptEntry]
  var newestSequence: Int64
  var hasMore: Bool

  enum CodingKeys: String, CodingKey {
    case entries
    case newestSequence = "newest_sequence"
    case hasMore = "has_more"
  }
}

struct AgentTranscriptContentPage: Codable, Equatable {
  var entryId: String
  var field: String
  var offset: Int
  var nextOffset: Int
  var totalChunks: Int
  var totalLength: Int
  var sha256: String
  var chunks: [String]
  var done: Bool

  enum CodingKeys: String, CodingKey {
    case entryId = "entry_id"
    case field
    case offset
    case nextOffset = "next_offset"
    case totalChunks = "total_chunks"
    case totalLength = "total_length"
    case sha256
    case chunks
    case done
  }
}

protocol AgentTranscriptEntryStore {
  @discardableResult
  func insert(_ entry: AgentTranscriptEntry) -> Bool
  @discardableResult
  func replaceBatch(_ entries: [AgentTranscriptEntry]) -> Bool
  func listAll(limit: Int) -> [AgentTranscriptEntry]
  func replaceAll(_ entries: [AgentTranscriptEntry])
  func listConversation(_ conversationId: String) -> [AgentTranscriptEntry]
  func listConversations(_ conversationIds: Set<String>) -> [AgentTranscriptEntry]
  func listConversationPage(
    conversationId: String,
    beforeSequenceExclusive: Int64?,
    pageSize: Int
  ) -> AgentTranscriptPage
  func listConversationAfter(
    conversationId: String,
    afterSequenceExclusive: Int64,
    pageSize: Int
  ) -> AgentTranscriptDelta
  func findById(_ entryId: String) -> AgentTranscriptEntry?
  func findByDedupeKey(conversationId: String, dedupeKey: String) -> AgentTranscriptEntry?
  func textChunkPage(entryId: String, offset: Int, pageSize: Int) -> AgentTranscriptContentPage?
  func clear()
}

final class UserDefaultsAgentTranscriptEntryStore: AgentTranscriptEntryStore {
  static let defaultKey = "signalasi_agent_transcript_entries"
  static let defaultPageSize = 80
  static let maxPageSize = 500
  static let maxContentPageChunks = 16

  private struct Document: Codable {
    var version: Int
    var nextSequence: Int64
    var rows: [StoredRow]
    var chunks: [StoredChunk]
  }

  private struct StoredRow: Codable, Equatable {
    var sequence: Int64
    var entry: AgentTranscriptEntry
  }

  private struct StoredChunk: Codable, Equatable {
    var entryId: String
    var field: String
    var index: Int
    var value: String
    var utf16Count: Int
    var sha256: String

    enum CodingKeys: String, CodingKey {
      case entryId = "entry_id"
      case field
      case index
      case value
      case utf16Count = "utf16_count"
      case sha256
    }
  }

  private let defaults: UserDefaults
  private let key: String
  private let secrets: SignalASISecretStore
  private let lock = NSLock()

  init(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentTranscriptEntryStore.defaultKey,
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.key = key
    self.secrets = secrets
    normalizePersistedState()
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    key: String = UserDefaultsAgentTranscriptEntryStore.defaultKey,
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    SignalASIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
  }

  @discardableResult
  func insert(_ entry: AgentTranscriptEntry) -> Bool {
    locked {
      var document = load()
      let cleanId = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanId.isEmpty,
            !document.rows.contains(where: { $0.entry.id == cleanId }) else {
        return false
      }
      let prepared = preparedEntry(entry)
      let sequence = document.nextSequence
      document.nextSequence += 1
      document.rows.append(StoredRow(sequence: sequence, entry: prepared.entry))
      document.chunks += prepared.chunks
      document.rows = Self.orderedRows(document.rows)
      document.chunks = Self.orderedChunks(document.chunks)
      persist(document)
      return true
    }
  }

  @discardableResult
  func replaceBatch(_ entries: [AgentTranscriptEntry]) -> Bool {
    locked {
      guard !entries.isEmpty else { return true }
      let cleanIds = entries.map { $0.id.trimmingCharacters(in: .whitespacesAndNewlines) }
      guard cleanIds.allSatisfy({ !$0.isEmpty }), Set(cleanIds).count == entries.count else {
        return false
      }

      var document = load()
      let replacedIds = Set(cleanIds)
      document.rows.removeAll { replacedIds.contains($0.entry.id) }
      document.chunks.removeAll { replacedIds.contains($0.entryId) }
      for (index, entry) in entries.enumerated() {
        var normalizedEntry = entry
        normalizedEntry.id = cleanIds[index]
        let prepared = preparedEntry(normalizedEntry)
        document.rows.append(StoredRow(sequence: document.nextSequence, entry: prepared.entry))
        document.nextSequence += 1
        document.chunks += prepared.chunks
      }
      return persist(document)
    }
  }

  func listAll(limit: Int = 500) -> [AgentTranscriptEntry] {
    locked {
      let safeLimit = min(max(0, limit), Self.maxBackupEntries)
      guard safeLimit > 0 else { return [] }
      let document = load()
      return Array(Self.orderedRows(document.rows).suffix(safeLimit))
        .map { hydrate($0.entry, chunks: document.chunks) }
    }
  }

  func replaceAll(_ entries: [AgentTranscriptEntry]) {
    locked {
      var document = Document(version: 1, nextSequence: 1, rows: [], chunks: [])
      var seenIds = Set<String>()
      for entry in entries.suffix(Self.maxBackupEntries) {
        let cleanId = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty, seenIds.insert(cleanId).inserted else { continue }
        let prepared = preparedEntry(entry)
        document.rows.append(StoredRow(sequence: document.nextSequence, entry: prepared.entry))
        document.nextSequence += 1
        document.chunks += prepared.chunks
      }
      persist(document)
    }
  }

  func listConversation(_ conversationId: String) -> [AgentTranscriptEntry] {
    locked {
      let document = load()
      return Self.orderedRows(document.rows)
        .filter { $0.entry.conversationId == conversationId }
        .map { hydrate($0.entry, chunks: document.chunks) }
    }
  }

  func listConversations(_ conversationIds: Set<String>) -> [AgentTranscriptEntry] {
    guard !conversationIds.isEmpty else { return [] }
    return locked {
      let document = load()
      return Self.orderedRows(document.rows)
        .filter { conversationIds.contains($0.entry.conversationId) }
        .map { hydrate($0.entry, chunks: document.chunks) }
    }
  }

  func listConversationPage(
    conversationId: String,
    beforeSequenceExclusive: Int64? = nil,
    pageSize: Int = UserDefaultsAgentTranscriptEntryStore.defaultPageSize
  ) -> AgentTranscriptPage {
    locked {
      let safePageSize = Self.safePageSize(pageSize)
      let rows = Self.orderedRows(load().rows)
        .filter { row in
          guard row.entry.conversationId == conversationId else {
            return false
          }
          return beforeSequenceExclusive.map { row.sequence < $0 } ?? true
        }
        .sorted { $0.sequence > $1.sequence }
      let retained = Array(rows.prefix(safePageSize))
      let hasMore = rows.count > retained.count
      return AgentTranscriptPage(
        entries: retained.reversed().map(\.entry),
        nextBeforeSequence: hasMore ? retained.last?.sequence : nil,
        hasMore: hasMore,
        newestSequence: retained.first?.sequence
      )
    }
  }

  func listConversationAfter(
    conversationId: String,
    afterSequenceExclusive: Int64,
    pageSize: Int = UserDefaultsAgentTranscriptEntryStore.defaultPageSize
  ) -> AgentTranscriptDelta {
    locked {
      let safePageSize = Self.safePageSize(pageSize)
      let rows = Self.orderedRows(load().rows)
        .filter { $0.entry.conversationId == conversationId && $0.sequence > afterSequenceExclusive }
      let retained = Array(rows.prefix(safePageSize))
      return AgentTranscriptDelta(
        entries: retained.map(\.entry),
        newestSequence: retained.last?.sequence ?? afterSequenceExclusive,
        hasMore: rows.count > retained.count
      )
    }
  }

  func findById(_ entryId: String) -> AgentTranscriptEntry? {
    locked {
      let document = load()
      guard let row = document.rows.first(where: { $0.entry.id == entryId.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
        return nil
      }
      return hydrate(row.entry, chunks: document.chunks)
    }
  }

  func findByDedupeKey(conversationId: String, dedupeKey: String) -> AgentTranscriptEntry? {
    let cleanKey = dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanKey.isEmpty else {
      return nil
    }
    return locked {
      let document = load()
      guard let row = document.rows.first(where: {
        $0.entry.conversationId == conversationId && $0.entry.dedupeKey == cleanKey
      }) else {
        return nil
      }
      return hydrate(row.entry, chunks: document.chunks)
    }
  }

  func textChunkPage(
    entryId: String,
    offset: Int = 0,
    pageSize: Int = 2
  ) -> AgentTranscriptContentPage? {
    contentChunkPage(entryId: entryId, field: Self.fieldText, offset: offset, pageSize: pageSize)
  }

  func richOutputChunkPage(
    entryId: String,
    offset: Int = 0,
    pageSize: Int = 2
  ) -> AgentTranscriptContentPage? {
    contentChunkPage(entryId: entryId, field: Self.fieldRichOutput, offset: offset, pageSize: pageSize)
  }

  func clear() {
    locked {
      SignalASIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: key, secrets: secrets)
    }
  }

  private func contentChunkPage(
    entryId: String,
    field: String,
    offset: Int,
    pageSize: Int
  ) -> AgentTranscriptContentPage? {
    locked {
      let cleanEntryId = entryId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanEntryId.isEmpty else {
        return nil
      }
      let document = load()
      guard let row = document.rows.first(where: { $0.entry.id == cleanEntryId }) else {
        return nil
      }
      let entry = row.entry
      let safeOffset = max(0, offset)
      let safePageSize = min(max(1, pageSize), Self.maxContentPageChunks)
      let storedChunks = Self.orderedChunks(document.chunks)
        .filter { $0.entryId == cleanEntryId && $0.field == field }
      if storedChunks.isEmpty {
        let value = field == Self.fieldText ? entry.text : entry.richOutputJson
        let chunks = safeOffset == 0 && !value.isEmpty ? [value] : []
        return AgentTranscriptContentPage(
          entryId: cleanEntryId,
          field: field,
          offset: safeOffset,
          nextOffset: safeOffset + chunks.count,
          totalChunks: value.isEmpty ? 0 : 1,
          totalLength: value.utf16.count,
          sha256: AgentLargeOutputPolicy.digest(value),
          chunks: chunks,
          done: true
        )
      }
      let selected = storedChunks
        .filter { $0.index >= safeOffset }
        .prefix(safePageSize)
      let values = selected.enumerated().map { position, chunk in
        precondition(chunk.index == safeOffset + position, "Agent transcript chunk order mismatch")
        precondition(chunk.value.utf16.count == chunk.utf16Count, "Agent transcript chunk length mismatch")
        precondition(AgentLargeOutputPolicy.digest(chunk.value) == chunk.sha256, "Agent transcript chunk digest mismatch")
        return chunk.value
      }
      let nextOffset = safeOffset + values.count
      return AgentTranscriptContentPage(
        entryId: cleanEntryId,
        field: field,
        offset: safeOffset,
        nextOffset: nextOffset,
        totalChunks: field == Self.fieldText ? entry.textChunkCount : entry.richOutputChunkCount,
        totalLength: field == Self.fieldText ? entry.textLength : entry.richOutputLength,
        sha256: field == Self.fieldText ? entry.textSha256 : entry.richOutputSha256,
        chunks: values,
        done: nextOffset >= storedChunks.count
      )
    }
  }

  private func preparedEntry(_ entry: AgentTranscriptEntry) -> (entry: AgentTranscriptEntry, chunks: [StoredChunk]) {
    let text = AgentLargeOutputPolicy.prepare(entry.text, includePreview: true)
    let richOutput = AgentLargeOutputPolicy.prepare(entry.richOutputJson, includePreview: false)
    var stored = entry
    stored.text = text.storedValue
    stored.richOutputJson = richOutput.storedValue
    stored.textChunkCount = text.chunkCount
    stored.textLength = text.totalLength
    stored.textSha256 = text.sha256
    stored.richOutputChunkCount = richOutput.chunkCount
    stored.richOutputLength = richOutput.totalLength
    stored.richOutputSha256 = richOutput.sha256
    let chunks = Self.chunks(entryId: entry.id, field: Self.fieldText, values: text.chunks) +
      Self.chunks(entryId: entry.id, field: Self.fieldRichOutput, values: richOutput.chunks)
    return (stored, chunks)
  }

  private func hydrate(_ entry: AgentTranscriptEntry, chunks: [StoredChunk]) -> AgentTranscriptEntry {
    guard AgentLargeOutputPolicy.hasDeferredContent(entry) else {
      return entry
    }
    var hydrated = entry
    if entry.textChunkCount > 0 {
      hydrated.text = readChunks(
        entryId: entry.id,
        field: Self.fieldText,
        expectedCount: entry.textChunkCount,
        expectedLength: entry.textLength,
        expectedSha256: entry.textSha256,
        chunks: chunks
      )
    }
    if entry.richOutputChunkCount > 0 {
      hydrated.richOutputJson = readChunks(
        entryId: entry.id,
        field: Self.fieldRichOutput,
        expectedCount: entry.richOutputChunkCount,
        expectedLength: entry.richOutputLength,
        expectedSha256: entry.richOutputSha256,
        chunks: chunks
      )
    }
    return hydrated
  }

  private func readChunks(
    entryId: String,
    field: String,
    expectedCount: Int,
    expectedLength: Int,
    expectedSha256: String,
    chunks: [StoredChunk]
  ) -> String {
    let selected = Self.orderedChunks(chunks)
      .filter { $0.entryId == entryId && $0.field == field }
    precondition(selected.count == expectedCount, "Agent transcript chunk count mismatch")
    for (index, chunk) in selected.enumerated() {
      precondition(chunk.index == index, "Agent transcript chunk order mismatch")
      precondition(chunk.value.utf16.count == chunk.utf16Count, "Agent transcript chunk length mismatch")
      precondition(AgentLargeOutputPolicy.digest(chunk.value) == chunk.sha256, "Agent transcript chunk digest mismatch")
    }
    let value = selected.map(\.value).joined()
    precondition(value.utf16.count == expectedLength, "Agent transcript hydrated length mismatch")
    precondition(AgentLargeOutputPolicy.digest(value) == expectedSha256, "Agent transcript hydrated digest mismatch")
    return value
  }

  private static func chunks(entryId: String, field: String, values: [String]) -> [StoredChunk] {
    values.enumerated().map { index, value in
      StoredChunk(
        entryId: entryId,
        field: field,
        index: index,
        value: value,
        utf16Count: value.utf16.count,
        sha256: AgentLargeOutputPolicy.digest(value)
      )
    }
  }

  private static func orderedRows(_ rows: [StoredRow]) -> [StoredRow] {
    rows.sorted {
      if $0.sequence == $1.sequence {
        return $0.entry.id < $1.entry.id
      }
      return $0.sequence < $1.sequence
    }
  }

  private static func orderedChunks(_ chunks: [StoredChunk]) -> [StoredChunk] {
    chunks.sorted {
      if $0.entryId == $1.entryId {
        if $0.field == $1.field {
          return $0.index < $1.index
        }
        return $0.field < $1.field
      }
      return $0.entryId < $1.entryId
    }
  }

  private static func safePageSize(_ pageSize: Int) -> Int {
    min(max(1, pageSize), maxPageSize)
  }

  private func normalizePersistedState() {
    locked {
      let document = load()
      if document.version != 1 {
        persist(document)
      }
    }
  }

  private func load() -> Document {
    let encryptedData = SignalASIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: key,
      secrets: secrets
    )
    let data = encryptedData ?? defaults.data(forKey: key)
    guard let data,
          let decoded = try? JSONDecoder().decode(Document.self, from: data) else {
      return Document(version: 1, nextSequence: 1, rows: [], chunks: [])
    }
    let nextSequence = max(decoded.nextSequence, (decoded.rows.map(\.sequence).max() ?? 0) + 1)
    let normalized = Document(
      version: 1,
      nextSequence: nextSequence,
      rows: Self.orderedRows(decoded.rows),
      chunks: Self.orderedChunks(decoded.chunks)
    )
    if encryptedData == nil {
      persist(normalized)
    }
    return normalized
  }

  @discardableResult
  private func persist(_ document: Document) -> Bool {
    let normalized = Document(
      version: 1,
      nextSequence: max(document.nextSequence, (document.rows.map(\.sequence).max() ?? 0) + 1),
      rows: Self.orderedRows(document.rows),
      chunks: Self.orderedChunks(document.chunks)
    )
    guard let data = try? JSONEncoder().encode(normalized) else { return false }
    return SignalASIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: key,
      secrets: secrets
    )
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static let fieldText = "text"
  private static let fieldRichOutput = "rich_output"
  private static let maxBackupEntries = 500
}
