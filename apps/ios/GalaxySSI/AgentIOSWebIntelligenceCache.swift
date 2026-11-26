import CryptoKit
import Foundation

struct AgentIOSWebIntelligenceCacheDocument: Codable, Equatable {
  var url: String
  var title: String
  var content: String
  var contentType: String
  var contentSHA256: String
  var retrievedAtMillis: Int64
  var expiresAtMillis: Int64
  var links: [String]
  var metadata: [String: String]
  var vector: [Float]? = nil
  var embeddingModelID: String? = nil

  func value(includeContent: Bool = true) -> AgentMcpJSONObject {
    var result: AgentMcpJSONObject = [
      "url": .string(url),
      "title": .string(title),
      "content_type": .string(contentType),
      "content_sha256": .string(contentSHA256),
      "retrieved_at_millis": .int(retrievedAtMillis),
      "expires_at_millis": .int(expiresAtMillis),
      "links": .array(links.map { .string($0) }),
      "metadata": .object(metadata.mapValues { .string($0) })
    ]
    if includeContent {
      result["content"] = .string(content)
    }
    return result
  }
}

struct AgentIOSWebIntelligenceCacheWatch: Codable, Equatable {
  var id: String
  var url: String
  var intervalMinutes: Int
  var enabled: Bool
  var lastCheckedAtMillis: Int64
  var lastChangedAtMillis: Int64
  var lastSHA256: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64

  func value() -> AgentMcpJSONObject {
    [
      "watch_id": .string(id),
      "url": .string(url),
      "interval_minutes": .int(Int64(intervalMinutes)),
      "enabled": .bool(enabled),
      "last_checked_at_millis": .int(lastCheckedAtMillis),
      "last_changed_at_millis": .int(lastChangedAtMillis),
      "last_sha256": .string(lastSHA256),
      "created_at_millis": .int(createdAtMillis),
      "updated_at_millis": .int(updatedAtMillis)
    ]
  }
}

final class AgentIOSWebIntelligenceCacheStore {
  static let shared = AgentIOSWebIntelligenceCacheStore()

  private struct Snapshot: Codable {
    var version = 1
    var documents: [AgentIOSWebIntelligenceCacheDocument] = []
    var watches: [AgentIOSWebIntelligenceCacheWatch] = []
    var learnedSources: [AgentIOSLearnedWebSource]? = nil
    var sourceHealth: [AgentIOSWebSourceHealth]? = nil
    var searchResponses: [SearchResponse]? = nil
  }

  private struct EncryptedEnvelope: Codable {
    var version: Int
    var nonce: String
    var ciphertext: String
    var tag: String
  }

  private struct SearchResponse: Codable {
    var key: String
    var storedAtMillis: Int64
    var expiresAtMillis: Int64
    var result: AgentNativeToolExecutionResult

    var isValid: Bool {
      key.count == 64 && key.allSatisfy { "0123456789abcdef".contains($0) } &&
        storedAtMillis >= 0 && expiresAtMillis > storedAtMillis &&
        expiresAtMillis - storedAtMillis <= 30 * 24 * 60 * 60_000 && result.isSuccess &&
        !(result.output["results"]?.arrayValue ?? []).isEmpty &&
        (result.output["results"]?.arrayValue?.count ?? 0) <= AgentIOSWebSearchCapacity.maximumResults &&
        (try? JSONEncoder().encode(self).count).map { $0 <= AgentIOSWebSearchCapacity.maximumCachedResponseBytes } == true
    }
  }

  static let maxSearchResponses = 32

  func searchResponse(key: String) -> AgentNativeToolExecutionResult? {
    lock.lock()
    defer { lock.unlock() }
    let now = nowMillis()
    guard let row = try? cacheIndexUnlocked().entry(.search, id: key),
      let entry = try? JSONDecoder().decode(SearchResponse.self, from: row.payload), entry.isValid,
      entry.key == key, entry.storedAtMillis <= now, now < entry.expiresAtMillis else { return nil }
    return entry.result
  }

  func searchCacheGeneration() -> UUID {
    lock.lock()
    defer { lock.unlock() }
    return (try? cacheIndexUnlocked().generation()) ?? UUID()
  }

