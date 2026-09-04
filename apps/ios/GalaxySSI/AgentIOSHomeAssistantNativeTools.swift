import Foundation

protocol AgentIOSHomeAssistantToolProviding {
  var implementationId: String { get }
  func availability() -> AgentNativeToolAvailability
  func connectionStatus(nowMillis: Int64) -> AgentNativeToolExecutionResult
  func listEntities(query: String, domains: [String], limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult
  func readEntity(entityId: String, nowMillis: Int64) -> AgentNativeToolExecutionResult
  func callService(
    serviceDomain: String,
    service: String,
    entityId: String,
    serviceData: AgentMcpJSONObject,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableHomeAssistantToolProvider: AgentIOSHomeAssistantToolProviding {
  var settings: HomeAssistantSettings
  var implementationId: String

  init(
    settings: HomeAssistantSettings = .default,
    implementationId: String = "galaxyssi.ios.home_assistant_unconfigured"
  ) {
    self.settings = settings.normalized
    self.implementationId = implementationId
  }

  func availability() -> AgentNativeToolAvailability {
    if !settings.credentialsConfigured {
      return AgentNativeToolAvailability(status: .requiresSetup, reason: "Home Assistant URL and access token are not configured")
    }
    if !settings.enabled {
      return AgentNativeToolAvailability(status: .unavailable, reason: "Home Assistant device control is disabled")
    }
    return AgentNativeToolAvailability(status: .requiresSetup, reason: "Home Assistant REST provider is not connected")
  }

  func connectionStatus(nowMillis: Int64) -> AgentNativeToolExecutionResult {
    failure("Home Assistant REST provider is not connected")
  }

  func listEntities(query: String, domains: [String], limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    failure("Home Assistant entity listing provider is not connected")
  }

  func readEntity(entityId: String, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    failure("Home Assistant entity read provider is not connected")
  }

  func callService(
    serviceDomain: String,
    service: String,
    entityId: String,
    serviceData: AgentMcpJSONObject,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    failure("Home Assistant service-call provider is not connected")
  }

  private func failure(_ message: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "home_assistant_provider_unavailable",
      message: message,
      retryable: true
    )
  }
}

enum AgentIOSHomeAssistantNativeToolCatalog {
  static let connectionStatus = "galaxyssi.home_assistant.connection.status"
  static let entitiesList = "galaxyssi.home_assistant.entities.list"
  static let entityRead = "galaxyssi.home_assistant.entity.read"
  static let serviceCall = "galaxyssi.home_assistant.service.call"

  static let networkPermission = "galaxyssi.scope.network_client"
  static let readConsent = "galaxyssi.consent.home_assistant_read"
  static let controlConsent = "galaxyssi.consent.home_assistant_control"
  static let executorId = "galaxyssi.ios_home_assistant_tools"

  static let maxEntityResults = 100
  static let maxServiceDataEntries = 16
  static let maxServiceDataCharacters = 8_192

  static let toolIds: Set<String> = [connectionStatus, entitiesList, entityRead, serviceCall]

  static func definitions(
    provider: AgentIOSHomeAssistantToolProviding = AgentIOSConfiguredHomeAssistantToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    [
      definition(
        provider: provider,
        id: connectionStatus,
        title: "Check Home Assistant connection",
        description: "Checks the configured Home Assistant endpoint without exposing its URL or credentials.",
        inputSchema: objectSchema(),
        risk: .low,
        capabilities: ["smart_home.connection.read", "smart_home.credentials.redacted"],
        consentId: nil,
        idempotency: .idempotent
      ),
      definition(
        provider: provider,
        id: entitiesList,
        title: "List Home Assistant entities",
        description: "Lists bounded configured entities; protected security and presence states remain redacted.",
        inputSchema: objectSchema(properties: [
          "query": stringSchema(maxLength: 200),
          "domains": arraySchema(items: stringSchema(maxLength: 64), maxItems: 16),
          "limit": integerSchema(minimum: 1, maximum: Int64(maxEntityResults))
        ]),
        risk: .medium,
        capabilities: ["smart_home.entities.read", "smart_home.sensitive_state.redaction"],
        consentId: readConsent,
        idempotency: .idempotent
      ),
      definition(
        provider: provider,
        id: entityRead,
        title: "Read one Home Assistant entity",
        description: "Reads one exact entity; protected security and presence state values remain redacted.",
        inputSchema: objectSchema(
          properties: ["entity_id": entityIdSchema()],
          required: ["entity_id"]
        ),
        risk: .medium,
        capabilities: ["smart_home.entity.read", "smart_home.sensitive_state.redaction"],
        consentId: readConsent,
        idempotency: .idempotent
      ),
      definition(
        provider: provider,
        id: serviceCall,
        title: "Call one Home Assistant entity service",
        description: "Calls one bounded entity service with idempotency and controller-state verification when available.",
        inputSchema: objectSchema(
          properties: [
            "service_domain": nameSchema(),
            "service": nameSchema(),
            "entity_id": entityIdSchema(),
            "service_data": objectSchema(additionalProperties: true)
          ],
          required: ["service_domain", "service", "entity_id"]
        ),
        risk: .medium,
        capabilities: ["smart_home.entity.control", "smart_home.single_entity_scope", "smart_home.controller_state.verify"],
        consentId: controlConsent,
        idempotency: .idempotencyKeyRequired
      )
    ]
  }

  private static func definition(
    provider: AgentIOSHomeAssistantToolProviding,
    id: String,
    title: String,
    description: String,
    inputSchema: AgentMcpJSONObject,
    risk: AgentNativeToolRisk,
    capabilities: Set<String>,
    consentId: String?,
    idempotency: AgentNativeToolIdempotency
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: AgentPhoneNativeToolCatalog.version,
      title: title,
      description: description,
      location: .application,
      inputSchema: inputSchema,
      outputSchema: AgentNativeToolDescriptor.objectSchema(),
      risk: risk,
      capabilities: capabilities,
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: networkPermission,
          title: "Network client",
          description: "Allows the app to reach the user-configured Home Assistant server."
        )
      ],
      requiredConsents: consentId.map {
        [AgentNativeConsentRequirement(
          id: $0,
          title: $0 == readConsent ? "Read Home Assistant state" : "Control Home Assistant entity",
          description: $0 == readConsent
            ? "Allows bounded entity metadata and non-protected state reads."
            : "Authorizes this exact Home Assistant entity service call."
        )]
      } ?? [noExtraConsent],
      timeoutMillis: 16_000,
      idempotency: idempotency,
      availability: provider.availability()
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "transport": "home_assistant_rest",
        "credential_storage": "ios_keychain",
        "credential_exposure": "none",
        "base_url_exposed": "false",
        "access_token_exposed": "false",
        "target_scope": "single_entity",
        "result_policy": "bounded-v1"
      ]
    )
  }

  private static func objectSchema(
    properties: [String: AgentMcpJSONObject] = [:],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties.mapValues { .object($0) }),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(maxLength: Int64, pattern: String? = nil, minLength: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("string"),
      "maxLength": .int(maxLength)
    ]
    if let minLength { schema["minLength"] = .int(minLength) }
    if let pattern { schema["pattern"] = .string(pattern) }
    return schema
  }

  private static func nameSchema() -> AgentMcpJSONObject {
    stringSchema(maxLength: 64, pattern: #"^[a-z_][a-z0-9_]*$"#, minLength: 1)
  }

  private static func entityIdSchema() -> AgentMcpJSONObject {
    stringSchema(maxLength: 160, pattern: #"^[a-z_][a-z0-9_]*\.[a-z0-9_]+$"#, minLength: 1)
  }

  private static func integerSchema(minimum: Int64, maximum: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("integer"),
      "minimum": .int(minimum),
      "maximum": .int(maximum)
    ]
  }

  private static func arraySchema(items: AgentMcpJSONObject, maxItems: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(items),
      "maxItems": .int(maxItems)
    ]
  }

  private static let noExtraConsent = AgentNativeConsentRequirement(
    id: "galaxyssi.consent.none",
    title: "No additional consent",
    description: "No additional interactive consent is required.",
    required: false
  )
}

