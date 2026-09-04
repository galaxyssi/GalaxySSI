import Foundation

final class UserDefaultsAgentTerminalDeliveryStore: AgentTerminalDeliveryStoring {
  static let defaultStorageKey = "galaxyssi_agent_terminal_deliveries"

  private let defaults: UserDefaults
  private let storageKey: String
  private let secrets: GalaxySSISecretStore
  private static let persistenceLock = NSRecursiveLock()
  private var store: InMemoryAgentTerminalDeliveryStore

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentTerminalDeliveryStore.defaultStorageKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.secrets = secrets
    store = InMemoryAgentTerminalDeliveryStore(records: Self.loadRecords(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ))
  }

  func mark(_ delivery: AgentTerminalDelivery) {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    store.mark(delivery)
    persistLocked()
  }

  func find(sourceMessageId: Int64) -> AgentTerminalDelivery? {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    return store.find(sourceMessageId: sourceMessageId)
  }

  func isTerminal(_ response: AgentConnectorResponse) -> Bool {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    return store.isTerminal(response)
  }

  func records() -> [AgentTerminalDelivery] {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    reloadLocked()
    return store.records()
  }

  func clear() {
    Self.persistenceLock.lock()
    defer { Self.persistenceLock.unlock() }
    store.clear()
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: storageKey, secrets: secrets)
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentTerminalDeliveryStore.defaultStorageKey,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    persistenceLock.lock()
    defer { persistenceLock.unlock() }
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  private func persistLocked() {
    guard let data = try? JSONEncoder().encode(store.records()) else { return }
    _ = GalaxySSIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  private func reloadLocked() {
    store = InMemoryAgentTerminalDeliveryStore(records: Self.loadRecords(
      defaults: defaults,
      storageKey: storageKey,
      secrets: secrets
    ))
  }

  private static func loadRecords(
    defaults: UserDefaults,
    storageKey: String,
    secrets: GalaxySSISecretStore
  ) -> [AgentTerminalDelivery] {
    GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    ).flatMap { try? JSONDecoder().decode([AgentTerminalDelivery].self, from: $0) } ?? []
  }
}

final class UserDefaultsAgentConnectorResponseStore: AgentConnectorResponseSink {
  static let defaultStorageKey = "galaxyssi_agent_connector_responses"

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
