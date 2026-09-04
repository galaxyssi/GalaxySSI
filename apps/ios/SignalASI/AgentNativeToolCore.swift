import CryptoKit
import Foundation

enum AgentNativeToolLocation: String, Codable, CaseIterable, Identifiable {
  case phone
  case desktop
  case application
  case androidSystem = "android_system"
  case accessibilityService = "accessibility_service"
  case unknown

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentNativeToolLocation {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .unknown
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentNativeToolRisk: String, Codable, CaseIterable, Identifiable {
  case low
  case medium
  case high
  case blocked

  var id: String { rawValue }

  var weight: Int {
    switch self {
    case .low: return 1
    case .medium: return 2
    case .high: return 3
    case .blocked: return 4
    }
  }

  static func fromWireValue(_ value: String?) -> AgentNativeToolRisk {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .medium
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentNativeToolIdempotency: String, Codable, CaseIterable, Identifiable {
  case nonIdempotent = "non_idempotent"
  case idempotent
  case idempotencyKeyRequired = "idempotency_key_required"

  var id: String { rawValue }
}

enum AgentNativeToolAvailabilityStatus: String, Codable, CaseIterable, Identifiable {
  case available
  case requiresSetup = "requires_setup"
  case unavailable

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentNativeToolAvailabilityStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .unavailable
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentNativeToolAvailability: Codable, Equatable {
  var status: AgentNativeToolAvailabilityStatus
  var reason: String
  var checkedAtEpochMillis: Int64?

  static let available = AgentNativeToolAvailability(status: .available)

  init(
    status: AgentNativeToolAvailabilityStatus,
    reason: String = "",
    checkedAtEpochMillis: Int64? = nil
  ) {
    self.status = status
    self.reason = reason
    self.checkedAtEpochMillis = checkedAtEpochMillis
  }

  enum CodingKeys: String, CodingKey {
    case status
    case reason
    case checkedAtEpochMillis = "checked_at_epoch_millis"
  }
}

struct AgentNativePermissionRequirement: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var description: String
  var required: Bool

  init(
    id: String,
    title: String? = nil,
    description: String = "",
    required: Bool = true
  ) {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.id = cleanId
    self.title = (title ?? cleanId).trimmingCharacters(in: .whitespacesAndNewlines)
    self.description = description
    self.required = required
  }
}

struct AgentNativeConsentRequirement: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var description: String
  var required: Bool

  init(
    id: String,
    title: String? = nil,
    description: String = "",
    required: Bool = true
  ) {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.id = cleanId
    self.title = (title ?? cleanId).trimmingCharacters(in: .whitespacesAndNewlines)
    self.description = description
    self.required = required
  }
}

struct AgentNativeToolDescriptor: Codable, Equatable, Identifiable {
  static let defaultTimeoutMillis: Int64 = 30_000

  var id: String
  var version: String
  var title: String
  var description: String
  var location: AgentNativeToolLocation
  var inputSchema: AgentMcpJSONObject
  var outputSchema: AgentMcpJSONObject
  var risk: AgentNativeToolRisk
  var capabilities: Set<String>
  var requiredPermissions: [AgentNativePermissionRequirement]
  var requiredConsents: [AgentNativeConsentRequirement]
  var timeoutMillis: Int64
  var idempotency: AgentNativeToolIdempotency
  var availability: AgentNativeToolAvailability

  init(
    id: String,
    version: String,
    title: String,
    description: String,
    location: AgentNativeToolLocation,
    inputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    outputSchema: AgentMcpJSONObject = AgentNativeToolDescriptor.objectSchema(),
    risk: AgentNativeToolRisk,
    capabilities: Set<String> = [],
    requiredPermissions: [AgentNativePermissionRequirement] = [],
    requiredConsents: [AgentNativeConsentRequirement] = [],
    timeoutMillis: Int64 = AgentNativeToolDescriptor.defaultTimeoutMillis,
    idempotency: AgentNativeToolIdempotency = .nonIdempotent,
    availability: AgentNativeToolAvailability = .available
  ) throws {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleanId.range(
      of: #"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$"#,
      options: .regularExpression
    ) != nil else {
      throw AgentRuntimeCapabilityError.invalid("Tool id must be a stable lowercase dotted identifier")
    }
    guard version.range(
      of: #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$"#,
      options: .regularExpression
    ) != nil else {
      throw AgentRuntimeCapabilityError.invalid("Tool version must be semantic")
    }
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("Tool title must not be blank")
    }
    guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("Tool description must not be blank")
    }
    guard timeoutMillis > 0 else {
      throw AgentRuntimeCapabilityError.invalid("Tool timeout must be positive")
    }
    guard capabilities.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      throw AgentRuntimeCapabilityError.invalid("Capability ids must not be blank")
    }
    guard Set(requiredPermissions.map(\.id)).count == requiredPermissions.count else {
      throw AgentRuntimeCapabilityError.invalid("Permission ids must be unique")
    }
    guard Set(requiredConsents.map(\.id)).count == requiredConsents.count else {
      throw AgentRuntimeCapabilityError.invalid("Consent ids must be unique")
    }

    self.id = cleanId
    self.version = version
    self.title = title
    self.description = description
    self.location = location
    self.inputSchema = inputSchema
    self.outputSchema = outputSchema
    self.risk = risk
    self.capabilities = capabilities
    self.requiredPermissions = requiredPermissions
    self.requiredConsents = requiredConsents
    self.timeoutMillis = timeoutMillis
    self.idempotency = idempotency
    self.availability = availability
  }

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case title
    case description
    case location
    case inputSchema = "input_schema"
    case outputSchema = "output_schema"
    case risk
    case capabilities
    case requiredPermissions = "required_permissions"
    case requiredConsents = "required_consents"
    case timeoutMillis = "timeout_millis"
    case idempotency
    case availability
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      version: try container.decodeIfPresent(String.self, forKey: .version) ?? "0.0.0",
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
      location: try container.decodeIfPresent(AgentNativeToolLocation.self, forKey: .location) ?? .unknown,
      inputSchema: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .inputSchema) ?? Self.objectSchema(),
      outputSchema: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .outputSchema) ?? Self.objectSchema(),
      risk: try container.decodeIfPresent(AgentNativeToolRisk.self, forKey: .risk) ?? .medium,
      capabilities: try container.decodeIfPresent(Set<String>.self, forKey: .capabilities) ?? [],
      requiredPermissions: try container.decodeIfPresent([AgentNativePermissionRequirement].self, forKey: .requiredPermissions) ?? [],
      requiredConsents: try container.decodeIfPresent([AgentNativeConsentRequirement].self, forKey: .requiredConsents) ?? [],
      timeoutMillis: try container.decodeIfPresent(Int64.self, forKey: .timeoutMillis) ?? Self.defaultTimeoutMillis,
      idempotency: try container.decodeIfPresent(AgentNativeToolIdempotency.self, forKey: .idempotency) ?? .nonIdempotent,
      availability: try container.decodeIfPresent(AgentNativeToolAvailability.self, forKey: .availability) ?? .available
    )
  }

  static func objectSchema() -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object([:]),
      "required": .array([]),
      "additionalProperties": .bool(true)
    ]
  }
}

