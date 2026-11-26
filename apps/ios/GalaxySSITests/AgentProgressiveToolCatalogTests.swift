import XCTest
@testable import GalaxySSI

final class AgentProgressiveToolCatalogTests: XCTestCase {
  private func tool(_ id: String = "galaxyssi.hardware.synthetic") throws -> AgentNativeToolDescriptor {
    try AgentNativeToolDescriptor(id: id, version: "1.0.0", title: "Synthetic capability",
      description: "Read a registered test capability", location: .application,
      inputSchema: AgentNativeToolDescriptor.objectSchema(), risk: .low, idempotency: .idempotent, effect: .readOnly)
  }

  private func registry() throws -> AgentNativeToolRegistry {
    try AgentNativeToolRegistry().registerExecutables(AgentToolInspectionCatalog.executableDefinitions())
  }

  func testInspectionBindsToInvokingSubsetInsteadOfInstallerRegistry() throws {
    let full = try registry()
    try full.register(.init(descriptor: tool("galaxyssi.hardware.hidden"), executorId: "metadata"))
    let limited = try full.subset { AgentToolInspectionCatalog.toolIds.contains($0.id) }
    let denied = limited.invoke(AgentToolInspectionCatalog.describe,
      input: ["tool_id": .string("galaxyssi.hardware.hidden")], context: .init())
    XCTAssertFalse(denied.isSuccess)
    XCTAssertEqual(denied.error?.code, "tool_not_disclosed")
    let listing = limited.invoke(AgentToolInspectionCatalog.discover, input: [:], context: .init())
    XCTAssertTrue(listing.isSuccess)
    XCTAssertEqual(Set((listing.output["tools"]?.arrayValue ?? []).compactMap { $0.objectValue?.string("id") }),
      AgentToolInspectionCatalog.toolIds)
  }

  func testContractReadDoesNotExecuteTargetOrGrantItsRequiredConsent() throws {
    let registry = try registry()
    var descriptor = try tool()
    descriptor.requiredConsents = [.init(id: "test.required_consent")]
    var executions = 0
    try registry.registerExecutable(.init(definition: .init(descriptor: descriptor, executorId: "test"), executor: { _ in
      executions += 1
      return .success(output: [:])
    }))
    let inspected = registry.invoke(AgentToolInspectionCatalog.describe,
      input: ["tool_id": .string(descriptor.id)], context: .init())
    XCTAssertTrue(inspected.isSuccess)
    XCTAssertEqual(inspected.output["definition"], .object(descriptor.inputSchema))
    XCTAssertEqual(inspected.output["target_executed"], .bool(false))
    XCTAssertFalse(registry.invoke(descriptor.id, input: [:], context: .init()).isSuccess)
    XCTAssertEqual(executions, 0)
  }

  func testContractPointersPreserveNullAndEscapedKeysAndRejectInvalidArrayIndexes() {
    let root: AgentMcpJSONValue = .object(["a/b": .object(["~": .array([.null, .string("value")])])])
    XCTAssertEqual(AgentToolInspectionCatalog.select(root, path: ""), root)
    XCTAssertEqual(AgentToolInspectionCatalog.select(root, path: "/a~1b/~0/0"), .null)
    XCTAssertEqual(AgentToolInspectionCatalog.select(root, path: "/a~1b/~0/1"), .string("value"))
    for path in ["a/b", "/a~2b", "/a~1b/~0/01", "/a~1b/~0/-1", "/a~1b/~0/2"] {
      XCTAssertNil(AgentToolInspectionCatalog.select(root, path: path), path)
    }
  }

  func testDiscoveryCursorBindsQueryCatalogAndExistingPageBoundary() throws {
    let registry = try registry()
    for index in 0..<5 { try registry.register(.init(descriptor: tool("galaxyssi.hardware.test\(index)"), executorId: "metadata")) }
    let catalog = try XCTUnwrap(registry.catalogObject()["tools"]?.arrayValue).compactMap(\.objectValue)
    let first = AgentToolInspectionCatalog.page(catalog, input: ["query": .string("hardware"), "limit": .int(2)])
    let cursor = try XCTUnwrap(first.output["next_cursor"])
    let next = AgentToolInspectionCatalog.page(catalog, input: ["query": .string("hardware"), "limit": .int(2), "cursor": cursor])
    XCTAssertTrue(next.isSuccess)
    XCTAssertNotEqual(first.output["tools"], next.output["tools"])
    XCTAssertFalse(AgentToolInspectionCatalog.page(catalog, input: ["query": .string("tools"), "cursor": cursor]).isSuccess)
    var changed = catalog
    changed[0]["description"] = .string("Updated capability")
    XCTAssertEqual(AgentToolInspectionCatalog.page(changed, input: ["query": .string("hardware"), "cursor": cursor]).error?.code,
      "tool_catalog_changed")
  }

