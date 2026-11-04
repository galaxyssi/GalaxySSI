import XCTest
@testable import GalaxySSI

final class AgentIOSPhonePublicHTMLAttachmentTests: XCTestCase {
  @MainActor
  func testScreenSourceValidatesWeChatArticleLinksWithoutRewritingQuery() {
    let url = "https://mp.weixin.qq.com/s?__biz=abc&mid=123&sn=xyz"
    XCTAssertEqual(GalaxySSIScreenAnalysisLinkPicker.validatedLink(" \(url)\n", weChatOnly: true), url)
    XCTAssertNotNil(GalaxySSIScreenAnalysisLinkPicker.validatedLink(
      "https://mp.weixin.qq.com/s/articleID", weChatOnly: true))
    for invalid in ["http://mp.weixin.qq.com/s/a", "https://mp.weixin.qq.com.evil.test/s/a",
      "https://user@mp.weixin.qq.com/s/a", "https://mp.weixin.qq.com:8443/s/a",
      "https://mp.weixin.qq.com/not-an-article"] {
      XCTAssertNil(GalaxySSIScreenAnalysisLinkPicker.validatedLink(invalid, weChatOnly: true))
    }
    XCTAssertNotNil(GalaxySSIScreenAnalysisLinkPicker.validatedLink(
      "https://example.com/article", weChatOnly: false))
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
