import Foundation

private struct AgentIOSArticleStructuredMetadata {
  var title = ""
  var author = ""
  var publishedAt = ""
  var articleBody = ""
  var images: [String] = []
  var articleLike = false
}

enum AgentIOSGenericArticleParser {
  private static let articleTypes: Set<String> = [
    "article", "newsarticle", "blogposting", "techarticle", "report",
    "scholarlyarticle", "discussionforumposting", "analysisnewsarticle"
  ]
  private static let contentHints = [
    "article-body", "article-content", "article__body", "post-content", "entry-content",
    "story-body", "story-content", "main-content", "articlebody"
  ]
  private static let noiseHints = [
    "advert", "banner", "breadcrumb", "comment", "cookie", "footer", "header", "menu",
    "nav", "newsletter", "promo", "recommend", "related", "share", "sidebar", "social"
  ]
  private static let blockTags: Set<String> = [
    "article", "blockquote", "br", "div", "figcaption", "h1", "h2", "h3", "h4",
    "h5", "h6", "li", "ol", "p", "pre", "section", "table", "td", "th", "tr", "ul"
  ]

  static func parse(url: URL, source: String) -> AgentIOSPublicArticle? {
    let structured = structuredMetadata(source)
    let cleaned = removeNoise(from: source)
    guard let root = bestContentRoot(in: cleaned) else { return nil }
    let domContent = plainText(root.html)
    let structuredContent = normalizeText(structured.articleBody)
    let content = structuredContent.count >= 40 &&
      structuredContent.count >= Int(Double(domContent.count) * 0.65)
      ? structuredContent
      : domContent
    let title = firstNonEmpty([
      structured.title,
      metaContent(property: "og:title", in: source),
      metaContent(name: "twitter:title", in: source),
      metaContent(name: "title", in: source),
      firstElementText(named: "h1", in: root.html),
      firstElementText(named: "title", in: source)
    ])
    guard content.count >= 40 || !title.isEmpty else { return nil }
    let author = firstNonEmpty([
      structured.author,
      metaContent(name: "author", in: source),
      metaContent(property: "article:author", in: source),
      metaContent(name: "byl", in: source),
      firstElementText(attribute: "itemprop", value: "author", in: source),
      firstElementText(attribute: "rel", value: "author", in: source),
      firstElementText(classHint: "byline", in: source),
      firstElementText(classHint: "author", in: source)
    ])
    let publishedAt = firstNonEmpty([
      structured.publishedAt,
      metaContent(property: "article:published_time", in: source),
      metaContent(name: "date", in: source),
      metaContent(name: "pubdate", in: source),
      firstAttribute("datetime", onElementWith: "itemprop", value: "datePublished", in: source),
      firstAttribute("datetime", onTag: "time", in: source)
    ])
    let metadataImages = structured.images + [
      metaContent(property: "og:image", in: source),
      metaContent(name: "twitter:image", in: source)
    ]
    let structuredRoot = root.tag == "article" ||
      root.attributes.lowercased().contains("articlebody") ||
      structured.articleLike
    return AgentIOSPublicArticle(
      title: String(normalizeInline(title).prefix(2_048)),
      author: String(normalizeInline(author).prefix(1_024)),
      publishedAt: String(normalizeInline(publishedAt).prefix(256)),
      content: String(normalizeText(content).prefix(240_000)),
      links: links(in: root.html, baseURL: url, limit: 100),
      images: images(in: root.html, metadata: metadataImages, baseURL: url, limit: 100),
      sourceType: structuredRoot ? "structured_web_article" : "generic_web_page"
    )
  }

  private struct ContentRoot {
    var tag: String
    var attributes: String
    var html: String
    var score: Double
  }

