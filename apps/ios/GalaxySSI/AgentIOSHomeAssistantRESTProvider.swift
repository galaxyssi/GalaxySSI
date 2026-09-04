import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct AgentIOSHomeAssistantHTTPRequest {
  enum Method: Equatable {
    case get
    case post
  }

  var method: Method
  var path: String
  var body: AgentMcpJSONObject
}

protocol AgentIOSHomeAssistantRESTTransport {
  func send(_ request: AgentIOSHomeAssistantHTTPRequest, settings: HomeAssistantSettings) throws -> Data
}

enum AgentIOSHomeAssistantRESTError: Error, Equatable {
  case invalidURL
  case invalidJSONBody
  case httpStatus(Int)
  case timeout
  case emptyResponse
}

struct AgentIOSURLSessionHomeAssistantRESTTransport: AgentIOSHomeAssistantRESTTransport {
  var timeoutSeconds: TimeInterval
  var session: URLSession

  init(
    timeoutSeconds: TimeInterval = 12,
    session: URLSession = .shared
  ) {
    self.timeoutSeconds = max(1, timeoutSeconds)
    self.session = session
  }

  func send(_ request: AgentIOSHomeAssistantHTTPRequest, settings: HomeAssistantSettings) throws -> Data {
    guard let url = URL(string: settings.baseUrl + request.path) else {
      throw AgentIOSHomeAssistantRESTError.invalidURL
    }
    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = timeoutSeconds
    urlRequest.httpMethod = request.method == .get ? "GET" : "POST"
    urlRequest.setValue("Bearer \(settings.accessToken)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
    if request.method == .post {
      let body = Self.jsonObject(request.body)
      guard JSONSerialization.isValidJSONObject(body) else {
        throw AgentIOSHomeAssistantRESTError.invalidJSONBody
      }
      urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
      urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var responseData: Data?
    var responseCode: Int?
    var responseError: Error?
    let task = session.dataTask(with: urlRequest) { data, response, error in
      lock.lock()
      responseData = data
      responseCode = (response as? HTTPURLResponse)?.statusCode
      responseError = error
      lock.unlock()
      semaphore.signal()
    }
    task.resume()
    if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
      task.cancel()
      throw AgentIOSHomeAssistantRESTError.timeout
    }

    lock.lock()
    let data = responseData
    let statusCode = responseCode
    let error = responseError
    lock.unlock()
    if let error {
      throw error
    }
    if let statusCode, !(200...299).contains(statusCode) {
      throw AgentIOSHomeAssistantRESTError.httpStatus(statusCode)
    }
    return data ?? Data()
  }

  private static func jsonObject(_ value: AgentMcpJSONObject) -> [String: Any] {
    value.mapValues(jsonValue)
  }

  private static func jsonValue(_ value: AgentMcpJSONValue) -> Any {
    switch value {
    case .string(let string):
      return string
    case .int(let int):
      return int
    case .double(let double):
      return double
    case .bool(let bool):
      return bool
    case .object(let object):
      return jsonObject(object)
    case .array(let array):
      return array.map(jsonValue)
    case .null:
      return NSNull()
    }
  }
}

struct AgentIOSConfiguredHomeAssistantToolProvider: AgentIOSHomeAssistantToolProviding {
  var settingsProvider: () -> HomeAssistantSettings
  var transport: AgentIOSHomeAssistantRESTTransport
  var implementationId: String
  var stateVerificationRetries: Int
  var stateVerificationRetryDelayMillis: Int

  init(
    settingsProvider: @escaping () -> HomeAssistantSettings = { .default },
    transport: AgentIOSHomeAssistantRESTTransport = AgentIOSURLSessionHomeAssistantRESTTransport(),
    implementationId: String = "galaxyssi.ios.home_assistant_rest",
    stateVerificationRetries: Int = 3,
    stateVerificationRetryDelayMillis: Int = 250
  ) {
    self.settingsProvider = settingsProvider
    self.transport = transport
    self.implementationId = implementationId
    self.stateVerificationRetries = max(0, stateVerificationRetries)
    self.stateVerificationRetryDelayMillis = max(0, stateVerificationRetryDelayMillis)
  }

  func availability() -> AgentNativeToolAvailability {
    let settings = settingsProvider().normalized
    if !settings.credentialsConfigured {
      return AgentNativeToolAvailability(status: .requiresSetup, reason: "Home Assistant URL and access token are not configured")
    }
    if !settings.enabled {
      return AgentNativeToolAvailability(status: .unavailable, reason: "Home Assistant device control is disabled")
    }
    return .available
  }

