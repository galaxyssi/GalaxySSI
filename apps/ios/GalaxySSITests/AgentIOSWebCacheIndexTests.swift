import CryptoKit
import Foundation
import XCTest
@testable import GalaxySSI

final class AgentIOSWebCacheIndexTests: XCTestCase {
  func testSearchRowsCrossLegacyBlobLimitWhileOtherKindsKeepTheirBounds() throws {
    try fixture { url in
      let index = try AgentIOSWebCacheIndex(url: url, master: SymmetricKey(size: .bits256), identity: "fixture", beforeCommit: {})
      try index.initialize(allowImport: true) { [] }
      var large = entry(.search, "large")
      large.payload = Data(repeating: 120, count: 4_200_000)
      try index.transaction { try index.put(large) }
      XCTAssertEqual(try index.entry(.search, id: "large")?.payload, large.payload)
      for kind in [AgentIOSWebCacheIndex.Kind.document, .watch, .learned] {
        var bounded = large; bounded.kind = kind
        XCTAssertThrowsError(try index.transaction { try index.put(bounded) })
        XCTAssertNil(try index.entry(kind, id: "large"))
      }
    }
  }

  func testConfiguredSQLiteRowLimitRejectsReplacementWithoutLosingExistingData() throws {
    try fixture { url in
      let index = try AgentIOSWebCacheIndex(url: url, master: SymmetricKey(size: .bits256), identity: "fixture",
        maximumRowBytes: 4_096, beforeCommit: {})
      try index.initialize(allowImport: true) { [] }
      let original = entry(.search, "saved")
      try index.transaction { try index.put(original) }
      let generation = try index.generation()
      var replacement = original; replacement.payload = Data(repeating: 120, count: 4_000)
      XCTAssertThrowsError(try index.transaction { try index.put(replacement) })
      XCTAssertEqual(try index.entry(.search, id: "saved")?.payload, original.payload)
      XCTAssertEqual(try index.generation(), generation)
    }
  }

  func testIndexedCountsAndPointReadsDoNotDecodeOtherBodies() throws {
    try fixture { url in
      var decodes = 0
      let index = try AgentIOSWebCacheIndex(url: url, master: SymmetricKey(size: .bits256), identity: "fixture",
        beforeCommit: {}, didDecode: { decodes += 1 })
      try index.initialize(allowImport: true) { (0..<200).map { entry(.document, "doc-\($0)", updated: Int64($0)) } }
      XCTAssertEqual(try index.metadata(now: 1000)["entry_count"], .int(200))
      XCTAssertEqual(decodes, 0)
      XCTAssertEqual(try index.entry(.document, id: "doc-199")?.id, "doc-199")
      XCTAssertEqual(decodes, 1)
      XCTAssertNil(try index.entry(.document, id: "missing"))
      XCTAssertEqual(decodes, 1)
    }
  }

  func testFullClearAndGenerationCommitAtomicallyWhileWatchesRemain() throws {
    try fixture { url in
      let key = SymmetricKey(size: .bits256)
      var reject = false
      let index = try AgentIOSWebCacheIndex(url: url, master: key, identity: "fixture", beforeCommit: {
        if reject { throw CocoaError(.fileWriteOutOfSpace) }
      })
      try index.initialize(allowImport: true) { AgentIOSWebCacheIndex.Kind.allCases.map { entry($0, $0.rawValue) } }
      let generation = try index.generation()
      reject = true
      XCTAssertThrowsError(try index.clear(expiredOnly: false, now: 1000))
      XCTAssertEqual(try index.generation(), generation)
      for kind in AgentIOSWebCacheIndex.Kind.allCases { XCTAssertNotNil(try index.entry(kind, id: kind.rawValue)) }
      reject = false
      let counts = try index.clear(expiredOnly: false, now: 1000)
      XCTAssertEqual(counts.documents, 1)
      XCTAssertEqual(counts.searches, 1)
      XCTAssertEqual(counts.learned, 1)
      XCTAssertNotNil(try index.entry(.watch, id: "watch"))
      let other = try AgentIOSWebCacheIndex(url: url, master: key, identity: "fixture", beforeCommit: {})
      try other.initialize(allowImport: false) { XCTFail("Must not reimport"); return [] }
      XCTAssertNotEqual(try other.generation(), generation)
      XCTAssertThrowsError(try other.putSearch(entry(.search, "stale"), now: 1000, expected: generation))
      XCTAssertNil(try other.entry(.search, id: "stale"))
    }
  }

  func testExpiryBoundariesDoNotRotateTheFullClearGeneration() throws {
    try fixture { url in
      let index = try AgentIOSWebCacheIndex(url: url, master: SymmetricKey(size: .bits256), identity: "fixture", beforeCommit: {})
      try index.initialize(allowImport: true) { [entry(.document, "equal", expires: 1000), entry(.document, "old", expires: 999),
        entry(.search, "equal", expires: 1000), entry(.watch, "watch"), entry(.learned, "learned")] }
      let generation = try index.generation(), counts = try index.clear(expiredOnly: true, now: 1000)
      XCTAssertEqual(counts.documents, 1)
      XCTAssertEqual(counts.searches, 0)
      XCTAssertNotNil(try index.entry(.search, id: "equal"))
      XCTAssertEqual(counts.learned, 0)
      XCTAssertNotNil(try index.entry(.document, id: "equal"))
      XCTAssertNotNil(try index.entry(.learned, id: "learned"))
      XCTAssertEqual(try index.generation(), generation)
    }
  }

