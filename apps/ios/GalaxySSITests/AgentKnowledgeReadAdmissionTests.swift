import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeReadAdmissionTests: XCTestCase {
  private final class Secrets: GalaxySSISecretStore {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var callback: (() -> Void)?
    func onNextIndexRead(_ action: @escaping () -> Void) { lock.lock(); callback = action; lock.unlock() }
    func setString(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    func string(account: String) -> String? {
      lock.lock()
      let value = values[account]
      let action = account == "agent.knowledge.index.hmac256.v1" ? callback : nil
      if action != nil { callback = nil }
      lock.unlock(); action?()
      return value
    }
    func delete(account: String) { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
  }
  private func item(_ body: String = "needle committed body") -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: "item", kind: .document, title: "Synthetic", content: body, source: "source", updatedAtMillis: 10)
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, Secrets) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite"), secrets = Secrets()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll([item()]))
    try body(database, url, secrets)
  }
  private func scalar(_ database: OpaquePointer, _ sql: String) throws -> Int64 {
    var row: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &row, nil) == SQLITE_OK, let row else { throw AgentKnowledgeDatabaseError.unavailable }
    defer { sqlite3_finalize(row) }
    guard sqlite3_step(row) == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
    return sqlite3_column_int64(row, 0)
  }

  func testIndependentViewPinsCommittedStateAndIsQueryOnly() throws {
    try fixture { database, url, _ in
      let old = try AgentKnowledgeCommittedReadView(fileURL: url, checkActive: {})
      defer { old.close() }
      let revision = old.revision
      XCTAssertEqual(try old.read { try scalar($0, "SELECT COUNT(*) FROM knowledge_items") }, 1)
      XCTAssertEqual(try old.read { sqlite3_exec($0, "DELETE FROM knowledge_items", nil, nil, nil) }, SQLITE_READONLY)
      var second = item("needle second"); second.id = "second"
      XCTAssertTrue(database.replaceAll([item(), second]))
      let new = try AgentKnowledgeCommittedReadView(fileURL: url, checkActive: {})
      defer { new.close() }
      XCTAssertGreaterThan(new.revision, revision)
      XCTAssertEqual(try old.read { try scalar($0, "SELECT COUNT(*) FROM knowledge_items") }, 1)
      XCTAssertEqual(try new.read { try scalar($0, "SELECT COUNT(*) FROM knowledge_items") }, 2)
      old.close(); old.close()
      XCTAssertThrowsError(try old.read { _ in 1 })
    }
  }

  func testHeldWriterDoesNotBlockCandidateReadOrFinalCommittedValidation() throws {
    try fixture { database, _, secrets in
      let held = expectation(description: "uncommitted canonical writer held")
      let readerDone = expectation(description: "reader completed while writer held")
      let writerDone = expectation(description: "writer committed")
      let gate = DispatchSemaphore(value: 0)
      let readerFinished = DispatchSemaphore(value: 0)
      let changed = item("needle replacement body"), original = item()
      secrets.onNextIndexRead { held.fulfill(); _ = gate.wait(timeout: .now() + 8) }
      DispatchQueue.global().async {
        XCTAssertTrue(database.replaceAll([changed])); writerDone.fulfill()
      }
      let admission = XCTWaiter.wait(for: [held], timeout: 3)
      if admission == .completed {
        DispatchQueue.global().async {
          do { XCTAssertEqual(try database.searchCandidates(query: "needle"), [original]) }
          catch { XCTFail("Committed reader failed: \(error)") }
          readerDone.fulfill(); readerFinished.signal()
        }
        let completedUnderWriter = XCTWaiter.wait(for: [readerDone], timeout: 3)
        gate.signal()
        XCTAssertEqual(completedUnderWriter, .completed)
        XCTAssertEqual(XCTWaiter.wait(for: [writerDone], timeout: 10), .completed)
        // Join independently of the XCTest wait (an expectation is waited once).
        XCTAssertEqual(readerFinished.wait(timeout: .now() + 10), .success)
      } else {
        gate.signal(); XCTAssertEqual(admission, .completed)
        _ = XCTWaiter.wait(for: [writerDone], timeout: 10)
      }
      XCTAssertEqual(try database.searchCandidates(query: "needle"), [changed])
    }
  }

  func testSecondCommittedViewRejectsReplacementDeletionAndACLChanges() throws {
    try fixture { database, _, _ in
      for mutation in 0..<3 {
        let original = item()
        XCTAssertTrue(database.replaceAll([original]))
        let hits = try database.searchCandidates(query: "needle", beforeValidation: {
          var changed = original
          if mutation == 0 { changed.content = "needle changed" }
          if mutation == 1 { changed.cloudAccess = .full; changed.agentAccess = .anyPairedAgent }
          XCTAssertTrue(database.replaceAll(mutation == 2 ? [] : [changed]))
        })
        XCTAssertTrue(hits.isEmpty)
      }
    }
  }

  func testLifecycleGenerationChangeCannotPublishThroughANewerValidationView() throws {
    try fixture { database, _, _ in
      XCTAssertThrowsError(try database.searchCandidates(query: "needle", beforeValidation: { database.nativeFiles.invalidate() })) {
        XCTAssertTrue($0 is CancellationError)
      }
      XCTAssertEqual(try database.searchCandidates(query: "needle"), [item()])
    }
  }

  func testReentrantSearchInsideOwnUncommittedWriterIsRejected() throws {
    try fixture { database, _, secrets in
      var rejected = false
      secrets.onNextIndexRead {
        do { _ = try database.searchCandidates(query: "needle"); XCTFail("Uncommitted writer admitted a snapshot") }
        catch AgentKnowledgeDatabaseError.unavailable { rejected = true }
        catch { XCTFail("Unexpected rejection: \(error)") }
      }
      XCTAssertTrue(database.replaceAll([item("needle new body")]))
      XCTAssertTrue(rejected)
    }
  }

  func testValidationAuthenticatesCiphertextRatherThanTrustingStableSQLIdentity() throws {
    try fixture { database, url, _ in
      XCTAssertThrowsError(try database.searchCandidates(query: "needle", beforeValidation: {
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
        defer { sqlite3_close(raw) }
        XCTAssertEqual(sqlite3_exec(raw, "UPDATE knowledge_items SET encrypted_payload=X'00'", nil, nil, nil), SQLITE_OK)
      }))
    }
  }

  func testViewRejectsCloseDuringReadAndLifecycleInvalidation() throws {
    try fixture { _, url, _ in
      var active = true
      let view = try AgentKnowledgeCommittedReadView(fileURL: url) { if !active { throw CancellationError() } }
      XCTAssertThrowsError(try view.read { _ in active = false; return 1 })
      active = true
      XCTAssertThrowsError(try view.read { _ in view.close(); return 1 })
      XCTAssertThrowsError(try view.read { _ in 1 })
    }
  }

  func testCancelledCandidatePublicationThrowsAfterValidationHook() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = AgentKnowledgeDatabase(fileURL: root.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
    XCTAssertTrue(database.replaceAll([item()]))
    let task = Task {
      do {
        _ = try database.searchCandidates(query: "needle", beforeValidation: { withUnsafeCurrentTask { $0?.cancel() } })
        XCTFail("Cancelled candidates published")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
    await task.value
  }

  func testRetryHintIsDeduplicatedAndRunsOffCaller() {
    let queue = DispatchQueue(label: "retry-fixture")
    let gate = AgentKnowledgeIndexRetryGate(queue: queue)
    XCTAssertFalse(gate.request { XCTFail("No known failure"); return true })
    gate.markFailure(); queue.suspend()
    var repairs = 0
    XCTAssertTrue(gate.request { repairs += 1; return true })
    for _ in 0..<100 { XCTAssertFalse(gate.request { repairs += 1; return true }) }
    XCTAssertEqual(repairs, 0)
    queue.resume(); queue.sync {}
    XCTAssertEqual(repairs, 1)
    XCTAssertFalse(gate.request { XCTFail("Successful repair requested again"); return true })
  }

  func testFailedRepairAndFailureDuringRepairRemainEligibleForRetry() {
    let queue = DispatchQueue(label: "retry-generation-fixture")
    let gate = AgentKnowledgeIndexRetryGate(queue: queue)
    gate.markFailure()
    XCTAssertTrue(gate.request { false }); queue.sync {}
    XCTAssertTrue(gate.request { gate.markFailure(); return true }); queue.sync {}
    XCTAssertTrue(gate.request { true }); queue.sync {}
    XCTAssertFalse(gate.request { true })
  }

  func testKnownFailedBackfillIsRetriedAsynchronouslyWithoutDiscardingCorpus() throws {
    try fixture { _, url, secrets in
      var raw: OpaquePointer?, row: OpaquePointer?
      XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
      defer { sqlite3_finalize(row); sqlite3_close(raw) }
      XCTAssertEqual(sqlite3_prepare_v2(raw, "SELECT encrypted_payload FROM knowledge_items", -1, &row, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(row), SQLITE_ROW)
      let bytes = try XCTUnwrap(sqlite3_column_blob(row, 0))
      let saved = Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 0)))
      sqlite3_finalize(row); row = nil
      XCTAssertEqual(sqlite3_exec(raw, "UPDATE knowledge_items SET encrypted_payload=X'00'; DELETE FROM knowledge_fts", nil, nil, nil), SQLITE_OK)
      let queue = DispatchQueue(label: "actual-backfill-fixture")
      let gate = AgentKnowledgeIndexRetryGate(queue: queue)
      queue.suspend()
      var resumed = false
      defer { if !resumed { queue.resume() }; queue.sync {} }
      // Eager open detects the missing index but cannot authenticate this body.
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets, indexRetryGate: gate)
      XCTAssertThrowsError(try reopened.all())
      XCTAssertTrue(try reopened.searchCandidates(query: "needle").isEmpty)
      XCTAssertFalse(gate.request { XCTFail("Duplicate repair admitted"); return false })
      XCTAssertEqual(sqlite3_prepare_v2(raw, "UPDATE knowledge_items SET encrypted_payload=?", -1, &row, nil), SQLITE_OK)
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      XCTAssertEqual(saved.withUnsafeBytes { sqlite3_bind_blob(row, 1, $0.baseAddress, Int32(saved.count), transient) }, SQLITE_OK)
      XCTAssertEqual(sqlite3_step(row), SQLITE_DONE)
      sqlite3_finalize(row); row = nil
      queue.resume(); resumed = true; queue.sync {}
      XCTAssertEqual(try reopened.searchCandidates(query: "needle"), [item()])
      XCTAssertEqual(try reopened.all().count, 1)
      XCTAssertFalse(gate.request { XCTFail("Successful repair repeated"); return false })
    }
  }
}
