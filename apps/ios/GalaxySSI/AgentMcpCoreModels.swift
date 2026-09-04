import CryptoKit
import Foundation

extension Notification.Name {
  static let galaxySSIDesktopMarketplaceDidUpdate = Notification.Name(
    "galaxyssi.desktopMarketplaceDidUpdate"
  )
  static let galaxySSIAgentRoutingDidUpdate = Notification.Name(
    "galaxyssi.agentRoutingDidUpdate"
  )
}

enum AgentMcpJSONValue: Codable, Equatable {
  case string(String)
  case int(Int64)
  case double(Double)
  case bool(Bool)
  case object([String: AgentMcpJSONValue])
  case array([AgentMcpJSONValue])
  case null

  var boolValue: Bool? {
    if case .bool(let value) = self {
      return value
    }
    return nil
  }

  var stringValue: String? {
    switch self {
    case .string(let value):
      return value
    case .int(let value):
      return String(value)
    case .double(let value):
      return String(value)
    case .bool(let value):
      return value ? "true" : "false"
    case .object, .array, .null:
      return nil
    }
  }

  var intValue: Int64? {
    switch self {
    case .int(let value):
      return value
    case .double(let value):
      return Int64(value)
    case .string(let value):
      return Int64(value)
    case .bool, .object, .array, .null:
      return nil
    }
  }

  var objectValue: AgentMcpJSONObject? {
    if case .object(let value) = self {
      return value
    }
    return nil
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: AgentMcpJSONValue].self) {
      self = .object(value)
    } else {
      self = .array((try? container.decode([AgentMcpJSONValue].self)) ?? [])
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .int(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }
}

typealias AgentMcpJSONObject = [String: AgentMcpJSONValue]

extension AgentMcpJSONValue {
  var strictStringValue: String? {
    if case .string(let value) = self {
      return value
    }
    return nil
  }

  var arrayValue: [AgentMcpJSONValue]? {
    if case .array(let value) = self {
      return value
    }
    return nil
  }

  var integerForSchema: Int? {
    switch self {
    case .int(let value):
      return Int(value)
    case .double(let value) where value.isFinite && value.rounded(.towardZero) == value:
      return Int(value)
    default:
      return nil
    }
  }

  var doubleForSchema: Double? {
    switch self {
    case .int(let value):
      return Double(value)
    case .double(let value) where value.isFinite:
      return value
    default:
      return nil
    }
  }
}

extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  var isBlank: Bool {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var nonEmpty: String? {
    let clean = trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
  }
}

