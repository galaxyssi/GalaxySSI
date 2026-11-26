import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebExtractionTests: XCTestCase {
  func testHeadingsAndLiteralRequestedFieldsFollowReferenceHeuristics() throws {
    let fields = AgentIOSWebLocalExtraction.requestedFields(.array([.string(" Price[USD] "), .string("missing"), .string("Price[USD]")]))
    XCTAssertEqual(fields, ["Price[USD]", "missing"])
    let value = try AgentIOSWebLocalExtraction.structured(title: "Fixture", url: "https://source.test/", content:
      "# Heading\r\nShort title\r\n###\r\nSentence.\r\nprice[usd] = 123\r\nPriceXUSD = wrong\r\nShort title",
      links: ["https://source.test/child"], fields: fields)
    XCTAssertEqual(value["headings"]?.arrayValue?.prefix(3).map(\.stringValue), ["Heading", "Short title", ""])
    XCTAssertEqual(value["requested"]?.objectValue?["Price[USD]"], .string("123"))
    XCTAssertEqual(value["requested"]?.objectValue?["missing"], .string(""))
    XCTAssertEqual(value["links"], .array([.string("https://source.test/child")]))
  }

  func testFieldHeadingAndCaptureBoundsAreExplicit() throws {
    let fields = AgentIOSWebLocalExtraction.requestedFields(.array((0..<150).map { .string("field-\($0)") }))
    XCTAssertEqual(fields.count, 100)
    let longName = String(repeating: "a", count: 127) + "\u{1F600}"
    let bounded = AgentIOSWebLocalExtraction.requestedFields(.array([.string(longName)]))
    XCTAssertLessThanOrEqual(bounded[0].utf16.count, 128)
    XCTAssertFalse(bounded[0].contains("\u{FFFD}"))
    let lines = (0..<150).map { "# Header \($0)" }.joined(separator: "\n")
    let value = try AgentIOSWebLocalExtraction.structured(title: "", url: "", content: lines + "\nkey: " + String(repeating: "x", count: 501),
      links: [], fields: ["key"])
    XCTAssertEqual(value["headings"]?.arrayValue?.count, 100)
    XCTAssertEqual(value["requested"]?.objectValue?["key"], .string(""), "Reference rejects a whole value longer than 500, not a fabricated truncated match")
  }

  func testLanguageHintRetainsReferenceRangePriority() {
    XCTAssertEqual(AgentIOSWebLocalExtraction.language("\u{4E2D}\u{3042}"), "zh")
    XCTAssertEqual(AgentIOSWebLocalExtraction.language("\u{3042}"), "ja")
    XCTAssertEqual(AgentIOSWebLocalExtraction.language("\u{AC00}"), "ko")
    XCTAssertEqual(AgentIOSWebLocalExtraction.language("plain English"), "en")
    XCTAssertEqual(AgentIOSWebLocalExtraction.language(""), "en")
  }

  func testRegistrySuppliedContentExtractsAndCachesWithoutNetwork() throws {
    let fixture = ExtractionFixture()
    defer { fixture.close() }
    let result = try fixture.call(["content": .string("<title>Receipt</title><h1>Invoice</h1><p>Price: 42</p>"),
      "fields": .array([.string("Price"), .string("missing")])])
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    let structured = try XCTUnwrap(result.output["metadata"]?.objectValue?["structured"]?.objectValue)
    XCTAssertEqual(structured["requested"]?.objectValue?["Price"], .string("42"))
    XCTAssertEqual(result.output["url"], .string("https://local.galaxyssi.invalid/content"))
    XCTAssertEqual(result.output["source_receipts"]?.arrayValue?.first?.objectValue?["network"], .bool(false))
    XCTAssertEqual(result.metadata["network_attempted"], .bool(false))
    XCTAssertTrue(fixture.transport.requests.isEmpty)
    let stored = try XCTUnwrap(fixture.cache.document(url: "https://local.galaxyssi.invalid/content"))
    XCTAssertEqual(stored.metadata["fetch_tier"], "local_content")
    XCTAssertEqual(stored.expiresAtMillis - stored.retrievedAtMillis, 6 * 60 * 60_000)
  }

  func testCacheOnlyURLTakesPrecedenceOverSuppliedContent() throws {
    let fixture = ExtractionFixture()
    defer { fixture.close() }
    XCTAssertTrue(fixture.cache.putDocument(url: "https://source.test/page", title: "Cached", content: "Price: 55",
      contentType: "text/plain", contentSHA256: String(repeating: "a", count: 64), retrievedAtMillis: 1_000, expiresAtMillis: 61_000))
    let result = try fixture.call(["url": .string("https://source.test/page"), "content": .string("Price: wrong"),
      "fields": .array([.string("Price")])])
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["operation"], .string("extract"))
    XCTAssertEqual(result.output["metadata"]?.objectValue?["structured"]?.objectValue?["requested"]?.objectValue?["Price"], .string("55"))
    XCTAssertEqual(result.output["cache"]?.objectValue?["hit"], .bool(true))
    XCTAssertEqual(result.metadata["network_attempted"], .bool(false))
    XCTAssertTrue(fixture.transport.requests.isEmpty)
    let forced = try fixture.call(["url": .string("https://source.test/page"), "force": .bool(true)])
    XCTAssertEqual(forced.error?.code, "public_web_scope_required")
    let absent = try fixture.call(["url": .string("https://source.test/missing")])
    XCTAssertEqual(absent.error?.code, "public_web_scope_required")
    XCTAssertTrue(fixture.transport.requests.isEmpty)
  }

  func testNetworkURLReusesFetchAndForceRefreshWithBothScopes() throws {
    let fixture = ExtractionFixture()
    defer { fixture.close() }
    let input: AgentMcpJSONObject = ["url": .string("https://source.test/page"), "content": .string("Price: ignored"),
      "fields": .array([.string("Price")])]
    let first = try fixture.call(input, network: true)
    XCTAssertTrue(first.isSuccess, first.error?.message ?? "")
    XCTAssertEqual(first.output["metadata"]?.objectValue?["structured"]?.objectValue?["requested"]?.objectValue?["Price"], .string("100"))
    XCTAssertEqual(first.metadata["network_attempted"], .bool(true))
    let cached = try fixture.call(input)
    XCTAssertTrue(cached.isSuccess, cached.error?.message ?? "")
    XCTAssertEqual(fixture.transport.requests.count, 1)
    fixture.transport.price = 200
    let fresh = try fixture.call(input.merging(["force": .bool(true)]) { _, new in new }, network: true)
    XCTAssertTrue(fresh.isSuccess, fresh.error?.message ?? "")
    XCTAssertEqual(fresh.output["metadata"]?.objectValue?["structured"]?.objectValue?["requested"]?.objectValue?["Price"], .string("200"))
    XCTAssertEqual(fixture.transport.requests.count, 2)
  }

  func testStructuredCheckpointAndCancelledProviderDoNotPersistLocalContent() throws {
    var checks = 0
    XCTAssertThrowsError(try AgentIOSWebLocalExtraction.structured(title: "", url: "", content: "one\ntwo\nthree", links: [], fields: [], checkpoint: {
      checks += 1
      if checks == 3 { throw AgentNativeToolInvocationError.cancelled }
    }))
    let fixture = ExtractionFixture()
    defer { fixture.close() }
    let input: AgentMcpJSONObject = ["content": .string("Price: 42")]
    let descriptor = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: fixture.provider)
      .first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.extract }?.descriptor)
    let invocation = AgentNativeToolInvocation(descriptor: descriptor, input: input, context: fixture.context(network: false),
      startedAtEpochMillis: 1_000, deadlineEpochMillis: 61_000, nowMillis: { 1_000 },
      cancellationRequested: { true }, progressReporter: { _, _ in })
    let result = fixture.provider.invoke(operation: .extract, input: input, invocation: invocation)
    XCTAssertEqual(result.error?.code, "cancelled")
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: fixture.file).path))
    XCTAssertTrue(fixture.transport.requests.isEmpty)
  }

  func testDirectLocalExtractionWithoutCacheScopeHasNoPersistence() throws {
    let fixture = ExtractionFixture()
    defer { fixture.close() }
    let descriptor = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: fixture.provider)
      .first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.extract }?.descriptor)
    let input: AgentMcpJSONObject = ["content": .string("Price: 42"), "fields": .array([.string("Price")])]
    let invocation = AgentNativeToolInvocation(descriptor: descriptor, input: input, context: .init(),
      startedAtEpochMillis: 1_000, deadlineEpochMillis: 61_000, nowMillis: { 1_000 },
      cancellationRequested: { false }, progressReporter: { _, _ in })
    let local = fixture.provider.invoke(operation: .extract, input: input, invocation: invocation)
    XCTAssertTrue(local.isSuccess)
    XCTAssertNil(local.output["cache"])
    let denied = fixture.provider.invoke(operation: .extract, input: ["url": .string("https://source.test/page")], invocation: invocation)
    XCTAssertEqual(denied.error?.code, "cache_scope_required")
    XCTAssertTrue(fixture.transport.requests.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: fixture.file).path))
  }
}

