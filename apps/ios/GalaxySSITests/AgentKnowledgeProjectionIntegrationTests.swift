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
    try stage.finishIncoming(); try stage.finishPrevious()
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
    try stage.finishIncoming(); try stage.finishPrevious()
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
}
