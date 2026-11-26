import XCTest
@testable import GalaxySSI

final class AgentRoutingHealthSnapshotTests: XCTestCase {
  private func registration(_ id: String, cloud: Bool = false) -> AgentRegistration {
    AgentRegistration(agentId: id, installationId: "installation-\(id)", deviceId: "device-\(id)",
      providerId: cloud ? "cloud-provider" : "provider-\(id)", displayName: id,
      kind: cloud ? .model : .agent, location: cloud ? .cloud : .trustedDesktop,
      runtimeFailureDomain: "runtime-\(id)")
  }

  func testCaptureReadsRealLedgerWithoutLeasingOrClearingCircuit() {
    let ledger = InMemoryAgentProviderHealthLedger()
    let selected = registration("desktop:codex")
    ledger.recordFailure(registration: selected, operation: "start_run", kind: .transportCrash,
      latencyMillis: 1200, nowMillis: 1000)
    let before = ledger.snapshots()
    let snapshot = AgentRoutingHealthSnapshot.capture(registrations: [selected], ledger: ledger, nowMillis: 2000)
    XCTAssertFalse(snapshot.allows(targetId: selected.agentId))
    XCTAssertEqual(ledger.snapshots(), before)
    XCTAssertEqual(snapshot.resources[selected.agentId]?.target?.failures, 1)
    XCTAssertEqual(snapshot.resources[selected.agentId]?.targetLatencyMillis, 1200)
  }

  func testExactRegistrationScopeDoesNotBorrowAnotherDesktopCircuit() {
    let first = registration("desktop-a:codex")
    let second = registration("desktop-b:codex")
    let failure = AgentProviderHealthSnapshot(scopeId: first.runtimeHealthScope(), failures: 1,
      consecutiveFailures: 1, lastFailureAtMillis: 1000, circuitOpenUntilMillis: 9000,
      lastFailureKind: .transportCrash, lastOperation: "start_run")
    let snapshot = AgentRoutingHealthSnapshot(registrations: [first, second], snapshots: [failure], nowMillis: 2000)
    XCTAssertFalse(snapshot.allows(targetId: first.agentId))
    XCTAssertTrue(snapshot.allows(targetId: second.agentId))
    XCTAssertNil(snapshot.resources[second.agentId]?.target)
    var duplicate = first
    duplicate.runtimeFailureDomain = second.runtimeFailureDomain
    XCTAssertFalse(AgentRoutingHealthSnapshot(registrations: [first, duplicate], snapshots: [failure], nowMillis: 2000)
      .allows(targetId: first.agentId))
  }

  func testReadinessProjectionSharesLedgerPolicyAndRetainsProbeLeaseAuthority() {
    let ledger = InMemoryAgentProviderHealthLedger()
    var selected = registration("desktop:codex")
    ledger.recordFailure(registration: selected, operation: "start_run", kind: .transportCrash,
      latencyMillis: 100, nowMillis: 1000)
    selected.lastHeartbeatMillis = 2000
    let before = ledger.snapshots()
    XCTAssertTrue(AgentRoutingHealthSnapshot.capture(registrations: [selected], ledger: ledger, nowMillis: 3000)
      .allows(targetId: selected.agentId))
    XCTAssertEqual(ledger.snapshots(), before)
    ledger.observeAvailability(registration: selected, nowMillis: 3000)
    XCTAssertEqual(ledger.snapshot(registration: selected).circuitState(nowMillis: 3000), .halfOpen)
    XCTAssertTrue(ledger.acquire(registration: selected, operation: "start_run", nowMillis: 3000).probe)
    XCTAssertFalse(AgentRoutingHealthSnapshot.capture(registrations: [selected], ledger: ledger, nowMillis: 3001)
      .allows(targetId: selected.agentId))
    XCTAssertTrue(AgentRoutingHealthSnapshot.capture(registrations: [selected], ledger: ledger, nowMillis: 33_000)
      .allows(targetId: selected.agentId))
  }

  func testReadinessCannotClearAuthorizationFailureOrStaleHeartbeat() {
    var selected = registration("desktop:codex")
    let authorization = AgentProviderHealthSnapshot(scopeId: selected.runtimeHealthScope(), failures: 1,
      consecutiveFailures: 1, lastFailureAtMillis: 1000, circuitOpenUntilMillis: 9000,
      lastFailureKind: .authorization, lastOperation: "start_run")
    selected.lastHeartbeatMillis = 2000
    XCTAssertNil(AgentProviderAvailabilityPolicy.observingReadiness(authorization, registration: selected, nowMillis: 3000))
    var transport = authorization
    transport.lastFailureKind = .transportCrash
    selected.lastHeartbeatMillis = 1000
    XCTAssertNil(AgentProviderAvailabilityPolicy.observingReadiness(transport, registration: selected, nowMillis: 3000))
    selected.lastHeartbeatMillis = 64_000
    XCTAssertNil(AgentProviderAvailabilityPolicy.observingReadiness(transport, registration: selected, nowMillis: 3000))
  }

