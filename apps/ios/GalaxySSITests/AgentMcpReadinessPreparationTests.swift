import XCTest
@testable import GalaxySSI

final class AgentMcpReadinessPreparationTests: XCTestCase {
  func testExistingDefinitionsStillResolveInitialAvailability() {
    let provider = Provider()
    let definitions = AgentMcpNativeTools.definitions(provider: provider)
    XCTAssertEqual(provider.probes.count, AgentIOSMcpNativeToolOperation.allCases.count)
    XCTAssertTrue(definitions.allSatisfy { $0.descriptor.availability.status == .available })
  }

  func testDeferredRegistrationDoesNotProbeOrInvokeTheProvider() throws {
    let provider = Provider()
    let registry = try deferredRegistry(provider)
    XCTAssertEqual(registry.ids(), AgentMcpNativeTools.toolIds)
    XCTAssertTrue(provider.probes.isEmpty)
    XCTAssertTrue(provider.calls.isEmpty)
    XCTAssertEqual(registry.lookup(AgentMcpNativeTools.listTools)?.descriptor.availability,
      AgentMcpNativeTools.uncheckedAvailability)
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .available })
    XCTAssertEqual(provider.probes.count, 3)
  }

  func testExactDiscoveryReadsCurrentReadinessWithoutScanningOtherTools() throws {
    let provider = Provider()
    let registry = try deferredRegistry(provider)
    try AgentLocalModelToolCatalog.installDiscovery(in: registry) { _ in }
    provider.readiness = .init(status: .requiresSetup, reason: "Fixture requires setup")
    let first = inspect(registry, tool: AgentMcpNativeTools.listTools)
    XCTAssertTrue(first.isSuccess)
    XCTAssertEqual(first.output["status"], .string("requires_setup"))
    XCTAssertEqual(first.output["reason"], .string("Fixture requires setup"))
    XCTAssertEqual(first.output["grants_permissions"], .bool(false))
    XCTAssertEqual(provider.probes, [.listTools])
    provider.readiness = .available
    XCTAssertEqual(inspect(registry, tool: AgentMcpNativeTools.listTools).output["status"], .string("available"))
    XCTAssertEqual(provider.probes, [.listTools, .listTools])
    XCTAssertTrue(provider.calls.isEmpty)
  }

  func testInvocationUsesDynamicReadinessInsteadOfUncheckedDescriptor() throws {
    let provider = Provider()
    let registry = try deferredRegistry(provider)
    let result = registry.invoke(AgentMcpNativeTools.listConnections, input: [:],
      context: .init(grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(provider.calls, [.listConnections])
  }

  func testUnavailableProviderCannotExecuteAfterDeferredRegistration() throws {
    let provider = Provider()
    let registry = try deferredRegistry(provider)
    provider.readiness = .init(status: .unavailable, reason: "Fixture offline")
    let result = registry.invoke(AgentMcpNativeTools.listConnections, input: [:],
      context: .init(grantedPermissions: [AgentMcpNativeTools.mcpHostPermission]))
    XCTAssertFalse(result.isSuccess)
    XCTAssertTrue(provider.calls.isEmpty)
  }

  func testDeferredAvailabilityDoesNotGrantMissingPermission() throws {
    let provider = Provider()
    let registry = try deferredRegistry(provider)
    let result = registry.invoke(AgentMcpNativeTools.listConnections, input: [:],
      context: AgentNativeToolInvocationContext())
    XCTAssertFalse(result.isSuccess)
    XCTAssertTrue(provider.calls.isEmpty)
  }

  func testRegisteredContractIdentityDoesNotDependOnInitialReadiness() throws {
    let provider = Provider()
    let eager = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: provider))
    let deferred = try deferredRegistry(provider)
    XCTAssertEqual(eager.registeredContractFingerprint(), deferred.registeredContractFingerprint())
    provider.readiness = .init(status: .requiresSetup, reason: "Changed")
    deferred.refreshAvailability()
    _ = deferred.descriptors()
    XCTAssertEqual(eager.registeredContractFingerprint(), deferred.registeredContractFingerprint())
  }

  func testUnknownExactToolDoesNotProbeOtherProviders() throws {
    let provider = Provider()
    let registry = try deferredRegistry(provider)
    try AgentLocalModelToolCatalog.installDiscovery(in: registry) { _ in }
    XCTAssertFalse(inspect(registry, tool: "fixture.unknown").isSuccess)
    XCTAssertTrue(provider.probes.isEmpty)
    XCTAssertTrue(provider.calls.isEmpty)
  }

  private func deferredRegistry(_ provider: Provider) throws -> AgentNativeToolRegistry {
    try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.mcpExecutableDefinitions(provider: provider,
        initialAvailability: AgentMcpNativeTools.uncheckedAvailability))
  }

  private func inspect(_ registry: AgentNativeToolRegistry, tool: String) -> AgentNativeToolResult {
    registry.invoke(AgentLocalModelToolCatalog.discoveryID, input: ["tool_id": .string(tool)],
      context: AgentNativeToolInvocationContext())
  }

  private final class Provider: AgentIOSMcpNativeToolProviding {
    var implementationId = "fixture.mcp.readiness"
    var readiness: AgentNativeToolAvailability = .available
    var probes: [AgentIOSMcpNativeToolOperation] = []
    var calls: [AgentIOSMcpNativeToolOperation] = []
    func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability {
      probes.append(operation)
      return readiness
    }
    func invoke(operation: AgentIOSMcpNativeToolOperation, input: AgentMcpJSONObject,
                invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
      calls.append(operation)
      return .success(output: ["fixture": .bool(true)])
    }
  }
}
