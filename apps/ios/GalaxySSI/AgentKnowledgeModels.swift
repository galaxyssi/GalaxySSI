import Foundation

enum AgentKnowledgeKind: String, Codable, CaseIterable, Identifiable {
  case note = "NOTE"
  case document = "DOCUMENT"
  case screen = "SCREEN"
  case chat = "CHAT"
  case task = "TASK"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentKnowledgeKind {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .note
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentKnowledgeCloudAccess: String, Codable, CaseIterable, Identifiable {
  case deny = "DENY"
  case summaryOnly = "SUMMARY_ONLY"
  case full = "FULL"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentKnowledgeCloudAccess {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .deny
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentKnowledgeAgentAccess: String, Codable, CaseIterable, Identifiable {
  case localOnly = "LOCAL_ONLY"
  case selectedAgents = "SELECTED_AGENTS"
  case anyPairedAgent = "ANY_PAIRED_AGENT"

  var id: String { rawValue }

  static func fromWireValue(_ value: String?) -> AgentKnowledgeAgentAccess {
    let normalized = value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "-", with: "_")
      .uppercased() ?? ""
    return allCases.first { $0.rawValue == normalized } ?? .localOnly
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    self = Self.fromWireValue(try? container.decode(String.self))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

enum AgentKnowledgeEvidenceMode: String, Codable, CaseIterable, Identifiable, Equatable, Hashable {
  case full = "FULL"
  case summary = "SUMMARY"

  var id: String { rawValue }
}

struct AgentKnowledgeItem: Codable, Equatable, Identifiable {
  var id: String
  var kind: AgentKnowledgeKind
  var title: String
  var content: String
  var source: String
  var tags: [String]
  var summary: String
  var cloudAccess: AgentKnowledgeCloudAccess
  var agentAccess: AgentKnowledgeAgentAccess
  var allowedAgentIds: [String]
  var chunkIndex: Int
  var chunkCount: Int
  var updatedAtMillis: Int64

  init(
    id: String = UUID().uuidString,
    kind: AgentKnowledgeKind,
    title: String,
    content: String,
    source: String = "",
    tags: [String] = [],
    summary: String = "",
    cloudAccess: AgentKnowledgeCloudAccess = .deny,
    agentAccess: AgentKnowledgeAgentAccess = .localOnly,
    allowedAgentIds: [String] = [],
    chunkIndex: Int = 0,
    chunkCount: Int = 1,
    updatedAtMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    self.id = String(id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters)).ifBlank(UUID().uuidString)
    self.kind = kind
    self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTitleCharacters))
    self.content = String(content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxContentCharacters))
    self.source = String(source.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxSourceCharacters))
    self.tags = tags
      .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(Self.maxTagCharacters)) }
      .filter { !$0.isBlank }
      .stableDistinct()
      .prefixArray(Self.maxTags)
    self.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxSummaryCharacters))
    self.cloudAccess = cloudAccess
    self.agentAccess = agentAccess
    self.allowedAgentIds = allowedAgentIds
      .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxIdCharacters)) }
      .filter { !$0.isBlank }
      .stableDistinct()
      .prefixArray(Self.maxAllowedAgents)
    self.chunkIndex = max(chunkIndex, 0)
    self.chunkCount = max(chunkCount, 1)
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case id
    case kind
    case title
    case content
    case source
    case tags
    case summary
    case cloudAccess = "cloud_access"
    case agentAccess = "agent_access"
    case allowedAgentIds = "allowed_agent_ids"
    case chunkIndex = "chunk_index"
    case chunkCount = "chunk_count"
    case updatedAtMillis = "updated_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
      kind: try container.decodeIfPresent(AgentKnowledgeKind.self, forKey: .kind) ?? .note,
      title: try container.decodeIfPresent(String.self, forKey: .title) ?? "",
      content: try container.decodeIfPresent(String.self, forKey: .content) ?? "",
      source: try container.decodeIfPresent(String.self, forKey: .source) ?? "",
      tags: try container.decodeIfPresent([String].self, forKey: .tags) ?? [],
      summary: try container.decodeIfPresent(String.self, forKey: .summary) ?? "",
      cloudAccess: try container.decodeIfPresent(AgentKnowledgeCloudAccess.self, forKey: .cloudAccess) ?? .deny,
      agentAccess: try container.decodeIfPresent(AgentKnowledgeAgentAccess.self, forKey: .agentAccess) ?? .localOnly,
      allowedAgentIds: try container.decodeIfPresent([String].self, forKey: .allowedAgentIds) ?? [],
      chunkIndex: try container.decodeIfPresent(Int.self, forKey: .chunkIndex) ?? 0,
      chunkCount: try container.decodeIfPresent(Int.self, forKey: .chunkCount) ?? 1,
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0
    )
  }

  private static let maxIdCharacters = 160
  private static let maxTitleCharacters = 500
  private static let maxContentCharacters = 128_000
  private static let maxSourceCharacters = 4_096
  private static let maxSummaryCharacters = 4_000
  private static let maxTagCharacters = 80
  private static let maxTags = 24
  private static let maxAllowedAgents = 32
}

