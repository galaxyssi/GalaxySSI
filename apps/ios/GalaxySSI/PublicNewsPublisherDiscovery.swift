import Foundation

struct PublicNewsPublisherState: Codable, Equatable {
  struct Feed: Codable, Equatable {
    let url: URL
    let publisher: String
    var interests: Set<PublicNewsInterest>
    var pollAfter: Date
    var failures = 0

    var source: PublicNewsSource {
      PublicNewsSource(publisher: publisher, url: url, additionalInterests: interests, learned: true)
    }
  }

  var feeds: [Feed] = []
  var probeAfter: [String: Date] = [:]
  var builtInOffset = 0

  mutating func plan(now: Date, enabled: Bool, probe: Bool) -> [PublicNewsSource] {
    feeds.removeAll { !PublicNewsPublisherDiscovery.acceptsFeed($0.url, publisher: $0.publisher) }
    let due = enabled ? feeds.filter { $0.pollAfter <= now }.sorted {
      $0.pollAfter == $1.pollAfter ? $0.url.absoluteString < $1.url.absoluteString : $0.pollAfter < $1.pollAfter
    }.prefix(2).map(\.source) : []
    let builtIn = PublicNewsSource.builtIn
    guard !builtIn.isEmpty else { return due }
    let start = max(0, builtInOffset) % builtIn.count
    let count = min(builtIn.count, 4 - due.count - (probe ? 1 : 0))
    let selected = (0..<count).map { builtIn[(start + $0) % builtIn.count] }
    builtInOffset = (start + count) % builtIn.count
    return selected + due
  }

  mutating func learn(_ urls: [URL], from article: PublicNewsArticle, host: String, now: Date) {
    let interests = article.interests ?? []
    guard !interests.isEmpty else { return }
    for url in urls where PublicNewsPublisherDiscovery.acceptsFeed(url, publisher: host) {
      if let index = feeds.firstIndex(where: { $0.url == url }) {
        feeds[index].interests.formUnion(interests)
      } else if feeds.count < 24 && feeds.filter({ $0.publisher == host }).count < 2 {
        feeds.append(Feed(url: url, publisher: host, interests: interests, pollAfter: now))
      }
    }
  }

  mutating func recordPoll(_ source: PublicNewsSource, success: Bool, discussion: Bool, now: Date) {
    guard source.learned, let index = feeds.firstIndex(where: { $0.url == source.url }) else { return }
    if discussion {
      feeds.remove(at: index)
    } else if success {
      feeds[index].failures = 0
      feeds[index].pollAfter = now.addingTimeInterval(60 * 60)
    } else {
      let failures = min(8, max(0, feeds[index].failures))
      feeds[index].failures = min(failures + 1, 8)
      feeds[index].pollAfter = now.addingTimeInterval(min(86_400, 900 * pow(2, Double(failures))))
    }
  }

  func probeCandidate(in articles: [PublicNewsArticle], now: Date) -> (host: String, article: PublicNewsArticle)? {
    for article in articles.prefix(120) {
      guard let host = PublicNewsPublisherDiscovery.probeHost(article.url),
            article.interests?.isEmpty == false,
            (probeAfter[host] ?? .distantPast) <= now,
            feeds.filter({ $0.publisher == host }).count < 2 else { continue }
      return (host, article)
    }
    return nil
  }
}

enum PublicNewsPublisherDiscovery {
  // Untrusted URLs from a news feed never expand this network allowlist.
  private static let permittedPublishers: Set<String> = [
    "404media.co", "9to5google.com", "aboutamazon.com", "latent.space", "seangoedecke.com", "simonwillison.net"
  ]
  private static let types: Set<String> = ["application/rss+xml", "application/atom+xml", "application/rdf+xml"]
  private static let headLimit = 128 * 1_024

  static func probeHost(_ url: URL) -> String? {
    guard url.absoluteString.utf8.count <= 2_048, url.scheme == "https", url.user == nil, url.password == nil,
          url.fragment == nil, url.port == nil || url.port == 443, let host = canonicalHost(url),
          permittedPublishers.contains(host) else { return nil }
    return host
  }

  static func acceptsFeed(_ url: URL, publisher: String) -> Bool {
    probeHost(url) == publisher && !discussionURL(url) && !PublicNewsSource.builtIn.contains { $0.url == url }
  }

  static func canonicalHost(_ url: URL) -> String? {
    guard let host = url.host?.lowercased(), host.contains(".") else { return nil }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
  }

  static func discussionTitle(_ title: String) -> Bool {
    title.range(of: "\\b(?:comments?|replies)\\b|\u{8BC4}\u{8BBA}|\u{56DE}\u{590D}",
      options: [.regularExpression, .caseInsensitive]) != nil
  }

  private static func discussionURL(_ url: URL) -> Bool {
    let segments = url.path.lowercased().split(separator: "/")
    if segments.contains(where: { ["comment", "comments", "replies"].contains($0) || $0.hasPrefix("comments.") }) {
      return true
    }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return query.contains {
      let name = $0.name.lowercased()
      let value = $0.value?.lowercased() ?? ""
      return (name == "feed" && value.hasPrefix("comments")) || (name == "withcomments" && value == "1")
    }
  }

  static func discover(html: String, origin: URL) -> [URL] {
    guard let host = probeHost(origin) else { return [] }
    // Scan only declared head metadata; comments and raw-text elements are opaque tokens.
    let head = String(decoding: html.utf8.prefix(headLimit), as: UTF8.self)
    let pattern = #"(?is)<!--.*?(?:-->|$)|<(script|style|title|textarea)\b[^>]*>.*?(?:</\1\s*>|$)|</?head\b[^>]*>|<body\b[^>]*>|<link\b(?:[^<>"']|"[^"]*"|'[^']*')*>"#
    let scanner = try! NSRegularExpression(pattern: pattern)
    var inHead = false
    var seen = Set<URL>()
    var result: [URL] = []
    for match in scanner.matches(in: head, range: NSRange(head.startIndex..<head.endIndex, in: head)) {
      guard let range = Range(match.range, in: head) else { continue }
      let token = String(head[range])
      let lower = token.lowercased()
      if lower.hasPrefix("<head") { inHead = true; continue }
      if lower.hasPrefix("</head") || lower.hasPrefix("<body") { break }
      guard inHead, lower.hasPrefix("<link") else { continue }
      let attributes = linkAttributes(token)
      let rel = (attributes["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
      let type = (attributes["type"] ?? "").lowercased().components(separatedBy: ";")[0]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard rel.contains("alternate"), types.contains(type), !discussionTitle(attributes["title"] ?? ""),
            let href = attributes["href"], let url = URL(string: href, relativeTo: origin)?.absoluteURL,
            acceptsFeed(url, publisher: host), seen.insert(url).inserted else { continue }
      result.append(url)
      if result.count == 2 { break }
    }
    return result
  }

  private static func linkAttributes(_ token: String) -> [String: String] {
    let pattern = #"([^\s=<>/"']+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s<>"'=]+))"#
    let expression = try! NSRegularExpression(pattern: pattern)
    var result: [String: String] = [:]
    for match in expression.matches(in: token, range: NSRange(token.startIndex..<token.endIndex, in: token)) {
      guard let key = Range(match.range(at: 1), in: token),
            let value = (2...4).compactMap({ Range(match.range(at: $0), in: token) }).first else { continue }
      let name = token[key].lowercased()
      if result[name] == nil {
        result[name] = String(token[value]).replacingOccurrences(of: "&amp;", with: "&")
          .trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return result
  }
}
