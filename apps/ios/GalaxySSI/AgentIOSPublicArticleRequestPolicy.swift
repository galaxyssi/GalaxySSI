import Foundation

enum AgentIOSPublicArticleRequestPolicy {
  private static let weChatArticleHost = "mp.weixin.qq.com"

  static func headers(for url: URL) -> [String: String] {
    guard url.host?.lowercased() == weChatArticleHost else {
      return [:]
    }
    return [
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
      "Referer": "https://mp.weixin.qq.com/",
      "User-Agent": mobileWeChatUserAgent
    ]
  }

  private static let mobileWeChatUserAgent =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 " +
    "(KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.60 Language/zh_CN"
}
