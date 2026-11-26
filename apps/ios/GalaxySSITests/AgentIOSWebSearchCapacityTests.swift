import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebSearchCapacityTests: XCTestCase {
  func testIntelligenceRegistryReturnsAndCachesOneHundredTextResults() throws {
    let fixture = try SearchCapacityFixture()
    defer { fixture.close() }
    let input: AgentMcpJSONObject = ["query": .string("alpha"), "engines": .array([.string("github")]), "limit": .int(100)]
    let first = try fixture.call(input)
    XCTAssertTrue(first.isSuccess, first.error?.message ?? "")
    XCTAssertEqual(first.output["results"]?.arrayValue?.count, 100)
    XCTAssertEqual(first.output["evidence"]?.arrayValue?.count, 100)
    XCTAssertEqual(first.output["source_receipts"]?.arrayValue?.count, 100)
    XCTAssertEqual(first.output["result_count"], .int(100))
    let request = try XCTUnwrap(fixture.transport.requests.first)
    XCTAssertEqual(queryItem("per_page", request.url), "100")
    let second = try fixture.call(input)
    XCTAssertEqual(second.output["results"], first.output["results"])
    XCTAssertEqual(second.output["source_receipts"], first.output["source_receipts"])
    XCTAssertEqual(second.metadata["cache_hit"], .bool(true))
    XCTAssertEqual(second.metadata["network_attempted"], .bool(false))
    XCTAssertEqual(fixture.transport.requests.count, 1)
    XCTAssertEqual(fixture.media.searchScope, .webMedia, "Native scope is selected only on the per-invocation copy")
  }

  func testDefaultTenAndLongQueryReachTheNativeAdapter() throws {
    let fixture = try SearchCapacityFixture()
    defer { fixture.close() }
    let query = String(repeating: "alpha ", count: 600)
    let result = try fixture.call(["query": .string(query), "engines": .array([.string("github")]), "use_cache": .bool(false)])
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["result_count"], .int(10))
    let request = try XCTUnwrap(fixture.transport.requests.first)
    XCTAssertEqual(queryItem("per_page", request.url), "10")
    XCTAssertGreaterThan(queryItem("q", request.url)?.count ?? 0, 1_024)
    XCTAssertLessThanOrEqual(queryItem("q", request.url)?.count ?? Int.max, 4_096)
  }

  func testImageAndMixedRequestsAreNotCutAtTwenty() throws {
    let pure = try SearchCapacityFixture()
    defer { pure.close() }
    let images = try pure.call(["query": .string("alpha"), "engines": .array([.string("brave_image")]), "limit": .int(60)])
    XCTAssertTrue(images.isSuccess, images.error?.message ?? "")
    XCTAssertEqual(images.output["results"]?.arrayValue?.count, 60)
    XCTAssertEqual(queryItem("count", try XCTUnwrap(pure.transport.requests.first).url), "60")
    for row in (images.output["results"]?.arrayValue ?? []).compactMap(\.objectValue) {
      XCTAssertNotNil(row["lead_image_url"])
      XCTAssertEqual(row["images"]?.arrayValue?.first?.objectValue?["retrieval_status"], .string("search_result_not_downloaded"))
    }
    let mixed = try SearchCapacityFixture(textRows: 70, imageRows: 30)
    defer { mixed.close() }
    let result = try mixed.call(["query": .string("alpha"), "engines": .array([.string("github"), .string("brave_image")]), "limit": .int(100)])
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    let rows = (result.output["results"]?.arrayValue ?? []).compactMap(\.objectValue)
    XCTAssertEqual(rows.count, 100)
    XCTAssertEqual(rows.filter { $0["lead_image_url"] != nil }.count, 30)
    XCTAssertEqual(rows.filter { $0["lead_image_url"] == nil }.count, 70)
    for request in mixed.transport.requests where request.url.host == "api.github.com" {
      XCTAssertNil(request.headers["X-Subscription-Token"])
    }
  }

  func testRawWebMediaCannotSelectCapacityFromJSON() throws {
    let fixture = try SearchCapacityFixture()
    defer { fixture.close() }
    let descriptor = try XCTUnwrap(AgentIOSWebMediaNativeToolCatalog.definitions(provider: fixture.media)
      .first { $0.descriptor.id == AgentIOSWebMediaNativeToolCatalog.webSearch }?.descriptor)
    XCTAssertEqual(descriptor.inputSchema["properties"]?.objectValue?["max_results"]?.objectValue?["maximum"], .int(24))
    let input: AgentMcpJSONObject = ["query": .string("alpha"), "engines": .array([.string("github")]),
      "max_results": .int(100), "search_scope": .string("intelligence")]
    let invocation = AgentNativeToolInvocation(descriptor: descriptor, input: input, context: fixture.context,
      startedAtEpochMillis: 1_000, deadlineEpochMillis: 31_000, hardDeadlineEpochMillis: 31_000, nowMillis: { 1_000 },
      cancellationRequested: { false }, progressReporter: { _, _ in })
    let result = fixture.media.invoke(operation: .webSearch, input: input, invocation: invocation)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["results"]?.arrayValue?.count, 24)
    XCTAssertEqual(queryItem("per_page", try XCTUnwrap(fixture.transport.requests.first).url), "24")
  }

  func testFindSimilarCanFillBeyondTwentyFourWithScopedRemoteSearch() throws {
    let fixture = try SearchCapacityFixture()
    defer { fixture.close() }
    let spy = CapacityWebMediaSpy()
    let result = try fixture.call(["query": .string("alpha"), "limit": .int(80)], operation: .findSimilar, media: spy)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["results"]?.arrayValue?.count, 80)
    XCTAssertEqual(spy.input["max_results"], .int(80))
    XCTAssertEqual(spy.input["engine_fanout"], .int(12))
    XCTAssertEqual(result.metadata["network_attempted"], .bool(true))
  }

  func testExactCacheAllowsLargeHundredRowsButRejectsOverBounds() throws {
    let fixture = try SearchCapacityFixture()
    defer { fixture.close() }
    let key = String(repeating: "a", count: 64)
    let rows = (0..<100).map { AgentMcpJSONValue.object(["url": .string("https://source.test/\($0)"), "title": .string("alpha")]) }
    let response = AgentNativeToolExecutionResult.success(output: ["results": .array(rows),
      "padding": .string(String(repeating: "x", count: 300_000))])
    XCTAssertTrue(fixture.cache.putSearchResponse(key: key, result: response, ttlMillis: 60_000))
    XCTAssertEqual(fixture.cache.searchResponse(key: key)?.output, response.output)
    var tooMany = response
    tooMany.output["results"] = .array(rows + [rows[0]])
    XCTAssertFalse(fixture.cache.putSearchResponse(key: key, result: tooMany, ttlMillis: 60_000))
    var tooLarge = response
    tooLarge.output["padding"] = .string(String(repeating: "x", count: AgentIOSWebSearchCapacity.maximumCachedResponseBytes + 1))
    XCTAssertFalse(fixture.cache.putSearchResponse(key: key, result: tooLarge, ttlMillis: 60_000))
    XCTAssertEqual(fixture.cache.searchResponse(key: key)?.output, response.output)
  }

  func testResearchEvidenceSchemaRemainsTwentyFour() throws {
    let definitions = AgentIOSWebIntelligenceNativeToolCatalog.definitions()
    for id in [AgentIOSWebIntelligenceNativeToolCatalog.research, AgentIOSWebIntelligenceNativeToolCatalog.agent] {
      let definition = try XCTUnwrap(definitions.first { $0.descriptor.id == id })
      XCTAssertEqual(definition.descriptor.inputSchema["properties"]?.objectValue?["evidence_limit"]?.objectValue?["maximum"], .int(24))
    }
    XCTAssertEqual(AgentIOSWebSearchCapacity.Scope.webMedia.imageCandidates(100), 20)
    XCTAssertEqual(AgentIOSWebSearchCapacity.Scope.intelligence.imageCandidates(1_000), 100)
    XCTAssertEqual(AgentIOSWebSearchCapacity.Scope.intelligence.imageCandidates(-1), 1)
  }

  private func queryItem(_ name: String, _ url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
  }
}

