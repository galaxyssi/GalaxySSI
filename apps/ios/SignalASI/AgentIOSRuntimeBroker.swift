import CryptoKit
import Foundation
import Network

struct AgentIOSRuntimeBrokerConfiguration: Codable, Equatable {
  static let defaultHost = "127.0.0.1"
  static let defaultPort = 39_761
  static let maximumPort = 65_535

  var enabled: Bool
  var host: String
  var port: Int

  static let `default` = AgentIOSRuntimeBrokerConfiguration(
    enabled: false,
    host: defaultHost,
    port: defaultPort
  )

  func validated() throws -> AgentIOSRuntimeBrokerConfiguration {
    let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleanHost == Self.defaultHost else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration(
        "The runtime broker must use the local loopback address."
      )
    }
    guard (1...Self.maximumPort).contains(port) else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The runtime broker port is invalid.")
    }
    return AgentIOSRuntimeBrokerConfiguration(enabled: enabled, host: cleanHost, port: port)
  }
}

final class AgentIOSRuntimeBrokerConfigurationStore {
  static let configurationKey = "signalasi.ios_runtime_broker.configuration.v1"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> AgentIOSRuntimeBrokerConfiguration {
    guard let data = defaults.data(forKey: Self.configurationKey),
          let configuration = try? JSONDecoder().decode(AgentIOSRuntimeBrokerConfiguration.self, from: data),
          let valid = try? configuration.validated() else {
      return .default
    }
    return valid
  }

  func save(_ configuration: AgentIOSRuntimeBrokerConfiguration) throws {
    let valid = try configuration.validated()
    defaults.set(try JSONEncoder().encode(valid), forKey: Self.configurationKey)
  }
}

struct AgentIOSRuntimeBrokerCredentials {
  static let sessionKeyAccount = "signalasi.ios_runtime_broker.session_key.v1"

  var secretStore: SignalASISecretStore = KeychainSecretStore.shared

  func sessionKey() -> Data? {
    guard let raw = secretStore.string(account: Self.sessionKeyAccount),
          let decoded = Data(base64Encoded: raw),
          decoded.count >= 32 else {
      return nil
    }
    return decoded
  }

  func storeSessionKey(base64Encoded value: String) throws {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let decoded = Data(base64Encoded: clean), decoded.count >= 32 else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration(
        "The runtime broker pairing key must be Base64 and at least 32 bytes."
      )
    }
    try secretStore.setString(decoded.base64EncodedString(), account: Self.sessionKeyAccount)
  }

  func clearSessionKey() {
    secretStore.delete(account: Self.sessionKeyAccount)
  }
}

enum AgentIOSRuntimeBrokerError: LocalizedError {
  case disabled
  case pairingRequired
  case invalidConfiguration(String)
  case timeout
  case transport(String)
  case malformedResponse
  case authenticationFailed
  case remote(code: String, message: String, retryable: Bool)

  var errorDescription: String? {
    switch self {
    case .disabled:
      return "The local iOS runtime broker is disabled."
    case .pairingRequired:
      return "Pair this device with the local iOS runtime broker first."
    case .invalidConfiguration(let message), .transport(let message):
      return message
    case .timeout:
      return "The local iOS runtime broker did not respond in time."
    case .malformedResponse:
      return "The local iOS runtime broker returned an invalid response."
    case .authenticationFailed:
      return "The local iOS runtime broker response could not be authenticated."
    case .remote(_, let message, _):
      return message
    }
  }

  var code: String {
    switch self {
    case .disabled:
      return "runtime_broker_disabled"
    case .pairingRequired:
      return "runtime_broker_pairing_required"
    case .invalidConfiguration:
      return "runtime_broker_invalid_configuration"
    case .timeout:
      return "runtime_broker_timeout"
    case .transport:
      return "runtime_broker_transport_failed"
    case .malformedResponse:
      return "runtime_broker_malformed_response"
    case .authenticationFailed:
      return "runtime_broker_authentication_failed"
    case .remote(let code, _, _):
      return code
    }
  }

  var retryable: Bool {
    switch self {
    case .disabled, .pairingRequired, .invalidConfiguration, .malformedResponse, .authenticationFailed:
      return false
    case .timeout, .transport:
      return true
    case .remote(_, _, let retryable):
      return retryable
    }
  }
}

