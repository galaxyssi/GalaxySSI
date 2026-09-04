import Foundation
import XCTest
@testable import GalaxySSI

@MainActor
final class AgentModelPlannerContactResolverTests: XCTestCase {
  func testAgentModelPlannerContactResolverPrefersConfiguredReadyContact() throws {
    let store = makeStore(secrets: InMemorySecretStore())
    _ = try store.addCloudModelContact(
      displayName: "GPT Planner",
      provider: "OpenAI",
      modelId: "gpt-planner",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiKey: "sk-live-openai",
      apiStyle: .openAICompatible
    )
    _ = try store.addCloudModelContact(
      displayName: "Claude Planner",
      provider: "Anthropic",
      modelId: "claude-planner",
      endpoint: "https://api.anthropic.com/v1/messages",
      apiKey: "sk-live-anthropic",
      apiStyle: .anthropic
    )

    let settings = AgentModelPlannerSettings(enabled: true, cloudContactId: " cloud:anthropic ")
    let resolver = AgentModelPlannerContactResolver(store: store)
    let resolution = resolver.resolve(settings: settings)
    let provider = resolver.makePlanningProvider(settings: settings)
    let planner = resolver.makePlanner(settings: settings)
    let toolLoopProvider = try resolver.makeToolLoopPlanningProvider(
      settings: settings,
      toolRegistry: AgentNativeToolRegistry()
    )
    let toolLoopPlanner = try resolver.makeToolLoopPlanner(
      settings: settings,
      toolRegistry: AgentNativeToolRegistry()
    )

    XCTAssertEqual(resolution?.contact.id, "cloud:anthropic")
    XCTAssertEqual(resolution?.contactId, "cloud:anthropic")
    XCTAssertEqual(resolution?.selectedModel.modelId, "claude-planner")
    XCTAssertEqual(resolution?.modelProfile, "claude-planner")
    XCTAssertEqual(provider?.contact.id, "cloud:anthropic")
    XCTAssertEqual(planner?.modelProfile, "claude-planner")
    XCTAssertNotNil(toolLoopProvider)
    XCTAssertEqual(toolLoopPlanner?.modelProfile, "claude-planner")
  }

  func testAgentModelPlannerContactResolverFallsBackToFirstReadyStoredContact() {
    let notReady = makeCloudContact(
      id: "cloud:not-ready",
      provider: "OpenAI",
      modelId: "gpt-offline",
      setupStatus: "needs_setup"
    )
    let readyLaterAlphabetically = makeCloudContact(
      id: "cloud:zeta",
      provider: "Zeta",
      modelId: "zeta-planner",
      endpoint: "https://zeta.example.test/v1/chat/completions",
      keychainAccount: "zeta"
    )
    let readyEarlierAlphabetically = makeCloudContact(
      id: "cloud:alpha",
      provider: "Alpha",
      modelId: "alpha-planner",
      endpoint: "https://alpha.example.test/v1/chat/completions",
      keychainAccount: "alpha"
    )

    let preferredNotReady = AgentModelPlannerContactResolver.resolve(
      preferredContactId: "cloud:not-ready",
      contacts: [notReady, readyLaterAlphabetically, readyEarlierAlphabetically],
      apiKey: { _ in "sk-live-key" }
    )
    let preferredMissing = AgentModelPlannerContactResolver.resolve(
      preferredContactId: "cloud:missing",
      contacts: [readyLaterAlphabetically, readyEarlierAlphabetically],
      apiKey: { _ in "sk-live-key" }
    )

    XCTAssertEqual(preferredNotReady?.contact.id, "cloud:zeta")
    XCTAssertEqual(preferredMissing?.contact.id, "cloud:zeta")
  }

