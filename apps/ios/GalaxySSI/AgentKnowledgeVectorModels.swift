import CryptoKit
import Foundation

struct AgentKnowledgeVectorProvenance: Codable, Equatable {
  var modelSHA256: String
  var dimensions: Int
  var contextTokens: Int
  var chunkingContract: String

  init(modelSHA256: String, dimensions: Int, contextTokens: Int, chunkingContract: String) {
    self.modelSHA256 = modelSHA256.lowercased()
    self.dimensions = max(dimensions, 1)
    self.contextTokens = max(contextTokens, 32)
    self.chunkingContract = String(chunkingContract.prefix(160))
  }
}

struct AgentKnowledgeVectorCheckpoint: Codable, Equatable, Identifiable {
  var itemId: String
  var sourceRevision: String
  var chunkIndex: Int
  var chunkCount: Int
  var vector: [Float]
  var provenance: AgentKnowledgeVectorProvenance
  var updatedAtMillis: Int64

  var id: String { "\(itemId):\(chunkIndex):\(provenance.modelSHA256)" }

  init(
    itemId: String,
    sourceRevision: String,
    chunkIndex: Int,
    chunkCount: Int = 1,
    vector: [Float],
    provenance: AgentKnowledgeVectorProvenance,
    updatedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    self.itemId = String(itemId.prefix(160))
    self.sourceRevision = sourceRevision.lowercased()
    self.chunkIndex = max(chunkIndex, 0)
    self.chunkCount = max(chunkCount, 1)
    self.vector = vector
    self.provenance = provenance
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  var isValid: Bool {
    !itemId.isEmpty && sourceRevision.count == 64 && chunkIndex < chunkCount &&
      provenance.modelSHA256.count == 64 &&
      vector.count == provenance.dimensions && vector.allSatisfy(\.isFinite) &&
      abs(vector.reduce(0.0) { $0 + Double($1) * Double($1) } - 1) < 0.01
  }

  static func sourceRevision(for item: AgentKnowledgeItem) -> String {
    let data = (try? JSONEncoder.galaxySSI.encode(item)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

enum AgentKnowledgeEmbeddingChunker {
  static let contract = "llama-token-window-v1"

  static func chunks(
    _ text: String,
    maximumTokens: Int,
    tokenCount: (String) async throws -> Int
  ) async throws -> [String] {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return [] }
    guard try await tokenCount(clean) > maximumTokens else { return [clean] }
    var remaining = clean[...]
    var chunks: [String] = []
    while !remaining.isEmpty {
      var low = 1
      var high = remaining.count
      var accepted = 0
      while low <= high {
        let middle = low + (high - low) / 2
        let end = remaining.index(remaining.startIndex, offsetBy: middle)
        let candidate = String(remaining[..<end])
        if try await tokenCount(candidate) <= maximumTokens {
          accepted = middle
          low = middle + 1
        } else {
          high = middle - 1
        }
      }
      guard accepted > 0 else { throw GalaxySSIEmbeddingRuntimeError.inferenceFailed("Unable to fit input in embedding window") }
      var end = remaining.index(remaining.startIndex, offsetBy: accepted)
      if end < remaining.endIndex,
         let boundary = remaining[..<end].lastIndex(where: { $0.isWhitespace }) {
        end = remaining.index(after: boundary)
      }
      let chunk = String(remaining[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !chunk.isEmpty { chunks.append(chunk) }
      remaining = remaining[end...].drop(while: { $0.isWhitespace })
    }
    return chunks
  }
}

final class AgentKnowledgeVectorIndexer {
  private let database: AgentKnowledgeDatabase
  private let runtime: GalaxySSIEmbeddingRuntime
  private let provenance: AgentKnowledgeVectorProvenance

  init(
    database: AgentKnowledgeDatabase,
    runtime: GalaxySSIEmbeddingRuntime,
    provenance: AgentKnowledgeVectorProvenance
  ) {
    self.database = database
    self.runtime = runtime
    self.provenance = provenance
  }

  func indexPending(pageSize: Int = 32) async throws -> Int {
    let pending = try database.pendingVectorItems(
      modelSHA256: provenance.modelSHA256,
      limit: min(max(pageSize, 1), 64)
    )
    var indexed = 0
    for item in pending {
      try Task.checkCancellation()
      guard database.clearVectorCheckpoints(itemId: item.id, modelSHA256: provenance.modelSHA256) else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      let chunks = try await AgentKnowledgeEmbeddingChunker.chunks(
        item.content,
        maximumTokens: provenance.contextTokens,
        tokenCount: { try await self.runtime.tokenCount($0) }
      )
      for (index, chunk) in chunks.enumerated() {
        try Task.checkCancellation()
        let vector = try await runtime.embed(chunk)
        let checkpoint = AgentKnowledgeVectorCheckpoint(
          itemId: item.id,
          sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
          chunkIndex: index,
          chunkCount: chunks.count,
          vector: vector,
          provenance: AgentKnowledgeVectorProvenance(
            modelSHA256: provenance.modelSHA256,
            dimensions: vector.count,
            contextTokens: provenance.contextTokens,
            chunkingContract: provenance.chunkingContract
          )
        )
        guard database.storeVectorCheckpoint(checkpoint) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
      }
      indexed += 1
    }
    return indexed
  }
}