  @discardableResult
  func putSearchResponse(key: String, result: AgentNativeToolExecutionResult, ttlMillis: Int64,
    expectedGeneration: UUID? = nil) -> Bool {
    let now = max(0, nowMillis())
    let ttl = min(max(ttlMillis, 60_000), 30 * 24 * 60 * 60_000)
    guard now <= Int64.max - ttl else { return false }
    let entry = SearchResponse(key: key, storedAtMillis: now, expiresAtMillis: now + ttl, result: result)
    guard entry.isValid else { return false }
    lock.lock()
    defer { lock.unlock() }
    do {
      try cacheIndexUnlocked().putSearch(try indexEntry(.search, id: key, updated: now, expires: entry.expiresAtMillis, value: entry),
        now: now, expected: expectedGeneration)
      return true
    } catch { return false }
  }

  static let maxDocuments = 2_000
  static let maxContentCharacters = 240_000
  static let maxWatches = 100
  static let keyAccount = "web_intelligence.cache_key"

  private let fileURL: URL
  private let secrets: GalaxySSISecretStore
  private let fileManager: FileManager
  private let nowMillis: () -> Int64
  private let lock: NSLock
  private let beforeCommit: () throws -> Void
  private let learningQueue: AgentIOSWebMaintenanceQueue
  private let healthBeforeCommit: () throws -> Void
  private let state: State
  private final class State {
    let lock = NSLock()
    var generation = UUID()
    var lastLearningStatus = "idle"
  }
  private static let gatesLock = NSLock()
  private static var fileStates: [String: State] = [:]
  private static let keyLock = NSLock()

  private static func state(for url: URL) -> State {
    gatesLock.lock()
    defer { gatesLock.unlock() }
    let path = url.standardizedFileURL.path
    if let state = fileStates[path] { return state }
    let state = State()
    fileStates[path] = state
    return state
  }

  init(
    fileURL: URL = AgentIOSWebIntelligenceCacheStore.defaultFileURL(),
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    fileManager: FileManager = .default,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    learningQueue: AgentIOSWebMaintenanceQueue = .shared,
    healthBeforeCommit: @escaping () throws -> Void = {},
    beforeCommit: @escaping () throws -> Void = {}
  ) {
    self.fileURL = fileURL
    self.secrets = secrets
    self.fileManager = fileManager
    self.nowMillis = nowMillis
    self.beforeCommit = beforeCommit
    self.learningQueue = learningQueue
    self.healthBeforeCommit = healthBeforeCommit
    let sharedState = Self.state(for: fileURL)
    state = sharedState
    lock = sharedState.lock
  }

  static func defaultFileURL(fileManager: FileManager = .default) -> URL {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return base
      .appendingPathComponent("GalaxySSI", isDirectory: true)
      .appendingPathComponent("web-intelligence-cache.json", isDirectory: false)
  }

  @discardableResult
  func putDocument(
    url: String,
    title: String,
    content: String,
    contentType: String,
    contentSHA256: String,
    retrievedAtMillis: Int64,
    expiresAtMillis: Int64,
    links: [String] = [],
    metadata: [String: String] = [:]
  ) -> Bool {
    let cleanURL = canonicalURL(url)
    guard !cleanURL.isEmpty else { return false }
    let document = AgentIOSWebIntelligenceCacheDocument(
      url: cleanURL,
      title: String(title.prefix(512)),
      content: String(content.prefix(Self.maxContentCharacters)),
      contentType: String(contentType.prefix(256)),
      contentSHA256: String(contentSHA256.prefix(128)),
      retrievedAtMillis: max(0, retrievedAtMillis),
      expiresAtMillis: max(0, expiresAtMillis),
      links: Array(links.prefix(100)),
      metadata: metadata.reduce(into: [:]) { result, entry in
        result[String(entry.key.prefix(128))] = String(entry.value.prefix(512))
      }
    )
    return putDocuments([document])
  }

