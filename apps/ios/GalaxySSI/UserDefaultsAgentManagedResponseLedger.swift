import Foundation

final class UserDefaultsAgentManagedResponseLedger: AgentManagedResponseLedger {
  static let defaultStorageKey = "galaxyssi_managed_connector_responses_v3"
  static let maxRecords = 512

  private let defaults: UserDefaults
  private let storageKey: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()
  private var records: [String: AgentManagedResponseRecord]

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = UserDefaultsAgentManagedResponseLedger.defaultStorageKey,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.nowMillis = nowMillis
    let decoded = AgentManagedResponseCodec.decode(defaults.string(forKey: storageKey) ?? "[]")
    self.records = decoded.reduce(into: [:]) { result, record in
      result[record.ownerRunId] = record
    }
    self.records = self.records.filter { !$0.value.isStale(nowMillis: max(nowMillis(), 0)) }
  }

  func register(_ record: AgentManagedResponseRecord) throws {
    guard !record.ownerRunId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      record.sourceMessageId > 0 else {
      throw AgentRuntimeCapabilityError.invalid("Managed response records require owner run id and source message id")
    }
    lock.lock()
    defer { lock.unlock() }
    pruneStaleLocked()
    records[record.ownerRunId] = record
    persistLocked()
  }

  func complete(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? {
    lock.lock()
    pruneStaleLocked()
    guard let key = records.first(where: { $0.value.correlates(response) })?.key else {
      lock.unlock()
      return nil
    }
    let current = records[key]!
    guard current.state == .pending else {
      lock.unlock()
      return current
    }
    let completed = AgentManagedResponseRecord(
      ownerRunId: current.ownerRunId,
      supervisorRunId: current.supervisorRunId,
      agentId: current.agentId,
      deliveryMode: current.deliveryMode,
      sourceMessageId: current.sourceMessageId,
      contactId: current.contactId,
      conversationId: current.conversationId,
      turnId: current.turnId,
      taskId: current.taskId,
      state: .completed,
      response: response,
      createdAtMillis: current.createdAtMillis,
      completedAtMillis: response.receivedAtMillis
    )
    records[key] = completed
    persistLocked()
    lock.unlock()
    AgentLateManagedResponseBus.shared.publish(completed)
    return completed
  }

  func acknowledge(_ response: AgentConnectorResponse) -> AgentManagedResponseRecord? {
    lock.lock()
    defer { lock.unlock() }
    pruneStaleLocked()
    guard let key = records.first(where: { $0.value.correlates(response) })?.key else {
      return nil
    }
    let current = records[key]!
    let acknowledged = AgentManagedResponseRecord(
      ownerRunId: current.ownerRunId,
      supervisorRunId: current.supervisorRunId,
      agentId: current.agentId,
      deliveryMode: current.deliveryMode,
      sourceMessageId: current.sourceMessageId,
      contactId: current.contactId,
      conversationId: current.conversationId,
      turnId: current.turnId,
      taskId: current.taskId,
      state: .applied,
      response: response,
      createdAtMillis: current.createdAtMillis,
      completedAtMillis: response.receivedAtMillis
    )
    records[key] = acknowledged
    persistLocked()
    return acknowledged
  }

  func pendingForSupervisor(_ supervisorRunId: String) -> [AgentManagedResponseRecord] {
    lock.lock()
    defer { lock.unlock() }
    pruneStaleLocked()
    return records.values
      .filter { $0.supervisorRunId == supervisorRunId && $0.state == .pending }
      .sorted { $0.createdAtMillis < $1.createdAtMillis }
  }

  func completedUnapplied() -> [AgentManagedResponseRecord] {
    lock.lock()
    defer { lock.unlock() }
    pruneStaleLocked()
    return records.values
      .filter { $0.state == .completed && $0.response != nil }
      .sorted { $0.completedAtMillis < $1.completedAtMillis }
  }

  func markApplied(ownerRunId: String) {
    lock.lock()
    defer { lock.unlock() }
    guard var record = records[ownerRunId], record.state != .applied else {
      return
    }
    record.state = .applied
    records[ownerRunId] = record
    persistLocked()
  }

  func removeOwner(_ ownerRunId: String) {
    lock.lock()
    defer { lock.unlock() }
    guard records.removeValue(forKey: ownerRunId) != nil else {
      return
    }
    persistLocked()
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    records.removeAll()
    defaults.removeObject(forKey: storageKey)
  }

  func serializedSnapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    pruneStaleLocked()
    return AgentManagedResponseCodec.encode(records.values.sorted { $0.createdAtMillis < $1.createdAtMillis })
  }

  private func pruneStaleLocked() {
    let now = max(nowMillis(), 0)
    let active = records.filter { !$0.value.isStale(nowMillis: now) }
    guard active.count != records.count else {
      return
    }
    records = active
    persistLocked()
  }

  private func persistLocked() {
    let ordered = records.values.sorted {
      max($0.createdAtMillis, $0.completedAtMillis) < max($1.createdAtMillis, $1.completedAtMillis)
    }
    defaults.set(
      AgentManagedResponseCodec.encode(Array(ordered.suffix(Self.maxRecords))),
      forKey: storageKey
    )
  }
}
