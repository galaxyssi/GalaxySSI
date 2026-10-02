import SQLite3
import XCTest
@testable import GalaxySSI

final class MqttDurableChunksTests: XCTestCase {
  func testPartialFragmentsAndEpochSurviveDatabaseReopen() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    XCTAssertNil(try f.store.accept(authenticatedScope: "pair", wire: packets[0]))
    let before = try f.state("pair", query)
    XCTAssertEqual(before.storedIndices, [0])
    try f.reopen()
    let after = try f.state("pair", query)
    XCTAssertEqual(after, before)
    var result: String?
    for packet in packets.dropFirst() { result = try f.store.accept(authenticatedScope: "pair", wire: packet) }
    XCTAssertEqual(result, try f.wire())
    try f.reopen()
    XCTAssertEqual(try f.store.recoverComplete(authenticatedScope: "pair", query: query), try f.wire())
  }

  func testRepeatedFragmentsDoNotAdvanceRevisionOrClaimBusinessStorage() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    let before = try f.state("pair", query)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    XCTAssertEqual(try f.state("pair", query), before)
    for packet in packets.dropFirst() { _ = try f.store.accept(authenticatedScope: "pair", wire: packet) }
    let complete = try f.store.snapshot(authenticatedScope: "pair", query: query)
    XCTAssertEqual(try MqttChunkReceipts.parseState(complete.state).storedIndices.count, packets.count)
    XCTAssertNil(complete.proof)
    XCTAssertFalse(try f.store.releaseAfterStore(authenticatedScope: "pair", transfer: query.transfer,
      storedWireHash: String(repeating: "e", count: 64), messageID: "message-1"))
    XCTAssertEqual(try f.store.recoverComplete(authenticatedScope: "pair", query: query), try f.wire())
  }

  func testCommittedInboxProofReleasesPartsButRetainsReplayReceiptAcrossReopen() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    for packet in packets { _ = try f.store.accept(authenticatedScope: "pair", wire: packet) }
    let hash = try f.wireHash()
    XCTAssertTrue(try f.store.releaseAfterStore(authenticatedScope: "pair", transfer: query.transfer,
      storedWireHash: hash, messageID: "committed-message"))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_parts"), 0)
    try f.reopen()
    let snapshot = try f.store.snapshot(authenticatedScope: "pair", query: query)
    XCTAssertEqual(snapshot.proof?.messageID, "committed-message")
    XCTAssertEqual(snapshot.proof?.wireHash, hash)
    XCTAssertEqual(try MqttChunkReceipts.parseState(snapshot.state).storedIndices.count, packets.count)
    XCTAssertNil(try f.store.accept(authenticatedScope: "pair", wire: packets[0]))
    XCTAssertNil(try f.store.recoverComplete(authenticatedScope: "pair", query: query))
    XCTAssertTrue(try f.store.releaseAfterStore(authenticatedScope: "pair", transfer: query.transfer,
      storedWireHash: hash, messageID: "committed-message"))
    XCTAssertFalse(try f.store.releaseAfterStore(authenticatedScope: "pair", transfer: query.transfer,
      storedWireHash: hash, messageID: "different-message"))
  }

  func testFailedMetadataCommitRollsBackNewFragmentAndProgress() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    let before = try f.state("pair", query)
    try f.execute("CREATE TRIGGER reject_progress BEFORE UPDATE ON mqtt_wire_transfers BEGIN SELECT RAISE(ABORT, 'injected'); END")
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "pair", wire: packets[1]))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_parts"), 1)
    XCTAssertEqual(try f.state("pair", query), before)
    try f.execute("DROP TRIGGER reject_progress")
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[1])
    XCTAssertEqual(try f.state("pair", query).storedIndices, [0, 1])
  }

  func testFailedReleaseCommitKeepsAllFragmentsForReplay() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    for packet in packets { _ = try f.store.accept(authenticatedScope: "pair", wire: packet) }
    try f.execute("CREATE TRIGGER reject_release BEFORE UPDATE ON mqtt_wire_transfers BEGIN SELECT RAISE(ABORT, 'injected'); END")
    XCTAssertThrowsError(try f.store.releaseAfterStore(authenticatedScope: "pair", transfer: query.transfer,
      storedWireHash: f.wireHash(), messageID: "committed"))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_parts"), Int64(packets.count))
    XCTAssertNil(try f.store.snapshot(authenticatedScope: "pair", query: query).proof)
    try f.execute("DROP TRIGGER reject_release")
    XCTAssertEqual(try f.store.recoverComplete(authenticatedScope: "pair", query: query), try f.wire())
  }

  func testCorruptPartIsRemovedFromBitmapAndCanBeRetransmitted() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[1])
    let before = try f.state("pair", query)
    try f.execute("UPDATE mqtt_wire_parts SET encrypted_data=zeroblob(length(encrypted_data)) WHERE chunk_index=0")
    let repaired = try f.state("pair", query)
    XCTAssertEqual(repaired.storedIndices, [1])
    XCTAssertEqual(repaired.epoch, before.epoch)
    XCTAssertEqual(repaired.revision, before.revision + 1)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    XCTAssertEqual(try f.state("pair", query).storedIndices, [0, 1])
  }

  func testMatchingRetransmissionRepairsCorruptionWithoutLosingOtherParts() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    let before = try f.state("pair", query)
    try f.execute("UPDATE mqtt_wire_parts SET encrypted_data=zeroblob(length(encrypted_data))")
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    let after = try f.state("pair", query)
    XCTAssertEqual(after.storedIndices, [0])
    XCTAssertEqual(after.revision, before.revision + 1)
  }

  func testWrongKeyAndCorruptManifestFailClosedWithoutEmptyAcknowledgement() throws {
    let f = try ChunkFixture()
    let packet = try f.packets()[0]
    let query = try f.query(packet)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packet)
    XCTAssertThrowsError(try MqttDurableChunks(fileURL: f.url, secrets: InMemorySecretStore()))
    try f.execute("UPDATE mqtt_wire_transfers SET encrypted_metadata=zeroblob(length(encrypted_metadata))")
    XCTAssertThrowsError(try f.store.snapshot(authenticatedScope: "pair", query: query))
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "pair", wire: packet))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_parts"), 1)
  }

  func testStoredBytesCannotBeReassignedToAnotherAuthenticatedScope() throws {
    let f = try ChunkFixture()
    let packet = try f.packets()[0]
    let query = try f.query(packet)
    _ = try f.store.accept(authenticatedScope: "old-key", wire: packet)
    XCTAssertTrue(try f.state("new-key", query).storedIndices.isEmpty)
    let old = MqttRouteProtocol.digest(Data("old-key".utf8))
    let new = MqttRouteProtocol.digest(Data("new-key".utf8))
    _ = try f.store.accept(authenticatedScope: "new-key", wire: packet)
    try f.execute("UPDATE mqtt_wire_parts SET encrypted_data=(SELECT encrypted_data FROM mqtt_wire_parts WHERE scope_digest='\(old)' AND chunk_index=0) WHERE scope_digest='\(new)' AND chunk_index=0")
    XCTAssertTrue(try f.state("new-key", query).storedIndices.isEmpty)
    XCTAssertEqual(try f.state("old-key", query).storedIndices, [0])
  }

  func testExpiryCreatesNewStoreEpochAndDoesNotCarryOldBitmap() throws {
    let f = try ChunkFixture()
    let packets = try f.packets()
    let query = try f.query(packets[0])
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    let first = try f.state("pair", query)
    f.clock.value += MqttDurableChunks.retentionMillis
    let expired = try f.state("pair", query)
    XCTAssertEqual(expired.epoch, String(repeating: "0", count: 32))
    XCTAssertEqual(expired.revision, 0)
    XCTAssertTrue(expired.storedIndices.isEmpty)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[1])
    let next = try f.state("pair", query)
    XCTAssertNotEqual(next.epoch, first.epoch)
    XCTAssertEqual(next.storedIndices, [1])
  }

  func testPeerAndGlobalQuotasReserveWholeTransferAndNeverEvictAcknowledgedParts() throws {
    let f = try ChunkFixture()
    var limits = MqttDurableChunks.Limits()
    limits.transfers = 2
    limits.peerTransfers = 1
    try f.reopen(limits: limits)
    let first = try f.packets()[0]
    let other = try f.packets(body: "other-body")[0]
    _ = try f.store.accept(authenticatedScope: "peer-a", wire: first)
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "peer-a", wire: other))
    _ = try f.store.accept(authenticatedScope: "peer-b", wire: first)
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "peer-c", wire: first))
    XCTAssertEqual(try f.state("peer-a", f.query(first)).storedIndices, [0])
    XCTAssertEqual(try f.state("peer-b", f.query(first)).storedIndices, [0])
    try f.store.forget(authenticatedScope: "peer-a")
    _ = try f.store.accept(authenticatedScope: "peer-c", wire: first)
    XCTAssertTrue(try f.state("peer-a", f.query(first)).storedIndices.isEmpty)
  }

  func testByteQuotaIsCheckedBeforeAnyFragmentIsWritten() throws {
    let f = try ChunkFixture()
    var limits = MqttDurableChunks.Limits()
    limits.bytes = Int64(try f.wire().utf8.count - 1)
    try f.reopen(limits: limits)
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "pair", wire: f.packets()[0]))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_parts"), 0)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_transfers"), 0)
  }

  func testConflictingManifestOrFragmentDoesNotChangePersistedState() throws {
    let f = try ChunkFixture()
    let packet = try f.packets()[0]
    let query = try f.query(packet)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packet)
    let original = try f.state("pair", query)
    var changed = packet
    changed["from"] = "other"
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "pair", wire: changed))
    changed = packet
    let forged = Data(repeating: 0x61, count: 24)
    changed["data"] = forged.base64EncodedString()
    changed["chunk_sha256"] = MqttRouteProtocol.digest(forged)
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "pair", wire: changed))
    XCTAssertEqual(try f.state("pair", query), original)
  }

  func testReassembledEndpointsAndSignalDigestAreCheckedBeforeCommit() throws {
    let f = try ChunkFixture()
    var packets = try f.packets()
    for index in packets.indices { packets[index]["from"] = "forged-source" }
    let query = try f.query(packets[0])
    for packet in packets.dropLast() { _ = try f.store.accept(authenticatedScope: "pair", wire: packet) }
    XCTAssertThrowsError(try f.store.accept(authenticatedScope: "pair", wire: packets.last!))
    XCTAssertEqual(try f.state("pair", query).storedIndices.count, packets.count - 1)
    XCTAssertNil(try f.store.recoverComplete(authenticatedScope: "pair", query: query))
  }

  func testMetadataAndFragmentsAreEncryptedAndClearRemovesBothTables() throws {
    let f = try ChunkFixture()
    let packet = try f.packets()[0]
    _ = try f.store.accept(authenticatedScope: "private-pair-name", wire: packet)
    let metadata = try f.blob("SELECT encrypted_metadata FROM mqtt_wire_transfers")
    let fragment = try f.blob("SELECT encrypted_data FROM mqtt_wire_parts")
    XCTAssertNil(metadata.range(of: Data("phone-sensitive".utf8)))
    XCTAssertNil(metadata.range(of: Data("private-pair-name".utf8)))
    XCTAssertNil(fragment.range(of: try MqttChunkManifest.parse(packet).data))
    try f.store.clear()
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_parts"), 0)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_transfers"), 0)
  }

  func testSeparateConnectionsReadCommittedProgressWithoutStaleCaches() throws {
    let f = try ChunkFixture()
    let clock = f.clock
    let second = try MqttDurableChunks(fileURL: f.url, secrets: f.secrets, now: { clock.value })
    let packets = try f.packets()
    let query = try f.query(packets[0])
    _ = try f.store.accept(authenticatedScope: "pair", wire: packets[0])
    _ = try second.accept(authenticatedScope: "pair", wire: packets[1])
    XCTAssertEqual(try f.state("pair", query).storedIndices, [0, 1])
    XCTAssertEqual(try MqttChunkReceipts.parseState(second.snapshot(authenticatedScope: "pair", query: query).state).storedIndices, [0, 1])
  }

  func testMissingKeyMarkerDoesNotReinitializeNonemptyStorage() throws {
    let f = try ChunkFixture()
    let packet = try f.packets()[0]
    let query = try f.query(packet)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packet)
    try f.execute("DELETE FROM mqtt_chunk_key")
    XCTAssertThrowsError(try f.store.snapshot(authenticatedScope: "pair", query: query))
    XCTAssertThrowsError(try MqttDurableChunks(fileURL: f.url, secrets: f.secrets))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_wire_parts"), 1)
  }

  func testEmptyCorruptPartCanBeExcludedAndRepaired() throws {
    let f = try ChunkFixture()
    let packet = try f.packets()[0]
    let query = try f.query(packet)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packet)
    try f.execute("UPDATE mqtt_wire_parts SET encrypted_data=zeroblob(0)")
    XCTAssertTrue(try f.state("pair", query).storedIndices.isEmpty)
    _ = try f.store.accept(authenticatedScope: "pair", wire: packet)
    XCTAssertEqual(try f.state("pair", query).storedIndices, [0])
  }
}

