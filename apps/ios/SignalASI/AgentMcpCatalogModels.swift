import CryptoKit
import Foundation

struct AgentMcpCatalogEntry: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var summary: String
  var distribution: AgentMcpDistribution
  var transport: AgentMcpTransportKind
  var defaultEndpoint: String
  var authProfiles: [AgentMcpAuthProfile]
  var version: String
  var toolHints: [String]
  var tags: Set<String>
  var featured: Bool
  var requiresPackage: Bool

  init(
    id: String,
    name: String,
    summary: String,
    distribution: AgentMcpDistribution,
    transport: AgentMcpTransportKind = .streamableHTTP,
    defaultEndpoint: String = "",
    authProfiles: [AgentMcpAuthProfile]? = nil,
    version: String = "1.0.0",
    toolHints: [String] = [],
    tags: Set<String> = [],
    featured: Bool = true,
    requiresPackage: Bool = false
  ) throws {
    guard id.range(of: #"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$"#, options: .regularExpression) != nil,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("MCP catalog entry is invalid")
    }
    let profiles: [AgentMcpAuthProfile]
    if let authProfiles {
      profiles = authProfiles
    } else {
      profiles = [try AgentMcpAuthProfile(.none)]
    }
    guard !profiles.isEmpty, Set(profiles.map(\.method)).count == profiles.count else {
      throw AgentRuntimeCapabilityError.invalid("MCP catalog authentication profiles must be unique")
    }
    self.id = id
    self.name = name
    self.summary = summary
    self.distribution = distribution
    self.transport = transport
    self.defaultEndpoint = defaultEndpoint
    self.authProfiles = profiles
    self.version = version
    self.toolHints = toolHints
    self.tags = tags
    self.featured = featured
    self.requiresPackage = requiresPackage
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case summary
    case distribution
    case transport
    case defaultEndpoint = "default_endpoint"
    case authProfiles = "auth_profiles"
    case version
    case toolHints = "tool_hints"
    case tags
    case featured
    case requiresPackage = "requires_package"
  }
}

struct AgentSkillManifest: Codable, Equatable {
  var id: String
  var name: String
  var version: String
  var summary: String
  var instructions: String
  var nativeTools: Set<String>
  var permissions: Set<String>
  var mcpCatalogIds: Set<String>
  var resources: [AgentSkillResource]
  var parameters: AgentSkillParameterSchema
  var steps: [AgentSkillStep]
  var formatVersion: Int
  var description: String
  var author: String
  var source: String
  var autoInvoke: Bool
  var triggerExamples: [String]
  var negativeExamples: [String]
  var renderSpec: AgentMcpJSONObject
  var tests: [AgentSkillTestCase]

  init(
    id: String,
    name: String,
    version: String,
    summary: String,
    instructions: String = "",
    nativeTools: Set<String> = [],
    permissions: Set<String> = [],
    mcpCatalogIds: Set<String> = [],
    resources: [AgentSkillResource] = [],
    parameters: AgentSkillParameterSchema = AgentSkillParameterSchema.objectSchema(),
    steps: [AgentSkillStep] = [],
    formatVersion: Int = AgentSkillLimits.supportedFormatVersion,
    description: String = "",
    author: String = "SignalASI",
    source: String = "built_in",
    autoInvoke: Bool = false,
    triggerExamples: [String] = [],
    negativeExamples: [String] = [],
    renderSpec: AgentMcpJSONObject = [:],
    tests: [AgentSkillTestCase] = []
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
    self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxTitleCharacters))
    self.version = String(version.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxVersionCharacters))
    self.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxInstructionsCharacters))
    self.instructions = String(instructions.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxInstructionsCharacters))
      .ifBlank(self.summary)
    self.nativeTools = nativeTools
    self.permissions = permissions
    self.mcpCatalogIds = mcpCatalogIds
    self.resources = Array(resources.prefix(AgentSkillLimits.maxResources))
    self.parameters = parameters
    self.steps = Array(steps.prefix(AgentSkillLimits.maxSteps))
    self.formatVersion = formatVersion
    self.description = String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxInstructionsCharacters))
      .ifBlank(self.summary)
    self.author = String(author.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxTitleCharacters))
      .ifBlank("SignalASI")
    self.source = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxIdCharacters))
      .ifBlank("built_in")
    self.autoInvoke = autoInvoke
    self.triggerExamples = triggerExamples.prefix(AgentSkillLimits.maxExamples).map {
      String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxRequestCharacters))
    }.filter { !$0.isEmpty }
    self.negativeExamples = negativeExamples.prefix(AgentSkillLimits.maxExamples).map {
      String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AgentSkillLimits.maxRequestCharacters))
    }.filter { !$0.isEmpty }
    self.renderSpec = renderSpec
    self.tests = Array(tests.prefix(AgentSkillLimits.maxTests))
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case title
    case version
    case summary
    case instructions
    case nativeTools = "native_tools"
    case permissions
    case mcpCatalogIds = "mcp_catalog_ids"
    case resources
    case parameters
    case steps
    case formatVersion = "format_version"
    case description
    case author
    case source
    case autoInvoke = "auto_invoke"
    case triggerExamples = "trigger_examples"
    case negativeExamples = "negative_examples"
    case renderSpec = "render_spec"
    case tests
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
    let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
    let decodedSummary = try container.decodeIfPresent(String.self, forKey: .summary)
    let decodedDescription = try container.decodeIfPresent(String.self, forKey: .description)
    let name = decodedName ?? decodedTitle ?? ""
    let summary = decodedSummary ?? decodedDescription ?? ""
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
      name: name,
      version: try container.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0",
      summary: summary,
      instructions: try container.decodeIfPresent(String.self, forKey: .instructions) ?? "",
      nativeTools: try container.decodeIfPresent(Set<String>.self, forKey: .nativeTools) ?? [],
      permissions: try container.decodeIfPresent(Set<String>.self, forKey: .permissions) ?? [],
      mcpCatalogIds: try container.decodeIfPresent(Set<String>.self, forKey: .mcpCatalogIds) ?? [],
      resources: try container.decodeIfPresent([AgentSkillResource].self, forKey: .resources) ?? [],
      parameters: try container.decodeIfPresent(AgentSkillParameterSchema.self, forKey: .parameters) ??
        AgentSkillParameterSchema.objectSchema(),
      steps: try container.decodeIfPresent([AgentSkillStep].self, forKey: .steps) ?? [],
      formatVersion: try container.decodeIfPresent(Int.self, forKey: .formatVersion) ??
        AgentSkillLimits.supportedFormatVersion,
      description: try container.decodeIfPresent(String.self, forKey: .description) ?? "",
      author: try container.decodeIfPresent(String.self, forKey: .author) ?? "SignalASI",
      source: try container.decodeIfPresent(String.self, forKey: .source) ?? "built_in",
      autoInvoke: try container.decodeIfPresent(Bool.self, forKey: .autoInvoke) ?? false,
      triggerExamples: try container.decodeIfPresent([String].self, forKey: .triggerExamples) ?? [],
      negativeExamples: try container.decodeIfPresent([String].self, forKey: .negativeExamples) ?? [],
      renderSpec: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .renderSpec) ?? [:],
      tests: try container.decodeIfPresent([AgentSkillTestCase].self, forKey: .tests) ?? []
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(name, forKey: .title)
    try container.encode(version, forKey: .version)
    try container.encode(summary, forKey: .summary)
    try container.encode(instructions, forKey: .instructions)
    try container.encode(nativeTools.sorted(), forKey: .nativeTools)
    try container.encode(permissions.sorted(), forKey: .permissions)
    try container.encode(mcpCatalogIds.sorted(), forKey: .mcpCatalogIds)
    try container.encode(resources, forKey: .resources)
    try container.encode(parameters, forKey: .parameters)
    try container.encode(steps, forKey: .steps)
    try container.encode(formatVersion, forKey: .formatVersion)
    try container.encode(description, forKey: .description)
    try container.encode(author, forKey: .author)
    try container.encode(source, forKey: .source)
    try container.encode(autoInvoke, forKey: .autoInvoke)
    try container.encode(triggerExamples, forKey: .triggerExamples)
    try container.encode(negativeExamples, forKey: .negativeExamples)
    try container.encode(renderSpec, forKey: .renderSpec)
    try container.encode(tests, forKey: .tests)
  }
}