enum AgentNativeVerificationStatus: String, Codable, CaseIterable, Identifiable {
  case passed
  case failed
  case skipped

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentNativeVerificationStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .skipped
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentNativeToolVerification: Codable, Equatable {
  var status: AgentNativeVerificationStatus
  var message: String
  var evidence: AgentMcpJSONObject

  init(
    status: AgentNativeVerificationStatus,
    message: String = "",
    evidence: AgentMcpJSONObject = [:]
  ) {
    self.status = status
    self.message = message
    self.evidence = evidence
  }

  enum CodingKeys: String, CodingKey {
    case status
    case message
    case evidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      status: try container.decodeIfPresent(AgentNativeVerificationStatus.self, forKey: .status) ?? .skipped,
      message: try container.decodeIfPresent(String.self, forKey: .message) ?? "",
      evidence: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .evidence) ?? [:]
    )
  }
}

struct AgentNativeToolError: Codable, Equatable {
  var code: String
  var message: String
  var retryable: Bool
  var details: AgentMcpJSONObject

  init(
    code: String,
    message: String,
    retryable: Bool = false,
    details: AgentMcpJSONObject = [:]
  ) {
    self.code = code
    self.message = message
    self.retryable = retryable
    self.details = details
  }

  enum CodingKeys: String, CodingKey {
    case code
    case message
    case retryable
    case details
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      code: try container.decodeIfPresent(String.self, forKey: .code) ?? "",
      message: try container.decodeIfPresent(String.self, forKey: .message) ?? "",
      retryable: try container.decodeIfPresent(Bool.self, forKey: .retryable) ?? false,
      details: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .details) ?? [:]
    )
  }
}

struct AgentNativeToolProvenance: Codable, Equatable {
  var toolId: String
  var toolVersion: String
  var location: AgentNativeToolLocation
  var executorId: String
  var contractVersion: String
  var legacyAgentActionId: String?
  var metadata: [String: String]

  init(
    toolId: String,
    toolVersion: String,
    location: AgentNativeToolLocation,
    executorId: String,
    contractVersion: String,
    legacyAgentActionId: String? = nil,
    metadata: [String: String] = [:]
  ) {
    self.toolId = toolId
    self.toolVersion = toolVersion
    self.location = location
    self.executorId = executorId
    self.contractVersion = contractVersion
    self.legacyAgentActionId = legacyAgentActionId
    self.metadata = metadata
  }

  enum CodingKeys: String, CodingKey {
    case toolId = "tool_id"
    case toolVersion = "tool_version"
    case location
    case executorId = "executor_id"
    case contractVersion = "contract_version"
    case legacyAgentActionId = "legacy_agent_action_id"
    case metadata
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      toolId: container.decode(String.self, forKey: .toolId),
      toolVersion: container.decode(String.self, forKey: .toolVersion),
      location: container.decodeIfPresent(AgentNativeToolLocation.self, forKey: .location) ?? .unknown,
      executorId: container.decodeIfPresent(String.self, forKey: .executorId) ?? "",
      contractVersion: container.decodeIfPresent(String.self, forKey: .contractVersion) ?? "",
      legacyAgentActionId: container.decodeIfPresent(String.self, forKey: .legacyAgentActionId),
      metadata: container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    )
  }
}

