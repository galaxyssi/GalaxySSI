import XCTest
@testable import GalaxySSI

final class MqttOutgoingChunksTests: XCTestCase {
  private let epoch = String(repeating: "d", count: 32)

  func testSenderReceiverExchangeResumesOnlyMissingPartsAfterReopen() throws {
    let f = try ChunkFixture()
    var sender = try outgoing(f)
    let parts = try f.packets()
    let first = try sender.prepare(authenticatedScope: "outgoing-pair", parts: parts)
    XCTAssertEqual(first.selected.count, parts.count)
    _ = try f.store.accept(authenticatedScope: "incoming-pair", wire: first.selected[0].wire)
    let feedback = try f.store.snapshot(authenticatedScope: "incoming-pair", query: first.query)
    XCTAssertTrue(try sender.accept(authenticatedScope: "outgoing-pair", state: feedback.state))
    XCTAssertTrue(try sender.recordPath(authenticatedScope: "outgoing-pair", query: first.query, index: 1, broker: "hivemq"))
    sender = try outgoing(f)
    try f.reopen()
    let resumed = try sender.prepare(authenticatedScope: "outgoing-pair", parts: parts)
    XCTAssertNotEqual(resumed.query.request, first.query.request)
    XCTAssertEqual(resumed.selected.map(\.index), Array(1..<parts.count))
    XCTAssertEqual(resumed.attempted(index: 1), ["hivemq"])
    XCTAssertFalse(try sender.accept(authenticatedScope: "outgoing-pair", state: feedback.state))
    var assembled: String?
    for selection in resumed.selected { assembled = try f.store.accept(authenticatedScope: "incoming-pair", wire: selection.wire) }
    XCTAssertEqual(assembled, try f.wire())
    let complete = try f.store.snapshot(authenticatedScope: "incoming-pair", query: resumed.query)
    XCTAssertTrue(try sender.accept(authenticatedScope: "outgoing-pair", state: complete.state))
    XCTAssertNil(complete.proof)
  }