struct AgentSkillCatalogEntry: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var summary: String
  var requiredNativeTools: Set<String>
  var requiredMcpCatalogIds: Set<String>
  var featured: Bool
  var manifest: AgentSkillManifest

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case summary
    case requiredNativeTools = "required_native_tools"
    case requiredMcpCatalogIds = "required_mcp_catalog_ids"
    case featured
    case manifest
  }
}

struct AgentSkillInstallation: Codable, Equatable, Identifiable {
  var manifest: AgentSkillManifest
  var enabled: Bool
  var installedAtMillis: Int64
  var updatedAtMillis: Int64
  var useCount: Int64
  var lastUsedAtMillis: Int64
  var autoInvokeOverride: Bool?

  var id: String { manifest.id }
  var version: String { manifest.version }
  var autoInvoke: Bool { autoInvokeOverride ?? manifest.autoInvoke }

  init(
    manifest: AgentSkillManifest,
    enabled: Bool = true,
    installedAtMillis: Int64 = 0,
    updatedAtMillis: Int64? = nil,
    useCount: Int64 = 0,
    lastUsedAtMillis: Int64 = 0,
    autoInvokeOverride: Bool? = nil
  ) {
    self.manifest = manifest
    self.enabled = enabled
    self.installedAtMillis = max(installedAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis ?? installedAtMillis, 0)
    self.useCount = max(useCount, 0)
    self.lastUsedAtMillis = max(lastUsedAtMillis, 0)
    self.autoInvokeOverride = autoInvokeOverride
  }

  enum CodingKeys: String, CodingKey {
    case manifest
    case enabled
    case installedAtMillis = "installed_at"
    case updatedAtMillis = "updated_at"
    case useCount = "use_count"
    case lastUsedAtMillis = "last_used_at"
    case autoInvokeOverride = "auto_invoke_override"
    case installedAtMillisLegacy = "installed_at_millis"
    case updatedAtMillisLegacy = "updated_at_millis"
    case lastUsedAtMillisLegacy = "last_used_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let installedAt = try container.decodeIfPresent(Int64.self, forKey: .installedAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .installedAtMillisLegacy)) ?? 0
    let updatedAt = try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillisLegacy)) ?? installedAt
    let lastUsedAt = try container.decodeIfPresent(Int64.self, forKey: .lastUsedAtMillis) ??
      (try container.decodeIfPresent(Int64.self, forKey: .lastUsedAtMillisLegacy)) ?? 0
    self.init(
      manifest: try container.decode(AgentSkillManifest.self, forKey: .manifest),
      enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
      installedAtMillis: installedAt,
      updatedAtMillis: updatedAt,
      useCount: try container.decodeIfPresent(Int64.self, forKey: .useCount) ?? 0,
      lastUsedAtMillis: lastUsedAt,
      autoInvokeOverride: try container.decodeIfPresent(Bool.self, forKey: .autoInvokeOverride)
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(manifest, forKey: .manifest)
    try container.encode(enabled, forKey: .enabled)
    try container.encode(installedAtMillis, forKey: .installedAtMillis)
    try container.encode(updatedAtMillis, forKey: .updatedAtMillis)
    try container.encode(useCount, forKey: .useCount)
    try container.encode(lastUsedAtMillis, forKey: .lastUsedAtMillis)
    try container.encodeIfPresent(autoInvokeOverride, forKey: .autoInvokeOverride)
  }
}

struct AgentMcpConnection: Codable, Equatable, Identifiable {
  var id: String
  var catalogId: String
  var displayName: String
  var endpoint: String
  var distribution: AgentMcpDistribution
  var transport: AgentMcpTransportKind
  var authProfile: AgentMcpAuthProfile
  var authState: AgentMcpAuthState
  var authStepIndex: Int
  var state: AgentMcpConnectionState
  var enabled: Bool
  var permissionMode: AgentMcpPermissionMode
  var installedAtMillis: Int64
  var updatedAtMillis: Int64
  var expiresAtMillis: Int64
  var refreshAtMillis: Int64
  var lastValidatedAtMillis: Int64
  var lastError: String
  var toolIds: [String]
  var packageVersion: String
  var packageSha256: String

  var currentAuthStep: AgentMcpAuthStepSpec? {
    authProfile.steps.indices.contains(authStepIndex) ? authProfile.steps[authStepIndex] : nil
  }

  init(
    id: String,
    catalogId: String = "",
    displayName: String,
    endpoint: String,
    distribution: AgentMcpDistribution,
    transport: AgentMcpTransportKind,
    authProfile: AgentMcpAuthProfile,
    authState: AgentMcpAuthState,
    authStepIndex: Int = 0,
    state: AgentMcpConnectionState = .installed,
    enabled: Bool = true,
    permissionMode: AgentMcpPermissionMode = .askForChanges,
    installedAtMillis: Int64 = 0,
    updatedAtMillis: Int64? = nil,
    expiresAtMillis: Int64 = 0,
    refreshAtMillis: Int64 = 0,
    lastValidatedAtMillis: Int64 = 0,
    lastError: String = "",
    toolIds: [String] = [],
    packageVersion: String = "",
    packageSha256: String = ""
  ) {
    self.id = id
    self.catalogId = catalogId
    self.displayName = displayName
    self.endpoint = endpoint
    self.distribution = distribution
    self.transport = transport
    self.authProfile = authProfile
    self.authState = authState
    self.authStepIndex = authStepIndex
    self.state = state
    self.enabled = enabled
    self.permissionMode = permissionMode
    self.installedAtMillis = installedAtMillis
    self.updatedAtMillis = updatedAtMillis ?? installedAtMillis
    self.expiresAtMillis = expiresAtMillis
    self.refreshAtMillis = refreshAtMillis
    self.lastValidatedAtMillis = lastValidatedAtMillis
    self.lastError = lastError
    self.toolIds = toolIds
    self.packageVersion = packageVersion
    self.packageSha256 = packageSha256
  }

  func effectiveAuthState(nowMillis: Int64) -> AgentMcpAuthState {
    if authProfile.method == .none {
      return .notRequired
    }
    if authState == .authenticated, expiresAtMillis > 0, nowMillis >= expiresAtMillis {
      return .reauthenticationRequired
    }
    if authState == .authenticated, refreshAtMillis > 0, nowMillis >= refreshAtMillis {
      return .refreshing
    }
    return authState
  }

  func isCallable(nowMillis: Int64) -> Bool {
    let auth = effectiveAuthState(nowMillis: nowMillis)
    return enabled &&
      !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      state != .error &&
      [.notRequired, .authenticated, .refreshing].contains(auth)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case catalogId = "catalog_id"
    case displayName = "display_name"
    case endpoint
    case distribution
    case transport
    case authProfile = "auth_profile"
    case authState = "auth_state"
    case authStepIndex = "auth_step_index"
    case state
    case enabled
    case permissionMode = "permission_mode"
    case installedAtMillis = "installed_at"
    case updatedAtMillis = "updated_at"
    case expiresAtMillis = "expires_at"
    case refreshAtMillis = "refresh_at"
    case lastValidatedAtMillis = "last_validated_at"
    case lastError = "last_error"
    case toolIds = "tool_ids"
    case packageVersion = "package_version"
    case packageSha256 = "package_sha256"
  }
}