  @discardableResult
  func putDocuments(_ documents: [AgentIOSWebIntelligenceCacheDocument]) -> Bool {
    if documents.isEmpty { return true }
    var bounded: [AgentIOSWebIntelligenceCacheDocument] = []
    for var document in documents.prefix(Self.maxDocuments) {
      document.url = canonicalURL(document.url)
      guard !document.url.isEmpty else { return false }
      document.title = String(document.title.prefix(512))
      document.content = String(document.content.prefix(Self.maxContentCharacters))
      document.contentType = String(document.contentType.prefix(256))
      document.contentSHA256 = String(document.contentSHA256.prefix(128))
      document.retrievedAtMillis = max(0, document.retrievedAtMillis)
      document.expiresAtMillis = max(0, document.expiresAtMillis)
      document.links = Array(document.links.prefix(100))
      document.metadata = document.metadata.reduce(into: [:]) { values, entry in
        values[String(entry.key.prefix(128))] = String(entry.value.prefix(512))
      }
      document.vector = AgentIOSWebFeatureHashEmbedder.standard.embedDocument(title: document.title, content: document.content)
      document.embeddingModelID = AgentIOSWebFeatureHashEmbedder.standard.modelID
      bounded.removeAll { $0.url == document.url }
      bounded.append(document)
    }
    lock.lock()
    defer { lock.unlock() }
    do {
      let index = try cacheIndexUnlocked()
      try index.transaction {
        for document in bounded { try index.put(try documentEntry(document)) }
        try index.prune(.document, limit: Self.maxDocuments)
      }
      return true
    } catch { return false }
  }

  func document(url: String, allowStale: Bool = false) -> AgentIOSWebIntelligenceCacheDocument? {
    let cleanURL = canonicalURL(url)
    guard !cleanURL.isEmpty else { return nil }
    lock.lock()
    defer { lock.unlock() }
    guard let row = try? cacheIndexUnlocked().entry(.document, id: cleanURL),
      let document = try? decodeDocument(row) else { return nil }
    return allowStale || document.expiresAtMillis >= nowMillis() ? document : nil
  }

  func search(
    query: String,
    limit: Int,
    allowStale: Bool = true
  ) -> [AgentIOSWebIntelligenceCacheDocument] {
    let tokens = query
      .lowercased()
      .split { $0.isWhitespace || $0 == "," || $0 == "." }
      .map(String.init)
      .filter { $0.count >= 2 }
    let now = nowMillis()
    lock.lock()
    defer { lock.unlock() }
    var scored: [(AgentIOSWebIntelligenceCacheDocument, Int)] = []
    do {
      try cacheIndexUnlocked().forEach(.document) { row in
        let document = try decodeDocument(row)
        guard allowStale || document.expiresAtMillis >= now else { return }
        let haystack = "\(document.title) \(document.url) \(document.content)".lowercased()
        let score = tokens.reduce(0) { $0 + haystack.components(separatedBy: $1).count - 1 }
        guard tokens.isEmpty || score > 0 else { return }
        scored.append((document, score))
        scored.sort { $0.1 == $1.1 ? $0.0.retrievedAtMillis > $1.0.retrievedAtMillis : $0.1 > $1.1 }
        if scored.count > max(1, min(limit, 100)) { scored.removeLast() }
      }
      return scored.map { $0.0 }
    } catch { return [] }
  }

  struct SimilarityHit {
    var document: AgentIOSWebIntelligenceCacheDocument
    var score: Double
  }

  func similarDocuments(query: String, limit: Int, excludingURL: String = "", target: [Float]? = nil) -> [SimilarityHit] {
    let embedder = AgentIOSWebFeatureHashEmbedder.standard
    let queryVector = target ?? embedder.embed(query)
    let excluded = excludingURL.isEmpty ? "" : canonicalURL(excludingURL)
    lock.lock()
    defer { lock.unlock() }
    var ranked: [(Int, SimilarityHit)] = [], ordinal = 0
    do {
      try cacheIndexUnlocked().forEach(.document) { row in
        let document = try decodeDocument(row), offset = ordinal
        ordinal += 1
        guard excluded.isEmpty || canonicalURL(document.url) != excluded else { return }
        let vector: [Float]
        if document.embeddingModelID == embedder.modelID, let saved = document.vector,
          saved.count == embedder.dimensions, saved.allSatisfy(\.isFinite) { vector = saved }
        else { vector = embedder.embedDocument(title: document.title, content: document.content) }
        let score = (embedder.cosine(queryVector, vector) + 1) / 2
        ranked.append((offset, SimilarityHit(document: document, score: score)))
        ranked.sort {
        if $0.1.score != $1.1.score { return $0.1.score > $1.1.score }
        if $0.1.document.retrievedAtMillis != $1.1.document.retrievedAtMillis {
          return $0.1.document.retrievedAtMillis > $1.1.document.retrievedAtMillis
        }
        return $0.0 < $1.0
        }
        if ranked.count > max(1, min(limit, 100)) { ranked.removeLast() }
      }
      return ranked.map { $0.1 }
    } catch { return [] }
  }

