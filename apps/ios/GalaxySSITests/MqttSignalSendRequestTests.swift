import XCTest
@testable import GalaxySSI

final class MqttSignalSendRequestTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 10)

  func testCanonicalIntentHashIgnoresDictionaryAndDependencyOrder() throws {
    let a = try request(payload: ["message_id": "message", "text": "hello"], dependencies: [sendDependencyB, sendDependencyA])
    let b = try request(payload: ["text": "hello", "message_id": "message"], dependencies: [sendDependencyA, sendDependencyB, sendDependencyA])
    XCTAssertEqual(try a.digest(), b.digest())
    XCTAssertEqual(a.attachmentDependencies, [sendDependencyA, sendDependencyB])
  }

  func testLocalOnlyPayloadCannotAuthorizeItself() throws {
    XCTAssertThrowsError(try request(payload: ["message_id": "message", "type": "self_evolution"]))
    XCTAssertThrowsError(try request(payload: ["message_id": "message", "type": "text", "conversation_id": "global-cognition:run",
      "trustedBackgroundCognitionAuthorized": true]))
    XCTAssertThrowsError(try request(payload: ["message_id": "message", "_link_rx_key": "forged"]))
    XCTAssertThrowsError(try request(payload: ["message_id": "message", "_mqtt_delivery": [:]]))
  }

  func testInvalidAttachmentDependencyIsRejectedNotSilentlyDropped() throws {
    XCTAssertThrowsError(try request(dependencies: ["not-a-transfer"]))
    XCTAssertThrowsError(try request(dependencies: (0...64).map { String(format: "%064x", $0) }))
    XCTAssertThrowsError(try MqttSignalSendRequest(identity: sendTestIdentity(), payload: ["message_id": "message"],
      remoteName: "remote", deviceID: 0, topic: sendTopic))
  }

  func testChangedRoutingOrPrivacyMetadataChangesIntentHash() throws {
    let original = try request()
    let otherTopic = try MqttSignalSendRequest(identity: sendTestIdentity(), payload: ["message_id": "message", "text": "hello"],
      remoteName: "remote", topic: String(repeating: "t", count: 43))
    let network = try MqttSignalSendRequest(identity: sendTestIdentity(), payload: ["message_id": "message", "text": "hello"],
      remoteName: "remote", topic: sendTopic, requiresValidatedNetwork: true)
    XCTAssertNotEqual(try original.digest(), otherTopic.digest())
    XCTAssertNotEqual(try original.digest(), network.digest())
  }

  func testDeferredRecordReopensWithoutExposingPlaintext() throws {
    let f = try ChunkFixture()
    var outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets)
    let request = try request(dependencies: [sendDependencyA])
    XCTAssertTrue(try outbox.enqueueDeferred(request, now: date))
    outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets)
    let saved = try XCTUnwrap(outbox.entry(identity: request.identity, messageID: request.messageID))
    XCTAssertFalse(saved.isPrepared)
    XCTAssertTrue(saved.wireHash.isEmpty)
    XCTAssertTrue(saved.message.wirePayload.isEmpty)
    XCTAssertEqual(saved.deferredRequest?.payload, request.payload)
    XCTAssertEqual(saved.requestHash, try request.digest())
    let encrypted = try f.blob("SELECT encrypted_metadata FROM mqtt_business_outbox")
    XCTAssertNil(encrypted.range(of: request.payload))
    XCTAssertNil(encrypted.range(of: Data(request.payload.base64EncodedString().utf8)))
  }

  func testUnpreparedEntryCannotAcceptPublicationOrDeliveryReceipt() throws {
    let f = try ChunkFixture()
    let outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets)
    let request = try request(dependencies: [sendDependencyA])
    try outbox.enqueueDeferred(request, now: date)
    XCTAssertThrowsError(try outbox.updateRetry(identity: request.identity, messageID: request.messageID, published: true, now: date))
    XCTAssertNil(try outbox.acknowledgeVerified(identity: request.identity, messageID: request.messageID, wireHash: sendDependencyA))
    XCTAssertNotNil(try outbox.entry(identity: request.identity, messageID: request.messageID))
  }

  func testDependencyReleaseIsScopedAndWaitsForEveryTransfer() throws {
    let f = try ChunkFixture()
    let outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets)
    let request = try request(dependencies: [sendDependencyA, sendDependencyB])
    try outbox.enqueueDeferred(request, now: date)
    let wrong = try sendTestIdentity(secretByte: 8)
    XCTAssertEqual(try outbox.releaseAttachment(identity: wrong, transferID: sendDependencyA).matched, 0)
    let first = try outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyA)
    XCTAssertEqual(first.matched, 1)
    XCTAssertEqual(first.released, 0)
    XCTAssertEqual(try outbox.entry(identity: request.identity, messageID: request.messageID)?.message.blockedByAttachmentTransferIds, [sendDependencyB])
    XCTAssertEqual(try outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyB).released, 1)
    XCTAssertEqual(try outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyB).matched, 0)
  }

  func testDependencyPageWriteFailureRollsBackWholePage() throws {
    let f = try ChunkFixture()
    let outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets)
    let a = try request(payload: ["message_id": "a"], dependencies: [sendDependencyA])
    let b = try request(payload: ["message_id": "b"], dependencies: [sendDependencyA])
    try outbox.enqueueDeferred(a, now: date)
    try outbox.enqueueDeferred(b, now: date)
    let last = try [a.identity.key(messageID: "a"), b.identity.key(messageID: "b")].sorted().last!
    try f.execute("CREATE TRIGGER fail_release BEFORE UPDATE ON mqtt_business_outbox WHEN NEW.record_key='\(last)' BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try outbox.releaseAttachment(identity: a.identity, transferID: sendDependencyA))
    XCTAssertEqual(try outbox.entry(identity: a.identity, messageID: "a")?.message.blockedByAttachmentTransferIds, [sendDependencyA])
    XCTAssertEqual(try outbox.entry(identity: b.identity, messageID: "b")?.message.blockedByAttachmentTransferIds, [sendDependencyA])
  }

  func testBoundedPagesCanAdvancePastBlockedMessages() throws {
    let f = try ChunkFixture()
    let outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets)
    let identity = try sendTestIdentity()
    for id in ["one", "two", "three"] {
      try outbox.enqueueDeferred(request(payload: ["message_id": id], dependencies: [sendDependencyA]), now: date)
    }
    var cursor: MqttBusinessOutbox.Cursor?
    var ids: [String] = []
    repeat {
      let page = try outbox.pendingPage(identity: identity, now: date, after: cursor, limit: 1)
      ids += page.entries.map(\.message.messageId)
      cursor = page.next
    } while cursor != nil
    XCTAssertEqual(Set(ids), Set(["one", "two", "three"]))
    XCTAssertEqual(ids.count, 3)
  }

  func testOuterSignalTransactionFailureRollsBackDeferredOutbox() throws {
    let f = try ChunkFixture()
    let journal = try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
    let request = try request(dependencies: [sendDependencyA])
    XCTAssertThrowsError(try journal.commit(expected: nil) { token -> (Void, Data) in
      try journal.outbox.enqueueDeferred(request, now: self.date, transaction: token)
      throw MqttChunkStorageError.databaseFailure
    })
    XCTAssertNil(try journal.load())
    XCTAssertNil(try journal.outbox.entry(identity: request.identity, messageID: request.messageID))
  }

  func testDeferredDuplicateCannotReplaceIntentOrResetReleasedDependencies() throws {
    let f = try ChunkFixture()
    let outbox = try MqttBusinessOutbox(fileURL: f.url, secrets: f.secrets)
    let request = try request(dependencies: [sendDependencyA])
    try outbox.enqueueDeferred(request, now: date)
    _ = try outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyA)
    XCTAssertFalse(try outbox.enqueueDeferred(request, now: date.addingTimeInterval(10)))
    XCTAssertEqual(try outbox.entry(identity: request.identity, messageID: request.messageID)?.message.blockedByAttachmentTransferIds, [])
    XCTAssertThrowsError(try outbox.enqueueDeferred(self.request(payload: ["message_id": "message", "text": "changed"],
      dependencies: [sendDependencyA]), now: date))
  }

  private func request(payload: [String: Any] = ["message_id": "message", "text": "hello"],
                       dependencies: [String] = []) throws -> MqttSignalSendRequest {
    try MqttSignalSendRequest(identity: sendTestIdentity(), payload: payload, remoteName: "remote", topic: sendTopic,
      attachmentDependencies: dependencies)
  }
}

let sendTopic = String(repeating: "s", count: 43)
let sendDependencyA = String(repeating: "a", count: 64)
let sendDependencyB = String(repeating: "b", count: 64)

func sendTestIdentity(local: String = String(repeating: "a", count: 64), remote: String = String(repeating: "b", count: 64),
                      secretByte: UInt8 = 7) throws -> MqttBusinessIdentity {
  try MqttBusinessIdentity(MqttPeerBinding(scope: "signal-send", sender: local, receiver: remote,
    secret: Data(repeating: secretByte, count: 32).base64URLEncodedString(), sendTopic: sendTopic,
    sendTopics: [sendTopic], receiveTopics: [String(repeating: "r", count: 43)]))
}
