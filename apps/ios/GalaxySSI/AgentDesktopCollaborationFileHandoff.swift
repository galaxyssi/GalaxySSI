import CryptoKit
import Foundation

enum AgentDesktopCollaborationFileHandoff {
  static let format = "galaxyssi.file-artifact/1"
  static let maximumBytes: Int64 = 1_073_741_824
  static let maximumGrantCount = 128

  struct Pair: Codable, Equatable {
    let desktopID: String
    let clientRouteID: String
    let contactID: String
    let phoneFingerprint: String
    let desktopFingerprint: String

    var storeID: String? {
      let parts = [desktopID, clientRouteID, contactID, phoneFingerprint, desktopFingerprint]
      guard parts.allSatisfy({ !$0.isBlank && $0.utf8.count <= 512 }) else { return nil }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.withoutEscapingSlashes]
      guard let bytes = try? encoder.encode(parts) else { return nil }
      return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
  }

  struct Binding: Codable, Equatable {
    let pair: Pair
    let generation: Int64
  }

  struct Selector {
    let objectID: String
    let revision: Int64
    let sha256: String?

    init?(_ input: AgentMcpJSONObject) {
      guard Set(input.keys).isSubset(of: ["mode", "object_id", "revision", "sha256", "offset"]),
            input["mode"] == .string("workspace"),
            let object = input["object_id"]?.strictStringValue, validHash(object),
            case .int(let revision)? = input["revision"], (1...Int64(Int32.max)).contains(revision),
            input["offset"] == nil || input["offset"] == .int(0) else { return nil }
      if let value = input["sha256"] {
        guard let hash = value.strictStringValue, validHash(hash) else { return nil }
        sha256 = hash
      } else { sha256 = nil }
      self.objectID = object
      self.revision = revision
    }
  }

  static func isFile(_ draft: AgentCollaborationResearchDraft) -> Bool {
    draft.body["format"] == .string(format)
  }

  static func valid(_ draft: AgentCollaborationResearchDraft, binding: Binding) -> Bool {
    let body = draft.body
    guard draft.kind == .artifact, isFile(draft), draft.parents.isEmpty, draft.resolves?.isEmpty != false,
          (0..<Int64(Int32.max)).contains(draft.baseRevision),
          AgentRemoteOutcomePolicy.validGeneration(binding.generation),
          Set(body.keys) == ["format", "store_id", "file_id", "name", "size_bytes", "sha256", "availability"],
          let store = binding.pair.storeID, body["store_id"] == .string(store),
          let id = body["file_id"]?.strictStringValue, validHash(id), id == draft.id,
          let digest = body["sha256"]?.strictStringValue, validHash(digest),
          let name = body["name"]?.strictStringValue, validFilename(name),
          case .int(let bytes)? = body["size_bytes"], (0...maximumBytes).contains(bytes),
          body["availability"] == .string("originating_desktop") else { return false }
    return true
  }

  static func response(_ record: AgentCollaborationResearchRevision) -> AgentMcpJSONObject? {
    guard let binding = record.desktopFile, valid(record.draft, binding: binding) else { return nil }
    let ref = record.reference
    let content = AgentMcpJSONCodec.stringify(["object_id": .string(ref.objectId), "revision": .int(ref.revision),
      "sha256": .string(ref.sha256), "kind": .string("artifact"), "body": .object(record.draft.body)])
    // The descriptor fits one page; Desktop measures offsets in UTF-16 code units.
    guard !content.isEmpty, content.utf8.count <= 4_096 else { return nil }
    return ["success": .bool(true), "status": .string("returned"), "content": .string(content),
      "total_characters": .int(Int64(content.utf16.count)), "next_offset": .null]
  }

  static func publicationPrefix(_ scope: AgentCollaborationToolEvidenceScope) -> String {
    "desktop-file:" + scope.ownershipDigest + ":"
  }

  static func publicationKey(_ scope: AgentCollaborationToolEvidenceScope, reference: AgentCollaborationResearchReference) -> String {
    publicationPrefix(scope) + AgentMcpJSONCodec.sha256(["object": .string(reference.objectId),
      "revision": .int(reference.revision), "digest": .string(reference.sha256)])
  }

  static func identityKey(_ draft: AgentCollaborationResearchDraft) -> String {
    "desktop-file-identity:" + AgentMcpJSONCodec.sha256(["store": draft.body["store_id"] ?? .null,
      "file": draft.body["file_id"] ?? .null])
  }

  static func grantKey(_ scope: AgentCollaborationToolEvidenceScope) -> String {
    "desktop-file-grants:" + scope.ownershipDigest
  }

  static func validateReceipt(_ receipt: AgentCollaborationResearchPublication, pair: Pair?,
      conversation: String, database: AgentTeamHistoryDatabase) throws {
    for reference in receipt.references {
      guard let row = try database.researchRecord(AgentCollaborationResearchRevision.self, conversationId: conversation,
        key: "object:" + reference.objectId, revision: reference.revision), row.reference == reference
      else { throw AgentTeamHistoryDatabase.Failure.stale }
      if isFile(row.draft) {
        guard let binding = row.desktopFile, binding.pair == pair, valid(row.draft, binding: binding)
        else { throw AgentTeamHistoryDatabase.Failure.stale }
      }
    }
  }

