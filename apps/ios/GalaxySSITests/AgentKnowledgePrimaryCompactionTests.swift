import Darwin
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryCompactionTests: XCTestCase {
  private typealias Fixture = AgentKnowledgePrimaryPartitionsTests.Fixture
  private enum Fault: Error { case injected }
  private func key(_ index: Int) -> String { "aa" + String(format: "%062x", index) }
  private func mixed(_ f: Fixture, count: Int = 1, body: Data = Data("live".utf8)) throws {
    for generation in 0..<2 {
      try f.batch {
        for index in 0..<count { try f.stage(generation == 0 ? Data("dead".utf8) : body, key: key(index)) }
      }
    }
  }
  private func reopen(_ f: Fixture, beforeRetiredUnlink: @escaping () throws -> Void = {}) throws {
    f.store = nil
    f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets, beforeRetiredUnlink: beforeRetiredUnlink)
    try f.store.setup(catalog: f.catalog)
  }
  @discardableResult private func drain(_ f: Fixture) throws -> Int {
    var total = 0
    for _ in 0..<64 {
      let page = try f.store.reclaim(catalog: f.catalog)
      XCTAssertFalse(page.deferred); XCTAssertLessThanOrEqual(page.moved, 8)
      total += page.moved
      if page.complete { return total }
    }
    XCTFail("Bounded fixture did not complete")
    return total
  }
  private func mutateFrames(_ f: Fixture, sql: String) throws {
    var raw: OpaquePointer?
    let id = try f.partitionID(key: key(0))
    guard sqlite3_open(f.partitionURL(id).path, &raw) == SQLITE_OK, let raw else { throw Fault.injected }
    defer { AgentKnowledgeSQLiteStatements.shared.close(raw) }
    guard sqlite3_exec(raw, sql, nil, nil, nil) == SQLITE_OK else { throw Fault.injected }
  }

  func testMixedPartitionMovesBodyAndRetiresOnlyAfterPublication() throws {
    let f = try Fixture()
    try mixed(f)
    let source = try f.partitionID(key: key(0)), oldFile = f.partitionURL(source)
    let page = try f.store.reclaim(catalog: f.catalog)
    XCTAssertEqual(page.moved, 1); XCTAssertEqual(page.removed, 1)
    XCTAssertNotEqual(try f.partitionID(key: key(0)), source)
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
    XCTAssertEqual(try f.store.read(itemHash: key(0), catalog: f.catalog), Data("live".utf8))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_items WHERE encrypted_payload=x'00'"), 1)
    try reopen(f)
    XCTAssertEqual(try drain(f), 0)
    XCTAssertEqual(try f.store.read(itemHash: key(0), catalog: f.catalog), Data("live".utf8))
  }

  func testEightRecordPagesResumeFromRemainingSourceReferences() throws {
    let f = try Fixture()
    try mixed(f, count: 20)
    let source = try f.partitionID(key: key(0))
    let first = try f.store.reclaim(catalog: f.catalog)
    XCTAssertEqual(first.moved, 8); XCTAssertFalse(first.complete)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_refs WHERE partition_id='\(source)'"), 12)
    XCTAssertEqual(try f.scalar("SELECT sealed FROM knowledge_primary_partitions WHERE partition_id='\(source)'"), 1)
    try reopen(f)
    XCTAssertEqual(try drain(f), 12)
    for index in 0..<20 { XCTAssertEqual(try f.store.read(itemHash: key(index), catalog: f.catalog), Data("live".utf8)) }
  }

  func testBetweenPageDeletionAndReplacementWinWithoutResurrection() throws {
    let f = try Fixture()
    try mixed(f, count: 20)
    XCTAssertEqual(try f.store.reclaim(catalog: f.catalog).moved, 8)
    try f.sql("DELETE FROM knowledge_items WHERE item_hash='\(key(19))'")
    try f.write(Data("replacement".utf8), key: key(18))
    XCTAssertEqual(try drain(f), 10)
    XCTAssertNil(try f.store.read(itemHash: key(19), catalog: f.catalog))
    XCTAssertEqual(try f.store.read(itemHash: key(18), catalog: f.catalog), Data("replacement".utf8))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_items"), 19)
  }

  func testMultiframeBinaryBodyRetainsCompleteHashAfterRelocation() throws {
    let f = try Fixture(), body = Data((0..<300_001).map { UInt8(truncatingIfNeeded: $0 * 73) })
    try mixed(f, body: body)
    XCTAssertEqual(try drain(f), 1)
    try reopen(f)
    XCTAssertEqual(try f.store.read(itemHash: key(0), catalog: f.catalog), body)
  }

  func testHealthyCandidateLeavesQueueAndLaterDeletionReenqueuesIt() throws {
    let f = try Fixture()
    for index in 0..<4 { try f.write(Data("healthy".utf8), key: key(index)) }
    let source = try f.partitionID(key: key(0))
    XCTAssertEqual(try drain(f), 0)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_dirty"), 0)
    for index in 2..<4 { try f.sql("DELETE FROM knowledge_items WHERE item_hash='\(key(index))'") }
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_dirty WHERE partition_id='\(source)'"), 1)
    XCTAssertEqual(try drain(f), 2)
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.partitionURL(source).path))
  }

  func testFrameCommitFailureRollsBackCatalogAndCanResume() throws {
    var armed = false
    let f = try Fixture(beforePartitionCommit: { _ in if armed { throw Fault.injected } })
    try mixed(f)
    let source = try f.partitionID(key: key(0))
    armed = true
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try f.partitionID(key: key(0)), source)
    XCTAssertEqual(sqlite3_get_autocommit(f.catalog), 1)
    try reopen(f)
    XCTAssertEqual(try drain(f), 1)
  }

  func testPhysicalCommitBeforeCatalogFailureKeepsOldReferenceAuthoritative() throws {
    var armed = false, physical = 0
    let f = try Fixture(beforeCatalogPublication: { if armed { XCTAssertGreaterThan(physical, 0); throw Fault.injected } },
      beforePartitionCommit: { _ in if armed { physical += 1 } })
    try mixed(f)
    let source = try f.partitionID(key: key(0))
    armed = true
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try f.partitionID(key: key(0)), source)
    XCTAssertEqual(try f.store.read(itemHash: key(0), catalog: f.catalog), Data("live".utf8))
    try reopen(f)
    XCTAssertEqual(try drain(f), 1)
  }

  func testCooperativeCancellationDoesNotPublishPartialFrames() throws {
    let f = try Fixture(), body = Data(repeating: 65, count: 64 * 1_024 * 30)
    try mixed(f, body: body)
    let source = try f.partitionID(key: key(0))
    var checks = 0
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog) {
      checks += 1; if checks == 20 { throw CancellationError() }
    })
    XCTAssertEqual(try f.partitionID(key: key(0)), source)
    XCTAssertEqual(sqlite3_get_autocommit(f.catalog), 1)
    XCTAssertEqual(try drain(f), 1)
    XCTAssertEqual(try f.store.read(itemHash: key(0), catalog: f.catalog), body)
  }

  func testCorruptAndOversizedFrameRejectWithoutPublishingDestination() throws {
    for sql in ["UPDATE frames SET sealed=x'00'", "UPDATE frames SET sealed=zeroblob(196609)"] {
      let f = try Fixture()
      try mixed(f)
      let source = try f.partitionID(key: key(0))
      try mutateFrames(f, sql: sql)
      XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
      XCTAssertEqual(try f.partitionID(key: key(0)), source)
      XCTAssertTrue(FileManager.default.fileExists(atPath: f.partitionURL(source).path))
      XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_retired"), 0)
    }
  }

  func testAuthenticatedReferenceFailureLeavesSourceRegistered() throws {
    let f = try Fixture()
    try mixed(f)
    let source = try f.partitionID(key: key(0))
    try f.sql("UPDATE knowledge_primary_refs SET sealed_ref=x'00'")
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try f.partitionID(key: key(0)), source)
    XCTAssertEqual(try f.scalar("SELECT sealed FROM knowledge_primary_partitions WHERE partition_id='\(source)'"), 0)
  }

  func testIndependentSnapshotDefersCompactionAndUnlink() throws {
    let f = try Fixture()
    try mixed(f)
    var snapshot: AgentKnowledgePrimaryPartitions.SnapshotLease? = try f.store.snapshotLease()
    let page = try f.store.reclaim(catalog: f.catalog)
    XCTAssertTrue(page.deferred); XCTAssertEqual(page.moved, 0)
    withExtendedLifetime(snapshot) {}; snapshot = nil
    XCTAssertEqual(try drain(f), 1)
  }

  func testCatalogCommitSurvivesFailureBeforePhysicalUnlink() throws {
    let f = try Fixture()
    try mixed(f)
    let source = try f.partitionID(key: key(0))
    try reopen(f, beforeRetiredUnlink: { throw Fault.injected })
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertNotEqual(try f.partitionID(key: key(0)), source)
    XCTAssertEqual(try f.store.read(itemHash: key(0), catalog: f.catalog), Data("live".utf8))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_retired WHERE partition_id='\(source)'"), 1)
    try reopen(f)
    XCTAssertEqual(try drain(f), 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.partitionURL(source).path))
  }

  func testLegacyDiscoveryAndCandidateSelectionUseBoundedKeysetPages() throws {
    let f = try Fixture()
    try f.sql("DROP TRIGGER knowledge_primary_dirty_insert")
    let ids = (0..<35).map { String(format: "00000000-0000-4000-8000-%012x", $0) }
    for id in ids { try f.sql("INSERT INTO knowledge_primary_partitions VALUES('\(id)',0,0,0,1)") }
    try AgentKnowledgePrimaryCompaction.setup(f.catalog)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_dirty"), 0)
    try f.sql("BEGIN IMMEDIATE")
    let moved = try AgentKnowledgePrimaryCompaction.advance(f.catalog, checkActive: {}) { _, _ in XCTFail("No live records") }
    XCTAssertEqual(moved, 0)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_retired"), 8)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_dirty"), 24)
    XCTAssertEqual(try f.scalar("SELECT discovered FROM knowledge_primary_compaction"), 0)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_compaction WHERE after_partition='\(ids[31])'"), 1)
    try f.sql("ROLLBACK")
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_partitions"), 35)
  }

  func testCompactionNeverDowngradesExclusivePhysicalLease() throws {
    var armed = false, descriptor: Int32 = -1, probes = 0
    let probe: () throws -> Void = {
      guard armed else { return }
      probes += 1
      XCTAssertEqual(Darwin.flock(descriptor, LOCK_SH | LOCK_NB), -1)
      XCTAssertTrue(errno == EWOULDBLOCK || errno == EAGAIN)
    }
    let f = try Fixture(beforeCatalogPublication: probe, beforePartitionCommit: { _ in try probe() })
    try mixed(f)
    descriptor = Darwin.open(f.store.root.appendingPathComponent(".access.lock").path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
    XCTAssertGreaterThanOrEqual(descriptor, 0)
    defer { if descriptor >= 0 { Darwin.close(descriptor) } }
    armed = true
    XCTAssertEqual(try drain(f), 1)
    XCTAssertGreaterThanOrEqual(probes, 2)
  }

  func testExistingBackgroundStorageSlicePreservesLogicalSourceRevision() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let item = AgentKnowledgeItem(id: "stable", kind: .document, title: "Body", content: "complete body", source: "fixture", updatedAtMillis: 1)
    var previous = item; previous.content = "obsolete body"
    XCTAssertTrue(database.replaceAll([previous])); XCTAssertTrue(database.replaceAll([item]))
    let revision = try database.sourcePage().groups.first?.sourceRevision
    XCTAssertFalse(try database.maintainPrimaryStorageSlice(maximumPages: 8))
    XCTAssertEqual(try database.all(), [item])
    XCTAssertEqual(try database.sourcePage().groups.first?.sourceRevision, revision)
    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    XCTAssertEqual(try reopened.all(), [item])
    XCTAssertEqual(try reopened.sourcePage().groups.first?.sourceRevision, revision)
  }
}