  func stats() -> AgentMcpJSONObject {
    lock.lock()
    defer { lock.unlock() }
    guard var result = try? cacheIndexUnlocked().metadata(now: nowMillis()), let health = try? healthIndexUnlocked().records() else {
      return ["available": .bool(false), "status": .string("unavailable"), "encryption": .string("ios_keychain_aes_gcm")]
    }
    let now = nowMillis()
    result.merge([
      "available": .bool(true),
      "last_learning_status": .string(state.lastLearningStatus),
      "source_health_count": .int(Int64(health.count)),
      "source_circuits_open": .int(Int64(health.values.filter { $0.circuitState(now: now) == "open" }.count)),
      "cache_version": .int(2),
      "stats_scope": .string("indexed_counts"),
      "legacy_cleanup_pending": .bool(fileManager.fileExists(atPath: fileURL.path)),
      "encryption": .string("ios_keychain_aes_gcm")
    ]) { _, next in next }
    return result
  }

  func cacheMetadata() -> AgentMcpJSONObject {
    lock.lock()
    defer { lock.unlock() }
    do {
      var result = try cacheIndexUnlocked().metadata(now: nowMillis())
      result["source_health_count"] = .int(try healthIndexUnlocked().count())
      result["available"] = .bool(true)
      result["cache_version"] = .int(2)
      result["stats_scope"] = .string("indexed_counts")
      result["legacy_cleanup_pending"] = .bool(fileManager.fileExists(atPath: fileURL.path))
      result["encryption"] = .string("ios_keychain_aes_gcm")
      result["last_learning_status"] = .string(state.lastLearningStatus)
      return result
    } catch { return ["available": .bool(false), "status": .string("unavailable"), "encryption": .string("ios_keychain_aes_gcm")] }
  }

  func clear(expiredOnly: Bool) -> AgentMcpJSONObject {
    var removed = 0
    var learnedRemoved = 0
    var searchesRemoved = 0
    let now = nowMillis()
    lock.lock()
    let committed: Bool
    do {
      if !expiredOnly { state.generation = UUID() }
      let counts = try cacheIndexUnlocked().clear(expiredOnly: expiredOnly, now: now)
      removed = Int(clamping: counts.documents)
      searchesRemoved = Int(clamping: counts.searches)
      learnedRemoved = Int(clamping: counts.learned)
      committed = true
      if !expiredOnly { state.lastLearningStatus = committed ? "cleared" : "failed_write" }
    } catch {
      committed = false
    }
    lock.unlock()
    if committed && !expiredOnly {
      NotificationCenter.default.post(name: .galaxySSIWebLearningDidChange, object: self)
    }
    return ["documents_removed": .int(Int64(committed ? removed : 0)), "committed": .bool(committed),
      "learned_sources_removed": .int(Int64(committed ? learnedRemoved : 0)),
      "searches_removed": .int(Int64(committed ? searchesRemoved : 0))]
  }

  func learnedSources() -> [AgentIOSLearnedWebSource]? {
    lock.lock()
    defer { lock.unlock() }
    guard let learned = try? learnedUnlocked(cacheIndexUnlocked()) else { return nil }
    return learned.sorted {
      if ($0.status == "verified") != ($1.status == "verified") { return $0.status == "verified" }
      if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
      if $0.lastSeenAtMillis != $1.lastSeenAtMillis { return $0.lastSeenAtMillis > $1.lastSeenAtMillis }
      return $0.sourceID < $1.sourceID
    }
  }

  func sourceHealth(ids: Set<String> = []) -> [String: AgentIOSWebSourceHealth]? {
    lock.lock()
    defer { lock.unlock() }
    return try? healthIndexUnlocked().records(ids: ids)
  }

