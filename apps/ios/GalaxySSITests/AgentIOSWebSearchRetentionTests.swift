import CryptoKit
import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebSearchRetentionTests: XCTestCase {
  func testFacadeRetainsNinetySixKeysAcrossReopenAndReplacement() throws {
    let fixture = SearchRetentionFixture()
    defer { fixture.close() }
    let first = fixture.cache()
    for number in 0..<96 {
      XCTAssertTrue(first.putSearchResponse(key: key(number), result: response("row-\(number)"), ttlMillis: 60_000))
    }
    let reopened = fixture.cache()
    XCTAssertEqual(reopened.cacheMetadata()["search_count"], .int(96))
    for number in 0..<96 { XCTAssertEqual(reopened.searchResponse(key: key(number)), response("row-\(number)")) }
    XCTAssertTrue(reopened.putSearchResponse(key: key(0), result: response("replacement"), ttlMillis: 60_000))
    XCTAssertEqual(first.searchResponse(key: key(0)), response("replacement"))
    XCTAssertEqual(first.cacheMetadata()["search_count"], .int(96))
  }

  func testEqualityExpiryBoundaryAndExplicitCleanupMatchReference() throws {
    let fixture = SearchRetentionFixture()
    defer { fixture.close() }
    let cache = fixture.cache(), original = response("equal")
    XCTAssertTrue(cache.putSearchResponse(key: key(0), result: original, ttlMillis: 60_000))
    let generation = cache.searchCacheGeneration()
    fixture.now = 61_000
    XCTAssertEqual(cache.searchResponse(key: key(0)), original)
    XCTAssertEqual(cache.clear(expiredOnly: true)["searches_removed"], .int(0))
    fixture.now += 1
    XCTAssertNil(cache.searchResponse(key: key(0)))
    XCTAssertTrue(cache.putSearchResponse(key: key(1), result: response("new"), ttlMillis: 60_000))
    XCTAssertEqual(cache.cacheMetadata()["search_count"], .int(2), "Unrelated writes do not silently reclaim expired rows")
    XCTAssertEqual(cache.clear(expiredOnly: true)["searches_removed"], .int(1))
    XCTAssertEqual(cache.cacheMetadata()["search_count"], .int(1))
    XCTAssertEqual(cache.searchCacheGeneration(), generation)
    XCTAssertNotNil(cache.searchResponse(key: key(1)))
  }

  func testFailedWriteAndClearRetainAllKeysAndGeneration() throws {
    let fixture = SearchRetentionFixture()
    defer { fixture.close() }
    var reject = false
    let cache = fixture.cache(beforeCommit: { if reject { throw CocoaError(.fileWriteOutOfSpace) } })
    for number in 0..<40 { XCTAssertTrue(cache.putSearchResponse(key: key(number), result: response("old"), ttlMillis: 60_000)) }
    let generation = cache.searchCacheGeneration()
    reject = true
    XCTAssertFalse(cache.putSearchResponse(key: key(0), result: response("lost"), ttlMillis: 60_000))
    XCTAssertFalse(cache.putSearchResponse(key: key(40), result: response("new"), ttlMillis: 60_000))
    XCTAssertEqual(cache.clear(expiredOnly: false)["committed"], .bool(false))
    XCTAssertEqual(cache.searchCacheGeneration(), generation)
    XCTAssertEqual(cache.cacheMetadata()["search_count"], .int(40))
    XCTAssertEqual(cache.searchResponse(key: key(0)), response("old"))
    XCTAssertNil(cache.searchResponse(key: key(40)))
    reject = false
    XCTAssertEqual(cache.clear(expiredOnly: false)["searches_removed"], .int(40))
    XCTAssertFalse(cache.putSearchResponse(key: key(0), result: response("stale"), ttlMillis: 60_000, expectedGeneration: generation))
    XCTAssertEqual(cache.cacheMetadata()["search_count"], .int(0))
  }

  func testIndexedCountsAndPointLookupSupportMoreThanTwoThousandSearchKeys() throws {
    let fixture = SearchRetentionFixture()
    defer { fixture.close() }
    var decodes = 0
    let index = try AgentIOSWebCacheIndex(url: fixture.file.deletingLastPathComponent().appendingPathComponent("index.sqlite"),
      master: SymmetricKey(size: .bits256), identity: "retention", beforeCommit: {}, didDecode: { decodes += 1 })
    try index.initialize(allowImport: true) { [] }
    let generation = try index.generation()
    for number in 0..<2_005 {
      try index.putSearch(.init(kind: .search, id: key(number), updated: 1_000, expires: 61_000, payload: Data("bounded fixture".utf8)),
        now: 1_000, expected: generation)
    }
    XCTAssertEqual(try index.metadata(now: 1_000)["search_count"], .int(2_005))
    XCTAssertEqual(decodes, 0)
    XCTAssertEqual(try index.entry(.search, id: key(0))?.id, key(0))
    XCTAssertEqual(try index.entry(.search, id: key(2_004))?.id, key(2_004))
    XCTAssertEqual(decodes, 2, "Point lookup does not scan all search payloads")
    XCTAssertEqual(try index.clear(expiredOnly: true, now: 61_000).searches, 0)
    XCTAssertEqual(try index.clear(expiredOnly: true, now: 61_001).searches, 2_005)
  }

  func testAuthenticatedRowAndInnerResponseTimestampsMustAgree() throws {
    let fixture = SearchRetentionFixture()
    defer { fixture.close() }
    let cache = fixture.cache(), value = response("valid")
    XCTAssertTrue(cache.putSearchResponse(key: key(0), result: value, ttlMillis: 60_000))
    let encoded = try XCTUnwrap(try fixture.secrets.string(account: AgentIOSWebIntelligenceCacheStore.keyAccount))
    let master = SymmetricKey(data: try XCTUnwrap(Data(base64Encoded: encoded)))
    let database = AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: fixture.file)
    let relative = fixture.file.standardizedFileURL.pathComponents.dropFirst(FileManager.default.temporaryDirectory.standardizedFileURL.pathComponents.count)
    let index = try AgentIOSWebCacheIndex(url: database, master: master, identity: "temporary:" + relative.joined(separator: "/"), beforeCommit: {})
    try index.initialize(allowImport: false) { XCTFail("Existing index only"); return [] }
    let original = try XCTUnwrap(index.entry(.search, id: key(0)))
    for changeExpiry in [false, true] {
      var mismatch = original
      if changeExpiry { mismatch.expires += 1 } else { mismatch.updated += 1 }
      try index.transaction { try index.put(mismatch) }
      XCTAssertNil(cache.searchResponse(key: key(0)))
    }
    try index.transaction { try index.put(original) }
    XCTAssertEqual(cache.searchResponse(key: key(0)), value)
  }

  func testInvalidResponsesStillDoNotReplaceRetainedData() throws {
    let fixture = SearchRetentionFixture()
    defer { fixture.close() }
    let cache = fixture.cache(), value = response("valid")
    XCTAssertTrue(cache.putSearchResponse(key: key(0), result: value, ttlMillis: 60_000))
    var tooMany = value
    tooMany.output["results"] = .array(Array(repeating: .object(["title": .string("row")]), count: 101))
    for invalid in [AgentNativeToolExecutionResult.success(), .failure(code: "failed", message: "fixture"), tooMany] {
      XCTAssertFalse(cache.putSearchResponse(key: key(0), result: invalid, ttlMillis: 60_000))
      XCTAssertEqual(cache.searchResponse(key: key(0)), value)
    }
    XCTAssertEqual(cache.cacheMetadata()["search_count"], .int(1))
  }

  private func key(_ value: Int) -> String { String(format: "%064x", value) }
  private func response(_ title: String) -> AgentNativeToolExecutionResult {
    .success(output: ["results": .array([.object(["title": .string(title), "url": .string("https://retention.test/page")])])])
  }
}

private final class SearchRetentionFixture {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent("search-retention-\(UUID())", isDirectory: true).appendingPathComponent("cache.json")
  let secrets = InMemorySecretStore()
  var now: Int64 = 1_000
  func cache(beforeCommit: @escaping () throws -> Void = {}) -> AgentIOSWebIntelligenceCacheStore {
    .init(fileURL: file, secrets: secrets, nowMillis: { self.now }, beforeCommit: beforeCommit)
  }
  func close() {
    removeWebCacheFixture(file)
    try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }
}
