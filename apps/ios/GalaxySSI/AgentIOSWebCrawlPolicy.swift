import Foundation
import SwiftSoup

struct AgentIOSWebCrawlPolicy {
  enum Failure: Error { case invalidURL, invalidPattern }
  struct Node: Equatable { var url: String; var depth: Int }
  static let maximumLinks = 100
  let root: String
  let maxPages: Int
  let maxDepth: Int
  let timeoutMillis: Int64
  let sameOrigin: Bool
  private let include: NSRegularExpression?
  private let exclude: NSRegularExpression?
  private var queue: [Node]
  private var head = 0
  private var discovered: Set<String>
  private var resolved: Set<String> = []

  init(input: AgentMcpJSONObject) throws {
    guard let root = Self.canonical(input["url"]?.stringValue ?? "") else { throw Failure.invalidURL }
    self.root = root
    maxPages = Int(min(max(input["max_pages"]?.intValue ?? 20, 1), 100))
    maxDepth = Int(min(max(input["max_depth"]?.intValue ?? 2, 0), 5))
    timeoutMillis = min(max(input["timeout_ms"]?.intValue ?? 60_000, 1_000), 600_000)
    sameOrigin = input["same_origin"]?.boolValue ?? true
    func pattern(_ name: String) throws -> NSRegularExpression? {
      let value = input[name]?.stringValue ?? ""
      guard value.count <= 512 else { throw Failure.invalidPattern }
      if value.isEmpty { return nil }
      do { return try NSRegularExpression(pattern: value) }
      catch { throw Failure.invalidPattern }
    }
    include = try pattern("include_pattern")
    exclude = try pattern("exclude_pattern")
    queue = [Node(url: root, depth: 0)]
    discovered = [root]
  }

  var discoveredCount: Int { discovered.count }
  var remainingCount: Int { queue.count - head }
  mutating func next(shouldStop: @escaping () -> Bool = { false }) -> Node? {
    while head < queue.count {
      if shouldStop() { return nil }
      let node = queue[head]
      head += 1
      guard !resolved.contains(node.url) else { continue }
      if let include {
        guard let matched = Self.matches(include, node.url, shouldStop: shouldStop) else { restoreUnstarted(node); return nil }
        if !matched { continue }
      }
      if let exclude {
        guard let matched = Self.matches(exclude, node.url, shouldStop: shouldStop) else { restoreUnstarted(node); return nil }
        if matched { continue }
      }
      return node
    }
    return nil
  }
  mutating func restoreUnstarted(_ node: Node) {
    if head > 0 && queue[head - 1] == node { head -= 1 }
  }
  private static func matches(_ pattern: NSRegularExpression, _ value: String,
    shouldStop: @escaping () -> Bool) -> Bool? {
    var matched = false, interrupted = false
    pattern.enumerateMatches(in: value, options: .reportProgress, range: NSRange(value.startIndex..., in: value)) { match, _, stop in
      if shouldStop() { interrupted = true; stop.pointee = true }
      else if match != nil { matched = true; stop.pointee = true }
    }
    return interrupted ? nil : matched
  }
  mutating func expand(_ node: Node, finalURL: String, links: [String]) {
    if let url = Self.canonical(finalURL) { resolved.insert(url) }
    guard node.depth < maxDepth else { return }
    // At most 100 successful pages can each contribute 100 distinct links.
    for raw in links.prefix(Self.maximumLinks) {
      guard let url = Self.canonical(raw, relativeTo: finalURL),
        !sameOrigin || Self.origin(url) == Self.origin(root),
        discovered.count < 10_001, discovered.insert(url).inserted else { continue }
      queue.append(Node(url: url, depth: node.depth + 1))
    }
  }

  static func canonical(_ value: String, relativeTo base: String? = nil) -> String? {
    let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty, raw.count <= 4_096,
      !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
      let url = URL(string: raw, relativeTo: base.flatMap { URL(string: $0) })?.absoluteURL,
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
      parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(), !host.isEmpty,
      parts.user == nil, parts.password == nil, !AgentIOSPublicAddressPolicy.blocksHost(host),
      parts.port == nil || (1...65_535).contains(parts.port ?? 0) else { return nil }
    parts.scheme = "https"; parts.host = host; parts.fragment = nil
    if parts.port == 443 { parts.port = nil }
    if parts.path.isEmpty { parts.path = "/" }
    guard let result = parts.url?.absoluteString, result.count <= 4_096 else { return nil }
    return result
  }
  private static func origin(_ value: String) -> String {
    guard let parts = URLComponents(string: value) else { return "" }
    return "https://\(parts.host?.lowercased() ?? ""):\(parts.port ?? 443)"
  }
  static func links(output: AgentMcpJSONObject, baseURL: String, rawHTML: Bool) -> [String] {
    let stored = output["links"]?.arrayValue ?? output["article"]?.objectValue?["links"]?.arrayValue
    let candidates: [String]
    if let stored {
      candidates = stored.prefix(maximumLinks).compactMap(\.stringValue)
    } else if rawHTML, let document = try? SwiftSoup.parse(output["text"]?.stringValue ?? "", baseURL),
      let anchors = try? document.select("a[href]") {
      var values: [String] = []
      var seen = Set<String>()
      for anchor in anchors.array() {
        guard let href = try? anchor.attr("href"), let url = canonical(href, relativeTo: baseURL), seen.insert(url).inserted else { continue }
        values.append(url)
        if values.count == maximumLinks { break }
      }
      candidates = values
    } else { candidates = [] }
    var seen = Set<String>()
    return candidates.compactMap { raw in
      guard let value = canonical(raw, relativeTo: baseURL), seen.insert(value).inserted else { return nil }
      return value
    }
  }
}

struct AgentIOSWebCrawlDeadline {
  private let started: Int64
  private let duration: Int64
  private let now: () -> Int64
  init(durationMillis: Int64, startedAtMillis: Int64? = nil, now: @escaping () -> Int64) {
    self.now = now
    started = startedAtMillis ?? now()
    duration = min(max(durationMillis, 1_000), 600_000)
  }
  var remainingMillis: Int64 {
    let elapsed = now().subtractingReportingOverflow(started)
    guard !elapsed.overflow, elapsed.partialValue >= 0 else { return 0 }
    return max(0, duration - min(duration, elapsed.partialValue))
  }
  var expired: Bool { remainingMillis == 0 }
  func invocation(parent: AgentNativeToolInvocation, input: AgentMcpJSONObject,
    nowMillis: @escaping () -> Int64) throws -> AgentNativeToolInvocation {
    if parent.isCancellationRequested { throw AgentNativeToolInvocationError.cancelled }
    let remaining = min(remainingMillis, parent.remainingTimeMillis, 15_000)
    guard remaining > 0 else { throw AgentNativeToolInvocationError.timedOut }
    let now = nowMillis(), sum = now.addingReportingOverflow(remaining)
    let end = min(parent.deadlineEpochMillis, sum.overflow ? Int64.max : sum.partialValue)
    return AgentNativeToolInvocation(descriptor: parent.descriptor, input: input, context: parent.context,
      startedAtEpochMillis: now, deadlineEpochMillis: end, hardDeadlineEpochMillis: end, nowMillis: nowMillis,
      cancellationRequested: { parent.isCancellationRequested || self.expired }, progressReporter: { _, _ in })
  }
}
