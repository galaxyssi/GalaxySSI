import CryptoKit
import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebSearchFusionTests: XCTestCase {
  private let now: Int64 = 1_800_000_000_000
  private typealias Fusion = AgentIOSWebSearchFusion

  func testSingleHitUsesPinnedNineFeaturesAndSixTermWebScore() throws {
    let hit = AgentIOSPublicSearchParser.Hit(title: "alpha", url: "https://source.test/path", excerpt: "alpha")
    let result = try XCTUnwrap(Fusion.fuse(query: "alpha", groups: [.init(sourceID: "fixture", results: [hit])], limit: 1, nowMillis: now).first)
    let score = try XCTUnwrap(result.searchScore)
    let model = AgentIOSImageSearchFusion.rankerScore([1, 1, 1, 0.5, 0.35, 1, 1, 0.925, 0])
    XCTAssertEqual(score.localModel, model, accuracy: 1e-12)
    XCTAssertEqual(score.final, 0.28 + 0.21 + 0.14 + 0.05 + 0.07 * 0.35 + 0.20 * model, accuracy: 1e-12)
    XCTAssertEqual(result.searchEngines, ["fixture"])
    XCTAssertEqual(score.freshness, 0.35)
  }

  func testCanonicalDuplicatesMergeLongerTextAndCountEachSourceOnlyOnce() throws {
    let first = AgentIOSPublicSearchParser.Hit(title: "alpha", url: "https://www.source.test/a/?utm_source=fixture#one", excerpt: "",
      retrievalStatus: "local_index_reference")
    let second = AgentIOSPublicSearchParser.Hit(title: "alpha longer", url: "https://source.test/a", excerpt: "alpha longer body",
      publishedAt: "2026-01-01T00:00:00Z")
    let groups: [Fusion.Group] = [.init(sourceID: "one", results: [first, first]), .init(sourceID: "two", results: [second])]
    let result = try XCTUnwrap(Fusion.fuse(query: "alpha", groups: groups, limit: 10, nowMillis: now).first)
    XCTAssertEqual(result.url, "https://source.test/a")
    XCTAssertEqual(result.title, second.title)
    XCTAssertEqual(result.excerpt, second.excerpt)
    XCTAssertEqual(result.publishedAt, second.publishedAt)
    XCTAssertEqual(result.searchEngines, ["one", "two"])
    XCTAssertEqual(result.searchScore?.consensus, 1)
    XCTAssertNil(result.retrievalStatus)
    XCTAssertEqual(Fusion.fuse(query: "alpha", groups: groups, limit: 10, nowMillis: now).count, 1)
  }

  func testRelevantTextBeatsEarlierNoiseAndFreshnessCanReorderEquivalentTitles() {
    let noise = AgentIOSPublicSearchParser.Hit(title: "unrelated", url: "https://source.test/noise", excerpt: "")
    let relevant = AgentIOSPublicSearchParser.Hit(title: "alpha", url: "https://source.test/alpha", excerpt: "alpha")
    XCTAssertEqual(Fusion.fuse(query: "alpha", groups: [.init(sourceID: "one", results: [noise, relevant])],
      limit: 2, nowMillis: now).first?.url, relevant.url)
    var old = relevant; old.url = "https://source.test/old"; old.publishedAt = "1970-01-01T00:00:00Z"
    var fresh = relevant; fresh.url = "https://source.test/fresh"; fresh.publishedAt = String(now / 1000)
    XCTAssertEqual(Fusion.fuse(query: "alpha", groups: [.init(sourceID: "one", results: [old, fresh])],
      limit: 2, nowMillis: now).first?.url, fresh.url)
  }

  func testPublicationFreshnessUsesReferenceEpochISOYearAndUnknownPriors() {
    XCTAssertEqual(Fusion.freshness("", nowMillis: now), 0.35)
    XCTAssertEqual(Fusion.freshness("unknown", nowMillis: now), 0.35)
    XCTAssertEqual(Fusion.freshness(String(now), nowMillis: now), 1)
    XCTAssertEqual(Fusion.freshness(String(now / 1000), nowMillis: now), 1)
    let iso = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(now) / 1000))
    XCTAssertEqual(Fusion.freshness(iso, nowMillis: now), 1)
    XCTAssertEqual(Fusion.freshness("1970-01-01T00:00:00Z", nowMillis: now), 0.05)
    let year = Calendar(identifier: .gregorian).component(.year, from: Date(timeIntervalSince1970: Double(now) / 1000))
    XCTAssertEqual(Fusion.freshness("Published " + String(year), nowMillis: now), 1)
    // Android interprets an entirely numeric string as epoch seconds, even a numeric year.
    XCTAssertEqual(Fusion.freshness(String(year), nowMillis: now), 0.05)
  }

  func testInvalidGroupsImagesAndCredentialsDoNotBecomeRankedText() {
    let hit = AgentIOSPublicSearchParser.Hit(title: "alpha", url: "https://source.test/a", excerpt: "")
    var credentialed = hit; credentialed.url = "https://user:pass@source.test/a"
    var image = hit; image.image = ["url": .string("https://source.test/a.jpg")]
    XCTAssertEqual(Fusion.fuse(query: "alpha", groups: [.init(sourceID: "bad", results: [hit], weight: .nan),
      .init(sourceID: "one", results: [credentialed, image])], limit: 2, nowMillis: now), [])
    XCTAssertEqual(Fusion.fuse(query: "alpha", groups: [.init(sourceID: "one", results: [hit])], limit: 0, nowMillis: now), [])
    XCTAssertEqual(Fusion.group(sourceID: "bing", results: []).weight, 1.05)
    XCTAssertEqual(Fusion.group(sourceID: "bing_news", results: []).weight, 1.1)
    XCTAssertEqual(Fusion.group(sourceID: "learned_fixture", results: []).authority, 0.5)
  }

  func testActualRegistryRanksWithinOneProviderAndPreservesScoreAndPublication() throws {
    let transport = TextFusionTransport()
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("fusion-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { self.now })
    let registry = try makeRegistry(transport: transport, cache: cache)
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("alpha"), "engines": .array([.string("github")]), "limit": .int(2)],
      context: context(), hooks: .init(nowMillis: { self.now }))
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    let row = try XCTUnwrap(result.output["results"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(row["url"], .string("https://github.com/fixture/alpha"))
    XCTAssertNotNil(row["score"]?.objectValue?["final"])
    XCTAssertEqual(row["engines"], .array([.string("github")]))
    XCTAssertEqual(row["published_at"], .string("2026-01-01T00:00:00Z"))
    XCTAssertEqual(result.output["evidence"]?.arrayValue?.first?.objectValue?["published_at"], row["published_at"])
    XCTAssertEqual(result.metadata["text_ranker"], .string(Fusion.modelID))
    XCTAssertEqual(transport.requests.count, 1)
  }

  func testCachedPublicationIsPreservedInDocumentButNotReusedForAnotherSearch() throws {
    let transport = TextFusionTransport()
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("fusion-cache-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { self.now })
    let content = "alpha cached summary"
    let hash = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    XCTAssertTrue(cache.putDocuments([.init(url: "https://source.test/alpha", title: "alpha", content: content,
      contentType: "text/x-galaxyssi-search-result", contentSHA256: hash, retrievedAtMillis: now, expiresAtMillis: now + 60_000,
      links: [], metadata: ["source": "web_search", "published_at": "2025-01-01T00:00:00Z"])]))
    let registry = try makeRegistry(transport: transport, cache: cache)
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: ["query": .string("alpha"), "use_cache": .bool(true), "limit": .int(1)], context: context(cache: true),
      hooks: .init(nowMillis: { self.now }))
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertFalse(transport.requests.isEmpty)
    let row = try XCTUnwrap(result.output["results"]?.arrayValue?.first?.objectValue)
    XCTAssertNotEqual(row["url"], .string("https://source.test/alpha"))
    XCTAssertNil(row["published_at"])
    XCTAssertNotNil(row["score"])
    XCTAssertEqual(cache.document(url: "https://source.test/alpha")?.metadata["published_at"], "2025-01-01T00:00:00Z")
    XCTAssertEqual(result.metadata["network_attempted"], .bool(true))
  }

  func testExactResponseCachePreservesScoresAndReceiptsWithoutAnotherRequest() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("exact-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let secrets = InMemorySecretStore()
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: secrets, nowMillis: { self.now })
    let transport = TextFusionTransport()
    let registry = try makeRegistry(transport: transport, cache: cache)
    let input: AgentMcpJSONObject = ["query": .string("alpha"), "engines": .array([.string("github")]), "limit": .int(1)]
    let first = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input,
      context: context(cache: true), hooks: .init(nowMillis: { self.now }))
    let second = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input,
      context: context(cache: true), hooks: .init(nowMillis: { self.now }))
    XCTAssertTrue(first.isSuccess)
    XCTAssertTrue(second.isSuccess)
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(second.metadata["cache_hit"], .bool(true))
    XCTAssertEqual(second.metadata["network_attempted"], .bool(false))
    XCTAssertEqual(second.metadata["response_cache_original_receipts"], .bool(true))
    XCTAssertEqual(second.output["results"], first.output["results"])
    XCTAssertEqual(second.output["source_receipts"], first.output["source_receipts"])
    XCTAssertFalse(String(decoding: try Data(contentsOf: AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: file)), as: UTF8.self).contains("fixture/alpha"))
    XCTAssertEqual(AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: secrets,
      nowMillis: { self.now }).stats()["search_count"], .int(1))
  }

  func testExactSearchIdentitySeparatesQueryProfileFanoutAndTopics() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("identity-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { self.now })
    let transport = TextFusionTransport(), registry = try makeRegistry(transport: transport, cache: cache)
    let base: AgentMcpJSONObject = ["query": .string("alpha"), "engines": .array([.string("github")]), "limit": .int(1)]
    let variations: [AgentMcpJSONObject] = [[:], ["query": .string("beta")], ["limit": .int(2)],
      ["profile": .string("fast")], ["engine_fanout": .int(2)], ["categories": .array([.string("code")])],
      ["verticals": .array([.string("code")])]]
    for changes in variations {
      let before = transport.requests.count
      let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
        input: base.merging(changes) { _, next in next }, context: context(cache: true), hooks: .init(nowMillis: { self.now }))
      XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
      XCTAssertEqual(transport.requests.count, before + 1)
      XCTAssertEqual(result.metadata["cache_hit"], .bool(false))
    }
    let invalidImage = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: base.merging(["verticals": .array([.string("image")])]) { _, next in next },
      context: context(cache: true), hooks: .init(nowMillis: { self.now }))
    XCTAssertFalse(invalidImage.isSuccess)
  }

  func testForcedRefreshUnconsentedSearchAndCredentialRotationDoNotHitOldResponse() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("fresh-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { self.now })
    let credentials = InMemorySecretStore(), transport = TextFusionTransport()
    let registry = try makeRegistry(transport: transport, cache: cache, credentials: credentials)
    let input: AgentMcpJSONObject = ["query": .string("alpha"), "engines": .array([.string("github")]), "limit": .int(1)]
    _ = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input,
      context: context(cache: true), hooks: .init(nowMillis: { self.now }))
    let refresh = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search,
      input: input.merging(["use_cache": .bool(false)]) { _, next in next },
      context: context(cache: true), hooks: .init(nowMillis: { self.now }))
    XCTAssertEqual(refresh.metadata["cache_hit"], .bool(false))
    let unscoped = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input,
      context: context(), hooks: .init(nowMillis: { self.now }))
    XCTAssertEqual(unscoped.metadata["cache_hit"], .bool(false))
    XCTAssertNil(unscoped.output["cache"]?.objectValue?["search_count"])
    try credentials.setString("changed-fixture-token", account: AgentIOSWebIntelligenceCredentialKey.githubToken.account)
    _ = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: input,
      context: context(cache: true), hooks: .init(nowMillis: { self.now }))
    XCTAssertEqual(transport.requests.count, 4)
    XCTAssertEqual(cache.stats()["search_count"], .int(2))
  }

  func testSearchResponseExpiryAndClearInvalidateInFlightGeneration() throws {
    var clock: Int64 = 1_000
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("expiry-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { clock })
    let key = String(repeating: "a", count: 64), response = cachedFixture()
    XCTAssertTrue(cache.putSearchResponse(key: key, result: response, ttlMillis: 60_000))
    XCTAssertNotNil(cache.searchResponse(key: key))
    clock = 61_001
    XCTAssertNil(cache.searchResponse(key: key))
    XCTAssertEqual(cache.clear(expiredOnly: true)["searches_removed"], .int(1))
    let generation = cache.searchCacheGeneration()
    XCTAssertEqual(cache.clear(expiredOnly: false)["committed"], .bool(true))
    XCTAssertFalse(cache.putSearchResponse(key: key, result: response, ttlMillis: 60_000, expectedGeneration: generation))
    XCTAssertNil(cache.searchResponse(key: key))
  }

  func testSearchResponseBoundsRejectEmptyFailedAndRetainLargeEntries() throws {
    var clock: Int64 = 1_000
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("bounds-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { clock })
    for index in 0..<33 {
      clock += 1
      let key = String(repeating: "a", count: 62) + String(format: "%02x", index)
      XCTAssertTrue(cache.putSearchResponse(key: key, result: cachedFixture(), ttlMillis: 60_000))
    }
    XCTAssertEqual(cache.stats()["search_count"], .int(33))
    XCTAssertNotNil(cache.searchResponse(key: String(repeating: "a", count: 62) + "00"))
    let key = String(repeating: "b", count: 64)
    XCTAssertFalse(cache.putSearchResponse(key: key, result: .failure(code: "failed", message: "fixture"), ttlMillis: 60_000))
    XCTAssertFalse(cache.putSearchResponse(key: key, result: .success(), ttlMillis: 60_000))
    var oversized = cachedFixture()
    oversized.output["padding"] = .string(String(repeating: "x", count: 4_200_000))
    XCTAssertTrue(cache.putSearchResponse(key: key, result: oversized, ttlMillis: 60_000))
    XCTAssertEqual(cache.searchResponse(key: key)?.output, oversized.output)
  }

  func testSearchResponseMultibytePayloadIsNotCappedByOldEncodedByteLimit() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("unicode-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 })
    let key = String(repeating: "c", count: 64)
    var response = cachedFixture()
    let text = String(repeating: "\u{1F680}", count: 600_000)
    XCTAssertEqual(text.utf8.count, 2_400_000)
    response.output["padding"] = .string(text)
    XCTAssertTrue(cache.putSearchResponse(key: key, result: response, ttlMillis: 60_000))
    XCTAssertEqual(cache.searchResponse(key: key)?.output, response.output)
  }

  func testLargeResponseFailedReplacementPreservesPriorDataAndGeneration() throws {
    var reject = false
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("large-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 },
      beforeCommit: { if reject { throw CocoaError(.fileWriteOutOfSpace) } })
    let key = String(repeating: "d", count: 64)
    var original = cachedFixture(); original.output["padding"] = .string(String(repeating: "x", count: 4_200_000))
    XCTAssertTrue(cache.putSearchResponse(key: key, result: original, ttlMillis: 60_000))
    let generation = cache.searchCacheGeneration()
    var replacement = original; replacement.output["padding"] = .string(String(repeating: "y", count: 4_300_000))
    reject = true
    XCTAssertFalse(cache.putSearchResponse(key: key, result: replacement, ttlMillis: 60_000))
    XCTAssertEqual(cache.searchCacheGeneration(), generation)
    XCTAssertEqual(cache.searchResponse(key: key)?.output, original.output)
  }

  func testSearchResponseFailedWriteAndCorruptReadDoNotErasePriorData() throws {
    var reject = false
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("failure-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 },
      beforeCommit: {
        if reject { throw CocoaError(.fileWriteOutOfSpace) }
      })
    let key = String(repeating: "a", count: 64)
    XCTAssertTrue(cache.putSearchResponse(key: key, result: cachedFixture(), ttlMillis: 60_000))
    let index = AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: file)
    let original = try Data(contentsOf: index)
    reject = true
    XCTAssertFalse(cache.putSearchResponse(key: String(repeating: "b", count: 64), result: cachedFixture(), ttlMillis: 60_000))
    XCTAssertEqual(try Data(contentsOf: index), original)
    XCTAssertNotNil(cache.searchResponse(key: key))
    let corrupt = Data("not-an-envelope".utf8)
    try corrupt.write(to: index)
    reject = false
    XCTAssertNil(cache.searchResponse(key: key))
    XCTAssertFalse(cache.putSearchResponse(key: key, result: cachedFixture(), ttlMillis: 60_000))
    XCTAssertEqual(try Data(contentsOf: index), corrupt)
  }

  func testLegacySnapshotWithoutSearchResponsesRemainsReadableAndRetained() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-response-\(UUID()).json")
    defer { removeWebCacheFixture(file) }
    let secrets = InMemorySecretStore(), key = SymmetricKey(size: .bits256)
    try secrets.setString(key.withUnsafeBytes { Data($0) }.base64EncodedString(), account: AgentIOSWebIntelligenceCacheStore.keyAccount)
    let sealed = try AES.GCM.seal(Data(#"{"version":1,"documents":[],"watches":[]}"#.utf8), using: key)
    let envelope: [String: Any] = ["version": 1, "nonce": sealed.nonce.withUnsafeBytes { Data($0) }.base64EncodedString(),
      "ciphertext": sealed.ciphertext.base64EncodedString(), "tag": sealed.tag.base64EncodedString()]
    try JSONSerialization.data(withJSONObject: envelope).write(to: file)
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: secrets, nowMillis: { 1_000 })
    XCTAssertEqual(cache.stats()["available"], .bool(true))
    XCTAssertEqual(cache.stats()["search_count"], .int(0))
    let id = String(repeating: "a", count: 64)
    XCTAssertTrue(cache.putSearchResponse(key: id, result: cachedFixture(), ttlMillis: 60_000))
    XCTAssertEqual(cache.searchResponse(key: id), cachedFixture())
  }

  private func cachedFixture() -> AgentNativeToolExecutionResult {
    .success(output: ["results": .array([.object(["url": .string("https://source.test/a"),
      "images": .array([.object(["url": .string("https://media.test/a.jpg")])]),
      "score": .object(["final": .double(0.75)])])])])
  }

  private func makeRegistry(transport: TextFusionTransport, cache: AgentIOSWebIntelligenceCacheStore,
    credentials: GalaxySSISecretStore = InMemorySecretStore()) throws -> AgentNativeToolRegistry {
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil,
      imageCredentials: .init(secrets: credentials), nowMillis: { self.now })
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache, nowMillis: { self.now })
    return try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
  }
  private func context(cache: Bool = false) -> AgentNativeToolInvocationContext {
    .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission] +
      (cache ? [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission] : []),
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent] +
      (cache ? [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent] : []))
  }
}

private final class TextFusionTransport: AgentIOSURLSessionWebTransporting {
  private let lock = NSLock()
  private var saved: [AgentIOSURLSessionWebRequest] = []
  var requests: [AgentIOSURLSessionWebRequest] { lock.lock(); defer { lock.unlock() }; return saved }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock(); saved.append(request); lock.unlock()
    if request.url.host == "api2.marginalia-search.com" {
      return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "application/json"],
        body: Data(#"{"results":[{"title":"alpha","url":"https://fresh.example/alpha","description":"alpha source excerpt"}]}"#.utf8),
        retrievedAtEpochMillis: 1_800_000_000_000)
    }
    let json = #"{"items":[{"full_name":"noise unrelated","html_url":"https://github.com/fixture/noise"},{"full_name":"alpha repo","html_url":"https://github.com/fixture/alpha","updated_at":"2026-01-01T00:00:00Z","description":"alpha"}]}"#
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "application/json"],
      body: Data(json.utf8), retrievedAtEpochMillis: 1_800_000_000_000)
  }
}
