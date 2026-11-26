import XCTest
@testable import GalaxySSI

final class AgentModelPickerPolicyTests: XCTestCase {
  func testActiveOlderModelStaysVisibleWithoutOpeningOtherOlderModels() {
    let codex = target("desktop:codex", ["gpt-6.2-astra", "gpt-6.2-sol", "gpt-6-astra", "gpt-5.6-sol"])
    let groups = AgentModelPickerPolicy.modelGroups(codex, selectedModelId: "gpt-6-astra")
    XCTAssertEqual(groups.visible.map(\.id), ["gpt-6.2-astra", "gpt-6.2-sol", "gpt-6-astra"])
    XCTAssertEqual(groups.folded.map(\.id), ["gpt-5.6-sol"])
  }

  func testOldOnlyCatalogRemainsVisibleAndUnknownNewIdsNeedNoAppUpdate() {
    let old = target("desktop:codex", ["gpt-6-astra", "gpt-5.6-sol"])
    let groups = AgentModelPickerPolicy.modelGroups(old, selectedModelId: "")
    XCTAssertEqual(groups.visible, old.invocationProfile.models)
    XCTAssertTrue(groups.folded.isEmpty)
    XCTAssertEqual(AgentModelPickerPolicy.modelGroups(target("desktop:codex", ["gpt-future", "gpt-6-astra"]),
      selectedModelId: "").visible.map(\.id), ["gpt-future"])
  }

  func testDifferentComputersKeepTheirOwnTargetsAndSelectedAgentSortsFirst() {
    let a = target("desktop_a:codex"), b = target("desktop_b:codex"), claude = target("desktop_a:claude")
    XCTAssertEqual(AgentModelPickerPolicy.desktopTargets([claude, a, target("codex"), b], selectedId: b.id).map(\.id),
      [b.id, a.id, claude.id])
    XCTAssertEqual(AgentModelPickerPolicy.desktopTargets([a, claude, b], selectedId: claude.id).map(\.id),
      [claude.id, a.id, b.id])
  }

  func testUnavailableAndDuplicateTargetsDoNotBecomeSelectable() {
    var unavailable = target("offline:codex")
    unavailable.status = .needsSetup
    let available = target("online:codex")
    XCTAssertEqual(AgentModelPickerPolicy.desktopTargets([unavailable, available, available], selectedId: unavailable.id).map(\.id), [available.id])
  }

  func testLegacyFoldingIsSpecificToAgentFamilyNotCloudOrOtherAgents() {
    let claude = target("desktop:claude", ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5"])
    XCTAssertEqual(AgentModelPickerPolicy.modelGroups(claude, selectedModelId: "claude-opus-5").folded.map(\.id), ["claude-sonnet-5"])
    var model = claude
    model.kind = .model
    XCTAssertTrue(AgentModelPickerPolicy.modelGroups(model, selectedModelId: "").folded.isEmpty)
    var other = claude
    other.id = "desktop:custom"
    XCTAssertTrue(AgentModelPickerPolicy.modelGroups(other, selectedModelId: "").folded.isEmpty)
  }

  func testRetiredModelsStayExcludedEvenIfManuallyAddedToProfile() {
    var codex = target("desktop:codex", ["gpt-future"])
    codex.invocationProfile.models.append(.init(id: "gpt-5.3-codex-spark"))
    let groups = AgentModelPickerPolicy.modelGroups(codex, selectedModelId: "gpt-5.3-codex-spark")
    XCTAssertFalse((groups.visible + groups.folded).contains { RetiredAgentModelPolicy.isRetired($0.id) })
  }

  func testAliasedOlderSelectionUsesTheMergedCanonicalInvocationProfile() {
    var claude = target("desktop:claude", ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5"])
    claude.invocationProfile.modelAliases = ["old-opus": "claude-opus-5"]
    let groups = AgentModelPickerPolicy.modelGroups(claude, selectedModelId: "old-opus")
    XCTAssertEqual(groups.visible.map(\.id), ["claude-opus-5-5", "claude-opus-5"])
    XCTAssertEqual(groups.folded.map(\.id), ["claude-sonnet-5"])
    XCTAssertEqual(claude.invocationProfile.canonicalModelId("old-opus"), "claude-opus-5")
  }

  func testSourceDefaultsFollowLocalCloudSelectedDesktopAndAvailableFallbacks() {
    XCTAssertEqual(AgentModelPickerPolicy.initialSource(selection: .init(), agents: [], hasCloud: false, hasLocal: false), .desktop)
    XCTAssertEqual(AgentModelPickerPolicy.initialSource(selection: .init(), agents: [], hasCloud: true, hasLocal: true), .cloud)
    XCTAssertEqual(AgentModelPickerPolicy.initialSource(selection: .init(), agents: [], hasCloud: false, hasLocal: true), .local)
    XCTAssertEqual(AgentModelPickerPolicy.initialSource(selection: .init(mode: .manual, targetId: "local-llm"),
      agents: [target("desktop:codex")], hasCloud: true, hasLocal: true), .local)
    XCTAssertEqual(AgentModelPickerPolicy.initialSource(selection: .init(mode: .manual, targetId: "cloud:model"),
      agents: [target("desktop:codex")], hasCloud: true, hasLocal: false), .cloud)
    XCTAssertEqual(AgentModelPickerPolicy.initialSource(selection: .init(mode: .manual, targetId: "offline:codex"),
      agents: [], hasCloud: true, hasLocal: true), .desktop)
  }

  func testPresentationLabelsDoNotChangeIdentifiersOrCatalogs() {
    let original = target("desktop:codex", ["gpt-6.2-astra"])
    XCTAssertEqual(AgentModelPickerPolicy.desktopLabel("Codex Agent \u{00B7} Desktop-T14").name, "Codex Agent")
    XCTAssertEqual(AgentModelPickerPolicy.desktopLabel("Codex Agent \u{00B7} Desktop-T14").device, "Desktop-T14")
    XCTAssertEqual(AgentModelPickerPolicy.desktopLabel("No separator").device, "")
    XCTAssertEqual(AgentModelPickerPolicy.modelLabel("gpt-6.2-astra"), "GPT-6.2 Astra")
    XCTAssertEqual(AgentModelPickerPolicy.modelLabel("gpt-6.2-sol"), "GPT-6.2 Sol")
    XCTAssertEqual(AgentModelPickerPolicy.modelLabel("custom-model"), "custom-model")
    _ = AgentModelPickerPolicy.modelGroups(original, selectedModelId: "")
    XCTAssertEqual(original.invocationProfile.models.first?.id, "gpt-6.2-astra")
  }

  private func target(_ id: String, _ models: [String] = []) -> AgentCallableTarget {
    .init(id: id, title: id, kind: .agent, status: .available, capabilities: [.chat],
      invocationProfile: .init(models: models.map { .init(id: $0) }))
  }
}
