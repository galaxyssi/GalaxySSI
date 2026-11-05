import XCTest
@testable import GalaxySSI

final class PublicNewsFeedTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let source = PublicNewsSource(publisher: "Fixture", url: URL(string: "https://example.com/feed/")!)

  func testRSSSkipsUnsafeLinksAndDuplicateAnchorsButKeepsOtherArticles() throws {
    let xml = """
      <rss version="2.0"><channel>
        <item><title>News &amp; analysis</title><link>/article#section</link>
          <description><![CDATA[<p>Publisher summary.</p>]]></description>
          <pubDate>Fri, 01 Nov 2024 12:00:00 GMT</pubDate></item>
        <item><title>Duplicate</title><link>/article</link></item>
        <item><title>Unsafe</title><link>javascript:alert(1)</link></item>
        <item><title>Undated</title><link>/undated</link></item>
      </channel></rss>
      """
    let articles = try PublicNewsFeedParser.parse(Data(xml.utf8), source: source, now: now)
    XCTAssertEqual(articles.map(\.title), ["News & analysis", "Undated"])
    XCTAssertEqual(articles.first?.url.absoluteString, "https://example.com/article")
    XCTAssertEqual(articles.first?.summary, "Publisher summary.")
    XCTAssertNotNil(articles.first?.publishedAt)
    XCTAssertNil(articles.last?.publishedAt)
    XCTAssertEqual(articles.last?.discoveredAt, now)
  }

  func testAtomChoosesAlternateLinkAndDoesNotTreatUpdateAsPublication() throws {
    let xml = """
      <feed xmlns="http://www.w3.org/2005/Atom"><entry>
        <title>Research update</title>
        <link rel="self" href="/api/123" />
        <link rel="alternate" href="/research" />
        <updated>2024-11-01T12:00:00Z</updated>
        <summary type="html">&lt;p&gt;Abstract&lt;/p&gt;</summary>
      </entry></feed>
      """
    let article = try XCTUnwrap(PublicNewsFeedParser.parse(Data(xml.utf8), source: source, now: now).first)
    XCTAssertEqual(article.url.absoluteString, "https://example.com/research")
    XCTAssertEqual(article.summary, "Abstract")
    XCTAssertNil(article.publishedAt)
  }

  func testArchiveRefreshPreservesReadBookmarkAndDiscoveryDate() throws {
    let old = PublicNewsArticle(url: URL(string: "https://example.com/a")!, title: "Original",
      summary: "Original summary", publisher: "Fixture", publishedAt: now, discoveredAt: now,
      read: true, saved: true)
    let new = PublicNewsArticle(url: old.url, title: "Updated", summary: "", publisher: "Fixture",
      discoveredAt: now.addingTimeInterval(60))
    let result = PublicNewsArchive.merge(existing: [old], incoming: [new, old])
    let article = try XCTUnwrap(result.first)
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(article.title, "Updated")
    XCTAssertEqual(article.summary, old.summary)
    XCTAssertEqual(article.discoveredAt, now)
    XCTAssertEqual(article.publishedAt, now)
    XCTAssertTrue(article.read)
    XCTAssertTrue(article.saved)
  }
}
