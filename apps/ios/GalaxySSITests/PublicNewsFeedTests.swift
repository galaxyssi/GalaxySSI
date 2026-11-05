import XCTest
@testable import GalaxySSI

final class PublicNewsFeedTests: XCTestCase {
  func testSpeechBookmarkResumesPausedAndInvalidatesOldParagraphCallbacks() throws {
    let suite = "PublicNewsSpeechBookmarkTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PublicNewsSpeechBookmarkStore(defaults: defaults)
    let first = PublicNewsSpeechBookmark.Item(articleKey: PublicNewsSpeechBookmark.key(for: "first"), edition: .original)
    let second = PublicNewsSpeechBookmark.Item(articleKey: PublicNewsSpeechBookmark.key(for: "second"), edition: .chinese)
    let fingerprint = PublicNewsSpeechBookmark.key(for: "body")
    var queue = PublicNewsSpeechQueue()
    XCTAssertTrue(queue.replace([first, first, second], paragraph: 1, documentKey: fingerprint))
    XCTAssertEqual(queue.bookmark.items, [first, second])
    let token = try XCTUnwrap(queue.resume())
    XCTAssertTrue(queue.prepare(documentKey: fingerprint, paragraphCount: 3, token: token))
    XCTAssertTrue(queue.began(paragraph: 1, token: token))
    queue.pause()
    XCTAssertFalse(queue.finishedParagraph(1, count: 3, token: token))
    store.save(queue.bookmark)
    let restored = PublicNewsSpeechQueue(bookmark: store.load())
    XCTAssertEqual(restored.phase, .paused)
    XCTAssertEqual(restored.bookmark.paragraph, 1)
    let next = try XCTUnwrap(queue.resume())
    XCTAssertTrue(queue.prepare(documentKey: PublicNewsSpeechBookmark.key(for: "new-body"), paragraphCount: 3, token: next))
    XCTAssertEqual(queue.bookmark.paragraph, 0)
    XCTAssertTrue(queue.next())
    XCTAssertEqual(queue.current, second)
    queue.stop()
    store.save(queue.bookmark)
    XCTAssertEqual(store.load(), PublicNewsSpeechBookmark())
  }

  func testSpeechDocumentOnlyLoadsValidatedCachedArticlesAndAvailableEditions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PublicNewsBodyStore(root: root)
    let articleID = "https://github.blog/example"
    let body = PublicNewsOriginalBody(title: "News", paragraphs: ["First paragraph", "Second paragraph"])
    _ = try await store.install(body, articleID: articleID)
    let key = PublicNewsSpeechBookmark.key(for: articleID)
    let original = await store.speechDocument(for: .init(articleKey: key, edition: .original))
    let translated = await store.speechDocument(for: .init(articleKey: key, edition: .chinese))
    let invalid = await store.speechDocument(for: .init(articleKey: "../wrong", edition: .original))
    XCTAssertEqual(original?.paragraphs, body.paragraphs)
    XCTAssertEqual(original?.key, body.fingerprint)
    XCTAssertNil(translated)
    XCTAssertNil(invalid)
  }

  @MainActor
  func testNotRelevantPersistsAcrossReopenWithoutDiscardingArchive() throws {
    struct Fixture: Encodable { let articles: [PublicNewsArticle] }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let article = PublicNewsArticle(url: URL(string: "https://example.com/a")!, title: "Headline",
      summary: "Summary", publisher: "Fixture", discoveredAt: Date(), saved: true)
    try JSONEncoder().encode(Fixture(articles: [article])).write(to: file)
    let archive = PublicNewsArchive(fileURL: file)
    XCTAssertNil(archive.reminderUnreadCount)
    archive.load()
    XCTAssertEqual(archive.reminderUnreadCount, 1)
    XCTAssertFalse(archive.markNotRelevant("missing"))
    XCTAssertTrue(archive.markNotRelevant(article.id))
    XCTAssertTrue(archive.eligibleArticles.isEmpty)
    let reopened = PublicNewsArchive(fileURL: file)
    reopened.load()
    XCTAssertEqual(reopened.notRelevantIDs, [article.id])
    XCTAssertEqual(reopened.articles, [article])
    XCTAssertTrue(reopened.eligibleArticles.isEmpty)
    XCTAssertEqual(reopened.reminderUnreadCount, 0)
  }

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

  func testFirebaseCursorPersistsPendingAndDeduplicatesReconnectAndReappearingStories() throws {
    var cursor = PublicNewsPushCursor()
    func data(_ text: String) -> Data { Data(text.utf8) }
    try cursor.accept(type: "put", data: data(#"{"path":"/","data":[101,100]}"#), now: now)
    XCTAssertTrue(cursor.pending.isEmpty)
    try cursor.accept(type: "patch", data: data(#"{"path":"/","data":{"0":102,"1":101,"2":100}}"#), now: now)
    XCTAssertEqual(cursor.next(at: now), 102)
    cursor = try JSONDecoder().decode(PublicNewsPushCursor.self, from: JSONEncoder().encode(cursor))
    cursor.deferItem(102, now: now)
    XCTAssertNil(cursor.next(at: now))
    XCTAssertEqual(cursor.next(at: now.addingTimeInterval(11)), 102)
    cursor.complete(102)
    try cursor.accept(type: "put", data: data(#"{"path":"/0","data":null}"#), now: now)
    try cursor.accept(type: "put", data: data(#"{"path":"/","data":[103,102,101,100]}"#), now: now)
    XCTAssertEqual(Set(cursor.pending.keys), [103])
    XCTAssertNil(cursor.next(at: now.addingTimeInterval(PublicNewsPushCursor.retention + 1)))
  }

  func testInvalidFirebasePatchDoesNotMutateCursor() throws {
    var cursor = PublicNewsPushCursor()
    try cursor.accept(type: "put", data: Data(#"{"path":"/","data":[101]}"#.utf8), now: now)
    let prior = cursor
    XCTAssertThrowsError(try cursor.accept(type: "patch",
      data: Data(#"{"path":"/","data":{"0":102,"1":true}}"#.utf8), now: now))
    XCTAssertEqual(cursor, prior)
  }

  func testSSEDecoderHandlesCommentsMultilineAndCRLF() throws {
    var decoder = PublicNewsSSEDecoder()
    let body = ": ready\r\n\r\nevent: patch\r\ndata: {\"path\":\"/\",\r\ndata: \"data\":{\"1\":102}}\r\n\r\n"
    var events: [PublicNewsSSEDecoder.Event] = []
    for byte in body.utf8 {
      if let event = try decoder.append(byte) { events.append(event) }
    }
    XCTAssertEqual(events, [.init(type: "patch", data: Data("{\"path\":\"/\",\n\"data\":{\"1\":102}}".utf8))])
  }

  func testHackerNewsSubmissionIsNotPresentedAsPublisherDate() throws {
    let payload = Data(#"{"id":102,"type":"story","time":1800000000,"url":"https://example.com/a#ref","title":"<b>News</b>"}"#.utf8)
    let article = try XCTUnwrap(PublicNewsPushClient.article(payload, id: 102, now: now))
    XCTAssertEqual(article.title, "News")
    XCTAssertEqual(article.url.absoluteString, "https://example.com/a")
    XCTAssertNil(article.publishedAt)
    XCTAssertThrowsError(try PublicNewsPushClient.article(payload, id: 103, now: now))
  }
}
