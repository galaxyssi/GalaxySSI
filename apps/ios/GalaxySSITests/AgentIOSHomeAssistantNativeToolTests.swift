import XCTest
@testable import GalaxySSI

extension GalaxySSIStoreTests {
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
    XCTAssertEqual(connection.descriptor.requiredConsents.map(\.id), ["galaxyssi.consent.none"])
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

  func testAgentIOSHomeAssistantRESTProviderUsesConfiguredSettingsAndRedactsSecrets() throws {
    let settings = HomeAssistantSettings(
      enabled: true,
      baseUrl: "http://homeassistant.local:8123/",
      accessToken: "ha-token",
      defaultEntityId: "light.office"
    )
    let transport = TestHomeAssistantRESTTransport(responses: [
      "GET /api/": [#"{"message":"API running."}"#],
      "GET /api/states": [
        #"""
        [
          {"entity_id":"lock.front_door","state":"locked","attributes":{"friendly_name":"Front Door"}},
          {"entity_id":"light.office","state":"on","attributes":{"friendly_name":"Office"}},
          {"entity_id":"switch.fan","state":"off","attributes":{"friendly_name":"Fan"}}
        ]
        """#
      ],
      "GET /api/states/lock.front_door": [
        #"{"entity_id":"lock.front_door","state":"locked","attributes":{"friendly_name":"Front Door"}}"#
      ],
      "GET /api/states/light.office": [
        #"{"entity_id":"light.office","state":"off","attributes":{"friendly_name":"Office"}}"#,
        #"{"entity_id":"light.office","state":"on","attributes":{"friendly_name":"Office"}}"#
      ],
      "POST /api/services/homeassistant/turn_on": [
        #"[{"entity_id":"light.office","state":"on"}]"#
      ]
    ])
    let provider = AgentIOSConfiguredHomeAssistantToolProvider(
      settingsProvider: { settings },
      transport: transport,
      stateVerificationRetries: 0
    )

    let connection = provider.connectionStatus(nowMillis: 10_000)
    let listed = provider.listEntities(query: "office", domains: ["light", "lock"], limit: 10, nowMillis: 10_001)
    let protectedRead = provider.readEntity(entityId: "LOCK.FRONT_DOOR", nowMillis: 10_002)
    let service = provider.callService(
      serviceDomain: "homeassistant",
      service: "turn_on",
      entityId: "light.office",
      serviceData: ["brightness": .int(128)],
      nowMillis: 10_003
    )

    XCTAssertEqual(provider.availability().status, .available)
    XCTAssertTrue(connection.toJson(), connection.isSuccess)
    XCTAssertEqual(connection.output["connected"], .bool(true))
    XCTAssertEqual(connection.metadata["access_token_exposed"], .bool(false))
    XCTAssertEqual(connection.metadata["base_url_exposed"], .bool(false))

    XCTAssertTrue(listed.toJson(), listed.isSuccess)
    XCTAssertEqual(listed.output["result_count"], .int(1))
    XCTAssertEqual(listed.output["total_matched"], .int(1))
    let listedEntity = try XCTUnwrap(listed.output["entities"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(listedEntity["entity_id"], .string("light.office"))
    XCTAssertEqual(listedEntity["state"], .string("on"))
    XCTAssertEqual(listed.output["protected_state_count"], .int(0))

    XCTAssertTrue(protectedRead.toJson(), protectedRead.isSuccess)
    let protectedEntity = try XCTUnwrap(protectedRead.output["entity"]?.objectValue)
    XCTAssertEqual(protectedEntity["entity_id"], .string("lock.front_door"))
    XCTAssertEqual(protectedEntity["state"], .string("protected"))
    XCTAssertEqual(protectedRead.metadata["protected_state_redacted"], .bool(true))

    XCTAssertTrue(service.toJson(), service.isSuccess)
    XCTAssertEqual(service.output["request_accepted"], .bool(true))
    XCTAssertEqual(service.output["controller_state_verified"], .bool(true))
    XCTAssertEqual(service.output["previous_state"], .string("off"))
    XCTAssertEqual(service.output["current_state"], .string("on"))
    XCTAssertEqual(service.output["changed_state_count"], .int(1))
    XCTAssertEqual(service.metadata["single_entity_scope"], .bool(true))
    XCTAssertEqual(service.metadata["access_token_exposed"], .bool(false))
    let postRequest = try XCTUnwrap(transport.requests.first { $0.method.testName == "POST" })
    XCTAssertEqual(postRequest.body["entity_id"], .string("light.office"))
    XCTAssertEqual(postRequest.body["brightness"], .int(128))
    XCTAssertEqual(transport.requestKeys, [
      "GET /api/",
      "GET /api/states",
      "GET /api/states/lock.front_door",
      "GET /api/states/light.office",
      "POST /api/services/homeassistant/turn_on",
      "GET /api/states/light.office"
    ])
  }

  func testAgentPhoneNativeToolCatalogDefaultRegistryUsesHomeAssistantSettingsProvider() throws {
    let root = try temporaryDirectory("native-tool-home-assistant-default")
    defer { try? FileManager.default.removeItem(at: root) }
    let actionExecutor = TestAgentActionExecutor { action, _ in
      AgentActionResult(actionId: action.id, success: true, message: "Executed")
    }

    let registry = try AgentPhoneNativeToolCatalog.defaultRegistry(
      actionExecutor: actionExecutor,
      screenProvider: { _ in AgentScreenContext(foregroundApp: "GalaxySSI", pageTitle: "Agent") },
      capabilityStatusProvider: { readyPhoneCapabilityStatuses() },
      storageRootURL: root,
      homeAssistantSettingsProvider: {
        HomeAssistantSettings(
          enabled: true,
          baseUrl: "http://homeassistant.local:8123",
          accessToken: "ha-token",
          defaultEntityId: "light.office"
        )
      }
    )
    let definition = try XCTUnwrap(registry.lookup(AgentIOSHomeAssistantNativeToolCatalog.connectionStatus))

    XCTAssertEqual(definition.provenanceMetadata["implementation"], "galaxyssi.ios.home_assistant_rest")
    XCTAssertEqual(definition.descriptor.availability.status, .available)
    XCTAssertEqual(definition.provenanceMetadata["credential_exposure"], "none")
  }

  func testAgentHomeAssistantPromptRouterBuildsAndroidCompatibleServiceCalls() throws {
    func assertRoute(
      _ prompt: String,
      defaultEntityId: String = "",
      serviceDomain: String,
      service: String,
      entityId: String,
      serviceData: AgentMcpJSONObject = [:],
      file: StaticString = #filePath,
      line: UInt = #line
    ) throws {
      let request = try XCTUnwrap(
        AgentHomeAssistantPromptRouter.serviceCall(for: prompt, defaultEntityId: defaultEntityId),
        file: file,
        line: line
      )
      XCTAssertEqual(request.serviceDomain, serviceDomain, file: file, line: line)
      XCTAssertEqual(request.service, service, file: file, line: line)
      XCTAssertEqual(request.entityId, entityId, file: file, line: line)
      XCTAssertEqual(request.serviceData, serviceData, file: file, line: line)
      XCTAssertEqual(request.nativeToolInput["service_domain"], .string(serviceDomain), file: file, line: line)
      XCTAssertEqual(request.nativeToolInput["service"], .string(service), file: file, line: line)
      XCTAssertEqual(request.nativeToolInput["entity_id"], .string(entityId), file: file, line: line)
      XCTAssertEqual(request.nativeToolInput["service_data"], .object(serviceData), file: file, line: line)
    }

    try assertRoute(
      "Turn on light.office",
      serviceDomain: "homeassistant",
      service: "turn_on",
      entityId: "light.office"
    )
    try assertRoute(
      "Turn off",
      defaultEntityId: " switch.kitchen ",
      serviceDomain: "homeassistant",
      service: "turn_off",
      entityId: "switch.kitchen"
    )
    try assertRoute(
      "Run automation automation.good_morning with skip condition",
      serviceDomain: "automation",
      service: "trigger",
      entityId: "automation.good_morning",
      serviceData: ["skip_condition": .bool(true)]
    )
    try assertRoute(
      "Run script script.morning",
      serviceDomain: "script",
      service: "turn_on",
      entityId: "script.morning"
    )
    try assertRoute(
      "Activate scene scene.movie",
      serviceDomain: "scene",
      service: "turn_on",
      entityId: "scene.movie"
    )
    try assertRoute(
      "Unlock lock.front_door",
      serviceDomain: "lock",
      service: "unlock",
      entityId: "lock.front_door"
    )
    try assertRoute(
      "Open cover.garage",
      serviceDomain: "cover",
      service: "open_cover",
      entityId: "cover.garage"
    )
    try assertRoute(
      "Close valve.water",
      serviceDomain: "valve",
      service: "close_valve",
      entityId: "valve.water"
    )
    try assertRoute(
      "\u{6253}\u{5f00} light.office",
      serviceDomain: "homeassistant",
      service: "turn_on",
      entityId: "light.office"
    )

    XCTAssertNil(AgentHomeAssistantPromptRouter.serviceCall(for: "Run automation script.morning"))
    XCTAssertNil(AgentHomeAssistantPromptRouter.serviceCall(for: "Turn on the office light"))
    XCTAssertEqual(
      AgentHomeAssistantRiskPolicy.entityId(for: "Turn on the default light", defaultEntityId: "switch.kitchen"),
      "switch.kitchen"
    )
  }
}

private final class TestHomeAssistantRESTTransport: AgentIOSHomeAssistantRESTTransport {
  private var responses: [String: [Data]]
  private(set) var requests: [AgentIOSHomeAssistantHTTPRequest] = []

  var requestKeys: [String] {
    requests.map { "\($0.method.testName) \($0.path)" }
  }

  init(responses: [String: [String]]) {
    self.responses = responses.mapValues { values in
      values.map { Data($0.utf8) }
    }
  }

  func send(_ request: AgentIOSHomeAssistantHTTPRequest, settings: HomeAssistantSettings) throws -> Data {
    guard settings.baseUrl == "http://homeassistant.local:8123",
          settings.accessToken == "ha-token" else {
      throw AgentIOSHomeAssistantRESTError.invalidURL
    }
    requests.append(request)
    let key = "\(request.method.testName) \(request.path)"
    guard var values = responses[key], !values.isEmpty else {
      throw AgentIOSHomeAssistantRESTError.httpStatus(404)
    }
    let data = values.removeFirst()
    responses[key] = values
    return data
  }
}

private extension AgentIOSHomeAssistantHTTPRequest.Method {
  var testName: String {
    switch self {
    case .get:
      return "GET"
    case .post:
      return "POST"
    }
  }
}