  func connectionStatus(nowMillis: Int64) -> AgentNativeToolExecutionResult {
    requestResult(nowMillis: nowMillis, requiresEnabled: false) { settings in
      _ = try transport.send(
        AgentIOSHomeAssistantHTTPRequest(method: .get, path: "/api/", body: [:]),
        settings: settings
      )
      return AgentNativeToolExecutionResult.success(
        output: [
          "connected": .bool(true),
          "credentials_exposed": .bool(false),
          "checked_at_epoch_ms": .int(nowMillis)
        ],
        message: "Home Assistant is connected",
        metadata: secretSafeMetadata()
      )
    }
  }

  func listEntities(query: String, domains: [String], limit: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    requestResult(nowMillis: nowMillis) { settings in
      let data = try transport.send(
        AgentIOSHomeAssistantHTTPRequest(method: .get, path: "/api/states", body: [:]),
        settings: settings
      )
      let payload = try jsonArray(data)
      let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let domainFilter = Set(domains.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty })
      let matched = payload.compactMap { try? entity(from: $0) }
        .filter { entity in
          domainFilter.isEmpty || domainFilter.contains(entity.domain)
        }
        .filter { entity in
          guard !cleanQuery.isEmpty else { return true }
          let searchableState = entity.protected ? "" : entity.state
          return "\(entity.entityId) \(entity.friendlyName) \(entity.domain) \(searchableState)"
            .lowercased()
            .contains(cleanQuery)
        }
        .sorted {
          if $0.domain != $1.domain { return $0.domain < $1.domain }
          return $0.friendlyName < $1.friendlyName
        }
      let boundedLimit = max(1, min(limit, AgentIOSHomeAssistantNativeToolCatalog.maxEntityResults))
      let entities = Array(matched.prefix(boundedLimit))
      return AgentNativeToolExecutionResult.success(
        output: [
          "entities": .array(entities.map { .object(entityOutput($0)) }),
          "result_count": .int(Int64(entities.count)),
          "total_matched": .int(Int64(matched.count)),
          "truncated": .bool(matched.count > boundedLimit),
          "observed_at_epoch_ms": .int(nowMillis),
          "protected_state_count": .int(Int64(entities.filter(\.protected).count))
        ],
        message: "Loaded \(entities.count) Home Assistant entities",
        metadata: secretSafeMetadata().merging(["protected_states_redacted": .bool(true)]) { _, next in next }
      )
    }
  }

  func readEntity(entityId: String, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let cleanEntityId = entityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard Self.entityIdPattern.firstMatch(in: cleanEntityId, range: NSRange(cleanEntityId.startIndex..., in: cleanEntityId)) != nil else {
      return failure("invalid_home_assistant_entity", "Invalid Home Assistant entity id", retryable: false)
    }
    return requestResult(nowMillis: nowMillis) { settings in
      let entity = try readEntityState(cleanEntityId, settings: settings)
      return AgentNativeToolExecutionResult.success(
        output: [
          "entity": .object(entityOutput(entity)),
          "observed_at_epoch_ms": .int(nowMillis)
        ],
        message: entity.protected ? "Protected Home Assistant entity state hidden" : "Read Home Assistant entity",
        metadata: secretSafeMetadata().merging(["protected_state_redacted": .bool(entity.protected)]) { _, next in next }
      )
    }
  }

