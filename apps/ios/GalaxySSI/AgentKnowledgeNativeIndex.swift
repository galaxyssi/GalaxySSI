import Foundation

protocol AgentKnowledgeNativeSession: AnyObject {
  func checkpoint() throws -> AgentKnowledgeNativeCheckpoint
  func begin(_ event: AgentKnowledgeNativeEvent, skip: Bool) throws -> AgentKnowledgeNativeCheckpoint
  func append(_ page: AgentKnowledgeVectorReplayPage) throws -> AgentKnowledgeNativeCheckpoint
  func search(_ query: [Float], count: Int, breadth: Int) throws -> [AgentKnowledgeNativeMatch]
  func recordsPartitioned() throws -> Bool
  func migrateRecords(limit: Int) throws -> Bool
  func cancel()
  func close()
}

// Owned by one serial utility queue. Each advance is bounded; Rust checkpoints
// commit with graph transactions and survive queue/handle/process lifetimes.
final class AgentKnowledgeNativeIndex {
  typealias Factory = (AgentKnowledgeVectorFeedStamp, UInt64, [Float]?) throws -> AgentKnowledgeNativeSession?
  private let database: AgentKnowledgeDatabase
  private let provenance: AgentKnowledgeVectorProvenance
  private let backgroundLease: AgentKnowledgeNativeFiles.BackgroundLease?
  private let factory: Factory
  private var session: AgentKnowledgeNativeSession?
  private let cancellationLock = NSLock()
  private weak var cancellableSession: AgentKnowledgeNativeSession?
  var cancellationCheck: () -> Bool = { false }
  private var epoch = ""
  private var generation: UInt64?
  private(set) var readyStamp: AgentKnowledgeVectorFeedStamp?
  private(set) var needsReplay = false

  init(database: AgentKnowledgeDatabase, provenance: AgentKnowledgeVectorProvenance,
    backgroundLease: AgentKnowledgeNativeFiles.BackgroundLease? = nil, factory: Factory? = nil) {
    self.database = database
    self.provenance = provenance
    self.backgroundLease = backgroundLease
    self.factory = factory ?? { [files = database.nativeFiles] stamp, token, root in
      try files.open(provenance: provenance, epoch: stamp.epoch, token: token, root: root, backgroundLease: backgroundLease)
        .map { $0 as AgentKnowledgeNativeSession }
    }
  }

  deinit { close() }

  func advance(maxPages: Int = 4, token: UInt64) throws -> Bool {
    guard (1...16).contains(maxPages) else { throw AgentKnowledgeNativeError.invalidRecord }
    readyStamp = nil
    needsReplay = false
    try active(token)
    let initial = try database.vectorFeedStamp(modelSHA256: provenance.modelSHA256)
    if epoch != initial.epoch || generation != token {
      close()
      epoch = initial.epoch
      generation = token
    }
    do {
      if session == nil { session = try factory(initial, token, nil) }
      if session == nil {
        var seed = try database.nativeRootSeed(provenance: provenance, stamp: initial)
        defer {
          if seed.vector != nil { for index in seed.vector!.indices { seed.vector![index] = 0 } }
        }
        guard seed.vector != nil else { needsReplay = seed.pending; return false }
        try active(token)
        session = try factory(initial, token, seed.vector)
      }
      guard let session else { throw AgentKnowledgeNativeError.nativeFailure }
      cancellationLock.lock()
      cancellableSession = session
      cancellationLock.unlock()
      let expectedEpoch = try AgentKnowledgeNativeWire.epoch(initial.epoch).map { String(format: "%02x", $0) }.joined()
      for _ in 0..<maxPages {
        try active(token)
        let checkpoint = try session.checkpoint()
        guard checkpoint.epoch == expectedEpoch else { throw AgentKnowledgeDatabaseError.staleCursor }
        let page = try database.vectorChangePage(modelSHA256: provenance.modelSHA256,
          epoch: initial.epoch, afterSequence: checkpoint.sequence, limit: 1)
        guard let change = page.events.first else {
          guard checkpoint.pending == nil else { throw AgentKnowledgeNativeError.invalidRecord }
          return try markReady(checkpoint: checkpoint, token: token)
        }
        let event = AgentKnowledgeNativeEvent(change: change)
        if let pending = checkpoint.pending, pending.event != event { throw AgentKnowledgeNativeError.invalidRecord }
        if change.operation == .removal {
          _ = try session.begin(event, skip: false)
        } else {
          let next = checkpoint.pending?.next ?? 0
          guard next >= 0, next < Int64(change.chunkCount) else { throw AgentKnowledgeNativeError.invalidRecord }
          let vectors = try database.vectorReplayPage(event: change, provenance: provenance, afterChunkIndex: Int(next), limit: 64)
          _ = try session.begin(event, skip: vectors == nil)
          if let vectors {
            try active(token)
            _ = try session.append(vectors)
          }
        }
      }
      return try markReady(checkpoint: session.checkpoint(), token: token)
    } catch {
      close()
      throw error
    }
  }

  // Explicit maintenance only. Foreground advance/search never rewrite layout.
  // A ready graph can still have legacy provenance records requiring migration.
  func maintainRecords(pageSize: Int = 64, token: UInt64) throws -> Bool {
    guard backgroundLease != nil, (1...256).contains(pageSize) else { throw AgentKnowledgeNativeError.invalidRecord }
    try active(token)
    guard generation == token else { throw AgentKnowledgeDatabaseError.staleCursor }
    guard let session else { return true }
    do {
      let partitioned = try session.recordsPartitioned()
      try active(token)
      if partitioned { return true }
      let complete = try session.migrateRecords(limit: pageSize)
      try active(token)
      return complete
    } catch { close(); throw error }
  }

  func search(_ vector: [Float], count: Int, token: UInt64) throws -> [AgentKnowledgeHit] {
    try active(token)
    guard generation == token, let session, let stamp = readyStamp,
      try database.vectorFeedStamp(modelSHA256: provenance.modelSHA256) == stamp else {
      throw AgentKnowledgeDatabaseError.staleCursor
    }
    let count = min(max(count, 1), 256)
    let matches = try session.search(vector, count: count, breadth: max(256, count + 1))
    try active(token)
    let hits = try database.resolveNativeMatches(matches, provenance: provenance, stamp: stamp)
    try active(token)
    return hits
  }

  func close() {
    readyStamp = nil
    needsReplay = false
    session?.cancel()
    session?.close()
    session = nil
    cancellationLock.lock()
    cancellableSession = nil
    cancellationLock.unlock()
  }

  // May be called off the owner queue, but only for the currently active request.
  func cancelCurrentSession() {
    cancellationLock.lock()
    let current = cancellableSession
    cancellationLock.unlock()
    current?.cancel()
    current?.close()
  }

  private func active(_ token: UInt64) throws {
    guard !cancellationCheck() else { throw CancellationError() }
    if let backgroundLease {
      guard backgroundLease.token == token, backgroundLease.isValid else { throw CancellationError() }
    } else {
      guard database.nativeFiles.activeToken() == token else { throw CancellationError() }
    }
  }

  private func markReady(checkpoint: AgentKnowledgeNativeCheckpoint, token: UInt64) throws -> Bool {
    try active(token)
    let current = try database.vectorFeedStamp(modelSHA256: provenance.modelSHA256)
    let expectedEpoch = try AgentKnowledgeNativeWire.epoch(current.epoch).map { String(format: "%02x", $0) }.joined()
    if checkpoint.epoch == expectedEpoch, checkpoint.sequence == current.head, checkpoint.pending == nil {
      readyStamp = current
      return true
    }
    needsReplay = true
    return false
  }
}
