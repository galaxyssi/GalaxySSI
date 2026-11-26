import CryptoKit
import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebWatchTests: XCTestCase {
  func testDueBoundaryDisabledFutureAndMalformedIntervals() {
    var value = watch("due")
    value.lastCheckedAtMillis = 1_000
    XCTAssertFalse(AgentIOSWebWatchPolicy.isDue(value, now: 900_999))
    XCTAssertTrue(AgentIOSWebWatchPolicy.isDue(value, now: 901_000))
    XCTAssertFalse(AgentIOSWebWatchPolicy.isDue(value, now: 999))
    value.enabled = false
    XCTAssertFalse(AgentIOSWebWatchPolicy.isDue(value, now: Int64.max))
    value.enabled = true; value.intervalMinutes = Int.max
    XCTAssertFalse(AgentIOSWebWatchPolicy.isDue(value, now: Int64.max))
    value = watch("new")
    XCTAssertTrue(AgentIOSWebWatchPolicy.isDue(value, now: 1_000))
    value.url = "https://127.0.0.1/private"
    XCTAssertFalse(AgentIOSWebWatchPolicy.isValid(value))
  }

  func testCompletionUsesFinishTimeAndFirstBaselineDoesNotSignalChange() throws {
    let first = try XCTUnwrap(AgentIOSWebWatchPolicy.completed(watch("first"), hash: String(repeating: "a", count: 64), now: 2_000))
    XCTAssertFalse(first.changed)
    XCTAssertEqual(first.watch.lastCheckedAtMillis, 2_000)
    XCTAssertEqual(first.watch.lastChangedAtMillis, 0)
    let changed = try XCTUnwrap(AgentIOSWebWatchPolicy.completed(first.watch, hash: String(repeating: "b", count: 64), now: 3_000))
    XCTAssertTrue(changed.changed)
    XCTAssertEqual(changed.watch.lastChangedAtMillis, 3_000)
    let same = try XCTUnwrap(AgentIOSWebWatchPolicy.completed(changed.watch, hash: String(repeating: "B", count: 64), now: 4_000))
    XCTAssertFalse(same.changed)
    XCTAssertEqual(same.watch.lastChangedAtMillis, 3_000)
    let rollback = try XCTUnwrap(AgentIOSWebWatchPolicy.completed(same.watch, hash: same.watch.lastSHA256, now: 500))
    XCTAssertEqual(rollback.watch.lastCheckedAtMillis, 4_000)
    XCTAssertNil(AgentIOSWebWatchPolicy.completed(same.watch, hash: "invalid", now: 5_000))
  }

  func testMixedChecksPreserveFailureAndSuccessReceiptsAndForwardTimeout() throws {
    let fixture = WebWatchFixture()
    defer { fixture.close() }
    fixture.clock.now = 10_000
    fixture.graph.afterCall = { fixture.clock.now += 100 }
    fixture.graph.failing = ["/bad"]
    XCTAssertTrue(fixture.cache.putWatch(watch("good")))
    XCTAssertTrue(fixture.cache.putWatch(watch("bad")))
    let result = try fixture.call(["action": .string("check_due"), "timeout_ms": .int(7_777)])
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(result.output["status"], .string("partial"))
    XCTAssertEqual(result.output["metadata"]?.objectValue?["checked_count"], .int(1))
    XCTAssertEqual(result.output["metadata"]?.objectValue?["failed_count"], .int(1))
    XCTAssertEqual(result.output["source_receipts"]?.arrayValue?.count, 2)
    XCTAssertEqual(fixture.cache.watch(id: "bad")?.lastCheckedAtMillis, 0)
    XCTAssertGreaterThan(try XCTUnwrap(fixture.cache.watch(id: "good")).lastCheckedAtMillis, 10_000)
    XCTAssertTrue(fixture.graph.inputs.allSatisfy { $0["timeout_ms"] == .int(7_777) })
    let failed = try fixture.call(["action": .string("check"), "watch_id": .string("bad")])
    XCTAssertFalse(failed.isSuccess)
    XCTAssertEqual(failed.error?.code, "watch_check_failed")
    XCTAssertEqual(failed.output["failures"]?.arrayValue?.first?.objectValue?["code"], .string("fixture_fetch_failed"))
    XCTAssertEqual(failed.error?.details["source_receipts"], failed.output["source_receipts"])
  }

  func testNativeManualDisabledWatchUsesCompletionTimeAndActualDelta() throws {
    let transport = WatchNativeTransport(), clock = WebWatchClock()
    let fixture = WebWatchFixture(clock: clock, media: AgentIOSURLSessionWebMediaToolProvider(transport: transport,
      sourceHealthStore: nil, nowMillis: { clock.now }))
    defer { fixture.close() }
    var disabled = watch("native"); disabled.enabled = false
    XCTAssertTrue(fixture.cache.putWatch(disabled))
    transport.afterCall = { clock.now += 500 }
    let input: AgentMcpJSONObject = ["action": .string("check"), "watch_id": .string("native")]
    let first = try fixture.call(input)
    XCTAssertTrue(first.isSuccess, first.error?.message ?? "")
    XCTAssertEqual(first.output["watch"]?.objectValue?["last_checked_at_millis"], .int(1_500))
    XCTAssertEqual(first.output["metadata"]?.objectValue?["checked"]?.arrayValue?.first?.objectValue?["changed"], .bool(false))
    transport.label = "Changed public page content"
    let second = try fixture.call(input)
    XCTAssertTrue(second.isSuccess, second.error?.message ?? "")
    XCTAssertEqual(fixture.cache.watch(id: "native")?.lastChangedAtMillis, 2_000)
    XCTAssertEqual(fixture.cache.watch(id: "native")?.enabled, false)
    XCTAssertEqual(second.output["source_receipts"]?.arrayValue?.first?.objectValue?["watch_id"], .string("native"))
    XCTAssertFalse(second.output["diff"]?.objectValue?["summary"]?.stringValue?.isEmpty ?? true)
    XCTAssertEqual(transport.requests.count, 2)
    transport.afterCall = {}
  }

  func testDueSelectionHonorsDefaultTwentyAndExplicitHundredWithoutFutureOrDisabled() throws {
    let fixture = WebWatchFixture()
    defer { fixture.close() }
    fixture.clock.now = 2_000
    for index in 0..<25 { XCTAssertTrue(fixture.cache.putWatch(watch("due-\(index)"))) }
    var disabled = watch("disabled"); disabled.enabled = false
    var recent = watch("recent"); recent.lastCheckedAtMillis = 1_500
    var future = watch("future"); future.lastCheckedAtMillis = 10_000
    for value in [disabled, recent, future] { XCTAssertTrue(fixture.cache.putWatch(value)) }
    let first = try fixture.call(["action": .string("check_due")])
    XCTAssertEqual(first.output["metadata"]?.objectValue?["checked_count"], .int(20))
    let rest = try fixture.call(["action": .string("check_due"), "limit": .int(100)])
    XCTAssertEqual(rest.output["metadata"]?.objectValue?["checked_count"], .int(5))
    XCTAssertEqual(fixture.graph.inputs.count, 25)
    XCTAssertFalse(fixture.graph.inputs.contains { [disabled.url, recent.url, future.url].contains($0["url"]?.stringValue ?? "") })
  }

  func testCancellationStopsFurtherChecksAndPreservesUncommittedCursors() throws {
    let fixture = WebWatchFixture()
    defer { fixture.close() }
    for id in ["one", "two"] { XCTAssertTrue(fixture.cache.putWatch(watch(id))) }
    var cancelled = false
    fixture.graph.afterCall = { cancelled = true }
    let descriptor = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: fixture.provider)
      .first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.watch }?.descriptor)
    let input: AgentMcpJSONObject = ["action": .string("check_due")]
    let invocation = AgentNativeToolInvocation(descriptor: descriptor, input: input, context: fixture.context,
      startedAtEpochMillis: 1_000, deadlineEpochMillis: 61_000, hardDeadlineEpochMillis: 61_000,
      nowMillis: { fixture.clock.now }, cancellationRequested: { cancelled }, progressReporter: { _, _ in })
    let result = fixture.provider.invoke(operation: .watch, input: input, invocation: invocation)
    XCTAssertEqual(result.error?.code, "cancelled")
    XCTAssertEqual(fixture.graph.inputs.count, 1)
    XCTAssertEqual(result.output["metadata"]?.objectValue?["remaining_count"], .int(1))
    XCTAssertEqual(fixture.cache.watch(id: "one")?.lastCheckedAtMillis, 0)
    XCTAssertEqual(fixture.cache.watch(id: "two")?.lastCheckedAtMillis, 0)
  }

  func testSnapshotAndWatchCommitFailuresNeverAdvanceTheCursor() throws {
    for allowedWrites in [0, 1] {
      var remaining: Int? = nil
      let fixture = WebWatchFixture(beforeCommit: {
        if let count = remaining {
          if count == 0 { throw CocoaError(.fileWriteOutOfSpace) }
          remaining = count - 1
        }
      })
      defer { fixture.close() }
      let original = watch("failed")
      XCTAssertTrue(fixture.cache.putWatch(original))
      remaining = allowedWrites
      let result = try fixture.call(["action": .string("check"), "watch_id": .string(original.id)])
      XCTAssertEqual(result.error?.code, "cache_persistence_failed")
      XCTAssertEqual(result.output["source_receipts"]?.arrayValue?.count, 1)
      XCTAssertEqual(fixture.cache.watch(id: original.id), original)
      XCTAssertEqual(result.output["failures"]?.arrayValue?.first?.objectValue?["phase"], .string(allowedWrites == 0 ? "snapshot" : "watch"))
    }
  }

  func testConcurrentEditAndDeleteCannotBeOverwrittenOrResurrected() throws {
    for deleting in [false, true] {
      let fixture = WebWatchFixture()
      defer { fixture.close() }
      let original = watch("changed")
      XCTAssertTrue(fixture.cache.putWatch(original))
      fixture.graph.afterCall = {
        if deleting { XCTAssertEqual(fixture.cache.removeWatch(id: original.id), true) }
        else { var edited = original; edited.intervalMinutes = 30; XCTAssertTrue(fixture.cache.putWatch(edited)) }
      }
      let result = try fixture.call(["action": .string("check"), "watch_id": .string(original.id)])
      XCTAssertFalse(result.isSuccess)
      XCTAssertEqual(result.output["failures"]?.arrayValue?.first?.objectValue?["code"], .string("watch_changed"))
      if deleting { XCTAssertNil(fixture.cache.watch(id: original.id)) }
      else {
        XCTAssertEqual(fixture.cache.watch(id: original.id)?.intervalMinutes, 30)
        XCTAssertEqual(fixture.cache.watch(id: original.id)?.lastCheckedAtMillis, 0)
      }
    }
  }

  func testIndependentIndexHandlesOnlyCommitOneExpectedWatchVersion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("watch-cas-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("cache.sqlite"), master = SymmetricKey(size: .bits256)
    let handles = try (0..<2).map { _ in try AgentIOSWebCacheIndex(url: file, master: master, identity: "watch-fixture", beforeCommit: {}) }
    let old = watch("shared")
    func entry(_ value: AgentIOSWebIntelligenceCacheWatch) throws -> AgentIOSWebCacheIndex.Entry {
      .init(kind: .watch, id: value.id, updated: value.updatedAtMillis, payload: try JSONEncoder().encode(value))
    }
    try handles[0].initialize(allowImport: true) { [try entry(old)] }
    try handles[1].initialize(allowImport: false) { XCTFail("Do not reimport"); return [] }
    let lock = NSLock()
    var results: [Bool] = [], errors: [String] = []
    DispatchQueue.concurrentPerform(iterations: 2) { index in
      do {
        let updated = try XCTUnwrap(AgentIOSWebWatchPolicy.completed(old, hash: String(repeating: index == 0 ? "a" : "b", count: 64), now: 2_000))
        let committed = try handles[index].compareAndPutWatch(entry(updated.watch), expected: old)
        lock.lock(); results.append(committed); lock.unlock()
      } catch { lock.lock(); errors.append(String(describing: error)); lock.unlock() }
    }
    XCTAssertTrue(errors.isEmpty)
    XCTAssertEqual(results.filter { $0 }.count, 1)
    XCTAssertEqual(results.filter { !$0 }.count, 1)
  }

  func testLocalActionsRequireCacheScopeAndValidateIDsWithoutNetwork() throws {
    let fixture = WebWatchFixture()
    defer { fixture.close() }
    let descriptor = try XCTUnwrap(AgentIOSWebIntelligenceNativeToolCatalog.definitions(provider: fixture.provider)
      .first { $0.id == AgentIOSWebIntelligenceNativeToolCatalog.watch }?.descriptor)
    let invocation = AgentNativeToolInvocation(descriptor: descriptor, input: [:], context: .init(), startedAtEpochMillis: 1_000,
      deadlineEpochMillis: 61_000, nowMillis: { 1_000 }, cancellationRequested: { false }, progressReporter: { _, _ in })
    XCTAssertEqual(fixture.provider.invoke(operation: .watch, input: ["action": .string("list")], invocation: invocation).error?.code, "cache_scope_required")
    XCTAssertFalse(FileManager.default.fileExists(atPath: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: fixture.file).path))
    let missing = try fixture.call(["action": .string("remove")], network: false)
    XCTAssertEqual(missing.error?.code, "watch_id_required")
    let invalid = try fixture.call(["action": .string("create"), "url": .string("https://127.0.0.1/private")], network: false)
    XCTAssertEqual(invalid.error?.code, "watch_url_invalid")
    XCTAssertTrue(fixture.graph.inputs.isEmpty)
  }

  private func watch(_ id: String) -> AgentIOSWebIntelligenceCacheWatch {
    .init(id: id, url: "https://watch.test/\(id)", intervalMinutes: 15, enabled: true, lastCheckedAtMillis: 0,
      lastChangedAtMillis: 0, lastSHA256: "", createdAtMillis: 1_000, updatedAtMillis: 1_000)
  }
}

