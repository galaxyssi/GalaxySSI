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
    callerId: String = "galaxyssi.mobile_agent",
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
    self.callerId = cleanCallerId.isEmpty ? "galaxyssi.mobile_agent" : cleanCallerId
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
      callerId: try container.decodeIfPresent(String.self, forKey: .callerId) ?? "galaxyssi.mobile_agent",
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

enum AgentNativeToolRegistryError: LocalizedError, Equatable {
  case duplicateTool(String)

  var errorDescription: String? {
    switch self {
    case .duplicateTool(let id):
      return "Native tool id is already registered: \(id)"
    }
  }
}

private struct GuardedNativeToolExecution {
  var execution: AgentNativeToolExecutionResult
  var outputValidation: AgentNativeValidationResult?
  var verification: AgentNativeToolVerification?
}

final class AgentNativeToolExecutionGate {
  static let shared = AgentNativeToolExecutionGate()

  private let readPermits: AgentAdaptiveBlockingPermitGate
  private let mutationPermits: AgentAdaptiveBlockingPermitGate

  init(
    readLimitProvider: @escaping () -> Int = {
      AgentAdaptiveConcurrencyRuntime.currentLimit(.nativeReadIO)
    },
    mutationLimitProvider: @escaping () -> Int = {
      AgentAdaptiveConcurrencyRuntime.currentLimit(.nativeMutation)
    }
  ) {
    readPermits = AgentAdaptiveBlockingPermitGate(limitProvider: readLimitProvider)
    mutationPermits = AgentAdaptiveBlockingPermitGate(limitProvider: mutationLimitProvider)
  }

  func execute<T>(
    descriptor: AgentNativeToolDescriptor,
    invocation: AgentNativeToolInvocation,
    operation: () throws -> T
  ) throws -> T {
    let permits = descriptor.concurrency == .parallelReadOnly ? readPermits : mutationPermits
    try permits.acquire(checkpoint: invocation.checkpoint)
    defer { permits.release() }
    let workspaceId = (invocation.context.attributes["workspace_id"] ?? "")
      .ifBlank(invocation.context.conversationId)
      .ifBlank(invocation.context.sessionId)
      .ifBlank(invocation.context.turnId)
    let plan = AgentNativeToolResourcePolicy.resolve(
      descriptor: descriptor,
      input: invocation.input,
      fallbackWorkspaceId: workspaceId
    )
    return try AgentNativeToolResourceLockTable.execute(
      plan: plan,
      checkpoint: invocation.checkpoint,
      operation: operation
    )
  }
}

final class AgentNativeToolRegistry {
  static let contractVersion = "galaxyssi.phone-native-tools/1.0"
  static let legacyActionIdAttribute = AgentNativeToolAgentActionAdapter.legacyActionIdAttribute
  static let defaultDescriptorCacheTtlMillis: Int64 = 5_000

  private var definitionsById: [String: AgentPhoneNativeToolDefinition] = [:]
  private var executableById: [String: AgentNativeToolExecutableDefinition] = [:]
  private let replayStore: AgentNativeToolReplayStore
  private let auditStore: AgentNativeToolAuditStore
  private let nowMillis: () -> Int64
  private let descriptorCacheTtlMillis: Int64
  private var descriptorSnapshot: DescriptorSnapshot?

  private struct DescriptorSnapshot {
    var createdAtEpochMillis: Int64
    var descriptors: [AgentNativeToolDescriptor]
  }

  init(
    definitions: [AgentPhoneNativeToolDefinition] = [],
    replayStore: AgentNativeToolReplayStore = InMemoryAgentNativeToolReplayStore(),
    auditStore: AgentNativeToolAuditStore = InMemoryAgentNativeToolAuditStore(),
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    descriptorCacheTtlMillis: Int64 = AgentNativeToolRegistry.defaultDescriptorCacheTtlMillis
  ) throws {
    self.replayStore = replayStore
    self.auditStore = auditStore
    self.nowMillis = nowMillis
    self.descriptorCacheTtlMillis = max(0, descriptorCacheTtlMillis)
    try registerAll(definitions)
  }

  @discardableResult
  func register(_ definition: AgentPhoneNativeToolDefinition) throws -> AgentNativeToolRegistry {
    guard definitionsById[definition.id] == nil else {
      throw AgentNativeToolRegistryError.duplicateTool(definition.id)
    }
    definitionsById[definition.id] = definition
    descriptorSnapshot = nil
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
    descriptorSnapshot = nil
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
    let now = max(0, nowMillis())
    if let snapshot = descriptorSnapshot,
       now >= snapshot.createdAtEpochMillis,
       now - snapshot.createdAtEpochMillis <= descriptorCacheTtlMillis {
      return snapshot.descriptors
    }
    let resolved = definitionsById.values
      .map { resolvedDescriptor($0, context: nil) }
      .sorted { $0.id < $1.id }
    descriptorSnapshot = DescriptorSnapshot(createdAtEpochMillis: now, descriptors: resolved)
    return resolved
  }

