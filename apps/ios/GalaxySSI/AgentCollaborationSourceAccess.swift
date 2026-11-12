import CryptoKit
import Foundation

enum AgentGoalWorkMilestoneRead {
  static let toolID = "collaboration_milestone_read"
  static let instructions = "Read only the milestones granted to this assignment. Use list to see tokens, references " +
    "with a token for exact versions, workspace with token/object_id/revision/sha256, or evidence, native_evidence " +
    "and desktop_evidence with token/evidence_id/sha256. Follow byte next_offset until null and join decoded data_b64. " +
    "An input_role of prerequisite is supporting data, not a review subject. " +
    "A reference is not proof of delivery, truth, or independent review. No other member output is granted."
  static let schema: AgentMcpJSONObject = [
    "type": .string("object"), "required": .array([.string("mode")]), "additionalProperties": .bool(false),
    "properties": .object([
      "mode": .object(["type": .string("string"), "enum": .array(
        ["list", "references", "workspace", "evidence", "native_evidence", "desktop_evidence"].map(AgentMcpJSONValue.string))]),
      "token": .object(["type": .string("string")]), "object_id": .object(["type": .string("string")]),
      "revision": .object(["type": .string("integer")]), "evidence_id": .object(["type": .string("string")]),
      "sha256": .object(["type": .string("string")]), "offset": .object(["type": .string("integer")])
    ])
  ]

  static let pageBytes = AgentDesktopToolEvidenceWire.maximumPageBytes
  static let desktopInstructions = "Use collaboration_recall mode=workspace to list granted versions. Follow next_cursor. " +
    "Read only an exact object_id/revision/sha256 from that directory. For recorded observations use mode=archive " +
    "with the listed record_id. Follow byte next_offset until null and join decoded data_b64. " +
    "An input_role of prerequisite is supporting data, not a review subject. " +
    "A reference is not proof of delivery, truth, or independent review."
  static let coordinatorInstructions = "Use uses_milestones:[exact host token] for an interim version; this does not " +
    "wait for, complete, or expose the author's other work. Use depends_on when the whole work result is required. " +
    "For independent_review, review_milestones is the subset of uses_milestones being reviewed; omit it to review all. " +
    "The other tokens are supporting prerequisites and can come from the reviewer."

  static func inputRole(_ token: String, reviewTokens: [String]?) -> AgentMcpJSONValue? {
    reviewTokens.map { .string($0.contains(token) ? "review_subject" : "prerequisite") }
  }

  static func inputRoles(_ tokens: [String], reviewTokens: [String]?) -> AgentMcpJSONValue? {
    guard let reviewTokens else { return nil }
    return .array(tokens.map { token in
      .object(["token": .string(token), "input_role": .string(reviewTokens.contains(token) ? "review_subject" : "prerequisite")])
    })
  }

  static func response(bytes: Data, offset: Int, total: Int, reference: AgentMcpJSONObject) -> AgentMcpJSONObject {
    ["status": .string("returned"), "data_b64": .string(bytes.base64EncodedString()),
     "offset": .int(Int64(offset)), "total_bytes": .int(Int64(total)),
     "next_offset": offset + bytes.count < total ? .int(Int64(offset + bytes.count)) : .null,
     "source_reference": .object(reference), "trust": .string("untrusted_group_evidence")]
  }

  static func observationSelectors(_ record: AgentCollaborationResearchRevision, token: String) -> [AgentMcpJSONObject] {
    func selector(_ mode: String, id: String, hash: String) -> AgentMcpJSONObject {
      ["mode": .string(mode), "token": .string(token), "evidence_id": .string(id), "sha256": .string(hash)]
    }
    return (record.frozenCloudReads ?? []).map { selector("evidence", id: $0.evidenceId, hash: $0.sha256) } +
      (record.frozenNativeReads ?? []).map { selector("native_evidence", id: $0.evidenceId, hash: $0.sha256) } +
      (record.frozenDesktopReads ?? []).map { selector("desktop_evidence", id: $0.evidenceId, hash: $0.sha256) }
  }
}

enum AgentCollaborationSourceAccess {
  static let mode = "source_access"
  static let pageSize = 20
  static let instructions = "Use source_access with exact workspace object_id, revision and sha256 to inspect direct sources. Follow next_cursor with the same root. Available means readable now, not read or verified. Author read coverage is frozen at publication and does not credit the current reader. Read relevant originals or report unavailable evidence. No access is granted."

  static func matches(tool: String, input: AgentMcpJSONObject) -> Bool {
    tool == CloudModelStreamMutableConversation.collaborationRecallName && input["mode"] == .string(mode)
  }

  static func validDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func workspaceReference(_ reference: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    ["object_id": .string(reference.objectId), "revision": .int(reference.revision), "sha256": .string(reference.sha256)]
  }