protocol AgentMcpStore {
  func list() -> [AgentMcpConnection]
  func upsert(_ connection: AgentMcpConnection)
  func delete(id: String) -> Bool
  func readSecrets(id: String) -> [String: String]
  func writeSecrets(id: String, values: [String: String])
  func clearSecrets(id: String)
  func clear()
}

final class InMemoryAgentMcpStore: AgentMcpStore {
  private let lock = NSRecursiveLock()
  private var connections: [String: AgentMcpConnection]
  private var secrets: [String: [String: String]] = [:]

  init(_ initialConnections: [AgentMcpConnection] = []) {
    self.connections = Dictionary(uniqueKeysWithValues: initialConnections.map { ($0.id, $0) })
  }

  func list() -> [AgentMcpConnection] {
    synchronized {
      connections.values.sorted {
        let left = $0.displayName.lowercased()
        let right = $1.displayName.lowercased()
        if left == right { return $0.id < $1.id }
        return left < right
      }
    }
  }

  func upsert(_ connection: AgentMcpConnection) {
    synchronized {
      connections[connection.id] = connection
    }
  }

  func delete(id: String) -> Bool {
    synchronized {
      secrets.removeValue(forKey: id)
      return connections.removeValue(forKey: id) != nil
    }
  }

  func readSecrets(id: String) -> [String: String] {
    synchronized { secrets[id] ?? [:] }
  }

  func writeSecrets(id: String, values: [String: String]) {
    synchronized {
      secrets[id] = values
    }
  }

  func clearSecrets(id: String) {
    synchronized {
      secrets.removeValue(forKey: id)
    }
  }

  func clear() {
    synchronized {
      connections.removeAll()
      secrets.removeAll()
    }
  }

  private func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

enum AgentMcpConnectionCodec {
  static func emptyDocument() -> String {
    #"{"version":1,"connections":[]}"#
  }

  static func emptySecretsDocument() -> String {
    #"{"version":1,"values":{}}"#
  }

  static func encode(_ connections: [AgentMcpConnection]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let document = AgentMcpConnectionDocument(
      version: 1,
      connections: connections.sorted { $0.id < $1.id }
    )
    guard let data = try? encoder.encode(document) else {
      return emptyDocument()
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ document: String) -> [AgentMcpConnection] {
    guard let data = document.data(using: .utf8),
      let decoded = try? JSONDecoder().decode(AgentMcpConnectionDocument.self, from: data) else {
      return []
    }
    return decoded.connections.filter {
      !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  static func encodeSecrets(_ values: [String: String]) -> String {
    AgentMcpJSONCodec.stringify([
      "version": .int(1),
      "values": .object(values.reduce(into: AgentMcpJSONObject()) { result, item in
        result[item.key] = .string(item.value)
      })
    ])
  }

  static func decodeSecrets(_ document: String) -> [String: String] {
    guard let data = document.data(using: .utf8),
      let object = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data),
      let values = object.object("values") else {
      return [:]
    }
    return values.reduce(into: [String: String]()) { result, item in
      if let value = item.value.stringValue {
        result[item.key] = value
      }
    }
  }

  private struct AgentMcpConnectionDocument: Codable {
    var version: Int
    var connections: [AgentMcpConnection]
  }
}

final class AgentMcpRegistry {
  private let store: AgentMcpStore
  private let nowMillis: () -> Int64

  init(_ store: AgentMcpStore, nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }) {
    self.store = store
    self.nowMillis = nowMillis
  }

  func list() -> [AgentMcpConnection] {
    store.list()
  }

  func get(_ id: String) -> AgentMcpConnection? {
    list().first { $0.id == id }
  }

  func readyConnections() -> [AgentMcpConnection] {
    list().filter { $0.isCallable(nowMillis: nowMillis()) }
  }

  func addRemote(
    displayName: String,
    endpoint: String,
    authProfile: AgentMcpAuthProfile,
    catalogId: String = "",
    id: String = UUID().uuidString
  ) throws -> AgentMcpConnection {
    let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedName.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("MCP name must not be blank")
    }
    let normalizedEndpoint = try AgentMcpEndpointPolicy.normalize(endpoint)
    let now = nowMillis()
    let authState: AgentMcpAuthState = authProfile.method == .none ? .notRequired : .notConfigured
    let connection = AgentMcpConnection(
      id: id,
      catalogId: catalogId,
      displayName: normalizedName,
      endpoint: normalizedEndpoint,
      distribution: .remote,
      transport: .streamableHTTP,
      authProfile: authProfile,
      authState: authState,
      state: authState == .notRequired ? .installed : .needsSetup,
      installedAtMillis: now,
      updatedAtMillis: now
    )
    store.upsert(connection)
    return connection
  }

  func installCatalogEntry(
    _ entry: AgentMcpCatalogEntry,
    endpoint: String? = nil,
    authMethod: AgentMcpAuthMethod? = nil
  ) throws -> AgentMcpConnection {
    guard !entry.requiresPackage else {
      throw AgentRuntimeCapabilityError.invalid("This MCP catalog entry requires a local package")
    }
    let selectedMethod = authMethod ?? entry.authProfiles[0].method
    guard let profile = entry.authProfiles.first(where: { $0.method == selectedMethod }) else {
      throw AgentRuntimeCapabilityError.invalid("Unsupported authentication method")
    }
    if let existing = list().first(where: { $0.catalogId == entry.id }) {
      return existing
    }
    return try addRemote(
      displayName: entry.name,
      endpoint: endpoint ?? entry.defaultEndpoint,
      authProfile: profile,
      catalogId: entry.id
    )
  }

  func installPackage(_ manifest: AgentMcpPackageManifest, packageSha256: String) throws -> AgentMcpConnection {
    let now = nowMillis()
    let profile = manifest.authProfiles.first ?? (try AgentMcpAuthProfile(.none))
    let endpoint: String
    if manifest.transport == .localStdio {
      endpoint = manifest.endpoint
    } else {
      endpoint = try AgentMcpEndpointPolicy.normalize(manifest.endpoint)
    }
    let authState: AgentMcpAuthState = profile.method == .none ? .notRequired : .notConfigured
    let connection = AgentMcpConnection(
      id: manifest.id,
      catalogId: manifest.catalogId,
      displayName: manifest.name,
      endpoint: endpoint,
      distribution: .localPackage,
      transport: manifest.transport,
      authProfile: profile,
      authState: authState,
      state: authState == .notRequired ? .installed : .needsSetup,
      installedAtMillis: now,
      updatedAtMillis: now,
      toolIds: manifest.tools.map(\.name),
      packageVersion: manifest.version,
      packageSha256: packageSha256
    )
    store.upsert(connection)
    return connection
  }

  func markConnecting(_ id: String) throws -> AgentMcpConnection {
    try update(id) {
      var copy = $0
      copy.state = .connecting
      copy.updatedAtMillis = nowMillis()
      copy.lastError = ""
      return copy
    }
  }

  func markConnected(_ id: String, toolIds: [String]) throws -> AgentMcpConnection {
    try update(id) {
      var copy = $0
      copy.state = .connected
      copy.toolIds = Array(Set(toolIds)).sorted()
      copy.lastValidatedAtMillis = nowMillis()
      copy.updatedAtMillis = copy.lastValidatedAtMillis
      copy.lastError = ""
      return copy
    }
  }

