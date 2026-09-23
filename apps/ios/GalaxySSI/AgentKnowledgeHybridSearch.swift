import CryptoKit
import Foundation
import USearch

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
  private struct IndexedEntry {
    var checkpoint: AgentKnowledgeVectorCheckpoint
    var item: AgentKnowledgeItem
  }

  private struct Cache {
    var index: USearchIndex
    var entriesByLabel: [UInt64: IndexedEntry]
    var signature: String
    var builtAtMillis: Int64
  }

  private let database: AgentKnowledgeDatabase
  private let runtime: GalaxySSIEmbeddingRuntime
  private let provenance: AgentKnowledgeVectorProvenance
  private let queue = DispatchQueue(label: "com.galaxyssi.knowledge-hnsw", qos: .utility)
  private let ttlMillis: Int64
  private let admission: AgentKnowledgeRetrievalAdmission
  private var cache: Cache?

  init(
    database: AgentKnowledgeDatabase,
    runtime: GalaxySSIEmbeddingRuntime,
    provenance: AgentKnowledgeVectorProvenance,
    ttlMillis: Int64 = 300_000,
    admission: AgentKnowledgeRetrievalAdmission = AgentKnowledgeRetrievalAdmission()
  ) {
    self.database = database
    self.runtime = runtime
    self.provenance = provenance
    self.ttlMillis = max(ttlMillis, 1_000)
    self.admission = admission
  }

  func search(
    query: String,
    lexicalHits: [AgentKnowledgeHit],
    limit: Int = 24,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) async throws -> [AgentKnowledgeHit] {
    guard let lease = admission.acquire() else {
      return Array(lexicalHits.prefix(max(limit, 0)))
    }
    defer { lease.release() }
    let queryVector = try await runtime.embed(query)
    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          let semantic = try semanticHits(vector: queryVector, limit: max(limit * 4, 32), nowMillis: nowMillis)
          let fused = AgentKnowledgeHybridRanking.reciprocalRankFusion(
            lexicalIds: lexicalHits.map(\.item.id),
            semanticIds: semantic.map(\.item.id)
          )
          let lexicalById = Dictionary(uniqueKeysWithValues: lexicalHits.map { ($0.item.id, $0) })
          let semanticById = Dictionary(semantic.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })
          let results = fused.prefix(max(limit, 0)).compactMap { ranked -> AgentKnowledgeHit? in
            guard let hit = lexicalById[ranked.id] ?? semanticById[ranked.id] else { return nil }
            return AgentKnowledgeHit(
              item: hit.item,
              score: min(ranked.score * 30, 1),
              excerpt: hit.excerpt,
              matchedTerms: hit.matchedTerms
            )
          }
          continuation.resume(returning: results)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func clearTransientIndex() {
    queue.async { [weak self] in self?.cache = nil }
  }

  private func semanticHits(
    vector: [Float],
    limit: Int,
    nowMillis: Int64
  ) throws -> [AgentKnowledgeHit] {
    let cache = try currentCache(nowMillis: nowMillis)
    guard !cache.entriesByLabel.isEmpty, vector.count == provenance.dimensions else { return [] }
    let (labels, distances) = try cache.index.search(
      vector: vector,
      count: min(limit, cache.entriesByLabel.count)
    )
    let currentItems = try database.all()
    let currentById = Dictionary(uniqueKeysWithValues: currentItems.map { ($0.id, $0) })
    return zip(labels, distances).compactMap { label, distance in
      guard let entry = cache.entriesByLabel[label],
            let current = currentById[entry.item.id],
            AgentKnowledgeVectorCheckpoint.sourceRevision(for: current) == entry.checkpoint.sourceRevision else {
        return nil
      }
      return AgentKnowledgeHit(
        item: current,
        score: max(0, min(1, 1 - Double(distance))),
        excerpt: String(current.content.prefix(360)),
        matchedTerms: []
      )
    }
  }

  private func currentCache(nowMillis: Int64) throws -> Cache {
    let catalog = try loadCatalog()
    let signature = catalogSignature(catalog.map(\.checkpoint))
    if let cache,
       cache.signature == signature,
       nowMillis - cache.builtAtMillis <= ttlMillis {
      return cache
    }
    let bytes = catalog.count * provenance.dimensions * MemoryLayout<Float>.size
    guard bytes <= 64 * 1_024 * 1_024 else { throw AgentKnowledgeDatabaseError.unavailable }
    let index = try USearchIndex.make(
      metric: .cos,
      dimensions: UInt32(provenance.dimensions),
      connectivity: 16,
      quantization: .f32
    )
    try index.reserve(UInt32(max(catalog.count, 1)))
    var entries: [UInt64: IndexedEntry] = [:]
    for (offset, entry) in catalog.enumerated() {
      let label = UInt64(offset + 1)
      try index.add(key: label, vector: entry.checkpoint.vector)
      entries[label] = entry
    }
    let next = Cache(index: index, entriesByLabel: entries, signature: signature, builtAtMillis: nowMillis)
    cache = next
    return next
  }

  private func loadCatalog() throws -> [IndexedEntry] {
    let items = try database.all()
    let itemsById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    var offset = 0
    var output: [IndexedEntry] = []
    while true {
      let page = try database.vectorCatalog(
        modelSHA256: provenance.modelSHA256,
        offset: offset,
        limit: 256
      )
      for checkpoint in page {
        guard checkpoint.provenance == provenance,
              let item = itemsById[checkpoint.itemId],
              AgentKnowledgeVectorCheckpoint.sourceRevision(for: item) == checkpoint.sourceRevision else {
          continue
        }
        output.append(IndexedEntry(checkpoint: checkpoint, item: item))
      }
      if page.count < 256 { break }
      offset += page.count
    }
    return output
  }

  private func catalogSignature(_ checkpoints: [AgentKnowledgeVectorCheckpoint]) -> String {
    let material = checkpoints.map {
      "\($0.id)|\($0.sourceRevision)|\($0.updatedAtMillis)"
    }.joined(separator: "\n")
    return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
