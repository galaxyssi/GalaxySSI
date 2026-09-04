import CryptoKit
import Foundation

enum AgentSkillParameterType: String, Codable, CaseIterable, Identifiable {
  case object
  case array
  case string
  case integer
  case number
  case boolean

  var id: String { rawValue }
}

final class AgentSkillParameterSchema: Codable, Equatable {
  var type: AgentSkillParameterType
  var properties: [String: AgentSkillParameterSchema]
  var required: Set<String>
  var additionalProperties: Bool
  var items: AgentSkillParameterSchema?
  var enumValues: [AgentMcpJSONValue]
  var minLength: Int?
  var maxLength: Int?
  var minimum: Double?
  var maximum: Double?
  var minItems: Int?
  var maxItems: Int?

  init(
    type: AgentSkillParameterType = .object,
    properties: [String: AgentSkillParameterSchema] = [:],
    required: Set<String> = [],
    additionalProperties: Bool = false,
    items: AgentSkillParameterSchema? = nil,
    enumValues: [AgentMcpJSONValue] = [],
    minLength: Int? = nil,
    maxLength: Int? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil,
    minItems: Int? = nil,
    maxItems: Int? = nil
  ) {
    self.type = type
    self.properties = properties
    self.required = required
    self.additionalProperties = additionalProperties
    self.items = items
    self.enumValues = enumValues
    self.minLength = minLength
    self.maxLength = maxLength
    self.minimum = minimum
    self.maximum = maximum
    self.minItems = minItems
    self.maxItems = maxItems
  }

  static func objectSchema(
    properties: [String: AgentSkillParameterSchema] = [:],
    required: Set<String> = [],
    additionalProperties: Bool = false
  ) -> AgentSkillParameterSchema {
    AgentSkillParameterSchema(
      type: .object,
      properties: properties,
      required: required,
      additionalProperties: additionalProperties
    )
  }

  static func array(
    items: AgentSkillParameterSchema,
    minItems: Int? = nil,
    maxItems: Int? = nil
  ) -> AgentSkillParameterSchema {
    AgentSkillParameterSchema(type: .array, items: items, minItems: minItems, maxItems: maxItems)
  }

  static func string(
    enumValues: [String] = [],
    minLength: Int? = nil,
    maxLength: Int? = nil
  ) -> AgentSkillParameterSchema {
    AgentSkillParameterSchema(
      type: .string,
      enumValues: enumValues.map(AgentMcpJSONValue.string),
      minLength: minLength,
      maxLength: maxLength
    )
  }

  static func integer(minimum: Int64? = nil, maximum: Int64? = nil) -> AgentSkillParameterSchema {
    AgentSkillParameterSchema(type: .integer, minimum: minimum.map(Double.init), maximum: maximum.map(Double.init))
  }

  static func number(minimum: Double? = nil, maximum: Double? = nil) -> AgentSkillParameterSchema {
    AgentSkillParameterSchema(type: .number, minimum: minimum, maximum: maximum)
  }

  static func boolean() -> AgentSkillParameterSchema {
    AgentSkillParameterSchema(type: .boolean)
  }

  static func == (lhs: AgentSkillParameterSchema, rhs: AgentSkillParameterSchema) -> Bool {
    lhs.type == rhs.type &&
      lhs.properties == rhs.properties &&
      lhs.required == rhs.required &&
      lhs.additionalProperties == rhs.additionalProperties &&
      lhs.items == rhs.items &&
      lhs.enumValues == rhs.enumValues &&
      lhs.minLength == rhs.minLength &&
      lhs.maxLength == rhs.maxLength &&
      lhs.minimum == rhs.minimum &&
      lhs.maximum == rhs.maximum &&
      lhs.minItems == rhs.minItems &&
      lhs.maxItems == rhs.maxItems
  }

  enum CodingKeys: String, CodingKey {
    case type
    case properties
    case required
    case additionalProperties = "additional_properties"
    case additionalPropertiesLegacy = "additionalProperties"
    case items
    case enumValues = "enum"
    case enumValuesLegacy = "enum_values"
    case minLength = "min_length"
    case minLengthLegacy = "minLength"
    case maxLength = "max_length"
    case maxLengthLegacy = "maxLength"
    case minimum
    case maximum
    case minItems = "min_items"
    case minItemsLegacy = "minItems"
    case maxItems = "max_items"
    case maxItemsLegacy = "maxItems"
  }

  convenience init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      type: try container.decodeIfPresent(AgentSkillParameterType.self, forKey: .type) ?? .object,
      properties: try container.decodeIfPresent([String: AgentSkillParameterSchema].self, forKey: .properties) ?? [:],
      required: try container.decodeIfPresent(Set<String>.self, forKey: .required) ?? [],
      additionalProperties: try container.decodeIfPresent(Bool.self, forKey: .additionalProperties) ??
        (try container.decodeIfPresent(Bool.self, forKey: .additionalPropertiesLegacy)) ?? false,
      items: try container.decodeIfPresent(AgentSkillParameterSchema.self, forKey: .items),
      enumValues: try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .enumValues) ??
        (try container.decodeIfPresent([AgentMcpJSONValue].self, forKey: .enumValuesLegacy)) ?? [],
      minLength: try container.decodeIfPresent(Int.self, forKey: .minLength) ??
        (try container.decodeIfPresent(Int.self, forKey: .minLengthLegacy)),
      maxLength: try container.decodeIfPresent(Int.self, forKey: .maxLength) ??
        (try container.decodeIfPresent(Int.self, forKey: .maxLengthLegacy)),
      minimum: try container.decodeIfPresent(Double.self, forKey: .minimum),
      maximum: try container.decodeIfPresent(Double.self, forKey: .maximum),
      minItems: try container.decodeIfPresent(Int.self, forKey: .minItems) ??
        (try container.decodeIfPresent(Int.self, forKey: .minItemsLegacy)),
      maxItems: try container.decodeIfPresent(Int.self, forKey: .maxItems) ??
        (try container.decodeIfPresent(Int.self, forKey: .maxItemsLegacy))
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    if !properties.isEmpty {
      try container.encode(properties, forKey: .properties)
    }
    if !required.isEmpty {
      try container.encode(required.sorted(), forKey: .required)
    }
    if type == .object {
      try container.encode(additionalProperties, forKey: .additionalProperties)
    }
    try container.encodeIfPresent(items, forKey: .items)
    if !enumValues.isEmpty {
      try container.encode(enumValues, forKey: .enumValues)
    }
    try container.encodeIfPresent(minLength, forKey: .minLength)
    try container.encodeIfPresent(maxLength, forKey: .maxLength)
    try container.encodeIfPresent(minimum, forKey: .minimum)
    try container.encodeIfPresent(maximum, forKey: .maximum)
    try container.encodeIfPresent(minItems, forKey: .minItems)
    try container.encodeIfPresent(maxItems, forKey: .maxItems)
  }
}