enum AgentNativeToolResultStatus: String, Codable, CaseIterable, Identifiable {
  case succeeded
  case failed
  case verificationFailed = "verification_failed"
  case rejected
  case unavailable
  case cancelled
  case timedOut = "timed_out"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentNativeToolResultStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .failed
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentNativeToolReceipt: Codable, Equatable {
  var invocationId: String
  var idempotencyKey: String?
  var startedAtEpochMillis: Int64
  var finishedAtEpochMillis: Int64
  var durationMillis: Int64
  var status: AgentNativeToolResultStatus
  var inputSha256: String
  var outputSha256: String
  var replayed: Bool
  var originalInvocationId: String?

  init(
    invocationId: String,
    idempotencyKey: String? = nil,
    startedAtEpochMillis: Int64,
    finishedAtEpochMillis: Int64,
    durationMillis: Int64,
    status: AgentNativeToolResultStatus,
    inputSha256: String,
    outputSha256: String,
    replayed: Bool = false,
    originalInvocationId: String? = nil
  ) {
    self.invocationId = invocationId
    self.idempotencyKey = idempotencyKey
    self.startedAtEpochMillis = startedAtEpochMillis
    self.finishedAtEpochMillis = finishedAtEpochMillis
    self.durationMillis = durationMillis
    self.status = status
    self.inputSha256 = inputSha256
    self.outputSha256 = outputSha256
    self.replayed = replayed
    self.originalInvocationId = originalInvocationId
  }

  enum CodingKeys: String, CodingKey {
    case invocationId = "invocation_id"
    case idempotencyKey = "idempotency_key"
    case startedAtEpochMillis = "started_at_epoch_ms"
    case finishedAtEpochMillis = "finished_at_epoch_ms"
    case durationMillis = "duration_ms"
    case status
    case inputSha256 = "input_sha256"
    case outputSha256 = "output_sha256"
    case replayed
    case originalInvocationId = "original_invocation_id"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      invocationId: container.decode(String.self, forKey: .invocationId),
      idempotencyKey: container.decodeIfPresent(String.self, forKey: .idempotencyKey),
      startedAtEpochMillis: container.decodeIfPresent(Int64.self, forKey: .startedAtEpochMillis) ?? 0,
      finishedAtEpochMillis: container.decodeIfPresent(Int64.self, forKey: .finishedAtEpochMillis) ?? 0,
      durationMillis: container.decodeIfPresent(Int64.self, forKey: .durationMillis) ?? 0,
      status: container.decodeIfPresent(AgentNativeToolResultStatus.self, forKey: .status) ?? .failed,
      inputSha256: container.decodeIfPresent(String.self, forKey: .inputSha256) ?? "",
      outputSha256: container.decodeIfPresent(String.self, forKey: .outputSha256) ?? "",
      replayed: container.decodeIfPresent(Bool.self, forKey: .replayed) ?? false,
      originalInvocationId: container.decodeIfPresent(String.self, forKey: .originalInvocationId)
    )
  }
}

struct AgentNativeToolResult: Codable, Equatable {
  var status: AgentNativeToolResultStatus
  var output: AgentMcpJSONObject
  var message: String
  var metadata: AgentMcpJSONObject
  var error: AgentNativeToolError?
  var verification: AgentNativeToolVerification?
  var receipt: AgentNativeToolReceipt
  var provenance: AgentNativeToolProvenance

  var isSuccess: Bool { status == .succeeded }

  init(
    status: AgentNativeToolResultStatus,
    output: AgentMcpJSONObject,
    message: String,
    metadata: AgentMcpJSONObject = [:],
    error: AgentNativeToolError? = nil,
    verification: AgentNativeToolVerification? = nil,
    receipt: AgentNativeToolReceipt,
    provenance: AgentNativeToolProvenance
  ) {
    self.status = status
    self.output = output
    self.message = message
    self.metadata = metadata
    self.error = error
    self.verification = verification
    self.receipt = receipt
    self.provenance = provenance
  }

  enum CodingKeys: String, CodingKey {
    case status
    case output
    case message
    case metadata
    case error
    case verification
    case receipt
    case provenance
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      status: container.decodeIfPresent(AgentNativeToolResultStatus.self, forKey: .status) ?? .failed,
      output: container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .output) ?? [:],
      message: container.decodeIfPresent(String.self, forKey: .message) ?? "",
      metadata: container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .metadata) ?? [:],
      error: container.decodeIfPresent(AgentNativeToolError.self, forKey: .error),
      verification: container.decodeIfPresent(AgentNativeToolVerification.self, forKey: .verification),
      receipt: container.decode(AgentNativeToolReceipt.self, forKey: .receipt),
      provenance: container.decode(AgentNativeToolProvenance.self, forKey: .provenance)
    )
  }

  func toJson() -> String {
    AgentMcpJSONCodec.stringify(toJSONObject())
  }

  func toJsonValue() -> AgentMcpJSONValue {
    .object(toJSONObject())
  }

  func toJSONObject() -> AgentMcpJSONObject {
    [
      "status": .string(status.rawValue),
      "output": .object(output),
      "message": .string(message),
      "metadata": .object(metadata),
      "error": error.map { .object($0.toJSONObject()) } ?? .null,
      "verification": verification.map { .object($0.toJSONObject()) } ?? .null,
      "receipt": .object(receipt.toJSONObject()),
      "provenance": .object(provenance.toJSONObject())
    ]
  }

  static func fromJSONObject(_ object: AgentMcpJSONObject) -> AgentNativeToolResult? {
    let raw = AgentMcpJSONCodec.stringify(object)
    guard let data = raw.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode(AgentNativeToolResult.self, from: data)
  }
}

