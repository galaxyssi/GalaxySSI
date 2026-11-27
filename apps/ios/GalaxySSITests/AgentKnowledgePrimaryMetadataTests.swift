import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

final class AgentKnowledgePrimaryMetadataTests: XCTestCase {
  private typealias Fixture = AgentKnowledgePrimaryPartitionsTests.Fixture
  private enum Fault: Error { case injected }
  private let header = Data("synthetic encrypted header".utf8)
  private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
  private func stage(_ f: Fixture, body: Data, header: Data) throws {
    let pointer = try AgentKnowledgePrimaryMetadata.pointer(header)
    try f.sql("DELETE FROM knowledge_items WHERE item_hash='\(f.key)'")
    try f.sql("INSERT INTO knowledge_items VALUES('\(f.key)',x'\(hex(pointer))')")
    try f.store.append(body, itemHash: f.key, catalog: f.catalog, header: header)
  }
  private func write(_ f: Fixture, body: Data, header: Data) throws {
    try f.sql("BEGIN IMMEDIATE")
    var committed = false
    defer { if !committed { try? f.sql("ROLLBACK") } }
    try stage(f, body: body, header: header)
    try f.sql("COMMIT"); committed = true
  }
  private func resolved(_ f: Fixture) throws -> AgentKnowledgePrimaryMetadata.Resolved {
    try XCTUnwrap(f.store.resolveHeader(itemHash: f.key, catalog: f.catalog, stored: AgentKnowledgePrimaryMetadata.pointer(header)))
  }
  private func reopen(_ f: Fixture, beforePublication: @escaping () throws -> Void = {}) throws {
    f.store = nil
    f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets, beforeCatalogPublication: beforePublication)
    try f.store.setup(catalog: f.catalog)
  }
  private func physical(_ f: Fixture, _ id: String, _ sql: String) throws -> Int64 {
    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open(f.partitionURL(id).path, &raw), SQLITE_OK)
    let database = try XCTUnwrap(raw)
    defer { AgentKnowledgeSQLiteStatements.shared.close(database) }
    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
    let row = try XCTUnwrap(statement)
    defer { sqlite3_finalize(row) }
    let status = sqlite3_step(row)
    guard status == SQLITE_ROW || status == SQLITE_DONE else { throw Fault.injected }
    return status == SQLITE_ROW ? sqlite3_column_int64(row, 0) : 0
  }
  private func finish(_ f: Fixture) throws -> Int {
    var moved = 0
    for _ in 0..<32 {
      let page = try f.store.reclaim(catalog: f.catalog); moved += page.moved
      if page.complete { return moved }
    }
    XCTFail("Metadata fixture did not finish"); return moved
  }

  func testPointerIsFixedLengthAndMalformedTokensFailClosed() throws {
    let pointer = try AgentKnowledgePrimaryMetadata.pointer(header)
    XCTAssertEqual(pointer.count, 69)
    XCTAssertEqual(try AgentKnowledgePrimaryMetadata.pointerHash(pointer), try AgentKnowledgePrimaryMetadata.hash(header))
    XCTAssertNil(try AgentKnowledgePrimaryMetadata.pointerHash(Data([0])))
    for value in ["khp1:", "khp1:" + String(repeating: "G", count: 64), "khp1:" + String(repeating: "a", count: 65)] {
      XCTAssertThrowsError(try AgentKnowledgePrimaryMetadata.pointerHash(Data(value.utf8)))
    }
    XCTAssertThrowsError(try AgentKnowledgePrimaryMetadata.hash(Data()))
    XCTAssertThrowsError(try AgentKnowledgePrimaryMetadata.hash(Data(count: 4_097)))
  }
  func testHeaderOnlyResolutionDoesNotMaterializeBodyFrames() throws {
    let f = try Fixture()
    try write(f, body: Data("body".utf8), header: header)
    let id = try f.partitionID()
    _ = try physical(f, id, "UPDATE frames SET sealed=x'00'")
    XCTAssertEqual(try resolved(f).encrypted, header)
    XCTAssertThrowsError(try f.store.read(itemHash: f.key, catalog: f.catalog))
    XCTAssertEqual(try physical(f, id, "PRAGMA user_version"), 2)
  }
  func testPendingOwnedBatchReadsHeaderWithoutIndependentReaderSlot() throws {
    let slots = AgentKnowledgePrimaryReaderSlots(capacity: 1), f = try Fixture(readerSlots: slots)
    let occupied = try slots.acquire(); defer { occupied.end() }
    try f.batch {
      try stage(f, body: Data("pending".utf8), header: header)
      XCTAssertEqual(try resolved(f).encrypted, header)
    }
    occupied.end()
    XCTAssertEqual(try resolved(f).encrypted, header)
  }
  func testLegacyVersionZeroReadsUnchangedThenUpgradesOnWrite() throws {
    let f = try Fixture()
    try f.write(Data("legacy".utf8))
    let id = try f.partitionID()
    f.store = nil
    _ = try physicalWithoutStore(f, id, "DROP TABLE headers")
    _ = try physicalWithoutStore(f, id, "PRAGMA user_version=0")
    try reopen(f)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), Data("legacy".utf8))
    XCTAssertNil(try f.store.resolveHeader(itemHash: f.key, catalog: f.catalog, stored: Data([0])))
    XCTAssertEqual(try physical(f, id, "PRAGMA user_version"), 0)
    try write(f, body: Data("new".utf8), header: header)
    XCTAssertEqual(try physical(f, id, "PRAGMA user_version"), 2)
    XCTAssertEqual(try resolved(f).encrypted, header)
  }
  private func physicalWithoutStore(_ f: Fixture, _ id: String, _ sql: String) throws -> Int64 {
    var raw: OpaquePointer?
    let url = URL(fileURLWithPath: f.url.path + ".primary").appendingPathComponent(id + ".sqlite")
    XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
    let database = try XCTUnwrap(raw)
    defer { AgentKnowledgeSQLiteStatements.shared.close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Fault.injected }
    return 0
  }
  func testUnknownPhysicalVersionRejectsReaderAndWriter() throws {
    let f = try Fixture()
    try write(f, body: Data("body".utf8), header: header)
    let id = try f.partitionID()
    f.store = nil; _ = try physicalWithoutStore(f, id, "PRAGMA user_version=3")
    try reopen(f)
    XCTAssertThrowsError(try resolved(f))
    XCTAssertThrowsError(try write(f, body: Data("rejected".utf8), header: header))
  }
  func testMissingOrCorruptHeaderDoesNotFallBackToBodyMetadata() throws {
    for sql in ["DELETE FROM headers", "UPDATE headers SET sealed=x'00'", "UPDATE headers SET sealed=zeroblob(4097)"] {
      let f = try Fixture()
      try write(f, body: Data("body".utf8), header: header)
      _ = try physical(f, f.partitionID(), sql)
      XCTAssertThrowsError(try resolved(f))
    }
  }
  func testPointerMismatchAndMissingPointerRejectVersionTwoReference() throws {
    let f = try Fixture()
    try write(f, body: Data("body".utf8), header: header)
    for stored in [Data([0]), try AgentKnowledgePrimaryMetadata.pointer(Data("other".utf8))] {
      XCTAssertThrowsError(try f.store.resolveHeader(itemHash: f.key, catalog: f.catalog, stored: stored))
    }
  }
  func testSmallCompactionPreservesExactEncryptedHeaderAndPointer() throws {
    let f = try Fixture()
    try f.write(Data("dead".utf8)); try write(f, body: Data("live".utf8), header: header)
    let source = try f.partitionID(), pointer = try AgentKnowledgePrimaryMetadata.pointer(header)
    XCTAssertEqual(try finish(f), 1)
    XCTAssertNotEqual(try f.partitionID(), source)
    XCTAssertEqual(try resolved(f).encrypted, header)
    XCTAssertEqual(try AgentKnowledgePrimaryMetadata.pointer(resolved(f).encrypted), pointer)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), Data("live".utf8))
  }
  func testCheckpointedCopyCopiesHeaderBeforeFinalPublicationAndReplaysIdempotently() throws {
    let f = try Fixture(), body = Data(repeating: 65, count: 32 * 65_536 + 17)
    try f.write(Data("dead".utf8)); try write(f, body: body, header: header)
    _ = try f.store.reclaim(catalog: f.catalog)
    let job = try XCTUnwrap(AgentKnowledgePrimaryCopyStore.load(f.catalog))
    for _ in 0..<5 { _ = try f.store.reclaim(catalog: f.catalog) }
    try reopen(f, beforePublication: { throw Fault.injected })
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try f.partitionID(), job.source)
    XCTAssertEqual(try physical(f, job.destination, "SELECT COUNT(*) FROM headers"), 1)
    try reopen(f); XCTAssertEqual(try finish(f), 1)
    XCTAssertEqual(try f.partitionID(), job.destination)
    XCTAssertEqual(try resolved(f).encrypted, header)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), body)
    let bytes = try physical(f, job.destination, "SELECT (SELECT SUM(length(sealed)) FROM frames)+(SELECT SUM(length(sealed)) FROM headers)")
    XCTAssertEqual(try f.scalar("SELECT bytes FROM knowledge_primary_partitions WHERE partition_id='\(job.destination)'"), bytes)
  }
  func testSourceHeaderCorruptionPreventsCompactionPublication() throws {
    let f = try Fixture()
    try f.write(Data("dead".utf8)); try write(f, body: Data("live".utf8), header: header)
    let source = try f.partitionID()
    _ = try physical(f, source, "UPDATE headers SET sealed=x'00'")
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try f.partitionID(), source)
  }
  func testCatalogSnapshotRetainsOldHeaderAndBodyIdentity() throws {
    let f = try Fixture()
    try write(f, body: Data("old".utf8), header: header)
    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(f.url.path, &raw, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil), SQLITE_OK)
    let snapshot = try XCTUnwrap(raw), pointer = try AgentKnowledgePrimaryMetadata.pointer(header)
    defer { sqlite3_exec(snapshot, "ROLLBACK", nil, nil, nil); AgentKnowledgeSQLiteStatements.shared.close(snapshot) }
    XCTAssertEqual(sqlite3_exec(snapshot, "BEGIN", nil, nil, nil), SQLITE_OK)
    let lease = try f.store.snapshotLease(); defer { withExtendedLifetime(lease) {} }
    XCTAssertEqual(try f.store.resolveHeader(itemHash: f.key, catalog: snapshot, stored: pointer)?.encrypted, header)
    try write(f, body: Data("new".utf8), header: Data("new encrypted header".utf8))
    XCTAssertEqual(try f.store.resolveHeader(itemHash: f.key, catalog: snapshot, stored: pointer)?.encrypted, header)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: snapshot), Data("old".utf8))
    XCTAssertTrue(try f.store.reclaim(catalog: f.catalog).deferred)
  }
  func testFailureAfterStagingHeaderAndFramesDoesNotPublishEither() throws {
    var armed = false
    let f = try Fixture(beforePartitionCommit: { _ in if armed { throw Fault.injected } })
    try f.write(Data("old".utf8))
    let id = try f.partitionID()
    armed = true
    XCTAssertThrowsError(try write(f, body: Data("rejected".utf8), header: header))
    try reopen(f)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), Data("old".utf8))
    XCTAssertEqual(try physical(f, id, "SELECT COUNT(*) FROM headers"), 0)
    XCTAssertNil(try f.store.resolveHeader(itemHash: f.key, catalog: f.catalog, stored: Data([0])))
  }
  func testLegacyInlineRecordRemainsReadableWithoutForcedHeaderRewrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let item = AgentKnowledgeItem(id: "legacy", kind: .document, title: "Record", content: "old body", source: "fixture", updatedAtMillis: 1)
    XCTAssertTrue(database.replaceAll([item]))
    try seedLegacyKnowledgePayloads([item], url: url, secrets: secrets)
    XCTAssertEqual(try database.all(), [item])
    let revision = try database.sourceBrowseRevision()
    XCTAssertTrue(try database.maintainPrimaryPayloads().complete)
    XCTAssertEqual(try database.all(), [item])
    XCTAssertEqual(try database.sourceBrowseRevision(), revision)
  }
  func testActualDatabaseUsesPointersAndRejectsIndexTampering() throws {
    for sql in ["UPDATE knowledge_items SET source_hash='wrong'", "UPDATE knowledge_items SET updated_at=99", "UPDATE knowledge_items SET encrypted_payload=x'00'"] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
      let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
      let item = AgentKnowledgeItem(id: "record", kind: .document, title: "Record", content: "body", source: "fixture", updatedAtMillis: 1)
      XCTAssertTrue(database.replaceAll([item])); XCTAssertEqual(try database.all(), [item])
      var raw: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
      let db = try XCTUnwrap(raw); defer { AgentKnowledgeSQLiteStatements.shared.close(db) }
      var row: OpaquePointer?
      XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT length(encrypted_payload) FROM knowledge_items", -1, &row, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(row), SQLITE_ROW); XCTAssertEqual(sqlite3_column_int(row, 0), 69); sqlite3_finalize(row)
      XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
      XCTAssertThrowsError(try database.all())
    }
  }
  func testActualDatabaseRelocationPreservesSourceAndVectorRevisionIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let item = AgentKnowledgeItem(id: "record", kind: .document, title: "Record", content: "new body", source: "fixture", updatedAtMillis: 2)
    var old = item; old.content = "old body"
    XCTAssertTrue(database.replaceAll([old])); XCTAssertTrue(database.replaceAll([item]))
    let source = try database.sourceBrowseRevision(), model = String(repeating: "b", count: 64)
    let checkpoint = AgentKnowledgeVectorCheckpoint(itemId: item.id, sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0, vector: [0.6, 0.8], provenance: .init(modelSHA256: model, dimensions: 2, contextTokens: 512,
        chunkingContract: AgentKnowledgeEmbeddingChunker.contract), updatedAtMillis: 10, sourceStartUTF16: 0, sourceEndUTF16: item.content.utf16.count)
    XCTAssertTrue(database.storeVectorCheckpoint(checkpoint))
    let savedVector = try database.vectorCheckpoints(itemId: item.id, modelSHA256: model).first
    let head = try database.vectorChangePage(modelSHA256: model)
    XCTAssertFalse(try database.maintainPrimaryStorageSlice(maximumPages: 8))
    XCTAssertEqual(try database.sourceBrowseRevision(), source)
    XCTAssertEqual(try database.vectorChangePage(modelSHA256: model).headSequence, head.headSequence)
    XCTAssertEqual(try database.vectorChangePage(modelSHA256: model).epoch, head.epoch)
    XCTAssertEqual(try database.vectorCheckpoints(itemId: item.id, modelSHA256: model).first, savedVector)
    XCTAssertEqual(try AgentKnowledgeDatabase(fileURL: url, secrets: secrets).all(), [item])
  }
}
