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
      return try access { database in
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
        snapshot.updatedAtMillis = max(snapshot.updatedAtMillis, now)
        try database.put(snapshot)
        return true
      }
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
    let bytes = try access { database -> Data in
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
        return try encoder.encode(record)
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
      return data
    }
    let characters = String(decoding: bytes, as: UTF8.self)
    guard offset <= Int64(characters.count) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let page = String(characters.dropFirst(Int(offset)).prefix(2_000))
    let next = offset + Int64(page.count)
    return [
      idKey: .string(id), "sha256": .string(hash), "content": .string(page),
      "next_offset": next < Int64(characters.count) ? .int(next) : .null,
      "trust": .string("untrusted_group_evidence")
    ]
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
    let publicationKey = "publication:" + AgentMcpJSONCodec.sha256([
      "run": .string(runId), "member": .string(memberId), "source": .string(sourceId)
    ])
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
        guard draft.observations?.isEmpty != false else { throw AgentTeamHistoryDatabase.Failure.corrupt }
        if draft.kind == .acceptanceReview {
          let parents = draft.parents.map { AgentCollaborationDocumentaryAcceptance.Reference(
            objectId: $0.objectId, revision: $0.revision, sha256: $0.sha256) }
          guard AgentCollaborationDocumentaryAcceptance.validReviewPublication(body: draft.body, parents: parents)
          else { throw AgentTeamHistoryDatabase.Failure.corrupt }
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
          runId: runId, turnId: turnId, authorId: memberId, sourceId: sourceId, draft: draft)
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
              prior.allSatisfy({
                $0.conversationId == checkpoint.conversationId && $0.turnId == checkpoint.turnId &&
                  $0.contract == checkpoint.contract && $0.completedWorkIds.isDisjoint(with: checkpoint.completedWorkIds)
              }) else { return false }
        try database.insertGoalCheckpoint(checkpoint)
        return true
      }
    } catch { return false }
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