private final class WebWatchClock { var now: Int64 = 1_000 }
private final class WebWatchFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("watch-check-\(UUID()).json")
  let clock: WebWatchClock
  let graph = WatchGraphProvider()
  let cache: AgentIOSWebIntelligenceCacheStore
  let media: AgentIOSWebMediaToolProviding
  init(clock: WebWatchClock = WebWatchClock(), media: AgentIOSWebMediaToolProviding? = nil, beforeCommit: @escaping () throws -> Void = {}) {
    self.clock = clock
    self.media = media ?? graph
    cache = .init(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { clock.now }, beforeCommit: beforeCommit)
  }
  var provider: AgentIOSURLSessionWebIntelligenceProvider {
    .init(webMediaProvider: media, cacheStore: cache, nowMillis: { self.clock.now }, uptimeMillis: { 0 })
  }
  var context: AgentNativeToolInvocationContext {
    .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission, AgentIOSWebIntelligenceNativeToolCatalog.networkPermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent, AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent])
  }
  func call(_ input: AgentMcpJSONObject, network: Bool = true) throws -> AgentNativeToolResult {
    var scope = context
    if !network { scope.grantedPermissions.remove(AgentIOSWebIntelligenceNativeToolCatalog.networkPermission); scope.grantedConsents.remove(AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent) }
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.watch, input: input, context: scope, hooks: .init(nowMillis: { self.clock.now }))
  }
  func close() { graph.afterCall = {}; removeWebCacheFixture(file) }
}

