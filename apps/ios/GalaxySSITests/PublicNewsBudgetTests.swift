import XCTest
@testable import GalaxySSI

@MainActor
final class PublicNewsBudgetTests: XCTestCase {
  private let now: TimeInterval = 360_000
  private func profile(_ last: TimeInterval, charging: Bool) -> PublicNewsBudgetProfile {
    .init(now: now, lastRead: last, charging: charging)
  }
  private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "PublicNewsBudgetTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }
  func testIdleTopicsUseTwelveHoursEvenWhileCharging() {
    for last in [0, now - 86_400, now + 3_600, .nan] {
      for charging in [false, true] {
        let value = profile(last, charging: charging)
        XCTAssertFalse(value.recentlyRead); XCTAssertFalse(value.allowPush)
        XCTAssertEqual(value.feedInterval, 43_200)
      }
    }
  }
  func testActiveReadingAndChargingSelectAndroidLimitsAndSpacing() {
    let battery = profile(now - 3_600, charging: false), plugged = profile(now - 3_600, charging: true)
    XCTAssertEqual(battery.feedInterval, 3_600); XCTAssertEqual(plugged.feedInterval, 1_800)
    XCTAssertEqual(battery.feedSpacing, 60); XCTAssertEqual(plugged.feedSpacing, 15)
    XCTAssertEqual(profile(0, charging: false).feedSpacing, 300)
    XCTAssertEqual(battery.articleLimit, 4); XCTAssertEqual(plugged.articleLimit, 10)
    XCTAssertEqual(profile(0, charging: false).articleLimit, 2)
    XCTAssertEqual(battery.articleTime, 30); XCTAssertEqual(plugged.articleTime, 60)
    XCTAssertFalse(battery.allowPush); XCTAssertTrue(plugged.allowPush)
  }
  func testZeroOutputAndIdleBackoffUsePersistedBoundary() throws {
    try withDefaults { defaults in
      let at = Date(timeIntervalSince1970: now)
      let budget = PublicNewsBudget(defaults: defaults)
      budget.noteRead(now: at.addingTimeInterval(-3_600))
      budget.articleBoundary(now: at.addingTimeInterval(-660))
      let restarted = PublicNewsBudget(defaults: defaults)
      XCTAssertEqual(restarted.articleDelay(now: at, charging: false), 34 * 60)
      XCTAssertEqual(restarted.articleDelay(now: at, charging: true), 0)
      restarted.articleBoundary(now: at.addingTimeInterval(-660), published: true)
      XCTAssertEqual(restarted.articleDelay(now: at, charging: false), 4 * 60)
      let tomorrow = at.addingTimeInterval(86_400)
      restarted.articleBoundary(now: tomorrow)
      XCTAssertEqual(restarted.articleDelay(now: tomorrow, charging: false), 43_200)
      XCTAssertEqual(restarted.articleDelay(now: tomorrow, charging: true), 600)
    }
  }
  func testOnlySweepBoundaryUsesLongIntervalAndReadingRestoresCadence() throws {
    try withDefaults { defaults in
      let at = Date(timeIntervalSince1970: now), later = Date(timeIntervalSince1970: now + 60)
      let budget = PublicNewsBudget(defaults: defaults)
      budget.feedFinished(now: at, completedSweep: true)
      let restarted = PublicNewsBudget(defaults: defaults)
      XCTAssertEqual(restarted.feedDelay(now: later, atSweepBoundary: true, charging: false), 43_140)
      XCTAssertEqual(restarted.feedDelay(now: later, atSweepBoundary: false, charging: false), 240)
      restarted.noteRead(now: later)
      XCTAssertEqual(restarted.feedDelay(now: later, atSweepBoundary: true, charging: false), 3_540)
      XCTAssertEqual(restarted.feedDelay(now: later, atSweepBoundary: true, charging: true), 1_740)
      XCTAssertEqual(restarted.feedDelay(now: later, atSweepBoundary: false, charging: false), 0)
      restarted.feedFinished(now: later, completedSweep: false)
      XCTAssertEqual(restarted.feedDelay(now: later, atSweepBoundary: false, charging: true), 15)
    }
  }
  func testReadTimestampWritesAtMostOncePerMinuteAndBadClockIsNotActiveReading() throws {
    try withDefaults { defaults in
      let budget = PublicNewsBudget(defaults: defaults), at = Date(timeIntervalSince1970: now)
      budget.noteRead(now: at)
      budget.noteRead(now: at.addingTimeInterval(59))
      XCTAssertFalse(budget.profile(now: at.addingTimeInterval(86_400), charging: true).recentlyRead)
      XCTAssertFalse(budget.profile(now: at.addingTimeInterval(-1), charging: true).recentlyRead)
      budget.noteRead(now: at.addingTimeInterval(60))
      XCTAssertTrue(budget.profile(now: at.addingTimeInterval(86_400), charging: true).recentlyRead)
      XCTAssertEqual(PublicNewsBudgetProfile.remaining(now: now, last: now + 1, interval: 60), 0)
      XCTAssertEqual(PublicNewsBudgetProfile.remaining(now: now, last: .nan, interval: 60), 0)
    }
  }
  func testTenPercentOfOneCoreSuspendsNewsForFiveMinutes() {
    var window = PublicNewsCPUWindow()
    XCTAssertEqual(window.delay(uptime: 1, cpu: 0.5), 0)
    XCTAssertEqual(window.delay(uptime: 6, cpu: 1), 0)
    XCTAssertEqual(window.delay(uptime: 11, cpu: 1.5), 300)
    XCTAssertEqual(window.delay(uptime: 71, cpu: 1.6), 240)
    XCTAssertEqual(window.delay(uptime: 311, cpu: 1.6), 0)
    XCTAssertEqual(window.delay(uptime: 321, cpu: 2.599), 0)
  }
  func testLongIdleAndCounterResetDoNotChargeOldCpuToNewBatch() {
    var window = PublicNewsCPUWindow()
    XCTAssertEqual(window.delay(uptime: 1, cpu: 1), 0)
    XCTAssertEqual(window.delay(uptime: 121, cpu: 100), 0)
    XCTAssertEqual(window.delay(uptime: 131, cpu: 101.5), 300)
    XCTAssertEqual(window.delay(uptime: 1, cpu: 0), 0)
    XCTAssertEqual(window.delay(uptime: 11, cpu: 0.9), 0)
    XCTAssertEqual(window.delay(uptime: 21, cpu: 0.1), 0)
    XCTAssertEqual(window.delay(uptime: .nan, cpu: 0), 60)
  }
  func testUnvisitedFeedsAreNotAdvancedAndCompletedCursorSurvivesRestart() throws {
    var state = PublicNewsPublisherState()
    let sources = state.plan(now: Date(), enabled: false, probe: false, advanceBuiltIns: false)
    let first = try XCTUnwrap(sources.first)
    XCTAssertEqual(state.builtInOffset, 0)
    state.recordPoll(first, success: true, discussion: false, now: Date())
    var reopened = try JSONDecoder().decode(PublicNewsPublisherState.self, from: JSONEncoder().encode(state))
    XCTAssertEqual(reopened.builtInOffset, 1 % PublicNewsSource.builtIn.count)
    let next = reopened.plan(now: Date(), enabled: false, probe: false, advanceBuiltIns: false)
    XCTAssertEqual(next.first?.url, PublicNewsSource.builtIn[reopened.builtInOffset].url)
    for source in PublicNewsSource.builtIn { reopened.recordPoll(source, success: false, discussion: false, now: Date()) }
    XCTAssertEqual(reopened.builtInOffset, 0)
  }
  func testLearnedFeedCadenceChangesWithoutOverwritingFailureBackoff() throws {
    let at = Date(timeIntervalSince1970: now)
    let feed = PublicNewsPublisherState.Feed(url: URL(string: "https://simonwillison.net/feeds/fixture.xml")!,
      publisher: "simonwillison.net", interests: [], pollAfter: at)
    var state = PublicNewsPublisherState(feeds: [feed])
    state.recordPoll(feed.source, success: true, discussion: false, now: at, interval: 43_200)
    _ = state.plan(now: at, enabled: true, probe: false, interval: 1_800)
    XCTAssertEqual(state.feeds.first?.pollAfter, at.addingTimeInterval(1_800))
    state.recordPoll(feed.source, success: false, discussion: false, now: at.addingTimeInterval(1_800))
    let retry = state.feeds.first?.pollAfter
    _ = state.plan(now: at, enabled: true, probe: false, interval: 43_200)
    XCTAssertEqual(state.feeds.first?.pollAfter, retry)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(feed)) as? [String: Any])
    object.removeValue(forKey: "lastPoll"); object.removeValue(forKey: "storedInterval")
    let old = try JSONDecoder().decode(PublicNewsPublisherState.Feed.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(old.lastPoll); XCTAssertNil(old.storedInterval)
  }
  func testBudgetReleaseDoesNotIncrementRetryFailuresOrLoseClaims() {
    let at = Date(timeIntervalSince1970: now)
    var headlines = PublicNewsHeadlineRetryLedger()
    let lease = headlines.claim(["title"], at: at, retaining: ["title"])
    headlines.releaseBudgetClaim("title", lease: UUID(), at: at, delay: 300)
    XCTAssertEqual(headlines.entries["title"]?.lease, lease)
    headlines.releaseBudgetClaim("title", lease: lease, at: at, delay: 300)
    XCTAssertNil(headlines.entries["title"]?.lease); XCTAssertEqual(headlines.entries["title"]?.attempts, 0)
    XCTAssertEqual(headlines.entries["title"]?.next, at.addingTimeInterval(300))
    let backlog = PublicNewsBacklogLedger()
    XCTAssertEqual(backlog.nextEligible(articleIDs: ["pending"], now: at), at)
    XCTAssertNil(backlog.nextEligible(articleIDs: [], now: at))
  }
  func testTranslationBudgetYieldPreservesPreviouslySavedSegments() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PublicNewsBodyStore(root: root), id = "https://github.blog/budget-fixture"
    let original = PublicNewsOriginalBody(title: "Publisher report", paragraphs: ["First paragraph."])
    let staged = try await store.install(original, articleID: id)
    let saved = try await store.record("\u{53D1}\u{5E03}\u{62A5}\u{544A}", index: 0, articleID: id, fingerprint: staged.fingerprint)
    do {
      _ = try await PublicNewsTranslation.run(saved, store: store,
        budgetCheck: { throw PublicNewsBudgetYield() }, progress: { _ in })
      XCTFail("A deferred budget must yield before starting the next segment")
    } catch is PublicNewsBudgetYield { }
    let reopened = await PublicNewsBodyStore(root: root).load(id)
    XCTAssertEqual(reopened?.translated, saved.translated)
  }
}
