import CryptoKit
import Foundation

let agentPlanNodeObservationPendingEvidence = "agent_node_observation_pending"

struct AgentPlanNodeKey: Codable, Equatable, Hashable {
  var sessionId: String
  var planId: String
  var actionId: String
  var checkpointId: String
  var conversationId: String
  var turnId: String
  var specificationSha256: String

  static func make(
    sessionId: String,
    plan: AgentPlan,
    action: AgentAction,
    conversationId: String,
    turnId: String
  ) -> AgentPlanNodeKey? {
    guard let checkpoint = plan.checkpoints.last(where: {
      $0.actionId == action.id && $0.status == .active
    }) else { return nil }
    var parameters = action.parameters
    if checkpoint.revisionParameterPresent == false,
       parameters[AgentDurablePlanHistoryPolicy.revisionParameter] == String(checkpoint.planRevision) {
      parameters.removeValue(forKey: AgentDurablePlanHistoryPolicy.revisionParameter)
    }
    let specification: [String: Any] = [
      "kind": action.kind.rawValue,
      "target": action.target,
      "parameters": parameters,
      "revision": checkpoint.planRevision
    ]
    guard JSONSerialization.isValidJSONObject(specification),
          let data = try? JSONSerialization.data(
            withJSONObject: specification,
            options: [.sortedKeys, .withoutEscapingSlashes]
          ) else { return nil }
    return AgentPlanNodeKey(
      sessionId: sessionId,
      planId: plan.planId,
      actionId: action.id,
      checkpointId: checkpoint.id,
      conversationId: conversationId.ifBlank(sessionId),
      turnId: turnId.ifBlank(plan.planId),
      specificationSha256: sha256(data)
    )
  }

  var journalId: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = (try? encoder.encode(self)) ?? Data()
    return "plan-node:" + Self.sha256(data)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case planId = "plan_id"
    case actionId = "action_id"
    case checkpointId = "checkpoint_id"
    case conversationId = "conversation_id"
    case turnId = "turn_id"
    case specificationSha256 = "specification_sha256"
  }
}

struct AgentPlanNodeObservation: Codable, Equatable {
  var result: AgentActionResult
  var verified: Bool
  var evidence: String

  init(result: AgentActionResult, verified: Bool, evidence: String = "") {
    self.result = result
    self.verified = verified
    self.evidence = evidence
  }
}

enum AgentPlanNodeClaim: Equatable {
  case acquired
  case pending
  case observed(AgentPlanNodeObservation)
}

protocol AgentPlanNodeJournaling: AnyObject {
  func observe(_ key: AgentPlanNodeKey) throws -> AgentPlanNodeClaim?
  func claim(_ key: AgentPlanNodeKey) throws -> AgentPlanNodeClaim
  func record(_ key: AgentPlanNodeKey, observation: AgentPlanNodeObservation) throws
  func read(_ key: AgentPlanNodeKey) throws -> AgentPlanNodeObservation?
  func clear()
}

enum AgentPlanNodeJournalError: Error, Equatable {
  case persistenceFailed
  case missingDispatch
  case identityMismatch
  case resultChanged
}

final class EncryptedAgentPlanNodeJournal: AgentPlanNodeJournaling {
  private struct Entry: Codable, Equatable {
    var key: AgentPlanNodeKey
    var observation: AgentPlanNodeObservation?
    var startedAtMillis: Int64
    var updatedAtMillis: Int64
  }

  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let storageKey: String
  private let nowMillis: () -> Int64
  private let lock = NSRecursiveLock()

  init(
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    storageKey: String = "galaxyssi.agent.plan-node-journal.v1",
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.defaults = defaults
    self.secrets = secrets
    self.storageKey = storageKey
    self.nowMillis = nowMillis
  }

  func claim(_ key: AgentPlanNodeKey) throws -> AgentPlanNodeClaim {
    lock.lock()
    defer { lock.unlock() }
    var entries = try load()
    if let entry = entries[key.journalId] {
      guard entry.key == key else { throw AgentPlanNodeJournalError.identityMismatch }
      return entry.observation.map(AgentPlanNodeClaim.observed) ?? .pending
    }
    let now = nowMillis()
    entries[key.journalId] = Entry(
      key: key,
      observation: nil,
      startedAtMillis: now,
      updatedAtMillis: now
    )
    try persist(entries)
    return .acquired
  }

  func observe(_ key: AgentPlanNodeKey) throws -> AgentPlanNodeClaim? {
    lock.lock()
    defer { lock.unlock() }
    guard let entry = try load()[key.journalId] else { return nil }
    guard entry.key == key else { throw AgentPlanNodeJournalError.identityMismatch }
    return entry.observation.map(AgentPlanNodeClaim.observed) ?? .pending
  }

  func record(_ key: AgentPlanNodeKey, observation: AgentPlanNodeObservation) throws {
    lock.lock()
    defer { lock.unlock() }
    guard observation.result.actionId == key.actionId else {
      throw AgentPlanNodeJournalError.identityMismatch
    }
    var entries = try load()
    guard var entry = entries[key.journalId] else {
      throw AgentPlanNodeJournalError.missingDispatch
    }
    guard entry.key == key else { throw AgentPlanNodeJournalError.identityMismatch }
    if let previous = entry.observation {
      guard previous == observation else { throw AgentPlanNodeJournalError.resultChanged }
      return
    }
    entry.observation = observation
    entry.updatedAtMillis = nowMillis()
    entries[key.journalId] = entry
    try persist(entries)
  }

  func read(_ key: AgentPlanNodeKey) throws -> AgentPlanNodeObservation? {
    lock.lock()
    defer { lock.unlock() }
    guard let entry = try load()[key.journalId] else { return nil }
    guard entry.key == key else { throw AgentPlanNodeJournalError.identityMismatch }
    return entry.observation
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    GalaxySSIEncryptedUserDefaultsStore.destroy(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    )
  }

  private func load() throws -> [String: Entry] {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(
      defaults: defaults,
      key: storageKey,
      secrets: secrets
    ) else {
      if defaults.object(forKey: "\(storageKey).encrypted.v1") != nil {
        throw AgentPlanNodeJournalError.persistenceFailed
      }
      return [:]
    }
    guard let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
      throw AgentPlanNodeJournalError.persistenceFailed
    }
    return entries
  }

  private func persist(_ entries: [String: Entry]) throws {
    guard let data = try? JSONEncoder().encode(entries),
          GalaxySSIEncryptedUserDefaultsStore.write(
            data,
            defaults: defaults,
            key: storageKey,
            secrets: secrets
          ) else {
      throw AgentPlanNodeJournalError.persistenceFailed
    }
  }
}