protocol AgentIOSRuntimeBrokerTransport {
  func exchange(
    frame: Data,
    host: String,
    port: UInt16,
    timeoutMillis: Int64
  ) throws -> Data
}

final class AgentIOSLoopbackRuntimeBrokerTransport: AgentIOSRuntimeBrokerTransport {
  func exchange(
    frame: Data,
    host: String,
    port: UInt16,
    timeoutMillis: Int64
  ) throws -> Data {
    guard host == AgentIOSRuntimeBrokerConfiguration.defaultHost,
          let endpointPort = NWEndpoint.Port(rawValue: port) else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The runtime broker endpoint is invalid.")
    }
    guard frame.count <= AgentIOSRuntimeBrokerClient.maximumFrameBytes else {
      throw AgentIOSRuntimeBrokerError.invalidConfiguration("The runtime broker request is too large.")
    }
    let connection = NWConnection(
      host: NWEndpoint.Host(host),
      port: endpointPort,
      using: .tcp
    )
    let queue = DispatchQueue(label: "com.signalasi.ios.runtime-broker", qos: .userInitiated)
    connection.start(queue: queue)
    defer { connection.cancel() }

    let boundedTimeout = min(Int64(30_000), max(Int64(250), timeoutMillis))
    let timeout = DispatchTime.now() + .milliseconds(Int(boundedTimeout))
    try send(framePrefix(frame) + frame, through: connection, timeout: timeout)
    let header = try receive(exactly: 4, through: connection, timeout: timeout)
    let responseLength = header.reduce(0) { ($0 << 8) | Int($1) }
    guard (1...AgentIOSRuntimeBrokerClient.maximumFrameBytes).contains(responseLength) else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    return try receive(exactly: responseLength, through: connection, timeout: timeout)
  }

  private func send(_ data: Data, through connection: NWConnection, timeout: DispatchTime) throws {
    let signal = DispatchSemaphore(value: 0)
    var failure: Error?
    connection.send(content: data, completion: .contentProcessed { error in
      failure = error
      signal.signal()
    })
    guard signal.wait(timeout: timeout) == .success else {
      throw AgentIOSRuntimeBrokerError.timeout
    }
    if let failure {
      throw AgentIOSRuntimeBrokerError.transport(failure.localizedDescription)
    }
  }

  private func receive(exactly length: Int, through connection: NWConnection, timeout: DispatchTime) throws -> Data {
    let signal = DispatchSemaphore(value: 0)
    var received: Data?
    var failure: NWError?
    connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
      received = data
      failure = error
      signal.signal()
    }
    guard signal.wait(timeout: timeout) == .success else {
      throw AgentIOSRuntimeBrokerError.timeout
    }
    if let failure {
      throw AgentIOSRuntimeBrokerError.transport(failure.localizedDescription)
    }
    guard let received, received.count == length else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    return received
  }

  private func framePrefix(_ frame: Data) -> Data {
    let length = UInt32(frame.count).bigEndian
    return withUnsafeBytes(of: length) { Data($0) }
  }
}

protocol AgentIOSRuntimeBrokerProviding {
  var implementationId: String { get }
  func availability() -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    deadlineEpochMillis: Int64
  ) throws -> AgentMcpJSONObject
}

struct AgentIOSRuntimeBrokerClient: AgentIOSRuntimeBrokerProviding {
  static let protocolVersion: Int64 = 1
  static let maximumFrameBytes = 1_048_576

  var implementationId: String = "signalasi.ios_runtime_broker.loopback_v1"
  var configurationStore: AgentIOSRuntimeBrokerConfigurationStore
  var credentials: AgentIOSRuntimeBrokerCredentials
  var transport: AgentIOSRuntimeBrokerTransport
  var nowMillis: () -> Int64
  var requestId: () -> String

  init(
    configurationStore: AgentIOSRuntimeBrokerConfigurationStore = AgentIOSRuntimeBrokerConfigurationStore(),
    credentials: AgentIOSRuntimeBrokerCredentials = AgentIOSRuntimeBrokerCredentials(),
    transport: AgentIOSRuntimeBrokerTransport = AgentIOSLoopbackRuntimeBrokerTransport(),
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    requestId: @escaping () -> String = { UUID().uuidString }
  ) {
    self.configurationStore = configurationStore
    self.credentials = credentials
    self.transport = transport
    self.nowMillis = nowMillis
    self.requestId = requestId
  }