private extension AgentNativeToolError {
  func toJSONObject() -> AgentMcpJSONObject {
    [
      "code": .string(code),
      "message": .string(message),
      "retryable": .bool(retryable),
      "details": .object(details)
    ]
  }
}

private extension AgentNativeToolVerification {
  func toJSONObject() -> AgentMcpJSONObject {
    [
      "status": .string(status.rawValue),
      "message": .string(message),
      "evidence": .object(evidence)
    ]
  }
}

private extension AgentNativeToolReceipt {
  func toJSONObject() -> AgentMcpJSONObject {
    [
      "invocation_id": .string(invocationId),
      "idempotency_key": idempotencyKey.map(AgentMcpJSONValue.string) ?? .null,
      "started_at_epoch_ms": .int(startedAtEpochMillis),
      "finished_at_epoch_ms": .int(finishedAtEpochMillis),
      "duration_ms": .int(durationMillis),
      "status": .string(status.rawValue),
      "input_sha256": .string(inputSha256),
      "output_sha256": .string(outputSha256),
      "replayed": .bool(replayed),
      "original_invocation_id": originalInvocationId.map(AgentMcpJSONValue.string) ?? .null
    ]
  }
}

private extension AgentNativeToolProvenance {
  func toJSONObject() -> AgentMcpJSONObject {
    [
      "tool_id": .string(toolId),
      "tool_version": .string(toolVersion),
      "location": .string(location.rawValue),
      "executor_id": .string(executorId),
      "contract_version": .string(contractVersion),
      "legacy_agent_action_id": legacyAgentActionId.map(AgentMcpJSONValue.string) ?? .null,
      "metadata": .object(metadata.reduce(into: AgentMcpJSONObject()) { result, item in
        result[item.key] = .string(item.value)
      })
    ]
  }
}

struct AgentNativeToolReplayKey: Codable, Equatable, Hashable {
  var toolId: String
  var toolVersion: String
  var idempotencyKey: String

  init(toolId: String, toolVersion: String, idempotencyKey: String) {
    self.toolId = toolId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.toolVersion = toolVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    self.idempotencyKey = idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var isComplete: Bool {
    !toolId.isEmpty && !toolVersion.isEmpty && !idempotencyKey.isEmpty
  }

  enum CodingKeys: String, CodingKey {
    case toolId = "tool_id"
    case toolVersion = "tool_version"
    case idempotencyKey = "idempotency_key"
  }
}

protocol AgentNativeToolReplayStore: AnyObject {
  func get(_ key: AgentNativeToolReplayKey) -> AgentNativeToolResult?
  func put(_ key: AgentNativeToolReplayKey, result: AgentNativeToolResult) throws
  func clear()
}

enum AgentNativeToolReplayError: Error, Equatable {
  case unsuccessfulResult
}

final class InMemoryAgentNativeToolReplayStore: AgentNativeToolReplayStore {
  static let maxEntries = 2_000

  private let lock = NSRecursiveLock()
  private var entries: [AgentNativeToolReplayKey: AgentNativeToolResult] = [:]
  private var order: [AgentNativeToolReplayKey] = []

  func get(_ key: AgentNativeToolReplayKey) -> AgentNativeToolResult? {
    lock.lock()
    defer { lock.unlock() }
    return entries[key]
  }

  func put(_ key: AgentNativeToolReplayKey, result: AgentNativeToolResult) throws {
    lock.lock()
    defer { lock.unlock() }
    if entries[key] == nil {
      order.append(key)
    }
    entries[key] = result
    while entries.count > Self.maxEntries, let oldest = order.first {
      order.removeFirst()
      entries.removeValue(forKey: oldest)
    }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    entries.removeAll()
    order.removeAll()
  }
}

struct AgentNativeToolReplayEntry: Equatable {
  var key: AgentNativeToolReplayKey
  var result: AgentNativeToolResult
  var savedAtMillis: Int64
}

enum AgentNativeToolReplayJsonCodec {
  static func stringify(_ entries: [AgentNativeToolReplayEntry]) -> String {
    AgentMcpJSONCodec.stringify(.array(entries.map(entryObject)))
  }

  static func decode(_ raw: String) -> [AgentNativeToolReplayEntry] {
    guard let data = raw.data(using: .utf8),
          let values = try? JSONDecoder().decode([AgentMcpJSONValue].self, from: data) else {
      return []
    }
    return values.compactMap { value in
      guard let object = value.objectValue,
            let resultObject = object.object("result"),
            let result = AgentNativeToolResult.fromJSONObject(resultObject) else {
        return nil
      }
      let key = AgentNativeToolReplayKey(
        toolId: object.string("tool_id"),
        toolVersion: object.string("tool_version"),
        idempotencyKey: object.string("idempotency_key")
      )
      guard key.isComplete else {
        return nil
      }
      return AgentNativeToolReplayEntry(
        key: key,
        result: result,
        savedAtMillis: object.int64("saved_at_millis")
      )
    }
  }

