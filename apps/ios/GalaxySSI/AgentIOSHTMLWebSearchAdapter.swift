import Foundation
import SwiftSoup

enum AgentIOSHTMLWebSearchAdapter {
  typealias Entry = AgentIOSJSONWebSearchAdapter.Entry
  static let entries: [Entry] = [
    .init(id: "brave", title: "Brave Search", vertical: .general,
      template: "https://search.brave.com/search?q={query}&source=web", authority: 0.5),
    .init(id: "mojeek", title: "Mojeek", vertical: .general,
      template: "https://www.mojeek.com/search?q={query}", authority: 0.5),
    .init(id: "qwant", title: "Qwant", vertical: .regional,
      template: "https://www.qwant.com/?q={query}&t=web", authority: 0.5),
    .init(id: "yahoo", title: "Yahoo", vertical: .general,
      template: "https://search.yahoo.com/search?p={query}", authority: 0.5),
    .init(id: "yandex", title: "Yandex", vertical: .regional,
      template: "https://yandex.com/search/?text={query}", authority: 0.5),
    .init(id: "ecosia", title: "Ecosia", vertical: .general,
      template: "https://www.ecosia.org/search?q={query}", authority: 0.5),
    .init(id: "startpage", title: "Startpage", vertical: .general,
      template: "https://www.startpage.com/sp/search?query={query}", authority: 0.5),
    .init(id: "sogou", title: "Sogou", vertical: .regional,
      template: "https://www.sogou.com/web?query={query}", authority: 0.5, languages: ["zh"]),
    .init(id: "naver", title: "Naver", vertical: .regional,
      template: "https://search.naver.com/search.naver?query={query}", authority: 0.5, languages: ["ko"]),
    .init(id: "google", title: "Google", vertical: .general,
      template: "https://www.google.com/search?q={query}&num={limit}", authority: 0.5, enabledByDefault: false),
    .init(id: "bing_news", title: "Bing News", vertical: .news,
      template: "https://www.bing.com/news/search?q={query}&count={limit}", authority: 0.5),
    .init(id: "brave_news", title: "Brave News", vertical: .news,
      template: "https://search.brave.com/news?q={query}", authority: 0.5),
    .init(id: "x_public", title: "X Public Posts", vertical: .social,
      template: "https://html.duckduckgo.com/html/?q=site%3Ax.com%2Fstatus+{query}", authority: 0.65),
    .init(id: "wechat_public", title: "WeChat Public Articles", vertical: .publishing,
      template: "https://weixin.sogou.com/weixin?type=2&query={query}", authority: 0.75, languages: ["zh"]),
    .init(id: "zhihu_public", title: "Zhihu Public Content", vertical: .qa,
      template: "https://html.duckduckgo.com/html/?q=site%3Azhihu.com+{query}", authority: 0.7, languages: ["zh"]),
    .init(id: "xiaohongshu_public", title: "Xiaohongshu Public Notes", vertical: .social,
      template: "https://html.duckduckgo.com/html/?q=site%3Axiaohongshu.com+{query}", authority: 0.65, languages: ["zh"]),
    .init(id: "pypi", title: "PyPI", vertical: .packages,
      template: "https://pypi.org/search/?q={query}", authority: 0.8)
  ]

  static func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

  static func parse(_ source: String, id: String, baseURL: String, limit: Int) throws -> [AgentIOSPublicSearchParser.Hit] {
    guard entry(id) != nil, Int64(source.utf8.count) <= AgentIOSWebMediaNativeToolCatalog.maxFetchBytes else {
      throw AgentIOSURLSessionWebError.invalidSearchResponse
    }
    guard limit > 0 else { return [] }
    if id == "wechat_public" {
      let document = try SwiftSoup.parse(source, baseURL)
      try document.select("script, style, nav, footer, header").remove()
      var hits: [AgentIOSPublicSearchParser.Hit] = [], seen = Set<String>()
      for anchor in try document.select("a[href]").array().prefix(2000) {
        guard let url = AgentIOSPublicSearchParser.destination(try anchor.attr("href"), baseURL: baseURL),
          accepts(url, id: id) else { continue }
        let title = String(try anchor.text().prefix(2048))
        guard !title.isEmpty, seen.insert(url).inserted else { continue }
        hits.append(.init(title: title, url: url, excerpt: ""))
        if hits.count >= min(limit, 100) { break }
      }
      return hits
    }
    return Array(try AgentIOSPublicSearchParser.parse(source, baseURL: baseURL, limit: 100)
      .filter { accepts($0.url, id: id) }.prefix(min(limit, 100)))
  }

  private static func accepts(_ url: String, id: String) -> Bool {
    guard let parts = URLComponents(string: url), let rawHost = parts.host?.lowercased(),
      parts.user == nil, parts.password == nil else { return false }
    let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
    switch id {
    case "x_public": return ["x.com", "twitter.com"].contains(host) && parts.path.contains("/status/")
    case "wechat_public": return host == "mp.weixin.qq.com" || (host == "weixin.sogou.com" && parts.path.hasPrefix("/link"))
    case "zhihu_public": return ["zhihu.com", "zhuanlan.zhihu.com"].contains(host)
    case "xiaohongshu_public": return host == "xiaohongshu.com" &&
      (parts.path.hasPrefix("/explore/") || parts.path.hasPrefix("/discovery/item/"))
    default: return true
    }
  }
}
