import Foundation
import XCTest
@testable import GalaxySSI

final class GlobalRealtimePlanningScopeTests: XCTestCase {
  func testDisabledScopeDoesNotLoadConversationsOrAccessProvider() {
    var sessionReads = 0, providerReads = 0
    func sessions() -> [AgentConversation] { sessionReads += 1; return [] }
    func provider() -> GlobalRealtimeContextProvider { providerReads += 1; return make([]) }
    let scope = GlobalRealtimePlanningScope(enabled: false, conversations: sessions())
    XCTAssertFalse(scope.canRead)
    XCTAssertEqual(scope.context(provider: provider(), query: "Status", currentConversationId: "a"), "")
    XCTAssertEqual(sessionReads, 0)
    XCTAssertEqual(providerReads, 0)
  }

  func testExplicitSuppressionDoesNotLoadConversationsOrAccessProvider() {
    var reads = 0, providerReads = 0
    func sessions() -> [AgentConversation] { reads += 1; return [session("a")] }
    func provider() -> GlobalRealtimeContextProvider { providerReads += 1; return make([]) }
    let scope = GlobalRealtimePlanningScope(enabled: true, suppressed: true, conversations: sessions())
    XCTAssertFalse(scope.canRead)
    XCTAssertTrue(scope.allowedConversationIds.isEmpty)
    XCTAssertEqual(scope.context(provider: provider(), query: "Status", currentConversationId: "a"), "")
    XCTAssertEqual(reads, 0)
    XCTAssertEqual(providerReads, 0)
  }

  func testBlankOverridesAndSelectedProviderRemainExplicitlySuppressed() {
    for text in ["", " \n\t "] {
      XCTAssertTrue(GlobalRealtimePlanningScope.suppressesGlobalContext(selectedProviderOnly: false, overrideGlobalContext: text))
    }
    XCTAssertTrue(GlobalRealtimePlanningScope.suppressesGlobalContext(selectedProviderOnly: true, overrideGlobalContext: "Allowed snapshot"))
    XCTAssertFalse(GlobalRealtimePlanningScope.suppressesGlobalContext(selectedProviderOnly: false, overrideGlobalContext: nil))
    XCTAssertFalse(GlobalRealtimePlanningScope.suppressesGlobalContext(selectedProviderOnly: false, overrideGlobalContext: "Allowed snapshot"))
  }

  func testOneCurrentConversationSnapshotDefinesAllowedAndExcludedIds() {
    var archived = session("archived")
    archived.status = .archived
    let scope = GlobalRealtimePlanningScope(enabled: true,
      conversations: [session("a"), session("private", privateMode: true), session("paused", trackingPaused: true), archived])
    XCTAssertEqual(scope.allowedConversationIds, ["a", "archived"])
    XCTAssertEqual(scope.excludedConversationIds, ["private", "paused"])
  }

  func testCachedProjectionRechecksPrivatePausedAndRemovedConversationsWithoutRefresh() {
    let queue = DispatchQueue(label: "planning-scope-cache")
    let provider = make([goal("Allowed task", ["a"]), goal("Private task", ["b"]),
      goal("Paused task", ["c"]), goal("Removed task", ["d"])], queue: queue)
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    let before = GlobalRealtimePlanningScope(enabled: true, conversations: [session("a"), session("b"), session("c"), session("d")])
    XCTAssertTrue(context(before, provider).contains("Private task"))
    let after = GlobalRealtimePlanningScope(enabled: true, conversations: [session("a"),
      session("b", privateMode: true), session("c", trackingPaused: true)])
    let result = context(after, provider)
    XCTAssertTrue(result.contains("Allowed task"))
    XCTAssertFalse(result.contains("Private task"))
    XCTAssertFalse(result.contains("Paused task"))
    XCTAssertFalse(result.contains("Removed task"))
  }

  func testMixedConversationItemsRequireEveryScopeAndGlobalItemsStayEligible() {
    let queue = DispatchQueue(label: "planning-scope-mixed")
    let provider = make([goal("Global task", []), goal("Mixed task", ["a", "deleted"]), goal("Known task", ["a"])], queue: queue)
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    let result = context(GlobalRealtimePlanningScope(enabled: true, conversations: [session("a")]), provider)
    XCTAssertTrue(result.contains("Global task"))
    XCTAssertTrue(result.contains("Known task"))
    XCTAssertFalse(result.contains("Mixed task"))
  }