  private static func entryObject(_ entry: AgentNativeToolReplayEntry) -> AgentMcpJSONValue {
    .object([
      "tool_id": .string(entry.key.toolId),
      "tool_version": .string(entry.key.toolVersion),
      "idempotency_key": .string(entry.key.idempotencyKey),
      "saved_at_millis": .int(entry.savedAtMillis),
      "result": entry.result.toJsonValue()
    ])
  }
}

final class AgentNativeToolReplaySnapshotStore: AgentNativeToolReplayStore {
  static let maxEntries = 2_000
  static let retentionMillis: Int64 = 30 * 24 * 60 * 60 * 1_000

  private let lock = NSRecursiveLock()
  private var serializedEntries: String
  private let nowMillis: () -> Int64

  init(
    serializedEntries: String = "[]",
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.serializedEntries = serializedEntries
    self.nowMillis = nowMillis
  }

  func get(_ key: AgentNativeToolReplayKey) -> AgentNativeToolResult? {
    lock.lock()
    defer { lock.unlock() }
    let loaded = load()
    let retained = retainedEntries(loaded, nowMillis: nowMillis())
    if retained.count != loaded.count {
      save(retained)
    }
    return retained.last { $0.key == key }?.result
  }

  func put(_ key: AgentNativeToolReplayKey, result: AgentNativeToolResult) throws {
    guard result.isSuccess else {
      throw AgentNativeToolReplayError.unsuccessfulResult
    }
    lock.lock()
    defer { lock.unlock() }
    let now = nowMillis()
    var entries = Array(retainedEntries(load(), nowMillis: now)
      .filter { $0.key != key }
      .suffix(Self.maxEntries - 1))
    entries.append(AgentNativeToolReplayEntry(key: key, result: result, savedAtMillis: now))
    save(entries)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    serializedEntries = "[]"
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    return serializedEntries
  }

  private func load() -> [AgentNativeToolReplayEntry] {
    AgentNativeToolReplayJsonCodec.decode(serializedEntries)
  }

  private func save(_ entries: [AgentNativeToolReplayEntry]) {
    serializedEntries = AgentNativeToolReplayJsonCodec.stringify(entries)
  }

  private func retainedEntries(
    _ entries: [AgentNativeToolReplayEntry],
    nowMillis: Int64
  ) -> [AgentNativeToolReplayEntry] {
    entries.filter { nowMillis - $0.savedAtMillis <= Self.retentionMillis }
  }
}

struct AgentSystemTool: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var kind: AgentActionKind
  var risk: AgentRisk
  var capabilities: [AgentCapability]
  var examples: [String]

  init(
    id: String,
    title: String,
    kind: AgentActionKind,
    risk: AgentRisk,
    capabilities: [AgentCapability],
    examples: [String] = []
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.risk = risk
    self.capabilities = capabilities
    self.examples = examples
  }
}

struct AgentCallableTarget: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var kind: AgentConnectorKind
  var status: AgentConnectorStatus
  var capabilities: [AgentCapability]
  var failureDomain: String
  var runtimeFailureDomain: String
  var adapterType: String
  var independentlyUpgradeable: Bool
  var desktopAccessProfile: String
  var providerProfile: ProviderProfile?
  var invocationProfile: AgentInvocationProfile

  init(
    id: String,
    title: String,
    kind: AgentConnectorKind,
    status: AgentConnectorStatus,
    capabilities: [AgentCapability],
    failureDomain: String = "",
    runtimeFailureDomain: String = "",
    adapterType: String = "",
    independentlyUpgradeable: Bool = true,
    desktopAccessProfile: String = "",
    providerProfile: ProviderProfile? = nil,
    invocationProfile: AgentInvocationProfile = AgentInvocationProfile()
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.status = status
    self.capabilities = capabilities
    self.failureDomain = failureDomain
    self.runtimeFailureDomain = runtimeFailureDomain
    self.adapterType = adapterType
    self.independentlyUpgradeable = independentlyUpgradeable
    self.desktopAccessProfile = desktopAccessProfile
    self.providerProfile = providerProfile
    self.invocationProfile = invocationProfile
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case kind
    case status
    case capabilities
    case failureDomain = "failure_domain"
    case runtimeFailureDomain = "runtime_failure_domain"
    case adapterType = "adapter_type"
    case independentlyUpgradeable = "independently_upgradeable"
    case desktopAccessProfile = "desktop_access_profile"
    case providerProfile = "provider_profile"
    case invocationProfile = "invocation_profile"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      kind: try container.decodeIfPresent(AgentConnectorKind.self, forKey: .kind) ?? .agent,
      status: try container.decodeIfPresent(AgentConnectorStatus.self, forKey: .status) ?? .disconnected,
      capabilities: try container.decodeIfPresent([AgentCapability].self, forKey: .capabilities) ?? [],
      failureDomain: try container.decodeIfPresent(String.self, forKey: .failureDomain) ?? "",
      runtimeFailureDomain: try container.decodeIfPresent(String.self, forKey: .runtimeFailureDomain) ?? "",
      adapterType: try container.decodeIfPresent(String.self, forKey: .adapterType) ?? "",
      independentlyUpgradeable: try container.decodeIfPresent(
        Bool.self,
        forKey: .independentlyUpgradeable
      ) ?? true,
      desktopAccessProfile: try container.decodeIfPresent(String.self, forKey: .desktopAccessProfile) ?? "",
      providerProfile: try container.decodeIfPresent(ProviderProfile.self, forKey: .providerProfile),
      invocationProfile: try container.decodeIfPresent(
        AgentInvocationProfile.self,
        forKey: .invocationProfile
      ) ?? AgentInvocationProfile()
    )
  }
}

