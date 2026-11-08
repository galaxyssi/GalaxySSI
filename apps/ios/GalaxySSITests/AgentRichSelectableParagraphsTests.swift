import XCTest
import UIKit
@testable import GalaxySSI

final class AgentRichSelectableParagraphsTests: XCTestCase {
  @MainActor
  func testPeerSelectionDeleteInvokesOwningMessageWithoutEditingItsText() {
    let view = GalaxySSIPeerSelectionTextView()
    view.isEditable = false
    view.text = "Select this message"
    var deleted = 0
    view.onDeleteMessage = { deleted += 1 }
    let selector = #selector(UIResponderStandardEditActions.delete(_:))
    view.selectedRange = NSRange(location: 0, length: 0)
    XCTAssertFalse(view.canPerformAction(selector, withSender: nil))
    view.delete(nil)
    XCTAssertEqual(deleted, 0)
    view.selectedRange = NSRange(location: 0, length: 6)
    if #available(iOS 16.0, *) {
      XCTAssertFalse(view.canPerformAction(selector, withSender: nil))
      let menu = GalaxySSIPeerTextSelectionView.Coordinator().textView(view,
        editMenuForTextIn: view.selectedRange, suggestedActions: [])
      XCTAssertEqual(menu?.children.count, 1)
      XCTAssertTrue((menu?.children.first as? UIAction)?.attributes.contains(.destructive) == true)
    } else { XCTAssertTrue(view.canPerformAction(selector, withSender: nil)) }
    XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.cut(_:)), withSender: nil))
    XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil))
    view.delete(nil)
    XCTAssertEqual(deleted, 1)
    XCTAssertEqual(view.text, "Select this message")
    view.onDeleteMessage = nil
    view.delete(nil)
    XCTAssertEqual(deleted, 1)
  }

  @MainActor
  func testPeerSelectionMoreKeepsNativeItemsAndDoesNotDelete() {
    let view = GalaxySSIPeerSelectionTextView()
    view.isSelectable = true
    view.isEditable = false
    view.text = "First paragraph.\n\nSecond paragraph."
    view.moreTitle = "More"
    var opened = 0
    view.onMoreMessage = { opened += 1 }
    view.onDeleteMessage = { XCTFail("More must not delete the message") }
    let more = #selector(GalaxySSIPeerSelectionTextView.showPeerMessageActions(_:))
    view.selectedRange = NSRange(location: 0, length: 0)
    XCTAssertFalse(view.canPerformAction(more, withSender: nil))
    view.showPeerMessageActions(nil)
    XCTAssertEqual(opened, 0)
    view.selectedRange = NSRange(location: 6, length: 19)
    XCTAssertTrue(view.canPerformAction(more, withSender: nil))
    XCTAssertFalse(view.canPerformAction(#selector(UIResponderStandardEditActions.delete(_:)), withSender: nil))
    if #available(iOS 16.0, *) {
      let copy = UIAction(title: "Copy") { _ in }
      let menu = GalaxySSIPeerTextSelectionView.Coordinator().textView(view,
        editMenuForTextIn: view.selectedRange, suggestedActions: [copy])
      XCTAssertEqual(menu?.children.map(\.title), ["Copy", "More"])
    }
    view.showPeerMessageActions(nil)
    XCTAssertEqual(opened, 1)
    XCTAssertEqual(view.text, "First paragraph.\n\nSecond paragraph.")
  }

  @MainActor
  func testPeerVoiceSelectionUsesVerbatimParagraphsAndStableWidth() {
    let original = "One **literal** line\n\nSecond line"
    let rendered = GalaxySSIPeerTextRenderer.transcript(original, fontSize: 14, outgoing: true)
    XCTAssertEqual(rendered.string, original)
    XCTAssertEqual((rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .right)
    let source = original as NSString
    let selected = source.range(of: "Second")
    let paragraph = GalaxySSIParagraphSelectionPolicy.expansion(in: original, glyphOffset: selected.location,
      nativeSelection: selected)
    XCTAssertEqual(paragraph.map { source.substring(with: $0) }, "Second line")
    let size = GalaxySSIPeerTextRenderer.size(rendered, maximumWidth: 160)
    XCTAssertGreaterThan(size.height, 0)
    XCTAssertLessThanOrEqual(size.width, 160)
  }

  @MainActor
  func testPeerNativeRendererPreservesParagraphStylesLinksAndConstrainedWidth() {
    let blocks = [
      AgentRichBlock(id: "heading", type: .heading, text: "Heading", metadata: ["level": "1"]),
      AgentRichBlock(id: "text", type: .text, text: "Use **bold**, *italic*, `code` and [link](https://example.com)."),
      AgentRichBlock(id: "list", type: .list, rows: [["checked", "Done"], ["2", "Next"]])
    ]
    let rendered = GalaxySSIPeerTextRenderer.render(blocks, fontSize: 17)
    XCTAssertEqual(rendered.string, String(AgentRichSelectableParagraphs.render(blocks).characters))
    XCTAssertEqual((rendered.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize, 20)
    let link = (rendered.string as NSString).range(of: "link")
    XCTAssertEqual((rendered.attribute(.link, at: link.location, effectiveRange: nil) as? URL)?.absoluteString,
      "https://example.com")
    for width in [CGFloat(1), 160, 280] {
      let size = GalaxySSIPeerTextRenderer.size(rendered, maximumWidth: width)
      XCTAssertLessThanOrEqual(size.width, width)
      XCTAssertGreaterThan(size.height, 0)
    }
  }

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
      "Use **bold** and [GalaxySSI](https://galaxyssi.com)."
    )

    XCTAssertEqual(String(rendered.characters), "Use bold and GalaxySSI.")
    XCTAssertTrue(rendered.runs.contains { $0.link?.absoluteString == "https://galaxyssi.com" })
  }
}
