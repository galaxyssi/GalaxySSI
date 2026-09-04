import CryptoKit
import Foundation

struct AgentIOSWebCitationValidation: Equatable {
  var status: String
  var evidenceItemCount: Int
  var verifiedEvidenceItemCount: Int
  var citedURLs: [String]
  var invalidCitationURLs: [String]

  var valid: Bool { status == "verified" }
  var requiresRepair: Bool { evidenceItemCount > 0 && !valid }
}

enum AgentIOSWebEvidenceVerification {
  static func attach(_ pack: AgentMcpJSONObject) -> AgentMcpJSONObject {
    var enriched = pack
    let conflicts = conflictReview(objects(pack["items"]))
    enriched["verification"] = .object(verify(enriched))
    enriched["conflict_review"] = .object(conflicts)
    var contract = pack["synthesis_contract"]?.objectValue ?? [:]
    contract["detect_material_conflicts"] = .bool(true)
    contract["surface_uncertainty"] = .bool(true)
    contract["never_invent_citations"] = .bool(true)
    contract["allowed_citation_urls"] = .string("evidence_pack_items_only")
    contract["compare_independent_retrieved_bodies"] = .bool(true)
    contract["host_conflict_candidates_require_model_review"] = .bool(true)
    enriched["synthesis_contract"] = .object(contract)
    return enriched
  }

