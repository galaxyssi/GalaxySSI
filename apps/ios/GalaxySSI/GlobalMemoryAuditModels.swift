import Foundation

enum GlobalMemoryAuditFindingKind: String, Codable, CaseIterable, Identifiable {
  case expired = "EXPIRED"
  case duplicate = "DUPLICATE"
  case lowConfidenceReused = "LOW_CONFIDENCE_REUSED"
  case staleCandidate = "STALE_CANDIDATE"
  case unresolvedConflict = "UNRESOLVED_CONFLICT"
  case skillCandidate = "SKILL_CANDIDATE"
  case completedGoal = "COMPLETED_GOAL"

  var id: String { rawValue }
}

struct GlobalMemoryAuditFinding: Codable, Equatable, Identifiable {
  var kind: GlobalMemoryAuditFindingKind
  var stableKey: String
  var summary: String
  var evidenceCount: Int

  var id: String { "\(kind.rawValue):\(stableKey)" }

  enum CodingKeys: String, CodingKey {
    case kind
    case stableKey = "stable_key"
    case summary
    case evidenceCount = "evidence_count"
  }

  init(
    kind: GlobalMemoryAuditFindingKind,
    stableKey: String,
    summary: String,
    evidenceCount: Int
  ) {
    self.kind = kind
    self.stableKey = String(stableKey.prefix(240))
    self.summary = GlobalMemoryEvolutionPolicy.compact(summary, maximum: 600)
    self.evidenceCount = max(evidenceCount, 0)
  }
}

struct GlobalMemoryTheme: Codable, Equatable, Identifiable {
  var id: String
  var title: String
  var itemStableKeys: [String]
  var itemCount: Int
  var evidenceCount: Int
  var conversationCount: Int
  var confidence: Double
  var lastUpdatedAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case id
    case title
    case itemStableKeys = "item_stable_keys"
    case itemCount = "item_count"
    case evidenceCount = "evidence_count"
    case conversationCount = "conversation_count"
    case confidence
    case lastUpdatedAtMillis = "last_updated_at_millis"
  }

  init(
    id: String,
    title: String,
    itemStableKeys: [String],
    itemCount: Int,
    evidenceCount: Int,
    conversationCount: Int,
    confidence: Double,
    lastUpdatedAtMillis: Int64
  ) {
    self.id = String(id.prefix(160))
    self.title = GlobalMemoryEvolutionPolicy.compact(title, maximum: 160)
    self.itemStableKeys = Array(GlobalMemoryEvolutionPolicy.uniqueStrings(itemStableKeys).prefix(24))
    self.itemCount = max(itemCount, 0)
    self.evidenceCount = max(evidenceCount, 0)
    self.conversationCount = max(conversationCount, 0)
    self.confidence = min(max(confidence, 0), 1)
    self.lastUpdatedAtMillis = max(lastUpdatedAtMillis, 0)
  }
}

struct GlobalMemoryAuditReport: Codable, Equatable {
  var findings: [GlobalMemoryAuditFinding]
  var themes: [GlobalMemoryTheme]
  var auditedItemCount: Int
  var createdAtMillis: Int64

  enum CodingKeys: String, CodingKey {
    case findings
    case themes
    case auditedItemCount = "audited_item_count"
    case createdAtMillis = "created_at_millis"
  }

  init(
    findings: [GlobalMemoryAuditFinding] = [],
    themes: [GlobalMemoryTheme] = [],
    auditedItemCount: Int = 0,
    createdAtMillis: Int64 = 0
  ) {
    self.findings = Array(findings.prefix(200))
    self.themes = Array(themes.prefix(80))
    self.auditedItemCount = max(auditedItemCount, 0)
    self.createdAtMillis = max(createdAtMillis, 0)
  }
}