  private static func bestContentRoot(in source: String) -> ContentRoot? {
    let openingPattern = #"(?is)<(article|main|section|div|body)\b([^>]*)>"#
    guard let expression = try? NSRegularExpression(pattern: openingPattern) else { return nil }
    var candidates: [ContentRoot] = []
    let matches = expression.matches(in: source, range: fullRange(source))
    for match in matches.prefix(120) {
      guard let tagRange = Range(match.range(at: 1), in: source),
        let attributesRange = Range(match.range(at: 2), in: source) else { continue }
      let tag = String(source[tagRange]).lowercased()
      let attributes = String(source[attributesRange])
      let lowerAttributes = attributes.lowercased()
      let explicit = tag == "article" || tag == "main" ||
        lowerAttributes.range(of: #"\brole\s*=\s*[\"']?main\b"#, options: .regularExpression) != nil ||
        lowerAttributes.contains("articlebody") ||
        contentHints.contains(where: { lowerAttributes.contains($0) })
      if !explicit && tag != "body" && candidates.count >= 80 { continue }
      guard let html = matchingElement(from: match.range, tag: tag, source: source) else { continue }
      let text = plainText(html)
      let minimum = explicit || tag == "body" ? 40 : 120
      guard text.count >= minimum else { continue }
      let score = contentScore(
        text: text,
        html: html,
        tag: tag,
        attributes: lowerAttributes
      )
      candidates.append(ContentRoot(tag: tag, attributes: attributes, html: html, score: score))
    }
    return candidates.max { $0.score < $1.score }
  }

  private static func contentScore(
    text: String,
    html: String,
    tag: String,
    attributes: String
  ) -> Double {
    let linkTextLength = elementBodies(named: "a", in: html, limit: 250)
      .map { normalizeInline(plainText($0)).count }
      .reduce(0, +)
    let linkDensity = Double(linkTextLength) / Double(max(1, text.count))
    let paragraphCount = ["p", "li", "blockquote", "pre"]
      .flatMap { elementBodies(named: $0, in: html, limit: 500) }
      .map { plainText($0) }
      .filter { $0.count >= 30 }
      .count
    let punctuation = text.unicodeScalars.filter {
      ".,;:!?\u{3002}\u{ff0c}\u{ff1b}\u{ff1a}\u{ff01}\u{ff1f}".unicodeScalars.contains($0)
    }.count
    let semanticBonus: Double
    switch tag {
    case "article": semanticBonus = 1_200
    case "main": semanticBonus = 900
    case "section": semanticBonus = 150
    default: semanticBonus = 0
    }
    let itemPropBonus = attributes.contains("articlebody") ? 1_000.0 : 0
    let noisePenalty = Double(noiseHints.filter { attributes.contains($0) }.count) * 600
    return Double(text.count) + Double(paragraphCount * 100 + punctuation * 4) + semanticBonus +
      itemPropBonus - Double(text.count) * linkDensity * 1.8 - noisePenalty
  }

  private static func removeNoise(from source: String) -> String {
    var result = source
    let tags = [
      "script", "style", "noscript", "template", "svg", "canvas", "iframe", "nav", "footer",
      "aside", "form", "button", "select", "textarea"
    ]
    for tag in tags {
      result = result.replacingOccurrences(
        of: #"(?is)<"# + tag + #"\b[^>]*>.*?</"# + tag + #"\s*>"#,
        with: " ",
        options: .regularExpression
      )
    }
    result = result.replacingOccurrences(
      of: #"(?is)<(input|meta|link)\b[^>]*(?:>|/>)"#,
      with: " ",
      options: .regularExpression
    )
    for hint in noiseHints {
      let pattern = #"(?is)<(div|section|aside)\b[^>]*(?:id|class)\s*=\s*[\"'][^\"']*"# +
        NSRegularExpression.escapedPattern(for: hint) + #"[^\"']*[\"'][^>]*>.*?</\1\s*>"#
      result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }
    return result
  }

  private static func structuredMetadata(_ source: String) -> AgentIOSArticleStructuredMetadata {
    let scripts = captures(
      pattern: #"(?is)<script\b[^>]*type\s*=\s*[\"']application/ld\+json[^\"']*[\"'][^>]*>(.*?)</script\s*>"#,
      in: source,
      group: 1,
      limit: 30
    )
    var objects: [[String: Any]] = []
    for script in scripts {
      guard let data = script.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
        let value = try? JSONSerialization.jsonObject(with: data) else { continue }
      collectJSONObjects(value, output: &objects, depth: 0)
    }
    let ordered = objects.sorted { jsonScore($0) > jsonScore($1) }
    let contentObjects = ordered.filter { object in
      let types = jsonTypes(object)
      return !types.isDisjoint(with: articleTypes) || types.contains("webpage") ||
        object["headline"] != nil || object["articleBody"] != nil
    }
    return AgentIOSArticleStructuredMetadata(
      title: firstJSONText(contentObjects, keys: ["headline", "name"]),
      author: contentObjects.lazy.map { jsonAuthors($0["author"]) }.first(where: { !$0.isEmpty }) ?? "",
      publishedAt: firstJSONText(contentObjects, keys: ["datePublished", "dateCreated", "dateModified"]),
      articleBody: firstJSONText(contentObjects, keys: ["articleBody", "text"]),
      images: unique(contentObjects.flatMap { jsonImages($0["image"]) }).prefix(20).map { $0 },
      articleLike: ordered.contains { !jsonTypes($0).isDisjoint(with: articleTypes) }
    )
  }

  private static func collectJSONObjects(_ value: Any, output: inout [[String: Any]], depth: Int) {
    guard depth <= 8, output.count < 100 else { return }
    if let object = value as? [String: Any] {
      output.append(object)
      for nested in object.values {
        collectJSONObjects(nested, output: &output, depth: depth + 1)
      }
    } else if let array = value as? [Any] {
      for nested in array {
        collectJSONObjects(nested, output: &output, depth: depth + 1)
      }
    }
  }

  private static func jsonScore(_ object: [String: Any]) -> Int {
    let types = jsonTypes(object)
    let typeScore = !types.isDisjoint(with: articleTypes) ? 1_000 : (types.contains("webpage") ? 300 : 0)
    return typeScore + min(jsonText(object["articleBody"]).count, 500) +
      (jsonText(object["headline"]).isEmpty ? 0 : 100)
  }

  private static func jsonTypes(_ object: [String: Any]) -> Set<String> {
    Set(jsonStrings(object["@type"]).map {
      $0.split(separator: "/").last.map(String.init)?.lowercased() ?? $0.lowercased()
    })
  }

  private static func firstJSONText(_ objects: [[String: Any]], keys: [String]) -> String {
    for object in objects {
      for key in keys {
        let text = jsonText(object[key])
        if !text.isEmpty { return text }
      }
    }
    return ""
  }

  private static func jsonAuthors(_ value: Any?) -> String {
    if let array = value as? [Any] {
      return unique(array.map { jsonAuthors($0) }.filter { !$0.isEmpty }).joined(separator: ", ")
    }
    if let object = value as? [String: Any] {
      return jsonText(object["name"]).ifBlank(jsonText(object["alternateName"]))
    }
    return jsonText(value)
  }

  private static func jsonImages(_ value: Any?) -> [String] {
    if let array = value as? [Any] { return array.flatMap { jsonImages($0) } }
    if let object = value as? [String: Any] {
      return ["url", "contentUrl", "thumbnailUrl"].compactMap { key in
        let text = jsonText(object[key])
        return text.isEmpty ? nil : text
      }.prefix(1).map { $0 }
    }
    let text = jsonText(value)
    return text.isEmpty ? [] : [text]
  }

  private static func jsonStrings(_ value: Any?) -> [String] {
    if let array = value as? [Any] { return array.flatMap { jsonStrings($0) } }
    let text = jsonText(value)
    return text.isEmpty ? [] : [text]
  }

  private static func jsonText(_ value: Any?) -> String {
    switch value {
    case let text as String: return normalizeInline(text)
    case let number as NSNumber: return number.stringValue
    case let object as [String: Any]:
      return ["name", "headline", "text", "url"].lazy
        .map { jsonText(object[$0]) }
        .first(where: { !$0.isEmpty }) ?? ""
    default: return ""
    }
  }

  private static func links(in source: String, baseURL: URL, limit: Int) -> [String] {
    let tags = captures(pattern: #"(?is)<a\b[^>]*>"#, in: source, group: 0, limit: limit * 3)
    return unique(tags.compactMap { publicHTTPSURL(attribute("href", in: $0), baseURL: baseURL) })
      .prefix(limit).map { $0 }
  }

  private static func images(
    in source: String,
    metadata: [String],
    baseURL: URL,
    limit: Int
  ) -> [AgentIOSPublicArticleImage] {
    var values: [(String, String, Int?, Int?)] = metadata.compactMap { raw in
      publicHTTPSURL(raw, baseURL: baseURL).map { ($0, "", nil, nil) }
    }
    let tags = captures(pattern: #"(?is)<img\b[^>]*>"#, in: source, group: 0, limit: limit * 3)
    for tag in tags {
      let raw = firstNonEmpty([
        attribute("data-src", in: tag),
        attribute("data-original", in: tag),
        attribute("data-lazy-src", in: tag),
        attribute("src", in: tag),
        srcsetURL(attribute("srcset", in: tag))
      ])
      guard let imageURL = publicHTTPSURL(raw, baseURL: baseURL) else { continue }
      values.append((
        imageURL,
        String(normalizeInline(attribute("alt", in: tag)).prefix(500)),
        positiveDimension(firstNonEmpty([attribute("data-w", in: tag), attribute("data-width", in: tag), attribute("width", in: tag)])),
        positiveDimension(firstNonEmpty([attribute("data-h", in: tag), attribute("data-height", in: tag), attribute("height", in: tag)]))
      ))
    }
    var seen: Set<String> = []
    return values.compactMap { value in
      guard seen.insert(value.0).inserted, seen.count <= limit else { return nil }
      return AgentIOSPublicArticleImage(
        index: seen.count - 1,
        url: value.0,
        alt: value.1,
        width: value.2,
        height: value.3
      )
    }
  }

  private static func matchingElement(from openingRange: NSRange, tag: String, source: String) -> String? {
    guard let expression = try? NSRegularExpression(
      pattern: #"(?is)</?"# + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#
    ) else { return nil }
    let searchRange = NSRange(location: openingRange.location, length: source.utf16.count - openingRange.location)
    var depth = 0
    for match in expression.matches(in: source, range: searchRange) {
      guard let range = Range(match.range, in: source) else { continue }
      let token = String(source[range])
      if token.range(of: #"^\s*</"#, options: .regularExpression) != nil {
        depth -= 1
        if depth == 0,
          let full = Range(NSRange(location: openingRange.location, length: NSMaxRange(match.range) - openingRange.location), in: source) {
          return String(source[full])
        }
      } else if !token.hasSuffix("/>") {
        depth += 1
      }
    }
    return nil
  }

  private static func elementBodies(named tag: String, in source: String, limit: Int) -> [String] {
    captures(
      pattern: #"(?is)<"# + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>(.*?)</"# +
        NSRegularExpression.escapedPattern(for: tag) + #"\s*>"#,
      in: source,
      group: 1,
      limit: limit
    )
  }

  private static func firstElementText(named tag: String, in source: String) -> String {
    elementBodies(named: tag, in: source, limit: 1).first.map(plainText) ?? ""
  }

  private static func firstElementText(attribute name: String, value: String, in source: String) -> String {
    let escapedName = NSRegularExpression.escapedPattern(for: name)
    let escapedValue = NSRegularExpression.escapedPattern(for: value)
    let pattern = #"(?is)<([A-Za-z][A-Za-z0-9]*)\b[^>]*\b"# + escapedName +
      #"\s*=\s*[\"'][^\"']*"# + escapedValue + #"[^\"']*[\"'][^>]*>(.*?)</\1\s*>"#
    return captures(pattern: pattern, in: source, group: 2, limit: 1).first.map(plainText) ?? ""
  }

  private static func firstElementText(classHint: String, in source: String) -> String {
    firstElementText(attribute: "class", value: classHint, in: source)
  }

  private static func firstAttribute(
    _ requested: String,
    onElementWith name: String,
    value: String,
    in source: String
  ) -> String {
    let pattern = #"(?is)<[A-Za-z][A-Za-z0-9]*\b[^>]*\b"# +
      NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*[\"'][^\"']*"# +
      NSRegularExpression.escapedPattern(for: value) + #"[^\"']*[\"'][^>]*>"#
    guard let tag = captures(pattern: pattern, in: source, group: 0, limit: 1).first else { return "" }
    return attribute(requested, in: tag)
  }

  private static func firstAttribute(_ requested: String, onTag tag: String, in source: String) -> String {
    let pattern = #"(?is)<"# + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#
    guard let element = captures(pattern: pattern, in: source, group: 0, limit: 1).first else { return "" }
    return attribute(requested, in: element)
  }

  private static func metaContent(property: String? = nil, name: String? = nil, in source: String) -> String {
    for tag in captures(pattern: #"(?is)<meta\b[^>]*>"#, in: source, group: 0, limit: 200) {
      if let property, attribute("property", in: tag).caseInsensitiveCompare(property) != .orderedSame { continue }
      if let name, attribute("name", in: tag).caseInsensitiveCompare(name) != .orderedSame { continue }
      let value = normalizeInline(attribute("content", in: tag))
      if !value.isEmpty { return value }
    }
    return ""
  }

  private static func attribute(_ name: String, in tag: String) -> String {
    let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
      let match = expression.firstMatch(in: tag, range: fullRange(tag)) else { return "" }
    for index in 1...3 where match.range(at: index).location != NSNotFound {
      if let range = Range(match.range(at: index), in: tag) { return decodeHTMLEntities(String(tag[range])) }
    }
    return ""
  }

  private static func plainText(_ html: String) -> String {
    var value = html
    for tag in blockTags {
      value = value.replacingOccurrences(
        of: #"(?is)</?"# + NSRegularExpression.escapedPattern(for: tag) + #"\b[^>]*>"#,
        with: "\n",
        options: .regularExpression
      )
    }
    value = value.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
    return normalizeText(value)
  }

  private static func normalizeInline(_ value: String) -> String {
    decodeHTMLEntities(value)
      .replacingOccurrences(of: "\u{00a0}", with: " ")
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizeText(_ value: String) -> String {
    decodeHTMLEntities(value)
      .replacingOccurrences(of: "\u{00a0}", with: " ")
      .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
      .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func decodeHTMLEntities(_ value: String) -> String {
    var result = value
      .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
      .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
      .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
    guard let expression = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else { return result }
    for match in expression.matches(in: result, range: fullRange(result)).reversed() {
      guard let full = Range(match.range, in: result), let digits = Range(match.range(at: 1), in: result) else { continue }
      let token = String(result[digits])
      let radix = token.lowercased().hasPrefix("x") ? 16 : 10
      let number = radix == 16 ? String(token.dropFirst()) : token
      if let value = UInt32(number, radix: radix), let scalar = UnicodeScalar(value) {
        result.replaceSubrange(full, with: String(scalar))
      }
    }
    return result
  }

  private static func publicHTTPSURL(_ value: String, baseURL: URL) -> String? {
    let decoded = decodeHTMLEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !decoded.isEmpty, !decoded.lowercased().hasPrefix("data:"),
      var url = URL(string: decoded, relativeTo: baseURL)?.absoluteURL,
      let host = url.host, !host.isEmpty else { return nil }
    if url.scheme?.lowercased() == "http", host.lowercased().hasSuffix("qpic.cn") {
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.scheme = "https"
      url = components?.url ?? url
    }
    guard url.scheme?.lowercased() == "https" else { return nil }
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.fragment = nil
    return components?.url?.absoluteString
  }

  private static func positiveDimension(_ value: String) -> Int? {
    Int(value.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0 > 0 ? $0 : nil }
  }

  private static func srcsetURL(_ value: String) -> String {
    value.split(separator: ",").compactMap { item in
      item.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }.last ?? ""
  }

  private static func captures(
    pattern: String,
    in source: String,
    group: Int,
    limit: Int
  ) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    return expression.matches(in: source, range: fullRange(source)).prefix(limit).compactMap { match in
      guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: source) else { return nil }
      return String(source[range])
    }
  }

  private static func firstNonEmpty(_ values: [String]) -> String {
    values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
  }

  private static func unique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  private static func fullRange(_ value: String) -> NSRange {
    NSRange(value.startIndex..<value.endIndex, in: value)
  }
}
