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
  var headlineTranslation: PublicNewsHeadlineTranslation?
  var coverURL: URL?

  var id: String { url.absoluteString }
  var sortDate: Date { publishedAt ?? discoveredAt }
  var displayTitle: String {
    guard let headlineTranslation, headlineTranslation.source == title, !headlineTranslation.chinese.isEmpty else { return title }
    return headlineTranslation.chinese
  }
}

struct PublicNewsTimeline {
  enum Filter: String, CaseIterable { case all, unread, saved }

  private(set) var filter: Filter = .all
  private(set) var visibleIDs: [String] = []
  private(set) var pendingIDs: [String] = []
  private var hasContent = false

  mutating func select(_ filter: Filter, articles: [PublicNewsArticle], retainingUnread: Set<String> = []) {
    self.filter = filter
    visibleIDs = []
    hasContent = false
    reconcile(articles, retainingUnread: retainingUnread)
  }

  mutating func reconcile(_ articles: [PublicNewsArticle], retainingUnread: Set<String> = []) {
    let matching = articles.filter {
      switch filter {
      case .all: return true
      case .unread: return !$0.read || retainingUnread.contains($0.id)
      case .saved: return $0.saved
      }
    }.map(\.id)
    if !hasContent {
      visibleIDs = matching
      pendingIDs = []
      hasContent = !matching.isEmpty
      return
    }
    // Marking an open unread row read must not remove it under the reader.
    let eligible = Set(filter == .unread ? articles.map(\.id) : matching)
    visibleIDs.removeAll { !eligible.contains($0) }
    let visible = Set(visibleIDs)
    pendingIDs = matching.filter { !visible.contains($0) }
    if filter == .saved { revealArrivals() }
  }

  mutating func revealArrivals() {
    visibleIDs.insert(contentsOf: pendingIDs, at: 0)
    pendingIDs = []
  }
}

struct PublicNewsReadDwell {
  private var visibleSince: [String: TimeInterval] = [:]

  mutating func sample(_ visible: Set<String>, now: TimeInterval) -> Set<String> {
    visibleSince = visibleSince.filter { visible.contains($0.key) }
    var ready: Set<String> = []
    for id in visible {
      let firstSeen = visibleSince[id, default: now]
      if now - firstSeen >= 2 { ready.insert(id) }
      else { visibleSince[id] = firstSeen }
    }
    for id in ready { visibleSince.removeValue(forKey: id) }
    return ready
  }
}

struct PublicNewsExpansionDwell {
  private var previousOffset: CGPoint?

  mutating func reset() { previousOffset = nil }

  mutating func shouldCollapse(offset: CGPoint, moving: Bool, expandedFrame: CGRect?,
                               viewportHeight: CGFloat, anchorFrame: CGRect?) -> Bool {
    guard !moving, viewportHeight > 0, let anchorFrame,
          anchorFrame.maxY > 0, anchorFrame.minY < viewportHeight else {
      reset()
      return false
    }
    let settled = previousOffset == offset
    previousOffset = offset
    guard settled else { return false }
    // Lazy stacks may already have removed a fully offscreen row's frame.
    guard let expandedFrame else { return true }
    guard expandedFrame.height > 0 else { return false }
    return expandedFrame.maxY <= 0 || expandedFrame.minY >= viewportHeight
  }
}

struct PublicNewsPageWindow {
  static let pageSize = 40
  private(set) var range = 0..<0

  static func initialRange(count: Int, anchor: Int?) -> Range<Int> {
    let start = max(0, min((anchor ?? 0) - 12, count - pageSize))
    return start..<min(count, start + pageSize)
  }

  mutating func reset(_ ids: [String], anchor: String? = nil) {
    range = Self.initialRange(count: ids.count, anchor: anchor.flatMap { ids.firstIndex(of: $0) })
  }

  mutating func reconcile(from previous: [String], to next: [String]) {
    let positions = Dictionary(next.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    let retained = previous[clamped(to: previous.count)].compactMap { positions[$0] }
    if let first = retained.min(), let last = retained.max() {
      range = first..<min(next.count, max(last + 1, first + Self.pageSize))
    } else {
      reset(next)
    }
  }

  func clamped(to count: Int) -> Range<Int> {
    min(range.lowerBound, count)..<min(range.upperBound, count)
  }

  mutating func extend(older: Bool, count: Int) {
    if older { range = range.lowerBound..<min(count, range.upperBound + Self.pageSize) }
    else { range = max(0, range.lowerBound - Self.pageSize)..<range.upperBound }
  }
}

struct PublicNewsSource {
  let publisher: String
  let url: URL
  var interest: PublicNewsInterest? = nil
  var additionalInterests: Set<PublicNewsInterest> = []
  var learned = false

