import XCTest
@testable import GalaxySSI

final class GlobalIntelligenceAcquisitionTests: XCTestCase {
  func testResearchPlanCarriesExecutableQueriesAndEvidenceRequirements() {
    let plan = GlobalResearchPlanBuilder.create(task: task(.deepResearch), nowMillis: now)

    XCTAssertEqual(plan.depth, .deepResearch)
    XCTAssertTrue(plan.units.allSatisfy { $0.queryCandidates.count == 3 })
    XCTAssertTrue(plan.units.allSatisfy { $0.minimumIndependentSources >= 1 })
    XCTAssertTrue(plan.units.allSatisfy { $0.freshnessWindowMillis > 0 })
    let primary = plan.units.first { $0.purpose == .primaryEvidence }
    let primaryQueries = primary?.queryCandidates ?? []
    XCTAssertTrue(primary?.requiredSourceKinds.contains(.official) == true)
    XCTAssertTrue(primaryQueries.contains { $0.contains("official documentation") })
  }

  func testContinuousMonitorCarriesPreviousBaselineIntoNextCycle() {
    var monitor = task(.continuousMonitor)
    monitor.result = "Runtime version 12.4 remains the supported baseline."
    monitor.evidenceUris = ["https://developer.android.com/releases/12.4?utm_source=old"]
    monitor.lastCompletedAtMillis = now - dayMillis
    monitor.researchPlan = GlobalResearchPlan(createdAtMillis: now)

    let baseline = GlobalContinuousMonitorPolicy.baselineBlock(task: monitor)

    XCTAssertTrue(baseline.contains("Previous monitoring baseline"))
    XCTAssertTrue(baseline.contains("Runtime version 12.4"))
    XCTAssertTrue(baseline.contains("https://developer.android.com/releases/12.4"))
    XCTAssertFalse(baseline.contains("utm_source"))
    XCTAssertTrue(baseline.contains("MATERIAL_CHANGE"))
    XCTAssertEqual(GlobalContinuousMonitorPolicy.contextCutoffMillis(task: monitor), now)
  }

  func testContinuousMonitorKeepsComparisonContractWhenBaselineIsLong() {
    var monitor = task(.continuousMonitor)
    monitor.result = String(repeating: "A", count: 5_000)
    monitor.lastCompletedAtMillis = now

    let baseline = GlobalContinuousMonitorPolicy.baselineBlock(task: monitor, maximumCharacters: 800)

    XCTAssertTrue(baseline.contains("new citation or rewording alone is not a material change"))
    XCTAssertTrue(baseline.contains("MATERIAL_CHANGE"))
    XCTAssertLessThanOrEqual(baseline.count, 800)
  }

  func testOneShotResearchDoesNotReceiveMonitoringBaseline() {
    var research = task(.deepResearch)
    research.result = "Previous result"

    XCTAssertEqual(GlobalContinuousMonitorPolicy.baselineBlock(task: research), "")
  }

  func testQualityGateCreatesTargetedFollowUpEvidenceUnits() {
    let researchTask = task(.deepResearch)
    let initial = GlobalResearchPlanBuilder.create(task: researchTask, nowMillis: now)
    let completed = GlobalResearchPlan(
      id: initial.id,
      depth: initial.depth,
      phase: initial.phase,
      units: initial.units.enumerated().map { index, unit in
        if index == 0 {
          return completedUnit(
            unit,
            result: evidence(
              "A community report claims the runtime behavior changed for packaged libraries.",
              "https://reddit.com/r/androiddev/comments/example",
              "2026-07-01"
            )
          )
        }
        return failedUnit(unit)
      },
      qualityExpansionCount: initial.qualityExpansionCount,
      createdAtMillis: initial.createdAtMillis,
      updatedAtMillis: initial.updatedAtMillis
    )
    let ledger = GlobalEvidenceEvaluator.build(plan: completed, nowMillis: now)

    let expanded = GlobalResearchPlanBuilder.closeCollection(
      task: researchTask,
      plan: completed,
      ledger: ledger,
      nowMillis: now + 1
    )

    XCTAssertEqual(expanded.phase, .collecting)
    XCTAssertEqual(expanded.qualityExpansionCount, 1)
    XCTAssertFalse(expanded.pendingUnits().isEmpty)
    XCTAssertTrue(expanded.pendingUnits().contains { $0.purpose == .primaryEvidence })
    XCTAssertTrue(expanded.pendingUnits().contains { $0.purpose == .corroboration })
    XCTAssertTrue(expanded.pendingUnits().allSatisfy { !$0.queryCandidates.isEmpty })
  }