  func testAgentModelPlannerContactResolverRejectsUnsafeCandidates() {
    var missingModel = makeCloudContact(id: "cloud:missing-model")
    missingModel.cloudModels = []

    XCTAssertNil(resolve(makeCloudContact(id: "cloud:deleted", deleted: true)))
    XCTAssertNil(resolve(makeCloudContact(id: "cloud:link", deliveryMode: .link)))
    XCTAssertNil(resolve(makeCloudContact(id: "cloud:needs-setup", setupStatus: "needs_setup")))
    XCTAssertNil(resolve(makeCloudContact(id: "cloud:blank-provider", provider: "")))
    XCTAssertNil(resolve(makeCloudContact(id: "cloud:blank-model", modelId: "")))
    XCTAssertNil(resolve(makeCloudContact(
      id: "cloud:example",
      endpoint: "https://api.example.com/v1/chat/completions"
    )))
    XCTAssertNil(resolve(makeCloudContact(id: "cloud:placeholder-key"), apiKey: "your-api-key"))
    XCTAssertNil(resolve(makeCloudContact(id: "cloud:smoke-key"), apiKey: "sk-galaxyssi-smoke-key"))
    XCTAssertNil(resolve(missingModel))
  }

  func testAgentModelPlannerContactResolverUsesSelectedModelAndNormalizesInvalidSelection() {
    var contact = makeCloudContact(
      id: "cloud:openai",
      provider: "OpenAI",
      modelId: "model-a",
      keychainAccount: "model-a"
    )
    contact.cloudModels.append(CloudModelConfig(
      id: "openai:model-b",
      displayName: "Model B",
      provider: "OpenAI",
      modelId: "model-b",
      endpoint: "https://api.openai.com/v1/chat/completions",
      apiStyle: .openAICompatible,
      keychainAccount: "model-b",
      updatedAt: Date(timeIntervalSince1970: 1_800_000_001)
    ))
    contact.selectedCloudModelId = "model-b"

    let selected = AgentModelPlannerContactResolver.resolve(
      contacts: [contact],
      apiKey: { model in model.keychainAccount == "model-b" ? "sk-live-b" : nil }
    )
    contact.selectedCloudModelId = "missing-model"
    let normalized = AgentModelPlannerContactResolver.resolve(
      contacts: [contact],
      apiKey: { model in model.keychainAccount == "model-a" ? "sk-live-a" : nil }
    )

    XCTAssertEqual(selected?.selectedModel.modelId, "model-b")
    XCTAssertEqual(selected?.contact.selectedCloudModelId, "model-b")
    XCTAssertEqual(normalized?.selectedModel.modelId, "model-a")
    XCTAssertEqual(normalized?.contact.selectedCloudModelId, "model-a")
  }

  private func resolve(
    _ contact: GalaxySSIContact,
    apiKey: String? = "sk-live-key"
  ) -> AgentModelPlannerContactResolution? {
    AgentModelPlannerContactResolver.resolve(contacts: [contact], apiKey: { _ in apiKey })
  }

  private func makeStore(secrets: GalaxySSISecretStore) -> GalaxySSIStore {
    let suite = "AgentModelPlannerContactResolverTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSIStore(defaults: defaults, secrets: secrets)
  }

  private func makeCloudContact(
    id: String = "cloud:openai",
    provider: String = "OpenAI",
    modelId: String = "planner-model",
    endpoint: String = "https://api.openai.com/v1/chat/completions",
    keychainAccount: String = "planner-model",
    setupStatus: String = "ready",
    deliveryMode: GalaxySSIDeliveryMode = .cloudAPI,
    deleted: Bool = false
  ) -> GalaxySSIContact {
    let model = CloudModelConfig(
      id: "\(id):\(modelId)",
      displayName: modelId.isEmpty ? "Planner" : modelId,
      provider: provider,
      modelId: modelId,
      endpoint: endpoint,
      apiStyle: .openAICompatible,
      keychainAccount: keychainAccount,
      updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    return GalaxySSIContact(
      id: id,
      galaxySSIId: id,
      name: provider.isEmpty ? id : provider,
      displayName: provider.isEmpty ? id : provider,
      type: "agent",
      agentKind: "cloud-api",
      deliveryMode: deliveryMode,
      trustState: .verified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: setupStatus,
      setupDetail: "Mobile direct cloud model API",
      cloudProvider: provider,
      cloudModels: [model],
      selectedCloudModelId: modelId,
      deleted: deleted,
      createdAt: Date(timeIntervalSince1970: 1_800_000_000),
      updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }
}
