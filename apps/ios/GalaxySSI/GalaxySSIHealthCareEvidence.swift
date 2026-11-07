import CryptoKit
import Foundation

enum GalaxySSIHealthCareEvidence {
  enum PublicSource: String, CaseIterable, Identifiable, Hashable {
    case labResults, glucose, pressure
    var id: String { rawValue }

    var url: URL {
      switch self {
      case .labResults: return URL(string: "https://medlineplus.gov/lab-tests/how-to-understand-your-lab-results/")!
      case .glucose: return URL(string: "https://www.niddk.nih.gov/health-information/diabetes/overview/tests-diagnosis")!
      case .pressure: return URL(string: "https://www.nhlbi.nih.gov/health/high-blood-pressure/diagnosis")!
      }
    }

    var title: String {
      switch self {
      case .labResults: return "MedlinePlus: Understanding lab results"
      case .glucose: return "NIDDK: Diabetes tests and diagnosis"
      case .pressure: return "NHLBI: High blood pressure diagnosis"
      }
    }
  }

  struct Binding: Codable, Equatable {
    let owner: String
    let thread: UUID
    let turn: UUID
    let concern: UUID
    let revision: Int
    let carePermission: UUID
    let onlinePermission: UUID
    let destination: String

    init(_ approval: GalaxySSIHealthCareDiscussion.Approval) {
      owner = approval.owner
      thread = approval.threadID
      turn = approval.id
      concern = approval.concernID
      revision = approval.concernRevision
      carePermission = approval.carePermission
      onlinePermission = approval.onlinePermission
      destination = approval.destinationDigest
    }
  }

  struct Provenance: Codable, Equatable {
    let receiptID: UUID
    let contentHash: String
    let retrievedAt: Date
    let observedAt: Date
    let quote: String
  }

  struct Receipt: Codable, Equatable, Identifiable {
    var id = UUID()
    let binding: Binding
    let url: URL
    let title: String
    let contentHash: String
    let excerpt: String
    let retrievedAt: Date
    let observedAt: Date

    var modelValue: AgentMcpJSONObject {
      let date = ISO8601DateFormatter()
      return ["evidence_id": .string(id.uuidString), "url": .string(url.absoluteString), "title": .string(title),
        "content_sha256": .string(contentHash), "excerpt": .string(excerpt),
        "retrieved_at": .string(date.string(from: retrievedAt)), "observed_at": .string(date.string(from: observedAt))]
    }

    func valid(for approval: GalaxySSIHealthCareDiscussion.Approval, now: Date) -> Bool {
      binding == Binding(approval) && approval.reviewedAt <= retrievedAt && retrievedAt <= observedAt &&
        observedAt <= now && PublicSource.allCases.contains(where: { $0.url == url }) &&
        (100...8_000).contains(excerpt.count) && !title.isBlank && title.utf8.count <= 1_024 &&
        contentHash.range(of: #"\A[a-f0-9]{64}\z"#, options: .regularExpression) != nil
    }

    func match(url claimed: URL, quote: String) -> Provenance? {
      let original = GalaxySSIHealthCareEvidence.whitespace(quote)
      guard url.absoluteString == claimed.absoluteString, (12...600).contains(original.count),
            GalaxySSIHealthCareEvidence.whitespace(excerpt).contains(original) else { return nil }
      return .init(receiptID: id, contentHash: contentHash, retrievedAt: retrievedAt, observedAt: observedAt, quote: original)
    }
  }

  static func fetch(_ source: PublicSource, binding: Binding) async throws -> Receipt {
    var request = URLRequest(url: source.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
    request.httpMethod = "GET"
    request.setValue("text/html, application/xhtml+xml", forHTTPHeaderField: "Accept")
    let data = try await GalaxySSIHealthSummaryTransport.responseBytes(request, limit: 1_000_000,
      mimeTypes: ["text/html", "application/xhtml+xml"])
    let retrieved = Date()
    return try await Task.detached(priority: .utility) {
      try fromNativeBody(data, source: source, binding: binding, retrievedAt: retrieved)
    }.value
  }

  static func fromNativeBody(_ data: Data, source: PublicSource, binding: Binding,
                             retrievedAt: Date, observedAt: Date? = nil) throws -> Receipt {
    let decoded = AgentIOSWebTextDecoder.decode(data, contentType: "text/html")
    guard decoded.lossless, let article = AgentIOSPublicArticleParser.parse(url: source.url, source: decoded.text)
    else { throw GalaxySSIHealthRecords.Failure.invalid }
    let excerpt = String(whitespace(article.content).prefix(8_000))
    guard excerpt.count >= 100 else { throw GalaxySSIHealthRecords.Failure.invalid }
    return Receipt(binding: binding, url: source.url, title: String(article.title.ifBlank(source.title).prefix(256)),
      contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
      excerpt: excerpt, retrievedAt: retrievedAt, observedAt: observedAt ?? Date())
  }

  private static func whitespace(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }
}
