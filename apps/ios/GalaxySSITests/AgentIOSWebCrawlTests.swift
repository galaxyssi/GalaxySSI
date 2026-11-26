import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebCrawlTests: XCTestCase {
  func testDefaultLimitsAndDepthBoundedBreadthFirstQueue() throws {
    var policy = try AgentIOSWebCrawlPolicy(input: ["url": .string("https://site.test/root")])
    XCTAssertEqual(policy.maxPages, 20)
    XCTAssertEqual(policy.maxDepth, 2)
    XCTAssertEqual(policy.timeoutMillis, 60_000)
    let root = try XCTUnwrap(policy.next())
    policy.expand(root, finalURL: root.url, links: ["/one", "/two", "/one#fragment", "/root"])
    let one = try XCTUnwrap(policy.next())
    XCTAssertEqual(one.depth, 1)
    policy.expand(one, finalURL: one.url, links: ["/grandchild"])
    XCTAssertEqual(policy.next()?.url, "https://site.test/two")
    let grandchild = try XCTUnwrap(policy.next())
    XCTAssertEqual(grandchild.depth, 2)
    policy.expand(grandchild, finalURL: grandchild.url, links: ["/too-deep"])
    XCTAssertNil(policy.next())
    XCTAssertEqual(policy.discoveredCount, 4)
    var pending = try AgentIOSWebCrawlPolicy(input: ["url": .string("https://site.test/root")])
    XCTAssertNil(pending.next(shouldStop: { true }))
    let unstarted = try XCTUnwrap(pending.next())
    pending.restoreUnstarted(unstarted)
    XCTAssertEqual(pending.remainingCount, 1)
    XCTAssertEqual(pending.next(), unstarted)
  }

  func testDepthZeroRegexValidationAndExactOriginPorts() throws {
    var zero = try AgentIOSWebCrawlPolicy(input: ["url": .string("https://SITE.test:443/root#fragment"), "max_depth": .int(0)])
    let root = try XCTUnwrap(zero.next())
    XCTAssertEqual(root.url, "https://site.test/root")
    zero.expand(root, finalURL: root.url, links: ["/child"])
    XCTAssertNil(zero.next())
    var filtered = try AgentIOSWebCrawlPolicy(input: ["url": .string("https://site.test/root"),
      "include_pattern": .string("ROOT|KEEP"), "exclude_pattern": .string("BLOCKED")])
    let first = try XCTUnwrap(filtered.next())
    filtered.expand(first, finalURL: first.url, links: ["/drop", "/keep", "/keep-blocked",
      "https://site.test:8443/keep", "https://other.test/keep"])
    XCTAssertEqual(filtered.next()?.url, "https://site.test/keep")
    XCTAssertNil(filtered.next())
    XCTAssertThrowsError(try AgentIOSWebCrawlPolicy(input: ["url": .string(root.url), "include_pattern": .string("[")]))
    for url in ["http://site.test/", "https://127.0.0.1/", "https://user@site.test/", "https://site.test:0/"] {
      XCTAssertThrowsError(try AgentIOSWebCrawlPolicy(input: ["url": .string(url)]), url)
    }
    var crossOrigin = try AgentIOSWebCrawlPolicy(input: ["url": .string(root.url), "same_origin": .bool(false)])
    let crossRoot = try XCTUnwrap(crossOrigin.next())
    crossOrigin.expand(crossRoot, finalURL: root.url,
      links: ["https://other.test/keep", "https://127.0.0.1/private"])
    XCTAssertEqual(crossOrigin.next()?.url, "https://other.test/keep")
    XCTAssertNil(crossOrigin.next())
  }

  func testDOMLinksKeepUnquotedAttributesAndOneHundredDestinations() {
    let html = "<script>const inert = '<a href=/wrong>wrong</a>';</script>" +
      (0..<120).map { "<a href=/page-\($0)>page</a>" }.joined() + "<a href=/page-0#again>duplicate</a>"
    let links = AgentIOSWebCrawlPolicy.links(output: ["text": .string(html)], baseURL: "https://site.test/root", rawHTML: true)
    XCTAssertEqual(links.count, 100)
    XCTAssertEqual(links.first, "https://site.test/page-0")
    XCTAssertFalse(links.contains("https://site.test/wrong"))
    let long = "https://site.test/" + String(repeating: "x", count: 1_000)
    XCTAssertEqual(AgentIOSWebCrawlPolicy.links(output: ["links": .array([.string(long)])],
      baseURL: "https://site.test/root", rawHTML: false), [long])
  }

  func testMonotonicDeadlineSupportsTenMinutesAndClampsFixedChildren() throws {
    var ticks: Int64 = 0, wall: Int64 = 1_000
    let budget = AgentIOSWebCrawlDeadline(durationMillis: 600_000, now: { ticks })
    let descriptor = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions().first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.crawl }?.descriptor)
    let parent = AgentNativeToolInvocation(descriptor: descriptor, input: [:], context: .init(), startedAtEpochMillis: wall,
      deadlineEpochMillis: 20_000, hardDeadlineEpochMillis: 20_000, nowMillis: { wall },
      cancellationRequested: { false }, progressReporter: { _, _ in })
    XCTAssertEqual(try budget.invocation(parent: parent, input: [:], nowMillis: { wall }).remainingTimeMillis, 15_000)
    ticks = 10_000; wall = 19_000
    XCTAssertEqual(budget.remainingMillis, 590_000)
    let child = try budget.invocation(parent: parent, input: [:], nowMillis: { wall })
    try child.checkpoint()
    XCTAssertEqual(child.deadlineEpochMillis, 20_000)
    XCTAssertEqual(child.remainingTimeMillis, 1_000)
    ticks = -1
    XCTAssertTrue(budget.expired)
    XCTAssertThrowsError(try budget.invocation(parent: parent, input: [:], nowMillis: { wall }))
    ticks = Int64.min
    let overflow = AgentIOSWebCrawlDeadline(durationMillis: 600_000, now: { ticks })
    ticks = Int64.max
    XCTAssertTrue(overflow.expired)
    ticks = 1_001
    XCTAssertTrue(AgentIOSWebCrawlDeadline(durationMillis: 1_000, startedAtMillis: 0, now: { ticks }).expired)
  }

  func testNativeRegistryCrawlReachesOneHundredAndReusesScopedCache() throws {
    let fixture = CrawlNativeFixture()
    defer { fixture.close() }
    let input: AgentMcpJSONObject = ["url": .string("https://crawl.test/root"), "max_pages": .int(100), "max_depth": .int(1)]
    let first = try fixture.call(input, cache: true)
    XCTAssertTrue(first.isSuccess, first.error?.message ?? "")
    XCTAssertEqual(first.output["page_count"], .int(100))
    XCTAssertEqual(first.output["status"], .string("partial"))
    XCTAssertEqual(first.output["metadata"]?.objectValue?["stop_reason"], .string("page_limit"))
    XCTAssertEqual(fixture.transport.requests.count, 100)
    XCTAssertFalse(fixture.transport.requests.contains { $0.url.path == "/wrong" })
    XCTAssertEqual(first.output["source_receipts"]?.arrayValue?.count, 100)
    let second = try fixture.call(input, cache: true)
    XCTAssertEqual(second.output["page_count"], .int(100))
    XCTAssertEqual(fixture.transport.requests.count, 100)
    XCTAssertTrue((second.output["pages"]?.arrayValue ?? []).allSatisfy { $0.objectValue?["cache_hit"] == .bool(true) })
  }

  func testNetworkOnlyCrawlDoesNotOpenOrWriteTheEncryptedCache() throws {
    let fixture = CrawlNativeFixture()
    defer { fixture.close() }
    let result = try fixture.call(["url": .string("https://crawl.test/root"), "max_pages": .int(30), "max_depth": .int(1)], cache: false)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["page_count"], .int(30))
    XCTAssertNil(result.output["cache"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.file.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: fixture.file).path))
  }

  func testOverallDeadlineAndCancellationStopSubsequentRequests() throws {
    var ticks: Int64 = 0
    let media = CrawlGraphProvider()
    media.afterCall = { ticks += 500 }
    let result = try direct(media, input: ["url": .string("https://crawl.test/root"), "timeout_ms": .int(1_000)],
      uptime: { ticks })
    XCTAssertEqual(result.output["page_count"], .int(2))
    XCTAssertEqual(result.output["status"], .string("partial"))
    XCTAssertEqual(result.output["metadata"]?.objectValue?["deadline_reached"], .bool(true))
    XCTAssertEqual(media.calls.map { $0.input["timeout_ms"]?.intValue }, [1_000, 500])
    XCTAssertEqual(media.calls.last?.deadline, 1_500)
    var cancelled = false
    let cancelling = CrawlGraphProvider()
    cancelling.afterCall = { cancelled = true }
    let partial = try direct(cancelling, input: ["url": .string("https://crawl.test/root")],
      isCancelled: { cancelled })
    XCTAssertEqual(cancelling.calls.count, 1)
    XCTAssertEqual(partial.output["page_count"], .int(1))
    XCTAssertEqual(partial.output["metadata"]?.objectValue?["cancelled"], .bool(true))
  }

  func testFailedSiblingReceiptsSurviveAndAllFailedRootKeepsDiagnostics() throws {
    let media = CrawlGraphProvider()
    media.failing = ["/bad"]
    let result = try direct(media, input: ["url": .string("https://crawl.test/root"), "max_depth": .int(1)])
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.output["page_count"], .int(2))
    XCTAssertEqual(result.output["status"], .string("partial"))
    XCTAssertEqual(result.output["source_receipts"]?.arrayValue?.count, 3)
    XCTAssertEqual(result.output["failures"]?.arrayValue?.first?.objectValue?["code"], .string("fixture_failed"))
    let failed = CrawlGraphProvider()
    failed.failing = ["/root"]
    let empty = try direct(failed, input: ["url": .string("https://crawl.test/root")])
    XCTAssertFalse(empty.isSuccess)
    XCTAssertEqual(empty.error?.code, "crawl_no_pages")
    XCTAssertEqual(empty.output["source_receipts"]?.arrayValue?.count, 1)
    XCTAssertEqual(empty.error?.details["metadata"], empty.output["metadata"])
  }

  func testInvalidPatternsFailBeforeNativeTransport() throws {
    let fixture = CrawlNativeFixture()
    defer { fixture.close() }
    let result = try fixture.call(["url": .string("https://crawl.test/root"), "exclude_pattern": .string("[")], cache: true)
    XCTAssertFalse(result.isSuccess)
    XCTAssertEqual(result.error?.code, "invalid_crawl_pattern")
    XCTAssertTrue(fixture.transport.requests.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: fixture.file).path))
  }

  private func direct(_ media: CrawlGraphProvider, input: AgentMcpJSONObject,
    uptime: @escaping () -> Int64 = { 0 }, isCancelled: @escaping () -> Bool = { false }) throws -> AgentNativeToolExecutionResult {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("crawl-direct-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media,
      cacheStore: .init(fileURL: file, secrets: InMemorySecretStore()), nowMillis: { 1_000 }, uptimeMillis: uptime)
    let descriptor = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: provider)
      .first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.crawl }?.descriptor)
    let invocation = AgentNativeToolInvocation(descriptor: descriptor, input: input, context: .init(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]), startedAtEpochMillis: 1_000,
      deadlineEpochMillis: 601_000, hardDeadlineEpochMillis: 601_000, nowMillis: { 1_000 },
      cancellationRequested: isCancelled, progressReporter: { _, _ in })
    return provider.invoke(operation: .crawl, input: input, invocation: invocation)
  }
}