  func markFailure(
    _ id: String,
    message: String,
    authenticationFailure: Bool = false
  ) throws -> AgentMcpConnection {
    try update(id) {
      var copy = $0
      copy.state = authenticationFailure ? .needsSetup : .error
      if authenticationFailure {
        copy.authState = .reauthenticationRequired
      }
      copy.updatedAtMillis = nowMillis()
      copy.lastError = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
      return copy
    }
  }

  func beginAuthentication(_ id: String) throws -> AgentMcpAuthStepSpec? {
    let connection = try requireConnection(id)
    guard connection.authProfile.method != .none else {
      return nil
    }
    var next = connection
    next.authState = .challengeRequired
    next.authStepIndex = 0
    next.state = .needsSetup
    next.updatedAtMillis = nowMillis()
    next.lastError = ""
    store.clearSecrets(id: id)
    store.upsert(next)
    return next.currentAuthStep
  }

  func submitAuthenticationStep(_ id: String, values: [String: String]) throws -> AgentMcpConnection {
    let current = try requireConnection(id)
    guard let step = current.currentAuthStep else {
      throw AgentRuntimeCapabilityError.invalid("No authentication step is pending")
    }
    let normalized = values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let missing = step.fields.filter { $0.required && (normalized[$0.id] ?? "").isEmpty }
    guard missing.isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("Missing authentication fields: \(missing.map(\.label).joined(separator: ", "))")
    }
    let merged = store.readSecrets(id: id).merging(normalized.filter { !$0.value.isEmpty }) { _, new in new }
    store.writeSecrets(id: id, values: merged)
    let nextIndex = current.authStepIndex + 1
    let now = nowMillis()
    let finished = nextIndex >= current.authProfile.steps.count
    let expiresAt = finished && current.authProfile.accessTokenTtlMillis > 0
      ? now + current.authProfile.accessTokenTtlMillis
      : 0
    let refreshAt = expiresAt > 0 && current.authProfile.supportsRefresh
      ? max(expiresAt - current.authProfile.refreshLeadMillis, now)
      : 0
    var next = current
    next.authState = finished ? .authenticated : .challengeRequired
    next.authStepIndex = finished ? current.authStepIndex : nextIndex
    next.state = finished ? .installed : .needsSetup
    next.expiresAtMillis = expiresAt
    next.refreshAtMillis = refreshAt
    next.updatedAtMillis = now
    next.lastError = ""
    store.upsert(next)
    return next
  }

  func markAuthenticationRefreshed(_ id: String, values: [String: String]) throws -> AgentMcpConnection {
    var current = try requireConnection(id)
    let now = nowMillis()
    store.writeSecrets(
      id: id,
      values: store.readSecrets(id: id).merging(values.filter { !$0.value.isEmpty }) { _, new in new }
    )
    current.authState = .authenticated
    current.state = .installed
    current.expiresAtMillis = current.authProfile.accessTokenTtlMillis > 0 ? now + current.authProfile.accessTokenTtlMillis : 0
    current.refreshAtMillis = current.expiresAtMillis > 0 && current.authProfile.supportsRefresh
      ? max(current.expiresAtMillis - current.authProfile.refreshLeadMillis, now)
      : 0
    current.updatedAtMillis = now
    current.lastError = ""
    store.upsert(current)
    return current
  }

  func requestHeaders(_ id: String) throws -> [String: String] {
    let connection = try requireConnection(id)
    let secrets = store.readSecrets(id: id)
    switch connection.authProfile.method {
    case .none:
      return [:]
    case .bearerToken, .oauth2, .deviceCode:
      return tokenHeader(secrets)
    case .apiKey:
      let key = secrets["api_key"] ?? ""
      let header = (secrets["header_name"] ?? "").isEmpty ? "X-API-Key" : secrets["header_name"] ?? "X-API-Key"
      return key.isEmpty ? [:] : [header: key]
    case .usernamePassword:
      let username = secrets["username"] ?? ""
      let password = secrets["password"] ?? ""
      guard !username.isEmpty, !password.isEmpty else {
        return [:]
      }
      let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
      return ["Authorization": "Basic \(encoded)"]
    case .dynamic:
      var headers = tokenHeader(secrets)
      if let cookie = secrets["session_cookie"], !cookie.isEmpty {
        headers["Cookie"] = cookie
      }
      for (key, value) in secrets where key.hasPrefix("header.") && !value.isEmpty {
        headers[String(key.dropFirst("header.".count))] = value
      }
      return headers
    }
  }

  func setEnabled(_ id: String, enabled: Bool) throws -> AgentMcpConnection {
    try update(id) {
      var copy = $0
      copy.enabled = enabled
      copy.updatedAtMillis = nowMillis()
      return copy
    }
  }

  func setPermissionMode(_ id: String, mode: AgentMcpPermissionMode) throws -> AgentMcpConnection {
    try update(id) {
      var copy = $0
      copy.permissionMode = mode
      copy.updatedAtMillis = nowMillis()
      return copy
    }
  }

  func delete(_ id: String) -> Bool {
    store.delete(id: id)
  }

  func secrets(_ id: String) -> [String: String] {
    store.readSecrets(id: id)
  }

  private func tokenHeader(_ secrets: [String: String]) -> [String: String] {
    let token = (secrets["access_token"] ?? "").isEmpty
      ? ((secrets["token"] ?? "").isEmpty ? (secrets["device_code"] ?? "") : (secrets["token"] ?? ""))
      : (secrets["access_token"] ?? "")
    return token.isEmpty ? [:] : ["Authorization": "Bearer \(token)"]
  }

  private func requireConnection(_ id: String) throws -> AgentMcpConnection {
    guard let connection = get(id) else {
      throw AgentRuntimeCapabilityError.invalid("MCP connection not found: \(id)")
    }
    return connection
  }

  private func update(_ id: String, transform: (AgentMcpConnection) throws -> AgentMcpConnection) throws -> AgentMcpConnection {
    let next = try transform(try requireConnection(id))
    store.upsert(next)
    return next
  }
}

enum AgentMcpEndpointPolicy {
  static func normalize(_ value: String) throws -> String {
    let endpoint = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard endpoint.count >= 8, endpoint.count <= 2_048,
      var components = URLComponents(string: endpoint),
      let scheme = components.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      components.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
      components.user == nil,
      components.password == nil,
      components.fragment == nil else {
      throw AgentRuntimeCapabilityError.invalid("MCP endpoint is invalid")
    }
    components.scheme = scheme
    guard let normalized = components.url?.absoluteString else {
      throw AgentRuntimeCapabilityError.invalid("MCP endpoint is invalid")
    }
    return normalized
  }
}

struct AgentCapabilityDependencyStatus: Codable, Equatable {
  var available: Bool
  var missingNativeTools: Set<String>
  var missingMcpCatalogIds: Set<String>

  init(
    available: Bool,
    missingNativeTools: Set<String> = [],
    missingMcpCatalogIds: Set<String> = []
  ) {
    self.available = available
    self.missingNativeTools = missingNativeTools
    self.missingMcpCatalogIds = missingMcpCatalogIds
  }

  enum CodingKeys: String, CodingKey {
    case available
    case missingNativeTools = "missing_native_tools"
    case missingMcpCatalogIds = "missing_mcp_catalog_ids"
  }
}

