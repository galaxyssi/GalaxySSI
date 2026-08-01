import CryptoKit
import Foundation

enum AgentMcpDistribution: String, Codable, CaseIterable, Identifiable {
  case remote
  case localPackage = "local_package"

  var id: String { rawValue }
}

enum AgentMcpAuthMethod: String, Codable, CaseIterable, Identifiable {
  case none
  case bearerToken = "bearer_token"
  case apiKey = "api_key"
  case usernamePassword = "username_password"
  case oauth2
  case deviceCode = "device_code"
  case dynamic

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMcpAuthMethod {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .none
  }
}

enum AgentMcpAuthFieldType: String, Codable, CaseIterable, Identifiable {
  case text
  case password
  case apiKey = "api_key"
  case phone
  case email
  case otp
  case totp
  case captcha
  case select
  case checkbox
  case url

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMcpAuthFieldType {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .text
  }
}

enum AgentMcpAuthState: String, Codable, CaseIterable, Identifiable {
  case notRequired = "not_required"
  case notConfigured = "not_configured"
  case challengeRequired = "challenge_required"
  case authenticating
  case authenticated
  case refreshing
  case reauthenticationRequired = "reauthentication_required"
  case error

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMcpAuthState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .notConfigured
  }
}

enum AgentMcpConnectionState: String, Codable, CaseIterable, Identifiable {
  case installed
  case connecting
  case connected
  case needsSetup = "needs_setup"
  case unavailable
  case error

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMcpConnectionState {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .installed
  }
}

struct AgentMcpAuthFieldSpec: Codable, Equatable, Identifiable {
  var id: String
  var label: String
  var type: AgentMcpAuthFieldType
  var required: Bool
  var secret: Bool
  var placeholder: String
  var options: [String]

  init(
    id: String,
    label: String,
    type: AgentMcpAuthFieldType,
    required: Bool = true,
    secret: Bool? = nil,
    placeholder: String = "",
    options: [String] = []
  ) throws {
    guard id.range(of: #"^[a-z][a-z0-9_.-]{0,95}$"#, options: .regularExpression) != nil else {
      throw AgentRuntimeCapabilityError.invalid("MCP authentication field id is invalid")
    }
    guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      options.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      throw AgentRuntimeCapabilityError.invalid("MCP authentication field labels and options must not be blank")
    }
    self.id = id
    self.label = label
    self.type = type
    self.required = required
    self.secret = secret ?? [.password, .apiKey, .otp, .totp].contains(type)
    self.placeholder = placeholder
    self.options = options
  }
}

struct AgentMcpAuthExchangeSpec: Codable, Equatable {
  var method: String
  var pathTemplate: String
  var headerTemplates: [String: String]
  var bodyTemplate: String
  var responseMappings: [String: String]
  var acceptedStatusCodes: Set<Int>

  init(
    method: String,
    pathTemplate: String,
    headerTemplates: [String: String] = [:],
    bodyTemplate: String = "",
    responseMappings: [String: String] = [:],
    acceptedStatusCodes: Set<Int> = [200]
  ) throws {
    let normalizedMethod = method.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard ["GET", "POST", "PUT", "PATCH"].contains(normalizedMethod),
      pathTemplate.hasPrefix("/"),
      !pathTemplate.contains(".."),
      !pathTemplate.contains("://"),
      responseMappings.keys.allSatisfy({ $0.range(of: #"^[a-z][a-z0-9_.-]{0,95}$"#, options: .regularExpression) != nil }),
      !acceptedStatusCodes.isEmpty,
      acceptedStatusCodes.allSatisfy({ (200...299).contains($0) }) else {
      throw AgentRuntimeCapabilityError.invalid("MCP authentication exchange is invalid")
    }
    self.method = normalizedMethod
    self.pathTemplate = pathTemplate
    self.headerTemplates = headerTemplates
    self.bodyTemplate = bodyTemplate
    self.responseMappings = responseMappings
    self.acceptedStatusCodes = acceptedStatusCodes
  }

  enum CodingKeys: String, CodingKey {
    case method
    case pathTemplate = "path"
    case headerTemplates = "headers"
    case bodyTemplate = "body_template"
    case responseMappings = "response_mappings"
    case acceptedStatusCodes = "accepted_status_codes"
  }
}

struct AgentMcpAuthStepSpec: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var description: String
  var fields: [AgentMcpAuthFieldSpec]
  var expiresInSeconds: Int64
  var exchange: AgentMcpAuthExchangeSpec?

  init(
    id: String,
    title: String,
    description: String = "",
    fields: [AgentMcpAuthFieldSpec],
    expiresInSeconds: Int64 = 0,
    exchange: AgentMcpAuthExchangeSpec? = nil
  ) throws {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      Set(fields.map(\.id)).count == fields.count,
      expiresInSeconds >= 0 else {
      throw AgentRuntimeCapabilityError.invalid("MCP authentication step is invalid")
    }
    self.id = id
    self.title = title
    self.description = description
    self.fields = fields
    self.expiresInSeconds = expiresInSeconds
    self.exchange = exchange
  }

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case description
    case fields
    case expiresInSeconds = "expires_in_seconds"
    case exchange
  }
}

struct AgentMcpAuthProfile: Codable, Equatable {
  var method: AgentMcpAuthMethod
  var steps: [AgentMcpAuthStepSpec]
  var accessTokenTtlMillis: Int64
  var refreshLeadMillis: Int64
  var supportsRefresh: Bool
  var refreshExchange: AgentMcpAuthExchangeSpec?
  var authorizationUrl: String
  var tokenUrl: String
  var scopes: [String]

  init(
    _ method: AgentMcpAuthMethod,
    steps: [AgentMcpAuthStepSpec]? = nil,
    accessTokenTtlMillis: Int64 = 0,
    refreshLeadMillis: Int64 = 5 * 60_000,
    supportsRefresh: Bool = false,
    refreshExchange: AgentMcpAuthExchangeSpec? = nil,
    authorizationUrl: String = "",
    tokenUrl: String = "",
    scopes: [String] = []
  ) throws {
    let effectiveSteps: [AgentMcpAuthStepSpec]
    if let steps {
      effectiveSteps = steps
    } else {
      effectiveSteps = try Self.defaultSteps(method)
    }
    guard Set(effectiveSteps.map(\.id)).count == effectiveSteps.count,
      accessTokenTtlMillis >= 0,
      refreshLeadMillis >= 0 else {
      throw AgentRuntimeCapabilityError.invalid("MCP authentication profile is invalid")
    }
    self.method = method
    self.steps = effectiveSteps
    self.accessTokenTtlMillis = accessTokenTtlMillis
    self.refreshLeadMillis = refreshLeadMillis
    self.supportsRefresh = supportsRefresh
    self.refreshExchange = refreshExchange
    self.authorizationUrl = authorizationUrl
    self.tokenUrl = tokenUrl
    self.scopes = scopes
  }

  enum CodingKeys: String, CodingKey {
    case method
    case steps
    case accessTokenTtlMillis = "token_ttl_ms"
    case refreshLeadMillis = "refresh_lead_ms"
    case supportsRefresh = "supports_refresh"
    case refreshExchange = "refresh_exchange"
    case authorizationUrl = "authorization_url"
    case tokenUrl = "token_url"
    case scopes
  }

