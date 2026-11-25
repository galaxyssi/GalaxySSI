import Foundation

enum CloudImageSearchEvidence {
  private static let itemFields: Set<String> = ["citation_id", "source_kind", "evidence_level", "url", "title",
    "content_sha256", "rank", "published_at", "retrieved_at_millis", "media_evidence_level"]

  static func isImageOnly(_ output: AgentMcpJSONObject) -> Bool {
    guard let results = output["results"]?.arrayValue, !results.isEmpty,
      (output["documents"]?.arrayValue?.isEmpty ?? true) else { return false }
    return results.allSatisfy { $0.objectValue?["vertical"] == .string("image") }
  }

  static func prepare(_ output: AgentMcpJSONObject) -> AgentMcpJSONObject {
    guard var pack = output["evidence_pack"]?.objectValue,
      pack["protocol"] == .string(AgentIOSWebEvidencePack.protocolId),
      let items = pack["items"]?.arrayValue else { return output }
    pack["items"] = .array(items.compactMap { raw in
      guard let item = raw.objectValue else { return nil }
      var compact = item.filter { itemFields.contains($0.key) }
      compact["excerpt"] = .string(String(item.string("excerpt").prefix(240)))
      compact["images"] = .array((item["images"]?.arrayValue ?? []).compactMap { value in
        guard var image = value.objectValue,
          let original = AgentIOSWebEvidencePack.mediaURL(image.string("url")) else { return nil }
        for key in ["thumbnail_url", "original_url"] {
          image[key] = AgentIOSWebEvidencePack.mediaURL(image.string(key)).map(AgentMcpJSONValue.string)
        }
        if let preview = secureURL(image.string("thumbnail_url")), preview != original {
          image["url"] = .string(preview)
          image["original_url"] = image["original_url"] ?? .string(original)
          image["display_kind"] = .string("search_preview")
          image.removeValue(forKey: "width")
          image.removeValue(forKey: "height")
        }
        return .object(image)
      })
      return .object(compact)
    })
    var contract = pack["synthesis_contract"]?.objectValue ?? [:]
    contract["image_response"] = .object([
      "format": .string("Markdown images with source links; no duplicate JSON galleries"),
      "selection": .string("Show the exact requested subjects and qualifiers such as interior, exterior, diagram or real photograph. " +
        "Check each image's own title/alt, not only the parent page title. Prefer the object itself over recipes or comparisons unless asked. " +
        "If evidence is insufficient, refine the query instead of filling a count with adjacent topics."),
      "display": .string("Use images.url, a search preview where available. Keep original_url for an explicit original-resolution request; " +
        "it has not been downloaded or validated. Omitted candidates or original URLs require follow-up, not reconstruction."),
      "verification": .string("Titles and source relevance are evidence, not visual identification.")
    ])
    pack["synthesis_contract"] = .object(contract)
    pack["presentation"] = .string("compact_image_candidates")
    var prepared = output
    prepared["evidence_pack"] = .object(AgentIOSWebEvidenceVerification.attach(pack))
    return prepared
  }

  // Admit whole candidate URLs; never turn a truncated URL into a new destination.
  static func boundedModelJSON(_ output: AgentMcpJSONObject, maximumCharacters: Int) -> String {
    guard let pack = output["evidence_pack"]?.objectValue,
      pack["protocol"] == .string(AgentIOSWebEvidencePack.protocolId),
      let items = pack["items"]?.arrayValue else { return failure(maximumCharacters) }
    let root = output.filter { ["protocol", "operation", "status"].contains($0.key) }
    let encoded = AgentMcpJSONCodec.stringify(root.merging(["evidence_pack": .object(pack)]) { _, next in next })
    if encoded.count <= maximumCharacters { return encoded }
    let originalItems = items.compactMap(\.objectValue)
    let totalImages = originalItems.reduce(0) { $0 + ($1["images"]?.arrayValue?.count ?? 0) }
    func encode(_ selected: [AgentMcpJSONObject]) -> String {
      var compact = pack
      let ranked = selected.enumerated().map { index, item -> AgentMcpJSONValue in
        var item = item
        item["rank"] = .int(Int64(index + 1))
        return .object(item)
      }
      let count = selected.reduce(0) { $0 + ($1["images"]?.arrayValue?.count ?? 0) }
      compact["items"] = .array(ranked)
      compact["receipts"] = .array([])
      compact["presentation_partial"] = .bool(true)
      compact["presentation_original_item_count"] = .int(Int64(originalItems.count))
      compact["presentation_omitted_images"] = .int(Int64(max(0, totalImages - count)))
      compact["presentation_image_count"] = .int(Int64(count))
      var stats = pack["stats"]?.objectValue ?? [:]
      stats["item_count"] = .int(Int64(selected.count))
      stats["domain_count"] = .int(Int64(Set(selected.compactMap { URL(string: $0.string("url"))?.host }).count))
      stats["document_count"] = .int(Int64(selected.filter { $0["source_kind"] == .string("document") }.count))
      stats["discovery_count"] = .int(Int64(selected.filter { $0["source_kind"] != .string("document") }.count))
      compact["stats"] = .object(stats)
      return AgentMcpJSONCodec.stringify(root.merging([
        "evidence_pack": .object(AgentIOSWebEvidenceVerification.attach(compact))
      ]) { _, next in next })
    }
    var selected: [AgentMcpJSONObject] = []
    for item in originalItems {
      var admitted: [AgentMcpJSONValue] = []
      for raw in item["images"]?.arrayValue ?? [] {
        guard let image = raw.objectValue, let url = AgentIOSWebEvidencePack.mediaURL(image.string("url")) else { continue }
        var full = image.filter { ["url", "original_url", "title", "alt", "display_kind", "width", "height"].contains($0.key) }
        if full["original_url"] == full["url"] { full.removeValue(forKey: "original_url") }
        let minimal: AgentMcpJSONObject = ["url": .string(url), "media_fields_omitted": .bool(true)]
        for candidate in [full, minimal] {
          var trial = item
          trial["images"] = .array(admitted + [.object(candidate)])
          if encode(selected + [trial]).count <= maximumCharacters {
            admitted.append(.object(candidate))
            break
          }
        }
      }
      if !admitted.isEmpty {
        var item = item
        item["images"] = .array(admitted)
        selected.append(item)
      }
    }
    return selected.isEmpty ? failure(maximumCharacters) : encode(selected)
  }

  private static func secureURL(_ value: String) -> String? {
    guard let safe = AgentIOSWebEvidencePack.mediaURL(value), URLComponents(string: safe)?.scheme?.lowercased() == "https" else { return nil }
    return safe
  }

  private static func failure(_ maximumCharacters: Int) -> String {
    let value = AgentMcpJSONCodec.stringify(["status": .string("failed"), "error_code": .string("image_candidate_output_limit")])
    return value.count <= maximumCharacters ? value : (maximumCharacters >= 2 ? "{}" : "")
  }
}
