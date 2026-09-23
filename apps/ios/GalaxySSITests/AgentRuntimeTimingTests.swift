import XCTest
@testable import GalaxySSI

final class AgentRuntimeTimingTests: XCTestCase {
  func testRuntimeTimingRecordsIndependentOpaqueSpans() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentRuntimeTimingTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var ticks: [Int64] = [10_000_000, 20_000_000, 30_000_000, 50_000_000]
    let tracer = AgentLatencyTracer(
      journal: AgentLatencyJournal(fileURL: root.appendingPathComponent("runtime.jsonl")),
      monotonicNs: { ticks.removeFirst() },
      wallClockMs: { 1 },
      clockId: "0123456789abcdef0123456789abcdef"
    )
    let timing = AgentRuntimeTiming(tracer: tracer)

    XCTAssertEqual(
      timing.measure(taskId: "task", phase: .actionDispatch) { "first" },
      "first"
    )
    XCTAssertEqual(
      timing.measure(taskId: "task", phase: .actionDispatch) { "second" },
      "second"
    )

    let metric = try XCTUnwrap(tracer.summary()["phone_runtime_action_dispatch_ms"])
    XCTAssertEqual(metric.count, 2)
    XCTAssertEqual(metric.incomplete, 0)
    XCTAssertEqual(metric.unsuccessful, 0)
    XCTAssertEqual(metric.p50Ms, 10)
    XCTAssertEqual(metric.p95Ms, 20)
  }

  func testFailedAndCancelledSpansDoNotEnterSuccessfulPercentiles() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgentRuntimeTimingOutcomeTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var tick: Int64 = 0
    let tracer = AgentLatencyTracer(
      journal: AgentLatencyJournal(fileURL: root.appendingPathComponent("runtime.jsonl")),
      monotonicNs: { tick += 1_000_000; return tick },
      wallClockMs: { 1 },
      clockId: "fedcba9876543210fedcba9876543210"
    )
    let timing = AgentRuntimeTiming(tracer: tracer)

    XCTAssertFalse(timing.measure(
      taskId: "failed-task",
      phase: .resultVerify,
      outcome: { $0 ? "completed" : "failed" },
      operation: { false }
    ))
    XCTAssertThrowsError(try timing.measure(
      taskId: "cancelled-task",
      phase: .resultVerify,
      operation: { () throws -> String in throw CancellationError() }
    ))

    let metric = try XCTUnwrap(tracer.summary()["phone_runtime_result_verify_ms"])
    XCTAssertEqual(metric.count, 0)
    XCTAssertEqual(metric.incomplete, 0)
    XCTAssertEqual(metric.unsuccessful, 2)
    XCTAssertNil(metric.p50Ms)
  }

  func testMissingTaskIdentityDoesNotTouchTracer() {
    var calls = 0
    let timing = AgentRuntimeTiming(tracer: nil)
    let result = timing.measure(taskId: "", phase: .screenObserve) {
      calls += 1
      return "screen"
    }

    XCTAssertEqual(result, "screen")
    XCTAssertEqual(calls, 1)
  }
}