  static func defaultSteps(_ method: AgentMcpAuthMethod) throws -> [AgentMcpAuthStepSpec] {
    switch method {
    case .none:
      return []
    case .bearerToken:
      return [try AgentMcpAuthStepSpec(
        id: "token",
        title: "Access token",
        fields: [try AgentMcpAuthFieldSpec(id: "access_token", label: "Access token", type: .apiKey)]
      )]
    case .apiKey:
      return [try AgentMcpAuthStepSpec(
        id: "api_key",
        title: "API key",
        fields: [
          try AgentMcpAuthFieldSpec(id: "api_key", label: "API key", type: .apiKey),
          try AgentMcpAuthFieldSpec(
            id: "header_name",
            label: "Header name",
            type: .text,
            required: false,
            secret: false,
            placeholder: "X-API-Key"
          )
        ]
      )]
    case .usernamePassword:
      return [try AgentMcpAuthStepSpec(
        id: "credentials",
        title: "Sign in",
        fields: [
          try AgentMcpAuthFieldSpec(id: "username", label: "Username", type: .text, secret: false),
          try AgentMcpAuthFieldSpec(id: "password", label: "Password", type: .password)
        ]
      )]
    case .oauth2:
      return [try AgentMcpAuthStepSpec(
        id: "oauth",
        title: "Authorize access",
        fields: [try AgentMcpAuthFieldSpec(id: "access_token", label: "OAuth access token", type: .apiKey)]
      )]
    case .deviceCode:
      return [try AgentMcpAuthStepSpec(
        id: "device_code",
        title: "Device authorization",
        fields: [try AgentMcpAuthFieldSpec(id: "device_code", label: "Device code", type: .otp)]
      )]
    case .dynamic:
      return [
        try AgentMcpAuthStepSpec(
          id: "credentials",
          title: "Sign in",
          fields: [
            try AgentMcpAuthFieldSpec(id: "username", label: "Username", type: .text, secret: false),
            try AgentMcpAuthFieldSpec(id: "password", label: "Password", type: .password)
          ]
        ),
        try AgentMcpAuthStepSpec(
          id: "verification",
          title: "Verify sign-in",
          fields: [try AgentMcpAuthFieldSpec(id: "otp", label: "Verification code", type: .otp)],
          expiresInSeconds: 300
        )
      ]
    }
  }
}

struct AgentMcpDeclarativeTool: Codable, Equatable, Identifiable {
  var name: String
  var title: String
  var description: String
  var inputSchema: AgentMcpJSONObject
  var method: String
  var pathTemplate: String
  var headerTemplates: [String: String]
  var bodyTemplate: String
  var resultJsonPath: String
  var mutating: Bool

  var id: String { name }

  enum CodingKeys: String, CodingKey {
    case name
    case title
    case description
    case inputSchema = "input_schema"
    case method
    case pathTemplate = "path"
    case headerTemplates = "headers"
    case bodyTemplate = "body_template"
    case resultJsonPath = "result_json_path"
    case mutating
  }
}

struct AgentMcpLocalRuntimeSpec: Codable, Equatable {
  var language: AgentRuntimeLanguage
  var entrypoint: String
  var arguments: [String]
  var environment: [String: String]
  var allowedNetworkDomains: [String]
  var timeoutMillis: Int64

  init(
    language: AgentRuntimeLanguage,
    entrypoint: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    allowedNetworkDomains: [String] = [],
    timeoutMillis: Int64 = 60_000
  ) {
    self.language = language
    self.entrypoint = entrypoint
    self.arguments = arguments
    self.environment = environment
    self.allowedNetworkDomains = allowedNetworkDomains
    self.timeoutMillis = timeoutMillis
  }

  enum CodingKeys: String, CodingKey {
    case language = "runtime"
    case entrypoint
    case arguments
    case environment
    case allowedNetworkDomains = "allowed_network_domains"
    case timeoutMillis = "timeout_ms"
  }
}

struct AgentMcpPackageManifest: Codable, Equatable, Identifiable {
  static let supportedFormatVersion = 1

  var id: String
  var version: String
  var name: String
  var description: String
  var catalogId: String
  var endpoint: String
  var transport: AgentMcpTransportKind
  var authProfiles: [AgentMcpAuthProfile]
  var tools: [AgentMcpDeclarativeTool]
  var localRuntime: AgentMcpLocalRuntimeSpec?
  var formatVersion: Int
  var author: String
  var website: String

  init(
    id: String,
    version: String,
    name: String,
    description: String,
    catalogId: String = "",
    endpoint: String,
    transport: AgentMcpTransportKind,
    authProfiles: [AgentMcpAuthProfile],
    tools: [AgentMcpDeclarativeTool],
    localRuntime: AgentMcpLocalRuntimeSpec? = nil,
    formatVersion: Int = AgentMcpPackageManifest.supportedFormatVersion,
    author: String = "",
    website: String = ""
  ) {
    self.id = id
    self.version = version
    self.name = name
    self.description = description
    self.catalogId = catalogId
    self.endpoint = endpoint
    self.transport = transport
    self.authProfiles = authProfiles
    self.tools = tools
    self.localRuntime = localRuntime
    self.formatVersion = formatVersion
    self.author = author
    self.website = website
  }

  enum CodingKeys: String, CodingKey {
    case id
    case version
    case name
    case description
    case catalogId = "catalog_id"
    case endpoint
    case transport
    case authProfiles = "authentication"
    case tools
    case localRuntime = "local_runtime"
    case formatVersion = "format_version"
    case author
    case website
  }
}

enum AgentMcpPackageManifestCodec {
  static func decode(_ document: String) throws -> AgentMcpPackageManifest {
    guard Data(document.utf8).count <= maxManifestBytes,
          let data = document.data(using: .utf8),
          let root = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      throw AgentRuntimeCapabilityError.invalid("MCP package manifest is invalid")
    }
    let formatVersion = Int(root["format_version"]?.intValue ?? 1)
    guard formatVersion == AgentMcpPackageManifest.supportedFormatVersion else {
      throw AgentRuntimeCapabilityError.invalid("Unsupported MCP package format version: \(formatVersion)")
    }
    let id = try requiredString(root, "id")
    let version = try requiredString(root, "version")
    let name = try requiredString(root, "name")
    guard matches(id, idPattern) else {
      throw AgentRuntimeCapabilityError.invalid("Invalid MCP package id: \(id)")
    }
    guard matches(version, versionPattern) else {
      throw AgentRuntimeCapabilityError.invalid("Invalid MCP package version: \(version)")
    }
    guard let transportObject = root["transport"]?.objectValue else {
      throw AgentRuntimeCapabilityError.invalid("MCP package transport is required")
    }
    let transportValue = string(transportObject, "type", defaultValue: AgentMcpTransportKind.streamableHTTP.rawValue)
    guard let transport = AgentMcpTransportKind(rawValue: transportValue) else {
      throw AgentRuntimeCapabilityError.invalid("Unsupported MCP package transport")
    }
    let localRuntime = transport == .localStdio ? try decodeLocalRuntime(transportObject) : nil
    let endpoint: String
    if transport == .localStdio {
      endpoint = "local-mcp:\(id)"
    } else {
      endpoint = try AgentMcpEndpointPolicy.normalize(try requiredString(transportObject, "endpoint"))
    }
    let authProfiles = try decodeAuthProfiles(root["authentication"]?.arrayValue)
    let tools = try decodeTools(root["tools"]?.arrayValue, transport: transport)
    if transport == .declarativeHTTP, tools.isEmpty {
      throw AgentRuntimeCapabilityError.invalid("Declarative MCP package must declare at least one tool")
    }
    if transport == .localStdio {
      let exchanges = authProfiles.flatMap(\.steps).contains { $0.exchange != nil } ||
        authProfiles.contains { $0.refreshExchange != nil }
      guard !exchanges else {
        throw AgentRuntimeCapabilityError.invalid(
          "Local stdio MCP authentication must be handled inside the sandboxed server"
        )
      }
    }
    guard Set(tools.map(\.name)).count == tools.count else {
      throw AgentRuntimeCapabilityError.invalid("MCP package tool names must be unique")
    }
    return AgentMcpPackageManifest(
      id: id,
      version: version,
      name: name,
      description: bounded(string(root, "description"), maxTextCharacters),
      catalogId: bounded(string(root, "catalog_id"), maxIdCharacters),
      endpoint: endpoint,
      transport: transport,
      authProfiles: authProfiles.isEmpty ? [try AgentMcpAuthProfile(.none)] : authProfiles,
      tools: tools,
      localRuntime: localRuntime,
      formatVersion: formatVersion,
      author: bounded(string(root, "author"), maxTextCharacters),
      website: bounded(string(root, "website"), maxUrlCharacters)
    )
  }

