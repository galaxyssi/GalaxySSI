import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentIOSWebSourceHealthDatabaseTests: XCTestCase {
  func testScopedHealthReadsDecryptOnlyRequestedRowsAndCountsDecryptNone() throws {
    try fixture { url, key in
      var decoded = 0
      let index = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key, didDecode: { decoded += 1 })
      try index.initialize { (0..<200).map { AgentIOSWebSourceHealth(sourceID: "source-\($0)") } }
      XCTAssertEqual(try index.count(), 200)
      XCTAssertEqual(decoded, 0)
      XCTAssertEqual(try index.records(ids: ["source-1", "source-2", "missing"]).count, 2)
      XCTAssertEqual(decoded, 2)
      XCTAssertEqual(try index.count(), 200)
      XCTAssertEqual(decoded, 2)
    }
  }

  func testReceiptBatchEvolvesDuplicateSourceIDsInOrderWithOneCommit() throws {
    try fixture { url, key in
      var commits = 0
      let index = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key, beforeCommit: { commits += 1 })
      try index.initialize { [] }
      commits = 0
      try index.record([receipt("bing", "failed"), receipt("bing", "failed"), receipt("bing", "completed"),
        receipt("baidu", "empty")], now: { 1000 })
      let records = try index.records()
      XCTAssertEqual(commits, 1)
      XCTAssertEqual(records["bing"]?.attempts, 3)
      XCTAssertEqual(records["bing"]?.failures, 2)
      XCTAssertEqual(records["bing"]?.successes, 1)
      XCTAssertEqual(records["bing"]?.consecutiveFailures, 0)
      XCTAssertEqual(records["baidu"]?.emptyResponses, 1)
    }
  }

  func testFailedBatchAndResetRollBackBeforeAnotherHandleReads() throws {
    try fixture { url, key in
      var reject = false
      let index = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key, beforeCommit: {
        if reject { throw CocoaError(.fileWriteOutOfSpace) }
      })
      try index.initialize { [] }
      try index.record([receipt("bing", "failed")], now: { 1000 })
      let before = try index.records()
      reject = true
      XCTAssertThrowsError(try index.record([receipt("bing", "completed"), receipt("baidu", "empty")], now: { 2000 }))
      XCTAssertThrowsError(try index.reset())
      let reopened = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key)
      try reopened.initialize { XCTFail("Migration must not run again"); return [] }
      XCTAssertEqual(try reopened.records(), before)
      XCTAssertEqual(try reopened.count(), 1)
    }
  }

  func testMigrationRowsAndMarkerCommitTogetherAndCanRetryAfterFailure() throws {
    try fixture { url, key in
      var reject = true, imports = 0
      let index = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key, beforeCommit: {
        if reject { throw CocoaError(.fileWriteOutOfSpace) }
      })
      XCTAssertThrowsError(try index.initialize { imports += 1; return [AgentIOSWebSourceHealth(sourceID: "bing")] })
      XCTAssertEqual(try index.count(), 0)
      reject = false
      try index.initialize { imports += 1; return [AgentIOSWebSourceHealth(sourceID: "bing")] }
      try index.initialize { imports += 1; return [] }
      XCTAssertEqual(imports, 2)
      XCTAssertEqual(try index.count(), 1)
    }
  }

  func testWrongKeyAndDifferentNamespaceCannotAuthenticateMigratedRows() throws {
    try fixture { url, key in
      let index = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key)
      try index.initialize { [AgentIOSWebSourceHealth(sourceID: "private-source")] }
      let wrong = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: SymmetricKey(size: .bits256))
      XCTAssertThrowsError(try wrong.initialize { XCTFail("Wrong key must not replace migration"); return [] })
      XCTAssertThrowsError(try wrong.records())
      let bytes = try Data(contentsOf: url)
      XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private-source"))
      // Copy committed rows with SQLite backup; a new pathname changes AEAD/HMAC keys.
      let copy = url.deletingLastPathComponent().appendingPathComponent("copy.sqlite")
      try copyDatabase(url, to: copy)
      let other = try AgentIOSWebSourceHealthDatabase(fileURL: copy, masterKey: key)
      XCTAssertThrowsError(try other.initialize { XCTFail("Copied marker must not authenticate"); return [] })
    }
  }

  func testFacadeImportsLegacyHealthOnceWithoutRewritingDocumentsOrResurrectingReset() throws {
    try fixture { url, key in
      let legacy = url.deletingLastPathComponent().appendingPathComponent("legacy.json"), secrets = InMemorySecretStore()
      try secrets.setString(key.withUnsafeBytes { Data($0) }.base64EncodedString(), account: AgentIOSWebIntelligenceCacheStore.keyAccount)
      try writeLegacy(legacy, key: key, records: [AgentIOSWebSourceHealth(sourceID: "bing")])
      let original = try Data(contentsOf: legacy)
      let cache = AgentIOSWebIntelligenceCacheStore(fileURL: legacy, secrets: secrets)
      XCTAssertEqual(cache.sourceHealth(ids: ["bing"])?.count, 1)
      XCTAssertEqual(try Data(contentsOf: legacy), original)
      XCTAssertEqual(cache.resetSourceHealth()["source_health_removed"], .int(1))
      let reopened = AgentIOSWebIntelligenceCacheStore(fileURL: legacy, secrets: secrets)
      XCTAssertTrue(try XCTUnwrap(reopened.sourceHealth()).isEmpty)
      try Data("corrupt legacy snapshot".utf8).write(to: legacy)
      XCTAssertTrue(try XCTUnwrap(reopened.sourceHealth()).isEmpty)
      XCTAssertEqual(reopened.stats()["available"], .bool(false))
    }
  }

  func testStableLogicalIdentitySurvivesADataContainerPathChange() throws {
    try fixture { url, key in
      let identity = "app-support:GalaxySSI/web-intelligence-cache.json"
      let index = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key, storageIdentity: identity)
      try index.initialize { [AgentIOSWebSourceHealth(sourceID: "bing")] }
      let moved = url.deletingLastPathComponent().appendingPathComponent("moved.sqlite")
      try copyDatabase(url, to: moved)
      let reopened = try AgentIOSWebSourceHealthDatabase(fileURL: moved, masterKey: key, storageIdentity: identity)
      try reopened.initialize { XCTFail("Relocation must not reimport"); return [] }
      XCTAssertEqual(try reopened.records(ids: ["bing"]).count, 1)
      let other = try AgentIOSWebSourceHealthDatabase(fileURL: moved, masterKey: key, storageIdentity: "another-cache")
      XCTAssertThrowsError(try other.initialize { [] })
    }
  }

  func testLostIndexOrMissingKeyCannotResurrectLegacyHealthOrReplaceTheMasterKey() throws {
    try fixture { url, key in
      let legacy = url.deletingLastPathComponent().appendingPathComponent("legacy.json"), secrets = InMemorySecretStore()
      try secrets.setString(key.withUnsafeBytes { Data($0) }.base64EncodedString(), account: AgentIOSWebIntelligenceCacheStore.keyAccount)
      try writeLegacy(legacy, key: key, records: [AgentIOSWebSourceHealth(sourceID: "bing")])
      let cache = AgentIOSWebIntelligenceCacheStore(fileURL: legacy, secrets: secrets)
      XCTAssertEqual(cache.sourceHealth()?.count, 1)
      let indexURL = AgentIOSWebIntelligenceCacheStore.sourceHealthDatabaseURL(for: legacy)
      try Data().write(to: indexURL)
      XCTAssertNil(cache.sourceHealth())
      XCTAssertFalse(cache.recordSourceReceipts([receipt("baidu", "empty")]))
      try FileManager.default.removeItem(at: indexURL.deletingLastPathComponent())
      XCTAssertNil(cache.sourceHealth())
      XCTAssertFalse(cache.recordSourceReceipts([receipt("baidu", "empty")]))
      secrets.delete(account: AgentIOSWebIntelligenceCacheStore.keyAccount)
      try FileManager.default.removeItem(at: legacy)
      XCTAssertFalse(cache.putDocument(url: "https://example.test/", title: "Source", content: "body", contentType: "text/plain",
        contentSHA256: "hash", retrievedAtMillis: 1, expiresAtMillis: 2))
      XCTAssertNil(secrets.string(account: AgentIOSWebIntelligenceCacheStore.keyAccount))
    }
  }

  func testTwoHandlesCannotLoseReceiptsFromOverlappingBatches() throws {
    try fixture { url, key in
      let first = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key)
      try first.initialize { [] }
      let second = try AgentIOSWebSourceHealthDatabase(fileURL: url, masterKey: key)
      try second.initialize { [] }
      let group = DispatchGroup(), errors = HealthDatabaseFixtureErrors()
      for index in [first, second] {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
          defer { group.leave() }
          do { try index.record(Array(repeating: self.receipt("bing", "completed"), count: 32), now: { 1000 }) }
          catch { errors.append(error) }
        }
      }
      XCTAssertEqual(group.wait(timeout: .now() + .seconds(10)), .success)
      XCTAssertTrue(errors.isEmpty)
      XCTAssertEqual(try first.records(ids: ["bing"])["bing"]?.attempts, 64)
    }
  }

  private func fixture(_ body: (URL, SymmetricKey) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("health-index-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appendingPathComponent("health.sqlite"), SymmetricKey(size: .bits256))
  }
  private func receipt(_ id: String, _ status: String) -> AgentIOSWebSourceReceipt {
    .init(sourceID: id, status: status, durationMillis: 100, resultCount: status == "completed" ? 1 : 0)
  }
  private func writeLegacy(_ url: URL, key: SymmetricKey, records: [AgentIOSWebSourceHealth]) throws {
    let health = try JSONSerialization.jsonObject(with: JSONEncoder().encode(records))
    let data = try JSONSerialization.data(withJSONObject: ["version": 1, "documents": [], "watches": [], "sourceHealth": health])
    let box = try AES.GCM.seal(data, using: key)
    let envelope: [String: Any] = ["version": 1, "nonce": box.nonce.withUnsafeBytes { Data($0) }.base64EncodedString(),
      "ciphertext": box.ciphertext.base64EncodedString(), "tag": box.tag.base64EncodedString()]
    try JSONSerialization.data(withJSONObject: envelope).write(to: url)
  }
  private func copyDatabase(_ source: URL, to destination: URL) throws {
    var reader: OpaquePointer?, writer: OpaquePointer?
    guard sqlite3_open_v2(source.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      if let reader { sqlite3_close_v2(reader) }
      throw AgentIOSWebSourceHealthDatabase.Failure.unavailable
    }
    defer { sqlite3_close_v2(reader) }
    guard sqlite3_open_v2(destination.path, &writer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      if let writer { sqlite3_close_v2(writer) }
      throw AgentIOSWebSourceHealthDatabase.Failure.unavailable
    }
    defer { sqlite3_close_v2(writer) }
    guard let backup = sqlite3_backup_init(writer, "main", reader, "main") else { throw AgentIOSWebSourceHealthDatabase.Failure.unavailable }
    let status = sqlite3_backup_step(backup, -1), closed = sqlite3_backup_finish(backup)
    guard status == SQLITE_DONE, closed == SQLITE_OK else { throw AgentIOSWebSourceHealthDatabase.Failure.unavailable }
  }
}

private final class HealthDatabaseFixtureErrors {
  private let lock = NSLock()
  private var values: [Error] = []
  func append(_ error: Error) { lock.lock(); values.append(error); lock.unlock() }
  var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return values.isEmpty }
}
