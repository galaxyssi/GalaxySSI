import Foundation

enum GlobalSemanticEventClass: String, Codable, CaseIterable, Identifiable {
  case message
  case file
  case decision
  case task
  case tool
  case feedback
  case conversation
  case memory
  case knowledge
  case authorization
  case resource

  var id: String { rawValue }
}

struct GlobalEventPublisherDescriptor: Codable, Equatable {
  var publisherId: String
  var semanticClass: GlobalSemanticEventClass
  var eventTypes: Set<GlobalConversationEventType>

  enum CodingKeys: String, CodingKey {
    case publisherId = "publisher_id"
    case semanticClass = "semantic_class"
    case eventTypes = "event_types"
  }
}

struct GlobalEventPublisherAudit: Equatable {
  var missingEventTypes: Set<GlobalConversationEventType>
  var multiplyOwnedEventTypes: Set<GlobalConversationEventType>
  var missingRequiredSemanticClasses: Set<GlobalSemanticEventClass>
  var duplicatePublisherIds: Set<String>

  var complete: Bool {
    missingEventTypes.isEmpty &&
      multiplyOwnedEventTypes.isEmpty &&
      missingRequiredSemanticClasses.isEmpty &&
      duplicatePublisherIds.isEmpty
  }
}

enum GlobalEventPublisherContract {
  static let schemaVersion = "signalasi.global-event.v1"
  static let metadataSchemaVersion = "event_schema"
  static let metadataPublisherId = "publisher_id"
  static let metadataSemanticClass = "semantic_class"

  static let descriptors: [GlobalEventPublisherDescriptor] = [
    descriptor(
      "conversation.message",
      .message,
      .messageCreated,
      .messageUpdated,
      .messageDeleted
    ),
    descriptor(
      "conversation.lifecycle",
      .conversation,
      .conversationCreated,
      .conversationUpdated,
      .conversationMerged,
      .conversationDeleted
    ),
    descriptor(
      "conversation.files",
      .file,
      .attachmentAdded,
      .artifactCreated
    ),
    descriptor(
      "run.tasks",
      .task,
      .taskUpdated
    ),
    descriptor(
      "run.tools",
      .tool,
      .toolStarted,
      .toolCompleted,
      .toolCancelled,
      .toolFailed,
      .toolResult
    ),
    descriptor(
      "cognition.decisions",
      .decision,
      .cognitionResult
    ),
    descriptor(
      "cognition.feedback",
      .feedback,
      .userFeedback
    ),
    descriptor(
      "memory.lifecycle",
      .memory,
      .memoryCreated,
      .memoryUpdated,
      .memoryConflicted,
      .memoryDeleted
    ),
    descriptor(
      "knowledge.lifecycle",
      .knowledge,
      .knowledgeImported,
      .knowledgeUpdated,
      .knowledgeAccessChanged,
      .knowledgeDeleted
    ),
    descriptor(
      "authorization.lifecycle",
      .authorization,
      .authorizationGranted,
      .authorizationRevoked,
      .authorizationPolicyChanged
    ),
    descriptor(
      "resource.lifecycle",
      .resource,
      .resourceRegistered,
      .resourceUpdated,
      .resourceRemoved,
      .resourceStateChanged,
      .capabilitySnapshotReset
    )
  ]

  static func descriptor(for type: GlobalConversationEventType) -> GlobalEventPublisherDescriptor? {
    let matches = descriptors.filter { $0.eventTypes.contains(type) }
    return matches.count == 1 ? matches[0] : nil
  }

  static func canonicalMetadata(_ event: GlobalConversationEvent) -> [String: String] {
    guard let descriptor = descriptor(for: event.type) else {
      return event.metadata
    }
    var metadata = event.metadata.filter { !canonicalMetadataKeys.contains($0.key) }
    metadata[metadataSchemaVersion] = schemaVersion
    metadata[metadataPublisherId] = descriptor.publisherId
    metadata[metadataSemanticClass] = descriptor.semanticClass.rawValue
    return metadata
  }