  static func encode(_ manifest: AgentMcpPackageManifest) throws -> String {
    var transport: AgentMcpJSONObject = ["type": .string(manifest.transport.rawValue)]
    if manifest.transport == .localStdio {
      guard let runtime = manifest.localRuntime else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP package runtime is required")
      }
      transport["runtime"] = .string(runtime.language.rawValue)
      transport["entrypoint"] = .string(runtime.entrypoint)
      transport["arguments"] = .array(runtime.arguments.map(AgentMcpJSONValue.string))
      transport["environment"] = .object(runtime.environment.reduce(into: AgentMcpJSONObject()) { object, item in
        object[item.key] = .string(item.value)
      })
      transport["allowed_network_domains"] = .array(runtime.allowedNetworkDomains.map(AgentMcpJSONValue.string))
      transport["timeout_ms"] = .int(runtime.timeoutMillis)
    } else {
      transport["endpoint"] = .string(manifest.endpoint)
    }
    return AgentMcpJSONCodec.stringify([
      "format_version": .int(Int64(manifest.formatVersion)),
      "id": .string(manifest.id),
      "version": .string(manifest.version),
      "name": .string(manifest.name),
      "description": .string(manifest.description),
      "catalog_id": .string(manifest.catalogId),
      "author": .string(manifest.author),
      "website": .string(manifest.website),
      "transport": .object(transport),
      "authentication": .array(manifest.authProfiles.map { .object(encodeAuthProfile($0)) }),
      "tools": .array(manifest.tools.map { .object(encodeTool($0)) })
    ])
  }

  private static func decodeAuthProfiles(_ array: [AgentMcpJSONValue]?) throws -> [AgentMcpAuthProfile] {
    guard let array else { return [] }
    guard array.count <= maxAuthProfiles else {
      throw AgentRuntimeCapabilityError.invalid("Too many MCP authentication profiles")
    }
    var profiles: [AgentMcpAuthProfile] = []
    var seen: Set<AgentMcpAuthMethod> = []
    for value in array {
      guard let raw = value.objectValue else {
        throw AgentRuntimeCapabilityError.invalid("Invalid MCP authentication profile")
      }
      let method = AgentMcpAuthMethod.fromWireValue(string(raw, "method", defaultValue: "none"))
      let steps = try decodeAuthSteps(raw["steps"]?.arrayValue)
      let profile = try AgentMcpAuthProfile(
        method,
        steps: steps.isEmpty ? nil : steps,
        accessTokenTtlMillis: max(raw["access_token_ttl_seconds"]?.intValue ?? 0, 0) * 1_000,
        refreshLeadMillis: max(raw["refresh_lead_seconds"]?.intValue ?? 300, 0) * 1_000,
        supportsRefresh: raw["supports_refresh"]?.boolValue ?? false,
        refreshExchange: try raw["refresh_exchange"]?.objectValue.map { try decodeAuthExchange($0) },
        authorizationUrl: bounded(string(raw, "authorization_url"), maxUrlCharacters),
        tokenUrl: bounded(string(raw, "token_url"), maxUrlCharacters),
        scopes: try stringList(raw["scopes"]?.arrayValue, limit: maxScopes)
      )
      if !seen.contains(method) {
        profiles.append(profile)
        seen.insert(method)
      }
    }
    return profiles
  }

  private static func decodeAuthSteps(_ array: [AgentMcpJSONValue]?) throws -> [AgentMcpAuthStepSpec] {
    guard let array else { return [] }
    guard array.count <= maxAuthSteps else {
      throw AgentRuntimeCapabilityError.invalid("Too many MCP authentication steps")
    }
    return try array.map { value in
      guard let raw = value.objectValue else {
        throw AgentRuntimeCapabilityError.invalid("Invalid MCP authentication step")
      }
      let fieldsArray = raw["fields"]?.arrayValue ?? []
      guard fieldsArray.count <= maxAuthFields else {
        throw AgentRuntimeCapabilityError.invalid("Too many MCP authentication fields")
      }
      let fields = try fieldsArray.map { fieldValue -> AgentMcpAuthFieldSpec in
        guard let field = fieldValue.objectValue else {
          throw AgentRuntimeCapabilityError.invalid("Invalid MCP authentication field")
        }
        let type = AgentMcpAuthFieldType.fromWireValue(string(field, "type", defaultValue: "text"))
        return try AgentMcpAuthFieldSpec(
          id: try requiredString(field, "id"),
          label: bounded(try requiredString(field, "label"), maxTextCharacters),
          type: type,
          required: field["required"]?.boolValue ?? true,
          secret: field["secret"]?.boolValue,
          placeholder: bounded(string(field, "placeholder"), maxTextCharacters),
          options: try stringList(field["options"]?.arrayValue, limit: maxOptions)
        )
      }
      return try AgentMcpAuthStepSpec(
        id: try requiredString(raw, "id"),
        title: bounded(try requiredString(raw, "title"), maxTextCharacters),
        description: bounded(string(raw, "description"), maxTextCharacters),
        fields: fields,
        expiresInSeconds: max(raw["expires_in_seconds"]?.intValue ?? 0, 0),
        exchange: try raw["exchange"]?.objectValue.map { try decodeAuthExchange($0) }
      )
    }
  }

  private static func decodeAuthExchange(_ raw: AgentMcpJSONObject) throws -> AgentMcpAuthExchangeSpec {
    let statuses = raw["accepted_status_codes"]?.arrayValue?
      .compactMap(\.intValue)
      .map(Int.init)
      .filter { (200...299).contains($0) } ?? []
    return try AgentMcpAuthExchangeSpec(
      method: string(raw, "method", defaultValue: "POST").uppercased(),
      pathTemplate: bounded(try requiredString(raw, "path"), maxTemplateCharacters),
      headerTemplates: stringMap(raw["headers"]?.objectValue, maxValueCharacters: maxTemplateCharacters),
      bodyTemplate: bounded(string(raw, "body_template"), maxBodyTemplateCharacters),
      responseMappings: stringMap(raw["response_mappings"]?.objectValue, maxValueCharacters: maxTextCharacters),
      acceptedStatusCodes: statuses.isEmpty ? Set([200]) : Set(statuses)
    )
  }

  private static func decodeTools(
    _ array: [AgentMcpJSONValue]?,
    transport: AgentMcpTransportKind
  ) throws -> [AgentMcpDeclarativeTool] {
    guard let array else { return [] }
    guard array.count <= maxTools else {
      throw AgentRuntimeCapabilityError.invalid("MCP package declares too many tools")
    }
    return try array.map { value in
      guard let raw = value.objectValue else {
        throw AgentRuntimeCapabilityError.invalid("Invalid MCP package tool")
      }
      let request = raw["request"]?.objectValue ?? [:]
      let method = string(request, "method", defaultValue: "POST").uppercased()
      guard allowedMethods.contains(method) else {
        throw AgentRuntimeCapabilityError.invalid("Unsupported declarative MCP method: \(method)")
      }
      let path = string(request, "path", defaultValue: "/").trimmingCharacters(in: .whitespacesAndNewlines)
      guard path.hasPrefix("/"), !path.contains(".."), !path.contains("://") else {
        throw AgentRuntimeCapabilityError.invalid("Declarative MCP tool path must be an endpoint-relative path")
      }
      if transport == .declarativeHTTP, request["path"] == nil {
        throw AgentRuntimeCapabilityError.invalid("Declarative MCP tool request path is required")
      }
      let name = try requiredString(raw, "name")
      return AgentMcpDeclarativeTool(
        name: name,
        title: bounded(string(raw, "title", defaultValue: name), maxTextCharacters),
        description: bounded(string(raw, "description"), maxTextCharacters),
        inputSchema: raw["input_schema"]?.objectValue ?? [:],
        method: method,
        pathTemplate: bounded(path, maxTemplateCharacters),
        headerTemplates: stringMap(request["headers"]?.objectValue, maxValueCharacters: maxTemplateCharacters),
        bodyTemplate: bounded(string(request, "body_template"), maxBodyTemplateCharacters),
        resultJsonPath: bounded(string(raw, "result_json_path"), maxTextCharacters),
        mutating: raw["mutating"]?.boolValue ?? !["GET", "HEAD"].contains(method)
      )
    }
  }

  private static func decodeLocalRuntime(_ raw: AgentMcpJSONObject) throws -> AgentMcpLocalRuntimeSpec {
    let runtime = try requiredString(raw, "runtime").lowercased()
    guard let language = AgentRuntimeLanguage(rawValue: runtime), localRuntimeLanguages.contains(language) else {
      throw AgentRuntimeCapabilityError.invalid("Unsupported local MCP runtime")
    }
    let entrypoint = try normalizeRuntimePath(try requiredString(raw, "entrypoint"))
    guard entrypoint.hasPrefix(runtimeDirectory) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP entrypoint must be stored under runtime/")
    }
    let arguments = try stringList(raw["arguments"]?.arrayValue, limit: maxLocalArguments)
    guard arguments.allSatisfy({ $0.count <= maxLocalArgumentCharacters && !$0.contains("\u{0000}") }) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP runtime argument is invalid")
    }
    let environment = try localEnvironment(raw["environment"]?.objectValue)
    let domains = try stringList(raw["allowed_network_domains"]?.arrayValue, limit: maxLocalNetworkDomains)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    guard domains.allSatisfy({ matches($0, domainPattern) }) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP network domain is invalid")
    }
    guard domains.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid(
        "Local stdio MCP direct networking is unavailable; use a remote or declarative HTTP transport"
      )
    }
    let timeout = raw["timeout_ms"]?.intValue ?? 60_000
    guard (minLocalTimeoutMillis...maxLocalTimeoutMillis).contains(timeout) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP timeout is outside the allowed range")
    }
    return AgentMcpLocalRuntimeSpec(
      language: language,
      entrypoint: entrypoint,
      arguments: arguments,
      environment: environment,
      allowedNetworkDomains: unique(domains),
      timeoutMillis: timeout
    )
  }

  private static func normalizeRuntimePath(_ raw: String) throws -> String {
    let normalized = String(raw.replacingOccurrences(of: "\\", with: "/").drop { $0 == "/" })
    guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          normalized.count <= maxLocalEntrypointCharacters else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP entrypoint is invalid")
    }
    let segments = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP entrypoint is unsafe")
    }
    guard normalized.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP entrypoint must be relative")
    }
    return normalized
  }

  private static func encodeAuthProfile(_ profile: AgentMcpAuthProfile) -> AgentMcpJSONObject {
    var object: AgentMcpJSONObject = [
      "method": .string(profile.method.rawValue),
      "access_token_ttl_seconds": .int(profile.accessTokenTtlMillis / 1_000),
      "refresh_lead_seconds": .int(profile.refreshLeadMillis / 1_000),
      "supports_refresh": .bool(profile.supportsRefresh),
      "authorization_url": .string(profile.authorizationUrl),
      "token_url": .string(profile.tokenUrl),
      "scopes": .array(profile.scopes.map(AgentMcpJSONValue.string)),
      "steps": .array(profile.steps.map { step in
        var stepObject: AgentMcpJSONObject = [
          "id": .string(step.id),
          "title": .string(step.title),
          "description": .string(step.description),
          "expires_in_seconds": .int(step.expiresInSeconds),
          "fields": .array(step.fields.map { field in
            .object([
              "id": .string(field.id),
              "label": .string(field.label),
              "type": .string(field.type.rawValue),
              "required": .bool(field.required),
              "secret": .bool(field.secret),
              "placeholder": .string(field.placeholder),
              "options": .array(field.options.map(AgentMcpJSONValue.string))
            ])
          })
        ]
        if let exchange = step.exchange {
          stepObject["exchange"] = .object(encodeAuthExchange(exchange))
        }
        return .object(stepObject)
      })
    ]
    if let exchange = profile.refreshExchange {
      object["refresh_exchange"] = .object(encodeAuthExchange(exchange))
    }
    return object
  }

  private static func encodeAuthExchange(_ exchange: AgentMcpAuthExchangeSpec) -> AgentMcpJSONObject {
    [
      "method": .string(exchange.method),
      "path": .string(exchange.pathTemplate),
      "headers": .object(exchange.headerTemplates.reduce(into: AgentMcpJSONObject()) { object, item in
        object[item.key] = .string(item.value)
      }),
      "body_template": .string(exchange.bodyTemplate),
      "response_mappings": .object(exchange.responseMappings.reduce(into: AgentMcpJSONObject()) { object, item in
        object[item.key] = .string(item.value)
      }),
      "accepted_status_codes": .array(exchange.acceptedStatusCodes.sorted().map { .int(Int64($0)) })
    ]
  }

  private static func encodeTool(_ tool: AgentMcpDeclarativeTool) -> AgentMcpJSONObject {
    [
      "name": .string(tool.name),
      "title": .string(tool.title),
      "description": .string(tool.description),
      "input_schema": .object(tool.inputSchema),
      "result_json_path": .string(tool.resultJsonPath),
      "mutating": .bool(tool.mutating),
      "request": .object([
        "method": .string(tool.method),
        "path": .string(tool.pathTemplate),
        "headers": .object(tool.headerTemplates.reduce(into: AgentMcpJSONObject()) { object, item in
          object[item.key] = .string(item.value)
        }),
        "body_template": .string(tool.bodyTemplate)
      ])
    ]
  }

  private static func requiredString(_ object: AgentMcpJSONObject, _ key: String) throws -> String {
    let value = string(object, key).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("MCP package field '\(key)' is required")
    }
    return value
  }

  private static func string(_ object: AgentMcpJSONObject, _ key: String, defaultValue: String = "") -> String {
    object[key]?.stringValue ?? defaultValue
  }

  private static func stringMap(
    _ object: AgentMcpJSONObject?,
    maxValueCharacters: Int
  ) -> [String: String] {
    object?.reduce(into: [String: String]()) { result, item in
      result[item.key] = bounded(item.value.stringValue ?? "", maxValueCharacters)
    } ?? [:]
  }

  private static func localEnvironment(_ object: AgentMcpJSONObject?) throws -> [String: String] {
    guard let object else { return [:] }
    guard object.count <= maxLocalEnvironmentValues else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP environment is too large")
    }
    return try object.reduce(into: [String: String]()) { result, item in
      guard matches(item.key, environmentKeyPattern) else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP environment key is invalid: \(item.key)")
      }
      let value = item.value.stringValue ?? ""
      guard value.count <= maxLocalEnvironmentValueCharacters, !value.contains("\u{0000}") else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP environment value is invalid")
      }
      result[item.key] = value
    }
  }

  private static func stringList(_ values: [AgentMcpJSONValue]?, limit: Int) throws -> [String] {
    guard let values else { return [] }
    guard values.count <= limit else {
      throw AgentRuntimeCapabilityError.invalid("MCP package list is too large")
    }
    return values.compactMap {
      $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
  }

  private static func bounded(_ value: String, _ limit: Int) -> String {
    String(value.prefix(limit))
  }

  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
  }

  private static let maxManifestBytes = 256 * 1_024
  private static let maxIdCharacters = 128
  private static let maxTextCharacters = 512
  private static let maxUrlCharacters = 2_048
  private static let maxTemplateCharacters = 4_096
  private static let maxBodyTemplateCharacters = 64 * 1_024
  private static let maxAuthProfiles = 8
  private static let maxAuthSteps = 8
  private static let maxAuthFields = 24
  private static let maxOptions = 64
  private static let maxScopes = 64
  private static let maxTools = 128
  private static let maxLocalArguments = 32
  private static let maxLocalArgumentCharacters = 2_048
  private static let maxLocalEnvironmentValues = 32
  private static let maxLocalEnvironmentValueCharacters = 4_096
  private static let maxLocalNetworkDomains = 32
  private static let maxLocalEntrypointCharacters = 512
  private static let minLocalTimeoutMillis: Int64 = 5_000
  private static let maxLocalTimeoutMillis: Int64 = 180_000
  private static let runtimeDirectory = "runtime/"
  private static let idPattern = #"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$"#
  private static let versionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$"#
  private static let allowedMethods: Set<String> = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]
  private static let localRuntimeLanguages: Set<AgentRuntimeLanguage> = [.shell, .python, .javascript, .typescript]
  private static let environmentKeyPattern = #"^[A-Z_][A-Z0-9_]{0,63}$"#
  private static let domainPattern = #"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#
}