enum AgentRuntimeCapabilitySource: String, Codable, CaseIterable, Identifiable {
  case nativeTool = "NATIVE_TOOL"
  case systemTool = "SYSTEM_TOOL"
  case connector = "CONNECTOR"

  var id: String { rawValue }

  var sortOrder: Int {
    switch self {
    case .nativeTool: return 0
    case .systemTool: return 1
    case .connector: return 2
    }
  }

  static func fromWireValue(_ value: String?) -> AgentRuntimeCapabilitySource {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .connector
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentRuntimeCapabilityState: String, Codable, CaseIterable, Identifiable {
  case available = "AVAILABLE"
  case requiresSetup = "REQUIRES_SETUP"
  case unavailable = "UNAVAILABLE"
  case blocked = "BLOCKED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentRuntimeCapabilityState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .unavailable
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

struct AgentRuntimeCapabilityEntry: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var source: AgentRuntimeCapabilitySource
  var state: AgentRuntimeCapabilityState
  var capabilities: Set<String>
  var location: String
  var risk: String
  var reason: String
  var requiredPermissions: Set<String>
  var requiredConsents: Set<String>

  var executable: Bool {
    state == .available && risk != AgentNativeToolRisk.blocked.rawValue
  }

  init(
    id: String,
    title: String,
    source: AgentRuntimeCapabilitySource,
    state: AgentRuntimeCapabilityState,
    capabilities: Set<String>,
    location: String,
    risk: String,
    reason: String = "",
    requiredPermissions: Set<String> = [],
    requiredConsents: Set<String> = []
  ) {
    self.id = id
    self.title = title
    self.source = source
    self.state = state
    self.capabilities = capabilities
    self.location = location
    self.risk = risk
    self.reason = reason
    self.requiredPermissions = requiredPermissions
    self.requiredConsents = requiredConsents
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case source
    case state
    case capabilities
    case location
    case risk
    case reason
    case requiredPermissions = "required_permissions"
    case requiredConsents = "required_consents"
  }
}

struct AgentRuntimeCapabilitySnapshot: Codable, Equatable {
  var entries: [AgentRuntimeCapabilityEntry]

  static let empty = AgentRuntimeCapabilitySnapshot(entries: [])

  var availableEntries: [AgentRuntimeCapabilityEntry] {
    entries.filter(\.executable)
  }

  var availableNativeToolIds: Set<String> {
    Set(entries.filter { $0.source == .nativeTool && $0.executable }.map(\.id))
  }

  var setupRequiredEntries: [AgentRuntimeCapabilityEntry] {
    entries.filter { $0.state == .requiresSetup }
  }

  var unavailableEntries: [AgentRuntimeCapabilityEntry] {
    entries.filter { $0.state == .unavailable || $0.state == .blocked }
  }

  func entry(source: AgentRuntimeCapabilitySource, id: String) -> AgentRuntimeCapabilityEntry? {
    entries.first { $0.source == source && $0.id == id }
  }

  func isNativeToolExecutable(id: String) -> Bool {
    entry(source: .nativeTool, id: id)?.executable == true
  }
}

enum AgentRuntimeCapabilityError: LocalizedError, Equatable {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let message):
      return message
    }
  }
}

struct AgentNativeToolExecutionResult: Codable, Equatable {
  var output: AgentMcpJSONObject
  var message: String
  var metadata: AgentMcpJSONObject
  var error: AgentNativeToolError?

  var isSuccess: Bool { error == nil }

  init(
    output: AgentMcpJSONObject = [:],
    message: String = "",
    metadata: AgentMcpJSONObject = [:],
    error: AgentNativeToolError? = nil
  ) {
    self.output = output
    self.message = message
    self.metadata = metadata
    self.error = error
  }

  static func success(
    output: AgentMcpJSONObject = [:],
    message: String = "",
    metadata: AgentMcpJSONObject = [:]
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult(output: output, message: message, metadata: metadata)
  }

  static func failure(
    code: String,
    message: String,
    retryable: Bool = false,
    details: AgentMcpJSONObject = [:]
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult(
      message: message,
      error: AgentNativeToolError(
        code: code,
        message: message,
        retryable: retryable,
        details: details
      )
    )
  }
}

struct AgentNativeToolCall: Codable, Equatable {
  var toolId: String
  var input: AgentMcpJSONObject
  var context: AgentNativeToolInvocationContext

  enum CodingKeys: String, CodingKey {
    case toolId = "tool_id"
    case input
    case context
  }
}

enum AgentNativeToolInvocationError: Error, Equatable {
  case cancelled
  case timedOut
}

struct AgentNativeToolProgressUpdate: Codable, Equatable {
  var sequence: Int64
  var stage: String
  var message: String
  var percent: Int?
  var timestampEpochMillis: Int64

  init(
    sequence: Int64,
    stage: String,
    message: String = "",
    percent: Int? = nil,
    timestampEpochMillis: Int64
  ) {
    self.sequence = max(0, sequence)
    self.stage = String(stage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    self.message = String(message.prefix(2_000))
    self.percent = percent.map { min(100, max(0, $0)) }
    self.timestampEpochMillis = max(0, timestampEpochMillis)
  }

  enum CodingKeys: String, CodingKey {
    case sequence
    case stage
    case message
    case percent
    case timestampEpochMillis = "timestamp_epoch_millis"
  }
}

struct AgentNativeToolInvocation {
  var descriptor: AgentNativeToolDescriptor
  var input: AgentMcpJSONObject
  var context: AgentNativeToolInvocationContext
  var startedAtEpochMillis: Int64
  var deadlineEpochMillis: Int64

