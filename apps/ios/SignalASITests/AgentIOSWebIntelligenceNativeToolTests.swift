import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentIOSWebIntelligenceNativeToolCatalogAndExecutorUsesProviderBoundaries() throws {
    final class FakeWebIntelligenceProvider: AgentIOSWebIntelligenceToolProviding {
      var implementationId = "fake.ios.web_intelligence"
      var engineCatalogSize = 7
      var rankerId = "feature-hash-ranker-v1"
      var currentAvailability: AgentNativeToolAvailability = .available
      var invokedOperations: [AgentIOSWebIntelligenceOperation] = []

      func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability {
        currentAvailability
      }

      func invoke(
        operation: AgentIOSWebIntelligenceOperation,
        input: AgentMcpJSONObject,
        invocation: AgentNativeToolInvocation
      ) -> AgentNativeToolExecutionResult {
        invokedOperations.append(operation)
        return AgentNativeToolExecutionResult.success(
          output: [
            "request_id": .string("req-\(operation.rawValue)"),
            "result_count": .int(1)
          ],
          message: "",
          metadata: ["provider_operation": .string(operation.rawValue)]
        )
      }
    }

    let provider = FakeWebIntelligenceProvider()
    let definitions = AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider)
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider)
    )
    let networkContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]
    )
    let cacheContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSWebIntelligenceNativeToolCatalog.executorId)
      XCTAssertEqual(definition.descriptor.location, .phone)
      XCTAssertEqual(definition.descriptor.risk, .low)
      XCTAssertEqual(definition.descriptor.idempotency, .idempotent)
      XCTAssertTrue(definition.descriptor.capabilities.contains("web_intelligence.native"))
      XCTAssertTrue(definition.descriptor.capabilities.contains("source.receipts"))
      XCTAssertFalse(definition.descriptor.requiredPermissions.isEmpty)
      XCTAssertFalse(definition.descriptor.requiredConsents.isEmpty)
      XCTAssertEqual(definition.provenanceMetadata["protocol"], AgentIOSWebIntelligenceNativeToolCatalog.protocolId)
      XCTAssertEqual(definition.provenanceMetadata["engine_catalog_size"], "7")
      XCTAssertEqual(definition.provenanceMetadata["cookies"], "none")
    }
    let fetch = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.fetch })
    let cache = try XCTUnwrap(definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.cache })
    XCTAssertEqual(fetch.descriptor.requiredPermissions.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission])
    XCTAssertEqual(fetch.descriptor.requiredConsents.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent])
    XCTAssertEqual(cache.descriptor.requiredPermissions.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission])
    XCTAssertEqual(cache.descriptor.requiredConsents.map(\.id), [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])

    let denied = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("SignalASI")],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission]
      )
    )
    XCTAssertEqual(denied.status, .rejected)
    XCTAssertEqual(denied.error?.code, "missing_consents")
    XCTAssertTrue(provider.invokedOperations.isEmpty)

    let search = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("SignalASI"), "limit": .int(3)],
      context: networkContext
    )
    let cacheStatus = registry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("status")],
      context: cacheContext
    )
    let unavailableProvider = FakeWebIntelligenceProvider()
    unavailableProvider.currentAvailability = AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "Network provider missing"
    )
    let unavailableRegistry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: unavailableProvider)
    )
    let unavailable = unavailableRegistry.invoke(
      AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("SignalASI")],
      context: networkContext
    )

    XCTAssertTrue(search.isSuccess)
    XCTAssertEqual(search.output["protocol"], .string(AgentIOSWebIntelligenceNativeToolCatalog.protocolId))
    XCTAssertEqual(search.output["operation"], .string("search"))
    XCTAssertEqual(search.output["status"], .string("completed"))
    XCTAssertEqual(search.metadata["source_isolation"], .bool(true))
    XCTAssertEqual(search.metadata["evidence_is_untrusted"], .bool(true))
    XCTAssertEqual(search.message, "Search across independent web sources completed")
    XCTAssertTrue(cacheStatus.isSuccess)
    XCTAssertEqual(cacheStatus.output["operation"], .string("cache"))
    XCTAssertEqual(provider.invokedOperations, [.search, .cache])
    XCTAssertEqual(unavailable.status, .unavailable)
    XCTAssertEqual(unavailable.error?.code, "tool_unavailable")
    XCTAssertTrue(unavailableProvider.invokedOperations.isEmpty)
  }

}
