import XCTest
@testable import GalaxySSI

@MainActor
final class AgentProviderHealthRecoveryTests: XCTestCase {
  func testNewerConfigurationRecoversOlderProviderCircuit() {
    let ledger = InMemoryAgentProviderHealthLedger()
    let registration = deepSeekRegistration()
    ledger.recordFailure(
      registration: registration,
      operation: "start_run",
      kind: .authorization,
      latencyMillis: 10,
      nowMillis: 8_000
    )
    ledger.markAvailable(scopeIds: [registration.runtimeHealthScope()], nowMillis: 9_000)

    let projected = ledger.availabilitySnapshot(registration: registration, nowMillis: 10_000)

    XCTAssertEqual(projected.circuitState(nowMillis: 10_000), .closed)
    XCTAssertEqual(
      ledger.snapshot(scopeId: registration.cloudProviderHealthScopeId!).circuitState(nowMillis: 10_000),
      .closed
    )
    XCTAssertTrue(ledger.acquire(registration: registration, operation: "connect", nowMillis: 10_000).allowed)
  }

  func testStaleOrFailedTargetDoesNotBypassProviderCircuit() {
    let provider = AgentProviderHealthSnapshot(
      scopeId: "domain:cloud:deepseek",
      consecutiveFailures: 1,
      lastFailureAtMillis: 8_000,
      circuitOpenUntilMillis: 20_000
    )
    let stale = AgentProviderHealthSnapshot(
      scopeId: "cloud-model:DeepSeek:deepseek",
      lastSuccessAtMillis: 7_000
    )
    let failed = AgentProviderHealthSnapshot(
      scopeId: "cloud-model:DeepSeek:deepseek",
      consecutiveFailures: 1,
      lastSuccessAtMillis: 9_000
    )

    XCTAssertFalse(CloudProviderHealthRecoveryPolicy.shouldRecoverProviderCircuit(
      target: stale, provider: provider, nowMillis: 10_000
    ))
    XCTAssertFalse(CloudProviderHealthRecoveryPolicy.shouldRecoverProviderCircuit(
      target: failed, provider: provider, nowMillis: 10_000
    ))
  }

  func testExplicitConfigurationClearsRuntimeTargetAndProviderScopes() {
    let ledger = InMemoryAgentProviderHealthLedger()
    let registration = deepSeekRegistration()
    ledger.recordFailure(
      registration: registration,
      operation: "start_run",
      kind: .authorization,
      latencyMillis: 10,
      nowMillis: 8_000
    )

    ledger.markConfigurationAvailable(registration: registration, nowMillis: 9_000)

    for scopeId in registration.healthTrackingScopeIds() {
      let snapshot = ledger.snapshot(scopeId: scopeId)
      XCTAssertEqual(snapshot.circuitOpenUntilMillis, 0)
      XCTAssertEqual(snapshot.consecutiveFailures, 0)
      XCTAssertEqual(snapshot.lastSuccessAtMillis, 9_000)
      XCTAssertEqual(snapshot.lastOperation, "configuration")
    }
  }

  func testSelectingConfiguredCloudModelClearsPersistedHealth() throws {
    let suiteName = "AgentProviderHealthRecoveryTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = GalaxySSIStore(defaults: defaults, secrets: InMemorySecretStore())
    let contact = try store.addCloudModelContact(
      displayName: "DeepSeek Chat",
      provider: "DeepSeek",
      modelId: "deepseek-chat",
      endpoint: "https://api.deepseek.com/v1/chat/completions",
      apiKey: "sk-live-test-credential",
      apiStyle: .openAICompatible
    )
    let target = try XCTUnwrap(AgentCallableTargetCatalog.build(
      contacts: [contact],
      apiKey: { store.apiKey(for: $0) },
      activeLocalProfiles: []
    ).first)
    let registration = AgentMentionCandidatePolicy.registration(for: target)
    let ledger = UserDefaultsAgentProviderHealthLedger(defaults: defaults)
    ledger.recordFailure(
      registration: registration,
      operation: "start_run",
      kind: .authorization,
      latencyMillis: 10,
      nowMillis: AgentControlPlaneClock.nowMillis()
    )
    XCTAssertEqual(ledger.snapshot(registration: registration).consecutiveFailures, 1)

    XCTAssertTrue(store.setSelectedCloudModel(contactId: contact.id, modelId: "deepseek-chat"))

    for scopeId in registration.healthTrackingScopeIds() {
      XCTAssertEqual(ledger.snapshot(scopeId: scopeId).consecutiveFailures, 0)
      XCTAssertEqual(ledger.snapshot(scopeId: scopeId).circuitOpenUntilMillis, 0)
    }
  }

  private func deepSeekRegistration() -> AgentRegistration {
    AgentRegistration(
      agentId: "cloud:deepseek",
      installationId: "cloud-model:DeepSeek",
      deviceId: "cloud-model:DeepSeek",
      providerId: "deepseek",
      displayName: "DeepSeek",
      kind: .model,
      location: .cloud,
      status: .online,
      capabilities: [.chat, .reasoning],
      runtimeFailureDomain: "cloud-model:DeepSeek:deepseek",
      adapterType: "openai-model-api"
    )
  }
}