struct AgentIOSHomeAssistantNativeToolExecutor {
  var provider: AgentIOSHomeAssistantToolProviding
  var nowMillis: () -> Int64

  init(
    provider: AgentIOSHomeAssistantToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) {
    self.provider = provider
    self.nowMillis = nowMillis
  }

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    let verifier: ((AgentNativeToolInvocation, AgentNativeToolExecutionResult) throws -> AgentNativeToolVerification?)? =
      definition.id == AgentIOSHomeAssistantNativeToolCatalog.serviceCall
        ? { invocation, execution in try self.verifyServiceCall(invocation, execution) }
        : nil
    return AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = self.execute(invocation)
        try invocation.checkpoint()
        return result
      },
      verifier: verifier
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    let now = max(0, nowMillis())
    switch invocation.descriptor.id {
    case AgentIOSHomeAssistantNativeToolCatalog.connectionStatus:
      return secretSafe(provider.connectionStatus(nowMillis: now))
    case AgentIOSHomeAssistantNativeToolCatalog.entitiesList:
      return secretSafe(provider.listEntities(
        query: string(invocation.input, "query", limit: 200),
        domains: stringArray(invocation.input, "domains", limit: 16),
        limit: int(invocation.input, "limit", defaultValue: 40, minimum: 1, maximum: AgentIOSHomeAssistantNativeToolCatalog.maxEntityResults),
        nowMillis: now
      ))
    case AgentIOSHomeAssistantNativeToolCatalog.entityRead:
      return secretSafe(provider.readEntity(
        entityId: string(invocation.input, "entity_id", limit: 160),
        nowMillis: now
      ))
    case AgentIOSHomeAssistantNativeToolCatalog.serviceCall:
      return serviceCall(invocation, nowMillis: now)
    default:
      return AgentNativeToolExecutionResult.failure(
        code: "home_assistant_unknown_tool",
        message: "Unknown Home Assistant native tool."
      )
    }
  }

  private func serviceCall(_ invocation: AgentNativeToolInvocation, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let serviceDomain = string(invocation.input, "service_domain", limit: 64)
    let service = string(invocation.input, "service", limit: 64)
    let entityId = string(invocation.input, "entity_id", limit: 160)
    let serviceData = invocation.input["service_data"]?.objectValue ?? [:]
    if let failure = validateServiceCall(
      serviceDomain: serviceDomain,
      service: service,
      entityId: entityId,
      serviceData: serviceData
    ) {
      return failure
    }
    return secretSafe(provider.callService(
      serviceDomain: serviceDomain,
      service: service,
      entityId: entityId,
      serviceData: serviceData,
      nowMillis: nowMillis
    ))
  }

  private func verifyServiceCall(
    _ invocation: AgentNativeToolInvocation,
    _ execution: AgentNativeToolExecutionResult
  ) throws -> AgentNativeToolVerification? {
    guard execution.isSuccess else { return nil }
    let accepted = execution.output["request_accepted"]?.boolValue == true
    let supported = execution.output["verification_supported"]?.boolValue == true
    let verified = execution.output["controller_state_verified"]?.boolValue == true
    if !accepted {
      return AgentNativeToolVerification(status: .failed, message: "Home Assistant did not accept the service call")
    }
    if supported && !verified {
      return AgentNativeToolVerification(
        status: .failed,
        message: "Home Assistant controller state did not match the requested deterministic state",
        evidence: ["physical_outcome_verified": .bool(false)]
      )
    }
    if supported {
      return AgentNativeToolVerification(
        status: .passed,
        message: "Home Assistant controller state matched the requested deterministic state",
        evidence: ["controller_state_verified": .bool(true), "physical_outcome_verified": .bool(false)]
      )
    }
    return AgentNativeToolVerification(
      status: .skipped,
      message: "This Home Assistant service has no deterministic entity-state verification",
      evidence: ["request_accepted": .bool(true), "physical_outcome_verified": .bool(false)]
    )
  }

  private func validateServiceCall(
    serviceDomain: String,
    service: String,
    entityId: String,
    serviceData: AgentMcpJSONObject
  ) -> AgentNativeToolExecutionResult? {
    let entityDomain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    if serviceDomain == "homeassistant" && !Self.genericEntityServices.contains(service) {
      return failure("unsupported_core_service", "Only entity-scoped Home Assistant core services are allowed")
    }
    if serviceDomain != "homeassistant" && serviceDomain != entityDomain {
      return failure("domain_mismatch", "Service domain must match the target entity")
    }
    if Self.blockedAdministrativeServices.contains(service) {
      return failure("administrative_service", "Administrative Home Assistant services are not exposed")
    }
    if serviceData.count > AgentIOSHomeAssistantNativeToolCatalog.maxServiceDataEntries {
      return failure("max_properties", "Too many Home Assistant service parameters")
    }
    if AgentMcpJSONCodec.stringify(serviceData).count > AgentIOSHomeAssistantNativeToolCatalog.maxServiceDataCharacters ||
      containsSecretKey(.object(serviceData)) {
      return failure("invalid_service_data", "Home Assistant service data is too large or contains secret-like keys")
    }
    return nil
  }

  private func secretSafe(_ result: AgentNativeToolExecutionResult) -> AgentNativeToolExecutionResult {
    var metadata = result.metadata
    metadata["credentials_exposed"] = .bool(false)
    metadata["base_url_exposed"] = .bool(false)
    metadata["access_token_exposed"] = .bool(false)
    return AgentNativeToolExecutionResult(
      output: result.output,
      message: result.message,
      metadata: metadata,
      error: result.error
    )
  }

  private func failure(_ code: String, _ message: String) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(code: code, message: message, retryable: false)
  }

  private func string(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> String {
    String((input[key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  private func stringArray(_ input: AgentMcpJSONObject, _ key: String, limit: Int) -> [String] {
    Array((input[key]?.arrayValue ?? [])
      .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
      .prefix(limit))
  }

  private func int(_ input: AgentMcpJSONObject, _ key: String, defaultValue: Int, minimum: Int, maximum: Int) -> Int {
    let value = Int(input[key]?.intValue ?? Int64(defaultValue))
    return max(minimum, min(value, maximum))
  }

  private func containsSecretKey(_ value: AgentMcpJSONValue) -> Bool {
    switch value {
    case .object(let object):
      return object.contains { entry in
        Self.secretKeyFragments.contains { entry.key.lowercased().contains($0) } || containsSecretKey(entry.value)
      }
    case .array(let values):
      return values.contains { containsSecretKey($0) }
    case .string, .int, .double, .bool, .null:
      return false
    }
  }

  private static let genericEntityServices: Set<String> = ["turn_on", "turn_off", "toggle"]
  private static let blockedAdministrativeServices: Set<String> = [
    "restart", "stop", "reload_core_config", "check_config", "update_entity"
  ]
  private static let secretKeyFragments = ["password", "passwd", "secret", "token", "authorization", "cookie"]
}
