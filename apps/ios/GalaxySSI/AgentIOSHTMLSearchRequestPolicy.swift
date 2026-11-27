import Foundation

struct AgentIOSHTMLSearchRequestPolicy {
  let source: String

  func headers(for url: URL) -> [String: String] {
    guard source == "baidu", let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "https", parts.host?.lowercased() == "www.baidu.com",
      parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
      parts.percentEncodedPath == "/s" else { return [:] }
    return ["User-Agent": Self.baiduUserAgent]
  }

  static let baiduUserAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
}
