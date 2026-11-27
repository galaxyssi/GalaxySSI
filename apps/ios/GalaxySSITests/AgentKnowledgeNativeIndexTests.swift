import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeNativeIndexTests: XCTestCase {
  func testRequestCancellationDoesNotRotateDatabaseScopeOrCancelAnotherOwner() throws {
    try fixture(chunks: 130) { database, _, spec in
      let state = try sessionState(database, spec)
      let token = try XCTUnwrap(database.nativeFiles.activeToken())
      let first = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      var cancelled = false
      first.cancellationCheck = { cancelled }
      state.onAppend = { cancelled = true; first.cancelCurrentSession() }
      defer { state.onAppend = nil }
      XCTAssertThrowsError(try first.advance(maxPages: 1, token: token))
      XCTAssertEqual(database.nativeFiles.activeToken(), token)
      XCTAssertEqual(state.checkpoint.pending?.next, 64)
      let other = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      XCTAssertTrue(try other.advance(token: token))
      XCTAssertNotNil(other.readyStamp)
      XCTAssertEqual(state.ordinals, Array(0..<130))
      XCTAssertEqual(database.nativeFiles.activeToken(), token)
    }
  }

  func testReplayResumesPartialChunksAcrossOwnerRecreation() throws {
    try fixture(chunks: 130) { database, item, spec in
      let state = try sessionState(database, spec)
      let token = try XCTUnwrap(database.nativeFiles.activeToken())
      let first = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      XCTAssertFalse(try first.advance(maxPages: 1, token: token))
      XCTAssertEqual(state.checkpoint.pending?.next, 64)
      XCTAssertTrue(first.needsReplay)
      first.close()
      let resumed = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      XCTAssertFalse(try resumed.advance(maxPages: 1, token: token))
      XCTAssertEqual(state.checkpoint.pending?.next, 128)
      XCTAssertTrue(try resumed.advance(maxPages: 1, token: token))
      XCTAssertEqual(state.ordinals, Array(0..<130))
      XCTAssertNil(state.checkpoint.pending)
      XCTAssertNotNil(resumed.readyStamp)
      let event = try XCTUnwrap(database.nativePublicationPage(modelSHA256: spec.modelSHA256).events.first)
      state.matches = [match(event)]
      XCTAssertEqual(try resumed.search([0.6, 0.8], count: 24, token: token).first?.item.id, item.id)
      XCTAssertEqual(state.searches, 1)
    }
  }

  func testObsoletePublicationIsSkippedWithoutAppendingItsVectors() throws {
    try fixture(chunks: 1) { database, item, spec in
      let state = try sessionState(database, spec)
      state.created = true
      var changed = item
      changed.content = "replacement"
      XCTAssertTrue(database.replaceAll([changed]))
      let index = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      XCTAssertTrue(try index.advance(token: XCTUnwrap(database.nativeFiles.activeToken())))
      XCTAssertEqual(state.skipped.count, 1)
      XCTAssertTrue(state.ordinals.isEmpty)
    }
  }

  func testRemovalAndReadditionRetireOldNativeMatches() throws {
    try fixture(chunks: 1) { database, item, spec in
      let state = try sessionState(database, spec)
      let token = try XCTUnwrap(database.nativeFiles.activeToken())
      let index = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      XCTAssertTrue(try index.advance(token: token))
      let old = try XCTUnwrap(database.nativePublicationPage(modelSHA256: spec.modelSHA256).events.first)
      XCTAssertTrue(database.clearVectorCheckpoints(itemId: item.id, modelSHA256: spec.modelSHA256))
      XCTAssertTrue(database.storeVectorCheckpoint(checkpoint(item, spec: spec, index: 0, total: 1)))
      XCTAssertTrue(try index.advance(token: token))
      state.matches = [match(old)]
      XCTAssertTrue(try index.search([0.6, 0.8], count: 24, token: token).isEmpty)
      let current = try XCTUnwrap(database.nativePublicationPage(modelSHA256: spec.modelSHA256).events.first)
      state.matches = [match(current)]
      XCTAssertEqual(try index.search([0.6, 0.8], count: 24, token: token).count, 1)
    }
  }

  func testInvalidationRejectsLateAppendAndSearchButKeepsCommittedProgress() throws {
    try fixture(chunks: 130) { database, _, spec in
      let state = try sessionState(database, spec)
      let index = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      let token = try XCTUnwrap(database.nativeFiles.activeToken())
      state.onAppend = { database.nativeFiles.invalidate() }
      XCTAssertThrowsError(try index.advance(maxPages: 1, token: token))
      XCTAssertNil(index.readyStamp)
      XCTAssertEqual(state.checkpoint.pending?.next, 64)
      XCTAssertGreaterThan(state.closes, 0)
      state.onAppend = nil
      let next = try XCTUnwrap(database.nativeFiles.activeToken())
      XCTAssertTrue(try index.advance(token: next))
      XCTAssertEqual(state.ordinals, Array(0..<130))
      state.onSearch = { database.nativeFiles.invalidate() }
      XCTAssertThrowsError(try index.search([0.6, 0.8], count: 24, token: next))
    }
  }

  func testRootSeekIsBoundedAndResumesAfterDatabaseReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let secrets = InMemorySecretStore(), url = directory.appendingPathComponent("knowledge.sqlite")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let items = (0..<65).map { AgentKnowledgeItem(id: "seed-\($0)", kind: .note, title: "Source", content: "x", updatedAtMillis: 1) }
    let spec = provenance()
    XCTAssertTrue(database.replaceAll(items))
    for item in items { XCTAssertTrue(database.storeVectorCheckpoint(checkpoint(item, spec: spec, index: 0, total: 1))) }
    var different = spec
    different.chunkingContract = "different-contract"
    let stamp = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
    let first = try database.nativeRootSeed(provenance: different, stamp: stamp)
    XCTAssertNil(first.vector)
    XCTAssertTrue(first.pending)
    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let last = try reopened.nativeRootSeed(provenance: different, stamp: stamp)
    XCTAssertNil(last.vector)
    XCTAssertFalse(last.pending)
  }

  func testLexicalFallbackCannotReuseSourcesFromAnOlderPolicySnapshot() throws {
    try fixture(chunks: 1) { database, item, spec in
      let hit = AgentKnowledgeHit(item: item, score: 1, excerpt: item.content, matchedTerms: ["x"])
      let stamp = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      XCTAssertEqual(try database.validatedLexicalHits([hit], stamp: stamp, modelSHA256: spec.modelSHA256), [hit])
      var changed = item
      changed.agentAccess = .anyPairedAgent
      XCTAssertTrue(database.replaceAll([changed]))
      XCTAssertThrowsError(try database.validatedLexicalHits([hit], stamp: stamp, modelSHA256: spec.modelSHA256))
      let current = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      XCTAssertTrue(try database.validatedLexicalHits([hit], stamp: current, modelSHA256: spec.modelSHA256).isEmpty)
      XCTAssertThrowsError(try database.validatedLexicalHits(Array(repeating: hit, count: 257), stamp: current, modelSHA256: spec.modelSHA256))
    }
  }

  func testReadyGraphStillMigratesOneBoundedRecordPage() throws {
    try backgroundFixture { index, state, lease in
      XCTAssertNotNil(index.readyStamp)
      let before = state.checkpoint
      XCTAssertFalse(try index.maintainRecords(pageSize: 64, token: lease.token))
      XCTAssertEqual(state.migrationPages, [64])
      XCTAssertEqual(state.checkpoint, before)
      XCTAssertNotNil(index.readyStamp)
      state.migrationCompletes = true
      XCTAssertTrue(try index.maintainRecords(pageSize: 64, token: lease.token))
      XCTAssertEqual(state.migrationPages, [64, 64])
    }
  }

  func testPartitionedGraphDoesNotEnterWriteMigration() throws {
    try backgroundFixture { index, state, lease in
      state.partitioned = true
      XCTAssertTrue(try index.maintainRecords(token: lease.token))
      XCTAssertTrue(state.migrationPages.isEmpty)
    }
  }

  func testForegroundReplayAndSearchNeverMigrateRecords() throws {
    try fixture(chunks: 1) { database, _, spec in
      let state = try sessionState(database, spec), token = try XCTUnwrap(database.nativeFiles.activeToken())
      let index = AgentKnowledgeNativeIndex(database: database, provenance: spec, factory: factory(state))
      XCTAssertTrue(try index.advance(token: token))
      _ = try index.search([0.6, 0.8], count: 4, token: token)
      XCTAssertThrowsError(try index.maintainRecords(token: token))
      XCTAssertTrue(state.migrationPages.isEmpty)
    }
  }

  func testMigrationBoundsAndExpiredLeaseDoNotReachTheWriter() throws {
    try backgroundFixture { index, state, lease in
      for size in [0, 257, Int.max] { XCTAssertThrowsError(try index.maintainRecords(pageSize: size, token: lease.token)) }
      lease.end()
      XCTAssertThrowsError(try index.maintainRecords(token: lease.token))
      XCTAssertTrue(state.migrationPages.isEmpty)
    }
  }

  func testMigrationFailureRetiresSessionWithoutRewritingReplayProgress() throws {
    try backgroundFixture { index, state, lease in
      let before = state.checkpoint
      state.migrationFails = true
      XCTAssertThrowsError(try index.maintainRecords(token: lease.token))
      XCTAssertNil(index.readyStamp)
      XCTAssertGreaterThan(state.closes, 0)
      XCTAssertEqual(state.checkpoint, before)
    }
  }

  func testLeaseExpiryDuringMigrationRejectsLateCompletion() throws {
    try backgroundFixture { index, state, lease in
      state.migrationCompletes = true
      state.onMigrate = { lease.end() }
      defer { state.onMigrate = nil }
      XCTAssertThrowsError(try index.maintainRecords(token: lease.token))
      XCTAssertNil(index.readyStamp)
      XCTAssertEqual(state.migrationPages, [64])
    }
  }

  func testIncompleteMigrationResumesAfterIndexOwnerRecreation() throws {
    try fixture(chunks: 1) { database, _, spec in
      let lease = try database.nativeFiles.beginBackgroundLease()
      defer { lease.end() }
      let state = try sessionState(database, spec)
      let first = AgentKnowledgeNativeIndex(database: database, provenance: spec, backgroundLease: lease, factory: factory(state))
      XCTAssertTrue(try first.advance(token: lease.token))
      XCTAssertFalse(try first.maintainRecords(pageSize: 16, token: lease.token))
      let checkpoint = state.checkpoint
      first.close()
      let resumed = AgentKnowledgeNativeIndex(database: database, provenance: spec, backgroundLease: lease, factory: factory(state))
      defer { resumed.close() }
      XCTAssertTrue(try resumed.advance(token: lease.token))
      state.migrationCompletes = true
      XCTAssertTrue(try resumed.maintainRecords(pageSize: 16, token: lease.token))
      XCTAssertEqual(state.migrationPages, [16, 16])
      XCTAssertEqual(state.checkpoint, checkpoint)
    }
  }

  private func backgroundFixture(_ body: (AgentKnowledgeNativeIndex, SessionState, AgentKnowledgeNativeFiles.BackgroundLease) throws -> Void) throws {
    try fixture(chunks: 1) { database, _, spec in
      let lease = try database.nativeFiles.beginBackgroundLease()
      defer { lease.end() }
      let state = try sessionState(database, spec)
      let index = AgentKnowledgeNativeIndex(database: database, provenance: spec, backgroundLease: lease, factory: factory(state))
      defer { index.close() }
      XCTAssertTrue(try index.advance(token: lease.token))
      try body(index, state, lease)
    }
  }

  private func fixture(chunks: Int, _ body: (AgentKnowledgeDatabase, AgentKnowledgeItem, AgentKnowledgeVectorProvenance) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = AgentKnowledgeDatabase(fileURL: directory.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
    let item = AgentKnowledgeItem(id: "source", kind: .note, title: "Source", content: String(repeating: "x", count: chunks), updatedAtMillis: 1)
    let spec = provenance()
    XCTAssertTrue(database.replaceAll([item]))
    for index in 0..<chunks { XCTAssertTrue(database.storeVectorCheckpoint(checkpoint(item, spec: spec, index: index, total: chunks))) }
    try body(database, item, spec)
  }

  private func provenance() -> AgentKnowledgeVectorProvenance {
    AgentKnowledgeVectorProvenance(modelSHA256: String(repeating: "b", count: 64), dimensions: 2,
      contextTokens: 512, chunkingContract: AgentKnowledgeEmbeddingChunker.contract)
  }
  private func checkpoint(_ item: AgentKnowledgeItem, spec: AgentKnowledgeVectorProvenance, index: Int, total: Int) -> AgentKnowledgeVectorCheckpoint {
    AgentKnowledgeVectorCheckpoint(itemId: item.id, sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: index, chunkCount: total, vector: [0.6, 0.8], provenance: spec, updatedAtMillis: 10,
      sourceStartUTF16: index, sourceEndUTF16: index + 1)
  }
  private func match(_ event: AgentKnowledgeVectorChange) -> AgentKnowledgeNativeMatch {
    AgentKnowledgeNativeMatch(key: event.itemHash, revision: event.sourceRevisionHash, sequence: event.sequence,
      ordinal: 0, startUTF16: 0, endUTF16: 1, similarity: 0.9)
  }
  private func sessionState(_ database: AgentKnowledgeDatabase, _ spec: AgentKnowledgeVectorProvenance) throws -> SessionState {
    let stamp = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
    let epoch = try AgentKnowledgeNativeWire.epoch(stamp.epoch).map { String(format: "%02x", $0) }.joined()
    return SessionState(epoch: epoch)
  }
  private func factory(_ state: SessionState) -> AgentKnowledgeNativeIndex.Factory {
    { _, _, root in
      if !state.created && root == nil { return nil }
      state.created = true
      return Session(state)
    }
  }

  // Simulated ABI boundary only: these fixtures are not Rust/disk acceptance.
  private final class SessionState {
    var checkpoint: AgentKnowledgeNativeCheckpoint
    var created = false
    var ordinals: [Int] = [], skipped: [Int64] = []
    var searches = 0, closes = 0
    var partitioned = false, migrationCompletes = false, migrationFails = false
    var migrationPages: [Int] = []
    var onMigrate: (() -> Void)?
    var matches: [AgentKnowledgeNativeMatch] = []
    var onAppend: (() -> Void)?, onSearch: (() -> Void)?
    init(epoch: String) { checkpoint = AgentKnowledgeNativeCheckpoint(epoch: epoch, last: nil, pending: nil) }
  }
  private final class Session: AgentKnowledgeNativeSession {
    let state: SessionState
    private var cancelled = false, closed = false
    init(_ state: SessionState) { self.state = state }
    func checkpoint() throws -> AgentKnowledgeNativeCheckpoint { try live(); return state.checkpoint }
    func begin(_ event: AgentKnowledgeNativeEvent, skip: Bool) throws -> AgentKnowledgeNativeCheckpoint {
      try live()
      if skip || event.removed {
        if skip { state.skipped.append(event.sequence) }
        state.checkpoint.last = event
        state.checkpoint.pending = nil
      } else if state.checkpoint.pending == nil {
        state.checkpoint.pending = .init(event: event, next: 0)
      }
      return state.checkpoint
    }
    func append(_ page: AgentKnowledgeVectorReplayPage) throws -> AgentKnowledgeNativeCheckpoint {
      try live()
      guard let pending = state.checkpoint.pending, pending.event == AgentKnowledgeNativeEvent(change: page.event),
        let last = page.checkpoints.last else { throw AgentKnowledgeNativeError.invalidRecord }
      state.ordinals.append(contentsOf: page.checkpoints.map(\.chunkIndex))
      let next = Int64(last.chunkIndex + 1)
      if next == pending.event.chunks { state.checkpoint.last = pending.event; state.checkpoint.pending = nil }
      else { state.checkpoint.pending?.next = next }
      state.onAppend?()
      return state.checkpoint
    }
    func search(_ query: [Float], count: Int, breadth: Int) throws -> [AgentKnowledgeNativeMatch] {
      try live(); state.searches += 1; state.onSearch?(); return state.matches
    }
    func recordsPartitioned() throws -> Bool { try live(); return state.partitioned }
    func migrateRecords(limit: Int) throws -> Bool {
      try live(); state.migrationPages.append(limit)
      if state.migrationFails { throw AgentKnowledgeNativeError.nativeFailure }
      state.onMigrate?()
      state.partitioned = state.migrationCompletes
      return state.partitioned
    }
    func cancel() { cancelled = true }
    func close() { if !closed { state.closes += 1; closed = true } }
    private func live() throws { if cancelled || closed { throw AgentKnowledgeNativeError.closed } }
  }
}
