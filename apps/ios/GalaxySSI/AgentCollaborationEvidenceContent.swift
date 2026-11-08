import CryptoKit
import Foundation

struct AgentCollaborationEvidenceContent {
  static let offsetUnit = "utf16_code_units"
  static let jsonStringEncoding = "galaxyssi_json_string_utf8_v1"
  static let digestScope = "complete_evidence_content"
  static let coverageTrust = "host_served_pages_not_comprehension_or_claim_verification"

  static func coverageBinding(_ scope: AgentCollaborationToolEvidenceScope, id: String, hash: String,
                              origin: String) -> AgentMcpJSONObject {
    ["format": .string("galaxyssi.ios-evidence-read-coverage.v1"), "mode": .string("scoped_pages"),
      "evidence_id": .string(id), "sha256": .string(hash), "origin": .string(origin),
      "reader": .object(["run_id": .string(scope.runId), "conversation_id": .string(scope.conversationId),
        "turn_id": .string(scope.turnId), "member_id": .string(scope.memberId), "source_id": .string(scope.sourceId)]),
      "trust": .string(coverageTrust), "transfers_coverage": .bool(false)]
  }

  static func frozenTextCoverage(_ data: Data, scope: AgentCollaborationToolEvidenceScope,
                                 id: String, hash: String, origin: String) -> AgentMcpJSONObject {
    let text = String(decoding: data, as: UTF8.self)
    let total = Int64(text.utf16.count)
    return coverageBinding(scope, id: id, hash: hash, origin: origin).merging([
      "complete": .bool(true), "covered_characters": .int(total), "total_characters": .int(total),
      "first_missing_offset": .null, "offset_unit": .string(offsetUnit),
      "content_utf8_sha256": .string(hash), "content_sha256": .string(digest(AgentMcpJSONCodec.stringify(.string(text)))),
      "content_sha256_encoding": .string(jsonStringEncoding), "content_digest_scope": .string(digestScope)
    ]) { _, value in value }
  }

  static func byteCoverage(_ scope: AgentCollaborationToolEvidenceScope, id: String, hash: String,
                           total: Int64, firstMissing: Int64) -> AgentMcpJSONObject {
    coverageBinding(scope, id: id, hash: hash, origin: "desktop_codex_tool").merging([
      "complete": .bool(firstMissing == total), "contiguous_bytes": .int(firstMissing), "total_bytes": .int(total),
      "first_missing_offset": firstMissing == total ? .null : .int(firstMissing),
      "offset_unit": .string("bytes"), "content_sha256": .string(hash),
      "content_sha256_encoding": .string("raw_bytes"), "content_digest_scope": .string(digestScope)
    ]) { _, value in value }
  }

  struct Page {
    let content: String
    let end: Int64
    let wireTotal: Int64
    let ledgerStart: Int64
    let ledgerEnd: Int64
    let total: Int64
    let original: String

    func firstMissingOffset(_ missing: Int64) throws -> AgentMcpJSONValue {
      guard missing >= 0, missing <= total,
            let index = original.index(original.startIndex, offsetBy: Int(missing), limitedBy: original.endIndex) else {
        throw AgentTeamHistoryDatabase.Failure.corrupt
      }
      return missing == total ? .null : .int(Int64(index.utf16Offset(in: original)))
    }

    var rawDigest: String { AgentCollaborationEvidenceContent.digest(original) }
    var jsonStringDigest: String {
      AgentCollaborationEvidenceContent.digest(AgentMcpJSONCodec.stringify(.string(original)))
    }

    func wireCoverage(_ ledgerSummary: AgentMcpJSONObject) throws -> AgentMcpJSONObject {
      var result = ledgerSummary
      if case .int(let missing)? = result["first_missing_offset"] {
        result["first_missing_offset"] = try firstMissingOffset(missing)
      }
      result["total_characters"] = .int(wireTotal)
      if result["complete"] == .bool(true) { result["covered_characters"] = .int(wireTotal) }
      result["content_utf8_sha256"] = .string(rawDigest)
      result["content_sha256"] = .string(jsonStringDigest)
      result["content_sha256_encoding"] = .string(AgentCollaborationEvidenceContent.jsonStringEncoding)
      result["content_digest_scope"] = .string(AgentCollaborationEvidenceContent.digestScope)
      result["offset_unit"] = .string(AgentCollaborationEvidenceContent.offsetUnit)
      result["trust"] = .string(AgentCollaborationEvidenceContent.coverageTrust)
      return result
    }
  }

  static func page(_ bytes: Data, offset: Int64, evidence: Bool) throws -> Page {
    let original = String(decoding: bytes, as: UTF8.self)
    let ledgerTotal = Int64(original.count)
    let total = evidence ? Int64(original.utf16.count) : ledgerTotal
    guard offset >= 0, offset <= total else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let start: String.Index
    if evidence {
      // Persisted coverage is measured in Swift Characters, not wire UTF-16 offsets.
      let utf16 = original.utf16
      guard let index = String.Index(utf16.index(utf16.startIndex, offsetBy: Int(offset)), within: original)
      else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      start = index
    } else {
      start = original.index(original.startIndex, offsetBy: Int(offset))
    }
    let ledgerStart = Int64(original.distance(from: original.startIndex, to: start))
    let ledgerEnd = min(ledgerTotal, ledgerStart + 2_000)
    let end = original.index(start, offsetBy: Int(ledgerEnd - ledgerStart))
    return Page(content: String(original[start..<end]),
      end: evidence ? Int64(end.utf16Offset(in: original)) : ledgerEnd, wireTotal: total,
      ledgerStart: ledgerStart, ledgerEnd: ledgerEnd, total: ledgerTotal, original: original)
  }

  private static func digest(_ content: String) -> String {
    SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
