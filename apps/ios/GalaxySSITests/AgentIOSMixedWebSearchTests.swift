import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSMixedWebSearchTests: XCTestCase {
  typealias Fusion = AgentIOSWebSearchFusion
  typealias Hit = AgentIOSPublicSearchParser.Hit

  func testImageOnlyRoutingUsesDirectParsersAndConfiguredCredentials() {
    let learned = imageSource()
    let automatic = AgentIOSWebIntelligenceQueryRouting.select(query: "alpha", requestedVerticals: [.image],
      requestedEngineIds: [], learnedSources: [learned], fanout: 32)
    XCTAssertEqual(Set(automatic.selected.map(\.id)), ["sogou_image", "duckduckgo_image"])
    let configured = AgentIOSWebIntelligenceQueryRouting.select(query: "alpha", requestedVerticals: [.image],
      requestedEngineIds: [], learnedSources: [learned], fanout: 32, braveImageKeyAvailable: true)
    XCTAssertEqual(Set(configured.selected.map(\.id)), AgentIOSImageSearchRequestPolicy.supported)
    XCTAssertFalse(configured.selected.contains { $0.id == learned.sourceID })
    let explicit = AgentIOSWebIntelligenceQueryRouting.select(query: "alpha", requestedVerticals: [.image],
      requestedEngineIds: [learned.sourceID], learnedSources: [learned])
    XCTAssertEqual(explicit.selected.map(\.id), [learned.sourceID])
  }

  func testMixedRoutingAndExplicitOrderIncludeQualifiedImageTopicSites() {
    let learned = imageSource()
    XCTAssertTrue(learned.isSearchEligible)
    let automatic = AgentIOSWebIntelligenceQueryRouting.select(query: "alpha", requestedVerticals: [.image, .news],
      requestedEngineIds: [], requestedCategories: ["image"], learnedSources: [learned], fanout: 32)
    XCTAssertTrue(automatic.selected.contains { $0.id == learned.sourceID })
    XCTAssertTrue(automatic.selected.contains { $0.vertical == .news })
    XCTAssertTrue(automatic.selected.contains { $0.id == "sogou_image" })
    let explicit = AgentIOSWebIntelligenceQueryRouting.select(query: "alpha", requestedVerticals: [],
      requestedEngineIds: ["github", "brave_image"], requestedEngineOrder: ["github", "brave_image"])
    XCTAssertEqual(explicit.selected.map(\.id), ["github", "brave_image"])
  }

  func testMixedFusionUsesOneConsensusDenominatorAndReferenceImageFormula() throws {
    let page = Hit(title: "alpha", url: "https://text.test/page", excerpt: "alpha")
    let image = imageHit("one", page: "image.test/page")
    let ranked = Fusion.fuse(query: "alpha", groups: [
      .init(sourceID: "text", results: [page]),
      .init(sourceID: "image", results: [image], vertical: .image),
      .init(sourceID: "third", results: [Hit(title: "unrelated", url: "https://third.test/page", excerpt: "")])
    ], limit: 10, nowMillis: 1_000, includeImages: true)
    for result in ranked {
      let score = try XCTUnwrap(result.searchScore)
      XCTAssertEqual(score.consensus, 1.0 / 3, accuracy: 1e-12)
      let web = 0.28 * score.reciprocalRank + 0.21 * score.lexical + 0.14 * score.consensus +
        0.10 * score.authority + 0.07 * score.freshness + 0.20 * score.localModel
      XCTAssertEqual(score.final, result.image == nil ? web : 0.45 * web + 0.55, accuracy: 1e-12)
    }
  }

  func testPageDiversityAppliesOnlyWhenAllCandidatesAreImageVertical() {
    let images = [imageHit("one", page: "shared.test/page"), imageHit("two", page: "shared.test/page"),
      imageHit("three", page: "other.test/page")]
    let pure = Fusion.fuse(query: "alpha", groups: [.init(sourceID: "images", results: images, vertical: .image)],
      limit: 2, nowMillis: 1_000, includeImages: true)
    XCTAssertEqual(Set(pure.map(\.url)).count, 2)
    let mixed = Fusion.fuse(query: "alpha", groups: [
      .init(sourceID: "images", results: images, vertical: .image),
      .init(sourceID: "text", results: [.init(title: "unrelated", url: "https://text.test/page", excerpt: "")])
    ], limit: 2, nowMillis: 1_000, includeImages: true)
    XCTAssertEqual(mixed.map(\.url), ["https://shared.test/page", "https://shared.test/page"])
  }

  func testImageMergeKeepsDimensionsAndDoesNotConvertTopicLinksIntoImages() throws {
    var first = imageHit("one", page: "source.test/page")
    first.image?["width"] = .int(0)
    var second = first
    second.image?["width"] = .int(640)
    second.image?["thumbnail_url"] = .string("https://media.test/preview.jpg")
    let hits = Fusion.fuse(query: "alpha", groups: [
      .init(sourceID: "a", results: [first], vertical: .image), .init(sourceID: "b", results: [second], vertical: .image),
      .init(sourceID: "learned", results: [.init(title: "alpha", url: "https://topic.test/page", excerpt: "alpha")], vertical: .image)
    ], limit: 10, nowMillis: 1_000, includeImages: true)
    XCTAssertEqual(hits.count, 2)
    let media = try XCTUnwrap(hits.first { $0.image != nil })
    XCTAssertEqual(media.image?["width"], .int(640))
    XCTAssertEqual(media.searchEngines, ["a", "b"])
    let topic = try XCTUnwrap(hits.first { $0.image == nil })
    XCTAssertEqual(topic.vertical, "image")
    XCTAssertEqual(topic.retrievalStatus, "image_topic_page_reference")
  }

  func testActualMixedRegistryPreservesTextAndTypedImagesWithIsolatedKeys() throws {
    let transport = MixedSearchTransport(), secrets = InMemorySecretStore()
    try secrets.setString("brave-fixture", account: AgentIOSWebIntelligenceCredentialKey.braveAPIKey.account)
    try secrets.setString("github-fixture", account: AgentIOSWebIntelligenceCredentialKey.githubToken.account)
    let result = try invoke(["github", "brave_image"], transport: transport, secrets: secrets)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.count, 2)
    let rows = (result.output["results"]?.arrayValue ?? []).compactMap(\.objectValue)
    XCTAssertTrue(rows.contains { $0["vertical"] == .string("code") && $0["images"] == nil })
    XCTAssertTrue(rows.contains { $0["vertical"] == .string("image") && $0["lead_image_url"] == .string("https://media.test/alpha.jpg") })
    XCTAssertNotNil(result.metadata["mixed_ranker"])
    for request in transport.requests {
      if request.url.host == "api.search.brave.com" {
        XCTAssertEqual(request.headers["X-Subscription-Token"], "brave-fixture")
        XCTAssertNil(request.headers["Authorization"])
      } else {
        XCTAssertNil(request.headers["X-Subscription-Token"])
      }
    }
    XCTAssertFalse(AgentMcpJSONCodec.stringify(result.output).contains("brave-fixture"))
  }

  func testUnconfiguredImageSourceDoesNotPreventRequestedTextResults() throws {
    let transport = MixedSearchTransport()
    let result = try invoke(["brave_image", "github"], transport: transport, secrets: InMemorySecretStore())
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.url.host, "api.github.com")
    XCTAssertTrue((result.metadata["unavailable_sources"]?.arrayValue ?? []).contains { $0.objectValue?["provider"] == .string("brave_image") })
  }

  func testActualLearnedImageTopicIndexDoesNotInventMediaAndPureImageSkipsIt() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("mixed-learned-\(UUID()).json")
    let operations = OperationQueue()
    defer { operations.waitUntilAllOperationsAreFinished(); try? FileManager.default.removeItem(at: file) }
    let cache = AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 },
      learningQueue: .init(queue: operations))
    for query in ["first alpha", "second alpha", "third alpha"] {
      _ = cache.learnSourceCandidates(query: query, categories: ["image"],
        results: [["url": .string("https://learned-image.example/page"), "vertical": .string("image")]])
    }
    operations.waitUntilAllOperationsAreFinished()
    let learned = try XCTUnwrap(cache.learnedSources()?.first)
    XCTAssertTrue(learned.isSearchEligible)
    let transport = MixedSearchTransport()
    let result = try invoke([learned.sourceID], transport: transport, secrets: InMemorySecretStore(), cache: cache)
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    let row = try XCTUnwrap(result.output["results"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(row["retrieval_status"], .string("image_topic_page_reference"))
    XCTAssertNil(row["images"])
    XCTAssertNil(row["lead_image_url"])
    XCTAssertEqual(result.output["evidence"]?.arrayValue?.first?.objectValue?["retrieval_status"], row["retrieval_status"])
    XCTAssertFalse(AgentIOSWebIntelligenceQueryRouting.select(query: "alpha", requestedVerticals: [.image],
      requestedEngineIds: [], learnedSources: [learned]).selected.contains { $0.id == learned.sourceID })
  }

  private func imageHit(_ name: String, page: String) -> Hit {
    .init(title: "alpha", url: "https://\(page)", excerpt: "alpha",
      image: ["url": .string("https://media.test/\(name).jpg"), "width": .int(320),
        "retrieval_status": .string("search_result_not_downloaded")])
  }
  private func imageSource() -> AgentIOSLearnedWebSource {
    .init(sourceID: AgentIOSWebSourceLearningPolicy.sourceID(host: "learned-image.example", vertical: "image"),
      host: "learned-image.example", vertical: "image", categoryTags: ["image"], status: "verified",
      observations: 4, queryFingerprints: [String(repeating: "a", count: 24), String(repeating: "b", count: 24)],
      firstSeenAtMillis: 1, lastSeenAtMillis: 2)
  }
  private func invoke(_ engines: [String], transport: MixedSearchTransport, secrets: GalaxySSISecretStore,
    cache supplied: AgentIOSWebIntelligenceCacheStore? = nil) throws -> AgentNativeToolResult {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("mixed-search-\(UUID()).json")
    let operations = OperationQueue()
    defer { operations.waitUntilAllOperationsAreFinished(); if supplied == nil { try? FileManager.default.removeItem(at: file) } }
    let cache = supplied ?? AgentIOSWebIntelligenceCacheStore(fileURL: file, secrets: InMemorySecretStore(), nowMillis: { 1_000 },
      learningQueue: .init(queue: operations))
    let media = AgentIOSURLSessionWebMediaToolProvider(transport: transport, sourceHealthStore: supplied,
      imageCredentials: .init(secrets: secrets), nowMillis: { 1_000 })
    let provider = AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache, nowMillis: { 1_000 })
    let registry = try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(provider: provider))
    return registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.search, input: [
      "query": .string("alpha"), "engines": .array(engines.map(AgentMcpJSONValue.string)), "limit": .int(8), "use_cache": .bool(false)
    ], context: .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission,
      AgentIOSWebIntelligenceNativeToolCatalog.cachePermission], grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent,
      AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent]), hooks: .init(nowMillis: { 1_000 }))
  }
}

