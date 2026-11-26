import Foundation
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryAllocationsTests: XCTestCase {
  private enum Fault: Error { case boundary }
  private typealias Fixture = AgentKnowledgePrimaryPartitionsTests.Fixture

  private func install(_ f: Fixture, afterIntent: @escaping (String) throws -> Void = { _ in },
                       afterFile: @escaping (String) throws -> Void = { _ in },
                       afterUnlink: @escaping () throws -> Void = {}) throws {
    f.store = nil
    f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets,
      afterRetiredUnlink: afterUnlink, afterAllocationIntent: afterIntent, afterAllocationFile: afterFile)
    try f.store.setup(catalog: f.catalog)
  }
  private func path(_ f: Fixture, _ id: String) -> URL { f.store.root.appendingPathComponent(id + ".sqlite") }

  func testIntentSurvivesCatalogRollbackBeforeAnyBodyFileExists() throws {
    let f = try Fixture()
    var id = ""
    try install(f, afterIntent: { id = $0; throw Fault.boundary })
    XCTAssertThrowsError(try f.write(Data("Interrupted".utf8)))
    XCTAssertFalse(id.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: path(f, id).path))
    XCTAssertTrue(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
    try install(f)
    let recovered = try f.store.reclaim(catalog: f.catalog, pageSize: 1)
    XCTAssertEqual(recovered.removed, 1)
    XCTAssertTrue(recovered.complete)
    XCTAssertFalse(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
  }

  func testCreatedUnpublishedFileIsRecoveredButUnknownLegacyFileIsUntouched() throws {
    let f = try Fixture()
    var id = ""
    try install(f, afterFile: { id = $0; throw Fault.boundary })
    XCTAssertThrowsError(try f.write(Data("Unpublished".utf8)))
    let orphan = path(f, id), unknown = path(f, UUID().uuidString.lowercased())
    let legacy = Data("Unknown legacy file".utf8)
    try legacy.write(to: unknown)
    XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
    try install(f)
    XCTAssertEqual(try f.store.reclaim(catalog: f.catalog).removed, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    XCTAssertEqual(try Data(contentsOf: unknown), legacy)
  }

  func testCommittedReferencedPartitionIsVerifiedAndPreserved() throws {
    let f = try Fixture(), body = Data("Committed".utf8)
    try f.write(body)
    let id = try f.partitionID()
    XCTAssertTrue(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
    let page = try f.store.reclaim(catalog: f.catalog)
    XCTAssertEqual(page.removed, 0)
    XCTAssertTrue(page.complete)
    XCTAssertTrue(FileManager.default.fileExists(atPath: path(f, id).path))
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
    XCTAssertFalse(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
  }

  func testAllocationReplayRespectsTheRequestedPageBound() throws {
    let f = try Fixture(), journal = AgentKnowledgePrimaryAllocations(root: f.store.root)
    for _ in 0..<10 { try journal.remember(UUID().uuidString.lowercased(), syncParent: {}) }
    let first = try f.store.reclaim(catalog: f.catalog, pageSize: 3)
    XCTAssertEqual(first.removed, 3)
    XCTAssertFalse(first.complete)
    var removed = first.removed
    for _ in 0..<3 { removed += try f.store.reclaim(catalog: f.catalog, pageSize: 3).removed }
    XCTAssertEqual(removed, 10)
    XCTAssertFalse(try journal.hasPending())
  }

  func testSnapshotLeaseDefersAllocationRecovery() throws {
    let f = try Fixture(), journal = AgentKnowledgePrimaryAllocations(root: f.store.root)
    try journal.remember(UUID().uuidString.lowercased(), syncParent: {})
    var lease: AgentKnowledgePrimaryPartitions.SnapshotLease? = try f.store.snapshotLease()
    try withExtendedLifetime(lease) {
      XCTAssertTrue(try f.store.reclaim(catalog: f.catalog).deferred)
      XCTAssertTrue(try journal.hasPending())
    }
    lease = nil
    XCTAssertEqual(try f.store.reclaim(catalog: f.catalog).removed, 1)
  }

  func testNonregularSidecarPreventsEveryUnlinkAndRetainsIntent() throws {
    let f = try Fixture(), journal = AgentKnowledgePrimaryAllocations(root: f.store.root)
    let id = UUID().uuidString.lowercased()
    try journal.remember(id, syncParent: {})
    let main = path(f, id), wal = URL(fileURLWithPath: main.path + "-wal")
    let victim = f.directory.appendingPathComponent("victim")
    let bytes = Data("Preserve all members".utf8)
    try bytes.write(to: main); try bytes.write(to: wal); try bytes.write(to: victim)
    try FileManager.default.createSymbolicLink(atPath: main.path + "-shm", withDestinationPath: victim.path)
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try Data(contentsOf: main), bytes)
    XCTAssertEqual(try Data(contentsOf: wal), bytes)
    XCTAssertEqual(try Data(contentsOf: victim), bytes)
    XCTAssertTrue(try journal.hasPending())
  }

  func testUnlinkBeforeJournalCommitReplaysIdempotentlyAfterReopen() throws {
    let f = try Fixture()
    var id = ""
    try install(f, afterFile: { id = $0; throw Fault.boundary })
    XCTAssertThrowsError(try f.write(Data("Interrupted".utf8)))
    let orphan = path(f, id)
    try install(f, afterUnlink: { throw Fault.boundary })
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    XCTAssertTrue(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
    try install(f)
    XCTAssertTrue(try f.store.reclaim(catalog: f.catalog).complete)
    XCTAssertFalse(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
  }

  func testMissingReferencedMainFileRetainsItsIntentAndCatalogReference() throws {
    let f = try Fixture()
    try f.write(Data("Committed".utf8))
    let id = try f.partitionID(), file = path(f, id)
    f.store = nil
    try FileManager.default.removeItem(at: file)
    try install(f)
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertTrue(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_refs"), 1)
  }

  func testInvalidIntentAndNonregularJournalDoNotCreateOrDeleteBodyFiles() throws {
    let f = try Fixture(), journal = AgentKnowledgePrimaryAllocations(root: f.store.root)
    XCTAssertThrowsError(try journal.remember("../outside", syncParent: {}))
    let file = f.store.root.appendingPathComponent(".allocations.sqlite")
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
    XCTAssertThrowsError(try f.write(Data("Rejected".utf8)))
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_refs"), 0)
  }

  func testAlreadyUnlinkedRetirementIsNotCountedAsAnOrphanAgain() throws {
    let f = try Fixture()
    try f.write(Data("Retired".utf8))
    let id = try f.partitionID(), file = path(f, id)
    try f.sql("DELETE FROM knowledge_items")
    try f.sql("INSERT INTO knowledge_primary_retired(partition_id) VALUES('\(id)')")
    try f.sql("DELETE FROM knowledge_primary_partitions WHERE partition_id='\(id)'")
    f.store = nil
    try FileManager.default.removeItem(at: file)
    try install(f)
    let page = try f.store.reclaim(catalog: f.catalog)
    XCTAssertEqual(page.removed, 1)
    XCTAssertTrue(page.complete)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_retired"), 0)
    XCTAssertFalse(try AgentKnowledgePrimaryAllocations(root: f.store.root).hasPending())
  }
}
