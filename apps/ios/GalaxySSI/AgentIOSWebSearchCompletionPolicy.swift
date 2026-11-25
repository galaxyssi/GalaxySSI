import Foundation

enum AgentIOSWebSearchCompletionPolicy {
  struct Candidate {
    var provider: String
    var title: String
    var url: String
    var excerpt: String
    var imageURL = ""
  }

  static func hasSufficientEvidence(
    profile: String,
    explicitSources: Bool,
    groups: [[String]],
    limit: Int,
    providerCount: Int,
    query: String = "",
    candidates: [Candidate]? = nil,
    imageOnly: Bool = false
  ) -> Bool {
    let normalizedProfile = profile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !explicitSources, normalizedProfile != "deep", limit > 0 else { return false }
    if imageOnly {
      let images = Set((candidates ?? []).compactMap { candidate -> String? in
        guard AgentIOSWebEvidencePack.mediaURL(candidate.url) != nil else { return nil }
        return AgentIOSWebEvidencePack.mediaURL(candidate.imageURL)
      })
      return images.count >= limit
    }
    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let candidates {
      let queryTokens = tokens(query)
      guard !queryTokens.isEmpty else { return false }
      var seen = Set<String>()
      let evidence = candidates.filter { candidate in
        guard candidate.excerpt.utf16.count >= 30, AgentIOSWebEvidencePack.mediaURL(candidate.url) != nil else { return false }
        let words = tokens(candidate.title + " " + candidate.excerpt)
        guard queryTokens.intersection(words).count * 2 >= queryTokens.count else { return false }
        return seen.insert(AgentIOSWebEvidencePack.canonicalURL(candidate.url)).inserted
      }
      let domains = Set(evidence.compactMap { URL(string: AgentIOSWebEvidencePack.canonicalURL($0.url))?.host })
      let fast = normalizedProfile == "fast"
      return evidence.count >= (fast ? min(limit, 4) : max(limit, 6)) &&
        domains.count >= min(limit, 3) && (fast || Set(evidence.map(\.provider)).count >= 2)
    }

    let successfulGroups = groups.filter { !$0.isEmpty }
    let uniqueURLs = Set(groups.flatMap { $0 }.map(canonicalURL).filter { !$0.isEmpty })
    let uniqueDomains = Set(uniqueURLs.compactMap { url in
      URL(string: url)?.host?.lowercased().removingPrefix("www.")
    })
    let fast = normalizedProfile == "fast"
    let requiredSources = fast
      ? min(providerCount, 2)
      : min(providerCount, max(2, providerCount - 1))
    let requiredResults = fast ? max(limit, 6) : max(limit * 2, 12)
    let requiredDomains = fast
      ? min(providerCount, 2)
      : min(providerCount, max(2, providerCount - 1))
    return successfulGroups.count >= requiredSources &&
      uniqueURLs.count >= requiredResults &&
      uniqueDomains.count >= requiredDomains
  }

  private static func tokens(_ value: String) -> Set<String> {
    let normalized = value.precomposedStringWithCompatibilityMapping.lowercased()
    func matches(_ expression: NSRegularExpression?) -> [String] {
      guard let regex = expression else { return [] }
      return regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap {
        Range($0.range, in: normalized).map { String(normalized[$0]) }
      }
    }
    var values = matches(latinTokens)
    for group in matches(cjkTokens) {
      if group.count == 1 { values.append(group) }
      else { values.append(contentsOf: zip(group, group.dropFirst()).map { String([$0.0, $0.1]) }) }
    }
    return Set(values)
  }

  private static let latinTokens = try? NSRegularExpression(pattern: "[a-z0-9][a-z0-9_+.-]{1,}")
  private static let cjkTokens = try? NSRegularExpression(pattern: "[\u{3400}-\u{9fff}]+")

  private static func canonicalURL(_ value: String) -> String {
    guard let url = URL(string: value),
          let scheme = url.scheme?.lowercased(),
          let host = url.host?.lowercased() else {
      return ""
    }
    var result = "\(scheme)://\(host)\(url.path)"
    if let query = url.query, !query.isEmpty {
      result += "?\(query)"
    }
    return result
  }
}

private extension String {
  func removingPrefix(_ prefix: String) -> String {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
  }
}
