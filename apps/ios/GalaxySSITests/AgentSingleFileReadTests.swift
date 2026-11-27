import XCTest
@testable import GalaxySSI

final class AgentSingleFileReadTests: XCTestCase {
  func testOnlyExplicitStructuredModelReportIsAccepted() throws {
    let report = try AgentSingleFileRead.parse(#"{"result":"unreadable","reply":"The selected scan is blurred."}"#)
    XCTAssertEqual(report.result, .unreadable)
    XCTAssertEqual(report.reply, "The selected scan is blurred.")
    for invalid in ["The file is recognized.", #"{"result":"recognized"}"#,
      #"{"result":"recognized","reply":"","actions":[]}"#,
      #"{"result":"stored","reply":"Delivered"}"#,
      #"{"result":true,"reply":"Yes"}"#,
      #"{"result":"recognized","reply":"```galaxyssi-rich"}"#] {
      XCTAssertThrowsError(try AgentSingleFileRead.parse(invalid))
    }
    XCTAssertThrowsError(try AgentSingleFileRead.parse(String(repeating: "x", count: 131_073)))
  }
  func testOpenAIRequestRetainsOneImageButNoToolsOrInheritedSystemInstruction() throws {
    let pixels: [[String: Any]] = [["type": "image_url", "image_url": ["url": "data:image/png;base64,synthetic"]]]
    let request = try fixture(.openAICompatible, ["messages": [["role": "system", "content": "old"],
      ["role": "user", "content": pixels]], "tools": [["type": "function"]], "tool_choice": "auto"])
    let isolated = try AgentSingleFileRead.isolatedRequest(request, system: "isolated")
    let body = try object(isolated)
    XCTAssertNil(body["tools"]); XCTAssertNil(body["tool_choice"])
    let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[0]["content"] as? String, "isolated")
    XCTAssertEqual(try JSONSerialization.data(withJSONObject: messages[1]["content"]!, options: [.sortedKeys]),
      try JSONSerialization.data(withJSONObject: pixels, options: [.sortedKeys]))
  }
  func testAnthropicAndGeminiRequestsDoNotAdvertiseTools() throws {
    for (provider, body) in [(ModelStreamProvider.anthropic, ["messages": [["role": "user", "content": "one file"]], "system": "old", "tools": []] as [String: Any]),
      (.gemini, ["contents": [["role": "user", "parts": [["text": "one file"]]]], "tools": [], "toolConfig": [:]] as [String: Any])] {
      let value = try object(AgentSingleFileRead.isolatedRequest(fixture(provider, body), system: "isolated"))
      XCTAssertNil(value["tools"]); XCTAssertNil(value["toolConfig"])
    }
  }
  func testUnexpectedHistoryIsRejectedRatherThanSent() throws {
    let request = try fixture(.openAICompatible, ["messages": [["role": "system", "content": "system"],
      ["role": "user", "content": "previous private question"], ["role": "assistant", "content": "old answer"],
      ["role": "user", "content": "selected file"]]])
    XCTAssertThrowsError(try AgentSingleFileRead.isolatedRequest(request, system: "isolated"))
  }
  func testBusyTransferAndRecognizedFileCannotStartAnotherInterpretation() {
    let transfer = String(repeating: "a", count: 64)
    var receipt = AgentFileReceipt()
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .uploading, fingerprint: "synthetic"))
    XCTAssertFalse(receipt.beginRead(turn: "read", now: 1))
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .failed))
    XCTAssertFalse(receipt.beginRead(turn: "read", now: 1))
    XCTAssertTrue(receipt.fold(transfer: transfer, state: .stored))
    XCTAssertTrue(receipt.beginRead(turn: "read", now: 1))
    XCTAssertTrue(receipt.report(turn: "read", original: "original", recognized: true))
    XCTAssertFalse(receipt.beginRead(turn: "next", now: 60_001))
  }
  private func fixture(_ provider: ModelStreamProvider, _ body: [String: Any]) throws -> ModelStreamRequest {
    .init(requestId: "fixture-request", provider: provider, endpoint: "https://example.invalid/model", headers: [:],
      bodyJson: String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self))
  }
  private func object(_ request: ModelStreamRequest) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.bodyJson.utf8)) as? [String: Any])
  }
}