enum AgentCapabilityDependencyResolver {
  static func resolve(
    _ skill: AgentSkillCatalogEntry,
    installedMcp: [AgentMcpConnection],
    nativeToolIds: Set<String>,
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentCapabilityDependencyStatus {
    let readyMcpIds = Set(installedMcp.filter { $0.isCallable(nowMillis: nowMillis) }.map(\.catalogId))
    let missingNative = skill.requiredNativeTools.subtracting(nativeToolIds)
    let missingMcp = skill.requiredMcpCatalogIds.subtracting(readyMcpIds)
    return AgentCapabilityDependencyStatus(
      available: missingNative.isEmpty && missingMcp.isEmpty,
      missingNativeTools: missingNative,
      missingMcpCatalogIds: missingMcp
    )
  }
}

enum AgentIOSMcpNativeToolOperation: String, Codable, CaseIterable, Identifiable {
  case listConnections = "connections.list"
  case listTools = "tools.list"
  case callTool = "tool.call"

  var id: String { rawValue }
}

protocol AgentIOSMcpNativeToolProviding {
  var implementationId: String { get }
  func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability
  func invoke(
    operation: AgentIOSMcpNativeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult
}

struct AgentIOSUnavailableMcpNativeToolProvider: AgentIOSMcpNativeToolProviding {
  var implementationId: String = "signalasi.ios.mcp_host_unconfigured"

  func availability(operation: AgentIOSMcpNativeToolOperation) -> AgentNativeToolAvailability {
    AgentNativeToolAvailability(
      status: .requiresSetup,
      reason: "No authenticated MCP connection is ready"
    )
  }

  func invoke(
    operation: AgentIOSMcpNativeToolOperation,
    input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation
  ) -> AgentNativeToolExecutionResult {
    AgentNativeToolExecutionResult.failure(
      code: "mcp_provider_unavailable",
      message: "iOS MCP host provider is not connected",
      retryable: true
    )
  }
}

enum AgentMcpNativeTools {
  static let listConnections = "signalasi.mcp.connections.list"
  static let listTools = "signalasi.mcp.tools.list"
  static let callTool = "signalasi.mcp.tool.call"

  static let executorId = "signalasi.mcp.host"
  static let mcpHostPermission = "signalasi.scope.mcp_host"
  static let noAdditionalConsent = "signalasi.consent.none"
  static let toolIds: Set<String> = [listConnections, listTools, callTool]

  static func definitions(
    provider: AgentIOSMcpNativeToolProviding = AgentIOSUnavailableMcpNativeToolProvider()
  ) -> [AgentPhoneNativeToolDefinition] {
    AgentIOSMcpNativeToolOperation.allCases.map { operation in
      definition(provider: provider, operation: operation)
    }
  }

  static func operation(for toolId: String) -> AgentIOSMcpNativeToolOperation? {
    switch toolId {
    case listConnections:
      return .listConnections
    case listTools:
      return .listTools
    case callTool:
      return .callTool
    default:
      return nil
    }
  }

  static func toolId(_ operation: AgentIOSMcpNativeToolOperation) -> String {
    switch operation {
    case .listConnections:
      return listConnections
    case .listTools:
      return listTools
    case .callTool:
      return callTool
    }
  }

  static func title(_ operation: AgentIOSMcpNativeToolOperation) -> String {
    switch operation {
    case .listConnections:
      return "List MCP connections"
    case .listTools:
      return "List MCP tools"
    case .callTool:
      return "Call MCP tool"
    }
  }

  private static func definition(
    provider: AgentIOSMcpNativeToolProviding,
    operation: AgentIOSMcpNativeToolOperation
  ) -> AgentPhoneNativeToolDefinition {
    let descriptor = try! AgentNativeToolDescriptor(
      id: toolId(operation),
      version: AgentPhoneNativeToolCatalog.version,
      title: title(operation),
      description: description(operation),
      location: .application,
      inputSchema: inputSchema(operation),
      outputSchema: outputSchema(operation),
      risk: operation == .callTool ? .medium : .low,
      capabilities: ["mcp", "tool_use"],
      requiredPermissions: [
        AgentNativePermissionRequirement(
          id: mcpHostPermission,
          title: "MCP host access",
          description: "Limits calls to installed and authenticated MCP connections managed by SignalASI."
        )
      ],
      requiredConsents: [
        AgentNativeConsentRequirement(
          id: noAdditionalConsent,
          title: "No additional consent",
          description: "MCP permission decisions are enforced by the MCP connection policy and audit layer.",
          required: false
        )
      ],
      timeoutMillis: operation == .callTool ? 60_000 : 30_000,
      idempotency: .nonIdempotent,
      availability: provider.availability(operation: operation)
    )
    return AgentPhoneNativeToolDefinition(
      descriptor: descriptor,
      executorId: executorId,
      provenanceMetadata: [
        "implementation": provider.implementationId,
        "protocol": "mcp",
        "host": "ios",
        "compatibility_source": "AgentMcpNativeTools",
        "permission_enforcement": "mcp_security_policy"
      ]
    )
  }

  private static func description(_ operation: AgentIOSMcpNativeToolOperation) -> String {
    switch operation {
    case .listConnections:
      return "Lists installed MCP connections and their authentication and availability state."
    case .listTools:
      return "Discovers tools exposed by one installed and authenticated MCP connection."
    case .callTool:
      return "Calls a named tool on an installed and authenticated MCP connection."
    }
  }

  private static func inputSchema(_ operation: AgentIOSMcpNativeToolOperation) -> AgentMcpJSONObject {
    switch operation {
    case .listConnections:
      return objectSchema()
    case .listTools:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128)
      ], required: ["connection_id"])
    case .callTool:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128),
        "tool_name": stringSchema(maxLength: 192),
        "arguments": objectSchema(additionalProperties: true)
      ], required: ["connection_id", "tool_name", "arguments"])
    }
  }

  private static func outputSchema(_ operation: AgentIOSMcpNativeToolOperation) -> AgentMcpJSONObject {
    switch operation {
    case .listConnections:
      return objectSchema([
        "connections": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 500)
      ], required: ["connections"], additionalProperties: true)
    case .listTools:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128),
        "tools": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 1_000)
      ], required: ["connection_id", "tools"], additionalProperties: true)
    case .callTool:
      return objectSchema([
        "connection_id": stringSchema(maxLength: 128),
        "tool_name": stringSchema(maxLength: 192),
        "content": arraySchema(itemSchema: objectSchema(additionalProperties: true), maxItems: 1_000),
        "structured_content": objectSchema(additionalProperties: true)
      ], additionalProperties: true)
    }
  }

  private static func objectSchema(
    _ properties: [String: AgentMcpJSONObject] = [:],
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

  private static func stringSchema(maxLength: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("string"),
      "maxLength": .int(maxLength)
    ]
  }

  private static func arraySchema(itemSchema: AgentMcpJSONObject, maxItems: Int64) -> AgentMcpJSONObject {
    [
      "type": .string("array"),
      "items": .object(itemSchema),
      "maxItems": .int(maxItems)
    ]
  }
}

struct AgentIOSMcpNativeToolExecutor {
  var provider: AgentIOSMcpNativeToolProviding

  func executableDefinition(_ definition: AgentPhoneNativeToolDefinition) -> AgentNativeToolExecutableDefinition {
    AgentNativeToolExecutableDefinition(
      definition: definition,
      executor: { invocation in
        try invocation.checkpoint()
        let result = try self.execute(invocation)
        try invocation.checkpoint()
        return result
      }
    )
  }

