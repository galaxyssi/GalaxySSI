import XCTest
@testable import SignalASI

extension SignalASIStoreTests {
  func testAgentIOSHomeAssistantNativeToolCatalogAndExecutorPreserveSecretSafePolicy() throws {
    struct FakeHomeAssistantProvider: AgentIOSHomeAssistantToolProviding {
      var implementationId = "fake.ios.home_assistant"
      var verified = true

      func availability() -> AgentNativeToolAvailability { .available }

      func connectionStatus(nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "connected": .bool(true),
            "credentials_exposed": .bool(false),
            "checked_at_epoch_ms": .int(nowMillis)
          ],
          message: "Connected"
        )
      }

      func listEntities(query: String, domains: [String], limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "entities": .array([.object([
              "entity_id": .string("light.office"),
              "friendly_name": .string("Office"),
              "state": .string("on"),
              "domain": .string("light"),
              "protected": .bool(false)
            ])]),
            "result_count": .int(1),
            "total_matched": .int(1),
            "truncated": .bool(false),
            "observed_at_epoch_ms": .int(nowMillis),
            "protected_state_count": .int(0)
          ],
          message: "Entities listed",
          metadata: ["query": .string(query), "domain_count": .int(Int64(domains.count))]
        )
      }

      func readEntity(entityId: String, nowMillis: Int64) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "entity": .object([
              "entity_id": .string(entityId),
              "friendly_name": .string("Office"),
              "state": .string("on"),
              "domain": .string("light"),
              "protected": .bool(false)
            ]),
            "observed_at_epoch_ms": .int(nowMillis)
          ],
          message: "Entity read"
        )
      }

      func callService(
        serviceDomain: String,
        service: String,
        entityId: String,
        serviceData: AgentMcpJSONObject,
        nowMillis: Int64
      ) -> AgentNativeToolExecutionResult {
        AgentNativeToolExecutionResult.success(
          output: [
            "request_accepted": .bool(true),
            "service_domain": .string(serviceDomain),
            "service": .string(service),
            "entity_id": .string(entityId),
            "verification_supported": .bool(true),
            "controller_state_observed": .bool(true),
            "controller_state_verified": .bool(verified),
            "previous_state": .string("off"),
            "current_state": .string(verified ? "on" : "off"),
            "state_protected": .bool(false),
            "changed_state_count": .int(verified ? 1 : 0),
            "physical_outcome_verified": .bool(false)
          ],
          message: "Service accepted",
          metadata: ["single_entity_scope": .bool(true)]
        )
      }
    }

    func serviceInput(
      _ serviceDomain: String,
      _ service: String,
      _ entityId: String,
      serviceData: AgentMcpJSONObject = [:]
    ) -> AgentMcpJSONObject {
      [
        "service_domain": .string(serviceDomain),
        "service": .string(service),
        "entity_id": .string(entityId),
        "service_data": .object(serviceData)
      ]
    }

    let definitions = AgentIOSHomeAssistantNativeToolCatalog.definitions(provider: FakeHomeAssistantProvider())
    let registry = try AgentNativeToolRegistry().registerExecutables(
      AgentPhoneNativeToolCatalog.homeAssistantExecutableDefinitions(
        provider: FakeHomeAssistantProvider(),
        nowMillis: { 7_000 }
      )
    )
    let readContext = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.readConsent]
    )
    let controlContext = AgentNativeToolInvocationContext(
      invocationId: "ha-service",
      idempotencyKey: "ha-service-1",
      grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
    )

    XCTAssertEqual(Set(definitions.map(\.id)), AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    XCTAssertEqual(registry.ids(), AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    definitions.forEach { definition in
      XCTAssertEqual(definition.executorId, AgentIOSHomeAssistantNativeToolCatalog.executorId)
      XCTAssertEqual(definition.provenanceMetadata["credential_exposure"], "none")
      XCTAssertEqual(definition.provenanceMetadata["access_token_exposed"], "false")
      XCTAssertEqual(definition.descriptor.requiredPermissions.map(\.id), [AgentIOSHomeAssistantNativeToolCatalog.networkPermission])
    }
    let connection = try XCTUnwrap(definitions.first { $0.id == AgentIOSHomeAssistantNativeToolCatalog.connectionStatus })
    let serviceDescriptor = try XCTUnwrap(definitions.first { $0.id == AgentIOSHomeAssistantNativeToolCatalog.serviceCall })
    XCTAssertEqual(connection.descriptor.requiredConsents.map(\.id), ["signalasi.consent.none"])
    XCTAssertFalse(connection.descriptor.requiredConsents.first?.required ?? true)
    XCTAssertEqual(serviceDescriptor.descriptor.idempotency, .idempotencyKeyRequired)
    XCTAssertEqual(serviceDescriptor.descriptor.requiredConsents.map(\.id), [AgentIOSHomeAssistantNativeToolCatalog.controlConsent])

    let deniedList = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.entitiesList,
      input: [:],
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission]
      )
    )
    let listed = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.entitiesList,
      input: [
        "query": .string("office"),
        "domains": .array([.string("light")]),
        "limit": .int(5)
      ],
      context: readContext
    )
    let read = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.entityRead,
      input: ["entity_id": .string("light.office")],
      context: readContext
    )
    let missingKey = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("light", "turn_on", "light.office"),
      context: AgentNativeToolInvocationContext(
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
      )
    )
    let service = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("light", "turn_on", "light.office"),
      context: controlContext
    )
    let mismatch = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("switch", "turn_on", "light.office"),
      context: AgentNativeToolInvocationContext(
        invocationId: "ha-mismatch",
        idempotencyKey: "ha-mismatch",
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
      )
    )
    let secret = registry.invoke(
      AgentIOSHomeAssistantNativeToolCatalog.serviceCall,
      input: serviceInput("light", "turn_on", "light.office", serviceData: ["access_token": .string("secret")]),
      context: AgentNativeToolInvocationContext(
        invocationId: "ha-secret",
        idempotencyKey: "ha-secret",
        grantedPermissions: [AgentIOSHomeAssistantNativeToolCatalog.networkPermission],
        grantedConsents: [AgentIOSHomeAssistantNativeToolCatalog.controlConsent]
      )
    )

    XCTAssertEqual(deniedList.status, .rejected)
    XCTAssertEqual(deniedList.error?.code, "missing_consents")
    XCTAssertTrue(listed.isSuccess)
    XCTAssertEqual(listed.metadata["access_token_exposed"], .bool(false))
    XCTAssertEqual((listed.output["entities"]?.arrayValue ?? []).count, 1)
    XCTAssertTrue(read.isSuccess)
    XCTAssertEqual(read.output["observed_at_epoch_ms"], .int(7_000))
    XCTAssertEqual(missingKey.status, .rejected)
    XCTAssertEqual(missingKey.error?.code, "missing_idempotency_key")
    XCTAssertTrue(service.isSuccess)
    XCTAssertEqual(service.verification?.status, .passed)
    XCTAssertEqual(service.output["physical_outcome_verified"], .bool(false))
    XCTAssertEqual(mismatch.status, .failed)
    XCTAssertEqual(mismatch.error?.code, "domain_mismatch")
    XCTAssertEqual(secret.status, .failed)
    XCTAssertEqual(secret.error?.code, "invalid_service_data")
  }
}
