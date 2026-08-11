import Foundation

/// Normalizes model-provided download arguments before they reach URLSession.
enum AgentIOSPublicDownloadPolicy {
  private static let httpsURLPattern = #"https://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+"#
  private static let trailingProsePunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}"]

  static func normalizeHTTPSURL(_ value: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let match = trimmed.range(
      of: httpsURLPattern,
      options: [.regularExpression, .caseInsensitive]
    ) else {
      return nil
    }

    var candidate = String(trimmed[match])
    while let last = candidate.last, trailingProsePunctuation.contains(last) {
      candidate.removeLast()
    }
    guard let components = URLComponents(string: candidate),
          components.scheme?.caseInsensitiveCompare("https") == .orderedSame,
          let host = components.host,
          !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          components.user == nil,
          components.password == nil,
          let url = components.url else {
      return nil
    }
    return url
  }
}
