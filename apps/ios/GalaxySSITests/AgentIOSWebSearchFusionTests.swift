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
    defer { try? FileManager.default.removeItem(at: file) }
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

  func testCachedPublicationIsPreservedButQueryDependentScoreIsNotInvented() throws {
    let transport = TextFusionTransport()
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("fusion-cache-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: file) }
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
    XCTAssertTrue(transport.requests.isEmpty)
    let row = try XCTUnwrap(result.output["results"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(row["published_at"], .string("2025-01-01T00:00:00Z"))
    XCTAssertNil(row["score"])
    XCTAssertEqual(result.metadata["network_attempted"], .bool(false))
  }

  private func makeRegistry(transport: TextFusionTransport, cache: AgentIOSWebIntelligenceCacheStore) throws -> AgentNativeToolRegistry {
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: nil,
      imageCredentials: .init(secrets: InMemorySecretStore()), nowMillis: { self.now })
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
    let json = #"{"items":[{"full_name":"noise unrelated","html_url":"https://github.com/fixture/noise"},{"full_name":"alpha repo","html_url":"https://github.com/fixture/alpha","updated_at":"2026-01-01T00:00:00Z","description":"alpha"}]}"#
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": "application/json"],
      body: Data(json.utf8), retrievedAtEpochMillis: 1_800_000_000_000)
  }
}
