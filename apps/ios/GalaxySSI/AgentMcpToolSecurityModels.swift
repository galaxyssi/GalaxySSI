import Foundation

struct AgentMcpTool: Codable, Equatable {
  var name: String
  var title: String?
  var description: String?
  var inputSchema: AgentMcpJSONObject
  var outputSchema: AgentMcpJSONObject?
  var annotations: AgentMcpJSONObject?
  var raw: AgentMcpJSONObject

  init(
    name: String,
    title: String? = nil,
    description: String? = nil,
    inputSchema: AgentMcpJSONObject = [:],
    outputSchema: AgentMcpJSONObject? = nil,
    annotations: AgentMcpJSONObject? = nil,
    raw: AgentMcpJSONObject = [:]
  ) {
    self.name = name
    self.title = title
    self.description = description
    self.inputSchema = inputSchema
    self.outputSchema = outputSchema
    self.annotations = annotations
    self.raw = raw
  }

  enum CodingKeys: String, CodingKey {
    case name
    case title
    case description
    case inputSchema = "input_schema"
    case outputSchema = "output_schema"
    case annotations
    case raw
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
      title: try container.decodeIfPresent(String.self, forKey: .title),
      description: try container.decodeIfPresent(String.self, forKey: .description),
      inputSchema: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .inputSchema) ?? [:],
      outputSchema: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .outputSchema),
      annotations: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .annotations),
      raw: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .raw) ?? [:]
    )
  }
}

struct AgentMcpToolAssessment: Codable, Equatable {
  var risk: AgentMcpToolRisk
  var permissions: Set<String>
  var reason: String
  var parameterPreview: AgentMcpJSONObject
  var inputSha256: String

  enum CodingKeys: String, CodingKey {
    case risk
    case permissions
    case reason
    case parameterPreview = "parameter_preview"
    case inputSha256 = "input_sha256"
  }

  func publicValue() -> AgentMcpJSONObject {
    [
      "risk": .string(risk.rawValue),
      "permissions": .array(permissions.sorted().map { .string($0) }),
      "reason": .string(reason),
      "parameter_preview": .object(parameterPreview),
      "input_sha256": .string(inputSha256)
    ]
  }
}

struct AgentMcpPermissionDecision: Codable, Equatable {
  var allowed: Bool
  var code: String
  var message: String
  var requiredUserAction: String

  init(
    allowed: Bool,
    code: String,
    message: String,
    requiredUserAction: String = ""
  ) {
    self.allowed = allowed
    self.code = code
    self.message = message
    self.requiredUserAction = requiredUserAction
  }

  enum CodingKeys: String, CodingKey {
    case allowed
    case code
    case message
    case requiredUserAction = "required_user_action"
  }
}

enum AgentMcpToolSecurityPolicy {
  static func provisionalRisk(toolName: String) -> AgentMcpToolRisk {
    let tokens = nameTokens(toolName)
    if tokens.contains(where: highRiskTerms.contains) {
      return .high
    }
    if tokens.contains(where: readOnlyTerms.contains) && !tokens.contains(where: mutatingTerms.contains) {
      return .low
    }
    return .medium
  }

  static func assess(
    tool: AgentMcpTool,
    arguments: AgentMcpJSONObject,
    transport: AgentMcpTransportKind
  ) -> AgentMcpToolAssessment {
    let tokens = nameTokens(tool.name)
    let readOnly = annotationBool(tool.annotations, names: ["readOnlyHint", "read_only_hint"])
    let destructive = annotationBool(tool.annotations, names: ["destructiveHint", "destructive_hint"])
    let openWorld = annotationBool(tool.annotations, names: ["openWorldHint", "open_world_hint"])
    let risk: AgentMcpToolRisk
    let reason: String
    if destructive == true || tokens.contains(where: highRiskTerms.contains) {
      risk = .high
      reason = "The tool is destructive or controls a sensitive external action."
    } else if readOnly == true && !tokens.contains(where: mutatingTerms.contains) {
      risk = .low
      reason = "The MCP server declares this tool read-only."
    } else if tokens.contains(where: readOnlyTerms.contains) && !tokens.contains(where: mutatingTerms.contains) {
      risk = .low
      reason = "The tool name describes a read-only operation."
    } else {
      risk = .medium
      reason = "The MCP tool can change data or external state."
    }

    let keys = collectKeys(arguments)
    var permissions: Set<String> = ["mcp.data.read"]
    permissions.insert(transport == .localStdio ? "mcp.process.execute" : "mcp.network.connect")
    if risk != .low {
      permissions.insert("mcp.data.write")
    }
    if risk == .high {
      permissions.insert("mcp.destructive")
    }
    if openWorld == true {
      permissions.insert("mcp.network.open_world")
    }
    if keys.contains(where: { matches(secretKeyPattern, in: $0) }) {
      permissions.insert("mcp.secrets.use")
    }
    if keys.contains(where: { matches(pathKeyPattern, in: $0) }) {
      permissions.insert("mcp.files.access")
    }
    return AgentMcpToolAssessment(
      risk: risk,
      permissions: permissions,
      reason: reason,
      parameterPreview: AgentMcpParameterRedactor.sanitize(arguments),
      inputSha256: AgentMcpJSONCodec.sha256(arguments)
    )
  }

