import Foundation

enum AgentKnowledgeHybridRanking {
  static func reciprocalRankFusion(
    lexicalIds: [String],
    semanticIds: [String],
    rankConstant: Double = 60
  ) -> [(id: String, score: Double)] {
    var scores: [String: Double] = [:]
    for (index, id) in lexicalIds.enumerated() where !id.isEmpty {
      scores[id, default: 0] += 1 / (rankConstant + Double(index + 1))
    }
    for (index, id) in semanticIds.enumerated() where !id.isEmpty {
      scores[id, default: 0] += 1 / (rankConstant + Double(index + 1))
    }
    return scores.map { (id: $0.key, score: $0.value) }.sorted {
      $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
    }
  }
}

final class AgentKnowledgeRetrievalAdmission {
  final class Lease {
    private let releaseHandler: () -> Void
    private let lock = NSLock()
    private var released = false

    fileprivate init(release: @escaping () -> Void) {
      releaseHandler = release
    }

    func release() {
      lock.lock()
      guard !released else {
        lock.unlock()
        return
      }
      released = true
      lock.unlock()
      releaseHandler()
    }

    deinit { release() }
  }

  private let semaphore = DispatchSemaphore(value: 1)

  func acquire(timeoutMillis: Int = 25) -> Lease? {
    let timeout = DispatchTime.now() + .milliseconds(max(timeoutMillis, 0))
    guard semaphore.wait(timeout: timeout) == .success else { return nil }
    let ownedSemaphore = semaphore
    return Lease { ownedSemaphore.signal() }
  }
}

final class AgentKnowledgeSemanticSearch {
  private let database: AgentKnowledgeDatabase
  private let runtime: GalaxySSIEmbeddingRuntime
  private let provenance: AgentKnowledgeVectorProvenance
  private let queue = DispatchQueue(label: "com.galaxyssi.knowledge-native", qos: .utility)
  private let ttlMillis: Int64
  private let admission: AgentKnowledgeRetrievalAdmission
  private let index: AgentKnowledgeNativeIndex
  private var lastAccessMillis: Int64 = 0
  private let requestLock = NSLock()
  private var activeRequest: UUID?
  private var cancelledRequests = Set<UUID>()

  init(database: AgentKnowledgeDatabase, runtime: GalaxySSIEmbeddingRuntime,
    provenance: AgentKnowledgeVectorProvenance, ttlMillis: Int64 = 30_000,
    admission: AgentKnowledgeRetrievalAdmission = AgentKnowledgeRetrievalAdmission()) {
    self.database = database
    self.runtime = runtime
    self.provenance = provenance
    self.ttlMillis = max(ttlMillis, 1_000)
    self.admission = admission
    index = AgentKnowledgeNativeIndex(database: database, provenance: provenance)
  }

