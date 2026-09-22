import XCTest
@testable import GalaxySSI

final class AgentRichContentMermaidTests: XCTestCase {
  func testFinalTextBlockExpandsMarkdownTableWithStableIdentity() throws {
    let markdown = """
    Results

    | Name | Value |
    | --- | ---: |
    | Apples | 3 |
    | Pears | 5 |
    """
    let encoded = AgentRichContentCodec.encode([
      AgentRichBlock(
        id: "desktop-final-text",
        type: .text,
        text: markdown,
        metadata: ["source": "desktop"]
      )
    ])

    let blocks = AgentRichContentCodec.decode(encoded)
    XCTAssertEqual(blocks.map(\.type), [.text, .table])
    XCTAssertEqual(blocks[0].id, "desktop-final-text")
    XCTAssertEqual(blocks[1].id, "desktop-final-text-markdown-1")
    XCTAssertEqual(blocks[1].columns, ["Name", "Value"])
    XCTAssertEqual(blocks[1].rows, [["Apples", "3"], ["Pears", "5"]])
    XCTAssertTrue(blocks.allSatisfy { $0.metadata["source"] == "desktop" })

    let reloaded = AgentRichContentCodec.decode(AgentRichContentCodec.encode(blocks))
    XCTAssertEqual(reloaded.map(\.id), blocks.map(\.id))
    XCTAssertEqual(reloaded.first(where: { $0.type == .table })?.rows, blocks[1].rows)
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