private final class MixedSearchTransport: AgentIOSURLSessionWebTransporting {
  private let lock = NSLock()
  private var saved: [AgentIOSURLSessionWebRequest] = []
  var requests: [AgentIOSURLSessionWebRequest] { lock.lock(); defer { lock.unlock() }; return saved }
  func execute(_ request: AgentIOSURLSessionWebRequest) throws -> AgentIOSURLSessionWebResponse {
    lock.lock(); saved.append(request); lock.unlock()
    let body: String
    if request.url.host == "api.search.brave.com" {
      body = #"{"results":[{"title":"alpha","url":"https://source.test/page","properties":{"url":"https://media.test/alpha.jpg","width":640,"height":480}}]}"#
    } else if request.url.host == "api.github.com" {
      body = #"{"items":[{"full_name":"alpha repository","html_url":"https://github.com/fixture/alpha","description":"alpha reference content sufficiently long for evidence"}]}"#
    } else {
      body = #"<li class="b_algo"><h2><a href="https://learned-image.example/page">alpha image topic</a></h2><p>alpha source article with no extracted media bytes or image URL</p></li>"#
    }
    return .init(statusCode: 200, finalURL: request.url, headers: ["content-type": request.url.host?.hasPrefix("api.") == true ? "application/json" : "text/html"],
      body: Data(body.utf8), retrievedAtEpochMillis: 1_000)
  }
}
