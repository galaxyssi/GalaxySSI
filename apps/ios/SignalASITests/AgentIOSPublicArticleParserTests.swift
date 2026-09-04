import XCTest
@testable import SignalASI

final class AgentIOSPublicArticleParserTests: XCTestCase {
  func testParsesGenericJSONLDArticleMetadataAndBody() throws {
    let html = #"""
      <html><head>
      <title>Fallback title</title>
      <meta property="og:image" content="https://example.com/cover.jpg">
      <script type="application/ld+json">
      {
        "@type": "NewsArticle",
        "headline": "Structured headline",
        "author": [{"@type":"Person","name":"Ada"}, {"name":"Lin"}],
        "datePublished": "2026-08-20T12:00:00Z",
        "articleBody": "This is the structured article body with enough detail to be selected over a short navigation shell.",
        "image": {"url":"https://example.com/jsonld.jpg"}
      }
      </script></head>
      <body><article><h1>Visible title</h1><p>This is a shorter visible article paragraph with useful context.</p></article></body>
      </html>
      """#

    let article = try XCTUnwrap(AgentIOSPublicArticleParser.parse(
      url: URL(string: "https://example.com/news/story")!,
      source: html
    ))

    XCTAssertEqual(article.title, "Structured headline")
    XCTAssertEqual(article.author, "Ada, Lin")
    XCTAssertEqual(article.publishedAt, "2026-08-20T12:00:00Z")
    XCTAssertTrue(article.content.contains("structured article body"))
    XCTAssertEqual(article.sourceType, "structured_web_article")
    XCTAssertEqual(article.images.map(\.url), [
      "https://example.com/jsonld.jpg",
      "https://example.com/cover.jpg"
    ])
  }

  func testScoresMainContentAndRemovesPageChrome() throws {
    let html = #"""
      <html><head><meta name="author" content="Site Author"></head><body>
      <nav><a href="/one">Menu one</a><a href="/two">Menu two</a></nav>
      <div class="sidebar related">Related story that must not enter the article body.</div>
      <main role="main">
        <h1>Useful guide</h1>
        <p>This paragraph contains the first substantial explanation, several facts, and enough punctuation to score as content.</p>
        <p>This paragraph contains the second substantial explanation and keeps the readable article together.</p>
        <a href="/reference">Reference</a>
        <img data-lazy-src="/images/example.jpg" alt="Example" data-width="640" data-height="480">
      </main>
      <footer>Copyright and footer links</footer>
      </body></html>
      """#

    let article = try XCTUnwrap(AgentIOSPublicArticleParser.parse(
      url: URL(string: "https://example.com/guides/read")!,
      source: html
    ))

    XCTAssertEqual(article.title, "Useful guide")
    XCTAssertEqual(article.author, "Site Author")
    XCTAssertTrue(article.content.contains("first substantial explanation"))
    XCTAssertFalse(article.content.contains("Related story"))
    XCTAssertFalse(article.content.contains("Copyright"))
    XCTAssertEqual(article.links, ["https://example.com/reference"])
    XCTAssertEqual(article.images.first?.url, "https://example.com/images/example.jpg")
    XCTAssertEqual(article.images.first?.width, 640)
    XCTAssertEqual(article.images.first?.height, 480)
    XCTAssertEqual(article.sourceType, "generic_web_page")
  }

  func testKeepsDedicatedWeChatArticleParser() throws {
    let html = #"""
      <html><head><meta property="og:title" content="WeChat title"></head><body>
      <div id="js_content"><p>Dedicated WeChat article content remains available and should use its specific evidence tier.</p></div>
      <span id="js_name">Publisher</span>
      </body></html>
      """#

    let article = try XCTUnwrap(AgentIOSPublicArticleParser.parse(
      url: URL(string: "https://mp.weixin.qq.com/s/example")!,
      source: html
    ))

    XCTAssertEqual(article.title, "WeChat title")
    XCTAssertEqual(article.author, "Publisher")
    XCTAssertEqual(article.sourceType, "wechat_public_account")
  }
}
