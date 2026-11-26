import XCTest
@testable import GalaxySSI

final class AgentAutomaticRoutingContextTests: XCTestCase {
  private let online = AgentRuntimeEnvironment(networkAvailable: true, networkValidated: true)

  func testHealthyPrimaryCarriesRealContextWithoutAlternativeRanking() throws {
    let primary = target("desktop:codex"), alternative = target("cloud-model:alternative", kind: .model)
    let budget = AgentTaskBudget(profile: .adaptive, networkPolicy: .unmeteredOnly, allowCloud: false)
    let context = capture([primary, alternative], budget: budget, preferred: primary.id, preserve: true)
    XCTAssertEqual(context.targets.map(\.id), [primary.id])
    XCTAssertEqual(context.decision.primary?.resource.targetId, primary.id)
    XCTAssertTrue(context.decision.primary?.reasons.contains("stable_auto_primary") == true)
    XCTAssertTrue(context.decision.fallbacks.isEmpty)
    XCTAssertEqual(context.decision.taskBudget, budget)
    XCTAssertEqual(context.decision.environment, online)
    XCTAssertEqual(Set(context.decision.catalog.map(\.targetId)), Set([primary.id, alternative.id]))
    let selected = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: [primary, alternative],
      decision: context.decision, preferredTargetId: primary.id, goal: "Explain", preserveHealthyPrimary: true))
    XCTAssertEqual(selected.target, primary)
    XCTAssertEqual(selected.decision, context.decision)
  }

  func testFullPreferredPrimaryIsExcludedBeforeScoringAndCannotBeResurrected() {
    let busy = target("desktop:codex"), available = target("cloud-model:a", kind: .model)
    var registration = AgentMentionCandidatePolicy.registration(for: busy)
    registration.activeRuns = registration.maxParallelRuns
    let context = capture([busy, available], registrations: [registration], preferred: busy.id, preserve: true)
    XCTAssertEqual(context.targets.map(\.id), [available.id])
    XCTAssertEqual(context.decision.orderedTargetIds, [available.id])
    XCTAssertTrue(context.decision.catalog.contains { $0.targetId == busy.id })
    XCTAssertFalse(context.decision.primary?.reasons.contains("stable_auto_primary") == true)
  }

  func testExplicitPrivacyCloudAndNetworkRulesRemainAdmissionNotScoreBonuses() {
    let cloud = target("cloud-model:a", kind: .model)
    XCTAssertTrue(capture([cloud], requirements: AgentTaskRequirements(localOnly: true)).targets.isEmpty)
    XCTAssertTrue(capture([cloud], requirements: AgentTaskRequirements(dataSensitivity: .restricted)).targets.isEmpty)
    XCTAssertTrue(capture([cloud], budget: AgentTaskBudget(allowCloud: false)).targets.isEmpty)
    XCTAssertTrue(capture([cloud], budget: AgentTaskBudget(networkPolicy: .offlineOnly)).targets.isEmpty)
    let disabled = AgentAutomaticRoutingContext.capture(goal: "Explain", targets: [cloud], registrations: [],
      budget: .default, environment: online, connectorCallsAllowed: false)
    XCTAssertTrue(disabled.targets.isEmpty)
    let offline = AgentAutomaticRoutingContext.capture(goal: "Explain", targets: [cloud], registrations: [],
      budget: .default, environment: AgentRuntimeEnvironment(), connectorCallsAllowed: true)
    XCTAssertNil(offline.decision.primary)
  }

  func testLocalReasoningRemainsAvailableWithoutNetworkOrConnectorPermission() {
    let local = target("local-llm", kind: .model)
    let context = AgentAutomaticRoutingContext.capture(goal: "Explain", targets: [local],
      registrations: [AgentMentionCandidatePolicy.registration(for: local)],
      budget: AgentTaskBudget(networkPolicy: .offlineOnly, allowCloud: false, allowPaidProviders: false),
      environment: AgentRuntimeEnvironment(), connectorCallsAllowed: false,
      requirements: AgentTaskRequirements(localOnly: true, dataSensitivity: .restricted))
    XCTAssertEqual(context.targets.map(\.id), [local.id])
    XCTAssertEqual(context.decision.orderedTargetIds, [local.id])
    XCTAssertEqual(context.decision.primary?.resource.location, .phone)
  }

  func testCandidatesStayCompleteUntilExistingCalibrationAndFallbackBounds() {
    let targets = (0..<12).map { target("cloud-model:\($0)", kind: .model) }
    let context = capture(targets)
    XCTAssertEqual(context.targets.count, 12)
    XCTAssertEqual(context.decision.orderedTargetIds.count, 12)
    XCTAssertEqual(Set(context.decision.orderedTargetIds), Set(targets.map(\.id)))
    XCTAssertFalse(context.decision.primary?.reasons.contains("stable_auto_primary") == true)
  }

  func testNoRouteDecisionCannotFallBackToInformationalCatalogOrDevice() {
    let cloud = target("cloud-model:a", kind: .model)
    let device = AgentCallableTarget(id: "device", title: "Device", kind: .device, status: .available,
      capabilities: [.chat, .deviceControl])
    let context = capture([cloud, device], budget: AgentTaskBudget(allowCloud: false))
    XCTAssertTrue(context.targets.isEmpty)
    XCTAssertTrue(context.decision.orderedTargetIds.isEmpty)
    XCTAssertEqual(context.decision.catalog.count, 2)
    XCTAssertNil(AgentConnectorRouteSelector.select(targets: [cloud, device], decision: context.decision,
      preferredTargetId: cloud.id, goal: "Explain", preserveHealthyPrimary: true))
  }

  func testExactRegistrationAndActualHealthBoundTheDecision() {
    let cloud = target("cloud-model:a", kind: .model)
    var foreign = AgentMentionCandidatePolicy.registration(for: cloud)
    foreign.agentId = "another-installation"
    foreign.trust = .verifiedPaired
    XCTAssertTrue(capture([cloud], registrations: [foreign],
      requirements: AgentTaskRequirements(dataSensitivity: .restricted)).targets.isEmpty)
    let primary = target("desktop:codex")
    let registration = AgentMentionCandidatePolicy.registration(for: primary)
    let ledger = InMemoryAgentProviderHealthLedger()
    ledger.recordFailure(registration: registration, operation: "start_run", kind: .transportCrash,
      latencyMillis: 100, nowMillis: 1_000)
    let before = ledger.snapshots()
    let health = AgentRoutingHealthSnapshot.capture(registrations: [registration], ledger: ledger, nowMillis: 2_000)
    let context = AgentAutomaticRoutingContext.capture(goal: "Explain", targets: [primary], registrations: [registration],
      budget: .default, environment: online, connectorCallsAllowed: true, preferredTargetId: primary.id,
      preserveHealthyPrimary: true, health: health)
    XCTAssertNil(context.decision.primary)
    XCTAssertEqual(ledger.snapshots(), before)
  }

  func testTelemetryCountersDoNotRestoreRemovedHardLimits() {
    let cloud = target("cloud-model:a", kind: .model)
    let budget = AgentTaskBudget(maxCostMicros: 1, maxInputTokens: 1, maxOutputTokens: 1, maxMemoryBytes: 1)
    let context = capture([cloud], budget: budget, requirements: AgentTaskRequirements(estimatedInputTokens: 100_000))
    XCTAssertEqual(context.targets.map(\.id), [cloud.id])
    XCTAssertEqual(context.decision.taskBudget, budget)
  }

  private func target(_ id: String, kind: AgentConnectorKind = .agent) -> AgentCallableTarget {
    AgentCallableTarget(id: id, title: id, kind: kind, status: .available,
      capabilities: [.chat, .reasoning, .toolUse], failureDomain: id, adapterType: kind == .agent ? "desktop-agent" : "cloud-api")
  }

  private func capture(_ targets: [AgentCallableTarget], registrations: [AgentRegistration] = [],
    budget: AgentTaskBudget = .default, preferred: String = "", preserve: Bool = false,
    requirements: AgentTaskRequirements? = nil) -> AgentAutomaticRoutingContext {
    AgentAutomaticRoutingContext.capture(goal: "Explain", targets: targets, registrations: registrations,
      budget: budget, environment: online, connectorCallsAllowed: true, preferredTargetId: preferred,
      preserveHealthyPrimary: preserve, hasPairedDesktop: true, requirements: requirements)
  }
}