private final class CrawlNativeFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("crawl-native-\(UUID()).json")
  let transport = CrawlNativeTransport()
  let cache: AgentIOSWebIntelligenceCacheStore
  init() { cache = .init(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 }) }
  func call(_ input: AgentMcpJSONObject, cache allowed: Bool) throws -> AgentNativeToolResult {
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: AgentIOSURLSessionWebMediaToolProvider(
      transport: transport, sourceHealthStore: nil, nowMillis: { 1_000 }), cacheStore: cache,
      nowMillis: { 1_000 }, uptimeMillis: { 0 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    var permissions: Set<String> = [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission]
    var consents: Set<String> = [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent]
    if allowed { permissions.insert(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission); consents.insert(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent) }
    return registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.crawl, input: input,
      context: .init(grantedPermissions: permissions, grantedConsents: consents), hooks: .init(nowMillis: { 1_000 }))
  }
  func close() { removeWebCacheFixture(file) }
}

private final class CrawlNativeTransport: AgentIOSURLSessionWebTransporting {
  private(set) var requests: [AgentIOSURLSessionWebRequest] = []
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    requests.append(request)
    let links = request.url.path == "/root" ? (0..<120).map { "<a href=/child-\($0)>child</a>" }.joined() : ""
    let body = "<html><head><title>Page \(request.url.path)</title><script>const inert = '<a href=/wrong>wrong</a>';</script></head><body><main><p>Public page body with enough readable evidence for native parsing and caching.</p>\(links)</main></body></html>"
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html; charset=utf-8"],
      body: Data(body.utf8), retrievedAtEpochMillis: 1_000)
  }
}

private final class CrawlGraphProvider: AgentIOSWebMediaToolProviding {
  let implementationId = "crawl-graph-fixture"
  var calls: [(input: AgentMcpJSONObject, deadline: Int64)] = []
  var failing: Set<String> = []
  var afterCall: () -> Void = {}
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    calls.append((input, invocation.deadlineEpochMillis))
    defer { afterCall() }
    let url = input["url"]?.stringValue ?? ""
    if failing.contains(URL(string: url)?.path ?? "") { return .failure(code: "fixture_failed", message: "Injected page failure") }
    let root = url.hasSuffix("/root")
    return .success(output: ["text": .string("<title>Page</title><p>Readable public evidence body.</p>"),
      "content_type": .string("text/html"), "links": .array(root ? [.string("/bad"), .string("/good")] : []),
      "source": .object(["requested_url": .string(url), "final_url": .string(url)])])
  }
}