private final class ExtractionFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("extraction-fixture-\(UUID()).json")
  let transport = ExtractionTransport()
  let cache: AgentIOSWebIntelligenceCacheStore
  var provider: AgentIOSURLSessionWebIntelligenceProvider {
    .init(webMediaProvider: AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil, nowMillis: { 1_000 }),
      cacheStore: cache, nowMillis: { 1_000 }, uptimeMillis: { 0 })
  }
  init() { cache = .init(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 }) }
  func context(network: Bool) -> AgentNativeToolInvocationContext {
    var permissions: Set<String> = [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission]
    var consents: Set<String> = [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent]
    if network { permissions.insert(AgentIOSWebIntelligenceNativeToolCatalog.networkPermission); consents.insert(AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent) }
    return .init(grantedPermissions: permissions, grantedConsents: consents)
  }
  func call(_ input: AgentMcpJSONObject, network: Bool = false) throws -> AgentNativeToolResult {
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.extract, input: input,
      context: context(network: network), hooks: .init(nowMillis: { 1_000 }))
  }
  func close() { removeWebCacheFixture(file) }
}

private final class ExtractionTransport: AgentIOSURLSessionWebTransporting {
  private(set) var requests: [AgentIOSURLSessionWebRequest] = []
  var price = 100
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    requests.append(request)
    let body = "<html><title>Invoice</title><body><main><h1>Invoice</h1><p>Price: \(price)</p><p>Readable public source details for this extraction fixture.</p><a href=/details>Details</a></main></body></html>"
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html; charset=utf-8"],
      body: Data(body.utf8), retrievedAtEpochMillis: 1_000)
  }
}
