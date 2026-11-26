import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebPageDiffTests: XCTestCase {
  func testOrderedSetSummaryTrimsDeduplicatesAndIgnoresReordering() throws {
    let report = try AgentIOSWebPageDiff.summarize(previous: " old \r\nshared\r\nold\n\n", current: "shared\nnew\nnew")
    XCTAssertEqual(report.text, "- old\n+ new")
    XCTAssertEqual(report.removedLines, 1)
    XCTAssertEqual(report.addedLines, 1)
    XCTAssertFalse(report.truncated)
    XCTAssertEqual(try AgentIOSWebPageDiff.summarize(previous: "a\nb", current: " b\n a \na").text, "")
    XCTAssertEqual(try AgentIOSWebPageDiff.summarize(previous: "", current: "first\nsecond").text, "+ first\n+ second")
  }

  func testSummaryBoundsFortyLinesPerSideAndSafeUTF16Prefixes() throws {
    let previous = (0..<60).map { "old-\($0)-" + String(repeating: "x", count: 400) }.joined(separator: "\n")
    let current = (0..<70).map { "new-\($0)-" + String(repeating: "y", count: 400) }.joined(separator: "\n")
    let report = try AgentIOSWebPageDiff.summarize(previous: previous, current: current)
    XCTAssertEqual(report.removedLines, 60)
    XCTAssertEqual(report.addedLines, 70)
    XCTAssertEqual(report.text.components(separatedBy: "\n").count, 80)
    XCTAssertTrue(report.truncated)
    XCTAssertLessThanOrEqual(report.text.utf16.count, 32_768)
    XCTAssertTrue(report.text.components(separatedBy: "\n").allSatisfy { $0.utf16.count <= 302 })
    let unicode = try AgentIOSWebPageDiff.summarize(previous: "", current: String(repeating: "a", count: 299) + "\u{1F600}tail")
    XCTAssertFalse(unicode.text.contains("\u{FFFD}"))
  }

  func testNativeRegistryProducesRealChangesThenEmptyUnchangedSummary() throws {
    let fixture = PageDiffFixture()
    defer { fixture.close() }
    try fixture.seed()
    let first = try fixture.call()
    XCTAssertTrue(first.isSuccess, first.error?.message ?? "")
    XCTAssertEqual(first.output["status"], .string("completed"))
    XCTAssertEqual(first.output["diff"]?.objectValue?["changed"], .bool(true))
    XCTAssertTrue(first.output["diff"]?.objectValue?["summary"]?.stringValue?.contains("- Old line") == true)
    XCTAssertTrue(first.output["diff"]?.objectValue?["summary"]?.stringValue?.contains("+ New line") == true)
    XCTAssertEqual(first.output["metadata"]?.objectValue?["previous_available"], .bool(true))
    XCTAssertEqual(first.output["cache"]?.objectValue?["write_committed"], .bool(true))
    let second = try fixture.call()
    XCTAssertEqual(second.output["diff"]?.objectValue?["changed"], .bool(false))
    XCTAssertEqual(second.output["diff"]?.objectValue?["summary"], .string(""))
    XCTAssertEqual(fixture.transport.requests.count, 2, "Diff must refetch, not accept a cached current page")
    let saved = try XCTUnwrap(fixture.cache.document(url: fixture.url))
    XCTAssertEqual(saved.expiresAtMillis - saved.retrievedAtMillis, 6 * 60 * 60_000)
  }

  func testRawHashChangeWithoutReadableLineChangeHasEmptySummary() throws {
    let fixture = PageDiffFixture()
    defer { fixture.close() }
    _ = try fixture.call()
    fixture.transport.attribute = " data-layout=changed"
    let changed = try fixture.call()
    XCTAssertTrue(changed.isSuccess)
    XCTAssertEqual(changed.output["diff"]?.objectValue?["changed"], .bool(true))
    XCTAssertEqual(changed.output["diff"]?.objectValue?["summary"], .string(""))
    XCTAssertEqual(changed.output["diff"]?.objectValue?["summary_mode"], .string("trimmed_line_set"))
  }

  func testNetworkFailureAndLossyDecodeDoNotReplacePriorSnapshot() throws {
    let fixture = PageDiffFixture()
    defer { fixture.close() }
    try fixture.seed()
    let previous = fixture.cache.document(url: fixture.url)
    fixture.transport.status = 503
    XCTAssertFalse(try fixture.call().isSuccess)
    XCTAssertEqual(fixture.cache.document(url: fixture.url), previous)
    let lossy = PageDiffLossyProvider()
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: lossy, cacheStore: fixture.cache,
      nowMillis: { 1_000 }, uptimeMillis: { 0 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    let failed = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.diff, input: ["url": .string(fixture.url)],
      context: fixture.context(cache: true, network: true), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertEqual(failed.error?.code, "web_text_decoding_failed")
    XCTAssertEqual(fixture.cache.document(url: fixture.url), previous)
  }

  func testOptionalCommitFailureKeepsPriorSnapshotAndReturnsNetworkDiff() throws {
    var reject = false
    let fixture = PageDiffFixture(beforeCommit: { if reject { throw CocoaError(.fileWriteOutOfSpace) } })
    defer { fixture.close() }
    try fixture.seed()
    let previous = fixture.cache.document(url: fixture.url)
    reject = true
    let result = try fixture.call()
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["cache"]?.objectValue?["write_committed"], .bool(false))
    XCTAssertTrue(result.output["diff"]?.objectValue?["summary"]?.stringValue?.contains("+ New line") == true)
    XCTAssertEqual(fixture.cache.document(url: fixture.url), previous)
  }

  func testNetworkOnlyComparisonCannotReadWriteOrExposeCache() throws {
    let fixture = PageDiffFixture()
    defer { fixture.close() }
    let result = try fixture.call(cache: false)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["comparison"], .string("no_prior_snapshot"))
    XCTAssertEqual(result.output["metadata"]?.objectValue?["previous_available"], .bool(false))
    XCTAssertNil(result.output["cache"])
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: fixture.file).path))
  }

  func testSearchSnippetCannotBecomePriorPageSnapshot() throws {
    let fixture = PageDiffFixture()
    defer { fixture.close() }
    XCTAssertTrue(fixture.cache.putDocument(url: fixture.url, title: "Search", content: "Cached search excerpt",
      contentType: "text/x-galaxyssi-search-result", contentSHA256: String(repeating: "a", count: 64),
      retrievedAtMillis: 500, expiresAtMillis: 60_500))
    let result = try fixture.call()
    XCTAssertEqual(result.output["metadata"]?.objectValue?["previous_available"], .bool(false))
    XCTAssertFalse(result.output["diff"]?.objectValue?["summary"]?.stringValue?.contains("- Cached search excerpt") == true)
  }

  func testWatchChecksRequireNetworkScopeAndReuseActualDiff() throws {
    let fixture = PageDiffFixture()
    defer { fixture.close() }
    let registry = try fixture.registry()
    let created = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.watch,
      input: ["action": .string("create"), "watch_id": .string("fixture-watch"), "url": .string(fixture.url)],
      context: fixture.context(cache: true, network: false), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertTrue(created.isSuccess)
    let input: AgentMcpJSONObject = ["action": .string("check"), "watch_id": .string("fixture-watch")]
    let denied = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.watch, input: input,
      context: fixture.context(cache: true, network: false), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertEqual(denied.error?.code, "public_web_scope_required")
    XCTAssertTrue(fixture.transport.requests.isEmpty)
    let checked = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.watch, input: input,
      context: fixture.context(cache: true, network: true), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertTrue(checked.isSuccess, checked.error?.message ?? "")
    XCTAssertEqual(checked.output["metadata"]?.objectValue?["checked"]?.arrayValue?.count, 1)
    XCTAssertTrue(checked.output["diff"]?.objectValue?["summary"]?.stringValue?.contains("+ New line") == true)
  }

  func testCheckpointCancellationAndDeclaredTimeoutCaps() throws {
    var checkpoints = 0
    XCTAssertThrowsError(try AgentIOSWebPageDiff.summarize(previous: "old", current: "new", checkpoint: {
      checkpoints += 1
      if checkpoints == 2 { throw AgentNativeToolInvocationError.cancelled }
    }))
    let definitions = AgentIOSWebIntelligenceNativeToolCatalog.definitions()
    for (id, maximum) in [(AgentIOSWebIntelligenceNativeToolCatalog.diff, Int64(60_000)),
      (AgentIOSWebIntelligenceNativeToolCatalog.extract, 60_000), (AgentIOSWebIntelligenceNativeToolCatalog.fetch, 120_000)] {
      let definition = try XCTUnwrap(definitions.first { $0.id == id })
      XCTAssertEqual(definition.descriptor.inputSchema["properties"]?.objectValue?["timeout_ms"]?.objectValue?["maximum"], .int(maximum))
    }
    let fixture = PageDiffFixture()
    defer { fixture.close() }
    let registry = try fixture.registry()
    let invalid = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.diff,
      input: ["url": .string(fixture.url), "timeout_ms": .int(60_001)],
      context: fixture.context(cache: true, network: true), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertFalse(invalid.isSuccess)
    XCTAssertTrue(fixture.transport.requests.isEmpty)
  }
}

