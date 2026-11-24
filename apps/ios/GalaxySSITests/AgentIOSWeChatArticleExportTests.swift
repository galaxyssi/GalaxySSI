import Foundation
import PDFKit
import UIKit
import XCTest
@testable import GalaxySSI

final class AgentIOSWeChatArticleExportTests: XCTestCase {
  func testOneGlobalExportOwnsTheLeaseUntilReleased() throws {
    let gate = AgentIOSWeChatExportGate()
    var lease: AgentIOSWeChatExportGate.Lease? = try gate.acquire()
    XCTAssertNotNil(lease)
    XCTAssertThrowsError(try gate.acquire()) { XCTAssertEqual($0 as? AgentIOSWeChatArticleFailure, .alreadySaving) }
    lease = nil
    let next = try gate.acquire()
    XCTAssertNotNil(next.id)
  }
  func testExactImageBudgetsAndCanonicalArticleBoundary() {
    XCTAssertEqual(AgentIOSWeChatArticleLimits.imageTimeout, 4_000)
    XCTAssertEqual(AgentIOSWeChatArticleLimits.imageBudget, 35_000)
    XCTAssertEqual(AgentIOSWeChatArticleLimits.imageBytes, 8 * 1_024 * 1_024)
    XCTAssertEqual(AgentIOSWeChatArticleLimits.allImageBytes, 48 * 1_024 * 1_024)
    XCTAssertEqual(AgentIOSWeChatArticleLimits.uniqueImages, 128)
    XCTAssertNil(AgentIOSWeChatArticlePDF.articleURL("https://mp.weixin.qq.com.evil.test/s/a"))
    XCTAssertNil(AgentIOSWeChatArticlePDF.articleURL("file:///s/a"))
    XCTAssertNil(AgentIOSWeChatArticlePDF.articleURL("https://user@mp.weixin.qq.com/s/a"))
    XCTAssertNotNil(AgentIOSWeChatArticlePDF.articleURL("https://mp.weixin.qq.com/s/fixture"))
  }
  func testPartialPDFKeepsMissingImageBetweenFirstAndLastParagraph() throws {
    let document = AgentIOSWeChatArticleDocument(title: "Fixture", hasBodyText: true, blocks: [
      .init(kind: .text, text: "FIRST_PARAGRAPH", source: nil),
      .init(kind: .image, text: nil, source: nil),
      .init(kind: .text, text: "LAST_PARAGRAPH", source: nil)
    ])
    let messages = AgentIOSWeChatArticleMessages(language: "en")
    let result = try AgentIOSWeChatArticleRenderer.render(document: document,
      url: URL(string: "https://mp.weixin.qq.com/s/fixture")!, messages: messages, clock: .init())
    defer { try? FileManager.default.removeItem(at: result.url) }
    XCTAssertEqual(result.missingImages, 1)
    let pdf = try XCTUnwrap(PDFDocument(url: result.url))
    let text = try XCTUnwrap(pdf.string)
    let first = try XCTUnwrap(text.range(of: "FIRST_PARAGRAPH"))
    let missing = try XCTUnwrap(text.range(of: messages.text("wechat_article_missing_image")))
    let last = try XCTUnwrap(text.range(of: "LAST_PARAGRAPH"))
    XCTAssertLessThan(first.lowerBound, missing.lowerBound)
    XCTAssertLessThan(missing.lowerBound, last.lowerBound)
    XCTAssertGreaterThan(result.pages, 0)
  }
  func testImageOnlyWithoutDecodedImagesNeverPublishesAPDF() throws {
    let document = AgentIOSWeChatArticleDocument(title: "Image only", hasBodyText: false,
      blocks: [.init(kind: .image, text: nil, source: "data:image/png;base64,YmFk")])
    XCTAssertThrowsError(try AgentIOSWeChatArticleRenderer.render(document: document,
      url: URL(string: "https://mp.weixin.qq.com/s/fixture")!,
      messages: .init(language: "en"), clock: .init())) {
      XCTAssertEqual($0 as? AgentIOSWeChatArticleFailure, .bodyUnavailable)
    }
  }
}
