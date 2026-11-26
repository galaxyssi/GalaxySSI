import Foundation

enum AgentIOSIndexedWebSourceCatalog {
  enum Failure: Error { case invalidCatalog }
  private struct Envelope: Decodable {
    let version: Int
    let sources: [Record]
  }
  private struct Record: Decodable {
    let id: String
    let title: String
    let vertical: String
    let host: String
    let scope: String
    let languages: [String]
    let authority: Double
  }

  static let sources: [AgentIOSWebIntelligenceSourceSpec] = {
    guard let url = Bundle.main.url(forResource: "web-indexed-sources", withExtension: "json"),
          let data = try? Data(contentsOf: url), let records = try? decode(data) else { return [] }
    return records
  }()

  static func decode(_ data: Data) throws -> [AgentIOSWebIntelligenceSourceSpec] {
    guard data.count <= 131_072 else { throw Failure.invalidCatalog }
    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
    guard envelope.version == 1, (1...512).contains(envelope.sources.count) else { throw Failure.invalidCatalog }
    var ids = Set<String>()
    return try envelope.sources.enumerated().map { index, record in
      guard (1...80).contains(record.id.utf8.count),
            record.id.allSatisfy({ "abcdefghijklmnopqrstuvwxyz0123456789_".contains($0) }),
            ids.insert(record.id).inserted, (1...160).contains(record.title.utf8.count),
            let vertical = AgentIOSWebIntelligenceVertical(rawValue: record.vertical), vertical != .local,
            AgentIOSWebSourceLearningPolicy.validHost(record.host),
            record.authority.isFinite, (0.0...1.0).contains(record.authority),
            !record.languages.isEmpty, record.languages.count <= 8,
            Set(record.languages).isSubset(of: ["*", "zh", "en", "ja", "ko"]),
            record.scope.utf8.count <= 1_024,
            let scope = URLComponents(string: "https://" + record.scope), scope.scheme == "https",
            scope.host == record.host, scope.user == nil, scope.password == nil,
            scope.port == nil, scope.query == nil, scope.fragment == nil,
            scope.path.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else { throw Failure.invalidCatalog }
      return AgentIOSWebIntelligenceSourceSpec(id: record.id, title: record.title, vertical: vertical,
        allowedHosts: [record.host], authority: record.authority, categoryTags: [record.vertical],
        indexEngine: index % 2 == 0 ? "duckduckgo" : "bing", scope: record.scope,
        languages: Set(record.languages))
    }
  }

  static func allowsResult(_ value: String, scope: String?) -> Bool {
    guard let scope else { return true }
    guard let expected = URLComponents(string: "https://" + scope),
          let result = URLComponents(string: value), let host = result.host?.lowercased(),
          let allowedHost = expected.host?.lowercased(),
          result.user == nil, result.password == nil, ["https", "http"].contains(result.scheme?.lowercased() ?? ""),
          host == allowedHost || host.hasSuffix("." + allowedHost),
          result.path.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else { return false }
    let path = expected.path.hasSuffix("/") ? String(expected.path.dropLast()) : expected.path
    return path.isEmpty || result.path == path || result.path.hasPrefix(path + "/")
  }
}
