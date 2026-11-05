import Foundation

struct PublicNewsArticle: Codable, Equatable, Identifiable {
  var url: URL
  var title: String
  var summary: String
  var publisher: String
  var publishedAt: Date?
  var discoveredAt: Date
  var read = false
  var saved = false
  var interests: Set<PublicNewsInterest>?

  var id: String { url.absoluteString }
  var sortDate: Date { publishedAt ?? discoveredAt }
}

struct PublicNewsSource {
  let publisher: String
  let url: URL
  var interest: PublicNewsInterest? = nil

  static let builtIn: [PublicNewsSource] = [
    ("IT Home", "https://www.ithome.com/rss/", PublicNewsInterest.technology),
    ("GitHub", "https://github.blog/feed/", .technology),
    ("China News", "https://www.chinanews.com.cn/rss/finance.xml", .finance),
    ("Federal Reserve", "https://www.federalreserve.gov/feeds/press_all.xml", .finance),
    ("MIT News", "https://news.mit.edu/rss/research", .research),
    ("PLOS Biology", "https://journals.plos.org/plosbiology/feed/atom", .research)
  ].compactMap { name, address, interest in
    URL(string: address).map { Self(publisher: name, url: $0, interest: interest) }
  }
}

enum PublicNewsFeedError: Error {
  case invalidFeed, invalidResponse, bodyTooLarge
}

final class PublicNewsFeedParser: NSObject, XMLParserDelegate {
  static let maximumBytes = 2_000_000
  private static let maximumArticles = 60
  private let source: PublicNewsSource
  private let now: Date
  private var depth = 0
  private var validRoot = false
  private var entryDepth: Int?
  private var field: String?
  private var fieldText = ""
  private var values: [String: String] = [:]
  private var entries: [PublicNewsArticle] = []
  private var seen = Set<String>()
  private var rejectedDeclaration = false

  private init(source: PublicNewsSource, now: Date) {
    self.source = source
    self.now = now
  }

  static func parse(_ data: Data, source: PublicNewsSource, now: Date) throws -> [PublicNewsArticle] {
    guard data.count <= maximumBytes else { throw PublicNewsFeedError.bodyTooLarge }
    let delegate = PublicNewsFeedParser(source: source, now: now)
    let parser = XMLParser(data: data)
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), delegate.validRoot, !delegate.rejectedDeclaration else {
      throw PublicNewsFeedError.invalidFeed
    }
    return delegate.entries
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes: [String: String]
  ) {
    depth += 1
    let name = localName(elementName)
    if depth == 1 { validRoot = ["rss", "rdf", "feed"].contains(name) }
    guard validRoot, entries.count < Self.maximumArticles else { return }
    if entryDepth == nil, (name == "item" || name == "entry"), (2...3).contains(depth) {
      entryDepth = depth
      values = [:]
      return
    }
    guard let entryDepth, depth == entryDepth + 1 else { return }
    if name == "link", let href = attributes["href"] {
      if (attributes["rel"] ?? "alternate").lowercased() == "alternate",
         publicArticleURL(href) != nil, values["link"] == nil { values["link"] = href }
      return
    }
    if ["title", "link", "description", "summary", "content", "encoded", "pubdate", "published", "date"].contains(name) {
      field = name
      fieldText = ""
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) { appendField(string) }

  func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
    if let text = String(data: CDATABlock, encoding: .utf8) { appendField(text) }
  }

  func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
    rejectDeclaration(parser)
  }

  func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
    rejectDeclaration(parser)
  }

  func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
    defer { depth -= 1 }
    guard let entryDepth else { return }
    if depth == entryDepth + 1, let field {
      if values[field] == nil { values[field] = fieldText }
      self.field = nil
      fieldText = ""
    }
    if depth == entryDepth {
      finishEntry()
      self.entryDepth = nil
      values = [:]
    }
  }

  private func rejectDeclaration(_ parser: XMLParser) {
    rejectedDeclaration = true
    parser.abortParsing()
  }

  private func appendField(_ text: String) {
    guard field != nil, fieldText.count < 12_000 else { return }
    fieldText += text.prefix(12_000 - fieldText.count)
  }

  private func finishEntry() {
    let title = Self.plainText(values["title"] ?? "", limit: 500)
    guard !title.isEmpty, let url = publicArticleURL(values["link"] ?? ""),
          seen.insert(url.absoluteString).inserted else { return }
    let summary = ["summary", "description", "content", "encoded"]
      .compactMap { values[$0] }.lazy.map { Self.plainText($0, limit: 4_000) }.first { !$0.isEmpty } ?? ""
    let published = ["published", "pubdate", "date"].compactMap { values[$0] }
      .lazy.compactMap { Self.date($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.first
    entries.append(PublicNewsArticle(
      url: url, title: title, summary: summary, publisher: source.publisher,
      publishedAt: published, discoveredAt: now, interests: source.interest.map { Set([$0]) }
    ))
  }

  private func publicArticleURL(_ text: String) -> URL? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= 2_048,
          let url = URL(string: value, relativeTo: source.url)?.absoluteURL,
          var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
          let host = parts.host, host.contains("."),
          parts.user == nil, parts.password == nil else { return nil }
    parts.fragment = nil
    return parts.url
  }

  private func localName(_ name: String) -> String {
    name.split(separator: ":").last.map { $0.lowercased() } ?? name.lowercased()
  }

  static func plainText(_ text: String, limit: Int) -> String {
    let plain = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
    return String(plain.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
  }

  private static func date(_ text: String) -> Date? {
    let iso = ISO8601DateFormatter()
    if let parsed = iso.date(from: text) { return parsed }
    iso.formatOptions.insert(.withFractionalSeconds)
    if let parsed = iso.date(from: text) { return parsed }
    let rfc = DateFormatter()
    rfc.locale = Locale(identifier: "en_US_POSIX")
    for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss zzz"] {
      rfc.dateFormat = format
      if let parsed = rfc.date(from: text) { return parsed }
    }
    return nil
  }
}

enum PublicNewsFeedClient {
  static func fetch(_ source: PublicNewsSource, now: Date) async throws -> [PublicNewsArticle] {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 12
    configuration.timeoutIntervalForResource = 20
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration, delegate: FeedRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: source.url)
    request.setValue("application/rss+xml, application/atom+xml, application/xml, text/xml", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
      throw PublicNewsFeedError.invalidResponse
    }
    let limit = PublicNewsFeedParser.maximumBytes
    guard response.expectedContentLength <= Int64(limit) else { throw PublicNewsFeedError.bodyTooLarge }
    var body = Data()
    for try await byte in bytes {
      guard body.count < limit else { throw PublicNewsFeedError.bodyTooLarge }
      body.append(byte)
    }
    try Task.checkCancellation()
    return try PublicNewsFeedParser.parse(body, source: source, now: now)
  }

  private final class FeedRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
      let url = request.url
      let allowed = url?.scheme == "https" && url?.host == task.originalRequest?.url?.host
        && url?.user == nil && url?.password == nil && (url?.port == nil || url?.port == 443)
      completionHandler(allowed ? request : nil)
    }
  }
}
