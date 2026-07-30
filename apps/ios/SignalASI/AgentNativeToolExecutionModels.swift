import CryptoKit
import Foundation

struct AgentNativeValidationIssue: Codable, Equatable {
  var path: String
  var code: String
  var message: String
}

struct AgentNativeValidationResult: Codable, Equatable {
  var issues: [AgentNativeValidationIssue]

  var isValid: Bool { issues.isEmpty }

  static let valid = AgentNativeValidationResult()

  init(issues: [AgentNativeValidationIssue] = []) {
    self.issues = issues
  }

  static func invalid(path: String, code: String, message: String) -> AgentNativeValidationResult {
    AgentNativeValidationResult(issues: [
      AgentNativeValidationIssue(path: path, code: code, message: message)
    ])
  }
}

enum AgentNativeJsonSchemaValidator {
  static func validate(schema: AgentMcpJSONObject, value: AgentMcpJSONValue) -> AgentNativeValidationResult {
    guard isJSONCompatible(value) else {
      return .invalid(
        path: "$",
        code: "invalid_json_value",
        message: "Value contains a type that JSON cannot represent"
      )
    }
    var issues: [AgentNativeValidationIssue] = []
    validateNode(schema: schema, value: value, path: "$", issues: &issues)
    return AgentNativeValidationResult(issues: issues)
  }

  static func validateObject(schema: AgentMcpJSONObject, object: AgentMcpJSONObject) -> AgentNativeValidationResult {
    validate(schema: schema, value: .object(object))
  }

  private static func validateNode(
    schema: AgentMcpJSONObject,
    value: AgentMcpJSONValue,
    path: String,
    issues: inout [AgentNativeValidationIssue]
  ) {
    let expectedTypes = typeNames(schema["type"])
    if !expectedTypes.isEmpty && !expectedTypes.contains(where: { matchesType($0, value) }) {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "type_mismatch",
        message: "Expected \(expectedTypes.joined(separator: " or ")), received \(jsonType(of: value))"
      ))
      return
    }

    if let enumValues = schema["enum"]?.arrayValue, !enumValues.isEmpty,
       !enumValues.contains(where: { jsonEquals($0, value) }) {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "not_in_enum",
        message: "Value is not one of the allowed values"
      ))
    }

    switch value {
    case .object(let object):
      validateObjectNode(schema: schema, value: object, path: path, issues: &issues)
    case .array(let array):
      validateArray(schema: schema, value: array, path: path, issues: &issues)
    case .string(let string):
      validateString(schema: schema, value: string, path: path, issues: &issues)
    case .int, .double:
      validateNumber(schema: schema, value: value, path: path, issues: &issues)
    case .bool, .null:
      break
    }
  }

  private static func validateObjectNode(
    schema: AgentMcpJSONObject,
    value: AgentMcpJSONObject,
    path: String,
    issues: inout [AgentNativeValidationIssue]
  ) {
    let properties = schema["properties"]?.objectValue ?? [:]
    let required = schema["required"]?.arrayValue?.compactMap(\.strictStringValue) ?? []
    for name in required where value[name] == nil {
      issues.append(AgentNativeValidationIssue(
        path: childPath(path, name),
        code: "required",
        message: "Required property is missing"
      ))
    }
    for (name, propertyValue) in value {
      if let propertySchema = properties[name]?.objectValue, !propertySchema.isEmpty {
        validateNode(schema: propertySchema, value: propertyValue, path: childPath(path, name), issues: &issues)
      } else if schema["additionalProperties"]?.boolValue == false {
        issues.append(AgentNativeValidationIssue(
          path: childPath(path, name),
          code: "additional_property",
          message: "Additional properties are not allowed"
        ))
      } else if let additionalSchema = schema["additionalProperties"]?.objectValue, !additionalSchema.isEmpty {
        validateNode(schema: additionalSchema, value: propertyValue, path: childPath(path, name), issues: &issues)
      }
    }
  }

  private static func validateArray(
    schema: AgentMcpJSONObject,
    value: [AgentMcpJSONValue],
    path: String,
    issues: inout [AgentNativeValidationIssue]
  ) {
    if let minItems = schema["minItems"]?.integerForSchema, value.count < minItems {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "min_items",
        message: "Expected at least \(minItems) items"
      ))
    }
    if let maxItems = schema["maxItems"]?.integerForSchema, value.count > maxItems {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "max_items",
        message: "Expected at most \(maxItems) items"
      ))
    }
    if let itemSchema = schema["items"]?.objectValue, !itemSchema.isEmpty {
      for (index, item) in value.enumerated() {
        validateNode(schema: itemSchema, value: item, path: "\(path)[\(index)]", issues: &issues)
      }
    }
  }

  private static func validateString(
    schema: AgentMcpJSONObject,
    value: String,
    path: String,
    issues: inout [AgentNativeValidationIssue]
  ) {
    if let minLength = schema["minLength"]?.integerForSchema, value.count < minLength {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "min_length",
        message: "Expected at least \(minLength) characters"
      ))
    }
    if let maxLength = schema["maxLength"]?.integerForSchema, value.count > maxLength {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "max_length",
        message: "Expected at most \(maxLength) characters"
      ))
    }
    if let pattern = schema["pattern"]?.strictStringValue, !pattern.isEmpty,
       value.range(of: pattern, options: .regularExpression) == nil {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "pattern",
        message: "Value does not match the required pattern"
      ))
    }
  }

  private static func validateNumber(
    schema: AgentMcpJSONObject,
    value: AgentMcpJSONValue,
    path: String,
    issues: inout [AgentNativeValidationIssue]
  ) {
    guard let number = value.doubleForSchema else { return }
    if let minimum = schema["minimum"]?.doubleForSchema, number < minimum {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "minimum",
        message: "Value must be at least \(minimum)"
      ))
    }
    if let maximum = schema["maximum"]?.doubleForSchema, number > maximum {
      issues.append(AgentNativeValidationIssue(
        path: path,
        code: "maximum",
        message: "Value must be at most \(maximum)"
      ))
    }
  }

  private static func typeNames(_ value: AgentMcpJSONValue?) -> [String] {
    switch value {
    case .string(let type):
      return [type]
    case .array(let values):
      return values.compactMap(\.strictStringValue)
    case .bool, .int, .double, .object, .null, .none:
      return []
    }
  }

  private static func matchesType(_ type: String, _ value: AgentMcpJSONValue) -> Bool {
    switch type {
    case "null":
      if case .null = value { return true }
      return false
    case "object":
      if case .object = value { return true }
      return false
    case "array":
      if case .array = value { return true }
      return false
    case "string":
      if case .string = value { return true }
      return false
    case "boolean":
      if case .bool = value { return true }
      return false
    case "number":
      return value.doubleForSchema?.isFinite == true
    case "integer":
      return value.integerForSchema != nil
    default:
      return false
    }
  }

  private static func jsonType(of value: AgentMcpJSONValue) -> String {
    switch value {
    case .null: return "null"
    case .object: return "object"
    case .array: return "array"
    case .string: return "string"
    case .bool: return "boolean"
    case .int: return "integer"
    case .double(let double): return double.rounded(.towardZero) == double ? "integer" : "number"
    }
  }

  private static func jsonEquals(_ left: AgentMcpJSONValue, _ right: AgentMcpJSONValue) -> Bool {
    switch (left, right) {
    case (.int(let left), .int(let right)):
      return left == right
    case (.int(let left), .double(let right)):
      return Double(left) == right
    case (.double(let left), .int(let right)):
      return left == Double(right)
    case (.double(let left), .double(let right)):
      return left == right
    default:
      return left == right
    }
  }

  private static func childPath(_ parent: String, _ child: String) -> String {
    if child.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil {
      return "\(parent).\(child)"
    }
    return "\(parent)['\(child.replacingOccurrences(of: "'", with: "\\'"))']"
  }

  private static func isJSONCompatible(_ value: AgentMcpJSONValue) -> Bool {
    switch value {
    case .double(let double):
      return double.isFinite
    case .array(let values):
      return values.allSatisfy(isJSONCompatible)
    case .object(let object):
      return object.values.allSatisfy(isJSONCompatible)
    case .string, .int, .bool, .null:
      return true
    }
  }
}

struct AgentNativeToolInvocationContext: Codable, Equatable {
  var invocationId: String
  var sessionId: String
  var conversationId: String
  var turnId: String
  var callerId: String
  var requestedAtEpochMillis: Int64
  var deadlineEpochMillis: Int64?
  var idempotencyKey: String?
  var grantedPermissions: Set<String>
  var grantedConsents: Set<String>
  var attributes: [String: String]

