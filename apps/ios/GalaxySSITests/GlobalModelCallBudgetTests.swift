import XCTest
@testable import GalaxySSI

final class GlobalModelCallBudgetTests: XCTestCase {
  func testGlobalModelCallBudgetAcquisitionIdempotencyAndConcurrency() {
    let first = acquireModelCall(GlobalModelCallBudgetState(), "call-1", concurrencyLimit: 1)
    let duplicateActive = acquireModelCall(first.state, "call-1", concurrencyLimit: 1)
    let blocked = acquireModelCall(first.state, "call-2", concurrencyLimit: 1)
    let released = GlobalModelCallBudgetPolicy.release(
      state: first.state,
      leaseId: first.leaseId,
      nowMillis: globalBudgetNow + 100
    )
    let second = acquireModelCall(
      released,
      "call-2",
      concurrencyLimit: 1,
      nowMillis: globalBudgetNow + 100
    )
    let duplicateReleased = acquireModelCall(
      released,
      "call-1",
      nowMillis: globalBudgetNow + 100
    )

    XCTAssertTrue(first.granted)
    XCTAssertTrue(first.leaseId.hasPrefix("model-call:"))
    XCTAssertEqual(first.state.dispatches.count, 1)
    XCTAssertEqual(first.state.activeLeases.count, 1)
    XCTAssertEqual(first.state.activeLeases.first?.ownerKey, "call-1")
    XCTAssertTrue(duplicateActive.granted)
    XCTAssertEqual(duplicateActive.leaseId, first.leaseId)
    XCTAssertEqual(duplicateActive.state.dispatches.count, 1)
    XCTAssertFalse(blocked.granted)
    XCTAssertEqual(blocked.denial, .concurrencyLimit)
    XCTAssertEqual(blocked.nextEligibleAtMillis, globalBudgetNow + globalBudgetLeaseMillis)
    XCTAssertTrue(second.granted)
    XCTAssertEqual(second.state.dispatches.count, 2)
    XCTAssertEqual(second.state.activeLeases.count, 1)
    XCTAssertFalse(duplicateReleased.granted)
    XCTAssertEqual(duplicateReleased.denial, .duplicateDispatch)
  }

