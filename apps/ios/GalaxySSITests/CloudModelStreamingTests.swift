import XCTest
@testable import GalaxySSI

final class CloudModelStreamingTests: XCTestCase {
  func testModelStreamRequestAllowsHttpsAndLoopbackOnly() {
    let request = ModelStreamRequest(
      requestId: "request-1",
      provider: .openAICompatible,
      endpoint: "https://api.example.test/v1/chat/completions",
      headers: ["Authorization": "Bearer token"],
      bodyJson: #"{"stream":true}"#
    )

    XCTAssertEqual(request.requestId, "request-1")
    XCTAssertEqual(request.transport, .sse)
    XCTAssertEqual(request.connectTimeoutMs, 20_000)
    XCTAssertEqual(request.readTimeoutMs, 300_000)
  }

  func testUiMergerPublishesFirstDeltaThrottlesAndFlushesCompletion() {
    let merger = ModelStreamUiMerger(minUpdateIntervalMs: 80)

    let first = merger.offer(sequence: 1, delta: "Hel", nowMs: 1_000)
    let throttled = merger.offer(sequence: 2, delta: "lo", nowMs: 1_030)
    let published = merger.offer(sequence: 3, delta: " there", nowMs: 1_100)
    let complete = merger.flush(nowMs: 1_120, complete: true)

    XCTAssertEqual(first, ModelStreamUiUpdate(text: "Hel", firstDelta: true, complete: false))
    XCTAssertNil(throttled)
    XCTAssertEqual(published, ModelStreamUiUpdate(text: "Hello there", firstDelta: false, complete: false))
    XCTAssertEqual(complete, ModelStreamUiUpdate(text: "Hello there", firstDelta: false, complete: true))
  }

  func testUiMergerIgnoresStaleSequenceAndCapsText() {
    let merger = ModelStreamUiMerger(minUpdateIntervalMs: 16, maxCharacters: 4_096)
    let oversized = String(repeating: "a", count: 4_200)

    _ = merger.offer(sequence: 2, delta: oversized, nowMs: 100)
    XCTAssertNil(merger.offer(sequence: 1, delta: "stale", nowMs: 200))

    XCTAssertEqual(merger.snapshot().count, 4_096)
    XCTAssertTrue(merger.snapshot().allSatisfy { $0 == "a" })
  }

  func testToolCallDeltaAssemblerMergesNonRepeatedDeltasInIndexOrder() {
    let assembler = ToolCallDeltaAssembler()

    assembler.accept(ToolCallPayload(callId: "", index: 1, nameDelta: "search"))
    assembler.accept(ToolCallPayload(callId: "call-0", index: 0, nameDelta: "open"))
    assembler.accept(ToolCallPayload(callId: "call-1", index: 1, nameDelta: "search"))
    assembler.accept(ToolCallPayload(callId: "call-1", index: 1, argumentsDelta: #"{"q":"sig"#))
    assembler.accept(ToolCallPayload(callId: "call-1", index: 1, argumentsDelta: #"nal"}"#))

    XCTAssertEqual(
      assembler.completedCalls(),
      [
        AssembledToolCall(callId: "call-0", index: 0, name: "open", argumentsJson: "{}"),
        AssembledToolCall(callId: "call-1", index: 1, name: "search", argumentsJson: #"{"q":"signal"}"#),
      ]
    )
  }

  func testToolCallDeltaAssemblerClearsState() {
    let assembler = ToolCallDeltaAssembler()
    assembler.accept(ToolCallPayload(callId: "call-1", index: 0, nameDelta: "search"))

    XCTAssertFalse(assembler.completedCalls().isEmpty)
    assembler.clear()
    XCTAssertTrue(assembler.completedCalls().isEmpty)
  }

  func testStreamEventExposesRequestId() {
    let event = ModelStreamEvent.textDelta(
      ModelStreamTextDelta(
        requestId: "request-1",
        sequence: 7,
        text: "hello",
        receivedAtElapsedMs: 123
      )
    )

    XCTAssertEqual(event.requestId, "request-1")
  }
}
