import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgeProjectionIntegrationTests: XCTestCase {
  private enum Fault: Error { case injected }
  private func items(_ generation: Int) -> [AgentKnowledgeItem] {
    ["z", "a", "middle"].enumerated().map { index, id in
      AgentKnowledgeItem(id: id, kind: .document, title: "Synthetic", content: "synthetic generation \(generation) \(id)",
        source: "source", summary: "summary \(generation) \(id)", chunkIndex: index, chunkCount: 3,
        updatedAtMillis: Int64(generation + 10))
    }
  }
  private func fixture(_ body: (AgentKnowledgeDatabase, URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = AgentKnowledgeDatabase(fileURL: root.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
    XCTAssertTrue(database.replaceAll(items(1)))
    try body(database, root)
  }
  private func replace(_ database: AgentKnowledgeDatabase, generation: Int) throws {
    var iterator = items(generation).makeIterator()
    let result = try database.replaceSource("source", next: { iterator.next() })
    result.stage.close()
  }

  func testBulkAndTargetedWritesPublishCompleteContentRevisions() throws {
    try fixture { database, _ in
      let bulk = try XCTUnwrap(database.sourcePage().groups.first)
      XCTAssertEqual(bulk.sourceRevision, AgentKnowledgeSourceRevision.digest(items(1)))
      XCTAssertFalse(bulk.sourceRevision.isEmpty)
      try replace(database, generation: 2)
      let next = try XCTUnwrap(database.sourcePage().groups.first)
      XCTAssertEqual(next.sourceRevision, AgentKnowledgeSourceRevision.digest(items(2)))
      XCTAssertNotEqual(next.sourceRevision, bulk.sourceRevision)
      XCTAssertEqual(try database.sourceSnapshotItems(next).count, 3)
    }
  }

  @MainActor func testActualBridgeExportsFreshTargetedSourceAndExactOutputHash() throws {
    try fixture { database, root in
      try replace(database, generation: 2)
      let group = try XCTUnwrap(database.sourcePage().groups.first)
      let destination = root.appendingPathComponent("projection.md")
      let hash = try AgentIOSObsidianBridge.writeKnowledgeProjection(database: database, group: group,
        sourceKey: "synthetic", type: "knowledge", fallbackTitle: "Synthetic", source: "source", destination: destination)
      let data = try Data(contentsOf: destination)
      XCTAssertEqual(hash, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
      let text = String(decoding: data, as: UTF8.self)
      for item in items(2) { XCTAssertTrue(text.contains(item.content)) }
      XCTAssertFalse(text.contains("synthetic generation 1"))
    }
  }

  func testStaleSourceGroupRejectsBeforeDeliveringAnyRecord() throws {
    try fixture { database, _ in
      let old = try XCTUnwrap(database.sourcePage().groups.first)
      try replace(database, generation: 2)
      var delivered = 0
      XCTAssertThrowsError(try database.enumerateSourceSnapshotItems(old) { _ in delivered += 1 }) {
        XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .staleCursor)
      }
      XCTAssertEqual(delivered, 0)
    }
  }

  func testSnapshotKeepsOldHeadersAndBodiesAcrossTargetedReplacement() throws {
    try fixture { database, _ in
      let old = try XCTUnwrap(database.sourcePage().groups.first)
      var collected: [AgentKnowledgeItem] = [], changed = false
      try database.enumerateSourceSnapshotItems(old) { value in
        collected.append(value)
        if !changed {
          changed = true
          try self.replace(database, generation: 2)
          XCTAssertTrue(try database.reclaimPrimaryPartitions().deferred)
        }
      }
      XCTAssertEqual(AgentKnowledgeSourceRevision.digest(collected), old.sourceRevision)
      XCTAssertEqual(collected.sorted { $0.id < $1.id }, items(1).sorted { $0.id < $1.id })
      XCTAssertFalse(try database.reclaimPrimaryPartitions().deferred)
      let current = try XCTUnwrap(database.sourcePage().groups.first)
      XCTAssertEqual(try database.sourceSnapshotItems(current).sorted { $0.id < $1.id }, items(2).sorted { $0.id < $1.id })
    }
  }

  func testLifecycleInvalidationStopsFurtherSnapshotDeliveryAndAllowsFreshView() throws {
    try fixture { database, _ in
      let group = try XCTUnwrap(database.sourcePage().groups.first)
      var count = 0
      XCTAssertThrowsError(try database.enumerateSourceSnapshotItems(group) { _ in
        count += 1; database.nativeFiles.invalidate()
      }) { XCTAssertTrue($0 is CancellationError) }
      XCTAssertEqual(count, 1)
      var retry = 0
      try database.enumerateSourceSnapshotItems(group) { _ in retry += 1 }
      XCTAssertEqual(retry, 3)
    }
  }

  func testStreamedSourceDigestUsesIdentityOrderAndLegacyEncoding() throws {
    let source = ["z", "a", "\u{e9}", "e\u{301}", "\u{1f600}"].enumerated().map { index, id in
      AgentKnowledgeItem(id: id, kind: .document, title: "Synthetic", content: "body \(index)", source: "source",
        summary: "summary", chunkIndex: index, chunkCount: 5, updatedAtMillis: 11)
    }
    let stage = try AgentKnowledgeSourceStaging(source: "source")
    defer { stage.close() }
    for item in source { XCTAssertTrue(try stage.accept(item)) }
    try stage.finishIncoming(); try stage.finishPrevious(); try stage.finishMutation()
    XCTAssertEqual(try stage.sourceRevision(), AgentKnowledgeSourceRevision.digest(source))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    var hash = SHA256()
    for item in source.sorted(by: { AgentKnowledgeSourceRevision.identityPrecedes($0.id, $1.id) }) {
      let bytes = try encoder.encode(item); var size = UInt64(bytes.count).bigEndian
      withUnsafeBytes(of: &size) { hash.update(data: Data($0)) }; hash.update(data: bytes)
    }
    XCTAssertEqual(try stage.sourceRevision(), hash.finalize().map { String(format: "%02x", $0) }.joined())
  }

  func testMissingStagedRecordCannotPublishACompletedSourceDigest() throws {
    let stage = try AgentKnowledgeSourceStaging(source: "source")
    defer { stage.close() }
    for item in items(1) { XCTAssertTrue(try stage.accept(item)) }
    try stage.finishIncoming(); try stage.finishPrevious(); try stage.finishMutation()
    var raw: OpaquePointer?
    guard sqlite3_open(stage.fileURL.path, &raw) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_close_v2(raw) }
    XCTAssertEqual(sqlite3_exec(raw, "DELETE FROM records WHERE token=(SELECT token FROM records LIMIT 1)", nil, nil, nil), SQLITE_OK)
    XCTAssertThrowsError(try stage.sourceRevision())
  }

  @MainActor func testLifecycleChangeDuringSecondRenderPassPreservesDestination() throws {
    try fixture { database, root in
      let group = try XCTUnwrap(database.sourcePage().groups.first)
      let destination = root.appendingPathComponent("projection.md"), baseline = Data("synthetic user baseline".utf8)
      try baseline.write(to: destination)
      var scans = 0
      let order = try AgentKnowledgeProjectionOrder(beforeScan: { _ in
        scans += 1
        if scans == 2 { database.nativeFiles.invalidate() }
      })
      XCTAssertThrowsError(try AgentIOSObsidianBridge.writeKnowledgeProjection(database: database, group: group,
        sourceKey: "synthetic", type: "knowledge", fallbackTitle: "Synthetic", source: "source",
        destination: destination, scratchOrder: order)) { XCTAssertTrue($0 is CancellationError) }
      XCTAssertEqual(scans, 2)
      XCTAssertEqual(try Data(contentsOf: destination), baseline)
      XCTAssertFalse(FileManager.default.fileExists(atPath: order.lease.directory.path))
    }
  }

  func testSourceDigestCannotStartInsidePendingMutationTransaction() throws {
    let stage = try AgentKnowledgeSourceStaging(source: "source")
    defer { stage.close() }
    for item in items(1) { XCTAssertTrue(try stage.accept(item)) }
    try stage.finishIncoming(); try stage.finishPrevious()
    XCTAssertThrowsError(try stage.sourceRevision())
    try stage.finishMutation()
    XCTAssertEqual(try stage.sourceRevision(), AgentKnowledgeSourceRevision.digest(items(1)))
  }

  private func rewriteHeader(_ root: URL, secrets: InMemorySecretStore,
    transform: (inout AgentKnowledgeSourceGroup) -> Void) throws -> AgentKnowledgeSourceGroup {
    var raw: OpaquePointer?
    guard sqlite3_open(root.appendingPathComponent("knowledge.sqlite").path, &raw) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_close_v2(raw) }
    var row: OpaquePointer?
    guard sqlite3_prepare_v2(raw, "SELECT source_hash,encrypted_header FROM knowledge_source_headers", -1, &row, nil) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_finalize(row) }
    guard sqlite3_step(row) == SQLITE_ROW, let text = sqlite3_column_text(row, 0),
      let pointer = sqlite3_column_blob(row, 1) else { throw Fault.injected }
    let hash = String(cString: text), encrypted = Data(bytes: pointer, count: Int(sqlite3_column_bytes(row, 1)))
    guard sqlite3_step(row) == SQLITE_DONE else { throw Fault.injected }
    let cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "agent.knowledge.row.aes256.v1")
    let purpose = "agent-knowledge-source:\(hash)"
    var group = try JSONDecoder.galaxySSI.decode(AgentKnowledgeSourceGroup.self, from: cipher.decrypt(encrypted, expectedPurpose: purpose))
    transform(&group)
    let replacement = try cipher.encrypt(JSONEncoder.galaxySSI.encode(group), purpose: purpose)
    var update: OpaquePointer?
    guard sqlite3_prepare_v2(raw, "UPDATE knowledge_source_headers SET encrypted_header=?", -1, &update, nil) == SQLITE_OK else { throw Fault.injected }
    defer { sqlite3_finalize(update) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    guard replacement.withUnsafeBytes({ sqlite3_bind_blob(update, 1, $0.baseAddress, Int32(replacement.count), transient) }) == SQLITE_OK,
      sqlite3_step(update) == SQLITE_DONE, sqlite3_changes(raw) == 1 else { throw Fault.injected }
    return group
  }

  private func legacyFixture(_ body: (AgentKnowledgeDatabase, URL, InMemorySecretStore, AgentKnowledgeSourceGroup) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: root.appendingPathComponent("knowledge.sqlite"), secrets: secrets)
    XCTAssertTrue(database.replaceAll(items(1)))
    let group = try rewriteHeader(root, secrets: secrets) { $0.sourceRevision = "" }
    try body(database, root, secrets, group)
  }

  func testLegacyRevisionRecoverySurvivesReopenWithoutChangingSourceFields() throws {
    try legacyFixture { database, root, secrets, group in
      let browse = try database.sourceBrowseRevision()
      let resolved = try database.resolveSourceExportGroup(group)
      var expected = group; expected.sourceRevision = AgentKnowledgeSourceRevision.digest(items(1))
      XCTAssertEqual(resolved, expected)
      XCTAssertEqual(try database.sourceBrowseRevision(), browse + 1)
      let reopened = AgentKnowledgeDatabase(fileURL: root.appendingPathComponent("knowledge.sqlite"), secrets: secrets)
      XCTAssertEqual(try reopened.sourcePage().groups.first, resolved)
      XCTAssertEqual(try reopened.sourceSnapshotItems(resolved).count, 3)
      var invoked = false
      XCTAssertEqual(try reopened.resolveSourceExportGroup(resolved, beforePublication: { invoked = true }), resolved)
      XCTAssertFalse(invoked)
    }
  }

  @MainActor func testActualBridgeRecoversLegacyRevisionBeforePublishingOutput() throws {
    try legacyFixture { database, root, _, group in
      let destination = root.appendingPathComponent("legacy.md")
      let hash = try AgentIOSObsidianBridge.writeKnowledgeProjection(database: database, group: group,
        sourceKey: "synthetic", type: "knowledge", fallbackTitle: "Synthetic", source: "source", destination: destination)
      let output = try Data(contentsOf: destination)
      XCTAssertEqual(hash, SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined())
      for item in items(1) { XCTAssertTrue(String(decoding: output, as: UTF8.self).contains(item.content)) }
      XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, AgentKnowledgeSourceRevision.digest(items(1)))
    }
  }

  func testLegacyRecoveryRejectsConcurrentSourceReplacement() throws {
    try legacyFixture { database, _, _, group in
      XCTAssertThrowsError(try database.resolveSourceExportGroup(group, beforePublication: {
        try self.replace(database, generation: 2)
      })) { XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .sourceReplacementChanged) }
      let winner = try XCTUnwrap(database.sourcePage().groups.first)
      XCTAssertEqual(winner.sourceRevision, AgentKnowledgeSourceRevision.digest(items(2)))
      XCTAssertEqual(try database.sourceSnapshotItems(winner).count, 3)
    }
  }

  func testLegacyRecoveryRejectsSameLogicalHeaderWithDifferentCiphertext() throws {
    try legacyFixture { database, root, secrets, group in
      XCTAssertThrowsError(try database.resolveSourceExportGroup(group, beforePublication: {
        _ = try self.rewriteHeader(root, secrets: secrets) { _ in }
      })) { XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .staleCursor) }
      XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, "")
      XCTAssertFalse(try database.resolveSourceExportGroup(group).sourceRevision.isEmpty)
    }
  }

  func testLegacyRecoveryCountMismatchDoesNotPublishGuessedRevision() throws {
    try legacyFixture { database, root, secrets, _ in
      let mismatched = try rewriteHeader(root, secrets: secrets) { $0.chunkCount += 1 }
      let revision = try database.sourceBrowseRevision()
      XCTAssertThrowsError(try database.resolveSourceExportGroup(mismatched)) {
        XCTAssertEqual($0 as? AgentKnowledgeDatabaseError, .corruptRecord)
      }
      XCTAssertEqual(try database.sourceBrowseRevision(), revision)
      XCTAssertEqual(try database.sourcePage().groups.first, mismatched)
    }
  }

  func testLegacyRecoveryFaultAndLifecycleLossDoNotPublishAndAllowRetry() throws {
    try legacyFixture { database, _, _, group in
      let revision = try database.sourceBrowseRevision()
      XCTAssertThrowsError(try database.resolveSourceExportGroup(group, beforePublication: { throw Fault.injected }))
      XCTAssertEqual(try database.sourceBrowseRevision(), revision)
      XCTAssertThrowsError(try database.resolveSourceExportGroup(group, beforePublication: { database.nativeFiles.invalidate() })) {
        XCTAssertTrue($0 is CancellationError)
      }
      XCTAssertEqual(try database.sourceBrowseRevision(), revision)
      XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, "")
      XCTAssertFalse(try database.resolveSourceExportGroup(group).sourceRevision.isEmpty)
    }
  }

  func testLegacyMetadataRepairKeepsPreparedSourceGenerationAndVectorLedger() throws {
    try legacyFixture { database, _, _, group in
      var iterator = items(2).makeIterator()
      let prepared = try database.prepareSourceReplacement("source", next: { iterator.next() })
      defer { prepared.close() }
      let before = try database.vectorFeedStamp(modelSHA256: String(repeating: "a", count: 64))
      _ = try database.resolveSourceExportGroup(group)
      let after = try database.vectorFeedStamp(modelSHA256: String(repeating: "a", count: 64))
      XCTAssertEqual(before.epoch, after.epoch); XCTAssertEqual(before.head, after.head)
      XCTAssertEqual(after.sourceRevision, before.sourceRevision + 1)
      let result = try database.commitSourceReplacement(prepared); result.stage.close()
      XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, AgentKnowledgeSourceRevision.digest(items(2)))
    }
  }

  func testLegacyRecoveryRejectsUnauthenticatedHeaderWithoutPublishing() throws {
    try legacyFixture { database, root, _, group in
      let revision = try database.sourceBrowseRevision()
      var raw: OpaquePointer?
      guard sqlite3_open(root.appendingPathComponent("knowledge.sqlite").path, &raw) == SQLITE_OK else { throw Fault.injected }
      defer { sqlite3_close_v2(raw) }
      XCTAssertEqual(sqlite3_exec(raw, "UPDATE knowledge_source_headers SET encrypted_header=x'00010203'", nil, nil, nil), SQLITE_OK)
      XCTAssertThrowsError(try database.resolveSourceExportGroup(group))
      XCTAssertEqual(try database.sourceBrowseRevision(), revision)
    }
  }
}
