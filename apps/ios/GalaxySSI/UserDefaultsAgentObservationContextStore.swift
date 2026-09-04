import Foundation

final class UserDefaultsAgentObservationContextStore: AgentObservationContextStore {
  static let defaultStorageKey = "galaxyssi_agent_observation_context_v1"

  private let defaults: UserDefaults
  private let storageKey: String
  private let clock: () -> Int64
  private let idFactory: () -> String
  private let lock = NSRecursiveLock()
  private var document: String

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentObservationContextStore.defaultStorageKey,
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
    idFactory: @escaping () -> String = { UUID().uuidString }
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.clock = clock
    self.idFactory = idFactory
    self.document = defaults.string(forKey: storageKey) ?? "[]"
    let now = max(clock(), 0)
    self.document = AgentObservationContextJsonCodec.encode(
      AgentObservationContextJsonCodec.decode(self.document, nowMillis: now)
    )
  }

  func observe(
    targetId: String,
    text: String,
    conversationId: String = "",
    taskId: String = ""
  ) -> AgentObservedContext? {
    lock.lock()
    defer { lock.unlock() }
    let now = max(clock(), 0)
    let entry = AgentObservedContext(
      id: idFactory(),
      targetId: targetId,
      text: text,
      conversationId: conversationId,
      taskId: taskId,
      createdAtMillis: now,
      expiresAtMillis: now + AgentObservedContext.defaultTTLMillis
    )
    guard entry.isUsable else {
      return nil
    }
    let current = load(nowMillis: now).filter { existing in
      !(existing.targetId == entry.targetId &&
        existing.text == entry.text &&
        existing.conversationId == entry.conversationId)
    }
    let otherTargets = current.filter { $0.targetId != entry.targetId }
    let targetEntries = Array((current.filter { $0.targetId == entry.targetId } + [entry])
      .suffix(AgentObservedContext.maxEntriesPerTarget))
    let bounded = Array((otherTargets + targetEntries)
      .sorted { $0.createdAtMillis < $1.createdAtMillis }
      .suffix(AgentObservedContext.maxTotalEntries))
    save(bounded)
    return entry
  }

  func peek(targetId: String, conversationId: String = "") -> [AgentObservedContext] {
    lock.lock()
    defer { lock.unlock() }
    let cleanTarget = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanConversation = conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    return Array(load(nowMillis: max(clock(), 0)).filter { entry in
      entry.targetId == cleanTarget &&
        (cleanConversation.isEmpty || entry.conversationId.isEmpty || entry.conversationId == cleanConversation)
    }.suffix(AgentObservedContext.maxEntriesPerTarget))
  }

  func acknowledge(entryIds: Set<String>) -> Int {
    lock.lock()
    defer { lock.unlock() }
    guard !entryIds.isEmpty else {
      return 0
    }
    let current = load(nowMillis: max(clock(), 0))
    let remaining = current.filter { !entryIds.contains($0.id) }
    guard remaining.count != current.count else {
      return 0
    }
    save(remaining)
    return current.count - remaining.count
  }

  func clearTarget(_ targetId: String) -> Int {
    lock.lock()
    defer { lock.unlock() }
    let cleanTarget = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    let current = load(nowMillis: max(clock(), 0))
    let remaining = current.filter { $0.targetId != cleanTarget }
    guard remaining.count != current.count else {
      return 0
    }
    save(remaining)
    return current.count - remaining.count
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    document = "[]"
    defaults.removeObject(forKey: storageKey)
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    let current = load(nowMillis: max(clock(), 0))
    save(current)
    return document
  }

  private func load(nowMillis: Int64) -> [AgentObservedContext] {
    let decoded = AgentObservationContextJsonCodec.decode(document, nowMillis: nowMillis)
    let normalized = AgentObservationContextJsonCodec.encode(decoded)
    if normalized != document {
      document = normalized
      defaults.set(normalized, forKey: storageKey)
    }
    return decoded
  }

  private func save(_ items: [AgentObservedContext]) {
    document = AgentObservationContextJsonCodec.encode(items)
    defaults.set(document, forKey: storageKey)
  }
}
