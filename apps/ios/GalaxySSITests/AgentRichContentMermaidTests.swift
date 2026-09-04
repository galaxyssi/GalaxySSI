import XCTest
@testable import GalaxySSI

final class AgentRichContentMermaidTests: XCTestCase {
  func testSingleMarkdownSourceLinkRemainsInlineWithoutWebpagePreview() throws {
    let blocks = AgentRichContentCodec.fromText(
      "Open [animated result](https://example.com/animation) in the output area."
    )

    XCTAssertEqual(blocks.count, 1)
    let text = try XCTUnwrap(blocks.first)
    XCTAssertEqual(text.type, .text)
    XCTAssertTrue(text.text.contains("https://example.com/animation"))
    XCTAssertFalse(blocks.contains { $0.type == .webpage })
  }

  func testMarkdownFenceBecomesDiagramInsteadOfCode() throws {
    let blocks = AgentRichContentCodec.fromText(
      """
      Architecture:

      ```mermaid
      flowchart TD
        A[Request] --> B[Agent]
      ```
      """
    )

    let diagram = try XCTUnwrap(blocks.first { $0.type == .mermaid })
    XCTAssertEqual(diagram.language, "mermaid")
    XCTAssertTrue(diagram.text.contains("A[Request] --> B[Agent]"))
    XCTAssertFalse(blocks.contains { $0.type == .code && $0.language == "mermaid" })
  }

  func testStructuredMermaidCodeIsPromoted() throws {
    let encoded = AgentRichContentCodec.encode([
      AgentRichBlock(
        id: "diagram",
        type: .code,
        text: "flowchart LR\nA --> B",
        language: "MERMAID"
      )
    ])

    let diagram = try XCTUnwrap(AgentRichContentCodec.decode(encoded).first)
    XCTAssertEqual(diagram.type, .mermaid)
    XCTAssertEqual(diagram.text, "flowchart LR\nA --> B")
  }

  func testStructuredTextExpandsEmbeddedDiagramAndPreservesSurroundingText() {
    let encoded = AgentRichContentCodec.encode([
      AgentRichBlock(
        id: "mixed",
        type: .text,
        text: "Before\n```mermaid\nflowchart TD\nA --> B\n```\nAfter",
        metadata: ["section": "final"]
      )
    ])

    let blocks = AgentRichContentCodec.decode(encoded)

    XCTAssertTrue(blocks.contains { $0.type == .mermaid })
    XCTAssertTrue(blocks.contains { $0.type == .text && $0.text == "Before" })
    XCTAssertTrue(blocks.contains { $0.type == .text && $0.text == "After" })
    XCTAssertTrue(blocks.allSatisfy { $0.metadata["section"] == "final" })
  }
}
