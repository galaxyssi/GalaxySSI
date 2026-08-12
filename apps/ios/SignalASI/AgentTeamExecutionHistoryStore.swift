import Foundation

extension Notification.Name {
  static let signalASIAgentTeamExecutionHistoryDidUpdate = Notification.Name(
    "signalasi.agentTeamExecutionHistoryDidUpdate"
  )
}

final class AgentTeamExecutionHistoryStore {
  static let shared = AgentTeamExecutionHistoryStore()
  static let defaultStorageKey = "signalasi.agent_team_execution_history_v1"
  static let defaultRecentLimit = 20
  static let maxSnapshots = 200

  private let defaults: UserDefaults
  private let storageKey: String
  private let secrets: SignalASISecretStore
  private let lock = NSRecursiveLock()
  private var snapshotsByRunId: [String: AgentTeamExecutionSnapshot]

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = AgentTeamExecutionHistoryStore.defaultStorageKey,
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.secrets = secrets
    let data = SignalASIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    ) ?? defaults.data(forKey: storageKey)
    let restored = data.flatMap { try? JSONDecoder().decode([AgentTeamExecutionSnapshot].self, from: $0) } ?? []
    self.snapshotsByRunId = Self.normalized(restored)
  }

  static func destroyPersistentStore(
    defaults: UserDefaults = .standard,
    storageKey: String = AgentTeamExecutionHistoryStore.defaultStorageKey,
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    SignalASIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  func upsert(_ snapshot: AgentTeamExecutionSnapshot) {
    let runId = snapshot.supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !runId.isEmpty else { return }
    lock.lock()
    snapshotsByRunId[runId] = snapshot
    trimAndPersistLocked()
    lock.unlock()
    NotificationCenter.default.post(
      name: .signalASIAgentTeamExecutionHistoryDidUpdate,
      object: runId
    )
  }

  func recent(_ limit: Int = AgentTeamExecutionHistoryStore.defaultRecentLimit) -> [AgentTeamExecutionSnapshot] {
    lock.lock()
    defer { lock.unlock() }
    return orderedSnapshotsLocked().prefix(max(limit, 0)).map { $0 }
  }

  func snapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot? {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    lock.lock()
    defer { lock.unlock() }
    return snapshotsByRunId[clean]
  }

  func remove(supervisorRunId: String) {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    lock.lock()
    let removed = snapshotsByRunId.removeValue(forKey: clean) != nil
    if removed {
      persistLocked()
    }
    lock.unlock()
    if removed {
      NotificationCenter.default.post(
        name: .signalASIAgentTeamExecutionHistoryDidUpdate,
        object: clean
      )
    }
  }

  func clear() {
    lock.lock()
    snapshotsByRunId.removeAll()
    Self.destroyPersistentStore(defaults: defaults, storageKey: storageKey, secrets: secrets)
    lock.unlock()
    NotificationCenter.default.post(name: .signalASIAgentTeamExecutionHistoryDidUpdate, object: nil)
  }

  private func trimAndPersistLocked() {
    let ordered = orderedSnapshotsLocked()
    snapshotsByRunId = Dictionary(uniqueKeysWithValues: ordered
      .prefix(Self.maxSnapshots)
      .map { ($0.supervisorRunId, $0) })
    persistLocked()
  }

  private func orderedSnapshotsLocked() -> [AgentTeamExecutionSnapshot] {
    snapshotsByRunId.values.sorted { left, right in
      if left.updatedAtMillis != right.updatedAtMillis {
        return left.updatedAtMillis > right.updatedAtMillis
      }
      return left.supervisorRunId > right.supervisorRunId
    }
  }

  private func persistLocked() {
    let data = (try? JSONEncoder().encode(orderedSnapshotsLocked())) ?? Data("[]".utf8)
    _ = SignalASIEncryptedUserDefaultsStore.write(
      data,
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  private static func normalized(_ snapshots: [AgentTeamExecutionSnapshot]) -> [String: AgentTeamExecutionSnapshot] {
    var result: [String: AgentTeamExecutionSnapshot] = [:]
    for snapshot in snapshots {
      let runId = snapshot.supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !runId.isEmpty else { continue }
      if let current = result[runId], current.updatedAtMillis > snapshot.updatedAtMillis {
        continue
      }
      result[runId] = snapshot
    }
    return result
  }
}
