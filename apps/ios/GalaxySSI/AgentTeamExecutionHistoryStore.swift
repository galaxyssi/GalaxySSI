import Foundation
import CoreFoundation

struct AgentTeamReplyObservation: Equatable {
  let generation: Int64?
  let sequence: Int64?
  private(set) var valid: Bool

  init(generation: Int64? = nil, sequence: Int64? = nil) {
    self.generation = generation
    self.sequence = sequence
    valid = (generation.map { AgentRemoteOutcomePolicy.validGeneration($0) } ?? true) &&
      (sequence.map { (0...9_007_199_254_740_991).contains($0) } ?? true)
  }

  init(payload: [String: Any]) {
    let rawGeneration = payload["execution_generation"]
    let rawSequence = payload["status_sequence"] ?? payload["status_seq"]
    self.init(generation: Self.integer(rawGeneration), sequence: Self.integer(rawSequence))
    valid = valid && (rawGeneration == nil || generation != nil) && (rawSequence == nil || sequence != nil)
  }

  private static func integer(_ value: Any?) -> Int64? {
    if let text = value as? String { return Int64(text) }
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 9_007_199_254_740_991,
          Double(number.int64Value) == number.doubleValue else { return nil }
    return number.int64Value
  }
}

struct AgentTeamReplyOwner: Codable, Equatable {
  var supervisorRunId: String
  var memberId: String
  var conversationId: String
  var turnId: String
  var sourceMessageId: String
  var contactId: String
  var deliveryMode: AgentDeliveryMode
  var observedGeneration: Int64? = nil
  var observedSequence: Int64? = nil

  func accepts(_ observation: AgentTeamReplyObservation) -> Bool {
    guard observation.valid else { return false }
    if let observedGeneration {
      guard let generation = observation.generation, generation >= observedGeneration else { return false }
      if generation > observedGeneration { return true }
    } else if observation.generation != nil { return true }
    if let observedSequence {
      guard let sequence = observation.sequence, sequence >= observedSequence else { return false }
    }
    return true
  }

  func advancing(_ observation: AgentTeamReplyObservation) -> AgentTeamReplyOwner {
    var result = self
    if let generation = observation.generation, generation != observedGeneration {
      result.observedGeneration = generation
      result.observedSequence = observation.sequence
    } else if let sequence = observation.sequence { result.observedSequence = sequence }
    return result
  }
}

enum AgentTeamReplyDisposition: Equatable {
  case notOwned, primary, observerProgress, observerCommitted, observerDuplicate, observerStale, retired
}

typealias AgentTeamReplyRecoveryContext = (owner: AgentTeamReplyOwner, team: AgentTeamExecutionSnapshot, member: AgentTeamMemberSnapshot)

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
                  replacement.richOutputJson == member.richOutputJson,
                  replacement.replyContent == member.replyContent else { throw AgentTeamHistoryDatabase.Failure.stale }
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

  func consumeOwnedReply(source: String, conversation: String, turn: String, task: String,
                         contact: String, content: String, richOutputJson: String,
                         terminal: Bool, success: Bool, now: Int64,
                         observation: AgentTeamReplyObservation = AgentTeamReplyObservation(),
                         persistObservation: Bool = true) throws -> AgentTeamReplyDisposition {
    guard !source.isBlank, task == source, !conversation.isBlank, !turn.isBlank, !contact.isBlank else { return .notOwned }
    var changedRun: String?
    let disposition = try access { database -> AgentTeamReplyDisposition in
      guard let owner = try database.replyOwner(source: source, conversation: conversation, turn: turn, contact: contact) else { return .notOwned }
      guard let saved = try database.snapshots(runId: owner.supervisorRunId).first,
            let member = saved.members.first(where: { $0.memberId == owner.memberId &&
              $0.sourceMessageId == source && $0.agentId == contact }), saved.state != .cancelled else { return .retired }
      if owner.deliveryMode == .respond { return .primary }
      guard owner.accepts(observation) else { return .observerStale }
      if (member.status.isTerminal && member.status != .interrupted) || saved.state.deliverable {
        let expected = success ? AgentSubagentStatus.succeeded : .failed
        let preview = success ? member.output : member.errorMessage
        if terminal, member.status == expected, member.richOutputJson == richOutputJson,
           member.replyContent == content || (member.replyContent == nil && preview == content) {
          if persistObservation { try database.updateReplyOwner(owner.advancing(observation)) }
          if member.replyContent == nil, let index = saved.members.firstIndex(where: { $0.memberId == owner.memberId }) {
            var restored = saved
            restored.members[index].replyContent = content
            try database.put(restored)
          }
        }
        return .observerDuplicate
      }
      if persistObservation {
        let advanced = owner.advancing(observation)
        if advanced != owner { try database.updateReplyOwner(advanced) }
      }
      guard terminal else { return .observerProgress }
      guard let updated = AgentSavedTeamReplyPolicy.apply(to: saved, source: source, conversation: conversation,
        turn: turn, task: task, contact: contact, content: content, richOutputJson: richOutputJson,
        success: success, now: now) else { throw AgentTeamHistoryDatabase.Failure.stale }
      try database.put(updated)
      try database.pruneFinished()
      changedRun = updated.supervisorRunId
      return .observerCommitted
    }
    if let changedRun { notify(changedRun) }
    return disposition
  }

  func pendingRecoveryPage(after: String, limit: Int = 8) throws -> (teams: [AgentTeamExecutionSnapshot], next: String?) {
    try access { try $0.recoveryPage(after: after, limit: limit) }
  }

  func recoveryContext(source: String, conversation: String, turn: String, contact: String) throws -> AgentTeamReplyRecoveryContext? {
    try access { database in
      guard let owner = try database.replyOwner(source: source, conversation: conversation, turn: turn, contact: contact),
            let team = try database.snapshots(runId: owner.supervisorRunId).first,
            team.conversationId == conversation, team.taskId == turn,
            let member = team.members.first(where: { $0.memberId == owner.memberId &&
              $0.sourceMessageId == source && $0.agentId == contact && $0.deliveryMode == owner.deliveryMode }) else { return nil }
      return (owner, team, member)
    }
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

  func recallCollaborationResults(conversationId: String, excludingTurnId: String,
                                  query: String, limit: Int = 12) -> [AgentTeamExecutionSnapshot] {
    guard !conversationId.isBlank, limit > 0, query.utf8.count <= 1_000,
          let records = try? access({
            try $0.snapshots(conversation: conversationId, deliverableOnly: true, limit: Self.maxSnapshots)
          }) else { return [] }
    let terms = query.split(whereSeparator: \.isWhitespace).prefix(16)
    return Array(records.lazy.filter { record in
      guard record.conversationId == conversationId, record.taskId != excludingTurnId else { return false }
      let fields = [record.goal, record.finalOutput] + record.members.flatMap {
        [$0.agentId, $0.role, $0.output]
      }
      return terms.allSatisfy { term in
        fields.contains { $0.localizedCaseInsensitiveContains(String(term)) }
      }
    }.prefix(min(limit, 50)))
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
      try database.transaction { try database.remove(preserveOwners: true) }
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