  static func page(_ input: AgentMcpJSONObject, scope: AgentCollaborationToolEvidenceScope,
                   dependencies: [String], generation: Int64?, database: AgentTeamHistoryDatabase) throws -> AgentMcpJSONObject {
    guard input["mode"] == .string(mode),
          Set(input.keys).isSubset(of: ["mode", "object_id", "revision", "sha256", "cursor"]),
          validDigest(input.string("object_id")), validDigest(input.string("sha256")),
          case .int(let revision)? = input["revision"], revision > 0,
          case .string(let cursor) = input["cursor"] ?? .string(""), cursor.utf8.count <= 128 else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    let rootRef = AgentCollaborationResearchReference(objectId: input.string("object_id"), revision: revision,
      sha256: input.string("sha256"))
    guard let root = try database.readableCollaborationRevision(rootRef, scope: scope) else {
      throw AgentTeamHistoryDatabase.Failure.stale
    }
    let observations = root.frozenCloudReads ?? []
    let parents = root.draft.parents
    let total = parents.count + observations.count
    let binding = AgentMcpJSONCodec.sha256([
      "mode": .string(mode), "assignment": .string(scope.ownershipDigest),
      "generation": generation.map(AgentMcpJSONValue.int) ?? .null,
      "dependencies": .array(dependencies.sorted().map(AgentMcpJSONValue.string)),
      "root": .object(workspaceReference(rootRef))
    ])
    let start: Int
    if cursor.isEmpty { start = 0 }
    else {
      let parts = cursor.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2, String(parts[0]) == binding, let offset = Int(parts[1]),
            String(parts[1]) == String(offset), offset > 0, offset < total, offset % pageSize == 0 else {
        throw AgentTeamHistoryDatabase.Failure.corrupt
      }
      start = offset
    }
    let end = min(total, start + pageSize)
    var rows: [AgentMcpJSONValue] = []
    for position in start..<end {
      let kind: String, field: String, index: Int, reference: AgentMcpJSONObject, available: Bool
      if position < parents.count {
        kind = "workspace"
        field = "parents"
        index = position
        let parent = parents[index]
        reference = workspaceReference(parent)
        available = (try? database.readableCollaborationRevision(parent, scope: scope)) != nil
      } else {
        kind = "evidence"
        field = "host_observations"
        index = position - parents.count
        let observation = observations[index]
        reference = ["evidence_id": .string(observation.evidenceId), "sha256": .string(observation.sha256)]
        available = (try? database.readableCollaborationEvidence(id: observation.evidenceId,
          sha256: observation.sha256, scope: scope)) != nil
      }
      var row: AgentMcpJSONObject = [
        "kind": .string(kind), "source_field": .string(field), "source_index": .int(Int64(index)),
        "reference": .object(reference), "status": .string(available ? "available" : "missing_changed_or_out_of_scope")
      ]
      if field == "host_observations", let coverage = observations[index].hostReadCoverage {
        row["author_read_coverage"] = .object(coverage)
      }
      if available {
        var selector = reference
        selector["mode"] = .string(kind)
        selector["offset"] = .int(0)
        row["read_original"] = .object(selector)
      }
      rows.append(.object(row))
    }
    return [
      "status": .string("returned"), "source_reference": .object(workspaceReference(rootRef)),
      "references": .array(rows), "total_references": .int(Int64(total)),
      "next_cursor": end < total ? .string("\(binding):\(end)") : .null,
      "availability_snapshot": .bool(false), "scope": .string("direct_declared_references_only"),
      "trust": .string("current_access_not_read_coverage_or_verification"),
      "guidance": .string(instructions)
    ]
  }
}

enum AgentDesktopCollaborationEvidenceDelivery {
  static func acceptsConfirmation(_ input: AgentMcpJSONObject, delivery: AgentMcpJSONObject?) -> Bool {
    guard ["evidence", "desktop_evidence"].contains(input.string("mode")), let delivery,
          Set(delivery.keys) == ["receipt_id", "content_sha256"],
          UUID(uuidString: delivery.string("receipt_id")) != nil,
          AgentCollaborationSourceAccess.validDigest(delivery.string("content_sha256")) else { return false }
    return true
  }

