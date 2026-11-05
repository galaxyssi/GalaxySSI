import XCTest
@testable import GalaxySSI

final class AgentRichContentMermaidTests: XCTestCase {
  func testDeclaredHTMLRequiresClosingFenceAndPreservesCompleteProgram() throws {
    let program = "<!doctype html>\n<html><body><script>\n" +
      String(repeating: "window.frame = 1;\n", count: 720) + "</script></body></html>"
    let declared = AgentRichContentCodec.fromText("Intro\n\n```galaxyssi-html\n\(program)\n```\nAfter")
    XCTAssertEqual(declared.map(\.type), [.text, .html, .text])
    XCTAssertEqual(try XCTUnwrap(declared.first(where: { $0.type == .html })).text, program)
    XCTAssertEqual(AgentRichContentCodec.fromText("```html\n\(program)\n```").first?.type, .code)
    XCTAssertEqual(AgentRichContentCodec.fromText("```galaxyssi-html\n\(program)").first?.type, .code)
    XCTAssertFalse(AgentVisualOutputPolicy.isCompleteHTML("<html><script>run()</html>"))
    XCTAssertFalse(AgentVisualOutputPolicy.isCompleteHTML("<html>Unclosed"))
    XCTAssertTrue(AgentRichBlock(id: "large", type: .html,
      text: "<html>" + String(repeating: "a", count: 32_000) + "</html>").text.isEmpty)
  }

  func testPrivateHTMLAttachmentChecksExactBytesAndRejectsForgedReference() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let materializer = AgentRichContentMaterializer(directoryURL: directory)
    let html = "<html><body><script>window.frame=1;</script></body></html>"
    let raw = AgentRichBlock(id: "animation", type: .html, title: "Animation", text: html)
    let stored = try XCTUnwrap(materializer.storeDeclaredHTML(raw))
    XCTAssertTrue(stored.text.isEmpty)
    XCTAssertEqual(stored.metadata["storage"], "app_private_file")
    XCTAssertEqual(stored.metadata["size_bytes"], String(html.utf8.count))
    XCTAssertEqual(materializer.loadDeclaredHTML(stored), html)
    XCTAssertEqual(materializer.storeDeclaredHTML(raw), stored)
    var forged = stored
    forged.uri = "file:///private/other.html"
    XCTAssertNil(materializer.loadDeclaredHTML(forged))
    let digest = try XCTUnwrap(stored.metadata["sha256"])
    let file = directory.appendingPathComponent("\(digest).html")
    let tampered = Data(html.replacingOccurrences(of: "frame=1", with: "frame=2").utf8)
    try GalaxySSILocalAttachmentStore.shared.write(tampered, to: file, purpose: "rich-html:\(digest)")
    XCTAssertNil(materializer.loadDeclaredHTML(stored))
    XCTAssertEqual(materializer.storeDeclaredHTML(raw), stored)
    XCTAssertEqual(materializer.loadDeclaredHTML(stored), html)
  }

  func testInternalArtifactMarkdownReferencesAreHiddenButCodeAndWebLinksRemain() {
    let internalImage = "![Generated image](galaxyssi-artifact://task/outputs/generated-image.png)"
    XCTAssertEqual(AgentRichContentCodec.fromText("Done.\n\n\(internalImage)").map(\.text), ["Done."])
    XCTAssertTrue(AgentRichContentCodec.fromText(internalImage).isEmpty)
    for value in [
      "`\(internalImage)`",
      "```markdown\n\(internalImage)\n```",
      "~~~\n\(internalImage)\n~~~",
      "[Source](https://example.com/page)",
      "![Image](https://example.com/image.png)"
    ] {
      XCTAssertEqual(AgentMarkdownArtifactReferences.removingInternalLinks(value), value)
    }
  }

  func testInternalArtifactLinksHandleTitlesParenthesesAndHistoryReload() throws {
    let target = "galaxyssi-artifact://task/outputs/image_(1).png"
    for reference in [
      "[Download](<\(target)>)",
      "![Image](\n<\(target)>\n)",
      "![Image](<\(target)> \"Title\")"
    ] {
      XCTAssertEqual(
        AgentMarkdownArtifactReferences.removingInternalLinks("Before \(reference) after"),
        "Before  after"
      )
    }
    let attachment = AgentRichBlock(
      id: "image",
      type: .image,
      title: "Image",
      uri: "galaxyssi-artifact://blob/transfer/image",
      mimeType: "image/png",
      metadata: ["sha256": String(repeating: "a", count: 64)]
    )
    let encoded = String(decoding: try JSONSerialization.data(withJSONObject: [
      "version": 1,
      "blocks": [
        ["id": "text", "type": "text", "text": "Done.\n\n![Image](\(target))"],
        [
          "id": attachment.id,
          "type": attachment.type.rawValue,
          "title": attachment.title,
          "uri": attachment.uri,
          "mime_type": attachment.mimeType,
          "metadata": attachment.metadata
        ]
      ]
    ], options: [.sortedKeys]), as: UTF8.self)
    let decoded = AgentRichContentCodec.decode(encoded)
    XCTAssertEqual(decoded.map(\.type), [.text, .image])
    XCTAssertEqual(decoded.first?.text, "Done.")
    XCTAssertEqual(decoded.last?.uri, attachment.uri)
    XCTAssertEqual(AgentRichContentCodec.decode(AgentRichContentCodec.normalize(encoded)), decoded)
  }

  func testRichContentUpdatePolicyIgnoresGeneratedIdsAndKeepsPassiveGroupsStable() {
    let first = [
      AgentRichBlock(id: "one", type: .text, text: "First"),
      AgentRichBlock(id: "two", type: .heading, text: "Second"),
      AgentRichBlock(id: "three", type: .image, uri: "https://example.com/image.jpg"),
      AgentRichBlock(id: "four", type: .code, text: "print(1)")
    ]
    let regenerated = zip(first, 0...).map { block, index in
      var copy = block
      copy.id = "generated-\(index)"
      return copy
    }

    XCTAssertTrue(AgentRichContentUpdatePolicy.supports(first))
    XCTAssertEqual(AgentRichContentUpdatePolicy.groups(first).map(\.count), [2, 1, 1])
    XCTAssertTrue(AgentRichContentUpdatePolicy.sameContent(first, regenerated))
    XCTAssertFalse(AgentRichContentUpdatePolicy.sameContent(first, Array(regenerated.dropLast())))
  }

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

  func testLinkedMarkdownImageBecomesImageAndSourceWithoutWrapperResidue() throws {
    let blocks = AgentRichContentCodec.fromText(
      "Before [![Mackerel](https://images.example/fish.jpg)](https://source.example/fish) after"
    )

    XCTAssertEqual(blocks.map(\.type), [.text, .image, .text, .text])
    XCTAssertEqual(blocks[1].uri, "https://images.example/fish.jpg")
    XCTAssertEqual(blocks[2].text, "[Mackerel](<https://source.example/fish>)")
    XCTAssertEqual(blocks[3].text, "after")
    XCTAssertFalse(blocks.compactMap(\.text).joined().contains("](https://source.example"))
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
