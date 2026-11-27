import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeSourceWriteTimingTests: XCTestCase {
  private final class Secrets: GalaxySSISecretStore {
    private var values: [String: String] = [:]
    func setString(_ value: String, account: String) throws { values[account] = value }
    func string(account: String) -> String? { values[account] }
    func delete(account: String) { values.removeValue(forKey: account) }
  }
  private final class Fault: Error {}
  private func item(_ id: String = "synthetic-id", source: String = "synthetic-source", body: String = "new") -> AgentKnowledgeItem {
    AgentKnowledgeItem(id: id, kind: .document, title: "Synthetic title", content: body,
      source: source, summary: body, updatedAtMillis: 10)
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, AgentLatencyJournal, AgentLatencyTracer, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = AgentKnowledgeDatabase(fileURL: root.appendingPathComponent("knowledge.sqlite"), secrets: Secrets())
    XCTAssertTrue(database.replaceAll([item(body: "old")]))
    let journal = AgentLatencyJournal(fileURL: root.appendingPathComponent("timing.jsonl"))
    var tick: Int64 = 0
    let tracer = AgentLatencyTracer(journal: journal, monotonicNs: { tick += 1_000_000; return tick },
      wallClockMs: { 1 }, clockId: "0123456789abcdef0123456789abcdef")
    try body(database, journal, tracer, root)
  }
  private func timing(_ tracer: AgentLatencyTracer) -> AgentKnowledgeSourceWriteTiming {
    AgentKnowledgeSourceWriteTiming(timing: AgentRuntimeTiming(tracer: tracer), deferJournal: false)
  }
  @discardableResult
  private func replace(_ database: AgentKnowledgeDatabase, _ timing: AgentKnowledgeSourceWriteTiming,
    items: [AgentKnowledgeItem], beforeCommit: (AgentKnowledgeSourceStaging) throws -> Void = { _ in },
    afterMutation: (Int) throws -> Void = { _ in }) throws -> Int {
    var iterator = items.makeIterator()
    return try timing.measure(.total) {
      let result = try database.replaceSource("synthetic-source", next: { iterator.next() }, timing: timing,
        beforeCommit: beforeCommit, afterMutation: afterMutation)
      defer { result.stage.close() }
      return result.changed
    }
  }
  private func metric(_ phase: String, _ tracer: AgentLatencyTracer) throws -> AgentLatencyMetric {
    try XCTUnwrap(tracer.summary()["phone_runtime_knowledge_source_\(phase)_ms"])
  }

  func testSuccessfulProductionReplacementHasSevenNestedOpaqueSpans() throws {
    try fixture { database, journal, tracer, _ in
      XCTAssertEqual(try replace(database, timing(tracer), items: [item()]), 1)
      let points = journal.snapshot()
      XCTAssertEqual(points.count, 14)
      XCTAssertEqual(Set(points.map(\.traceId)).count, 1)
      XCTAssertEqual(Set(points.compactMap(\.operationId)).count, 7)
      for phase in AgentKnowledgeSourceWriteTiming.Phase.allCases {
        XCTAssertEqual(try metric(phase.rawValue, tracer).count, 1)
      }
      let stages = points.map(\.stage)
      XCTAssertEqual(stages.first, .phoneRuntimeKnowledgeSourceTotalStarted)
      XCTAssertEqual(stages.last, .phoneRuntimeKnowledgeSourceTotalFinished)
      let applyEnd = try XCTUnwrap(stages.firstIndex(of: .phoneRuntimeKnowledgeSourceApplyFinished))
      let observeStart = try XCTUnwrap(stages.firstIndex(of: .phoneRuntimeKnowledgeSourceObserveStarted))
      let observeEnd = try XCTUnwrap(stages.firstIndex(of: .phoneRuntimeKnowledgeSourceObserveFinished))
      let commitEnd = try XCTUnwrap(stages.firstIndex(of: .phoneRuntimeKnowledgeSourceCommitFinished))
      XCTAssertLessThan(applyEnd, observeStart); XCTAssertLessThan(observeEnd, commitEnd)
      XCTAssertEqual(try database.all().first?.content, "new")
      XCTAssertFalse(try database.pendingSourceObservations().isEmpty)
    }
  }

  func testTelemetryContainsNoSourceIdentityBodyPathOrErrorText() throws {
    try fixture { database, journal, tracer, root in
      _ = try replace(database, timing(tracer), items: [item(body: "synthetic-private-body")])
      let encoded = String(decoding: try JSONEncoder().encode(journal.snapshot()), as: UTF8.self)
      for forbidden in ["synthetic-source", "synthetic-id", "Synthetic title", "synthetic-private-body", root.path] {
        XCTAssertFalse(encoded.contains(forbidden))
      }
      XCTAssertTrue(journal.snapshot().allSatisfy(AgentLatencyContract.valid))
    }
  }

  func testSeparateReplacementsHaveIndependentCorrelationEvenForSameSource() throws {
    try fixture { database, journal, tracer, _ in
      _ = try replace(database, timing(tracer), items: [item()])
      _ = try replace(database, timing(tracer), items: [item(body: "next")])
      XCTAssertEqual(Set(journal.snapshot().map(\.traceId)).count, 2)
      XCTAssertEqual(try metric("total", tracer).count, 2)
    }
  }

  func testInputFailurePreservesExceptionAndDoesNotEnterPreparationOrWriter() throws {
    try fixture { database, journal, tracer, _ in
      let timing = timing(tracer), fault = Fault()
      XCTAssertThrowsError(try timing.measure(.total) {
        try database.replaceSource("synthetic-source", next: { throw fault }, timing: timing)
      }) { XCTAssertTrue(($0 as? Fault) === fault) }
      XCTAssertEqual(journal.snapshot().count, 4)
      XCTAssertEqual(try metric("stage", tracer).unsuccessful, 1)
      XCTAssertEqual(try metric("total", tracer).count, 0)
      XCTAssertEqual(try metric("prepare", tracer).count, 0)
      XCTAssertEqual(try database.all().first?.content, "old")
    }
  }

  func testPreparationFailureDoesNotEmitCommit() throws {
    try fixture { database, journal, tracer, _ in
      let timing = timing(tracer), fault = Fault()
      var next: AgentKnowledgeItem? = item()
      XCTAssertThrowsError(try timing.measure(.total) {
        try database.prepareSourceReplacement("synthetic-source", next: { defer { next = nil }; return next },
          timing: timing, onPage: { _ in throw fault })
      }) { XCTAssertTrue(($0 as? Fault) === fault) }
      XCTAssertEqual(try metric("prepare", tracer).unsuccessful, 1)
      XCTAssertFalse(journal.snapshot().contains { $0.stage == .phoneRuntimeKnowledgeSourceCommitStarted })
      XCTAssertEqual(try database.all().first?.content, "old")
    }
  }

  func testOwnershipFailureIsNotSuccessfulApplyAndDoesNotMutateSource() throws {
    try fixture { database, journal, tracer, _ in
      XCTAssertTrue(database.replaceAll([item(body: "old"), item("claimed", source: "other", body: "other")]))
      XCTAssertThrowsError(try replace(database, timing(tracer), items: [item("claimed")]))
      XCTAssertEqual(try metric("ownership", tracer).unsuccessful, 1)
      XCTAssertEqual(try metric("commit", tracer).unsuccessful, 1)
      XCTAssertFalse(journal.snapshot().contains { $0.stage == .phoneRuntimeKnowledgeSourceApplyStarted })
      XCTAssertEqual(try database.all().count, 2)
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
    }
  }

  func testApplyCancellationRollsBackAndIsExcludedFromSuccessPercentiles() throws {
    try fixture { database, journal, tracer, _ in
      XCTAssertThrowsError(try replace(database, timing(tracer), items: [item()], afterMutation: { _ in throw CancellationError() })) {
        XCTAssertTrue($0 is CancellationError)
      }
      for phase in ["total", "commit", "apply"] {
        let value = try metric(phase, tracer)
        XCTAssertEqual(value.count, 0); XCTAssertEqual(value.unsuccessful, 1); XCTAssertNil(value.p95Ms)
      }
      XCTAssertTrue(journal.snapshot().filter { $0.outcome == "cancelled" }.count == 3)
      XCTAssertEqual(try database.all().first?.content, "old")
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
    }
  }

  func testPrecommitFailureDoesNotMisreportACompletedObservationAsDurableCommit() throws {
    try fixture { database, _, tracer, _ in
      let fault = Fault()
      XCTAssertThrowsError(try replace(database, timing(tracer), items: [item()], beforeCommit: { _ in throw fault })) {
        XCTAssertTrue(($0 as? Fault) === fault)
      }
      XCTAssertEqual(try metric("observe", tracer).count, 1)
      XCTAssertEqual(try metric("commit", tracer).count, 0)
      XCTAssertEqual(try metric("total", tracer).unsuccessful, 1)
      XCTAssertEqual(try database.all().first?.content, "old")
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
    }
  }

  func testNoopDoesNotClaimObservationAndEmptySequenceRetainsDeletionSemantics() throws {
    try fixture { database, journal, tracer, _ in
      XCTAssertEqual(try replace(database, timing(tracer), items: [item(body: "old")]), 0)
      XCTAssertEqual(journal.snapshot().count, 12)
      XCTAssertEqual(try metric("observe", tracer).count, 0)
      XCTAssertEqual(try replace(database, timing(tracer), items: []), 1)
      XCTAssertTrue(try database.all().isEmpty)
      XCTAssertEqual(try metric("observe", tracer).count, 1)
    }
  }

  func testBrokenJournalDoesNotRetryOrPreventSuccessfulCanonicalWrite() throws {
    try fixture { database, _, _, root in
      let blocker = root.appendingPathComponent("not-a-directory")
      try Data([0]).write(to: blocker)
      let journal = AgentLatencyJournal(fileURL: blocker.appendingPathComponent("timing.jsonl"))
      let tracer = AgentLatencyTracer(journal: journal)
      var calls = 0, next: AgentKnowledgeItem? = item()
      let timing = timing(tracer)
      let result = try timing.measure(.total) {
        try database.replaceSource("synthetic-source", next: {
          calls += 1; defer { next = nil }; return next
        }, timing: timing)
      }
      result.stage.close()
      XCTAssertEqual(calls, 2); XCTAssertEqual(result.changed, 1)
      XCTAssertEqual(try database.all().first?.content, "new")
    }
  }

  func testDisabledTimingExecutesOnceAndPreservesThrownIdentity() throws {
    var calls = 0
    XCTAssertEqual(AgentKnowledgeSourceWriteTiming.disabled.measure(.total) { calls += 1; return 7 }, 7)
    let fault = Fault()
    XCTAssertThrowsError(try AgentKnowledgeSourceWriteTiming.disabled.measure(.stage) { () throws -> Int in
      calls += 1; throw fault
    }) { XCTAssertTrue(($0 as? Fault) === fault) }
    XCTAssertEqual(calls, 2)
  }

  func testMissingFinishRemainsIncompleteNotSuccessful() throws {
    try fixture { _, _, tracer, _ in
      tracer.recordOpaque(taskId: "synthetic-operation", stage: .phoneRuntimeKnowledgeSourceCommitStarted, operationId: "synthetic-span")
      let value = try metric("commit", tracer)
      XCTAssertEqual(value.incomplete, 1); XCTAssertEqual(value.count, 0); XCTAssertNil(value.p99Ms)
    }
  }

  func testRevisionConflictDoesNotEnterOwnershipOrApply() throws {
    try fixture { database, journal, tracer, _ in
      let timing = timing(tracer)
      var next: AgentKnowledgeItem? = item()
      let prepared = try database.prepareSourceReplacement("synthetic-source", next: { defer { next = nil }; return next }, timing: timing)
      defer { prepared.close() }
      XCTAssertTrue(database.replaceAll([item(body: "concurrent")]))
      XCTAssertThrowsError(try timing.measure(.total) { try database.commitSourceReplacement(prepared, timing: timing) }) {
        XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementChanged)
      }
      XCTAssertEqual(try metric("commit", tracer).unsuccessful, 1)
      XCTAssertFalse(journal.snapshot().contains { $0.stage == .phoneRuntimeKnowledgeSourceOwnershipStarted })
      XCTAssertEqual(try database.all().first?.content, "concurrent")
    }
  }

  func testObservationOutboxFailureRollsBackAndDoesNotBlameApply() throws {
    try fixture { database, _, tracer, root in
      var connection: OpaquePointer?
      XCTAssertEqual(sqlite3_open(root.appendingPathComponent("knowledge.sqlite").path, &connection), SQLITE_OK)
      defer { sqlite3_close(connection) }
      XCTAssertEqual(sqlite3_exec(connection, "CREATE TRIGGER synthetic_observe_failure BEFORE INSERT ON knowledge_source_observations BEGIN SELECT RAISE(ABORT,'synthetic'); END", nil, nil, nil), SQLITE_OK)
      XCTAssertThrowsError(try replace(database, timing(tracer), items: [item()]))
      XCTAssertEqual(try metric("apply", tracer).count, 1)
      XCTAssertEqual(try metric("observe", tracer).unsuccessful, 1)
      XCTAssertEqual(try metric("commit", tracer).unsuccessful, 1)
      XCTAssertEqual(try metric("total", tracer).count, 0)
      XCTAssertEqual(try database.all().first?.content, "old")
      XCTAssertTrue(try database.pendingSourceObservations().isEmpty)
    }
  }
}
