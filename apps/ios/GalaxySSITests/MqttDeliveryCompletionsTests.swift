import XCTest
@testable import GalaxySSI

final class MqttDeliveryCompletionsTests: XCTestCase {
  func testChatDeliveryCommitSurvivesReopenAndIsIdempotent() throws {
    let f = try ChunkFixture()
    let history = GalaxySSIChatHistoryDatabase(fileURL: f.url, secrets: f.secrets)
    let message = ChatMessage(contactId: "contact", content: "outgoing", isMine: true)
    XCTAssertTrue(history.upsert(message))
    let event = try chatEvent(message)
    let first = try history.persistTransportDelivery(event)
    let second = try history.persistTransportDelivery(event)
    XCTAssertEqual(first, second)
    XCTAssertEqual(first.deliveryStatus, .delivered)
    XCTAssertEqual(first.deliveryTrace.count, message.deliveryTrace.count + 1)
    let reopened = GalaxySSIChatHistoryDatabase(fileURL: f.url, secrets: f.secrets)
    XCTAssertEqual(reopened.message(id: message.id), first)
  }

  func testChatDeliveryWriteFailurePreservesMessageAndAllowsRetry() throws {
    let f = try ChunkFixture()
    let history = GalaxySSIChatHistoryDatabase(fileURL: f.url, secrets: f.secrets)
    let message = ChatMessage(contactId: "contact", content: "outgoing", isMine: true)
    XCTAssertTrue(history.upsert(message))
    let event = try chatEvent(message)
    try f.execute("CREATE TRIGGER fail_chat BEFORE UPDATE ON chat_messages BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try history.persistTransportDelivery(event))
    XCTAssertEqual(history.message(id: message.id), message)
    try f.execute("DROP TRIGGER fail_chat")
    XCTAssertEqual(try history.persistTransportDelivery(event).deliveryStatus, .delivered)
  }

  func testChatDeliveryDoesNotDowngradeReadOrAcknowledgeAnotherContact() throws {
    let f = try ChunkFixture()
    let history = GalaxySSIChatHistoryDatabase(fileURL: f.url, secrets: f.secrets)
    var message = ChatMessage(contactId: "contact", content: "outgoing", isMine: true)
    message.deliveryStatus = .read
    XCTAssertTrue(history.upsert(message))
    XCTAssertThrowsError(try history.persistTransportDelivery(chatEvent(message, contact: "other")))
    XCTAssertEqual(history.message(id: message.id), message)
    XCTAssertEqual(try history.persistTransportDelivery(chatEvent(message)).deliveryStatus, .read)
  }

  func testChatDeliveryRejectsIncomingMissingAndAttachmentMessages() throws {
    let f = try ChunkFixture()
    let history = GalaxySSIChatHistoryDatabase(fileURL: f.url, secrets: f.secrets)
    let incoming = ChatMessage(contactId: "contact", content: "incoming", isMine: false)
    XCTAssertTrue(history.upsert(incoming))
    XCTAssertThrowsError(try history.persistTransportDelivery(chatEvent(incoming)))
    let missing = ChatMessage(contactId: "contact", content: "missing", isMine: true)
    XCTAssertThrowsError(try history.persistTransportDelivery(chatEvent(missing)))
    XCTAssertTrue(history.upsert(missing))
    XCTAssertThrowsError(try history.persistTransportDelivery(chatEvent(missing, attachment: sendDependencyA)))
    XCTAssertThrowsError(try history.persistTransportDelivery(chatEvent(missing, traffic: "progress")))
    XCTAssertEqual(history.message(id: missing.id), missing)
  }

  private func chatEvent(_ message: ChatMessage, contact: String = "contact", attachment: String = "",
                         traffic: String = "message") throws -> MqttDeliveryCompletions.Event {
    MqttDeliveryCompletions.Event(identity: try sendTestIdentity(), messageID: "transport-message",
      wireHash: String(repeating: "a", count: 64), traffic: traffic, requestHash: nil,
      sourceMessageID: message.id.uuidString, contactID: contact, attachmentTransferID: attachment,
      receivedAt: 1000, consumedAt: nil)
  }

  func testStoredApplicationReceiptCommitsAllThreeJournalsAndReplays() throws {
    let f = try ChunkFixture()
    let journal = try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
    let entry = try enqueue(journal.outbox)
    try stageReceipt(journal, entry: entry)
    let event = try journal.consumeStoredReceipt(identity: entry.identity, receiptMessageID: "ack")
    XCTAssertEqual(event?.messageID, entry.message.messageId)
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
    XCTAssertNil(try journal.outbox.entry(identity: entry.identity, messageID: entry.message.messageId))
    XCTAssertNil(try journal.consumeStoredReceipt(identity: entry.identity, receiptMessageID: "ack"))
    XCTAssertEqual(try journal.outbox.completions.pending().count, 1)
  }

  func testInboxCompletionFailureRollsBackOutgoingAcknowledgement() throws {
    let f = try ChunkFixture()
    let journal = try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
    let entry = try enqueue(journal.outbox)
    try stageReceipt(journal, entry: entry)
    try f.execute("CREATE TRIGGER fail_inbox BEFORE UPDATE ON mqtt_business_inbox BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try journal.consumeStoredReceipt(identity: entry.identity, receiptMessageID: "ack"))
    XCTAssertNotNil(try journal.outbox.entry(identity: entry.identity, messageID: entry.message.messageId))
    XCTAssertTrue(try journal.outbox.completions.pending().isEmpty)
    XCTAssertEqual(try journal.inbox.pending().count, 1)
    try f.execute("DROP TRIGGER fail_inbox")
    XCTAssertNotNil(try journal.consumeStoredReceipt(identity: entry.identity, receiptMessageID: "ack"))
  }

  func testStoredReceiptAfterRawReceiptUsesExistingCompletion() throws {
    let f = try ChunkFixture()
    let journal = try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
    let entry = try enqueue(journal.outbox)
    _ = try acknowledge(journal.outbox, entry)
    try stageReceipt(journal, entry: entry)
    XCTAssertNotNil(try journal.consumeStoredReceipt(identity: entry.identity, receiptMessageID: "ack"))
    XCTAssertEqual(try journal.outbox.completions.pending().count, 1)
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
  }

  func testStoredReceiptWrongHashPreservesAllPendingState() throws {
    let f = try ChunkFixture()
    let journal = try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
    let entry = try enqueue(journal.outbox)
    try stageReceipt(journal, entry: entry, hash: sendDependencyA)
    XCTAssertThrowsError(try journal.consumeStoredReceipt(identity: entry.identity, receiptMessageID: "ack"))
    XCTAssertNotNil(try journal.outbox.entry(identity: entry.identity, messageID: entry.message.messageId))
    XCTAssertEqual(try journal.inbox.pending().count, 1)
    XCTAssertTrue(try journal.outbox.completions.pending().isEmpty)
  }

  func testStoredReceiptCannotBeConsumedUnderDifferentRelationship() throws {
    let f = try ChunkFixture()
    let journal = try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
    let entry = try enqueue(journal.outbox)
    try stageReceipt(journal, entry: entry)
    XCTAssertNil(try journal.consumeStoredReceipt(identity: sendTestIdentity(secretByte: 8), receiptMessageID: "ack"))
    XCTAssertEqual(try journal.inbox.pending().count, 1)
    XCTAssertNotNil(try journal.outbox.entry(identity: entry.identity, messageID: entry.message.messageId))
  }

  private func stageReceipt(_ journal: MqttSignalStateJournal, entry: MqttBusinessOutbox.Entry,
                            hash: String? = nil) throws {
    var payload = try MqttDeliveryEnvelope.storedReceipt(messageID: entry.message.messageId, wireHash: hash ?? entry.wireHash)
    payload["message_id"] = "ack"
    _ = try journal.inbox.accept(identity: entry.identity, messageID: "ack", payload: payload,
      ciphertextDigest: String(repeating: "e", count: 64), wireHash: String(repeating: "f", count: 64), receiptRequired: false)
  }

  func testReceiptAtomicallyReplacesOutboxWithRecoverableUIEvent() throws {
    let f = try ChunkFixture()
    var outbox = try box(f)
    let entry = try enqueue(outbox)
    XCTAssertNotNil(try acknowledge(outbox, entry))
    outbox = try box(f)
    XCTAssertNil(try outbox.entry(identity: entry.identity, messageID: entry.message.messageId))
    let event = try XCTUnwrap(outbox.completions.pending().first)
    XCTAssertEqual(event.identity, entry.identity)
    XCTAssertEqual(event.messageID, entry.message.messageId)
    XCTAssertEqual(event.wireHash, entry.wireHash)
    XCTAssertEqual(event.sourceMessageID, "source-ui")
    XCTAssertEqual(event.contactID, "contact")
    XCTAssertEqual(event.attachmentTransferID, sendDependencyA)
    XCTAssertEqual(event.receivedAt, 1000)
    XCTAssertNil(try acknowledge(outbox, entry))
    XCTAssertEqual(try outbox.completions.pending().count, 1)
  }

  func testCompletionWriteFailureDoesNotDeleteOutgoingWire() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    try f.execute("CREATE TRIGGER fail_completion BEFORE INSERT ON mqtt_delivery_completions BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try acknowledge(outbox, entry))
    XCTAssertEqual(try outbox.entry(identity: entry.identity, messageID: entry.message.messageId)?.message, entry.message)
    XCTAssertTrue(try outbox.completions.pending().isEmpty)
  }

  func testOutboxDeleteFailureRollsBackCompletionEvent() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    try f.execute("CREATE TRIGGER fail_delete BEFORE DELETE ON mqtt_business_outbox BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try acknowledge(outbox, entry))
    XCTAssertTrue(try outbox.completions.pending().isEmpty)
    XCTAssertNotNil(try outbox.entry(identity: entry.identity, messageID: entry.message.messageId))
    try f.execute("DROP TRIGGER fail_delete")
    XCTAssertNotNil(try acknowledge(outbox, entry))
  }

  func testUndeliveredUIEventsNeverExpireAndConsumptionKeepsReplayTombstone() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    _ = try acknowledge(outbox, entry)
    let late = MqttBusinessStorage.retention + 10_000
    XCTAssertEqual(try outbox.completions.pruneConsumed(at: late), 0)
    XCTAssertEqual(try outbox.completions.pending().count, 1)
    XCTAssertTrue(try outbox.completions.consume(identity: entry.identity, messageID: entry.message.messageId, at: late))
    XCTAssertFalse(try outbox.completions.consume(identity: entry.identity, messageID: entry.message.messageId, at: late + 1))
    XCTAssertTrue(try outbox.completions.pending().isEmpty)
    XCTAssertNotNil(try outbox.completions.event(identity: entry.identity, messageID: entry.message.messageId))
    XCTAssertEqual(try outbox.completions.pruneConsumed(at: late + MqttBusinessStorage.retention), 0)
    XCTAssertEqual(try outbox.completions.pruneConsumed(at: late + MqttBusinessStorage.retention + 1), 1)
  }

  func testDeliveredIDCannotBeRequeuedBeforeTombstoneExpires() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    _ = try acknowledge(outbox, entry)
    XCTAssertThrowsError(try outbox.enqueue(identity: entry.identity, message: entry.message, traffic: .message)) { error in
      guard case MqttChunkStorageError.alreadyDelivered = error else { return XCTFail("Expected delivered tombstone") }
    }
    _ = try outbox.completions.consume(identity: entry.identity, messageID: entry.message.messageId, at: 2000)
    XCTAssertThrowsError(try outbox.enqueue(identity: entry.identity, message: entry.message, traffic: .message))
    XCTAssertNil(try outbox.entry(identity: entry.identity, messageID: entry.message.messageId))
  }

