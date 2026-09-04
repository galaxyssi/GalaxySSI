import XCTest
@testable import GalaxySSI

final class URLSessionCloudModelStreamClientTests: XCTestCase {
  func testSSEFrameAccumulatorCombinesEventAndMultilineData() {
    let accumulator = ModelStreamFrameAccumulator(transport: .sse)
    var frames: [ModelStreamFrame] = []

    frames += accumulator.accept(line: ": heartbeat")
    frames += accumulator.accept(line: "event: response.output_text.delta")
    frames += accumulator.accept(line: #"data: {"delta":"hel"}"#)
    frames += accumulator.accept(line: #"data: {"delta":"lo"}"#)
    frames += accumulator.accept(line: "")

    XCTAssertEqual(
      frames,
      [
        ModelStreamFrame(
          eventName: "response.output_text.delta",
          data: #"{"delta":"hel"}"# + "\n" + #"{"delta":"lo"}"#
        )
      ]
    )
  }

  func testSSEFrameAccumulatorFlushesTrailingDataWithoutBlankLine() {
    let accumulator = ModelStreamFrameAccumulator(transport: .sse)

    _ = accumulator.accept(line: #"data: {"choices":[]}"#)

    XCTAssertEqual(
      accumulator.finish(),
      ModelStreamFrame(eventName: nil, data: #"{"choices":[]}"#)
    )
  }

  func testSSEFrameAccumulatorAcceptsBareJsonLines() {
    let accumulator = ModelStreamFrameAccumulator(transport: .sse)

    _ = accumulator.accept(line: #"{"choices":[{"delta":{}}]}"#)
    let frames = accumulator.accept(line: "")

    XCTAssertEqual(
      frames,
      [ModelStreamFrame(eventName: nil, data: #"{"choices":[{"delta":{}}]}"#)]
    )
  }

  func testJsonLineAccumulatorIgnoresBlankLinesAndTrimsPayload() {
    let accumulator = ModelStreamFrameAccumulator(transport: .jsonLines)

    XCTAssertEqual(accumulator.accept(line: "   "), [])
    XCTAssertEqual(
      accumulator.accept(line: #"  {"text":"hi"}  "#),
      [ModelStreamFrame(eventName: nil, data: #"{"text":"hi"}"#)]
    )
  }

  func testEmissionStateSequencesIncrease() {
    let state = ModelStreamEmissionState()

    XCTAssertEqual(state.nextSequence(), 1)
    XCTAssertEqual(state.nextSequence(), 2)
  }
}
