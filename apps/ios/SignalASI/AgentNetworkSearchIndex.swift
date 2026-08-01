import Foundation

struct AgentNetworkSearchQuery: Codable, Equatable {
  static let defaultPageSize = 24
  static let maxPageSize = 100

  var text: String
  var requiredCapabilities: Set<AgentCapability>
  var preferredCapabilities: Set<AgentCapability>
  var kinds: Set<AgentConnectorKind>
  var locations: Set<AgentResourceLocation>
  var statuses: Set<AgentEndpointStatus>
  var providerIds: Set<String>
  var deviceIds: Set<String>
  var excludedAgentIds: Set<String>
  var trustedOnly: Bool
  var routableOnly: Bool
  var includeAtCapacity: Bool
  var maximumCost: AgentResourceCost?
  var maximumLatency: AgentResourceLatency?
  var minimumReputationScore: Int?
  var minimumReputationConfidence: Int
  var pageSize: Int
  var cursor: String

  init(
    text: String = "",
    requiredCapabilities: Set<AgentCapability> = [],
    preferredCapabilities: Set<AgentCapability> = [],
    kinds: Set<AgentConnectorKind> = [],
    locations: Set<AgentResourceLocation> = [],
    statuses: Set<AgentEndpointStatus> = [],
    providerIds: Set<String> = [],
    deviceIds: Set<String> = [],
    excludedAgentIds: Set<String> = [],
    trustedOnly: Bool = false,
    routableOnly: Bool = true,
    includeAtCapacity: Bool = false,
    maximumCost: AgentResourceCost? = nil,
    maximumLatency: AgentResourceLatency? = nil,
    minimumReputationScore: Int? = nil,
    minimumReputationConfidence: Int = 40,
    pageSize: Int = AgentNetworkSearchQuery.defaultPageSize,
    cursor: String = ""
  ) {
    self.text = text
    self.requiredCapabilities = requiredCapabilities
    self.preferredCapabilities = preferredCapabilities
    self.kinds = kinds
    self.locations = locations
    self.statuses = statuses
    self.providerIds = providerIds
    self.deviceIds = deviceIds
    self.excludedAgentIds = excludedAgentIds
    self.trustedOnly = trustedOnly
    self.routableOnly = routableOnly
    self.includeAtCapacity = includeAtCapacity
    self.maximumCost = maximumCost
    self.maximumLatency = maximumLatency
    self.minimumReputationScore = minimumReputationScore
    self.minimumReputationConfidence = minimumReputationConfidence
    self.pageSize = pageSize
    self.cursor = cursor
  }

  enum CodingKeys: String, CodingKey {
    case text
    case requiredCapabilities = "required_capabilities"
    case preferredCapabilities = "preferred_capabilities"
    case kinds
    case locations
    case statuses
    case providerIds = "provider_ids"
    case deviceIds = "device_ids"
    case excludedAgentIds = "excluded_agent_ids"
    case trustedOnly = "trusted_only"
    case routableOnly = "routable_only"
    case includeAtCapacity = "include_at_capacity"
    case maximumCost = "maximum_cost"
    case maximumLatency = "maximum_latency"
    case minimumReputationScore = "minimum_reputation_score"
    case minimumReputationConfidence = "minimum_reputation_confidence"
    case pageSize = "page_size"
    case cursor
  }
}

struct AgentNetworkSearchHit: Codable, Equatable {
  var registration: AgentRegistration
  var score: Int
  var matchedCapabilities: Set<AgentCapability>
  var reasons: [String]
  var reputation: AgentReputationSnapshot

  enum CodingKeys: String, CodingKey {
    case registration
    case score
    case matchedCapabilities = "matched_capabilities"
    case reasons
    case reputation
  }
}

struct AgentNetworkSearchPage: Codable, Equatable {
  var queryId: String
  var revision: Int64
  var hits: [AgentNetworkSearchHit]
  var totalMatches: Int
  var nextCursor: String
  var cursorReset: Bool
  var generatedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case queryId = "query_id"
    case revision
    case hits
    case totalMatches = "total_matches"
    case nextCursor = "next_cursor"
    case cursorReset = "cursor_reset"
    case generatedAtMillis = "generated_at_millis"
  }
}

