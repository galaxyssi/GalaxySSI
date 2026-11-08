import CryptoKit
import Foundation

enum AgentCollaborationSourceAccess {
  static let mode = "source_access"
  static let pageSize = 20
  static let instructions = "Use source_access with exact workspace object_id, revision and sha256 to inspect direct sources. Follow next_cursor with the same root. Available means readable now, not read or verified. Read relevant originals or report unavailable evidence. No access is granted."

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
    guard input["mode"] == .string("evidence"), let delivery,
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
    if let confirmation {
      guard acceptsConfirmation(input, delivery: confirmation),
            case .response(let saved) = replay.lookup(key: prefix + confirmation.string("receipt_id"),
              fingerprint: binding, now: now),
            saved["delivery"] == .object(confirmation),
            let content = try read(false)["content"]?.stringValue,
            digest(content) == confirmation.string("content_sha256"),
            let coverage = try read(true)["host_read_coverage"] else { return nil }
      return ["success": .bool(true), "status": .string("confirmed"),
              "delivery": .object(confirmation), "host_read_coverage": coverage]
    }
    var page = try read(false)
    guard let content = page["content"]?.stringValue else { return nil }
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

extension AgentTeamHistoryDatabase {
  func readableCollaborationRevision(_ reference: AgentCollaborationResearchReference,
                                     scope: AgentCollaborationToolEvidenceScope) throws -> AgentCollaborationResearchRevision? {
    guard AgentCollaborationSourceAccess.validDigest(reference.objectId),
          AgentCollaborationSourceAccess.validDigest(reference.sha256), reference.revision > 0,
          let record = try researchRecord(AgentCollaborationResearchRevision.self, conversationId: scope.conversationId,
            key: "object:" + reference.objectId, revision: reference.revision), record.reference == reference,
          record.turnId != scope.turnId || (record.runId == scope.runId && record.authorId == scope.memberId) else { return nil }
    return record
  }

  func readableCollaborationEvidence(id: String, sha256: String, scope: AgentCollaborationToolEvidenceScope)
    throws -> (record: AgentCollaborationCloudToolEvidence, bytes: Data)? {
    guard AgentCollaborationSourceAccess.validDigest(id), AgentCollaborationSourceAccess.validDigest(sha256),
          let record = try cloudEvidence(id: id, conversationId: scope.conversationId),
          record.scope.conversationId == scope.conversationId,
          record.scope.turnId != scope.turnId || record.scope == scope else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(record)
    guard SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == sha256 else {
      throw AgentTeamHistoryDatabase.Failure.corrupt
    }
    return (record, bytes)
  }
}