  init(
    invocationId: String = UUID().uuidString,
    sessionId: String = "",
    conversationId: String = "",
    turnId: String = "",
    callerId: String = "signalasi.mobile_agent",
    requestedAtEpochMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    deadlineEpochMillis: Int64? = nil,
    idempotencyKey: String? = nil,
    grantedPermissions: Set<String> = [],
    grantedConsents: Set<String> = [],
    attributes: [String: String] = [:]
  ) {
    let cleanInvocationId = invocationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanCallerId = callerId.trimmingCharacters(in: .whitespacesAndNewlines)
    self.invocationId = cleanInvocationId.isEmpty ? UUID().uuidString : cleanInvocationId
    self.sessionId = sessionId
    self.conversationId = conversationId
    self.turnId = turnId
    self.callerId = cleanCallerId.isEmpty ? "signalasi.mobile_agent" : cleanCallerId
    self.requestedAtEpochMillis = max(0, requestedAtEpochMillis)
    self.deadlineEpochMillis = deadlineEpochMillis
    self.idempotencyKey = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.grantedPermissions = Set(grantedPermissions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    self.grantedConsents = Set(grantedConsents.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    self.attributes = attributes.reduce(into: [:]) { result, entry in
      let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
      if !key.isEmpty {
        result[key] = entry.value
      }
    }
  }

  enum CodingKeys: String, CodingKey {
    case invocationId = "invocation_id"
    case sessionId = "session_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case callerId = "caller_id"
    case requestedAtEpochMillis = "requested_at_epoch_millis"
    case deadlineEpochMillis = "deadline_epoch_millis"
    case idempotencyKey = "idempotency_key"
    case grantedPermissions = "granted_permissions"
    case grantedConsents = "granted_consents"
    case attributes
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      invocationId: try container.decodeIfPresent(String.self, forKey: .invocationId) ?? "",
      sessionId: try container.decodeIfPresent(String.self, forKey: .sessionId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      turnId: try container.decodeIfPresent(String.self, forKey: .turnId) ?? "",
      callerId: try container.decodeIfPresent(String.self, forKey: .callerId) ?? "signalasi.mobile_agent",
      requestedAtEpochMillis: try container.decodeIfPresent(Int64.self, forKey: .requestedAtEpochMillis) ?? 0,
      deadlineEpochMillis: try container.decodeIfPresent(Int64.self, forKey: .deadlineEpochMillis),
      idempotencyKey: try container.decodeIfPresent(String.self, forKey: .idempotencyKey),
      grantedPermissions: try container.decodeIfPresent(Set<String>.self, forKey: .grantedPermissions) ?? [],
      grantedConsents: try container.decodeIfPresent(Set<String>.self, forKey: .grantedConsents) ?? [],
      attributes: try container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(invocationId, forKey: .invocationId)
    try container.encode(sessionId, forKey: .sessionId)
    try container.encode(conversationId, forKey: .conversationId)
    try container.encode(turnId, forKey: .turnId)
    try container.encode(callerId, forKey: .callerId)
    try container.encode(requestedAtEpochMillis, forKey: .requestedAtEpochMillis)
    try container.encodeIfPresent(deadlineEpochMillis, forKey: .deadlineEpochMillis)
    try container.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
    try container.encode(Array(grantedPermissions).sorted(), forKey: .grantedPermissions)
    try container.encode(Array(grantedConsents).sorted(), forKey: .grantedConsents)
    try container.encode(attributes, forKey: .attributes)
  }
}

struct AgentNativeToolAuthorizationDecision: Codable, Equatable {
  var toolId: String
  var allowed: Bool
  var code: String
  var message: String
  var availability: AgentNativeToolAvailability
  var risk: AgentNativeToolRisk
  var missingPermissions: [AgentNativePermissionRequirement]
  var missingConsents: [AgentNativeConsentRequirement]
  var validationIssues: [AgentNativeValidationIssue]

  enum CodingKeys: String, CodingKey {
    case toolId = "tool_id"
    case allowed
    case code
    case message
    case availability
    case risk
    case missingPermissions = "missing_permissions"
    case missingConsents = "missing_consents"
    case validationIssues = "validation_issues"
  }
}

enum AgentNativeToolReplayDecisionCode: String, Codable {
  case bypassed
  case accepted
  case replay
  case conflict
  case keyRequired = "key_required"
  case unknownTool = "unknown_tool"
}

struct AgentNativeToolReplayDecision: Codable, Equatable {
  var code: AgentNativeToolReplayDecisionCode
  var replayed: Bool
  var originalInvocationId: String?
  var inputSha256: String

  enum CodingKeys: String, CodingKey {
    case code
    case replayed
    case originalInvocationId = "original_invocation_id"
    case inputSha256 = "input_sha256"
  }
}

struct AgentNativeToolReplayRecord: Codable, Equatable {
  var toolId: String
  var idempotencyKey: String
  var inputSha256: String
  var invocationId: String
  var recordedAtEpochMillis: Int64

  enum CodingKeys: String, CodingKey {
    case toolId = "tool_id"
    case idempotencyKey = "idempotency_key"
    case inputSha256 = "input_sha256"
    case invocationId = "invocation_id"
    case recordedAtEpochMillis = "recorded_at_epoch_millis"
  }
}

final class InMemoryAgentNativeToolReplayStore {
  private var records: [String: AgentNativeToolReplayRecord] = [:]
  private var results: [String: AgentNativeToolResult] = [:]

  func decide(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext
  ) -> AgentNativeToolReplayDecision {
    guard descriptor.idempotency != .nonIdempotent else {
      return AgentNativeToolReplayDecision(
        code: .bypassed,
        replayed: false,
        originalInvocationId: nil,
        inputSha256: AgentMcpJSONCodec.sha256(input)
      )
    }
    guard let key = context.idempotencyKey, !key.isEmpty else {
      let code: AgentNativeToolReplayDecisionCode = descriptor.idempotency == .idempotencyKeyRequired
        ? .keyRequired
        : .accepted
      return AgentNativeToolReplayDecision(
        code: code,
        replayed: false,
        originalInvocationId: nil,
        inputSha256: AgentMcpJSONCodec.sha256(input)
      )
    }

    let digest = AgentMcpJSONCodec.sha256(input)
    let storageKey = self.storageKey(descriptor: descriptor, idempotencyKey: key)
    if let existing = records[storageKey] {
      return AgentNativeToolReplayDecision(
        code: existing.inputSha256 == digest ? .replay : .conflict,
        replayed: existing.inputSha256 == digest,
        originalInvocationId: existing.invocationId,
        inputSha256: digest
      )
    }
    records[storageKey] = AgentNativeToolReplayRecord(
      toolId: descriptor.id,
      idempotencyKey: key,
      inputSha256: digest,
      invocationId: context.invocationId,
      recordedAtEpochMillis: context.requestedAtEpochMillis
    )
    return AgentNativeToolReplayDecision(
      code: .accepted,
      replayed: false,
      originalInvocationId: nil,
      inputSha256: digest
    )
  }

  func cachedResult(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext
  ) -> (AgentNativeToolReplayDecision, AgentNativeToolResult?) {
    guard descriptor.idempotency != .nonIdempotent else {
      return (
        AgentNativeToolReplayDecision(
          code: .bypassed,
          replayed: false,
          originalInvocationId: nil,
          inputSha256: AgentMcpJSONCodec.sha256(input)
        ),
        nil
      )
    }
    guard let key = context.idempotencyKey, !key.isEmpty else {
      return (
        AgentNativeToolReplayDecision(
          code: descriptor.idempotency == .idempotencyKeyRequired ? .keyRequired : .accepted,
          replayed: false,
          originalInvocationId: nil,
          inputSha256: AgentMcpJSONCodec.sha256(input)
        ),
        nil
      )
    }

    let digest = AgentMcpJSONCodec.sha256(input)
    let keyValue = storageKey(descriptor: descriptor, idempotencyKey: key)
    guard let existing = records[keyValue] else {
      return (
        AgentNativeToolReplayDecision(
          code: .accepted,
          replayed: false,
          originalInvocationId: nil,
          inputSha256: digest
        ),
        nil
      )
    }
    guard existing.inputSha256 == digest else {
      return (
        AgentNativeToolReplayDecision(
          code: .conflict,
          replayed: false,
          originalInvocationId: existing.invocationId,
          inputSha256: digest
        ),
        nil
      )
    }
    return (
      AgentNativeToolReplayDecision(
        code: .replay,
        replayed: true,
        originalInvocationId: existing.invocationId,
        inputSha256: digest
      ),
      results[keyValue]
    )
  }

  func recordResult(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    result: AgentNativeToolResult
  ) {
    guard descriptor.idempotency != .nonIdempotent,
          let key = context.idempotencyKey,
          !key.isEmpty else {
      return
    }
    let digest = AgentMcpJSONCodec.sha256(input)
    let keyValue = storageKey(descriptor: descriptor, idempotencyKey: key)
    records[keyValue] = AgentNativeToolReplayRecord(
      toolId: descriptor.id,
      idempotencyKey: key,
      inputSha256: digest,
      invocationId: context.invocationId,
      recordedAtEpochMillis: result.receipt.finishedAtEpochMillis
    )
    results[keyValue] = result
  }

  func snapshot() -> [AgentNativeToolReplayRecord] {
    records.values.sorted {
      if $0.toolId != $1.toolId {
        return $0.toolId < $1.toolId
      }
      return $0.idempotencyKey < $1.idempotencyKey
    }
  }

  private func storageKey(
    descriptor: AgentNativeToolDescriptor,
    idempotencyKey: String
  ) -> String {
    "\(descriptor.id)\u{001F}\(descriptor.version)\u{001F}\(idempotencyKey)"
  }
}

enum AgentNativeToolRegistryError: LocalizedError, Equatable {
  case duplicateTool(String)

  var errorDescription: String? {
    switch self {
    case .duplicateTool(let id):
      return "Native tool id is already registered: \(id)"
    }
  }
}

final class AgentNativeToolRegistry {
  static let contractVersion = "signalasi.phone-native-tools/1.0"
  static let legacyActionIdAttribute = AgentNativeToolAgentActionAdapter.legacyActionIdAttribute

  private var definitionsById: [String: AgentPhoneNativeToolDefinition] = [:]
  private var executableById: [String: AgentNativeToolExecutableDefinition] = [:]
  private let replayStore: InMemoryAgentNativeToolReplayStore
  private let auditStore: AgentNativeToolAuditStore

  init(
    definitions: [AgentPhoneNativeToolDefinition] = [],
    replayStore: InMemoryAgentNativeToolReplayStore = InMemoryAgentNativeToolReplayStore(),
    auditStore: AgentNativeToolAuditStore = InMemoryAgentNativeToolAuditStore()
  ) throws {
    self.replayStore = replayStore
    self.auditStore = auditStore
    try registerAll(definitions)
  }

  @discardableResult
  func register(_ definition: AgentPhoneNativeToolDefinition) throws -> AgentNativeToolRegistry {
    guard definitionsById[definition.id] == nil else {
      throw AgentNativeToolRegistryError.duplicateTool(definition.id)
    }
    definitionsById[definition.id] = definition
    return self
  }

  @discardableResult
  func registerExecutable(_ executable: AgentNativeToolExecutableDefinition) throws -> AgentNativeToolRegistry {
    try register(executable.definition)
    executableById[executable.id] = executable
    return self
  }

  @discardableResult
  func registerExecutables(_ executables: [AgentNativeToolExecutableDefinition]) throws -> AgentNativeToolRegistry {
    try registerAll(executables.map(\.definition))
    for executable in executables {
      executableById[executable.id] = executable
    }
    return self
  }

  @discardableResult
  func registerAll(_ definitions: [AgentPhoneNativeToolDefinition]) throws -> AgentNativeToolRegistry {
    var incoming: Set<String> = []
    for definition in definitions {
      guard incoming.insert(definition.id).inserted else {
        throw AgentNativeToolRegistryError.duplicateTool(definition.id)
      }
      guard definitionsById[definition.id] == nil else {
        throw AgentNativeToolRegistryError.duplicateTool(definition.id)
      }
    }
    for definition in definitions {
      definitionsById[definition.id] = definition
    }
    return self
  }

  func lookup(_ id: String) -> AgentPhoneNativeToolDefinition? {
    definitionsById[id]
  }

  func executable(_ id: String) -> AgentNativeToolExecutableDefinition? {
    executableById[id]
  }

  func ids() -> Set<String> {
    Set(definitionsById.keys)
  }

  func descriptors() -> [AgentNativeToolDescriptor] {
    definitionsById.values.map(\.descriptor).sorted { $0.id < $1.id }
  }

  func subset(_ predicate: (AgentNativeToolDescriptor) -> Bool) throws -> AgentNativeToolRegistry {
    let matchingDefinitions = definitionsById.values.filter { predicate($0.descriptor) }
    let matchingIds = Set(matchingDefinitions.map(\.id))
    let matchingExecutables = executableById.values.filter { matchingIds.contains($0.id) }
    let registry = try AgentNativeToolRegistry(replayStore: replayStore, auditStore: auditStore)
    if matchingExecutables.isEmpty {
      return try registry.registerAll(matchingDefinitions)
    }
    let executableIds = Set(matchingExecutables.map(\.id))
    let definitionOnly = matchingDefinitions.filter { !executableIds.contains($0.id) }
    try registry.registerExecutables(matchingExecutables)
    return try registry.registerAll(definitionOnly)
  }

  func catalogObject() -> AgentMcpJSONObject {
    [
      "contract_version": .string(Self.contractVersion),
      "tools": .array(descriptors().map { .object(catalogValue($0)) })
    ]
  }

  func catalogJson() -> String {
    AgentMcpJSONCodec.stringify(catalogObject())
  }

  func audit(
    limit: Int = 100,
    toolId: String = "",
    status: AgentNativeToolResultStatus? = nil
  ) -> [AgentNativeToolAuditRecord] {
    auditStore.list(limit: limit, toolId: toolId, status: status)
  }

  func validateInput(_ id: String, input: AgentMcpJSONObject) -> AgentNativeValidationResult {
    guard let definition = lookup(id) else {
      return .invalid(
        path: "$",
        code: "unknown_tool",
        message: "No native tool is registered with id \(id)"
      )
    }
    return AgentNativeJsonSchemaValidator.validateObject(
      schema: definition.descriptor.inputSchema,
      object: input
    )
  }

  func authorize(
    _ id: String,
    input: AgentMcpJSONObject = [:],
    context: AgentNativeToolInvocationContext = AgentNativeToolInvocationContext()
  ) -> AgentNativeToolAuthorizationDecision {
    guard let definition = lookup(id) else {
      return AgentNativeToolAuthorizationDecision(
        toolId: id,
        allowed: false,
        code: "unknown_tool",
        message: "No native tool is registered with id \(id)",
        availability: AgentNativeToolAvailability(status: .unavailable, reason: "Unknown tool"),
        risk: .blocked,
        missingPermissions: [],
        missingConsents: [],
        validationIssues: []
      )
    }
    let descriptor = definition.descriptor
    if descriptor.risk == .blocked {
      return decision(
        descriptor: descriptor,
        allowed: false,
        code: "tool_blocked",
        message: descriptor.availability.reason.nilIfEmpty ?? "Native tool execution is blocked by host policy"
      )
    }
    if descriptor.availability.status != .available {
      return decision(
        descriptor: descriptor,
        allowed: false,
        code: "tool_unavailable",
        message: descriptor.availability.reason.nilIfEmpty ?? "Native tool is not currently available"
      )
    }
    let validation = validateInput(id, input: input)
    if !validation.isValid {
      return decision(
        descriptor: descriptor,
        allowed: false,
        code: "invalid_input",
        message: "Native tool input does not satisfy its JSON schema",
        validationIssues: validation.issues
      )
    }
    let missingPermissions = descriptor.requiredPermissions
      .filter { $0.required && !context.grantedPermissions.contains($0.id) }
      .sorted { $0.id < $1.id }
    if !missingPermissions.isEmpty {
      return decision(
        descriptor: descriptor,
        allowed: false,
        code: "missing_permissions",
        message: "Native tool requires permissions that were not granted",
        missingPermissions: missingPermissions
      )
    }
    let missingConsents = descriptor.requiredConsents
      .filter { $0.required && !context.grantedConsents.contains($0.id) }
      .sorted { $0.id < $1.id }
    if !missingConsents.isEmpty {
      return decision(
        descriptor: descriptor,
        allowed: false,
        code: "missing_consents",
        message: "Native tool requires user consent that was not granted",
        missingConsents: missingConsents
      )
    }
    if descriptor.idempotency == .idempotencyKeyRequired && context.idempotencyKey == nil {
      return decision(
        descriptor: descriptor,
        allowed: false,
        code: "missing_idempotency_key",
        message: "Native tool requires an idempotency key"
      )
    }
    return decision(
      descriptor: descriptor,
      allowed: true,
      code: "ok",
      message: "Native tool invocation is authorized"
    )
  }

  func makeResult(
    _ id: String,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext = AgentNativeToolInvocationContext(),
    status: AgentNativeToolResultStatus,
    output: AgentMcpJSONObject = [:],
    message: String = "",
    metadata: AgentMcpJSONObject = [:],
    error: AgentNativeToolError? = nil,
    verification: AgentNativeToolVerification? = nil,
    startedAtEpochMillis: Int64? = nil,
    finishedAtEpochMillis: Int64? = nil,
    replayed: Bool = false,
    originalInvocationId: String? = nil
  ) -> AgentNativeToolResult {
    let definition = lookup(id)
    let descriptor = definition?.descriptor
    let startedAt = max(0, startedAtEpochMillis ?? context.requestedAtEpochMillis)
    let finishedAt = max(startedAt, finishedAtEpochMillis ?? startedAt)
    return AgentNativeToolResult(
      status: status,
      output: output,
      message: message,
      metadata: metadata,
      error: error,
      verification: verification,
      receipt: AgentNativeToolReceipt(
        invocationId: context.invocationId,
        idempotencyKey: context.idempotencyKey,
        startedAtEpochMillis: startedAt,
        finishedAtEpochMillis: finishedAt,
        durationMillis: max(0, finishedAt - startedAt),
        status: status,
        inputSha256: AgentMcpJSONCodec.sha256(input),
        outputSha256: AgentMcpJSONCodec.sha256(output),
        replayed: replayed,
        originalInvocationId: originalInvocationId
      ),
      provenance: AgentNativeToolProvenance(
        toolId: descriptor?.id ?? id,
        toolVersion: descriptor?.version ?? "",
        location: descriptor?.location ?? .unknown,
        executorId: definition?.executorId ?? "unknown",
        contractVersion: Self.contractVersion,
        legacyAgentActionId: context.attributes[Self.legacyActionIdAttribute],
        metadata: definition?.provenanceMetadata ?? [:]
      )
    )
  }

  func preflightRejectionResult(
    _ id: String,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext = AgentNativeToolInvocationContext()
  ) -> AgentNativeToolResult? {
    let authorization = authorize(id, input: input, context: context)
    guard !authorization.allowed else { return nil }
    let unavailableCodes: Set<String> = ["tool_unavailable", "tool_blocked", "unknown_tool"]
    let status: AgentNativeToolResultStatus = unavailableCodes.contains(authorization.code)
      ? .unavailable
      : .rejected
    return makeResult(
      id,
      input: input,
      context: context,
      status: status,
      message: authorization.message,
      error: AgentNativeToolError(
        code: authorization.code,
        message: authorization.message,
        retryable: authorization.availability.status == .requiresSetup,
        details: authorizationDetails(authorization)
      )
    )
  }

  func invoke(
    _ id: String,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext = AgentNativeToolInvocationContext(),
    hooks: AgentNativeToolInvocationHooks = AgentNativeToolInvocationHooks()
  ) -> AgentNativeToolResult {
    guard let executable = executableById[id] else {
      if let definition = lookup(id) {
        return finishSynthetic(
          id,
          input: input,
          context: context,
          hooks: hooks,
          startedAtEpochMillis: hooks.nowMillis(),
          status: .unavailable,
          error: AgentNativeToolError(
            code: "missing_executor",
            message: "No executable native tool implementation is registered for id \(id)"
          ),
          risk: definition.descriptor.risk
        )
      } else {
        return finishSynthetic(
          id,
          input: input,
          context: context,
          hooks: hooks,
          startedAtEpochMillis: hooks.nowMillis(),
          status: .rejected,
          error: AgentNativeToolError(
            code: "unknown_tool",
            message: "No native tool is registered with id \(id)"
          ),
          risk: .blocked
        )
      }
    }

    let descriptor = executable.descriptor
    let startedAt = hooks.nowMillis()
    let deadline = min(context.deadlineEpochMillis ?? Int64.max, safeAdd(startedAt, descriptor.timeoutMillis))
    let invocation = AgentNativeToolInvocation(
      descriptor: descriptor,
      input: input,
      context: context,
      startedAtEpochMillis: startedAt,
      deadlineEpochMillis: deadline,
      nowMillis: hooks.nowMillis,
      cancellationRequested: hooks.cancellationRequested,
      progressReporter: hooks.onProgress
    )
    hooks.onStarted(invocation)

    func finish(
      status: AgentNativeToolResultStatus,
      output: AgentMcpJSONObject = [:],
      message: String = "",
      metadata: AgentMcpJSONObject = [:],
      error: AgentNativeToolError? = nil,
      verification: AgentNativeToolVerification? = nil,
      replayed: Bool = false,
      originalInvocationId: String? = nil,
      finishedAtEpochMillis: Int64? = nil
    ) -> AgentNativeToolResult {
      let result = makeResult(
        id,
        input: input,
        context: context,
        status: status,
        output: output,
        message: message,
        metadata: metadata,
        error: error,
        verification: verification,
        startedAtEpochMillis: startedAt,
        finishedAtEpochMillis: finishedAtEpochMillis ?? hooks.nowMillis(),
        replayed: replayed,
        originalInvocationId: originalInvocationId
      )
      appendAudit(result, context: context, risk: descriptor.risk)
      hooks.onFinished(result)
      return result
    }

    do {
      try invocation.checkpoint()

      if let preflight = preflightRejectionResult(id, input: input, context: context) {
        let result = makeResult(
          id,
          input: input,
          context: context,
          status: preflight.status,
          message: preflight.message,
          error: preflight.error,
          startedAtEpochMillis: startedAt,
          finishedAtEpochMillis: hooks.nowMillis()
        )
        appendAudit(result, context: context, risk: descriptor.risk)
        hooks.onFinished(result)
        return result
      }

      let replay = replayStore.cachedResult(descriptor: descriptor, input: input, context: context)
      switch replay.0.code {
      case .conflict:
        return finish(
          status: .rejected,
          error: AgentNativeToolError(
            code: "idempotency_key_conflict",
            message: "The idempotency key was already used with different input"
          )
        )
      case .replay:
        if let cached = replay.1 {
          return finish(
            status: cached.status,
            output: cached.output,
            message: cached.message,
            metadata: cached.metadata,
            error: cached.error,
            verification: cached.verification,
            replayed: true,
            originalInvocationId: cached.receipt.originalInvocationId ?? cached.receipt.invocationId
          )
        }
      case .bypassed, .accepted, .keyRequired, .unknownTool:
        break
      }

      let execution = try executable.executor(invocation)
      try invocation.checkpoint()
      if !execution.isSuccess {
        return finish(
          status: .failed,
          output: execution.output,
          message: execution.message,
          metadata: execution.metadata,
          error: execution.error
        )
      }

      let outputValidation = AgentNativeJsonSchemaValidator.validateObject(
        schema: descriptor.outputSchema,
        object: execution.output
      )
      if !outputValidation.isValid {
        return finish(
          status: .failed,
          output: execution.output,
          message: execution.message,
          metadata: execution.metadata,
          error: AgentNativeToolError(
            code: "invalid_output",
            message: "Native tool output does not satisfy its JSON schema",
            details: validationDetails(outputValidation)
          )
        )
      }

      let verification = try executable.verifier?(invocation, execution)
      try invocation.checkpoint()
      if verification?.status == .failed {
        let verificationMessage = verification?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return finish(
          status: .verificationFailed,
          output: execution.output,
          message: execution.message,
          metadata: execution.metadata,
          error: AgentNativeToolError(
            code: "verification_failed",
            message: verificationMessage.isEmpty ? "Native tool verification failed" : verificationMessage
          ),
          verification: verification
        )
      }

      let result = finish(
        status: .succeeded,
        output: execution.output,
        message: execution.message,
        metadata: execution.metadata,
        verification: verification
      )
      replayStore.recordResult(
        descriptor: descriptor,
        input: input,
        context: context,
        result: result
      )
      return result
    } catch AgentNativeToolInvocationError.cancelled {
      hooks.onCancelled(invocation)
      return finish(
        status: .cancelled,
        error: AgentNativeToolError(
          code: "cancelled",
          message: "Native tool invocation was cancelled",
          retryable: true
        )
      )
    } catch AgentNativeToolInvocationError.timedOut {
      hooks.onTimeout(invocation)
      return finish(
        status: .timedOut,
        error: AgentNativeToolError(
          code: "timeout",
          message: "Native tool invocation exceeded its deadline",
          retryable: true
        )
      )
    } catch {
      return finish(
        status: .failed,
        error: AgentNativeToolError(
          code: "tool_invocation_failed",
          message: error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
        )
      )
    }
  }

  func replayDecision(
    _ id: String,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext
  ) -> AgentNativeToolReplayDecision {
    guard let definition = lookup(id) else {
      return AgentNativeToolReplayDecision(
        code: .unknownTool,
        replayed: false,
        originalInvocationId: nil,
        inputSha256: AgentMcpJSONCodec.sha256(input)
      )
    }
    return replayStore.decide(
      descriptor: definition.descriptor,
      input: input,
      context: context
    )
  }

  private func authorizationDetails(_ decision: AgentNativeToolAuthorizationDecision) -> AgentMcpJSONObject {
    var details: AgentMcpJSONObject = [
      "availability": .string(decision.availability.status.rawValue),
      "risk": .string(decision.risk.rawValue)
    ]
    if !decision.missingPermissions.isEmpty {
      details["missing_permissions"] = .array(decision.missingPermissions.map { .object(requirementValue($0)) })
    }
    if !decision.missingConsents.isEmpty {
      details["missing_consents"] = .array(decision.missingConsents.map { .object(requirementValue($0)) })
    }
    if !decision.validationIssues.isEmpty {
      details["validation_issues"] = .array(decision.validationIssues.map { issue in
        .object([
          "path": .string(issue.path),
          "code": .string(issue.code),
          "message": .string(issue.message)
        ])
      })
    }
    return details
  }

  private func finishSynthetic(
    _ id: String,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext,
    hooks: AgentNativeToolInvocationHooks,
    startedAtEpochMillis: Int64,
    status: AgentNativeToolResultStatus,
    error: AgentNativeToolError,
    risk: AgentNativeToolRisk
  ) -> AgentNativeToolResult {
    let result = makeResult(
      id,
      input: input,
      context: context,
      status: status,
      message: error.message,
      error: error,
      startedAtEpochMillis: startedAtEpochMillis,
      finishedAtEpochMillis: hooks.nowMillis()
    )
    appendAudit(result, context: context, risk: risk)
    hooks.onFinished(result)
    return result
  }

  private func appendAudit(
    _ result: AgentNativeToolResult,
    context: AgentNativeToolInvocationContext,
    risk: AgentNativeToolRisk
  ) {
    auditStore.append(AgentNativeToolAuditRecord.from(result: result, context: context, risk: risk))
  }

  private func validationDetails(_ result: AgentNativeValidationResult) -> AgentMcpJSONObject {
    [
      "issues": .array(result.issues.map { issue in
        .object([
          "path": .string(issue.path),
          "code": .string(issue.code),
          "message": .string(issue.message)
        ])
      })
    ]
  }

  private func decision(
    descriptor: AgentNativeToolDescriptor,
    allowed: Bool,
    code: String,
    message: String,
    missingPermissions: [AgentNativePermissionRequirement] = [],
    missingConsents: [AgentNativeConsentRequirement] = [],
    validationIssues: [AgentNativeValidationIssue] = []
  ) -> AgentNativeToolAuthorizationDecision {
    AgentNativeToolAuthorizationDecision(
      toolId: descriptor.id,
      allowed: allowed,
      code: code,
      message: message,
      availability: descriptor.availability,
      risk: descriptor.risk,
      missingPermissions: missingPermissions,
      missingConsents: missingConsents,
      validationIssues: validationIssues
    )
  }

  private func catalogValue(_ descriptor: AgentNativeToolDescriptor) -> AgentMcpJSONObject {
    [
      "id": .string(descriptor.id),
      "version": .string(descriptor.version),
      "title": .string(descriptor.title),
      "description": .string(descriptor.description),
      "location": .string(descriptor.location.rawValue),
      "input_schema": .object(descriptor.inputSchema),
      "output_schema": .object(descriptor.outputSchema),
      "risk": .string(descriptor.risk.rawValue),
      "capabilities": .array(descriptor.capabilities.sorted().map(AgentMcpJSONValue.string)),
      "required_permissions": .array(descriptor.requiredPermissions.sorted { $0.id < $1.id }.map {
        .object(requirementValue($0))
      }),
      "required_consents": .array(descriptor.requiredConsents.sorted { $0.id < $1.id }.map {
        .object(requirementValue($0))
      }),
      "timeout_ms": .int(descriptor.timeoutMillis),
      "idempotency": .string(descriptor.idempotency.rawValue),
      "availability": .object([
        "status": .string(descriptor.availability.status.rawValue),
        "reason": .string(descriptor.availability.reason),
        "checked_at_epoch_ms": descriptor.availability.checkedAtEpochMillis.map(AgentMcpJSONValue.int) ?? .null
      ])
    ]
  }

  private func requirementValue(_ requirement: AgentNativePermissionRequirement) -> AgentMcpJSONObject {
    [
      "id": .string(requirement.id),
      "title": .string(requirement.title),
      "description": .string(requirement.description),
      "required": .bool(requirement.required)
    ]
  }

  private func requirementValue(_ requirement: AgentNativeConsentRequirement) -> AgentMcpJSONObject {
    [
      "id": .string(requirement.id),
      "title": .string(requirement.title),
      "description": .string(requirement.description),
      "required": .bool(requirement.required)
    ]
  }
}

enum AgentPhoneNativeToolCatalog {
  static let workspaceInitialize = "signalasi.workspace.initialize"
  static let workspaceMkdir = "signalasi.workspace.directory.create"
  static let workspaceList = "signalasi.workspace.directory.list"
  static let workspaceStat = "signalasi.workspace.file.stat"
  static let workspaceReadText = "signalasi.workspace.file.read.text"
  static let workspaceReadBytes = "signalasi.workspace.file.read.bytes"
  static let workspaceWriteText = "signalasi.workspace.file.write.text"
  static let workspaceCreateText = "signalasi.workspace.file.create.text"
  static let workspaceAppendText = "signalasi.workspace.file.append.text"
  static let workspaceWriteBytes = "signalasi.workspace.file.write.bytes"
  static let workspaceCreateBytes = "signalasi.workspace.file.create.bytes"
  static let workspaceAppendBytes = "signalasi.workspace.file.append.bytes"
  static let workspaceMove = "signalasi.workspace.entry.move"
  static let workspaceCopy = "signalasi.workspace.entry.copy"
  static let workspaceDelete = "signalasi.workspace.entry.delete"
  static let workspaceSearchText = "signalasi.workspace.file.search.text"
  static let workspaceApplyExactPatch = "signalasi.workspace.file.patch.exact"
  static let workspaceDiffSummary = "signalasi.workspace.file.diff.summary"
  static let workspaceSha256 = "signalasi.workspace.file.sha256"
  static let workspaceZipCreate = "signalasi.workspace.zip.create"
  static let workspaceZipList = "signalasi.workspace.zip.list"
  static let workspaceZipExtract = "signalasi.workspace.zip.extract"

  static let workspacePrivatePermission = "signalasi.scope.app_private_workspace"
  static let workspaceReadConsent = "signalasi.consent.workspace_read"
  static let workspaceWriteConsent = "signalasi.consent.workspace_write"

  static let version = "1.0.0"
  static let fileExecutorId = "signalasi.workspace_file_tools"
  static let actionExecutorId = "signalasi.ios_agent_action"
  static let descriptorExecutorId = "signalasi.ios_native_catalog"

  static let supportedActionKinds: [AgentActionKind] = [
    .readScreen,
    .tap,
    .typeText,
    .swipe,
    .longPress,
    .deleteText,
    .pasteText,
    .copyScreenText,
    .back,
    .home,
    .recents,
    .lockScreen,
    .openApp,
    .openURL,
    .setAlarm,
    .replyNotification
  ]

  static let toolIds: Set<String> = Set(workspaceToolIds + supportedActionKinds.map {
    AgentNativeToolAgentActionAdapter.defaultToolId($0)
  })
    .union(AgentIOSSystemNativeToolCatalog.toolIds)
    .union(AgentIOSHardwareNativeToolCatalog.toolIds)
    .union(AgentIOSHomeAssistantNativeToolCatalog.toolIds)
    .union(AgentIOSNotificationNativeToolCatalog.toolIds)
    .union(AgentIOSVisibleCaptureNativeToolCatalog.toolIds)
    .union(AgentIOSWebMediaNativeToolCatalog.toolIds)
    .union(AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    .union(AgentIOSMediaNativeToolCatalog.toolIds)
    .union(AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    .union(AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    .union(AgentMcpNativeTools.toolIds)
    .union(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)

  static let defaultToolIds: Set<String> = toolIds
    .union(AgentPhoneCapabilityNativeCoverage.coveredToolIds)
    .union(AgentIOSWebMediaNativeToolCatalog.toolIds)
    .union(AgentIOSMediaNativeToolCatalog.toolIds)
    .union(AgentIOSWebIntelligenceNativeToolCatalog.toolIds)
    .union(AgentIOSSystemNativeToolCatalog.toolIds)
    .union(AgentIOSSelfEvolutionNativeToolCatalog.toolIds)
    .union(AgentIOSDesktopRemoteNativeToolCatalog.toolIds)
    .union(AgentMcpNativeTools.toolIds)
    .union(AgentIOSOnDeviceRuntimeNativeToolCatalog.toolIds)

  static func definitions(
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses()
  ) -> [AgentPhoneNativeToolDefinition] {
    workspaceDefinitions() +
      actionDefinitions(capabilityStatuses: capabilityStatuses) +
      AgentIOSSystemNativeToolCatalog.definitions() +
      AgentIOSHardwareNativeToolCatalog.definitions() +
      AgentIOSHomeAssistantNativeToolCatalog.definitions() +
      AgentIOSNotificationNativeToolCatalog.definitions() +
      AgentIOSVisibleCaptureNativeToolCatalog.definitions() +
      AgentIOSWebMediaNativeToolCatalog.definitions() +
      AgentIOSWebIntelligenceNativeToolCatalog.definitions() +
      AgentIOSMediaNativeToolCatalog.definitions() +
      AgentIOSSelfEvolutionNativeToolCatalog.definitions() +
      AgentIOSDesktopRemoteNativeToolCatalog.definitions() +
      AgentMcpNativeTools.definitions() +
      AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions()
  }

  static func descriptors(
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses()
  ) -> [AgentNativeToolDescriptor] {
    definitions(capabilityStatuses: capabilityStatuses).map(\.descriptor)
  }

  static func workspaceExecutableDefinitions(
    store: AgentWorkspaceNativeToolExecutor = AgentWorkspaceNativeToolExecutor()
  ) -> [AgentNativeToolExecutableDefinition] {
    workspaceDefinitions().map(store.executableDefinition)
  }

  static func systemExecutableDefinitions(
    executor: AgentIOSSystemNativeToolExecutor = AgentIOSSystemNativeToolExecutor()
  ) -> [AgentNativeToolExecutableDefinition] {
    AgentIOSSystemNativeToolCatalog.definitions()
      .filter { AgentIOSSystemNativeToolCatalog.executableToolIds.contains($0.id) }
      .map(executor.executableDefinition)
  }

  static func hardwareExecutableDefinitions(
    executor: AgentIOSHardwareNativeToolExecutor = AgentIOSHardwareNativeToolExecutor()
  ) -> [AgentNativeToolExecutableDefinition] {
    AgentIOSHardwareNativeToolCatalog.definitions()
      .filter { AgentIOSHardwareNativeToolCatalog.executableToolIds.contains($0.id) }
      .map(executor.executableDefinition)
  }

  static func homeAssistantExecutableDefinitions(
    provider: AgentIOSHomeAssistantToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSHomeAssistantNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSHomeAssistantNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func notificationExecutableDefinitions(
    provider: AgentIOSNotificationToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSNotificationNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSNotificationNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func visibleCaptureExecutableDefinitions(
    provider: AgentIOSVisibleCaptureToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSVisibleCaptureNativeToolExecutor(provider: provider)
    return AgentIOSVisibleCaptureNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func webIntelligenceExecutableDefinitions(
    provider: AgentIOSWebIntelligenceToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSWebIntelligenceNativeToolExecutor(provider: provider)
    return AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func webMediaExecutableDefinitions(
    provider: AgentIOSWebMediaToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSWebMediaNativeToolExecutor(provider: provider)
    return AgentIOSWebMediaNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func mediaExecutableDefinitions(
    provider: AgentIOSMediaNativeToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSMediaNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSMediaNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func selfEvolutionExecutableDefinitions(
    provider: AgentIOSSelfEvolutionToolProviding,
    nowMillis: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) }
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSSelfEvolutionNativeToolExecutor(provider: provider, nowMillis: nowMillis)
    return AgentIOSSelfEvolutionNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func desktopRemoteExecutableDefinitions(
    provider: AgentIOSDesktopRemoteToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSDesktopRemoteNativeToolExecutor(provider: provider)
    return AgentIOSDesktopRemoteNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func mcpExecutableDefinitions(
    provider: AgentIOSMcpNativeToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSMcpNativeToolExecutor(provider: provider)
    return AgentMcpNativeTools.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func onDeviceRuntimeExecutableDefinitions(
    provider: AgentIOSOnDeviceRuntimeToolProviding
  ) -> [AgentNativeToolExecutableDefinition] {
    let executor = AgentIOSOnDeviceRuntimeNativeToolExecutor(provider: provider)
    return AgentIOSOnDeviceRuntimeNativeToolCatalog.definitions(provider: provider).map(executor.executableDefinition)
  }

  static func actionExecutableDefinitions(
    delegate: AgentActionExecutor,
    screenProvider: @escaping (AgentNativeToolInvocation) -> AgentScreenContext,
    capabilityStatuses: [AgentPhoneCapabilityStatus] = AgentPhoneCapabilityCatalog.declaredStatuses()
  ) -> [AgentNativeToolExecutableDefinition] {
    zip(supportedActionKinds, actionDefinitions(capabilityStatuses: capabilityStatuses)).map { kind, definition in
      AgentActionNativeToolExecutor.executableDefinition(
        definition: definition,
        delegate: delegate,
        kind: kind,
        screenProvider: screenProvider
      )
    }
  }

  static func capabilities(for kind: AgentActionKind) -> Set<AgentPhoneCapabilityId> {
    switch kind {
    case .readScreen:
      return [.accessibilityUITree]
    case .copyScreenText:
      return [.accessibilityUITree, .clipboard]
    case .pasteText:
      return [.accessibilityGestures, .clipboard]
    case .tap, .typeText, .swipe, .longPress, .deleteText, .back, .home, .recents, .lockScreen:
      return [.accessibilityGestures]
    case .openApp, .openURL, .setAlarm:
      return [.intentLaunch]
    case .replyNotification:
      return [.notificationReply]
    case .saveScreenKnowledge, .draftPlan, .createNotification, .importWebKnowledge, .callConnector, .callNativeTool, .controlDevice:
      return []
    }
  }

  private static func workspaceDefinitions() -> [AgentPhoneNativeToolDefinition] {
    [
      workspaceDefinition(workspaceInitialize, "Initialize app-private workspace", .low, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceMkdir, "Create workspace directory", .low, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceList, "List workspace directory", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceStat, "Inspect workspace entry", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceReadText, "Read workspace text file", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceReadBytes, "Read workspace binary file", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceWriteText, "Write workspace text file", .medium, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceCreateText, "Create workspace text file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceAppendText, "Append workspace text file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceWriteBytes, "Write workspace binary file", .medium, workspaceWriteConsent, .idempotent),
      workspaceDefinition(workspaceCreateBytes, "Create workspace binary file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceAppendBytes, "Append workspace binary file", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceMove, "Move workspace entry", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceCopy, "Copy workspace entry", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceDelete, "Delete workspace entry", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceSearchText, "Search workspace text", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceApplyExactPatch, "Apply exact workspace patch", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceDiffSummary, "Summarize workspace diff", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceSha256, "Hash workspace file", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceZipCreate, "Create workspace zip", .medium, workspaceWriteConsent, .idempotencyKeyRequired),
      workspaceDefinition(workspaceZipList, "List workspace zip", .low, workspaceReadConsent, .idempotent),
      workspaceDefinition(workspaceZipExtract, "Extract workspace zip", .medium, workspaceWriteConsent, .idempotencyKeyRequired)
    ]
  }

  private static func workspaceDefinition(
    _ id: String,
    _ title: String,
    _ risk: AgentNativeToolRisk,
    _ consentId: String,
    _ idempotency: AgentNativeToolIdempotency
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: id,
      version: version,
      title: title,
      description: "Bounded operation inside SignalASI app-private Agent workspace storage.",
      location: .application,
      inputSchema: workspaceInputSchema(id),
      outputSchema: workspaceOutputSchema(id),
      risk: risk,
      capabilities: ["workspace.app_private", "workspace.file.bounded"],
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: workspacePrivatePermission,
          title: "App-private workspace scope",
          description: "Restricts access to SignalASI-owned workspace storage."
        )
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: consentId,
          title: consentId == workspaceReadConsent ? "Read app-private workspace" : "Modify app-private workspace",
          description: "Authorizes this invocation to access the selected Agent workspace."
        )
      ],
      timeoutMillis: 15_000,
      idempotency: idempotency,
      availability: .available
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: fileExecutorId,
      provenanceMetadata: [
        "storage_scope": "app_private",
        "path_policy": "workspace_relative_no_symlinks",
        "result_policy": "bounded-v1"
      ]
    )
  }

  private static func actionDefinitions(
    capabilityStatuses: [AgentPhoneCapabilityStatus]
  ) -> [AgentPhoneNativeToolDefinition] {
    supportedActionKinds.map { kind in
      let capabilityIds = capabilities(for: kind)
      let boundaries = capabilityIds.map { AgentPhoneCapabilityCatalog.find($0) }
      let descriptor = try! AgentNativeToolDescriptor(
        id: AgentNativeToolAgentActionAdapter.defaultToolId(kind),
        version: version,
        title: actionTitle(kind),
        description: actionDescription(kind),
        location: nativeLocation(boundaries),
        inputSchema: actionInputSchema(kind),
        outputSchema: actionOutputSchema(),
        risk: nativeRisk(boundaries.map(\.risk).max { $0.weight < $1.weight }),
        capabilities: Set(capabilityIds.map(\.wireId)),
        requiredPermissions: permissionRequirements(boundaries),
        requiredConsents: consentRequirements(boundaries),
        timeoutMillis: 15_000,
        idempotency: .nonIdempotent,
        availability: capabilityAvailability(capabilityIds, statuses: capabilityStatuses)
      )
      return AgentPhoneNativeToolDefinition(
        descriptor: descriptor,
        executorId: actionExecutorId,
        provenanceMetadata: [
          "adapter": "AgentActionExecutor",
          "legacy_action_kind": kind.rawValue,
          "result_policy": "bounded-v1",
          "platform": "ios"
        ]
      )
    }
  }

  private static func permissionRequirements(
    _ boundaries: [AgentPhoneCapabilityBoundary]
  ) -> [AgentNativePermissionRequirement] {
    var requirements: [String: AgentNativePermissionRequirement] = [:]
    for boundary in boundaries {
      for permission in boundary.platformPermissions.sorted() {
        requirements[permission] = AgentNativePermissionRequirement(
          id: permission,
          title: permission,
          description: "iOS permission or Info.plist usage key required by \(boundary.id.wireId)."
        )
      }
      for access in boundary.specialAccess.sorted(by: { $0.rawValue < $1.rawValue }) {
        let id = "signalasi.special_access.\(access.rawValue.lowercased())"
        requirements[id] = AgentNativePermissionRequirement(
          id: id,
          title: access.rawValue.replacingOccurrences(of: "_", with: " ").lowercased(),
          description: "Special platform access required by \(boundary.id.wireId)."
        )
      }
    }
    if requirements.isEmpty {
      requirements[normalAppExecutionPermission] = AgentNativePermissionRequirement(
        id: normalAppExecutionPermission,
        title: "Normal app execution",
        description: "No runtime permission or special-access grant is required.",
        required: false
      )
    }
    return requirements.values.sorted { $0.id < $1.id }
  }

  private static func consentRequirements(
    _ boundaries: [AgentPhoneCapabilityBoundary]
  ) -> [AgentNativeConsentRequirement] {
    let consents = boundaries.reduce(into: Set<AgentPhoneUserConsent>()) { result, boundary in
      result.formUnion(boundary.userConsent)
    }
    if consents.isEmpty || consents == Set([.none]) {
      return [
        AgentNativeConsentRequirement(
          id: "signalasi.consent.none",
          title: "No additional consent",
          description: "This capability has no additional interactive consent requirement.",
          required: false
        )
      ]
    }
    return consents
      .filter { $0 != .none }
      .sorted { $0.rawValue < $1.rawValue }
      .map { consent in
        AgentNativeConsentRequirement(
          id: "signalasi.consent.\(consent.rawValue.lowercased())",
          title: consent.rawValue.replacingOccurrences(of: "_", with: " ").lowercased(),
          description: "User consent required by the phone capability boundary."
        )
      }
  }

  private static func capabilityAvailability(
    _ ids: Set<AgentPhoneCapabilityId>,
    statuses: [AgentPhoneCapabilityStatus]
  ) -> AgentNativeToolAvailability {
    guard !ids.isEmpty else {
      return AgentNativeToolAvailability(status: .unavailable, reason: "No phone capability mapping is declared")
    }
    let byId = Dictionary(uniqueKeysWithValues: statuses.map { ($0.boundary.id, $0) })
    let resolved = ids.map { id in
      byId[id] ?? AgentPhoneCapabilityStatus(
        boundary: AgentPhoneCapabilityCatalog.find(id),
        availability: .unknown,
        evidence: "Capability status was not provided"
      )
    }
    if let unavailable = resolved.first(where: { $0.availability.nativeAvailabilityStatus == .unavailable }) {
      return AgentNativeToolAvailability(
        status: .unavailable,
        reason: unavailable.evidence.isEmpty ? unavailable.boundary.limitation : unavailable.evidence
      )
    }
    if let setup = resolved.first(where: { $0.availability.nativeAvailabilityStatus == .requiresSetup }) {
      return AgentNativeToolAvailability(
        status: .requiresSetup,
        reason: setup.evidence.isEmpty ? setup.boundary.limitation : setup.evidence
      )
    }
    let limitedReason = resolved
      .filter { $0.availability == .limited }
      .map(\.boundary.limitation)
      .joined(separator: "; ")
    return AgentNativeToolAvailability(status: .available, reason: String(limitedReason.prefix(maxReasonCharacters)))
  }

  private static func nativeLocation(_ boundaries: [AgentPhoneCapabilityBoundary]) -> AgentNativeToolLocation {
    if boundaries.contains(where: { $0.executionLocation == .accessibilityService }) {
      return .accessibilityService
    }
    if boundaries.contains(where: {
      $0.executionLocation == .androidSystemService ||
        $0.executionLocation == .systemUIHandoff ||
        $0.executionLocation == .notificationListenerService ||
        $0.executionLocation == .screenCaptureService
    }) {
      return .androidSystem
    }
    if boundaries.allSatisfy({ $0.executionLocation == .appProcess }) {
      return .application
    }
    return .phone
  }

  private static func nativeRisk(_ risk: AgentRisk?) -> AgentNativeToolRisk {
    switch risk ?? .medium {
    case .low: return .low
    case .medium: return .medium
    case .high: return .high
    case .blocked: return .blocked
    }
  }

  private static func actionTitle(_ kind: AgentActionKind) -> String {
    kind.rawValue.replacingOccurrences(of: "_", with: " ").lowercased().capitalized
  }

  private static func actionDescription(_ kind: AgentActionKind) -> String {
    switch kind {
    case .readScreen:
      return "Reads bounded screen context through the iOS phone action adapter when the capability boundary allows it."
    case .tap, .typeText, .swipe, .longPress, .deleteText, .pasteText, .copyScreenText, .back, .home, .recents, .lockScreen:
      return "Adapts a legacy phone action into a native tool descriptor with iOS capability, consent, and risk metadata."
    case .openApp, .openURL, .setAlarm:
      return "Hands work to an app or system UI surface while keeping target completion untrusted."
    case .replyNotification:
      return "Replies only through SignalASI-owned notification actions and explicit user confirmation."
    case .saveScreenKnowledge, .draftPlan, .createNotification, .importWebKnowledge, .callConnector, .callNativeTool, .controlDevice:
      return "Unsupported phone-native action kind for this catalog."
    }
  }

  private static func workspaceInputSchema(_ id: String) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONValue] = [
      "workspace_id": .object(stringSchema(minLength: 1, maxLength: 64))
    ]
    var required: [String] = ["workspace_id"]
    if id == workspaceInitialize {
      return objectSchema(properties: properties, required: required)
    }
    if id == workspaceList {
      properties["path"] = .object(stringSchema(maxLength: 1_024))
      properties["recursive"] = .object(boolSchema())
      properties["max_entries"] = .object(integerSchema(minimum: 1))
      return objectSchema(properties: properties, required: required)
    }
    if [workspaceMove, workspaceCopy].contains(id) {
      properties["source_path"] = .object(stringSchema(maxLength: 1_024))
      properties["destination_path"] = .object(stringSchema(maxLength: 1_024))
      properties["overwrite"] = .object(boolSchema())
      properties["create_parents"] = .object(boolSchema())
      return objectSchema(properties: properties, required: ["workspace_id", "source_path", "destination_path"])
    }
    if id == workspaceZipCreate {
      properties["archive_path"] = .object(stringSchema(maxLength: 1_024))
      properties["source_paths"] = .object(arraySchema(items: stringSchema(maxLength: 1_024), minItems: 1, maxItems: 2_048))
      properties["overwrite"] = .object(boolSchema())
      properties["create_parents"] = .object(boolSchema())
      return objectSchema(properties: properties, required: ["workspace_id", "archive_path", "source_paths"])
    }
    if id == workspaceZipList {
      properties["archive_path"] = .object(stringSchema(maxLength: 1_024))
      return objectSchema(properties: properties, required: ["workspace_id", "archive_path"])
    }
    if id == workspaceZipExtract {
      properties["archive_path"] = .object(stringSchema(maxLength: 1_024))
      properties["destination_path"] = .object(stringSchema(maxLength: 1_024))
      properties["overwrite"] = .object(boolSchema())
      return objectSchema(properties: properties, required: ["workspace_id", "archive_path", "destination_path"])
    }
    if id != workspaceInitialize {
      properties["path"] = .object(stringSchema(maxLength: 1_024))
      required.append("path")
    }
    if [workspaceMkdir, workspaceDelete].contains(id) {
      properties["recursive"] = .object(boolSchema())
    }
    if [workspaceReadText, workspaceReadBytes].contains(id) {
      properties["max_bytes"] = .object(integerSchema(minimum: 1))
    }
    if [workspaceWriteText, workspaceCreateText, workspaceAppendText].contains(id) {
      properties["text"] = .object(stringSchema(maxLength: 1_048_576))
      required.append("text")
    }
    if [workspaceWriteText, workspaceCreateText].contains(id) {
      properties["create_parents"] = .object(boolSchema())
    }
    if [workspaceWriteBytes, workspaceCreateBytes, workspaceAppendBytes].contains(id) {
      properties["base64"] = .object(stringSchema(maxLength: 22_369_624))
      required.append("base64")
    }
    if [workspaceWriteBytes, workspaceCreateBytes].contains(id) {
      properties["create_parents"] = .object(boolSchema())
    }
    if id == workspaceSearchText {
      properties["query"] = .object(stringSchema(minLength: 1, maxLength: 4_096))
      properties["case_sensitive"] = .object(boolSchema())
      properties["max_results"] = .object(integerSchema(minimum: 1))
      required.append("query")
    }
    if id == workspaceApplyExactPatch {
      properties["expected_text"] = .object(stringSchema(minLength: 1, maxLength: 1_048_576))
      properties["replacement_text"] = .object(stringSchema(maxLength: 1_048_576))
      properties["expected_occurrences"] = .object(integerSchema(minimum: 1))
      required.append(contentsOf: ["expected_text", "replacement_text"])
    }
    if id == workspaceDiffSummary {
      properties["proposed_text"] = .object(stringSchema(maxLength: 1_048_576))
      required.append("proposed_text")
    }
    return objectSchema(properties: properties, required: required)
  }

  private static func workspaceOutputSchema(_ id: String) -> AgentMcpJSONObject {
    if id == workspaceList {
      return directoryListingSchema()
    }
    if id == workspaceStat {
      return workspaceMetadataSchema()
    }
    if id == workspaceReadText {
      return textReadSchema()
    }
    if id == workspaceReadBytes {
      return bytesReadSchema()
    }
    if id == workspaceSearchText {
      return searchResultSchema()
    }
    if id == workspaceApplyExactPatch {
      return patchResultSchema()
    }
    if id == workspaceDiffSummary {
      return diffSummarySchema()
    }
    if id == workspaceSha256 {
      return digestSchema()
    }
    if [workspaceZipCreate, workspaceZipList].contains(id) {
      return zipListingSchema()
    }
    if id == workspaceZipExtract {
      return zipExtractionSchema()
    }
    return mutationSchema()
  }

  private static func workspaceMetadataSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "type": .object(enumStringSchema(["file", "directory"])),
      "size_bytes": .object(integerSchema(minimum: 0)),
      "last_modified_epoch_ms": .object(integerSchema(minimum: 0))
    ], required: ["path", "type", "size_bytes", "last_modified_epoch_ms"])
  }

  private static func mutationSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "kind": .object(stringSchema(maxLength: 64)),
      "path": .object(stringSchema(maxLength: 4_096)),
      "source_path": .object(stringSchema(maxLength: 4_096)),
      "affected_entries": .object(integerSchema(minimum: 0)),
      "affected_bytes": .object(integerSchema(minimum: 0)),
      "metadata": .object(workspaceMetadataSchema())
    ], required: ["kind", "path", "source_path", "affected_entries", "affected_bytes"])
  }

  private static func directoryListingSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "recursive": .object(boolSchema()),
      "entries": .object(arraySchema(items: workspaceMetadataSchema(), maxItems: 10_000))
    ], required: ["path", "recursive", "entries"])
  }

  private static func textReadSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "text": .object(stringSchema(maxLength: 1_048_576)),
      "size_bytes": .object(integerSchema(minimum: 0)),
      "sha256": .object(stringSchema(minLength: 64, maxLength: 64))
    ], required: ["path", "text", "size_bytes", "sha256"])
  }

  private static func bytesReadSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "base64": .object(stringSchema(maxLength: 11_184_812)),
      "metadata": .object(workspaceMetadataSchema()),
      "sha256": .object(stringSchema(minLength: 64, maxLength: 64))
    ], required: ["path", "base64", "metadata", "sha256"])
  }

  private static func searchResultSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "query": .object(stringSchema(maxLength: 4_096)),
      "matches": .object(arraySchema(items: objectSchema(properties: [
        "path": .object(stringSchema(maxLength: 4_096)),
        "line": .object(integerSchema(minimum: 1)),
        "column": .object(integerSchema(minimum: 1)),
        "excerpt": .object(stringSchema(maxLength: 512))
      ], required: ["path", "line", "column", "excerpt"]), maxItems: 500)),
      "scanned_files": .object(integerSchema(minimum: 0)),
      "skipped_files": .object(integerSchema(minimum: 0)),
      "scanned_bytes": .object(integerSchema(minimum: 0)),
      "truncated": .object(boolSchema())
    ], required: ["query", "matches", "scanned_files", "skipped_files", "scanned_bytes", "truncated"])
  }

  private static func diffSummarySchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "before_sha256": .object(stringSchema(minLength: 64, maxLength: 64)),
      "after_sha256": .object(stringSchema(minLength: 64, maxLength: 64)),
      "before_bytes": .object(integerSchema(minimum: 0)),
      "after_bytes": .object(integerSchema(minimum: 0)),
      "before_lines": .object(integerSchema(minimum: 0)),
      "after_lines": .object(integerSchema(minimum: 0)),
      "added_lines": .object(integerSchema(minimum: 0)),
      "deleted_lines": .object(integerSchema(minimum: 0)),
      "changed_line_pairs": .object(integerSchema(minimum: 0)),
      "first_changed_line": .object(integerSchema(minimum: 1))
    ], required: [
      "before_sha256", "after_sha256", "before_bytes", "after_bytes",
      "before_lines", "after_lines", "added_lines", "deleted_lines", "changed_line_pairs"
    ])
  }

  private static func patchResultSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "replacements": .object(integerSchema(minimum: 1)),
      "diff": .object(diffSummarySchema()),
      "metadata": .object(workspaceMetadataSchema())
    ], required: ["path", "replacements", "diff", "metadata"])
  }

  private static func digestSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 4_096)),
      "algorithm": .object(enumStringSchema(["SHA-256"])),
      "hex": .object(stringSchema(minLength: 64, maxLength: 64)),
      "size_bytes": .object(integerSchema(minimum: 0))
    ], required: ["path", "algorithm", "hex", "size_bytes"])
  }

  private static func zipListingSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "archive_path": .object(stringSchema(maxLength: 4_096)),
      "archive_bytes": .object(integerSchema(minimum: 0)),
      "total_compressed_bytes": .object(integerSchema(minimum: 0)),
      "total_uncompressed_bytes": .object(integerSchema(minimum: 0)),
      "entries": .object(arraySchema(items: zipEntrySchema(), maxItems: 2_048))
    ], required: [
      "archive_path",
      "archive_bytes",
      "total_compressed_bytes",
      "total_uncompressed_bytes",
      "entries"
    ])
  }

  private static func zipExtractionSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "archive_path": .object(stringSchema(maxLength: 4_096)),
      "destination_path": .object(stringSchema(maxLength: 4_096)),
      "extracted_entries": .object(integerSchema(minimum: 0)),
      "extracted_bytes": .object(integerSchema(minimum: 0))
    ], required: ["archive_path", "destination_path", "extracted_entries", "extracted_bytes"])
  }

  private static func zipEntrySchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "path": .object(stringSchema(maxLength: 512)),
      "directory": .object(boolSchema()),
      "compressed_bytes": .object(integerSchema(minimum: 0)),
      "uncompressed_bytes": .object(integerSchema(minimum: 0)),
      "compression_ratio": .object(numberSchema(minimum: 0)),
      "crc32": .object(integerSchema(minimum: 0)),
      "last_modified_epoch_ms": .object(integerSchema(minimum: 0))
    ], required: [
      "path",
      "directory",
      "compressed_bytes",
      "uncompressed_bytes",
      "compression_ratio",
      "crc32",
      "last_modified_epoch_ms"
    ])
  }

  private static func actionInputSchema(_ kind: AgentActionKind) -> AgentMcpJSONObject {
    var properties: [String: AgentMcpJSONValue] = [
      "target": .object(stringSchema(maxLength: 512)),
      "parameters": .object(objectSchema(additionalProperties: true))
    ]
    var required: [String] = ["target"]
    if kind == .openURL {
      properties["url"] = .object(stringSchema(minLength: 1, maxLength: 2_048))
      required.append("url")
    }
    if kind == .replyNotification {
      properties["notification_key"] = .object(stringSchema(minLength: 1, maxLength: 1_024))
      properties["reply_text"] = .object(stringSchema(minLength: 1, maxLength: 16_384))
      required.append(contentsOf: ["notification_key", "reply_text"])
    }
    return objectSchema(properties: properties, required: required)
  }

  private static func actionOutputSchema() -> AgentMcpJSONObject {
    objectSchema(properties: [
      "action_id": .object(stringSchema(maxLength: 128)),
      "success": .object(["type": .string("boolean")]),
      "message": .object(stringSchema(maxLength: 2_048)),
      "metadata": .object(objectSchema(additionalProperties: true))
    ], required: ["action_id", "success", "message", "metadata"])
  }

  private static func objectSchema(
    properties: [String: AgentMcpJSONValue] = [:],
    required: [String] = [],
    additionalProperties: Bool = false
  ) -> AgentMcpJSONObject {
    [
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required.map(AgentMcpJSONValue.string)),
      "additionalProperties": .bool(additionalProperties)
    ]
  }

  private static func stringSchema(
    minLength: Int64? = nil,
    maxLength: Int64? = nil
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("string")]
    if let minLength { schema["minLength"] = .int(minLength) }
    if let maxLength { schema["maxLength"] = .int(maxLength) }
    return schema
  }

  private static func integerSchema(minimum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("integer")]
    if let minimum { schema["minimum"] = .int(minimum) }
    return schema
  }

  private static func numberSchema(minimum: Int64? = nil) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = ["type": .string("number")]
    if let minimum { schema["minimum"] = .int(minimum) }
    return schema
  }

  private static func boolSchema() -> AgentMcpJSONObject {
    ["type": .string("boolean")]
  }

  private static func enumStringSchema(_ values: [String]) -> AgentMcpJSONObject {
    var schema = stringSchema()
    schema["enum"] = .array(values.map(AgentMcpJSONValue.string))
    return schema
  }

  private static func arraySchema(
    items: AgentMcpJSONObject,
    minItems: Int64? = nil,
    maxItems: Int64? = nil
  ) -> AgentMcpJSONObject {
    var schema: AgentMcpJSONObject = [
      "type": .string("array"),
      "items": .object(items)
    ]
    if let minItems { schema["minItems"] = .int(minItems) }
    if let maxItems { schema["maxItems"] = .int(maxItems) }
    return schema
  }

  private static let maxReasonCharacters = 2_048
  private static let normalAppExecutionPermission = "signalasi.scope.normal_app_execution"
  private static let workspaceToolIds = [
    workspaceInitialize,
    workspaceMkdir,
    workspaceList,
    workspaceStat,
    workspaceReadText,
    workspaceReadBytes,
    workspaceWriteText,
    workspaceCreateText,
    workspaceAppendText,
    workspaceWriteBytes,
    workspaceCreateBytes,
    workspaceAppendBytes,
    workspaceMove,
    workspaceCopy,
    workspaceDelete,
    workspaceSearchText,
    workspaceApplyExactPatch,
    workspaceDiffSummary,
    workspaceSha256,
    workspaceZipCreate,
    workspaceZipList,
    workspaceZipExtract
  ]
}

