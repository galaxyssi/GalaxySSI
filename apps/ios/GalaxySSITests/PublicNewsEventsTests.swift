import XCTest
@testable import GalaxySSI

final class PublicNewsEventsTests: XCTestCase {
  private let base = Date(timeIntervalSince1970: 1_800_000_000)
  private let title = "Mission team publishes the first detailed observations of Venus"
  private let enabled: Set<PublicNewsInterest> = [.technology, .research]

  func testGroupingIsDeterministicAndKeepsEveryIndependentReport() throws {
    let a = article("a", hour: 0), b = article("b", hour: 2), c = article("c", hour: 1)
    let first = try PublicNewsEvents.group([a, b, c], enabled: enabled)
    let second = try PublicNewsEvents.group([c, a, b], enabled: enabled)
    XCTAssertEqual(first, second)
    let event = try XCTUnwrap(first[a.id])
    XCTAssertEqual(event.sources, 3)
    XCTAssertEqual(event.reports.map(\.id), [b.id, c.id, a.id])
    XCTAssertEqual(PublicNewsEvents.representatives([a, b, c], events: first).map(\.id), [b.id])
    XCTAssertEqual([a, b, c].count, 3)
  }

  func testGroupingNeverBridgesThirtySixHourPeriodsOrTopicIntersections() throws {
    let a = article("a", hour: 0), b = article("b", hour: 30), c = article("c", hour: 60)
    XCTAssertEqual(Set(try PublicNewsEvents.group([a, b, c], enabled: enabled).keys), Set([a.id, b.id]))
    var wide = article("wide", hour: 1)
    wide.interests = enabled
    var research = article("research", hour: 2)
    research.interests = [.research]
    let groups = try PublicNewsEvents.group([a, wide, research], enabled: enabled)
    XCTAssertEqual(Set(groups.keys), Set([a.id, wide.id]))
    XCTAssertNil(groups[research.id])
  }

  func testGroupingRejectsDisabledTopicsMissingDatesBriefQuestionsAndSamePublisher() throws {
    let a = article("a", hour: 0)
    var disabled = article("disabled", hour: 1)
    disabled.interests = [.finance]
    var undated = article("undated", hour: 1)
    undated.publishedAt = nil
    var samePublisher = article("same", hour: 1)
    samePublisher.url = URL(string: "https://a.example/other")!
    for other in [disabled, undated, samePublisher] {
      XCTAssertTrue(try PublicNewsEvents.group([a, other], enabled: enabled).isEmpty)
    }
    for headline in ["Market", title + "?"] {
      XCTAssertTrue(try PublicNewsEvents.group([article("a", hour: 0, title: headline),
        article("b", hour: 1, title: headline)], enabled: enabled).isEmpty)
    }
  }

  func testOnlyOriginalHeadlinesGroupWithoutMergingVersionsNegationOrTranslatedCollisions() throws {
    let a = article("a", hour: 0)
    var translated = article("b", hour: 1, title: "Independent report describes a different mission with other observations")
    translated.headlineTranslation = .init(source: translated.title, chinese: title, provider: .localModel)
    for other in [translated, article("n", hour: 1, title: "No " + title),
                  article("v", hour: 1, title: title + " 6.2")] {
      XCTAssertTrue(try PublicNewsEvents.group([a, other], enabled: enabled).isEmpty)
    }
    let normalized = article("b", hour: 1, title: "  " + title.uppercased() + ".  ")
    XCTAssertEqual(try PublicNewsEvents.group([a, normalized], enabled: enabled)[a.id]?.sources, 2)
  }

  func testNewSourcesRequireAnActualRecordedReadNotAVisitOrLegacyReadFlag() throws {
    var a = article("a", hour: 0)
    let b = article("b", hour: 2), c = article("c", hour: 0)
    a.read = true
    XCTAssertEqual(try PublicNewsEvents.group([a, b, c], enabled: enabled)[a.id]?.newCount, 0)
    a.readAt = base.addingTimeInterval(3_600)
    let event = try XCTUnwrap(PublicNewsEvents.group([a, b, c], enabled: enabled)[a.id])
    XCTAssertEqual(event.newCount, 1)
    XCTAssertEqual(event.reports.filter(event.arrivedSinceRead).map(\.id), [b.id])
    XCTAssertFalse(b.read)
    XCTAssertFalse(c.read)
  }

