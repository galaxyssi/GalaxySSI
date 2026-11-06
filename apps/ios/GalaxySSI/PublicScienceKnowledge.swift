import Foundation

enum PublicScienceSource: String, CaseIterable, Identifiable {
  case biology = "biology-2e"
  case microbiology
  case anatomy = "anatomy-and-physiology-2e"
  case molecule = "pdb101"

  var id: String { rawValue }
  var publisher: String { self == .molecule ? "RCSB PDB-101" : "OpenStax" }
  var endpoint: URL {
    URL(string: self == .molecule ? "https://pdb101.rcsb.org/motm/motm-by-date" :
      "https://openstax.org/books/\(rawValue)/pages/preface")!
  }

  func acceptsArticle(_ url: URL) -> Bool {
    guard Self.safe(url), url.host == endpoint.host, url.query == nil, url.fragment == nil else { return false }
    let path = url.path
    if self == .molecule { return path.range(of: #"^/motm/[0-9]{1,6}/?$"#, options: .regularExpression) != nil }
    let prefix = "/books/\(rawValue)/pages/"
    return path.hasPrefix(prefix) && path.dropFirst(prefix.count).range(
      of: #"^[0-9]+-[0-9]+-[a-z0-9-]+$"#, options: .regularExpression
    ) != nil
  }

  func acceptsImage(_ url: URL) -> Bool {
    guard Self.safe(url), url.query == nil, url.fragment == nil else { return false }
    if self == .molecule {
      return url.host == "cdn.rcsb.org" && url.path.hasPrefix("/pdb101/motm/")
    }
    return url.host == "openstax.org" && url.path.hasPrefix("/apps/archive/") && url.path.contains("/resources/")
  }

  static func safe(_ url: URL) -> Bool {
    url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
      && !url.pathComponents.contains("..")
  }
}

struct PublicScienceEntry: Codable, Identifiable {
  let url: URL
  let title: String
  var id: URL { url }
}

struct PublicScienceDocument: Codable {
  struct Figure: Codable, Identifiable {
    let url: URL
    let caption: String
    var id: URL { url }
  }

  struct Section: Codable, Identifiable {
    let id: Int
    let heading: Bool
    let text: String
  }

  let title: String
  let sections: [Section]
  let figures: [Figure]
  let attribution: [String]
  let license: URL?
}

enum PublicScienceError: Error { case invalidSource, unavailable, tooLarge, unreadable }

enum PublicScienceTransport {
  static func fetch(_ url: URL, limit: Int) async throws -> Data {
    let resource = try await fetchResource(url, limit: limit)
    return resource.body
  }

  static func fetchResource(_ url: URL, limit: Int) async throws -> (body: Data, contentType: String) {
    guard PublicScienceSource.safe(url) else { throw PublicScienceError.invalidSource }
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.urlCache = nil
    config.timeoutIntervalForRequest = 12
    config.timeoutIntervalForResource = 20
    let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw PublicScienceError.unavailable }
    guard http.expectedContentLength <= Int64(limit) else { throw PublicScienceError.tooLarge }
    var body = Data()
    for try await byte in bytes {
      guard body.count < limit else { throw PublicScienceError.tooLarge }
      body.append(byte)
    }
    try Task.checkCancellation()
    return (body, http.value(forHTTPHeaderField: "Content-Type") ?? "")
  }

  private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
      newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
  }
}

enum PublicScienceCatalog {
  private struct Cached: Codable {
    let refreshedAt: Date
    let entries: [PublicScienceEntry]
  }

  static func cached(_ source: PublicScienceSource) -> (entries: [PublicScienceEntry], fresh: Bool)? {
    guard let url = cacheURL(source), let data = try? Data(contentsOf: url), data.count <= 1_000_000,
          let cached = try? JSONDecoder().decode(Cached.self, from: data) else { return nil }
    let entries = cached.entries.filter { source.acceptsArticle($0.url) }
    guard !entries.isEmpty else { return nil }
    let age = Date().timeIntervalSince(cached.refreshedAt)
    return (entries, age >= 0 && age < 86_400)
  }

  static func store(_ entries: [PublicScienceEntry], source: PublicScienceSource) {
    guard let url = cacheURL(source), let data = try? JSONEncoder().encode(Cached(refreshedAt: Date(), entries: entries))
    else { return }
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  private static func cacheURL(_ source: PublicScienceSource) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      .first?.appendingPathComponent("public-science-\(source.rawValue).json")
  }
}