  static func isAuthorizedForGlobalStream(_ event: GlobalConversationEvent) -> Bool {
    if controlEventTypes.contains(event.type) {
      return true
    }
    let normalized = normalizedMetadataKeys(event.metadata)
    let authorizationState = [
      normalized["authorization_state"],
      normalized["permission_state"],
      normalized["consent_state"]
    ]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }?
      .lowercased() ?? ""
    return !deniedAuthorizationStates.contains(authorizationState)
  }

  static func requiresLifecycleSanitization(_ event: GlobalConversationEvent) -> Bool {
    let normalized = normalizedMetadataKeys(event.metadata)
    return normalized["global_visibility"]?.caseInsensitiveCompare("excluded") == .orderedSame ||
      normalized["private_mode"]?.caseInsensitiveCompare("true") == .orderedSame ||
      normalized["tracking_paused"]?.caseInsensitiveCompare("true") == .orderedSame
  }

  static func audit() -> GlobalEventPublisherAudit {
    let owners = Dictionary(uniqueKeysWithValues: GlobalConversationEventType.allCases.map { type in
      (type, descriptors.filter { $0.eventTypes.contains(type) }.count)
    })
    let publisherCounts = Dictionary(grouping: descriptors.map(\.publisherId), by: { $0 })
      .mapValues { $0.count }
    return GlobalEventPublisherAudit(
      missingEventTypes: Set(owners.filter { $0.value == 0 }.map(\.key)),
      multiplyOwnedEventTypes: Set(owners.filter { $0.value > 1 }.map(\.key)),
      missingRequiredSemanticClasses: requiredSemanticClasses.subtracting(Set(descriptors.map(\.semanticClass))),
      duplicatePublisherIds: Set(publisherCounts.filter { $0.value > 1 }.map(\.key))
    )
  }

  private static func descriptor(
    _ publisherId: String,
    _ semanticClass: GlobalSemanticEventClass,
    _ eventTypes: GlobalConversationEventType...
  ) -> GlobalEventPublisherDescriptor {
    GlobalEventPublisherDescriptor(
      publisherId: publisherId,
      semanticClass: semanticClass,
      eventTypes: Set(eventTypes)
    )
  }

  private static func normalizedMetadataKeys(_ metadata: [String: String]) -> [String: String] {
    metadata.reduce(into: [:]) { result, entry in
      result[normalizedMetadataKey(entry.key)] = entry.value
    }
  }

  private static func normalizedMetadataKey(_ key: String) -> String {
    key.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
  }

  private static let requiredSemanticClasses: Set<GlobalSemanticEventClass> = [
    .message,
    .file,
    .decision,
    .task,
    .tool,
    .feedback
  ]
  private static let controlEventTypes: Set<GlobalConversationEventType> = [
    .messageDeleted,
    .conversationUpdated,
    .conversationMerged,
    .conversationDeleted,
    .memoryDeleted,
    .knowledgeAccessChanged,
    .knowledgeDeleted,
    .authorizationGranted,
    .authorizationRevoked,
    .authorizationPolicyChanged,
    .resourceRemoved,
    .capabilitySnapshotReset
  ]
  private static let deniedAuthorizationStates: Set<String> = [
    "blocked",
    "denied",
    "disallowed",
    "expired",
    "rejected",
    "revoked",
    "unauthorized"
  ]
  private static let canonicalMetadataKeys: Set<String> = [
    metadataSchemaVersion,
    metadataPublisherId,
    metadataSemanticClass
  ]
}

enum GlobalConversationEventPolicy {
  static func normalize(_ event: GlobalConversationEvent) -> GlobalConversationEvent? {
    let id = boundedIdentifier(event.id)
    let conversationId = boundedIdentifier(event.conversationId)
    guard !id.isEmpty, !conversationId.isEmpty else {
      return nil
    }
    let lifecycleOnly = event.sensitivity == .sessionPrivate ||
      GlobalEventPublisherContract.requiresLifecycleSanitization(event)
    if lifecycleOnly && event.type == .conversationDeleted {
      return nil
    }
    if lifecycleOnly && !privateLifecycleEventTypes.contains(event.type) {
      return nil
    }
    if !lifecycleOnly && !GlobalEventPublisherContract.isAuthorizedForGlobalStream(event) {
      return nil
    }

    let sourceMetadata = lifecycleOnly
      ? event.metadata
      : GlobalEventPublisherContract.canonicalMetadata(event)
    var normalized = event
    normalized.id = id
    normalized.conversationId = conversationId
    normalized.messageId = boundedIdentifier(event.messageId)
    normalized.timestampMillis = max(event.timestampMillis, 0)
    normalized.content = lifecycleOnly ? "" : cleanText(event.content, maximumCharacters: maxContentCharacters)
    normalized.contentRef = lifecycleOnly ? "" : sanitizeContentRef(event.contentRef)
    normalized.conversationTitle = lifecycleOnly ? "" : cleanText(
      event.conversationTitle,
      maximumCharacters: maxTitleCharacters
    )
    normalized.topicHints = lifecycleOnly ? [] : normalizeTopicHints(event.topicHints)
    normalized.sensitivity = lifecycleOnly ? .sessionPrivate : event.sensitivity
    normalized.metadata = normalizeMetadata(sourceMetadata, sessionPrivate: lifecycleOnly)
    normalized.causalEventIds = normalizeIdentifiers(event.causalEventIds)
    normalized.retractedEventIds = normalizeIdentifiers(event.retractedEventIds)
    return normalized
  }