  private func execute(_ invocation: AgentNativeToolInvocation) throws -> AgentNativeToolExecutionResult {
    guard let operation = AgentMcpNativeTools.operation(for: invocation.descriptor.id) else {
      return AgentNativeToolExecutionResult.failure(
        code: "mcp_unknown_tool",
        message: "Unknown MCP native tool."
      )
    }
    try invocation.reportProgress(
      stage: "mcp",
      message: AgentMcpNativeTools.title(operation),
      percent: 10
    )
    let execution = provider.invoke(operation: operation, input: invocation.input, invocation: invocation)
    guard execution.isSuccess else { return execution }
    var output = execution.output
    switch operation {
    case .listConnections:
      output["connections"] = output["connections"] ?? .array([])
    case .listTools:
      output["connection_id"] = output["connection_id"] ?? invocation.input["connection_id"] ?? .string("")
      output["tools"] = output["tools"] ?? .array([])
    case .callTool:
      output["connection_id"] = output["connection_id"] ?? invocation.input["connection_id"] ?? .string("")
      output["tool_name"] = output["tool_name"] ?? invocation.input["tool_name"] ?? .string("")
    }
    var metadata = execution.metadata
    metadata["protocol"] = metadata["protocol"] ?? .string("mcp")
    metadata["host"] = metadata["host"] ?? .string("ios")
    metadata["implementation"] = metadata["implementation"] ?? .string(provider.implementationId)
    return AgentNativeToolExecutionResult.success(
      output: output,
      message: execution.message.isEmpty ? "\(AgentMcpNativeTools.title(operation)) completed" : execution.message,
      metadata: metadata
    )
  }
}

enum AgentDefaultCapabilityCatalog {
  static let mcpEntries: [AgentMcpCatalogEntry] = [
    try! AgentMcpCatalogEntry(
      id: "signalasi.mcp.github",
      name: "GitHub",
      summary: "Repositories, issues, pull requests, and code workflows",
      distribution: .remote,
      defaultEndpoint: "https://api.githubcopilot.com/mcp/",
      authProfiles: [
        try! AgentMcpAuthProfile(.oauth2, supportsRefresh: true),
        try! AgentMcpAuthProfile(.bearerToken)
      ],
      toolHints: ["github.repositories", "github.issues", "github.pull_requests"],
      tags: ["development", "source-control"]
    ),
    try! AgentMcpCatalogEntry(
      id: "signalasi.mcp.notion",
      name: "Notion",
      summary: "Search, read, and update Notion workspaces",
      distribution: .remote,
      defaultEndpoint: "https://mcp.notion.com/mcp",
      authProfiles: [try! AgentMcpAuthProfile(.oauth2, supportsRefresh: true)],
      toolHints: ["notion.search", "notion.pages"],
      tags: ["knowledge", "documents"]
    ),
    try! AgentMcpCatalogEntry(
      id: "signalasi.mcp.home_assistant",
      name: "Home Assistant",
      summary: "Control trusted smart-home entities and automations",
      distribution: .remote,
      authProfiles: [
        try! AgentMcpAuthProfile(.bearerToken),
        try! AgentMcpAuthProfile(.oauth2, supportsRefresh: true)
      ],
      toolHints: ["home_assistant.entities", "home_assistant.services"],
      tags: ["smart-home", "automation"]
    ),
    try! AgentMcpCatalogEntry(
      id: "signalasi.mcp.relay_controller",
      name: "Relay Controller",
      summary: "Install a signed local package for authenticated relay control",
      distribution: .localPackage,
      authProfiles: [try! AgentMcpAuthProfile(.dynamic)],
      toolHints: ["relay.devices", "relay.switch"],
      tags: ["devices", "automation"],
      requiresPackage: true
    )
  ]

  static let skillEntries: [AgentSkillCatalogEntry] = [
    skill(
      id: "signalasi.catalog.deep-research",
      title: "Deep Research",
      summary: "Search, compare sources, and produce a cited brief",
      tools: [
        "signalasi.web.intelligence.search",
        "signalasi.web.intelligence.fetch",
        "signalasi.web.intelligence.research",
        "signalasi.web.intelligence.diff"
      ]
    ),
    skill(
      id: "signalasi.catalog.device-health",
      title: "Device Health",
      summary: "Summarize battery, storage, power, and network health",
      tools: [
        "signalasi.hardware.battery.status",
        "signalasi.hardware.storage.status",
        "signalasi.hardware.network.status"
      ]
    ),
    skill(
      id: "signalasi.catalog.github-triage",
      title: "GitHub Triage",
      summary: "Review issues and pull requests using the GitHub MCP",
      tools: [AgentMcpNativeTools.callTool],
      requiredMcp: ["signalasi.mcp.github"]
    ),
    skill(
      id: "signalasi.catalog.notion-brief",
      title: "Notion Brief",
      summary: "Turn selected workspace pages into a concise brief",
      tools: [AgentMcpNativeTools.callTool],
      requiredMcp: ["signalasi.mcp.notion"]
    ),
    skill(
      id: "signalasi.catalog.smart-home-routine",
      title: "Smart Home Routine",
      summary: "Run a verified multi-device routine through Home Assistant",
      tools: [AgentMcpNativeTools.callTool],
      requiredMcp: ["signalasi.mcp.home_assistant"]
    )
  ]

  static func mcp(_ id: String) -> AgentMcpCatalogEntry? {
    mcpEntries.first { $0.id == id }
  }

  static func skill(_ id: String) -> AgentSkillCatalogEntry? {
    skillEntries.first { $0.id == id }
  }

