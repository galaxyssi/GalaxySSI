import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeStatisticsReadAdmissionTests: XCTestCase {
  private final class Secrets: GalaxySSISecretStore {
    private let lock = NSLock()
    private var values: [String: String] = [:], callback: (() -> Void)?
    func onNextIndexRead(_ work: @escaping () -> Void) { lock.lock(); callback = work; lock.unlock() }
    func setString(_ value: String, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = value }
    func string(account: String) -> String? {
      lock.lock()
      let value = values[account], work = account == "agent.knowledge.index.hmac256.v1" ? callback : nil
      if work != nil { callback = nil }
      lock.unlock(); work?(); return value
    }
    func delete(account: String) { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: account) }
  }
  private enum Fault: Error { case injected }
  private func item(_ id: String = "synthetic", updated: Int64 = 11) -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: id, kind: .document, title: "Synthetic", content: "needle body", source: "source", updatedAtMillis: updated)
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL, Secrets) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("knowledge.sqlite"), secrets = Secrets()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertTrue(database.replaceAll([item()]))
    try body(database, url, secrets)
  }
  private func sql(_ url: URL, _ query: String) throws {
    var raw: OpaquePointer?
    guard sqlite3_open(url.path, &raw) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_close_v2(raw) }
    guard sqlite3_exec(raw, query, nil, nil, nil) == SQLITE_OK else { throw Fault.injected }
  }

  func testStatisticsCompleteUnderHeldUncommittedWriterUsingPreviousCommittedCounters() throws {
    try fixture { database, _, secrets in
      let held = expectation(description: "catalog writer held"), finished = expectation(description: "writer finished")
      let read = expectation(description: "statistics read completed before writer release")
      let release = DispatchSemaphore(value: 0), joined = DispatchSemaphore(value: 0)
      secrets.onNextIndexRead { held.fulfill(); _ = release.wait(timeout: .now() + 10) }
      let next = [item(), item("second", updated: 22)]
      DispatchQueue.global().async { XCTAssertTrue(database.replaceAll(next)); finished.fulfill() }
      let admission = XCTWaiter.wait(for: [held], timeout: 3)
      if admission == .completed {
        DispatchQueue.global().async {
          do {
            let stats = try database.knowledgeStats()
            XCTAssertEqual(stats.itemCount, 1); XCTAssertEqual(stats.sourceCount, 1)
            XCTAssertEqual(stats.lastUpdatedAtMillis, 11); XCTAssertTrue(stats.countsComplete)
          } catch { XCTFail("Committed statistics read failed") }
          read.fulfill(); joined.signal()
        }
        let completed = XCTWaiter.wait(for: [read], timeout: 3)
        release.signal()
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertEqual(joined.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(completed, .completed)
        let current = try database.knowledgeStats()
        XCTAssertEqual(current.itemCount, 2); XCTAssertEqual(current.sourceCount, 1)
        XCTAssertEqual(current.lastUpdatedAtMillis, 22)
      } else {
        release.signal(); XCTAssertEqual(admission, .completed)
        _ = XCTWaiter.wait(for: [finished], timeout: 10)
      }
    }
  }

  func testReentrantStatisticsNeverReadTheirOwnUncommittedWriter() throws {
    try fixture { database, _, secrets in
      var rejected = false
      secrets.onNextIndexRead {
        do { _ = try database.knowledgeStats(); XCTFail("Uncommitted statistics admitted") }
        catch AgentKnowledgeDatabaseError.unavailable { rejected = true }
        catch { XCTFail("Unexpected statistics rejection") }
      }
      XCTAssertTrue(database.replaceAll([item(updated: 22)]))
      XCTAssertTrue(rejected)
      XCTAssertEqual(try database.knowledgeStats().lastUpdatedAtMillis, 22)
    }
  }

  func testMalformedCounterTypesAndWideFlagsBecomeUnavailableInsteadOfTruncatedTotals() throws {
    try fixture { database, url, _ in
      for mutation in ["UPDATE knowledge_item_count_state SET items=1.5",
        "UPDATE knowledge_source_directory_state SET groups=1.5",
        "UPDATE knowledge_item_count_state SET complete=4294967297",
        "UPDATE knowledge_source_directory_state SET complete=4294967297"] {
        // Deliberate synthetic corruption; production CHECK constraints are untouched.
        try sql(url, "PRAGMA ignore_check_constraints=ON; " + mutation)
        XCTAssertThrowsError(try database.knowledgeStats())
        let resolved = AgentKnowledgeStatisticsContext.resolve(try? database.knowledgeStats())
        XCTAssertTrue(resolved.countsUnavailable); XCTAssertFalse(resolved.countsComplete)
        XCTAssertNil(AgentKnowledgeStatisticsContext.parameters(resolved)["item_count"])
        XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(resolved)["knowledge_count_status"], "unavailable")
        try sql(url, "UPDATE knowledge_item_count_state SET items=1,complete=1; UPDATE knowledge_source_directory_state SET groups=1,complete=1")
      }
    }
  }

  func testSingleViewRetainsPartialFlagsAndExactWideIntegerMetadata() throws {
    try fixture { database, url, _ in
      try sql(url, "UPDATE knowledge_source_directory_state SET groups=0,complete=0")
      let partial = try database.knowledgeStats()
      XCTAssertEqual(partial.itemCount, 1); XCTAssertEqual(partial.sourceCount, 0)
      XCTAssertEqual(partial.lastUpdatedAtMillis, 11); XCTAssertFalse(partial.countsComplete)
      XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(partial)["knowledge_count_status"], "partial_indexing")
      // Wide synthetic metadata is precision coverage, not a large corpus fixture.
      try sql(url, "UPDATE knowledge_item_count_state SET items=9007199254740993; UPDATE knowledge_source_directory_state SET groups=9007199254740994,complete=1")
      let wide = try database.knowledgeStats()
      XCTAssertEqual(wide.itemCount, 9_007_199_254_740_993)
      XCTAssertEqual(wide.sourceCount, 9_007_199_254_740_994)
      XCTAssertTrue(wide.countsComplete)
      XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(wide)["item_count"], "9007199254740993")
      XCTAssertEqual(AgentKnowledgeStatisticsContext.parameters(wide)["source_count"], "9007199254740994")
    }
  }

  func testMetadataStatisticsDoNotRequestKnownLexicalRepair() throws {
    try fixture { _, url, secrets in
      let queue = DispatchQueue(label: "statistics-no-repair-fixture")
      queue.suspend()
      var resumed = false
      defer { if !resumed { queue.resume() }; queue.sync {} }
      let gate = AgentKnowledgeIndexRetryGate(queue: queue)
      let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets, indexRetryGate: gate)
      gate.markFailure()
      XCTAssertEqual(try database.knowledgeStats().itemCount, 1)
      // The metadata-only query must not already have queued a repair callback.
      XCTAssertTrue(gate.request { false })
      queue.resume(); resumed = true; queue.sync {}
    }
  }
}
