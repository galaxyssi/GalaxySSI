import Foundation

final class UserDefaultsAgentConnectorResponseStore: AgentConnectorResponseSink {
  static let defaultStorageKey = "signalasi_agent_connector_responses"

  private let defaults: UserDefaults
  private let storageKey: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()
  private let store: AgentConnectorResponseStore

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentConnectorResponseStore.defaultStorageKey,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.nowMillis = nowMillis
    self.store = AgentConnectorResponseStore(
      serialized: defaults.string(forKey: storageKey) ?? "[]",
      nowMillis: nowMillis
    )
  }

  @discardableResult
  func publish(_ response: AgentConnectorResponse) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let accepted = store.publish(response)
    persistLocked()
    return accepted
  }

  func pending() -> [AgentConnectorResponse] {
    lock.lock()
    defer { lock.unlock() }
    let responses = store.pending(nowMillis: nowMillis())
    persistLocked()
    return responses
  }

  func remove(_ response: AgentConnectorResponse) {
    lock.lock()
    defer { lock.unlock() }
    store.remove(response)
    persistLocked()
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    store.clear()
    defaults.removeObject(forKey: storageKey)
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    persistLocked()
    return store.serializedSnapshot()
  }

  private func persistLocked() {
    defaults.set(store.serializedSnapshot(), forKey: storageKey)
  }
}
