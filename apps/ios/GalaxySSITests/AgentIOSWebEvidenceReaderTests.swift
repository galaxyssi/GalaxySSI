import XCTest
@testable import GalaxySSI

final class AgentIOSWebEvidenceReaderTests: XCTestCase {
  private final class ConcurrencyProbe {
    private let lock = NSLock()
    private var active = 0
    private var activeByHost: [String: Int] = [:]
    private(set) var maxActive = 0
    private(set) var maxPerHost = 0

    func begin(host: String) {
      lock.lock()
      active += 1
      activeByHost[host, default: 0] += 1
      maxActive = max(maxActive, active)
      maxPerHost = max(maxPerHost, activeByHost[host, default: 0])
      lock.unlock()
    }

    func end(host: String) {
      lock.lock()
      active = max(0, active - 1)
      activeByHost[host] = max(0, activeByHost[host, default: 0] - 1)
      lock.unlock()
    }
  }

  func testResearchSchemasExposeParallelPageReadControls() throws {
    let definitions = AgentIOSWebIntelligenceNativeToolCatalog.definitions(
      provider: AgentIOSUnavailableWebIntelligenceToolProvider()
    )
    let research = try XCTUnwrap(
      definitions.first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.research }
    )
    let nativeProperties = try XCTUnwrap(research.descriptor.inputSchema["properties"]?.objectValue)
    let expected = Set([
      "profile", "engines", "verticals", "categories", "use_cache",
      "page_read_parallelism", "per_host_parallelism", "page_read_timeout_ms", "early_complete"
    ])
    XCTAssertTrue(expected.isSubset(of: Set(nativeProperties.keys)))

    let cloudResearch = try XCTUnwrap(CloudWebGrounding.openAITools().first {
      $0["function"]?.objectValue?["name"] == .string("web_research")
    })
    let cloudProperties = try XCTUnwrap(
      cloudResearch["function"]?.objectValue?["parameters"]?.objectValue?["properties"]?.objectValue
    )
    XCTAssertTrue(expected.isSubset(of: Set(cloudProperties.keys)))
  }

  func testReadsEvidenceConcurrentlyWithHostLimitAndFailureIsolation() throws {
    let urls = [
      "https://same.example.test/evidence-a",
      "https://same.example.test/evidence-b",
      "https://fail.example.test/evidence",
      "https://one.example.test/evidence",
      "https://two.example.test/evidence",
      "https://three.example.test/evidence",
      "https://four.example.test/evidence"
    ]
    let probe = ConcurrencyProbe()
    let batch = try AgentIOSWebEvidenceReader().read(
      results: urls.map { ["url": .string($0)] },
      evidenceLimit: 6,
      parallelism: 6,
      perHostParallelism: 1,
      timeoutMillis: 5_000,
      earlyComplete: true
    ) { url, _, cancelled in
      let host = URL(string: url)?.host ?? ""
      if host == "fail.example.test" {
        throw AgentIOSWebEvidenceFetchError(
          code: "source_failed",
          message: "Source failed",
          retryable: true
        )
      }
      probe.begin(host: host)
      defer { probe.end(host: host) }
      let slow = host == "four.example.test"
      for _ in 0..<(slow ? 60 : 8) {
        if cancelled() { throw AgentNativeToolInvocationError.cancelled }
        Thread.sleep(forTimeInterval: 0.005)
      }
      return fetched(url: url, content: String(repeating: "evidence ", count: 100))
    }

    XCTAssertGreaterThanOrEqual(probe.maxActive, 3)
    XCTAssertLessThanOrEqual(probe.maxPerHost, 1)
    XCTAssertGreaterThanOrEqual(batch.documents.count, 4)
    XCTAssertTrue(batch.sufficient)
    XCTAssertTrue(batch.earlyCompleted)
    XCTAssertEqual(batch.completionReason, "sufficient_diverse_evidence")
    XCTAssertGreaterThanOrEqual(batch.domainCount, 3)
    XCTAssertTrue(batch.receipts.contains { $0["error_code"] == .string("source_failed") })
    XCTAssertTrue(batch.receipts.contains { $0["status"] == .string("cancelled") })
  }

  func testUsesOneSharedDeadlineForPendingPages() throws {
    let results = (1...6).map {
      ["url": AgentMcpJSONValue.string("https://deadline-\($0).example.test/evidence")]
    }
    let started = ProcessInfo.processInfo.systemUptime
    let batch = try AgentIOSWebEvidenceReader().read(
      results: results,
      evidenceLimit: 6,
      parallelism: 2,
      perHostParallelism: 1,
      timeoutMillis: 150,
      earlyComplete: false
    ) { url, _, cancelled in
      for _ in 0..<200 {
        if cancelled() { throw AgentNativeToolInvocationError.cancelled }
        Thread.sleep(forTimeInterval: 0.01)
      }
      return fetched(url: url, content: String(repeating: "late ", count: 150))
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - started

    XCTAssertEqual(batch.completionReason, "shared_deadline")
    XCTAssertEqual(batch.candidateCount, 6)
    XCTAssertTrue(batch.documents.isEmpty)
    XCTAssertLessThan(elapsed, 1)
    XCTAssertTrue(batch.receipts.allSatisfy { $0["error_code"] == .string("shared_deadline") })
  }

  func testPreservesSearchRankWhenPagesFinishOutOfOrder() throws {
    let results = (1...4).map {
      ["url": AgentMcpJSONValue.string("https://rank-\($0).example.test/evidence")]
    }
    let batch = try AgentIOSWebEvidenceReader().read(
      results: results,
      evidenceLimit: 4,
      parallelism: 4,
      perHostParallelism: 1,
      timeoutMillis: 2_000,
      earlyComplete: false
    ) { url, _, _ in
      let rank = Int(url.split(separator: "-").last?.split(separator: ".").first ?? "1") ?? 1
      Thread.sleep(forTimeInterval: Double(5 - rank) * 0.02)
      return fetched(url: url, content: String(repeating: "ranked evidence ", count: 100))
    }

    XCTAssertEqual(
      batch.documents.compactMap { $0["url"]?.stringValue },
      results.compactMap { $0["url"]?.stringValue }
    )
    XCTAssertEqual(batch.completionReason, "evidence_limit_reached")
  }

  func testCompletionPolicyRequiresSubstantialDomainDiverseEvidence() {
    let documents = (1...4).map { index in
      [
        "url": AgentMcpJSONValue.string("https://source-\(index).example/evidence"),
        "content": AgentMcpJSONValue.string(String(repeating: "x", count: 700))
      ]
    }

    XCTAssertTrue(
      AgentIOSWebEvidenceCompletionPolicy.hasSufficientEvidence(
        documents: documents,
        evidenceLimit: 8
      )
    )
    XCTAssertFalse(
      AgentIOSWebEvidenceCompletionPolicy.hasSufficientEvidence(
        documents: Array(documents.prefix(3)),
        evidenceLimit: 8
      )
    )
  }

  private func fetched(url: String, content: String) -> AgentIOSWebEvidenceFetchedDocument {
    AgentIOSWebEvidenceFetchedDocument(
      document: [
        "url": .string(url),
        "content": .string(content),
        "content_sha256": .string(String(repeating: "a", count: 64))
      ],
      receipt: ["network_policy": .string("public_https_urlsession_revalidated_v1")]
    )
  }
}