  func testGlobalModelCallBudgetRollingDailyTokenAndCostLimits() {
    let first = acquireModelCall(GlobalModelCallBudgetState(), "call-1", dailyLimit: 1)
    let released = GlobalModelCallBudgetPolicy.release(
      state: first.state,
      leaseId: first.leaseId,
      nowMillis: globalBudgetNow + 100
    )
    let dailyDenied = acquireModelCall(
      released,
      "call-2",
      dailyLimit: 1,
      nowMillis: globalBudgetNow + 100
    )
    let afterWindow = acquireModelCall(
      dailyDenied.state,
      "call-2",
      dailyLimit: 1,
      nowMillis: globalBudgetNow + GlobalModelCallBudgetPolicy.windowMillis + 1
    )

    let tokenReserved = acquireModelCall(
      GlobalModelCallBudgetState(),
      "token-1",
      estimatedInputTokens: 9_000,
      dailyTokenLimit: 10_000
    )
    let tokenCompleted = GlobalModelCallBudgetPolicy.complete(
      state: tokenReserved.state,
      leaseId: tokenReserved.leaseId,
      inputTokens: 9_000,
      outputTokens: 900,
      reportedCostMicros: 0,
      responseText: "done",
      nowMillis: globalBudgetNow + 100
    )
    let tokenDenied = acquireModelCall(
      tokenCompleted,
      "token-2",
      estimatedInputTokens: 500,
      dailyTokenLimit: 10_000,
      nowMillis: globalBudgetNow + 200
    )

    let oversized = acquireModelCall(
      GlobalModelCallBudgetState(),
      "oversized",
      estimatedInputTokens: 20_000,
      dailyTokenLimit: 10_000
    )
    let oversizedReleased = GlobalModelCallBudgetPolicy.release(
      state: oversized.state,
      leaseId: oversized.leaseId,
      nowMillis: globalBudgetNow + 1
    )
    let oversizedFollowUp = acquireModelCall(
      oversizedReleased,
      "oversized-next",
      estimatedInputTokens: 1,
      dailyTokenLimit: 10_000,
      nowMillis: globalBudgetNow + 2
    )

    let costFirst = acquireModelCall(
      GlobalModelCallBudgetState(),
      "cost-1",
      dailyReportedCostLimitMicros: 10_000
    )
    let costCompleted = GlobalModelCallBudgetPolicy.complete(
      state: costFirst.state,
      leaseId: costFirst.leaseId,
      inputTokens: 10,
      outputTokens: 5,
      reportedCostMicros: 10_000,
      responseText: "done",
      nowMillis: globalBudgetNow + 100
    )
    let costDenied = acquireModelCall(
      costCompleted,
      "cost-2",
      dailyReportedCostLimitMicros: 10_000,
      nowMillis: globalBudgetNow + 200
    )

    XCTAssertFalse(dailyDenied.granted)
    XCTAssertEqual(dailyDenied.denial, .dailyLimit)
    XCTAssertEqual(dailyDenied.nextEligibleAtMillis, globalBudgetNow + GlobalModelCallBudgetPolicy.windowMillis)
    XCTAssertTrue(afterWindow.granted)
    XCTAssertEqual(afterWindow.state.dispatches.count, 1)
    XCTAssertFalse(tokenDenied.granted)
    XCTAssertEqual(tokenDenied.denial, .tokenLimit)
    XCTAssertTrue(oversized.granted)
    XCTAssertFalse(oversizedFollowUp.granted)
    XCTAssertEqual(oversizedFollowUp.denial, .tokenLimit)
    XCTAssertFalse(costDenied.granted)
    XCTAssertEqual(costDenied.denial, .reportedCostLimit)
    XCTAssertEqual(costDenied.nextEligibleAtMillis, globalBudgetNow + GlobalModelCallBudgetPolicy.windowMillis)
  }

  func testGlobalModelCallBudgetCompletionCancellationAndAvailability() {
    let acquired = acquireModelCall(
      GlobalModelCallBudgetState(),
      "call-1",
      resourceId: "cloud-model:primary",
      estimatedInputTokens: 120
    )
    let completed = GlobalModelCallBudgetPolicy.complete(
      state: acquired.state,
      leaseId: acquired.leaseId,
      inputTokens: 180,
      outputTokens: 45,
      reportedCostMicros: 2_500,
      responseText: "done",
      nowMillis: globalBudgetNow + 500
    )
    let estimatedAcquired = acquireModelCall(GlobalModelCallBudgetState(), "call-2", estimatedInputTokens: 80)
    let estimated = GlobalModelCallBudgetPolicy.complete(
      state: estimatedAcquired.state,
      leaseId: estimatedAcquired.leaseId,
      inputTokens: 0,
      outputTokens: 0,
      reportedCostMicros: 0,
      responseText: "A useful answer",
      nowMillis: globalBudgetNow + 500
    )
    let cancelledFirst = acquireModelCall(GlobalModelCallBudgetState(), "cancel-1", dailyLimit: 1)
    let cancelled = GlobalModelCallBudgetPolicy.cancel(
      state: cancelledFirst.state,
      leaseId: cancelledFirst.leaseId,
      nowMillis: globalBudgetNow + 100
    )
    let afterCancel = acquireModelCall(cancelled, "cancel-2", dailyLimit: 1, nowMillis: globalBudgetNow + 100)
    let busy = GlobalModelCallBudgetPolicy.availability(
      state: acquired.state,
      dailyLimit: 48,
      concurrencyLimit: 1,
      nowMillis: globalBudgetNow + 100
    )

    let dispatch = completed.dispatches.first
    XCTAssertEqual(dispatch?.inputTokens, 180)
    XCTAssertEqual(dispatch?.outputTokens, 45)
    XCTAssertEqual(dispatch?.totalTokens, 225)
    XCTAssertEqual(dispatch?.reportedCostMicros, 2_500)
    XCTAssertEqual(dispatch?.usageEstimated, false)
    XCTAssertEqual(dispatch?.completedAtMillis, globalBudgetNow + 500)
    XCTAssertTrue(completed.activeLeases.isEmpty)
    XCTAssertEqual(estimated.dispatches.first?.inputTokens, 80)
    XCTAssertTrue((estimated.dispatches.first?.outputTokens ?? 0) > 0)
    XCTAssertEqual(estimated.dispatches.first?.usageEstimated, true)
    XCTAssertTrue(afterCancel.granted)
    XCTAssertEqual(afterCancel.state.dispatches.count, 1)
    XCTAssertFalse(busy.granted)
    XCTAssertEqual(busy.denial, .concurrencyLimit)
    XCTAssertEqual(busy.state.dispatches.count, 1)
  }