final class ChunkTestClock { var value: Int64 = 1000 }

final class ChunkFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("mqtt-chunks-\(UUID().uuidString)", isDirectory: true)
  let secrets = InMemorySecretStore()
  let clock = ChunkTestClock()
  var store: MqttDurableChunks!
  var url: URL { root.appendingPathComponent("chunks.sqlite") }

  init() throws { try reopen() }
  deinit { store = nil; try? FileManager.default.removeItem(at: root) }

  func reopen(limits: MqttDurableChunks.Limits = .init()) throws {
    store = nil
    let clock = self.clock
    store = try MqttDurableChunks(fileURL: url, secrets: secrets, limits: limits, now: { clock.value })
  }

  func wire(body: String = String(repeating: "x", count: 160)) throws -> String {
    let payload: [String: Any] = ["scheme": "signal", "from": "phone-sensitive", "to": "desktop-sensitive", "body": body, "version": 1]
    return String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
  }

  func wireHash() throws -> String {
    try MqttDeliveryEnvelope.contentHash(XCTUnwrap(JSONSerialization.jsonObject(with: Data(wire().utf8)) as? [String: Any]))
  }

  func packets(body: String = String(repeating: "x", count: 160)) throws -> [[String: Any]] {
    try GalaxySSIMqttWireChunking.encode(wirePayload: wire(body: body), directLimitBytes: 1, chunkDataBytes: 24).map {
      try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
    }
  }

  func query(_ packet: [String: Any]) throws -> MqttChunkReceipts.Query {
    let chunk = try MqttChunkManifest.parse(packet)
    return try .init(transfer: chunk.transfer, manifest: chunk.manifestHash, count: chunk.count, request: String(repeating: "c", count: 32))
  }

  func state(_ scope: String, _ query: MqttChunkReceipts.Query) throws -> MqttChunkReceipts.State {
    try MqttChunkReceipts.parseState(store.snapshot(authenticatedScope: scope, query: query).state)
  }

  func execute(_ sql: String) throws {
    try connection { handle in
      guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw MqttChunkStorageError.databaseFailure }
    }
  }

  func scalar(_ sql: String) throws -> Int64 { try read(sql) { sqlite3_column_int64($0, 0) } }
  func blob(_ sql: String) throws -> Data {
    try read(sql) {
      let bytes = try XCTUnwrap(sqlite3_column_blob($0, 0))
      return Data(bytes: bytes, count: Int(sqlite3_column_bytes($0, 0)))
    }
  }

  private func read<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
    try connection { handle in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw MqttChunkStorageError.databaseFailure }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW else { throw MqttChunkStorageError.databaseFailure }
      return try body(statement)
    }
  }

  private func connection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let handle else {
      if let handle { sqlite3_close_v2(handle) }
      throw MqttChunkStorageError.databaseFailure
    }
    defer { sqlite3_close_v2(handle) }
    return try body(handle)
  }
}
