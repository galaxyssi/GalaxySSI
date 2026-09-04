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
    author: String = "GalaxySSI",
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
      .ifBlank("GalaxySSI")
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
      author: try container.decodeIfPresent(String.self, forKey: .author) ?? "GalaxySSI",
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
    let profile: AgentMcpAuthProfile
    if let firstProfile = manifest.authProfiles.first {
      profile = firstProfile
    } else {
      profile = try AgentMcpAuthProfile(.none)
    }
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

enum AgentDefaultCapabilityCatalog {
  static let mcpEntries: [AgentMcpCatalogEntry] = [
    try! AgentMcpCatalogEntry(
      id: "galaxyssi.mcp.github",
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
      id: "galaxyssi.mcp.notion",
      name: "Notion",
      summary: "Search, read, and update Notion workspaces",
      distribution: .remote,
      defaultEndpoint: "https://mcp.notion.com/mcp",
      authProfiles: [try! AgentMcpAuthProfile(.oauth2, supportsRefresh: true)],
      toolHints: ["notion.search", "notion.pages"],
      tags: ["knowledge", "documents"]
    ),
    try! AgentMcpCatalogEntry(
      id: "galaxyssi.mcp.home_assistant",
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
      id: "galaxyssi.mcp.relay_controller",
      name: "Relay Controller",
      summary: "Install a signed local package for authenticated relay control",
      distribution: .localPackage,
      authProfiles: [try! AgentMcpAuthProfile(.dynamic)],
      toolHints: ["relay.devices", "relay.switch"],
      tags: ["devices", "automation"],
      requiresPackage: true
    )
  ]

  static let skillEntries: [AgentSkillCatalogEntry] = AgentIOSBuiltInSkills.statusEntries + [
    skill(
      id: "galaxyssi.catalog.deep-research",
      title: "Deep Research",
      summary: "Search, compare sources, and produce a cited brief",
      tools: [
        "galaxyssi.web.intelligence.search",
        "galaxyssi.web.intelligence.fetch",
        "galaxyssi.web.intelligence.research",
        "galaxyssi.web.intelligence.diff"
      ]
    ),
    skill(
      id: "galaxyssi.catalog.device-health",
      title: "Device Health",
      summary: "Summarize battery, memory, storage, power, and network health",
      tools: [
        "galaxyssi.hardware.device.status",
        "galaxyssi.hardware.battery.status",
        "galaxyssi.hardware.memory.status",
        "galaxyssi.hardware.storage.status",
        "galaxyssi.hardware.network.status"
      ]
    ),
    skill(
      id: "galaxyssi.catalog.github-triage",
      title: "GitHub Triage",
      summary: "Review issues and pull requests using the GitHub MCP",
      tools: [AgentMcpNativeTools.callTool],
      requiredMcp: ["galaxyssi.mcp.github"]
    ),
    skill(
      id: "galaxyssi.catalog.notion-brief",
      title: "Notion Brief",
      summary: "Turn selected workspace pages into a concise brief",
      tools: [AgentMcpNativeTools.callTool],
      requiredMcp: ["galaxyssi.mcp.notion"]
    ),
    skill(
      id: "galaxyssi.catalog.smart-home-routine",
      title: "Smart Home Routine",
      summary: "Run a verified multi-device routine through Home Assistant",
      tools: [AgentMcpNativeTools.callTool],
      requiredMcp: ["galaxyssi.mcp.home_assistant"]
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
      AgentMarketplacePermission(id: $0.id, title: $0.title, description: $0.description, scope: "ios_permission", risk: tool.risk.rawValue)
    } + tool.requiredConsents.map {
      AgentMarketplacePermission(id: $0.id, title: $0.title, description: $0.description, scope: "user_consent", risk: tool.risk.rawValue)
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
      id: "network.\(entry.id)",
      title: "Connect to \(entry.name)",
      description: "Exchange requests with the configured MCP server.",
      scope: "network",
      risk: "low"
    )] + entry.toolHints.map { capability in
      AgentMarketplacePermission(
        id: capability,
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
        id: permissionId,
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
