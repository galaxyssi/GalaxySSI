import XCTest
@testable import GalaxySSI

final class AgentIOSPhonePublicHTMLAttachmentTests: XCTestCase {
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
