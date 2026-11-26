import Foundation
import XCTest
@testable import GalaxySSI

final class CloudWebFallbackTests: XCTestCase {
  func testFallbackKeepsCompleteSourceURLsThroughReferenceLengthBoundary() {
    let first = address(length: 2_049), second = address(length: 4_096)
    let result = fallback(["results": .array([
      .object(["url": .string(first), "title": .string("First")]),
      .object(["url": .string(second), "title": .string("Second")])])])
    XCTAssertTrue(result.contains("(<\(first)>)"))
    XCTAssertTrue(result.contains("(<\(second)>)"))
    XCTAssertFalse(result.contains("(<\(String(second.prefix(2_048)))>)"))
  }

  func testFallbackRejectsOversizedURLsRatherThanInventingTruncatedSources() {
    let oversized = address(length: 4_097)
    let result = fallback(["results": .array([.object(["url": .string(oversized), "title": .string("Oversized")])])])
    XCTAssertFalse(result.contains("https://source.test/"))
    XCTAssertTrue(result.hasPrefix("No reliable web evidence is available yet."))
  }

  func testFallbackDoesNotPromotePluralOrSingularImageObjectsToSourcePages() {
    let page = "https://source.test/page", media = "https://cdn.test/photo.jpg"
    let image: AgentMcpJSONValue = .object(["url": .string(media), "title": .string("Image candidate")])
    let result = fallback(["results": .array([.object(["url": .string(page), "title": .string("Source page"),
      "image": image, "images": .array([image])])]), "images": .array([image])])
    XCTAssertTrue(result.contains(page))
    XCTAssertFalse(result.contains(media))
    XCTAssertFalse(result.contains("Image candidate"))
    XCTAssertFalse(fallback(["images": .array([image])]).contains(media))
  }

  func testFallbackRetainsDedupSixSourceBoundHTTPSAndMessageOverrides() {
    let rows: [AgentMcpJSONValue] = (0..<8).map {
      .object(["url": .string("https://source.test/\($0)"), "title": .string("Source \($0)")])
    }
    let input: AgentMcpJSONObject = ["results": .array(rows + [rows[0], .object(["url": .string("http://insecure.test/")])])]
    let encoded = AgentMcpJSONCodec.stringify(input)
    let result = CloudWebGrounding.evidenceFallback(results: [("web_search", encoded)], sourcesMessage: "Custom heading", language: "en")
    XCTAssertTrue(result.hasPrefix("Custom heading"))
    XCTAssertEqual(result.components(separatedBy: "\n- ").count - 1, 6)
    XCTAssertEqual(result.components(separatedBy: "https://source.test/0").count - 1, 1)
    XCTAssertFalse(result.contains("insecure.test"))
    XCTAssertEqual(CloudWebGrounding.evidenceFallback(results: [], emptyMessage: "Custom empty", language: "zh-CN"), "Custom empty")
  }

  func testFallbackUsesIncompleteSynthesisCopyAndConfiguredInterfaceLanguage() {
    let input: AgentMcpJSONObject = ["url": .string("https://source.test/page")]
    let encoded = AgentMcpJSONCodec.stringify(input)
    let english = CloudWebGrounding.evidenceFallback(results: [("web_search", encoded)], language: "en")
    XCTAssertTrue(english.hasPrefix("These sources were retrieved, but a reliable synthesis is not complete:"))
    let chinese = CloudWebGrounding.evidenceFallback(results: [("web_search", encoded)], language: "zh-CN")
    XCTAssertNotEqual(chinese, english)
    XCTAssertTrue(chinese.contains("https://source.test/page"))
    XCTAssertNotEqual(CloudWebGrounding.evidenceFallback(results: [], language: "zh-CN"),
      CloudWebGrounding.evidenceFallback(results: [], language: "en"))
  }

  func testInlineEvidenceGuidanceStaysRequestFocusedAndUntrusted() {
    let call = CloudWebGrounding.InlineToolCall(name: "web_image_search", arguments: ["query": .string("exact subject")])
    let prompt = CloudWebGrounding.inlineEvidenceMessage([(call, "{\"status\":\"completed\"}")])
    for required in ["untrusted", "Discard off-topic results", "only exact Evidence Pack URLs", "not visual verification", "without duplicating Markdown images"] {
      XCTAssertTrue(prompt.contains(required), required)
    }
  }

  private func fallback(_ object: AgentMcpJSONObject) -> String {
    CloudWebGrounding.evidenceFallback(results: [("web_search", AgentMcpJSONCodec.stringify(object))], language: "en")
  }
  private func address(length: Int) -> String {
    let base = "https://source.test/"
    return base + String(repeating: "a", count: length - base.count)
  }
}