  func testGlobalModelCallBudgetResourceUsageSnapshotAndSaturation() {
    let first = acquireModelCall(GlobalModelCallBudgetState(), "call-1", resourceId: "model-a")
    let firstDone = GlobalModelCallBudgetPolicy.complete(
      state: first.state,
      leaseId: first.leaseId,
      inputTokens: 100,
      outputTokens: 20,
      reportedCostMicros: 1_000,
      responseText: "a",
      nowMillis: globalBudgetNow + 1
    )
    let second = acquireModelCall(firstDone, "call-2", resourceId: "model-a", nowMillis: globalBudgetNow + 2)
    let secondDone = GlobalModelCallBudgetPolicy.complete(
      state: second.state,
      leaseId: second.leaseId,
      inputTokens: 200,
      outputTokens: 40,
      reportedCostMicros: 3_000,
      responseText: "b",
      nowMillis: globalBudgetNow + 3
    )
    let third = acquireModelCall(secondDone, "call-3", resourceId: "model-b", nowMillis: globalBudgetNow + 4)
    let usage = GlobalModelCallBudgetPolicy.resourceUsage(
      dispatches: third.state.dispatches,
      resourceId: "model-a"
    )
    let saturated = GlobalModelCallBudgetPolicy.totalTokens([
      GlobalModelCallDispatch(leaseId: "a", kind: .cognition, startedAtMillis: globalBudgetNow, inputTokens: Int64.max),
      GlobalModelCallDispatch(leaseId: "b", kind: .cognition, startedAtMillis: globalBudgetNow + 1, outputTokens: Int64.max)
    ])
    let snapshot = GlobalModelCallBudgetPolicy.snapshot(
      state: third.state,
      dailyLimit: 999,
      concurrencyLimit: 99,
      nowMillis: globalBudgetNow + 5,
      dailyTokenLimit: 999_999_999,
      dailyReportedCostLimitMicros: 999_999_999
    )

    XCTAssertEqual(usage.dispatches, 2)
    XCTAssertEqual(usage.averageInputTokens, 150)
    XCTAssertEqual(usage.averageOutputTokens, 30)
    XCTAssertEqual(usage.averageTotalTokens, 180)
    XCTAssertEqual(usage.averageReportedCostMicros, 2_000)
    XCTAssertEqual(saturated, Int64.max)
    XCTAssertEqual(snapshot.dailyLimit, GlobalModelCallBudgetPolicy.maxDailyLimit)
    XCTAssertEqual(snapshot.concurrencyLimit, GlobalModelCallBudgetPolicy.maxConcurrencyLimit)
    XCTAssertEqual(snapshot.dailyTokenLimit, GlobalModelCallBudgetPolicy.maxDailyTokenLimit)
    XCTAssertEqual(snapshot.dailyReportedCostLimitMicros, GlobalModelCallBudgetPolicy.maxDailyReportedCostLimitMicros)
    XCTAssertEqual(snapshot.dispatchesByKind[GlobalModelCallKind.cognition.rawValue] ?? 0, 3)
    XCTAssertEqual(snapshot.totalTokensInWindow, 360)
    XCTAssertEqual(snapshot.reportedCostMicrosInWindow, 4_000)
  }

