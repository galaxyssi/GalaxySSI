import Foundation

enum AgentPermissionSubjectType: String, Codable, CaseIterable, Identifiable {
  case model = "MODEL"
  case agent = "AGENT"
  case tool = "TOOL"
  case android = "ANDROID"
  case device = "DEVICE"
  case file = "FILE"
  case app = "APP"
  case consequentialAction = "CONSEQUENTIAL_ACTION"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionSubjectType {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .tool
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

enum AgentPermissionGrantLifetime: String, Codable, CaseIterable, Identifiable {
  case singleUse = "SINGLE_USE"
  case temporary = "TEMPORARY"
  case permanent = "PERMANENT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionGrantLifetime {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .singleUse
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

enum AgentPermissionGrantStatus: String, Codable, CaseIterable, Identifiable {
  case active = "ACTIVE"
  case consumed = "CONSUMED"
  case revoked = "REVOKED"
  case expired = "EXPIRED"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionGrantStatus {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .active
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

enum AgentPermissionGrantIssuer: String, Codable, CaseIterable, Identifiable {
  case user = "USER"
  case hostPolicy = "HOST_POLICY"
  case admin = "ADMIN"
  case `import` = "IMPORT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentPermissionGrantIssuer {
    let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .user
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

struct AgentPermissionGrantLedgerError: Error, Equatable {
  var message: String
}

struct AgentPermissionGrant: Codable, Equatable, Identifiable {
  var grantId: String
  var subjectType: AgentPermissionSubjectType
  var subjectId: String
  var scope: String
  var action: String
  var resource: String
  var target: String
  var constraintsJson: String
  var issuer: AgentPermissionGrantIssuer
  var evidence: String
  var lifetime: AgentPermissionGrantLifetime
  var status: AgentPermissionGrantStatus
  var maxUses: Int
  var uses: Int
  var createdAtMillis: Int64
  var expiresAtMillis: Int64
  var consumedAtMillis: Int64
  var revokedAtMillis: Int64
  var revocationReason: String

  var id: String { grantId }

  init(
    grantId: String = UUID().uuidString,
    subjectType: AgentPermissionSubjectType,
    subjectId: String,
    scope: String,
    action: String = "",
    resource: String = "",
    target: String = "",
    constraintsJson: String = "{}",
    issuer: AgentPermissionGrantIssuer,
    evidence: String,
    lifetime: AgentPermissionGrantLifetime,
    status: AgentPermissionGrantStatus = .active,
    maxUses: Int? = nil,
    uses: Int = 0,
    createdAtMillis: Int64 = 0,
    expiresAtMillis: Int64 = 0,
    consumedAtMillis: Int64 = 0,
    revokedAtMillis: Int64 = 0,
    revocationReason: String = ""
  ) {
    self.grantId = grantId
    self.subjectType = subjectType
    self.subjectId = subjectId
    self.scope = scope
    self.action = action
    self.resource = resource
    self.target = target
    self.constraintsJson = constraintsJson
    self.issuer = issuer
    self.evidence = evidence
    self.lifetime = lifetime
    self.status = status
    self.maxUses = maxUses ?? (lifetime == .singleUse ? 1 : 0)
    self.uses = uses
    self.createdAtMillis = createdAtMillis
    self.expiresAtMillis = expiresAtMillis
    self.consumedAtMillis = consumedAtMillis
    self.revokedAtMillis = revokedAtMillis
    self.revocationReason = revocationReason
  }

  enum CodingKeys: String, CodingKey {
    case grantId = "grant_id"
    case subjectType = "subject_type"
    case subjectId = "subject_id"
    case scope
    case action
    case resource
    case target
    case constraintsJson = "constraints_json"
    case issuer
    case evidence
    case lifetime
    case status
    case maxUses = "max_uses"
    case uses
    case createdAtMillis = "created_at_millis"
    case expiresAtMillis = "expires_at_millis"
    case consumedAtMillis = "consumed_at_millis"
    case revokedAtMillis = "revoked_at_millis"
    case revocationReason = "revocation_reason"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let lifetime = try container.decodeIfPresent(AgentPermissionGrantLifetime.self, forKey: .lifetime) ?? .singleUse
    self.init(
      grantId: try container.decodeIfPresent(String.self, forKey: .grantId) ?? UUID().uuidString,
      subjectType: try container.decodeIfPresent(AgentPermissionSubjectType.self, forKey: .subjectType) ?? .tool,
      subjectId: try container.decodeIfPresent(String.self, forKey: .subjectId) ?? "",
      scope: try container.decodeIfPresent(String.self, forKey: .scope) ?? "",
      action: try container.decodeIfPresent(String.self, forKey: .action) ?? "",
      resource: try container.decodeIfPresent(String.self, forKey: .resource) ?? "",
      target: try container.decodeIfPresent(String.self, forKey: .target) ?? "",
      constraintsJson: try container.decodeIfPresent(String.self, forKey: .constraintsJson) ?? "{}",
      issuer: try container.decodeIfPresent(AgentPermissionGrantIssuer.self, forKey: .issuer) ?? .user,
      evidence: try container.decodeIfPresent(String.self, forKey: .evidence) ?? "",
      lifetime: lifetime,
      status: try container.decodeIfPresent(AgentPermissionGrantStatus.self, forKey: .status) ?? .active,
      maxUses: try container.decodeIfPresent(Int.self, forKey: .maxUses),
      uses: try container.decodeIfPresent(Int.self, forKey: .uses) ?? 0,
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      expiresAtMillis: try container.decodeIfPresent(Int64.self, forKey: .expiresAtMillis) ?? 0,
      consumedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .consumedAtMillis) ?? 0,
      revokedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .revokedAtMillis) ?? 0,
      revocationReason: try container.decodeIfPresent(String.self, forKey: .revocationReason) ?? ""
    )
  }

  func isUsable(nowMillis: Int64) -> Bool {
    status == .active &&
      (expiresAtMillis <= 0 || nowMillis < expiresAtMillis) &&
      (maxUses <= 0 || uses < maxUses)
  }
}

struct AgentPermissionRequest: Codable, Equatable {
  var subjectType: AgentPermissionSubjectType
  var subjectId: String
  var scope: String
  var action: String
  var resource: String
  var target: String

  init(
    subjectType: AgentPermissionSubjectType,
    subjectId: String,
    scope: String,
    action: String = "",
    resource: String = "",
    target: String = ""
  ) {
    self.subjectType = subjectType
    self.subjectId = subjectId
    self.scope = scope
    self.action = action
    self.resource = resource
    self.target = target
  }

  enum CodingKeys: String, CodingKey {
    case subjectType = "subject_type"
    case subjectId = "subject_id"
    case scope
    case action
    case resource
    case target
  }
}

struct AgentPermissionDecision: Codable, Equatable {
  var granted: Bool
  var grant: AgentPermissionGrant?
  var reason: String
}

struct AgentPermissionRevocation: Codable, Equatable {
  var revokedGrantIds: Set<String>
  var scopes: Set<String>
  var reason: String
  var revokedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case revokedGrantIds = "revoked_grant_ids"
    case scopes
    case reason
    case revokedAtMillis = "revoked_at_millis"
  }
}

final class InMemoryAgentPermissionGrantStore {
  private let lock = NSRecursiveLock()
  private let nowMillis: () -> Int64
  private var grants: [AgentPermissionGrant]

  init(
    serialized: String = "[]",
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.nowMillis = nowMillis
    self.grants = AgentPermissionGrantJsonCodec.decode(serialized)
  }

  func grant(_ grant: AgentPermissionGrant) throws -> AgentPermissionGrant {
    try synchronized {
      let now = currentTime()
      let normalized = try normalize(grant, now: now)
      var refreshed = refreshExpired(grants, now: now)
      if let equivalent = refreshed.first(where: { existing in
        existing.status == .active &&
          existing.subjectType == normalized.subjectType &&
          existing.subjectId == normalized.subjectId &&
          existing.scope == normalized.scope &&
          existing.action == normalized.action &&
          existing.resource == normalized.resource &&
          existing.target == normalized.target &&
          existing.constraintsJson == normalized.constraintsJson &&
          existing.lifetime == normalized.lifetime &&
          existing.expiresAtMillis == normalized.expiresAtMillis
      }) {
        grants = bound(refreshed)
        return equivalent
      }
      guard !refreshed.contains(where: { $0.grantId == normalized.grantId }) else {
        throw AgentPermissionGrantLedgerError(message: "Permission grant id was already used")
      }
      refreshed.append(normalized)
      grants = bound(refreshed)
      return normalized
    }
  }

  func authorize(
    _ request: AgentPermissionRequest,
    consume: Bool = false
  ) throws -> AgentPermissionDecision {
    try synchronized {
      let normalizedRequest = try normalize(request)
      let now = currentTime()
      var refreshed = refreshExpired(grants, now: now)
      guard let match = refreshed
        .filter({ $0.isUsable(nowMillis: now) && matches($0, request: normalizedRequest) })
        .sorted(by: { left, right in
          let leftScore = matchSpecificity(left, request: normalizedRequest)
          let rightScore = matchSpecificity(right, request: normalizedRequest)
          if leftScore == rightScore {
            return left.createdAtMillis > right.createdAtMillis
          }
          return leftScore > rightScore
        })
        .first else {
        grants = bound(refreshed)
        return AgentPermissionDecision(granted: false, grant: nil, reason: "no_matching_host_grant")
      }
      guard consume else {
        grants = bound(refreshed)
        return AgentPermissionDecision(granted: true, grant: match, reason: "host_grant_active")
      }
      let updatedUses = match.uses + 1
      var consumed = match
      consumed.uses = updatedUses
      consumed.status = match.maxUses > 0 && updatedUses >= match.maxUses ? .consumed : .active
      consumed.consumedAtMillis = now
      if let index = refreshed.firstIndex(where: { $0.grantId == match.grantId }) {
        refreshed[index] = consumed
      }
      grants = bound(refreshed)
      return AgentPermissionDecision(granted: true, grant: consumed, reason: "host_grant_consumed")
    }
  }

  func list(includeInactive: Bool = true) -> [AgentPermissionGrant] {
    synchronized {
      let now = currentTime()
      grants = bound(refreshExpired(grants, now: now))
      return grants
        .filter { includeInactive || $0.status == .active }
        .sorted {
          if $0.createdAtMillis == $1.createdAtMillis {
            return $0.grantId < $1.grantId
          }
          return $0.createdAtMillis > $1.createdAtMillis
        }
    }
  }

  func revokeGrant(
    grantId: String,
    reason: String
  ) -> AgentPermissionRevocation {
    let cleanId = grantId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanId.isEmpty else {
      return emptyRevocation(reason: reason)
    }
    return revoke(reason: reason) { $0.grantId == cleanId }
  }

  func revokeScope(
    scope: String,
    reason: String
  ) -> AgentPermissionRevocation {
    let cleanScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanScope.isEmpty else {
      return emptyRevocation(reason: reason)
    }
    return revoke(reason: reason) { $0.scope == cleanScope }
  }

  func clear() {
    synchronized {
      grants = []
    }
  }

  func serializedSnapshot() -> String {
    synchronized {
      AgentPermissionGrantJsonCodec.encode(grants)
    }
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func revoke(
    reason: String,
    predicate: (AgentPermissionGrant) -> Bool
  ) -> AgentPermissionRevocation {
    synchronized {
      let now = currentTime()
      let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        .prefix(Self.maxReasonCharacters)
        .description
        .ifBlank("revoked_by_host")
      let refreshed = refreshExpired(grants, now: now)
      let revoked = refreshed.filter { $0.status == .active && predicate($0) }
      guard !revoked.isEmpty else {
        grants = bound(refreshed)
        return emptyRevocation(reason: cleanReason, now: now)
      }
      let revokedIds = Set(revoked.map(\.grantId))
      grants = bound(refreshed.map { grant in
        guard revokedIds.contains(grant.grantId) else {
          return grant
        }
        var updated = grant
        updated.status = .revoked
        updated.revokedAtMillis = now
        updated.revocationReason = cleanReason
        return updated
      })
      return AgentPermissionRevocation(
        revokedGrantIds: revokedIds,
        scopes: Set(revoked.map(\.scope)),
        reason: cleanReason,
        revokedAtMillis: now
      )
    }
  }

  private func normalize(_ grant: AgentPermissionGrant, now: Int64) throws -> AgentPermissionGrant {
    let grantId = try required(grant.grantId, limit: Self.maxIdCharacters, label: "grant id")
    let subjectId = try required(grant.subjectId, limit: Self.maxIdCharacters, label: "subject id")
    let scope = try required(grant.scope, limit: Self.maxScopeCharacters, label: "scope")
    let evidence = try required(grant.evidence, limit: Self.maxEvidenceCharacters, label: "evidence")
    let createdAt = grant.createdAtMillis > 0 ? grant.createdAtMillis : now
    guard grant.status == .active else {
      throw AgentPermissionGrantLedgerError(message: "Only active permission grants can be issued")
    }
    guard grant.uses == 0 && grant.consumedAtMillis == 0 && grant.revokedAtMillis == 0 else {
      throw AgentPermissionGrantLedgerError(message: "A new permission grant cannot contain prior usage or revocation state")
    }
    switch grant.lifetime {
    case .singleUse:
      guard grant.maxUses == 1 else {
        throw AgentPermissionGrantLedgerError(message: "Single-use permission grants must allow exactly one use")
      }
    case .temporary:
      guard grant.expiresAtMillis > createdAt else {
        throw AgentPermissionGrantLedgerError(message: "Temporary permission grants require a future expiry")
      }
    case .permanent:
      guard grant.expiresAtMillis == 0 else {
        throw AgentPermissionGrantLedgerError(message: "Permanent permission grants cannot expire")
      }
    }
    var normalized = grant
    normalized.grantId = grantId
    normalized.subjectId = subjectId
    normalized.scope = scope
    normalized.action = String(grant.action.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxScopeCharacters))
    normalized.resource = String(grant.resource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters))
    normalized.target = String(grant.target.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters))
    normalized.constraintsJson = try normalizeJson(grant.constraintsJson)
    normalized.evidence = evidence
    normalized.createdAtMillis = createdAt
    normalized.revocationReason = ""
    return normalized
  }

  private func normalize(_ request: AgentPermissionRequest) throws -> AgentPermissionRequest {
    AgentPermissionRequest(
      subjectType: request.subjectType,
      subjectId: try required(request.subjectId, limit: Self.maxIdCharacters, label: "subject id"),
      scope: try required(request.scope, limit: Self.maxScopeCharacters, label: "scope"),
      action: String(request.action.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxScopeCharacters)),
      resource: String(request.resource.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters)),
      target: String(request.target.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxResourceCharacters))
    )
  }

  private func refreshExpired(
    _ grants: [AgentPermissionGrant],
    now: Int64
  ) -> [AgentPermissionGrant] {
    grants.map { grant in
      guard grant.status == .active,
            grant.expiresAtMillis > 0,
            now >= grant.expiresAtMillis else {
        return grant
      }
      var expired = grant
      expired.status = .expired
      return expired
    }
  }

  private func matches(
    _ grant: AgentPermissionGrant,
    request: AgentPermissionRequest
  ) -> Bool {
    grant.subjectType == request.subjectType &&
      (grant.subjectId == request.subjectId || grant.subjectId == Self.wildcard) &&
      (grant.scope == request.scope || grant.scope == Self.wildcard) &&
      (grant.action.isEmpty || grant.action == request.action) &&
      (grant.resource.isEmpty || grant.resource == request.resource) &&
      (grant.target.isEmpty || grant.target == request.target)
  }

  private func matchSpecificity(
    _ grant: AgentPermissionGrant,
    request: AgentPermissionRequest
  ) -> Int {
    (grant.subjectId == request.subjectId ? 16 : 0) +
      (grant.scope == request.scope ? 8 : 0) +
      (grant.action.isEmpty ? 0 : 4) +
      (grant.resource.isEmpty ? 0 : 2) +
      (grant.target.isEmpty ? 0 : 1)
  }

  private func bound(_ grants: [AgentPermissionGrant]) -> [AgentPermissionGrant] {
    Array(grants.sorted {
      if $0.createdAtMillis == $1.createdAtMillis {
        return $0.grantId < $1.grantId
      }
      return $0.createdAtMillis < $1.createdAtMillis
    }.suffix(Self.maxGrants))
  }

  private func required(
    _ value: String,
    limit: Int,
    label: String
  ) throws -> String {
    let clean = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    guard !clean.isEmpty else {
      throw AgentPermissionGrantLedgerError(message: "Permission \(label) must not be blank")
    }
    return clean
  }

  private func normalizeJson(_ value: String) throws -> String {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("{}")
    guard let data = clean.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          JSONSerialization.isValidJSONObject(object),
          object is [String: Any],
          let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
      throw AgentPermissionGrantLedgerError(message: "Permission grant constraints must be a JSON object")
    }
    return String(decoding: encoded, as: UTF8.self)
  }

  private func emptyRevocation(
    reason: String,
    now: Int64? = nil
  ) -> AgentPermissionRevocation {
    AgentPermissionRevocation(
      revokedGrantIds: [],
      scopes: [],
      reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
      revokedAtMillis: now ?? currentTime()
    )
  }

  private func currentTime() -> Int64 {
    max(nowMillis(), 0)
  }

  private static let maxGrants = 2_000
  private static let maxIdCharacters = 256
  private static let maxScopeCharacters = 256
  private static let maxResourceCharacters = 2_048
  private static let maxEvidenceCharacters = 2_048
  private static let maxReasonCharacters = 1_024
  private static let wildcard = "*"
}

enum AgentPermissionGrantJsonCodec {
  static func encode(_ grants: [AgentPermissionGrant]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(grants) else {
      return "[]"
    }
    return String(decoding: data, as: UTF8.self)
  }

  static func decode(_ raw: String) -> [AgentPermissionGrant] {
    guard let data = raw.data(using: .utf8),
          let grants = try? JSONDecoder().decode([AgentPermissionGrant].self, from: data) else {
      return []
    }
    return grants
  }
}