  private let nowMillis: () -> Int64
  private let cancellationRequested: () -> Bool
  private let progressReporter: (AgentNativeToolInvocation, AgentNativeToolProgressUpdate) -> Void

  var remainingTimeMillis: Int64 {
    max(0, deadlineEpochMillis - nowMillis())
  }

  var isCancellationRequested: Bool {
    cancellationRequested()
  }

  var isTimedOut: Bool {
    nowMillis() >= deadlineEpochMillis
  }

  init(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    startedAtEpochMillis: Int64,
    deadlineEpochMillis: Int64,
    nowMillis: @escaping () -> Int64,
    cancellationRequested: @escaping () -> Bool,
    progressReporter: @escaping (AgentNativeToolInvocation, AgentNativeToolProgressUpdate) -> Void
  ) {
    self.descriptor = descriptor
    self.input = input
    self.context = context
    self.startedAtEpochMillis = max(0, startedAtEpochMillis)
    self.deadlineEpochMillis = max(0, deadlineEpochMillis)
    self.nowMillis = nowMillis
    self.cancellationRequested = cancellationRequested
    self.progressReporter = progressReporter
  }

  func checkpoint() throws {
    if isCancellationRequested {
      throw AgentNativeToolInvocationError.cancelled
    }
    if isTimedOut {
      throw AgentNativeToolInvocationError.timedOut
    }
  }

  func reportProgress(
    stage: String,
    message: String = "",
    percent: Int? = nil,
    sequence: Int64 = 0,
    timestampEpochMillis: Int64? = nil
  ) throws {
    try checkpoint()
    progressReporter(
      self,
      AgentNativeToolProgressUpdate(
        sequence: sequence,
        stage: stage,
        message: message,
        percent: percent,
        timestampEpochMillis: timestampEpochMillis ?? nowMillis()
      )
    )
  }
}

struct AgentNativeToolInvocationHooks {
  var nowMillis: () -> Int64
  var cancellationRequested: () -> Bool
  var onStarted: (AgentNativeToolInvocation) -> Void
  var onProgress: (AgentNativeToolInvocation, AgentNativeToolProgressUpdate) -> Void
  var onCancelled: (AgentNativeToolInvocation) -> Void
  var onTimeout: (AgentNativeToolInvocation) -> Void
  var onFinished: (AgentNativeToolResult) -> Void

  init(
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    },
    cancellationRequested: @escaping () -> Bool = { false },
    onStarted: @escaping (AgentNativeToolInvocation) -> Void = { _ in },
    onProgress: @escaping (AgentNativeToolInvocation, AgentNativeToolProgressUpdate) -> Void = { _, _ in },
    onCancelled: @escaping (AgentNativeToolInvocation) -> Void = { _ in },
    onTimeout: @escaping (AgentNativeToolInvocation) -> Void = { _ in },
    onFinished: @escaping (AgentNativeToolResult) -> Void = { _ in }
  ) {
    self.nowMillis = nowMillis
    self.cancellationRequested = cancellationRequested
    self.onStarted = onStarted
    self.onProgress = onProgress
    self.onCancelled = onCancelled
    self.onTimeout = onTimeout
    self.onFinished = onFinished
  }
}

