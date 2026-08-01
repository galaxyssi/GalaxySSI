import Foundation

enum GlobalPersistentContextObservationExtractor {
  static func memoryMutations(
    before: [AgentMemoryItem],
    after: [AgentMemoryItem],
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [GlobalConversationEvent] {
    let previous = before.reduce(into: [String: AgentMemoryItem]()) { result, item in
      result[item.id] = item
    }
    let current = after.reduce(into: [String: AgentMemoryItem]()) { result, item in
      result[item.id] = item
    }
    return previous.keys.reduce(into: Set(current.keys)) { result, key in result.insert(key) }
      .sorted()
      .compactMap { itemId in
        let oldItem = previous[itemId]
        let newItem = current[itemId]
        if oldItem == newItem {
          return nil
        }
        if let newItem {
          return memoryUpserted(previous: oldItem, item: newItem, timestampMillis: timestampMillis)
        }
        if let oldItem {
          return memoryDeleted(oldItem, timestampMillis: timestampMillis)
        }
        return nil
      }
  }

  static func knowledgeMutations(
    before: [AgentKnowledgeItem],
    after: [AgentKnowledgeItem],
    timestampMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) -> [GlobalConversationEvent] {
    let previous = knowledgeSources(before)
    let current = knowledgeSources(after)
    return previous.keys.reduce(into: Set(current.keys)) { result, key in result.insert(key) }
      .sorted()
      .compactMap { sourceKey in
        let oldSource = previous[sourceKey]
        let newSource = current[sourceKey]
        if oldSource == newSource {
          return nil
        }
        if let newSource {
          return knowledgeUpserted(previous: oldSource, source: newSource, timestampMillis: timestampMillis)
        }
        if let oldSource {
          return knowledgeDeleted(oldSource, timestampMillis: timestampMillis)
        }
        return nil
      }
  }

  private static func memoryUpserted(
    previous: AgentMemoryItem?,
    item: AgentMemoryItem,
    timestampMillis: Int64
  ) -> GlobalConversationEvent {
    let eventType: GlobalConversationEventType
    if item.status == .conflicted {
      eventType = .memoryConflicted
    } else if previous == nil {
      eventType = .memoryCreated
    } else {
      eventType = .memoryUpdated
    }
    let rootId = memoryRootId(item.id)
    let projection = item.status == .superseded ? "retract_only" : "upsert"
    let conversationId = item.scope == .conversation && !item.scopeId.isBlank ? item.scopeId : memoryConversationId
    let content = projection == "upsert" ? compact(item.value, limit: maxContent) : ""
    return GlobalConversationEvent(
      id: memoryEventId(item),
      type: eventType,
      conversationId: conversationId,
      messageId: item.id,
      actor: .system,
      timestampMillis: timestampMillis,
      content: content,
      contentRef: "encrypted://agent-memory/\(item.id)",
      conversationTitle: "Personal memory",
      topicHints: Set([memoryTopic(item)]),
      metadata: [
        "origin": "agent_memory",
        "memory_id": item.id,
        "memory_root_id": rootId,
        "memory_kind": item.kind.rawValue,
        "memory_scope": item.scope.rawValue,
        "memory_scope_id": String(item.scopeId.prefix(160)),
        "memory_status": item.status.rawValue,
        "memory_topic": memoryTopic(item),
        "memory_source": String(item.source.prefix(120)),
        "version": String(item.version),
        "important": String(item.important),
        "auto_learned": String(item.autoLearned),
        "confidence": String(min(max(item.confidence, 0), 1)),
        "evidence_count": String(max(item.evidenceCount, 1)),
        "expires_at_millis": String(max(item.expiresAtMillis, 0)),
        "conflict_group_id": String(item.conflictGroupId.prefix(160)),
        "context_visibility": memoryContextVisibility(item).rawValue,
        "projection": projection
      ],
      causalEventIds: Set([rootId]),
      retractedEventIds: previous.map { Set([memoryEventId($0)]) } ?? []
    )
  }

  private static func memoryDeleted(
    _ item: AgentMemoryItem,
    timestampMillis: Int64
  ) -> GlobalConversationEvent {
    let rootId = memoryRootId(item.id)
    let conversationId = item.scope == .conversation && !item.scopeId.isBlank ? item.scopeId : memoryConversationId
    return GlobalConversationEvent(
      id: "memory-deleted:\(item.id):\(timestampMillis)",
      type: .memoryDeleted,
      conversationId: conversationId,
      messageId: item.id,
      actor: .system,
      timestampMillis: timestampMillis,
      contentRef: "encrypted://agent-memory/\(item.id)",
      conversationTitle: "Personal memory",
      metadata: [
        "origin": "agent_memory",
        "memory_id": item.id,
        "memory_root_id": rootId,
        "projection": "retract_only"
      ],
      retractedEventIds: Set([rootId, memoryEventId(item)])
    )
  }

  private static func knowledgeUpserted(
    previous: KnowledgeSourceSnapshot?,
    source: KnowledgeSourceSnapshot,
    timestampMillis: Int64
  ) -> GlobalConversationEvent {
    let type: GlobalConversationEventType
    if previous == nil {
      type = .knowledgeImported
    } else if previous?.contentFingerprint == source.contentFingerprint &&
      previous?.accessFingerprint != source.accessFingerprint {
      type = .knowledgeAccessChanged
    } else {
      type = .knowledgeUpdated
    }
    return GlobalConversationEvent(
      id: source.eventId,
      type: type,
      conversationId: knowledgeConversationId,
      messageId: source.sourceKey,
      actor: .system,
      timestampMillis: timestampMillis,
      content: source.observationContent,
      contentRef: "encrypted://agent-knowledge/source/\(source.sourceKey)",
      conversationTitle: "Personal knowledge",
      topicHints: Set([source.title]),
      metadata: [
        "origin": "agent_knowledge",
        "knowledge_source_key": source.sourceKey,
        "knowledge_title": String(source.title.prefix(180)),
        "knowledge_kind": source.kind,
        "source_kind": source.sourceKind,
        "item_count": String(source.itemCount),
        "cloud_access": source.cloudAccess.rawValue,
        "agent_access": source.agentAccess.rawValue,
        "allowed_agent_count": String(source.allowedAgentCount),
        "context_visibility": source.contextVisibility.rawValue,
        "projection": "upsert"
      ],
      causalEventIds: Set([source.rootId]),
      retractedEventIds: previous.map { Set([$0.eventId]) } ?? []
    )
  }

  private static func knowledgeDeleted(
    _ source: KnowledgeSourceSnapshot,
    timestampMillis: Int64
  ) -> GlobalConversationEvent {
    GlobalConversationEvent(
      id: "knowledge-deleted:\(source.sourceKey):\(timestampMillis)",
      type: .knowledgeDeleted,
      conversationId: knowledgeConversationId,
      messageId: source.sourceKey,
      actor: .system,
      timestampMillis: timestampMillis,
      contentRef: "encrypted://agent-knowledge/source/\(source.sourceKey)",
      conversationTitle: "Personal knowledge",
      metadata: [
        "origin": "agent_knowledge",
        "knowledge_source_key": source.sourceKey,
        "projection": "retract_only"
      ],
      retractedEventIds: Set([source.rootId, source.eventId])
    )
  }

  private static func knowledgeSources(_ items: [AgentKnowledgeItem]) -> [String: KnowledgeSourceSnapshot] {
    let grouped = Dictionary(grouping: items, by: knowledgeSourceKey)
    return grouped.mapValues { items in
      knowledgeSourceSnapshot(sourceKey: knowledgeSourceKey(items[0]), items: items)
    }
  }

  private static func knowledgeSourceSnapshot(
    sourceKey: String,
    items: [AgentKnowledgeItem]
  ) -> KnowledgeSourceSnapshot {
    let ordered = items.sorted {
      $0.chunkIndex == $1.chunkIndex ? $0.id < $1.id : $0.chunkIndex < $1.chunkIndex
    }
    let first = ordered[0]
    let title = compact(
      first.title
        .replacingOccurrences(of: #"\s+\[\d+/\d+\]$"#, with: "", options: .regularExpression),
      limit: 180
    ).ifBlank("Knowledge source")
    let summary = ordered
      .map { compact($0.summary, limit: maxKnowledgeSummary) }
      .first { !$0.isBlank } ?? ""
    let tags = ordered
      .flatMap(\.tags)
      .map { compact($0, limit: 80) }
      .filter { !$0.isBlank }
      .stableDistinct()
      .sorted()
      .prefixArray(maxTags)
    let cloudAccess: AgentKnowledgeCloudAccess
    if ordered.contains(where: { $0.cloudAccess == .deny }) {
      cloudAccess = .deny
    } else if ordered.contains(where: { $0.cloudAccess == .summaryOnly }) {
      cloudAccess = .summaryOnly
    } else {
      cloudAccess = .full
    }
    let agentAccess: AgentKnowledgeAgentAccess
    if ordered.contains(where: { $0.agentAccess == .localOnly }) {
      agentAccess = .localOnly
    } else if ordered.contains(where: { $0.agentAccess == .selectedAgents }) {
      agentAccess = .selectedAgents
    } else {
      agentAccess = .anyPairedAgent
    }
    let allowedAgentIds = ordered.flatMap(\.allowedAgentIds).stableDistinct().sorted()
    let contentDigest = GlobalAgentText.privateFingerprint(
      ordered.map { item in
        GlobalAgentText.privateFingerprint([
          item.id,
          item.kind.rawValue,
          item.title,
          item.content,
          item.summary,
          item.tags.joined(separator: "|"),
          String(item.chunkIndex),
          String(item.chunkCount)
        ].joined(separator: "\u{0000}"))
      }.joined(separator: "|")
    )
    let contentFingerprint = GlobalAgentText.stableKey(title, summary, tags.joined(separator: "|"), contentDigest)
    let accessFingerprint = GlobalAgentText.stableKey(
      cloudAccess.rawValue,
      agentAccess.rawValue,
      allowedAgentIds.joined(separator: "|")
    )
    let eventFingerprint = GlobalAgentText.stableKey(contentFingerprint, accessFingerprint)
    let contextVisibility: GlobalWorldContextVisibility =
      cloudAccess != .deny && agentAccess == .anyPairedAgent ? .shareable : .localOnly
    return KnowledgeSourceSnapshot(
      sourceKey: sourceKey,
      rootId: "knowledge-root:\(sourceKey)",
      eventId: "knowledge:\(sourceKey):\(eventFingerprint)",
      title: title,
      summary: summary,
      kind: ordered.map { $0.kind.rawValue }.stableDistinct().sorted().joined(separator: ","),
      sourceKind: sourceKind(first.source),
      itemCount: ordered.count,
      cloudAccess: cloudAccess,
      agentAccess: agentAccess,
      allowedAgentCount: allowedAgentIds.count,
      contextVisibility: contextVisibility,
      contentFingerprint: contentFingerprint,
      accessFingerprint: accessFingerprint,
      tags: tags
    )
  }

  private static func knowledgeSourceKey(_ item: AgentKnowledgeItem) -> String {
    item.source.isBlank
      ? "item-\(GlobalAgentText.stableKey(item.id))"
      : "source-\(GlobalAgentText.stableKey(item.source))"
  }

  private static func sourceKind(_ source: String) -> String {
    let lower = source.lowercased()
    if lower.hasPrefix("https://") { return "https" }
    if lower.hasPrefix("http://") { return "http" }
    if lower.hasPrefix("content://") { return "content" }
    if lower.hasPrefix("file://") { return "file" }
    if lower.hasPrefix("screen:") { return "screen" }
    return source.isBlank ? "internal" : "local"
  }

  private static func memoryTopic(_ item: AgentMemoryItem) -> String {
    compact(item.key, limit: 160).ifBlank(item.kind.rawValue.lowercased())
  }

  private static func memoryContextVisibility(_ item: AgentMemoryItem) -> GlobalWorldContextVisibility {
    switch item.kind {
    case .contact, .safety:
      return .localOnly
    default:
      return .shareable
    }
  }

  private static func memoryRootId(_ itemId: String) -> String {
    "memory-root:\(itemId)"
  }

  private static func memoryEventId(_ item: AgentMemoryItem) -> String {
    let fingerprint = GlobalAgentText.stableKey(
      item.kind.rawValue,
      item.value,
      item.key,
      String(item.version),
      item.status.rawValue,
      item.conflictGroupId,
      item.scope.rawValue,
      item.scopeId,
      String(item.important),
      String(item.confidence),
      String(item.evidenceCount),
      String(item.autoLearned),
      String(item.expiresAtMillis)
    )
    return "memory:\(item.id):\(fingerprint)"
  }

  private static func compact(_ value: String, limit: Int) -> String {
    value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefixString(limit)
  }

  private struct KnowledgeSourceSnapshot: Equatable {
    var sourceKey: String
    var rootId: String
    var eventId: String
    var title: String
    var summary: String
    var kind: String
    var sourceKind: String
    var itemCount: Int
    var cloudAccess: AgentKnowledgeCloudAccess
    var agentAccess: AgentKnowledgeAgentAccess
    var allowedAgentCount: Int
    var contextVisibility: GlobalWorldContextVisibility
    var contentFingerprint: String
    var accessFingerprint: String
    var tags: [String]

    var observationContent: String {
      let suffix = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
      return "\(title)\(summary.isBlank ? "" : ": \(summary)")\(suffix)"
        .prefixString(GlobalPersistentContextObservationExtractor.maxContent)
    }
  }

  private static let memoryConversationId = "global-memory"
  private static let knowledgeConversationId = "knowledge-library"
  private static let maxContent = 1_200
  private static let maxKnowledgeSummary = 640
  private static let maxTags = 12
}

private extension StringProtocol {
  func prefixString(_ limit: Int) -> String {
    String(prefix(Swift.max(limit, 0)))
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
