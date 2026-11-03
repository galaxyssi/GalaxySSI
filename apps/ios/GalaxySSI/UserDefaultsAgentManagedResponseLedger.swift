import Foundation

// Retains the public name for legacy callers; UserDefaults is migration input only.
final class UserDefaultsAgentManagedResponseLedger: AgentManagedResponseLedger {
  static let defaultStorageKey = "galaxyssi_managed_connector_responses_v3"
  private static let processLock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let storageKey: String
  private let nowMillis: () -> Int64
  private let database: AgentManagedResponseDatabase?

  init(defaults: UserDefaults = .standard,
       storageKey: String = UserDefaultsAgentManagedResponseLedger.defaultStorageKey,
       nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
       fileURL: URL = AgentManagedResponseDatabase.defaultFileURL(),
       secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.nowMillis = nowMillis
    database = try? AgentManagedResponseDatabase(fileURL: fileURL, storageKey: storageKey, secrets: secrets)
  }

  func register(_ record: AgentManagedResponseRecord) throws {
    guard !record.ownerRunId.isBlank, record.sourceMessageId > 0 else {
      throw AgentRuntimeCapabilityError.invalid("Managed response records require owner run id and source message id")
    }
    try access { database in
      if let current = try database.owner(record.ownerRunId) {
        guard record.executionGeneration >= current.executionGeneration else {
          throw AgentManagedResponseDatabase.Failure.corrupt
        }
        if current.executionGeneration == record.executionGeneration {
          guard current.sourceMessageId == record.sourceMessageId, current.contactId == record.contactId,
                current.conversationId == record.conversationId, current.turnId == record.turnId,
                current.taskId == record.taskId, current.supervisorRunId == record.supervisorRunId else {
            throw AgentManagedResponseDatabase.Failure.ambiguous
          }
          return
        }
      }
      try database.put(record)
    }
  }

  func ownsResponse(_ response: AgentConnectorResponse) throws -> Bool {
    try access { try $0.matching(response) != nil }
  }

  func complete(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? {
    var notify = false
    let record = try? access { database -> AgentManagedResponseRecord? in
      guard var current = try database.matching(response) else { return nil }
      guard current.state == .pending else { return current }
      current.state = .completed
      current.response = response
      current.completedAtMillis = response.receivedAtMillis
      try database.put(current)
      notify = true
      return current
    }
    if notify, let record { AgentLateManagedResponseBus.shared.publish(record) }
    return record
  }

  func acknowledge(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? {
    try? access { database -> AgentManagedResponseRecord? in
      guard var current = try database.matching(response) else { return nil }
      if current.state == .applied { return current }
      current.state = .applied
      current.response = current.response ?? response
      current.completedAtMillis = max(current.completedAtMillis, response.receivedAtMillis)
      try database.put(current)
      return current
    }
  }

  func pendingForSupervisor(_ supervisorRunId: String) -> [AgentManagedResponseRecord] {
    (try? access { try $0.records(supervisor: supervisorRunId).filter { $0.state == .pending }
      .sorted { $0.createdAtMillis < $1.createdAtMillis } }) ?? []
  }

  func completedUnapplied() -> [AgentManagedResponseRecord] {
    (try? access { try $0.records().filter { $0.state == .completed && $0.response != nil }
      .sorted { $0.completedAtMillis < $1.completedAtMillis } }) ?? []
  }

  func markApplied(ownerRunId: String) {
    _ = try? access { database in
      guard var record = try database.owner(ownerRunId), record.state != .applied else { return }
      record.state = .applied
      try database.put(record)
    }
  }

  func removeOwner(_ ownerRunId: String) { _ = try? access { try $0.remove(owner: ownerRunId) } }

  func clear() {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    guard let database else { return }
    do {
      try database.transaction { try database.clear() }
      defaults.removeObject(forKey: storageKey)
    } catch { return }
  }

  func serializedSnapshot() -> String {
    (try? access { AgentManagedResponseCodec.encode(try $0.records().sorted { $0.createdAtMillis < $1.createdAtMillis }) }) ?? "[]"
  }

  private func access<T>(_ operation: (AgentManagedResponseDatabase) throws -> T) throws -> T {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    guard let database else { throw AgentManagedResponseDatabase.Failure.unavailable }
    let result = try database.transaction {
      if try !database.initialized() {
        if let raw = defaults.string(forKey: storageKey) {
          guard let data = raw.data(using: .utf8),
                let array = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw AgentManagedResponseDatabase.Failure.corrupt
          }
          let records = AgentManagedResponseCodec.decode(raw)
          guard records.count == array.count, Set(records.map(\.ownerRunId)).count == records.count else {
            throw AgentManagedResponseDatabase.Failure.corrupt
          }
          for record in records { try database.put(record) }
        }
        try database.markInitialized()
      }
      try database.pruneApplied(cutoff: max(nowMillis(), 0) - AgentManagedResponseRecord.maxAgeMillis)
      return try operation(database)
    }
    // A committed migration marker prevents legacy resurrection after clear/reopen.
    defaults.removeObject(forKey: storageKey)
    return result
  }
}