struct AgentNativeToolExecutableDefinition {
  var definition: AgentPhoneNativeToolDefinition
  var executor: (AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult
  var verifier: ((AgentNativeToolInvocation, AgentNativeToolExecutionResult) throws -> AgentNativeToolVerification?)?

  var id: String { definition.id }
  var descriptor: AgentNativeToolDescriptor { definition.descriptor }
  var executorId: String { definition.executorId }
  var provenanceMetadata: [String: String] { definition.provenanceMetadata }

  init(
    definition: AgentPhoneNativeToolDefinition,
    executor: @escaping (AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult,
    verifier: ((AgentNativeToolInvocation, AgentNativeToolExecutionResult) throws -> AgentNativeToolVerification?)? = nil
  ) {
    self.definition = definition
    self.executor = executor
    self.verifier = verifier
  }
}

enum AgentNativeToolAgentActionAdapter {
  static let legacyActionIdAttribute = "legacy_agent_action_id"

  static func defaultToolId(_ kind: AgentActionKind) -> String {
    "signalasi.agent_action.\(kind.rawValue.lowercased().replacingOccurrences(of: "_", with: "."))"
  }

  static func fromAgentAction(
    _ action: AgentAction,
    toolId: String? = nil,
    context: AgentNativeToolInvocationContext? = nil
  ) -> AgentNativeToolCall {
    var mergedContext = context ?? AgentNativeToolInvocationContext(invocationId: action.id)
    mergedContext.attributes[legacyActionIdAttribute] = action.id
    return AgentNativeToolCall(
      toolId: toolId ?? defaultToolId(action.kind),
      input: [
        "target": .string(action.target),
        "description": .string(action.description),
        "parameters": .object(action.parameters.reduce(into: AgentMcpJSONObject()) { result, entry in
          result[entry.key] = .string(entry.value)
        }),
        "requires_confirmation": .bool(action.requiresConfirmation)
      ],
      context: mergedContext
    )
  }

  static func toAgentAction(
    call: AgentNativeToolCall,
    descriptor: AgentNativeToolDescriptor,
    kind: AgentActionKind,
    target: String? = nil,
    description: String? = nil,
    parameters: [String: String]? = nil
  ) -> AgentAction {
    AgentAction(
      id: call.context.attributes[legacyActionIdAttribute] ?? call.context.invocationId,
      kind: kind,
      target: target ?? call.input["target"]?.stringValue ?? "",
      risk: descriptor.risk.legacyRisk,
      status: .running,
      description: description ?? call.input["description"]?.stringValue ?? descriptor.description,
      parameters: parameters ?? defaultParameters(call.input),
      requiresConfirmation: call.input["requires_confirmation"]?.boolValue == true ||
        descriptor.requiredConsents.contains { $0.required } ||
        descriptor.risk.weight >= AgentNativeToolRisk.medium.weight
    )
  }

  static func fromAgentActionResult(_ result: AgentActionResult) -> AgentNativeToolExecutionResult {
    let output: AgentMcpJSONObject = [
      "action_id": .string(result.actionId),
      "success": .bool(result.success),
      "message": .string(result.message),
      "metadata": .object(result.metadata.reduce(into: AgentMcpJSONObject()) { object, entry in
        object[entry.key] = .string(entry.value)
      })
    ]
    if result.success {
      return .success(output: output, message: result.message)
    }
    return AgentNativeToolExecutionResult(
      output: output,
      message: result.message,
      error: AgentNativeToolError(
        code: "agent_action_failed",
        message: result.message.isEmpty ? "Legacy AgentAction execution failed" : result.message
      )
    )
  }

  static func toAgentActionResult(_ result: AgentNativeToolResult, actionId: String) -> AgentActionResult {
    AgentActionResult(
      actionId: actionId,
      success: result.isSuccess,
      message: result.message.isEmpty ? result.error?.message ?? "" : result.message,
      metadata: [
        "native_tool_id": result.provenance.toolId,
        "native_tool_version": result.provenance.toolVersion,
        "native_receipt_id": result.receipt.invocationId,
        "native_status": result.status.rawValue
      ]
    )
  }

  private static func defaultParameters(_ input: AgentMcpJSONObject) -> [String: String] {
    if case .object(let nested)? = input["parameters"] {
      return nested.reduce(into: [:]) { result, entry in
        result[entry.key] = legacyString(entry.value)
      }
    }
    return input.reduce(into: [:]) { result, entry in
      if entry.key != "target" && entry.key != "description" {
        result[entry.key] = legacyString(entry.value)
      }
    }
  }

  private static func legacyString(_ value: AgentMcpJSONValue) -> String {
    if case .string(let string) = value {
      return string
    }
    return AgentMcpJSONCodec.stringify(value)
  }
}

struct AgentActionNativeToolExecutor {
  var delegate: AgentActionExecutor
  var screenProvider: (AgentNativeToolInvocation) -> AgentScreenContext
  var actionFactory: (AgentNativeToolInvocation) -> AgentAction

  init(
    delegate: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    actionFactory: @escaping (AgentNativeToolInvocation) -> AgentAction
  ) {
    self.delegate = delegate
    self.screenProvider = screenProvider
    self.actionFactory = actionFactory
  }

  func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    try invocation.checkpoint()
    let action = actionFactory(invocation)
    let result = delegate.execute(action: action, screen: screenProvider(invocation))
    try invocation.checkpoint()
    return AgentNativeToolAgentActionAdapter.fromAgentActionResult(result)
  }

  static func forKind(
    delegate: AgentActionExecutor,
    kind: AgentActionKind,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    targetProvider: ((AgentNativeToolInvocation) -> String)? = nil,
    descriptionProvider: ((AgentNativeToolInvocation) -> String)? = nil
  ) -> AgentActionNativeToolExecutor {
    AgentActionNativeToolExecutor(
      delegate: delegate,
      screenProvider: screenProvider,
      actionFactory: { invocation in
        let call = AgentNativeToolCall(
          toolId: invocation.descriptor.id,
          input: invocation.input,
          context: invocation.context
        )
        return AgentNativeToolAgentActionAdapter.toAgentAction(
          call: call,
          descriptor: invocation.descriptor,
          kind: kind,
          target: targetProvider?(invocation),
          description: descriptionProvider?(invocation)
        )
      }
    )
  }

  static func executableDefinition(
    definition: AgentPhoneNativeToolDefinition,
    delegate: AgentActionExecutor,
    kind: AgentActionKind,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    targetProvider: ((AgentNativeToolInvocation) -> String)? = nil,
    descriptionProvider: ((AgentNativeToolInvocation) -> String)? = nil
  ) -> AgentNativeToolExecutableDefinition {
    let executor = forKind(
      delegate: delegate,
      kind: kind,
      screenProvider: screenProvider,
      targetProvider: targetProvider,
      descriptionProvider: descriptionProvider
    )
    return AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: executor.execute
    )
  }
}

private extension AgentNativeToolRisk {
  var legacyRisk: AgentRisk {
    switch self {
    case .low:
      return .low
    case .medium:
      return .medium
    case .high:
      return .high
    case .blocked:
      return .blocked
    }
  }
}
