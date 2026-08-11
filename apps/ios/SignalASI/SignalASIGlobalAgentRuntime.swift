import Foundation

final class SignalASIGlobalLongHorizonRuntimeStore: GlobalLongHorizonRuntimeStore {
  private var settingsValue: GlobalAgentSettings
  private var worldValue: PersonalWorldModel
  private let graphValue: GlobalTopicProjectGraph
  private let deliberationStore: GlobalAgentDeliberationStore
  private(set) var emittedProactiveMessages: [GlobalProactiveMessage] = []

  init(
    settings: GlobalAgentSettings,
    world: PersonalWorldModel,
    topicGraph: GlobalTopicProjectGraph,
    deliberationStore: GlobalAgentDeliberationStore = GlobalAgentDeliberationStore()
  ) {
    self.settingsValue = settings
    self.worldValue = world
    self.graphValue = topicGraph
    self.deliberationStore = deliberationStore
  }

  func settings() -> GlobalAgentSettings {
    settingsValue
  }

  func loadWorld() -> PersonalWorldModel {
    worldValue
  }

  func saveWorld(_ world: PersonalWorldModel) {
    worldValue = world
  }

  func topicGraph() -> GlobalTopicProjectGraph {
    graphValue
  }

  func cognitionTasks() -> [GlobalCognitionTask] {
    deliberationStore.cognitionTasks()
  }

  func upsertCognitionTask(_ task: GlobalCognitionTask) {
    deliberationStore.upsertCognitionTask(task)
  }

  func autonomousRuns() -> [GlobalAutonomousRun] {
    deliberationStore.autonomousRuns()
  }

  func appendProactiveMessage(_ message: GlobalProactiveMessage) {
    guard !emittedProactiveMessages.contains(where: { $0.id == message.id }) else { return }
    emittedProactiveMessages.append(message)
  }
}

@MainActor
enum SignalASIGlobalAgentRuntimeBridge {
  @discardableResult
  static func processLongHorizonCycle(
    store: SignalASIStore,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalLongHorizonCycleResult {
    let runtimeStore = SignalASIGlobalLongHorizonRuntimeStore(
      settings: store.globalAgentSettings,
      world: worldModel(from: store.agentMemorySnapshot(), nowMillis: nowMillis),
      topicGraph: topicGraph(from: store.agentSessions(includeArchived: true), nowMillis: nowMillis)
    )
    let coordinator = GlobalLongHorizonCoordinator(runtimeStore: runtimeStore)
    let result = coordinator.processDue(nowMillis: nowMillis)
    runtimeStore.emittedProactiveMessages.forEach { store.appendGlobalProactiveMessage($0) }
    return result
  }

  private static func worldModel(
    from snapshot: AgentMemorySnapshot,
    nowMillis: Int64
  ) -> PersonalWorldModel {
    let items = snapshot.activeItems.compactMap { item -> GlobalWorldItem? in
      let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return nil }
      let topic = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
        .ifBlank(item.kind.rawValue.lowercased())
      let conversationIds = item.scope == .conversation && !item.scopeId.isBlank
        ? Set([item.scopeId])
        : []
      let timestamp = max(item.timestampMillis, 0)
      return GlobalWorldItem(
        id: item.id,
        stableKey: GlobalAgentText.stableKey("ios-memory", item.kind.rawValue, topic, value),
        kind: worldKind(for: item.kind),
        layer: item.scope == .conversation ? .conversation : .user,
        namespace: worldNamespace(for: item.scope),
        namespaceId: item.scopeId,
        topic: topic,
        value: value,
        confidence: item.confidence,
        contextVisibility: item.scope == .conversation ? .localOnly : .shareable,
        evidenceCount: item.evidenceCount,
        conversationIds: conversationIds,
        evidenceEventIds: [item.id],
        evidenceProvenance: [GlobalEvidenceRef(
          eventId: item.id,
          conversationId: item.scopeId,
          timestampMillis: timestamp
        )],
        status: item.status == .conflicted ? .conflicted : .active,
        temporalState: .current,
        conflictGroupId: item.conflictGroupId,
        firstSeenAtMillis: timestamp,
        lastSeenAtMillis: max(item.lastAccessedAtMillis, timestamp),
        expiresAtMillis: item.expiresAtMillis
      )
    }
    return PersonalWorldModel(items: items, updatedAtMillis: max(nowMillis, 0))
  }

  private static func topicGraph(
    from conversations: [AgentConversation],
    nowMillis: Int64
  ) -> GlobalTopicProjectGraph {
    let nodes = conversations.compactMap { conversation -> GlobalTopicNode? in
      let topicKey = conversation.globalTopicKey.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !topicKey.isEmpty else { return nil }
      let timestamp = max(conversation.updatedAt, conversation.createdAt)
      return GlobalTopicNode(
        id: topicKey,
        stableKey: topicKey,
        name: conversation.title,
        kind: conversation.createdByAgent ? .project : .topic,
        status: conversation.status == .archived ? .archived : .active,
        conversationIds: [conversation.id],
        confidence: 0.85,
        firstSeenAtMillis: max(conversation.createdAt, 0),
        lastSeenAtMillis: max(timestamp, 0)
      )
    }
    return GlobalTopicProjectGraph(nodes: nodes, updatedAtMillis: max(nowMillis, 0))
  }

  private static func worldKind(for kind: AgentMemoryKind) -> GlobalWorldItemKind {
    switch kind {
    case .preference:
      return .preference
    case .task, .workflow:
      return .task
    case .identity, .contact, .knowledge, .safety:
      return .fact
    }
  }

  private static func worldNamespace(for scope: AgentMemoryScope) -> GlobalMemoryNamespace {
    switch scope {
    case .device:
      return .device
    case .workspace, .application:
      return .project
    case .contact, .conversation, .global:
      return .user
    }
  }
}
