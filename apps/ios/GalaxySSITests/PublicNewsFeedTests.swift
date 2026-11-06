import SwiftUI
import UIKit
import XCTest
@testable import GalaxySSI

final class PublicNewsFeedTests: XCTestCase {
  @MainActor
  func testNewsFeedHeaderUsesPageColorsWithoutChangingTheSharedDefault() {
    let feed = GalaxySSITopBar(title: "Following updates", backgroundColor: .galaxySSIPageBackground,
      leading: { EmptyView() }, trailing: { EmptyView() })
    let reader = GalaxySSITopBar(title: "Article", leading: { EmptyView() }, trailing: { EmptyView() })

    func rgb(_ color: Color, style: UIUserInterfaceStyle) -> [Int] {
      let traits = UITraitCollection(userInterfaceStyle: style)
      var result: [Int] = []
      traits.performAsCurrent {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: nil) else { return }
        result = [red, green, blue].map { Int(($0 * 255).rounded()) }
      }
      return result
    }

    XCTAssertEqual(rgb(feed.backgroundColor, style: .light), [0xF6, 0xF7, 0xF8])
    XCTAssertEqual(rgb(feed.backgroundColor, style: .dark), [0x15, 0x17, 0x1B])
    XCTAssertEqual(rgb(reader.backgroundColor, style: .light), [0xFF, 0xFF, 0xFF])
    XCTAssertEqual(rgb(reader.backgroundColor, style: .dark), [0x20, 0x23, 0x29])
  }

  func testNewsUnreadCountFitsOnlyBetweenCenteredTitleAndMenu() {
    for width in [280.0, 320.0, 390.0, 768.0] {
      for title in [70.0, 120.0, 280.0, 500.0] {
        let container = CGFloat(width), measuredTitle = CGFloat(title)
        let count = PublicNewsHeaderLayout.unreadWidth(container: container, title: measuredTitle)
        let side = PublicNewsHeaderLayout.sidePadding + PublicNewsHeaderLayout.actionWidth
        let clampedTitle = min(measuredTitle, container - 2 * side)
        let titleRight = container / 2 + clampedTitle / 2
        let menuStart = container - side
        XCTAssertGreaterThanOrEqual(count, 0)
        if count > 0 {
          XCTAssertEqual(titleRight + PublicNewsHeaderLayout.countGap + count + PublicNewsHeaderLayout.actionGap,
                         menuStart, accuracy: 0.001)
        }
      }
    }
  }

  func testNewsMoreGlyphKeepsFiveBalancedDots() {
    let dots = PublicNewsHeaderLayout.glyphOffsets
    XCTAssertEqual(dots.count, 5)
    XCTAssertEqual(dots.filter { $0.x == 0 }.map(\.y).sorted(), [-7, 0, 7])
    XCTAssertEqual(dots.filter { $0.y == 0 }.map(\.x).sorted(), [-7, 0, 7])
  }

  func testFollowingTimelineHonorsFilterBeforeLoadAndBuffersArrivalsWithoutMovingVisibleRows() {
    let first = timelineArticle("first")
    let second = timelineArticle("second")
    let incoming = timelineArticle("incoming")
    var alreadyRead = timelineArticle("already-read")
    alreadyRead.read = true
    var timeline = PublicNewsTimeline()
    timeline.select(.unread, articles: [])
    timeline.reconcile([first, alreadyRead, second])
    XCTAssertEqual(timeline.visibleIDs, [first.id, second.id])
    XCTAssertTrue(timeline.pendingIDs.isEmpty)

    var opened = first
    opened.read = true
    timeline.reconcile([incoming, second, opened, alreadyRead])
    XCTAssertEqual(timeline.visibleIDs, [first.id, second.id])
    XCTAssertEqual(timeline.pendingIDs, [incoming.id])
    timeline.revealArrivals()
    XCTAssertEqual(timeline.visibleIDs, [incoming.id, first.id, second.id])
    XCTAssertTrue(timeline.pendingIDs.isEmpty)

    timeline.select(.unread, articles: [incoming, opened, second], retainingUnread: [first.id])
    XCTAssertTrue(timeline.visibleIDs.contains(first.id))
    timeline.select(.unread, articles: [incoming, opened, second])
    XCTAssertFalse(timeline.visibleIDs.contains(first.id))
  }

  func testFollowingSavedFilterImmediatelyReflectsBookmarkChanges() {
    var first = timelineArticle("first")
    var second = timelineArticle("second")
    first.saved = true
    var timeline = PublicNewsTimeline()
    timeline.select(.saved, articles: [first, second])
    XCTAssertEqual(timeline.visibleIDs, [first.id])
    first.saved = false
    second.saved = true
    timeline.reconcile([first, second])
    XCTAssertEqual(timeline.visibleIDs, [second.id])
    XCTAssertTrue(timeline.pendingIDs.isEmpty)
  }

  func testFollowingReadDwellResetsWhenScrollingOrLosingVisibility() {
    var dwell = PublicNewsReadDwell()
    XCTAssertTrue(dwell.sample(["first", "second"], now: 1).isEmpty)
    XCTAssertTrue(dwell.sample(["first"], now: 2).isEmpty)
    XCTAssertEqual(dwell.sample(["first", "second"], now: 3), ["first"])
    XCTAssertTrue(dwell.sample([], now: 4).isEmpty)
    XCTAssertTrue(dwell.sample(["second"], now: 5).isEmpty)
    XCTAssertEqual(dwell.sample(["second"], now: 7), ["second"])
  }

  private func timelineArticle(_ slug: String) -> PublicNewsArticle {
    PublicNewsArticle(url: URL(string: "https://example.com/\(slug)")!, title: slug,
      summary: "", publisher: "Fixture", discoveredAt: .distantPast)
  }

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
    let original = store.speechDocument(for: .init(articleKey: key, edition: .original))
    let translated = store.speechDocument(for: .init(articleKey: key, edition: .chinese))
    let invalid = store.speechDocument(for: .init(articleKey: "../wrong", edition: .original))
    XCTAssertEqual(original?.paragraphs, body.paragraphs)
    XCTAssertEqual(original?.key, body.fingerprint)
    XCTAssertNil(translated)
    XCTAssertNil(invalid)
    let items = await store.speechItems(articleIDs: ["https://github.blog/missing", articleID, articleID])
    XCTAssertEqual(items, [.init(articleKey: key, edition: .original)])
  }

  func testNewsSpeechAdvancesBookmarkOnlyWhenTheNextParagraphCanStart() throws {
    let key = PublicNewsSpeechBookmark.key(for: "article")
    var queue = PublicNewsSpeechQueue()
    XCTAssertTrue(queue.replace([.init(articleKey: key, edition: .original)]))
    let token = try XCTUnwrap(queue.resume())
    XCTAssertTrue(queue.prepare(documentKey: key, paragraphCount: 2, token: token))
    XCTAssertFalse(queue.began(paragraph: 1, token: token))
    XCTAssertTrue(queue.began(paragraph: 0, token: token))
    XCTAssertTrue(queue.finishedParagraph(0, count: 2, token: token))
    XCTAssertTrue(queue.began(paragraph: 1, token: token))
    XCTAssertFalse(queue.finishedParagraph(0, count: 2, token: token))
    queue.pause()
    XCTAssertEqual(queue.bookmark.paragraph, 1)
    XCTAssertFalse(queue.began(paragraph: 1, token: token))
    XCTAssertFalse(queue.next())
    XCTAssertEqual(queue.phase, .finished)
    XCTAssertEqual(queue.bookmark.paragraph, 0)
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

  @MainActor
  func testUnreadMetadataCoexistsWithLegacyArchiveAndTracksReadAndHiddenArticles() throws {
    struct LegacySnapshot: Codable {
      let articles: [PublicNewsArticle]
      let notRelevantIDs: Set<String>
    }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    func article(_ name: String) throws -> PublicNewsArticle {
      PublicNewsArticle(url: try XCTUnwrap(URL(string: "https://example.com/\(name)")), title: name,
        summary: String(repeating: "Summary ", count: 2048), publisher: "Fixture", discoveredAt: now, saved: true)
    }
    let first = try article("first")
    let second = try article("second")
    let hidden = try article("hidden")
    XCTAssertEqual(PublicNewsArchive.readReminderUnreadCount(fileURL: file, allowLegacy: false), 0)
    let fixture = LegacySnapshot(articles: [first, second, hidden], notRelevantIDs: [hidden.id])
    try JSONEncoder().encode(fixture).write(to: file)
    XCTAssertNil(PublicNewsArchive.readReminderUnreadCount(fileURL: file, allowLegacy: false))
    XCTAssertEqual(PublicNewsArchive.readReminderUnreadCount(fileURL: file), 2)

    let archive = PublicNewsArchive(fileURL: file)
    archive.load()
    archive.markRead(first.id)
    XCTAssertEqual(archive.reminderUnreadCount, 1)
    XCTAssertEqual(PublicNewsArchive.readReminderUnreadCount(fileURL: file, allowLegacy: false), 1)
    let rewritten = try JSONDecoder().decode(LegacySnapshot.self, from: Data(contentsOf: file))
    XCTAssertEqual(rewritten.articles.map(\.read), [true, false, false])
    XCTAssertEqual(rewritten.articles.map(\.saved), [true, true, true])
    XCTAssertEqual(rewritten.articles.map(\.summary), fixture.articles.map(\.summary))
    XCTAssertEqual(rewritten.notRelevantIDs, [hidden.id])

    XCTAssertTrue(archive.markNotRelevant(second.id))
    XCTAssertEqual(archive.reminderUnreadCount, 0)
    XCTAssertEqual(PublicNewsArchive.readReminderUnreadCount(fileURL: file, allowLegacy: false), 0)
  }

  func testUnreadMetadataDoesNotTreatTruncatedOrCorruptArchiveAsEmpty() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try Data("{\"unreadCountV1\":9,\n\"articles\":".utf8).write(to: file)
    XCTAssertNil(PublicNewsArchive.readReminderUnreadCount(fileURL: file, allowLegacy: false))
    XCTAssertNil(PublicNewsArchive.readReminderUnreadCount(fileURL: file))
  }

  @MainActor
  func testIndexedFirstPageRestoresOlderAnchorWithoutDroppingRetainedHistory() throws {
    struct LegacySnapshot: Codable { let articles: [PublicNewsArticle] }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let articles = try (0..<1_205).map { index in
      PublicNewsArticle(url: try XCTUnwrap(URL(string: "https://example.com/\(index)")),
        title: "Article \(index)", summary: "Summary", publisher: "Fixture",
        discoveredAt: now.addingTimeInterval(Double(-index)), saved: index.isMultiple(of: 2))
    }
    try JSONEncoder().encode(LegacySnapshot(articles: articles)).write(to: file)
    let archive = PublicNewsArchive(fileURL: file)
    archive.load()
    archive.markRead(articles[900].id)
    XCTAssertTrue(archive.markNotRelevant(articles[899].id))
    let anchor = PublicNewsSpeechBookmark.key(for: articles[900].id)
    let first = try XCTUnwrap(PublicNewsArchive.readFirstPage(fileURL: file, filter: .all, anchor: "", retaining: []))
    XCTAssertEqual(first.map(\.id), articles.prefix(40).map(\.id))
    let restored = try XCTUnwrap(PublicNewsArchive.readFirstPage(
      fileURL: file, filter: .unread, anchor: anchor, retaining: [anchor]))
    XCTAssertEqual(restored.count, 40)
    XCTAssertEqual(restored[12].id, articles[900].id)
    XCTAssertTrue(restored[12].read)
    XCTAssertFalse(restored.contains { $0.id == articles[899].id })
    let saved = try XCTUnwrap(PublicNewsArchive.readFirstPage(fileURL: file, filter: .saved, anchor: anchor, retaining: []))
    XCTAssertEqual(saved[12].id, articles[900].id)
    XCTAssertTrue(saved.allSatisfy(\.saved))
    let reopened = try JSONDecoder().decode(LegacySnapshot.self, from: Data(contentsOf: file))
    XCTAssertEqual(reopened.articles.count, 1_205)
    XCTAssertEqual(PublicNewsArchive.merge(existing: reopened.articles, incoming: [articles[0]]).count, 1_205)
  }

  func testNewsPageWindowExtendsBothWaysAndKeepsTheExistingRowsWhenArrivalsPrepend() {
    let ids = (0..<180).map(String.init)
    var window = PublicNewsPageWindow()
    window.reset(ids, anchor: "90")
    XCTAssertEqual(window.range, 78..<118)
    window.extend(older: true, count: ids.count)
    window.extend(older: false, count: ids.count)
    XCTAssertEqual(window.range, 38..<158)
    let arrivals = ["new"] + ids
    window.reconcile(from: ids, to: arrivals)
    XCTAssertEqual(Array(arrivals[window.range]), Array(ids[38..<158]))
  }

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
    XCTAssertNil(cursor.nextWake(at: now))
    try cursor.accept(type: "patch", data: data(#"{"path":"/","data":{"0":102,"1":101,"2":100}}"#), now: now)
    XCTAssertEqual(cursor.next(at: now), 102)
    XCTAssertEqual(cursor.nextWake(at: now), now)
    cursor = try JSONDecoder().decode(PublicNewsPushCursor.self, from: JSONEncoder().encode(cursor))
    cursor.deferItem(102, now: now)
    XCTAssertNil(cursor.next(at: now))
    XCTAssertEqual(cursor.nextWake(at: now), now.addingTimeInterval(10))
    XCTAssertEqual(cursor.next(at: now.addingTimeInterval(11)), 102)
    cursor.complete(102)
    try cursor.accept(type: "put", data: data(#"{"path":"/0","data":null}"#), now: now)
    try cursor.accept(type: "put", data: data(#"{"path":"/","data":[103,102,101,100]}"#), now: now)
    XCTAssertEqual(Set(cursor.pending.keys), [103])
    XCTAssertNil(cursor.next(at: now.addingTimeInterval(PublicNewsPushCursor.retention + 1)))
    XCTAssertNil(cursor.nextWake(at: now.addingTimeInterval(PublicNewsPushCursor.retention + 1)))
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