final class AgentNetworkIndex {
  private var registrationsById: [String: AgentRegistration] = [:]
  private var order: [String] = []
  private var currentRevision: Int64 = 0
  private var reputationsByAgentId: [String: AgentReputationSnapshot] = [:]
  private var reputationRevision: Int64 = 0

  init(
    _ registrations: [AgentRegistration] = [],
    reputations: [String: AgentReputationSnapshot] = [:],
    reputationRevision: Int64 = 0
  ) {
    for registration in registrations where registrationsById[registration.agentId] == nil {
      registrationsById[registration.agentId] = registration
      order.append(registration.agentId)
    }
    if !registrationsById.isEmpty {
      currentRevision = 1
    }
    self.reputationsByAgentId = reputations
    self.reputationRevision = reputationRevision
  }

  func size() -> Int {
    registrationsById.count
  }

  func revision() -> Int64 {
    effectiveRevision()
  }

  func get(_ agentId: String, nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()) -> AgentRegistration? {
    registrationsById[agentId]?.withEffectiveNetworkStatus(nowMillis: nowMillis)
  }

  func upsert(_ registration: AgentRegistration) {
    let previous = registrationsById[registration.agentId]
    guard previous != registration else {
      return
    }
    if previous == nil {
      order.append(registration.agentId)
    }
    registrationsById[registration.agentId] = registration
    currentRevision += 1
  }

  func replaceReputations(_ reputations: [String: AgentReputationSnapshot], revision: Int64) {
    reputationsByAgentId = reputations
    reputationRevision = revision
  }

  func search(
    _ query: AgentNetworkSearchQuery,
    nowMillis: Int64 = AgentRemoteApprovalClock.nowMillis()
  ) -> AgentNetworkSearchPage {
    var normalizedQuery = query
    normalizedQuery.pageSize = min(max(query.pageSize, 1), AgentNetworkSearchQuery.maxPageSize)
    let searchRevision = effectiveRevision()
    let queryId = fingerprint(normalizedQuery)
    let inferred = inferredCapabilities(from: normalizedQuery.text)
    let preferredCapabilities = normalizedQuery.preferredCapabilities.union(inferred)
    let queryTokens = searchTokens(normalizedQuery.text)

    let ranked = order
      .compactMap { registrationsById[$0] }
      .map { $0.withEffectiveNetworkStatus(nowMillis: nowMillis) }
      .filter { matches($0, query: normalizedQuery, inferred: inferred, preferred: preferredCapabilities, nowMillis: nowMillis) }
      .map {
        toSearchHit(
          registration: $0,
          query: normalizedQuery,
          preferredCapabilities: preferredCapabilities,
          queryTokens: queryTokens,
          nowMillis: nowMillis
        )
      }
      .sorted {
        if $0.score != $1.score {
          return $0.score > $1.score
        }
        let lhsName = $0.registration.displayName.lowercased()
        let rhsName = $1.registration.displayName.lowercased()
        if lhsName != rhsName {
          return lhsName < rhsName
        }
        return $0.registration.agentId < $1.registration.agentId
      }

    let decodedCursor = AgentNetworkCursor.decode(normalizedQuery.cursor)
    let cursorValid = decodedCursor?.revision == searchRevision && decodedCursor?.queryId == queryId
    let cursorIndex = cursorValid
      ? ranked.firstIndex { $0.registration.agentId == decodedCursor?.lastAgentId } ?? -1
      : -1
    let cursorReset = !normalizedQuery.cursor.isEmpty && (!cursorValid || cursorIndex < 0)
    let startIndex = cursorValid && cursorIndex >= 0 ? cursorIndex + 1 : 0
    let endIndex = min(startIndex + normalizedQuery.pageSize, ranked.count)
    let hits = startIndex < ranked.count ? Array(ranked[startIndex..<endIndex]) : []
    let nextCursor = endIndex < ranked.count && !hits.isEmpty
      ? AgentNetworkCursor(revision: searchRevision, queryId: queryId, lastAgentId: hits.last?.registration.agentId ?? "").encode()
      : ""
    return AgentNetworkSearchPage(
      queryId: queryId,
      revision: searchRevision,
      hits: hits,
      totalMatches: ranked.count,
      nextCursor: nextCursor,
      cursorReset: cursorReset,
      generatedAtMillis: nowMillis
    )
  }