struct AgentSkillResource: Codable, Equatable, Identifiable {
  var id: String
  var path: String
  var mimeType: String
  var maxBytes: Int64

  init(
    id: String,
    path: String,
    mimeType: String = "application/octet-stream",
    maxBytes: Int64 = AgentSkillLimits.defaultResourceMaxBytes
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.path = String(path.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxResourcePathCharacters))
    self.mimeType = String(mimeType.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxMimeTypeCharacters))
      .ifBlank("application/octet-stream")
    self.maxBytes = min(max(maxBytes, 1), AgentSkillLimits.maxResourceBytes)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case path
    case mimeType = "mime_type"
    case maxBytes = "max_bytes"
  }
}

struct AgentSkillStep: Codable, Equatable, Identifiable {
  var id: String
  var toolId: String
  var input: AgentMcpJSONObject
  var dependsOn: [String]

  init(id: String, toolId: String, input: AgentMcpJSONObject = [:], dependsOn: [String] = []) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.toolId = String(toolId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.input = input
    self.dependsOn = dependsOn.prefix(AgentSkillLimits.maxSteps).map {
      String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    }.filter { !$0.isEmpty }
  }

  enum CodingKeys: String, CodingKey {
    case id
    case toolId = "tool_id"
    case input
    case dependsOn = "depends_on"
  }
}

struct AgentSkillTestCase: Codable, Equatable, Identifiable {
  var id: String
  var input: AgentMcpJSONObject
  var expectedToolIds: Set<String>
  var excludedPhrases: Set<String>

  init(
    id: String,
    input: AgentMcpJSONObject = [:],
    expectedToolIds: Set<String> = [],
    excludedPhrases: Set<String> = []
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.input = input
    self.expectedToolIds = expectedToolIds
    self.excludedPhrases = excludedPhrases
  }

  enum CodingKeys: String, CodingKey {
    case id
    case input
    case expectedToolIds = "expected_tool_ids"
    case excludedPhrases = "excluded_phrases"
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(input, forKey: .input)
    try container.encode(expectedToolIds.sorted(), forKey: .expectedToolIds)
    try container.encode(excludedPhrases.sorted(), forKey: .excludedPhrases)
  }
}

enum AgentToolCallStatus: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case running = "RUNNING"
  case succeeded = "SUCCEEDED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentToolCallStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
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

struct AgentToolCallRecord: Codable, Equatable, Identifiable {
  var id: String
  var toolName: String
  var status: AgentToolCallStatus
  var arguments: AgentMcpJSONObject
  var result: AgentMcpJSONObject
  var errorMessage: String
  var startedAtMillis: Int64
  var completedAtMillis: Int64