  static func freezeGrants(team: AgentTeamExecutionSnapshot, member: AgentTeamMemberSnapshot,
                           database: AgentTeamHistoryDatabase) throws {
    guard let dependencies = member.dispatchDependencyMemberIds, !dependencies.isEmpty else { return }
    let recipient = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
      turnId: team.taskId, memberId: member.memberId, sourceId: member.sourceMessageId)
    var grants: [AgentCollaborationResearchReference] = []
    for producer in team.members where producer.deliveryMode != .ignore && dependencies.contains(producer.memberId) {
      let owner = AgentCollaborationToolEvidenceScope(runId: team.supervisorRunId, conversationId: team.conversationId,
        turnId: team.taskId, memberId: producer.memberId, sourceId: producer.sourceMessageId)
      let prefix = publicationPrefix(owner)
      var cursor = ""
      for _ in 0..<4 {
        let keys = try database.milestoneKeys(conversationId: team.conversationId, prefix: prefix, after: cursor)
        for key in keys.prefix(32) {
          guard grants.count < maximumGrantCount else { break }
          guard let reference = try database.researchRecord(AgentCollaborationResearchReference.self,
            conversationId: team.conversationId, key: key, revision: 0),
            key == publicationKey(owner, reference: reference),
            let row = try database.researchRecord(AgentCollaborationResearchRevision.self, conversationId: team.conversationId,
              key: "object:" + reference.objectId), row.reference == reference,
            row.runId == owner.runId, row.turnId == owner.turnId, row.authorId == owner.memberId, row.sourceId == owner.sourceId,
            let binding = row.desktopFile, valid(row.draft, binding: binding) else { continue }
          grants.append(reference)
        }
        guard keys.count > 32, grants.count < maximumGrantCount else { break }
        cursor = keys[31]
      }
      if grants.count >= maximumGrantCount { break }
    }
    if !grants.isEmpty {
      try database.insertResearchRecord(grants, conversationId: team.conversationId, key: grantKey(recipient), revision: 0)
    }
  }

  static func recall(_ selector: Selector, scope: AgentCollaborationToolEvidenceScope, reader: Binding,
      database: AgentTeamHistoryDatabase) throws -> AgentMcpJSONObject {
    guard AgentRemoteOutcomePolicy.validGeneration(reader.generation),
          !PhoneExecutionAuthority.isCancelled(taskId: scope.turnId),
          let team = try database.snapshots(runId: scope.runId).first, team.state == .running,
          team.conversationId == scope.conversationId, team.taskId == scope.turnId,
          let member = team.members.first(where: { $0.memberId == scope.memberId && $0.sourceMessageId == scope.sourceId &&
            $0.agentId == reader.pair.contactID && $0.deliveryMode != .ignore && !$0.status.isTerminal &&
            ($0.dispatchCheckpoint == .dispatching || $0.dispatchCheckpoint == .accepted) }),
          try database.researchRecord(Bool.self, conversationId: scope.conversationId,
            key: "native-evidence-revoked", revision: 0) != true,
          let row = try database.researchRecord(AgentCollaborationResearchRevision.self, conversationId: scope.conversationId,
            key: "object:" + selector.objectID, revision: selector.revision),
          row.reference.objectId == selector.objectID, row.reference.revision == selector.revision,
          selector.sha256 == nil || selector.sha256 == row.reference.sha256,
          let binding = row.desktopFile, binding.pair == reader.pair, let result = response(row)
    else { throw AgentTeamHistoryDatabase.Failure.stale }
    if row.turnId == scope.turnId {
      guard row.runId == scope.runId else { throw AgentTeamHistoryDatabase.Failure.stale }
      if row.authorId != scope.memberId || row.sourceId != scope.sourceId {
        guard member.dispatchDependencyMemberIds?.contains(row.authorId) == true,
              team.members.contains(where: { $0.memberId == row.authorId && $0.sourceMessageId == row.sourceId && $0.deliveryMode != .ignore }),
              let grants = try database.researchRecord([AgentCollaborationResearchReference].self,
                conversationId: scope.conversationId, key: grantKey(scope), revision: 0),
              grants.contains(row.reference) else { throw AgentTeamHistoryDatabase.Failure.stale }
      }
    }
    return result
  }

  private static func validHash(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func validFilename(_ value: String) -> Bool {
    guard !value.isEmpty, value.unicodeScalars.count <= 200, !value.hasPrefix("."),
          !value.hasSuffix("."), !value.hasSuffix(" "),
          !value.unicodeScalars.contains(where: { $0.value < 32 || "<>:\"/\\|?*".unicodeScalars.contains($0) }),
          let stem = value.split(separator: ".", maxSplits: 1).first?.uppercased() else { return false }
    let reserved = ["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
    return !reserved.contains(stem)
  }
}
