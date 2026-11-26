import Foundation
import XCTest
@testable import GalaxySSI

final class GlobalRealtimePrewarmTests: XCTestCase {
  func testPrewarmReturnsBeforeSourceIOAndCoalescesConcurrentRequests() {
    let queue = DispatchQueue(label: "prewarm-fixture")
    var loads = 0
    let provider = make(queue) { loads += 1; return [self.goal("Ready")] }
    queue.suspend()
    for _ in 0..<20 { provider.prewarm(nowMillis: 1_000) }
    XCTAssertEqual(context(provider), "")
    XCTAssertEqual(loads, 0)
    queue.resume(); queue.sync {}
    XCTAssertEqual(loads, 1)
    XCTAssertTrue(context(provider).contains("Ready"))
    XCTAssertEqual(loads, 1)
  }

  func testLastCompleteSnapshotSurvivesBackgroundRefreshAndTTLBoundary() {
    let queue = DispatchQueue(label: "prewarm-ttl")
    var loads = 0, title = "Original"
    let provider = make(queue) { loads += 1; return [self.goal(title)] }
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    XCTAssertTrue(context(provider, now: 15_999).contains("Original"))
    XCTAssertEqual(loads, 1)
    queue.suspend()
    title = "Updated"
    XCTAssertTrue(context(provider, now: 16_000).contains("Original"))
    XCTAssertTrue(context(provider, now: 16_000).contains("Original"))
    XCTAssertEqual(loads, 1)
    queue.resume(); queue.sync {}
    XCTAssertTrue(context(provider, now: 16_000).contains("Updated"))
    XCTAssertEqual(loads, 2)
  }

  func testInvalidatedOldProducerCannotPublishOrClearTheNewRefreshToken() {
    let queue = DispatchQueue(label: "prewarm-invalidation")
    let firstStarted = DispatchSemaphore(value: 0), firstRelease = DispatchSemaphore(value: 0)
    let secondStarted = DispatchSemaphore(value: 0), secondRelease = DispatchSemaphore(value: 0)
    var loads = 0
    let provider = make(queue) {
      loads += 1
      if loads == 1 {
        firstStarted.signal(); _ = firstRelease.wait(timeout: .now() + 3)
        return [self.goal("Old owner")]
      }
      secondStarted.signal(); _ = secondRelease.wait(timeout: .now() + 3)
      return [self.goal("New owner")]
    }
    provider.prewarm(nowMillis: 1_000)
    XCTAssertEqual(firstStarted.wait(timeout: .now() + 3), .success)
    provider.invalidate()
    provider.prewarm(nowMillis: 2_000)
    firstRelease.signal()
    XCTAssertEqual(secondStarted.wait(timeout: .now() + 3), .success)
    XCTAssertEqual(context(provider, now: 2_000), "", "The old producer must not publish while new refresh is in flight")
    secondRelease.signal(); queue.sync {}
    let result = context(provider, now: 2_000)
    XCTAssertTrue(result.contains("New owner"))
    XCTAssertFalse(result.contains("Old owner"))
    XCTAssertEqual(loads, 2)
  }

  func testAllowedAndExcludedConversationSetsApplyToEveryCachedRender() {
    let queue = DispatchQueue(label: "prewarm-scope")
    let provider = make(queue) { [self.goal("Allowed work", conversation: "allowed"),
      self.goal("Private work", conversation: "private"), self.goal("Deleted work", conversation: "deleted")] }
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    let rendered = provider.buildNonBlocking(query: "Show all tasks and current status", currentConversationId: "allowed",
      excludedConversationIds: ["private"], nowMillis: 1_000, allowedConversationIds: ["allowed"])
    XCTAssertTrue(rendered.contains("Allowed work"))
    XCTAssertFalse(rendered.contains("Private work"))
    XCTAssertFalse(rendered.contains("Deleted work"))
    XCTAssertEqual(provider.buildNonBlocking(query: "Show all tasks and current status", currentConversationId: "allowed",
      excludedConversationIds: ["allowed", "private"], nowMillis: 1_000, allowedConversationIds: ["allowed"]), "")
  }

  func testClockRollbackAndOverflowRefreshWithoutTrapping() {
    for captured in [Int64(1_000), Int64.min] {
      let queue = DispatchQueue(label: "prewarm-clock")
      var loads = 0
      let provider = make(queue) { loads += 1; return [] }
      provider.prewarm(nowMillis: captured); queue.sync {}
      queue.suspend()
      _ = context(provider, now: captured == Int64.min ? Int64.max : 999)
      XCTAssertEqual(loads, 1)
      queue.resume(); queue.sync {}
      XCTAssertEqual(loads, 2)
    }
  }

  func testInvalidationDropsWarmSnapshotUntilFreshSourceCompletes() {
    let queue = DispatchQueue(label: "prewarm-clear")
    var title = "Previous scope"
    let provider = make(queue) { [self.goal(title)] }
    provider.prewarm(nowMillis: 1_000); queue.sync {}
    XCTAssertTrue(context(provider).contains("Previous scope"))
    queue.suspend()
    provider.invalidate(); title = "Current scope"
    XCTAssertEqual(context(provider), "")
    queue.resume(); queue.sync {}
    XCTAssertTrue(context(provider).contains("Current scope"))
    XCTAssertFalse(context(provider).contains("Previous scope"))
  }

  func testInvalidatedQueuedRefreshSkipsSourceIOWithoutClearingNewWork() {
    let queue = DispatchQueue(label: "prewarm-obsolete-queued")
    var loads = 0
    let provider = make(queue) { loads += 1; return [self.goal("Current source")] }
    queue.suspend()
    provider.prewarm(nowMillis: 1_000)
    provider.invalidate()
    provider.prewarm(nowMillis: 2_000)
    queue.resume(); queue.sync {}
    XCTAssertEqual(loads, 1)
    XCTAssertTrue(context(provider, now: 2_000).contains("Current source"))
  }

  func testExplicitSynchronousBuildRetainsItsOriginalContract() {
    let queue = DispatchQueue(label: "prewarm-explicit-build")
    var loads = 0
    let provider = make(queue) { loads += 1; return [self.goal("Synchronous source")] }
    let result = provider.build(query: "Show all tasks and current status", currentConversationId: "conversation", nowMillis: 1_000)
    XCTAssertTrue(result.contains("Synchronous source"))
    XCTAssertEqual(loads, 1)
  }

  private func make(_ queue: DispatchQueue, goals: @escaping () -> [GlobalLongHorizonGoal]) -> GlobalRealtimeContextProvider {
    .init(cognitionTasksSource: { [] }, researchTasksSource: { [] }, autonomousRunsSource: { [] },
      longHorizonGoalsSource: goals, continuitySource: { nil }, refreshQueue: queue)
  }
  private func context(_ provider: GlobalRealtimeContextProvider, now: Int64 = 1_000) -> String {
    provider.buildNonBlocking(query: "Show all tasks and current status", currentConversationId: "conversation", nowMillis: now)
  }
  private func goal(_ title: String, conversation: String = "conversation") -> GlobalLongHorizonGoal {
    .init(id: "goal-" + conversation, stableKey: "goal-" + conversation, topic: "GalaxySSI", title: title, status: .blocked,
      sourceConversationIds: [conversation], blocker: "Waiting", updatedAtMillis: 1_000)
  }
}
