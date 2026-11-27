import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeIndexKeyMemoTests: XCTestCase {
  private enum Fault: Error { case injected }
  private let output = String(repeating: "a", count: 64)

  func testRepeatedInputCalculatesOnceWithinMemo() throws {
    let memo = try AgentKnowledgeIndexKeyMemo()
    var calculations = 0
    for _ in 0..<20 {
      XCTAssertEqual(try memo.key("private source") { calculations += 1; return output }, output)
    }
    XCTAssertEqual(calculations, 1); XCTAssertEqual(memo.count, 1)
  }
  func testLRUEvictsLeastRecentlyUsedEntryAndNeverExceedsCapacity() throws {
    let memo = try AgentKnowledgeIndexKeyMemo(capacity: 2)
    _ = try memo.key("a") { output }; _ = try memo.key("b") { output }
    _ = try memo.key("a") { XCTFail("Hot entry was evicted"); return output }
    _ = try memo.key("c") { output }
    var recomputed = false
    _ = try memo.key("b") { recomputed = true; return output }
    XCTAssertTrue(recomputed); XCTAssertEqual(memo.count, 2)
    for index in 0..<1_000 { _ = try memo.key("id-\(index)") { output }; XCTAssertLessThanOrEqual(memo.count, 2) }
  }
  func testRawUTF8InputsDoNotAliasCanonicalEquivalentStringsOrNulBoundaries() throws {
    let memo = try AgentKnowledgeIndexKeyMemo()
    var calculations = 0
    for input in ["\u{e9}", "e\u{301}", "a\u{0000}b", "ab", ""] {
      _ = try memo.key(input) { calculations += 1; return output }
    }
    XCTAssertEqual(calculations, 5); XCTAssertEqual(memo.count, 5)
  }
  func testFailedCalculationIsNotCachedAndCanRetry() throws {
    let memo = try AgentKnowledgeIndexKeyMemo()
    XCTAssertThrowsError(try memo.key("input") { throw Fault.injected })
    XCTAssertEqual(memo.count, 0)
    XCTAssertEqual(try memo.key("input") { output }, output)
  }
  func testCloseIsIdempotentClearsValuesAndRejectsReuse() throws {
    let memo = try AgentKnowledgeIndexKeyMemo()
    _ = try memo.key("input") { output }
    memo.close(); memo.close()
    XCTAssertEqual(memo.count, 0)
    XCTAssertThrowsError(try memo.key("input") { XCTFail("Closed memo calculated"); return output })
  }
  func testCloseDuringCalculationCannotResurrectEntries() throws {
    let memo = try AgentKnowledgeIndexKeyMemo()
    XCTAssertThrowsError(try memo.key("input") { memo.close(); return output })
    XCTAssertEqual(memo.count, 0)
  }
  func testCapacityBoundsAndIndependentOperationLifetimes() throws {
    XCTAssertThrowsError(try AgentKnowledgeIndexKeyMemo(capacity: 0))
    XCTAssertThrowsError(try AgentKnowledgeIndexKeyMemo(capacity: 257))
    let first = try AgentKnowledgeIndexKeyMemo(capacity: 1), second = try AgentKnowledgeIndexKeyMemo(capacity: 256)
    var calculations = 0
    _ = try first.key("input") { calculations += 1; return output }; first.close()
    _ = try second.key("input") { calculations += 1; return output }
    XCTAssertEqual(calculations, 2)
  }
  func testHexFormattingPreservesLeadingZerosAndAllByteValues() {
    let bytes = (0...255).map(UInt8.init)
    XCTAssertEqual(AgentKnowledgeIndexKeyMemo.hex(bytes), bytes.map { String(format: "%02x", $0) }.joined())
    XCTAssertEqual(AgentKnowledgeIndexKeyMemo.hex([UInt8]()), "")
  }

  private final class Secrets: GalaxySSISecretStore {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var reads = 0
    var onIndexRead: ((Int) -> Void)?
    var indexReads: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func resetReads() { lock.lock(); reads = 0; lock.unlock() }
    func setString(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    func string(account: String) -> String? {
      lock.lock()
      let value = values[account]
      let indexed = account == "agent.knowledge.index.hmac256.v1"
      if indexed { reads += 1 }
      let count = reads, callback = onIndexRead
      lock.unlock()
      if indexed { callback?(count) }
      return value
    }
    func delete(account: String) { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, Secrets) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = Secrets(), url = root.appendingPathComponent("knowledge.sqlite")
    try secrets.setString(Data((0..<32).map(UInt8.init)).base64EncodedString(), account: "agent.knowledge.index.hmac256.v1")
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll([AgentKnowledgeItem(id: "memo", kind: .document, title: "Memo", content: "memo body", source: "source")]))
    secrets.resetReads()
    try body(database, url, secrets)
  }
  func testDatabaseSharesHashWithinOperationButReleasesItBeforeNextOperation() throws {
    try fixture { database, _, secrets in
      XCTAssertEqual(try database.items(ids: ["memo"]).count, 1)
      // Lookup and authenticated decode hash the same ID in the same operation.
      XCTAssertEqual(secrets.indexReads, 1)
      XCTAssertEqual(try database.items(ids: ["memo"]).count, 1)
      XCTAssertEqual(secrets.indexReads, 2)
    }
  }
  func testDatabaseThrowingDecodeDoesNotLeakOperationMemo() throws {
    try fixture { database, url, secrets in
      var raw: OpaquePointer?
      XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
      defer { sqlite3_close(raw) }
      XCTAssertEqual(sqlite3_exec(raw, "UPDATE knowledge_items SET encrypted_payload=X'00'", nil, nil, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_exec(raw, "DELETE FROM knowledge_primary_refs", nil, nil, nil), SQLITE_OK)
      XCTAssertThrowsError(try database.items(ids: ["memo"]))
      XCTAssertEqual(secrets.indexReads, 1)
      XCTAssertThrowsError(try database.items(ids: ["memo"]))
      XCTAssertEqual(secrets.indexReads, 2)
    }
  }
  func testPersistentIndexHMACAndReopenRemainCompatible() throws {
    try fixture { database, url, secrets in
      let key = SymmetricKey(data: Data((0..<32).map(UInt8.init)))
      let expected = HMAC<SHA256>.authenticationCode(for: Data("memo".utf8), using: key).map { String(format: "%02x", $0) }.joined()
      var raw: OpaquePointer?, row: OpaquePointer?
      XCTAssertEqual(sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
      defer { sqlite3_finalize(row); sqlite3_close(raw) }
      XCTAssertEqual(sqlite3_prepare_v2(raw, "SELECT item_hash FROM knowledge_items", -1, &row, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(row), SQLITE_ROW)
      XCTAssertEqual(sqlite3_column_text(row, 0).map { String(cString: $0) }, expected)
      let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      XCTAssertEqual(try reopened.items(ids: ["memo"]), try database.items(ids: ["memo"]))
    }
  }
  func testSnapshotHashDoesNotWaitForOrBorrowHeldOperationMemo() throws {
    try fixture { database, _, secrets in
      let held = expectation(description: "writer operation held after memo ID was cached")
      let independentHash = expectation(description: "snapshot computed its own hash")
      let writerDone = expectation(description: "writer done"), readerDone = expectation(description: "reader done")
      let gate = DispatchSemaphore(value: 0)
      secrets.onIndexRead = { count in
        if count == 2 { held.fulfill(); _ = gate.wait(timeout: .now() + 5) }
        if count == 3 { independentHash.fulfill() }
      }
      DispatchQueue.global().async {
        do { _ = try database.items(ids: ["memo", "hold"]) } catch { XCTFail("Writer error: \(error)") }
        writerDone.fulfill()
      }
      let admission = XCTWaiter.wait(for: [held], timeout: 2)
      if admission == .completed {
        DispatchQueue.global().async {
          do { _ = try database.searchCandidates(query: "memo") } catch { XCTFail("Reader error: \(error)") }
          readerDone.fulfill()
        }
        let result = XCTWaiter.wait(for: [independentHash], timeout: 2)
        gate.signal()
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(XCTWaiter.wait(for: [writerDone, readerDone], timeout: 5), .completed)
      } else {
        gate.signal(); XCTAssertEqual(admission, .completed)
        _ = XCTWaiter.wait(for: [writerDone], timeout: 5)
      }
      // This checks hash admission only, not an end-to-end writer-held latency target.
    }
  }
}

// Synchronous read/write operation scopes; authored only unless run by XCTest.
extension AgentKnowledgeIndexKeyMemoTests {
  func testNestedScopeSharesOnlyItsOuterOperationAndDropsOnReturn() {
    let scope = AgentKnowledgeIndexOperationScope()
    var calculations = 0
    func hash() -> String { calculations += 1; return output }
    scope.withOperation {
      _ = scope.key("input", calculate: hash)
      scope.withOperation { for _ in 0..<20 { _ = scope.key("input", calculate: hash) } }
    }
    XCTAssertEqual(calculations, 1)
    scope.withOperation { _ = scope.key("input", calculate: hash) }
    XCTAssertEqual(calculations, 2)
  }

  func testThrowingScopeClearsMemoAndUnscopedHashesAreNeverRetained() {
    let scope = AgentKnowledgeIndexOperationScope()
    var calculations = 0
    func hash() -> String { calculations += 1; return output }
    XCTAssertThrowsError(try scope.withOperation {
      _ = scope.key("input", calculate: hash)
      throw Fault.injected
    })
    _ = scope.key("input", calculate: hash); _ = scope.key("input", calculate: hash)
    XCTAssertEqual(calculations, 3)
    scope.withOperation { _ = scope.key("input", calculate: hash) }
    XCTAssertEqual(calculations, 4)
  }

  func testDifferentDatabaseScopesNeverBorrowEachOthersEntryOnOneThread() {
    let first = AgentKnowledgeIndexOperationScope(), second = AgentKnowledgeIndexOperationScope()
    var calculations = 0
    func hash() -> String { calculations += 1; return output }
    first.withOperation {
      _ = first.key("input", calculate: hash)
      second.withOperation { _ = second.key("input", calculate: hash) }
      _ = first.key("input", calculate: hash)
    }
    XCTAssertEqual(calculations, 2)
    _ = first.key("input", calculate: hash)
    XCTAssertEqual(calculations, 3)
  }

  private final class Calculations {
    private let lock = NSLock()
    private var value = 0
    func increment() -> String { lock.lock(); defer { lock.unlock() }; value += 1; return String(repeating: "a", count: 64) }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
  }

  func testConcurrentReadersOwnSeparateEntriesWithoutBlockingEachOther() {
    let scope = AgentKnowledgeIndexOperationScope(), calls = Calculations()
    let entered = DispatchSemaphore(value: 0), finish = DispatchSemaphore(value: 0), group = DispatchGroup()
    for _ in 0..<2 {
      group.enter()
      DispatchQueue.global().async {
        defer { group.leave() }
        scope.withOperation {
          _ = scope.key("input", calculate: calls.increment)
          entered.signal()
          _ = finish.wait(timeout: .now() + 5)
          _ = scope.key("input", calculate: calls.increment)
        }
      }
    }
    let first = entered.wait(timeout: .now() + 2), second = entered.wait(timeout: .now() + 2)
    finish.signal(); finish.signal()
    XCTAssertEqual(first, .success); XCTAssertEqual(second, .success)
    XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
    XCTAssertEqual(calls.count, 2)
  }

  func testCommittedViewBracketsMemoAndDropsItAfterThrowingRead() throws {
    try fixture { _, url, _ in
      let scope = AgentKnowledgeIndexOperationScope()
      let view = try AgentKnowledgeCommittedReadView(fileURL: url, indexMemoScope: scope) {}
      defer { view.close() }
      var calculations = 0
      func hash() -> String { calculations += 1; return output }
      XCTAssertThrowsError(try view.read { _ in
        _ = scope.key("input", calculate: hash); _ = scope.key("input", calculate: hash)
        throw Fault.injected
      })
      try view.read { _ in
        _ = scope.key("input", calculate: hash)
        try view.read { _ in _ = scope.key("input", calculate: hash) }
      }
      XCTAssertEqual(calculations, 2)
    }
  }

  func testClosingViewInsideReadCannotRetainAnOperationMemo() throws {
    try fixture { _, url, _ in
      let scope = AgentKnowledgeIndexOperationScope()
      let view = try AgentKnowledgeCommittedReadView(fileURL: url, indexMemoScope: scope) {}
      defer { view.close() }
      var calculations = 0
      func hash() -> String { calculations += 1; return output }
      XCTAssertThrowsError(try view.read { _ in
        _ = scope.key("input", calculate: hash)
        view.close()
      })
      scope.withOperation { _ = scope.key("input", calculate: hash) }
      XCTAssertEqual(calculations, 2)
      XCTAssertThrowsError(try view.read { _ in XCTFail("Closed view admitted a read") })
    }
  }
}
