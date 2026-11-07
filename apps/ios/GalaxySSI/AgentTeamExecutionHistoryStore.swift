import CryptoKit
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

  static func integer(_ value: Any?) -> Int64? {
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
  var closedRecallGeneration: Int64? = nil
  var recallEventGeneration: Int64? = nil

  func observingPrimaryRecall(_ observation: AgentTeamReplyObservation, terminal: Bool) -> Self {
    guard deliveryMode == .respond, observation.valid, let generation = observation.generation else { return self }
    var next = accepts(observation) ? advancing(observation) : self
    if terminal, max(next.observedGeneration ?? 0, next.recallEventGeneration ?? 0) == generation {
      next.closedRecallGeneration = generation
    }
    return next
  }

  func permitsRecall(generation: Int64) -> Bool {
    AgentRemoteOutcomePolicy.validGeneration(generation) &&
      max(observedGeneration ?? 0, recallEventGeneration ?? 0) == generation && closedRecallGeneration != generation
  }

  func observingRecallEvent(_ observation: AgentTeamReplyObservation, terminal: Bool) -> Self {
    guard deliveryMode == .respond || deliveryMode == .observe,
          observation.valid, let generation = observation.generation,
          generation >= max(observedGeneration ?? 0, recallEventGeneration ?? 0) else { return self }
    var next = self
    next.recallEventGeneration = generation
    if terminal { next.closedRecallGeneration = generation }
    return next
  }

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
          if current.goal != incoming.goal {
            let pinned = try database.goalCheckpoints(runId: incoming.supervisorRunId, newestOnly: true)
            if !pinned.isEmpty || current.members.contains(where: { $0.dispatchCheckpoint != nil }) {
              throw AgentTeamHistoryDatabase.Failure.stale
            }
          }
          if current.state.deliverable || current.updatedAtMillis > incoming.updatedAtMillis { return false }
          for member in current.members where member.dispatchCheckpoint != nil {
            guard let replacement = incoming.members.first(where: { $0.memberId == member.memberId }),
                  replacement.sourceMessageId == member.sourceMessageId,
                  replacement.dispatchCheckpoint == member.dispatchCheckpoint,
                  replacement.dispatchDependencyMemberIds == member.dispatchDependencyMemberIds,
                  replacement.dispatchAllowsSavedToolTest == member.dispatchAllowsSavedToolTest,
                  replacement.dispatchResourceObservation == member.dispatchResourceObservation else {
              throw AgentTeamHistoryDatabase.Failure.stale
            }
          }
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

  @discardableResult
  func advanceDispatchCheckpoint(runId: String, conversationId: String, turnId: String,
                                 memberId: String, sourceMessageId: String,
                                 to checkpoint: AgentTeamMemberDispatchCheckpoint, now: Int64) -> Bool {
    guard !sourceMessageId.isBlank else { return false }
    do {
      let advanced = try access { database in
        guard var snapshot = try database.snapshots(runId: runId).first,
              snapshot.conversationId == conversationId, snapshot.taskId == turnId,
              let index = snapshot.members.firstIndex(where: {
                $0.memberId == memberId && $0.sourceMessageId == sourceMessageId
              }) else { return false }
        let previous = snapshot.members[index].dispatchCheckpoint
        switch checkpoint {
        case .notStarted:
          return false
        case .dispatching:
          guard previous == .notStarted, !snapshot.state.isTerminal,
                !snapshot.members[index].status.isTerminal else { return false }
        case .accepted:
          if previous == .accepted { return true }
          guard previous == .dispatching else { return false }
        }
        snapshot.members[index].dispatchCheckpoint = checkpoint
        if checkpoint == .dispatching {
          snapshot.members[index].executionStartedAtMillis = now
        }
        snapshot.updatedAtMillis = max(snapshot.updatedAtMillis, now)
        try database.put(snapshot)
        return true
      }
      if advanced { notify(runId) }
      return advanced
    } catch { return false }
  }

  func recordDispatchResourceObservation(_ observation: AgentMcpJSONObject,
                                         scope: AgentCollaborationToolEvidenceScope,
                                         sections: [String: String] = [:]) throws {
    guard sections.allSatisfy({ AgentCollaborationInlineOriginals.contextSections.contains($0.key) &&
      $0.value.utf8.count <= AgentCollaborationInlineOriginals.maximumContextSectionBytes }) else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    try access { database in
      guard var snapshot = try database.snapshots(runId: scope.runId).first,
            snapshot.conversationId == scope.conversationId, snapshot.taskId == scope.turnId,
            !snapshot.state.isTerminal,
            let index = snapshot.members.firstIndex(where: {
              $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId &&
                $0.dispatchCheckpoint == .dispatching && !$0.status.isTerminal
            }),
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true else { throw AgentTeamHistoryDatabase.Failure.stale }
      if !sections.isEmpty {
        let key = Self.dispatchContextKey(scope)
        let originals = sections.mapValues { Data($0.utf8) }
        if let saved = try database.researchRecord([String: Data].self, conversationId: scope.conversationId,
          key: key, revision: 0) {
          guard saved == originals else { throw AgentTeamHistoryDatabase.Failure.stale }
        } else {
          try database.insertResearchRecord(originals, conversationId: scope.conversationId, key: key, revision: 0)
        }
      }
      if let saved = snapshot.members[index].dispatchResourceObservation {
        guard saved == observation else { throw AgentTeamHistoryDatabase.Failure.stale }
        return
      }
      snapshot.members[index].dispatchResourceObservation = observation
      snapshot.updatedAtMillis = max(snapshot.updatedAtMillis, observation.int64("observed_at_unix_ms"))
      try database.put(snapshot)
    }
  }

  private static func dispatchContextKey(_ scope: AgentCollaborationToolEvidenceScope) -> String {
    "dispatch-context:" + AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "turn": .string(scope.turnId),
      "member": .string(scope.memberId), "source": .string(scope.sourceId)
    ])
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

  func commitManagedBrowserReceipt(_ receipt: AgentManagedBrowserMemberReceipt,
                                   binding: AgentManagedBrowserDispatchBinding, now: Int64) throws -> Bool {
    let owner = binding.owner
    let saved = try access { database -> Bool in
      guard let team = try database.snapshots(runId: owner.runId).first,
            binding.matches(team: team, profileID: binding.profileID, modelID: binding.modelID,
                            hostContextDigest: binding.hostContextDigest),
            let index = team.members.firstIndex(where: {
              $0.memberId == owner.memberId && $0.sourceMessageId == owner.sourceId && $0.agentId == binding.agentID
            }) else { throw AgentTeamHistoryDatabase.Failure.stale }
      let member = team.members[index]
      let success = receipt.state == .completed
      if member.status.isTerminal && member.status != .interrupted {
        return success ? (member.status == .succeeded && member.replyContent == receipt.text) : member.status == .cancelled
      }
      guard var updated = AgentSavedTeamReplyPolicy.apply(to: team, source: owner.sourceId,
        conversation: owner.conversationId, turn: owner.turnId, task: owner.sourceId, contact: binding.agentID,
        content: receipt.text, success: success, now: now) else { return false }
      if !success { updated.members[index].status = .cancelled }
      try database.put(updated)
      return true
    }
    if saved { notify(owner.runId) }
    return saved
  }

  func reopenManagedBrowserMember(binding: AgentManagedBrowserDispatchBinding, now: Int64) throws -> Bool {
    let owner = binding.owner
    let changed = try access { database -> Bool in
      guard var team = try database.snapshots(runId: owner.runId).first,
            binding.matches(team: team, profileID: binding.profileID, modelID: binding.modelID,
                            hostContextDigest: binding.hostContextDigest),
            let index = team.members.firstIndex(where: {
              $0.memberId == owner.memberId && $0.sourceMessageId == owner.sourceId && $0.agentId == binding.agentID
            }) else { throw AgentTeamHistoryDatabase.Failure.stale }
      if team.state == .running && !team.members[index].status.isTerminal { return false }
      guard team.state == .interrupted, team.members[index].status == .interrupted else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      team.state = .running
      team.members[index].status = .running
      team.updatedAtMillis = max(now, team.updatedAtMillis)
      try database.put(team)
      return true
    }
    if changed { notify(owner.runId) }
    return true
  }

  func reopenManagedBrowserTeam(_ input: AgentManagedBrowserTeamDispatch, outgoing: ChatMessage,
                               profileID: String, now: Int64) throws -> AgentTeamExecutionSnapshot {
    let team = try access { database -> AgentTeamExecutionSnapshot in
      guard var team = try database.snapshots(runId: input.runID).first,
            input.matches(team, outgoing: outgoing, profileID: profileID),
            team.state == .running || team.state == .interrupted else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      var changed = false
      if team.state == .interrupted {
        team.state = .running
        changed = true
      }
      for index in team.members.indices where team.members[index].dispatchCheckpoint == .notStarted &&
        team.members[index].status == .interrupted {
        team.members[index].status = .pending
        changed = true
      }
      if changed {
        team.updatedAtMillis = max(now, team.updatedAtMillis)
        try database.put(team)
      }
      return team
    }
    return team
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
      if owner.deliveryMode == .respond {
        if persistObservation {
          let next = owner.observingPrimaryRecall(observation, terminal: terminal)
          if next != owner { try database.updateReplyOwner(next) }
        }
        return .primary
      }
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

  func cancelRecoveryForMissingScope(expected: AgentTeamExecutionSnapshot, now: Int64) throws -> AgentTeamExecutionSnapshot? {
    let stopped = try access { database -> AgentTeamExecutionSnapshot? in
      guard var current = try database.snapshots(runId: expected.supervisorRunId).first,
            current == expected, !current.state.deliverable else { return nil }
      current.state = .cancelled
      current.updatedAtMillis = max(current.updatedAtMillis, now)
      current.executionEndedAtMillis = now
      try database.put(current)
      return current
    }
    if let stopped { notify(stopped.supervisorRunId) }
    return stopped
  }

  func pendingPublicationRecoveryPage(after: String) throws -> (owners: [AgentTeamReplyOwner], next: String?) {
    try access { database in
      let page = try database.publicationRecoveryPage(after: after)
      var owners: [AgentTeamReplyOwner] = []
      for team in page.teams where team.state != .cancelled {
        for member in team.members where member.deliveryMode == .observe && member.status == .succeeded &&
          member.replyContent?.contains(AgentCollaborationResearchEnvelope.wireFormat) == true {
          guard let owner = try database.replyOwner(source: member.sourceMessageId, conversation: team.conversationId,
            turn: team.taskId, contact: member.agentId), owner.supervisorRunId == team.supervisorRunId,
            owner.memberId == member.memberId, owner.deliveryMode == .observe else { continue }
          let key = Self.researchPublicationKey(runId: team.supervisorRunId, memberId: member.memberId,
            sourceId: member.sourceMessageId)
          if try database.researchRecord(AgentCollaborationResearchPublication.self,
            conversationId: team.conversationId, key: key, revision: 0) == nil {
            owners.append(owner)
          }
        }
      }
      return (owners, page.next)
    }
  }

  func observeDesktopRecallEvent(source: String, conversation: String, turn: String, contact: String,
                                 observation: AgentTeamReplyObservation, terminal: Bool) throws {
    try access { database in
      guard let owner = try database.replyOwner(source: source, conversation: conversation, turn: turn, contact: contact)
      else { return }
      let next = owner.observingRecallEvent(observation, terminal: terminal)
      if next != owner { try database.updateReplyOwner(next) }
    }
  }

  func recoveryContext(source: String, conversation: String, turn: String, contact: String,
                       requireResearchAccess: Bool = false) throws -> AgentTeamReplyRecoveryContext? {
    try access { database in
      if requireResearchAccess,
         try database.researchRecord(Bool.self, conversationId: conversation,
           key: "native-evidence-revoked", revision: 0) == true { return nil }
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

  func recordCloudEvidence(_ evidence: AgentCollaborationCloudToolEvidence) throws -> AgentMcpJSONObject {
    let scope = evidence.scope
    let id = AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "member": .string(scope.memberId), "source": .string(scope.sourceId),
      "round": .int(Int64(evidence.round)), "call": .string(evidence.call.callId), "index": .int(Int64(evidence.call.index))
    ])
    return try access { database in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId,
            !team.state.isTerminal,
            team.members.contains(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }) else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let saved: AgentCollaborationCloudToolEvidence
      if let prior = try database.cloudEvidence(id: id, conversationId: scope.conversationId) {
        guard prior.scope == scope, prior.call == evidence.call, prior.output == evidence.output,
              prior.succeeded == evidence.succeeded else { throw AgentTeamHistoryDatabase.Failure.stale }
        saved = prior
      } else {
        try database.insertCloudEvidence(evidence, id: id)
        saved = evidence
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let hash = try SHA256.hash(data: encoder.encode(saved)).map { String(format: "%02x", $0) }.joined()
      if saved.observedFailure { try database.indexCloudProblem(id: id, scope: scope) }
      return [
        "evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_cloud_tool"),
        "trust": .string("execution_observed_not_claim_verified")
      ]
    }
  }

  func admitCollaborationModelCall(_ admission: AgentCollaborationModelAdmission) throws {
    let scope = admission.scope
    let key = "model-call:" + admission.id.uuidString.lowercased()
    try access { database in
      guard admission.round >= 0, admission.startedAtMillis > 0,
            (admission.requestedModel?.utf8.count ?? 0) <= 256,
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true,
            let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            team.members.contains(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal })
      else { throw AgentTeamHistoryDatabase.Failure.stale }
      try database.insertResearchRecord(admission, conversationId: scope.conversationId, key: key, revision: 0)
    }
  }

  func settleCollaborationModelCall(_ admission: AgentCollaborationModelAdmission,
                                    settlement: AgentCollaborationModelSettlement) throws {
    let conversation = admission.scope.conversationId
    let key = "model-call:" + admission.id.uuidString.lowercased()
    try access { database in
      guard settlement.finishedAtMillis >= admission.startedAtMillis, !settlement.usageComplete,
            settlement.costMicros == nil, (settlement.reportedModel?.utf8.count ?? 0) <= 256,
            try database.researchRecord(AgentCollaborationModelAdmission.self,
              conversationId: conversation, key: key, revision: 0) == admission
      else { throw AgentTeamHistoryDatabase.Failure.stale }
      if let existing = try database.researchRecord(AgentCollaborationModelSettlement.self,
        conversationId: conversation, key: key, revision: 1) {
        guard existing == settlement else { throw AgentTeamHistoryDatabase.Failure.stale }
      } else {
        try database.insertResearchRecord(settlement, conversationId: conversation, key: key, revision: 1)
      }
    }
  }

  func collaborationModelCall(_ admission: AgentCollaborationModelAdmission)
    throws -> (admitted: Bool, settlement: AgentCollaborationModelSettlement?) {
    let conversation = admission.scope.conversationId
    let key = "model-call:" + admission.id.uuidString.lowercased()
    return try access { database in
      guard try database.researchRecord(AgentCollaborationModelAdmission.self,
        conversationId: conversation, key: key, revision: 0) == admission else { return (false, nil) }
      return (true, try database.researchRecord(AgentCollaborationModelSettlement.self,
        conversationId: conversation, key: key, revision: 1))
    }
  }

  func collaborationModelAuditPage(conversationId: String, after: String = "", limit: Int = 16)
    throws -> (entries: [AgentCollaborationModelAuditEntry], next: String?) {
    guard !conversationId.isBlank, (1...32).contains(limit),
          after.isEmpty || UUID(uuidString: after)?.uuidString.lowercased() == after
    else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return try access { database in
      let keys = try database.modelCallAdmissionKeys(conversationId: conversationId, after: after, limit: limit + 1)
      let entries = try keys.prefix(limit).map { key in
        guard let admission = try database.researchRecord(AgentCollaborationModelAdmission.self,
                conversationId: conversationId, key: key, revision: 0),
              admission.scope.conversationId == conversationId,
              key == "model-call:" + admission.id.uuidString.lowercased()
        else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        let settlement = try database.researchRecord(AgentCollaborationModelSettlement.self,
          conversationId: conversationId, key: key, revision: 1)
        return AgentCollaborationModelAuditEntry(admission: admission, settlement: settlement)
      }
      let next = keys.count > limit ? entries.last?.admission.id.uuidString.lowercased() : nil
      return (entries, next)
    }
  }

  func removeCloudEvidence(conversationId: String) {
    _ = try? access { try $0.removeCloudEvidence(conversationId: conversationId) }
  }

  enum EvidenceReadMode: Equatable {
    case local, desktopPreview, desktopConfirm(contentHash: String)
  }

  func recallCollaborationOriginal(_ input: AgentMcpJSONObject, scope: AgentCollaborationToolEvidenceScope,
                                   evidenceRead: EvidenceReadMode = .local) throws -> AgentMcpJSONObject {
    let mode = input.string("mode")
    guard evidenceRead == .local || mode == "evidence" else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    if mode == "dependency" { return try recallDependencyOriginal(input, scope: scope) }
    if mode == "capabilities" { return try recallCapabilities(input, scope: scope) }
    if mode == "evolution_rules" {
      guard Set(input.keys).isSubset(of: ["mode", "topic", "offset"]),
            case .string(let topic) = input["topic"] ?? .string("all"), topic.utf8.count <= 32,
            case .int(let offset) = input["offset"] ?? .int(0), let start = Int(exactly: offset), start >= 0 else {
        throw AgentTeamHistoryDatabase.Failure.corrupt
      }
      return try access { database in
        guard let team = try database.snapshots(runId: scope.runId).first,
              team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
              team.members.contains(where: { $0.memberId == scope.memberId &&
                $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }),
              try database.researchRecord(Bool.self, conversationId: scope.conversationId,
                key: "native-evidence-revoked", revision: 0) != true,
              let page = AgentCollaborationRuleTopics.page(topic: topic, offset: start) else {
          throw AgentTeamHistoryDatabase.Failure.stale
        }
        return page
      }
    }
    if mode == "goal" {
      guard Set(input.keys).isSubset(of: ["mode", "section", "offset", "sha256"]),
            case .int(let offset) = input["offset"] ?? .int(0), let start = Int(exactly: offset),
            input["sha256"] == nil || input["sha256"]?.stringValue != nil else {
        throw AgentTeamHistoryDatabase.Failure.corrupt
      }
      return try readPinnedCollaborationGoal(scope: scope, section: input.string("section"), offset: start,
        expectedHash: input["sha256"]?.stringValue)
    }
    if mode == "problems" { return try recallCloudProblems(input, scope: scope) }
    let hash = input.string("sha256")
    let idKey = mode == "workspace" ? "object_id" : "evidence_id"
    let id = input.string(idKey)
    var allowed: Set<String> = ["mode", "sha256", "offset", idKey]
    if mode == "workspace" { allowed.insert("revision") }
    guard ["workspace", "evidence"].contains(mode), Set(input.keys).isSubset(of: allowed),
          [id, hash].allSatisfy({ $0.utf8.count == 64 &&
            $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }),
          case .int(let offset) = input["offset"] ?? .int(0), offset >= 0 else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    typealias OriginalSlice = (content: String, end: Int64, total: Int64)
    func page(_ bytes: Data) throws -> OriginalSlice {
      let characters = String(decoding: bytes, as: UTF8.self)
      let total = Int64(characters.count)
      guard offset <= total else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      let content = String(characters.dropFirst(Int(offset)).prefix(2_000))
      return (content, offset + Int64(content.count), total)
    }
    let (slice, sourceReference, coverage) = try access { database
      -> (OriginalSlice, AgentMcpJSONObject?, AgentMcpJSONObject?) in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            let reader = team.members.first(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }),
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      if mode == "workspace" {
        guard case .int(let revision)? = input["revision"], revision > 0,
              let record = try database.researchRecord(AgentCollaborationResearchRevision.self,
                conversationId: scope.conversationId, key: "object:" + id, revision: revision),
              record.reference.objectId == id, record.reference.revision == revision,
              record.reference.sha256 == hash,
              record.turnId != scope.turnId || (record.runId == scope.runId && record.authorId == scope.memberId)
        else { throw AgentTeamHistoryDatabase.Failure.stale }
        return (try page(encoder.encode(record)), nil, nil)
      }
      func evidencePage(_ data: Data, source: AgentMcpJSONObject, key: String)
        throws -> (OriginalSlice, AgentMcpJSONObject?, AgentMcpJSONObject?) {
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else {
          throw AgentTeamHistoryDatabase.Failure.corrupt
        }
        let slice = try page(data)
        if evidenceRead == .desktopPreview { return (slice, source, nil) }
        if case .desktopConfirm(let expected) = evidenceRead,
           AgentDesktopNativeEvidenceDelivery.digest(slice.content) != expected {
          throw AgentTeamHistoryDatabase.Failure.stale
        }
        let previous = try database.researchRecord(AgentCollaborationReadCoverage.self,
          conversationId: scope.conversationId, key: key, revision: 0) ?? AgentCollaborationReadCoverage()
        var coverage = previous
        coverage.include(start: offset, end: slice.end)
        if coverage != previous {
          try database.insertResearchRecord(coverage, conversationId: scope.conversationId,
            key: key, revision: 0, replaceCoverage: true)
        }
        let complete = coverage.contiguousEnd == slice.total
        return (slice, source, [
          "complete": .bool(complete), "total_characters": .int(slice.total),
          "first_missing_offset": complete ? .null : .int(coverage.contiguousEnd),
          "content_utf8_sha256": .string(hash)
        ])
      }
      if let native = try database.researchRecord(AgentCollaborationNativeToolObservation.self,
        conversationId: scope.conversationId, key: "native-evidence:" + id, revision: 0) {
        let sameRun = native.runId == scope.runId && native.turnId == scope.turnId
        let own = sameRun && native.memberId == scope.memberId && native.sourceId == scope.sourceId
        let dependency = sameRun && reader.dispatchDependencyMemberIds?.contains(native.memberId) == true &&
          team.members.contains { $0.memberId == native.memberId && $0.sourceMessageId == native.sourceId &&
            $0.deliveryMode != .ignore && $0.status.isTerminal }
        guard native.conversationId == scope.conversationId, own || dependency || native.turnId != scope.turnId,
              Self.nativeObservationId(native, hash: hash) == id else {
          throw AgentTeamHistoryDatabase.Failure.stale
        }
        let key = "native-read-coverage:" + Self.readCoverageDigest(scope: scope, id: id, hash: hash)
        return try evidencePage(encoder.encode(native), source: [
          "evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_native_tool"),
          "tool": .string(native.result.provenance.toolId), "status": .string(native.result.status.rawValue),
          "tool_version": .string(native.result.provenance.toolVersion),
          "replayed": .bool(native.result.receipt.replayed)
        ], key: key)
      }
      guard evidenceRead == .local, let record = try database.cloudEvidence(id: id, conversationId: scope.conversationId),
            record.scope.conversationId == scope.conversationId,
            record.scope.turnId != scope.turnId || record.scope == scope else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let key = Self.cloudReadCoverageKey(scope: scope, id: id, hash: hash)
      return try evidencePage(encoder.encode(record), source: [
        "evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_cloud_tool"),
        "tool": .string(record.call.name), "status": .string(record.observedFailure ? "failed" : "succeeded")
      ], key: key)
    }
    var result: AgentMcpJSONObject = [
      idKey: .string(id), "sha256": .string(hash), "content": .string(slice.content),
      "next_offset": slice.end < slice.total ? .int(slice.end) : .null,
      "trust": .string("untrusted_group_evidence")
    ]
    if let coverage { result["host_read_coverage"] = .object(coverage) }
    if let sourceReference {
      result["source_reference"] = .object(sourceReference)
      result["citation_guidance"] = .string(
        "Cite the original observation using source_reference.evidence_id and source_reference.sha256. " +
        "galaxyssi_evidence_receipt records this read, not the original observation. Follow next_offset until null; " +
        "reading every page does not verify the claims in the source."
      )
    }
    return result
  }

  private func recallDependencyOriginal(_ input: AgentMcpJSONObject,
                                        scope: AgentCollaborationToolEvidenceScope) throws -> AgentMcpJSONObject {
    let id = input.string("member_id")
    guard Set(input.keys).isSubset(of: ["mode", "member_id", "offset", "sha256"]),
          !id.isBlank, id.utf8.count <= 256, id != scope.memberId,
          case .int(let offset) = input["offset"] ?? .int(0), offset >= 0,
          offset == 0 || input["sha256"] != nil else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return try access { database in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            team.members.contains(where: { $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId &&
              !$0.status.isTerminal && ($0.dispatchCheckpoint == .dispatching || $0.dispatchCheckpoint == .accepted) &&
              $0.dispatchDependencyMemberIds?.contains(id) == true }),
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true,
            let author = team.members.first(where: { $0.memberId == id && $0.status == .succeeded }),
            let original = author.replyContent else { throw AgentTeamHistoryDatabase.Failure.stale }
      let bytes = Data(original.utf8)
      let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      guard offset <= Int64(bytes.count), input["sha256"] == nil || input["sha256"] == .string(hash) else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let start = Int(offset)
      let end = start + min(8_192, bytes.count - start)
      return ["member_id": .string(id), "sha256": .string(hash), "offset": .int(offset),
        "data_b64": .string(bytes.subdata(in: start..<end).base64EncodedString()),
        "total_bytes": .int(Int64(bytes.count)), "next_offset": end < bytes.count ? .int(Int64(end)) : .null,
        "trust": .string("untrusted_group_evidence")]
    }
  }

  func initialCollaborationCapabilities(scope: AgentCollaborationToolEvidenceScope) throws -> [AgentMcpJSONValue] {
    try recallCapabilities([:], scope: scope, pinInitial: true)["capabilities"]?.arrayValue ?? []
  }

  private func recallCapabilities(_ input: AgentMcpJSONObject, scope: AgentCollaborationToolEvidenceScope,
                                  pinInitial: Bool = false) throws -> AgentMcpJSONObject {
    guard Set(input.keys).isSubset(of: ["mode", "query", "cursor"]),
          case .string(let query) = input["query"] ?? .string(""), query.utf8.count <= 512,
          case .string(let cursor) = input["cursor"] ?? .string(""),
          cursor.isEmpty || (cursor.utf8.count == 64 &&
            cursor.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }) else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard terms.count <= 12 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return try access { database in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            team.members.contains(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }),
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let pinKey = "capability-initial:" + AgentMcpJSONCodec.sha256([
        "run": .string(scope.runId), "group": .string(scope.conversationId), "turn": .string(scope.turnId),
        "member": .string(scope.memberId), "source": .string(scope.sourceId)
      ])
      if pinInitial, let saved = try database.researchRecord(AgentMcpJSONObject.self,
        conversationId: scope.conversationId, key: pinKey, revision: 0) { return saved }
      let initialTerms = pinInitial ? Array(team.goal.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .filter { $0.count >= 2 && !["the", "and", "for", "with", "this", "that", "from", "use", "please"].contains(String($0)) }
        .prefix(12).map(String.init)) : []
      let keys = try database.researchObjectKeys(conversationId: scope.conversationId, after: cursor, limit: 33)
      var entries: [AgentMcpJSONValue] = []
      var ranked: [(score: Int, entry: AgentMcpJSONObject)] = []
      var scanned = 0
      for key in keys.prefix(32) {
        scanned += 1
        guard let head = try database.researchRecord(AgentCollaborationResearchRevision.self,
                conversationId: scope.conversationId, key: key),
              key == "object:" + head.reference.objectId else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        guard head.turnId != scope.turnId || (head.runId == scope.runId && head.authorId == scope.memberId) else { continue }
        let kind = head.draft.kind.rawValue
        guard ["workflow_method", "executable_tool", "failure_experience", "capability_lesson"].contains(kind),
              let body = head.draft.body[kind]?.objectValue else { continue }
        let text = ([head.draft.title, kind] + ["purpose", "domain", "applies_when", "observed_issue", "rationale"]
          .map { body.string($0) }).joined(separator: "\n")
        func matches(_ term: String) -> Bool {
          text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        let score = pinInitial ? Set(initialTerms.filter(matches)).count : 0
        guard pinInitial ? score > 0 : terms.allSatisfy(matches) else { continue }
        let state: String
        switch kind {
        case "capability_lesson": state = body.string("decision") == "retain" ? "retained_lesson" : "historical_lesson"
        case "failure_experience": state = "observed_failure"
        default: state = "unverified_candidate"
        }
        var entry: AgentMcpJSONObject = ["object_id": .string(head.reference.objectId), "revision": .int(head.reference.revision),
          "sha256": .string(head.reference.sha256), "kind": .string(kind), "title": .string(head.draft.title),
          "state": .string(state)]
        if pinInitial {
          entry.removeValue(forKey: "title")
          ranked.append((score, entry))
          continue
        }
        entries.append(.object(entry))
        if entries.count == 8 { break }
      }
      if pinInitial {
        let selected = ranked.sorted { left, right in
          left.score == right.score ? left.entry.string("object_id") < right.entry.string("object_id") : left.score > right.score
        }.prefix(4).map { AgentMcpJSONValue.object($0.entry) }
        let saved: AgentMcpJSONObject = ["capabilities": .array(selected)]
        try database.insertResearchRecord(saved, conversationId: scope.conversationId, key: pinKey, revision: 0)
        return saved
      }
      let next = scanned < keys.count && scanned > 0 ? String(keys[scanned - 1].dropFirst("object:".count)) : nil
      return ["capabilities": .array(entries), "next_cursor": next.map(AgentMcpJSONValue.string) ?? .null,
        "grants_permissions": .bool(false), "trust": .string("directory_not_execution_authority")]
    }
  }

  private func recallCloudProblems(_ input: AgentMcpJSONObject,
                                   scope: AgentCollaborationToolEvidenceScope) throws -> AgentMcpJSONObject {
    guard Set(input.keys).isSubset(of: ["mode", "cursor"]),
          case .string(let cursor) = input["cursor"] ?? .string(""),
          cursor.isEmpty || (cursor.utf8.count == 64 &&
            cursor.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }) else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    return try access { database in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            team.members.contains(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }),
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let ids = try database.cloudProblemIds(scope: scope, after: cursor, limit: 9)
      let page = ids.prefix(8)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let entries = try page.map { id -> AgentMcpJSONValue in
        guard let original = try database.cloudEvidence(id: id, conversationId: scope.conversationId),
              original.observedFailure, original.scope.conversationId == scope.conversationId,
              original.scope.turnId != scope.turnId || original.scope == scope else {
          throw AgentTeamHistoryDatabase.Failure.corrupt
        }
        let hash = try SHA256.hash(data: encoder.encode(original)).map { String(format: "%02x", $0) }.joined()
        return .object(["evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_cloud_tool"),
          "tool": .string(original.call.name), "status": .string("failed"), "cause": .string("not_diagnosed")])
      }
      return ["problems": .array(entries), "next_cursor": ids.count > page.count ? page.last.map(AgentMcpJSONValue.string) ?? .null : .null]
    }
  }

  private static func cloudReadCoverageKey(scope: AgentCollaborationToolEvidenceScope, id: String, hash: String) -> String {
    "cloud-read-coverage:" + readCoverageDigest(scope: scope, id: id, hash: hash)
  }

  private static func readCoverageDigest(scope: AgentCollaborationToolEvidenceScope, id: String, hash: String) -> String {
    AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "group": .string(scope.conversationId), "turn": .string(scope.turnId),
      "member": .string(scope.memberId), "source": .string(scope.sourceId),
      "evidence": .string(id), "sha256": .string(hash)
    ])
  }

  private static func freezeCloudReads(_ references: [AgentMcpJSONObject], scope: AgentCollaborationToolEvidenceScope,
                                       database: AgentTeamHistoryDatabase,
                                       requireFailure: Bool = false) throws -> [AgentCollaborationFrozenCloudRead] {
    guard references.count <= 32 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var seen = Set<String>()
    var foundFailure = false
    let reads = try references.map { reference in
      let id = reference.string("evidence_id")
      let hash = reference.string("sha256")
      guard Set(reference.keys) == Set(["evidence_id", "sha256"]),
            [id, hash].allSatisfy({ $0.utf8.count == 64 &&
              $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }),
            seen.insert(id).inserted,
            let original = try database.cloudEvidence(id: id, conversationId: scope.conversationId),
            original.scope.conversationId == scope.conversationId,
            original.scope.turnId != scope.turnId || original.scope == scope else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let data = try encoder.encode(original)
      let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      let total = Int64(String(decoding: data, as: UTF8.self).count)
      let key = cloudReadCoverageKey(scope: scope, id: id, hash: hash)
      guard actualHash == hash,
            let coverage = try database.researchRecord(AgentCollaborationReadCoverage.self,
              conversationId: scope.conversationId, key: key, revision: 0),
            coverage.contiguousEnd == total else { throw AgentTeamHistoryDatabase.Failure.stale }
      if requireFailure {
        guard !original.call.name.lowercased().contains("recall") else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        foundFailure = foundFailure || original.observedFailure
      }
      return AgentCollaborationFrozenCloudRead(evidenceId: id, sha256: hash, totalCharacters: total)
    }
    guard !requireFailure || foundFailure else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return reads
  }

  func recoverable(conversationId: String) -> [AgentTeamExecutionSnapshot] {
    guard !conversationId.isBlank else { return [] }
    return (try? access { try $0.snapshots(conversation: conversationId, recoverableOnly: true) }) ?? []
  }

  func publishResearchObjects(_ drafts: [AgentCollaborationResearchDraft], runId: String,
                              conversationId: String, turnId: String, memberId: String,
                              sourceId: String, milestone: (id: String, hash: String)? = nil,
                              finalMilestones: [String] = [])
    throws -> AgentCollaborationResearchPublication {
    guard !drafts.isEmpty || !finalMilestones.isEmpty, drafts.count <= 32, !sourceId.isBlank,
          finalMilestones.count <= 32, Set(finalMilestones).count == finalMilestones.count,
          finalMilestones.allSatisfy({ !$0.isBlank && $0.utf8.count <= 160 }),
          milestone == nil || finalMilestones.isEmpty else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    func digest<T: Encodable>(_ value: T) throws -> String {
      let bytes = try encoder.encode(value)
      guard bytes.count <= 256_000 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    let draftHash = try digest(drafts)
    let requestHash = milestone?.hash ?? (finalMilestones.isEmpty ? draftHash : AgentMcpJSONCodec.sha256([
      "draft_sha256": .string(draftHash), "milestones": .array(finalMilestones.map(AgentMcpJSONValue.string))
    ]))
    let baseKey = Self.researchPublicationKey(runId: runId, memberId: memberId, sourceId: sourceId)
    let publicationKey = milestone.map { Self.milestoneKey(baseKey, id: $0.id) } ?? baseKey
    return try access { database in
      guard let snapshot = try database.snapshots(runId: runId).first,
            snapshot.conversationId == conversationId, snapshot.taskId == turnId,
            let member = snapshot.members.first(where: { $0.memberId == memberId && $0.sourceMessageId == sourceId }),
            snapshot.state != .cancelled,
            milestone == nil ? member.status == .succeeded : Self.canPublishMilestone(snapshot, member: member),
            try database.researchRecord(Bool.self, conversationId: conversationId,
              key: "native-evidence-revoked", revision: 0) != true else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      if let prior = try database.researchRecord(AgentCollaborationResearchPublication.self,
        conversationId: conversationId, key: publicationKey, revision: 0) {
        guard prior.requestHash == requestHash else { throw AgentTeamHistoryDatabase.Failure.stale }
        return prior
      }
      var revisions: [AgentCollaborationResearchRevision] = []
      var linked: [AgentCollaborationResearchReference] = []
      for id in finalMilestones {
        guard let prior = try database.researchRecord(AgentCollaborationResearchPublication.self,
          conversationId: conversationId, key: Self.milestoneKey(baseKey, id: id), revision: 0)
        else { throw AgentTeamHistoryDatabase.Failure.stale }
        for reference in prior.references where !linked.contains(reference) { linked.append(reference) }
      }
      var objectIds = Set<String>()
      let transferBatchUpdates = Set(drafts.compactMap(\.objectId).filter { !$0.isBlank })
      let revisedInBatch = Set(drafts.compactMap(\.objectId).filter { !$0.isBlank })
      var replayBytes = 0
      for draft in drafts {
        guard !draft.id.isBlank, draft.id.utf8.count <= 160, !draft.title.isBlank,
              draft.title.utf8.count <= 960, !draft.body.isEmpty,
              draft.baseRevision >= 0, draft.baseRevision < Int64.max else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        if draft.kind == .capabilityGap || draft.kind == .innovation {
          guard AgentCollaborationEvolutionIntake.validates(draft) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        }
        let references = draft.observations ?? []
        var frozenReads: [AgentCollaborationFrozenCloudRead]? = nil
        var expectedUtilities: [String: Double]? = nil
        var expectedInformation: [String: Double]? = nil
        var hypothesisFeedback: AgentMcpJSONObject? = nil
        var carriedPosterior: AgentMcpJSONObject? = nil
        var measuredCases: [AgentCollaborationMeasuredCase]? = nil
        var trialAuthors: [String]? = nil
        var numericReplay: AgentMcpJSONObject? = nil
        if draft.kind == .acceptanceReview {
          let parents = draft.parents.map { AgentCollaborationDocumentaryAcceptance.Reference(
            objectId: $0.objectId, revision: $0.revision, sha256: $0.sha256) }
          guard AgentCollaborationDocumentaryAcceptance.validReviewPublication(body: draft.body, parents: parents)
          else { throw AgentTeamHistoryDatabase.Failure.corrupt }
          if !references.isEmpty {
            let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
              turnId: turnId, memberId: memberId, sourceId: sourceId)
            frozenReads = try Self.freezeCloudReads(references, scope: scope, database: database)
          }
        } else if draft.kind == .workflowMethod {
          guard references.isEmpty, draft.objectId?.isBlank != false, draft.baseRevision == 0,
                let method = draft.body["workflow_method"]?.objectValue,
                method["previous_method"] == nil, method["feedback"] == nil,
                AgentCollaborationWorkflowIntake.validates(method) else {
            throw AgentTeamHistoryDatabase.Failure.corrupt
          }
        } else if draft.kind == .executableTool || draft.kind == .toolTestPlan {
          guard references.isEmpty, draft.objectId?.isBlank != false, draft.baseRevision == 0,
                let spec = draft.body[draft.kind.rawValue]?.objectValue else {
            throw AgentTeamHistoryDatabase.Failure.corrupt
          }
          if draft.kind == .executableTool {
            guard AgentCollaborationToolRegistration.parameterSchema(spec) != nil else {
              throw AgentTeamHistoryDatabase.Failure.corrupt
            }
          } else {
            guard let link = spec["executable_tool"]?.objectValue,
                  Set(link.keys) == Set(["object_id", "revision", "sha256"]),
                  case .int(let version)? = link["revision"], version > 0 else {
              throw AgentTeamHistoryDatabase.Failure.corrupt
            }
            let reference = AgentCollaborationResearchReference(objectId: link.string("object_id"),
              revision: version, sha256: link.string("sha256"))
            guard draft.parents.contains(reference),
                  let candidate = try database.researchRecord(AgentCollaborationResearchRevision.self,
                    conversationId: conversationId, key: "object:" + reference.objectId),
                  candidate.reference == reference, candidate.draft.kind == .executableTool,
                  candidate.turnId != turnId || (candidate.runId == runId && candidate.authorId == memberId),
                  let tool = candidate.draft.body["executable_tool"]?.objectValue,
                  AgentCollaborationToolRegistration.validatesTestPlan(spec, tool: tool)
            else { throw AgentTeamHistoryDatabase.Failure.stale }
          }
        } else if draft.kind == .environmentModel || draft.kind == .actionForecast {
          guard draft.objectId?.isBlank != false, draft.baseRevision == 0,
                let value = draft.body[draft.kind.rawValue]?.objectValue,
                let pinned = try database.goalCheckpoints(runId: runId, revision: 1, newestOnly: true).first,
                pinned.conversationId == conversationId, pinned.turnId == turnId
          else { throw AgentTeamHistoryDatabase.Failure.stale }
          let model: AgentMcpJSONObject
          if draft.kind == .environmentModel {
            model = value
            guard model["previous_model"] == nil, model["feedback"] == nil,
                  AgentCollaborationForecastIntake.hasText(model, ["domain", "environment", "scope", "mechanism",
                    "uncertainty", "valid_when", "refresh_when"]),
                  let confounders = model["confounders"]?.arrayValue, !confounders.isEmpty,
                  confounders.allSatisfy({ $0.stringValue?.isBlank == false }),
                  let basis = model["basis"]?.arrayValue, !basis.isEmpty,
                  let states = model["state"]?.arrayValue, (1...32).contains(states.count)
            else { throw AgentTeamHistoryDatabase.Failure.corrupt }
            for item in basis {
              guard let reference = Self.forecastReference(item), draft.parents.contains(reference),
                    let saved = try database.researchRecord(AgentCollaborationResearchRevision.self,
                      conversationId: conversationId, key: "object:" + reference.objectId),
                    saved.reference == reference,
                    [.artifact, .evidence, .proposal, .counterexample].contains(saved.draft.kind)
              else { throw AgentTeamHistoryDatabase.Failure.stale }
            }
            var stateIds = Set<String>()
            for item in states {
              guard let state = item.objectValue, AgentCollaborationForecastIntake.hasText(state, ["id", "value", "basis"]),
                    stateIds.insert(state.string("id")).inserted,
                    ["observed", "assumed", "unknown"].contains(state.string("epistemic_status")),
                    state.string("epistemic_status") != "observed" ||
                      state["observation"]?.objectValue.map({ references.contains($0) }) == true
              else { throw AgentTeamHistoryDatabase.Failure.corrupt }
            }
            if !references.isEmpty {
              let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
                turnId: turnId, memberId: memberId, sourceId: sourceId)
              frozenReads = try Self.freezeCloudReads(references, scope: scope, database: database)
            }
          } else {
            guard references.isEmpty, let reference = Self.forecastReference(value["task_environment_model"]),
                  draft.parents.contains(reference),
                  let saved = try database.researchRecord(AgentCollaborationResearchRevision.self,
                    conversationId: conversationId, key: "object:" + reference.objectId),
                  saved.reference == reference, saved.draft.kind == .environmentModel,
                  let savedModel = saved.draft.body["task_environment_model"]?.objectValue,
                  case .int(let deadline)? = value["valid_until"], deadline >= AgentControlPlaneClock.nowMillis(),
                  let source = value["source"]?.objectValue, source.string("origin") == "ios_cloud_tool",
                  !source.string("tool").isBlank, !source.string("tool").lowercased().contains("recall"),
                  let pointer = value["report_pointer"]?.stringValue, pointer.isEmpty || pointer.hasPrefix("/"),
                  snapshot.members.contains(where: { $0.memberId == value.string("executor") && $0.deliveryMode != .ignore }),
                  let actions = AgentCollaborationForecastIntake.actionIds(savedModel),
                  let utilities = AgentCollaborationForecastIntake.utilities(value, actions: actions)
            else { throw AgentTeamHistoryDatabase.Failure.stale }
            model = savedModel
            expectedUtilities = utilities
            if value["hypothesis_test"] != nil {
              let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
                turnId: turnId, memberId: memberId, sourceId: sourceId)
              if let test = value["hypothesis_test"]?.objectValue, let prior = test["prior_outcome"] {
                carriedPosterior = try Self.loadHypothesisPosterior(prior, test: test, model: savedModel,
                  parents: draft.parents, scope: scope, database: database)
              }
              guard let information = AgentCollaborationForecastIntake.hypothesisInformation(value,
                carriedPosterior: carriedPosterior) else {
                throw AgentTeamHistoryDatabase.Failure.corrupt
              }
              expectedInformation = information
            }
          }
          let goalHash = SHA256.hash(data: Data(snapshot.goal.utf8)).map { String(format: "%02x", $0) }.joined()
          guard model.string("goal_sha256") == goalHash,
                pinned.contract.contains(where: {
                  $0.id == model.string("criterion_id") && $0.requirement == model.string("requirement")
                }), AgentCollaborationForecastIntake.actionIds(model) != nil
          else { throw AgentTeamHistoryDatabase.Failure.stale }
        } else if draft.kind == .teamExchange {
          let valid = try AgentCollaborationTeamExchangeIntake.validates(draft, author: memberId) { reference in
            guard !drafts.contains(where: { $0.objectId == reference.objectId }),
                  let record = try database.researchRecord(AgentCollaborationResearchRevision.self,
                    conversationId: conversationId, key: "object:" + reference.objectId),
                  record.reference == reference,
                  record.turnId != turnId || (record.runId == runId && record.authorId == memberId) else { return nil }
            return record
          }
          guard valid else { throw AgentTeamHistoryDatabase.Failure.stale }
          if !references.isEmpty {
            let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
              turnId: turnId, memberId: memberId, sourceId: sourceId)
            frozenReads = try Self.freezeCloudReads(references, scope: scope, database: database)
          }
        } else if draft.kind == .failureExperience {
          guard draft.validFailureExperience, !references.isEmpty else { throw AgentTeamHistoryDatabase.Failure.corrupt }
          let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
            turnId: turnId, memberId: memberId, sourceId: sourceId)
          frozenReads = try Self.freezeCloudReads(references, scope: scope, database: database, requireFailure: true)
        } else if draft.kind == .innovationOpportunity {
          guard let pinned = try database.goalCheckpoints(runId: runId, revision: 1, newestOnly: true).first,
                pinned.conversationId == conversationId, pinned.turnId == turnId else {
            throw AgentTeamHistoryDatabase.Failure.stale
          }
          let goalHash = SHA256.hash(data: Data(snapshot.goal.utf8)).map { String(format: "%02x", $0) }.joined()
          let valid = try AgentCollaborationOpportunityIntake.validates(draft, goalHash: goalHash,
            contract: pinned.contract) { reference in
              guard !drafts.contains(where: { $0.objectId == reference.objectId }),
                    let source = try database.researchRecord(AgentCollaborationResearchRevision.self,
                      conversationId: conversationId, key: "object:" + reference.objectId),
                    source.reference == reference,
                    source.turnId != turnId || (source.runId == runId && source.authorId == memberId)
              else { return nil }
              return source.draft.kind.rawValue
          }
          guard valid else { throw AgentTeamHistoryDatabase.Failure.stale }
          if !references.isEmpty {
            let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
              turnId: turnId, memberId: memberId, sourceId: sourceId)
            frozenReads = try Self.freezeCloudReads(references, scope: scope, database: database)
          }
        } else if draft.kind == .experimentPlan {
          guard references.isEmpty else { throw AgentTeamHistoryDatabase.Failure.corrupt }
          let valid = try AgentCollaborationExperimentPlanIntake.validates(draft) { reference in
            guard !drafts.contains(where: { $0.objectId == reference.objectId }),
                  let record = try database.researchRecord(AgentCollaborationResearchRevision.self,
                    conversationId: conversationId, key: "object:" + reference.objectId),
                  record.reference == reference,
                  record.turnId != turnId || (record.runId == runId && record.authorId == memberId) else { return nil }
            return record
          }
          guard valid else { throw AgentTeamHistoryDatabase.Failure.stale }
        } else if draft.kind == .numericModelTrial {
          guard draft.objectId?.isBlank != false, draft.baseRevision == 0, references.isEmpty,
                let trial = draft.body["numeric_model_trial"]?.objectValue,
                var replay = AgentCollaborationNumericTrial.evaluate(trial)
          else { throw AgentTeamHistoryDatabase.Failure.corrupt }
          if let previous = trial["previous_trial"] {
            guard let ref = Self.forecastReference(previous), draft.parents.contains(ref),
                  let saved = try database.researchRecord(AgentCollaborationResearchRevision.self,
                    conversationId: conversationId, key: "object:" + ref.objectId, revision: ref.revision),
                  saved.reference == ref, saved.draft.kind == .numericModelTrial,
                  saved.turnId != turnId || (saved.runId == runId && saved.authorId == memberId),
                  let original = saved.numericReplay,
                  let comparison = AgentCollaborationNumericTrial.comparison(previous: original, current: replay)
            else { throw AgentTeamHistoryDatabase.Failure.stale }
            replay["comparison"] = .object(comparison)
          }
          numericReplay = replay
        } else if draft.kind == .predictionOutcome {
          let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
            turnId: turnId, memberId: memberId, sourceId: sourceId)
          guard draft.objectId?.isBlank != false, draft.baseRevision == 0, references.count == 1,
                let value = draft.body["prediction_outcome"]?.objectValue, Set(value.keys) == ["forecast"],
                let ref = Self.forecastReference(value["forecast"]), draft.parents.contains(ref),
                let forecast = try database.researchRecord(AgentCollaborationResearchRevision.self,
                  conversationId: conversationId, key: "object:" + ref.objectId, revision: ref.revision),
                forecast.reference == ref, forecast.draft.kind == .actionForecast,
                forecast.turnId != turnId || (forecast.runId == runId && forecast.authorId == memberId),
                forecast.expectedInformationGainBits != nil, let registered = forecast.registeredAtMillis,
                let spec = forecast.draft.body["action_forecast"]?.objectValue,
                let deadline = spec["valid_until"]?.intValue,
                let tool = spec["source"]?.objectValue?.string("tool"),
                let ids = spec["hypothesis_test"]?.objectValue?["event_ids"]?.arrayValue?.compactMap(\.strictStringValue),
                let event = spec["events"]?.arrayValue?.compactMap(\.objectValue).first(where: { ids.contains($0.string("id")) })
          else { throw AgentTeamHistoryDatabase.Failure.stale }
          let reads = try Self.freezeCloudReads(references, scope: scope, database: database)
          guard let read = reads.first, let original = try database.cloudEvidence(id: read.evidenceId, conversationId: conversationId),
                original.succeeded, original.call.name == tool, original.scope.memberId == spec.string("executor"),
                original.scope.runId == forecast.runId, original.scope.turnId == forecast.turnId,
                original.startedAtMillis >= registered, original.finishedAtMillis >= original.startedAtMillis,
                forecast.carriedHypothesisPosterior == nil || original.startedAtMillis > registered,
                let feedback = AgentCollaborationForecastIntake.hypothesisFeedback(spec,
                  observed: Self.measurementValue(original.output, pointer: event.string("pointer")),
                  withinValidity: original.finishedAtMillis <= deadline,
                  carriedPosterior: forecast.carriedHypothesisPosterior)
          else { throw AgentTeamHistoryDatabase.Failure.stale }
          hypothesisFeedback = feedback
          frozenReads = reads
        } else if draft.kind == .experimentResult {
          guard draft.objectId?.isBlank != false, draft.baseRevision == 0, !references.isEmpty,
                let value = draft.body["experiment_result"]?.objectValue,
                !value.string("interpretation").isBlank, !value.string("limitations").isBlank,
                let link = AgentCollaborationExperimentPlanIntake.reference(value["plan"]), draft.parents.contains(link),
                let plan = try database.researchRecord(AgentCollaborationResearchRevision.self,
                  conversationId: conversationId, key: "object:" + link.objectId),
                plan.reference == link, plan.draft.kind == .experimentPlan,
                plan.turnId != turnId || (plan.runId == runId && plan.authorId == memberId),
                let registered = plan.registeredAtMillis,
                let spec = plan.draft.body["experiment_plan"]?.objectValue,
                let source = spec["source"]?.objectValue, source.string("origin") == "ios_cloud_tool"
          else { throw AgentTeamHistoryDatabase.Failure.stale }
          let scope = AgentCollaborationToolEvidenceScope(runId: runId, conversationId: conversationId,
            turnId: turnId, memberId: memberId, sourceId: sourceId)
          let reads = try Self.freezeCloudReads(references, scope: scope, database: database)
          var authors = Set<String>()
          let reports = try reads.map { read -> AgentMcpJSONObject in
            guard let original = try database.cloudEvidence(id: read.evidenceId, conversationId: conversationId),
                  original.succeeded, original.startedAtMillis >= registered,
                  original.finishedAtMillis >= original.startedAtMillis,
                  original.call.name == source.string("tool"),
                  let report = Self.measurementReport(original.output, pointer: spec.string("report_pointer"))
            else { throw AgentTeamHistoryDatabase.Failure.stale }
            authors.insert(original.scope.memberId)
            return report
          }
          guard let measured = AgentCollaborationExperimentPlanIntake.measure(reports, plan: plan) else {
            throw AgentTeamHistoryDatabase.Failure.corrupt
          }
          frozenReads = reads
          measuredCases = measured
          trialAuthors = authors.sorted()
        } else if draft.kind == .capabilityLesson {
          frozenReads = try Self.validateCapabilityLesson(draft, scope: .init(runId: runId,
            conversationId: conversationId, turnId: turnId, memberId: memberId, sourceId: sourceId),
            changedIds: Set(drafts.compactMap(\.objectId)), database: database)
        } else if !references.isEmpty {
          throw AgentTeamHistoryDatabase.Failure.corrupt
        }
        let existingId = draft.objectId.flatMap { $0.isBlank ? nil : $0 }
        let objectId = existingId ?? AgentMcpJSONCodec.sha256([
          "group": .string(conversationId), "author": .string(memberId), "id": .string(draft.id)
        ])
        guard objectIds.insert(objectId).inserted else { throw AgentTeamHistoryDatabase.Failure.stale }
        let head = try database.researchRecord(AgentCollaborationResearchRevision.self,
          conversationId: conversationId, key: "object:" + objectId)
        if let head {
          guard existingId != nil, head.authorId == memberId, head.draft.kind == draft.kind,
                head.reference.revision == draft.baseRevision else { throw AgentTeamHistoryDatabase.Failure.stale }
        } else {
          guard existingId == nil, draft.baseRevision == 0 else { throw AgentTeamHistoryDatabase.Failure.stale }
        }
        for parent in draft.parents + (draft.resolves ?? []) {
          guard let existing = try database.researchRecord(AgentCollaborationResearchRevision.self,
            conversationId: conversationId, key: "object:" + parent.objectId, revision: parent.revision),
            existing.reference == parent,
            existing.turnId != turnId || existing.authorId == memberId else {
            throw AgentTeamHistoryDatabase.Failure.stale
          }
        }
        if draft.kind == .transferStudy {
          let valid = try AgentCollaborationTransferIntake.validates(draft) { reference in
            guard !transferBatchUpdates.contains(reference.objectId),
                  let record = try database.researchRecord(AgentCollaborationResearchRevision.self,
                    conversationId: conversationId, key: "object:" + reference.objectId),
                  record.reference == reference else { return nil }
            if record.draft.kind.rawValue == "failure_experience",
               record.frozenCloudReads?.isEmpty != false { return nil }
            return record.draft.kind.rawValue
          }
          guard valid else { throw AgentTeamHistoryDatabase.Failure.stale }
        }
        if draft.kind == .learningAgenda {
          let members = Set(snapshot.members.filter { $0.deliveryMode != .ignore }.map(\.memberId))
          let valid = try AgentCollaborationLearningAgendaIntake.validates(draft, members: members) { reference in
            guard !revisedInBatch.contains(reference.objectId),
                  let gap = try database.researchRecord(AgentCollaborationResearchRevision.self,
                    conversationId: conversationId, key: "object:" + reference.objectId),
                  gap.reference == reference, gap.draft.kind.rawValue == "capability_gap",
                  let options = gap.draft.body["capability_gap"]?.objectValue?["learning_options"]?.arrayValue
            else { return nil }
            return Set(options.compactMap { $0.objectValue?["id"]?.stringValue })
          }
          guard valid else { throw AgentTeamHistoryDatabase.Failure.stale }
        }
        var revision = AgentCollaborationResearchRevision(reference: .init(objectId: objectId,
          revision: draft.baseRevision + 1, sha256: ""), previousHash: head?.reference.sha256,
          runId: runId, turnId: turnId, authorId: memberId, sourceId: sourceId, draft: draft,
          frozenCloudReads: frozenReads, declaredExpectedUtilities: expectedUtilities,
          expectedInformationGainBits: expectedInformation,
          hypothesisFeedback: hypothesisFeedback,
          carriedHypothesisPosterior: carriedPosterior,
          registeredAtMillis: [.experimentPlan, .actionForecast].contains(draft.kind) ? AgentControlPlaneClock.nowMillis() : nil,
          measuredCases: measuredCases, trialAuthors: trialAuthors, numericReplay: numericReplay)
        let bytes = try encoder.encode(revision)
        // Reserve space for the SHA-256 field populated after the digest.
        guard bytes.count <= revision.storageBytesLimit - 64 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        revision.reference.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        if numericReplay != nil {
          replayBytes += bytes.count + 64
          guard replayBytes <= AgentCollaborationResearchRevision.numericReplayBatchBytes else {
            throw AgentTeamHistoryDatabase.Failure.corrupt
          }
        }
        revisions.append(revision)
      }
      for revision in revisions {
        try database.insertResearchRecord(revision, conversationId: conversationId,
          key: "object:" + revision.reference.objectId, revision: revision.reference.revision)
      }
      let receipt = AgentCollaborationResearchPublication(requestHash: requestHash,
        references: linked + revisions.map(\.reference), milestoneId: milestone?.id,
        recordedAtMillis: milestone == nil ? nil : AgentControlPlaneClock.nowMillis())
      try database.insertResearchRecord(receipt, conversationId: conversationId, key: publicationKey, revision: 0)
      return receipt
    }
  }

  private static func validateCapabilityLesson(_ draft: AgentCollaborationResearchDraft,
    scope: AgentCollaborationToolEvidenceScope, changedIds: Set<String>, database: AgentTeamHistoryDatabase)
    throws -> [AgentCollaborationFrozenCloudRead]? {
    let reference = AgentCollaborationExperimentPlanIntake.reference
    guard draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let value = draft.body["capability_lesson"]?.objectValue,
          ["retain", "reject", "revise"].contains(value.string("decision")),
          ["rationale", "applies_when", "avoid_when", "procedure", "transfer_test"].allSatisfy({
            value[$0]?.stringValue?.isBlank == false
          }), let resultRef = reference(value["result"]), let rollback = reference(value["rollback"]),
          draft.parents.contains(resultRef), draft.parents.contains(rollback)
    else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let retaining = value.string("decision") == "retain"
    func exact(_ ref: AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision? {
      guard !retaining || !changedIds.contains(ref.objectId),
            let saved = try database.researchRecord(AgentCollaborationResearchRevision.self,
              conversationId: scope.conversationId, key: "object:" + ref.objectId, revision: retaining ? nil : ref.revision),
            saved.reference == ref, saved.turnId != scope.turnId || (saved.runId == scope.runId && saved.authorId == scope.memberId)
      else { return nil }
      return saved
    }
    guard let result = try exact(resultRef), result.draft.kind == .experimentResult,
          let planRef = reference(result.draft.body["experiment_result"]?.objectValue?["plan"]),
          let plan = try exact(planRef), plan.draft.kind == .experimentPlan,
          let spec = plan.draft.body["experiment_plan"]?.objectValue,
          reference(spec["baseline"]) == rollback, let baseline = try exact(rollback),
          let ideaRef = reference(spec["innovation"]), let idea = try exact(ideaRef),
          idea.draft.kind.rawValue == "innovation"
    else { throw AgentTeamHistoryDatabase.Failure.stale }
    let references = draft.observations ?? []
    if !retaining {
      guard references.isEmpty else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      return nil
    }
    guard let cases = result.measuredCases, AgentCollaborationMeasuredCase.supportsRetention(cases),
          let authors = result.trialAuthors, !authors.isEmpty,
          let required = result.frozenCloudReads, !required.isEmpty
    else { throw AgentTeamHistoryDatabase.Failure.stale }
    var seen = Set<String>()
    var pending = [idea, baseline, plan, result]
    func person(_ id: String) -> String {
      let parts = id.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard let first = parts.first, let uuid = UUID(uuidString: String(first)),
            parts.count == 1 || ["revise", "recheck"].contains(String(parts[1])) else { return id }
      return uuid.uuidString.lowercased()
    }
    let reviewer = person(scope.memberId)
    guard !authors.map(person).contains(reviewer) else {
      throw AgentTeamHistoryDatabase.Failure.stale
    }
    while let record = pending.popLast() {
      guard seen.insert(record.reference.objectId).inserted else { continue }
      guard seen.count <= 128, person(record.authorId) != reviewer else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      for ref in record.draft.parents {
        guard let original = try exact(ref) else { throw AgentTeamHistoryDatabase.Failure.stale }
        pending.append(original)
      }
    }
    let reads = try freezeCloudReads(references, scope: scope, database: database)
    guard required.allSatisfy({ original in
      reads.contains { $0.evidenceId == original.evidenceId && $0.sha256 == original.sha256 &&
        $0.totalCharacters == original.totalCharacters }
    }) else { throw AgentTeamHistoryDatabase.Failure.stale }
    return reads
  }

  private static func measurementReport(_ raw: String, pointer: String) -> AgentMcpJSONObject? {
    guard let node = measurementValue(raw, pointer: pointer) else { return nil }
    if let report = node.objectValue { return report }
    guard let encoded = node.stringValue else { return nil }
    return try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(encoded.utf8))
  }

  private static func measurementValue(_ raw: String, pointer: String) -> AgentMcpJSONValue? {
    guard var node = try? JSONDecoder().decode(AgentMcpJSONValue.self, from: Data(raw.utf8)),
          pointer.isEmpty || pointer.hasPrefix("/") else { return nil }
    for part in pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
      let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
      if let child = node.objectValue?[key] {
        node = child
      } else if let list = node.arrayValue, let index = Int(key), String(index) == key, list.indices.contains(index) {
        node = list[index]
      } else {
        return nil
      }
    }
    return node
  }

  private static func loadHypothesisPosterior(_ prior: AgentMcpJSONValue, test: AgentMcpJSONObject,
    model: AgentMcpJSONObject, parents: [AgentCollaborationResearchReference],
    scope: AgentCollaborationToolEvidenceScope, database: AgentTeamHistoryDatabase) throws -> AgentMcpJSONObject {
    func exact(_ value: AgentMcpJSONValue?, kind: AgentCollaborationResearchDraft.Kind)
      throws -> AgentCollaborationResearchRevision? {
      guard let ref = forecastReference(value),
            let saved = try database.researchRecord(AgentCollaborationResearchRevision.self,
              conversationId: scope.conversationId, key: "object:" + ref.objectId, revision: ref.revision),
            saved.reference == ref, saved.draft.kind == kind,
            saved.turnId != scope.turnId || (saved.runId == scope.runId && saved.authorId == scope.memberId)
      else { return nil }
      return saved
    }
    guard let ref = forecastReference(prior), parents.contains(ref),
          let outcome = try exact(prior, kind: .predictionOutcome),
          let feedback = outcome.hypothesisFeedback, feedback.string("state") == "updated_from_observation",
          let posterior = feedback["posterior"]?.objectValue,
          let observation = outcome.frozenCloudReads?.first,
          let original = try database.cloudEvidence(id: observation.evidenceId, conversationId: scope.conversationId),
          original.finishedAtMillis < AgentControlPlaneClock.nowMillis(),
          let previous = try exact(outcome.draft.body["prediction_outcome"]?.objectValue?["forecast"], kind: .actionForecast),
          let forecast = previous.draft.body["action_forecast"]?.objectValue,
          let oldTest = forecast["hypothesis_test"]?.objectValue,
          AgentCollaborationForecastIntake.sameHypothesisQuestion(oldTest, test),
          let environment = try exact(forecast["task_environment_model"], kind: .environmentModel),
          let oldModel = environment.draft.body["task_environment_model"]?.objectValue,
          ["goal_sha256", "criterion_id", "requirement", "domain", "environment", "scope"].allSatisfy({
            Data(oldModel.string($0).utf8) == Data(model.string($0).utf8)
          }) else { throw AgentTeamHistoryDatabase.Failure.stale }
    return posterior
  }

  private static func forecastReference(_ value: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let object = value?.objectValue, Set(object.keys) == Set(["object_id", "revision", "sha256"]),
          case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return .init(objectId: object.string("object_id"), revision: revision, sha256: object.string("sha256"))
  }

  private static func researchPublicationKey(runId: String, memberId: String, sourceId: String) -> String {
    "publication:" + AgentMcpJSONCodec.sha256([
      "run": .string(runId), "member": .string(memberId), "source": .string(sourceId)
    ])
  }

  private static func milestonePrefix(_ baseKey: String) -> String {
    baseKey + ":milestone:"
  }

  private static func milestoneKey(_ baseKey: String, id: String) -> String {
    milestonePrefix(baseKey) + AgentMcpJSONCodec.sha256(["id": .string(id)])
  }

  private static func canPublishMilestone(_ snapshot: AgentTeamExecutionSnapshot, member: AgentTeamMemberSnapshot) -> Bool {
    snapshot.state == .running && member.deliveryMode == .observe && !member.status.isTerminal &&
      (member.dispatchCheckpoint == .dispatching || member.dispatchCheckpoint == .accepted)
  }

  func publishCollaborationMilestone(_ input: AgentMcpJSONObject,
                                     scope: AgentCollaborationToolEvidenceScope) throws -> AgentMcpJSONObject {
    let mode = input.string("mode")
    let id = input.string("milestone_id")
    if mode == "validate_assessment" {
      guard Set(input.keys) == ["mode", "artifact"], let raw = input["artifact"]?.strictStringValue,
            raw.utf8.count <= 131_072 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      let established = try access { database in
        guard let team = try database.snapshots(runId: scope.runId).first,
              team.conversationId == scope.conversationId, team.taskId == scope.turnId, team.state == .running,
              team.members.contains(where: { $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId &&
                $0.deliveryMode != .ignore && !$0.status.isTerminal &&
                ($0.dispatchCheckpoint == .dispatching || $0.dispatchCheckpoint == .accepted) }),
              try database.researchRecord(Bool.self, conversationId: scope.conversationId,
                key: "native-evidence-revoked", revision: 0) != true
        else { throw AgentTeamHistoryDatabase.Failure.stale }
        return try database.goalCheckpoints(runId: scope.runId, revision: 1, newestOnly: true).first != nil
      }
      return AgentCollaborationGoalAssessmentPolicy.preflight(raw, establishedContract: established)
    }
    if ["status", "receipt", "list"].contains(mode) {
      return try access { database in
        guard let snapshot = try database.snapshots(runId: scope.runId).first,
              snapshot.conversationId == scope.conversationId, snapshot.taskId == scope.turnId,
              let member = snapshot.members.first(where: { $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId }),
              Self.canPublishMilestone(snapshot, member: member),
              try database.researchRecord(Bool.self, conversationId: scope.conversationId,
                key: "native-evidence-revoked", revision: 0) != true
        else { throw AgentTeamHistoryDatabase.Failure.stale }
        if mode == "status", Set(input.keys) == ["mode"] {
          return ["success": .bool(true), "status": .string("available")]
        }
        let base = Self.researchPublicationKey(runId: scope.runId, memberId: scope.memberId, sourceId: scope.sourceId)
        if mode == "list" {
          guard Set(input.keys).isSubset(of: ["mode", "cursor"]),
                case .string(let cursor) = input["cursor"] ?? .string("") else {
            throw AgentTeamHistoryDatabase.Failure.corrupt
          }
          let prefix = Self.milestonePrefix(base)
          let suffix = cursor.dropFirst(prefix.utf8.count)
          guard cursor.isEmpty || (cursor.hasPrefix(prefix) && suffix.utf8.count == 64 &&
            suffix.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })) else {
            throw AgentTeamHistoryDatabase.Failure.stale
          }
          let keys = try database.milestoneKeys(conversationId: scope.conversationId, prefix: prefix, after: cursor)
          let rows: [AgentMcpJSONValue] = try keys.prefix(32).map { key in
            guard let saved = try database.researchRecord(AgentCollaborationResearchPublication.self,
              conversationId: scope.conversationId, key: key, revision: 0),
              let id = saved.milestoneId, let recorded = saved.recordedAtMillis, Self.milestoneKey(base, id: id) == key
            else { throw AgentTeamHistoryDatabase.Failure.corrupt }
            return .object(["milestone_id": .string(id), "raw_sha256": .string(saved.requestHash),
              "recorded_at": .int(recorded), "revision_count": .int(Int64(saved.references.count))])
          }
          return ["success": .bool(true), "status": .string("returned"), "milestones": .array(rows),
            "next_cursor": keys.count > 32 ? .string(keys[31]) : .null,
            "trust": .string("host_recorded_interim_versions_not_task_completion_or_verification")]
        }
        let hash = input.string("artifact_sha256")
        guard mode == "receipt", Set(input.keys) == ["mode", "milestone_id", "artifact_sha256"],
              !id.isBlank, id.utf8.count <= 160, hash.utf8.count == 64,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        let saved = try database.researchRecord(AgentCollaborationResearchPublication.self,
          conversationId: scope.conversationId, key: Self.milestoneKey(base, id: id), revision: 0)
        if let saved, saved.requestHash == hash { return Self.milestoneReceipt(saved, id: id, status: "recorded") }
        if let rejected = try database.researchRecord(AgentCollaborationMilestoneRejection.self,
          conversationId: scope.conversationId, key: Self.milestoneRejectionKey(base, id: id, hash: hash), revision: 0) {
          return Self.milestoneRejectedReceipt(id: id, hash: hash, reason: rejected.reason)
        }
        if saved == nil {
          return ["success": .bool(false), "status": .string("not_recorded")]
        }
        throw AgentTeamHistoryDatabase.Failure.stale
      }
    }
    guard !id.isBlank, id.utf8.count <= 160,
          Set(input.keys) == ["mode", "milestone_id", "artifact"], input["mode"] == .string("publish"),
          let raw = input["artifact"]?.strictStringValue, raw.utf8.count <= 131_072
    else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let hash = Self.replyHash(raw)
    do {
      guard let envelope = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(raw.utf8)),
            !envelope.string("summary").isBlank,
            let drafts = try? AgentCollaborationResearchEnvelope.publication(in: raw)
      else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      let receipt = try publishResearchObjects(drafts, runId: scope.runId, conversationId: scope.conversationId,
        turnId: scope.turnId, memberId: scope.memberId, sourceId: scope.sourceId, milestone: (id, hash))
      return Self.milestoneReceipt(receipt, id: id, status: "published")
    } catch AgentTeamHistoryDatabase.Failure.corrupt {
      return try retainRejectedMilestone(raw, id: id, hash: hash, scope: scope, reason: "invalid_artifact")
    } catch AgentTeamHistoryDatabase.Failure.stale {
      return try retainRejectedMilestone(raw, id: id, hash: hash, scope: scope, reason: "stale_binding_or_revision")
    }
  }

  private func retainRejectedMilestone(_ raw: String, id: String, hash: String,
                                       scope: AgentCollaborationToolEvidenceScope, reason: String) throws -> AgentMcpJSONObject {
    try access { database in
      guard let snapshot = try database.snapshots(runId: scope.runId).first,
            snapshot.conversationId == scope.conversationId, snapshot.taskId == scope.turnId,
            let member = snapshot.members.first(where: { $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId }),
            Self.canPublishMilestone(snapshot, member: member),
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true
      else { throw AgentTeamHistoryDatabase.Failure.stale }
      let base = Self.researchPublicationKey(runId: scope.runId, memberId: scope.memberId, sourceId: scope.sourceId)
      let key = Self.milestoneRejectionKey(base, id: id, hash: hash)
      if let saved = try database.researchRecord(AgentCollaborationMilestoneRejection.self,
        conversationId: scope.conversationId, key: key, revision: 0) {
        guard saved.artifact == Data(raw.utf8) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        return Self.milestoneRejectedReceipt(id: id, hash: hash, reason: saved.reason)
      }
      try database.insertResearchRecord(AgentCollaborationMilestoneRejection(
        artifact: Data(raw.utf8), reason: reason), conversationId: scope.conversationId, key: key, revision: 0)
      return Self.milestoneRejectedReceipt(id: id, hash: hash, reason: reason)
    }
  }

  private static func milestoneRejectionKey(_ base: String, id: String, hash: String) -> String {
    base + ":rejected-milestone:" + AgentMcpJSONCodec.sha256(["id": .string(id), "hash": .string(hash)])
  }

  private static func milestoneRejectedReceipt(id: String, hash: String, reason: String) -> AgentMcpJSONObject {
    ["success": .bool(false), "status": .string(reason), "milestone_id": .string(id),
      "artifact_sha256": .string(hash), "rejected_draft_preserved": .bool(true)]
  }

  private static func milestoneReceipt(_ receipt: AgentCollaborationResearchPublication, id: String,
                                       status: String) -> AgentMcpJSONObject {
    ["success": .bool(true), "status": .string(status), "milestone_id": .string(id),
      "artifact_sha256": .string(receipt.requestHash), "references": .array(receipt.references.map {
        .object(["object_id": .string($0.objectId), "revision": .int($0.revision), "sha256": .string($0.sha256)])
      })]
  }

  func publishSavedResearchReply(_ raw: String, scope: AgentCollaborationToolEvidenceScope) throws {
    guard try committedResearchRevisions(scope: scope) == nil else { return }
    let hash = Self.replyHash(raw)
    guard try access({ try Self.savedResearchReply(scope, database: $0).map(Self.replyHash) }) == hash else {
      throw AgentTeamHistoryDatabase.Failure.stale
    }
    let drafts: [AgentCollaborationResearchDraft]
    let milestones: [String]
    do {
      guard raw.utf8.count <= 256_000, raw.contains(AgentCollaborationResearchEnvelope.wireFormat) else { return }
      let envelope = try JSONDecoder().decode(AgentCollaborationResearchEnvelope.self, from: Data(raw.utf8))
      guard envelope.format == AgentCollaborationResearchEnvelope.wireFormat else { return }
      drafts = envelope.workspace ?? []
      milestones = envelope.milestones ?? []
    } catch {
      try recordResearchRejection(raw, scope: scope, reason: .malformedEnvelope)
      throw error
    }
    guard !drafts.isEmpty || !milestones.isEmpty else { return }
    do {
      _ = try publishResearchObjects(drafts, runId: scope.runId, conversationId: scope.conversationId,
        turnId: scope.turnId, memberId: scope.memberId, sourceId: scope.sourceId, finalMilestones: milestones)
    } catch AgentTeamHistoryDatabase.Failure.corrupt {
      try recordResearchRejection(raw, scope: scope, reason: .invalidDraft)
      throw AgentTeamHistoryDatabase.Failure.corrupt
    } catch AgentTeamHistoryDatabase.Failure.stale {
      try recordResearchRejection(raw, scope: scope, reason: .staleBindingOrRevision)
      throw AgentTeamHistoryDatabase.Failure.stale
    }
  }

  private static func researchRejectionKey(_ scope: AgentCollaborationToolEvidenceScope) -> String {
    "rejection:" + researchPublicationKey(runId: scope.runId, memberId: scope.memberId, sourceId: scope.sourceId)
  }

  private static func replyHash(_ raw: String) -> String {
    SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func recordResearchRejection(_ raw: String, scope: AgentCollaborationToolEvidenceScope,
                                       reason: AgentCollaborationPublicationRejection.Reason) throws {
    try access { database in
      let key = Self.researchRejectionKey(scope)
      let hash = Self.replyHash(raw)
      guard try Self.savedResearchReply(scope, database: database).map(Self.replyHash) == hash else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let publication = Self.researchPublicationKey(runId: scope.runId, memberId: scope.memberId, sourceId: scope.sourceId)
      guard try database.researchRecord(AgentCollaborationResearchPublication.self,
        conversationId: scope.conversationId, key: publication, revision: 0) == nil else { return }
      if try database.researchRecord(AgentCollaborationPublicationRejection.self,
        conversationId: scope.conversationId, key: key, revision: 0) == nil {
        try database.insertResearchRecord(AgentCollaborationPublicationRejection(scope: scope, replyHash: hash, reason: reason),
          conversationId: scope.conversationId, key: key, revision: 0)
      }
    }
  }

  func rejectedResearchReply(scope: AgentCollaborationToolEvidenceScope)
    throws -> (raw: String, rejection: AgentCollaborationPublicationRejection)? {
    try access { database in
      let publication = Self.researchPublicationKey(runId: scope.runId, memberId: scope.memberId, sourceId: scope.sourceId)
      guard try database.researchRecord(AgentCollaborationResearchPublication.self,
        conversationId: scope.conversationId, key: publication, revision: 0) == nil,
        let rejection = try database.researchRecord(AgentCollaborationPublicationRejection.self,
          conversationId: scope.conversationId, key: Self.researchRejectionKey(scope), revision: 0),
        rejection.scope == scope, let raw = try Self.savedResearchReply(scope, database: database),
        Self.replyHash(raw) == rejection.replyHash else { return nil }
      return (raw, rejection)
    }
  }

  private static func savedResearchReply(_ scope: AgentCollaborationToolEvidenceScope,
                                         database: AgentTeamHistoryDatabase) throws -> String? {
    guard try database.researchRecord(Bool.self, conversationId: scope.conversationId,
            key: "native-evidence-revoked", revision: 0) != true,
          let snapshot = try database.snapshots(runId: scope.runId).first,
          snapshot.conversationId == scope.conversationId, snapshot.taskId == scope.turnId,
          snapshot.state != .cancelled else { return nil }
    return snapshot.members.first {
      $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId && $0.status == .succeeded
    }?.replyContent
  }

  func committedResearchRevisions(scope: AgentCollaborationToolEvidenceScope) throws -> [AgentCollaborationResearchRevision]? {
    try access { database in
      guard let snapshot = try database.snapshots(runId: scope.runId).first,
            snapshot.conversationId == scope.conversationId, snapshot.taskId == scope.turnId,
            snapshot.state != .cancelled, snapshot.members.contains(where: {
              $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId && $0.status == .succeeded
            }) else { throw AgentTeamHistoryDatabase.Failure.stale }
      let key = Self.researchPublicationKey(runId: scope.runId, memberId: scope.memberId, sourceId: scope.sourceId)
      guard let receipt = try database.researchRecord(AgentCollaborationResearchPublication.self,
        conversationId: scope.conversationId, key: key, revision: 0) else { return nil }
      return try receipt.references.map { reference in
        guard let revision = try database.researchRecord(AgentCollaborationResearchRevision.self,
          conversationId: scope.conversationId, key: "object:" + reference.objectId, revision: reference.revision),
          revision.reference == reference, revision.runId == scope.runId, revision.turnId == scope.turnId,
          revision.authorId == scope.memberId, revision.sourceId == scope.sourceId else {
          throw AgentTeamHistoryDatabase.Failure.corrupt
        }
        if let citations = revision.draft.observations, !citations.isEmpty {
          guard [.acceptanceReview, .environmentModel, .teamExchange, .failureExperience, .innovationOpportunity,
                 .experimentResult, .predictionOutcome, .capabilityLesson].contains(revision.draft.kind),
                let reads = revision.frozenCloudReads,
                reads.count == citations.count,
                zip(reads, citations).allSatisfy({ pair in
                  pair.0.evidenceId == pair.1.string("evidence_id") &&
                    pair.0.sha256 == pair.1.string("sha256") && pair.0.totalCharacters > 0
                }) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        }
        return revision
      }
    }
  }

  func removeResearchObjects(conversationId: String) {
    guard !conversationId.isBlank else { return }
    _ = try? access { database in
      try database.removeResearchRecords(conversationId: conversationId)
      try database.insertResearchRecord(true, conversationId: conversationId, key: "native-evidence-revoked", revision: 0)
    }
  }

  func updateSavedToolExecution(_ operation: AgentCollaborationSavedToolExecution.Operation,
                                scope: AgentCollaborationSavedToolExecution.Scope,
                                allowAdmission: Bool = true,
                                process: String = AgentCollaborationSavedToolExecution.processID,
                                now: Int64 = AgentControlPlaneClock.nowMillis()) throws
    -> AgentCollaborationSavedToolExecution.Outcome {
    try access { database in
      let assignment = scope.assignment
      guard let team = try database.snapshots(runId: assignment.runId).first,
            team.state == .running, team.conversationId == assignment.conversationId, team.taskId == assignment.turnId,
            team.members.contains(where: { $0.memberId == assignment.memberId && $0.sourceMessageId == assignment.sourceId &&
              $0.deliveryMode != .ignore && !$0.status.isTerminal && $0.dispatchAllowsSavedToolTest == true &&
              ($0.dispatchCheckpoint == .dispatching || $0.dispatchCheckpoint == .accepted) }),
            try database.researchRecord(Bool.self, conversationId: assignment.conversationId,
              key: "native-evidence-revoked", revision: 0) != true else { throw AgentTeamHistoryDatabase.Failure.stale }
      let key = scope.key(operation.id)
      let existing = try database.researchRecord(AgentCollaborationSavedToolExecution.Record.self,
        conversationId: assignment.conversationId, key: key, revision: 0)
      let outcome = try AgentCollaborationSavedToolExecution.apply(operation, scope: scope,
        existing: existing, process: process, now: now, allowAdmission: allowAdmission)
      if let record = outcome.record, record != existing {
        if existing != nil { try database.removeResearchRecord(conversationId: assignment.conversationId, key: key) }
        try database.insertResearchRecord(record, conversationId: assignment.conversationId, key: key, revision: 0)
      }
      return outcome
    }
  }

  func prepareSavedToolTest(_ reference: AgentCollaborationResearchReference, timeoutMillis: Int64,
                            scope: AgentCollaborationToolEvidenceScope) throws -> AgentCollaborationSavedToolTest.Prepared {
    try access { database in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.state == .running, team.conversationId == scope.conversationId, team.taskId == scope.turnId,
            let member = team.members.first(where: { $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId }),
            member.deliveryMode != .ignore, !member.status.isTerminal, member.dispatchAllowsSavedToolTest == true,
            member.dispatchCheckpoint == .dispatching || member.dispatchCheckpoint == .accepted,
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true else { throw AgentTeamHistoryDatabase.Failure.stale }
      func current(_ ref: AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision {
        guard let record = try database.researchRecord(AgentCollaborationResearchRevision.self,
                conversationId: scope.conversationId, key: "object:" + ref.objectId),
              record.reference == ref else { throw AgentTeamHistoryDatabase.Failure.stale }
        if record.turnId == scope.turnId {
          guard record.runId == scope.runId, (record.authorId == scope.memberId && record.sourceId == scope.sourceId) ||
            (member.dispatchDependencyMemberIds?.contains(record.authorId) == true &&
              team.members.contains(where: { $0.memberId == record.authorId && $0.sourceMessageId == record.sourceId &&
                $0.deliveryMode != .ignore && $0.status.isTerminal })) else { throw AgentTeamHistoryDatabase.Failure.stale }
        }
        return record
      }
      let plan = try current(reference)
      guard plan.draft.kind == .toolTestPlan,
            let test = plan.draft.body["tool_test_plan"]?.objectValue,
            let tool = AgentCollaborationSavedToolTest.reference(test["executable_tool"]),
            let prepared = AgentCollaborationSavedToolTest.prepare(plan: plan, tool: try current(tool),
              timeoutMillis: timeoutMillis) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      return prepared
    }
  }

  func recordNativeObservation(_ observation: AgentCollaborationNativeToolObservation) throws -> AgentMcpJSONObject {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(observation)
    guard !observation.result.receipt.invocationId.isBlank, encoded.count <= 256_000 else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    let hash = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    let id = Self.nativeObservationId(observation, hash: hash)
    return try access { database in
      guard try database.researchRecord(Bool.self, conversationId: observation.conversationId,
        key: "native-evidence-revoked", revision: 0) != true,
        let team = try database.snapshots(runId: observation.runId).first,
        team.conversationId == observation.conversationId, team.taskId == observation.turnId,
        !team.state.isTerminal, team.members.contains(where: {
          $0.memberId == observation.memberId && $0.sourceMessageId == observation.sourceId && !$0.status.isTerminal
        }) else { throw AgentTeamHistoryDatabase.Failure.stale }
      let key = "native-evidence:" + id
      if let prior = try database.researchRecord(AgentCollaborationNativeToolObservation.self,
        conversationId: observation.conversationId, key: key, revision: 0) {
        guard try encoder.encode(prior) == encoded else { throw AgentTeamHistoryDatabase.Failure.stale }
      } else {
        try database.insertResearchRecord(observation, conversationId: observation.conversationId, key: key, revision: 0)
      }
      return [
        "evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_native_tool"),
        "trust": .string("execution_observed_not_claim_verified")
      ]
    }
  }

  private static func nativeObservationId(_ observation: AgentCollaborationNativeToolObservation, hash: String) -> String {
    AgentMcpJSONCodec.sha256([
      "run": .string(observation.runId), "source": .string(observation.sourceId),
      "invocation": .string(observation.result.receipt.invocationId), "sha256": .string(hash)
    ])
  }

  func archiveDesktopToolEvidence(request: AgentDesktopToolEvidenceWire.Request,
                                  descriptor: AgentDesktopToolEvidenceWire.Descriptor,
                                  pages: [Data]) throws -> AgentDesktopToolEvidenceWire.ArchiveReceipt {
    guard request.verifyOriginal(pages, descriptor: descriptor) != nil,
          let source = request.binding.teamSource else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let binding = request.binding
    let conversation = binding.identity.conversationId
    let id = request.archiveId(descriptor)
    let receipt = AgentDesktopToolEvidenceWire.ArchiveReceipt(archiveId: id, desktopId: binding.desktopId,
      evidenceId: descriptor.evidenceId, sha256: descriptor.sha256, generation: request.generation,
      totalBytes: descriptor.totalBytes, pageCount: descriptor.pageCount)
    return try access { database in
      guard let owner = try database.replyOwner(source: binding.sourceIdentity, conversation: conversation,
              turn: binding.identity.turnId, contact: binding.contactId),
            owner.supervisorRunId == source.supervisorRunId, owner.memberId == source.memberId,
            owner.deliveryMode == .observe, owner.observedGeneration == request.generation,
            let team = try database.snapshots(runId: owner.supervisorRunId).first,
            team.conversationId == conversation, team.taskId == binding.identity.turnId,
            team.state != .cancelled,
            team.members.contains(where: { $0.memberId == owner.memberId &&
              $0.sourceMessageId == owner.sourceMessageId && $0.status == .succeeded }) else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let key = "desktop-evidence:" + id
      if let prior = try database.researchRecord(AgentDesktopToolEvidenceWire.ArchiveReceipt.self,
        conversationId: conversation, key: key, revision: 0) {
        guard prior == receipt else { throw AgentTeamHistoryDatabase.Failure.stale }
        try database.removeResearchRecord(conversationId: conversation, key: request.stagedPageKey(descriptor))
        return prior
      }
      for (index, page) in pages.enumerated() {
        try database.insertResearchRecord(page, conversationId: conversation, key: key, revision: Int64(index + 1))
      }
      try database.insertResearchRecord(receipt, conversationId: conversation, key: key, revision: 0)
      try database.removeResearchRecord(conversationId: conversation, key: request.stagedPageKey(descriptor))
      return receipt
    }
  }

  func stageDesktopEvidencePage(_ response: AgentMcpJSONObject, desktopId: String,
                                request: AgentDesktopToolEvidenceWire.Request,
                                descriptor: AgentDesktopToolEvidenceWire.Descriptor, index: Int) throws -> Data {
    guard let page = request.verifyPage(response, authenticatedDesktopId: desktopId,
      descriptor: descriptor, index: index) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return try access { database in
      let conversation = request.binding.identity.conversationId
      let key = request.stagedPageKey(descriptor)
      let revision = Int64(index + 1)
      if let saved = try database.researchRecord(Data.self, conversationId: conversation, key: key, revision: revision) {
        guard saved == page else { throw AgentTeamHistoryDatabase.Failure.stale }
      } else {
        try database.insertResearchRecord(page, conversationId: conversation, key: key, revision: revision)
      }
      return page
    }
  }

  func stagedDesktopEvidencePage(request: AgentDesktopToolEvidenceWire.Request,
                                 descriptor: AgentDesktopToolEvidenceWire.Descriptor, index: Int) throws -> Data? {
    guard descriptor.canImport, (0..<descriptor.pageCount).contains(index) else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    return try access { database in
      try database.researchRecord(Data.self, conversationId: request.binding.identity.conversationId,
        key: request.stagedPageKey(descriptor), revision: Int64(index + 1))
    }
  }

  func desktopEvidenceCursor(_ request: AgentDesktopToolEvidenceWire.Request) throws
    -> AgentDesktopToolEvidenceWire.ImportCursor {
    try access { database in
      try database.researchRecord(AgentDesktopToolEvidenceWire.ImportCursor.self,
        conversationId: request.binding.identity.conversationId, key: request.cursorKey) ?? .init()
    }
  }

  func enqueueDesktopEvidenceJob(_ job: AgentDesktopToolEvidenceWire.ImportJob) throws {
    try access { database in
      let conversation = job.binding.identity.conversationId
      if try database.researchRecord(AgentDesktopToolEvidenceWire.ImportJob.self,
        conversationId: conversation, key: job.key, revision: 0) != nil { return }
      try database.insertResearchRecord(job, conversationId: conversation, key: job.key, revision: 0)
    }
  }

  func desktopEvidenceJobs(after: String) throws -> [AgentDesktopToolEvidenceWire.ImportJob] {
    try access { try $0.desktopEvidenceJobs(after: after, limit: 16) }
  }

  func removeDesktopEvidenceJob(_ job: AgentDesktopToolEvidenceWire.ImportJob) {
    _ = try? access { try $0.removeDesktopEvidenceJob(job) }
  }

  func hasArchivedDesktopEvidence(_ descriptor: AgentDesktopToolEvidenceWire.Descriptor,
                                  request: AgentDesktopToolEvidenceWire.Request) throws -> Bool {
    try access { database in
      let id = request.archiveId(descriptor)
      guard let receipt = try database.researchRecord(AgentDesktopToolEvidenceWire.ArchiveReceipt.self,
        conversationId: request.binding.identity.conversationId, key: "desktop-evidence:" + id, revision: 0)
      else { return false }
      guard receipt.archiveId == id, receipt.evidenceId == descriptor.evidenceId,
            receipt.desktopId == request.binding.desktopId, receipt.generation == request.generation,
            receipt.sha256 == descriptor.sha256, receipt.totalBytes == descriptor.totalBytes,
            receipt.pageCount == descriptor.pageCount else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      return true
    }
  }

  func advanceDesktopEvidenceCursor(_ request: AgentDesktopToolEvidenceWire.Request,
                                    from previous: Int64, to next: Int64, final: Bool) throws {
    guard previous >= 0, next >= previous, next <= 9_007_199_254_740_991,
          next > previous || final else { throw AgentTeamHistoryDatabase.Failure.stale }
    try access { database in
      let conversation = request.binding.identity.conversationId
      let current = try database.researchRecord(AgentDesktopToolEvidenceWire.ImportCursor.self,
        conversationId: conversation, key: request.cursorKey) ?? .init()
      guard !current.archiveFinal, current.sequence == previous else { throw AgentTeamHistoryDatabase.Failure.stale }
      // Reserve the odd revision for marking the same sequence final.
      try database.insertResearchRecord(AgentDesktopToolEvidenceWire.ImportCursor(sequence: next, archiveFinal: final),
        conversationId: conversation, key: request.cursorKey, revision: next * 2 + (final ? 1 : 0))
    }
  }

  func collaborationResults(conversationId: String, limit: Int) -> [AgentTeamExecutionSnapshot] {
    (try? readCollaborationResults(conversationId: conversationId, limit: limit)) ?? []
  }

  func readCollaborationResults(conversationId: String, limit: Int) throws -> [AgentTeamExecutionSnapshot] {
    guard !conversationId.isBlank, limit > 0 else { return [] }
    return try access {
      try $0.snapshots(conversation: conversationId, limit: min(limit, Self.maxSnapshots))
    }
  }

  func latestCollaborationRun(conversationId: String) -> AgentTeamExecutionSnapshot? {
    collaborationResults(conversationId: conversationId, limit: Self.maxSnapshots).max { lhs, rhs in
      let left = lhs.createdAtMillis > 0 ? lhs.createdAtMillis : lhs.updatedAtMillis
      let right = rhs.createdAtMillis > 0 ? rhs.createdAtMillis : rhs.updatedAtMillis
      return left == right ? lhs.supervisorRunId < rhs.supervisorRunId : left < right
    }
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

  func goalCheckpoint(runId: String, conversationId: String, turnId: String,
                      revision: Int64? = nil) -> AgentCollaborationGoalCheckpoint? {
    try? access { database -> AgentCollaborationGoalCheckpoint? in
      guard let snapshot = try database.snapshots(runId: runId).first,
            snapshot.conversationId == conversationId, snapshot.taskId == turnId,
            let checkpoint = try database.goalCheckpoints(runId: runId, revision: revision, newestOnly: true).first,
            checkpoint.conversationId == conversationId, checkpoint.turnId == turnId else { return nil }
      return checkpoint
    }
  }

  func readPinnedCollaborationGoal(scope: AgentCollaborationToolEvidenceScope, section: String,
                                   offset: Int = 0, expectedHash: String? = nil) throws -> AgentMcpJSONObject {
    guard AgentCollaborationInlineOriginals.recallSections.contains(section), offset >= 0,
          offset == 0 || expectedHash != nil else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let bytes = try access { database -> Data in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            let member = team.members.first(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }),
            !team.goal.isBlank,
            try database.researchRecord(Bool.self, conversationId: scope.conversationId,
              key: "native-evidence-revoked", revision: 0) != true else { throw AgentTeamHistoryDatabase.Failure.stale }
      if section == "goal", member.dispatchCheckpoint != nil { return Data(team.goal.utf8) }
      if AgentCollaborationInlineOriginals.contextSections.contains(section) {
        guard let originals = try database.researchRecord([String: Data].self,
          conversationId: scope.conversationId, key: Self.dispatchContextKey(scope), revision: 0),
          let original = originals[section] else { throw AgentTeamHistoryDatabase.Failure.stale }
        return original
      }
      guard let pinned = try database.goalCheckpoints(runId: scope.runId, revision: 1, newestOnly: true).first,
            pinned.conversationId == scope.conversationId, pinned.turnId == scope.turnId,
            !pinned.contract.isEmpty else { throw AgentTeamHistoryDatabase.Failure.stale }
      if section == "goal" { return Data(team.goal.utf8) }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let criteria = try encoder.encode(pinned.contract)
      return section == "source" ? AgentCollaborationInlineOriginals.source(goal: team.goal, criteria: criteria) : criteria
    }
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    guard offset <= bytes.count, expectedHash == nil || expectedHash == digest else {
      throw AgentTeamHistoryDatabase.Failure.stale
    }
    let next = offset + min(8_192, bytes.count - offset)
    return [
      "section": .string(section), "sha256": .string(digest),
      "data_b64": .string(bytes.subdata(in: offset..<next).base64EncodedString()),
      "offset": .int(Int64(offset)), "total_bytes": .int(Int64(bytes.count)),
      "next_offset": next < bytes.count ? .int(Int64(next)) : .null
    ]
  }

  func advanceGoalCheckpoint(_ checkpoint: AgentCollaborationGoalCheckpoint, expectedRevision: Int64) -> Bool {
    guard expectedRevision >= 0, expectedRevision < Int64.max, checkpoint.revision == expectedRevision + 1,
          !checkpoint.contract.isEmpty, Set(checkpoint.contract.map(\.id)).count == checkpoint.contract.count,
          checkpoint.contract.allSatisfy({ !$0.id.isBlank && !$0.requirement.isBlank && $0.hasValidValidatorBinding }),
          checkpoint.completedWorkIds.allSatisfy({ !$0.isBlank }) else { return false }
    do {
      return try access { database in
        guard let snapshot = try database.snapshots(runId: checkpoint.runId).first,
              snapshot.conversationId == checkpoint.conversationId, snapshot.taskId == checkpoint.turnId,
              !snapshot.state.deliverable else { return false }
        let prior = try database.goalCheckpoints(runId: checkpoint.runId, newestOnly: checkpoint.completedWorkIds.isEmpty)
        guard (prior.first?.revision ?? 0) == expectedRevision,
              (prior.first?.liveGraph?.work ?? []).elementsEqual(
                (checkpoint.liveGraph?.work ?? []).prefix(prior.first?.liveGraph?.work.count ?? 0)),
              prior.allSatisfy({
                $0.conversationId == checkpoint.conversationId && $0.turnId == checkpoint.turnId &&
                  $0.contract == checkpoint.contract && $0.completedWorkIds.isDisjoint(with: checkpoint.completedWorkIds)
              }) else { return false }
        let existing = prior.first?.liveGraph?.work ?? []
        let updated = checkpoint.liveGraph?.work ?? []
        let priorWorkflows = prior.first?.liveGraph?.workflowInstances ?? [:]
        let workflows = checkpoint.liveGraph?.workflowInstances ?? [:]
        let additions = updated.dropFirst(existing.count)
        let authors = Dictionary(updated.map { ($0.id, $0.member) }, uniquingKeysWith: { first, _ in first })
        guard priorWorkflows.allSatisfy({ workflows[$0.key] == $0.value }),
              authors.count == updated.count,
              additions.allSatisfy({ item in
                guard let id = item.workflowExecutionId else {
                  return item.review_targets == nil || item.hasIndependentReviewAuthors { authors[$0] }
                }
                return priorWorkflows[id] == nil && workflows[id] != nil
              }) else { return false }
        for (id, instance) in workflows where priorWorkflows[id] == nil {
          guard id == instance.execution_id,
                let compiled = try Self.resolveWorkflow(instance, snapshot: snapshot, database: database),
                compiled == additions.filter({ $0.workflowExecutionId == id }) else { return false }
        }
        guard let ranks = try Self.validatedLearningPriorities(updated, existingCount: existing.count,
          previous: prior.first?.liveGraph?.learningPriorities ?? [:], snapshot: snapshot,
          database: database) else { return false }
        var pinned = checkpoint
        pinned.liveGraph = checkpoint.liveGraph?.pinningLearningPriorities(ranks)
        try database.insertGoalCheckpoint(pinned)
        return true
      }
    } catch { return false }
  }

  func appendSavedCollaborationWorkflow(_ instance: AgentCollaborationWorkflowInstance,
    runId: String, conversationId: String, turnId: String, expectedRevision: Int64,
    historicalAuthors: [String: String], settled: [String: AgentCollaborationLiveGraph.Settlement]) -> Bool {
    guard var checkpoint = goalCheckpoint(runId: runId, conversationId: conversationId, turnId: turnId),
          let snapshot = snapshot(supervisorRunId: runId), snapshot.conversationId == conversationId,
          snapshot.taskId == turnId, !snapshot.state.isTerminal else { return false }
    let graph = checkpoint.liveGraph ?? .init()
    if let existing = graph.workflowInstances?[instance.execution_id] { return existing == instance }
    guard checkpoint.revision == expectedRevision, expectedRevision < Int64.max,
          let compiled = try? access({ try Self.resolveWorkflow(instance, snapshot: snapshot, database: $0) }),
          let expanded = graph.appendingWorkflow(instance, compiled: compiled,
            authorizedMembers: Set(snapshot.members.filter { $0.deliveryMode != .ignore }.map(\.memberId)),
            historicalAuthors: historicalAuthors, settled: settled) else { return false }
    checkpoint.liveGraph = expanded
    checkpoint.revision += 1
    checkpoint.completedWorkIds = []
    return advanceGoalCheckpoint(checkpoint, expectedRevision: expectedRevision)
  }

  private static func resolveWorkflow(_ instance: AgentCollaborationWorkflowInstance, snapshot: AgentTeamExecutionSnapshot,
    database: AgentTeamHistoryDatabase) throws -> [AgentCollaborationLiveGraph.Work]? {
    let assigned = Set(instance.roles.values)
    guard assigned.isSubset(of: Set(snapshot.members.filter { $0.deliveryMode != .ignore }.map(\.memberId))) else { return nil }
    func current(_ ref: AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision? {
      guard let saved = try database.researchRecord(AgentCollaborationResearchRevision.self,
        conversationId: snapshot.conversationId, key: "object:" + ref.objectId), saved.reference == ref else { return nil }
      return saved
    }
    guard let method = try current(instance.method), method.draft.kind == .workflowMethod,
          method.turnId != snapshot.taskId ||
            (method.runId == snapshot.supervisorRunId && method.authorId == snapshot.primaryMemberId),
          let body = method.draft.body["workflow_method"]?.objectValue else { return nil }
    for input in instance.inputs.values {
      guard let saved = try current(input), saved.turnId != snapshot.taskId ||
        (saved.runId == snapshot.supervisorRunId && assigned == [saved.authorId]) else { return nil }
    }
    return instance.compile(body)
  }

  private static func validatedLearningPriorities(_ work: [AgentCollaborationLiveGraph.Work], existingCount: Int,
    previous: [String: Int64], snapshot: AgentTeamExecutionSnapshot,
    database: AgentTeamHistoryDatabase) throws -> [String: Int64]? {
    var claims: [String: Set<String>] = [:]
    var ranks = previous
    for (index, item) in work.enumerated() {
      guard let binding = item.learning else { continue }
      guard claims[binding.agenda.objectId, default: []].insert(binding.option_id).inserted else { return nil }
      if index < existingCount, ranks[item.id] != nil { continue }
      guard let agenda = try database.researchRecord(AgentCollaborationResearchRevision.self,
              conversationId: snapshot.conversationId, key: "object:" + binding.agenda.objectId),
            agenda.reference == binding.agenda, agenda.draft.kind == .learningAgenda,
            agenda.runId == snapshot.supervisorRunId, agenda.turnId == snapshot.taskId,
            agenda.authorId == snapshot.primaryMemberId,
            snapshot.members.contains(where: { $0.memberId == item.member && $0.deliveryMode != .ignore }),
            let options = agenda.draft.body["learning_agenda"]?.objectValue?["options"]?.arrayValue,
            let option = options.compactMap(\.objectValue).first(where: { $0.string("id") == binding.option_id }),
            AgentCollaborationLearningAgendaIntake.matchesSelection(option, work: item),
            case .int(let rank)? = option["priority"], rank > 0 else {
        if index < existingCount { continue }
        return nil
      }
      if index < existingCount {
        ranks[item.id] = rank
        continue
      }
      guard
            let gap = option["gap"]?.objectValue, case .int(let revision)? = gap["revision"],
            let current = try database.researchRecord(AgentCollaborationResearchRevision.self,
              conversationId: snapshot.conversationId, key: "object:" + gap.string("object_id")),
            current.reference.revision == revision, current.reference.sha256 == gap.string("sha256"),
            current.draft.kind.rawValue == "capability_gap" else { return nil }
      ranks[item.id] = rank
    }
    return ranks
  }

  func appendCollaborationGraph(_ raw: String, runId: String, conversationId: String, turnId: String,
                                expectedRevision: Int64, authorizedMembers: Set<String>,
                                historicalAuthors: [String: String],
                                settled: [String: AgentCollaborationLiveGraph.Settlement]) -> Bool {
    guard raw.utf8.count <= 256_000,
          let expansion = try? JSONDecoder().decode(AgentCollaborationLiveGraph.WorkflowExpansion.self, from: Data(raw.utf8)),
          var checkpoint = goalCheckpoint(runId: runId, conversationId: conversationId, turnId: turnId),
          checkpoint.revision == expectedRevision, expectedRevision < Int64.max else { return false }
    let graph = checkpoint.liveGraph ?? .init()
    guard let updated = try? graph.appending(expansion, authorizedMembers: authorizedMembers,
      historicalAuthors: historicalAuthors, settled: settled, resolve: { instance in
        try access { database in
          guard let snapshot = try database.snapshots(runId: runId).first,
                snapshot.conversationId == conversationId, snapshot.taskId == turnId, !snapshot.state.isTerminal
          else { return nil }
          return try Self.resolveWorkflow(instance, snapshot: snapshot, database: database)
        }
      }) else { return false }
    if updated == graph { return true }
    checkpoint.liveGraph = updated
    checkpoint.revision += 1
    checkpoint.completedWorkIds = []
    return advanceGoalCheckpoint(checkpoint, expectedRevision: expectedRevision)
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