  func availability() -> AgentNativeToolAvailability {
    let configuration = configurationStore.load()
    guard configuration.enabled else {
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Enable and pair the local iOS runtime broker."
      )
    }
    guard credentials.sessionKey() != nil else {
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: "Pair this device with the local iOS runtime broker."
      )
    }
    return .available
  }

  func invoke(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    deadlineEpochMillis: Int64
  ) throws -> AgentMcpJSONObject {
    let configuration = try configurationStore.load().validated()
    guard configuration.enabled else { throw AgentIOSRuntimeBrokerError.disabled }
    guard let keyData = credentials.sessionKey() else { throw AgentIOSRuntimeBrokerError.pairingRequired }
    let now = max(0, nowMillis())
    let timeout = brokerTimeout(operation: operation, deadlineEpochMillis: deadlineEpochMillis, nowMillis: now)
    let request = signedRequest(
      operation: operation,
      input: input,
      context: context,
      nowMillis: now,
      sessionKey: keyData
    )
    let payload = Data(AgentMcpJSONCodec.stringify(request).utf8)
    let responseData = try transport.exchange(
      frame: payload,
      host: configuration.host,
      port: UInt16(configuration.port),
      timeoutMillis: timeout
    )
    guard let response = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: responseData) else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    try verify(response: response, sessionKey: keyData, nowMillis: now)
    guard response["ok"]?.boolValue == true else {
      let error = response["error"]?.objectValue ?? [:]
      throw AgentIOSRuntimeBrokerError.remote(
        code: error["code"]?.stringValue?.nonEmpty ?? "runtime_broker_failed",
        message: error["message"]?.stringValue?.nonEmpty ?? "The local iOS runtime broker rejected the request.",
        retryable: error["retryable"]?.boolValue ?? false
      )
    }
    guard let result = response["result"]?.objectValue else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    return result
  }

  private func signedRequest(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    nowMillis: Int64,
    sessionKey: Data
  ) -> AgentMcpJSONObject {
    var request: AgentMcpJSONObject = [
      "protocol_version": .int(Self.protocolVersion),
      "request_id": .string(requestId()),
      "operation": .string(operation.rawValue),
      "input": .object(input),
      "context": .object([
        "invocation_id": .string(context.invocationId),
        "conversation_id": .string(context.conversationId),
        "turn_id": .string(context.turnId),
        "workspace_id": .string(context.attributes["workspace_id"] ?? context.conversationId.ifBlank(context.invocationId))
      ]),
      "timestamp_epoch_ms": .int(nowMillis)
    ]
    request["mac"] = .string(mac(for: request, sessionKey: sessionKey))
    return request
  }

  private func verify(response: AgentMcpJSONObject, sessionKey: Data, nowMillis: Int64) throws {
    guard response["protocol_version"]?.intValue == Self.protocolVersion,
          let timestamp = response["timestamp_epoch_ms"]?.intValue,
          abs(timestamp - nowMillis) <= 5 * 60_000,
          let supplied = response["mac"]?.stringValue,
          let suppliedData = Data(base64Encoded: supplied) else {
      throw AgentIOSRuntimeBrokerError.malformedResponse
    }
    var unsigned = response
    unsigned.removeValue(forKey: "mac")
    guard constantTimeEquals(suppliedData, Data(base64Encoded: mac(for: unsigned, sessionKey: sessionKey)) ?? Data()) else {
      throw AgentIOSRuntimeBrokerError.authenticationFailed
    }
  }

  private func mac(for object: AgentMcpJSONObject, sessionKey: Data) -> String {
    let key = SymmetricKey(data: sessionKey)
    let payload = Data(AgentMcpJSONCodec.stringify(object).utf8)
    return Data(HMAC<SHA256>.authenticationCode(for: payload, using: key)).base64EncodedString()
  }

  private func constantTimeEquals(_ left: Data, _ right: Data) -> Bool {
    guard left.count == right.count else { return false }
    return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }

  private func brokerTimeout(
    operation: AgentIOSOnDeviceRuntimeToolOperation,
    deadlineEpochMillis: Int64,
    nowMillis: Int64
  ) -> Int64 {
    let configured: Int64 = operation == .execute ? 30 * 60_000 : 15_000
    let remaining = deadlineEpochMillis > nowMillis ? deadlineEpochMillis - nowMillis : configured
    return min(configured, max(250, remaining))
  }
}
