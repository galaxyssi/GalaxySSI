import Foundation

struct AgentIOSImageSearchRequestPolicy {
  var source: String
  var braveKey: String = ""
  var landing: URL? = nil

  static let supported: Set<String> = ["sogou_image", "brave_image", "duckduckgo_image"]
  static func validBraveKey(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 8192 && value.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
  }
  static func weight(_ source: String) -> Double { source == "sogou_image" ? 1.2 : 1 }
  static func authority(_ source: String) -> Double { source == "brave_image" ? 0.8 : 0.75 }

  func headers(for url: URL) -> [String: String] {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          parts.scheme == "https", parts.user == nil, parts.password == nil,
          parts.port == nil || parts.port == 443 else { return [:] }
    if source == "brave_image", parts.host?.lowercased() == "api.search.brave.com",
       parts.percentEncodedPath == "/res/v1/images/search", Self.validBraveKey(braveKey) {
      return ["Accept": "application/json", "X-Subscription-Token": braveKey]
    }
    if source == "duckduckgo_image", parts.host?.lowercased() == "duckduckgo.com",
       parts.percentEncodedPath == "/" || parts.percentEncodedPath == "/i.js" {
      var values = ["Accept": parts.percentEncodedPath == "/i.js" ? "application/json" : "text/html,application/xhtml+xml"]
      values["User-Agent"] = Self.browserUserAgent
      if parts.percentEncodedPath == "/i.js", let landing,
         landing.scheme == "https", landing.host?.lowercased() == "duckduckgo.com",
         landing.port == nil || landing.port == 443, landing.user == nil, landing.password == nil, landing.path == "/" {
        values["Referer"] = landing.absoluteString
      }
      return values
    }
    return [:]
  }

  private static let browserUserAgent =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"

  static func duckDuckGoToken(_ source: String) throws -> String {
    let regex = try NSRegularExpression(pattern: #"\bvqd\s*=\s*['"]([^'"]{1,256})['"]"#)
    guard let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
          let range = Range(match.range(at: 1), in: source) else { throw AgentIOSURLSessionWebError.imageSearchTokenUnavailable }
    let token = String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty, token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
      throw AgentIOSURLSessionWebError.imageSearchTokenUnavailable
    }
    return token
  }
}
