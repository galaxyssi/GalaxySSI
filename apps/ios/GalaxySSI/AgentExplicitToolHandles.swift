import Foundation

let agentToolHandleContract = "galaxyssi.tool-handle/1.0"

enum AgentExplicitToolHandleContract {
  static let version = agentToolHandleContract
}

struct AgentExplicitToolHandleException: Error, Equatable {
  var code: String
  var message: String
  var retryable: Bool

  init(code: String, message: String, retryable: Bool = false) {
    self.code = code
    self.message = message
    self.retryable = retryable
  }
}

typealias AgentExplicitToolHandleError = AgentExplicitToolHandleException

struct AgentExplicitToolHandleScope: Codable, Equatable {
  var ownerId: String
  var contextId: String

  init(ownerId: String, contextId: String = "") {
    precondition(!ownerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    self.ownerId = ownerId
    self.contextId = contextId
  }

  static func from(_ context: AgentNativeToolInvocationContext) -> AgentExplicitToolHandleScope {
    let contextId = context.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    return AgentExplicitToolHandleScope(
      ownerId: context.callerId,
      contextId: contextId.isEmpty ? context.sessionId : context.conversationId
    )
  }

  enum CodingKeys: String, CodingKey {
    case ownerId = "owner_id"
    case contextId = "context_id"
  }
}

struct AgentExplicitToolHandleResource: Codable, Equatable {
  var resourceId: String
  var payload: AgentRunControlPayload

  init(
    resourceId: String,
    payload: AgentRunControlPayload = [:]
  ) {
    self.resourceId = resourceId
    self.payload = payload
  }

  enum CodingKeys: String, CodingKey {
    case resourceId = "resource_id"
    case payload
  }
}

struct AgentExplicitToolHandleResolvedResource {
  var rawValue: Any
  private var explicitResource: AgentExplicitToolHandleResource?

  var payload: AgentRunControlPayload {
    explicitResource?.payload ?? [:]
  }

  init(_ rawValue: Any) {
    self.rawValue = rawValue
    self.explicitResource = rawValue as? AgentExplicitToolHandleResource
  }
}

struct AgentExplicitToolHandleResolution {
  var handleId: String
  var kind: String
  var capabilities: Set<String>
  var resourceId: String
  var resource: AgentExplicitToolHandleResolvedResource
  var expiresAtEpochMillis: Int64
  var useCount: Int64
}

struct AgentExplicitToolHandlePublicRecord: Codable, Equatable {
  var contract: String
  var handleId: String
  var kind: String
  var capabilities: [String]
  var ownerId: String
  var contextId: String
  var metadata: AgentRunControlPayload
  var createdAtEpochMillis: Int64
  var lastUsedAtEpochMillis: Int64
  var expiresAtEpochMillis: Int64
  var useCount: Int64

  enum CodingKeys: String, CodingKey {
    case contract
    case handleId = "handle_id"
    case kind
    case capabilities
    case ownerId = "owner_id"
    case contextId = "context_id"
    case metadata
    case createdAtEpochMillis = "created_at_epoch_ms"
    case lastUsedAtEpochMillis = "last_used_at_epoch_ms"
    case expiresAtEpochMillis = "expires_at_epoch_ms"
    case useCount = "use_count"
  }
}

struct AgentExplicitToolHandleStatus: Codable, Equatable {
  var contract: String
  var activeCount: Int
  var byKind: [String: Int]

