import CryptoKit
import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebFeatureHashTests: XCTestCase {
  private let embedder = AgentIOSWebFeatureHashEmbedder.standard

  func testJDKReferenceSparseFloatBitsIncludeUTF16AndMalformedBoundaryCases() {
    let expected: [String: [Int: UInt32]] = [
      "empty": [],
      "ascii": [16: 1052869776, 30: 3200353424, 33: 1052869776, 80: 1052869776, 152: 1052869776, 153: 3200353424, 169: 3200353424],
      "repeat": [16: 1056964608, 30: 3204448256, 80: 1056964608, 153: 3204448256],
      "compat": [182: 1065353216],
      "cjk": [39: 3202677038, 62: 1055193390, 105: 1055193390, 109: 3202677038, 121: 1055193390],
      "supplementary": [109: 1060439284, 171: 3207922932],
      "whitespace": [14: 3201369580, 61: 1053885932, 114: 3201369580, 116: 1053885932, 149: 3201369580, 164: 3201369580],
      "bounded": [162: 1060439284, 164: 3207922932]
    ]
    let texts = ["empty": "", "ascii": "alpha beta", "repeat": "alpha alpha",
      "compat": "\u{ff21}\u{ff29} \u{212a}", "cjk": "\u{4f60}\u{597d}\u{4e16}\u{754c}",
      "supplementary": "a\u{1f600}b", "whitespace": "ab\u{0085}cd\u{001c}ef"]
    for (label, wanted) in expected {
      let vector = label == "bounded"
        ? embedder.embedDocument(title: "", content: "ab\u{1f600}", bodyLimit: 3)
        : embedder.embed(texts[label] ?? "")
      let actual = Dictionary(uniqueKeysWithValues: vector.enumerated().filter { $0.element != 0 }.map { ($0.offset, $0.element.bitPattern) })
      XCTAssertEqual(actual, wanted, label)
      XCTAssertEqual(vector.count, 192)
    }
  }

  func testCosineNormalizationDimensionsAndZeroInputs() {
    let vector = embedder.embed("alpha beta")
    XCTAssertEqual(embedder.cosine(vector, vector), 1, accuracy: 0.000001)
    XCTAssertEqual(embedder.cosine([], []), 0)
    XCTAssertEqual(embedder.cosine(vector, [1]), 0)
    XCTAssertEqual(embedder.cosine([.nan], [1]), 0)
    XCTAssertEqual(embedder.embed(""), [Float](repeating: 0, count: 192))
    XCTAssertEqual(embedder.embed("\u{ff21}\u{ff29}"), embedder.embed("ai"))
    let custom = AgentIOSWebFeatureHashEmbedder(dimensions: 32)
    XCTAssertEqual(custom.embed("alpha").count, 32)
    XCTAssertEqual(custom.modelID, "galaxyssi-feature-hash-32-v1")
  }

  func testDocumentEmbeddingCutsUTF16BodyWithoutReadingBeyondBound() {
    XCTAssertEqual(embedder.embedDocument(title: "Title", content: "abcdef", bodyLimit: 3), embedder.embed("Title\nabc"))
    XCTAssertEqual(embedder.embedDocument(title: "Title", content: "abcXYZ", bodyLimit: 3),
      embedder.embedDocument(title: "Title", content: "abc123", bodyLimit: 3))
  }

  func testEncryptedDocumentVectorsPersistAndDoNotAppearInPublicProjection() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let secrets = InMemorySecretStore(), cache = makeCache(url, secrets)
    XCTAssertTrue(cache.putDocument(url: "https://source.test/a", title: "alpha", content: "beta",
      contentType: "text/plain", contentSHA256: "fixture", retrievedAtMillis: 1, expiresAtMillis: 2))
    let document = try XCTUnwrap(cache.document(url: "https://source.test/a", allowStale: true))
    XCTAssertEqual(document.vector, embedder.embedDocument(title: "alpha", content: "beta"))
    XCTAssertEqual(document.embeddingModelID, embedder.modelID)
    XCTAssertNil(document.value()["vector"])
    XCTAssertNil(document.value()["embeddingModelID"])
    let restored = makeCache(url, secrets)
    XCTAssertEqual(restored.document(url: document.url, allowStale: true)?.vector, document.vector)
    XCTAssertFalse(String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("feature-hash"))
  }

  func testLegacyDocumentsReembedWithoutMutatingReadSnapshot() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let secrets = InMemorySecretStore(), key = SymmetricKey(size: .bits256)
    try secrets.setString(key.withUnsafeBytes { Data($0) }.base64EncodedString(), account: AgentIOSWebIntelligenceCacheStore.keyAccount)
    let document = AgentIOSWebIntelligenceCacheDocument(url: "https://source.test/legacy", title: "alpha",
      content: "beta", contentType: "text/plain", contentSHA256: "fixture", retrievedAtMillis: 1,
      expiresAtMillis: 2, links: [], metadata: [:])
    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    raw.removeValue(forKey: "vector"); raw.removeValue(forKey: "embeddingModelID")
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "documents": [raw], "watches": []])
    let sealed = try AES.GCM.seal(data, using: key)
    let envelope: [String: Any] = ["version": 1, "nonce": sealed.nonce.withUnsafeBytes { Data($0) }.base64EncodedString(),
      "ciphertext": sealed.ciphertext.base64EncodedString(), "tag": sealed.tag.base64EncodedString()]
    try JSONSerialization.data(withJSONObject: envelope).write(to: url)
    let original = try Data(contentsOf: url), cache = makeCache(url, secrets)
    let match = try XCTUnwrap(cache.similarDocuments(query: "alpha beta", limit: 1).first)
    XCTAssertGreaterThan(match.score, 0.5)
    XCTAssertEqual(match.document.url, document.url)
    XCTAssertNil(match.document.vector)
    XCTAssertEqual(try Data(contentsOf: url), original)
  }

  func testSimilarityKeepsNoOverlapCandidatesAndExcludesRequestedURL() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let cache = makeCache(url, InMemorySecretStore())
    for index in 0..<3 {
      XCTAssertTrue(cache.putDocument(url: "https://source.test/\(index)", title: "entry \(index)",
        content: "stored body", contentType: "text/plain", contentSHA256: "fixture",
        retrievedAtMillis: Int64(index), expiresAtMillis: 2))
    }
    let matches = cache.similarDocuments(query: "", limit: 10, excludingURL: "https://source.test/1")
    XCTAssertEqual(matches.map(\.document.url), ["https://source.test/2", "https://source.test/0"])
    XCTAssertTrue(matches.allSatisfy { $0.score == 0.5 })
  }

  func testActualRegistryLocalSimilarityUsesVectorsAndReportsModelWithoutNetwork() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let cache = makeCache(url, InMemorySecretStore())
    XCTAssertTrue(cache.putDocument(url: "https://source.test/a", title: "alpha", content: "beta",
      contentType: "text/plain", contentSHA256: "fixture", retrievedAtMillis: 1, expiresAtMillis: 2))
    let media = FeatureHashMediaFixture(), registry = try makeRegistry(cache, media)
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.findSimilar,
      input: ["query": .string("alpha beta"), "search_web": .bool(false)],
      context: context(), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertTrue(result.isSuccess, result.error?.message ?? "")
    let row = try XCTUnwrap(result.output["results"]?.arrayValue?.first?.objectValue)
    XCTAssertEqual(row["engines"], .array([.string("local_cache")]))
    XCTAssertEqual(row["vertical"], .string("local"))
    XCTAssertGreaterThan(row["score"]?.objectValue?["final"]?.doubleForSchema ?? 0, 0.5)
    XCTAssertEqual(result.metadata["embedding_model"], .string(embedder.modelID))
    XCTAssertTrue(media.inputs.isEmpty)
    XCTAssertEqual(row["cache_document_retrieved_at_millis"], .int(1))
  }

  func testURLSelectionOverridesQueryAndSparseFallbackKeepsReceiptsAndDeduplicates() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let cache = makeCache(url, InMemorySecretStore())
    for name in ["origin", "related"] {
      XCTAssertTrue(cache.putDocument(url: "https://source.test/\(name)", title: "alpha", content: "beta",
        contentType: "text/plain", contentSHA256: "fixture", retrievedAtMillis: 1, expiresAtMillis: 2))
    }
    let media = FeatureHashMediaFixture(), registry = try makeRegistry(cache, media)
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.findSimilar,
      input: ["url": .string("https://source.test/origin"), "query": .string("ignored unrelated"),
        "limit": .int(4), "search_web": .bool(true)], context: context(), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(media.inputs.count, 1)
    XCTAssertEqual(media.inputs.first?["engine_fanout"], .int(12))
    XCTAssertEqual(result.output["query"], .string("alpha\nbeta"))
    let urls = (result.output["results"]?.arrayValue ?? []).compactMap { $0.objectValue?["url"]?.stringValue }
    XCTAssertFalse(urls.contains("https://source.test/origin"))
    XCTAssertEqual(Set(urls).count, urls.count)
    XCTAssertEqual(urls.count, 2)
    XCTAssertFalse((result.output["receipts"]?.arrayValue ?? []).isEmpty)
  }

  func testActualCacheQueryUsesSameLocalCosineScoresAndRejectsEmptyQuery() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let cache = makeCache(url, InMemorySecretStore())
    XCTAssertTrue(cache.putDocument(url: "https://source.test/a", title: "alpha", content: "beta",
      contentType: "text/plain", contentSHA256: "fixture", retrievedAtMillis: 1, expiresAtMillis: 2))
    let media = FeatureHashMediaFixture(), registry = try makeRegistry(cache, media)
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("query"), "query": .string("alpha beta")],
      context: context(), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertTrue(result.isSuccess)
    let row = try XCTUnwrap(result.output["results"]?.arrayValue?.first?.objectValue)
    XCTAssertGreaterThan(row["score"]?.objectValue?["final"]?.doubleForSchema ?? 0, 0.5)
    XCTAssertEqual(result.output["documents"], .array([]))
    XCTAssertTrue(media.inputs.isEmpty)
    let empty = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.cache,
      input: ["action": .string("query")], context: context(), hooks: .init(nowMillis: { 1_000 }))
    XCTAssertEqual(empty.error?.code, "invalid_query")
  }

  func testCacheOnlyScopeCannotFetchUncachedURLOrRunOptionalSearch() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let cache = makeCache(url, InMemorySecretStore())
    XCTAssertTrue(cache.putDocument(url: "https://source.test/local", title: "alpha", content: "beta",
      contentType: "text/plain", contentSHA256: "fixture", retrievedAtMillis: 1, expiresAtMillis: 2))
    let media = FeatureHashMediaFixture(), registry = try makeRegistry(cache, media)
    let localOnly = AgentNativeToolInvocationContext(
      grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])
    let result = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.findSimilar,
      input: ["query": .string("alpha beta"), "search_web": .bool(true)],
      context: localOnly, hooks: .init(nowMillis: { 1_000 }))
    XCTAssertTrue(result.isSuccess)
    XCTAssertEqual(result.metadata["network_attempted"], .bool(false))
    XCTAssertEqual(result.metadata["network_fallback_skipped"], .string("public_web_scope_required"))
    let missing = registry.invoke(AgentIOSWebIntelligenceNativeToolCatalog.findSimilar,
      input: ["url": .string("https://source.test/missing")], context: localOnly, hooks: .init(nowMillis: { 1_000 }))
    XCTAssertEqual(missing.error?.code, "public_web_scope_required")
    XCTAssertTrue(media.inputs.isEmpty)
  }

  private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("feature-hash-\(UUID()).json")
  }
  private func makeCache(_ url: URL, _ secrets: GalaxySSISecretStore) -> AgentIOSWebIntelligenceCacheStore {
    .init(fileURL: url, secrets: secrets, nowMillis: { 1_000 })
  }
  private func context() -> AgentNativeToolInvocationContext {
    .init(grantedPermissions: [AgentIOSWebIntelligenceNativeToolCatalog.networkPermission, AgentIOSWebIntelligenceNativeToolCatalog.cachePermission],
      grantedConsents: [AgentIOSWebIntelligenceNativeToolCatalog.publicWebConsent, AgentIOSWebIntelligenceNativeToolCatalog.cacheConsent])
  }
  private func makeRegistry(_ cache: AgentIOSWebIntelligenceCacheStore, _ media: FeatureHashMediaFixture) throws -> AgentNativeToolRegistry {
    try AgentNativeToolRegistry().registerExecutables(AgentPhoneNativeToolCatalog.webIntelligenceExecutableDefinitions(
      provider: AgentIOSURLSessionWebIntelligenceProvider(webMediaProvider: media, cacheStore: cache, nowMillis: { 1_000 })))
  }
}

private final class FeatureHashMediaFixture: AgentIOSWebMediaToolProviding {
  let implementationId = "fixture.feature_hash_media"
  var inputs: [AgentMcpJSONObject] = []
  func availability(operation: AgentIOSWebMediaOperation) -> AgentNativeToolAvailability { .available }
  func invoke(operation: AgentIOSWebMediaOperation, input: AgentMcpJSONObject,
    invocation: AgentNativeToolInvocation) -> AgentNativeToolExecutionResult {
    inputs.append(input)
    return .success(output: ["results": .array(["related", "related", "additional", "origin"].map {
      .object(["url": .string("https://source.test/\($0)"), "title": .string("alpha beta"), "excerpt": .string("alpha beta")])
    })], metadata: ["provider": .string("fixture")])
  }
}