  private static func normalizeMetadata(
    _ metadata: [String: String],
    sessionPrivate: Bool
  ) -> [String: String] {
    var result: [String: String] = [:]
    let priorityKeys = sessionPrivate ? [] : canonicalMetadataKeyOrder.filter { metadata.keys.contains($0) }
    let priorityKeySet = Set(priorityKeys)
    let orderedKeys = priorityKeys + metadata.keys.filter { !priorityKeySet.contains($0) }.sorted()
    for rawKey in orderedKeys {
      let key = String(rawKey.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxMetadataKeyCharacters))
      guard !key.isEmpty, !credentialKey(key) else {
        continue
      }
      if sessionPrivate && !privateLifecycleMetadataKeys.contains(key.lowercased()) {
        continue
      }
      if priorityKeySet.contains(key), result[key] != nil {
        continue
      }
      if result[key] == nil && result.count >= maxMetadataEntries {
        continue
      }
      result[key] = cleanText(metadata[rawKey] ?? "", maximumCharacters: maxMetadataValueCharacters)
    }
    return result
  }

  private static func normalizeIdentifiers(_ values: Set<String>) -> Set<String> {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values.map(boundedIdentifier).filter({ !$0.isEmpty }).sorted() where seen.insert(value).inserted {
      result.append(value)
      if result.count == maxCausalIdentifiers {
        break
      }
    }
    return Set(result)
  }

  private static func boundedIdentifier(_ value: String) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxIdentifierCharacters))
  }

  private static func cleanText(_ value: String, maximumCharacters: Int) -> String {
    var controlCleaned = ""
    for scalar in value.unicodeScalars {
      if strippedControlCharacters.contains(Int(scalar.value)) {
        controlCleaned.append(" ")
      } else {
        controlCleaned.unicodeScalars.append(scalar)
      }
    }
    let collapsed = controlCleaned
      .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return String(collapsed.prefix(maximumCharacters))
  }

  private static func sanitizeContentRef(_ value: String) -> String {
    var clean = cleanText(value, maximumCharacters: maxContentRefCharacters)
    guard !clean.isEmpty, !clean.hasPrefix("encrypted://") else {
      return clean
    }
    if let query = clean.firstIndex(of: "?") {
      clean = String(clean[..<query])
    }
    if let fragment = clean.firstIndex(of: "#") {
      clean = String(clean[..<fragment])
    }
    return String(clean.prefix(maxContentRefCharacters))
  }

  private static func normalizeTopicHints(_ values: Set<String>) -> Set<String> {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values
      .map({ cleanText($0, maximumCharacters: maxTopicHintCharacters) })
      .filter({ !$0.isEmpty })
      .sorted() where seen.insert(value).inserted {
      result.append(value)
      if result.count == maxTopicHints {
        break
      }
    }
    return Set(result)
  }

  private static func credentialKey(_ key: String) -> Bool {
    let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
    return credentialKeys.contains(normalized) ||
      credentialSuffixes.contains(where: normalized.hasSuffix)
  }

  private static let credentialKeys: Set<String> = [
    "access_token",
    "api_key",
    "apikey",
    "authorization",
    "bearer",
    "client_secret",
    "cookie",
    "credential",
    "credentials",
    "password",
    "passwd",
    "private_key",
    "refresh_token",
    "secret",
    "set_cookie",
    "token"
  ]
  private static let credentialSuffixes: Set<String> = [
    "_access_token",
    "_api_key",
    "_apikey",
    "_client_secret",
    "_credential",
    "_password",
    "_private_key",
    "_refresh_token",
    "_secret",
    "_token"
  ]
  private static let privateLifecycleMetadataKeys: Set<String> = [
    "changed_fields",
    "conversation_status",
    "created_by_agent",
    "global_visibility",
    "merged_at_millis",
    "merged_into_conversation_id",
    "origin",
    "parent_conversation_id",
    "private_mode",
    "tracking_paused"
  ]
  private static let privateLifecycleEventTypes: Set<GlobalConversationEventType> = [
    .conversationUpdated
  ]
  private static let canonicalMetadataKeyOrder = [
    GlobalEventPublisherContract.metadataSchemaVersion,
    GlobalEventPublisherContract.metadataPublisherId,
    GlobalEventPublisherContract.metadataSemanticClass
  ]
  private static let strippedControlCharacters = Set(
    Array(0...8) + [11, 12] + Array(14...31)
  )
  private static let maxIdentifierCharacters = 512
  private static let maxContentCharacters = 12_000
  private static let maxContentRefCharacters = 1_024
  private static let maxTitleCharacters = 160
  private static let maxTopicHints = 16
  private static let maxTopicHintCharacters = 160
  private static let maxMetadataEntries = 48
  private static let maxMetadataKeyCharacters = 64
  private static let maxMetadataValueCharacters = 1_024
  private static let maxCausalIdentifiers = 128
}