  func testGlobalModelCallBudgetModelsUseAndroidWireNames() throws {
    let state = try JSONDecoder.galaxySSI.decode(
      GlobalModelCallBudgetState.self,
      from: Data(
        #"""
        {
          "dispatches": [
            {
              "lease_id": "lease-1",
              "kind": "RESEARCH_EVIDENCE",
              "started_at_millis": 1000,
              "resource_id": "model-a",
              "input_tokens": 10,
              "output_tokens": 20,
              "reported_cost_micros": 30,
              "usage_estimated": false,
              "completed_at_millis": 1200
            }
          ],
          "active_leases": [
            {
              "id": "lease-2",
              "kind": "PLAN_REVIEW",
              "owner_key": "review",
              "started_at_millis": 1000,
              "expires_at_millis": 2000
            }
          ]
        }
        """#.utf8
      )
    )
    let fallbackKind = try JSONDecoder.galaxySSI.decode(
      GlobalModelCallKind.self,
      from: Data(#""future""#.utf8)
    )
    let fallbackDenial = try JSONDecoder.galaxySSI.decode(
      GlobalModelCallBudgetDenial.self,
      from: Data(#""future""#.utf8)
    )
    let decision = GlobalModelCallBudgetDecision(
      granted: false,
      state: state,
      denial: .dailyLimit,
      nextEligibleAtMillis: 9_999
    )
    let encodedDecision = String(decoding: try JSONEncoder.galaxySSI.encode(decision), as: UTF8.self)
    let encodedSnapshot = String(decoding: try JSONEncoder.galaxySSI.encode(
      GlobalModelCallBudgetPolicy.snapshot(
        state: state,
        dailyLimit: 48,
        concurrencyLimit: 3,
        nowMillis: 1_500
      )
    ), as: UTF8.self)

    XCTAssertEqual(state.dispatches.first?.kind, .researchEvidence)
    XCTAssertEqual(state.activeLeases.first?.kind, .planReview)
    XCTAssertEqual(fallbackKind, .cognition)
    XCTAssertEqual(fallbackDenial, .dailyLimit)
    XCTAssertTrue(encodedDecision.contains(#""next_eligible_at_millis":9999"#))
    XCTAssertTrue(encodedDecision.contains(#""active_leases""#))
    XCTAssertTrue(encodedSnapshot.contains(#""dispatches_by_kind""#))
    XCTAssertEqual(
      GlobalModelCallBudgetPolicy.leaseId(kind: .cognition, ownerKey: "Call 1"),
      GlobalModelCallBudgetPolicy.leaseId(kind: .cognition, ownerKey: " call   1 ")
    )
  }
  private var globalBudgetNow: Int64 { 1_000_000 }
  private var globalBudgetLeaseMillis: Int64 { 60_000 }

  private func acquireModelCall(
    _ state: GlobalModelCallBudgetState,
    _ ownerKey: String,
    kind: GlobalModelCallKind = .cognition,
    dailyLimit: Int = 48,
    concurrencyLimit: Int = 3,
    nowMillis: Int64? = nil,
    resourceId: String = "",
    estimatedInputTokens: Int64 = 0,
    dailyTokenLimit: Int64 = GlobalModelCallBudgetPolicy.maxDailyTokenLimit,
    dailyReportedCostLimitMicros: Int64 = 0
  ) -> GlobalModelCallBudgetDecision {
    GlobalModelCallBudgetPolicy.acquire(
      state: state,
      leaseId: GlobalModelCallBudgetPolicy.leaseId(kind: kind, ownerKey: ownerKey),
      kind: kind,
      ownerKey: ownerKey,
      leaseMillis: globalBudgetLeaseMillis,
      dailyLimit: dailyLimit,
      concurrencyLimit: concurrencyLimit,
      nowMillis: nowMillis ?? globalBudgetNow,
      resourceId: resourceId,
      estimatedInputTokens: estimatedInputTokens,
      dailyTokenLimit: dailyTokenLimit,
      dailyReportedCostLimitMicros: dailyReportedCostLimitMicros
    )
  }

}
