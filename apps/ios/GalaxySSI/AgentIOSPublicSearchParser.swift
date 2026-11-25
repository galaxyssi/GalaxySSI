import Foundation
import SwiftSoup

enum AgentIOSPublicSearchParser {
  struct Hit: Equatable {
    var title: String
    var url: String
    var excerpt: String
    var image: AgentMcpJSONObject? = nil
  }

  static func sogouImages(_ source: String, limit: Int) throws -> [Hit] {
    guard limit > 0 else { return [] }
    let document = try SwiftSoup.parse(source)
    let assignment = "window.__INITIAL_STATE__="
    guard let script = try document.select("script").array().map({ $0.data().trimmingCharacters(in: .whitespacesAndNewlines) })
      .first(where: { $0.hasPrefix(assignment) }) else { throw AgentIOSURLSessionWebError.invalidSearchResponse }
    var json = String(script.dropFirst(assignment.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    if json.hasSuffix(";") { json.removeLast() }
    guard let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
          let search = root["searchList"] as? [String: Any], let rows = search["searchList"] as? [Any] else {
      throw AgentIOSURLSessionWebError.invalidSearchResponse
    }
    var seen = Set<String>()
    var results: [Hit] = []
    for value in rows.prefix(100) {
      guard let row = value as? [String: Any] else { continue }
      let title = try SwiftSoup.parse(row["title"] as? String ?? "").text()
      let excerpt = try SwiftSoup.parse(row["content_major"] as? String ?? "").text()
      guard !title.isEmpty, let page = imageSearchURL(row["url"], httpsOnly: false) else { continue }
      let thumbnail = imageSearchURL(row["thumbUrl"])
      let original = imageSearchURL(row["oriPicUrl"]) ?? imageSearchURL(row["picUrl"])
      guard let image = original ?? thumbnail, seen.insert(image).inserted else { continue }
      func dimension(_ key: String) -> AgentMcpJSONValue {
        let value = row[key] as? NSNumber
        return .int(Int64(max(0, min(100_000, value?.intValue ?? 0))))
      }
      var media: AgentMcpJSONObject = ["url": .string(image),
        "source_url": .string(page), "title": .string(String(title.prefix(512))),
        "width": dimension(original == nil ? "thumbWidth" : "width"),
        "height": dimension(original == nil ? "thumbHeight" : "height"),
        "retrieval_status": .string("search_result_not_downloaded")]
      if let thumbnail { media["thumbnail_url"] = .string(thumbnail) }
      if let original { media["original_url"] = .string(original) }
      results.append(Hit(title: String(title.prefix(512)), url: page,
        excerpt: String(excerpt.prefix(2_048)), image: media))
      if results.count >= min(limit, 100) { break }
    }
    return results
  }

  private static func imageSearchURL(_ raw: Any?, httpsOnly: Bool = true) -> String? {
    guard let value = raw as? String, value.utf8.count <= 4_096,
          let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          components.scheme == "https" || (!httpsOnly && components.scheme == "http"),
          components.user == nil, components.password == nil, let host = components.host?.lowercased(),
          !host.isEmpty, host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local") else { return nil }
    return components.url?.absoluteString
  }

  static func imageRows(_ data: Data, brave: Bool, limit: Int) throws -> [Hit] {
    guard limit > 0 else { return [] }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rows = root["results"] as? [Any] else { throw AgentIOSURLSessionWebError.invalidSearchResponse }
    var hits: [Hit] = [], seen = Set<String>()
    for value in rows.prefix(100) {
      guard let row = value as? [String: Any] else { continue }
      let properties = row["properties"] as? [String: Any] ?? [:]
      let thumbnail = row["thumbnail"] as? [String: Any] ?? [:]
      guard let image = imageSearchURL(brave ? properties["url"] : row["image"]),
            AgentIOSWebRenderURLPolicy.allows(image) else { continue }
      let source = (row["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard let page = imageSearchURL(source.isEmpty ? image : source, httpsOnly: false),
            seen.insert(image).inserted else { continue }
      let title = try SwiftSoup.parse(row["title"] as? String ?? "").text()
      let cleanTitle = String((title.isEmpty ? URL(string: page)?.host ?? "" : title).prefix(512))
      guard !cleanTitle.isEmpty else { continue }
      let dimensions = brave ? properties : row
      func dimension(_ key: String) -> AgentMcpJSONValue {
        .int(Int64(max(0, min(100_000, (dimensions[key] as? NSNumber)?.intValue ?? 0))))
      }
      var media: AgentMcpJSONObject = ["url": .string(image), "original_url": .string(image),
        "source_url": .string(page), "title": .string(cleanTitle), "width": dimension("width"), "height": dimension("height"),
        "retrieval_status": .string("search_result_not_downloaded")]
      if let preview = imageSearchURL(brave ? thumbnail["src"] : row["thumbnail"]),
         AgentIOSWebRenderURLPolicy.allows(preview) { media["thumbnail_url"] = .string(preview) }
      let excerpt = try SwiftSoup.parse((row["source"] as? String ?? "").ifBlank(row["provider"] as? String ?? "")).text()
      hits.append(.init(title: cleanTitle, url: page, excerpt: String(excerpt.prefix(2048)), image: media))
      if hits.count >= min(limit, 100) { break }
    }
    return hits
  }

  static func parse(_ source: String, baseURL: String, limit: Int) throws -> [Hit] {
    guard limit > 0 else { return [] }
    let document = try SwiftSoup.parse(source, baseURL)
    let base = URL(string: baseURL)
    let engine = normalizedHost(base?.host ?? "")
    let pageTitle = try document.title()
    if (engine == "wappass.baidu.com" && (base?.path.contains("/captcha/") ?? false)) ||
       (engine == "baidu.com" && pageTitle == "\u{767e}\u{5ea6}\u{5b89}\u{5168}\u{9a8c}\u{8bc1}") {
      throw AgentIOSURLSessionWebError.sourceVerificationRequired
    }
    try document.select("script, style, nav, footer, header, .b_ad, .ads, [data-text-ad]").remove()
    var anchors = try document.select("h2 a[href], h3 a[href], a[href]:has(h2), a[href]:has(h3), a.result__a[href], a.result-link[href], a.heading-serpresult[href]").array()
    if anchors.isEmpty, let body = document.body(), !body.children().isEmpty(),
       body.children().array().allSatisfy({ $0.tagName() == "a" }) {
      anchors = try body.select("a[href]").array()
    }
    var results: [Hit] = []
    var seen = Set<String>()
    for anchor in anchors {
      let title = String(try anchor.text().prefix(2_048))
      var ancestor = anchor.parent()
      var card = ancestor
      while let current = ancestor {
        if ["b_algo", "result", "results_links", "vrResult", "vrwrap", "rb", "sa-spacing-text-heading", "c-container", "snippet"].contains(where: current.hasClass) {
          card = current
          break
        }
        ancestor = current.parent()
      }
      var direct: String?
      if engine == "baidu.com", let card, card.hasClass("c-container"),
         try card.select("h3 a[href]").first() === anchor {
        let raw = try card.attr("mu")
        if raw.hasPrefix("https://") || raw.hasPrefix("http://") { direct = destination(raw, baseURL: baseURL) }
      }
      let href = try anchor.attr("href")
      guard !title.isEmpty, let url = direct ?? destination(href, baseURL: baseURL),
            let host = URL(string: url)?.host, normalizedHost(host) != engine,
            seen.insert(url).inserted else { continue }
      var snippets: [String] = []
      var seenSnippets = Set<String>()
      for element in try card?.select(".b_caption p, .result__snippet, .click-sugg-content, [class*=introduceWrap], [data-module=abstract], .c-abstract, .c-span-last, .content, .snippet-description, p").array() ?? [] {
        let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, text != title, seenSnippets.insert(text).inserted { snippets.append(text) }
      }
      results.append(Hit(title: title, url: url, excerpt: String(snippets.joined(separator: " ").prefix(1_600))))
      if results.count >= min(limit, 100) { break }
    }
    return results
  }

  static func destination(_ raw: String, baseURL: String) -> String? {
    guard raw.utf8.count <= 4_096, let base = URL(string: baseURL),
          let absolute = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: base)?.absoluteURL,
          let components = URLComponents(url: absolute, resolvingAgainstBaseURL: true),
          components.user == nil, components.password == nil else { return nil }
    let host = normalizedHost(components.host ?? "")
    let baseHost = normalizedHost(base.host ?? "")
    let sameEngine = host == baseHost ||
      (["duckduckgo.com", "html.duckduckgo.com"].contains(host) && ["duckduckgo.com", "html.duckduckgo.com"].contains(baseHost))
    var candidate = absolute.absoluteString
    if sameEngine {
      let query = components.queryItems ?? []
      if (host == "bing.com" || host.hasSuffix(".bing.com")),
         let encoded = query.first(where: { $0.name == "u" })?.value, encoded.hasPrefix("a1") {
        var value = String(encoded.dropFirst(2)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let bytes = Data(base64Encoded: value), let decoded = String(data: bytes, encoding: .utf8) else { return nil }
        candidate = decoded
      } else {
        for key in ["uddg", "url", "target", "u", "r"] {
          if let value = query.first(where: { $0.name == key })?.value,
             value.hasPrefix("https://") || value.hasPrefix("http://") { candidate = value; break }
        }
      }
    }
    guard candidate.utf8.count <= 4_096, var final = URLComponents(string: candidate),
          ["http", "https"].contains(final.scheme?.lowercased() ?? ""),
          let targetHost = final.host, !targetHost.isEmpty, final.user == nil, final.password == nil else { return nil }
    final.fragment = nil
    return final.url?.absoluteString
  }

  private static func normalizedHost(_ host: String) -> String {
    let lower = host.lowercased()
    return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
  }
}
