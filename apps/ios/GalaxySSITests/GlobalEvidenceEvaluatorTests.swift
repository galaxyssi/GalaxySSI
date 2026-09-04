import XCTest
@testable import GalaxySSI

final class GlobalEvidenceEvaluatorTests: XCTestCase {
  func testPublisherSubdomainsCountAsOneIndependentAuthority() {
    let plan = completedPlan(
      depth: .deepResearch,
      results: [
        evidence(
          "The platform documents a current page-size compatibility requirement.",
          "https://developer.android.com/guide/practices/page-sizes?utm_source=test",
          "2026-07-01"
        ),
        evidence(
          "The platform documents a current page-size compatibility requirement.",
          "https://source.android.com/docs/core/architecture/page-sizes",
          "2026-07-02"
        )
      ]
    )

    let ledger = GlobalEvidenceEvaluator.build(plan: plan, nowMillis: now)

    XCTAssertEqual(ledger.independentSourceCount, 1)
    XCTAssertEqual(Set(ledger.sources.map(\.authority)), Set(["android.com"]))
    XCTAssertTrue(ledger.qualityIssues.contains(.insufficientSourceDiversity))
    XCTAssertFalse(ledger.verified)
  }

  func testTrackingParametersCannotCreateDuplicateEvidence() {
    let first = GlobalEvidenceEvaluator.canonicalUri("https://example.com/report?id=7&utm_source=a#summary")
    let second = GlobalEvidenceEvaluator.canonicalUri("https://EXAMPLE.com/report?id=7&utm_medium=b")

    XCTAssertEqual(first, "https://example.com/report?id=7")
    XCTAssertEqual(first, second)
  }

  func testContinuousMonitoringRequiresDatedFreshEvidence() {
    let plan = completedPlan(
      depth: .continuousMonitor,
      results: [
        evidence(
          "The current release changes the supported runtime compatibility contract.",
          "https://developer.android.com/about/versions/16/release-notes",
          "2026-07-10"
        ),
        evidence(
          "The current release changes the supported runtime compatibility contract.",
          "https://reuters.com/technology/runtime-release-analysis",
          "2024-01-01"
        )
      ]
    )

    let ledger = GlobalEvidenceEvaluator.build(plan: plan, nowMillis: now)

    XCTAssertEqual(ledger.freshSourceCount, 1)
    XCTAssertEqual(ledger.staleSourceCount, 1)
    XCTAssertTrue(ledger.sources.contains { $0.publishedAtMillis > 0 })
    XCTAssertTrue(ledger.verified)
  }

  func testStaleMonitoringEvidenceFailsTheFreshnessGate() {
    let plan = completedPlan(
      depth: .continuousMonitor,
      results: [
        evidence(
          "The documented release changes the supported runtime compatibility contract.",
          "https://developer.android.com/about/versions/16/release-notes",
          "2024-01-01"
        ),
        evidence(
          "The documented release changes the supported runtime compatibility contract.",
          "https://reuters.com/technology/runtime-release-analysis",
          "2024-02-01"
        )
      ]
    )

    let ledger = GlobalEvidenceEvaluator.build(plan: plan, nowMillis: now)

    XCTAssertEqual(ledger.freshSourceCount, 0)
    XCTAssertEqual(ledger.staleSourceCount, 2)
    XCTAssertTrue(ledger.qualityIssues.contains(.freshEvidenceMissing))
    XCTAssertFalse(ledger.verified)
  }

  func testRepeatedCitationOfOneUrlIsNotIndependentCorroboration() {
    let sharedUrl = "https://developer.android.com/guide/practices/page-sizes"
    let plan = completedPlan(
      depth: .deepResearch,
      results: [
        evidence("The compatibility requirement applies to packaged native libraries.", sharedUrl, "2026-06-01"),
        evidence("The compatibility requirement applies to packaged native libraries.", sharedUrl, "2026-06-01")
      ]
    )

    let ledger = GlobalEvidenceEvaluator.build(plan: plan, nowMillis: now)

    XCTAssertEqual(ledger.independentSourceCount, 1)
    XCTAssertEqual(ledger.corroboratedClaimCount, 0)
    XCTAssertTrue(ledger.qualityIssues.contains(.claimsNotCorroborated))
    XCTAssertFalse(ledger.verified)
  }

  func testContradictoryClaimsRemainExplicitlyContested() {
    let plan = completedPlan(
      depth: .deepResearch,
      results: [
        evidence(
          "The runtime supports sixteen kilobyte pages on every current device model.",
          "https://developer.android.com/guide/practices/page-sizes",
          "2026-07-01"
        ),
        evidence(
          "The runtime does not support sixteen kilobyte pages on every current device model.",
          "https://github.com/android/ndk/issues/2000",
          "2026-07-02"
        )
      ]
    )

    let ledger = GlobalEvidenceEvaluator.build(plan: plan, nowMillis: now)

    XCTAssertGreaterThanOrEqual(ledger.contestedClaimCount, 2)
    XCTAssertTrue(ledger.qualityIssues.contains(.unresolvedContradictions))
    XCTAssertFalse(ledger.verified)
  }

  func testUnrelatedPublishersRemainIndependent() {
    XCTAssertNotEqual(
      GlobalEvidenceEvaluator.sourceAuthority("https://developer.android.com/guide"),
      GlobalEvidenceEvaluator.sourceAuthority("https://github.com/android/ndk")
    )
  }

  private func completedPlan(depth: GlobalResearchDepth, results: [String]) -> GlobalResearchPlan {
    let initial = GlobalResearchPlanBuilder.create(task: task(depth), nowMillis: now)
    let resultCount = results.count
    let units = initial.units.enumerated().map { index, unit -> GlobalResearchUnit in
      if index < resultCount {
        return GlobalResearchUnit(
          id: unit.id,
          purpose: unit.purpose,
          question: unit.question,
          sourceFocus: unit.sourceFocus,
          queryCandidates: unit.queryCandidates,
          minimumIndependentSources: unit.minimumIndependentSources,
          requiredSourceKinds: unit.requiredSourceKinds,
          freshnessWindowMillis: unit.freshnessWindowMillis,
          status: .completed,
          result: results[index],
          evidenceUris: GlobalEvidenceEvaluator.extractUrls(results[index]),
          completedAtMillis: now
        )
      }
      return GlobalResearchUnit(
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
    return GlobalResearchPlan(
      id: initial.id,
      depth: initial.depth,
      phase: initial.phase,
      units: units,
      qualityExpansionCount: initial.qualityExpansionCount,
      createdAtMillis: initial.createdAtMillis,
      updatedAtMillis: initial.updatedAtMillis
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