  func testDiscoveryDoesNotTurnZeroMatchesIntoAbsentCapability() {
    let result = AgentToolInspectionCatalog.page([], input: ["query": .string("unknown")])
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["capability_absent"], .bool(false))
    XCTAssertEqual(result.output["target_executed"], .bool(false))
    XCTAssertNotNil(result.output["search_guidance"])
  }

  func testLargeCatalogKeepsOnlyEntryPointsAndEligibleRecentTools() throws {
    let helpers = AgentToolInspectionCatalog.definitions().map(\.descriptor)
    let filler = try (0..<30).map { try tool("galaxyssi.hardware.test\($0)") }
    let web = try tool(AgentIOSWebIntelligenceNativeToolCatalog.search)
    let catalog = helpers + [web] + filler
    let rendered = try XCTUnwrap(AgentProgressiveToolCatalog.render(catalog, recent: [filler[0].id, "not.available"])).text
    XCTAssertTrue(rendered.contains("Available families: hardware, tools, web."))
    XCTAssertTrue(rendered.contains(filler[0].id + " |"))
    XCTAssertFalse(rendered.contains(filler[1].id + " |"))
    XCTAssertFalse(rendered.contains("not.available |"))
    XCTAssertTrue(rendered.contains(web.id + " |"))
    XCTAssertNil(AgentProgressiveToolCatalog.render(Array(catalog.prefix(12)), recent: []))
    for helper in helpers {
      XCTAssertNil(AgentProgressiveToolCatalog.render(catalog.filter { $0.id != helper.id }, recent: []))
    }
  }

  func testRecentCarryForwardIsCompletedDistinctAndBoundedToFourIncludingDescriptions() {
    func action(_ id: String, inspected: String = "", status: AgentActionStatus = .completed) -> AgentAction {
      .init(id: UUID().uuidString, kind: .callNativeTool, target: id, risk: .low, status: status, description: "History",
        parameters: ["input_json": AgentMcpJSONCodec.stringify(["tool_id": .string(inspected)])])
    }
    let history = (1...8).map { action("galaxyssi.hardware.test\($0)") } + [
      action(AgentToolInspectionCatalog.describe, inspected: "galaxyssi.app.news"),
      action(AgentToolInspectionCatalog.describe, inspected: "not.completed", status: .failed),
      action(AgentToolInspectionCatalog.discover)]
    XCTAssertEqual(AgentProgressiveToolCatalog.recent(history), Set([
      "galaxyssi.hardware.test6", "galaxyssi.hardware.test7", "galaxyssi.hardware.test8", "galaxyssi.app.news"]))
  }

  func testCompactSignaturesPreserveRequiredFieldsSmallEnumsAndListTypes() {
    let schema: AgentMcpJSONObject = ["required": .array([.string("query")]), "properties": .object([
      "query": .object(["type": .string("string")]),
      "profile": .object(["enum": .array([.string("fast"), .string("balanced"), .string("deep")])]),
      "items": .object(["type": .string("array"), "items": .object(["type": .string("integer")])])])]
    let signature = AgentProgressiveToolCatalog.signature(schema)
    XCTAssertTrue(signature.contains("query!:string"))
    XCTAssertTrue(signature.contains("profile:fast|balanced|deep"))
    XCTAssertTrue(signature.contains("items:list<integer>"))
  }

  func testProductionPromptUsesProgressiveCatalogWithoutDroppingGoalOrDialogue() throws {
    let tools = AgentToolInspectionCatalog.definitions().map(\.descriptor) + (try (0..<30).map { try tool("galaxyssi.hardware.test\($0)") })
    let request = AgentModelPlanningPromptRequest(planRequest: .init(goal: "Hello, what can you help with?",
      screen: .init(foregroundApp: "GalaxySSI", pageTitle: "Agent", visibleTexts: [], isAccessibilityEnabled: true), nativeTools: tools),
      conversationContext: .init(conversationId: "conversation", summary: "Keep this context", turns: [], privateMode: false))
    let prompt = AgentModelPlanningPrompt.build(request: request, settings: .default)
    XCTAssertTrue(prompt.contains("Available families:"))
    XCTAssertTrue(prompt.contains(request.planRequest.goal))
    XCTAssertTrue(prompt.contains("Keep this context"))
    XCTAssertFalse(prompt.contains("- galaxyssi.hardware.test0 |"))
  }
}