  static func exchange(input: AgentMcpJSONObject, confirmation: AgentMcpJSONObject?,
                       binding: String, expiresAt: Int64, now: Int64,
                       replay: inout AgentDesktopCollaborationResponseReplay,
                       read: (Bool) throws -> AgentMcpJSONObject) throws -> AgentMcpJSONObject? {
    let prefix = "evidence-delivery:"
    let contentField = input["mode"] == .string("desktop_evidence") ? "data_b64" : "content"
    if let confirmation {
      guard acceptsConfirmation(input, delivery: confirmation),
            case .response(let saved) = replay.lookup(key: prefix + confirmation.string("receipt_id"),
              fingerprint: binding, now: now),
            saved["delivery"] == .object(confirmation),
            let content = try read(false)[contentField]?.stringValue,
            digest(content) == confirmation.string("content_sha256"),
            let coverage = try read(true)["host_read_coverage"] else { return nil }
      return ["success": .bool(true), "status": .string("confirmed"),
              "delivery": .object(confirmation), "host_read_coverage": coverage]
    }
    var page = try read(false)
    guard let content = page[contentField]?.stringValue else { return nil }
    let id = UUID().uuidString.lowercased()
    let delivery: AgentMcpJSONObject = ["receipt_id": .string(id), "content_sha256": .string(digest(content))]
    replay.remember(["success": .bool(true), "delivery": .object(delivery)],
      key: prefix + id, fingerprint: binding, expiresAt: expiresAt, now: now)
    page["delivery"] = .object(delivery)
    page["success"] = .bool(true)
    page["status"] = .string("returned")
    return page
  }

  private static func digest(_ content: String) -> String {
    SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

enum AgentCollaborationCoordinatorUpdates {
  static let mode = "team_updates"
  static let instructions = "An active coordinator can use team_updates with optional cursor to discover late published versions. Keep next_cursor, including at the empty tail. Offered versions are not completed or verified work."

  struct Entry: Codable {
    let producer: AgentCollaborationToolEvidenceScope
    let publicationKey: String
  }

  static func prefix(_ scope: AgentCollaborationToolEvidenceScope) -> String {
    "coordinator-update:" + AgentMcpJSONCodec.sha256(["run": .string(scope.runId), "turn": .string(scope.turnId)]) + ":"
  }

  static func key(_ prefix: String, _ sequence: Int64) -> String {
    prefix + String(format: "%020lld", sequence)
  }

  static func cursorKey(_ cursor: String, scope: AgentCollaborationToolEvidenceScope) -> String {
    "coordinator-cursor:" + scope.ownershipDigest + ":" + cursor
  }

  static func grantKey(_ kind: String, id: String, hash: String, revision: Int64 = 0,
                       scope: AgentCollaborationToolEvidenceScope) -> String {
    "coordinator-grant:" + AgentMcpJSONCodec.sha256(["reader": .string(scope.ownershipDigest), "kind": .string(kind),
      "id": .string(id), "sha256": .string(hash), "revision": .int(revision)])
  }

  static func record(_ entry: Entry, database: AgentTeamHistoryDatabase) throws {
    let scope = entry.producer
    let prefix = Self.prefix(scope)
    let counter = prefix + "sequence"
    let prior = try database.researchRecord(Int64.self, conversationId: scope.conversationId, key: counter, revision: 1) ?? 0
    guard prior >= 0, prior < Int64.max else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    try database.insertResearchRecord(entry, conversationId: scope.conversationId, key: key(prefix, prior + 1), revision: 0)
    try database.removeResearchRecord(conversationId: scope.conversationId, key: counter)
    try database.insertResearchRecord(prior + 1, conversationId: scope.conversationId, key: counter, revision: 1)
  }
}

extension AgentTeamHistoryDatabase {
  func readableCollaborationRevision(_ reference: AgentCollaborationResearchReference,
                                     scope: AgentCollaborationToolEvidenceScope, offered: Bool = false) throws -> AgentCollaborationResearchRevision? {
    guard AgentCollaborationSourceAccess.validDigest(reference.objectId),
          AgentCollaborationSourceAccess.validDigest(reference.sha256), reference.revision > 0,
          let record = try researchRecord(AgentCollaborationResearchRevision.self, conversationId: scope.conversationId,
            key: "object:" + reference.objectId, revision: reference.revision), record.reference == reference,
          record.turnId != scope.turnId || (record.runId == scope.runId && (record.authorId == scope.memberId || offered))
    else { return nil }
    return record
  }

  func readableCollaborationEvidence(id: String, sha256: String, scope: AgentCollaborationToolEvidenceScope, offered: Bool = false)
    throws -> (record: AgentCollaborationCloudToolEvidence, bytes: Data)? {
    guard AgentCollaborationSourceAccess.validDigest(id), AgentCollaborationSourceAccess.validDigest(sha256),
          let record = try cloudEvidence(id: id, conversationId: scope.conversationId),
          record.scope.conversationId == scope.conversationId,
          record.scope.turnId != scope.turnId || record.scope == scope || (offered && record.scope.runId == scope.runId)
    else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(record)
    guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == sha256 else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    return (record, bytes)
  }
}
