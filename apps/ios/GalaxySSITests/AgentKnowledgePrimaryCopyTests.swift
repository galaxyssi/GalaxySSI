import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryCopyTests: XCTestCase {
  private typealias Fixture = AgentKnowledgePrimaryPartitionsTests.Fixture
  private enum Fault: Error { case injected }
  private let body = Data(repeating: 65, count: 32 * 65_536 + 17)
  private func begin(_ f: Fixture) throws -> AgentKnowledgePrimaryCopyStore.Job {
    try f.write(Data("obsolete".utf8)); try f.write(body)
    XCTAssertEqual(try f.store.reclaim(catalog: f.catalog).moved, 0)
    return try XCTUnwrap(AgentKnowledgePrimaryCopyStore.load(f.catalog))
  }
  private func reopen(_ f: Fixture, beforePublication: @escaping () throws -> Void = {},
                      afterFrame: @escaping (Int) throws -> Void = { _ in }) throws {
    f.store = nil
    f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets,
      beforeCatalogPublication: beforePublication, afterCopyFrame: afterFrame)
    try f.store.setup(catalog: f.catalog)
  }
  private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  private func state(_ f: Fixture) throws -> AgentKnowledgePrimaryCopyState {
    let job = try XCTUnwrap(AgentKnowledgePrimaryCopyStore.load(f.catalog)), identity = sha(Data(f.url.lastPathComponent.utf8))
    let cipher = GalaxySSIAttachmentAtRestCipher(secrets: f.secrets, keyAccount: "agent.knowledge.primary.aes256.v1.\(identity)")
    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(f.catalog, "SELECT sealed FROM knowledge_primary_namespace WHERE id=1", -1, &raw, nil), SQLITE_OK)
    let row = try XCTUnwrap(raw)
    defer { sqlite3_finalize(row) }
    XCTAssertEqual(sqlite3_step(row), SQLITE_ROW)
    let marker = Data(bytes: try XCTUnwrap(sqlite3_column_blob(row, 0)), count: Int(sqlite3_column_bytes(row, 0)))
    let namespace = try XCTUnwrap(String(data: cipher.decrypt(marker, expectedPurpose: "knowledge-primary.namespace.v1:\(identity)"), encoding: .utf8))
    let purpose = "knowledge-primary.v1:\(namespace):reference:\(job.key):copy:v1:\(job.source):\(job.destination):\(sha(job.original))"
    return try JSONDecoder().decode(AgentKnowledgePrimaryCopyState.self, from: cipher.decrypt(job.checkpoint, expectedPurpose: purpose))
  }
  @discardableResult private func finish(_ f: Fixture) throws -> Int {
    var moved = 0
    for _ in 0..<32 {
      let page = try f.store.reclaim(catalog: f.catalog); moved += page.moved
      if page.complete { return moved }
    }
    XCTFail("Copy fixture did not finish"); return moved
  }
  private func destinationSQL(_ f: Fixture, _ job: AgentKnowledgePrimaryCopyStore.Job, _ sql: String) throws -> Int64 {
    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open(f.partitionURL(job.destination).path, &raw), SQLITE_OK)
    let db = try XCTUnwrap(raw)
    defer { AgentKnowledgeSQLiteStatements.shared.close(db) }
    var row: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &row, nil), SQLITE_OK)
    let statement = try XCTUnwrap(row)
    defer { sqlite3_finalize(statement) }
    let status = sqlite3_step(statement)
    guard status == SQLITE_ROW || status == SQLITE_DONE else { throw Fault.injected }
    return status == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : 0
  }

  func testDedicatedDestinationAndBothPartitionsRemainPinned() throws {
    let f = try Fixture(), job = try begin(f)
    XCTAssertNotEqual(job.source, job.destination)
    XCTAssertTrue(try AgentKnowledgePrimaryCopyStore.references(f.catalog, job.source))
    XCTAssertTrue(try AgentKnowledgePrimaryCopyStore.references(f.catalog, job.destination))
    XCTAssertEqual(try f.scalar("SELECT sealed FROM knowledge_primary_partitions WHERE partition_id='\(job.destination)'"), 1)
    XCTAssertEqual(try state(f).copied, 0)
    XCTAssertEqual(try f.partitionID(), job.source)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
  }
  func testCopyAndIndependentVerificationAdvanceAtMostSixteenFramesPerPage() throws {
    let f = try Fixture(), job = try begin(f)
    for copied in [16, 32, 33] {
      XCTAssertEqual(try f.store.reclaim(catalog: f.catalog).moved, 0)
      XCTAssertEqual(try state(f).copied, copied); XCTAssertEqual(try state(f).verified, 0)
      XCTAssertEqual(try f.partitionID(), job.source)
      try reopen(f)
    }
    for verified in [16, 32] {
      XCTAssertEqual(try f.store.reclaim(catalog: f.catalog).moved, 0)
      XCTAssertEqual(try state(f).verified, verified)
      XCTAssertEqual(try f.partitionID(), job.source)
    }
    XCTAssertEqual(try finish(f), 1)
    XCTAssertNil(try AgentKnowledgePrimaryCopyStore.load(f.catalog))
    XCTAssertEqual(try f.partitionID(), job.destination)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
  }
  func testCooperativeYieldCommitsOnlyCompletedFramePrefix() throws {
    let f = try Fixture(); _ = try begin(f)
    var yielded = false
    try reopen(f, afterFrame: { if $0 == 2 { yielded = true } })
    _ = try f.store.reclaim(catalog: f.catalog) { if yielded { throw AgentKnowledgeStorageYield.exhausted } }
    XCTAssertEqual(try state(f).copied, 3)
    try reopen(f)
    XCTAssertEqual(try finish(f), 1)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
  }
  func testHardFrameFailureRollsBackCurrentPageButKeepsOlderCheckpoint() throws {
    let f = try Fixture(); _ = try begin(f)
    _ = try f.store.reclaim(catalog: f.catalog)
    let checkpoint = try XCTUnwrap(AgentKnowledgePrimaryCopyStore.load(f.catalog)).checkpoint
    try reopen(f, afterFrame: { if $0 == 18 { throw CancellationError() } })
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try state(f).copied, 16)
    XCTAssertEqual(try XCTUnwrap(AgentKnowledgePrimaryCopyStore.load(f.catalog)).checkpoint, checkpoint)
    try reopen(f); XCTAssertEqual(try finish(f), 1)
  }
  func testPhysicalCommitBeforeCheckpointFailureTrimsUnpublishedTailOnReplay() throws {
    let f = try Fixture(), job = try begin(f)
    _ = try f.store.reclaim(catalog: f.catalog)
    try reopen(f, beforePublication: { throw Fault.injected })
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try state(f).copied, 16)
    XCTAssertEqual(try destinationSQL(f, job, "SELECT COUNT(*) FROM frames"), 32)
    try reopen(f); _ = try f.store.reclaim(catalog: f.catalog)
    XCTAssertEqual(try state(f).copied, 32)
    XCTAssertEqual(try destinationSQL(f, job, "SELECT COUNT(*) FROM frames"), 32)
    XCTAssertEqual(try finish(f), 1)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
  }
  func testUserReplacementDuringCopyWinsAndDiscardsUnpublishedDestination() throws {
    let f = try Fixture(), job = try begin(f)
    _ = try f.store.reclaim(catalog: f.catalog)
    try f.write(Data("latest".utf8))
    XCTAssertEqual(try finish(f), 0)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), Data("latest".utf8))
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.partitionURL(job.destination).path))
  }
  func testUserDeletionDuringVerificationCannotResurrectTheBody() throws {
    let f = try Fixture(), job = try begin(f)
    for _ in 0..<4 { _ = try f.store.reclaim(catalog: f.catalog) }
    XCTAssertEqual(try state(f).verified, 16)
    try f.sql("DELETE FROM knowledge_items")
    XCTAssertEqual(try finish(f), 0)
    XCTAssertNil(try f.store.read(itemHash: f.key, catalog: f.catalog))
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.partitionURL(job.destination).path))
  }
  func testCorruptCheckpointOrOriginalReferenceFailsClosed() throws {
    for column in ["checkpoint", "original", "destination_partition"] {
      let f = try Fixture(), job = try begin(f)
      let value = column == "destination_partition" ? "'\(UUID().uuidString.lowercased())'" : "x'00'"
      try f.sql("UPDATE knowledge_primary_copy SET \(column)=\(value)")
      XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
      XCTAssertEqual(try f.partitionID(), job.source)
      XCTAssertTrue(FileManager.default.fileExists(atPath: f.partitionURL(job.source).path))
      XCTAssertTrue(FileManager.default.fileExists(atPath: f.partitionURL(job.destination).path))
    }
  }
  func testCorruptVerifiedDestinationFrameNeverPublishes() throws {
    let f = try Fixture(), job = try begin(f)
    for _ in 0..<3 { _ = try f.store.reclaim(catalog: f.catalog) }
    _ = try destinationSQL(f, job, "UPDATE frames SET sealed=x'00' WHERE ordinal=0")
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try state(f).verified, 0)
    XCTAssertEqual(try f.partitionID(), job.source)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
  }
  func testUnexpectedDestinationTailRejectsFinalVerification() throws {
    let f = try Fixture(), job = try begin(f)
    for _ in 0..<3 { _ = try f.store.reclaim(catalog: f.catalog) }
    _ = try destinationSQL(f, job, "INSERT INTO frames SELECT entry_id,33,sealed FROM frames WHERE ordinal=32")
    for _ in 0..<2 { _ = try f.store.reclaim(catalog: f.catalog) }
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try f.partitionID(), job.source)
  }
  func testExactReferenceCompareAndSwapRefusesStalePublication() throws {
    let f = try Fixture(), job = try begin(f)
    try f.sql("UPDATE knowledge_primary_refs SET sealed_ref=x'00'")
    XCTAssertThrowsError(try AgentKnowledgePrimaryCopyStore.publish(f.catalog, job, reference: Data([1])))
    XCTAssertEqual(try f.partitionID(), job.source)
    XCTAssertTrue(try AgentKnowledgePrimaryCopyStore.pending(f.catalog))
  }
  func testPendingJobCannotBeRetiredAndSnapshotStillDefersPages() throws {
    let f = try Fixture(), job = try begin(f)
    XCTAssertThrowsError(try AgentKnowledgePrimaryCompaction.retire(f.catalog, job.destination))
    var lease: AgentKnowledgePrimaryPartitions.SnapshotLease? = try f.store.snapshotLease()
    XCTAssertTrue(try f.store.reclaim(catalog: f.catalog).deferred)
    withExtendedLifetime(lease) {}; lease = nil
    XCTAssertEqual(try state(f).copied, 0)
    XCTAssertEqual(try finish(f), 1)
  }
}