  func testNewExcerptAttributesDistinctCompleteSentenceAndPreservesConflictingAccounts() throws {
    var before = article("a", hour: 0, summary: "The team has not announced a final launch date.")
    before.read = true
    before.readAt = base.addingTimeInterval(3_600)
    var after = article("b", hour: 2,
      summary: "The team has not announced a final launch date. Another report says the launch date is now confirmed.")
    let event = try XCTUnwrap(PublicNewsEvents.group([before, after], enabled: enabled)[before.id])
    XCTAssertEqual(event.newExcerpt?.source, "b.example")
    XCTAssertEqual(event.newExcerpt?.text, "Another report says the launch date is now confirmed.")
    XCTAssertEqual(event.reports.last?.excerpts, [before.summary])
    after.summary = before.summary
    XCTAssertNil(try PublicNewsEvents.group([before, after], enabled: enabled)[before.id]?.newExcerpt)
    before.summary = ""
    after.summary = "Another report says the launch date is now confirmed."
    XCTAssertNil(try PublicNewsEvents.group([before, after], enabled: enabled)[before.id]?.newExcerpt)
  }

  func testPreviewExtractionIsBoundedAndDoesNotTreatMarkupLinksOrFragmentsAsStatements() throws {
    var a = article("a", hour: 0)
    a.read = true
    a.readAt = base.addingTimeInterval(3_600)
    let fragments = ["Unfinished preview text without a sentence ending", "<p>Untrusted markup is not a statement.</p>",
      "The report is at https://b.example/story.", String(repeating: "x", count: 221) + "."]
    for text in fragments {
      let b = article("b", hour: 2, summary: text)
      let event = try XCTUnwrap(PublicNewsEvents.group([a, b], enabled: enabled)[a.id])
      XCTAssertTrue(event.reports.first?.excerpts.isEmpty == true)
      XCTAssertNil(event.newExcerpt)
      XCTAssertEqual(event.newCount, 1)
    }
  }

  func testCuratedGroupingDoesNotHideUngroupedSameHeadlinesOrChangeSavedAndAllLists() throws {
    let a = article("a", hour: 0)
    var b = article("b", hour: 1)
    b.interests = [.research]
    b.saved = true
    let all = [b, a]
    let groups = try PublicNewsEvents.group(all, enabled: enabled)
    XCTAssertTrue(groups.isEmpty)
    let candidates = PublicNewsEvents.representatives(all, events: groups).map(PublicNewsHighlights.metadata)
    let ids = try PublicNewsHighlights.select(candidates, enabled: enabled, now: base.addingTimeInterval(7_200),
      deduplicateHeadlines: false)
    XCTAssertEqual(Set(ids), Set(all.map(\.id)))
    var timeline = PublicNewsTimeline()
    timeline.select(.all, articles: all)
    XCTAssertEqual(timeline.visibleIDs, all.map(\.id))
    timeline.select(.saved, articles: all)
    XCTAssertEqual(timeline.visibleIDs, [b.id])
  }

  func testReadTimestampSurvivesRefreshAndLegacyDecodingDoesNotInventOne() throws {
    var a = article("a", hour: 0)
    a.read = true
    a.readAt = base
    let refreshed = PublicNewsArchive.merge(existing: [a], incoming: [article("a", hour: 4)])
    XCTAssertEqual(refreshed.first?.readAt, base)
    XCTAssertEqual(refreshed.first?.discoveredAt, a.discoveredAt)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
    object.removeValue(forKey: "readAt")
    let legacy = try JSONDecoder().decode(PublicNewsArticle.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertTrue(legacy.read)
    XCTAssertNil(legacy.readAt)
  }

  @MainActor
  func testReadingOneArchivedSourceDoesNotMarkTheOtherAndPersistsOnlyItsTimestamp() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("news.json")
    let a = article("a", hour: 0), b = article("b", hour: 1)
    let snapshot = PublicNewsArchiveStorage.Snapshot(articles: [b, a])
    try JSONEncoder().encode(snapshot).write(to: file)
    let archive = PublicNewsArchive(fileURL: file)
    archive.load()
    XCTAssertTrue(archive.loaded)
    archive.markRead(b.id)
    let stamp = archive.articles.first { $0.id == b.id }?.readAt
    XCTAssertNotNil(stamp)
    archive.markRead(b.id)
    XCTAssertEqual(archive.articles.first { $0.id == b.id }?.readAt, stamp)
    let reopened = PublicNewsArchive(fileURL: file)
    reopened.load()
    XCTAssertEqual(reopened.articles.first { $0.id == b.id }?.readAt, stamp)
    XCTAssertFalse(try XCTUnwrap(reopened.articles.first { $0.id == a.id }).read)
    XCTAssertNil(reopened.articles.first { $0.id == a.id }?.readAt)
  }

  private func article(_ id: String, hour: TimeInterval, title: String? = nil,
                       summary: String = "A complete independent report describes the mission findings.") -> PublicNewsArticle {
    .init(url: URL(string: "https://\(id).example/report")!, title: title ?? self.title, summary: summary,
      publisher: id, publishedAt: base.addingTimeInterval(hour * 3_600),
      discoveredAt: base.addingTimeInterval(hour * 3_600), interests: [.technology])
  }
}