  func callService(
    serviceDomain: String,
    service: String,
    entityId: String,
    serviceData: AgentMcpJSONObject,
    nowMillis: Int64
  ) -> AgentNativeToolExecutionResult {
    let cleanDomain = serviceDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let cleanService = service.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let cleanEntityId = entityId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let invalidReason = validateServiceCall(
      serviceDomain: cleanDomain,
      service: cleanService,
      entityId: cleanEntityId,
      serviceData: serviceData
    ) {
      return AgentNativeToolExecutionResult.failure(
        code: "invalid_home_assistant_service_call",
        message: invalidReason,
        retryable: false
      )
    }

    return requestResult(nowMillis: nowMillis) { settings in
      let entityDomain = cleanEntityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? "unknown"
      let stateProtected = Self.protectedDomains.contains(entityDomain)
      let previousRawState = (try? readRawEntityState(cleanEntityId, settings: settings)) ?? ""
      let expected = expectedState(
        entityDomain: entityDomain,
        service: cleanService,
        previousState: previousRawState,
        serviceData: serviceData
      )
      let body = serviceData.merging(["entity_id": .string(cleanEntityId)]) { _, next in next }
      let data = try transport.send(
        AgentIOSHomeAssistantHTTPRequest(
          method: .post,
          path: "/api/services/\(cleanDomain)/\(cleanService)",
          body: body
        ),
        settings: settings
      )
      let changedStateCount = (try? jsonArray(data).count) ?? 0
      var currentRawState = (try? readRawEntityState(cleanEntityId, settings: settings)) ?? ""
      if let expected, !statesMatch(expected: expected, actual: currentRawState) {
        for _ in 0..<stateVerificationRetries {
          if stateVerificationRetryDelayMillis > 0 {
            Thread.sleep(forTimeInterval: Double(stateVerificationRetryDelayMillis) / 1_000)
          }
          currentRawState = (try? readRawEntityState(cleanEntityId, settings: settings)) ?? ""
          if statesMatch(expected: expected, actual: currentRawState) {
            break
          }
        }
      }
      let controllerStateObserved = !currentRawState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      let controllerStateVerified = expected.map { statesMatch(expected: $0, actual: currentRawState) } ?? false
      return AgentNativeToolExecutionResult.success(
        output: [
          "request_accepted": .bool(true),
          "service_domain": .string(cleanDomain),
          "service": .string(cleanService),
          "entity_id": .string(cleanEntityId),
          "verification_supported": .bool(expected != nil),
          "controller_state_observed": .bool(controllerStateObserved),
          "controller_state_verified": .bool(controllerStateVerified),
          "previous_state": .string(redactState(previousRawState, protected: stateProtected)),
          "current_state": .string(redactState(currentRawState, protected: stateProtected)),
          "state_protected": .bool(stateProtected),
          "changed_state_count": .int(Int64(changedStateCount)),
          "physical_outcome_verified": .bool(false),
          "executed_at_epoch_ms": .int(nowMillis)
        ],
        message: serviceMessage(expected: expected, verified: controllerStateVerified),
        metadata: secretSafeMetadata().merging(["single_entity_scope": .bool(true)]) { _, next in next }
      )
    }
  }

  private func requestResult(
    nowMillis: Int64,
    requiresEnabled: Bool = true,
    body: (HomeAssistantSettings) throws -> AgentNativeToolExecutionResult
  ) -> AgentNativeToolExecutionResult {
    let settings = settingsProvider().normalized
    if !settings.credentialsConfigured {
      return failure("home_assistant_not_configured", "Home Assistant local API is not configured", retryable: false)
    }
    if requiresEnabled && !settings.enabled {
      return failure("home_assistant_disabled", "Home Assistant device control is disabled", retryable: false)
    }
    do {
      return try body(settings)
    } catch {
      return requestFailure(error, nowMillis: nowMillis)
    }
  }

  private func requestFailure(_ error: Error, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let code = requestErrorCode(error)
    return AgentNativeToolExecutionResult.failure(
      code: code,
      message: requestErrorMessage(error),
      retryable: code == "home_assistant_request_failed" || code == "home_assistant_timeout",
      details: ["checked_at_epoch_ms": .int(nowMillis)]
    )
  }

  private func requestErrorCode(_ error: Error) -> String {
    if let restError = error as? AgentIOSHomeAssistantRESTError {
      switch restError {
      case .httpStatus(401), .httpStatus(403):
        return "home_assistant_auth_failed"
      case .httpStatus(404):
        return "home_assistant_not_found"
      case .timeout:
        return "home_assistant_timeout"
      case .invalidURL, .invalidJSONBody, .emptyResponse:
        return "home_assistant_request_failed"
      case .httpStatus:
        return "home_assistant_request_failed"
      }
    }
    let message = String(describing: error)
    if message.contains("401") || message.contains("403") {
      return "home_assistant_auth_failed"
    }
    if message.contains("404") {
      return "home_assistant_not_found"
    }
    return "home_assistant_request_failed"
  }

  private func requestErrorMessage(_ error: Error) -> String {
    if let restError = error as? AgentIOSHomeAssistantRESTError {
      switch restError {
      case .timeout:
        return "Home Assistant request timed out"
      case .httpStatus(let statusCode):
        return "Home Assistant HTTP \(statusCode)"
      case .invalidURL, .invalidJSONBody, .emptyResponse:
        return "Home Assistant request failed"
      }
    }
    return "Home Assistant request failed"
  }

