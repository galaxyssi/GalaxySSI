import Foundation
import XCTest
@testable import GalaxySSI

final class CloudWebFastSearchTests: XCTestCase {
  func testOrdinaryAliasDefaultsToFastThreeSourcesAndTenResults() {
    for name in ["web_search", " WEB_SEARCH "] {
      let result = CloudWebGrounding.normalizeArguments(name: name, arguments: ["query": .string("exact subject")])
      XCTAssertEqual(result["profile"], .string("fast"))
      XCTAssertEqual(result["engine_fanout"], .int(3))
      XCTAssertEqual(result["limit"], .int(10))
      XCTAssertEqual(result["query"], .string("exact subject"))
    }
  }

  func testExplicitProfilesAndFanoutAreNeverOverwritten() {
    for profile in ["balanced", "deep", "unavailable-profile"] {
      let result = CloudWebGrounding.normalizeArguments(name: "web_search", arguments: ["profile": .string(profile)])
      XCTAssertEqual(result["profile"], .string(profile))
      XCTAssertNil(result["engine_fanout"])
    }
    for requested in [AgentMcpJSONValue.int(7), .null] {
      let result = CloudWebGrounding.normalizeArguments(name: "web_search", arguments: ["engine_fanout": requested])
      XCTAssertEqual(result["engine_fanout"], requested, "Invalid explicit input stays available for schema rejection")
    }
    XCTAssertEqual(CloudWebGrounding.normalizeArguments(name: "web_search", arguments: ["profile": .string("fast")])["engine_fanout"], .int(3))
  }

  func testExplicitEnginePresenceOrderAndEmptySelectionRemainIntact() {
    for engines in [AgentMcpJSONValue.array([.string("github"), .string("bing")]), .array([]), .null] {
      let result = CloudWebGrounding.normalizeArguments(name: "web_search", arguments: ["engines": engines])
      XCTAssertEqual(result["engines"], engines)
      XCTAssertEqual(result["profile"], .string("fast"))
      XCTAssertNil(result["engine_fanout"], "Presence, not nonemptiness, protects an explicit source selector")
    }
  }

  func testNativeSearchImageAliasAndResearchDefaultsRemainDistinct() {
    let native = CloudWebGrounding.normalizeArguments(name: AgentIOSWebIntelligenceNativeToolCatalog.search, arguments: [:])
    XCTAssertEqual(native["profile"], .string("balanced"))
    XCTAssertNil(native["engine_fanout"])
    let image = CloudWebGrounding.normalizeArguments(name: "web_image_search", arguments: ["query": .string("photo"), "max_results": .int(1)])
    XCTAssertEqual(image["limit"], .int(1))
    XCTAssertEqual(image["profile"], .string("fast"))
    XCTAssertEqual(image["engine_fanout"], .int(3))
    XCTAssertEqual(image["verticals"], .array([.string("image")]))
    let research = CloudWebGrounding.normalizeArguments(name: "web_research", arguments: [:])
    XCTAssertEqual(research["profile"], .string("fast"))
    XCTAssertEqual(research["evidence_limit"], .int(3))
  }

  func testActualRegistryPathReceivesFastDefaultsWithoutNewGrants() throws {
    let provider = FastSearchCaptureProvider()
    _ = CloudWebGrounding.executeTool(provider: provider, name: "web_search", arguments: ["query": .string("subject")], context: context)
    XCTAssertEqual(provider.inputs.count, 1)
    XCTAssertEqual(provider.inputs.first?["profile"], .string("fast"))
    XCTAssertEqual(provider.inputs.first?["engine_fanout"], .int(3))
    XCTAssertEqual(provider.inputs.first?["limit"], .int(10))
    XCTAssertEqual(provider.permissions, context.grantedPermissions)
    XCTAssertEqual(provider.consents, context.grantedConsents)
    XCTAssertFalse(provider.permissions.contains(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission))
  }

  func testActualRegistryPathPreservesBalancedAndExplicitEngineRequests() {
    let provider = FastSearchCaptureProvider()
    let input: AgentMcpJSONObject = ["query": .string("subject"), "profile": .string("balanced"),
      "engines": .array([.string("github"), .string("bing")]), "engine_fanout": .int(8), "max_results": .int(25)]
    _ = CloudWebGrounding.executeTool(provider: provider, name: "web_search", arguments: input, context: context)
    XCTAssertEqual(provider.inputs.first?["profile"], input["profile"])
    XCTAssertEqual(provider.inputs.first?["engines"], input["engines"])
    XCTAssertEqual(provider.inputs.first?["engine_fanout"], .int(8))
    XCTAssertEqual(provider.inputs.first?["limit"], .int(25))
  }

  private var context: AgentNativeToolInvocationContext {
    .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent])
  }
}

private final class FastSearchCaptureProvider: AgentIOSWebIntelligenceToolProviding {
  let implementationId = "fast-search-fixture"
  let engineCatalogSize = 1
  let rankerId = "fixture"
  private(set) var inputs: [AgentMcpJSONObject] = []
  private(set) var permissions = Set<String>(), consents = Set<String>()
  func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebIntelligenceOperation, input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    inputs.append(input)
    permissions = invocation.context.grantedPermissions
    consents = invocation.context.grantedConsents
    return .success(output: ["query": input["query"] ?? .null, "results": .array([
      .object(["url": .string("https://source.test/page"), "title": .string("Source")])])])
  }
}
