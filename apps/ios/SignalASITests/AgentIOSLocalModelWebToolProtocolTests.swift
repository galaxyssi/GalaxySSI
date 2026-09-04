import XCTest
@testable import SignalASI

final class AgentIOSLocalModelWebToolProtocolTests: XCTestCase {
  func testDecodeAcceptsAnswerOrReadOnlyWebCalls() throws {
    let inference = LocalModelInferenceResult(
      text: "",
      profileId: "fixture",
      backend: "test",
      smeAvailable: false,
      elapsedMillis: 10
    )
    let answer = try AgentIOSLocalModelWebToolProtocol.decode(
      #"{"answer":"Stable answer","tool_calls":[]}"#,
      inference: inference
    )
    let call = try AgentIOSLocalModelWebToolProtocol.decode(
      #"{"answer":"","tool_calls":[{"name":"signalasi.web.intelligence.search","arguments":{"query":"current release"}}]}"#,
      inference: inference
    )

    XCTAssertEqual(answer.assistantText, "Stable answer")
    XCTAssertEqual(call.toolCalls.first?.toolId, AgentIOSWebIntelligenceNativeToolCatalog.search)
    XCTAssertEqual(call.toolCalls.first?.arguments["query"], .string("current release"))
  }

  func testToolAllowlistExcludesMutatingDownloads() {
    XCTAssertTrue(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSWebMediaNativeToolCatalog.webFetch))
    XCTAssertFalse(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSWebMediaNativeToolCatalog.webDownload))
    XCTAssertFalse(AgentIOSLocalModelWebToolProtocol.toolIDs.contains(AgentIOSWebMediaNativeToolCatalog.fileDownload))
  }
}
