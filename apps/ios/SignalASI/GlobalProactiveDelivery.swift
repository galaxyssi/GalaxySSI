import Foundation

final class GlobalProactiveDeliveryListener: Hashable {
  private let handler: () -> Void

  init(_ handler: @escaping () -> Void) {
    self.handler = handler
  }

  func onProactiveDeliveryReady() {
    handler()
  }

  static func == (lhs: GlobalProactiveDeliveryListener, rhs: GlobalProactiveDeliveryListener) -> Bool {
    lhs === rhs
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }
}

enum GlobalProactiveDeliveryBus {
  static func addListener(_ listener: GlobalProactiveDeliveryListener) {
    lock.lock()
    listeners.insert(listener)
    lock.unlock()
  }

  static func removeListener(_ listener: GlobalProactiveDeliveryListener) {
    lock.lock()
    listeners.remove(listener)
    lock.unlock()
  }

  static func signalReady() {
    lock.lock()
    let snapshot = Array(listeners)
    lock.unlock()
    for listener in snapshot {
      listener.onProactiveDeliveryReady()
    }
  }

  private static var listeners = Set<GlobalProactiveDeliveryListener>()
  private static let lock = NSLock()
}

enum GlobalProactiveRouteKind: String, Codable, CaseIterable, Identifiable {
  case claimed = "CLAIMED"
  case source = "SOURCE"
  case boundTopic = "BOUND_TOPIC"
  case relatedTopic = "RELATED_TOPIC"
  case titleMatch = "TITLE_MATCH"
  case createTopic = "CREATE_TOPIC"
  case sourceFallback = "SOURCE_FALLBACK"

  var id: String { rawValue }
}

struct GlobalProactiveDeliveryRoute: Codable, Equatable {
  var kind: GlobalProactiveRouteKind
  var conversationId: String
  var createConversation: Bool
  var title: String
  var parentConversationId: String
  var topicKey: String
  var bindTopic: Bool

  init(
    kind: GlobalProactiveRouteKind,
    conversationId: String = "",
    createConversation: Bool = false,
    title: String = "",
    parentConversationId: String = "",
    topicKey: String = "",
    bindTopic: Bool = false
  ) {
    self.kind = kind
    self.conversationId = conversationId
    self.createConversation = createConversation
    self.title = title
    self.parentConversationId = parentConversationId
    self.topicKey = topicKey
    self.bindTopic = bindTopic
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case conversationId = "conversation_id"
    case createConversation = "create_conversation"
    case title
    case parentConversationId = "parent_conversation_id"
    case topicKey = "topic_key"
    case bindTopic = "bind_topic"
  }
}

struct GlobalProactiveTopicNotice: Codable, Equatable {
  var parentConversationId: String
  var destinationConversationId: String
  var dedupeKey: String
  var taskId: String
  var text: String
  var actionLabel: String

  enum CodingKeys: String, CodingKey {
    case parentConversationId = "parent_conversation_id"
    case destinationConversationId = "destination_conversation_id"
    case dedupeKey = "dedupe_key"
    case taskId = "task_id"
    case text
    case actionLabel = "action_label"
  }
}

enum GlobalProactiveTopicNoticePolicy {
  static func create(
    message: GlobalProactiveMessage,
    destination: AgentConversation
  ) -> GlobalProactiveTopicNotice? {
    guard message.target == .newConversation,
          destination.createdByAgent,
          !destination.parentConversationId.isBlank,
          destination.parentConversationId == message.sourceConversationId,
          destination.status == .active else {
      return nil
    }
    let title = String(destination.title.trimmed().nonEmpty ?? message.topic.trimmed()).prefix(160)
    let cleanTitle = String(title).trimmed()
    if cleanTitle.isBlank { return nil }
    let chinese = GlobalAgentText.containsCjk("\(cleanTitle) \(message.content)")
    let text = chinese
      ? "\u{201c}\(cleanTitle)\u{201d}\u{5df2}\u{521b}\u{5efa}\u{4e3a}\u{72ec}\u{7acb}\u{4e13}\u{9898}\u{ff0c}\u{540e}\u{7eed}\u{7814}\u{7a76}\u{548c}\u{7ed3}\u{679c}\u{4f1a}\u{7ee7}\u{7eed}\u{6574}\u{7406}\u{5230}\u{90a3}\u{91cc}\u{3002}"
      : "\(cleanTitle) now has its own topic workspace. Follow-up research and results will continue there."
    return GlobalProactiveTopicNotice(
      parentConversationId: destination.parentConversationId,
      destinationConversationId: destination.id,
      dedupeKey: "global-agent-topic-created:\(destination.id)",
      taskId: "global-agent-topic:\(destination.id)",
      text: text,
      actionLabel: chinese ? "\u{6253}\u{5f00}\u{4e13}\u{9898}" : "Open topic"
    )
  }
}

enum GlobalProactiveConversationRouter {
  static func topicKey(_ topic: String) -> String {
    GlobalAgentText.stableKey("global-topic", topic)
  }

