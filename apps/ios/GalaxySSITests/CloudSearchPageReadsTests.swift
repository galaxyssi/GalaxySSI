import Foundation
import XCTest
@testable import GalaxySSI

final class CloudSearchPageReadsTests: XCTestCase {
  private final class Provider: AgentIOSWebIntelligenceToolProviding {
    let implementationId = "fixture.page-reads", engineCatalogSize = 1, rankerId = "fixture"
    let handler: (AgentIOSWebIntelligenceOperation, AgentNativeToolInvocation) -> AgentNativeToolExecutionResult
    private let lock = NSLock()
    private var calls: [AgentNativeToolInvocation] = []
    init(_ handler: @escaping (AgentIOSWebIntelligenceOperation, AgentNativeToolInvocation) -> AgentNativeToolExecutionResult) { self.handler = handler }
    func availability(operation: AgentIOSWebIntelligenceOperation) -> AgentNativeToolAvailability { .available }
    func invoke(operation: AgentIOSWebIntelligenceOperation, input: AgentMcpJSONObject,
                invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
      lock.lock(); calls.append(invocation); lock.unlock()
      return handler(operation, invocation)
    }
    var observed: [AgentNativeToolInvocation] { lock.lock(); defer { lock.unlock() }; return calls }
  }
  private var context: AgentNativeToolInvocationContext {
    .init(invocationId: "lookup", sessionId: "session", conversationId: "conversation", turnId: "turn",
      idempotencyKey: "owner", grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent], attributes: ["private_scope": "keep"])
  }
  private func search(_ urls: [String]) -> AgentMcpJSONObject {
    ["status": .string("completed"), "operation": .string("search"),
     "evidence_pack": .object(AgentIOSWebEvidencePack.build(query: "Fixture", status: "completed", documents: [],
       results: urls.map { ["url": .string($0), "title": .string("Lead"), "snippet": .string("Discovery only")] },
       receipts: [], generatedAtMillis: 1))]
  }
  private static func body(_ invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    .success(output: ["url": invocation.input["url"] ?? .string(""), "text": .string("Retrieved fixture body.")])
  }

  func testRankedURLsAreUniqueHTTPSAndCappedWithoutCredentialCoercion() {
    let output: AgentMcpJSONObject = ["evidence_pack": .object(["items": .array([
      "http://source.test/insecure", "https://user:secret@source.test/private", "https://source.test/z",
      "https://source.test/z?utm_source=duplicate", "https://source.test/a", "https://source.test/b",
      "https://source.test/c", "https://source.test/d"].map { .object(["url": .string($0)]) })])]
    XCTAssertEqual(CloudSearchPageReads.urls(in: output, limit: 100),
      ["https://source.test/z", "https://source.test/a", "https://source.test/b", "https://source.test/c"])
  }

  func testTwoPageBodiesStartTogetherButResultsRetainRankOrder() {
    let entered = DispatchGroup(); entered.enter(); entered.enter()
    let provider = Provider { _, invocation in
      entered.leave()
      guard entered.wait(timeout: .now() + 2) == .success else {
        return .failure(code: "serial_fetch", message: "Sibling did not start concurrently")
      }
      return Self.body(invocation)
    }
    let urls = ["https://source.test/z", "https://source.test/a"]
    let attempts = CloudSearchPageReads.read(urls, provider: provider, context: context)
    XCTAssertEqual(attempts.map(\.url), urls)
    XCTAssertTrue(attempts.allSatisfy { $0.result?.isSuccess == true })
  }

  func testChildRegistriesKeepOwnerGrantsAndOneSharedParentDeadline() throws {
    let provider = Provider { _, invocation in Self.body(invocation) }
    var parent = context; parent.deadlineEpochMillis = 2_500
    let attempts = CloudSearchPageReads.read(["https://source.test/a", "https://source.test/b"],
      provider: provider, context: parent, nowMillis: { 1_000 })
    XCTAssertEqual(attempts.count, 2)
    XCTAssertEqual(Set(provider.observed.map { $0.context.invocationId }).count, 2)
    for invocation in provider.observed {
      XCTAssertEqual(invocation.context.deadlineEpochMillis, 2_500)
      XCTAssertEqual(invocation.context.grantedPermissions, parent.grantedPermissions)
      XCTAssertEqual(invocation.context.grantedConsents, parent.grantedConsents)
      XCTAssertEqual(invocation.context.conversationId, parent.conversationId)
      XCTAssertEqual(invocation.context.turnId, parent.turnId)
      XCTAssertEqual(invocation.context.attributes, parent.attributes)
      let timeout = try XCTUnwrap(invocation.input["timeout_ms"]?.intValue)
      XCTAssertTrue((1_000...1_500).contains(timeout))
    }
  }

  func testDeniedPermissionsNeverReachThePageProvider() {
    let provider = Provider { _, invocation in Self.body(invocation) }
    let attempts = CloudSearchPageReads.read(["https://source.test/a"], provider: provider,
      context: AgentNativeToolInvocationContext())
    XCTAssertTrue(provider.observed.isEmpty)
    XCTAssertFalse(attempts.first?.result?.isSuccess ?? true)
  }

  func testExpiredParentAndAlreadyCancelledReadsDoNotStartWorkers() {
    let provider = Provider { _, invocation in Self.body(invocation) }
    var parent = context; parent.deadlineEpochMillis = 999
    let expired = CloudSearchPageReads.read(["https://source.test/a"], provider: provider, context: parent, nowMillis: { 1_000 })
    XCTAssertEqual(expired.first?.stopped, "page_read_deadline")
    parent.deadlineEpochMillis = 1_999
    let tooShort = CloudSearchPageReads.read(["https://source.test/a"], provider: provider, context: parent, nowMillis: { 1_000 })
    XCTAssertEqual(tooShort.first?.stopped, "page_read_insufficient_budget")
    let cancelled = CloudSearchPageReads.read(["https://source.test/a"], provider: provider, context: context, cancelled: { true })
    XCTAssertEqual(cancelled.first?.stopped, "page_read_cancelled")
    XCTAssertTrue(provider.observed.isEmpty)
  }

  func testFailedSiblingKeepsDiscoveryAndSuccessfulBodyWithTruthfulStats() throws {
    let urls = ["https://source.test/fails", "https://source.test/body"]
    let provider = Provider { _, invocation in
      invocation.input["url"] == .string(urls[0])
        ? .failure(code: "fixture_source_failed", message: "Fixture") : Self.body(invocation)
    }
    let attempts = CloudSearchPageReads.read(urls, provider: provider, context: context)
    let output = CloudSearchPageReads.attach(to: search(urls), attempts: attempts)
    let pack = try XCTUnwrap(output["evidence_pack"]?.objectValue)
    XCTAssertEqual(output["status"], .string("partial"))
    XCTAssertEqual(pack["page_read_status"], .string("partial"))
    let items = try XCTUnwrap(pack["items"]?.arrayValue)
    XCTAssertEqual(items.compactMap { $0.objectValue?["url"]?.stringValue }, urls)
    XCTAssertEqual(items[0].objectValue?["evidence_level"], .string("discovery_snippet"))
    XCTAssertEqual(items[1].objectValue?["evidence_level"], .string("retrieved_body"))
    XCTAssertEqual(items[1].objectValue?["rank"], .int(2))
    XCTAssertEqual(pack["stats"]?.objectValue?["document_count"], .int(1))
    XCTAssertEqual(pack["stats"]?.objectValue?["discovery_count"], .int(1))
    XCTAssertEqual(pack["verification"], .object(AgentIOSWebEvidenceVerification.verify(pack)))
    XCTAssertEqual(pack["page_reads"]?.arrayValue?.first?.objectValue?["error_code"], .string("fixture_source_failed"))
  }

  func testCancellationSealsTheSnapshotAndLateWorkerCannotPublishBody() {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
    let provider = Provider { _, invocation in
      entered.signal()
      _ = release.wait(timeout: .now() + 3)
      defer { finished.signal() }
      return Self.body(invocation)
    }
    let attempts = CloudSearchPageReads.read(["https://source.test/late"], provider: provider, context: context,
      cancelled: { entered.wait(timeout: .now()) == .success })
    XCTAssertEqual(attempts.first?.stopped, "page_read_cancelled")
    XCTAssertNil(attempts.first?.result)
    release.signal()
    XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
    XCTAssertNil(attempts.first?.result)
  }

  func testActualSearchOptInReadsPagesAndKeepsScopeThroughRegistry() throws {
    let urls = ["https://source.test/z", "https://source.test/a"]
    let provider = Provider { operation, invocation in
      if operation == .search { return .success(output: ["results": .array(urls.map { .object(["url": .string($0), "snippet": .string("Lead")]) })]) }
      return Self.body(invocation)
    }
    let encoded = CloudWebGrounding.executeTool(provider: provider, name: "web_search",
      arguments: ["query": .string("Fixture"), "read_pages": .bool(true)], context: context)
    let output = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(encoded.utf8))
    XCTAssertEqual(output["evidence_pack"]?.objectValue?["page_reads"]?.arrayValue?.count, 2)
    XCTAssertEqual(provider.observed.filter { $0.input["url"] != nil }.count, 2)
    for invocation in provider.observed { XCTAssertEqual(invocation.context.turnId, context.turnId) }
  }

  func testCancellationAfterWorkersCompleteDiscardsBodiesBeforePublication() throws {
    var cancelled = false
    let urls = ["https://source.test/a"]
    let provider = Provider { _, invocation in Self.body(invocation) }
    let attempts = CloudSearchPageReads.read(urls, provider: provider, context: context,
      cancelled: { cancelled }, schedule: { $0() }, beforePublication: { cancelled = true })
    XCTAssertEqual(provider.observed.count, 1)
    XCTAssertNil(attempts.first?.result)
    XCTAssertEqual(attempts.first?.stopped, "page_read_cancelled")
    let output = CloudSearchPageReads.attach(to: search(urls), attempts: attempts)
    let pack = try XCTUnwrap(output["evidence_pack"]?.objectValue)
    XCTAssertEqual(pack["items"]?.arrayValue?.first?.objectValue?["evidence_level"], .string("discovery_snippet"))
    XCTAssertEqual(pack["stats"]?.objectValue?["document_count"], .int(0))
  }

  func testQueuedWorkerCannotReuseTheAdmissionTimeout() {
    var clock: Int64 = 1_000
    var parent = context; parent.deadlineEpochMillis = 2_000
    let provider = Provider { _, invocation in Self.body(invocation) }
    let attempts = CloudSearchPageReads.read(["https://source.test/a"], provider: provider,
      context: parent, nowMillis: { clock }, schedule: { work in clock = 1_001; work() })
    XCTAssertTrue(provider.observed.isEmpty)
    XCTAssertEqual(attempts.first?.stopped, "page_read_insufficient_budget")
  }

  func testChildIdentifiersUseTheFullParentAndURLWithoutTruncationCollisions() throws {
    let provider = Provider { _, invocation in Self.body(invocation) }
    for suffix in ["first", "second"] {
      var parent = context
      parent.invocationId = String(repeating: "i", count: 100) + suffix
      parent.idempotencyKey = String(repeating: "k", count: 100) + suffix
      _ = CloudSearchPageReads.read(["https://source.test/a"], provider: provider,
        context: parent, schedule: { $0() })
    }
    var parent = context
    parent.invocationId = String(repeating: "i", count: 100) + "first"
    parent.idempotencyKey = String(repeating: "k", count: 100) + "first"
    _ = CloudSearchPageReads.read(["https://source.test/b"], provider: provider,
      context: parent, schedule: { $0() })
    let calls = provider.observed
    XCTAssertEqual(calls.count, 3)
    XCTAssertEqual(Set(calls.map { $0.context.invocationId }).count, 3)
    XCTAssertEqual(Set(calls.compactMap { $0.context.idempotencyKey }).count, 3)
    for call in calls {
      XCTAssertLessThanOrEqual(call.context.invocationId.utf8.count, 128)
      XCTAssertLessThanOrEqual(try XCTUnwrap(call.context.idempotencyKey).utf8.count, 128)
      XCTAssertEqual(call.context.turnId, context.turnId)
    }
  }

  func testBodyCompletingAfterWallDeadlineCannotPublish() {
    var clock: Int64 = 1_000
    var parent = context; parent.deadlineEpochMillis = 3_000
    let provider = Provider { _, invocation in clock = 3_001; return Self.body(invocation) }
    let attempts = CloudSearchPageReads.read(["https://source.test/a"], provider: provider,
      context: parent, nowMillis: { clock }, schedule: { $0() })
    XCTAssertEqual(provider.observed.count, 1)
    XCTAssertNil(attempts.first?.result)
    XCTAssertEqual(attempts.first?.stopped, "page_read_deadline")
  }

  func testNoOptInDoesNotIntroduceHiddenPageFetches() {
    let provider = Provider { _, _ in .success(output: ["results": .array([.object(["url": .string("https://source.test/a"), "snippet": .string("Lead")])])]) }
    _ = CloudWebGrounding.executeTool(provider: provider, name: "web_search", arguments: ["query": .string("Fixture")], context: context)
    XCTAssertEqual(provider.observed.count, 1)
  }

  func testCompactedOutputRetainsBoundedFailuresWithoutInventingCitationURLs() throws {
    var output = CloudSearchPageReads.attach(to: search(["https://source.test/a"]), attempts: [
      .init(url: "https://source.test/a", result: nil, stopped: "page_read_deadline")])
    var pack = try XCTUnwrap(output["evidence_pack"]?.objectValue)
    pack["fixture_padding"] = .string(String(repeating: "x", count: 30_000)); output["evidence_pack"] = .object(pack)
    let encoded = CloudWebGrounding.boundedModelJson(output)
    XCTAssertLessThanOrEqual(encoded.count, 24_000)
    let compact = try JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(encoded.utf8))
    let receipt = try XCTUnwrap(compact["evidence_pack"]?.objectValue?["page_reads"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(receipt["error_code"], .string("page_read_deadline"))
    XCTAssertEqual(receipt["scope"], .string("diagnostic_not_citation_evidence"))
    XCTAssertNil(receipt["url"])
  }

  func testNoEligiblePagesLeavesSearchOutputUnchanged() {
    let output = search(["http://source.test/a"])
    XCTAssertTrue(CloudSearchPageReads.urls(in: output, limit: 3).isEmpty)
    XCTAssertEqual(CloudSearchPageReads.attach(to: output, attempts: []), output)
  }
}