private final class PageDiffFixture {
  let url = "https://diff.test/page"
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("page-diff-\(UUID()).json")
  let transport = PageDiffTransport()
  let cache: AgentIOSWebIntelligenceCacheStore
  init(beforeCommit: @escaping () throws -> Void = {}) {
    cache = .init(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 }, beforeCommit: beforeCommit)
  }
  func seed() throws {
    XCTAssertTrue(cache.putDocument(url: url, title: "Page", content: "Old line\nShared evidence line with readable context",
      contentType: "text/plain", contentSHA256: String(repeating: "a", count: 64), retrievedAtMillis: 500, expiresAtMillis: 60_500))
  }
  func registry() throws -> AgentNativeToolRegistry {
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: AgentIOSURLSessionWebMediaToolProvider(
      transport: transport, sourceHealthStore: nil, nowMillis: { 1_000 }), cacheStore: cache,
      nowMillis: { 1_000 }, uptimeMillis: { 0 })
    return try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
  }
  func context(cache: Bool, network: Bool) -> AgentNativeToolInvocationContext {
    var permissions = Set<String>(), consents = Set<String>()
    if cache { permissions.insert(AgentIOSWebIntelligenceNativeToolCatalog.cachePermission); consents.insert(AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent) }
    if network { permissions.insert(AgentIOSWebIntelligenceNativeToolCatalog.networkPermission); consents.insert(AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent) }
    return .init(grantedPermissions: permissions, grantedConsents: consents)
  }
  func call(cache: Bool = true) throws -> AgentNativeToolResult {
    try registry().invoke(AgentIOSWebIntelligenceNativeToolCatalog.diff, input: ["url": .string(url)],
      context: context(cache: cache, network: true), hooks: .init(nowMillis: { 1_000 }))
  }
  func close() { removeWebCacheFixture(file) }
}

private final class PageDiffTransport: AgentIOSURLSessionWebTransporting {
  private(set) var requests: [AgentIOSURLSessionWebRequest] = []
  var status = 200
  var attribute = ""
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    requests.append(request)
    let body = "<html><title>Page</title><body><main\(attribute)><p>Shared evidence line with readable context</p><p>New line</p></main></body></html>"
    return .init(statusCode: status, finalURL: request.url, headers: ["content-type": "text/html; charset=utf-8"],
      body: Data(body.utf8), retrievedAtEpochMillis: 1_000)
  }
}

private struct PageDiffLossyProvider: AgentIOSWebMediaToolProviding {
  let implementationId = "lossy-diff-fixture"
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    .success(output: ["text": .string("corrupted text"), "text_decoding_lossless": .bool(false), "html_sha256": .string(String(repeating: "b", count: 64))])
  }
}