  static func resolve(
    message: GlobalProactiveMessage,
    conversations: [AgentConversation],
    relatedConversationIds: [String] = [],
    autoCreateConversationsEnabled: Bool,
    excludedConversationIds: Set<String> = []
  ) -> GlobalProactiveDeliveryRoute? {
    if excludedConversationIds.contains(message.sourceConversationId) { return nil }
    let eligible = conversations.filter(isEligible)
    let source = conversations.first { $0.id == message.sourceConversationId }
    if let source = source, !isEligible(source) { return nil }

    if !message.deliveryConversationId.isBlank,
       let claimed = eligible.first(where: { $0.id == message.deliveryConversationId }) {
      return GlobalProactiveDeliveryRoute(
        kind: .claimed,
        conversationId: claimed.id,
        topicKey: topicKey(message.topic)
      )
    }

    let stableTopicKey = topicKey(message.topic)
    let topicMatch = selectTopicConversation(
      message: message,
      conversations: eligible,
      relatedConversationIds: relatedConversationIds,
      stableTopicKey: stableTopicKey
    )
    let fallback = source ?? eligible.max { $0.updatedAt < $1.updatedAt }

    switch message.target {
    case .currentConversation:
      if let source = source {
        return GlobalProactiveDeliveryRoute(
          kind: .source,
          conversationId: source.id,
          topicKey: stableTopicKey
        )
      }
      return topicMatch ??
        createRoute(
          message: message,
          stableTopicKey: stableTopicKey,
          enabled: autoCreateConversationsEnabled
        ) ??
        fallback.map {
          GlobalProactiveDeliveryRoute(
            kind: .sourceFallback,
            conversationId: $0.id,
            topicKey: stableTopicKey
          )
        }
    case .newConversation:
      return topicMatch ??
        createRoute(
          message: message,
          stableTopicKey: stableTopicKey,
          enabled: autoCreateConversationsEnabled
        ) ??
        fallback.map {
          GlobalProactiveDeliveryRoute(
            kind: .sourceFallback,
            conversationId: $0.id,
            topicKey: stableTopicKey
          )
        }
    case .globalDigest:
      return nil
    }
  }

  static func isEligible(_ conversation: AgentConversation) -> Bool {
    conversation.status == .active &&
      !conversation.privateMode &&
      !conversation.trackingPaused
  }

  private static func selectTopicConversation(
    message: GlobalProactiveMessage,
    conversations: [AgentConversation],
    relatedConversationIds: [String],
    stableTopicKey: String
  ) -> GlobalProactiveDeliveryRoute? {
    if let bound = conversations
      .filter({ $0.globalTopicKey == stableTopicKey })
      .max(by: { $0.updatedAt < $1.updatedAt }) {
      return GlobalProactiveDeliveryRoute(
        kind: .boundTopic,
        conversationId: bound.id,
        topicKey: stableTopicKey
      )
    }

    if let related = conversations
      .filter({ conversation in
        relatedConversationIds.contains(conversation.id) && conversation.id != message.sourceConversationId
      })
      .sorted(by: { left, right in
        let leftIndex = relatedConversationIds.firstIndex(of: left.id) ?? Int.max
        let rightIndex = relatedConversationIds.firstIndex(of: right.id) ?? Int.max
        if leftIndex != rightIndex { return leftIndex < rightIndex }
        return left.updatedAt > right.updatedAt
      })
      .first {
      return GlobalProactiveDeliveryRoute(
        kind: .relatedTopic,
        conversationId: related.id,
        topicKey: stableTopicKey,
        bindTopic: message.target == .newConversation
      )
    }

    let normalizedTopic = GlobalAgentText.normalize(message.topic)
    let topicTokens = GlobalAgentText.tokens(message.topic)
    let titleMatch = conversations
      .filter { $0.id != message.sourceConversationId }
      .compactMap { conversation -> (AgentConversation, Double)? in
        let normalizedTitle = GlobalAgentText.normalize(conversation.title)
        let exact = !normalizedTopic.isBlank && normalizedTitle == normalizedTopic
        let overlap = GlobalAgentText.overlap(topicTokens, GlobalAgentText.tokens(conversation.title))
        let score: Double
        if exact {
          score = 2.0
        } else if overlap >= minimumTitleOverlap {
          score = overlap
        } else {
          score = 0
        }
        return score > 0 ? (conversation, score) : nil
      }
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.updatedAt > $1.0.updatedAt
      }
      .first?
      .0

    return titleMatch.map {
      GlobalProactiveDeliveryRoute(
        kind: .titleMatch,
        conversationId: $0.id,
        topicKey: stableTopicKey,
        bindTopic: message.target == .newConversation
      )
    }
  }

  private static func createRoute(
    message: GlobalProactiveMessage,
    stableTopicKey: String,
    enabled: Bool
  ) -> GlobalProactiveDeliveryRoute? {
    if !enabled || message.topic.isBlank { return nil }
    return GlobalProactiveDeliveryRoute(
      kind: .createTopic,
      createConversation: true,
      title: message.topic,
      parentConversationId: message.sourceConversationId,
      topicKey: stableTopicKey,
      bindTopic: true
    )
  }

  private static let minimumTitleOverlap = 0.62
}

extension GlobalAgentText {
  static func containsCjk(_ value: String) -> Bool {
    value.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
  }
}

private extension String {
  func trimmed() -> String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