  func testCompletionCapacityFailureRetainsSecondOutgoingMessage() throws {
    let f = try ChunkFixture()
    let limits = MqttDeliveryCompletions.Limits(records: 1, peerRecords: 1, bytes: 100_000, peerBytes: 100_000)
    let outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets, completionLimits: limits)
    _ = try acknowledge(outbox, enqueue(outbox, id: "first"))
    let second = try enqueue(outbox, id: "second")
    XCTAssertThrowsError(try acknowledge(outbox, second))
    XCTAssertNotNil(try outbox.entry(identity: second.identity, messageID: "second"))
    XCTAssertEqual(try outbox.completions.pending().map(\.messageID), ["first"])
  }

  func testConsumeFailureRetainsEventAndReservedBytesCoverMetadataGrowth() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    _ = try acknowledge(outbox, entry)
    let reserved = try f.scalar("SELECT payload_bytes FROM mqtt_delivery_completions")
    try f.execute("CREATE TRIGGER fail_consume BEFORE UPDATE ON mqtt_delivery_completions BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try outbox.completions.consume(identity: entry.identity, messageID: entry.message.messageId, at: 2000))
    XCTAssertEqual(try outbox.completions.pending().count, 1)
    try f.execute("DROP TRIGGER fail_consume")
    _ = try outbox.completions.consume(identity: entry.identity, messageID: entry.message.messageId,
      at: MqttRouteProtocol.maximumInteger - MqttBusinessStorage.retention)
    XCTAssertLessThanOrEqual(try f.scalar("SELECT payload_bytes FROM mqtt_delivery_completions"), reserved)
  }

  func testWrongReceiptDoesNotCreateCompletion() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    XCTAssertNil(try outbox.acknowledgeVerified(identity: entry.identity, messageID: entry.message.messageId, wireHash: sendDependencyA))
    XCTAssertNil(try outbox.acknowledgeVerified(identity: sendTestIdentity(secretByte: 8), messageID: entry.message.messageId, wireHash: entry.wireHash))
    XCTAssertTrue(try outbox.completions.pending().isEmpty)
  }

  func testScopedRetirementRollsBackTogetherWithOutboxFailure() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let completed = try enqueue(outbox, id: "done")
    _ = try acknowledge(outbox, completed)
    _ = try enqueue(outbox, id: "pending")
    try f.execute("CREATE TRIGGER fail_forget BEFORE DELETE ON mqtt_business_outbox BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try outbox.forget(identity: completed.identity))
    XCTAssertEqual(try outbox.completions.pending().count, 1)
    try f.execute("DROP TRIGGER fail_forget")
    try outbox.forget(identity: completed.identity)
    XCTAssertTrue(try outbox.completions.pending().isEmpty)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 0)
  }

  func testEncryptedCompletionAlonePreventsKeyAndIdentityReinitialization() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    _ = try acknowledge(outbox, entry)
    let bytes = try f.blob("SELECT encrypted_metadata FROM mqtt_delivery_completions")
    XCTAssertNil(bytes.range(of: Data("source-ui".utf8)))
    let journal = try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
    XCTAssertThrowsError(try journal.load())
    try f.execute("DELETE FROM mqtt_chunk_key")
    XCTAssertThrowsError(try box(f))
  }

  func testTamperedCompletionIndexFailsClosed() throws {
    let f = try ChunkFixture()
    let outbox = try box(f)
    let entry = try enqueue(outbox)
    _ = try acknowledge(outbox, entry)
    try f.execute("UPDATE mqtt_delivery_completions SET retain_until=0")
    XCTAssertThrowsError(try outbox.completions.event(identity: entry.identity, messageID: entry.message.messageId))
  }

  private func box(_ f: ChunkFixture) throws -> MqttBusinessOutbox { try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets) }
  private func enqueue(_ outbox: MqttBusinessOutbox, id: String = "message") throws -> MqttBusinessOutbox.Entry {
    let identity = try sendTestIdentity()
    let wire = try GalaxySSILinkProtocol.jsonData(["scheme": "signal", "from": "sender", "to": "receiver", "body": "AA=="])
    let message = PendingLinkMessage(messageId: id, topic: sendTopic, wirePayload: String(decoding: wire, as: UTF8.self),
      status: "queued", attempts: 0, nextAttemptAt: Date(timeIntervalSince1970: 1), createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 1), attachmentTransferId: sendDependencyA, clientSourceMessageId: "source-ui", contactId: "contact")
    try outbox.enqueue(identity: identity, message: message, traffic: .message)
    return try XCTUnwrap(outbox.entry(identity: identity, messageID: id))
  }
  private func acknowledge(_ outbox: MqttBusinessOutbox, _ entry: MqttBusinessOutbox.Entry) throws -> MqttBusinessOutbox.Entry? {
    try outbox.acknowledgeVerified(identity: entry.identity, messageID: entry.message.messageId, wireHash: entry.wireHash,
      now: Date(timeIntervalSince1970: 1))
  }
}