  func testCloudCircuitUsesExistingConfigurationRecoveryWithoutWriting() throws {
    let selected = registration("cloud-model:test", cloud: true)
    let scope = try XCTUnwrap(selected.cloudProviderHealthScopeId)
    let provider = AgentProviderHealthSnapshot(scopeId: scope, failures: 1, consecutiveFailures: 1,
      lastFailureAtMillis: 1000, circuitOpenUntilMillis: 9000, lastFailureKind: .authorization)
    let runtime = AgentProviderHealthSnapshot(scopeId: selected.runtimeHealthScope(), successes: 1,
      lastSuccessAtMillis: 2000, lastOperation: "configuration")
    XCTAssertFalse(AgentRoutingHealthSnapshot(registrations: [selected], snapshots: [provider], nowMillis: 3000)
      .allows(targetId: selected.agentId))
    XCTAssertTrue(AgentRoutingHealthSnapshot(registrations: [selected], snapshots: [runtime, provider], nowMillis: 3000)
      .allows(targetId: selected.agentId))
    XCTAssertEqual(provider.consecutiveFailures, 1)
    XCTAssertEqual(provider.circuitOpenUntilMillis, 9000)
  }

  func testUnknownHealthAddsNoFabricatedSamplesAndObservedLatencyReplacesProfileEstimate() {
    let target = AgentCallableTarget(id: "cloud-model:test", title: "Cloud", kind: .model,
      status: .available, capabilities: [.chat])
    var resource = AgentResourceCatalog.build(targets: [target], tools: [])[0]
    var profile = ProviderProfileCatalog.fromTarget(target)
    profile.performance = ProviderPerformanceProfile(attempts: 1, ewmaLatencyMs: 12_000)
    resource.providerProfile = profile
    let requirements = AgentTaskRequirements()
    let environment = AgentRuntimeEnvironment()
    let baseline = AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements, environment: environment)
    let empty = AgentRoutingResourceHealth(target: nil, domain: nil, selectable: true)
    XCTAssertEqual(AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements,
      environment: environment, health: empty), baseline)
    let observed = AgentRoutingResourceHealth(target: AgentProviderHealthSnapshot(scopeId: "target:cloud-model:test",
      successes: 1, averageLatencyMillis: 1200), domain: nil, selectable: true)
    let ranked = AgentProviderResourceRanking.candidate(resource: resource, requirements: requirements,
      environment: environment, health: observed)
    XCTAssertEqual(ranked.score - baseline.score, 190)
    XCTAssertTrue(ranked.reasons.contains("provider_latency_penalty:0"))
    XCTAssertTrue(ranked.reasons.contains("observed_adapter_latency_ms:1200"))
    XCTAssertNil(AgentRoutingResourceHealth.reliability(nil))
    XCTAssertNil(AgentRoutingResourceHealth.reliability(AgentProviderHealthSnapshot(scopeId: "empty")))
    XCTAssertEqual(AgentRoutingResourceHealth.reliability(AgentProviderHealthSnapshot(scopeId: "large",
      successes: Int.max, failures: Int.max)), 50)
  }

  func testActualSelectorRejectsCircuitOpenPreferredAndAllBlockedCandidates() throws {
    let first = registration("desktop:codex")
    let second = registration("cloud-model:test", cloud: true)
    let targets = [first, second].map {
      AgentCallableTarget(id: $0.agentId, title: $0.displayName, kind: $0.kind,
        status: .available, capabilities: [.chat])
    }
    let failure = AgentProviderHealthSnapshot(scopeId: first.runtimeHealthScope(), failures: 1,
      consecutiveFailures: 1, lastFailureAtMillis: 1000, circuitOpenUntilMillis: 9000,
      lastFailureKind: .transportCrash, lastOperation: "start_run")
    let health = AgentRoutingHealthSnapshot(registrations: [first, second], snapshots: [failure], nowMillis: 2000)
    let selection = try XCTUnwrap(AgentConnectorRouteSelector.select(targets: targets, decision: nil,
      preferredTargetId: first.agentId, goal: "Explain a note", preserveHealthyPrimary: true, routingHealth: health))
    XCTAssertEqual(selection.target.id, second.agentId)
    XCTAssertFalse(selection.decision?.orderedTargetIds.contains(first.agentId) == true)
    XCTAssertNil(AgentConnectorRouteSelector.select(targets: [targets[0]], decision: nil,
      preferredTargetId: first.agentId, preserveHealthyPrimary: true, routingHealth: health))
  }
}
