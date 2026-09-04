import XCTest
@testable import GalaxySSI

final class ScannedAgentConversationPolicyTests: XCTestCase {
  func testOnlyDesktopAgentContactsOpenAgentConversations() {
    let desktopAgent = contact()

    XCTAssertTrue(ScannedAgentConversationPolicy.opensAgentConversation(desktopAgent))
    XCTAssertFalse(ScannedAgentConversationPolicy.opensAgentConversation(contact(type: "device")))
    XCTAssertFalse(ScannedAgentConversationPolicy.opensAgentConversation(contact(deliveryMode: .cloudAPI)))
    XCTAssertFalse(ScannedAgentConversationPolicy.opensAgentConversation(contact(deleted: true)))
  }

  func testResolvesConcreteDesktopTargetBeforeGenericAgentTarget() throws {
    let desktopAgent = contact()
    let generic = target(id: "claude", title: "Claude Code")
    let concrete = target(id: desktopAgent.id, title: "Claude Code - Desktop")

    XCTAssertEqual(
      ScannedAgentConversationPolicy.resolveTarget(
        contact: desktopAgent,
        targets: [generic, concrete]
      ),
      concrete
    )
    XCTAssertEqual(
      ScannedAgentConversationPolicy.contact(
        for: "desktop-test:claude",
        contacts: [desktopAgent]
      ),
      desktopAgent
    )
  }

  func testPreselectionUsesAdvertisedDefaultsAndSupportedReasoning() {
    let target = target(
      id: "desktop-test:codex",
      title: "Codex - Desktop",
      defaultModelId: "gpt-default",
      reasoningEfforts: [.medium, .high]
    )

    let selection = ScannedAgentConversationPolicy.selection(
      for: target,
      remembered: AgentTargetConfiguration(modelId: "missing", reasoningEffort: .xhigh)
    )

    XCTAssertEqual(selection.mode, .manual)
    XCTAssertEqual(selection.targetId, target.id)
    XCTAssertEqual(selection.modelId, "gpt-default")
    XCTAssertEqual(selection.displayName, target.title)
    XCTAssertEqual(selection.reasoningEffort, .medium)
  }

  func testSessionOnlySelectionDoesNotReplaceGlobalDefault() throws {
    let suiteName = "ScannedAgentConversationPolicyTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    AgentModelSelectionSettings.selectManual(
      for: "existing",
      targetId: "desktop:codex",
      modelId: "gpt-default",
      displayName: "Codex",
      defaults: defaults
    )

    AgentModelSelectionSettings.selectManual(
      for: "scanned",
      targetId: "desktop:claude",
      modelId: "best",
      displayName: "Claude Code",
      rememberAsDefault: false,
      defaults: defaults
    )
    AgentModelSelectionSettings.inheritDefault(for: "next", defaults: defaults)

    XCTAssertEqual(
      AgentModelSelectionSettings.selection(for: "scanned", defaults: defaults).targetId,
      "desktop:claude"
    )
    XCTAssertEqual(
      AgentModelSelectionSettings.selection(for: "next", defaults: defaults).targetId,
      "desktop:codex"
    )
  }

  private func contact(
    type: String = "agent",
    deliveryMode: GalaxySSIDeliveryMode = .pcConnector,
    deleted: Bool = false
  ) -> GalaxySSIContact {
    GalaxySSIContact(
      id: "desktop-test:claude",
      galaxySSIId: "desktop-test:claude",
      name: "Claude Code",
      displayName: "Claude Code - Desktop",
      type: type,
      agentKind: "desktop-agent",
      deliveryMode: deliveryMode,
      trustState: .verified,
      desktopId: "desktop-test",
      desktopName: "Desktop",
      identityFingerprint: "fingerprint",
      setupStatus: "ready",
      setupDetail: "",
      cloudProvider: "",
      cloudModels: [],
      selectedCloudModelId: "",
      agentId: "claude",
      deleted: deleted,
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1)
    )
  }

  private func target(
    id: String,
    title: String,
    defaultModelId: String = "best",
    reasoningEfforts: [AgentModelReasoningEffort] = []
  ) -> AgentCallableTarget {
    AgentCallableTarget(
      id: id,
      title: title,
      kind: .agent,
      status: .available,
      capabilities: [.chat, .code],
      invocationProfile: AgentInvocationProfile(
        defaultModelId: defaultModelId,
        models: [AgentModelOption(id: defaultModelId, displayName: defaultModelId)],
        reasoningEfforts: reasoningEfforts
      )
    )
  }
}