  private func matches(
    _ registration: AgentRegistration,
    query: AgentNetworkSearchQuery,
    inferred: Set<AgentCapability>,
    preferred: Set<AgentCapability>,
    nowMillis: Int64
  ) -> Bool {
    if query.excludedAgentIds.contains(registration.agentId) { return false }
    if !registration.capabilities.isSuperset(of: query.requiredCapabilities) { return false }
    if !query.kinds.isEmpty && !query.kinds.contains(registration.kind) { return false }
    if !query.locations.isEmpty && !query.locations.contains(registration.location) { return false }
    if !query.statuses.isEmpty && !query.statuses.contains(registration.status) { return false }
    if !query.providerIds.isEmpty &&
      !query.providerIds.map(normalizeSearchText).contains(normalizeSearchText(registration.providerId)) {
      return false
    }
    if !query.deviceIds.isEmpty &&
      !query.deviceIds.map(normalizeSearchText).contains(normalizeSearchText(registration.deviceId)) {
      return false
    }
    if query.trustedOnly && registration.trust == .unknown { return false }
    if let maximumCost = query.maximumCost, registration.cost > maximumCost { return false }
    if let maximumLatency = query.maximumLatency, registration.latency > maximumLatency { return false }
    if query.routableOnly && !Self.routableStates.contains(registration.status) { return false }
    if query.routableOnly && !query.includeAtCapacity && !registration.hasCapacity { return false }
    if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let tokenMatches = !registration.indexTokens().isDisjoint(with: searchTokens(query.text))
      let capabilityMatches = inferred.isEmpty || !registration.capabilities.isDisjoint(with: inferred)
      if !tokenMatches && !capabilityMatches {
        return false
      }
    }
    if let minimumReputation = query.minimumReputationScore {
      let reputation = reputation(for: registration, capabilities: query.requiredCapabilities.union(preferred))
      let minimumConfidence = min(max(query.minimumReputationConfidence, 0), 100)
      if reputation.confidence >= minimumConfidence && reputation.score < min(max(minimumReputation, 0), 100) {
        return false
      }
    }
    return true
  }

  private func toSearchHit(
    registration: AgentRegistration,
    query: AgentNetworkSearchQuery,
    preferredCapabilities: Set<AgentCapability>,
    queryTokens: Set<String>,
    nowMillis: Int64
  ) -> AgentNetworkSearchHit {
    var reasons: [String] = []
    var score = 0
    let normalizedText = normalizeSearchText(query.text)
    let searchableFields = [
      registration.agentId,
      registration.displayName,
      registration.providerId,
      registration.deviceId,
      registration.adapterType
    ].map(normalizeSearchText).filter { !$0.isEmpty }
    if !normalizedText.isEmpty {
      if searchableFields.contains(normalizedText) {
        score += 1_200
        reasons.append("identity_exact")
      } else if searchableFields.contains(where: { $0.hasPrefix(normalizedText) }) {
        score += 760
        reasons.append("identity_prefix")
      } else if searchableFields.contains(where: { $0.contains(normalizedText) }) {
        score += 520
        reasons.append("identity_contains")
      }
      let tokenMatches = registration.indexTokens().intersection(queryTokens)
      if !tokenMatches.isEmpty {
        score += tokenMatches.count * 90
        reasons.append("text_tokens:\(tokenMatches.count)")
      }
    }
    let matchedCapabilities = registration.capabilities.intersection(preferredCapabilities)
    let missingPreferred = preferredCapabilities.subtracting(registration.capabilities)
    score += matchedCapabilities.count * 130
    score -= missingPreferred.count * 45
    if !matchedCapabilities.isEmpty {
      reasons.append("capabilities:\(matchedCapabilities.map(\.rawValue).sorted().joined(separator: ","))")
    }
    score += statusScore(registration.status)
    score += registration.hasCapacity ? 90 : -260
    score += trustScore(registration.trust)
    score -= registration.cost.rank * 35
    score -= registration.latency.rank * 30
    let reputation = reputation(for: registration, capabilities: query.requiredCapabilities.union(preferredCapabilities))
    score += reputation.routingAdjustment
    if searchTokens(query.text).contains("fast"), registration.latency <= .fast {
      score += 180
    }
    if searchTokens(query.text).contains("economy"), registration.cost <= .low {
      score += 180
    }
    if registration.lastHeartbeatMillis > 0 {
      let heartbeatAge = max(Int64(0), nowMillis - registration.lastHeartbeatMillis)
      switch heartbeatAge {
      case 0...30_000:
        score += 90
      case 30_001...120_000:
        score += 55
      case 120_001...Self.heartbeatTTLMillis:
        score += 20
      default:
        score -= 120
      }
      reasons.append("heartbeat_age_ms:\(heartbeatAge)")
    }
    reasons.append("status:\(registration.status.rawValue.lowercased())")
    reasons.append("trust:\(registration.trust.rawValue.lowercased())")
    reasons.append("latency:\(registration.latency.rawValue.lowercased())")
    reasons.append("cost:\(registration.cost.rawValue.lowercased())")
    if reputation.confidence > 0 {
      reasons.append("reputation:\(reputation.score)")
      reasons.append("reputation_confidence:\(reputation.confidence)")
    }
    return AgentNetworkSearchHit(
      registration: registration,
      score: score,
      matchedCapabilities: matchedCapabilities,
      reasons: distinctReasons(reasons),
      reputation: reputation
    )
  }

  private func reputation(
    for registration: AgentRegistration,
    capabilities: Set<AgentCapability>
  ) -> AgentReputationSnapshot {
    reputationsByAgentId[registration.agentId] ?? .neutral(registration.agentId)
  }

  private func effectiveRevision() -> Int64 {
    currentRevision * 1_000_003 + reputationRevision
  }

  private func fingerprint(_ query: AgentNetworkSearchQuery) -> String {
    var parts: [String] = []
    parts.append(normalizeSearchText(query.text))
    parts.append(query.requiredCapabilities.map(\.rawValue).sorted().joined(separator: ","))
    parts.append(query.preferredCapabilities.map(\.rawValue).sorted().joined(separator: ","))
    parts.append(query.kinds.map(\.rawValue).sorted().joined(separator: ","))
    parts.append(query.locations.map(\.rawValue).sorted().joined(separator: ","))
    parts.append(query.statuses.map(\.rawValue).sorted().joined(separator: ","))
    parts.append(query.providerIds.map(normalizeSearchText).sorted().joined(separator: ","))
    parts.append(query.deviceIds.map(normalizeSearchText).sorted().joined(separator: ","))
    parts.append(query.excludedAgentIds.sorted().joined(separator: ","))
    parts.append(String(query.trustedOnly))
    parts.append(String(query.routableOnly))
    parts.append(String(query.includeAtCapacity))
    parts.append(query.maximumCost?.rawValue ?? "")
    parts.append(query.maximumLatency?.rawValue ?? "")
    parts.append(query.minimumReputationScore.map { String(min(max($0, 0), 100)) } ?? "")
    parts.append(String(min(max(query.minimumReputationConfidence, 0), 100)))
    parts.append(String(min(max(query.pageSize, 1), AgentNetworkSearchQuery.maxPageSize)))
    let canonical = parts.joined(separator: "\u{001f}")
    return String(agentReputationSha256(Data(canonical.utf8)).prefix(24))
  }

  private func inferredCapabilities(from text: String) -> Set<AgentCapability> {
    let tokens = searchTokens(text)
    var capabilities = Set<AgentCapability>()
    if !tokens.isDisjoint(with: ["code", "coding", "debug", "python", "repo", "project", "commit"]) {
      capabilities.insert(.code)
    }
    if !tokens.isDisjoint(with: ["research", "search", "web", "latest", "news"]) {
      capabilities.insert(.research)
    }
    if !tokens.isDisjoint(with: ["live", "realtime", "online"]) {
      capabilities.insert(.liveData)
    }
    if !tokens.isDisjoint(with: ["reason", "architecture", "plan"]) {
      capabilities.insert(.reasoning)
    }
    if !tokens.isDisjoint(with: ["verify", "verification", "validate", "audit", "auditor"]) {
      capabilities.insert(.reasoning)
      capabilities.insert(.research)
    }
    return capabilities
  }

  private func statusScore(_ status: AgentEndpointStatus) -> Int {
    switch status {
    case .idle: return 240
    case .online: return 220
    case .busy: return 120
    case .degraded: return -80
    case .updating: return -140
    case .permissionRequired: return -180
    case .offline: return -300
    case .unreachable: return -420
    }
  }

  private func trustScore(_ trust: AgentResourceTrust) -> Int {
    switch trust {
    case .phoneSystem: return 180
    case .verifiedPaired: return 160
    case .privateConfigured: return 110
    case .cloudConfigured: return 55
    case .unknown: return -160
    }
  }

  private func distinctReasons(_ reasons: [String]) -> [String] {
    var seen = Set<String>()
    return reasons.filter { seen.insert($0).inserted }
  }

  private static let routableStates: Set<AgentEndpointStatus> = [.online, .idle, .busy]
  static let heartbeatTTLMillis: Int64 = 10 * 60_000
}