  init(
    id: String,
    toolName: String,
    status: AgentToolCallStatus = .pending,
    arguments: AgentMcpJSONObject = [:],
    result: AgentMcpJSONObject = [:],
    errorMessage: String = "",
    startedAtMillis: Int64 = 0,
    completedAtMillis: Int64 = 0
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.toolName = String(toolName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.status = status
    self.arguments = arguments
    self.result = result
    self.errorMessage = String(errorMessage.prefix(AgentSkillLimits.maxFeedbackCharacters))
    self.startedAtMillis = max(startedAtMillis, 0)
    self.completedAtMillis = max(completedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case toolName = "tool"
    case status
    case arguments
    case result
    case errorMessage = "error"
    case startedAtMillis = "started_at"
    case completedAtMillis = "completed_at"
  }
}

enum AgentSkillLimits {
  static let supportedFormatVersion = 1
  static let maxManifestBytes = 256 * 1_024
  static let maxStoreBytes = 4 * 1_024 * 1_024
  static let maxInstalledSkills = 128
  static let maxIdCharacters = 128
  static let maxVersionCharacters = 64
  static let maxTitleCharacters = 160
  static let maxInstructionsCharacters = 32 * 1_024
  static let maxRequestCharacters = 8_000
  static let maxNativeTools = 64
  static let maxPermissions = 64
  static let maxResources = 64
  static let maxSteps = 128
  static let maxExamples = 64
  static let maxTests = 64
  static let maxSchemaDepth = 12
  static let maxSchemaProperties = 128
  static let maxInputDepth = 16
  static let maxStepInputBytes = 64 * 1_024
  static let maxTemplateCharacters = 8 * 1_024
  static let maxTemplateReferences = 64
  static let maxToolCalls = 64
  static let maxArtifacts = 64
  static let maxFeedbackCharacters = 4_000
  static let maxResourcePathCharacters = 512
  static let maxMimeTypeCharacters = 160
  static let defaultResourceMaxBytes: Int64 = 1_024 * 1_024
  static let maxResourceBytes: Int64 = 32 * 1_024 * 1_024
}

struct AgentSkillValidationIssue: Codable, Equatable {
  var path: String
  var code: String
  var message: String
}

struct AgentSkillValidationResult: Codable, Equatable {
  var issues: [AgentSkillValidationIssue] = []

  var isValid: Bool { issues.isEmpty }

  func requireValid() throws {
    if !isValid {
      throw AgentSkillValidationError(result: self)
    }
  }
}

struct AgentSkillValidationError: Error, Equatable {
  var result: AgentSkillValidationResult
}

struct AgentSkillConflictError: Error, Equatable {
  var id: String
  var version: String
}

protocol AgentSkillStore {
  func list() -> [AgentSkillInstallation]
  func upsert(_ installation: AgentSkillInstallation)
  func replaceAll(_ installations: [AgentSkillInstallation])
  func delete(id: String, version: String) -> Bool
  func clear()
}

final class InMemoryAgentSkillStore: AgentSkillStore {
  private var document: String
  private let lock = NSRecursiveLock()

  init(initialSkills: [AgentSkillInstallation] = []) {
    document = AgentSkillStoreCodec.encode(initialSkills)
  }

  func list() -> [AgentSkillInstallation] {
    locked { AgentSkillStoreCodec.decode(document) }
  }

  func upsert(_ installation: AgentSkillInstallation) {
    locked {
      let current = list().filter { !($0.id == installation.id && $0.version == installation.version) }
      document = AgentSkillStoreCodec.encode(current + [installation])
    }
  }

  func replaceAll(_ installations: [AgentSkillInstallation]) {
    locked {
      document = AgentSkillStoreCodec.encode(installations)
    }
  }

  func delete(id: String, version: String) -> Bool {
    locked {
      let current = list()
      let remaining = current.filter { !($0.id == id.trimmingCharacters(in: .whitespacesAndNewlines) && $0.version == version.trimmingCharacters(in: .whitespacesAndNewlines)) }
      guard remaining.count != current.count else {
        return false
      }
      document = AgentSkillStoreCodec.encode(remaining)
      return true
    }
  }

  func clear() {
    locked {
      document = AgentSkillStoreCodec.emptyDocument()
    }
  }

  func serializedSnapshot() -> String {
    locked { document }
  }

  private func locked<T>(_ work: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return work()
  }
}

enum AgentSkillStoreCodec {
  static func emptyDocument() -> String {
    #"{"installations":[],"version":1}"#
  }

  static func encode(_ installations: [AgentSkillInstallation]) -> String {
    var seen: Set<String> = []
    let bounded = Array(installations
      .sorted { left, right in
        left.id == right.id ? left.version < right.version : left.id < right.id
      }
      .filter { installation in
        seen.insert("\(installation.id)\u{0}\(installation.version)").inserted
      }
      .prefix(AgentSkillLimits.maxInstalledSkills))
    let document = AgentSkillStoreDocument(version: AgentSkillLimits.supportedFormatVersion, skills: bounded)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(document), data.count <= AgentSkillLimits.maxStoreBytes else {
      return emptyDocument()
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> [AgentSkillInstallation] {
    guard let data = raw.data(using: .utf8), data.count <= AgentSkillLimits.maxStoreBytes,
      let document = try? JSONDecoder().decode(AgentSkillStoreDocument.self, from: data),
      document.version <= AgentSkillLimits.supportedFormatVersion else {
      return []
    }
    return Array(document.skills.prefix(AgentSkillLimits.maxInstalledSkills))
  }
}

private struct AgentSkillStoreDocument: Codable {
  var version: Int
  var skills: [AgentSkillInstallation]

  enum CodingKeys: String, CodingKey {
    case version
    case installations
    case skills
  }

  init(version: Int, skills: [AgentSkillInstallation]) {
    self.version = version
    self.skills = skills
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AgentSkillLimits.supportedFormatVersion
    skills = try container.decodeIfPresent([AgentSkillInstallation].self, forKey: .installations) ??
      (try container.decodeIfPresent([AgentSkillInstallation].self, forKey: .skills)) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
    try container.encode(skills, forKey: .installations)
  }
}

enum AgentSkillTemplateExpander {
  static func validate(
    _ template: String,
    path: String,
    manifest: AgentSkillManifest,
    issues: inout [AgentSkillValidationIssue]
  ) {
    if template.count > AgentSkillLimits.maxTemplateCharacters {
      issues.append(issue(path, "oversized_template", "Template exceeds its character limit"))
      return
    }
    let matches = templateMatches(template)
    if matches.count > AgentSkillLimits.maxTemplateReferences {
      issues.append(issue(path, "too_many_templates", "Template has too many references"))
    }
    let remainder = replacingTemplateReferences(in: template, with: "")
    if remainder.contains("{{") || remainder.contains("}}") {
      issues.append(issue(path, "invalid_template", "Template expression is malformed or unsupported"))
    }
    let resourceIds = Set(manifest.resources.map(\.id))
    for match in matches {
      let expression = match.expression
      if expression.hasPrefix("parameters.") {
        let names = expression.dropFirst("parameters.".count).split(separator: ".").map(String.init)
        if !schemaMayContain(manifest.parameters, names: names) {
          issues.append(issue(path, "unknown_parameter", "Template parameter \(expression) is not declared"))
        }
      } else if expression.hasPrefix("resources.") {
        let id = String(expression.dropFirst("resources.".count))
        if !resourceIds.contains(id) {
          issues.append(issue(path, "unknown_resource", "Template resource \(id) is not declared"))
        }
      } else {
        issues.append(issue(path, "unsupported_template", "Only parameters.* and resources.* references are supported"))
      }
    }
  }

  static func expand(
    _ value: AgentMcpJSONValue,
    parameters: AgentMcpJSONObject,
    resources: [String: AgentSkillResource] = [:],
    depth: Int = 0
  ) throws -> AgentMcpJSONValue {
    guard depth <= AgentSkillLimits.maxInputDepth else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
        issue("$.steps.input", "input_depth", "Skill input nesting is too deep")
      ]))
    }
    switch value {
    case .string(let text):
      return try expandString(text, parameters: parameters, resources: resources)
    case .array(let values):
      return .array(try values.map { try expand($0, parameters: parameters, resources: resources, depth: depth + 1) })
    case .object(let object):
      return .object(try object.mapValues { try expand($0, parameters: parameters, resources: resources, depth: depth + 1) })
    case .int, .double, .bool, .null:
      return value
    }
  }

  private static func expandString(
    _ value: String,
    parameters: AgentMcpJSONObject,
    resources: [String: AgentSkillResource]
  ) throws -> AgentMcpJSONValue {
    let matches = templateMatches(value)
    guard !matches.isEmpty else {
      return .string(value)
    }
    if matches.count == 1, matches[0].range.location == 0,
      matches[0].range.length == NSRange(value.startIndex..<value.endIndex, in: value).length {
      return try resolve(matches[0].expression, parameters: parameters, resources: resources)
    }
    var result = value
    for match in matches.reversed() {
      guard let range = Range(match.range, in: result) else {
        continue
      }
      let resolved = try resolve(match.expression, parameters: parameters, resources: resources)
      result.replaceSubrange(range, with: embeddedString(resolved))
    }
    return .string(result)
  }

  private static func resolve(
    _ expression: String,
    parameters: AgentMcpJSONObject,
    resources: [String: AgentSkillResource]
  ) throws -> AgentMcpJSONValue {
    if expression.hasPrefix("parameters.") {
      var current: AgentMcpJSONValue = .object(parameters)
      for name in expression.dropFirst("parameters.".count).split(separator: ".").map(String.init) {
        guard case .object(let object) = current, let next = object[name] else {
          throw missingTemplate(expression)
        }
        current = next
      }
      return current
    }
    if expression.hasPrefix("resources.") {
      let id = String(expression.dropFirst("resources.".count))
      guard let resource = resources[id] else {
        throw missingTemplate(expression)
      }
      return .string(resource.path)
    }
    throw missingTemplate(expression)
  }

  private static func embeddedString(_ value: AgentMcpJSONValue) -> String {
    switch value {
    case .string(let text):
      return text
    case .object, .array:
      return AgentMcpJSONCodec.stringify(value)
    case .int(let number):
      return String(number)
    case .double(let number):
      return number.isFinite ? String(number) : "null"
    case .bool(let bool):
      return bool ? "true" : "false"
    case .null:
      return "null"
    }
  }

  private static func schemaMayContain(_ schema: AgentSkillParameterSchema, names: [String]) -> Bool {
    var current = schema
    for name in names {
      guard let next = current.properties[name] else {
        return current.additionalProperties
      }
      current = next
    }
    return true
  }