  static func verify(_ pack: AgentMcpJSONObject) -> AgentMcpJSONObject {
    let protocolValid = pack["protocol"]?.stringValue == AgentIOSWebEvidencePack.protocolId
    let items = objects(pack["items"])
    var invalid: [AgentMcpJSONValue] = []
    var valid: [AgentMcpJSONObject] = []
    var seenURLs = Set<String>()
    var seenIDs = Set<String>()

    for (index, item) in items.enumerated() {
      var reasons: [AgentMcpJSONValue] = []
      let rawURL = item["url"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let canonical = AgentIOSWebEvidencePack.canonicalURL(rawURL)
      let contentHash = item["content_sha256"]?.stringValue?.lowercased() ?? ""
      let citationID = item["citation_id"]?.stringValue?.lowercased() ?? ""
      let rank = max(0, Int(item["rank"]?.intValue ?? 0))
      if !isWebURL(canonical) || canonical != rawURL { reasons.append(.string("invalid_or_noncanonical_url")) }
      if !matches(contentHash, pattern: #"^[a-f0-9]{64}$"#) { reasons.append(.string("invalid_content_sha256")) }
      if !matches(citationID, pattern: #"^[a-f0-9]{24}$"#) { reasons.append(.string("invalid_citation_id")) }
      if rank != index + 1 { reasons.append(.string("invalid_rank")) }
      if !canonical.isEmpty, !seenURLs.insert(canonical).inserted { reasons.append(.string("duplicate_url")) }
      if !citationID.isEmpty, !seenIDs.insert(citationID).inserted { reasons.append(.string("duplicate_citation_id")) }
      if !canonical.isEmpty, matches(contentHash, pattern: #"^[a-f0-9]{64}$"#),
         citationID != expectedCitationID(url: canonical, contentHash: contentHash) {
        reasons.append(.string("citation_id_mismatch"))
      }
      if reasons.isEmpty {
        valid.append([
          "citation_id": .string(citationID),
          "url": .string(canonical),
          "content_sha256": .string(contentHash)
        ])
      } else {
        invalid.append(.object([
          "index": .int(Int64(index)),
          "citation_id": .string(String(citationID.prefix(32))),
          "reasons": .array(reasons)
        ]))
      }
    }

    let status: String
    if !protocolValid || (!items.isEmpty && valid.isEmpty) {
      status = "failed"
    } else if !invalid.isEmpty {
      status = "partial"
    } else {
      status = "verified"
    }
    let manifest = valid.map {
      "\($0["citation_id"]?.stringValue ?? "")\n\($0["url"]?.stringValue ?? "")\n\($0["content_sha256"]?.stringValue ?? "")"
    }.joined(separator: "\n")
    return [
      "status": .string(status),
      "protocol_valid": .bool(protocolValid),
      "item_count": .int(Int64(items.count)),
      "valid_item_count": .int(Int64(valid.count)),
      "invalid_item_count": .int(Int64(invalid.count)),
      "invalid_items": .array(Array(invalid.prefix(12))),
      "citation_manifest": .array(valid.map(AgentMcpJSONValue.object)),
      "citation_manifest_sha256": .string(sha256(manifest)),
      "verified_at_build_time": .bool(true)
    ]
  }

  static func validateAnswer(
    _ answer: String,
    encodedToolResults: [(String, String)]
  ) -> AgentIOSWebCitationValidation {
    validateAnswer(answer, packs: encodedToolResults.compactMap { decodePack($0.1) })
  }

  static func validateAnswer(
    _ answer: String,
    packs: [AgentMcpJSONObject]
  ) -> AgentIOSWebCitationValidation {
    var allowed = Set<String>()
    var evidenceItems = 0
    var verifiedItems = 0
    for pack in packs {
      let items = objects(pack["items"])
      evidenceItems += items.count
      for item in items {
        let url = AgentIOSWebEvidencePack.canonicalURL(item["url"]?.stringValue ?? "")
        let hash = item["content_sha256"]?.stringValue?.lowercased() ?? ""
        let citationID = item["citation_id"]?.stringValue?.lowercased() ?? ""
        if isWebURL(url), matches(hash, pattern: #"^[a-f0-9]{64}$"#),
           citationID == expectedCitationID(url: url, contentHash: hash) {
          allowed.insert(url)
          verifiedItems += 1
        }
      }
    }
    let cited = markdownURLs(answer).map {
      AgentIOSWebEvidencePack.canonicalURL($0.trimmingCharacters(in: CharacterSet(charactersIn: ".,;")))
    }.filter { !$0.isEmpty }.uniqued()
    let invalid = cited.filter { !allowed.contains($0) }
    let status: String
    if evidenceItems == 0 {
      status = "not_required"
    } else if verifiedItems == 0 {
      status = "evidence_unverified"
    } else if cited.isEmpty {
      status = "missing_citations"
    } else if !invalid.isEmpty {
      status = "foreign_citations"
    } else {
      status = "verified"
    }
    return AgentIOSWebCitationValidation(
      status: status,
      evidenceItemCount: evidenceItems,
      verifiedEvidenceItemCount: verifiedItems,
      citedURLs: cited,
      invalidCitationURLs: invalid
    )
  }

  static func repairPrompt(
    validation: AgentIOSWebCitationValidation,
    encodedToolResults: [(String, String)]
  ) -> String {
    let allowed = encodedToolResults.compactMap { decodePack($0.1) }
      .flatMap { objects($0["items"]) }
      .compactMap { item -> String? in
        let url = AgentIOSWebEvidencePack.canonicalURL(item["url"]?.stringValue ?? "")
        return url.isEmpty ? nil : url
      }
      .uniqued()
      .prefix(12)
    var prompt = "Your draft did not pass SignalASI citation verification (status=\(validation.status)). " +
      "Rewrite the complete user-facing answer once. Keep useful conclusions, compare material disagreement " +
      "between independent retrieved bodies, state uncertainty, and place Markdown source links next to supported " +
      "claims. Cite only these verified Evidence Pack URLs; do not invent or substitute links:\n"
    for url in allowed { prompt += "- \(url)\n" }
    return String(prompt.prefix(8_000))
  }

  static func decodePack(_ encoded: String) -> AgentMcpJSONObject? {
    guard let data = encoded.data(using: .utf8),
          let root = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data) else { return nil }
    if root["protocol"]?.stringValue == AgentIOSWebEvidencePack.protocolId { return root }
    return root["evidence_pack"]?.objectValue
  }

  private static func conflictReview(_ items: [AgentMcpJSONObject]) -> AgentMcpJSONObject {
    let retrieved = items.filter { $0["evidence_level"]?.stringValue == "retrieved_body" }
    let domains = Set(retrieved.compactMap { host($0["url"]?.stringValue ?? "") })
    let duplicateGroups = Dictionary(grouping: retrieved) { $0["content_sha256"]?.stringValue ?? "" }
      .filter { matches($0.key, pattern: #"^[a-f0-9]{64}$"#) && Set($0.value.compactMap { $0["url"]?.stringValue }).count > 1 }
      .prefix(8)
      .map { entry in
        let (hash, group) = entry
        return AgentMcpJSONValue.object([
          "content_sha256": .string(hash),
          "citation_ids": .array(group.compactMap { $0["citation_id"]?.stringValue }.map(AgentMcpJSONValue.string)),
          "urls": .array(group.compactMap { $0["url"]?.stringValue }.map(AgentMcpJSONValue.string)),
          "independent_evidence": .bool(false)
        ])
      }
    let claims = retrieved.flatMap(numericClaims)
    let conflictGroups = Dictionary(grouping: claims, by: \NumericClaim.skeleton).values.filter { group in
      Set(group.map(\.domain)).count > 1 && Set(group.map { $0.values.joined(separator: "|") }).count > 1
    }.prefix(8)
    let conflicts = conflictGroups.map { group in
      AgentMcpJSONValue.object([
        "kind": .string("numeric_value_mismatch"),
        "confidence": .string("high"),
        "requires_model_review": .bool(true),
        "claims": .array(group.prefix(4).map { claim in
          .object([
            "citation_id": .string(claim.citationID),
            "url": .string(claim.url),
            "text": .string(claim.text),
            "values": .array(claim.values.map(AgentMcpJSONValue.string))
          ])
        })
      ])
    }
    return [
      "status": .string(conflicts.isEmpty ? "no_structural_conflict_detected" : "potential_conflict"),
      "review_required": .bool(domains.count >= 2),
      "independent_retrieved_domain_count": .int(Int64(domains.count)),
      "duplicate_content_groups": .array(Array(duplicateGroups)),
      "potential_conflicts": .array(Array(conflicts)),
      "detector_scope": .string("exact_cross_domain_numeric_claim_structure"),
      "semantic_resolution": .string("current_model_required")
    ]
  }

  private static func numericClaims(_ item: AgentMcpJSONObject) -> [NumericClaim] {
    let citationID = item["citation_id"]?.stringValue ?? ""
    let url = AgentIOSWebEvidencePack.canonicalURL(item["url"]?.stringValue ?? "")
    guard !citationID.isEmpty, let domain = host(url) else { return [] }
    return splitSentences(item["excerpt"]?.stringValue ?? "").prefix(64).compactMap { sentence in
      guard sentence.count >= 12, sentence.count <= 500 else { return nil }
      let values = regexMatches(sentence, pattern: numberPattern).map(normalizeValue)
      guard !values.isEmpty else { return nil }
      let skeleton = replacingMatches(sentence.lowercased(), pattern: numberPattern, replacement: "<value>")
        .replacingOccurrences(of: #"[^\p{L}\p{N}<>]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard skeleton.count >= 10 else { return nil }
      return NumericClaim(citationID: citationID, url: url, domain: domain, text: String(sentence.prefix(280)), values: values, skeleton: skeleton)
    }
  }

  private static func markdownURLs(_ answer: String) -> [String] {
    regexCaptureMatches(answer, pattern: #"\[[^]\n]{0,300}\]\((https?://[^\s)]+)(?:\s+[^)]*)?\)"#, group: 1)
  }

  private static func splitSentences(_ value: String) -> [String] {
    value.components(separatedBy: CharacterSet(charactersIn: "\n.!?;\u{3002}\u{ff01}\u{ff1f}\u{ff1b}"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func regexMatches(_ value: String, pattern: String) -> [String] {
    regexCaptureMatches(value, pattern: pattern, group: 0)
  }

  private static func regexCaptureMatches(_ value: String, pattern: String, group: Int) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
    let source = value as NSString
    return regex.matches(in: value, range: NSRange(location: 0, length: source.length)).compactMap { match in
      let range = match.range(at: group)
      return range.location == NSNotFound ? nil : source.substring(with: range)
    }
  }

  private static func replacingMatches(_ value: String, pattern: String, replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return value }
    return regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: replacement)
  }

  private static func expectedCitationID(url: String, contentHash: String) -> String {
    String(sha256("\(url)\n\(contentHash)").prefix(24))
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private static func isWebURL(_ value: String) -> Bool {
    guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased() else { return false }
    return (scheme == "http" || scheme == "https") && !(components.host ?? "").isEmpty
  }

  private static func host(_ value: String) -> String? {
    guard let rawHost = URLComponents(string: value)?.host?.lowercased() else { return nil }
    let host = rawHost.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    return host.isEmpty ? nil : host
  }

  private static func objects(_ value: AgentMcpJSONValue?) -> [AgentMcpJSONObject] {
    value?.arrayValue?.compactMap(\.objectValue) ?? []
  }

  private static func matches(_ value: String, pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }

  private static func normalizeValue(_ value: String) -> String {
    value.lowercased().replacingOccurrences(of: ",", with: "")
      .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
  }

  private struct NumericClaim {
    var citationID: String
    var url: String
    var domain: String
    var text: String
    var values: [String]
    var skeleton: String
  }

  private static let numberPattern =
    #"(?<![\p{L}\p{N}])[+-]?\d+(?:[.,]\d+)*(?:\s*(?:%|\x{2030}|\x{00b0}[cf]?|ms|s|sec|seconds?|minutes?|hours?|days?|kb|mb|gb|tb|kib|mib|gib|tib|hz|khz|mhz|ghz|w|kw|mw|v|mv|a|ma|usd|eur|cny|rmb|\x{5143}|\x{7f8e}\x{5143}|\x{6b27}\x{5143}|\x{79d2}|\x{5206}\x{949f}|\x{5c0f}\x{65f6}|\x{5929}|\x{5e74}|\x{6708}|\x{65e5}))?"#
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