  static func marketplaceItems(
    nativeTools: [AgentNativeToolDescriptor],
    installedMcp: [AgentMcpConnection],
    installedAutomations: [AgentSkillInstallation],
    nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [AgentMarketplaceItem] {
    let native = nativeTools.compactMap { nativeItem($0) }
    let mcp = mcpEntries.compactMap { entry -> AgentMarketplaceItem? in
      let connection = installedMcp.first { $0.catalogId == entry.id }
      let permissions = mcpMarketplacePermissions(entry)
      let installedVersion: String
      if let connection {
        installedVersion = connection.packageVersion.isEmpty ? entry.version : connection.packageVersion
      } else {
        installedVersion = ""
      }
      return try? AgentMarketplaceItem(
        id: entry.id,
        kind: .mcp,
        name: entry.name,
        summary: entry.summary,
        version: entry.version,
        installState: connection == nil ? .available : (connection?.isCallable(nowMillis: nowMillis) == true ? .installed : .needsSetup),
        enabled: connection?.enabled ?? false,
        featured: entry.featured,
        tags: entry.tags,
        dependencies: Set(entry.toolHints),
        requiresLocalPackage: entry.requiresPackage,
        capabilities: Set(entry.toolHints),
        permissions: permissions,
        permissionDiff: connection == nil
          ? AgentMarketplacePermissionDiff(added: permissions)
          : AgentMarketplacePermissionDiff(unchanged: permissions),
        installedVersion: installedVersion,
        updateAvailable: !installedVersion.isEmpty && compareMarketplaceVersions(entry.version, installedVersion) > 0,
        revocable: connection != nil,
        revoked: connection?.enabled == false
      )
    }
    let grouped = Dictionary(grouping: installedAutomations, by: \.id)
    let automations = skillEntries.compactMap { entry -> AgentMarketplaceItem? in
      let versions = (grouped[entry.id] ?? []).sorted {
        compareMarketplaceVersions($0.version, $1.version) > 0
      }
      let installation = versions.first(where: \.enabled) ?? versions.first
      let dependency = AgentCapabilityDependencyResolver.resolve(
        entry,
        installedMcp: installedMcp,
        nativeToolIds: Set(nativeTools.map(\.id)),
        nowMillis: nowMillis
      )
      let availablePermissions = skillMarketplacePermissions(entry.manifest)
      let installedPermissions = installation.map { skillMarketplacePermissions($0.manifest) } ?? []
      let availableById = Dictionary(uniqueKeysWithValues: availablePermissions.map { ($0.id, $0) })
      let installedById = Dictionary(uniqueKeysWithValues: installedPermissions.map { ($0.id, $0) })
      return try? AgentMarketplaceItem(
        id: entry.id,
        kind: .automation,
        name: entry.name,
        summary: entry.summary,
        version: entry.manifest.version,
        installState: installation != nil ? .installed : (dependency.available ? .available : .needsSetup),
        enabled: installation?.enabled ?? false,
        featured: entry.featured,
        tags: ["automation", "workflow"],
        dependencies: entry.requiredNativeTools.union(entry.requiredMcpCatalogIds),
        capabilities: entry.requiredNativeTools.union(entry.requiredMcpCatalogIds),
        permissions: availablePermissions,
        permissionDiff: AgentMarketplacePermissionDiff(
          added: (Set(availableById.keys).subtracting(installedById.keys)).compactMap { availableById[$0] }.sorted { $0.id < $1.id },
          removed: (Set(installedById.keys).subtracting(availableById.keys)).compactMap { installedById[$0] }.sorted { $0.id < $1.id },
          unchanged: (Set(availableById.keys).intersection(installedById.keys)).compactMap { availableById[$0] }.sorted { $0.id < $1.id }
        ),
        installedVersion: installation?.version ?? "",
        updateAvailable: installation != nil && compareMarketplaceVersions(entry.manifest.version, installation?.version ?? "") > 0,
        rollbackVersions: versions
          .filter { installation != nil && compareMarketplaceVersions($0.version, installation?.version ?? "") < 0 }
          .map(\.version),
        revocable: installation != nil,
        revoked: installation?.enabled == false
      )
    }
    return (native + mcp + automations).sorted {
      if $0.kind.sortOrder != $1.kind.sortOrder {
        return $0.kind.sortOrder < $1.kind.sortOrder
      }
      if $0.featured != $1.featured {
        return $0.featured
      }
      return $0.name.lowercased() < $1.name.lowercased()
    }
  }

  private static func nativeItem(_ tool: AgentNativeToolDescriptor) -> AgentMarketplaceItem? {
    let permissions = tool.requiredPermissions.map {
      AgentMarketplacePermission($0.id, title: $0.title, description: $0.description, scope: "ios_permission", risk: tool.risk.rawValue)
    } + tool.requiredConsents.map {
      AgentMarketplacePermission($0.id, title: $0.title, description: $0.description, scope: "user_consent", risk: tool.risk.rawValue)
    }
    let state: AgentMarketplaceInstallState
    if tool.risk == .blocked {
      state = .unavailable
    } else {
      switch tool.availability.status {
      case .available:
        state = .builtIn
      case .requiresSetup:
        state = .needsSetup
      case .unavailable:
        state = .unavailable
      }
    }
    return try? AgentMarketplaceItem(
      id: tool.id,
      kind: .nativeTool,
      name: tool.title,
      summary: tool.description,
      version: tool.version,
      installState: state,
      enabled: tool.risk != .blocked && tool.availability.status == .available,
      tags: tool.capabilities,
      dependencies: Set(tool.requiredPermissions.map(\.id)).union(tool.requiredConsents.map(\.id)),
      capabilities: tool.capabilities,
      permissions: permissions,
      permissionDiff: AgentMarketplacePermissionDiff(unchanged: permissions),
      installedVersion: tool.version
    )
  }

  private static func skill(
    id: String,
    title: String,
    summary: String,
    tools: Set<String>,
    requiredMcp: Set<String> = []
  ) -> AgentSkillCatalogEntry {
    let manifest = AgentSkillManifest(
      id: id,
      name: title,
      version: "1.0.0",
      summary: summary,
      nativeTools: tools,
      permissions: tools,
      mcpCatalogIds: requiredMcp
    )
    return AgentSkillCatalogEntry(
      id: id,
      name: title,
      summary: summary,
      requiredNativeTools: tools,
      requiredMcpCatalogIds: requiredMcp,
      featured: true,
      manifest: manifest
    )
  }

  private static func mcpMarketplacePermissions(_ entry: AgentMcpCatalogEntry) -> [AgentMarketplacePermission] {
    [AgentMarketplacePermission(
      "network.\(entry.id)",
      title: "Connect to \(entry.name)",
      description: "Exchange requests with the configured MCP server.",
      scope: "network",
      risk: "low"
    )] + entry.toolHints.map { capability in
      AgentMarketplacePermission(
        capability,
        title: capability,
        description: "Allow the MCP server to expose this capability.",
        scope: "mcp_tool",
        risk: capability.contains("write") || capability.contains("control") ? "high" : "medium"
      )
    }
  }

  private static func skillMarketplacePermissions(_ manifest: AgentSkillManifest) -> [AgentMarketplacePermission] {
    Array(manifest.permissions.union(manifest.nativeTools)).sorted().map { permissionId in
      AgentMarketplacePermission(
        permissionId,
        title: permissionId,
        description: "Required by this automation workflow.",
        scope: manifest.nativeTools.contains(permissionId) ? "native_tool" : "skill",
        risk: "medium"
      )
    }
  }

  private static func compareMarketplaceVersions(_ left: String, _ right: String) -> Int {
    let leftParts = versionParts(left)
    let rightParts = versionParts(right)
    for index in 0..<max(leftParts.count, rightParts.count, 3) {
      let delta = (index < leftParts.count ? leftParts[index] : 0) - (index < rightParts.count ? rightParts[index] : 0)
      if delta != 0 {
        return delta
      }
    }
    return 0
  }

  private static func versionParts(_ value: String) -> [Int] {
    value.split(separator: ".").map { part in
      Int(part.filter(\.isNumber)) ?? 0
    }
  }
}

private extension AgentCapabilityCatalogKind {
  var sortOrder: Int {
    switch self {
    case .nativeTool: return 0
    case .mcp: return 1
    case .automation: return 2
    }
  }
}

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

struct AgentMcpAuditRecord: Codable, Equatable, Identifiable {
  var auditId: String
  var timestampMillis: Int64
  var connectionId: String
  var connectionName: String
  var toolName: String
  var transport: String
  var source: String
  var callerId: String
  var taskId: String
  var conversationId: String
  var risk: String
  var permissions: [String]
  var permissionMode: String
  var permissionDecision: String
  var parameterPreview: AgentMcpJSONObject
  var inputSha256: String
  var status: String
  var durationMillis: Int64
  var outputSha256: String
  var errorCode: String
  var errorMessage: String

  var id: String { auditId }

