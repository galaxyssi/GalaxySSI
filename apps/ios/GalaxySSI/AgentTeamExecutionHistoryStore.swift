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
          if current.goal != incoming.goal,
             !(try database.goalCheckpoints(runId: incoming.supervisorRunId, newestOnly: true)).isEmpty {
            throw AgentTeamHistoryDatabase.Failure.stale
          }
          if current.state.deliverable || current.updatedAtMillis > incoming.updatedAtMillis { return false }
          for member in current.members where member.dispatchCheckpoint != nil {
            guard let replacement = incoming.members.first(where: { $0.memberId == member.memberId }),
                  replacement.sourceMessageId == member.sourceMessageId,
                  replacement.dispatchCheckpoint == member.dispatchCheckpoint else {
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
      return [
        "evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_cloud_tool"),
        "trust": .string("execution_observed_not_claim_verified")
      ]
    }
  }

  func removeCloudEvidence(conversationId: String) {
    _ = try? access { try $0.removeCloudEvidence(conversationId: conversationId) }
  }

  func recallCollaborationOriginal(_ input: AgentMcpJSONObject,
                                   scope: AgentCollaborationToolEvidenceScope) throws -> AgentMcpJSONObject {
    let mode = input.string("mode")
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
    func page(_ bytes: Data) throws -> (content: String, end: Int64, total: Int64) {
      let characters = String(decoding: bytes, as: UTF8.self)
      let total = Int64(characters.count)
      guard offset <= total else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      let content = String(characters.dropFirst(Int(offset)).prefix(2_000))
      return (content, offset + Int64(content.count), total)
    }
    let (slice, sourceReference, coverage) = try access { database
      -> ((content: String, end: Int64, total: Int64), AgentMcpJSONObject?, AgentMcpJSONObject?) in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            team.members.contains(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }) else {
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
      guard let record = try database.cloudEvidence(id: id, conversationId: scope.conversationId),
            record.scope.conversationId == scope.conversationId,
            record.scope.turnId != scope.turnId || record.scope == scope else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      let data = try encoder.encode(record)
      guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == hash else {
        throw AgentTeamHistoryDatabase.Failure.corrupt
      }
      let slice = try page(data)
      let key = Self.cloudReadCoverageKey(scope: scope, id: id, hash: hash)
      let previous = try database.researchRecord(AgentCollaborationReadCoverage.self,
        conversationId: scope.conversationId, key: key, revision: 0) ?? AgentCollaborationReadCoverage()
      var coverage = previous
      coverage.include(start: offset, end: slice.end)
      if coverage != previous {
        try database.insertResearchRecord(coverage, conversationId: scope.conversationId,
          key: key, revision: 0, replaceCoverage: true)
      }
      let complete = coverage.contiguousEnd == slice.total
      return (slice, [
        "evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_cloud_tool"),
        "tool": .string(record.call.name), "status": .string(record.succeeded ? "succeeded" : "failed")
      ], [
        "complete": .bool(complete), "total_characters": .int(slice.total),
        "first_missing_offset": complete ? .null : .int(coverage.contiguousEnd),
        "content_utf8_sha256": .string(hash)
      ])
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

  private static func cloudReadCoverageKey(scope: AgentCollaborationToolEvidenceScope, id: String, hash: String) -> String {
    "cloud-read-coverage:" + AgentMcpJSONCodec.sha256([
      "run": .string(scope.runId), "group": .string(scope.conversationId), "turn": .string(scope.turnId),
      "member": .string(scope.memberId), "source": .string(scope.sourceId),
      "evidence": .string(id), "sha256": .string(hash)
    ])
  }

  private static func freezeCloudReads(_ references: [AgentMcpJSONObject], scope: AgentCollaborationToolEvidenceScope,
                                       database: AgentTeamHistoryDatabase) throws -> [AgentCollaborationFrozenCloudRead] {
    guard references.count <= 32 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    var seen = Set<String>()
    return try references.map { reference in
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
      return AgentCollaborationFrozenCloudRead(evidenceId: id, sha256: hash, totalCharacters: total)
    }
  }

  func recoverable(conversationId: String) -> [AgentTeamExecutionSnapshot] {
    guard !conversationId.isBlank else { return [] }
    return (try? access { try $0.snapshots(conversation: conversationId, recoverableOnly: true) }) ?? []
  }

  func publishResearchObjects(_ drafts: [AgentCollaborationResearchDraft], runId: String,
                              conversationId: String, turnId: String, memberId: String,
                              sourceId: String) throws -> AgentCollaborationResearchPublication {
    guard !drafts.isEmpty, drafts.count <= 32, !sourceId.isBlank else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    func digest<T: Encodable>(_ value: T) throws -> String {
      let bytes = try encoder.encode(value)
      guard bytes.count <= 256_000 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    let requestHash = try digest(drafts)
    let publicationKey = Self.researchPublicationKey(runId: runId, memberId: memberId, sourceId: sourceId)
    return try access { database in
      guard let snapshot = try database.snapshots(runId: runId).first,
            snapshot.conversationId == conversationId, snapshot.taskId == turnId,
            let member = snapshot.members.first(where: { $0.memberId == memberId && $0.sourceMessageId == sourceId }),
            member.status == .succeeded, snapshot.state != .cancelled else {
        throw AgentTeamHistoryDatabase.Failure.stale
      }
      if let prior = try database.researchRecord(AgentCollaborationResearchPublication.self,
        conversationId: conversationId, key: publicationKey, revision: 0) {
        guard prior.requestHash == requestHash else { throw AgentTeamHistoryDatabase.Failure.stale }
        return prior
      }
      var revisions: [AgentCollaborationResearchRevision] = []
      var objectIds = Set<String>()
      for draft in drafts {
        guard !draft.id.isBlank, draft.id.utf8.count <= 160, !draft.title.isBlank,
              draft.title.utf8.count <= 960, !draft.body.isEmpty,
              draft.baseRevision >= 0, draft.baseRevision < Int64.max else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        let references = draft.observations ?? []
        var frozenReads: [AgentCollaborationFrozenCloudRead]? = nil
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
        var revision = AgentCollaborationResearchRevision(reference: .init(objectId: objectId,
          revision: draft.baseRevision + 1, sha256: ""), previousHash: head?.reference.sha256,
          runId: runId, turnId: turnId, authorId: memberId, sourceId: sourceId, draft: draft,
          frozenCloudReads: frozenReads)
        revision.reference.sha256 = try digest(revision)
        revisions.append(revision)
      }
      for revision in revisions {
        try database.insertResearchRecord(revision, conversationId: conversationId,
          key: "object:" + revision.reference.objectId, revision: revision.reference.revision)
      }
      let receipt = AgentCollaborationResearchPublication(requestHash: requestHash,
        references: revisions.map(\.reference))
      try database.insertResearchRecord(receipt, conversationId: conversationId, key: publicationKey, revision: 0)
      return receipt
    }
  }

  private static func researchPublicationKey(runId: String, memberId: String, sourceId: String) -> String {
    "publication:" + AgentMcpJSONCodec.sha256([
      "run": .string(runId), "member": .string(memberId), "source": .string(sourceId)
    ])
  }

  func publishSavedResearchReply(_ raw: String, scope: AgentCollaborationToolEvidenceScope) throws {
    guard try committedResearchRevisions(scope: scope) == nil else { return }
    let hash = Self.replyHash(raw)
    guard try access({ try Self.savedResearchReply(scope, database: $0).map(Self.replyHash) }) == hash else {
      throw AgentTeamHistoryDatabase.Failure.stale
    }
    let drafts: [AgentCollaborationResearchDraft]?
    do {
      drafts = try AgentCollaborationResearchEnvelope.publication(in: raw)
    } catch {
      try recordResearchRejection(raw, scope: scope, reason: .malformedEnvelope)
      throw error
    }
    guard let drafts else { return }
    do {
      _ = try publishResearchObjects(drafts, runId: scope.runId, conversationId: scope.conversationId,
        turnId: scope.turnId, memberId: scope.memberId, sourceId: scope.sourceId)
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
          guard revision.draft.kind == .acceptanceReview, let reads = revision.frozenCloudReads,
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

  func recordNativeObservation(_ observation: AgentCollaborationNativeToolObservation) throws -> AgentMcpJSONObject {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(observation)
    guard !observation.result.receipt.invocationId.isBlank, encoded.count <= 256_000 else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    let hash = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    let id = AgentMcpJSONCodec.sha256([
      "run": .string(observation.runId), "source": .string(observation.sourceId),
      "invocation": .string(observation.result.receipt.invocationId), "sha256": .string(hash)
    ])
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

  func archiveDesktopToolEvidence(request: AgentDesktopToolEvidenceWire.Request,
                                  descriptor: AgentDesktopToolEvidenceWire.Descriptor,
                                  pages: [Data]) throws -> AgentDesktopToolEvidenceWire.ArchiveReceipt {
    guard request.verifyOriginal(pages, descriptor: descriptor) != nil,
          let source = request.binding.teamSource else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let binding = request.binding
    let conversation = binding.identity.conversationId
    var identity = binding.fields.mapValues(AgentMcpJSONValue.string)
    identity["desktop_id"] = .string(binding.desktopId)
    identity["execution_generation"] = .int(request.generation)
    identity["evidence_id"] = .string(descriptor.evidenceId)
    let id = AgentMcpJSONCodec.sha256(identity)
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
        return prior
      }
      for (index, page) in pages.enumerated() {
        try database.insertResearchRecord(page, conversationId: conversation, key: key, revision: Int64(index + 1))
      }
      try database.insertResearchRecord(receipt, conversationId: conversation, key: key, revision: 0)
      return receipt
    }
  }

  func collaborationResults(conversationId: String, limit: Int) -> [AgentTeamExecutionSnapshot] {
    guard !conversationId.isBlank, limit > 0 else { return [] }
    return (try? access {
      try $0.snapshots(conversation: conversationId, limit: min(limit, Self.maxSnapshots))
    }) ?? []
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
    guard ["goal", "criteria"].contains(section), offset >= 0,
          offset == 0 || expectedHash != nil else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let bytes = try access { database -> Data in
      guard let team = try database.snapshots(runId: scope.runId).first,
            team.conversationId == scope.conversationId, team.taskId == scope.turnId, !team.state.isTerminal,
            team.members.contains(where: { $0.memberId == scope.memberId &&
              $0.sourceMessageId == scope.sourceId && !$0.status.isTerminal }),
            let pinned = try database.goalCheckpoints(runId: scope.runId, revision: 1, newestOnly: true).first,
            pinned.conversationId == scope.conversationId, pinned.turnId == scope.turnId,
            !pinned.contract.isEmpty else { throw AgentTeamHistoryDatabase.Failure.stale }
      if section == "goal" { return Data(team.goal.utf8) }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return try encoder.encode(pinned.contract)
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
          checkpoint.contract.allSatisfy({ !$0.id.isBlank && !$0.requirement.isBlank }),
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
        try database.insertGoalCheckpoint(checkpoint)
        return true
      }
    } catch { return false }
  }

  func appendCollaborationGraph(_ raw: String, runId: String, conversationId: String, turnId: String,
                                expectedRevision: Int64, authorizedMembers: Set<String>,
                                historicalAuthors: [String: String],
                                settled: [String: AgentCollaborationLiveGraph.Settlement]) -> Bool {
    guard var checkpoint = goalCheckpoint(runId: runId, conversationId: conversationId, turnId: turnId),
          checkpoint.revision == expectedRevision, expectedRevision < Int64.max,
          let graph = (checkpoint.liveGraph ?? .init()).appending(raw, authorizedMembers: authorizedMembers,
            historicalAuthors: historicalAuthors, settled: settled) else { return false }
    checkpoint.liveGraph = graph
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
