import CoreFoundation
import Foundation
import SwiftSoup

enum AgentIOSJSONWebSearchAdapter {
  struct Entry {
    let id: String
    let title: String
    let vertical: AgentIOSWebIntelligenceVertical
    let template: String
    let authority: Double
    var languages: Set<String> = ["*"]
    var enabledByDefault = true
    var spec: AgentIOSWebIntelligenceSourceSpec {
      .init(id: id, title: title, vertical: vertical, allowedHosts: [], authority: authority,
        languages: languages, enabledByDefault: enabledByDefault)
    }
  }

  // Android #3007's native JSON adapters, not site-index substitutes.
  static let entries: [Entry] = [
    .init(id: "marginalia", title: "Marginalia", vertical: .general,
      template: "https://api2.marginalia-search.com/search?query={query}&count={limit}&dc=3", authority: 0.7),
    .init(id: "wikipedia", title: "Wikipedia", vertical: .knowledge,
      template: "https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", authority: 0.9),
    .init(id: "wikipedia_zh", title: "Wikipedia Chinese", vertical: .knowledge,
      template: "https://zh.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit={limit}&srsearch={query}", authority: 0.9, languages: ["zh"]),
    .init(id: "github", title: "GitHub", vertical: .code,
      template: "https://api.github.com/search/repositories?q={query}&per_page={limit}", authority: 0.85),
    .init(id: "github_code", title: "GitHub Code Search", vertical: .code,
      template: "https://api.github.com/search/code?q={query}&per_page={limit}", authority: 0.9),
    .init(id: "gitlab", title: "GitLab", vertical: .code,
      template: "https://gitlab.com/api/v4/projects?search={query}&per_page={limit}", authority: 0.8),
    .init(id: "stackoverflow", title: "Stack Overflow", vertical: .qa,
      template: "https://api.stackexchange.com/2.3/search/advanced?site=stackoverflow&pagesize={limit}&q={query}", authority: 0.85),
    .init(id: "hacker_news", title: "Hacker News", vertical: .community,
      template: "https://hn.algolia.com/api/v1/search?hitsPerPage={limit}&query={query}", authority: 0.7),
    .init(id: "lobsters", title: "Lobsters", vertical: .community,
      template: "https://lobste.rs/search.json?q={query}", authority: 0.7),
    .init(id: "reddit", title: "Reddit", vertical: .community,
      template: "https://www.reddit.com/search.json?q={query}&limit={limit}&raw_json=1", authority: 0.65),
    .init(id: "crossref", title: "Crossref", vertical: .researchIndex,
      template: "https://api.crossref.org/works?rows={limit}&query={query}", authority: 0.9),
    .init(id: "semantic_scholar", title: "Semantic Scholar", vertical: .academic,
      template: "https://api.semanticscholar.org/graph/v1/paper/search?limit={limit}&fields=title,url,abstract,year,authors&query={query}", authority: 0.9),
    .init(id: "pubmed", title: "PubMed", vertical: .medical,
      template: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmode=json&retmax={limit}&term={query}", authority: 0.95),
    .init(id: "crates_io", title: "crates.io", vertical: .packages,
      template: "https://crates.io/api/v1/crates?q={query}&per_page={limit}", authority: 0.8),
    .init(id: "npm", title: "npm", vertical: .packages,
      template: "https://registry.npmjs.org/-/v1/search?size={limit}&text={query}", authority: 0.8),
    .init(id: "mdn", title: "MDN", vertical: .docs,
      template: "https://developer.mozilla.org/api/v1/search?q={query}&page_size={limit}", authority: 0.95)
  ]

  static func entry(_ id: String) -> Entry? { entries.first { $0.id == id } }

  static func requestURL(_ entry: Entry, query: String, limit: Int) throws -> URL {
    try requestURL(template: entry.template, query: query, limit: limit)
  }

  static func requestURL(template: String, query: String, limit: Int) throws -> URL {
    guard var parts = URLComponents(string: template.replacingOccurrences(of: "+", with: "%20")
      .replacingOccurrences(of: "{query}", with: "GALAXYSSI_QUERY")
      .replacingOccurrences(of: "{limit}", with: "GALAXYSSI_LIMIT")), parts.scheme == "https", parts.host != nil,
      parts.user == nil, parts.password == nil else { throw AgentIOSURLSessionWebError.invalidURL }
    parts.queryItems = parts.queryItems?.map {
      URLQueryItem(name: $0.name, value: $0.value?.replacingOccurrences(of: "GALAXYSSI_LIMIT", with: String(min(max(limit, 1), 100)))
        .replacingOccurrences(of: "GALAXYSSI_QUERY", with: query))
    }
    parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    guard let url = parts.url else { throw AgentIOSURLSessionWebError.invalidURL }
    return url
  }

  static func parse(_ data: Data, source: String, limit: Int) throws -> [AgentIOSPublicSearchParser.Hit] {
    guard limit > 0 else { return [] }
    guard Int64(data.count) <= AgentIOSWebMediaNativeToolCatalog.maxFetchBytes,
          entry(source) != nil else { throw AgentIOSURLSessionWebError.invalidSearchResponse }
    let value = try JSONSerialization.jsonObject(with: data)
    let root = value as? [String: Any] ?? [:]
    func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
    func text(_ value: Any?) -> String { value as? String ?? "" }
    func first(_ values: String...) -> String { values.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "" }
    let rawRows: Any?
    switch source {
    case "wikipedia", "wikipedia_zh": rawRows = object(root["query"])["search"]
    case "github", "github_code", "stackoverflow": rawRows = root["items"]
    case "gitlab", "lobsters": rawRows = value
    case "hacker_news": rawRows = root["hits"]
    case "reddit": rawRows = object(root["data"])["children"]
    case "crossref": rawRows = object(root["message"])["items"]
    case "semantic_scholar": rawRows = root["data"]
    case "pubmed": rawRows = object(root["esearchresult"])["idlist"]
    case "crates_io": rawRows = root["crates"]
    case "npm": rawRows = root["objects"]
    case "mdn": rawRows = root["documents"]
    case "marginalia": rawRows = root["results"]
    default: throw AgentIOSURLSessionWebError.invalidSearchResponse
    }
    guard let rows = rawRows as? [Any] else { throw AgentIOSURLSessionWebError.invalidSearchResponse }
    var hits: [AgentIOSPublicSearchParser.Hit] = [], seen = Set<String>()
    for value in rows.prefix(100) {
      var row = object(value)
      var title = "", url = "", excerpt = ""
      switch source {
      case "wikipedia", "wikipedia_zh":
        guard let number = row["pageid"] as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
          number.doubleValue > 0, number.doubleValue.rounded(.towardZero) == number.doubleValue,
          number.doubleValue < Double(Int64.max) else { continue }
        let language = source == "wikipedia_zh" ? "zh" : "en"
        title = text(row["title"]); excerpt = text(row["snippet"])
        url = "https://\(language).wikipedia.org/?curid=\(number.int64Value)"
      case "github":
        title = text(row["full_name"]); url = text(row["html_url"]); excerpt = text(row["description"])
      case "github_code":
        let repo = object(row["repository"]), file = first(text(row["path"]), text(row["name"]))
        title = [text(repo["full_name"]), file].filter { !$0.isEmpty }.joined(separator: " \u{00b7} ")
        url = text(row["html_url"]); excerpt = first(text(repo["description"]), file)
      case "gitlab":
        title = text(row["path_with_namespace"]); url = text(row["web_url"]); excerpt = text(row["description"])
      case "stackoverflow":
        title = text(row["title"]); url = text(row["link"]); excerpt = text(row["excerpt"])
      case "hacker_news":
        title = first(text(row["title"]), text(row["story_title"]))
        let id = text(row["objectID"])
        url = first(text(row["url"]), text(row["story_url"]),
          numericID(id) ? "https://news.ycombinator.com/item?id=\(id)" : "")
        excerpt = first(text(row["story_text"]), text(row["comment_text"]))
      case "lobsters", "marginalia":
        title = text(row["title"]); url = text(row["url"]); excerpt = text(row["description"])
      case "reddit":
        row = object(row["data"])
        title = text(row["title"]); excerpt = text(row["selftext"])
        let path = text(row["permalink"])
        url = first(text(row["url_overridden_by_dest"]),
          path.hasPrefix("/") && !path.hasPrefix("//") ? "https://www.reddit.com" + path : "")
      case "crossref":
        title = (row["title"] as? [String])?.first ?? ""; url = text(row["URL"]); excerpt = text(row["abstract"])
      case "semantic_scholar":
        title = text(row["title"]); url = text(row["url"]); excerpt = text(row["abstract"])
      case "pubmed":
        let id = text(value)
        guard numericID(id) else { continue }
        title = "PubMed record \(id)"; url = "https://pubmed.ncbi.nlm.nih.gov/\(id)/"
      case "crates_io":
        title = first(text(row["name"]), text(row["id"])); excerpt = text(row["description"])
        url = first(text(row["repository"]), pathURL(base: "https://crates.io/crates/", segment: title))
      case "npm":
        row = object(row["package"])
        let links = object(row["links"])
        title = text(row["name"]); excerpt = text(row["description"])
        url = first(text(links["npm"]), text(links["repository"]))
      case "mdn":
        title = text(row["title"]); excerpt = text(row["summary"])
        let raw = first(text(row["mdn_url"]), text(row["url"]))
        url = raw.hasPrefix("/") && !raw.hasPrefix("//") ? "https://developer.mozilla.org" + raw : raw
      default: continue
      }
      guard url.utf8.count <= 4096, var parts = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
        ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.user == nil, parts.password == nil,
        let host = parts.host?.lowercased(), AgentIOSWebSourceLearningPolicy.validHost(host) else { continue }
      parts.fragment = nil
      guard let cleanURL = parts.url?.absoluteString else { continue }
      let cleanTitle = String(try SwiftSoup.parse(String(title.prefix(8192))).text().prefix(2048))
      guard !cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, seen.insert(cleanURL).inserted else { continue }
      hits.append(.init(title: cleanTitle, url: cleanURL,
        excerpt: String(try SwiftSoup.parse(String(excerpt.prefix(16384))).text().prefix(2048))))
      if hits.count >= min(limit, 100) { break }
    }
    return hits
  }

  private static func numericID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 32 && value.allSatisfy { "0123456789".contains($0) }
  }

  private static func pathURL(base: String, segment: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#%")
    return base + (segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
  }
}

struct AgentIOSJSONWebSearchRequestPolicy {
  var source: String
  var githubToken: String = ""

  func headers(for url: URL) -> [String: String] {
    guard let entry = AgentIOSJSONWebSearchAdapter.entry(source),
      let expected = URLComponents(string: entry.template.replacingOccurrences(of: "{query}", with: "query")
        .replacingOccurrences(of: "{limit}", with: "1")),
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "https",
      parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
      parts.host?.lowercased() == expected.host?.lowercased(), parts.percentEncodedPath == expected.percentEncodedPath else { return [:] }
    var headers = ["Accept": "application/json"]
    if source == "marginalia" { headers["API-Key"] = "public" }
    if source == "github" || source == "github_code" {
      headers["Accept"] = "application/vnd.github+json"
      headers["X-GitHub-Api-Version"] = "2022-11-28"
      let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
      if !token.isEmpty, token.utf8.count <= 8192,
        token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) {
        headers["Authorization"] = "Bearer " + token
      }
    }
    return headers
  }
}