extension Int {
  func clamped(to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

enum AgentMcpJSONCodec {
  static func stringify(_ value: AgentMcpJSONValue) -> String {
    switch value {
    case .null:
      return "null"
    case .bool(let value):
      return value ? "true" : "false"
    case .int(let value):
      return String(value)
    case .double(let value):
      guard value.isFinite else {
        return "null"
      }
      return String(value)
    case .string(let value):
      return quote(value)
    case .array(let values):
      return "[" + values.map(stringify).joined(separator: ",") + "]"
    case .object(let object):
      return "{" + object.keys.sorted().map { key in
        "\(quote(key)):\(stringify(object[key] ?? .null))"
      }.joined(separator: ",") + "}"
    }
  }

  static func stringify(_ object: AgentMcpJSONObject) -> String {
    stringify(.object(object))
  }

  static func sha256(_ object: AgentMcpJSONObject) -> String {
    let digest = SHA256.hash(data: Data(stringify(object).utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func quote(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 34:
        result += "\\\""
      case 92:
        result += "\\\\"
      case 8:
        result += "\\b"
      case 12:
        result += "\\f"
      case 10:
        result += "\\n"
      case 13:
        result += "\\r"
      case 9:
        result += "\\t"
      default:
        if scalar.value < 0x20 {
          result += String(format: "\\u%04x", scalar.value)
        } else {
          result.unicodeScalars.append(scalar)
        }
      }
    }
    result += "\""
    return result
  }
}

enum AgentMcpLocalRuntimeResponseCodec {
  static let bridgeResultPrefix = "__GALAXYSSI_MCP_RESULT__"

  static func decode(_ stdout: String) throws -> AgentMcpJSONObject {
    guard let line = stdout
      .components(separatedBy: .newlines)
      .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
      .last(where: { $0.hasPrefix(bridgeResultPrefix) }) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP bridge returned no structured result")
    }
    let payload = String(line.dropFirst(bridgeResultPrefix.count))
    guard let data = payload.data(using: .utf8),
          let envelope = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else {
      throw AgentRuntimeCapabilityError.invalid("Local MCP bridge returned malformed structured result")
    }
    guard envelope["ok"]?.boolValue == true else {
      throw AgentRuntimeCapabilityError.invalid(
        envelope["error"]?.stringValue?.nilIfEmpty ?? "Local MCP bridge failed"
      )
    }
    return envelope["result"]?.objectValue ?? [:]
  }
}

enum UnifiedCommandProtocolError: Error, Equatable {
  case missingCommand
}

struct UnifiedCommandResult: Codable, Equatable {
  var commandId: String
  var status: String
  var runId: String
  var sourceMessageId: String
  var data: AgentMcpJSONObject
  var display: AgentMcpJSONObject
  var errorCode: String
  var message: String

  init(
    commandId: String,
    status: String,
    runId: String = "",
    sourceMessageId: String = "",
    data: AgentMcpJSONObject = [:],
    display: AgentMcpJSONObject = [:],
    errorCode: String = "",
    message: String = ""
  ) {
    self.commandId = commandId
    self.status = status
    self.runId = runId
    self.sourceMessageId = sourceMessageId
    self.data = data
    self.display = display
    self.errorCode = errorCode
    self.message = message
  }

  enum CodingKeys: String, CodingKey {
    case commandId = "command_id"
    case status
    case runId = "run_id"
    case sourceMessageId = "source_message_id"
    case data
    case display
    case errorCode = "error_code"
    case message
  }
}

enum UnifiedCommandProtocol {
  static let requestType = "unified_command"
  static let resultType = "unified_command_result"

  static func requestPayload(
    commandId: String,
    args: AgentMcpJSONObject = [:],
    raw: String = "",
    slash: String = "",
    contactId: String = "system",
    requestedBy: String = "paired_phone",
    approve: Bool = false,
    messageId: String = UUID().uuidString
  ) throws -> AgentMcpJSONObject {
    guard !isBlank(commandId) || !isBlank(raw) || !isBlank(slash) else {
      throw UnifiedCommandProtocolError.missingCommand
    }
    return [
      "type": .string(requestType),
      "message_id": .string(messageId),
      "source_message_id": .string(messageId),
      "contact_id": .string(contactId),
      "command_id": .string(commandId),
      "args": .object(args),
      "raw": .string(raw),
      "slash": .string(slash),
      "requested_by": .string(requestedBy),
      "approve": .bool(approve)
    ]
  }

  static func decodeResult(_ payload: AgentMcpJSONObject) -> UnifiedCommandResult? {
    guard payload.string("type") == resultType else {
      return nil
    }
    let result = payload.object("result") ?? [:]
    return UnifiedCommandResult(
      commandId: ifBlank(payload.string("command_id"), fallback: result.string("command_id")),
      status: ifBlank(payload.string("command_status"), fallback: result.string("status")),
      runId: result.string("run_id"),
      sourceMessageId: payload.string("source_message_id"),
      data: result.object("data") ?? [:],
      display: result.object("display") ?? [:],
      errorCode: result.string("error_code"),
      message: result.string("message")
    )
  }

  private static func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static func ifBlank(_ value: String, fallback: String) -> String {
    isBlank(value) ? fallback : value
  }
}

extension Dictionary where Key == String, Value == AgentMcpJSONValue {
  func string(_ key: String) -> String {
    self[key]?.stringValue ?? ""
  }

  func clippedString(_ key: String, limit: Int) -> String {
    String(string(key).prefix(limit))
  }

  func int64(_ key: String) -> Int64 {
    switch self[key] {
    case .string(let value):
      return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    case .int(let value):
      return Int64(value)
    case .double(let value):
      guard value.isFinite else { return 0 }
      return Int64(value)
    default:
      return 0
    }
  }

  func bool(_ key: String) -> Bool {
    switch self[key] {
    case .bool(let value):
      return value
    case .string(let value):
      return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    case .int(let value):
      return value != 0
    default:
      return false
    }
  }

  func object(_ key: String) -> AgentMcpJSONObject? {
    self[key]?.objectValue
  }
}

enum AgentMcpPermissionMode: String, Codable, CaseIterable, Identifiable {
  case readOnly = "read_only"
  case askForChanges = "ask_for_changes"
  case trusted = "trusted"
  case disabled = "disabled"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentMcpPermissionMode {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .askForChanges
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

enum AgentMcpToolRisk: String, Codable, CaseIterable, Identifiable {
  case low = "low"
  case medium = "medium"
  case high = "high"

  var id: String { rawValue }
}

enum AgentMcpTransportKind: String, Codable, CaseIterable, Identifiable {
  case streamableHTTP = "streamable_http"
  case declarativeHTTP = "declarative_http"
  case localStdio = "local_stdio"

  var id: String { rawValue }
}

enum AgentCapabilityCatalogKind: String, Codable, CaseIterable, Identifiable {
  case nativeTool = "native_tool"
  case mcp
  case automation

  var id: String { rawValue }
}

enum AgentMarketplaceInstallState: String, Codable, CaseIterable, Identifiable {
  case builtIn = "built_in"
  case available
  case installed
  case needsSetup = "needs_setup"
  case unavailable

  var id: String { rawValue }
}

struct AgentMarketplacePermission: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var description: String
  var scope: String
  var risk: String

  init(
    id: String,
    title: String? = nil,
    description: String = "",
    scope: String = "item",
    risk: String = "medium"
  ) {
    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    self.id = cleanId
    self.title = (title ?? cleanId).trimmingCharacters(in: .whitespacesAndNewlines)
    self.description = description
    self.scope = scope
    self.risk = risk
  }
}

struct AgentMarketplacePermissionDiff: Codable, Equatable {
  var added: [AgentMarketplacePermission]
  var removed: [AgentMarketplacePermission]
  var unchanged: [AgentMarketplacePermission]

  var requiresApproval: Bool {
    !added.isEmpty
  }

  init(
    added: [AgentMarketplacePermission] = [],
    removed: [AgentMarketplacePermission] = [],
    unchanged: [AgentMarketplacePermission] = []
  ) {
    self.added = added
    self.removed = removed
    self.unchanged = unchanged
  }
}

struct AgentMarketplaceItem: Codable, Equatable, Identifiable {
  var id: String
  var kind: AgentCapabilityCatalogKind
  var name: String
  var summary: String
  var version: String
  var publisher: String
  var installState: AgentMarketplaceInstallState
  var enabled: Bool
  var featured: Bool
  var trusted: Bool
  var tags: Set<String>
  var dependencies: Set<String>
  var requiresLocalPackage: Bool
  var capabilities: Set<String>
  var permissions: [AgentMarketplacePermission]
  var permissionDiff: AgentMarketplacePermissionDiff
  var installedVersion: String
  var availableVersion: String
  var updateAvailable: Bool
  var rollbackVersions: [String]
  var revocable: Bool
  var revoked: Bool

  init(
    id: String,
    kind: AgentCapabilityCatalogKind,
    name: String,
    summary: String,
    version: String,
    publisher: String = "GalaxySSI",
    installState: AgentMarketplaceInstallState,
    enabled: Bool = true,
    featured: Bool = true,
    trusted: Bool = true,
    tags: Set<String> = [],
    dependencies: Set<String> = [],
    requiresLocalPackage: Bool = false,
    capabilities: Set<String> = [],
    permissions: [AgentMarketplacePermission] = [],
    permissionDiff: AgentMarketplacePermissionDiff = AgentMarketplacePermissionDiff(),
    installedVersion: String = "",
    availableVersion: String? = nil,
    updateAvailable: Bool = false,
    rollbackVersions: [String] = [],
    revocable: Bool = false,
    revoked: Bool = false
  ) throws {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw AgentRuntimeCapabilityError.invalid("Marketplace items require stable identity, name, summary, and version")
    }
    self.id = id
    self.kind = kind
    self.name = name
    self.summary = summary
    self.version = version
    self.publisher = publisher
    self.installState = installState
    self.enabled = enabled
    self.featured = featured
    self.trusted = trusted
    self.tags = tags
    self.dependencies = dependencies
    self.requiresLocalPackage = requiresLocalPackage
    self.capabilities = capabilities
    self.permissions = permissions
    self.permissionDiff = permissionDiff
    self.installedVersion = installedVersion
    self.availableVersion = availableVersion ?? version
    self.updateAvailable = updateAvailable
    self.rollbackVersions = rollbackVersions
    self.revocable = revocable
    self.revoked = revoked
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case name
    case summary
    case version
    case publisher
    case installState = "install_state"
    case enabled
    case featured
    case trusted
    case tags
    case dependencies
    case requiresLocalPackage = "requires_local_package"
    case capabilities
    case permissions
    case permissionDiff = "permission_diff"
    case installedVersion = "installed_version"
    case availableVersion = "available_version"
    case updateAvailable = "update_available"
    case rollbackVersions = "rollback_versions"
    case revocable
    case revoked
  }
}

struct AgentDesktopMarketplaceItem: Codable, Equatable, Identifiable {
  var desktopId: String
  var desktopName: String
  var id: String
  var kind: AgentCapabilityCatalogKind
  var name: String
  var summary: String
  var version: String
  var installState: AgentMarketplaceInstallState
  var enabled: Bool
  var trusted: Bool
  var capabilities: Set<String>
  var permissions: [AgentMarketplacePermission]
  var permissionDiff: AgentMarketplacePermissionDiff
  var installedVersion: String
  var availableVersion: String
  var updateAvailable: Bool
  var rollbackVersions: [String]
  var revocable: Bool
  var revoked: Bool
  var updatedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case desktopId = "desktop_id"
    case desktopName = "desktop_name"
    case id
    case kind
    case name
    case summary
    case version
    case installState = "install_state"
    case enabled
    case trusted
    case capabilities
    case permissions
    case permissionDiff = "permission_diff"
    case installedVersion = "installed_version"
    case availableVersion = "available_version"
    case updateAvailable = "update_available"
    case rollbackVersions = "rollback_versions"
    case revocable
    case revoked
    case updatedAtMillis = "updated_at"
  }
}

struct AgentDesktopMarketplaceManifest: Codable, Equatable {
  var desktopId: String
  var desktopName: String
  var updatedAtMillis: Int64
  var items: [AgentDesktopMarketplaceItem]

