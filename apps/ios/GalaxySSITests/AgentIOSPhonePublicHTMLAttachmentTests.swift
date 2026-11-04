import XCTest
@testable import GalaxySSI

final class AgentIOSPhonePublicHTMLAttachmentTests: XCTestCase {
  func testWeChatPDFKeepsImageOrderAndRejectsVerificationPage() throws {
    let url = try XCTUnwrap(AgentIOSWeChatArticlePDF.articleURL("https://mp.weixin.qq.com/s/example"))
    let source = """
    <h1 id="activity-name">Article</h1><div id="js_content"><p>Before</p>
    <img data-src="https://mmbiz.qpic.cn/example"><p>After</p></div>
    """
    let (title, blocks) = try XCTUnwrap(AgentIOSPublicArticleParser.weChatPDFBlocks(url: url, source: source))
    XCTAssertEqual(title, "Article")
    XCTAssertEqual(blocks.count, 3)
    guard case .text("Before") = blocks.first,
          case .image("https://mmbiz.qpic.cn/example") = blocks.dropFirst().first,
          case .text("After") = blocks.last else { return XCTFail("Unexpected article block order") }
    XCTAssertNil(AgentIOSPublicArticleParser.weChatPDFBlocks(url: url, source: "<div id='js_verify'>Verify</div>"))
    XCTAssertNil(AgentIOSWeChatArticlePDF.articleURL("https://mp.weixin.qq.com.example.org/s/example"))
  }

  func testSourceArchivePreservesBytesWithoutPublishingExecutableHTML() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = Data("<html><script>throw 1</script><p>Original</p></html>".utf8)
    let file = try AgentIOSOriginalHTMLSourceArchive.save(source, documents: root)
    XCTAssertEqual(file.pathExtension, "txt")
    XCTAssertEqual(file.deletingLastPathComponent().lastPathComponent, "Downloads")
    XCTAssertEqual(try Data(contentsOf: file), source)
    XCTAssertEqual(try AgentIOSOriginalHTMLSourceArchive.save(source, documents: root), file)
    XCTAssertThrowsError(try AgentIOSOriginalHTMLSourceArchive.save(Data(), documents: root))
  }

  func testSeparatesASCIIURLFromAdjacentChineseInstruction() {
    let url = "https://mp.weixin.qq.com/s/sRAngxDkA5FNRteEhAUPVQ"
    let instruction = "\u{7406}\u{89e3}\u{548c}\u{603b}\u{7ed3}\u{4e00}\u{4e0b}\u{ff0c}" +
      "\u{4e3a}\u{5565}\u{5b83}\u{80fd}\u{81ea}\u{5df1}\u{8fdb}\u{5316}"

    XCTAssertEqual(AgentIOSPhonePublicHTMLAttachment.explicitPublicURLs(url + instruction), [url])
    XCTAssertEqual(AgentIOSPhonePublicHTMLAttachment.preferredPublicURL(url + instruction), url)
  }

  func testPreservesPercentEncodedInternationalURLPath() {
    XCTAssertEqual(
      AgentIOSPhonePublicHTMLAttachment.explicitPublicURLs(
        "Read https://example.com/%E4%B8%AD%E6%96%87?lang=zh-CN " +
          "\u{5e76}\u{603b}\u{7ed3}"
      ),
      ["https://example.com/%E4%B8%AD%E6%96%87?lang=zh-CN"]
    )
  }
}