  enum CodingKeys: String, CodingKey {
    case contract
    case activeCount = "active_count"
    case byKind = "by_kind"
  }
}

final class AgentExplicitToolHandleRegistry {
  init(
    clock: @escaping () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1_000).rounded()) },
    maxHandles: Int = 512
  ) {
    self.clock = clock
    self.maxHandles = maxHandles
  }

  convenience init(
    nowMillis: @escaping () -> Int64,
    maxHandles: Int = 512
  ) {
    self.init(clock: nowMillis, maxHandles: maxHandles)
  }

  func create(
    kind: String,
    resourceId: String,
    scope: AgentExplicitToolHandleScope,
    capabilities: Set<String>,
    resource: Any,
    ttlMillis: Int64 = AgentExplicitToolHandleRegistry.defaultTtlMillis,
    idleTimeoutMillis: Int64 = AgentExplicitToolHandleRegistry.defaultIdleTimeoutMillis,
    metadata: AgentMcpJSONObject = [:]
  ) throws -> AgentMcpJSONObject {
    let entry = try createEntry(
      kind: kind,
      resourceId: resourceId,
      scope: scope,
      capabilities: capabilities,
      resource: AgentExplicitToolHandleResolvedResource(resource),
      ttlMillis: ttlMillis,
      idleTimeoutMillis: idleTimeoutMillis,
      metadata: metadata
    )
    return publicEntry(entry)
  }

  func create(
    kind: String,
    resourceId: String,
    scope: AgentExplicitToolHandleScope,
    capabilities: Set<String>,
    resource: AgentExplicitToolHandleResource? = nil,
    ttlMillis: Int64 = AgentExplicitToolHandleRegistry.defaultTTLMillis,
    idleTimeoutMillis: Int64 = AgentExplicitToolHandleRegistry.defaultIdleTimeoutMillis,
    metadata: AgentRunControlPayload = [:]
  ) throws -> AgentExplicitToolHandlePublicRecord {
    let resolvedResource = resource ?? AgentExplicitToolHandleResource(resourceId: resourceId)
    let entry = try createEntry(
      kind: kind,
      resourceId: resourceId,
      scope: scope,
      capabilities: capabilities,
      resource: AgentExplicitToolHandleResolvedResource(resolvedResource),
      ttlMillis: ttlMillis,
      idleTimeoutMillis: idleTimeoutMillis,
      metadata: mcpMetadata(from: metadata)
    )
    return publicRecord(entry)
  }

  private func createEntry(
    kind: String,
    resourceId: String,
    scope: AgentExplicitToolHandleScope,
    capabilities: Set<String>,
    resource: AgentExplicitToolHandleResolvedResource,
    ttlMillis: Int64,
    idleTimeoutMillis: Int64,
    metadata: AgentMcpJSONObject
  ) throws -> Entry {
    let normalizedKind = try checked(kind, field: "kind", maxLength: 80).lowercased()
    let normalizedResourceId = try checked(resourceId, field: "resource_id", maxLength: 512)
    guard normalizedKind.range(of: "^[a-z0-9][a-z0-9._-]{0,79}$", options: .regularExpression) != nil else {
      throw failure("tool_handle_kind_invalid", "Tool handle kind is invalid")
    }
    guard !normalizedResourceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw failure("tool_handle_resource_required", "Tool handle resource is required")
    }
    let normalizedOwner = try checked(scope.ownerId, field: "owner_id", maxLength: 240)
    let normalizedContext = try checked(scope.contextId, field: "context_id", maxLength: 240)
    let normalizedCapabilities = Set(try capabilities.map {
      try checked($0, field: "capability", maxLength: 160)
    }.filter { !$0.isEmpty })
    guard !normalizedCapabilities.isEmpty else {
      throw failure("tool_handle_capability_required", "Tool handle requires at least one capability")
    }
    let now = clock()
    let ttl = clamp(ttlMillis, lower: 1, upper: Self.maxTtlMillis)
    let idle = clamp(idleTimeoutMillis, lower: 0, upper: ttl)
    let entry: Entry
    lock.lock()
    defer { lock.unlock() }
    pruneLocked(now)
    while entries.count >= Swift.max(maxHandles, 1),
      let oldest = entries.values.min(by: { $0.lastUsedAtEpochMillis < $1.lastUsedAtEpochMillis }) {
      entries.removeValue(forKey: oldest.handleId)
    }
    let handleId = newHandleId(kind: normalizedKind)
    entry = try Entry(
      handleId: handleId,
      kind: normalizedKind,
      resourceId: normalizedResourceId,
      ownerId: normalizedOwner,
      contextId: normalizedContext,
      capabilities: normalizedCapabilities,
      resource: resource,
      metadata: publicMetadata(metadata),
      createdAtEpochMillis: now,
      lastUsedAtEpochMillis: now,
      expiresAtEpochMillis: now + ttl,
      idleTimeoutMillis: idle
    )
    entries[handleId] = entry
    return entry
  }

  func resolve(
    handleId: String,
    kind: String,
    scope: AgentExplicitToolHandleScope,
    requiredCapability: String
  ) throws -> AgentExplicitToolHandleResolution {
    let normalizedId = try checked(handleId, field: "handle_id", maxLength: 240)
    let normalizedKind = try checked(kind, field: "kind", maxLength: 80).lowercased()
    let normalizedOwner = try checked(scope.ownerId, field: "owner_id", maxLength: 240)
    let normalizedContext = try checked(scope.contextId, field: "context_id", maxLength: 240)
    let capability = try checked(requiredCapability, field: "required_capability", maxLength: 160)
    let now = clock()
    lock.lock()
    defer { lock.unlock() }
    guard let entry = entries[normalizedId] else {
      throw failure("tool_handle_not_found", "Tool handle is missing, expired, or was released", retryable: true)
    }
    if expired(entry, now: now) {
      entries.removeValue(forKey: normalizedId)
      throw failure("tool_handle_expired", "Tool handle expired; create a new handle and retry", retryable: true)
    }
    guard entry.kind == normalizedKind else {
      throw failure("tool_handle_kind_mismatch", "Tool handle belongs to a different resource type")
    }
    guard entry.ownerId == normalizedOwner else {
      throw failure("tool_handle_owner_mismatch", "Tool handle belongs to a different caller")
    }
    if !entry.contextId.isEmpty && entry.contextId != normalizedContext {
      throw failure("tool_handle_context_mismatch", "Tool handle belongs to a different conversation context")
    }
    guard entry.capabilities.contains(capability) else {
      throw failure("tool_handle_capability_denied", "Tool handle does not grant the requested capability")
    }
    entry.lastUsedAtEpochMillis = now
    entry.useCount += 1
    return AgentExplicitToolHandleResolution(
      handleId: entry.handleId,
      kind: entry.kind,
      capabilities: entry.capabilities,
      resourceId: entry.resourceId,
      resource: entry.resource,
      expiresAtEpochMillis: entry.expiresAtEpochMillis,
      useCount: entry.useCount
    )
  }

  func release(handleId: String, scope: AgentExplicitToolHandleScope) throws -> Bool {
    let normalizedId = try checked(handleId, field: "handle_id", maxLength: 240)
    let normalizedOwner = try checked(scope.ownerId, field: "owner_id", maxLength: 240)
    let normalizedContext = try checked(scope.contextId, field: "context_id", maxLength: 240)
    lock.lock()
    defer { lock.unlock() }
    guard let entry = entries[normalizedId] else {
      return false
    }
    guard entry.ownerId == normalizedOwner else {
      throw failure("tool_handle_owner_mismatch", "Tool handle belongs to a different caller")
    }
    if !entry.contextId.isEmpty && entry.contextId != normalizedContext {
      throw failure("tool_handle_context_mismatch", "Tool handle belongs to a different conversation context")
    }
    entries.removeValue(forKey: normalizedId)
    return true
  }

  func revokeResource(kind: String, resourceId: String) throws -> Int {
    let normalizedKind = try checked(kind, field: "kind", maxLength: 80).lowercased()
    let normalizedResourceId = try checked(resourceId, field: "resource_id", maxLength: 512)
    lock.lock()
    defer { lock.unlock() }
    let targets = entries.values
      .filter { $0.kind == normalizedKind && $0.resourceId == normalizedResourceId }
      .map(\.handleId)
    for target in targets {
      entries.removeValue(forKey: target)
    }
    return targets.count
  }

  func status() -> AgentExplicitToolHandleStatus {
    lock.lock()
    defer { lock.unlock() }
    pruneLocked(clock())
    var byKind: [String: Int] = [:]
    for entry in entries.values {
      byKind[entry.kind, default: 0] += 1
    }
    return AgentExplicitToolHandleStatus(
      contract: AgentExplicitToolHandleContract.version,
      activeCount: entries.count,
      byKind: byKind
    )
  }

  func statusJSONObject() -> AgentMcpJSONObject {
    let status = status()
    return [
      "contract": .string(status.contract),
      "active_count": .int(Int64(status.activeCount)),
      "by_kind": .object(status.byKind.mapValues { .int(Int64($0)) })
    ]
  }

  static let shared = AgentExplicitToolHandleRegistry()
  static let defaultTtlMillis: Int64 = 30 * 60 * 1_000
  static let defaultTTLMillis = defaultTtlMillis
  static let defaultIdleTimeoutMillis: Int64 = 10 * 60 * 1_000
  static let maxTtlMillis: Int64 = 24 * 60 * 60 * 1_000
  static let maxTTLMillis = maxTtlMillis

  private final class Entry {
    var handleId: String
    var kind: String
    var resourceId: String
    var ownerId: String
    var contextId: String
    var capabilities: Set<String>
    var resource: AgentExplicitToolHandleResolvedResource
    var metadata: AgentMcpJSONObject
    var createdAtEpochMillis: Int64
    var lastUsedAtEpochMillis: Int64
    var expiresAtEpochMillis: Int64
    var idleTimeoutMillis: Int64
    var useCount: Int64

    init(
      handleId: String,
      kind: String,
      resourceId: String,
      ownerId: String,
      contextId: String,
      capabilities: Set<String>,
      resource: AgentExplicitToolHandleResolvedResource,
      metadata: AgentMcpJSONObject,
      createdAtEpochMillis: Int64,
      lastUsedAtEpochMillis: Int64,
      expiresAtEpochMillis: Int64,
      idleTimeoutMillis: Int64,
      useCount: Int64 = 0
    ) {
      self.handleId = handleId
      self.kind = kind
      self.resourceId = resourceId
      self.ownerId = ownerId
      self.contextId = contextId
      self.capabilities = capabilities
      self.resource = resource
      self.metadata = metadata
      self.createdAtEpochMillis = createdAtEpochMillis
      self.lastUsedAtEpochMillis = lastUsedAtEpochMillis
      self.expiresAtEpochMillis = expiresAtEpochMillis
      self.idleTimeoutMillis = idleTimeoutMillis
      self.useCount = useCount
    }
  }

  private let lock = NSLock()
  private let clock: () -> Int64
  private let maxHandles: Int
  private var entries: [String: Entry] = [:]

  private func pruneLocked(_ now: Int64) {
    let expiredIds = entries.values.filter { expired($0, now: now) }.map(\.handleId)
    for handleId in expiredIds {
      entries.removeValue(forKey: handleId)
    }
  }

  private func expired(_ entry: Entry, now: Int64) -> Bool {
    now >= entry.expiresAtEpochMillis ||
      entry.idleTimeoutMillis > 0 && now >= entry.lastUsedAtEpochMillis + entry.idleTimeoutMillis
  }

  private func publicEntry(_ entry: Entry) -> AgentMcpJSONObject {
    [
      "contract": .string(agentToolHandleContract),
      "handle_id": .string(entry.handleId),
      "kind": .string(entry.kind),
      "capabilities": .array(entry.capabilities.sorted().map { .string($0) }),
      "owner_id": .string(entry.ownerId),
      "context_id": .string(entry.contextId),
      "metadata": .object(entry.metadata),
      "created_at_epoch_ms": .int(entry.createdAtEpochMillis),
      "last_used_at_epoch_ms": .int(entry.lastUsedAtEpochMillis),
      "expires_at_epoch_ms": .int(entry.expiresAtEpochMillis),
      "use_count": .int(entry.useCount)
    ]
  }

  private func publicRecord(_ entry: Entry) -> AgentExplicitToolHandlePublicRecord {
    AgentExplicitToolHandlePublicRecord(
      contract: AgentExplicitToolHandleContract.version,
      handleId: entry.handleId,
      kind: entry.kind,
      capabilities: entry.capabilities.sorted(),
      ownerId: entry.ownerId,
      contextId: entry.contextId,
      metadata: runControlMetadata(from: entry.metadata),
      createdAtEpochMillis: entry.createdAtEpochMillis,
      lastUsedAtEpochMillis: entry.lastUsedAtEpochMillis,
      expiresAtEpochMillis: entry.expiresAtEpochMillis,
      useCount: entry.useCount
    )
  }

  private func checked(_ value: String, field: String, maxLength: Int) throws -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.count > maxLength || normalized.unicodeScalars.contains(where: { $0.value < 32 }) {
      throw failure("tool_handle_input_invalid", "\(field) exceeds its safe limit")
    }
    return normalized
  }

  private func failure(_ code: String, _ message: String, retryable: Bool = false) -> AgentExplicitToolHandleException {
    AgentExplicitToolHandleException(code: code, message: message, retryable: retryable)
  }

  private func newHandleId(kind: String) -> String {
    let prefix = kind.filter { $0.isLetter || $0.isNumber }.prefix(8)
    return "sth_\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
  }

  private func mcpMetadata(from values: AgentRunControlPayload) -> AgentMcpJSONObject {
    values.mapValues { value in
      switch value {
      case .string(let text):
        return .string(text)
      case .int(let number):
        return .int(number)
      case .bool(let flag):
        return .bool(flag)
      }
    }
  }

  private func runControlMetadata(from values: AgentMcpJSONObject) -> AgentRunControlPayload {
    var result: AgentRunControlPayload = [:]
    for (key, value) in values {
      switch value {
      case .bool(let flag):
        result[key] = .bool(flag)
      case .int(let number):
        result[key] = .int(number)
      case .double(let number):
        result[key] = .string(String(number))
      case .string(let text):
        result[key] = .string(text)
      case .null, .object, .array:
        continue
      }
    }
    return result
  }

  private func publicMetadata(_ values: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
    guard values.count <= 32 else {
      throw failure("tool_handle_input_invalid", "Tool handle metadata has too many entries")
    }
    var result: AgentMcpJSONObject = [:]
    for (key, value) in values {
      let normalizedKey = try checked(key, field: "metadata key", maxLength: 80)
      switch value {
      case .null, .bool, .int, .double:
        result[normalizedKey] = value
      case .string(let text):
        result[normalizedKey] = .string(try checked(text, field: "metadata \(normalizedKey)", maxLength: 240))
      case .object, .array:
        continue
      }
    }
    return result
  }

  private func clamp(_ value: Int64, lower: Int64, upper: Int64) -> Int64 {
    min(max(value, lower), upper)
  }
}
