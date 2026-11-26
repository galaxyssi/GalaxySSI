import CryptoKit
import Foundation
import SQLite3
import XCTest
@testable import GalaxySSI

// Build the actual pre-primary physical format without changing logical rows or revisions.
func seedLegacyKnowledgePayloads(_ items: [AgentKnowledgeItem], url: URL, secrets: GalaxySSISecretStore,
                                externalIDs: Set<String> = []) throws {
  let encodedKey = try XCTUnwrap(secrets.string(account: "agent.knowledge.index.hmac256.v1"))
  let indexKey = SymmetricKey(data: try XCTUnwrap(Data(base64Encoded: encodedKey)))
  let cipher = GalaxySSIAttachmentAtRestCipher(secrets: secrets, keyAccount: "agent.knowledge.row.aes256.v1")
  let namespace = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
  var raw: OpaquePointer?
  guard sqlite3_open(url.path, &raw) == SQLITE_OK, let database = raw else { throw AgentKnowledgeDatabaseError.unavailable }
  defer { sqlite3_close_v2(database) }
  guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  var committed = false
  defer { if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) } }
  let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  for item in items {
    let hash = HMAC<SHA256>.authenticationCode(for: Data(item.id.utf8), using: indexKey).map { String(format: "%02x", $0) }.joined()
    let plain = try JSONEncoder.galaxySSI.encode(item)
    let digest = SHA256.hash(data: plain).map { String(format: "%02x", $0) }.joined()
    let fileName = "\(hash)-\(digest.prefix(16)).saenc"
    let external = externalIDs.contains(item.id)
    let encrypted: Data
    if external {
      let path = URL(fileURLWithPath: url.path + ".payloads", isDirectory: true).appendingPathComponent(fileName)
      try cipher.write(plain, to: path, purpose: "agent-knowledge-external-payload:v1:\(namespace):\(hash)")
      encrypted = Data([0])
    } else { encrypted = try cipher.encrypt(plain, purpose: "agent-knowledge:\(hash)") }
    guard sqlite3_exec(database, "DELETE FROM knowledge_primary_refs WHERE item_hash='\(hash)'", nil, nil, nil) == SQLITE_OK,
          sqlite3_exec(database, "DELETE FROM knowledge_external_payloads WHERE item_hash='\(hash)'", nil, nil, nil) == SQLITE_OK else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    if external {
      let sql = "INSERT INTO knowledge_external_payloads VALUES('\(hash)','\(fileName)',\(plain.count),'\(digest)')"
      guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    var update: OpaquePointer?
    guard sqlite3_prepare_v2(database, "UPDATE knowledge_items SET encrypted_payload=? WHERE item_hash=?", -1, &update, nil) == SQLITE_OK else {
      throw AgentKnowledgeDatabaseError.unavailable
    }
    encrypted.withUnsafeBytes { sqlite3_bind_blob(update, 1, $0.baseAddress, Int32($0.count), transient) }
    hash.withCString { sqlite3_bind_text(update, 2, $0, -1, transient) }
    let saved = sqlite3_step(update) == SQLITE_DONE && sqlite3_changes(database) == 1
    sqlite3_finalize(update)
    guard saved else { throw AgentKnowledgeDatabaseError.unavailable }
  }
  guard sqlite3_exec(database, "UPDATE knowledge_primary_migration SET after_item_hash='',complete=0", nil, nil, nil) == SQLITE_OK,
        sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
  committed = true
}

final class AgentKnowledgePrimaryPartitionsTests: XCTestCase {
  private final class Fixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let secrets = InMemorySecretStore()
    var catalog: OpaquePointer!
    var store: AgentKnowledgePrimaryPartitions!
    var url: URL { directory.appendingPathComponent("knowledge.sqlite") }
    let key = String(repeating: "a", count: 64)