  func testQualityExpansionHasBoundedFallbackToSynthesis() {
    let researchTask = task(.deepResearch)
    let initial = GlobalResearchPlanBuilder.create(task: researchTask, nowMillis: now)
    let completed = GlobalResearchPlan(
      id: initial.id,
      depth: initial.depth,
      phase: initial.phase,
      units: initial.units.enumerated().map { index, unit in
        if index == 0 {
          return completedUnit(
            unit,
            result: evidence(
              "A single report describes a possible runtime compatibility change.",
              "https://example.com/runtime-report",
              "2026-07-01"
            )
          )
        }
        return failedUnit(unit)
      },
      qualityExpansionCount: 2,
      createdAtMillis: initial.createdAtMillis,
      updatedAtMillis: initial.updatedAtMillis
    )
    let ledger = GlobalEvidenceEvaluator.build(plan: completed, nowMillis: now)

    let closed = GlobalResearchPlanBuilder.closeCollection(
      task: researchTask,
      plan: completed,
      ledger: ledger,
      nowMillis: now + 1
    )

    XCTAssertEqual(closed.phase, .synthesisPending)
    XCTAssertEqual(closed.units.count, completed.units.count)
    XCTAssertFalse(ledger.verified)
  }

  func testStaleEvidenceUnitsRecoverOrFailAndParallelismIsBounded() {
    let researchTask = task(.deepResearch)
    let initial = GlobalResearchPlanBuilder.create(task: researchTask, nowMillis: now)
    let units = initial.units.enumerated().map { index, unit -> GlobalResearchUnit in
      GlobalResearchUnit(
        id: unit.id,
        purpose: unit.purpose,
        question: unit.question,
        sourceFocus: unit.sourceFocus,
        queryCandidates: unit.queryCandidates,
        minimumIndependentSources: unit.minimumIndependentSources,
        requiredSourceKinds: unit.requiredSourceKinds,
        freshnessWindowMillis: unit.freshnessWindowMillis,
        status: .running,
        resourceId: "resource-\(index)",
        attemptedResourceIds: [],
        sourceMessageId: 900 + Int64(index),
        attemptCount: index == 0 ? 1 : 3,
        leaseExpiresAtMillis: now - 1
      )
    }
    let stalePlan = GlobalResearchPlan(
      id: initial.id,
      depth: initial.depth,
      phase: .collecting,
      units: units,
      createdAtMillis: initial.createdAtMillis,
      updatedAtMillis: initial.updatedAtMillis
    )

    let recovered = GlobalResearchPlanBuilder.recoverStale(plan: stalePlan, nowMillis: now)

    XCTAssertEqual(recovered.units[0].status, .pending)
    XCTAssertEqual(recovered.units[1].status, .failed)
    XCTAssertEqual(recovered.units[0].sourceMessageId, 0)
    XCTAssertEqual(recovered.phase, .collecting)
    XCTAssertEqual(GlobalResearchPlanBuilder.parallelism(depth: .quickFact, resourceCount: 3), 1)
    XCTAssertEqual(GlobalResearchPlanBuilder.parallelism(depth: .continuousMonitor, resourceCount: 3), 2)
    XCTAssertEqual(GlobalResearchPlanBuilder.parallelism(depth: .deepResearch, resourceCount: 3), 3)
    XCTAssertEqual(GlobalResearchPlanBuilder.parallelism(depth: .deepResearch, resourceCount: 0), 0)
  }

  private func completedUnit(_ unit: GlobalResearchUnit, result: String) -> GlobalResearchUnit {
    GlobalResearchUnit(
      id: unit.id,
      purpose: unit.purpose,
      question: unit.question,
      sourceFocus: unit.sourceFocus,
      queryCandidates: unit.queryCandidates,
      minimumIndependentSources: unit.minimumIndependentSources,
      requiredSourceKinds: unit.requiredSourceKinds,
      freshnessWindowMillis: unit.freshnessWindowMillis,
      status: .completed,
      result: result,
      evidenceUris: GlobalEvidenceEvaluator.extractUrls(result),
      completedAtMillis: now
    )
  }

  private func failedUnit(_ unit: GlobalResearchUnit) -> GlobalResearchUnit {
    GlobalResearchUnit(
      id: unit.id,
      purpose: unit.purpose,
      question: unit.question,
      sourceFocus: unit.sourceFocus,
      queryCandidates: unit.queryCandidates,
      minimumIndependentSources: unit.minimumIndependentSources,
      requiredSourceKinds: unit.requiredSourceKinds,
      freshnessWindowMillis: unit.freshnessWindowMillis,
      status: .failed
    )
  }

  private func task(_ depth: GlobalResearchDepth) -> GlobalResearchTask {
    GlobalResearchTask(
      id: "research-\(depth.rawValue.lowercased())",
      sourceEventId: "event-1",
      sourceConversationId: "conversation-1",
      topic: "Runtime compatibility",
      question: "Assess current Android runtime compatibility requirements",
      depth: depth,
      preferredSources: ["official", "primary", "repository"],
      createdAtMillis: now,
      updatedAtMillis: now
    )
  }

  private func evidence(_ claim: String, _ url: String, _ date: String) -> String {
    "CLAIM: \(claim) | SOURCE: \(url) | DATE: \(date)"
  }

  private var now: Int64 { Self.nowMillis }
  private let dayMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let nowMillis = millis(year: 2026, month: 7, day: 20)

  private static func millis(year: Int, month: Int, day: Int) -> Int64 {
    var calendar = Calendar(identifier: .gregorian)
    if let utc = TimeZone(secondsFromGMT: 0) {
      calendar.timeZone = utc
    }
    let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    return Int64(date.timeIntervalSince1970 * 1_000)
  }
}
