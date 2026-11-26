import Foundation
import Combine
import XCTest
@testable import GalaxySSI

final class GlobalAgentDashboardLoaderTests: XCTestCase {
  func testBurstRequestsCoalesceIntoOneTrailingRefresh() throws {
    var state = GlobalAgentDashboardRefreshState()
    let first = try XCTUnwrap(state.request(identity: "one"))
    for _ in 0..<20 { XCTAssertNil(state.request(identity: "one")) }
    let completion = state.complete(first)
    XCTAssertTrue(completion.accepted)
    let trailing = try XCTUnwrap(completion.next)
    XCTAssertNotEqual(first, trailing)
    XCTAssertFalse(state.pending)
    XCTAssertNil(state.complete(trailing).next)
    XCTAssertNil(state.token)
  }

  func testInvalidationRejectsOldCompletion() throws {
    var state = GlobalAgentDashboardRefreshState()
    let old = try XCTUnwrap(state.request(identity: "one"))
    state.invalidate()
    XCTAssertFalse(state.complete(old).accepted)
    XCTAssertNil(state.identity)
    XCTAssertNil(state.token)
    XCTAssertFalse(state.pending)
  }

  func testIdentityChangeRejectsOldResultWithoutClearingNewWork() throws {
    var state = GlobalAgentDashboardRefreshState()
    let old = try XCTUnwrap(state.request(identity: "one"))
    let current = try XCTUnwrap(state.request(identity: "two"))
    XCTAssertNil(state.request(identity: "two"))
    XCTAssertFalse(state.complete(old).accepted)
    XCTAssertEqual(state.token, current)
    XCTAssertTrue(state.pending)
    XCTAssertNotNil(state.complete(current).next)
  }

  func testDuplicateCompletionCannotAcceptOrScheduleTwice() throws {
    var state = GlobalAgentDashboardRefreshState()
    let token = try XCTUnwrap(state.request(identity: "one"))
    XCTAssertTrue(state.complete(token).accepted)
    XCTAssertFalse(state.complete(token).accepted)
    XCTAssertNil(state.token)
  }

  @MainActor
  func testRefreshDoesNotReadSourcesOnCaller() async {
    let queue = DispatchQueue(label: "dashboard-background-fixture")
    queue.suspend()
    var loads = 0
    let loaded = expectation(description: "Background snapshot delivered")
    let loader = GlobalAgentDashboardLoader(queue: queue) {
      XCTAssertFalse(Thread.isMainThread)
      loads += 1
      return self.snapshot("loaded")
    }
    let observation = loader.$snapshot.sink {
      if $0.longHorizonGoals.first?.id == "loaded" { loaded.fulfill() }
    }
    loader.refresh(identity: "one")
    XCTAssertEqual(loads, 0)
    XCTAssertTrue(loader.snapshot.longHorizonGoals.isEmpty)
    queue.resume()
    await fulfillment(of: [loaded], timeout: 3)
    XCTAssertEqual(loads, 1)
    withExtendedLifetime(observation) {}
  }

  @MainActor
  func testFailedReadKeepsLastCompleteSnapshot() async {
    var loads = 0
    let loaded = expectation(description: "Complete snapshot")
    let failed = expectation(description: "Failed refresh")
    let loader = GlobalAgentDashboardLoader {
      loads += 1
      return loads == 1 ? self.snapshot("retained") : nil
    }
    let snapshotObservation = loader.$snapshot.sink {
      if $0.longHorizonGoals.first?.id == "retained" { loaded.fulfill() }
    }
    let failureObservation = loader.$refreshFailed.sink { if $0 { failed.fulfill() } }
    loader.refresh(identity: "one")
    await fulfillment(of: [loaded], timeout: 3)
    loader.refresh(identity: "one")
    await fulfillment(of: [failed], timeout: 3)
    XCTAssertEqual(loader.snapshot.longHorizonGoals.first?.id, "retained")
    withExtendedLifetime((snapshotObservation, failureObservation)) {}
  }

  @MainActor
  func testOffscreenPollingDoesNotReactivateLoader() async {
    let queue = DispatchQueue(label: "dashboard-offscreen-fixture")
    queue.suspend()
    var loads = 0
    let loader = GlobalAgentDashboardLoader(queue: queue) { loads += 1; return nil }
    loader.invalidate()
    loader.refreshIfActive(identity: "new")
    queue.resume()
    await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    XCTAssertEqual(loads, 0)
    XCTAssertTrue(loader.snapshot.longHorizonGoals.isEmpty)
  }

  private func snapshot(_ id: String) -> GlobalAgentDashboardRuntimeSnapshot {
    .init(longHorizonGoals: [.init(id: id, stableKey: id, topic: "GalaxySSI", title: id,
      status: .blocked, sourceConversationIds: ["conversation"], blocker: "Waiting", updatedAtMillis: 1_000)])
  }
}