  func sourceRoutingSnapshot() -> (learnedSources: [AgentIOSLearnedWebSource], health: [String: AgentIOSWebSourceHealth])? {
    lock.lock()
    defer { lock.unlock() }
    guard let learned = try? learnedUnlocked(cacheIndexUnlocked()), let health = try? healthIndexUnlocked().records() else { return nil }
    return (learned, health)
  }

  @discardableResult
  func recordSourceReceipts(_ receipts: [AgentIOSWebSourceReceipt]) -> Bool {
    guard receipts.count <= AgentIOSWebSourceHealth.maximumSources, receipts.allSatisfy(\.isValid) else { return false }
    if receipts.isEmpty { return true }
    lock.lock()
    defer { lock.unlock() }
    do { try healthIndexUnlocked().record(receipts, now: nowMillis); return true }
    catch { return false }
  }

  func resetSourceHealth() -> AgentMcpJSONObject {
    lock.lock()
    defer { lock.unlock() }
    do {
      let removed = try healthIndexUnlocked().reset()
      return ["committed": .bool(true), "source_health_removed": .int(removed)]
    } catch { return ["committed": .bool(false), "source_health_removed": .int(0)] }
  }

  func learnSourceCandidates(query: String, categories: [String], results: [AgentMcpJSONObject],
                             isCancelled: @escaping () -> Bool = { false }) -> AgentMcpJSONObject {
    let observations = AgentIOSWebSourceLearningPolicy.observations(query: query, categories: categories, results: results)
    guard !observations.isEmpty else { return ["status": .string("skipped_no_candidates")] }
    lock.lock()
    let generation = state.generation
    lock.unlock()
    let accepted = learningQueue.submit {
      if !isCancelled(), self.applyLearning(observations, generation: generation, isCancelled: isCancelled) {
        NotificationCenter.default.post(name: .galaxySSIWebLearningDidChange, object: self)
      }
    }
    return ["status": .string(accepted ? "queued" : "skipped_queue_full")]
  }