  enum CodingKeys: String, CodingKey {
    case desktopId = "desktop_id"
    case desktopName = "desktop_name"
    case updatedAtMillis = "updated_at"
    case items
  }
}

final class AgentDesktopMarketplaceStore {
  static let shared = AgentDesktopMarketplaceStore()

  private static let maxItemsPerDesktop = 512
  private static let maxText = 500
  private static let persistenceKey = "galaxyssi.desktopMarketplace.manifests.v1"
  private var manifests: [String: AgentDesktopMarketplaceManifest] = [:]
  private let lock = NSLock()
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    guard let data = userDefaults.data(forKey: Self.persistenceKey),
          let stored = try? JSONDecoder().decode(
            [String: AgentDesktopMarketplaceManifest].self,
            from: data
          ) else {
      return
    }
    manifests = stored
  }

  @discardableResult
  func update(payload: AgentMcpJSONObject, nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)) -> Bool {
    guard let manifest = Self.manifest(from: payload, nowMillis: nowMillis) else {
      return false
    }
    lock.lock()
    manifests[manifest.desktopId] = manifest
    let snapshot = manifests
    lock.unlock()
    persist(snapshot)
    NotificationCenter.default.post(name: .galaxySSIDesktopMarketplaceDidUpdate, object: manifest.desktopId)
    return true
  }

  func remove(desktopId: String) {
    lock.lock()
    manifests.removeValue(forKey: desktopId)
    let snapshot = manifests
    lock.unlock()
    persist(snapshot)
    NotificationCenter.default.post(name: .galaxySSIDesktopMarketplaceDidUpdate, object: desktopId)
  }

  func list(
    selectedKind: AgentCapabilityCatalogKind? = nil,
    pairedDesktopIds: Set<String>,
    desktopSessionDesktopIds: Set<String>
  ) -> [AgentDesktopMarketplaceItem] {
    let eligible = pairedDesktopIds.intersection(desktopSessionDesktopIds)
    lock.lock()
    let currentManifests = manifests
    lock.unlock()
    return currentManifests.values.flatMap { manifest -> [AgentDesktopMarketplaceItem] in
      guard eligible.contains(manifest.desktopId) else {
        return []
      }
      return manifest.items.compactMap { source -> AgentDesktopMarketplaceItem? in
        guard selectedKind == nil || source.kind == selectedKind else {
          return nil
        }
        var item = source
        item.desktopName = manifest.desktopName.nonEmpty ?? manifest.desktopId
        item.version = item.version.nonEmpty ?? "1.0.0"
        item.availableVersion = item.availableVersion.nonEmpty ?? item.version
        item.updatedAtMillis = manifest.updatedAtMillis
        return item
      }
    }.sorted {
      let desktopComparison = $0.desktopName.lowercased().localizedStandardCompare($1.desktopName.lowercased())
      if desktopComparison != .orderedSame {
        return desktopComparison == .orderedAscending
      }
      return $0.name.lowercased().localizedStandardCompare($1.name.lowercased()) == .orderedAscending
    }
  }

  private static func manifest(
    from payload: AgentMcpJSONObject,
    nowMillis: Int64
  ) -> AgentDesktopMarketplaceManifest? {
    guard payload.string("type") == "capability_manifest",
          let server = payload.object("server"),
          let marketplace = payload.object("tool_marketplace"),
          let values = marketplace["items"]?.arrayValue else {
      return nil
    }
    let desktopId = server.string("id").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !desktopId.isBlank else { return nil }
    let desktopName = String(server.string("name").prefix(160))
    let items = values
      .prefix(maxItemsPerDesktop)
      .compactMap { item(from: $0.objectValue, desktopId: desktopId, desktopName: desktopName, updatedAtMillis: nowMillis) }
    return AgentDesktopMarketplaceManifest(
      desktopId: desktopId,
      desktopName: desktopName,
      updatedAtMillis: nowMillis,
      items: items
    )
  }

  private func persist(_ snapshot: [String: AgentDesktopMarketplaceManifest]) {
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    userDefaults.set(data, forKey: Self.persistenceKey)
  }

  private static func item(
    from source: AgentMcpJSONObject?,
    desktopId: String,
    desktopName: String,
    updatedAtMillis: Int64
  ) -> AgentDesktopMarketplaceItem? {
    guard let source,
          let kind = kind(source.string("kind")),
          let installState = state(source.string("install_state")) else {
      return nil
    }
    let permissionDiff = source.object("permission_diff") ?? [:]
    return AgentDesktopMarketplaceItem(
      desktopId: desktopId,
      desktopName: desktopName,
      id: source.clippedString("id", limit: maxText),
      kind: kind,
      name: source.clippedString("name", limit: maxText),
      summary: source.clippedString("summary", limit: maxText),
      version: source.clippedString("version", limit: 80),
      installState: installState,
      enabled: source.bool("enabled"),
      trusted: source["trusted"] == nil ? true : source.bool("trusted"),
      capabilities: Set(boundedStrings(source["capabilities"], limit: 96)),
      permissions: boundedPermissions(source["permissions"]),
      permissionDiff: AgentMarketplacePermissionDiff(
        added: boundedPermissions(permissionDiff["added"]),
        removed: boundedPermissions(permissionDiff["removed"]),
        unchanged: boundedPermissions(permissionDiff["unchanged"])
      ),
      installedVersion: source.clippedString("installed_version", limit: 80),
      availableVersion: source.clippedString("available_version", limit: 80),
      updateAvailable: source.bool("update_available"),
      rollbackVersions: boundedStrings(source["rollback_versions"], limit: 8),
      revocable: source.bool("revocable"),
      revoked: source.bool("revoked"),
      updatedAtMillis: updatedAtMillis
    )
  }

  private static func kind(_ value: String) -> AgentCapabilityCatalogKind? {
    AgentCapabilityCatalogKind.allCases.first { $0.rawValue == value }
  }

  private static func state(_ value: String) -> AgentMarketplaceInstallState? {
    AgentMarketplaceInstallState.allCases.first { $0.rawValue == value }
  }

  private static func boundedStrings(_ value: AgentMcpJSONValue?, limit: Int) -> [String] {
    (value?.arrayValue ?? [])
      .prefix(limit)
      .compactMap { item -> String? in
        let normalized = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isBlank else { return nil }
        return String(normalized.prefix(160))
      }
  }

  private static func boundedPermissions(_ value: AgentMcpJSONValue?) -> [AgentMarketplacePermission] {
    (value?.arrayValue ?? [])
      .prefix(96)
      .compactMap { permission(from: $0.objectValue) }
  }

  private static func permission(from source: AgentMcpJSONObject?) -> AgentMarketplacePermission? {
    guard let source else { return nil }
    let id = source.string("id").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isBlank else { return nil }
    let clippedId = String(id.prefix(160))
    let title = source.clippedString("title", limit: maxText).nonEmpty ?? clippedId
    return AgentMarketplacePermission(
      id: clippedId,
      title: title,
      description: source.clippedString("description", limit: maxText),
      scope: source.clippedString("scope", limit: 80).nonEmpty ?? "item",
      risk: source.clippedString("risk", limit: 40).nonEmpty ?? "medium"
    )
  }
}