  var interests: Set<PublicNewsInterest> {
    interest.map { additionalInterests.union([$0]) } ?? additionalInterests
  }

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
  case invalidFeed, invalidResponse, bodyTooLarge, discussionFeed
}

final class PublicNewsFeedParser: NSObject, XMLParserDelegate {
  static let maximumBytes = 2_000_000
  private static let maximumArticles = 60
  private let source: PublicNewsSource
  private let now: Date
  private var depth = 0
  private var elementStack: [String] = []
  private var validRoot = false
  private var entryDepth: Int?
  private var field: String?
  private var fieldText = ""
  private var values: [String: String] = [:]
  private var entries: [PublicNewsArticle] = []
  private var seen = Set<String>()
  private var rejectedDeclaration = false
  private var headerTitleDepth: Int?
  private var headerTitle = ""

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
    if source.learned && PublicNewsPublisherDiscovery.discussionTitle(delegate.headerTitle) {
      throw PublicNewsFeedError.discussionFeed
    }
    return delegate.entries
  }

  func parser(
    _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
    qualifiedName qName: String?, attributes: [String: String]
  ) {
    depth += 1
    let name = localName(elementName)
    let parent = elementStack.last
    elementStack.append(name)
    if depth == 1 { validRoot = ["rss", "rdf", "feed"].contains(name) }
    guard validRoot, entries.count < Self.maximumArticles else { return }
    if source.learned, entryDepth == nil, name == "title",
       (depth == 2 && parent == "feed") || (depth == 3 && parent == "channel") {
      headerTitleDepth = depth
      return
    }
    if entryDepth == nil, (name == "item" || name == "entry"), (2...3).contains(depth) {
      entryDepth = depth
      values = [:]
      return
    }
    guard let entryDepth else { return }
    if depth == entryDepth + 1 || (depth == entryDepth + 2 && parent == "group"),
       (name == "thumbnail" || name == "content" || name == "enclosure"),
       let image = attributes["url"],
       name == "thumbnail" || attributes["type"]?.lowercased().hasPrefix("image/") == true ||
         attributes["medium"]?.lowercased() == "image",
       values["coverURL"] == nil {
      values["coverURL"] = image
    }
    guard depth == entryDepth + 1 else { return }
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
    defer { depth -= 1; _ = elementStack.popLast() }
    if headerTitleDepth == depth { headerTitleDepth = nil; return }
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
    if headerTitleDepth != nil, headerTitle.count < 1_000 {
      headerTitle += text.prefix(1_000 - headerTitle.count)
      return
    }
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
    let cover = values["coverURL"].flatMap { URL(string: $0, relativeTo: source.url)?.absoluteURL }
      .flatMap { PublicNewsImagePolicy.accepts($0, for: url) ? $0 : nil }
    entries.append(PublicNewsArticle(
      url: url, title: title, summary: summary, publisher: source.publisher,
      publishedAt: published, discoveredAt: now, interests: source.interests.isEmpty ? nil : source.interests,
      coverURL: cover
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
    if source.learned {
      guard PublicNewsPublisherDiscovery.acceptsFeed(source.url, publisher: source.publisher),
            AgentIOSWebRenderURLPolicy.resolvesToPublicAddress(source.url.absoluteString) else {
        throw PublicNewsFeedError.invalidResponse
      }
    }
    let (body, response) = try await fetchBytes(
      source.url, accept: "application/rss+xml, application/atom+xml, application/xml, text/xml", allowRedirects: !source.learned
    )
    let resolved = PublicNewsSource(publisher: source.publisher, url: response.url ?? source.url,
      interest: source.interest, additionalInterests: source.additionalInterests, learned: source.learned)
    return try PublicNewsFeedParser.parse(body, source: resolved, now: now)
  }

  static func probe(_ article: URL) async throws -> [URL] {
    guard PublicNewsPublisherDiscovery.probeHost(article) != nil,
          AgentIOSWebRenderURLPolicy.resolvesToPublicAddress(article.absoluteString) else {
      throw PublicNewsFeedError.invalidResponse
    }
    let (body, response) = try await fetchBytes(article, accept: "text/html, application/xhtml+xml", allowRedirects: false)
    guard ["text/html", "application/xhtml+xml"].contains(response.mimeType ?? "") else {
      throw PublicNewsFeedError.invalidResponse
    }
    return PublicNewsPublisherDiscovery.discover(html: String(decoding: body, as: UTF8.self), origin: article)
  }

  private static func fetchBytes(_ url: URL, accept: String, allowRedirects: Bool) async throws -> (Data, HTTPURLResponse) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpShouldSetCookies = false
    configuration.timeoutIntervalForRequest = 12
    configuration.timeoutIntervalForResource = 20
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration, delegate: FeedRedirectPolicy(allowed: allowRedirects), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.setValue(accept, forHTTPHeaderField: "Accept")
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
    return (body, response)
  }

  private final class FeedRedirectPolicy: NSObject, URLSessionTaskDelegate {
    let allowed: Bool
    init(allowed: Bool) { self.allowed = allowed }
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
      let url = request.url
      let valid = allowed && url?.scheme == "https" && url?.host == task.originalRequest?.url?.host
        && url?.user == nil && url?.password == nil && (url?.port == nil || url?.port == 443)
      completionHandler(valid ? request : nil)
    }
  }
}
