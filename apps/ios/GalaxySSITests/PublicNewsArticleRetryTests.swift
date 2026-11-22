import SQLite3
import XCTest
@testable import GalaxySSI

@MainActor
final class PublicNewsArticleRetryTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func article(_ name: String) -> PublicNewsArticle {
    .init(url: URL(string: "https://github.blog/\(name)")!, title: name, summary: "", publisher: "Fixture", discoveredAt: now)
  }
  private func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
  private func fail(_ article: PublicNewsArticle, in ledger: inout PublicNewsBacklogLedger, count: Int = 1) throws {
    for index in 0..<count {
      let date = now.addingTimeInterval(Double(index) * 20_000)
      let claim = try XCTUnwrap(ledger.claim([article], now: date))
      ledger.finish(claim, outcome: .failure("article_extraction_failed"), now: date)
    }
  }
  private func legacy(_ ledger: PublicNewsBacklogLedger) throws -> Data {
    var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger)) as? [String: Any])
    value.removeValue(forKey: "retryPolicyRevision"); value.removeValue(forKey: "pendingCleanup")
    return try JSONSerialization.data(withJSONObject: value)
  }
  private func seed(_ articles: [PublicNewsArticle], file: URL) throws {
    try JSONEncoder().encode(PublicNewsArchiveStorage.Snapshot(articles: articles)).write(to: file)
    _ = try PublicNewsRowArchive.load(legacyURL: file)
  }
  private func body(_ article: PublicNewsArticle, store: PublicNewsBodyStore, completed: Bool) async throws {
    let original = PublicNewsOriginalBody(title: "\u{62A5}\u{544A}", paragraphs: ["\u{5185}\u{5BB9}"])
    let staged = try await store.install(original, articleID: article.id)
    if completed {
      for (index, segment) in staged.segments.enumerated() {
        _ = try await store.record(segment, index: index, articleID: article.id, fingerprint: staged.fingerprint)
      }
    }
  }

  func testRetryPolicyAllowsThreeRetriesAfterInitialFailure() {
    for attempt in 0..<3 { XCTAssertFalse(PublicNewsArticleRetryPolicy.exhausted(attemptsBeforeClaim: attempt)) }
    XCTAssertTrue(PublicNewsArticleRetryPolicy.exhausted(attemptsBeforeClaim: 3))
    for attempt in 0...3 {
      XCTAssertEqual(PublicNewsArticleRetryPolicy.delay(attemptsBeforeClaim: attempt, error: "article_extraction_failed"),
        1_800 * pow(2, Double(attempt)))
      for reason in ["article_translation_timeout", "article_translation_model_pending", "request_timeout"] {
        XCTAssertEqual(PublicNewsArticleRetryPolicy.delay(attemptsBeforeClaim: attempt, error: reason), 60 * pow(2, Double(attempt)))
      }
    }
    XCTAssertEqual(PublicNewsArticleRetryPolicy.delay(attemptsBeforeClaim: 100, error: "article_bad"), 14_400)
  }
  func testFourthFailureDropsEntryButRetainsOnlyCleanupHash() throws {
    let value = article("exhausted")
    var ledger = PublicNewsBacklogLedger()
    try fail(value, in: &ledger, count: 3)
    XCTAssertEqual(ledger.entries[value.id]?.failures, 3)
    XCTAssertTrue(ledger.pendingCleanupKeys.isEmpty)
    let at = now.addingTimeInterval(60_000)
    let last = try XCTUnwrap(ledger.claim([value], now: at))
    ledger.finish(last, outcome: .retry, now: at)
    ledger.finish(last, outcome: .ready, now: at)
    XCTAssertNil(ledger.entries[value.id])
    XCTAssertEqual(ledger.pendingCleanupKeys, [PublicNewsArticleRetryPolicy.key(value.id)])
    XCTAssertNil(ledger.claim([value], now: at.addingTimeInterval(100_000)))
    XCTAssertNil(ledger.nextEligible(articleIDs: [value.id], now: at))
    let data = try JSONEncoder().encode(ledger)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(value.id))
    XCTAssertEqual(try JSONDecoder().decode(PublicNewsBacklogLedger.self, from: data), ledger)
    let counts = ledger.counts(articleIDs: [value.id], cachedReady: [], now: at)
    XCTAssertEqual(counts.waiting + counts.retry + counts.processing, 0)
  }
  func testBudgetReleasesDoNotSpendFailureAllowanceAndSuccessResetsFailures() throws {
    let value = article("paused")
    var ledger = PublicNewsBacklogLedger()
    for _ in 0..<10 {
      let claim = try XCTUnwrap(ledger.claim([value], now: now))
      ledger.finish(claim, outcome: .released, now: now)
    }
    XCTAssertEqual(ledger.entries[value.id]?.failures, 0)
    try fail(value, in: &ledger)
    let later = now.addingTimeInterval(2_000)
    let ready = try XCTUnwrap(ledger.claim([value], now: later))
    ledger.finish(ready, outcome: .ready, now: later)
    XCTAssertEqual(ledger.entries[value.id]?.failures, 0)
    XCTAssertTrue(ledger.entries[value.id]?.everPublished == true)
  }
  func testExhaustedRepairKeepsPublicationProofEvenAfterCacheEviction() throws {
    let value = article("published")
    var ledger = PublicNewsBacklogLedger()
    ledger.reconcileReady([value.id], cachedReady: [value.id], now: now)
    ledger.reconcileReady([value.id], cachedReady: [], now: now)
    try fail(value, in: &ledger, count: 4)
    XCTAssertTrue(ledger.entries[value.id]?.stopped == true); XCTAssertTrue(ledger.pendingCleanupKeys.isEmpty)
    ledger.reconcileReady([value.id], cachedReady: [value.id], now: now)
    ledger.reconcileReady([value.id], cachedReady: [], now: now)
    ledger.reconcile([], now: now)
    XCTAssertTrue(ledger.entries[value.id]?.everPublished == true)
    XCTAssertNil(ledger.claim([value], now: now.addingTimeInterval(100_000)))
    XCTAssertNil(ledger.nextEligible(articleIDs: [value.id], now: now))
  }
  func testUpgradeRemovesOldFailedOnlyOnceAndLeavesFreshRetries() throws {
    let failed = article("failed"), pending = article("pending"), published = article("published")
    var original = PublicNewsBacklogLedger()
    try fail(failed, in: &original)
    let claim = try XCTUnwrap(original.claim([pending], now: now)); original.finish(claim, outcome: .released, now: now)
    original.reconcileReady([failed.id, pending.id, published.id], cachedReady: [published.id], now: now)
    var migrated = try JSONDecoder().decode(PublicNewsBacklogLedger.self, from: legacy(original))
    XCTAssertNil(migrated.retryPolicyRevision)
    migrated.prepareRetryPolicy(cachedReady: [])
    XCTAssertNil(migrated.entries[failed.id]); XCTAssertNotNil(migrated.entries[pending.id])
    XCTAssertTrue(migrated.entries[published.id]?.everPublished == true)
    let fresh = article("new-retry"); try fail(fresh, in: &migrated)
    migrated.prepareRetryPolicy(cachedReady: [])
    XCTAssertEqual(migrated.entries[fresh.id]?.failures, 1)
  }
  func testUpgradeCleansFailedQueueAndPreservesPublishedAndUnattemptedContent() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("news.json"), queue = root.appendingPathComponent("queue.json")
    let failed = article("failed"), pending = article("pending"), published = article("published")
    try seed([failed, pending, published], file: file)
    let bodies = PublicNewsBodyStore(root: root.appendingPathComponent("bodies"))
    try await body(failed, store: bodies, completed: false)
    try await body(pending, store: bodies, completed: false)
    try await body(published, store: bodies, completed: true)
    var original = PublicNewsBacklogLedger()
    try fail(failed, in: &original); try fail(published, in: &original)
    try legacy(original).write(to: queue)
    let archive = PublicNewsArchive(fileURL: file, backlog: PublicNewsBacklogStore(file: queue), bodies: bodies)
    archive.load()
    let migrated = await archive.prepareArticleRetryPolicy()
    XCTAssertTrue(migrated)
    XCTAssertEqual(Set(archive.articles.map(\.id)), [pending.id, published.id])
    let removedBody = await bodies.load(failed.id), untouchedBody = await bodies.load(pending.id), keptBody = await bodies.load(published.id)
    XCTAssertNil(removedBody); XCTAssertNotNil(untouchedBody); XCTAssertNotNil(keptBody?.completed)
    XCTAssertEqual(try PublicNewsRowArchive.discardedIDs(legacyURL: file, candidates: [failed.id, pending.id]), [failed.id])
    XCTAssertEqual(try PublicNewsRowArchive.unreadCount(legacyURL: file), 2)
    let restarted = PublicNewsArchive(fileURL: file, backlog: PublicNewsBacklogStore(file: queue), bodies: bodies)
    restarted.load()
    let repeated = await restarted.prepareArticleRetryPolicy()
    XCTAssertTrue(repeated); XCTAssertEqual(restarted.articles, archive.articles)
    let state = try await archive.articleBacklog.load()
    XCTAssertTrue(state.pendingCleanupKeys.isEmpty); XCTAssertTrue(state.entries[published.id]?.stopped == true)
  }
  func testInterruptedCleanupResumesAfterArchiveCommitAndBlocksRediscovery() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("news.json"), queue = root.appendingPathComponent("queue.json")
    let failed = article("discarded"); try seed([failed], file: file)
    let bodies = PublicNewsBodyStore(root: root.appendingPathComponent("bodies"))
    try await body(failed, store: bodies, completed: false)
    var ledger = PublicNewsBacklogLedger(); try fail(failed, in: &ledger, count: 4)
    try JSONEncoder().encode(ledger).write(to: queue)
    try PublicNewsRowArchive.discardUnpublished(legacyURL: file, keys: ledger.pendingCleanupKeys)
    let beforeResume = await bodies.load(failed.id); XCTAssertNotNil(beforeResume)
    let archive = PublicNewsArchive(fileURL: file, backlog: PublicNewsBacklogStore(file: queue), bodies: bodies)
    archive.load(); let resumed = await archive.prepareArticleRetryPolicy(); XCTAssertTrue(resumed)
    let removed = await bodies.load(failed.id); XCTAssertNil(removed)
    let state = try await archive.articleBacklog.load(); XCTAssertTrue(state.pendingCleanupKeys.isEmpty)
    let saved = try PublicNewsRowArchive.load(legacyURL: file)
    XCTAssertThrowsError(try PublicNewsRowArchive.save(legacyURL: file, revision: saved.revision,
      previous: [], previousHidden: [], next: .init(articles: [failed])))
    XCTAssertTrue(try PublicNewsRowArchive.load(legacyURL: file).snapshot.articles.isEmpty)
  }
  func testBodyCompletedAfterDiscardWasQueuedIsRescued() async throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("news.json"), queue = root.appendingPathComponent("queue.json")
    let value = article("just-completed"); try seed([value], file: file)
    var ledger = PublicNewsBacklogLedger(); try fail(value, in: &ledger, count: 4)
    try JSONEncoder().encode(ledger).write(to: queue)
    let bodies = PublicNewsBodyStore(root: root.appendingPathComponent("bodies"))
    try await body(value, store: bodies, completed: true)
    let archive = PublicNewsArchive(fileURL: file, backlog: PublicNewsBacklogStore(file: queue), bodies: bodies)
    archive.load(); let prepared = await archive.prepareArticleRetryPolicy(); XCTAssertTrue(prepared)
    XCTAssertEqual(archive.articles, [value])
    XCTAssertTrue(try PublicNewsRowArchive.discardedIDs(legacyURL: file, candidates: [value.id]).isEmpty)
    let state = try await archive.articleBacklog.load()
    XCTAssertTrue(state.entries[value.id]?.everPublished == true); XCTAssertTrue(state.entries[value.id]?.stopped == true)
    let kept = await bodies.load(value.id); XCTAssertNotNil(kept?.completed)
  }
  func testDatabaseFailureDoesNotDeleteIncompleteBodyAndInvalidKeysAreRejected() async throws {
    struct FixtureFailure: Error {}
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let bodies = PublicNewsBodyStore(root: root), value = article("commit-failed")
    try await body(value, store: bodies, completed: false)
    do {
      _ = try await bodies.discardUnpublished([PublicNewsArticleRetryPolicy.key(value.id)], preserving: []) { _ in throw FixtureFailure() }
      XCTFail("A failed archive commit must not delete the body")
    } catch is FixtureFailure { }
    let saved = await bodies.load(value.id); XCTAssertNotNil(saved)
    do {
      _ = try await bodies.discardUnpublished(["../escape"], preserving: []) { _ in XCTFail("Invalid keys must never reach the commit") }
      XCTFail("Invalid keys must be rejected")
    } catch PublicNewsArticleBodyError.incompleteSource { }
  }
  func testVersionOneArchiveUpgradesWithoutLosingRows() throws {
    let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("news.json"), value = article("retained")
    try seed([value], file: file)
    let db = PublicNewsRowArchive.directory(for: file).appendingPathComponent("archive.sqlite3")
    var pointer: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(db.path, &pointer, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
    let connection = try XCTUnwrap(pointer)
    XCTAssertEqual(sqlite3_exec(connection, "DROP TABLE discarded_article; PRAGMA user_version = 1", nil, nil, nil), SQLITE_OK)
    sqlite3_close_v2(connection)
    let upgraded = try PublicNewsRowArchive.load(legacyURL: file)
    XCTAssertEqual(upgraded.schemaVersion, 2); XCTAssertEqual(upgraded.snapshot.articles, [value])
  }
}
