import Foundation

struct AgentIOSPublicArticle {
  var title: String
  var author: String
  var publishedAt: String
  var content: String
  var links: [String]
  var images: [AgentIOSPublicArticleImage]
  var sourceType: String
}

struct AgentIOSPublicArticleImage {
  var index: Int
  var url: String
  var alt: String
  var width: Int?
  var height: Int?
}

enum AgentIOSPublicArticleParser {
  private static let weChatArticleHost = "mp.weixin.qq.com"

  static func parse(url: URL, source: String) -> AgentIOSPublicArticle? {
    if url.host?.lowercased() != weChatArticleHost {
      return AgentIOSGenericArticleParser.parse(url: url, source: source)
    }
    guard let body = element(withID: "js_content", in: source)
      ?? element(withClass: "rich_media_content", in: source) else {
      return AgentIOSGenericArticleParser.parse(url: url, source: source)
    }

    let title = firstNonEmpty([
      text(in: element(withID: "activity-name", in: source)),
      text(in: element(withClass: "rich_media_title", in: source)),
      metaContent(property: "og:title", in: source),
      text(in: element(named: "title", in: source))
    ])
    let author = firstNonEmpty([
      text(in: element(withID: "js_name", in: source)),
      text(in: element(withClass: "rich_media_meta_nickname", in: source)),
      metaContent(name: "author", in: source)
    ])
    let publishedAt = firstNonEmpty([
      text(in: element(withID: "publish_time", in: source)),
      text(in: element(withClass: "rich_media_meta_text", in: source))
    ])

    return AgentIOSPublicArticle(
      title: String(title.prefix(2_048)),
      author: String(author.prefix(1_024)),
      publishedAt: String(publishedAt.prefix(256)),
      content: String(plainText(body).prefix(240_000)),
      links: urls(in: body, tag: "a", attribute: "href", baseURL: url, limit: 100),
      images: images(in: body, baseURL: url, limit: 100),
      sourceType: "wechat_public_account"
    )
  }

  static func plainText(from html: String) -> String {
    plainText(html)
  }

  private static func element(withID id: String, in source: String) -> String? {
    element(matching: #"<([A-Za-z][A-Za-z0-9]*)\b[^>]*\bid\s*=\s*[\"']"# +
      NSRegularExpression.escapedPattern(for: id) + #"[\"'][^>]*>"#, in: source)
  }

  private static func element(withClass className: String, in source: String) -> String? {
    element(matching: #"<([A-Za-z][A-Za-z0-9]*)\b[^>]*\bclass\s*=\s*[\"'][^\"']*\b"# +
      NSRegularExpression.escapedPattern(for: className) + #"\b[^\"']*[\"'][^>]*>"#, in: source)
  }

  private static func element(named name: String, in source: String) -> String? {
    element(matching: #"<("# + NSRegularExpression.escapedPattern(for: name) + #")\b[^>]*>"#, in: source)
  }

  private static func element(matching pattern: String, in source: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = expression.firstMatch(in: source, range: fullRange(source)),
          let tagRange = Range(match.range(at: 1), in: source) else {
      return nil
    }
    return matchingElement(from: match.range, tag: String(source[tagRange]), source: source)
  }

  private static func matchingElement(from openingRange: NSRange, tag: String, source: String) -> String? {
    let pattern = #"<\/?"# + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(location: openingRange.location, length: source.utf16.count - openingRange.location)
    var depth = 0
    for match in expression.matches(in: source, range: range) {
      guard let tagRange = Range(match.range, in: source) else { continue }
      let value = String(source[tagRange])
      if value.hasPrefix("</") {
        depth -= 1
        if depth == 0, let contentRange = Range(NSRange(
          location: openingRange.location,
          length: NSMaxRange(match.range) - openingRange.location
        ), in: source) {
          return String(source[contentRange])
        }
      } else if !value.hasSuffix("/>") {
        depth += 1
      }
    }
    return nil
  }

  private static func metaContent(property: String? = nil, name: String? = nil, in source: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]) else {
      return ""
    }
    for match in expression.matches(in: source, range: fullRange(source)) {
      guard let range = Range(match.range, in: source) else { continue }
      let tag = String(source[range])
      if let property = property,
         attribute("property", in: tag).caseInsensitiveCompare(property) != .orderedSame {
        continue
      }
      if let name = name,
         attribute("name", in: tag).caseInsensitiveCompare(name) != .orderedSame {
        continue
      }
      let value = decodeHTMLEntities(attribute("content", in: tag)).trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty { return value }
    }
    return ""
  }

  private static func urls(
    in source: String,
    tag: String,
    attribute: String,
    baseURL: URL,
    limit: Int
  ) -> [String] {
    urls(in: source, tag: tag, attributes: [attribute], baseURL: baseURL, limit: limit)
  }

  private static func urls(
    in source: String,
    tag: String,
    attributes: [String],
    baseURL: URL,
    limit: Int
  ) -> [String] {
    let pattern = #"<"# + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return []
    }
    var result: [String] = []
    var seen: Set<String> = []
    for match in expression.matches(in: source, range: fullRange(source)) {
      guard result.count < limit, let range = Range(match.range, in: source) else { continue }
      let tagText = String(source[range])
      guard let raw = attributes.lazy.map({ attribute($0, in: tagText) }).first(where: { !$0.isEmpty }),
            let resolved = publicHTTPSURL(raw, baseURL: baseURL),
            seen.insert(resolved).inserted else {
        continue
      }
      result.append(resolved)
    }
    return result
  }