enum AgentRuntimeCapabilityMatrix {
  static func build(
    nativeTools: [AgentNativeToolDescriptor],
    systemTools: [AgentSystemTool],
    targets: [AgentCallableTarget]
  ) -> AgentRuntimeCapabilitySnapshot {
    var nativeById: [String: AgentNativeToolDescriptor] = [:]
    for tool in nativeTools {
      nativeById[tool.id] = tool
    }
    let allEntries = nativeTools.map(nativeEntry) +
      systemTools.map { systemEntry($0, nativeById: nativeById) } +
      targets.map(connectorEntry)
    var seen: Set<String> = []
    let entries = allEntries.filter { entry in
      seen.insert("\(entry.source.rawValue):\(entry.id)").inserted
    }.sorted {
      if $0.source.sortOrder != $1.source.sortOrder {
        return $0.source.sortOrder < $1.source.sortOrder
      }
      return $0.id < $1.id
    }
    return AgentRuntimeCapabilitySnapshot(entries: entries)
  }

  static func availableNativeTools(
    nativeTools: [AgentNativeToolDescriptor],
    systemTools: [AgentSystemTool] = [],
    targets: [AgentCallableTarget] = []
  ) -> [AgentNativeToolDescriptor] {
    let snapshot = build(
      nativeTools: nativeTools,
      systemTools: systemTools,
      targets: targets
    )
    return nativeTools.filter { snapshot.isNativeToolExecutable(id: $0.id) }
  }