  init(
    auditId: String = UUID().uuidString,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
    connectionId: String,
    connectionName: String,
    toolName: String,
    transport: String,
    source: String,
    callerId: String,
    taskId: String,
    conversationId: String,
    risk: String,
    permissions: [String],
    permissionMode: String,
    permissionDecision: String,
    parameterPreview: AgentMcpJSONObject,
    inputSha256: String,
    status: String,
    durationMillis: Int64,
    outputSha256: String = "",
    errorCode: String = "",
    errorMessage: String = ""
  ) {
    self.auditId = auditId.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString
    self.timestampMillis = max(0, timestampMillis)
    self.connectionId = String(connectionId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.connectionName = String(connectionName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.toolName = String(toolName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.transport = String(transport.trimmingCharacters(in: .whitespacesAndNewlines).prefix(96))
    self.source = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
    self.callerId = String(callerId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.taskId = String(taskId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.conversationId = String(conversationId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(192))
    self.risk = String(risk.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.permissions = Array(Set(permissions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    self.permissionMode = String(permissionMode.trimmingCharacters(in: .whitespacesAndNewlines).prefix(96))
    self.permissionDecision = String(permissionDecision.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
    self.parameterPreview = AgentMcpParameterRedactor.sanitize(parameterPreview)
    self.inputSha256 = String(inputSha256.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.status = String(status.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.durationMillis = max(0, durationMillis)
    self.outputSha256 = String(outputSha256.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
    self.errorCode = String(errorCode.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
    self.errorMessage = AgentMcpParameterRedactor.sanitizeText(errorMessage)
  }

  static func toolCall(
    connection: AgentMcpConnection,
    toolName: String,
    assessment: AgentMcpToolAssessment,
    decision: AgentMcpPermissionDecision,
    context: AgentNativeToolInvocationContext,
    status: String,
    durationMillis: Int64,
    outputSha256: String = "",
    errorCode: String = "",
    errorMessage: String = "",
    auditId: String = UUID().uuidString,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> AgentMcpAuditRecord {
    AgentMcpAuditRecord(
      auditId: auditId,
      timestampMillis: timestampMillis,
      connectionId: connection.id,
      connectionName: connection.displayName,
      toolName: toolName,
      transport: connection.transport.rawValue,
      source: "ios-mcp:\(connection.id)",
      callerId: context.callerId,
      taskId: context.attributes["task_id"] ?? "",
      conversationId: context.conversationId,
      risk: assessment.risk.rawValue,
      permissions: assessment.permissions.sorted(),
      permissionMode: connection.permissionMode.rawValue,
      permissionDecision: decision.code,
      parameterPreview: assessment.parameterPreview,
      inputSha256: assessment.inputSha256,
      status: status,
      durationMillis: durationMillis,
      outputSha256: outputSha256,
      errorCode: errorCode,
      errorMessage: errorMessage
    )
  }

  enum CodingKeys: String, CodingKey {
    case auditId = "audit_id"
    case timestampMillis = "timestamp_ms"
    case connectionId = "connection_id"
    case connectionName = "connection_name"
    case toolName = "tool_name"
    case transport
    case source
    case callerId = "caller_id"
    case taskId = "task_id"
    case conversationId = "conversation_id"
    case risk
    case permissions
    case permissionMode = "permission_mode"
    case permissionDecision = "permission_decision"
    case parameterPreview = "parameter_preview"
    case inputSha256 = "input_sha256"
    case status
    case durationMillis = "duration_ms"
    case outputSha256 = "output_sha256"
    case errorCode = "error_code"
    case errorMessage = "error_message"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      auditId: try container.decodeIfPresent(String.self, forKey: .auditId) ?? UUID().uuidString,
      timestampMillis: try container.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? 0,
      connectionId: try container.decodeIfPresent(String.self, forKey: .connectionId) ?? "",
      connectionName: try container.decodeIfPresent(String.self, forKey: .connectionName) ?? "",
      toolName: try container.decodeIfPresent(String.self, forKey: .toolName) ?? "",
      transport: try container.decodeIfPresent(String.self, forKey: .transport) ?? "",
      source: try container.decodeIfPresent(String.self, forKey: .source) ?? "",
      callerId: try container.decodeIfPresent(String.self, forKey: .callerId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      risk: try container.decodeIfPresent(String.self, forKey: .risk) ?? "",
      permissions: try container.decodeIfPresent([String].self, forKey: .permissions) ?? [],
      permissionMode: try container.decodeIfPresent(String.self, forKey: .permissionMode) ?? "",
      permissionDecision: try container.decodeIfPresent(String.self, forKey: .permissionDecision) ?? "",
      parameterPreview: try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .parameterPreview) ?? [:],
      inputSha256: try container.decodeIfPresent(String.self, forKey: .inputSha256) ?? "",
      status: try container.decodeIfPresent(String.self, forKey: .status) ?? "",
      durationMillis: try container.decodeIfPresent(Int64.self, forKey: .durationMillis) ?? 0,
      outputSha256: try container.decodeIfPresent(String.self, forKey: .outputSha256) ?? "",
      errorCode: try container.decodeIfPresent(String.self, forKey: .errorCode) ?? "",
      errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
    )
  }
}

protocol AgentMcpAuditStore {
  func append(_ record: AgentMcpAuditRecord)
  func list(connectionId: String, limit: Int) -> [AgentMcpAuditRecord]
  func clear(connectionId: String) -> Int
}

final class InMemoryAgentMcpAuditStore: AgentMcpAuditStore {
  private let lock = NSRecursiveLock()
  private var records: [AgentMcpAuditRecord] = []

  func append(_ record: AgentMcpAuditRecord) {
    synchronized {
      records.append(record)
      if records.count > Self.maxRecords {
        records.removeFirst(records.count - Self.maxRecords)
      }
    }
  }

  func list(connectionId: String = "", limit: Int = 100) -> [AgentMcpAuditRecord] {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      return Array(records
        .filter { cleanConnectionId.isEmpty || $0.connectionId == cleanConnectionId }
        .suffix(min(max(limit, 1), 500))
        .reversed())
    }
  }

  func clear(connectionId: String = "") -> Int {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let before = records.count
      if cleanConnectionId.isEmpty {
        records.removeAll()
      } else {
        records.removeAll { $0.connectionId == cleanConnectionId }
      }
      return before - records.count
    }
  }

  private func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  static let maxRecords = 1_000
}

final class FileAgentMcpAuditStore: AgentMcpAuditStore {
  private let fileURL: URL
  private let fileManager: FileManager
  private let lock = NSRecursiveLock()

  init(directory: URL, fileName: String = "agent-mcp-audit.json", fileManager: FileManager = .default) {
    self.fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
    self.fileManager = fileManager
  }

  init(fileURL: URL, fileManager: FileManager = .default) {
    self.fileURL = fileURL
    self.fileManager = fileManager
  }

  func append(_ record: AgentMcpAuditRecord) {
    synchronized {
      var records = readRecords()
      records.append(record)
      writeRecords(Array(records.suffix(InMemoryAgentMcpAuditStore.maxRecords)))
    }
  }

  func list(connectionId: String = "", limit: Int = 100) -> [AgentMcpAuditRecord] {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      return Array(readRecords()
        .filter { cleanConnectionId.isEmpty || $0.connectionId == cleanConnectionId }
        .suffix(min(max(limit, 1), 500))
        .reversed())
    }
  }

  func clear(connectionId: String = "") -> Int {
    synchronized {
      let cleanConnectionId = connectionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let records = readRecords()
      let kept = cleanConnectionId.isEmpty ? [] : records.filter { $0.connectionId != cleanConnectionId }
      writeRecords(kept)
      return records.count - kept.count
    }
  }

  private func readRecords() -> [AgentMcpAuditRecord] {
    guard fileManager.fileExists(atPath: fileURL.path),
          let document = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return []
    }
    return AgentMcpAuditCodec.decode(document)
  }

  private func writeRecords(_ records: [AgentMcpAuditRecord]) {
    do {
      try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try AgentMcpAuditCodec.encode(records).write(to: fileURL, atomically: true, encoding: .utf8)
    } catch {
      return
    }
  }

  private func synchronized<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}

enum AgentMcpAuditCodec {
  static func emptyDocument() -> String {
    #"{"version":1,"records":[]}"#
  }

  static func encode(_ records: [AgentMcpAuditRecord]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let document = AgentMcpAuditDocument(version: 1, records: Array(records.suffix(InMemoryAgentMcpAuditStore.maxRecords)))
    guard let data = try? encoder.encode(document) else {
      return emptyDocument()
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ document: String) -> [AgentMcpAuditRecord] {
    guard let data = document.data(using: .utf8),
          let decoded = try? JSONDecoder().decode(AgentMcpAuditDocument.self, from: data),
          decoded.version == 1 else {
      return []
    }
    return Array(decoded.records
      .filter {
        !$0.connectionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
          !$0.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      .suffix(InMemoryAgentMcpAuditStore.maxRecords))
  }

  private struct AgentMcpAuditDocument: Codable {
    var version: Int
    var records: [AgentMcpAuditRecord]
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