  private static func images(in source: String, baseURL: URL, limit: Int) -> [AgentIOSPublicArticleImage] {
    let pattern = #"<img\b[^>]*>"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return []
    }
    var result: [AgentIOSPublicArticleImage] = []
    var seen: Set<String> = []
    for (index, match) in expression.matches(in: source, range: fullRange(source)).enumerated() {
      guard result.count < limit, let range = Range(match.range, in: source) else { continue }
      let tag = String(source[range])
      guard let raw = ["data-src", "data-original", "src"]
        .lazy
        .map({ attribute($0, in: tag) })
        .first(where: { !$0.isEmpty }),
        let resolved = publicHTTPSURL(raw, baseURL: baseURL),
        seen.insert(resolved).inserted else {
        continue
      }
      result.append(AgentIOSPublicArticleImage(
        index: index,
        url: resolved,
        alt: String(decodeHTMLEntities(attribute("alt", in: tag)).prefix(500)),
        width: positiveDimension(attribute("data-w", in: tag))
          ?? positiveDimension(attribute("width", in: tag)),
        height: positiveDimension(attribute("data-h", in: tag))
          ?? positiveDimension(attribute("height", in: tag))
      ))
    }
    return result
  }

  private static func publicHTTPSURL(_ value: String, baseURL: URL) -> String? {
    let decoded = decodeHTMLEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !decoded.isEmpty, !decoded.lowercased().hasPrefix("data:"),
          var url = URL(string: decoded, relativeTo: baseURL)?.absoluteURL,
          let host = url.host, !host.isEmpty else {
      return nil
    }
    if url.scheme?.lowercased() == "http", host.lowercased().hasSuffix("qpic.cn") {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.scheme = "https"
      url = components?.url ?? url
    }
    guard url.scheme?.lowercased() == "https" else { return nil }
    return url.absoluteString
  }

  private static func attribute(_ name: String, in tag: String) -> String {
    let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = expression.firstMatch(in: tag, range: fullRange(tag)) else {
      return ""
    }
    for index in 1...3 where match.range(at: index).location != NSNotFound {
      if let range = Range(match.range(at: index), in: tag) {
        return String(tag[range])
      }
    }
    return ""
  }

  private static func positiveDimension(_ value: String) -> Int? {
    Int(value.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 > 0 ? $0 : nil }
  }

  private static func text(in html: String?) -> String {
    guard let html else { return "" }
    return plainText(html)
  }

  private static func plainText(_ html: String) -> String {
    var value = html
    value = value.replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
    value = value.replacingOccurrences(of: #"(?i)</?(article|blockquote|br|div|h1|h2|h3|h4|h5|h6|li|ol|p|pre|section|table|td|th|tr|ul)\b[^>]*>"#, with: "\n", options: .regularExpression)
    value = value.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
    value = decodeHTMLEntities(value)
    value = value.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
    value = value.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
    value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func decodeHTMLEntities(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
      .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
      .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
  }

  private static func firstNonEmpty(_ values: [String]) -> String {
    values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
  }

  private static func fullRange(_ value: String) -> NSRange {
    NSRange(value.startIndex..<value.endIndex, in: value)
  }
}