  func search(query: String, lexicalHits: [AgentKnowledgeHit], limit: Int = 24,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) async throws -> [AgentKnowledgeHit] {
    let limit = min(max(limit, 0), 256)
    guard limit > 0 else { return [] }
    guard let token = database.nativeFiles.activeToken() else { throw CancellationError() }
    guard let lease = admission.acquire() else {
      return try await freshLexical(lexicalHits, limit: limit, token: token)
    }
    defer { lease.release() }
    let requestId = UUID()
    defer { finishRequest(requestId) }
    return try await withTaskCancellationHandler(operation: {
      try Task.checkCancellation()
      let queryVector = try await runtime.embed(query)
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        queue.async { [self] in
          if isCancelled(requestId) {
            finishRequest(requestId)
            continuation.resume(throwing: CancellationError())
            return
          }
          beginRequest(requestId)
          defer { index.cancellationCheck = { false } }
          index.cancellationCheck = { [weak self] in self?.isCancelled(requestId) ?? true }
          do {
            try active(token)
            expireIfIdle(nowMillis: nowMillis)
            let ready = try index.advance(token: token)
            let semantic: [AgentKnowledgeHit]
            if ready { semantic = try index.search(queryVector, count: min(max(limit * 4, 32), 256), token: token) }
            else { semantic = [] }
            let stamp = try database.vectorFeedStamp(modelSHA256: provenance.modelSHA256)
            if ready, index.readyStamp != stamp { throw AgentKnowledgeDatabaseError.staleCursor }
            let lexical = try database.validatedLexicalHits(Array(lexicalHits.prefix(256)),
              stamp: stamp, modelSHA256: provenance.modelSHA256)
            let fused = AgentKnowledgeHybridRanking.reciprocalRankFusion(
              lexicalIds: lexical.map(\.item.id), semanticIds: semantic.map(\.item.id))
            let lexicalById = Dictionary(lexical.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
            let semanticById = Dictionary(semantic.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
            let results = fused.prefix(limit).compactMap { ranked -> AgentKnowledgeHit? in
              guard let hit = lexicalById[ranked.id] ?? semanticById[ranked.id] else { return nil }
              return AgentKnowledgeHit(item: hit.item, score: min(ranked.score * 30, 1),
                excerpt: hit.excerpt, matchedTerms: hit.matchedTerms)
            }
            guard try database.vectorFeedStamp(modelSHA256: provenance.modelSHA256) == stamp else {
              throw AgentKnowledgeDatabaseError.staleCursor
            }
            try active(token)
            if finishRequest(requestId) {
              index.close()
              continuation.resume(throwing: CancellationError())
            } else { continuation.resume(returning: results) }
          } catch {
            if finishRequest(requestId) {
              index.close()
              continuation.resume(throwing: CancellationError())
            } else { continuation.resume(throwing: error) }
          }
        }
      }
    }, onCancel: { self.cancelRequest(requestId) })
  }

  // True means another bounded replay slice is required, not that replay failed.
  func advanceReplay() async throws -> Bool {
    guard let token = database.nativeFiles.activeToken() else { return false }
    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          try active(token)
          expireIfIdle(nowMillis: Int64(Date().timeIntervalSince1970 * 1_000))
          _ = try index.advance(token: token)
          try active(token)
          continuation.resume(returning: index.needsReplay)
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  func clearTransientIndex() {
    database.nativeFiles.invalidate()
    queue.async { [weak self] in self?.index.close() }
  }

  private func freshLexical(_ hits: [AgentKnowledgeHit], limit: Int, token: UInt64) async throws -> [AgentKnowledgeHit] {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          let stamp = try database.vectorFeedStamp(modelSHA256: provenance.modelSHA256)
          let fresh = try database.validatedLexicalHits(Array(hits.prefix(256)), stamp: stamp, modelSHA256: provenance.modelSHA256)
          guard try database.vectorFeedStamp(modelSHA256: provenance.modelSHA256) == stamp else {
            throw AgentKnowledgeDatabaseError.staleCursor
          }
          try active(token)
          continuation.resume(returning: Array(fresh.prefix(limit)))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func active(_ token: UInt64) throws {
    guard database.nativeFiles.activeToken() == token else { throw CancellationError() }
  }

  private func expireIfIdle(nowMillis: Int64) {
    if lastAccessMillis > 0, nowMillis >= lastAccessMillis, nowMillis - lastAccessMillis > ttlMillis { index.close() }
    lastAccessMillis = max(nowMillis, 0)
  }

  private func beginRequest(_ id: UUID) {
    requestLock.lock()
    activeRequest = id
    requestLock.unlock()
  }

  private func isCancelled(_ id: UUID) -> Bool {
    requestLock.lock()
    defer { requestLock.unlock() }
    return cancelledRequests.contains(id)
  }

  private func cancelRequest(_ id: UUID) {
    requestLock.lock()
    cancelledRequests.insert(id)
    if activeRequest == id { index.cancelCurrentSession() }
    requestLock.unlock()
  }

  @discardableResult
  private func finishRequest(_ id: UUID) -> Bool {
    requestLock.lock()
    defer { requestLock.unlock() }
    if activeRequest == id { activeRequest = nil }
    return cancelledRequests.remove(id) != nil
  }
}
