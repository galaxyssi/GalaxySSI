import Foundation

extension Notification.Name {
  static let galaxySSIAgentTeamExecutionHistoryDidUpdate = Notification.Name("galaxyssi.agentTeamExecutionHistoryDidUpdate")
}

final class AgentTeamExecutionHistoryStore {
  static let shared = AgentTeamExecutionHistoryStore()
  static let defaultStorageKey = "galaxyssi.agent_team_execution_history_v1"
  static let defaultRecentLimit = 20
  static let maxSnapshots = 200
  private static let processLock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let storageKey: String
  private let secrets: GalaxySSISecretStore
  private let executionStore: AgentTeamExecutionStore
  private let database: AgentTeamHistoryDatabase?

  init(defaults: UserDefaults = .standard, storageKey: String = AgentTeamExecutionHistoryStore.defaultStorageKey,
       secrets: GalaxySSISecretStore = KeychainSecretStore.shared, executionStore: AgentTeamExecutionStore? = nil,
       fileURL: URL = AgentTeamHistoryDatabase.defaultFileURL()) {
    self.defaults = defaults
    self.storageKey = storageKey
    self.secrets = secrets
    self.executionStore = executionStore ?? UserDefaultsAgentTeamExecutionStore(defaults: defaults, secrets: secrets)
    database = try? AgentTeamHistoryDatabase(fileURL: fileURL, storageKey: storageKey, secrets: secrets)
  }