  func testRequestRenewalFencesOldReceiptsAndLatePathCallbacks() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let parts = try f.packets()
    let first = try sender.prepare(authenticatedScope: "pair", parts: parts)
    let next = try sender.prepare(authenticatedScope: "pair", parts: parts)
    XCTAssertFalse(try sender.accept(authenticatedScope: "pair", state: first.query.response(epoch: epoch, revision: 1, indices: [0])))
    XCTAssertFalse(try sender.recordPath(authenticatedScope: "pair", query: first.query, index: 0, broker: "emqx"))
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: next.query.response(epoch: epoch, revision: 1, indices: [0])))
    let last = try sender.prepare(authenticatedScope: "pair", parts: parts)
    XCTAssertFalse(last.selected.contains { $0.index == 0 })
    XCTAssertTrue(last.attempted(index: 0).isEmpty)
  }

  func testRevisionMonotonicityAndConflictingSameRevision() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    let accepted = try batch.query.response(epoch: epoch, revision: 2, indices: [0, 1])
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: accepted))
    XCTAssertFalse(try sender.accept(authenticatedScope: "pair", state: accepted))
    XCTAssertFalse(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 1, indices: [])))
    XCTAssertThrowsError(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 2, indices: [0])))
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 3, indices: [1])))
    let next = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    XCTAssertTrue(next.selected.contains { $0.index == 0 })
    XCTAssertFalse(next.selected.contains { $0.index == 1 })
  }

  func testChangedReceiverEpochRequiresFreshRequestRound() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 5, indices: [0])))
    let restarted = String(repeating: "e", count: 32)
    XCTAssertFalse(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: restarted, revision: 0, indices: [])))
    let next = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: next.query.response(epoch: restarted, revision: 0, indices: [])))
    XCTAssertEqual(try sender.prepare(authenticatedScope: "pair", parts: f.packets()).selected.count, try f.packets().count)
  }

  func testFullBitmapProducesProbeNotBusinessCompletionAndEmptyStoreRestartsTransfer() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let parts = try f.packets()
    let batch = try sender.prepare(authenticatedScope: "pair", parts: parts)
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 1, indices: Set(parts.indices))))
    let probe = try sender.prepare(authenticatedScope: "pair", parts: parts)
    XCTAssertEqual(probe.selected.count, 1)
    XCTAssertEqual(probe.selected[0].index, -1)
    XCTAssertEqual(probe.selected[0].wire["type"] as? String, MqttChunkReceipts.probe)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_outgoing_chunks"), 1)
    let empty = try probe.query.response(epoch: String(repeating: "0", count: 32), revision: 0, indices: [])
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: empty))
    XCTAssertEqual(try sender.prepare(authenticatedScope: "pair", parts: parts).selected.count, parts.count)
  }

  func testScopeAndManifestMismatchCannotAcknowledgeAnotherTransfer() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    let response = try batch.query.response(epoch: epoch, revision: 1, indices: [0])
    XCTAssertFalse(try sender.accept(authenticatedScope: "different-key", state: response))
    var changed = response
    changed["manifest_hash"] = String(repeating: "a", count: 64)
    XCTAssertFalse(try sender.accept(authenticatedScope: "pair", state: changed))
    XCTAssertEqual(try sender.prepare(authenticatedScope: "pair", parts: f.packets()).selected.count, try f.packets().count)
  }

  func testPathBitOrderAndIndexBoundsMatchBrokerCatalog() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    for broker in ["emqx", "hivemq", "mosquitto"] {
      XCTAssertTrue(try sender.recordPath(authenticatedScope: "pair", query: batch.query, index: 0, broker: broker))
    }
    XCTAssertFalse(try sender.recordPath(authenticatedScope: "pair", query: batch.query, index: -1, broker: "emqx"))
    XCTAssertThrowsError(try sender.recordPath(authenticatedScope: "pair", query: batch.query, index: batch.query.count, broker: "emqx"))
    XCTAssertThrowsError(try sender.recordPath(authenticatedScope: "pair", query: batch.query, index: 0, broker: "other"))
    let next = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    XCTAssertEqual(next.attempted(index: 0), ["emqx", "hivemq", "mosquitto"])
    XCTAssertTrue(next.attempted(index: -1).isEmpty)
    XCTAssertTrue(next.attempted(index: next.query.count).isEmpty)
  }

  func testInvalidOrReorderedPartsNeverCreateResumeState() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let parts = try f.packets()
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "pair", parts: []))
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "pair", parts: Array(parts.dropLast())))
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "pair", parts: Array(parts.reversed())))
    var mixed = parts
    mixed[1]["from"] = "changed"
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "pair", parts: mixed))
    var changed = parts
    let bytes = Data(repeating: 0x7a, count: 24)
    changed[0]["data"] = bytes.base64EncodedString()
    changed[0]["chunk_sha256"] = MqttRouteProtocol.digest(bytes)
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "pair", parts: changed))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_outgoing_chunks"), 0)
  }

  func testFailedRequestRenewalPreservesPreviousRequestUntilCommit() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    try f.execute("CREATE TRIGGER reject_outgoing BEFORE UPDATE ON mqtt_outgoing_chunks BEGIN SELECT RAISE(ABORT, 'injected'); END")
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "pair", parts: f.packets()))
    XCTAssertThrowsError(try sender.recordPath(authenticatedScope: "pair", query: batch.query, index: 0, broker: "emqx"))
    try f.execute("DROP TRIGGER reject_outgoing")
    XCTAssertTrue(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 1, indices: [0])))
    let next = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    XCTAssertFalse(next.selected.contains { $0.index == 0 })
    XCTAssertTrue(next.attempted(index: 0).isEmpty)
  }

  func testFailedReceiptCommitLeavesMissingSelectionUnchanged() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    try f.execute("CREATE TRIGGER reject_receipt BEFORE UPDATE ON mqtt_outgoing_chunks BEGIN SELECT RAISE(ABORT, 'injected'); END")
    XCTAssertThrowsError(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 1, indices: [0])))
    try f.execute("DROP TRIGGER reject_receipt")
    XCTAssertEqual(try sender.prepare(authenticatedScope: "pair", parts: f.packets()).selected.count, try f.packets().count)
  }

  func testExpiryDropsOldProgressAndRejectsLateReceipts() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    _ = try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 1, indices: [0]))
    _ = try sender.recordPath(authenticatedScope: "pair", query: batch.query, index: 1, broker: "hivemq")
    f.clock.value += MqttOutgoingChunks.retentionMillis
    XCTAssertFalse(try sender.accept(authenticatedScope: "pair", state: batch.query.response(epoch: epoch, revision: 2, indices: [0, 1])))
    let next = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    XCTAssertNotEqual(next.query.request, batch.query.request)
    XCTAssertEqual(next.selected.count, try f.packets().count)
    XCTAssertTrue(next.attempted(index: 1).isEmpty)
  }

  func testMetadataCapacityDoesNotEvictOtherPeersAndForgetIsScoped() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f, limits: .init(transfers: 2, peerTransfers: 1))
    let parts = try f.packets()
    _ = try sender.prepare(authenticatedScope: "a", parts: parts)
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "a", parts: f.packets(body: "other")))
    _ = try sender.prepare(authenticatedScope: "b", parts: parts)
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "c", parts: parts))
    try sender.forget(authenticatedScope: "a")
    _ = try sender.prepare(authenticatedScope: "c", parts: parts)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_outgoing_chunks"), 2)
    try sender.clear()
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_outgoing_chunks"), 0)
  }

  func testCorruptMetadataAndMissingKeyMarkerCannotResetResumeState() throws {
    let f = try ChunkFixture()
    let sender = try outgoing(f)
    let batch = try sender.prepare(authenticatedScope: "pair", parts: f.packets())
    let data = try f.blob("SELECT encrypted_metadata FROM mqtt_outgoing_chunks")
    XCTAssertNil(data.range(of: Data(batch.query.request.utf8)))
    XCTAssertThrowsError(try MqttOutgoingChunks(fileURL: f.url, secrets: InMemorySecretStore()))
    try f.execute("UPDATE mqtt_outgoing_chunks SET encrypted_metadata=zeroblob(length(encrypted_metadata))")
    XCTAssertThrowsError(try sender.prepare(authenticatedScope: "pair", parts: f.packets()))
    try f.execute("DELETE FROM mqtt_chunk_key")
    XCTAssertThrowsError(try outgoing(f))
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_outgoing_chunks"), 1)
  }

  private func outgoing(_ f: ChunkFixture, limits: MqttOutgoingChunks.Limits = .init()) throws -> MqttOutgoingChunks {
    let clock = f.clock
    return try MqttOutgoingChunks(fileURL: f.url, secrets: f.secrets, limits: limits, now: { clock.value })
  }
}