  func testTwoThousandDocumentRetentionPrunesWithoutDecodingBodies() throws {
    try fixture { url in
      var decodes = 0
      let index = try AgentIOSWebCacheIndex(url: url, master: SymmetricKey(size: .bits256), identity: "fixture",
        beforeCommit: {}, didDecode: { decodes += 1 })
      try index.initialize(allowImport: true) { [] }
      try index.transaction {
        for number in 0..<2001 { try index.put(entry(.document, "doc-\(number)", updated: Int64(number))) }
        try index.prune(.document, limit: 2000)
      }
      XCTAssertEqual(try index.metadata(now: 1000)["entry_count"], .int(2000))
      XCTAssertEqual(decodes, 0)
      XCTAssertNil(try index.entry(.document, id: "doc-0"))
      XCTAssertNotNil(try index.entry(.document, id: "doc-2000"))
    }
  }

  func testMigrationFailureDoesNotCommitRowsOrPermitUnapprovedReimport() throws {
    try fixture { url in
      var reject = true
      let key = SymmetricKey(size: .bits256)
      let index = try AgentIOSWebCacheIndex(url: url, master: key, identity: "fixture", beforeCommit: {
        if reject { throw CocoaError(.fileWriteOutOfSpace) }
      })
      XCTAssertThrowsError(try index.initialize(allowImport: true) { [entry(.document, "one")] })
      XCTAssertEqual(try index.metadata(now: 1000)["entry_count"], .int(0))
      XCTAssertThrowsError(try index.initialize(allowImport: false) { XCTFail("No fallback"); return [] })
      reject = false
      try index.initialize(allowImport: true) { [entry(.document, "one")] }
      let wrong = try AgentIOSWebCacheIndex(url: url, master: key, identity: "another-cache", beforeCommit: {})
      XCTAssertThrowsError(try wrong.initialize(allowImport: true) { XCTFail("No key replacement"); return [] })
    }
  }

  func testUpdatedDocumentsUseInsertionRecencyRatherThanTheSourceTimestampForEviction() throws {
    try fixture { url in
      let index = try AgentIOSWebCacheIndex(url: url, master: SymmetricKey(size: .bits256), identity: "fixture", beforeCommit: {})
      try index.initialize(allowImport: true) { [entry(.document, "one", updated: 100), entry(.document, "two", updated: 200)] }
      try index.transaction {
        try index.put(entry(.document, "one", updated: 50))
        try index.prune(.document, limit: 1)
      }
      XCTAssertNotNil(try index.entry(.document, id: "one"))
      XCTAssertNil(try index.entry(.document, id: "two"))
    }
  }

  func testFacadeMigratesLegacyOnceAndDoesNotReopenTheArchiveAfterClear() throws {
    try fixture { url in
      let legacy = url.deletingLastPathComponent().appendingPathComponent("legacy.json"), key = SymmetricKey(size: .bits256)
      let secrets = InMemorySecretStore()
      try secrets.setString(key.withUnsafeBytes { Data($0) }.base64EncodedString(), account: AgentIOSWebIntelligenceCacheStore.keyAccount)
      let value = AgentIOSWebIntelligenceCacheDocument(url: "https://source.test/legacy", title: "Source", content: "Archive body",
        contentType: "text/plain", contentSHA256: "hash", retrievedAtMillis: 1, expiresAtMillis: 2000, links: [], metadata: [:])
      let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
      let plaintext = try JSONSerialization.data(withJSONObject: ["version": 1, "documents": [raw], "watches": []])
      let box = try AES.GCM.seal(plaintext, using: key)
      let archive = try JSONSerialization.data(withJSONObject: ["version": 1,
        "nonce": box.nonce.withUnsafeBytes { Data($0) }.base64EncodedString(),
        "ciphertext": box.ciphertext.base64EncodedString(), "tag": box.tag.base64EncodedString()])
      try archive.write(to: legacy)
      let cache = AgentIOSWebIntelligenceCacheStore(fileURL: legacy, secrets: secrets, nowMillis: { 1000 })
      XCTAssertEqual(cache.document(url: value.url)?.content, value.content)
      XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
      XCTAssertEqual(cache.clear(expiredOnly: false)["documents_removed"], .int(1))
      try Data("invalid old archive".utf8).write(to: legacy)
      XCTAssertNil(cache.document(url: value.url, allowStale: true))
      XCTAssertEqual(cache.cacheMetadata()["available"], .bool(true))
      XCTAssertEqual(cache.cacheMetadata()["entry_count"], .int(0))
      XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }
  }

  private func entry(_ kind: AgentIOSWebCacheIndex.Kind, _ id: String, updated: Int64 = 1, expires: Int64 = 2000) -> AgentIOSWebCacheIndex.Entry {
    .init(kind: kind, id: id, updated: updated, expires: expires, payload: Data("fixture".utf8))
  }
  private func fixture(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("web-index-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder.appendingPathComponent("index.sqlite"))
  }
}

func removeWebCacheFixture(_ file: URL) {
  let logical = file.standardizedFileURL
  let root = FileManager.default.temporaryDirectory.standardizedFileURL.pathComponents
  guard logical.isFileURL, logical.pathComponents.count > root.count,
    logical.pathComponents.prefix(root.count).elementsEqual(root) else { return }
  for target in [logical, AgentIOSWebIntelligenceCacheStore.indexDatabaseURL(for: logical).deletingLastPathComponent(),
    AgentIOSWebIntelligenceCacheStore.sourceHealthDatabaseURL(for: logical).deletingLastPathComponent()] {
    try? FileManager.default.removeItem(at: target)
  }
}