  private static func templateMatches(_ value: String) -> [TemplateMatch] {
    guard let regex = try? NSRegularExpression(pattern: referencePattern) else {
      return []
    }
    return regex.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)).compactMap { match in
      guard match.numberOfRanges >= 2,
        let expressionRange = Range(match.range(at: 1), in: value) else {
        return nil
      }
      return TemplateMatch(range: match.range(at: 0), expression: String(value[expressionRange]))
    }
  }

  private static func replacingTemplateReferences(in value: String, with replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: referencePattern) else {
      return value
    }
    return regex.stringByReplacingMatches(
      in: value,
      range: NSRange(value.startIndex..<value.endIndex, in: value),
      withTemplate: replacement
    )
  }

  private static func missingTemplate(_ expression: String) -> AgentSkillValidationError {
    AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
      issue("$.steps.input", "missing_template_value", "No value is available for \(expression)")
    ]))
  }

  private struct TemplateMatch {
    var range: NSRange
    var expression: String
  }

  private static let referencePattern = #"{{\s*([A-Za-z][A-Za-z0-9_.-]*)\s*}}"#
}

struct AgentSkillMatch: Equatable {
  var installation: AgentSkillInstallation
  var confidence: Double
  var parameters: AgentMcpJSONObject
  var explicit: Bool
}

enum AgentSkillRequestTransformer {
  static func transform(savedRequest: String, currentRequest: String) -> String {
    guard sameTaskFamily(savedRequest, currentRequest) else {
      return currentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return replaceSingleAlignedArgument(saved: savedRequest, current: currentRequest) ??
      currentRequest.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func sameTaskFamily(_ left: String, _ right: String) -> Bool {
    AgentLearningAnalyzer.sameTaskFamily(left, right)
  }

  private static func replaceSingleAlignedArgument(saved: String, current: String) -> String? {
    let savedTokens = semanticTokens(saved)
    let currentTokens = semanticTokens(current)
    for savedIndex in savedTokens.indices {
      for currentIndex in currentTokens.indices where savedTokens[savedIndex].text != currentTokens[currentIndex].text {
        let leftAnchored = savedIndex > 0 && currentIndex > 0 &&
          savedTokens[savedIndex - 1].text.caseInsensitiveCompare(currentTokens[currentIndex - 1].text) == .orderedSame
        let rightMatches = (1...3).filter { offset in
          guard let saved = savedTokens[safe: savedIndex + offset],
            let current = currentTokens[safe: currentIndex + offset] else {
            return false
          }
          return saved.text.caseInsensitiveCompare(current.text) == .orderedSame
        }.count
        guard leftAnchored, rightMatches >= 2 else {
          continue
        }
        let range = savedTokens[savedIndex].range
        return saved.replacingCharacters(in: range, with: currentTokens[currentIndex].text)
      }
    }
    return nil
  }

  private static func semanticTokens(_ value: String) -> [SemanticToken] {
    var tokens: [SemanticToken] = []
    var index = value.startIndex
    while index < value.endIndex {
      let character = value[index]
      if character.isWhitespace {
        index = value.index(after: index)
        continue
      }
      let start = index
      if character.isLetter || character.isNumber || character == "_" {
        var end = value.index(after: index)
        while end < value.endIndex {
          let next = value[end]
          guard next.isLetter || next.isNumber || next == "_" else {
            break
          }
          end = value.index(after: end)
        }
        tokens.append(SemanticToken(text: String(value[start..<end]), range: start..<end))
        index = end
      } else {
        let end = value.index(after: index)
        tokens.append(SemanticToken(text: String(value[start..<end]), range: start..<end))
        index = end
      }
    }
    return tokens
  }

  private struct SemanticToken {
    var text: String
    var range: Range<String.Index>
  }
}

final class AgentSkillMatcher {
  private let runtime: AgentSkillRuntime

  init(_ runtime: AgentSkillRuntime) {
    self.runtime = runtime
  }

  func match(_ request: String) -> AgentSkillMatch? {
    let normalized = normalize(request)
    guard !normalized.isEmpty else {
      return nil
    }
    let explicitRequest = request.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
      ? String(request.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
      : ""
    return runtime.list(enabledOnly: true)
      .filter { $0.autoInvoke || !explicitRequest.isEmpty }
      .filter { installation in
        !installation.manifest.negativeExamples.contains {
          similarity(normalized, normalize($0)) >= 0.7
        }
      }
      .compactMap { installation -> AgentSkillMatch? in
        let explicitTarget = [installation.id, installation.manifest.name].first {
          explicitRequest.caseInsensitiveCompare($0) == .orderedSame ||
            explicitRequest.lowercased().hasPrefix($0.lowercased() + " ")
        } ?? ""
        let explicit = !explicitTarget.isEmpty
        let score = explicit ? 1.0 : installation.manifest.triggerExamples.map {
          similarity(normalized, normalize($0))
        }.max() ?? 0
        guard explicit || score >= Self.autoMatchThreshold else {
          return nil
        }
        let requestParameter = explicit
          ? String(explicitRequest.dropFirst(explicitTarget.count)).trimmingCharacters(in: .whitespacesAndNewlines)
          : request.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentSkillMatch(
          installation: installation,
          confidence: score,
          parameters: ["request": .string(requestParameter)],
          explicit: explicit
        )
      }
      .sorted { left, right in
        if left.confidence != right.confidence {
          return left.confidence > right.confidence
        }
        let leftSpecificity = familyTemplateSpecificity(left, request: normalized)
        let rightSpecificity = familyTemplateSpecificity(right, request: normalized)
        if leftSpecificity != rightSpecificity {
          return leftSpecificity > rightSpecificity
        }
        return left.installation.installedAtMillis > right.installation.installedAtMillis
      }
      .first
  }

  private func familyTemplateSpecificity(_ match: AgentSkillMatch, request: String) -> Int {
    match.installation.manifest.triggerExamples
      .filter { AgentSkillRequestTransformer.sameTaskFamily($0, request) }
      .map { normalize($0).count }
      .max() ?? 0
  }

  private func normalize(_ value: String) -> String {
    AgentLearningAnalyzer.taskFamily(value)
  }

  private func similarity(_ left: String, _ right: String) -> Double {
    if AgentSkillRequestTransformer.sameTaskFamily(left, right) {
      return 0.97
    }
    if left == right {
      return 1
    }
    let leftTokens = Set(left.split(separator: " ").map(String.init).filter { !$0.isEmpty })
    let rightTokens = Set(right.split(separator: " ").map(String.init).filter { !$0.isEmpty })
    guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
      return 0
    }
    let tokenScore = Double(leftTokens.intersection(rightTokens).count) / Double(leftTokens.union(rightTokens).count)
    let containsScore = left.contains(right) || right.contains(left) ? 0.85 : 0
    let characterScore: Double
    if left.unicodeScalars.contains(where: isCJK) && right.unicodeScalars.contains(where: isCJK) {
      let leftPairs = characterPairs(left)
      let rightPairs = characterPairs(right)
      characterScore = leftPairs.isEmpty || rightPairs.isEmpty
        ? 0
        : 2.0 * Double(leftPairs.intersection(rightPairs).count) / Double(leftPairs.count + rightPairs.count)
    } else {
      characterScore = 0
    }
    return max(tokenScore, containsScore, characterScore)
  }

  private func characterPairs(_ value: String) -> Set<String> {
    let compact = value.filter { $0.isLetter || $0.isNumber }
    guard compact.count >= 2 else { return [] }
    return Set((0..<(compact.count - 1)).map { index in
      let start = compact.index(compact.startIndex, offsetBy: index)
      let end = compact.index(start, offsetBy: 2)
      return String(compact[start..<end])
    })
  }

  private func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    (0x3400...0x9FFF).contains(Int(scalar.value))
  }

  private static let autoMatchThreshold = 0.78
}

final class AgentConversationSkillCompiler {
  private let runtime: AgentSkillRuntime
  private let availableTools: () -> [AgentNativeToolDescriptor]

