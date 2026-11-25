import Foundation
import GalaxySSIMemory

// Synchronous borrows only. Rust owns operation serialization and handle retirement.
final class AgentKnowledgeNativeBridge {
  private let lock = NSLock()
  private var handle: Int64 = 0
  private let dimensions: Int

  init(directory: URL, key: Data, identity: Data, epoch: String, dimensions: Int,
    shards: Int = 4, cacheBytes: Int = 16 * 1_024 * 1_024, root: [Float]? = nil) throws {
    guard directory.isFileURL, key.count == 32, identity.count == 32,
      (1...8_192).contains(dimensions), (1...64).contains(shards),
      (1...(256 * 1_024 * 1_024)).contains(cacheBytes),
      root == nil || (root?.count == dimensions && root?.allSatisfy(\.isFinite) == true) else {
      throw AgentKnowledgeNativeError.invalidRecord
    }
    self.dimensions = dimensions
    var configuration = GSMemoryOpenConfig()
    var rootVector = root ?? []
    defer {
      withUnsafeMutableBytes(of: &configuration) { bytes in
        _ = bytes.initializeMemory(as: UInt8.self, repeating: 0)
      }
      for index in rootVector.indices { rootVector[index] = 0 }
    }
    configuration.abi_version = 1
    configuration.dimensions = UInt32(dimensions)
    configuration.shards = UInt32(shards)
    configuration.cache_bytes = UInt64(cacheBytes)
    withUnsafeMutableBytes(of: &configuration.key) { $0.copyBytes(from: key) }
    withUnsafeMutableBytes(of: &configuration.identity) { $0.copyBytes(from: identity) }
    let epochBytes = try AgentKnowledgeNativeWire.epoch(epoch)
    withUnsafeMutableBytes(of: &configuration.epoch) { $0.copyBytes(from: epochBytes) }
    let path = Data(directory.path.utf8)
    var opened: Int64 = 0
    let status = path.withUnsafeBytes { pathBytes in
      rootVector.withUnsafeBufferPointer { rootBytes in
        gs_memory_open(pathBytes.bindMemory(to: UInt8.self).baseAddress, path.count, &configuration,
          root == nil ? nil : rootBytes.baseAddress, rootVector.count, &opened)
      }
    }
    guard status == 0, opened > 0 else {
      if opened > 0 { _ = gs_memory_close(opened) }
      throw AgentKnowledgeNativeError.nativeFailure
    }
    handle = opened
  }

  deinit { close() }

  func checkpoint() throws -> AgentKnowledgeNativeCheckpoint {
    try output(capacity: 208, call: { gs_memory_checkpoint($0, $1, $2, $3) }, decode: AgentKnowledgeNativeWire.checkpoint)
  }

  func begin(_ event: AgentKnowledgeNativeEvent, skip: Bool = false) throws -> AgentKnowledgeNativeCheckpoint {
    var encoded = try AgentKnowledgeNativeWire.event(event)
    defer { encoded.wipeSensitive() }
    return try encoded.withUnsafeBytes { eventBytes in
      try output(capacity: 208, call: { id, bytes, capacity, written in
        gs_memory_begin(id, eventBytes.bindMemory(to: UInt8.self).baseAddress, encoded.count,
          skip ? 1 : 0, bytes, capacity, written)
      }, decode: AgentKnowledgeNativeWire.checkpoint)
    }
  }

  func append(_ page: AgentKnowledgeVectorReplayPage) throws -> AgentKnowledgeNativeCheckpoint {
    guard (1...64).contains(page.checkpoints.count), page.event.operation == .ready else {
      throw AgentKnowledgeNativeError.invalidRecord
    }
    var metadata: [UInt64] = [], vectors: [Float] = []
    defer {
      for index in metadata.indices { metadata[index] = 0 }
      for index in vectors.indices { vectors[index] = 0 }
    }
    let first = page.checkpoints[0].chunkIndex
    for (offset, checkpoint) in page.checkpoints.enumerated() {
      let (ordinal, overflow) = first.addingReportingOverflow(offset)
      guard !overflow, checkpoint.isValid, checkpoint.chunkIndex >= 0,
        checkpoint.provenance.dimensions == dimensions,
        checkpoint.provenance == page.checkpoints[0].provenance,
        checkpoint.itemId == page.checkpoints[0].itemId,
        checkpoint.sourceRevision == page.checkpoints[0].sourceRevision,
        checkpoint.chunkCount == page.event.chunkCount, checkpoint.chunkIndex == ordinal,
        let start = checkpoint.sourceStartUTF16, let end = checkpoint.sourceEndUTF16 else {
        throw AgentKnowledgeNativeError.invalidRecord
      }
      metadata.append(contentsOf: [UInt64(checkpoint.chunkIndex), UInt64(start), UInt64(end)])
      vectors.append(contentsOf: checkpoint.vector)
    }
    var encoded = try AgentKnowledgeNativeWire.event(AgentKnowledgeNativeEvent(change: page.event))
    defer { encoded.wipeSensitive() }
    return try encoded.withUnsafeBytes { eventBytes in
      try metadata.withUnsafeBufferPointer { metadataBytes in
        try vectors.withUnsafeBufferPointer { vectorBytes in
          try output(capacity: 208, call: { id, bytes, capacity, written in
            gs_memory_append(id, eventBytes.bindMemory(to: UInt8.self).baseAddress, encoded.count,
              metadataBytes.baseAddress, metadataBytes.count, vectorBytes.baseAddress, vectorBytes.count,
              bytes, capacity, written)
          }, decode: AgentKnowledgeNativeWire.checkpoint)
        }
      }
    }
  }

  func search(_ query: [Float], count: Int = 128, breadth: Int = 256) throws -> [AgentKnowledgeNativeMatch] {
    guard query.count == dimensions, query.allSatisfy(\.isFinite), (1...256).contains(count),
      breadth > count, breadth <= 4_096 else { throw AgentKnowledgeNativeError.invalidRecord }
    return try query.withUnsafeBufferPointer { queryBytes in
      try output(capacity: 8 + count * 104, call: { id, bytes, capacity, written in
        gs_memory_search(id, queryBytes.baseAddress, queryBytes.count, UInt32(count), UInt32(breadth), bytes, capacity, written)
      }, decode: AgentKnowledgeNativeWire.matches)
    }
  }

  func cancel() {
    lock.lock()
    let id = handle
    lock.unlock()
    if id > 0 { _ = gs_memory_cancel(id) }
  }

  func close() {
    lock.lock()
    let id = handle
    handle = 0
    lock.unlock()
    if id > 0 { _ = gs_memory_close(id) }
  }

  private func output<T>(capacity: Int,
    call: (Int64, UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>) -> Int32,
    decode: (Data) throws -> T) throws -> T {
    lock.lock()
    let id = handle
    lock.unlock()
    guard id > 0 else { throw AgentKnowledgeNativeError.closed }
    var data = Data(count: capacity)
    defer { data.wipeSensitive() }
    var written = 0
    let status = data.withUnsafeMutableBytes { bytes in
      call(id, bytes.bindMemory(to: UInt8.self).baseAddress, capacity, &written)
    }
    guard status == 0, (0...capacity).contains(written) else { throw AgentKnowledgeNativeError.nativeFailure }
    data.count = written
    return try decode(data)
  }
}
