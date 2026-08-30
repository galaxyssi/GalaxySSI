import XCTest
@testable import SignalASI

final class AgentIdentityPresentationTests: XCTestCase {
  func testPreservesOperationalMetadataAndUsesDeterministicCapabilityPriority() {
    let presentation = AgentIdentityPresenter.present(
      registration(
        agentId: "desktop:codex",
        name: "Codex",
        capabilities: [.chat, .toolUse, .code, .reasoning],
        cost: .low,
        latency: .fast
      )
    )

    XCTAssertEqual(presentation.avatarStyle, .codex)
    XCTAssertEqual(presentation.capabilities, [
      .code,
      .reasoning,
      .toolUse,
      .chat
    ])
    XCTAssertEqual(presentation.cost, .low)
    XCTAssertEqual(presentation.latency, .fast)
  }

  func testReportsBusyWhenTheEndpointHasNoRemainingCapacity() {
    let presentation = AgentIdentityPresenter.present(
      registration(
        agentId: "hermes",
        name: "Hermes",
        capabilities: [.research],
        activeRuns: 2,
        maxParallelRuns: 2
      )
    )

    XCTAssertEqual(presentation.avatarStyle, .hermes)
    XCTAssertEqual(presentation.status, .busy)
  }

  func testDistinguishesLocalAndCloudModelAvatars() {
    let local = AgentIdentityPresenter.present(
      registration(
        agentId: "local-llm",
        name: "Local LLM",
        capabilities: [.localInference],
        kind: .model,
        location: .phone
      )
    )
    let cloud = AgentIdentityPresenter.present(
      registration(
        agentId: "cloud:openai",
        name: "OpenAI",
        capabilities: [.chat],
        kind: .model,
        location: .cloud
      )
    )

    XCTAssertEqual(local.avatarStyle, .localModel)
    XCTAssertEqual(cloud.avatarStyle, .cloudModel)
  }

  func testGeminiAgentUsesGeminiProviderAsset() {
    XCTAssertEqual(
      SignalASIAgentAvatarAssetCatalog.assetName(for: ["desktop_t14:gemini", "Gemini CLI"]),
      "CloudProviderGemini"
    )
  }

  func testUnknownContactUsesStableGeneratedIdenticon() {
    XCTAssertTrue(
      SignalASIContactAvatarPolicy.usesGeneratedIdenticon(
        for: contact(id: "unknown-contact", name: "New contact")
      )
    )
  }

  func testKnownAgentsKeepDedicatedAvatars() {
    XCTAssertFalse(
      SignalASIContactAvatarPolicy.usesGeneratedIdenticon(
        for: contact(id: "desktop_t14:codex", name: "Codex")
      )
    )
    XCTAssertFalse(
      SignalASIContactAvatarPolicy.usesGeneratedIdenticon(
        for: contact(id: "desktop_t14:claude", name: "Claude Code")
      )
    )
  }

  private func contact(id: String, name: String) -> SignalASIContact {
    SignalASIContact(
      id: id,
      signalASIId: id,
      name: name,
      displayName: name,
      type: "agent",
      agentKind: "",
      deliveryMode: .link,
      trustState: .verified,
      desktopId: "",
      desktopName: "",
      identityFingerprint: "",
      setupStatus: "ready",
      setupDetail: "",
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      deleted: false,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private func registration(
    agentId: String,
    name: String,
    capabilities: Set<AgentCapability>,
    kind: AgentConnectorKind = .agent,
    location: AgentResourceLocation = .trustedDesktop,
    cost: AgentResourceCost = .free,
    latency: AgentResourceLatency = .normal,
    activeRuns: Int = 0,
    maxParallelRuns: Int = 1
  ) -> AgentRegistration {
    AgentRegistration(
      agentId: agentId,
      installationId: "installation",
      deviceId: "device",
      providerId: agentId,
      displayName: name,
      kind: kind,
      location: location,
      status: .online,
      capabilities: capabilities,
      protocol: AgentProtocolRange(preferred: "1", minimum: "1", maximum: "1"),
      connectionKind: .signalasiLink,
      cost: cost,
      latency: latency,
      activeRuns: activeRuns,
      maxParallelRuns: maxParallelRuns
    )
  }
}