  init(_ runtime: AgentSkillRuntime, availableTools: @escaping () -> [AgentNativeToolDescriptor]) {
    self.runtime = runtime
    self.availableTools = availableTools
  }

  func compile(_ runs: [AgentRecordedRun], titleHint: String = "") throws -> AgentSkillManifest {
    let successful = runs.filter { $0.status == .completed }
    guard let first = successful.first, let latest = successful.last else {
      throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
        issue("$", "completed_run_required", "A completed Agent run is required before saving a Skill")
      ]))
    }
    let descriptors = Dictionary(uniqueKeysWithValues: availableTools().map { ($0.id, $0) })
    let reusableCalls = latest.toolCalls.filter { $0.status == .succeeded && descriptors[$0.toolName] != nil }
    let usesOrchestration = reusableCalls.isEmpty
    let toolIds = usesOrchestration ? [Self.agentOrchestrationToolId] : Array(reusableCalls.map(\.toolName).stableDistinct())
    let skillId = "skill_\(AgentLearningAnalyzer.stableKey(first.originalRequest).prefix(16))"
    let version = nextVersion(skillId)
    let title = titleHint.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(AgentLearningAnalyzer.safeTitle(first.originalRequest))
    let steps: [AgentSkillStep]
    if usesOrchestration {
      steps = [
        AgentSkillStep(
          id: "step_1",
          toolId: Self.agentOrchestrationToolId,
          input: ["request": .string("{{parameters.request}}")]
        )
      ]
    } else {
      steps = reusableCalls.enumerated().map { index, call in
        AgentSkillStep(
          id: "step_\(index + 1)",
          toolId: call.toolName,
          input: parameterize(call.arguments, originalRequest: first.originalRequest),
          dependsOn: index == 0 ? [] : ["step_\(index)"]
        )
      }
    }
    let permissions = Set(toolIds.flatMap { descriptors[$0]?.requiredPermissions.filter(\.required).map(\.id) ?? [] })
    let manifest = AgentSkillManifest(
      id: skillId,
      name: title,
      version: version,
      summary: "Reusable method learned from a completed Agent task",
      instructions: buildInstructions(successful),
      nativeTools: Set(toolIds),
      permissions: permissions,
      parameters: AgentSkillParameterSchema.objectSchema(
        properties: ["request": .string(minLength: 1, maxLength: AgentSkillLimits.maxRequestCharacters)],
        required: ["request"]
      ),
      steps: steps,
      description: "Reusable method learned from a completed Agent task",
      author: "User Generated",
      source: "conversation",
      autoInvoke: true,
      triggerExamples: Array(successful.map { AgentLearningAnalyzer.generalize($0.originalRequest) }.stableDistinct().prefix(12)),
      renderSpec: latest.renderSpec,
      tests: [
        AgentSkillTestCase(
          id: "regression_1",
          input: ["request": .string(AgentLearningAnalyzer.generalize(first.originalRequest))],
          expectedToolIds: Set(toolIds)
        )
      ]
    )
    try runtime.validate(manifest).requireValid()
    return manifest
  }

  func install(_ runs: [AgentRecordedRun], titleHint: String = "") throws -> AgentSkillInstallation {
    try runtime.install(compile(runs, titleHint: titleHint))
  }

  private func nextVersion(_ skillId: String) -> String {
    guard let latest = runtime.list().filter({ $0.id == skillId }).max(by: {
      versionParts($0.version).lexicographicallyPrecedes(versionParts($1.version))
    }) else {
      return "1.0.0"
    }
    let parts = versionParts(latest.version)
    return "\(parts[safe: 0] ?? 1).\((parts[safe: 1] ?? 0) + 1).0"
  }

  private func versionParts(_ version: String) -> [Int] {
    version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
  }

  private func buildInstructions(_ runs: [AgentRecordedRun]) -> String {
    var parts = [
      "Complete requests in this task family by following the saved declarative tool workflow.",
      "Treat the request parameter as variable input. Never copy credentials, cookies, tokens, or private data into the Skill."
    ]
    let examples = runs.map { $0.originalRequest.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .stableDistinct()
    if !examples.isEmpty {
      parts.append("Learned successful request sequence: \(examples.map(AgentLearningAnalyzer.generalize).joined(separator: " -> ")).")
    }
    let feedback = runs.flatMap(\.userFeedback).stableDistinct()
    if !feedback.isEmpty {
      parts.append("User-approved refinements: \(feedback.joined(separator: "; "))")
    }
    return String(parts.joined(separator: " ").prefix(AgentSkillLimits.maxInstructionsCharacters))
  }

  private func parameterize(_ value: AgentMcpJSONObject, originalRequest: String) -> AgentMcpJSONObject {
    value.mapValues { parameterizeValue($0, originalRequest: originalRequest) }
  }

  private func parameterizeValue(_ value: AgentMcpJSONValue, originalRequest: String) -> AgentMcpJSONValue {
    switch value {
    case .string(let text):
      return text.trimmingCharacters(in: .whitespacesAndNewlines) == originalRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        ? .string("{{parameters.request}}")
        : .string(AgentLearningAnalyzer.sanitizeSecrets(text))
    case .object(let object):
      return .object(object.mapValues { parameterizeValue($0, originalRequest: originalRequest) })
    case .array(let values):
      return .array(values.map { parameterizeValue($0, originalRequest: originalRequest) })
    case .int, .double, .bool, .null:
      return value
    }
  }

  static let agentOrchestrationToolId = "galaxyssi.agent.orchestrate"
}

