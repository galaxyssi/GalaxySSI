import Foundation

struct AgentLocalResearchDisclosure: Codable, Equatable, Sendable {
  struct Source: Codable, Equatable, Identifiable, Sendable {
    var id: String { url.absoluteString }
    let url: URL
    var title: String
  }

  private(set) var queries: [String] = []
  private(set) var sources: [Source] = []
  private(set) var truncated = false
  var visible: Bool { !queries.isEmpty || !sources.isEmpty }

  static func observed(tool: String, output: AgentMcpJSONObject) -> Self {
    let nativeMedia: AgentIOSWebIntelligenceOperation?
    switch tool {
    case AgentIOSWebMediaNativeToolCatalog.webSearch: nativeMedia = .search
    case AgentIOSWebMediaNativeToolCatalog.webOpen, AgentIOSWebMediaNativeToolCatalog.webFetch: nativeMedia = .fetch
    default: nativeMedia = nil
    }
    guard let operation = CloudWebGrounding.operation(forToolName: tool) ?? nativeMedia,
          [.search, .fetch, .crawl, .research, .agent, .diff].contains(operation) else { return Self() }
    let body = output["result"]?.objectValue ?? output
    let pack = body["evidence_pack"]?.objectValue ??
      (body.string("protocol") == AgentIOSWebEvidencePack.protocolId ? body : [:])
    let research = body["research"]?.objectValue ?? pack["research_context"]?.objectValue ?? [:]
    var receipt = Self()
    if let discovered = research["discovered_source_count"]?.intValue,
       discovered > Int64(body["results"]?.arrayValue?.count ?? 0) { receipt.truncated = true }
    let queries: [AgentMcpJSONValue]
    switch operation {
    case .search:
      queries = [body["query"] ?? pack["query"] ?? .null]
    case .research, .agent:
      queries = research["executed_queries"]?.arrayValue ?? []
    default:
      queries = []
    }
    for query in queries { receipt.addQuery(query.stringValue ?? "") }
    for value in [body["results"], body["documents"], body["pages"]].compactMap({ $0 }) {
      let rows = value.arrayValue ?? []
      if rows.count > 512 { receipt.truncated = true }
      for row in rows.prefix(512) {
        guard let object = row.objectValue, let url = sourceURL(object.string("url")) else { continue }
        receipt.addSource(Source(url: url, title: text(object.string("title"), limit: 512)))
      }
    }
    let canonicalRawURLs = Set(receipt.sources.map { AgentIOSWebEvidencePack.canonicalURL($0.id) })
    for value in pack["items"]?.arrayValue?.prefix(512) ?? [] {
      guard let item = value.objectValue, let url = sourceURL(item.string("url")),
            !canonicalRawURLs.contains(url.absoluteString) else { continue }
      receipt.addSource(Source(url: url, title: text(item.string("title"), limit: 512)))
    }
    if receipt.sources.isEmpty, operation == .fetch,
       body["status"] == .string("completed"), let url = sourceURL(body.string("url")) {
      receipt.addSource(Source(url: url, title: text(body.string("title"), limit: 512)))
    }
    return receipt
  }

  static func restored(_ messages: [AgentModelMessage]) -> Self {
    messages.reduce(into: Self()) { receipt, message in
      guard let result = message.toolResult else { return }
      if let native = result.nativeResult, !native.isSuccess { return }
      receipt.merge(observed(tool: result.toolId, output: result.nativeResult?.output ?? result.output))
    }
  }

  mutating func merge(_ other: Self) {
    truncated = truncated || other.truncated
    for query in other.queries { addQuery(query) }
    for source in other.sources { addSource(source) }
  }

  mutating func trimForStorage() -> Bool {
    truncated = true
    if !sources.isEmpty { sources.removeLast(max(1, sources.count / 8)); return true }
    if !queries.isEmpty { queries.removeLast(max(1, queries.count / 8)); return true }
    return false
  }

  private mutating func addQuery(_ value: String) {
    let query = Self.text(value, limit: 1_024)
    guard !query.isEmpty, !queries.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) else { return }
    if queries.count < 128 { queries.append(query) } else { truncated = true }
  }

  private mutating func addSource(_ source: Source) {
    if let index = sources.firstIndex(where: { $0.url == source.url }) {
      if sources[index].title.isEmpty { sources[index].title = source.title }
    } else if sources.count < 512 {
      sources.append(source)
    } else { truncated = true }
  }

  private static func text(_ value: String, limit: Int) -> String {
    String(value.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
  }

  private static func sourceURL(_ value: String) -> URL? {
    guard value.utf8.count <= 4_096,
          var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = parts.host?.lowercased(), !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
    parts.scheme = scheme
    parts.host = host
    parts.fragment = nil
    if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) { parts.port = nil }
    if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
    return parts.url
  }
}

final class AgentLocalResearchCollector: Equatable, @unchecked Sendable {
  private let lock = NSLock()
  private var receipt = AgentLocalResearchDisclosure()

  static func == (lhs: AgentLocalResearchCollector, rhs: AgentLocalResearchCollector) -> Bool { lhs === rhs }

  func record(tool: String, output: AgentMcpJSONObject) {
    let delta = AgentLocalResearchDisclosure.observed(tool: tool, output: output)
    guard delta.visible else { return }
    lock.lock()
    defer { lock.unlock() }
    receipt.merge(delta)
  }

  func drain() -> AgentLocalResearchDisclosure {
    lock.lock()
    defer { lock.unlock() }
    let pending = receipt
    receipt = .init()
    return pending
  }
}

@MainActor
extension AgentResearchCheckpointStore {
  private static let maximumLocalDisclosureBytes = 196_608

  func localDisclosure(conversation: String, turn: String, source: UUID) -> AgentLocalResearchDisclosure {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults,
      key: localDisclosureKey(conversation, turn, source), secrets: secrets),
      data.count <= Self.maximumLocalDisclosureBytes else { return .init() }
    return (try? JSONDecoder().decode(AgentLocalResearchDisclosure.self, from: data)) ?? .init()
  }

  func mergeLocalDisclosure(_ receipt: AgentLocalResearchDisclosure, conversation: String, turn: String, source: UUID) -> Bool {
    guard receipt.visible else { return false }
    let previous = localDisclosure(conversation: conversation, turn: turn, source: source)
    var next = previous
    next.merge(receipt)
    guard next != previous else { return false }
    while let data = try? JSONEncoder().encode(next) {
      if data.count <= Self.maximumLocalDisclosureBytes {
        return GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults,
          key: localDisclosureKey(conversation, turn, source), secrets: secrets)
      }
      guard next.trimForStorage() else { return false }
    }
    return false
  }

  func removeLocalDisclosure(conversation: String, turn: String, source: UUID) {
    GalaxySSIEncryptedUserDefaultsStore.destroy(defaults: defaults, key: localDisclosureKey(conversation, turn, source), secrets: secrets)
  }

  private func localDisclosureKey(_ conversation: String, _ turn: String, _ source: UUID) -> String {
    key(conversation, turn, source) + ".local-disclosure"
  }
}
