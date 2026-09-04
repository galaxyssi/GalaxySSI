import Foundation

enum AgentIOSWebSearchCompletionPolicy {
  static func hasSufficientEvidence(
    profile: String,
    explicitSources: Bool,
    groups: [[String]],
    limit: Int,
    providerCount: Int
  ) -> Bool {
    let normalizedProfile = profile.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !explicitSources, normalizedProfile != "deep" else { return false }

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
