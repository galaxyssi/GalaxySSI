import XCTest
@testable import SignalASI

final class AgentRichSelectableParagraphsTests: XCTestCase {
  func testGroupsAdjacentSelectableBlocksAndKeepsInteractiveBlocksSeparate() {
    let blocks = [
      AgentRichBlock(id: "heading", type: .heading, text: "Heading"),
      AgentRichBlock(id: "text", type: .text, text: "Paragraph"),
      AgentRichBlock(id: "action", type: .actions),
      AgentRichBlock(id: "quote", type: .quote, text: "Quote"),
      AgentRichBlock(id: "list", type: .list, rows: [["bullet", "Item"]])
    ]

    let runs = AgentRichSelectableParagraphs.runs(blocks)

    XCTAssertEqual(runs.map(\.selectable), [true, false, true])
    XCTAssertEqual(runs.map { $0.blocks.map(\.id) }, [
      ["heading", "text"],
      ["action"],
      ["quote", "list"]
    ])
  }

  func testRendersOneSelectableStringAcrossParagraphKinds() {
    let blocks = [
      AgentRichBlock(id: "heading", type: .heading, text: "**Heading**", metadata: ["level": "1"]),
      AgentRichBlock(id: "quote", type: .quote, text: "Quoted"),
      AgentRichBlock(
        id: "list",
        type: .list,
        rows: [["checked", "Done"], ["2", "Next"]]
      ),
      AgentRichBlock(id: "divider", type: .divider)
    ]

    let rendered = AgentRichSelectableParagraphs.render(blocks)

    XCTAssertEqual(
      String(rendered.characters),
      "Heading\n\nQuoted\n\n\u{2713} Done\n2. Next\n\n\(String(repeating: "\u{2500}", count: 8))"
    )
  }

  func testInlineMarkdownRendererPreservesVisibleTextAndLink() {
    let rendered = AgentRichInlineMarkdownRenderer.render(
      "Use **bold** and [SignalASI](https://signalasi.com)."
    )

    XCTAssertEqual(String(rendered.characters), "Use bold and SignalASI.")
    XCTAssertTrue(rendered.runs.contains { $0.link?.absoluteString == "https://signalasi.com" })
  }
}
