import Foundation
import XCTest
@testable import GalaxySSI

final class AgentRuntimeToolReadinessTests: XCTestCase {
  func testRuntimeDeferredCatalogDoesNotProbeUntilDiscovery() throws {
    let state = State()
    try checkDeferred(AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: Runtime(state),
      initialAvailability: AgentIOSOnDeviceRuntimeNativeToolCatalog.uncheckedAvailability), state: state)
  }

  func testProjectReadDeferredCatalogDoesNotProbeUntilDiscovery() throws {
    let state = State()
    try checkDeferred(AgentIOSProjectRepositoryReadToolCatalog.definitions(runtimeProvider: Runtime(state),
      initialAvailability: AgentIOSOnDeviceRuntimeNativeToolCatalog.uncheckedAvailability), state: state)
    XCTAssertTrue(state.probes.allSatisfy { $0 == "execute" })
  }

  func testProjectMutationDeferredCatalogDoesNotProbeUntilDiscovery() throws {
    let state = State()
    try checkDeferred(AgentIOSProjectRepositoryMutationToolCatalog.definitions(runtimeProvider: Runtime(state),
      initialAvailability: AgentIOSOnDeviceRuntimeNativeToolCatalog.uncheckedAvailability), state: state)
    XCTAssertTrue(state.probes.allSatisfy { $0 == "execute" })
  }

  func testEvolutionDeferredCatalogDoesNotProbeUntilDiscovery() throws {
    let state = State()
    try checkDeferred(AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: Evolution(state),
      initialAvailability: AgentIOSOnDeviceRuntimeNativeToolCatalog.uncheckedAvailability), state: state)
  }

  func testExecutableCatalogHelpersForwardDeferredReadinessWithoutProbing() throws {
    let state = State(), initial = AgentIOSOnDeviceRuntimeNativeToolCatalog.uncheckedAvailability
    let executables = AgentPhoneNativeToolCatalog.onDeviceRuntimeExecutableDefinitions(provider: Runtime(state),
      initialAvailability: initial) +
      AgentPhoneNativeToolCatalog.projectRepositoryReadExecutableDefinitions(runtimeProvider: Runtime(state),
        initialAvailability: initial) +
      AgentPhoneNativeToolCatalog.projectRepositoryMutationExecutableDefinitions(runtimeProvider: Runtime(state),
        initialAvailability: initial) +
      AgentPhoneNativeToolCatalog.selfEvolutionExecutableDefinitions(provider: Evolution(state), initialAvailability: initial)
    XCTAssertEqual(executables.count, 27)
    XCTAssertTrue(state.probes.isEmpty)
    let registry = try AgentNativeToolRegistry().registerExecutables(executables)
    _ = registry.registeredContractFingerprint()
    XCTAssertTrue(state.probes.isEmpty)
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .requiresSetup })
    XCTAssertEqual(state.probes.count, executables.count)
    XCTAssertEqual(state.invocations, 0)
  }

  func testRuntimeCatalogReflectsSetupRecoveryAndFailure() throws {
    let state = State()
    try checkRefresh(AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: Runtime(state)), state: state)
  }

  func testProjectReadCatalogReflectsSetupRecoveryAndFailure() throws {
    let state = State()
    try checkRefresh(AgentIOSProjectRepositoryReadToolCatalog.definitions(runtimeProvider: Runtime(state)), state: state)
    XCTAssertTrue(state.probes.allSatisfy { $0 == "execute" })
  }

  func testProjectMutationCatalogReflectsSetupRecoveryAndFailure() throws {
    let state = State()
    try checkRefresh(AgentIOSProjectRepositoryMutationToolCatalog.definitions(runtimeProvider: Runtime(state)), state: state)
    XCTAssertTrue(state.probes.allSatisfy { $0 == "execute" })
  }

  func testEvolutionCatalogReflectsSetupRecoveryAndFailure() throws {
    let state = State()
    try checkRefresh(AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: Evolution(state)), state: state)
  }

  func testRuntimeInvocationChecksLiveReadinessAndPermission() throws {
    let state = State()
    try checkGate(AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: Runtime(state)),
      tool: AgentIOSOnDeviceRuntimeNativeToolCatalog.status, input: [:], state: state)
  }

  func testProjectReadInvocationChecksLiveReadinessAndPermission() throws {
    let state = State()
    try checkGate(AgentIOSProjectRepositoryReadToolCatalog.definitions(runtimeProvider: Runtime(state)),
      tool: AgentIOSProjectRepositoryReadToolCatalog.observe, input: ["workspace_id": .string("fixture")], state: state)
  }

  func testProjectMutationInvocationChecksLiveReadinessAndPermission() throws {
    let state = State()
    try checkGate(AgentIOSProjectRepositoryMutationToolCatalog.definitions(runtimeProvider: Runtime(state)),
      tool: AgentIOSProjectRepositoryMutationToolCatalog.fetch, input: ["workspace_id": .string("fixture")], state: state)
  }

  func testEvolutionInvocationChecksLiveReadinessAndPermission() throws {
    let state = State()
    try checkGate(AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: Evolution(state)),
      tool: AgentIOSSelfEvolutionNativeToolCatalog.status, input: [:], state: state)
  }

  private func checkRefresh(_ definitions: [AgentPhoneNativeToolDefinition], state: State) throws {
    XCTAssertEqual(state.probes.count, definitions.count, "Explicit catalog calls retain eager compatibility")
    let registry = try AgentNativeToolRegistry().registerAll(definitions)
    let identity = registry.registeredContractFingerprint()
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .requiresSetup })
    state.readiness = .available
    registry.refreshAvailability()
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .available })
    state.readiness = .init(status: .unavailable, reason: "Fixture runtime failed")
    registry.refreshAvailability()
    let unavailable = registry.descriptors()
    XCTAssertEqual(unavailable.count, definitions.count)
    XCTAssertTrue(unavailable.allSatisfy { $0.availability.status == .unavailable })
    XCTAssertTrue(unavailable.allSatisfy { $0.availability.reason == "Fixture runtime failed" })
    XCTAssertEqual(registry.registeredContractFingerprint(), identity)
    XCTAssertEqual(state.invocations, 0)
  }

  private func checkGate(_ definitions: [AgentPhoneNativeToolDefinition], tool: String,
                         input: AgentMcpJSONObject, state: State) throws {
    let definition = try XCTUnwrap(definitions.first { $0.id == tool })
    let registry = try AgentNativeToolRegistry().registerExecutable(.init(definition: definition, executor: { _ in
      state.invocations += 1
      return .failure(code: "fixture_reached", message: "Fixture executor reached; no external work")
    }))
    func context(permissions: Bool = true) -> AgentNativeToolInvocationContext {
      .init(invocationId: UUID().uuidString, sessionId: "fixture-session", conversationId: "fixture-conversation",
        turnId: UUID().uuidString, callerId: "fixture", idempotencyKey: UUID().uuidString,
        grantedPermissions: permissions ? Set(definition.descriptor.requiredPermissions.filter(\.required).map(\.id)) : [],
        grantedConsents: Set(definition.descriptor.requiredConsents.filter(\.required).map(\.id)))
    }
    _ = registry.invoke(tool, input: input, context: context())
    XCTAssertEqual(state.invocations, 0)
    state.readiness = .available
    _ = registry.invoke(tool, input: input, context: context())
    XCTAssertEqual(state.invocations, 1)
    state.readiness = .init(status: .unavailable, reason: "Fixture runtime failed")
    _ = registry.invoke(tool, input: input, context: context())
    XCTAssertEqual(state.invocations, 1)
    state.readiness = .available
    _ = registry.invoke(tool, input: input, context: context(permissions: false))
    XCTAssertEqual(state.invocations, 1)
  }

  private func checkDeferred(_ definitions: [AgentPhoneNativeToolDefinition], state: State) throws {
    XCTAssertFalse(definitions.isEmpty)
    XCTAssertTrue(state.probes.isEmpty)
    XCTAssertTrue(definitions.allSatisfy { $0.descriptor.availability ==
      AgentIOSOnDeviceRuntimeNativeToolCatalog.uncheckedAvailability })
    let registry = try AgentNativeToolRegistry().registerAll(definitions)
    let fingerprint = registry.registeredContractFingerprint()
    XCTAssertTrue(state.probes.isEmpty)
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .requiresSetup })
    XCTAssertEqual(state.probes.count, definitions.count)
    state.readiness = .available
    registry.refreshAvailability()
    XCTAssertTrue(registry.descriptors().allSatisfy { $0.availability.status == .available })
    XCTAssertEqual(registry.registeredContractFingerprint(), fingerprint)
    XCTAssertEqual(state.invocations, 0)
  }

  private final class State {
    var readiness = AgentNativeToolAvailability(status: .requiresSetup, reason: "Fixture requires setup")
    var probes: [String] = []
    var invocations = 0
    func probe(_ operation: String) -> AgentNativeToolAvailability {
      probes.append(operation)
      return readiness
    }
  }

  private struct Runtime: AgentIOSOnDeviceRuntimeToolProviding {
    var implementationId = "fixture.runtime.readiness"
    let state: State
    init(_ state: State) { self.state = state }
    func availability(operation: AgentIOSOnDeviceRuntimeToolOperation) -> AgentNativeToolAvailability {
      state.probe(operation.rawValue)
    }
    func invoke(operation: AgentIOSOnDeviceRuntimeToolOperation, input: AgentMcpJSONObject,
                invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
      XCTFail("Readiness fixtures must not invoke a real runtime provider")
      return .failure(code: "fixture_unexpected", message: "Unexpected runtime call")
    }
  }

  private struct Evolution: AgentIOSSelfEvolutionToolProviding {
    var implementationId = "fixture.evolution.readiness"
    let state: State
    init(_ state: State) { self.state = state }
    func availability(operation: AgentIOSSelfEvolutionOperation) -> AgentNativeToolAvailability {
      state.probe(operation.rawValue)
    }
    func invoke(operation: AgentIOSSelfEvolutionOperation, input: AgentMcpJSONObject,
                invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
      XCTFail("Readiness fixtures must not invoke a real evolution provider")
      return .failure(code: "fixture_unexpected", message: "Unexpected evolution call")
    }
  }
}
