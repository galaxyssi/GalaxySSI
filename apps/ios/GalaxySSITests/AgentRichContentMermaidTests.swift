import XCTest
@testable import GalaxySSI

final class AgentRichContentMermaidTests: XCTestCase {
  func testMarkdownImagesBecomeRenderableImageBlocks() throws {
    let blocks = AgentRichContentCodec.fromText(
      "Before ![Mackerel](https://example.com/fish.jpg) after"
    )

    XCTAssertEqual(blocks.map(\.type), [.text, .image, .text])
    let image = try XCTUnwrap(blocks.first { $0.type == .image })
    XCTAssertEqual(image.title, "Mackerel")
    XCTAssertEqual(image.uri, "https://example.com/fish.jpg")
    XCTAssertEqual(image.metadata["markdown_image_source"], image.uri)
  }

  func testMarkdownImageParserPreservesLiteralAndUnsafeSources() {
    let literalCases = [
      "[Image](https://example.com/fish.jpg)",
      #"\![Image](https://example.com/fish.jpg)"#,
      "`![Image](https://example.com/fish.jpg)`",
      "![Image](file:///private/image.jpg)",
      "![Image](https://user:password@example.com/image.jpg)"
    ]
    for value in literalCases {
      XCTAssertEqual(AgentRichContentCodec.fromText(value).map(\.type), [.text], value)
    }
  }

  func testDecodedDesktopTextExpandsMarkdownImageWithStableMetadata() throws {
    let source = "![A](<https://example.com/fish_(1)?size=100&amp;x=2> \"Photo\")"
    let encoded = AgentRichContentCodec.encode([
      AgentRichBlock(id: "final", type: .text, text: source, metadata: ["origin": "desktop"])
    ])
    let image = try XCTUnwrap(AgentRichContentCodec.decode(encoded).first)

    XCTAssertEqual(image.type, .image)
    XCTAssertEqual(image.id, "final")
    XCTAssertEqual(image.uri, "https://example.com/fish_(1)?size=100&x=2")
    XCTAssertEqual(image.metadata["origin"], "desktop")
  }

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
