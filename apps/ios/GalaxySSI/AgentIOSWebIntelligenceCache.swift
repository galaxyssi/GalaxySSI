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
        (result.output["results"]?.arrayValue?.count ?? 0) <= 24 &&
        (try? JSONEncoder().encode(self).count).map { $0 <= 262_144 } == true
    }
  }

  static let maxSearchResponses = 32

  func searchResponse(key: String) -> AgentNativeToolExecutionResult? {
    lock.lock()
    defer { lock.unlock() }
    let now = nowMillis()
    return readUnlocked()?.searchResponses?.first {
      $0.key == key && $0.storedAtMillis <= now && now < $0.expiresAtMillis
    }?.result
  }

  func searchCacheGeneration() -> UUID {
    lock.lock()
    defer { lock.unlock() }
    return state.generation
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
    guard expectedGeneration == nil || expectedGeneration == state.generation,
      var snapshot = readUnlocked() else { return false }
    do {
      var responses = (snapshot.searchResponses ?? []).filter { $0.key != key && $0.expiresAtMillis > now }
      responses.append(entry)
      snapshot.searchResponses = Array(responses.sorted {
        $0.storedAtMillis == $1.storedAtMillis ? $0.key < $1.key : $0.storedAtMillis > $1.storedAtMillis
      }.prefix(Self.maxSearchResponses))
    }
    return writeUnlocked(snapshot)
  }

  static let maxDocuments = 64
  static let maxContentCharacters = 240_000
  static let maxWatches = 100
  static let keyAccount = "web_intelligence.cache_key"

  private let fileURL: URL
  private let secrets: GalaxySSISecretStore
  private let fileManager: FileManager
  private let nowMillis: () -> Int64
  private let lock: NSLock
  private let writeFile: (Data, URL) throws -> Void
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
    writeFile: @escaping (Data, URL) throws -> Void = {
      try $0.write(to: $1, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
  ) {
    self.fileURL = fileURL
    self.secrets = secrets
    self.fileManager = fileManager
    self.nowMillis = nowMillis
    self.writeFile = writeFile
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
    let urls = Set(bounded.map(\.url))
    return mutate { snapshot in
      snapshot.documents.removeAll { urls.contains(canonicalURL($0.url)) }
      snapshot.documents.append(contentsOf: bounded)
      snapshot.documents.sort { $0.retrievedAtMillis > $1.retrievedAtMillis }
      if snapshot.documents.count > Self.maxDocuments {
        snapshot.documents = Array(snapshot.documents.prefix(Self.maxDocuments))
      }
    }
  }

  func document(url: String, allowStale: Bool = false) -> AgentIOSWebIntelligenceCacheDocument? {
    let cleanURL = canonicalURL(url)
    guard !cleanURL.isEmpty else { return nil }
    let snapshot = read()
    guard let document = snapshot.documents.first(where: { canonicalURL($0.url) == cleanURL }) else {
      return nil
    }
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
    let scored = read().documents.compactMap { document -> (AgentIOSWebIntelligenceCacheDocument, Int)? in
      guard allowStale || document.expiresAtMillis >= now else { return nil }
      let haystack = "\(document.title) \(document.url) \(document.content)".lowercased()
      let score = tokens.reduce(0) { partial, token in
        partial + haystack.components(separatedBy: token).count - 1
      }
      guard tokens.isEmpty || score > 0 else { return nil }
      return (document, score)
    }
    return scored
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.retrievedAtMillis > $1.0.retrievedAtMillis
      }
      .prefix(max(1, min(limit, Self.maxDocuments)))
      .map { $0.0 }
  }

  struct SimilarityHit {
    var document: AgentIOSWebIntelligenceCacheDocument
    var score: Double
  }

  func similarDocuments(query: String, limit: Int, excludingURL: String = "", target: [Float]? = nil) -> [SimilarityHit] {
    let embedder = AgentIOSWebFeatureHashEmbedder.standard
    let queryVector = target ?? embedder.embed(query)
    let excluded = excludingURL.isEmpty ? "" : canonicalURL(excludingURL)
    return read().documents.enumerated().filter { excluded.isEmpty || canonicalURL($0.element.url) != excluded }
      .map { offset, document -> (Int, SimilarityHit) in
        let vector: [Float]
        if document.embeddingModelID == embedder.modelID, let saved = document.vector,
          saved.count == embedder.dimensions, saved.allSatisfy(\.isFinite) { vector = saved }
        else { vector = embedder.embedDocument(title: document.title, content: document.content) }
        let score = (embedder.cosine(queryVector, vector) + 1) / 2
        return (offset, SimilarityHit(document: document, score: score))
      }.sorted {
        if $0.1.score != $1.1.score { return $0.1.score > $1.1.score }
        if $0.1.document.retrievedAtMillis != $1.1.document.retrievedAtMillis {
          return $0.1.document.retrievedAtMillis > $1.1.document.retrievedAtMillis
        }
        return $0.0 < $1.0
      }.prefix(max(1, min(limit, Self.maxDocuments))).map { $0.1 }
  }

  func stats() -> AgentMcpJSONObject {
    lock.lock()
    defer { lock.unlock() }
    guard let snapshot = readUnlocked(), let health = try? healthIndexUnlocked().records() else {
      return ["available": .bool(false), "status": .string("unavailable"), "encryption": .string("ios_keychain_aes_gcm")]
    }
    let now = nowMillis()
    return [
      "available": .bool(true),
      "learned_source_count": .int(Int64(snapshot.learnedSources?.count ?? 0)),
      "verified_learned_source_count": .int(Int64(snapshot.learnedSources?.filter { $0.status == "verified" }.count ?? 0)),
      "last_learning_status": .string(state.lastLearningStatus),
      "source_health_count": .int(Int64(health.count)),
      "source_circuits_open": .int(Int64(health.values.filter { $0.circuitState(now: now) == "open" }.count)),
      "cache_version": .int(Int64(snapshot.version)),
      "entry_count": .int(Int64(snapshot.documents.count)),
      "search_count": .int(Int64(snapshot.searchResponses?.count ?? 0)),
      "content_chars": .int(snapshot.documents.reduce(0) { $0 + Int64($1.content.count) }),
      "expired_count": .int(Int64(snapshot.documents.filter { $0.expiresAtMillis < now }.count)),
      "watch_count": .int(Int64(snapshot.watches.count)),
      "encryption": .string("ios_keychain_aes_gcm")
    ]
  }

  func clear(expiredOnly: Bool) -> AgentMcpJSONObject {
    var removed = 0
    var learnedRemoved = 0
    var searchesRemoved = 0
    let now = nowMillis()
    lock.lock()
    let committed: Bool
    if var snapshot = readUnlocked() {
      let before = snapshot.documents.count
      if expiredOnly {
        snapshot.documents.removeAll { $0.expiresAtMillis < now }
      } else {
        snapshot.documents.removeAll()
        state.generation = UUID()
        learnedRemoved = snapshot.learnedSources?.count ?? 0
        snapshot.learnedSources = []
      }
      let searchesBefore = snapshot.searchResponses?.count ?? 0
      if expiredOnly {
        snapshot.searchResponses?.removeAll { $0.expiresAtMillis <= now }
      } else {
        snapshot.searchResponses = []
      }
      searchesRemoved = searchesBefore - (snapshot.searchResponses?.count ?? 0)
      removed = before - snapshot.documents.count
      committed = writeUnlocked(snapshot)
      if !expiredOnly { state.lastLearningStatus = committed ? "cleared" : "failed_write" }
    } else {
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
    guard let snapshot = readUnlocked() else { return nil }
    return (snapshot.learnedSources ?? []).sorted {
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
    guard let snapshot = readUnlocked(), let health = try? healthIndexUnlocked().records() else { return nil }
    return (snapshot.learnedSources ?? [], health)
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
    guard var snapshot = readUnlocked() else { state.lastLearningStatus = "failed_read"; return false }
    var sources = Dictionary(uniqueKeysWithValues: (snapshot.learnedSources ?? []).map { ($0.sourceID, $0) })
    for observation in observations {
      sources[observation.sourceID] = AgentIOSWebSourceLearningPolicy.evolve(sources[observation.sourceID],
        observation: observation, now: nowMillis())
    }
    snapshot.learnedSources = Array(sources.values.sorted {
      $0.lastSeenAtMillis == $1.lastSeenAtMillis ? $0.sourceID < $1.sourceID : $0.lastSeenAtMillis > $1.lastSeenAtMillis
    }.prefix(AgentIOSWebSourceLearningPolicy.maximumSources))
    let committed = writeUnlocked(snapshot)
    state.lastLearningStatus = committed ? "saved" : "failed_write"
    return committed
  }

  @discardableResult
  func putWatch(_ watch: AgentIOSWebIntelligenceCacheWatch) -> Bool {
    mutate { snapshot in
      snapshot.watches.removeAll { $0.id == watch.id }
      snapshot.watches.append(watch)
      snapshot.watches.sort { $0.updatedAtMillis > $1.updatedAtMillis }
      if snapshot.watches.count > Self.maxWatches {
        snapshot.watches = Array(snapshot.watches.prefix(Self.maxWatches))
      }
    }
  }

  func watch(id: String) -> AgentIOSWebIntelligenceCacheWatch? {
    read().watches.first { $0.id == id }
  }

  func watches() -> [AgentIOSWebIntelligenceCacheWatch] {
    read().watches
  }

  func watchSnapshot() -> [AgentIOSWebIntelligenceCacheWatch]? {
    lock.lock()
    defer { lock.unlock() }
    return readUnlocked()?.watches
  }

  @discardableResult
  func removeWatch(id: String) -> Bool? {
    var removed = false
    let committed = mutate { snapshot in
      let before = snapshot.watches.count
      snapshot.watches.removeAll { $0.id == id }
      removed = before != snapshot.watches.count
    }
    return committed ? removed : nil
  }

  private func read() -> Snapshot {
    lock.lock()
    defer { lock.unlock() }
    return readUnlocked() ?? Snapshot()
  }

  private func mutate(_ body: (inout Snapshot) -> Void) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard var snapshot = readUnlocked() else { return false }
    body(&snapshot)
    return writeUnlocked(snapshot)
  }

  private func readUnlocked() -> Snapshot? {
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
          snapshot.documents.count <= Self.maxDocuments,
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

  private func writeUnlocked(_ snapshot: Snapshot) -> Bool {
    guard fileURL.isFileURL, let key = encryptionKey(createIfMissing: !fileManager.fileExists(atPath: fileURL.path)),
          let plaintext = try? JSONEncoder().encode(snapshot),
          let sealed = try? AES.GCM.seal(plaintext, using: key) else {
      return false
    }
    let nonce = sealed.nonce.withUnsafeBytes { Data($0) }
    guard let encoded = try? JSONEncoder().encode(EncryptedEnvelope(
      version: 1,
      nonce: nonce.base64EncodedString(),
      ciphertext: sealed.ciphertext.base64EncodedString(),
      tag: sealed.tag.base64EncodedString()
    )) else {
      return false
    }
    let directory = fileURL.deletingLastPathComponent()
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try writeFile(encoded, fileURL)
      return true
    } catch { return false }
  }

  private func encryptionKey(createIfMissing: Bool) -> SymmetricKey? {
    Self.keyLock.lock()
    defer { Self.keyLock.unlock() }
    if let encoded = secrets.string(account: Self.keyAccount) {
      guard let data = Data(base64Encoded: encoded), data.count == 32 else { return nil }
      return SymmetricKey(data: data)
    }
    guard createIfMissing, !fileManager.fileExists(atPath: Self.sourceHealthDatabaseURL(for: fileURL).path),
      secrets.string(account: healthImportAccount) == nil else { return nil }
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

  private func healthIndexUnlocked() throws -> AgentIOSWebSourceHealthDatabase {
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
      guard let snapshot = readUnlocked() else { throw AgentIOSWebSourceHealthDatabase.Failure.corrupt }
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