private final class SearchCapacityFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("capacity-search-\(UUID()).json")
  let operations = OperationQueue()
  let transport: CapacitySearchTransport
  let cache: AgentIOSWebIntelligenceCacheStore
  let media: AgentIOSURLSessionWebMediaToolProvider
  let context = AgentNativeToolInvocationContext(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission,
    AgentIOSWebIntelligenceNativeToolCatalog.cachePermission], grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent,
    AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])
  init(textRows: Int = 100, imageRows: Int = 100) throws {
    transport = CapacitySearchTransport(textRows: textRows, imageRows: imageRows)
    let credentials = InMemorySecretStore()
    try credentials.setString("brave-capacity-fixture", account: AgentIOSWebIntelligenceCredentialKey.braveAPIKey.account)
    cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 },
      learningQueue: .init(queue: operations))
    media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil,
      imageCredentials: .init(secrets: credentials), nowMillis: { 1_000 })
  }
  func call(_ input: AgentMcpJSONObject, operation: AgentIOSWebIntelligenceOperation = .search,
    media supplied: AgentIOSWebMediaToolProviding? = nil) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: supplied ?? media, cacheStore: cache, nowMillis: { 1_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.toolId(operation), input: input, context: context,
      hooks: .init(nowMillis: { 1_000 }))
  }
  func close() {
    operations.waitUntilAllOperationsAreFinished()
    removeWebCacheFixture(file)
  }
}

private final class CapacitySearchTransport: AgentIOSURLSessionWebTransporting {
  private let lock = NSLock()
  private var saved: [AgentIOSURLSessionWebRequest] = []
  private let textRows: Int
  private let imageRows: Int
  var requests: [AgentIOSURLSessionWebRequest] { lock.lock(); defer { lock.unlock() }; return saved }
  init(textRows: Int, imageRows: Int) { self.textRows = textRows; self.imageRows = imageRows }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock(); saved.append(request); lock.unlock()
    let value: [String: Any]
    if request.url.host == "api.search.brave.com" {
      value = ["results": (0..<imageRows).map { ["title": "alpha image \($0)", "url": "https://source.test/page-\($0)",
        "properties": ["url": "https://media.test/alpha-\($0).jpg", "width": 640, "height": 480]] as [String: Any] }]
    } else {
      value = ["items": (0..<textRows).map { ["full_name": "alpha repository \($0)",
        "html_url": "https://github.com/fixture/alpha-\($0)", "description": String(repeating: "alpha reference content ", count: 5)] }]
    }
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "application/json"],
      body: try JSONSerialization.data(withJSONObject: value), retrievedAtEpochMillis: 1_000)
  }
}

private final class CapacityWebMediaSpy: AgentIOSWebMediaToolProviding {
  let implementationId = "capacity-spy"
  var input: AgentMcpJSONObject = [:]
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    self.input = input
    let rows = (0..<100).map { AgentMcpJSONValue.object(["title": .string("alpha reference"),
      "url": .string("https://source.test/\($0)"), "snippet": .string("alpha reference content")]) }
    return .success(output: ["results": .array(rows)], metadata: ["provider": .string(implementationId)])
  }
}
