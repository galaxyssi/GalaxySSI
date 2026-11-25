import CryptoKit
import Foundation

struct AgentIOSLearnedWebSource: Codable, Equatable {
  var sourceID: String
  var host: String
  var vertical: String
  var categoryTags: [String]
  var status: String
  var observations: Int
  var queryFingerprints: [String]
  var firstSeenAtMillis: Int64
  var lastSeenAtMillis: Int64

  var confidence: Double {
    min(Double(observations) / 6, 1) * 0.6 + min(Double(queryFingerprints.count) / 4, 1) * 0.4
  }

  var isValid: Bool {
    AgentIOSWebSourceLearningPolicy.validHost(host) &&
      AgentIOSWebIntelligenceVertical(rawValue: vertical) != nil && vertical != "local" &&
      sourceID == AgentIOSWebSourceLearningPolicy.sourceID(host: host, vertical: vertical) &&
      ["candidate", "verified", "disabled"].contains(status) && observations >= 0 &&
      categoryTags.count <= 24 && categoryTags.allSatisfy(AgentIOSWebSourceLearningPolicy.validTag) &&
      queryFingerprints.count <= 16 && queryFingerprints.allSatisfy {
        $0.count == 24 && $0.allSatisfy { "0123456789abcdef".contains($0) }
      } && Set(queryFingerprints).count == queryFingerprints.count &&
      firstSeenAtMillis >= 0 && lastSeenAtMillis >= 0
  }

  func publicValue() -> AgentMcpJSONObject {
    ["source_id": .string(sourceID), "host": .string(host), "vertical": .string(vertical),
     "category_tags": .array(categoryTags.map { .string($0) }), "status": .string(status),
     "observations": .int(Int64(observations)), "distinct_queries": .int(Int64(queryFingerprints.count)),
     "confidence": .double(confidence), "first_seen_at_millis": .int(firstSeenAtMillis),
     "last_seen_at_millis": .int(lastSeenAtMillis),
     "verification_scope": .string("repeated_discovery_not_content_or_permission_verification")]
  }
}

enum AgentIOSWebSourceLearningPolicy {
  static let maximumSources = 512
  struct Observation {
    var sourceID: String
    var host: String
    var vertical: String
    var tags: [String]
    var queryFingerprint: String
  }
  private static let builtInHosts = Set(
    ["bing.com", "baidu.com", "duckduckgo.com", "sogou.com"] +
      AgentIOSWebIntelligenceSourceCatalog.officialDocumentationSources.flatMap(\.allowedHosts)
  )

  static func observations(query: String, categories: [String], results: [AgentMcpJSONObject]) -> [Observation] {
    let fingerprint = String(hash(String(query.prefix(4096)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).prefix(24))
    var seen = Set<String>()
    return results.prefix(20).compactMap { result in
      let raw = result.string("url")
      guard raw.utf8.count <= 4096, let url = URLComponents(string: raw),
        ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil,
        var host = url.host?.lowercased() else { return nil }
      if host.hasPrefix("www.") { host.removeFirst(4) }
      guard validHost(host), !builtInHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
      let parsedVertical = AgentIOSWebIntelligenceVertical(rawValue: result.string("vertical")) ?? .general
      let vertical = parsedVertical == .local ? "general" : parsedVertical.rawValue
      let id = sourceID(host: host, vertical: vertical)
      guard seen.insert(id).inserted else { return nil }
      let tags = Set((Array(categories.prefix(32)) + [vertical]).compactMap(AgentIOSWebResearchPlanCodec.normalizedCategory))
      return Observation(sourceID: id, host: host, vertical: vertical,
        tags: Array(tags.sorted().prefix(24)), queryFingerprint: fingerprint)
    }
  }

  static func evolve(_ previous: AgentIOSLearnedWebSource?, observation: Observation, now: Int64) -> AgentIOSLearnedWebSource {
    let queries = Array(Set((previous?.queryFingerprints ?? []) + [observation.queryFingerprint]).sorted(by: >).prefix(16))
    let count = min(previous?.observations ?? 0, Int.max - 1) + 1
    let broad = ["general", "knowledge"].contains(observation.vertical)
    let qualified = count >= (broad ? 4 : 3) && queries.count >= (broad ? 3 : 2)
    let firstSeen = previous?.firstSeenAtMillis ?? 0
    return AgentIOSLearnedWebSource(sourceID: observation.sourceID, host: observation.host, vertical: observation.vertical,
      categoryTags: Array(Set((previous?.categoryTags ?? []) + observation.tags).sorted().prefix(24)),
      status: previous?.status == "disabled" ? "disabled" : (qualified ? "verified" : "candidate"),
      observations: count, queryFingerprints: queries,
      firstSeenAtMillis: firstSeen > 0 ? firstSeen : max(0, now),
      lastSeenAtMillis: max(0, now))
  }

  static func validHost(_ host: String) -> Bool {
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    return (3...253).contains(host.utf8.count) && labels.count >= 2 &&
      !host.hasSuffix(".local") && !host.hasSuffix(".localhost") &&
      !host.replacingOccurrences(of: ".", with: "").allSatisfy(\.isNumber) && labels.allSatisfy { label in
        (1...63).contains(label.count) && label.first != "-" && label.last != "-" &&
          label.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789-".contains($0) }
      }
  }

  static func validTag(_ tag: String) -> Bool {
    AgentIOSWebResearchPlanCodec.normalizedCategory(tag) == tag
  }

  static func sourceID(host: String, vertical: String) -> String { "learned_" + String(hash(host + "|" + vertical).prefix(16)) }
  private static func hash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

// Only optional source learning enters this queue, never durable page/tool evidence.
final class AgentIOSWebMaintenanceQueue {
  static let shared = AgentIOSWebMaintenanceQueue()
  private let queue: OperationQueue
  private let admission = NSLock()

  init(queue: OperationQueue = OperationQueue()) {
    self.queue = queue
    queue.name = "galaxyssi.web-source-learning"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .utility
  }

  func submit(_ task: @escaping () -> Void) -> Bool {
    admission.lock()
    defer { admission.unlock() }
    // One worker plus at most sixteen waiting jobs, with no caller-thread fallback.
    guard queue.operationCount < 17 else { return false }
    queue.addOperation(task)
    return true
  }
}

extension Notification.Name {
  static let galaxySSIWebLearningDidChange = Notification.Name("galaxyssi.web-source-learning.changed")
}