private struct AgentNetworkCursor {
  var revision: Int64
  var queryId: String
  var lastAgentId: String

  func encode() -> String {
    Data("\(revision)\u{001f}\(queryId)\u{001f}\(lastAgentId)".utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  static func decode(_ raw: String) -> AgentNetworkCursor? {
    guard !raw.isEmpty else {
      return nil
    }
    var base64 = raw
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while base64.count % 4 != 0 {
      base64 += "="
    }
    guard let data = Data(base64Encoded: base64) else {
      return nil
    }
    let parts = String(decoding: data, as: UTF8.self).split(separator: "\u{001f}", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let revision = Int64(parts[0]) else {
      return nil
    }
    return AgentNetworkCursor(revision: revision, queryId: String(parts[1]), lastAgentId: String(parts[2]))
  }
}

private extension AgentRegistration {
  func withEffectiveNetworkStatus(nowMillis: Int64) -> AgentRegistration {
    let stale = location != .phone &&
      lastHeartbeatMillis > 0 &&
      nowMillis - lastHeartbeatMillis > AgentNetworkIndex.heartbeatTTLMillis &&
      status != .offline &&
      status != .unreachable
    guard stale else {
      return self
    }
    var copy = self
    copy.status = .unreachable
    return copy
  }

  func indexTokens() -> Set<String> {
    var tokens = Set<String>()
    [agentId, installationId, deviceId, providerId, displayName, adapterType].forEach {
      tokens.formUnion(searchTokens($0))
    }
    capabilities.forEach { tokens.formUnion(searchTokens($0.rawValue)) }
    toolIds.forEach { tokens.formUnion(searchTokens($0)) }
    return tokens
  }
}

func searchTokens(_ value: String) -> Set<String> {
  Set(normalizeSearchText(value)
    .components(separatedBy: CharacterSet.alphanumerics.inverted)
    .filter { $0.count >= 2 })
}

func normalizeSearchText(_ value: String) -> String {
  value
    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    .lowercased()
    .trimmingCharacters(in: .whitespacesAndNewlines)
}