  static func decide(
    mode: AgentMcpPermissionMode,
    assessment: AgentMcpToolAssessment,
    explicitlyApproved: Bool
  ) -> AgentMcpPermissionDecision {
    switch mode {
    case .disabled:
      return AgentMcpPermissionDecision(
        allowed: false,
        code: "mcp_disabled",
        message: "This MCP connection is disabled by its permission policy.",
        requiredUserAction: "enable_connection"
      )
    case .readOnly:
      if assessment.risk == .low {
        return AgentMcpPermissionDecision(allowed: true, code: "allowed_read_only", message: "Read-only MCP call allowed.")
      }
      return AgentMcpPermissionDecision(
        allowed: false,
        code: "mcp_write_not_allowed",
        message: "This MCP connection is restricted to read-only tools.",
        requiredUserAction: "change_permission_mode"
      )
    case .askForChanges:
      if assessment.risk == .low {
        return AgentMcpPermissionDecision(allowed: true, code: "allowed_low_risk", message: "Low-risk MCP call allowed.")
      }
      if assessment.risk == .medium && explicitlyApproved {
        return AgentMcpPermissionDecision(
          allowed: true,
          code: "allowed_explicit_change",
          message: "The user explicitly approved this MCP change."
        )
      }
      if assessment.risk == .high && explicitlyApproved {
        return AgentMcpPermissionDecision(
          allowed: true,
          code: "allowed_explicit_high_risk",
          message: "The user explicitly approved this high-risk MCP call."
        )
      }
      return AgentMcpPermissionDecision(
        allowed: false,
        code: assessment.risk == .high ? "mcp_high_risk_approval_required" : "mcp_approval_required",
        message: "This MCP tool needs explicit user approval.",
        requiredUserAction: "approve_tool_call"
      )
    case .trusted:
      if assessment.risk != .high {
        return AgentMcpPermissionDecision(allowed: true, code: "allowed_trusted", message: "Trusted MCP policy allowed the call.")
      }
      if explicitlyApproved {
        return AgentMcpPermissionDecision(
          allowed: true,
          code: "allowed_explicit_high_risk",
          message: "The user explicitly approved this high-risk MCP call."
        )
      }
      return AgentMcpPermissionDecision(
        allowed: false,
        code: "mcp_high_risk_approval_required",
        message: "High-risk MCP calls require approval every time.",
        requiredUserAction: "approve_tool_call"
      )
    }
  }

  private static func annotationBool(_ value: AgentMcpJSONObject?, names: [String]) -> Bool? {
    guard let value else {
      return nil
    }
    for name in names {
      if let result = value[name]?.boolValue {
        return result
      }
    }
    return nil
  }

  private static func collectKeys(_ object: AgentMcpJSONObject) -> Set<String> {
    var keys: Set<String> = []
    collectKeys(.object(object), into: &keys)
    return keys
  }

  private static func collectKeys(_ value: AgentMcpJSONValue, into keys: inout Set<String>) {
    switch value {
    case .object(let object):
      for (key, child) in object {
        keys.insert(key.lowercased())
        collectKeys(child, into: &keys)
      }
    case .array(let values):
      values.forEach { collectKeys($0, into: &keys) }
    case .string, .int, .double, .bool, .null:
      break
    }
  }

  private static func nameTokens(_ value: String) -> Set<String> {
    Set(
      value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
    )
  }