enum AgentLearningAnalyzer {
  static func taskFamily(_ request: String) -> String {
    var value = request.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for (pattern, replacement) in replacements {
      value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    return String(value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(240))
  }

  static func sameTaskFamily(_ left: String, _ right: String) -> Bool {
    let normalizedLeft = taskFamily(left)
    let normalizedRight = taskFamily(right)
    if normalizedLeft == normalizedRight {
      return true
    }
    if normalizedLeft.isEmpty || normalizedRight.isEmpty {
      return false
    }
    let leftTokens = Set(normalizedLeft.split(separator: " ").map(String.init))
    let rightTokens = Set(normalizedRight.split(separator: " ").map(String.init))
    if leftTokens.isEmpty || rightTokens.isEmpty {
      return false
    }
    let intersection = Double(leftTokens.intersection(rightTokens).count)
    let dice = 2.0 * intersection / Double(leftTokens.count + rightTokens.count)
    let smallerCoverage = intersection / Double(min(leftTokens.count, rightTokens.count))
    return dice >= 0.62 || (intersection >= 2 && smallerCoverage >= 0.60)
  }

  static func containsSensitiveData(_ value: String) -> Bool {
    value.range(
      of: #"(?i)(?:api[_-]?key|authorization|bearer|cookie|password|passwd|secret|token|otp|verification[_ -]?code)\s*[:=]?\s*\S+"#,
      options: .regularExpression
    ) != nil || value.range(of: "-----BEGIN ", options: .caseInsensitive) != nil
  }

  static func sanitizeSecrets(_ value: String) -> String {
    var clean = value
    clean = clean.replacingOccurrences(
      of: #"(?i)(?:api[_-]?key|authorization|bearer|cookie|password|passwd|secret|token|otp|verification[_ -]?code)\s*[:=]?\s*\S+"#,
      with: "[SECRET]",
      options: .regularExpression
    )
    return clean
  }

  static func generalize(_ value: String) -> String {
    sanitizeSecrets(value)
      .replacingOccurrences(of: #"(?i)\bhttps?://[^\s]+"#, with: "[URL]", options: .regularExpression)
      .replacingOccurrences(of: #"(?i)(?:[a-z]:\\|\\\\)[^\r\n]+"#, with: "[PATH]", options: .regularExpression)
  }

  static func safeTitle(_ request: String) -> String {
    taskFamily(request)
      .replacingOccurrences(of: #"<[^>]+>"#, with: "item", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(48)
      .description
      .ifBlank("Learned workflow")
  }

  static func stableKey(_ value: String) -> String {
    SHA256.hash(data: Data(taskFamily(value).utf8)).map { String(format: "%02x", $0) }.joined().prefix(24).description
  }

  private static let replacements: [(String, String)] = [
    (#"(?i)\bhttps?://[^\s]+"#, " <url> "),
    (#"(?i)(?:[a-z]:\\|\\\\)[^\r\n]+"#, " <path> "),
    (#"(?<![A-Za-z0-9])/(?:[^\s/]+/)*[^\s/]+"#, " <path> "),
    (#"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"#, " <id> "),
    (#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, " <email> "),
    (#"(["'`]).{1,160}\1"#, " <value> "),
    (#"(?<![\p{L}\p{N}])[-+]?\d+(?:[.,:]\d+)*(?![\p{L}\p{N}])"#, " <number> ")
  ]
}

enum AgentSkillManifestCodec {
  static func encode(_ manifest: AgentSkillManifest) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(manifest), data.count <= AgentSkillLimits.maxManifestBytes else {
      return "{}"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> AgentSkillManifest? {
    guard let data = raw.data(using: .utf8), data.count <= AgentSkillLimits.maxManifestBytes else {
      return nil
    }
    return try? JSONDecoder().decode(AgentSkillManifest.self, from: data)
  }
}

enum AgentSkillManifestValidator {
  static func validate(
    _ manifest: AgentSkillManifest,
    availableNativeToolIds: Set<String>? = nil
  ) -> AgentSkillValidationResult {
    var issues: [AgentSkillValidationIssue] = []
    stableToken(manifest.id, pattern: stableId, path: "$.id", code: "invalid_id", issues: &issues)
    stableToken(manifest.version, pattern: stableVersion, path: "$.version", code: "invalid_version", issues: &issues)
    if manifest.formatVersion != AgentSkillLimits.supportedFormatVersion {
      issues.append(issue("$.format_version", "unsupported_format", "Only format version 1 is supported"))
    }
    if manifest.name.isBlank {
      issues.append(issue("$.title", "blank_title", "Skill title is required"))
    }
    if manifest.instructions.isBlank {
      issues.append(issue("$.instructions", "blank_instructions", "Skill instructions are required"))
    }
    if manifest.permissions.count > AgentSkillLimits.maxPermissions {
      issues.append(issue("$.permissions", "too_many_permissions", "Too many permission declarations"))
    }
    if manifest.nativeTools.count > AgentSkillLimits.maxNativeTools {
      issues.append(issue("$.native_tools", "too_many_tools", "Too many native tool declarations"))
    }
    for tool in manifest.nativeTools {
      stableToken(tool, pattern: declarationId, path: "$.native_tools", code: "invalid_tool", issues: &issues)
      if let availableNativeToolIds, !availableNativeToolIds.contains(tool) {
        issues.append(issue("$.native_tools.\(tool)", "unknown_tool", "Native tool is not available"))
      }
    }
    for permission in manifest.permissions {
      stableToken(permission, pattern: declarationId, path: "$.permissions", code: "invalid_permission", issues: &issues)
    }
    validateResources(manifest.resources, issues: &issues)
    validateSchema(manifest.parameters, path: "$.parameters", depth: 0, issues: &issues)
    if manifest.parameters.type != .object {
      issues.append(issue("$.parameters", "root_schema_type", "Skill parameters must use an object schema"))
    }
    if manifest.steps.count > AgentSkillLimits.maxSteps {
      issues.append(issue("$.steps", "too_many_steps", "Too many Skill steps"))
    }
    let duplicateStepIds = duplicateValues(manifest.steps.map(\.id))
    for duplicated in duplicateStepIds {
      issues.append(issue("$.steps.\(duplicated)", "duplicate_step", "Step ids must be unique"))
    }
    let stepIds = Set(manifest.steps.map(\.id))
    for (index, step) in manifest.steps.enumerated() {
      let path = "$.steps[\(index)]"
      stableToken(step.id, pattern: stableId, path: "\(path).id", code: "invalid_step_id", issues: &issues)
      stableToken(step.toolId, pattern: declarationId, path: "\(path).tool_id", code: "invalid_tool", issues: &issues)
      if !manifest.nativeTools.contains(step.toolId) {
        issues.append(issue("\(path).tool_id", "undeclared_tool", "Step uses undeclared tool \(step.toolId)"))
      }
      for duplicated in duplicateValues(step.dependsOn) {
        issues.append(issue("\(path).depends_on", "duplicate_dependency", "Dependency \(duplicated) is repeated"))
      }
      for dependency in step.dependsOn {
        if dependency == step.id {
          issues.append(issue("\(path).depends_on", "self_dependency", "A step cannot depend on itself"))
        } else if !stepIds.contains(dependency) {
          issues.append(issue("\(path).depends_on", "unknown_dependency", "Step depends on missing step \(dependency)"))
        }
      }
      let inputBytes = AgentMcpJSONCodec.stringify(step.input).utf8.count
      if inputBytes > AgentSkillLimits.maxStepInputBytes {
        issues.append(issue("\(path).input", "oversized_input", "Step input exceeds the byte limit"))
      }
      validateTemplates(step.input, path: "\(path).input", manifest: manifest, issues: &issues, depth: 0)
    }
    if duplicateStepIds.isEmpty, (try? topologicalSteps(manifest.steps)) == nil {
      issues.append(issue("$.steps", "cycle", "Skill step dependencies contain a cycle"))
    }
    for (index, test) in manifest.tests.enumerated() {
      stableToken(test.id, pattern: stableId, path: "$.tests[\(index)].id", code: "invalid_test_id", issues: &issues)
      let missing = test.expectedToolIds.subtracting(manifest.nativeTools)
      if !missing.isEmpty {
        issues.append(issue("$.tests[\(index)].expected_tool_ids", "undeclared_tool", "Skill test expects undeclared tools"))
      }
    }
    return AgentSkillValidationResult(issues: issues)
  }

  static func validateParameters(
    _ schema: AgentSkillParameterSchema,
    value: AgentMcpJSONValue,
    path: String
  ) -> [AgentSkillValidationIssue] {
    switch (schema.type, value) {
    case (.object, .object(let object)):
      var issues: [AgentSkillValidationIssue] = []
      for required in schema.required where object[required] == nil {
        issues.append(issue("\(path).\(required)", "missing_required", "Required parameter is missing"))
      }
      if !schema.additionalProperties {
        for key in object.keys where schema.properties[key] == nil && !schema.required.contains(key) {
          issues.append(issue("\(path).\(key)", "unknown_parameter", "Parameter is not declared"))
        }
      }
      for (key, child) in schema.properties where object[key] != nil {
        issues += validateParameters(child, value: object[key] ?? .null, path: "\(path).\(key)")
      }
      return issues
    case (.string, .string(let string)):
      var issues: [AgentSkillValidationIssue] = []
      if let min = schema.minLength, string.count < min {
        issues.append(issue(path, "string_too_short", "String parameter is too short"))
      }
      if let max = schema.maxLength, string.count > max {
        issues.append(issue(path, "string_too_long", "String parameter is too long"))
      }
      if !schema.enumValues.isEmpty && !schema.enumValues.contains(.string(string)) {
        issues.append(issue(path, "enum_mismatch", "String parameter is not in the enum"))
      }
      return issues
    case (.integer, .int(let integer)):
      return numberIssues(Double(integer), schema: schema, path: path)
    case (.number, .double(let number)):
      return numberIssues(number, schema: schema, path: path)
    case (.number, .int(let integer)):
      return numberIssues(Double(integer), schema: schema, path: path)
    case (.boolean, .bool):
      return []
    case (.array, .array(let array)):
      var issues: [AgentSkillValidationIssue] = []
      if let min = schema.minItems, array.count < min {
        issues.append(issue(path, "array_too_short", "Array parameter is too short"))
      }
      if let max = schema.maxItems, array.count > max {
        issues.append(issue(path, "array_too_long", "Array parameter is too long"))
      }
      if let items = schema.items {
        for (index, item) in array.enumerated() {
          issues += validateParameters(items, value: item, path: "\(path)[\(index)]")
        }
      }
      return issues
    default:
      return [issue(path, "type_mismatch", "Parameter type does not match schema")]
    }
  }

  private static func validateResources(_ resources: [AgentSkillResource], issues: inout [AgentSkillValidationIssue]) {
    if resources.count > AgentSkillLimits.maxResources {
      issues.append(issue("$.resources", "too_many_resources", "Too many resource declarations"))
    }
    for duplicated in duplicateValues(resources.map(\.id)) {
      issues.append(issue("$.resources.\(duplicated)", "duplicate_resource", "Resource ids must be unique"))
    }
    for (index, resource) in resources.enumerated() {
      let path = "$.resources[\(index)]"
      stableToken(resource.id, pattern: stableId, path: "\(path).id", code: "invalid_resource", issues: &issues)
      if !isSafeRelativeResourcePath(resource.path) {
        issues.append(issue("\(path).path", "path_traversal", "Resource path must be a canonical relative path"))
      }
      if resource.mimeType.isBlank || resource.mimeType.count > AgentSkillLimits.maxMimeTypeCharacters {
        issues.append(issue("\(path).mime_type", "invalid_mime_type", "Resource MIME type is invalid"))
      }
      if resource.maxBytes < 1 || resource.maxBytes > AgentSkillLimits.maxResourceBytes {
        issues.append(issue("\(path).max_bytes", "invalid_resource_bound", "Resource byte bound is invalid"))
      }
    }
  }

  private static func validateSchema(
    _ schema: AgentSkillParameterSchema,
    path: String,
    depth: Int,
    issues: inout [AgentSkillValidationIssue]
  ) {
    if depth > AgentSkillLimits.maxSchemaDepth {
      issues.append(issue(path, "schema_depth", "Parameter schema is too deeply nested"))
      return
    }
    if schema.properties.count > AgentSkillLimits.maxSchemaProperties {
      issues.append(issue(path, "schema_properties", "Parameter schema has too many properties"))
    }
    for name in schema.properties.keys {
      stableToken(name, pattern: stableId, path: "\(path).properties", code: "invalid_parameter", issues: &issues)
    }
    for name in schema.required where schema.properties[name] == nil {
      issues.append(issue("\(path).required", "unknown_required", "Required parameter \(name) is not declared"))
    }
    if schema.enumValues.contains(where: { !jsonValueCompatible($0, depth: 0) }) {
      issues.append(issue("\(path).enum", "invalid_json_value", "Schema enum contains a non-JSON value"))
    }
    if let minimum = schema.minimum, !minimum.isFinite {
      issues.append(issue(path, "invalid_range", "Schema numeric range is invalid"))
    }
    if let maximum = schema.maximum, !maximum.isFinite {
      issues.append(issue(path, "invalid_range", "Schema numeric range is invalid"))
    }
    if let minimum = schema.minimum, let maximum = schema.maximum, minimum > maximum {
      issues.append(issue(path, "invalid_range", "Schema numeric range is invalid"))
    }
    if !validBounds(schema.minLength, schema.maxLength) || !validBounds(schema.minItems, schema.maxItems) {
      issues.append(issue(path, "invalid_bounds", "Schema size bounds are invalid"))
    }
    switch schema.type {
    case .object:
      for (name, child) in schema.properties {
        validateSchema(child, path: "\(path).properties.\(name)", depth: depth + 1, issues: &issues)
      }
    case .array:
      if let items = schema.items {
        validateSchema(items, path: "\(path).items", depth: depth + 1, issues: &issues)
      } else {
        issues.append(issue("\(path).items", "missing_items", "Array schema must declare its item schema"))
      }
    case .string, .integer, .number, .boolean:
      break
    }
  }

  private static func validateTemplates(
    _ value: AgentMcpJSONObject,
    path: String,
    manifest: AgentSkillManifest,
    issues: inout [AgentSkillValidationIssue],
    depth: Int
  ) {
    validateTemplates(.object(value), path: path, manifest: manifest, issues: &issues, depth: depth)
  }

  private static func validateTemplates(
    _ value: AgentMcpJSONValue,
    path: String,
    manifest: AgentSkillManifest,
    issues: inout [AgentSkillValidationIssue],
    depth: Int
  ) {
    if depth > AgentSkillLimits.maxInputDepth {
      issues.append(issue(path, "input_depth", "Step input nesting is too deep"))
      return
    }
    switch value {
    case .string(let template):
      AgentSkillTemplateExpander.validate(template, path: path, manifest: manifest, issues: &issues)
    case .object(let object):
      for (key, child) in object {
        validateTemplates(child, path: "\(path).\(key)", manifest: manifest, issues: &issues, depth: depth + 1)
      }
    case .array(let array):
      for (index, child) in array.enumerated() {
        validateTemplates(child, path: "\(path)[\(index)]", manifest: manifest, issues: &issues, depth: depth + 1)
      }
    case .int, .double, .bool, .null:
      break
    }
  }

  static func topologicalSteps(_ steps: [AgentSkillStep]) throws -> [AgentSkillStep] {
    var byId: [String: AgentSkillStep] = [:]
    for step in steps {
      if byId[step.id] != nil {
        throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [
          issue("$.steps.\(step.id)", "duplicate_step", "Step ids must be unique")
        ]))
      }
      byId[step.id] = step
    }
    var temporary: Set<String> = []
    var permanent: Set<String> = []
    var ordered: [AgentSkillStep] = []

    func visit(_ id: String) throws {
      if permanent.contains(id) {
        return
      }
      if temporary.contains(id) {
        throw AgentSkillValidationError(result: AgentSkillValidationResult(issues: [issue("$.steps", "dependency_cycle", "Skill step dependencies contain a cycle")]))
      }
      temporary.insert(id)
      for dependency in byId[id]?.dependsOn ?? [] where byId[dependency] != nil {
        try visit(dependency)
      }
      temporary.remove(id)
      permanent.insert(id)
      if let step = byId[id] {
        ordered.append(step)
      }
    }

    for step in steps {
      try visit(step.id)
    }
    return ordered
  }

  private static func numberIssues(_ value: Double, schema: AgentSkillParameterSchema, path: String) -> [AgentSkillValidationIssue] {
    var issues: [AgentSkillValidationIssue] = []
    if let minimum = schema.minimum, value < minimum {
      issues.append(issue(path, "number_too_small", "Number parameter is below the minimum"))
    }
    if let maximum = schema.maximum, value > maximum {
      issues.append(issue(path, "number_too_large", "Number parameter is above the maximum"))
    }
    return issues
  }

  private static func isSafeRelativeResourcePath(_ raw: String) -> Bool {
    if raw.isBlank || raw != raw.trimmingCharacters(in: .whitespacesAndNewlines) ||
      raw.count > AgentSkillLimits.maxResourcePathCharacters {
      return false
    }
    if raw.hasPrefix("/") || raw.hasPrefix("\\") || raw.contains("\\") || raw.contains(":") ||
      raw.contains("%") || raw.contains("\u{0}") {
      return false
    }
    return raw.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { segment in
      !segment.isEmpty && segment != "." && segment != ".." && segment != "~"
    }
  }

  private static func validBounds(_ minimum: Int?, _ maximum: Int?) -> Bool {
    (minimum.map { $0 >= 0 } ?? true) &&
      (maximum.map { $0 >= 0 } ?? true) &&
      (minimum == nil || maximum == nil || (minimum ?? 0) <= (maximum ?? 0))
  }

  private static func duplicateValues(_ values: [String]) -> Set<String> {
    var counts: [String: Int] = [:]
    for value in values {
      counts[value, default: 0] += 1
    }
    return Set(counts.compactMap { entry in entry.value > 1 ? entry.key : nil })
  }

  private static func jsonValueCompatible(_ value: AgentMcpJSONValue, depth: Int) -> Bool {
    if depth > AgentSkillLimits.maxInputDepth {
      return false
    }
    switch value {
    case .double(let number):
      return number.isFinite
    case .array(let values):
      return values.allSatisfy { jsonValueCompatible($0, depth: depth + 1) }
    case .object(let object):
      return object.values.allSatisfy { jsonValueCompatible($0, depth: depth + 1) }
    case .string, .int, .bool, .null:
      return true
    }
  }

  private static func stableToken(
    _ value: String,
    pattern: String,
    path: String,
    code: String,
    issues: inout [AgentSkillValidationIssue]
  ) {
    if value.isBlank || value.range(of: pattern, options: .regularExpression) == nil {
      issues.append(issue(path, code, "Value is not a stable token"))
    }
  }

  private static let stableId = #"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"#
  private static let stableVersion = #"^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$"#
  private static let declarationId = #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"#
}

private func issue(_ path: String, _ code: String, _ message: String) -> AgentSkillValidationIssue {
  AgentSkillValidationIssue(path: path, code: code, message: message)
}

private extension String {
  func matches(_ pattern: String) -> [Range<String.Index>] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    let fullRange = NSRange(startIndex..<endIndex, in: self)
    return regex.matches(in: self, range: fullRange).compactMap { Range($0.range, in: self) }
  }
}

private extension Array where Element: Hashable {
  func stableDistinct() -> [Element] {
    var seen: Set<Element> = []
    var values: [Element] = []
    for item in self where seen.insert(item).inserted {
      values.append(item)
    }
    return values
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
