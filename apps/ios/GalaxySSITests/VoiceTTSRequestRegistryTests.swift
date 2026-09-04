import XCTest
@testable import GalaxySSI

final class VoiceTTSRequestRegistryTests: XCTestCase {
  func testStaleCompletionCannotFinishReplacementRequest() {
    let registry = VoiceTTSRequestRegistry()
    var completedTrace = ""
    registry.begin(VoiceTTSRequest(utteranceId: "utterance-old", traceId: "trace-old") {
      completedTrace = "trace-old"
    })
    registry.begin(VoiceTTSRequest(utteranceId: "utterance-new", traceId: "trace-new") {
      completedTrace = "trace-new"
    })

    XCTAssertNil(registry.finish("utterance-old"))
    XCTAssertEqual(completedTrace, "")

    let current = registry.finish("utterance-new")
    current?.onFinished()
    XCTAssertEqual(current?.traceId, "trace-new")
    XCTAssertEqual(completedTrace, "trace-new")
  }

  func testBlankOrUnknownCompletionCannotClaimActiveRequest() {
    let registry = VoiceTTSRequestRegistry()
    registry.begin(VoiceTTSRequest(utteranceId: "utterance-1", traceId: "trace-1") {})

    XCTAssertNil(registry.finish(nil))
    XCTAssertNil(registry.finish(""))
    XCTAssertNil(registry.finish("utterance-other"))
    XCTAssertTrue(registry.isActive("utterance-1"))
    XCTAssertEqual(registry.finish("utterance-1")?.traceId, "trace-1")
    XCTAssertFalse(registry.isActive("utterance-1"))
  }

  func testDiscardOnlyRemovesMatchingRequest() {
    let registry = VoiceTTSRequestRegistry()
    registry.begin(VoiceTTSRequest(utteranceId: "utterance-1", traceId: "trace-1") {})

    XCTAssertFalse(registry.discard("utterance-other"))
    XCTAssertTrue(registry.discard("utterance-1"))
    XCTAssertNil(registry.finish("utterance-1"))
  }

  func testClearDropsActiveRequestWithoutCompletingIt() {
    let registry = VoiceTTSRequestRegistry()
    var completed = false
    registry.begin(VoiceTTSRequest(utteranceId: "utterance-1", traceId: "trace-1") {
      completed = true
    })

    registry.clear()

    XCTAssertNil(registry.finish("utterance-1"))
    XCTAssertFalse(completed)
  }
}
