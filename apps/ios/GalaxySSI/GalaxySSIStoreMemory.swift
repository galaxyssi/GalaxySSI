import Foundation

extension GalaxySSIStore {
  @discardableResult
  func captureExplicitAgentCoreMemory(
    _ content: String,
    conversationId: String,
    contactId: String
  ) -> [AgentMemoryItem] {
    guard let contact = contact(id: contactId),
          contact.id == "hermes" || contact.type == "agent" || contact.deliveryMode == .cloudAPI,
          let session = agentSession(id: conversationId),
          !session.privateMode,
          !session.trackingPaused else { return [] }
    let captured = AgentIOSCoreMemoryCoordinator(store: agentMemoryStore).captureExplicit(content)
    if !captured.isEmpty {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return captured
  }

  func agentCoreMemoryContext(maximumCharacters: Int = 1_800) -> String {
    AgentIOSCoreMemoryCoordinator(store: agentMemoryStore)
      .compilePrompt(maximumCharacters: maximumCharacters)
  }

  func exportAgentMemoryItems() -> [AgentMemoryItem] {
    agentMemoryStore.exportItems()
  }

  func agentMemorySnapshot() -> AgentMemorySnapshot {
    agentMemoryStore.snapshot()
  }

  func agentMemoryDeletionTombstones() -> [AgentMemoryDeletionTombstone] {
    memoryDeletionIndex.snapshot()
  }




  @discardableResult
  func rememberAgentMemory(_ item: AgentMemoryItem) -> AgentMemoryWriteResult {
    let result = agentMemoryStore.remember(item)
    agentMemoryItems = agentMemoryStore.exportItems()
    return result
  }

  @discardableResult
  func updateAgentMemory(id itemId: String, value: String, key: String) -> AgentMemoryWriteResult? {
    let result = agentMemoryStore.update(itemId: itemId, value: value, key: key)
    if result != nil {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return result
  }

  @discardableResult
  func setAgentMemoryImportant(id itemId: String, important: Bool) -> Bool {
    let changed = agentMemoryStore.setImportant(itemId: itemId, important: important)
    if changed {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return changed
  }

  @discardableResult
  func resolveAgentMemoryConflict(groupId: String, selectedItemId: String, mergedValue: String?) -> AgentMemoryItem? {
    let resolved = agentMemoryStore.resolveConflict(
      groupId: groupId,
      selectedItemId: selectedItemId,
      mergedValue: mergedValue
    )
    if resolved != nil {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return resolved
  }

  @discardableResult
  func replaceAgentMemoryItems(_ items: [AgentMemoryItem]) -> Int {
    let count = agentMemoryStore.replaceAll(items)
    agentMemoryItems = agentMemoryStore.exportItems()
    return count
  }

  @discardableResult
  func deleteAgentMemory(id itemId: String, deletedAtMillis: Int64 = AgentMemoryClock.nowMillis()) -> Bool {
    let deleted = agentMemoryStore.deleteById(itemId, deletedAtMillis: deletedAtMillis)
    if deleted {
      agentMemoryItems = agentMemoryStore.exportItems()
    }
    return deleted
  }
}