struct AgentKnowledgeHit: Codable, Equatable {
  var item: AgentKnowledgeItem
  var score: Double
  var excerpt: String
  var matchedTerms: [String]

  init(
    item: AgentKnowledgeItem,
    score: Double,
    excerpt: String,
    matchedTerms: [String] = []
  ) {
    self.item = item
    self.score = min(max(score, 0), 1)
    self.excerpt = String(excerpt.prefix(2_000))
    self.matchedTerms = matchedTerms
      .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80)) }
      .filter { !$0.isBlank }
      .stableDistinct()
  }

  enum CodingKeys: String, CodingKey {
    case item
    case score
    case excerpt
    case matchedTerms = "matched_terms"
  }
}

struct AgentKnowledgeImportAssessment: Equatable {
  var indexedContent: String
  var truncated: Bool
  var sensitiveFlags: [String]

  var isAllowed: Bool { sensitiveFlags.isEmpty }
}

enum AgentKnowledgeImportPolicy {
  static let maxSourceBytes = 20 * 1024 * 1024
  static let maxWebBytes = 5 * 1024 * 1024
  static let maxExtractedCharacters = 240_000

  static func assess(_ content: String) -> AgentKnowledgeImportAssessment {
    let normalized = content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return AgentKnowledgeImportAssessment(
      indexedContent: String(normalized.prefix(maxExtractedCharacters)),
      truncated: normalized.count > maxExtractedCharacters,
      sensitiveFlags: sensitiveFlags(in: normalized)
    )
  }

  static func sensitiveFlags(in content: String) -> [String] {
    let patterns: [(String, String)] = [
      ("private_key", "-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
      (
        "credential_assignment",
        "(?i)\\b(?:password|api[_ -]?key|access[_ -]?token|secret[_ -]?key)\\s*[:=]\\s*[^\\s]{8,}"
      ),
      ("access_token", "\\b(?:sk|rk|pk)_[A-Za-z0-9_-]{20,}\\b")
    ]
    return patterns.compactMap { flag, pattern in
      content.range(of: pattern, options: [.regularExpression, .caseInsensitive]) == nil
        ? nil
        : flag
    }
  }
}

struct AgentKnowledgeCitation: Codable, Equatable {
  var index: Int
  var itemId: String
  var title: String
  var source: String
  var excerpt: String
  var score: Double
  var evidenceMode: AgentKnowledgeEvidenceMode
}

struct AgentKnowledgeRAGContext: Equatable {
  var query: String
  var targetId: String
  var citations: [AgentKnowledgeCitation]
  var blockedMatchCount: Int
  var matchedHits: [AgentKnowledgeHit]

  var sourceCount: Int {
    Set(citations.map(\.source)).count
  }
}

enum AgentKnowledgeRetriever {
  static func retrieve(
    hits: [AgentKnowledgeHit],
    query: String,
    targetId: String,
    limit: Int = 8
  ) -> AgentKnowledgeRAGContext {
    var allowed: [(AgentKnowledgeHit, AgentKnowledgeEvidenceMode)] = []
    var blocked = 0
    for hit in hits {
      guard let mode = evidenceMode(for: hit.item, targetId: targetId) else {
        blocked += 1
        continue
      }
      allowed.append((hit, mode))
    }
    let selected = allowed.prefix(max(1, min(limit, maxCitations)))
    let citations = selected.enumerated().map { index, entry in
      let (hit, mode) = entry
      let excerpt = mode == .full
        ? hit.excerpt
        : String(hit.item.summary.ifBlank(hit.excerpt).prefix(maxSummaryEvidence))
      return AgentKnowledgeCitation(
        index: index + 1,
        itemId: hit.item.id,
        title: hit.item.title,
        source: sourceLabel(hit.item.source),
        excerpt: String(excerpt),
        score: hit.score,
        evidenceMode: mode
      )
    }
    return AgentKnowledgeRAGContext(
      query: query,
      targetId: targetId,
      citations: citations,
      blockedMatchCount: blocked,
      matchedHits: selected.map { $0.0 }
    )
  }