    init(bytes: Int64 = 64 * 1_024 * 1_024, records: Int64 = 65_536) throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var raw: OpaquePointer?
      guard sqlite3_open(url.path, &raw) == SQLITE_OK, let raw else { throw AgentKnowledgeDatabaseError.unavailable }
      catalog = raw
      try sql("PRAGMA journal_mode=WAL")
      try sql("CREATE TABLE knowledge_items(item_hash TEXT PRIMARY KEY,encrypted_payload BLOB NOT NULL)")
      store = AgentKnowledgePrimaryPartitions(catalogURL: url, secrets: secrets, partitionBytes: bytes, partitionRecords: records)
      try store.setup(catalog: catalog)
    }
    deinit {
      store = nil
      if let catalog { sqlite3_close_v2(catalog) }
      try? FileManager.default.removeItem(at: directory)
    }
    func sql(_ sql: String) throws {
      guard sqlite3_exec(catalog, sql, nil, nil, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
    }
    func scalar(_ sql: String) throws -> Int64 {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(catalog, sql, -1, &statement, nil) == SQLITE_OK else { throw AgentKnowledgeDatabaseError.unavailable }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW else { throw AgentKnowledgeDatabaseError.unavailable }
      return sqlite3_column_int64(statement, 0)
    }
    func write(_ plain: Data, key: String? = nil) throws {
      let key = key ?? self.key
      try sql("BEGIN IMMEDIATE TRANSACTION")
      var committed = false
      defer { if !committed { try? sql("ROLLBACK") } }
      try sql("DELETE FROM knowledge_items WHERE item_hash='\(key)'")
      try sql("INSERT INTO knowledge_items VALUES('\(key)',x'00')")
      try store.append(plain, itemHash: key, catalog: catalog)
      try sql("COMMIT")
      committed = true
    }
    func partitionID() throws -> String {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(catalog, "SELECT partition_id FROM knowledge_primary_refs WHERE item_hash='\(key)'", -1, &statement, nil) == SQLITE_OK else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
        throw AgentKnowledgeDatabaseError.unavailable
      }
      return String(cString: text)
    }
    func partitionURL(_ id: String) -> URL { store.root.appendingPathComponent(id + ".sqlite") }
  }

  func testFrameCodecRoundTripsCompressedRawAndBinaryBoundaries() throws {
    for data in [Data([0]), Data(repeating: 65, count: 64 * 1_024), Data((0..<65_536).map { UInt8(truncatingIfNeeded: $0 * 73) })] {
      XCTAssertEqual(try AgentKnowledgePrimaryFrameCodec.decode(AgentKnowledgePrimaryFrameCodec.encode(data)), data)
    }
    XCTAssertThrowsError(try AgentKnowledgePrimaryFrameCodec.encode(Data()))
    XCTAssertThrowsError(try AgentKnowledgePrimaryFrameCodec.encode(Data(count: 65_537)))
    let oversized = try JSONSerialization.data(withJSONObject: ["version": 1, "codec": "raw", "plainBytes": 65_537, "payload": "AA=="])
    XCTAssertThrowsError(try AgentKnowledgePrimaryFrameCodec.decode(oversized))
  }

  func testCompleteMultiFrameRecordsReopenWithTheSameNamespace() throws {
    let f = try Fixture()
    let plain = Data(String(repeating: "record \u{1F680}\u{4E2D}", count: 20_000).utf8)
    try f.write(plain)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), plain)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_refs"), 1)
    f.store = nil
    f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets)
    try f.store.setup(catalog: f.catalog)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), plain)
  }

  func testPartitionRotationUsesFourBucketsAndAppendTargetsNotCorpusLimits() throws {
    let f = try Fixture(bytes: 1, records: 1)
    for bucket in 0..<4 {
      for ordinal in 0..<3 {
        let key = String(format: "%02x", bucket + ordinal * 4) + String(repeating: "a", count: 62)
        let data = Data("\(bucket)-\(ordinal)".utf8)
        try f.write(data, key: key)
        XCTAssertEqual(try f.store.read(itemHash: key, catalog: f.catalog), data)
      }
    }
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_partitions"), 12)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_partitions WHERE sealed=0"), 4)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_refs"), 12)
  }

  func testCatalogPublicationFailureLeavesThePreviousRecordReadable() throws {
    let f = try Fixture()
    let original = Data("original".utf8)
    try f.write(original)
    f.store = nil
    f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets,
      beforeCatalogPublication: { throw AgentKnowledgeDatabaseError.unavailable })
    try f.store.setup(catalog: f.catalog)
    XCTAssertThrowsError(try f.write(Data("unpublished".utf8)))
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), original)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_refs"), 1)
  }

  func testOldCatalogSnapshotStillReadsTheOriginalImmutableFrames() throws {
    let f = try Fixture(records: 1)
    let old = Data("old body".utf8), replacement = Data("new body".utf8)
    try f.write(old)
    var snapshot: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(f.url.path, &snapshot, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil), SQLITE_OK)
    let handle = try XCTUnwrap(snapshot)
    defer { sqlite3_exec(handle, "ROLLBACK", nil, nil, nil); sqlite3_close_v2(handle) }
    XCTAssertEqual(sqlite3_exec(handle, "BEGIN", nil, nil, nil), SQLITE_OK)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: handle), old)
    try f.write(replacement)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: handle), old)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), replacement)
  }

  func testReclaimDefersUntilTheOldCatalogSnapshotCloses() throws {
    let f = try Fixture(records: 1)
    let old = Data("old pinned body".utf8), fresh = Data("replacement body".utf8)
    try f.write(old)
    let retired = try f.partitionID()
    do {
      let lease = try f.store.snapshotLease()
      defer { withExtendedLifetime(lease) {} }
      var snapshot: OpaquePointer?
      XCTAssertEqual(sqlite3_open_v2(f.url.path, &snapshot, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil), SQLITE_OK)
      let handle = try XCTUnwrap(snapshot)
      defer { sqlite3_exec(handle, "ROLLBACK", nil, nil, nil); sqlite3_close_v2(handle) }
      XCTAssertEqual(sqlite3_exec(handle, "BEGIN", nil, nil, nil), SQLITE_OK)
      XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: handle), old)
      try f.write(fresh)
      let page = try f.store.reclaim(catalog: f.catalog)
      XCTAssertTrue(page.deferred)
      XCTAssertEqual(page.removed, 0)
      XCTAssertTrue(FileManager.default.fileExists(atPath: f.partitionURL(retired).path))
      XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: handle), old)
    }
    let page = try f.store.reclaim(catalog: f.catalog)
    XCTAssertFalse(page.deferred)
    XCTAssertTrue(page.complete)
    XCTAssertEqual(page.removed, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.partitionURL(retired).path))
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), fresh)
  }

  func testAnotherStoreLeaseDefersReclaimWithoutBreakingReads() throws {
    let f = try Fixture(records: 1)
    try f.write(Data("original".utf8))
    var other: AgentKnowledgePrimaryPartitions? = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets)
    try other?.setup(catalog: f.catalog)
    let fresh = Data("fresh".utf8)
    try f.write(fresh)
    XCTAssertTrue(try f.store.reclaim(catalog: f.catalog).deferred)
    XCTAssertEqual(try other?.read(itemHash: f.key, catalog: f.catalog), fresh)
    withExtendedLifetime(other) {}
    other = nil
    XCTAssertEqual(try f.store.reclaim(catalog: f.catalog).removed, 1)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), fresh)
  }

  func testRetirementQueueResumesBeforeAndAfterPhysicalUnlink() throws {
    for afterUnlink in [false, true] {
      let f = try Fixture(records: 1)
      try f.write(Data("obsolete".utf8))
      let retired = try f.partitionID()
      let fresh = Data("still live".utf8)
      try f.write(fresh)
      f.store = nil
      f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets,
        beforeRetiredUnlink: { if !afterUnlink { throw AgentKnowledgeDatabaseError.unavailable } },
        afterRetiredUnlink: { if afterUnlink { throw AgentKnowledgeDatabaseError.unavailable } })
      try f.store.setup(catalog: f.catalog)
      XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
      XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_retired"), 1)
      XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_partitions"), 1)
      XCTAssertEqual(FileManager.default.fileExists(atPath: f.partitionURL(retired).path), !afterUnlink)
      XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), fresh)
      f.store = nil
      f.store = AgentKnowledgePrimaryPartitions(catalogURL: f.url, secrets: f.secrets)
      try f.store.setup(catalog: f.catalog)
      XCTAssertTrue(try f.store.reclaim(catalog: f.catalog).complete)
      XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_retired"), 0)
      XCTAssertFalse(FileManager.default.fileExists(atPath: f.partitionURL(retired).path))
      XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), fresh)
    }
  }

  func testReclaimRejectsLiveReferencesTraversalAndSymlinkTargets() throws {
    let f = try Fixture()
    let plain = Data("live".utf8)
    try f.write(plain)
    let live = try f.partitionID()
    try f.sql("INSERT INTO knowledge_primary_retired VALUES('\(live)')")
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), plain)
    try f.sql("DELETE FROM knowledge_primary_retired")
    try f.sql("INSERT INTO knowledge_primary_retired VALUES('../outside')")
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    try f.sql("DELETE FROM knowledge_primary_retired")
    let id = UUID().uuidString.lowercased()
    let outside = f.directory.appendingPathComponent("outside.txt")
    try Data("untouched".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: f.partitionURL(id), withDestinationURL: outside)
    try f.sql("INSERT INTO knowledge_primary_retired VALUES('\(id)')")
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    XCTAssertEqual(try Data(contentsOf: outside), Data("untouched".utf8))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_retired"), 1)
  }

  func testReclaimIsPagedAndNeverDropsALivePartitionOrUnknownFile() throws {
    let f = try Fixture(records: 1)
    for ordinal in 0..<4 { try f.write(Data("body \(ordinal)".utf8)) }
    let unknown = f.partitionURL(UUID().uuidString.lowercased())
    try Data("not registered".utf8).write(to: unknown)
    let first = try f.store.reclaim(catalog: f.catalog, pageSize: 1)
    XCTAssertEqual(first.removed, 1)
    XCTAssertFalse(first.complete)
    XCTAssertEqual(try f.store.reclaim(catalog: f.catalog, pageSize: 1).removed, 1)
    XCTAssertTrue(try f.store.reclaim(catalog: f.catalog, pageSize: 1).complete)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM knowledge_primary_partitions"), 1)
    XCTAssertEqual(try f.store.read(itemHash: f.key, catalog: f.catalog), Data("body 3".utf8))
    XCTAssertEqual(try Data(contentsOf: unknown), Data("not registered".utf8))
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog, pageSize: 0))
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog, pageSize: 33))
    try f.sql("BEGIN")
    XCTAssertThrowsError(try f.store.reclaim(catalog: f.catalog))
    try f.sql("ROLLBACK")
  }

  func testReferenceSwapOrMalformedSealedReferenceDoesNotFallBack() throws {
    let f = try Fixture()
    let other = String(repeating: "b", count: 64)
    try f.write(Data("first".utf8))
    try f.write(Data("second".utf8), key: other)
    try f.sql("UPDATE knowledge_primary_refs SET sealed_ref=(SELECT sealed_ref FROM knowledge_primary_refs WHERE item_hash='\(other)') WHERE item_hash='\(f.key)'")
    XCTAssertThrowsError(try f.store.read(itemHash: f.key, catalog: f.catalog))
    try f.sql("UPDATE knowledge_primary_refs SET sealed_ref=x'00' WHERE item_hash='\(other)'")
    XCTAssertThrowsError(try f.store.read(itemHash: other, catalog: f.catalog))
  }

  func testMissingAndCorruptedFramesRejectAnOtherwiseValidReference() throws {
    for mutation in ["DELETE FROM frames WHERE ordinal=0", "UPDATE frames SET sealed=x'00' WHERE ordinal=0"] {
      let f = try Fixture()
      try f.write(Data("protected body".utf8))
      var lookup: OpaquePointer?
      XCTAssertEqual(sqlite3_prepare_v2(f.catalog, "SELECT partition_id FROM knowledge_primary_refs", -1, &lookup, nil), SQLITE_OK)
      XCTAssertEqual(sqlite3_step(lookup), SQLITE_ROW)
      let id = String(cString: try XCTUnwrap(sqlite3_column_text(lookup, 0)))
      sqlite3_finalize(lookup)
      var raw: OpaquePointer?
      let path = f.store.root.appendingPathComponent(id + ".sqlite")
      XCTAssertEqual(sqlite3_open(path.path, &raw), SQLITE_OK)
      XCTAssertEqual(sqlite3_exec(raw, mutation, nil, nil, nil), SQLITE_OK)
      sqlite3_close_v2(raw)
      XCTAssertThrowsError(try f.store.read(itemHash: f.key, catalog: f.catalog))
    }
  }

  func testPersistentNamespaceSurvivesAContainerPathChange() throws {
    let f = try Fixture()
    let data = Data("relocated logical database".utf8)
    try f.write(data)
    f.store = nil
    sqlite3_close_v2(f.catalog)
    f.catalog = nil
    let destination = f.directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: destination) }
    try FileManager.default.copyItem(at: f.directory, to: destination)
    let url = destination.appendingPathComponent("knowledge.sqlite")
    var raw: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &raw), SQLITE_OK)
    let catalog = try XCTUnwrap(raw)
    defer { sqlite3_close_v2(catalog) }
    let moved = AgentKnowledgePrimaryPartitions(catalogURL: url, secrets: f.secrets)
    try moved.setup(catalog: catalog)
    XCTAssertEqual(try moved.read(itemHash: f.key, catalog: catalog), data)
  }

  func testPrimaryMigrationResumesWithoutChangingSourcesVectorsOrLogicalRecords() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("knowledge.sqlite"), secrets = InMemorySecretStore()
    let database = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    let items = (0..<11).map { index in AgentKnowledgeItem(id: "item-\(index)", kind: .document, title: "Record",
      content: index == 0 ? "small vector body" : String(repeating: "unicode \u{4E2D}\u{1F680} ", count: 8_000),
      source: "source", updatedAtMillis: Int64(index + 1)) }
    XCTAssertTrue(database.replaceAll(items))
    try seedLegacyKnowledgePayloads(items, url: url, secrets: secrets, externalIDs: [items[1].id])
    let source = try XCTUnwrap(database.sourcePage().groups.first)
    let item = items[0], model = String(repeating: "b", count: 64)
    let checkpoint = AgentKnowledgeVectorCheckpoint(itemId: item.id, sourceRevision: AgentKnowledgeVectorCheckpoint.sourceRevision(for: item),
      chunkIndex: 0, vector: [0.6, 0.8], provenance: .init(modelSHA256: model, dimensions: 2, contextTokens: 512,
        chunkingContract: AgentKnowledgeEmbeddingChunker.contract), updatedAtMillis: 10,
      sourceStartUTF16: 0, sourceEndUTF16: item.content.utf16.count)
    XCTAssertTrue(database.storeVectorCheckpoint(checkpoint))
    let savedVector = try database.vectorCheckpoints(itemId: item.id, modelSHA256: model).first
    let feed = try database.vectorChangePage(modelSHA256: model)
    let first = try database.maintainPrimaryPayloads(pageSize: 2)
    XCTAssertEqual(first.visited, 2)
    XCTAssertEqual(first.moved, 2)
    XCTAssertFalse(first.complete)
    let reopened = AgentKnowledgeDatabase(fileURL: url, secrets: secrets)
    var page = try reopened.maintainPrimaryPayloads(pageSize: 2)
    while !page.complete {
      XCTAssertLessThanOrEqual(page.visited, 2)
      page = try reopened.maintainPrimaryPayloads(pageSize: 2)
    }
    XCTAssertEqual(try reopened.all(), items)
    XCTAssertEqual(try reopened.sourcePage().groups.first?.sourceRevision, source.sourceRevision)
    XCTAssertEqual(try reopened.vectorChangePage(modelSHA256: model).headSequence, feed.headSequence)
    XCTAssertEqual(try reopened.vectorChangePage(modelSHA256: model).epoch, feed.epoch)
    XCTAssertEqual(try reopened.vectorCheckpoints(itemId: item.id, modelSHA256: model).first, savedVector)
    XCTAssertEqual(try reopened.maintainPrimaryPayloads().moved, 0)
  }

  func testDatabaseUsesPrimaryReferencesForSmallAndLargeNewWrites() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = AgentKnowledgeDatabase(fileURL: directory.appendingPathComponent("knowledge.sqlite"), secrets: InMemorySecretStore())
    let items = [AgentKnowledgeItem(id: "small", kind: .note, title: "Small", content: "body", source: "test", updatedAtMillis: 1),
      AgentKnowledgeItem(id: "large", kind: .document, title: "Large", content: String(repeating: "payload ", count: 20_000), source: "test", updatedAtMillis: 2)]
    XCTAssertTrue(database.replaceAll(items))
    XCTAssertEqual(try database.all(), items)
    XCTAssertTrue(try database.maintainExternalPayloads())
    XCTAssertEqual(try database.all(), items)
    XCTAssertThrowsError(try database.maintainPrimaryPayloads(pageSize: 0))
    XCTAssertThrowsError(try database.maintainPrimaryPayloads(pageSize: 33))
  }
}
