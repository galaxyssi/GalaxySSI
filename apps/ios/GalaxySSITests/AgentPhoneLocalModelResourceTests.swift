import XCTest
@testable import GalaxySSI

final class AgentPhoneLocalModelResourceTests: XCTestCase {
  func testActualCatalogBindsTheReadyNativeModelAndConfiguredContext() throws {
    let model = try XCTUnwrap(LocalModelRuntimeCatalog.profiles().first { $0.supportsIOSRuntime })
    let targets = AgentCallableTargetCatalog.build(contacts: [], apiKey: { _ in nil }, activeLocalProfiles: [model], localModelReady: { _ in true })
    let target = try XCTUnwrap(targets.first { $0.id == "local-llm" })
    let profile = try XCTUnwrap(target.providerProfile)
    let resource = try XCTUnwrap(AgentResourceCatalog.build(targets: [target], tools: []).first)
    XCTAssertEqual(profile.modelId, model.id)
    XCTAssertEqual(profile.contextWindowTokens, min(LocalModelRuntimeSettings.contextTokens(), model.maximumContextTokens))
    XCTAssertEqual(profile.location, .phone)
    XCTAssertEqual(profile.trust, .phoneSystem)
    XCTAssertEqual(profile.pricing.tier, .free)
    XCTAssertEqual(resource.type, .onDeviceModel)
    XCTAssertEqual(resource.location, .phone)
    XCTAssertEqual(resource.status, .available)
    XCTAssertFalse(profile.supportsBackground)
  }

  func testOfflinePrivateAdmissionAndQueuedBudgetUsePhoneIdentity() throws {
    let target = native()
    let resource = try XCTUnwrap(AgentResourceCatalog.build(targets: [target], tools: []).first)
    let budget = AgentTaskBudget(networkPolicy: .offlineOnly, allowCloud: false, allowPaidProviders: false)
    let decision = AgentTaskBudgetPolicy.evaluate(budget: budget, usage: AgentTaskBudgetUsage(usageEstimated: true),
      environment: AgentTaskBudgetEnvironment(), networkRequired: resource.location != .phone,
      trustedNetworkTarget: [.phone, .trustedDesktop, .privateNetwork].contains(resource.location),
      cloudProvider: resource.location == .cloud, paidProvider: resource.cost != .free)
    XCTAssertTrue(decision.allowed)
    XCTAssertEqual(resource.trust, .phoneSystem)
    XCTAssertNil(AgentAutomaticRouteAdmission.rejectionReason(resource: resource, registration: nil,
      requirements: AgentTaskRequirements(localOnly: true, dataSensitivity: .restricted), budget: budget,
      environment: AgentTaskBudgetEnvironment(), connectorCallsAllowed: false))
  }

  func testUnreadyNativeModelDoesNotGainAvailabilityFromLocalClassification() throws {
    let model = try XCTUnwrap(LocalModelRuntimeCatalog.profiles().first { $0.supportsIOSRuntime })
    let targets = AgentCallableTargetCatalog.build(contacts: [], apiKey: { _ in nil }, activeLocalProfiles: [model], localModelReady: { _ in false })
    let target = try XCTUnwrap(targets.first)
    XCTAssertEqual(target.status, .needsSetup)
    XCTAssertFalse(target.providerProfile?.endpointConfigured == true)
    XCTAssertFalse(AgentConnectorRouteSelector.isDeliverable(target))
    XCTAssertTrue(AgentAutomaticRouteAdmission.targets(targets, registrations: [], requirements: AgentTaskRequirements(),
      budget: .default, environment: AgentTaskBudgetEnvironment(), connectorCallsAllowed: true).isEmpty)
  }

  func testRemoteLocalModelsRetainNetworkRequirements() throws {
    var remote = native()
    remote.adapterType = "ollama"
    let resource = try XCTUnwrap(AgentResourceCatalog.build(targets: [remote], tools: []).first)
    XCTAssertFalse(ProviderProfileCatalog.isPhoneLocalModel(remote))
    XCTAssertNotEqual(resource.location, .phone)
    let decision = AgentTaskBudgetPolicy.evaluate(budget: .default, usage: AgentTaskBudgetUsage(),
      environment: AgentTaskBudgetEnvironment(), networkRequired: resource.location != .phone)
    XCTAssertFalse(decision.allowed)
    XCTAssertEqual(decision.limit, .network)
    remote.id = "desktop:local-llm"
    remote.adapterType = "ios-local-model"
    XCTAssertFalse(ProviderProfileCatalog.isPhoneLocalModel(remote))
    XCTAssertNotEqual(AgentResourceCatalog.build(targets: [remote], tools: []).first?.location, .phone)
  }

  func testNameAndAdapterWithoutNativeKindAndCapabilityDoNotQualify() {
    var wrong = native()
    wrong.kind = .agent
    XCTAssertFalse(ProviderProfileCatalog.isPhoneLocalModel(wrong))
    wrong = native()
    wrong.capabilities.removeAll { $0 == .localInference }
    XCTAssertFalse(ProviderProfileCatalog.isPhoneLocalModel(wrong))
    XCTAssertNil(ProviderProfileCatalog.phoneLocalModelProfile(for: wrong))
  }

  func testExistingConflictingProfileIsNotRewrittenAsPhoneExecution() {
    var remote = native()
    remote.adapterType = "ollama"
    let remoteProfile = ProviderProfileCatalog.fromTarget(remote)
    var target = native()
    target.providerProfile = remoteProfile
    XCTAssertFalse(ProviderProfileCatalog.isPhoneLocalModel(target))
    XCTAssertEqual(ProviderProfileCatalog.fromTarget(target), remoteProfile)
    XCTAssertNotEqual(AgentResourceCatalog.build(targets: [target], tools: []).first?.location, .phone)
  }

  func testRegistrationCapacityAndRuntimeKeyAreRetained() throws {
    let legacy = native()
    var current = legacy
    current.providerProfile = try XCTUnwrap(ProviderProfileCatalog.phoneLocalModelProfile(for: current, modelId: "fixture"))
    let before = AgentMentionCandidatePolicy.registration(for: legacy)
    let after = AgentMentionCandidatePolicy.registration(for: current)
    XCTAssertEqual(AgentRuntimeIdentity.key(before), AgentRuntimeIdentity.key(after))
    XCTAssertEqual(before.providerId, after.providerId)
    XCTAssertEqual(before.maxParallelRuns, after.maxParallelRuns)
    XCTAssertEqual(after.location, .phone)
    XCTAssertEqual(after.trust, .phoneSystem)
    XCTAssertEqual(after.cost, .free)
    XCTAssertEqual(after.providerProfile?.modelId, "fixture")
  }

  func testNativeProfileRoundTripsWithoutInventingAnOutputLimit() throws {
    let profile = try XCTUnwrap(ProviderProfileCatalog.phoneLocalModelProfile(for: native(), modelId: "fixture", contextWindowTokens: 2_048))
    XCTAssertEqual(try JSONDecoder().decode(ProviderProfile.self, from: JSONEncoder().encode(profile)), profile)
    XCTAssertEqual(profile.maxOutputTokens, 0)
    XCTAssertEqual(profile.contextWindowTokens, 2_048)
    XCTAssertTrue(profile.credentialConfigured)
  }

  private func native() -> AgentCallableTarget {
    AgentCallableTarget(id: "local-llm", title: "Phone model", kind: .model, status: .available,
      capabilities: [.chat, .reasoning, .toolUse, .localInference], failureDomain: "local-model", adapterType: "ios-local-model")
  }
}
