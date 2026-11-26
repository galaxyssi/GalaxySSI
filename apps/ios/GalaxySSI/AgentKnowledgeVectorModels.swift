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
  var sourceStartUTF16: Int? = nil
  var sourceEndUTF16: Int? = nil

  var id: String { "\(itemId):\(chunkIndex):\(provenance.modelSHA256)" }

  init(
    itemId: String,
    sourceRevision: String,
    chunkIndex: Int,
    chunkCount: Int = 1,
    vector: [Float],
    provenance: AgentKnowledgeVectorProvenance,
    updatedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    sourceStartUTF16: Int? = nil,
    sourceEndUTF16: Int? = nil
  ) {
    self.itemId = String(itemId.prefix(160))
    self.sourceRevision = sourceRevision.lowercased()
    self.chunkIndex = max(chunkIndex, 0)
    self.chunkCount = max(chunkCount, 1)
    self.vector = vector
    self.provenance = provenance
    self.updatedAtMillis = max(updatedAtMillis, 0)
    self.sourceStartUTF16 = sourceStartUTF16
    self.sourceEndUTF16 = sourceEndUTF16
  }

  var isValid: Bool {
    sourceRangeIsValid && !itemId.isEmpty && sourceRevision.count == 64 && chunkCount > 0 && chunkIndex >= 0 && chunkIndex < chunkCount &&
      provenance.modelSHA256.count == 64 &&
      vector.count == provenance.dimensions && vector.allSatisfy(\.isFinite) &&
      abs(vector.reduce(0.0) { $0 + Double($1) * Double($1) } - 1) < 0.01
  }

  private var sourceRangeIsValid: Bool {
    if sourceStartUTF16 == nil && sourceEndUTF16 == nil { return true }
    guard let start = sourceStartUTF16, let end = sourceEndUTF16 else { return false }
    return start >= 0 && start < end
  }

  func validatedSourceRange(in item: AgentKnowledgeItem) -> Range<String.Index>? {
    guard item.id == itemId, Self.sourceRevision(for: item) == sourceRevision,
      let start = sourceStartUTF16, let end = sourceEndUTF16, start >= 0, start < end,
      end <= item.content.utf16.count else { return nil }
    if let unit = item.content.utf16.dropFirst(start).first, (0xdc00...0xdfff).contains(unit) { return nil }
    if let unit = item.content.utf16.dropFirst(end).first, (0xdc00...0xdfff).contains(unit) { return nil }
    return Range(NSRange(location: start, length: end - start), in: item.content)
  }

  static func locateSourceRange(chunk: String, content: String, afterUTF16: Int) -> NSRange? {
    let count = content.utf16.count
    guard !chunk.isEmpty, afterUTF16 >= 0, afterUTF16 <= count,
      let searchRange = Range(NSRange(location: afterUTF16, length: count - afterUTF16), in: content),
      let found = content.range(of: chunk, options: .literal, range: searchRange) else { return nil }
    return NSRange(found, in: content)
  }

  static func sourceRevision(for item: AgentKnowledgeItem) -> String {
    let data = (try? JSONEncoder.galaxySSI.encode(item)) ?? Data()
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

enum AgentKnowledgeVectorStorageError: Error {
  case invalidPayload
  case unsupportedVersion
}

enum AgentKnowledgeVectorStorage {
  private static let version = 2
  private static let minimumCompactDimensions = 128
  private static let maximumDimensions = 8_192
  private static let maximumSquaredError = 0.0001

  enum Codec: String, Codable {
    case float32
    case scalar8
    case float16
  }

  private struct Envelope: Codable {
    var version: Int
    var codec: Codec
    var itemId: String
    var sourceRevision: String
    var chunkIndex: Int
    var chunkCount: Int
    var vectorPayload: Data
    var provenance: AgentKnowledgeVectorProvenance
    var updatedAtMillis: Int64
    var sourceStartUTF16: Int? = nil
    var sourceEndUTF16: Int? = nil
  }

  static func encode(_ checkpoint: AgentKnowledgeVectorCheckpoint) throws -> Data {
    guard checkpoint.isValid else { throw AgentKnowledgeVectorStorageError.invalidPayload }
    let packed = pack(checkpoint.vector)
    return try JSONEncoder.galaxySSI.encode(Envelope(
      version: version,
      codec: packed.codec,
      itemId: checkpoint.itemId,
      sourceRevision: checkpoint.sourceRevision,
      chunkIndex: checkpoint.chunkIndex,
      chunkCount: checkpoint.chunkCount,
      vectorPayload: packed.payload,
      provenance: checkpoint.provenance,
      updatedAtMillis: checkpoint.updatedAtMillis,
      sourceStartUTF16: checkpoint.sourceStartUTF16,
      sourceEndUTF16: checkpoint.sourceEndUTF16
    ))
  }

  static func decode(_ data: Data) throws -> AgentKnowledgeVectorCheckpoint {
    if let envelope = try? JSONDecoder.galaxySSI.decode(Envelope.self, from: data) {
      guard envelope.version == version else {
        throw AgentKnowledgeVectorStorageError.unsupportedVersion
      }
      let vector = try unpack(
        codec: envelope.codec,
        payload: envelope.vectorPayload,
        dimensions: envelope.provenance.dimensions
      )
      let checkpoint = AgentKnowledgeVectorCheckpoint(
        itemId: envelope.itemId,
        sourceRevision: envelope.sourceRevision,
        chunkIndex: envelope.chunkIndex,
        chunkCount: envelope.chunkCount,
        vector: vector,
        provenance: envelope.provenance,
        updatedAtMillis: envelope.updatedAtMillis,
        sourceStartUTF16: envelope.sourceStartUTF16,
        sourceEndUTF16: envelope.sourceEndUTF16
      )
      guard checkpoint.isValid else { throw AgentKnowledgeVectorStorageError.invalidPayload }
      return checkpoint
    }
    let legacy = try JSONDecoder.galaxySSI.decode(AgentKnowledgeVectorCheckpoint.self, from: data)
    guard legacy.isValid else { throw AgentKnowledgeVectorStorageError.invalidPayload }
    return legacy
  }

  static func codec(in data: Data) -> Codec? {
    try? JSONDecoder.galaxySSI.decode(Envelope.self, from: data).codec
  }

  private static func pack(_ vector: [Float]) -> (codec: Codec, payload: Data) {
    if vector.count >= minimumCompactDimensions,
       let scalar = scalar8Payload(vector),
       reconstructionError(vector, decodeScalar8(scalar)) <= maximumSquaredError {
      return (.scalar8, scalar)
    }
    if vector.count >= minimumCompactDimensions {
      let half = float16Payload(vector)
      if reconstructionError(vector, decodeFloat16(half)) <= maximumSquaredError {
        return (.float16, half)
      }
    }
    return (.float32, float32Payload(vector))
  }

  private static func unpack(codec: Codec, payload: Data, dimensions: Int) throws -> [Float] {
    guard (1...maximumDimensions).contains(dimensions) else {
      throw AgentKnowledgeVectorStorageError.invalidPayload
    }
    let vector: [Float]
    switch codec {
    case .scalar8:
      guard dimensions >= minimumCompactDimensions, payload.count == dimensions else {
        throw AgentKnowledgeVectorStorageError.invalidPayload
      }
      vector = decodeScalar8(payload)
    case .float16:
      guard dimensions >= minimumCompactDimensions, payload.count == dimensions * 2 else {
        throw AgentKnowledgeVectorStorageError.invalidPayload
      }
      vector = decodeFloat16(payload)
    case .float32:
      guard payload.count == dimensions * 4 else {
        throw AgentKnowledgeVectorStorageError.invalidPayload
      }
      vector = decodeFloat32(payload)
    }
    guard vector.count == dimensions, vector.allSatisfy(\.isFinite) else {
      throw AgentKnowledgeVectorStorageError.invalidPayload
    }
    return vector
  }

  private static func scalar8Payload(_ vector: [Float]) -> Data? {
    guard let maximum = vector.map({ abs($0) }).max(), maximum.isFinite, maximum > 0 else {
      return nil
    }
    return Data(vector.map { value in
      let scaled = min(max(value / maximum, -1), 1)
      return UInt8(min(max(Int(((scaled + 1) * 127.5).rounded()), 0), 255))
    })
  }

  private static func decodeScalar8(_ payload: Data) -> [Float] {
    normalized(payload.map { Float($0) * (2 / 255) - 1 })
  }

  private static func float16Payload(_ vector: [Float]) -> Data {
    var payload = Data(capacity: vector.count * 2)
    for value in vector {
      appendLittleEndian(Float16(value).bitPattern, to: &payload)
    }
    return payload
  }

  private static func decodeFloat16(_ payload: Data) -> [Float] {
    let bytes = [UInt8](payload)
    let values = stride(from: 0, to: bytes.count, by: 2).map { offset in
      Float(Float16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8))
    }
    return normalized(values)
  }

  private static func float32Payload(_ vector: [Float]) -> Data {
    var payload = Data(capacity: vector.count * 4)
    for value in vector {
      appendLittleEndian(value.bitPattern, to: &payload)
    }
    return payload
  }

  private static func decodeFloat32(_ payload: Data) -> [Float] {
    let bytes = [UInt8](payload)
    return stride(from: 0, to: bytes.count, by: 4).map { offset in
      let bits = UInt32(bytes[offset]) |
        UInt32(bytes[offset + 1]) << 8 |
        UInt32(bytes[offset + 2]) << 16 |
        UInt32(bytes[offset + 3]) << 24
      return Float(bitPattern: bits)
    }
  }

  private static func normalized(_ vector: [Float]) -> [Float] {
    let norm = sqrt(vector.reduce(0.0) { $0 + Double($1) * Double($1) })
    guard norm.isFinite, norm > 0 else { return [] }
    return vector.map { Float(Double($0) / norm) }
  }

  private static func reconstructionError(_ original: [Float], _ decoded: [Float]) -> Double {
    guard original.count == decoded.count else { return .infinity }
    return zip(original, decoded).reduce(0.0) { result, values in
      let delta = Double(values.0) - Double(values.1)
      return result + delta * delta
    }
  }

  private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    Swift.withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
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
  // Complete legacy records without a publication must be republished, not
  // mistaken for a resumable producer. Only an exact, incomplete source survives.
  static func resumableCheckpoints(_ checkpoints: [AgentKnowledgeVectorCheckpoint], item: AgentKnowledgeItem,
    provenance: AgentKnowledgeVectorProvenance, chunks: [String]) -> [Int: AgentKnowledgeVectorCheckpoint] {
    guard !checkpoints.isEmpty, checkpoints.count < chunks.count else { return [:] }
    let revision = AgentKnowledgeVectorCheckpoint.sourceRevision(for: item)
    var offsets: [NSRange] = [], cursor = 0
    for chunk in chunks {
      guard let range = AgentKnowledgeVectorCheckpoint.locateSourceRange(chunk: chunk, content: item.content,
        afterUTF16: cursor) else { return [:] }
      offsets.append(range)
      cursor = range.location + range.length
    }
    var result: [Int: AgentKnowledgeVectorCheckpoint] = [:]
    for checkpoint in checkpoints {
      let ordinal = checkpoint.chunkIndex
      guard checkpoint.isValid, checkpoint.itemId == item.id, checkpoint.sourceRevision == revision,
        checkpoint.provenance == provenance, checkpoint.chunkCount == chunks.count,
        offsets.indices.contains(ordinal), result[ordinal] == nil,
        checkpoint.sourceStartUTF16 == offsets[ordinal].location,
        checkpoint.sourceEndUTF16 == offsets[ordinal].location + offsets[ordinal].length else { return [:] }
      result[ordinal] = checkpoint
    }
    return result
  }

  private let database: AgentKnowledgeDatabase
  private let runtime: GalaxySSIEmbeddingRuntime
  private let provenance: AgentKnowledgeVectorProvenance
  private let activeCheck: () throws -> Void

  init(
    database: AgentKnowledgeDatabase,
    runtime: GalaxySSIEmbeddingRuntime,
    provenance: AgentKnowledgeVectorProvenance,
    activeCheck: @escaping () throws -> Void = {}
  ) {
    self.database = database
    self.runtime = runtime
    self.provenance = provenance
    self.activeCheck = activeCheck
  }

  func indexPending(pageSize: Int = 32, maximumChunks: Int = .max) async throws -> Int {
    var remainingChunks = max(maximumChunks, 0)
    let pending = try database.pendingVectorItems(
      modelSHA256: provenance.modelSHA256,
      limit: min(max(pageSize, 1), 64)
    )
    var indexed = 0
    for item in pending {
      try Task.checkCancellation()
      try activeCheck()
      let chunks = try await AgentKnowledgeEmbeddingChunker.chunks(
        item.content,
        maximumTokens: provenance.contextTokens,
        tokenCount: {
          try self.activeCheck()
          let count = try await self.runtime.tokenCount($0)
          try self.activeCheck()
          return count
        }
      )
      try Task.checkCancellation()
      try activeCheck()
      let existing = try database.vectorCheckpoints(itemId: item.id, modelSHA256: provenance.modelSHA256)
      let resumed = Self.resumableCheckpoints(existing, item: item, provenance: provenance, chunks: chunks)
      if resumed.isEmpty,
        !database.clearVectorCheckpoints(itemId: item.id, modelSHA256: provenance.modelSHA256) {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      var sourceCursor = 0
      for (index, chunk) in chunks.enumerated() {
        try Task.checkCancellation()
        try activeCheck()
        guard let offsets = AgentKnowledgeVectorCheckpoint.locateSourceRange(
          chunk: chunk, content: item.content, afterUTF16: sourceCursor) else { throw AgentKnowledgeDatabaseError.corruptRecord }
        sourceCursor = offsets.location + offsets.length
        if resumed[index] != nil { continue }
        guard remainingChunks > 0 else { return indexed }
        let vector = try await runtime.embed(chunk)
        try Task.checkCancellation()
        try activeCheck()
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
          ),
          sourceStartUTF16: offsets.location,
          sourceEndUTF16: offsets.location + offsets.length
        )
        guard database.storeVectorCheckpoint(checkpoint) else {
          throw AgentKnowledgeDatabaseError.corruptRecord
        }
        remainingChunks -= 1
      }
      indexed += 1
    }
    return indexed
  }
}