struct AgentMcpPackageInspection: Codable, Equatable {
  var manifest: AgentMcpPackageManifest
  var rawManifest: String
  var packageSha256: String
  var manifestSha256: String
  var integrityVerified: Bool
  var archiveEntries: [String]
  var runtimeFiles: [String: Data]

  enum CodingKeys: String, CodingKey {
    case manifest
    case rawManifest = "raw_manifest"
    case packageSha256 = "package_sha256"
    case manifestSha256 = "manifest_sha256"
    case integrityVerified = "integrity_verified"
    case archiveEntries = "archive_entries"
    case runtimeFiles = "runtime_files"
  }
}

struct AgentMcpPackageInstaller {
  func inspect(_ packageData: Data) throws -> AgentMcpPackageInspection {
    guard packageData.count <= Self.maxPackageBytes else {
      throw AgentRuntimeCapabilityError.invalid("MCP package content exceeds \(Self.maxPackageBytes) bytes")
    }
    let packageSha = Self.sha256(packageData)
    let files = try readArchive(packageData)
    guard let rawManifestData = files[Self.manifestPath],
          let rawManifest = String(data: rawManifestData, encoding: .utf8) else {
      throw AgentRuntimeCapabilityError.invalid("MCP package is missing \(Self.manifestPath)")
    }
    guard rawManifestData.count <= Self.maxManifestBytes else {
      throw AgentRuntimeCapabilityError.invalid("MCP package manifest is too large")
    }
    let manifestSha = Self.sha256(Data(rawManifest.utf8))
    let integrityVerified: Bool
    if let integrityData = files[Self.integrityPath],
       let integrity = String(data: integrityData, encoding: .utf8) {
      integrityVerified = try verifyIntegrity(integrity, manifestSha: manifestSha)
    } else {
      integrityVerified = false
    }
    let manifest = try AgentMcpPackageManifestCodec.decode(rawManifest)
    let runtimeFiles = files.filter { $0.key.hasPrefix(Self.runtimeDirectory) }
    if manifest.transport == .localStdio {
      let entrypoint = try requireLocalRuntime(manifest).entrypoint
      guard runtimeFiles[entrypoint] != nil else {
        throw AgentRuntimeCapabilityError.invalid("Local MCP package is missing its runtime entrypoint: \(entrypoint)")
      }
    }
    return AgentMcpPackageInspection(
      manifest: manifest,
      rawManifest: rawManifest,
      packageSha256: packageSha,
      manifestSha256: manifestSha,
      integrityVerified: integrityVerified,
      archiveEntries: files.keys.sorted(),
      runtimeFiles: runtimeFiles
    )
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private struct ZipEntry {
    var path: String
    var directory: Bool
    var method: UInt16
    var compressedBytes: Int64
    var uncompressedBytes: Int64
    var crc32: UInt32
    var dataOffset: Int
    var dataLength: Int
  }

  private func readArchive(_ data: Data) throws -> [String: Data] {
    let entries = try inspectZipData(data)
    var files: [String: Data] = [:]
    var extractedBytes: Int64 = 0
    for entry in entries where !entry.directory {
      guard files.count < Self.maxEntries else {
        throw AgentRuntimeCapabilityError.invalid("MCP package contains too many files")
      }
      guard files[entry.path] == nil else {
        throw AgentRuntimeCapabilityError.invalid("MCP package contains a duplicate path: \(entry.path)")
      }
      guard isAllowedEntry(entry.path) else {
        throw AgentRuntimeCapabilityError.invalid("MCP package contains unsupported executable content: \(entry.path)")
      }
      let maxBytes: Int
      if entry.path == Self.manifestPath || entry.path == Self.integrityPath {
        maxBytes = Self.maxManifestBytes
      } else {
        maxBytes = Self.maxAssetBytes
      }
      let content = try extractEntry(entry, from: data, maxBytes: maxBytes)
      guard let nextBytes = checkedAdd(extractedBytes, Int64(content.count)),
            nextBytes <= Self.maxExtractedBytes else {
        throw AgentRuntimeCapabilityError.invalid("MCP package expands beyond the allowed size")
      }
      extractedBytes = nextBytes
      files[entry.path] = content
    }
    return files
  }

  private func extractEntry(_ entry: ZipEntry, from data: Data, maxBytes: Int) throws -> Data {
    guard entry.uncompressedBytes <= Int64(maxBytes),
          rangeFits(start: entry.dataOffset, length: entry.dataLength, in: data) else {
      throw AgentRuntimeCapabilityError.invalid("MCP package content exceeds \(maxBytes) bytes")
    }
    let compressed = data.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.dataLength))
    let content: Data
    switch entry.method {
    case 0:
      guard entry.dataLength <= maxBytes else {
        throw AgentRuntimeCapabilityError.invalid("MCP package content exceeds \(maxBytes) bytes")
      }
      content = compressed
    case 8:
      content = try Self.inflateDeflate(compressed, expectedBytes: entry.uncompressedBytes, maxBytes: maxBytes)
    default:
      throw AgentRuntimeCapabilityError.invalid("MCP package ZIP compression method is not supported on iOS yet")
    }
    guard Int64(content.count) == entry.uncompressedBytes else {
      throw AgentRuntimeCapabilityError.invalid("MCP package entry size changed during extraction")
    }
    guard crc32(content) == entry.crc32 else {
      throw AgentRuntimeCapabilityError.invalid("MCP package entry CRC did not match")
    }
    return content
  }

  static func inflateDeflate(_ compressed: Data, expectedBytes: Int64, maxBytes: Int) throws -> Data {
    guard expectedBytes <= Int64(maxBytes) else {
      throw AgentRuntimeCapabilityError.invalid("MCP package content exceeds \(maxBytes) bytes")
    }
    var reader = DeflateBitReader(compressed)
    var output = Data()
    var finalBlock = false
    repeat {
      finalBlock = try reader.readBits(1) == 1
      let blockType = try reader.readBits(2)
      switch blockType {
      case 0:
        try inflateStoredBlock(reader: &reader, output: &output, maxBytes: maxBytes)
      case 1:
        try inflateCompressedBlock(
          reader: &reader,
          literalTable: Self.fixedLiteralLengthTable,
          distanceTable: Self.fixedDistanceTable,
          output: &output,
          maxBytes: maxBytes
        )
      case 2:
        let tables = try dynamicDeflateTables(reader: &reader)
        try inflateCompressedBlock(
          reader: &reader,
          literalTable: tables.literal,
          distanceTable: tables.distance,
          output: &output,
          maxBytes: maxBytes
        )
      default:
        throw AgentRuntimeCapabilityError.invalid("MCP package deflate block type is reserved")
      }
    } while !finalBlock
    guard Int64(output.count) == expectedBytes else {
      throw AgentRuntimeCapabilityError.invalid("MCP package entry size changed during extraction")
    }
    return output
  }

  private static func inflateStoredBlock(
    reader: inout DeflateBitReader,
    output: inout Data,
    maxBytes: Int
  ) throws {
    reader.alignToByte()
    let length = try reader.readBits(16)
    let inverseLength = try reader.readBits(16)
    guard UInt16(length) == ~UInt16(inverseLength) else {
      throw AgentRuntimeCapabilityError.invalid("MCP package deflate stored block length is invalid")
    }
    guard output.count <= maxBytes - length else {
      throw AgentRuntimeCapabilityError.invalid("MCP package content exceeds \(maxBytes) bytes")
    }
    output.append(try reader.readBytes(length))
  }

  private static func inflateCompressedBlock(
    reader: inout DeflateBitReader,
    literalTable: DeflateHuffmanTable,
    distanceTable: DeflateHuffmanTable,
    output: inout Data,
    maxBytes: Int
  ) throws {
    while true {
      let symbol = try literalTable.decode(reader: &reader)
      if symbol < 256 {
        guard output.count < maxBytes else {
          throw AgentRuntimeCapabilityError.invalid("MCP package content exceeds \(maxBytes) bytes")
        }
        output.append(UInt8(symbol))
      } else if symbol == 256 {
        return
      } else {
        let lengthIndex = symbol - 257
        guard Self.deflateLengthBases.indices.contains(lengthIndex) else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate length code is invalid")
        }
        let extraLength = try reader.readBits(Self.deflateLengthExtraBits[lengthIndex])
        let length = Self.deflateLengthBases[lengthIndex] + extraLength
        let distanceSymbol = try distanceTable.decode(reader: &reader)
        guard Self.deflateDistanceBases.indices.contains(distanceSymbol) else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate distance code is invalid")
        }
        let extraDistance = try reader.readBits(Self.deflateDistanceExtraBits[distanceSymbol])
        let distance = Self.deflateDistanceBases[distanceSymbol] + extraDistance
        try copyDeflateMatch(length: length, distance: distance, output: &output, maxBytes: maxBytes)
      }
    }
  }

  private static func copyDeflateMatch(length: Int, distance: Int, output: inout Data, maxBytes: Int) throws {
    guard distance > 0, distance <= output.count else {
      throw AgentRuntimeCapabilityError.invalid("MCP package deflate distance is invalid")
    }
    guard output.count <= maxBytes - length else {
      throw AgentRuntimeCapabilityError.invalid("MCP package content exceeds \(maxBytes) bytes")
    }
    for _ in 0..<length {
      output.append(output[output.count - distance])
    }
  }

  private static func dynamicDeflateTables(reader: inout DeflateBitReader) throws -> (literal: DeflateHuffmanTable, distance: DeflateHuffmanTable) {
    let literalCount = try reader.readBits(5) + 257
    let distanceCount = try reader.readBits(5) + 1
    let codeLengthCount = try reader.readBits(4) + 4
    var codeLengthLengths = Array(repeating: 0, count: 19)
    for index in 0..<codeLengthCount {
      codeLengthLengths[Self.deflateCodeLengthOrder[index]] = try reader.readBits(3)
    }
    let codeLengthTable = try DeflateHuffmanTable(lengths: codeLengthLengths)
    var lengths: [Int] = []
    let totalCount = literalCount + distanceCount
    while lengths.count < totalCount {
      let symbol = try codeLengthTable.decode(reader: &reader)
      switch symbol {
      case 0...15:
        lengths.append(symbol)
      case 16:
        guard let previous = lengths.last else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate repeat code has no previous length")
        }
        let repeatCount = try reader.readBits(2) + 3
        guard lengths.count <= totalCount - repeatCount else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate code lengths overflow")
        }
        lengths.append(contentsOf: Array(repeating: previous, count: repeatCount))
      case 17:
        let repeatCount = try reader.readBits(3) + 3
        guard lengths.count <= totalCount - repeatCount else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate code lengths overflow")
        }
        lengths.append(contentsOf: Array(repeating: 0, count: repeatCount))
      case 18:
        let repeatCount = try reader.readBits(7) + 11
        guard lengths.count <= totalCount - repeatCount else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate code lengths overflow")
        }
        lengths.append(contentsOf: Array(repeating: 0, count: repeatCount))
      default:
        throw AgentRuntimeCapabilityError.invalid("MCP package deflate code length symbol is invalid")
      }
    }
    return (
      try DeflateHuffmanTable(lengths: Array(lengths.prefix(literalCount))),
      try DeflateHuffmanTable(lengths: Array(lengths.dropFirst(literalCount)), allowEmpty: true)
    )
  }

  private struct DeflateBitReader {
    private let bytes: [UInt8]
    private var offset = 0
    private var bitBuffer: UInt32 = 0
    private var bitCount = 0

    init(_ data: Data) {
      self.bytes = Array(data)
    }

    mutating func readBits(_ count: Int) throws -> Int {
      guard count >= 0, count <= 16 else {
        throw AgentRuntimeCapabilityError.invalid("MCP package deflate bit count is invalid")
      }
      if count == 0 {
        return 0
      }
      while bitCount < count {
        guard offset < bytes.count else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate stream ended unexpectedly")
        }
        bitBuffer |= UInt32(bytes[offset]) << UInt32(bitCount)
        bitCount += 8
        offset += 1
      }
      let mask = (UInt32(1) << UInt32(count)) - 1
      let value = Int(bitBuffer & mask)
      bitBuffer >>= UInt32(count)
      bitCount -= count
      return value
    }

    mutating func alignToByte() {
      bitBuffer = 0
      bitCount = 0
    }

    mutating func readBytes(_ count: Int) throws -> Data {
      guard count >= 0, bitCount == 0, offset <= bytes.count, count <= bytes.count - offset else {
        throw AgentRuntimeCapabilityError.invalid("MCP package deflate byte range is invalid")
      }
      let next = offset + count
      let chunk = Data(bytes[offset..<next])
      offset = next
      return chunk
    }
  }

  private struct DeflateHuffmanTable {
    private let symbolsByLengthAndCode: [Int: Int]
    private let maxBits: Int

    init(lengths: [Int], allowEmpty: Bool = false) throws {
      let maxBits = lengths.max() ?? 0
      if maxBits == 0, allowEmpty {
        self.maxBits = 0
        self.symbolsByLengthAndCode = [:]
        return
      }
      guard maxBits > 0, maxBits <= 15 else {
        throw AgentRuntimeCapabilityError.invalid("MCP package deflate Huffman table is invalid")
      }
      var counts = Array(repeating: 0, count: maxBits + 1)
      for length in lengths where length > 0 {
        guard length <= maxBits else {
          throw AgentRuntimeCapabilityError.invalid("MCP package deflate Huffman length is invalid")
        }
        counts[length] += 1
      }
      var code = 0
      var nextCodes = Array(repeating: 0, count: maxBits + 1)
      for bitCount in 1...maxBits {
        code = (code + counts[bitCount - 1]) << 1
        nextCodes[bitCount] = code
      }
      var table: [Int: Int] = [:]
      for (symbol, length) in lengths.enumerated() where length > 0 {
        let reversed = Self.reversedBits(nextCodes[length], count: length)
        table[(length << 16) | reversed] = symbol
        nextCodes[length] += 1
      }
      self.maxBits = maxBits
      self.symbolsByLengthAndCode = table
    }

    func decode(reader: inout DeflateBitReader) throws -> Int {
      guard maxBits > 0 else {
        throw AgentRuntimeCapabilityError.invalid("MCP package deflate Huffman table is empty")
      }
      var code = 0
      for length in 1...maxBits {
        code |= try reader.readBits(1) << (length - 1)
        if let symbol = symbolsByLengthAndCode[(length << 16) | code] {
          return symbol
        }
      }
      throw AgentRuntimeCapabilityError.invalid("MCP package deflate Huffman code is invalid")
    }

    private static func reversedBits(_ value: Int, count: Int) -> Int {
      var result = 0
      for index in 0..<count {
        result = (result << 1) | ((value >> index) & 1)
      }
      return result
    }
  }

  private func inspectZipData(_ data: Data) throws -> [ZipEntry] {
    guard let eocdOffset = endOfCentralDirectoryOffset(data),
          let diskNumber = readUInt16LE(data, eocdOffset + 4),
          let centralDisk = readUInt16LE(data, eocdOffset + 6),
          let diskEntryCount = readUInt16LE(data, eocdOffset + 8),
          let totalEntryCount = readUInt16LE(data, eocdOffset + 10),
          let centralSizeValue = readUInt32LE(data, eocdOffset + 12),
          let centralOffsetValue = readUInt32LE(data, eocdOffset + 16) else {
      throw AgentRuntimeCapabilityError.invalid("ZIP central directory was not found")
    }
    guard diskNumber == 0, centralDisk == 0, diskEntryCount == totalEntryCount else {
      throw AgentRuntimeCapabilityError.invalid("Multi-disk MCP package archives are not supported")
    }
    let entryCount = Int(totalEntryCount)
    guard entryCount <= Self.maxEntries else {
      throw AgentRuntimeCapabilityError.invalid("MCP package contains too many files")
    }
    let centralOffset = Int(centralOffsetValue)
    let centralSize = Int(centralSizeValue)
    guard rangeFits(start: centralOffset, length: centralSize, in: data) else {
      throw AgentRuntimeCapabilityError.invalid("ZIP central directory is out of bounds")
    }

    var cursor = centralOffset
    var entries: [ZipEntry] = []
    var seen: Set<String> = []
    for _ in 0..<entryCount {
      guard readUInt32LE(data, cursor) == 0x02014b50,
            let flags = readUInt16LE(data, cursor + 8),
            let method = readUInt16LE(data, cursor + 10),
            let crc = readUInt32LE(data, cursor + 16),
            let compressed = readUInt32LE(data, cursor + 20),
            let uncompressed = readUInt32LE(data, cursor + 24),
            let nameLength = readUInt16LE(data, cursor + 28),
            let extraLength = readUInt16LE(data, cursor + 30),
            let commentLength = readUInt16LE(data, cursor + 32),
            let localOffsetValue = readUInt32LE(data, cursor + 42) else {
        throw AgentRuntimeCapabilityError.invalid("ZIP central directory entry is invalid")
      }
      guard flags & 0x0001 == 0 else {
        throw AgentRuntimeCapabilityError.invalid("Encrypted MCP package entries are not supported")
      }
      guard method == 0 || method == 8 else {
        throw AgentRuntimeCapabilityError.invalid("MCP package ZIP compression method is not supported on iOS yet")
      }
      let nameStart = cursor + 46
      let extraStart = nameStart + Int(nameLength)
      let commentStart = extraStart + Int(extraLength)
      let nextCursor = commentStart + Int(commentLength)
      guard rangeFits(start: nameStart, length: Int(nameLength), in: data),
            rangeFits(start: extraStart, length: Int(extraLength), in: data),
            rangeFits(start: commentStart, length: Int(commentLength), in: data),
            nextCursor <= centralOffset + centralSize else {
        throw AgentRuntimeCapabilityError.invalid("ZIP central directory entry is out of bounds")
      }
      guard let rawName = String(data: data.subdata(in: nameStart..<extraStart), encoding: .utf8) else {
        throw AgentRuntimeCapabilityError.invalid("ZIP entry name is not valid UTF-8")
      }
      let directory = rawName.hasSuffix("/") || rawName.hasSuffix("\\")
      let normalizedName = try normalizeEntryName(rawName)
      guard seen.insert(normalizedName).inserted else {
        throw AgentRuntimeCapabilityError.invalid("MCP package contains a duplicate path: \(normalizedName)")
      }
      let localOffset = Int(localOffsetValue)
      guard let dataOffset = zipEntryDataOffset(data, localOffset: localOffset),
            rangeFits(start: dataOffset, length: Int(compressed), in: data) else {
        throw AgentRuntimeCapabilityError.invalid("ZIP local entry is out of bounds")
      }
      entries.append(ZipEntry(
        path: normalizedName,
        directory: directory,
        method: method,
        compressedBytes: Int64(compressed),
        uncompressedBytes: Int64(uncompressed),
        crc32: crc,
        dataOffset: dataOffset,
        dataLength: Int(compressed)
      ))
      cursor = nextCursor
    }
    return entries.sorted { $0.path < $1.path }
  }

  private func normalizeEntryName(_ raw: String) throws -> String {
    var value = raw.replacingOccurrences(of: "\\", with: "/")
    while value.hasPrefix("/") {
      value.removeFirst()
    }
    while value.hasSuffix("/") {
      value.removeLast()
    }
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("MCP package contains an empty path")
    }
    guard !value.contains("\u{0000}") else {
      throw AgentRuntimeCapabilityError.invalid("MCP package path contains a null character")
    }
    guard value.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else {
      throw AgentRuntimeCapabilityError.invalid("MCP package path must be relative")
    }
    let segments = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw AgentRuntimeCapabilityError.invalid("MCP package path traversal is not allowed")
    }
    return value
  }

  private func isAllowedEntry(_ name: String) -> Bool {
    if [Self.manifestPath, Self.integrityPath, "README.md", "LICENSE"].contains(name) {
      return true
    }
    if name.hasPrefix(Self.runtimeDirectory) {
      let fileName = name.split(separator: "/").last.map(String.init) ?? ""
      let ext = fileName.split(separator: ".").last.map { String($0).lowercased() } ?? ""
      return Self.allowedRuntimeExtensions.contains(ext) || Self.allowedRuntimeFilenames.contains(fileName)
    }
    guard name.hasPrefix("assets/") else {
      return false
    }
    let ext = name.split(separator: ".").last.map { String($0).lowercased() } ?? ""
    return Self.allowedAssetExtensions.contains(ext)
  }

  private func verifyIntegrity(_ document: String, manifestSha: String) throws -> Bool {
    guard let data = document.data(using: .utf8),
          let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      throw AgentRuntimeCapabilityError.invalid("MCP package integrity digest is invalid")
    }
    let expected = (object["manifest_sha256"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard expected.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
      throw AgentRuntimeCapabilityError.invalid("MCP package integrity digest is invalid")
    }
    guard expected == manifestSha else {
      throw AgentRuntimeCapabilityError.invalid("MCP package manifest integrity check failed")
    }
    return true
  }

  private func requireLocalRuntime(_ manifest: AgentMcpPackageManifest) throws -> AgentMcpLocalRuntimeSpec {
    guard let localRuntime = manifest.localRuntime else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP package runtime is required")
    }
    return localRuntime
  }

  private func checkedAdd(_ left: Int64, _ right: Int64) -> Int64? {
    guard right >= 0, left <= Int64.max - right else {
      return nil
    }
    return left + right
  }

  private func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16? {
    guard rangeFits(start: offset, length: 2, in: data) else { return nil }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32? {
    guard rangeFits(start: offset, length: 4, in: data) else { return nil }
    return UInt32(data[offset]) |
      (UInt32(data[offset + 1]) << 8) |
      (UInt32(data[offset + 2]) << 16) |
      (UInt32(data[offset + 3]) << 24)
  }

  private func rangeFits(start: Int, length: Int, in data: Data) -> Bool {
    start >= 0 && length >= 0 && start <= data.count && length <= data.count - start
  }

  private func endOfCentralDirectoryOffset(_ data: Data) -> Int? {
    guard data.count >= 22 else { return nil }
    let minimumOffset = max(0, data.count - 65_557)
    for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
      if readUInt32LE(data, offset) == 0x06054b50 {
        return offset
      }
    }
    return nil
  }

  private func zipEntryDataOffset(_ data: Data, localOffset: Int) -> Int? {
    guard readUInt32LE(data, localOffset) == 0x04034b50,
          let nameLength = readUInt16LE(data, localOffset + 26),
          let extraLength = readUInt16LE(data, localOffset + 28) else {
      return nil
    }
    let dataOffset = localOffset + 30 + Int(nameLength) + Int(extraLength)
    return rangeFits(start: dataOffset, length: 0, in: data) ? dataOffset : nil
  }

  private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
      let index = Int((crc ^ UInt32(byte)) & 0xff)
      crc = (crc >> 8) ^ Self.crc32Table[index]
    }
    return crc ^ 0xffffffff
  }

  static let maxPackageBytes = 8 * 1_024 * 1_024
  static let maxManifestBytes = 256 * 1_024
  static let maxAssetBytes = 2 * 1_024 * 1_024
  static let maxExtractedBytes = 12 * 1_024 * 1_024
  static let maxEntries = 64
  static let manifestPath = "mcp.json"
  static let integrityPath = "integrity.json"
  static let runtimeDirectory = "runtime/"

  private static let allowedAssetExtensions = Set(["png", "jpg", "jpeg", "webp", "svg", "txt", "md"])
  private static let allowedRuntimeExtensions = Set([
    "py", "js", "mjs", "cjs", "json", "toml", "yaml", "yml", "txt", "md", "sh", "lock"
  ])
  private static let allowedRuntimeFilenames = Set(["package-lock.json", "uv.lock"])
  private static let fixedLiteralLengthTable: DeflateHuffmanTable = {
    var lengths = Array(repeating: 8, count: 288)
    for index in 144...255 {
      lengths[index] = 9
    }
    for index in 256...279 {
      lengths[index] = 7
    }
    for index in 280...287 {
      lengths[index] = 8
    }
    return try! DeflateHuffmanTable(lengths: lengths)
  }()
  private static let fixedDistanceTable: DeflateHuffmanTable = try! DeflateHuffmanTable(lengths: Array(repeating: 5, count: 32))
  private static let deflateCodeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
  private static let deflateLengthBases = [
    3, 4, 5, 6, 7, 8, 9, 10,
    11, 13, 15, 17, 19, 23, 27, 31,
    35, 43, 51, 59, 67, 83, 99, 115,
    131, 163, 195, 227, 258
  ]
  private static let deflateLengthExtraBits = [
    0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4,
    5, 5, 5, 5, 0
  ]
  private static let deflateDistanceBases = [
    1, 2, 3, 4, 5, 7, 9, 13,
    17, 25, 33, 49, 65, 97, 129, 193,
    257, 385, 513, 769, 1_025, 1_537, 2_049, 3_073,
    4_097, 6_145, 8_193, 12_289, 16_385, 24_577
  ]
  private static let deflateDistanceExtraBits = [
    0, 0, 0, 0, 1, 1, 2, 2,
    3, 3, 4, 4, 5, 5, 6, 6,
    7, 7, 8, 8, 9, 9, 10, 10,
    11, 11, 12, 12, 13, 13
  ]
  private static let crc32Table: [UInt32] = {
    (0..<256).map { value -> UInt32 in
      var crc = UInt32(value)
      for _ in 0..<8 {
        if crc & 1 == 1 {
          crc = (crc >> 1) ^ 0xedb88320
        } else {
          crc >>= 1
        }
      }
      return crc
    }
  }()
}