  private func readEntityState(_ entityId: String, settings: HomeAssistantSettings) throws -> AgentIOSHomeAssistantEntityState {
    let data = try transport.send(
      AgentIOSHomeAssistantHTTPRequest(method: .get, path: "/api/states/\(entityId)", body: [:]),
      settings: settings
    )
    return try entity(from: jsonObject(data), expectedEntityId: entityId)
  }

  private func readRawEntityState(_ entityId: String, settings: HomeAssistantSettings) throws -> String {
    try readEntityState(entityId, settings: settings).rawState
  }

  private func jsonObject(_ data: Data) throws -> [String: Any] {
    let value = try JSONSerialization.jsonObject(with: data, options: [])
    guard let object = value as? [String: Any] else {
      throw AgentIOSHomeAssistantRESTError.emptyResponse
    }
    return object
  }

  private func jsonArray(_ data: Data) throws -> [[String: Any]] {
    guard !data.isEmpty else { return [] }
    let value = try JSONSerialization.jsonObject(with: data, options: [])
    guard let array = value as? [[String: Any]] else {
      throw AgentIOSHomeAssistantRESTError.emptyResponse
    }
    return array
  }

  private func entity(
    from object: [String: Any],
    expectedEntityId: String? = nil
  ) throws -> AgentIOSHomeAssistantEntityState {
    let entityId = (expectedEntityId ?? string(object["entity_id"])).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if entityId.isEmpty {
      throw AgentIOSHomeAssistantRESTError.emptyResponse
    }
    let domain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? "unknown"
    let attributes = object["attributes"] as? [String: Any] ?? [:]
    let friendlyName = string(attributes["friendly_name"]).nilIfEmpty ?? entityId
    let rawState = string(object["state"]).nilIfEmpty ?? "unknown"
    let protected = Self.protectedDomains.contains(domain)
    return AgentIOSHomeAssistantEntityState(
      entityId: entityId,
      friendlyName: String(friendlyName.prefix(100)),
      rawState: String(rawState.prefix(Self.maxStateCharacters)),
      state: protected ? "protected" : String(rawState.prefix(Self.maxStateCharacters)),
      domain: domain,
      protected: protected
    )
  }

  private func entityOutput(_ entity: AgentIOSHomeAssistantEntityState) -> AgentMcpJSONObject {
    [
      "entity_id": .string(entity.entityId),
      "friendly_name": .string(entity.friendlyName),
      "state": .string(entity.state),
      "domain": .string(entity.domain),
      "protected": .bool(entity.protected)
    ]
  }

  private func validateServiceCall(
    serviceDomain: String,
    service: String,
    entityId: String,
    serviceData: AgentMcpJSONObject
  ) -> String? {
    if Self.namePattern.firstMatch(in: serviceDomain, range: NSRange(serviceDomain.startIndex..., in: serviceDomain)) == nil {
      return "Invalid Home Assistant service domain"
    }
    if Self.namePattern.firstMatch(in: service, range: NSRange(service.startIndex..., in: service)) == nil {
      return "Invalid Home Assistant service"
    }
    if Self.entityIdPattern.firstMatch(in: entityId, range: NSRange(entityId.startIndex..., in: entityId)) == nil {
      return "Invalid Home Assistant entity id"
    }
    let entityDomain = entityId.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
    if serviceDomain == "homeassistant" && !Self.genericEntityServices.contains(service) {
      return "Unsupported Home Assistant core service"
    }
    if serviceDomain != "homeassistant" && serviceDomain != entityDomain {
      return "Home Assistant service domain must match the target entity"
    }
    if Self.blockedAdministrativeServices.contains(service) {
      return "Administrative Home Assistant services are not exposed"
    }
    if serviceData.count > AgentIOSHomeAssistantNativeToolCatalog.maxServiceDataEntries {
      return "Home Assistant service data is too large"
    }
    if !boundedServiceData(.object(serviceData)) ||
      AgentMcpJSONCodec.stringify(serviceData).count > AgentIOSHomeAssistantNativeToolCatalog.maxServiceDataCharacters {
      return "Home Assistant service data is not a bounded JSON object"
    }
    return nil
  }

  private func boundedServiceData(_ value: AgentMcpJSONValue, depth: Int = 0) -> Bool {
    guard depth <= Self.maxServiceDataDepth else { return false }
    switch value {
    case .null, .bool, .int, .double:
      return true
    case .string(let string):
      return string.count <= Self.maxServiceValueCharacters
    case .array(let array):
      return array.count <= Self.maxServiceArrayItems && array.allSatisfy { boundedServiceData($0, depth: depth + 1) }
    case .object(let object):
      guard object.count <= AgentIOSHomeAssistantNativeToolCatalog.maxServiceDataEntries else { return false }
      return object.allSatisfy { key, nested in
        Self.namePattern.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil &&
          !Self.secretParameterNames.contains(key) &&
          boundedServiceData(nested, depth: depth + 1)
      }
    }
  }

