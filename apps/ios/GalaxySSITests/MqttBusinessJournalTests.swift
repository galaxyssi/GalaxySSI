import XCTest
@testable import GalaxySSI

final class MqttBusinessJournalTests: XCTestCase {
  private let hash = String(repeating: "c", count: 64)
  private let cipher = String(repeating: "d", count: 64)

  func testCommittedInboxSurvivesDatabaseReopenAndReturnsBoundReceipt() throws {
    let fixture = try ChunkFixture()
    let peer = try identity()
    var inbox = try inbox(fixture)
    let accepted = try accept(inbox, peer: peer)
    XCTAssertEqual(accepted.stage, .stored)
    XCTAssertEqual(accepted.receipt?.identity, peer)
    XCTAssertEqual(accepted.receipt?.messageID, "message")
    XCTAssertEqual(accepted.receipt?.wireHash, hash)
    inbox = try self.inbox(fixture)
    let pending = try inbox.pending()
    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending[0].key, accepted.key)
    XCTAssertEqual(pending[0].identity, peer)
    let replay = try inbox.replay(identity: peer, ciphertextDigest: cipher)
    XCTAssertEqual(replay?.stage, .pending)
    XCTAssertEqual(replay?.receipt?.wireHash, hash)
  }

  func testIncomingSameIDCannotChangeContentOrReceiptPolicy() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    _ = try accept(inbox, peer: peer)
    XCTAssertThrowsError(try accept(inbox, peer: peer, content: "changed"))
    XCTAssertThrowsError(try accept(inbox, peer: peer, receipt: false))
    XCTAssertEqual(try accept(inbox, peer: peer).stage, .pending)
    XCTAssertEqual(try inbox.pending().count, 1)
  }

  func testCiphertextAliasCannotMoveToAnotherMessageOrHash() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    _ = try accept(inbox, peer: peer)
    XCTAssertThrowsError(try accept(inbox, peer: peer, message: "other"))
    XCTAssertThrowsError(try accept(inbox, peer: peer, wireHash: String(repeating: "e", count: 64)))
    XCTAssertEqual(try fixture.scalar("SELECT COUNT(*) FROM mqtt_business_inbox"), 1)
    XCTAssertEqual(try fixture.scalar("SELECT COUNT(*) FROM mqtt_business_ciphertexts"), 1)
  }

  func testAliasGrowthIsBoundedAndReceiptsMatchEachCommittedWireHash() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    for index in 0..<8 {
      let digest = String(format: "%064x", index)
      _ = try accept(inbox, peer: peer, ciphertext: digest, wireHash: digest)
      XCTAssertEqual(try inbox.storedReceipt(identity: peer, messageID: "message", wireHash: digest)?.wireHash, digest)
    }
    XCTAssertThrowsError(try accept(inbox, peer: peer))
    XCTAssertEqual(try fixture.scalar("SELECT COUNT(*) FROM mqtt_business_ciphertexts"), 8)
  }

  func testNewPairKeyHasSeparateInboxAndCannotReadOldProof() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let old = try identity()
    let replacement = try identity(secretByte: 8)
    _ = try accept(inbox, peer: old)
    XCTAssertNil(try inbox.replay(identity: replacement, ciphertextDigest: cipher))
    XCTAssertNil(try inbox.storedReceipt(identity: replacement, messageID: "message", wireHash: hash))
    _ = try accept(inbox, peer: replacement)
    try inbox.forget(identity: old)
    XCTAssertEqual(try inbox.pending().map(\.identity), [replacement])
  }

  func testCompletedInboxReleasesBodyButRetainsReplayProofUntilExpiry() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    _ = try accept(inbox, peer: peer)
    XCTAssertTrue(try inbox.complete(identity: peer, messageID: "message"))
    XCTAssertTrue(try inbox.pending().isEmpty)
    XCTAssertEqual(try fixture.scalar("SELECT payload_bytes FROM mqtt_business_inbox"), 0)
    XCTAssertEqual(try inbox.replay(identity: peer, ciphertextDigest: cipher)?.stage, .completed)
    XCTAssertNotNil(try inbox.storedReceipt(identity: peer, messageID: "message", wireHash: hash))
    fixture.clock.value += MqttBusinessStorage.retention + 1
    XCTAssertEqual(try inbox.pruneCompleted(), 1)
    XCTAssertNil(try inbox.replay(identity: peer, ciphertextDigest: cipher))
  }

  func testPendingWorkIsNotExpiredOrEvictedToAdmitNewMessages() throws {
    let fixture = try ChunkFixture()
    let limits = MqttBusinessInbox.Limits(records: 1, peerRecords: 1, pendingBytes: 4096, peerPendingBytes: 4096)
    let inbox = try inbox(fixture, limits: limits)
    let peer = try identity()
    _ = try accept(inbox, peer: peer)
    fixture.clock.value += MqttBusinessStorage.retention + 1
    XCTAssertEqual(try inbox.pruneCompleted(), 0)
    XCTAssertThrowsError(try accept(inbox, peer: peer, message: "new", ciphertext: String(repeating: "e", count: 64)))
    XCTAssertEqual(try inbox.pending().map(\.messageID), ["message"])
  }

  func testIncomingTransactionRollsBackWhenCipherIndexWriteFails() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    try fixture.execute("CREATE TRIGGER fail_alias BEFORE INSERT ON mqtt_business_ciphertexts BEGIN SELECT RAISE(ABORT, 'forced'); END")
    XCTAssertThrowsError(try accept(inbox, peer: identity()))
    XCTAssertEqual(try fixture.scalar("SELECT COUNT(*) FROM mqtt_business_inbox"), 0)
    XCTAssertTrue(try inbox.pending().isEmpty)
    try fixture.execute("DROP TRIGGER fail_alias")
    XCTAssertEqual(try accept(inbox, peer: identity()).stage, .stored)
  }

  func testCompletionFailureKeepsBodyAndReceiptAccessible() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    _ = try accept(inbox, peer: peer)
    try fixture.execute("CREATE TRIGGER fail_complete BEFORE UPDATE ON mqtt_business_inbox BEGIN SELECT RAISE(ABORT, 'forced'); END")
    XCTAssertThrowsError(try inbox.complete(identity: peer, messageID: "message"))
    XCTAssertEqual(try inbox.pending().count, 1)
    XCTAssertEqual(try inbox.replay(identity: peer, ciphertextDigest: cipher)?.stage, .pending)
  }

  func testIncomingCorruptionAndIndexTamperingCannotProduceProof() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    _ = try accept(inbox, peer: peer)
    try fixture.execute("UPDATE mqtt_business_inbox SET payload_bytes=0")
    XCTAssertThrowsError(try inbox.storedReceipt(identity: peer, messageID: "message", wireHash: hash))
    try fixture.execute("UPDATE mqtt_business_inbox SET encrypted_metadata=X'00'")
    XCTAssertThrowsError(try inbox.replay(identity: peer, ciphertextDigest: cipher))
  }

  func testFrameMustMatchStoredApplicationIDHashAndRemoteIdentity() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    let message = try MqttDeliveryEnvelope.Message(messageID: "different", contentHash: hash,
      sender: peer.remote, receiver: peer.local, traffic: "message")
    let frame = try MqttDeliveryEnvelope.Frame(message: message,
      attempt: .init(attemptID: String(repeating: "f", count: 32), brokerID: "emqx", generation: 1))
    XCTAssertThrowsError(try inbox.accept(identity: peer, messageID: "message", payload: ["message_id": "message"],
      ciphertextDigest: cipher, wireHash: hash, receiptRequired: true, frame: frame))
    XCTAssertTrue(try inbox.pending().isEmpty)
  }

  func testReceiptMessagesDoNotReceiveReceiptProofs() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    XCTAssertNil(try accept(inbox, peer: peer, receipt: false).receipt)
    XCTAssertNil(try inbox.replay(identity: peer, ciphertextDigest: cipher)?.receipt)
    XCTAssertNil(try inbox.storedReceipt(identity: peer, messageID: "message", wireHash: hash))
  }

  func testOutboxReopenPreservesWireAndAttachmentMetadata() throws {
    let fixture = try ChunkFixture()
    var outbox = try outbox(fixture)
    let peer = try identity()
    var message = try item()
    message.blockedByAttachmentTransferIds = [String(repeating: "e", count: 64)]
    message.clientSourceMessageId = "ui-source"
    message.contactId = "contact"
    XCTAssertTrue(try outbox.enqueue(identity: peer, message: message, traffic: .message))
    XCTAssertFalse(try outbox.enqueue(identity: peer, message: message, traffic: .message))
    outbox = try self.outbox(fixture)
    XCTAssertEqual(try outbox.entry(identity: peer, messageID: "message")?.message, message)
  }

  func testVerifiedReceiptCannotDeleteWrongIdentityOrHash() throws {
    let fixture = try ChunkFixture()
    let outbox = try outbox(fixture)
    let peer = try identity()
    _ = try outbox.enqueue(identity: peer, message: item(), traffic: .message)
    let saved = try XCTUnwrap(outbox.entry(identity: peer, messageID: "message"))
    XCTAssertNil(try outbox.acknowledgeVerified(identity: identity(secretByte: 8), messageID: "message", wireHash: saved.wireHash))
    XCTAssertNil(try outbox.acknowledgeVerified(identity: peer, messageID: "message", wireHash: hash))
    XCTAssertNotNil(try outbox.entry(identity: peer, messageID: "message"))
    XCTAssertNotNil(try outbox.acknowledgeVerified(identity: peer, messageID: "message", wireHash: saved.wireHash))
    XCTAssertNil(try outbox.entry(identity: peer, messageID: "message"))
  }

  func testOutboxDeleteFailureLeavesExactCommittedMessage() throws {
    let fixture = try ChunkFixture()
    let outbox = try outbox(fixture)
    let peer = try identity()
    let message = try item()
    _ = try outbox.enqueue(identity: peer, message: message, traffic: .message)
    let saved = try XCTUnwrap(outbox.entry(identity: peer, messageID: message.messageId))
    try fixture.execute("CREATE TRIGGER fail_delete BEFORE DELETE ON mqtt_business_outbox BEGIN SELECT RAISE(ABORT, 'forced'); END")
    XCTAssertThrowsError(try outbox.acknowledgeVerified(identity: peer, messageID: message.messageId, wireHash: saved.wireHash))
    XCTAssertEqual(try outbox.entry(identity: peer, messageID: message.messageId)?.message, message)
  }

  func testBrokerPublicationUpdatesRetryWithoutDeletingOutbox() throws {
    let fixture = try ChunkFixture()
    let outbox = try outbox(fixture)
    let peer = try identity()
    _ = try outbox.enqueue(identity: peer, message: item(), traffic: .message)
    try outbox.updateRetry(identity: peer, messageID: "message", published: false, now: Date(timeIntervalSince1970: 2))
    try outbox.updateRetry(identity: peer, messageID: "message", published: true, now: Date(timeIntervalSince1970: 3))
    let saved = try XCTUnwrap(outbox.entry(identity: peer, messageID: "message"))
    XCTAssertEqual(saved.message.attempts, 1)
    XCTAssertEqual(saved.message.status, "published")
    XCTAssertTrue(try outbox.pending(identity: peer, now: Date(timeIntervalSince1970: 3)).isEmpty)
    XCTAssertEqual(try outbox.pending(identity: peer, now: Date(timeIntervalSince1970: 100)).count, 1)
  }

  func testOutboxCapacityReservesControlAndDoesNotOverwriteExistingWire() throws {
    let fixture = try ChunkFixture()
    let limits = MqttBusinessOutbox.Limits(records: 4, bytes: 100_000, peerRecords: 2, peerBytes: 100_000, controlReserve: 1)
    let outbox = try MqttBusinessOutbox(fileURL: fixture.url, secrets: fixture.secrets, limits: limits)
    let peer = try identity()
    _ = try outbox.enqueue(identity: peer, message: item(), traffic: .message)
    XCTAssertThrowsError(try outbox.enqueue(identity: peer, message: item(message: "ordinary"), traffic: .message))
    XCTAssertTrue(try outbox.enqueue(identity: peer, message: item(message: "control"), traffic: .control))
    var changed = try item()
    changed.wirePayload = changed.wirePayload.replacingOccurrences(of: "AA==", with: "BB==")
    XCTAssertThrowsError(try outbox.enqueue(identity: peer, message: changed, traffic: .message))
    XCTAssertEqual(try fixture.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 2)
  }

  func testBusinessRowsAreEncryptedAndMissingKeyMarkerFailsClosed() throws {
    let fixture = try ChunkFixture()
    let inbox = try inbox(fixture)
    let peer = try identity()
    _ = try accept(inbox, peer: peer, content: "private-plaintext-marker")
    let bytes = try fixture.blob("SELECT encrypted_metadata FROM mqtt_business_inbox")
    XCTAssertNil(bytes.range(of: Data("private-plaintext-marker".utf8)))
    try fixture.execute("DELETE FROM mqtt_chunk_key")
    XCTAssertThrowsError(try self.inbox(fixture))
    XCTAssertThrowsError(try inbox.pending())
  }

  func testOutboxRowsAlonePreventMissingKeyMarkerReinitialization() throws {
    let fixture = try ChunkFixture()
    let outbox = try outbox(fixture)
    _ = try outbox.enqueue(identity: identity(), message: item(), traffic: .message)
    try fixture.execute("DELETE FROM mqtt_chunk_key")
    XCTAssertThrowsError(try self.outbox(fixture))
  }

  private func identity(secretByte: UInt8 = 7) throws -> MqttBusinessIdentity {
    try .init(.init(scope: "pair", sender: String(repeating: "a", count: 64), receiver: String(repeating: "b", count: 64),
      secret: Data(repeating: secretByte, count: 32).base64URLEncodedString(), sendTopic: String(repeating: "s", count: 43),
      sendTopics: [String(repeating: "s", count: 43)], receiveTopics: [String(repeating: "r", count: 43)]))
  }
  private func inbox(_ fixture: ChunkFixture, limits: MqttBusinessInbox.Limits = .init()) throws -> MqttBusinessInbox {
    try MqttBusinessInbox(fileURL: fixture.url, secrets: fixture.secrets, limits: limits, now: { fixture.clock.value })
  }
  private func outbox(_ fixture: ChunkFixture) throws -> MqttBusinessOutbox {
    try MqttBusinessOutbox(fileURL: fixture.url, secrets: fixture.secrets)
  }
  private func accept(_ inbox: MqttBusinessInbox, peer: MqttBusinessIdentity, message: String = "message",
                      content: String = "content", ciphertext: String? = nil, wireHash: String? = nil,
                      receipt: Bool = true) throws -> MqttBusinessInbox.Accepted {
    try inbox.accept(identity: peer, messageID: message, payload: ["message_id": message, "content": content],
      ciphertextDigest: ciphertext ?? cipher, wireHash: wireHash ?? hash, receiptRequired: receipt)
  }
  private func item(message: String = "message") throws -> PendingLinkMessage {
    let wire = try GalaxySSILinkProtocol.jsonData(["scheme": "signal", "from": "sender", "to": "receiver", "body": "AA=="])
    return PendingLinkMessage(messageId: message, topic: String(repeating: "s", count: 43), wirePayload: String(decoding: wire, as: UTF8.self),
      status: "queued", attempts: 0, nextAttemptAt: Date(timeIntervalSince1970: 1), createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))
  }
}