  private static func evidenceMode(
    for item: AgentKnowledgeItem,
    targetId: String
  ) -> AgentKnowledgeEvidenceMode? {
    if targetId == "agent-knowledge-local" || targetId == "local-llm" {
      return .full
    }
    if targetId == "cloud-models" || targetId.hasPrefix("cloud-model:") {
      switch item.cloudAccess {
      case .deny: return nil
      case .summaryOnly: return .summary
      case .full: return .full
      }
    }
    switch item.agentAccess {
    case .localOnly:
      return nil
    case .anyPairedAgent:
      return .full
    case .selectedAgents:
      return item.allowedAgentIds.contains(targetId) ? .full : nil
    }
  }

  private static func sourceLabel(_ source: String) -> String {
    let clean = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return "Local knowledge" }
    if clean.hasPrefix("http://") || clean.hasPrefix("https://") {
      return String(clean.prefix(240))
    }
    return String(clean.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(180))
  }

  private static let maxCitations = 10
  private static let maxSummaryEvidence = 700
}

struct AgentKnowledgeStats: Codable, Equatable {
  var itemCount: Int
  var sourceCount: Int
  var lastUpdatedAtMillis: Int64

  init(
    itemCount: Int = 0,
    sourceCount: Int = 0,
    lastUpdatedAtMillis: Int64 = 0
  ) {
    self.itemCount = max(itemCount, 0)
    self.sourceCount = max(sourceCount, 0)
    self.lastUpdatedAtMillis = max(lastUpdatedAtMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case itemCount = "item_count"
    case sourceCount = "source_count"
    case lastUpdatedAtMillis = "last_updated_at_millis"
  }
}

struct AgentKnowledgeSourceGroup: Codable, Equatable, Identifiable {
  var source: String
  var title: String
  var itemIds: [String]
  var chunkCount: Int
  var cloudAccess: AgentKnowledgeCloudAccess
  var agentAccess: AgentKnowledgeAgentAccess
  var allowedAgentIds: [String]
  var updatedAtMillis: Int64

  var id: String { source }

  init(
    source: String,
    title: String,
    itemIds: [String],
    chunkCount: Int,
    cloudAccess: AgentKnowledgeCloudAccess,
    agentAccess: AgentKnowledgeAgentAccess,
    allowedAgentIds: [String] = [],
    updatedAtMillis: Int64
  ) {
    self.source = source
    self.title = title.ifBlank("Private knowledge")
    self.itemIds = itemIds.stableDistinct()
    self.chunkCount = max(chunkCount, 0)
    self.cloudAccess = cloudAccess
    self.agentAccess = agentAccess
    self.allowedAgentIds = allowedAgentIds.stableDistinct()
    self.updatedAtMillis = max(updatedAtMillis, 0)
  }
}

struct AgentKnowledgeAccessAuditEntry: Codable, Equatable, Identifiable {
  var queryHash: Int
  var targetId: String
  var itemIdHashes: [Int]
  var sourceCount: Int
  var evidenceModes: [AgentKnowledgeEvidenceMode]
  var blockedMatchCount: Int
  var timestampMillis: Int64

  var id: String { "\(queryHash):\(targetId):\(timestampMillis)" }

  init(
    queryHash: Int,
    targetId: String,
    itemIdHashes: [Int],
    sourceCount: Int,
    evidenceModes: [AgentKnowledgeEvidenceMode],
    blockedMatchCount: Int,
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    self.queryHash = queryHash
    self.targetId = String(targetId.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)).ifBlank("agent-knowledge-local")
    self.itemIdHashes = itemIdHashes
    self.sourceCount = max(sourceCount, 0)
    self.evidenceModes = evidenceModes.stableDistinct()
    self.blockedMatchCount = max(blockedMatchCount, 0)
    self.timestampMillis = max(timestampMillis, 0)
  }

  enum CodingKeys: String, CodingKey {
    case queryHash = "query_hash"
    case targetId = "target_id"
    case itemIdHashes = "item_id_hashes"
    case sourceCount = "source_count"
    case evidenceModes = "evidence_modes"
    case blockedMatchCount = "blocked_match_count"
    case timestampMillis = "timestamp_millis"
  }
}

private extension Array where Element: Hashable {
  func stableDistinct() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}

private extension Array {
  func prefixArray(_ limit: Int) -> [Element] {
    Array(prefix(Swift.max(limit, 0)))
  }
}