  private func expectedState(
    entityDomain: String,
    service: String,
    previousState: String,
    serviceData: AgentMcpJSONObject
  ) -> String? {
    let expected: String?
    switch service {
    case "turn_on":
      expected = Self.binaryTurnStateDomains.contains(entityDomain) ? "on" : nil
    case "turn_off":
      expected = Self.binaryTurnStateDomains.contains(entityDomain) || entityDomain == "climate" ? "off" : nil
    case "lock":
      expected = "locked"
    case "unlock":
      expected = "unlocked"
    case "open_cover", "open_valve":
      expected = "open"
    case "close_cover", "close_valve":
      expected = "closed"
    case "toggle":
      switch previousState.lowercased() {
      case "on":
        expected = "off"
      case "off":
        expected = "on"
      case "locked":
        expected = "unlocked"
      case "unlocked":
        expected = "locked"
      case "open":
        expected = "closed"
      case "closed":
        expected = "open"
      default:
        expected = nil
      }
    case "set_hvac_mode":
      expected = serviceData["hvac_mode"]?.stringValue
    case "select_option":
      expected = serviceData["option"]?.stringValue
    case "set_value":
      expected = serviceData["value"]?.stringValue
    default:
      expected = nil
    }
    return expected?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map {
      String($0.prefix(Self.maxStateCharacters))
    }
  }

  private func statesMatch(expected: String, actual: String) -> Bool {
    let cleanActual = actual.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanActual.isEmpty else { return false }
    if let expectedNumber = Double(expected), let actualNumber = Double(cleanActual) {
      return abs(expectedNumber - actualNumber) < 0.0001
    }
    return expected.caseInsensitiveCompare(cleanActual) == .orderedSame
  }

  private func redactState(_ state: String, protected: Bool) -> String {
    if state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return ""
    }
    return protected ? "protected" : String(state.prefix(Self.maxStateCharacters))
  }

  private func serviceMessage(expected: String?, verified: Bool) -> String {
    if verified {
      return "Home Assistant accepted the service call and controller state matched"
    }
    if expected != nil {
      return "Home Assistant accepted the service call, but controller state did not match yet"
    }
    return "Home Assistant accepted the service call"
  }

  private func secretSafeMetadata() -> AgentMcpJSONObject {
    [
      "credentials_exposed": .bool(false),
      "base_url_exposed": .bool(false),
      "access_token_exposed": .bool(false)
    ]
  }

  private func failure(_ code: String, _ message: String, retryable: Bool) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(code: code, message: message, retryable: retryable)
  }

  private func string(_ value: Any?) -> String {
    switch value {
    case let string as String:
      return string
    case let number as NSNumber:
      return number.stringValue
    case .some(let value):
      return String(describing: value)
    case .none:
      return ""
    }
  }

  private static let maxStateCharacters = 100
  private static let maxServiceDataDepth = 2
  private static let maxServiceArrayItems = 32
  private static let maxServiceValueCharacters = 256
  private static let namePattern = try! NSRegularExpression(pattern: #"^[a-z_][a-z0-9_]*$"#)
  private static let entityIdPattern = try! NSRegularExpression(pattern: #"^[a-z_][a-z0-9_]*\.[a-z0-9_]+$"#)
  private static let genericEntityServices: Set<String> = ["turn_on", "turn_off", "toggle"]
  private static let binaryTurnStateDomains: Set<String> = [
    "automation",
    "fan",
    "input_boolean",
    "light",
    "media_player",
    "siren",
    "switch"
  ]
  private static let protectedDomains: Set<String> = ["alarm_control_panel", "binary_sensor", "camera", "device_tracker", "lock", "person"]
  private static let blockedAdministrativeServices: Set<String> = [
    "check_config",
    "clear",
    "delete",
    "purge",
    "reload",
    "reload_core_config",
    "remove",
    "restart",
    "stop",
    "update_entity"
  ]
  private static let secretParameterNames: Set<String> = [
    "access_token",
    "api_key",
    "authorization",
    "code",
    "cookie",
    "password",
    "pin",
    "secret",
    "token"
  ]
}

private struct AgentIOSHomeAssistantEntityState {
  var entityId: String
  var friendlyName: String
  var rawState: String
  var state: String
  var domain: String
  var protected: Bool
}
