import Foundation
import SQLite3
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeVectorReadAdmissionTests: XCTestCase {
  private final class Secrets: GalaxySSISecretStore {
    let notifications = NotificationCenter()
    private let lock = NSLock()
    private var values: [String: String] = [:], callback: (() -> Void)?
    func onNextIndexRead(_ action: @escaping () -> Void) { lock.lock(); callback = action; lock.unlock() }
    func setString(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    func string(account: String) -> String? {
      lock.lock()
      let value = values[account], action = account == "agent.knowledge.index.hmac256.v1" ? callback : nil
      if action != nil { callback = nil }
      lock.unlock(); action?(); return value
    }
    func delete(account: String) { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, AgentKnowledgeItem, AgentKnowledgeVectorProvenance, URL, Secrets) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = Secrets(), url = root.appendingPathComponent("knowledge.sqlite")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets, nativeNotifications: secrets.notifications)
    let item = AgentKnowledgeItem(id: "item", kind: .document, title: "Synthetic", content: "needle", source: "source", updatedAtMillis: 10)
    let spec = AgentKnowledgeVectorProvenance(modelSHA256: String(repeating: "c", count: 64), dimensions: 2,
      contextTokens: 512, chunkingContract: AgentKnowledgeEmbeddingChunker.contract)
    XCTAssertTrue(database.replaceAll([item]))
    XCTAssertTrue(database.storeVectorCheckpoint(AgentKnowledgeVectorCheckpoint(itemId: item.id,
      sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item), chunkIndex: 0,
      vector: [0.6, 0.8], provenance: spec, updatedAtMillis: 10, sourceStartUTF16: 0, sourceEndUTF16: item.content.utf16.count)))
    _ = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
    _ = try database.vectorCountSnapshot(modelSHA256: spec.modelSHA256)
    try body(database, item, spec, url, secrets)
  }
  private func heldWriter(_ database: AgentKnowledgeDatabase, item: AgentKnowledgeItem, secrets: Secrets,
    read: @escaping () throws -> Void) {
    let held = expectation(description: "source writer held inside its transaction")
    let readerDone = expectation(description: "vector reader completed under held writer")
    let writerDone = expectation(description: "writer done")
    let release = DispatchSemaphore(value: 0), joined = DispatchSemaphore(value: 0)
    secrets.onNextIndexRead { held.fulfill(); _ = release.wait(timeout: .now() + 10) }
    var changed = item; changed.content = "replacement"
    let replacement = changed
    DispatchQueue.global().async { XCTAssertTrue(database.replaceAll([replacement])); writerDone.fulfill() }
    let admitted = XCTWaiter.wait(for: [held], timeout: 3)
    if admitted == .completed {
      DispatchQueue.global().async {
        do { try read() } catch { XCTFail("Vector read failed: \(error)") }
        readerDone.fulfill(); joined.signal()
      }
      let result = XCTWaiter.wait(for: [readerDone], timeout: 4)
      release.signal()
      XCTAssertEqual(result, .completed)
      XCTAssertEqual(XCTWaiter.wait(for: [writerDone], timeout: 10), .completed)
      XCTAssertEqual(joined.wait(timeout: .now() + 10), .success)
    } else {
      release.signal(); XCTAssertEqual(admitted, .completed)
      _ = XCTWaiter.wait(for: [writerDone], timeout: 10)
    }
  }
  private func event(_ database: AgentKnowledgeDatabase, _ spec: AgentKnowledgeVectorProvenance) throws -> AgentKnowledgeVectorChange {
    try XCTUnwrap(database.vectorChangePage(modelSHA256: spec.modelSHA256).events.last)
  }
  private func match(_ event: AgentKnowledgeVectorChange, _ item: AgentKnowledgeItem) -> AgentKnowledgeNativeMatch {
    AgentKnowledgeNativeMatch(key: event.itemHash, revision: event.sourceRevisionHash, sequence: event.sequence,
      ordinal: 0, startUTF16: 0, endUTF16: item.content.utf16.count, similarity: 1)
  }

  func testWarmFeedCatalogCountReplayAndFinalResolutionDoNotWaitForSourceWriter() throws {
    try fixture { database, item, spec, _, secrets in
      let stamp = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      let published = try event(database, spec), matched = match(published, item)
      heldWriter(database, item: item, secrets: secrets) {
        XCTAssertEqual(try database.vectorFeedStamp(modelSHA256: spec.modelSHA256), stamp)
        XCTAssertEqual(try database.vectorChangePage(modelSHA256: spec.modelSHA256).events, [published])
        XCTAssertEqual(try database.nativePublicationPage(modelSHA256: spec.modelSHA256).events, [published])
        XCTAssertEqual(try database.vectorCatalogPage(modelSHA256: spec.modelSHA256).checkpoints.count, 1)
        XCTAssertEqual(try database.vectorCatalog(modelSHA256: spec.modelSHA256).count, 1)
        XCTAssertEqual(try database.vectorCheckpoints(itemId: item.id, modelSHA256: spec.modelSHA256).count, 1)
        XCTAssertEqual(try database.vectorCountSnapshot(modelSHA256: spec.modelSHA256).chunks, 1)
        XCTAssertEqual(try database.vectorReplayPage(event: published, provenance: spec)?.checkpoints.count, 1)
        XCTAssertEqual(try database.resolveNativeMatches([matched], provenance: spec, stamp: stamp).map(\.item.id), [item.id])
        let lexical = AgentKnowledgeHit(item: item, score: 1, excerpt: item.content, matchedTerms: [])
        XCTAssertEqual(try database.validatedLexicalHits([lexical], stamp: stamp, modelSHA256: spec.modelSHA256), [lexical])
      }
    }
  }

  func testRealNativeBootstrapReplayAndRankedSearchUnderHeldSourceWriter() throws {
    try fixture { database, item, spec, _, secrets in
      heldWriter(database, item: item, secrets: secrets) {
        // Default factory exercises the linked Rust graph, not a fake session
        // or a production embedding model.
        let index = AgentKnowledgeNativeIndex(database: database, provenance: spec)
        defer { index.close() }
        let token = try XCTUnwrap(database.nativeFiles.activeToken())
        XCTAssertTrue(try index.advance(token: token))
        XCTAssertEqual(try index.search([0.6, 0.8], count: 4, token: token).map(\.item.id), [item.id])
      }
    }
  }

  func testReplayRevalidatesAfterDecryptAndDropsChangedSource() throws {
    try fixture { database, item, spec, _, _ in
      let published = try event(database, spec)
      let page = try database.vectorReplayPage(event: published, provenance: spec, beforeValidation: {
        var changed = item; changed.cloudAccess = .full
        XCTAssertTrue(database.replaceAll([changed]))
      })
      XCTAssertNil(page)
    }
  }

  func testResolutionAndLexicalValidationRejectChangesAfterDecode() throws {
    try fixture { database, item, spec, _, _ in
      let published = try event(database, spec), stamp = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      let matched = match(published, item)
      XCTAssertThrowsError(try database.resolveNativeMatches([matched], provenance: spec, stamp: stamp, beforeValidation: {
        var changed = item; changed.agentAccess = .anyPairedAgent
        XCTAssertTrue(database.replaceAll([changed]))
      }))
      let current = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      let lexical = AgentKnowledgeHit(item: item, score: 1, excerpt: "needle", matchedTerms: [])
      XCTAssertThrowsError(try database.validatedLexicalHits([lexical], stamp: current, modelSHA256: spec.modelSHA256,
        beforeValidation: { XCTAssertTrue(database.replaceAll([])) }))
    }
  }

  func testLifecycleChangeBetweenViewsCannotPublishOldVectorResults() throws {
    try fixture { database, item, spec, _, _ in
      let published = try event(database, spec), stamp = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      XCTAssertThrowsError(try database.resolveNativeMatches([match(published, item)], provenance: spec, stamp: stamp,
        beforeValidation: { database.nativeFiles.invalidate() })) { XCTAssertTrue($0 is CancellationError) }
      XCTAssertThrowsError(try database.vectorReplayPage(event: published, provenance: spec,
        beforeValidation: { database.nativeFiles.invalidate() })) { XCTAssertTrue($0 is CancellationError) }
    }
  }

  func testForeignAndEndedBackgroundLeasesCannotAuthorizeDatabaseReads() throws {
    try fixture { database, _, spec, url, secrets in
      let other = AgentKnowledgeNativeFiles(databaseURL: url.appendingPathExtension("other"), secrets: secrets)
      let foreign = try other.beginBackgroundLease()
      defer { foreign.end() }
      XCTAssertTrue(foreign.isValid)
      XCTAssertThrowsError(try database.vectorFeedStamp(modelSHA256: spec.modelSHA256, backgroundLease: foreign)) { XCTAssertTrue($0 is CancellationError) }
      let owned = try database.nativeFiles.beginBackgroundLease()
      XCTAssertNotNil(try database.vectorFeedStamp(modelSHA256: spec.modelSHA256, backgroundLease: owned))
      owned.end()
      XCTAssertThrowsError(try database.vectorFeedStamp(modelSHA256: spec.modelSHA256, backgroundLease: owned)) { XCTAssertTrue($0 is CancellationError) }
    }
  }

  func testBackgroundReadCapabilityDoesNotReenableForegroundOrSurviveProtectionLoss() throws {
    let center = NotificationCenter(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let files = AgentKnowledgeNativeFiles(databaseURL: root, secrets: InMemorySecretStore(), notifications: center)
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertNil(files.activeToken())
    let lease = try files.beginBackgroundLease()
    XCTAssertEqual(files.readToken(backgroundLease: lease), lease.token)
    XCTAssertNil(files.activeToken())
    center.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
    XCTAssertNil(files.readToken(backgroundLease: lease)); XCTAssertFalse(lease.isValid)
    center.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertNotNil(files.activeToken()); XCTAssertNil(files.readToken(backgroundLease: lease))
  }

  func testRealNativeBackgroundReplayKeepsReadLeaseThroughNestedCalls() throws {
    try fixture { database, _, spec, _, secrets in
      secrets.notifications.post(name: UIApplication.willResignActiveNotification, object: nil)
      XCTAssertNil(database.nativeFiles.activeToken())
      let lease = try database.nativeFiles.beginBackgroundLease()
      let index = AgentKnowledgeNativeIndex(database: database, provenance: spec, backgroundLease: lease)
      defer { index.close(); lease.end() }
      XCTAssertTrue(try index.advance(token: lease.token))
      XCTAssertNil(database.nativeFiles.activeToken())
      lease.end()
      XCTAssertThrowsError(try index.advance(token: lease.token)) { XCTAssertTrue($0 is CancellationError) }
    }
  }

  func testColdModelRegistrationAndVectorReadsSurviveDatabaseReopen() throws {
    try fixture { database, _, spec, url, secrets in
      let missing = String(repeating: "d", count: 64)
      let initial = try database.vectorFeedStamp(modelSHA256: missing)
      XCTAssertEqual(initial.head, 0)
      XCTAssertTrue(try database.vectorChangePage(modelSHA256: missing, epoch: initial.epoch).events.isEmpty)
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.vectorFeedStamp(modelSHA256: missing), initial)
      XCTAssertEqual(try reopened.vectorCatalogPage(modelSHA256: spec.modelSHA256).checkpoints.count, 1)
      XCTAssertEqual(try reopened.vectorReplayPage(event: event(reopened, spec), provenance: spec)?.checkpoints.count, 1)
    }
  }

  func testCorruptEncryptedVectorDoesNotReturnPartialCatalogOrReplay() throws {
    try fixture { database, _, spec, url, _ in
      let published = try event(database, spec)
      var raw: OpaquePointer?
      XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
      defer { sqlite3_close(raw) }
      XCTAssertEqual(sqlite3_exec(raw, "UPDATE knowledge_vectors SET encrypted_payload=X'00'", nil, nil, nil), SQLITE_OK)
      XCTAssertThrowsError(try database.vectorCatalog(modelSHA256: spec.modelSHA256))
      XCTAssertThrowsError(try database.vectorCatalogPage(modelSHA256: spec.modelSHA256))
      XCTAssertThrowsError(try database.vectorReplayPage(event: published, provenance: spec))
    }
  }

  func testForgedEpochAndFeedBoundsStillFailClosed() throws {
    try fixture { database, _, spec, _, _ in
      XCTAssertThrowsError(try database.vectorChangePage(modelSHA256: spec.modelSHA256, epoch: UUID().uuidString))
      XCTAssertThrowsError(try database.vectorChangePage(modelSHA256: spec.modelSHA256, afterSequence: Int64.max))
      XCTAssertThrowsError(try database.vectorCatalogPage(modelSHA256: spec.modelSHA256, afterVectorKey: "not-a-key"))
      XCTAssertThrowsError(try database.vectorCatalog(modelSHA256: spec.modelSHA256, offset: Int.max))
    }
  }

  func testWrongProvenanceCannotSupplyReplayOrNativeRootEvidence() throws {
    try fixture { database, _, spec, _, _ in
      let published = try event(database, spec)
      var wrong = spec; wrong.contextTokens += 32
      XCTAssertNil(try database.vectorReplayPage(event: published, provenance: wrong))
      let stamp = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      XCTAssertNil(try database.nativeRootSeed(provenance: wrong, stamp: stamp).vector)
    }
  }

  func testWriterCompletionSeesItsOwnUncommittedFinalChunk() throws {
    try fixture { database, item, spec, _, _ in
      XCTAssertTrue(database.clearVectorCheckpoints(itemId: item.id, modelSHA256: spec.modelSHA256))
      let before = try database.vectorFeedStamp(modelSHA256: spec.modelSHA256)
      for index in 0..<2 {
        XCTAssertTrue(database.storeVectorCheckpoint(AgentKnowledgeVectorCheckpoint(itemId: item.id,
          sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item), chunkIndex: index, chunkCount: 2,
          vector: [0.6, 0.8], provenance: spec, updatedAtMillis: 20, sourceStartUTF16: index, sourceEndUTF16: index + 1)))
        if index == 0 { XCTAssertEqual(try database.vectorFeedStamp(modelSHA256: spec.modelSHA256), before) }
      }
      let published = try event(database, spec)
      XCTAssertEqual(published.operation, .ready); XCTAssertEqual(published.chunkCount, 2)
      XCTAssertEqual(try database.vectorReplayPage(event: published, provenance: spec)?.checkpoints.count, 2)
    }
  }

  func testCancelledReadCannotRegisterColdModel() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: InMemorySecretStore())
    let item = AgentKnowledgeItem(id: "cancelled", kind: .document, title: "Synthetic", content: "body", source: "source")
    let spec = AgentKnowledgeVectorProvenance(modelSHA256: String(repeating: "e", count: 64), dimensions: 2,
      contextTokens: 512, chunkingContract: AgentKnowledgeEmbeddingChunker.contract)
    let checkpoint = AgentKnowledgeVectorCheckpoint(itemId: item.id, sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0, vector: [0.6, 0.8], provenance: spec, sourceStartUTF16: 0, sourceEndUTF16: 1)
    XCTAssertTrue(database.replaceAll([item]))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try database.vectorChangePage(modelSHA256: String(repeating: "e", count: 64))
        XCTFail("Cancelled cold registration proceeded")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertFalse(database.storeVectorCheckpoint(checkpoint))
    }
    await task.value
    var raw: OpaquePointer?, row: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
    defer { sqlite3_finalize(row); sqlite3_close(raw) }
    XCTAssertEqual(sqlite3_prepare_v2(raw, "SELECT COUNT(*) FROM knowledge_vector_feed_models", -1, &row, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_step(row), SQLITE_ROW); XCTAssertEqual(sqlite3_column_int64(row, 0), 0)
    sqlite3_finalize(row); row = nil
    XCTAssertEqual(sqlite3_prepare_v2(raw, "SELECT COUNT(*) FROM knowledge_vectors", -1, &row, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_step(row), SQLITE_ROW); XCTAssertEqual(sqlite3_column_int64(row, 0), 0)
  }
}