  private static func matches(_ pattern: String, in value: String) -> Bool {
    value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static let readOnlyTerms: Set<String> = [
    "get", "list", "read", "search", "query", "find", "inspect", "status",
    "describe", "fetch", "lookup", "view", "download"
  ]
  private static let mutatingTerms: Set<String> = [
    "set", "create", "update", "write", "edit", "send", "post", "put", "patch",
    "upload", "execute", "run", "start", "stop", "control", "toggle", "install",
    "approve", "merge", "comment", "reply", "publish"
  ]
  private static let highRiskTerms: Set<String> = [
    "delete", "remove", "destroy", "drop", "wipe", "reset", "payment", "purchase",
    "transfer", "credential", "permission", "shell", "terminal", "sudo", "lock",
    "unlock", "reboot", "shutdown", "deploy", "release"
  ]
  private static let secretKeyPattern =
    #"(^|[_.-])(password|passwd|passphrase|secret|token|api[_-]?key|authorization|cookie|otp|totp|private[_-]?key)($|[_.-])"#
  private static let pathKeyPattern =
    #"(^|[_.-])(path|file|folder|directory|uri|url)($|[_.-])"#
}

enum AgentMcpParameterRedactor {
  static func sanitize(_ arguments: AgentMcpJSONObject) -> AgentMcpJSONObject {
    guard case .object(let sanitized) = sanitizeValue(.object(arguments), key: "", depth: 0) else {
      return [:]
    }
    return sanitized
  }

  static func sanitizeText(_ value: String, limit: Int = 500) -> String {
    let boundedLimit = max(0, min(limit, 2_000))
    return String(stripURLSecrets(redactAssignments(redactBearer(value))).prefix(boundedLimit))
  }

  private static func sanitizeValue(
    _ value: AgentMcpJSONValue,
    key: String,
    depth: Int
  ) -> AgentMcpJSONValue {
    if matches(secretKeyPattern, in: key) {
      return .string("[REDACTED]")
    }
    if depth >= maxDepth {
      return .string("[TRUNCATED]")
    }
    switch value {
    case .object(let object):
      let pairs = object.keys.sorted().prefix(maxItems).map { childKey in
        (childKey, sanitizeValue(object[childKey] ?? .null, key: childKey, depth: depth + 1))
      }
      return .object(Dictionary(uniqueKeysWithValues: pairs))
    case .array(let values):
      return .array(values.prefix(maxItems).map { sanitizeValue($0, key: key, depth: depth + 1) })
    case .string(let value):
      return .string(sanitizeString(value))
    case .int, .double, .bool, .null:
      return value
    }
  }

  private static func sanitizeString(_ value: String) -> String {
    var text = redactAssignments(redactBearer(value))
    if text.lowercased().hasPrefix("https://") || text.lowercased().hasPrefix("http://") {
      text = text.components(separatedBy: "?").first ?? text
      text = text.components(separatedBy: "#").first ?? text
    }
    return String(text.prefix(maxString)) + (text.count > maxString ? "..." : "")
  }

  private static func redactBearer(_ value: String) -> String {
    replaceRegex(pattern: bearerPattern, in: value, with: "Bearer [REDACTED]")
  }

  private static func redactAssignments(_ value: String) -> String {
    replaceRegex(pattern: assignmentPattern, in: value, with: "$1=[REDACTED]")
  }

  private static func stripURLSecrets(_ value: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: urlInTextPattern, options: [.caseInsensitive]) else {
      return value
    }
    var result = value
    let range = NSRange(result.startIndex..<result.endIndex, in: result)
    for match in regex.matches(in: result, options: [], range: range).reversed() {
      guard let swiftRange = Range(match.range, in: result) else {
        continue
      }
      let url = String(result[swiftRange])
      let stripped = (url.components(separatedBy: "?").first ?? url)
        .components(separatedBy: "#").first ?? url
      result.replaceSubrange(swiftRange, with: stripped)
    }
    return result
  }

  private static func replaceRegex(pattern: String, in value: String, with replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return value
    }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: replacement)
  }

  private static func matches(_ pattern: String, in value: String) -> Bool {
    value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static let maxDepth = 6
  private static let maxItems = 64
  private static let maxString = 320
  private static let secretKeyPattern =
    #"(^|[_.-])(password|passwd|passphrase|secret|token|api[_-]?key|authorization|cookie|otp|totp|private[_-]?key)($|[_.-])"#
  private static let bearerPattern = #"\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"#
  private static let assignmentPattern = #"\b(password|passwd|secret|token|api[_-]?key|authorization)\s*=\s*[^\s,;]+"#
  private static let urlInTextPattern = #"https?://[^\s<>"]+"#
}
