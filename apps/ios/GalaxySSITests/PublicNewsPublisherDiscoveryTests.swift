import XCTest
@testable import GalaxySSI

final class PublicNewsPublisherDiscoveryTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let origin = URL(string: "https://www.seangoedecke.com/article/")!

  func testOnlyAcceptsSamePublisherDeclarationsInHeadAndRejectsDiscussion() {
    let html = """
      <head>
        <!-- <link rel="alternate" type="application/rss+xml" href="/commented.xml"> -->
        <script>let fake = '<link rel="alternate" type="application/rss+xml" href="/fake.xml">';</script>
        <link rel="alternate" type="application/rss+xml" href="/?feed=comments-rss2">
        <link rel="alternate" type="application/atom+xml" title="Replies" href="/discussion.xml">
        <link rel="alternate" type="application/rss+xml" href="https://example.com/foreign.xml">
        <link rel="alternate" type="application/rss+xml" href="https://seangoedecke.com/rss.xml">
        <link REL="alternate" TYPE="application/atom+xml; charset=UTF-8" href="/atom.xml?a=1&amp;b=2">
      </head><body><link rel="alternate" type="application/rss+xml" href="/body.xml"></body>
      """
    XCTAssertEqual(PublicNewsPublisherDiscovery.discover(html: html, origin: origin).map(\.absoluteString), [
      "https://seangoedecke.com/rss.xml", "https://www.seangoedecke.com/atom.xml?a=1&b=2"
    ])
    XCTAssertTrue(PublicNewsPublisherDiscovery.discover(html: html, origin: URL(string: "https://example.com/a")!).isEmpty)
  }

  func testLearnedFeedPollBudgetRotationBackoffAndDiscussionRemoval() throws {
    var state = PublicNewsPublisherState()
    let first = state.plan(now: now, enabled: true, probe: true)
    XCTAssertEqual(first.count, 3)
    let article = item(origin, title: "An article")
    let feed = URL(string: "https://seangoedecke.com/rss.xml")!
    state.learn([feed], from: article, host: "seangoedecke.com", now: now)
    let second = state.plan(now: now, enabled: true, probe: false)
    XCTAssertEqual(second.count, 4)
    XCTAssertTrue(Set(first.map(\.url)).isDisjoint(with: second.map(\.url)))
    let source = try XCTUnwrap(second.first(where: \.learned))
    XCTAssertEqual(source.interests, [.technology])
    state.recordPoll(source, success: false, discussion: false, now: now)
    state = try JSONDecoder().decode(PublicNewsPublisherState.self, from: JSONEncoder().encode(state))
    XCTAssertFalse(state.plan(now: now, enabled: true, probe: false).contains(where: \.learned))
    XCTAssertTrue(state.plan(now: now.addingTimeInterval(901), enabled: true, probe: false).contains(where: \.learned))
    state.recordPoll(source, success: false, discussion: true, now: now)
    XCTAssertTrue(state.feeds.isEmpty)
  }

  func testDiscussionTitleCannotEnterArchiveThroughHarmlessFeedPath() {
    let source = PublicNewsSource(publisher: "seangoedecke.com", url: origin, learned: true)
    let xml = "<rss><channel><title>Latest comments</title><item><title>Item</title><link>/a</link></item></channel></rss>"
    XCTAssertThrowsError(try PublicNewsFeedParser.parse(Data(xml.utf8), source: source, now: now)) {
      guard case PublicNewsFeedError.discussionFeed = $0 else { return XCTFail("Unexpected error: \($0)") }
    }
  }

  func testPublisherAliasReusesExactIdentityWithoutConflatingEncodedPathOrTitle() {
    var existing = item(URL(string: "https://www.seangoedecke.com/part%2Fone?q=a%2Bb")!, title: "An article")
    existing.read = true
    existing.saved = true
    let alias = item(URL(string: "https://seangoedecke.com/part%2Fone?q=a%2Bb")!, title: "An article")
    let distinctPath = item(URL(string: "https://seangoedecke.com/part/one?q=a%2Bb")!, title: "An article")
    let distinctQuery = item(URL(string: "https://seangoedecke.com/part%2Fone?q=a+b")!, title: "An article")
    let result = PublicNewsArchive.merge(existing: [existing], incoming: [alias, distinctPath, distinctQuery])
    XCTAssertEqual(Set(result.map(\.id)), [existing.id, distinctPath.id, distinctQuery.id])
    XCTAssertEqual(result.first(where: { $0.id == existing.id })?.read, true)
    XCTAssertEqual(result.first(where: { $0.id == existing.id })?.saved, true)
    let otherTitle = item(alias.url, title: "Different article")
    XCTAssertEqual(PublicNewsArchive.merge(existing: [existing], incoming: [otherTitle]).count, 2)
  }

  private func item(_ url: URL, title: String) -> PublicNewsArticle {
    .init(url: url, title: title, summary: "", publisher: "Fixture", discoveredAt: now, interests: [.technology])
  }
}
