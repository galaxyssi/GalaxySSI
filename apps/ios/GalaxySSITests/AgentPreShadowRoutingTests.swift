import XCTest
@testable import GalaxySSI

final class AgentPreShadowRoutingTests: XCTestCase {
  private func candidate(_ id: String, score: Int, location: AgentResourceLocation = .cloud,
                         domain: String = "") -> AgentResourceCandidate {
    AgentResourceCandidate(resource: AgentResourceDescriptor(id: "target:\(id)", title: id,
      type: location == .cloud ? .cloudModel : .remoteAgent, location: location, status: .available,
      capabilities: [.chat], cost: .free, latency: .fast, quality: .standard, supportsTools: true,
      targetId: id, failureDomain: domain), score: score)
  }

  private func decision(_ candidates: [AgentResourceCandidate]) -> AgentRoutingDecision {
    AgentRoutingDecision(requirements: AgentTaskRequirements(), primary: candidates.first,
      fallbacks: Array(candidates.dropFirst()), environment: .init(networkAvailable: true, appMemoryBytes: 123),
      catalog: candidates.map(\.resource))
  }

  func testCalibrationRunsOncePerExactEligibleCandidateBeforeTruncation() {
    let candidates = (0..<10).map { candidate("node-\($0)", score: 1000 - $0) }
    let input = decision(candidates + [candidates[0], candidate("tool", score: 1_000_000)])
    var seen: [String] = []
    let result = AgentProviderResourceRanking.prepareForQuality(decision: input,
      eligibleTargetIds: Set(candidates.map(\.resource.targetId)), preferredTargetId: "") { id in
      seen.append(id)
      return id == "node-9" ? 100 : 0
    }
    XCTAssertEqual(seen, candidates.map(\.resource.targetId))
    XCTAssertEqual(result.primary?.resource.targetId, "node-9")
    XCTAssertEqual(result.primary?.score, 1091)
    XCTAssertEqual(result.fallbacks.count, 6)
    XCTAssertEqual(result.catalog, input.catalog)
    XCTAssertEqual(result.environment, input.environment)
    XCTAssertEqual(result.taskBudget, input.taskBudget)
    XCTAssertFalse(result.orderedTargetIds.contains("tool"))
  }

  func testDomainDiversityIsAppliedBeforeQualityCandidateExposure() {
    let primary = candidate("primary", score: 10000, location: .trustedDesktop, domain: "desktop-a")
    let shared = (0..<7).map { candidate("shared-\($0)", score: 9999 - $0, location: .trustedDesktop, domain: "desktop-a") }
    let cloud = candidate("cloud", score: 100)
    let phone = candidate("phone", score: 90, location: .phone)
    let other = candidate("other", score: 200, location: .trustedDesktop, domain: "desktop-b")
    let all = [primary] + shared + [cloud, phone, other]
    let prepared = AgentProviderResourceRanking.prepareForQuality(decision: decision(all),
      eligibleTargetIds: Set(all.map(\.resource.targetId)), preferredTargetId: "") { _ in 0 }
    XCTAssertEqual(prepared.orderedTargetIds, ["primary", "cloud", "phone", "other", "shared-0", "shared-1", "shared-2"])
    let excludedPromotion = AgentShadowRoutingRecommendation(scenarioId: "scope", taskClass: .general,
      actualResourceId: "primary", recommendedResourceId: "shared-6", scores: [], shouldAutoSwitch: true, confidence: 1)
    XCTAssertEqual(AgentQualityAwareRoutingPolicy.apply(recommendation: excludedPromotion, to: prepared), prepared)
  }

  func testQualityPromotionRetainsTheAlreadyBoundedOrderAndEvidence() {
    let candidates = (0..<10).map { candidate("node-\($0)", score: 1000 - $0) }
    let prepared = AgentProviderResourceRanking.prepareForQuality(decision: decision(candidates),
      eligibleTargetIds: Set(candidates.map(\.resource.targetId)), preferredTargetId: "") { _ in 5 }
    let recommendation = AgentShadowRoutingRecommendation(scenarioId: "scope", taskClass: .general,
      actualResourceId: "node-0", recommendedResourceId: "node-4", scores: [], shouldAutoSwitch: true, confidence: 1)
    let promoted = AgentQualityAwareRoutingPolicy.apply(recommendation: recommendation, to: prepared)
    XCTAssertEqual(promoted.orderedTargetIds, ["node-4", "node-0", "node-1", "node-2", "node-3", "node-5", "node-6"])
    XCTAssertTrue(promoted.primary?.reasons.contains("routing_self_calibration_adjustment:5") == true)
    XCTAssertTrue(promoted.primary?.reasons.contains("quality_eval_promoted") == true)
    XCTAssertEqual(promoted.catalog, prepared.catalog)
  }

  func testAdmittedPreferenceIsKeptButCatalogCannotFabricateCandidates() {
    let candidates = (0..<10).map { candidate("node-\($0)", score: 1000 - $0) }
    var input = decision(candidates)
    input.catalog.append(candidate("catalog-only", score: 99999).resource)
    let preferred = AgentProviderResourceRanking.prepareForQuality(decision: input,
      eligibleTargetIds: Set(candidates.map(\.resource.targetId)), preferredTargetId: "node-9") { _ in 0 }
    XCTAssertEqual(preferred.primary?.resource.targetId, "node-9")
    XCTAssertEqual(preferred.fallbacks.count, 6)
    let denied = AgentProviderResourceRanking.prepareForQuality(decision: input,
      eligibleTargetIds: ["catalog-only"], preferredTargetId: "catalog-only") { _ in XCTFail("Not an admitted candidate"); return 0 }
    XCTAssertNil(denied.primary)
    XCTAssertTrue(denied.fallbacks.isEmpty)
    XCTAssertEqual(denied.catalog, input.catalog)
  }