enum GlobalMemoryCritic {
  static func audit(
    world: PersonalWorldModel,
    inbox: GlobalMemoryInbox,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> (world: PersonalWorldModel, report: GlobalMemoryAuditReport) {
    var findings: [GlobalMemoryAuditFinding] = []
    var items = world.items.map { item -> GlobalWorldItem in
      var updated = item
      if item.expiresAtMillis > 0 && item.expiresAtMillis <= nowMillis && item.status == .active {
        findings.append(GlobalMemoryAuditFinding(
          kind: .expired,
          stableKey: item.stableKey,
          summary: "Expired temporal evidence was retired",
          evidenceCount: item.evidenceCount
        ))
        updated.status = .superseded
        updated.temporalState = .deprecated
      } else if item.confidence < 0.50 && item.evidenceCount >= 3 {
        findings.append(GlobalMemoryAuditFinding(
          kind: .lowConfidenceReused,
          stableKey: item.stableKey,
          summary: "Frequently reused evidence remains low confidence",
          evidenceCount: item.evidenceCount
        ))
      }
      return updated
    }

    consolidateDuplicates(items: &items, findings: &findings)

    let conflicts = Dictionary(grouping: items.filter {
      $0.status == .conflicted && !$0.conflictGroupId.isEmpty
    }, by: \.conflictGroupId)
    for (group, conflicts) in conflicts {
      findings.append(GlobalMemoryAuditFinding(
        kind: .unresolvedConflict,
        stableKey: group,
        summary: "Conflicting memory evidence requires review",
        evidenceCount: conflicts.reduce(0) { $0 + $1.evidenceCount }
      ))
    }

    for item in items where item.kind == .decision && item.evidenceCount >= 3 {
      findings.append(GlobalMemoryAuditFinding(
        kind: .skillCandidate,
        stableKey: item.stableKey,
        summary: "Repeated workflow evidence may be promoted to a reviewed Skill",
        evidenceCount: item.evidenceCount
      ))
    }

    for item in items where item.kind == .goal && item.status == .completed {
      findings.append(GlobalMemoryAuditFinding(
        kind: .completedGoal,
        stableKey: item.stableKey,
        summary: "Completed goal can be archived",
        evidenceCount: item.evidenceCount
      ))
    }

    let stalePending = inbox.pending().filter {
      nowMillis - $0.createdAtMillis > pendingReviewWarningMillis
    }.count
    if stalePending > 0 {
      findings.append(GlobalMemoryAuditFinding(
        kind: .staleCandidate,
        stableKey: "memory-inbox",
        summary: "\(stalePending) memory candidates are still awaiting review",
        evidenceCount: stalePending
      ))
    }

    var evolved = world
    if items != world.items {
      evolved.items = items
      evolved.updatedAtMillis = max(world.updatedAtMillis, nowMillis)
    }
    let report = GlobalMemoryAuditReport(
      findings: distinctFindings(findings),
      themes: consolidateThemes(items),
      auditedItemCount: world.items.count,
      createdAtMillis: nowMillis
    )
    return (evolved, report)
  }

  static func due(
    lastAuditMillis: Int64,
    processedEvents: Int,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> Bool {
    processedEvents >= 20 || lastAuditMillis <= 0 || nowMillis - lastAuditMillis >= auditIntervalMillis
  }

  static func nextAuditAt(
    lastAuditMillis: Int64,
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> Int64 {
    lastAuditMillis <= 0 ? nowMillis : max(lastAuditMillis + auditIntervalMillis, nowMillis)
  }

  private static func consolidateDuplicates(
    items: inout [GlobalWorldItem],
    findings: inout [GlobalMemoryAuditFinding]
  ) {
    let ordered = items.indices.sorted { items[$0].lastSeenAtMillis > items[$1].lastSeenAtMillis }
    for (position, primaryIndex) in ordered.enumerated() {
      let primary = items[primaryIndex]
      if !primary.isGlobalMemoryCurrent { continue }
      for duplicateIndex in ordered.dropFirst(position + 1) {
        let currentPrimary = items[primaryIndex]
        let duplicate = items[duplicateIndex]
        if !duplicate.isGlobalMemoryCurrent || currentPrimary.layer != duplicate.layer { continue }
        if !GlobalMemoryEvolutionPolicy.equivalentAssertion(currentPrimary, duplicate) { continue }

        var merged = GlobalMemoryEvolutionPolicy.strengthened(existing: currentPrimary, incoming: duplicate)
        merged.supersedesItemIds = Array(
          GlobalMemoryEvolutionPolicy.uniqueStrings(currentPrimary.supersedesItemIds + [duplicate.id]).suffix(maxSupersessionTargets)
        )
        items[primaryIndex] = merged

        var superseded = duplicate
        superseded.status = .superseded
        superseded.temporalState = .deprecated
        superseded.conflictGroupId = ""
        superseded.supersededByItemId = merged.id
        items[duplicateIndex] = superseded

        findings.append(GlobalMemoryAuditFinding(
          kind: .duplicate,
          stableKey: merged.stableKey,
          summary: "Equivalent evidence was consolidated into the current memory",
          evidenceCount: merged.evidenceCount
        ))
      }
    }
  }

  private static func consolidateThemes(_ items: [GlobalWorldItem]) -> [GlobalMemoryTheme] {
    var clusters: [[GlobalWorldItem]] = []
    let eligible = items
      .filter { $0.isGlobalMemoryCurrent }
      .filter { $0.layer != .realtime }
      .filter { $0.contextVisibility == .shareable }
      .sorted { $0.lastSeenAtMillis > $1.lastSeenAtMillis }

    for item in eligible {
      let tokens = GlobalAgentText.tokens(item.topic)
      if let index = clusters.firstIndex(where: { cluster in
        cluster.contains { member in
          GlobalMemoryNamespacePolicy.same(item, member) &&
            GlobalAgentText.overlap(tokens, GlobalAgentText.tokens(member.topic)) >= themeTopicOverlap
        }
      }) {
        clusters[index].append(item)
      } else {
        clusters.append([item])
      }
    }

    return clusters.compactMap { cluster -> GlobalMemoryTheme? in
      let evidence = cluster.reduce(0) { $0 + $1.evidenceCount }
      let conversations = GlobalMemoryEvolutionPolicy.uniqueStrings(cluster.flatMap { Array($0.conversationIds) })
      if cluster.count < minThemeItems && conversations.count < minThemeConversations {
        return nil
      }
      guard let title = cluster.max(by: { $0.lastSeenAtMillis < $1.lastSeenAtMillis })?.topic,
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      let confidence: Double
      if cluster.isEmpty {
        confidence = 0.5
      } else {
        confidence = cluster.reduce(0) { $0 + $1.confidence } / Double(cluster.count)
      }
      return GlobalMemoryTheme(
        id: GlobalAgentText.stableKey("memory-theme", cluster[0].memoryNamespaceKey, title),
        title: title,
        itemStableKeys: cluster.map(GlobalMemoryNamespacePolicy.itemKey),
        itemCount: cluster.count,
        evidenceCount: evidence,
        conversationCount: conversations.count,
        confidence: confidence,
        lastUpdatedAtMillis: cluster.map(\.lastSeenAtMillis).max() ?? 0
      )
    }
    .sorted {
      if $0.evidenceCount != $1.evidenceCount { return $0.evidenceCount > $1.evidenceCount }
      return $0.lastUpdatedAtMillis > $1.lastUpdatedAtMillis
    }
    .prefix(maxThemes)
    .map { $0 }
  }

  private static func distinctFindings(_ findings: [GlobalMemoryAuditFinding]) -> [GlobalMemoryAuditFinding] {
    var seen = Set<String>()
    var result: [GlobalMemoryAuditFinding] = []
    for finding in findings {
      let key = "\(finding.kind.rawValue):\(finding.stableKey)"
      if seen.insert(key).inserted {
        result.append(finding)
      }
    }
    return Array(result.prefix(maxFindings))
  }

  private static let auditIntervalMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let pendingReviewWarningMillis: Int64 = 30 * 24 * 60 * 60 * 1_000
  private static let maxFindings = 200
  private static let themeTopicOverlap = 0.42
  private static let minThemeItems = 3
  private static let minThemeConversations = 2
  private static let maxThemes = 80
  private static let maxSupersessionTargets = 12
}

private extension GlobalWorldItem {
  var isGlobalMemoryCurrent: Bool {
    status == .active && [.current, .planned].contains(temporalState)
  }
}