  private static func nativeEntry(_ tool: AgentNativeToolDescriptor) -> AgentRuntimeCapabilityEntry {
    let state: AgentRuntimeCapabilityState
    if tool.risk == .blocked {
      state = .blocked
    } else {
      switch tool.availability.status {
      case .available:
        state = .available
      case .requiresSetup:
        state = .requiresSetup
      case .unavailable:
        state = .unavailable
      }
    }
    return AgentRuntimeCapabilityEntry(
      id: tool.id,
      title: tool.title,
      source: .nativeTool,
      state: state,
      capabilities: tool.capabilities,
      location: tool.location.rawValue,
      risk: tool.risk.rawValue,
      reason: tool.availability.reason,
      requiredPermissions: Set(tool.requiredPermissions.filter(\.required).map(\.id)),
      requiredConsents: Set(tool.requiredConsents.filter(\.required).map(\.id))
    )
  }

  private static func systemEntry(
    _ tool: AgentSystemTool,
    nativeById: [String: AgentNativeToolDescriptor]
  ) -> AgentRuntimeCapabilityEntry {
    let hostOwnedWorkflow = tool.id.hasPrefix("workflow:") || tool.id.hasPrefix("template:")
    let native = nativeById[AgentNativeToolAgentActionAdapter.defaultToolId(tool.kind)]
    let state: AgentRuntimeCapabilityState
    if tool.risk == .blocked {
      state = .blocked
    } else if hostOwnedWorkflow {
      state = .available
    } else if let native {
      switch (native.risk, native.availability.status) {
      case (.blocked, _):
        state = .blocked
      case (_, .available):
        state = .available
      case (_, .requiresSetup):
        state = .requiresSetup
      case (_, .unavailable):
        state = .unavailable
      }
    } else {
      state = .unavailable
    }
    return AgentRuntimeCapabilityEntry(
      id: tool.id,
      title: tool.title,
      source: .systemTool,
      state: state,
      capabilities: Set(tool.capabilities.map(\.wireValue)),
      location: "phone",
      risk: tool.risk.rawValue.lowercased(),
      reason: systemReason(hostOwnedWorkflow: hostOwnedWorkflow, native: native),
      requiredPermissions: Set(native?.requiredPermissions.filter(\.required).map(\.id) ?? []),
      requiredConsents: Set(native?.requiredConsents.filter(\.required).map(\.id) ?? [])
    )
  }

  private static func connectorEntry(_ target: AgentCallableTarget) -> AgentRuntimeCapabilityEntry {
    let state: AgentRuntimeCapabilityState
    switch target.status {
    case .available:
      state = .available
    case .needsSetup:
      state = .requiresSetup
    case .disconnected:
      state = .unavailable
    }
    return AgentRuntimeCapabilityEntry(
      id: target.id,
      title: target.title,
      source: .connector,
      state: state,
      capabilities: Set(target.capabilities.map(\.wireValue)),
      location: target.failureDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "external"
        : target.failureDomain,
      risk: AgentNativeToolRisk.medium.rawValue,
      reason: target.status.rawValue.lowercased()
    )
  }

  private static func systemReason(
    hostOwnedWorkflow: Bool,
    native: AgentNativeToolDescriptor?
  ) -> String {
    if hostOwnedWorkflow {
      return "Host-owned workflow is installed"
    }
    guard let native else {
      return "No executable native adapter is registered"
    }
    return native.availability.reason
  }
}