  func testStableTiesExactInstallationsAndOverflowSafeCalibration() {
    let candidates = [candidate("desktop-a:codex", score: 100), candidate("desktop-b:codex", score: 100)]
    let result = AgentProviderResourceRanking.prepareForQuality(decision: decision(candidates),
      eligibleTargetIds: Set(candidates.map(\.resource.targetId)), preferredTargetId: "") { _ in 0 }
    XCTAssertEqual(result.orderedTargetIds, ["desktop-a:codex", "desktop-b:codex"])
    let extremes = [candidate("high", score: Int.max - 1), candidate("low", score: Int.min + 1)]
    let safe = AgentProviderResourceRanking.prepareForQuality(decision: decision(extremes),
      eligibleTargetIds: ["high", "low"], preferredTargetId: "") { $0 == "high" ? 120 : -180 }
    XCTAssertEqual(safe.primary?.score, Int.max)
    XCTAssertEqual(safe.fallbacks.first?.score, Int.min)
  }

  func testRepeatedPreparationReplacesCalibrationRatherThanCompoundingIt() {
    let original = decision([candidate("high", score: Int.max - 1), candidate("low", score: Int.min + 1)])
    let first = AgentProviderResourceRanking.prepareForQuality(decision: original,
      eligibleTargetIds: ["high", "low"], preferredTargetId: "") { $0 == "high" ? 120 : -180 }
    let second = AgentProviderResourceRanking.prepareForQuality(decision: first,
      eligibleTargetIds: ["high", "low"], preferredTargetId: "") { _ in 0 }
    XCTAssertEqual(second.primary?.score, Int.max - 1)
    XCTAssertEqual(second.fallbacks.first?.score, Int.min + 1)
    XCTAssertEqual(second.primary?.reasons.filter { $0.hasPrefix("routing_self_calibration_baseline:") }.count, 1)
    XCTAssertEqual(second.primary?.reasons.filter { $0.hasPrefix("routing_self_calibration_adjustment:") },
      ["routing_self_calibration_adjustment:0"])
  }

  func testShadowScoringAcceptsClampedExtremeBaselineWithoutIntegerAddition() throws {
    let extremes = [candidate("high", score: Int.max), candidate("low", score: Int.min)]
    var settings = AgentEvalOpsSettings()
    settings.shadowRoutingEnabled = true
    settings.automaticQualityRoutingEnabled = false
    let shadow = try XCTUnwrap(AgentQualityAwareRoutingPolicy.recommend(goal: "", requirements: AgentTaskRequirements(),
      candidates: extremes, samples: [], actualResourceId: "high", settings: settings))
    XCTAssertEqual(shadow.scores.map(\.score), [1, 0])
    XCTAssertFalse(shadow.shouldAutoSwitch)
  }

  func testActualSelectorCapsBeforeQualityWithoutCatalogResurrection() throws {
    let candidates = (0..<10).map { candidate("node-\($0)", score: 1_000_000 - $0 * 10_000) }
    let targets = candidates.map { AgentCallableTarget(id: $0.resource.targetId, title: $0.resource.title,
      kind: .model, status: .available, capabilities: [.chat]) }
    var input = decision(candidates)
    input.catalog.append(candidate("catalog-only", score: 2_000_000).resource)
    let extra = AgentCallableTarget(id: "catalog-only", title: "Not admitted", kind: .model, status: .available, capabilities: [.chat])
    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: targets + [extra], decision: input,
      preferredTargetId: extra.id))
    XCTAssertEqual(selected.target.id, "node-0")
    XCTAssertEqual(selected.decision?.orderedTargetIds, (0..<7).map { "node-\($0)" })
    XCTAssertTrue(selected.decision?.primary?.reasons.contains { $0.hasPrefix("routing_self_calibration_adjustment:") } == true)
    XCTAssertFalse(selected.decision?.orderedTargetIds.contains("catalog-only") == true)
    let preferred = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: targets, decision: input,
      preferredTargetId: "node-9"))
    XCTAssertEqual(preferred.target.id, "node-9")
    XCTAssertEqual(preferred.decision?.fallbacks.count, 6)
  }

  func testHealthyStablePrimaryStillSkipsAlternateCalibrationAndShadow() throws {
    let primary = AgentCallableTarget(id: "stable", title: "Stable", kind: .model, status: .available, capabilities: [.chat])
    let alternate = AgentCallableTarget(id: "alternate", title: "Alternate", kind: .model, status: .available, capabilities: [.chat])
    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [primary, alternate], decision: nil,
      preferredTargetId: primary.id, goal: "Explain a note", preserveHealthyPrimary: true))
    XCTAssertEqual(selected.target.id, primary.id)
    XCTAssertEqual(selected.decision?.catalog.map(\.targetId), [primary.id])
    XCTAssertTrue(selected.decision?.fallbacks.isEmpty == true)
    XCTAssertFalse(selected.decision?.primary?.reasons.contains { $0.hasPrefix("routing_self_calibration_adjustment:") } == true)
  }

  func testDisconnectedAdmittedReasoningTargetRetainsRealRecoveryDiagnostic() throws {
    var resource = candidate("recovering", score: 1000)
    resource.resource.status = .disconnected
    let target = AgentCallableTarget(id: "recovering", title: "Recovering", kind: .agent,
      status: .disconnected, capabilities: [.chat])
    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [target], decision: decision([resource])))
    XCTAssertEqual(selected.target.id, target.id)
    XCTAssertTrue(selected.decision?.primary?.reasons.contains("recoverable_connector_status") == true)
    XCTAssertEqual(selected.decision?.catalog, [resource.resource])
  }
}