  private func applyLearning(_ observations: [AgentIOSWebSourceLearningPolicy.Observation], generation: UUID,
                             isCancelled: () -> Bool) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard state.generation == generation, !isCancelled() else { return false }
    do {
      let index = try cacheIndexUnlocked()
      try index.transaction {
        for observation in observations {
          let previous = try index.entry(.learned, id: observation.sourceID).map {
            try JSONDecoder().decode(AgentIOSLearnedWebSource.self, from: $0.payload)
          }
          let value = AgentIOSWebSourceLearningPolicy.evolve(previous, observation: observation, now: nowMillis())
          try index.put(try learnedEntry(value))
        }
        try index.prune(.learned, limit: AgentIOSWebSourceLearningPolicy.maximumSources)
      }
      state.lastLearningStatus = "saved"
      return true
    } catch { state.lastLearningStatus = "failed_write"; return false }
  }

  @discardableResult
  func putWatch(_ watch: AgentIOSWebIntelligenceCacheWatch) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    do {
      let index = try cacheIndexUnlocked()
      try index.transaction {
        try index.put(try watchEntry(watch))
        try index.prune(.watch, limit: Self.maxWatches)
      }
      return true
    } catch { return false }
  }

  func watchRecord(id: String) throws -> AgentIOSWebIntelligenceCacheWatch? {
    lock.lock()
    defer { lock.unlock() }
    guard let row = try cacheIndexUnlocked().entry(.watch, id: id) else { return nil }
    let watch = try JSONDecoder().decode(AgentIOSWebIntelligenceCacheWatch.self, from: row.payload)
    guard watch.id == id, watch.updatedAtMillis == row.updated else { throw AgentIOSWebCacheIndex.Failure.corrupt }
    return watch
  }

  func commitWatchCheck(_ updated: AgentIOSWebIntelligenceCacheWatch, expected: AgentIOSWebIntelligenceCacheWatch) -> Bool? {
    var permitted = expected
    permitted.lastSHA256 = updated.lastSHA256
    permitted.lastCheckedAtMillis = updated.lastCheckedAtMillis
    permitted.lastChangedAtMillis = updated.lastChangedAtMillis
    permitted.updatedAtMillis = updated.updatedAtMillis
    guard permitted == updated, updated.lastCheckedAtMillis >= expected.lastCheckedAtMillis,
      updated.lastChangedAtMillis >= expected.lastChangedAtMillis, updated.updatedAtMillis >= expected.updatedAtMillis else { return false }
    lock.lock()
    defer { lock.unlock() }
    do { return try cacheIndexUnlocked().compareAndPutWatch(try watchEntry(updated), expected: expected) }
    catch { return nil }
  }

  func watch(id: String) -> AgentIOSWebIntelligenceCacheWatch? {
    lock.lock()
    defer { lock.unlock() }
    guard let row = try? cacheIndexUnlocked().entry(.watch, id: id),
      let watch = try? JSONDecoder().decode(AgentIOSWebIntelligenceCacheWatch.self, from: row.payload), watch.id == id else { return nil }
    return watch
  }

  func watches() -> [AgentIOSWebIntelligenceCacheWatch] {
    watchSnapshot() ?? []
  }

  func watchSnapshot() -> [AgentIOSWebIntelligenceCacheWatch]? {
    lock.lock()
    defer { lock.unlock() }
    return try? cacheIndexUnlocked().entries(.watch, limit: Self.maxWatches).map {
      try JSONDecoder().decode(AgentIOSWebIntelligenceCacheWatch.self, from: $0.payload)
    }
  }

  @discardableResult
  func removeWatch(id: String) -> Bool? {
    lock.lock()
    defer { lock.unlock() }
    do {
      let index = try cacheIndexUnlocked()
      return try index.transaction { try index.remove(.watch, id: id) > 0 }
    } catch { return nil }
  }

  private func readLegacyUnlocked() -> Snapshot? {
    guard fileURL.isFileURL else { return nil }
    let data: Data
    do { data = try Data(contentsOf: fileURL) }
    catch let error as CocoaError where error.code == .fileReadNoSuchFile { return Snapshot() }
    catch { return nil }
    guard let envelope = try? JSONDecoder().decode(EncryptedEnvelope.self, from: data), envelope.version == 1,
          let key = encryptionKey(createIfMissing: false),
          let nonceData = Data(base64Encoded: envelope.nonce),
          let ciphertext = Data(base64Encoded: envelope.ciphertext),
          let tag = Data(base64Encoded: envelope.tag),
          let nonce = try? AES.GCM.Nonce(data: nonceData),
          let sealed = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
          let plaintext = try? AES.GCM.open(sealed, using: key),
          let snapshot = try? JSONDecoder().decode(Snapshot.self, from: plaintext), snapshot.version == 1,
          snapshot.documents.count <= 64,
          snapshot.documents.allSatisfy({ ($0.vector?.count ?? 0) <= 2048 && ($0.vector ?? []).allSatisfy(\.isFinite) }),
          (snapshot.learnedSources?.count ?? 0) <= AgentIOSWebSourceLearningPolicy.maximumSources,
          (snapshot.learnedSources ?? []).allSatisfy(\.isValid),
          Set((snapshot.learnedSources ?? []).map(\.sourceID)).count == (snapshot.learnedSources?.count ?? 0),
          (snapshot.sourceHealth?.count ?? 0) <= AgentIOSWebSourceHealth.maximumSources,
          (snapshot.sourceHealth ?? []).allSatisfy(\.isValid),
          (snapshot.searchResponses?.count ?? 0) <= Self.maxSearchResponses,
          (snapshot.searchResponses ?? []).allSatisfy(\.isValid),
          Set((snapshot.searchResponses ?? []).map(\.key)).count == (snapshot.searchResponses?.count ?? 0),
          Set((snapshot.sourceHealth ?? []).map(\.sourceID)).count == (snapshot.sourceHealth?.count ?? 0) else {
      return nil
    }
    return snapshot
  }

  static func indexDatabaseURL(for legacyURL: URL) -> URL {
    URL(fileURLWithPath: legacyURL.path + ".cache-index", isDirectory: true).appendingPathComponent("cache.sqlite")
  }

  private var cacheImportAccount: String {
    let digest = SHA256.hash(data: Data(Self.healthStorageIdentity(for: fileURL).utf8)).map { String(format: "%02x", $0) }.joined()
    return "web_intelligence.cache_import.v1.\(digest)"
  }

  private func cacheIndexUnlocked() throws -> AgentIOSWebCacheIndex {
    guard fileURL.isFileURL else { throw AgentIOSWebCacheIndex.Failure.unavailable }
    let url = Self.indexDatabaseURL(for: fileURL), receipt = secrets.string(account: cacheImportAccount)
    guard receipt == nil || receipt == "pending" || receipt == "1",
      receipt == nil || fileManager.fileExists(atPath: url.path) else { throw AgentIOSWebCacheIndex.Failure.corrupt }
    let existing = fileManager.fileExists(atPath: url.path) || fileManager.fileExists(atPath: fileURL.path)
    guard let master = encryptionKey(createIfMissing: !existing) else { throw AgentIOSWebCacheIndex.Failure.unavailable }
    let index = try AgentIOSWebCacheIndex(url: url, master: master, identity: Self.healthStorageIdentity(for: fileURL), beforeCommit: beforeCommit)
    if receipt == nil { try secrets.setString("pending", account: cacheImportAccount) }
    try index.initialize(allowImport: receipt != "1") {
      guard let snapshot = readLegacyUnlocked() else { throw AgentIOSWebCacheIndex.Failure.corrupt }
      _ = try healthIndexUnlocked(legacyHealth: snapshot.sourceHealth ?? [])
      return try snapshot.documents.reversed().map(documentEntry) + snapshot.watches.map(watchEntry) +
        (snapshot.learnedSources ?? []).reversed().map(learnedEntry) + (snapshot.searchResponses ?? []).map {
          try indexEntry(.search, id: $0.key, updated: $0.storedAtMillis, expires: $0.expiresAtMillis, value: $0)
        }
    }
    if receipt != "1" { try secrets.setString("1", account: cacheImportAccount) }
    // The committed indexes own every imported domain. Do not retain a second
    // decryptable copy of cleared documents; a failed unlink is retried later.
    if fileManager.fileExists(atPath: fileURL.path) { try? fileManager.removeItem(at: fileURL) }
    return index
  }

  private func indexEntry<T: Encodable>(_ kind: AgentIOSWebCacheIndex.Kind, id: String, updated: Int64,
    expires: Int64 = 0, characters: Int64 = 0, verified: Bool = false, value: T) throws -> AgentIOSWebCacheIndex.Entry {
    .init(kind: kind, id: id, updated: updated, expires: expires, characters: characters,
      verified: verified, payload: try JSONEncoder().encode(value))
  }
  private func documentEntry(_ value: AgentIOSWebIntelligenceCacheDocument) throws -> AgentIOSWebCacheIndex.Entry {
    try indexEntry(.document, id: canonicalURL(value.url), updated: value.retrievedAtMillis, expires: value.expiresAtMillis,
      characters: Int64(value.content.utf16.count), value: value)
  }
  private func watchEntry(_ value: AgentIOSWebIntelligenceCacheWatch) throws -> AgentIOSWebCacheIndex.Entry {
    try indexEntry(.watch, id: value.id, updated: value.updatedAtMillis, value: value)
  }
  private func learnedEntry(_ value: AgentIOSLearnedWebSource) throws -> AgentIOSWebCacheIndex.Entry {
    guard value.isValid else { throw AgentIOSWebCacheIndex.Failure.corrupt }
    return try indexEntry(.learned, id: value.sourceID, updated: value.lastSeenAtMillis, verified: value.status == "verified", value: value)
  }
  private func decodeDocument(_ row: AgentIOSWebCacheIndex.Entry) throws -> AgentIOSWebIntelligenceCacheDocument {
    let value = try JSONDecoder().decode(AgentIOSWebIntelligenceCacheDocument.self, from: row.payload)
    guard row.kind == .document, canonicalURL(value.url) == row.id, value.retrievedAtMillis == row.updated,
      value.expiresAtMillis == row.expires, Int64(value.content.utf16.count) == row.characters else { throw AgentIOSWebCacheIndex.Failure.corrupt }
    return value
  }
  private func learnedUnlocked(_ index: AgentIOSWebCacheIndex) throws -> [AgentIOSLearnedWebSource] {
    try index.entries(.learned, limit: AgentIOSWebSourceLearningPolicy.maximumSources).map { row in
      let value = try JSONDecoder().decode(AgentIOSLearnedWebSource.self, from: row.payload)
      guard value.isValid, value.sourceID == row.id else { throw AgentIOSWebCacheIndex.Failure.corrupt }
      return value
    }
  }

  private func encryptionKey(createIfMissing: Bool) -> SymmetricKey? {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    if let encoded = secrets.string(account: Self.keyAccount) {
      guard let data = Data(base64Encoded: encoded), data.count == 32 else { return nil }
      return SymmetricKey(data: data)
    }
    guard createIfMissing, !fileManager.fileExists(atPath: Self.sourceHealthDatabaseURL(for: fileURL).path),
      !fileManager.fileExists(atPath: Self.indexDatabaseURL(for: fileURL).path),
      secrets.string(account: healthImportAccount) == nil, secrets.string(account: cacheImportAccount) == nil else { return nil }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    guard (try? secrets.setString(data.base64EncodedString(), account: Self.keyAccount)) != nil else {
      return nil
    }
    return key
  }

  static func sourceHealthDatabaseURL(for legacyURL: URL) -> URL {
    URL(fileURLWithPath: legacyURL.path + ".health-index", isDirectory: true).appendingPathComponent("health.sqlite")
  }

  private func healthIndexUnlocked(legacyHealth: [AgentIOSWebSourceHealth]? = nil) throws -> AgentIOSWebSourceHealthDatabase {
    guard fileURL.isFileURL else { throw AgentIOSWebSourceHealthDatabase.Failure.unavailable }
    let url = Self.sourceHealthDatabaseURL(for: fileURL)
    let receipt = secrets.string(account: healthImportAccount)
    guard receipt == nil || receipt == "pending" || receipt == "1",
      receipt == nil || fileManager.fileExists(atPath: url.path) else { throw AgentIOSWebSourceHealthDatabase.Failure.corrupt }
    let existing = fileManager.fileExists(atPath: url.path) || fileManager.fileExists(atPath: fileURL.path)
    guard let key = encryptionKey(createIfMissing: !existing) else { throw AgentIOSWebSourceHealthDatabase.Failure.unavailable }
    let index = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key,
      storageIdentity: Self.healthStorageIdentity(for: fileURL), beforeCommit: healthBeforeCommit)
    // Remember that the health domain moved even if its database is later lost.
    // A deleted index must not resurrect stale legacy circuits after a reset.
    if receipt == nil { try secrets.setString("pending", account: healthImportAccount) }
    try index.initialize(allowLegacyImport: receipt != "1") {
      if let legacyHealth { return legacyHealth }
      guard let snapshot = readLegacyUnlocked() else { throw AgentIOSWebSourceHealthDatabase.Failure.corrupt }
      return snapshot.sourceHealth ?? []
    }
    if receipt != "1" { try secrets.setString("1", account: healthImportAccount) }
    return index
  }

  private var healthImportAccount: String {
    let digest = SHA256.hash(data: Data(Self.healthStorageIdentity(for: fileURL).utf8)).map { String(format: "%02x", $0) }.joined()
    return "web_intelligence.health_import.v1.\(digest)"
  }

  private static func healthStorageIdentity(for url: URL) -> String {
    let path = url.standardizedFileURL.pathComponents
    let roots: [(String, URL?)] = [
      ("app-support", FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first),
      ("temporary", FileManager.default.temporaryDirectory)
    ]
    for (name, root) in roots {
      guard let components = root?.standardizedFileURL.pathComponents, path.count > components.count,
        path.prefix(components.count).elementsEqual(components) else { continue }
      return name + ":" + path.dropFirst(components.count).joined(separator: "/")
    }
    return "explicit-path:" + url.standardizedFileURL.path
  }

  private func canonicalURL(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(),
          let host = components.host?.lowercased(),
          scheme == "https" else {
      return trimmed
    }
    components.scheme = scheme
    components.host = host
    components.fragment = nil
    if components.path.isEmpty { components.path = "/" }
    return components.string ?? trimmed
  }
}