  static func destroyPersistentStore(defaults: UserDefaults = .standard,
                                    storageKey: String = AgentTeamExecutionHistoryStore.defaultStorageKey,
                                    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
                                    fileURL: URL = AgentTeamHistoryDatabase.defaultFileURL()) {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    do {
      let database = try AgentTeamHistoryDatabase(fileURL: fileURL, storageKey: storageKey, secrets: secrets)
      try database.transaction { try database.remove() }
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: storageKey, secrets: secrets)
    } catch { return }
  }

  @discardableResult
  func upsert(_ snapshot: AgentTeamExecutionSnapshot) -> Bool {
    var incoming = snapshot
    incoming.supervisorRunId = incoming.supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !incoming.supervisorRunId.isEmpty else { return false }
    do {
      let changed = try access { database -> Bool in
        if let current = try database.snapshots(runId: incoming.supervisorRunId).first {
          guard current.teamId == incoming.teamId, current.conversationId == incoming.conversationId,
                current.taskId == incoming.taskId else { throw AgentTeamHistoryDatabase.Failure.stale }
          if current.state.deliverable || current.updatedAtMillis > incoming.updatedAtMillis { return false }
          for member in current.members where [.succeeded, .failed, .cancelled, .skipped].contains(member.status) {
            guard let replacement = incoming.members.first(where: { $0.memberId == member.memberId }),
                  replacement.sourceMessageId == member.sourceMessageId,
                  replacement.status == member.status, replacement.output == member.output,
                  replacement.richOutputJson == member.richOutputJson else { throw AgentTeamHistoryDatabase.Failure.stale }
          }
        }
        try database.put(incoming)
        try database.pruneFinished()
        return true
      }
      if changed { notify(incoming.supervisorRunId) }
      return true
    } catch { return false }
  }

  func applyReply(supervisorRunId: String, source: String, conversation: String, turn: String,
                  task: String, contact: String, content: String, richOutputJson: String = "",
                  success: Bool, now: Int64) -> AgentTeamExecutionSnapshot? {
    let updated = try? access { database -> AgentTeamExecutionSnapshot? in
      guard let saved = try database.snapshots(runId: supervisorRunId).first,
            let updated = AgentSavedTeamReplyPolicy.apply(to: saved, source: source, conversation: conversation,
              turn: turn, task: task, contact: contact, content: content, richOutputJson: richOutputJson,
              success: success, now: now) else { return nil }
      try database.put(updated)
      try database.pruneFinished()
      return updated
    }
    if let updated { notify(updated.supervisorRunId) }
    return updated
  }

  func recent(_ limit: Int = AgentTeamExecutionHistoryStore.defaultRecentLimit) -> [AgentTeamExecutionSnapshot] {
    guard limit > 0, let saved = try? access({ try $0.snapshots(limit: limit) }) else { return [] }
    var combined = Dictionary(uniqueKeysWithValues: saved.map { ($0.supervisorRunId, $0) })
    for live in executionStore.snapshots() {
      combined[live.supervisorRunId] = newer(combined[live.supervisorRunId], live)
    }
    return combined.values.sorted {
      $0.updatedAtMillis == $1.updatedAtMillis ? $0.supervisorRunId > $1.supervisorRunId : $0.updatedAtMillis > $1.updatedAtMillis
    }.prefix(max(0, limit)).map { $0 }
  }

  func recoverable(conversationId: String) -> [AgentTeamExecutionSnapshot] {
    guard !conversationId.isBlank else { return [] }
    return (try? access { try $0.snapshots(conversation: conversationId, recoverableOnly: true) }) ?? []
  }

  func deliverableSnapshots() -> [AgentTeamExecutionSnapshot] {
    (try? access { try $0.snapshots(deliverableOnly: true, limit: Self.maxSnapshots) }) ?? []
  }

  func snapshot(supervisorRunId: String) -> AgentTeamExecutionSnapshot? {
    let run = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !run.isEmpty else { return nil }
    do { return newer(try access { try $0.snapshots(runId: run).first }, executionStore.snapshot(supervisorRunId: run)) }
    catch { return nil }
  }

  func remove(supervisorRunId: String) {
    do {
      try access { try $0.remove(runId: supervisorRunId) }
      executionStore.remove(supervisorRunId: supervisorRunId)
      notify(supervisorRunId)
    } catch { return }
  }

  func clear() {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    guard let database else { return }
    do {
      try database.transaction { try database.remove() }
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: storageKey, secrets: secrets)
      executionStore.clear()
      notify(nil)
    } catch { return }
  }

  private func newer(_ saved: AgentTeamExecutionSnapshot?, _ live: AgentTeamExecutionSnapshot?) -> AgentTeamExecutionSnapshot? {
    guard let saved else { return live }
    guard let live else { return saved }
    if saved.state.deliverable { return saved }
    return saved.updatedAtMillis >= live.updatedAtMillis ? saved : live
  }

  private func access<T>(_ operation: (AgentTeamHistoryDatabase) throws -> T) throws -> T {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    guard let database else { throw AgentTeamHistoryDatabase.Failure.unavailable }
    let result = try database.transaction {
      if try !database.initialized() {
        let encryptedExists = defaults.object(forKey: storageKey + ".encrypted.v1") != nil
        let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: storageKey, secrets: secrets)
          ?? (encryptedExists ? nil : defaults.data(forKey: storageKey))
        if encryptedExists && data == nil { throw AgentTeamHistoryDatabase.Failure.corrupt }
        if let data {
          let snapshots = try JSONDecoder().decode([AgentTeamExecutionSnapshot].self, from: data)
          var normalized: [String: AgentTeamExecutionSnapshot] = [:]
          for var snapshot in snapshots {
            snapshot.supervisorRunId = snapshot.supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snapshot.supervisorRunId.isEmpty else { throw AgentTeamHistoryDatabase.Failure.corrupt }
            if let current = normalized[snapshot.supervisorRunId], current.updatedAtMillis > snapshot.updatedAtMillis { continue }
            normalized[snapshot.supervisorRunId] = snapshot
          }
          for snapshot in normalized.values { try database.put(snapshot) }
        }
        try database.markInitialized()
        try database.pruneFinished()
      }
      return try operation(database)
    }
    if defaults.object(forKey: storageKey) != nil || defaults.object(forKey: storageKey + ".encrypted.v1") != nil {
      GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: storageKey, secrets: secrets)
    }
    return result
  }

  private func notify(_ run: String?) {
    NotificationCenter.default.post(name: .galaxySSIAgentTeamExecutionHistoryDidUpdate, object: run)
  }
}