  func subset(_ predicate: (AgentNativeToolDescriptor) -> Bool) throws -> AgentNativeToolRegistry {
    let matchingDefinitions = definitionsById.values.filter { predicate(resolvedDescriptor($0, context: nil)) }
    let matchingIds = Set(matchingDefinitions.map(\.id))
    let matchingExecutables = executableById.values.filter { matchingIds.contains($0.id) }
    let registry = try AgentNativeToolRegistry(
      replayStore: replayStore,
      auditStore: auditStore,
      nowMillis: nowMillis,
      descriptorCacheTtlMillis: descriptorCacheTtlMillis
    )
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
    let descriptor = resolvedDescriptor(definition, context: context)
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
    let deadline = min(context.deadlineEpochMillis ?? Int64.max, Self.safeAdd(startedAt, descriptor.timeoutMillis))
    let invocation = AgentNativeToolInvocation(
      descriptor: descriptor,
      input: input,
      context: context,
      startedAtEpochMillis: startedAt,
      deadlineEpochMillis: deadline,
      hardDeadlineEpochMillis: context.deadlineEpochMillis,
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

      let replay = cachedReplayResult(descriptor: descriptor, input: input, context: context)
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

      let guarded = try AgentNativeToolExecutionGate.shared.execute(
        descriptor: descriptor,
        invocation: invocation
      ) {
        let execution = try executable.executor(invocation)
        guard execution.isSuccess else {
          return GuardedNativeToolExecution(execution: execution)
        }
        let outputValidation = AgentNativeJsonSchemaValidator.validateObject(
          schema: descriptor.outputSchema,
          object: execution.output
        )
        let verification = outputValidation.isValid
          ? try executable.verifier?(invocation, execution)
          : nil
        return GuardedNativeToolExecution(
          execution: execution,
          outputValidation: outputValidation,
          verification: verification
        )
      }
      let execution = guarded.execution
      if !execution.isSuccess {
        return finish(
          status: .failed,
          output: execution.output,
          message: execution.message,
          metadata: execution.metadata,
          error: execution.error
        )
      }

      guard let outputValidation = guarded.outputValidation else {
        return finish(
          status: .failed,
          output: execution.output,
          message: execution.message,
          metadata: execution.metadata,
          error: AgentNativeToolError(
            code: "missing_output_validation",
            message: "Native tool output validation did not complete"
          )
        )
      }
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

      let verification = guarded.verification
      if verification?.status == .failed {
        let verificationMessage = verification?.message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
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
      recordReplayResult(
        descriptor: descriptor,
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

  private static func safeAdd(_ left: Int64, _ right: Int64) -> Int64 {
    guard right > 0 else { return left }
    return left > Int64.max - right ? Int64.max : left + right
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
    return replayDecision(
      descriptor: definition.descriptor,
      input: input,
      context: context
    )
  }

  private func replayDecision(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext
  ) -> AgentNativeToolReplayDecision {
    let inputSha256 = AgentMcpJSONCodec.sha256(input)
    guard descriptor.idempotency != .nonIdempotent else {
      return AgentNativeToolReplayDecision(
        code: .bypassed,
        replayed: false,
        originalInvocationId: nil,
        inputSha256: inputSha256
      )
    }
    guard let idempotencyKey = context.idempotencyKey, !idempotencyKey.isEmpty else {
      return AgentNativeToolReplayDecision(
        code: descriptor.idempotency == .idempotencyKeyRequired ? .keyRequired : .accepted,
        replayed: false,
        originalInvocationId: nil,
        inputSha256: inputSha256
      )
    }
    let key = AgentNativeToolReplayKey(
      toolId: descriptor.id,
      toolVersion: descriptor.version,
      idempotencyKey: idempotencyKey
    )
    guard let cached = replayStore.get(key) else {
      return AgentNativeToolReplayDecision(
        code: .accepted,
        replayed: false,
        originalInvocationId: nil,
        inputSha256: inputSha256
      )
    }
    let matchesInput = cached.receipt.inputSha256 == inputSha256
    return AgentNativeToolReplayDecision(
      code: matchesInput ? .replay : .conflict,
      replayed: matchesInput,
      originalInvocationId: cached.receipt.originalInvocationId ?? cached.receipt.invocationId,
      inputSha256: inputSha256
    )
  }

  private func cachedReplayResult(
    descriptor: AgentNativeToolDescriptor,
    input: AgentMcpJSONObject,
    context: AgentNativeToolInvocationContext
  ) -> (AgentNativeToolReplayDecision, AgentNativeToolResult?) {
    let decision = replayDecision(descriptor: descriptor, input: input, context: context)
    guard decision.code == .replay,
          let idempotencyKey = context.idempotencyKey,
          !idempotencyKey.isEmpty else {
      return (decision, nil)
    }
    let key = AgentNativeToolReplayKey(
      toolId: descriptor.id,
      toolVersion: descriptor.version,
      idempotencyKey: idempotencyKey
    )
    return (decision, replayStore.get(key))
  }

  private func recordReplayResult(
    descriptor: AgentNativeToolDescriptor,
    context: AgentNativeToolInvocationContext,
    result: AgentNativeToolResult
  ) {
    guard descriptor.idempotency != .nonIdempotent,
          let idempotencyKey = context.idempotencyKey,
          !idempotencyKey.isEmpty,
          result.isSuccess else {
      return
    }
    let key = AgentNativeToolReplayKey(
      toolId: descriptor.id,
      toolVersion: descriptor.version,
      idempotencyKey: idempotencyKey
    )
    try? replayStore.put(key, result: result)
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

  private func resolvedDescriptor(
    _ definition: AgentPhoneNativeToolDefinition,
    context: AgentNativeToolInvocationContext?
  ) -> AgentNativeToolDescriptor {
    var descriptor = definition.descriptor
    descriptor.availability = definition.availabilityProvider.current(context)
    return descriptor
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
      "timeout_policy": .string(descriptor.timeoutPolicy.rawValue),
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