  func testDisabledWarmCacheDoesNotScheduleAnotherSourceReadAndCanBeReenabled() {
    let queue = DispatchQueue(label: "planning-scope-toggle")
    var loads = 0
    let provider = GlobalRealtimeContextProvider(cognitionTasksSource: { [] }, researchTasksSource: { [] },
      autonomousRunsSource: { [] }, longHorizonGoalsSource: { loads += 1; return [self.goal("Warm task", ["a"])] },
      continuitySource: { nil }, refreshQueue: queue)
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    let off = GlobalRealtimePlanningScope(enabled: false, conversations: [session("a")])
    XCTAssertEqual(off.context(provider: provider, query: "All task status", currentConversationId: "a", nowMillis: 1_000_000), "")
    queue.sync {}
    XCTAssertEqual(loads, 1)
    XCTAssertTrue(context(GlobalRealtimePlanningScope(enabled: true, conversations: [session("a")]), provider).contains("Warm task"))
    XCTAssertEqual(loads, 1)
  }

  func testMixedGoalCannotLoseItsPrivateSourceBeforeAllowlistValidation() {
    let queue = DispatchQueue(label: "planning-scope-original-sources")
    let provider = make([goal("Shared private goal", ["a", "private"]),
      goal("Shared paused goal", ["a", "paused"]), goal("Allowed goal", ["a"])], queue: queue)
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    let before = GlobalRealtimePlanningScope(enabled: true, conversations: [session("a"), session("private"), session("paused")])
    XCTAssertTrue(context(before, provider).contains("Shared private goal"))
    let after = GlobalRealtimePlanningScope(enabled: true, conversations: [session("a"),
      session("private", privateMode: true), session("paused", trackingPaused: true)])
    let result = context(after, provider)
    XCTAssertTrue(result.contains("Allowed goal"))
    XCTAssertFalse(result.contains("Shared private goal"))
    XCTAssertFalse(result.contains("Shared paused goal"))
  }

  func testCallerCharacterLimitIsForwardedToCachedFormatter() {
    let queue = DispatchQueue(label: "planning-scope-bound")
    let provider = make((0..<12).map { goal("\($0) " + String(repeating: "Task detail ", count: 100), ["a"]) }, queue: queue)
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    let scope = GlobalRealtimePlanningScope(enabled: true, conversations: [session("a")])
    let limit = 1_000
    XCTAssertGreaterThan(context(scope, provider).count, limit)
    let result = scope.context(provider: provider, query: "All task status", currentConversationId: "a",
      maximumItems: 12, maximumCharacters: limit, nowMillis: 1_000)
    XCTAssertFalse(result.isEmpty)
    XCTAssertLessThanOrEqual(result.count, limit)
  }

  private func context(_ scope: GlobalRealtimePlanningScope, _ provider: GlobalRealtimeContextProvider) -> String {
    scope.context(provider: provider, query: "Show all tasks and current status", currentConversationId: "a", nowMillis: 1_000)
  }

  private func make(_ goals: [GlobalLongHorizonGoal], queue: DispatchQueue = DispatchQueue(label: "scope-fixture")) -> GlobalRealtimeContextProvider {
    .init(cognitionTasksSource: { [] }, researchTasksSource: { [] }, autonomousRunsSource: { [] },
      longHorizonGoalsSource: { goals }, continuitySource: { nil }, refreshQueue: queue)
  }

  private func session(_ id: String, privateMode: Bool = false, trackingPaused: Bool = false) -> AgentConversation {
    .init(id: id, title: id, createdAt: 1, updatedAt: 1, privateMode: privateMode, trackingPaused: trackingPaused)
  }

  private func goal(_ title: String, _ conversations: Set<String>) -> GlobalLongHorizonGoal {
    .init(id: title, stableKey: title, topic: "GalaxySSI", title: title, status: .blocked,
      sourceConversationIds: conversations, blocker: "Waiting", updatedAtMillis: 1_000)
  }
}