private final class WatchGraphProvider: AgentIOSWebMediaToolProviding {
  let implementationId = "watch-graph-fixture"
  var inputs: [AgentMcpJSONObject] = []
  var failing = Set<String>()
  var afterCall: () -> Void = {}
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject, invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    inputs.append(input)
    defer { afterCall() }
    let url = input["url"]?.stringValue ?? ""
    if failing.contains(URL(string: url)?.path ?? "") { return .failure(code: "fixture_fetch_failed", message: "Injected page failure", retryable: true) }
    return .success(output: ["text": .string("Current readable page content"), "status_code": .int(200), "content_type": .string("text/plain"),
      "html_sha256": .string(String(repeating: "a", count: 64)), "text_decoding_lossless": .bool(true),
      "source": .object(["requested_url": .string(url), "final_url": .string(url)])])
  }
}

private final class WatchNativeTransport: AgentIOSURLSessionWebTransporting {
  private(set) var requests: [AgentIOSURLSessionWebRequest] = []
  var label = "Initial readable public content"
  var afterCall: () -> Void = {}
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    requests.append(request)
    defer { afterCall() }
    let body = "<html><title>Watched page</title><main><p>\(label)</p><p>Additional readable context for native page parsing.</p></main></html>"
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "text/html; charset=utf-8"],
      body: Data(body.utf8), retrievedAtEpochMillis: 1_000)
  }
}
