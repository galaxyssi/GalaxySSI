import XCTest
@testable import GalaxySSI

#if canImport(LibSignalClient)
final class MqttSignalSendTransactionTests: XCTestCase {
  func testAtomicSendReopensWithExactDecryptableWireAndMetadata() throws {
    let f = try SignalSendFixture()
    let request = try f.request()
    let entry = try f.sender.encryptAndEnqueue(request, now: f.date)
    XCTAssertTrue(entry.isPrepared)
    XCTAssertEqual(entry.requestHash, try request.digest())
    XCTAssertEqual(entry.message.clientSourceMessageId, "ui-source")
    XCTAssertEqual(entry.message.contactId, "contact")
    XCTAssertEqual(try f.decrypt(entry)["text"] as? String, "hello")
    try f.reopen()
    let saved = try XCTUnwrap(f.journal.outbox.entry(identity: request.identity, messageID: request.messageID))
    XCTAssertEqual(saved.message, entry.message)
    XCTAssertEqual(saved.wireHash, entry.wireHash)
  }

  func testDuplicateDoesNotReencryptOrResetRetryState() throws {
    let f = try SignalSendFixture()
    let request = try f.request()
    let first = try f.sender.encryptAndEnqueue(request, now: f.date)
    try f.journal.outbox.updateRetry(identity: request.identity, messageID: request.messageID, published: false, now: f.date)
    let state = try f.journal.load()
    let retry = try f.sender.encryptAndEnqueue(request, now: f.date.addingTimeInterval(30))
    XCTAssertEqual(retry.message.wirePayload, first.message.wirePayload)
    XCTAssertEqual(retry.message.attempts, 1)
    XCTAssertEqual(retry.message.status, "publishing")
    XCTAssertEqual(retry.message.createdAt, first.message.createdAt)
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertThrowsError(try f.sender.encryptAndEnqueue(f.request(text: "changed")))
    XCTAssertEqual(try f.journal.load(), state)
  }

  func testOutboxInsertFailureRestoresSendingRatchetForRetry() throws {
    let f = try SignalSendFixture()
    let request = try f.request()
    let state = try f.journal.load()
    try f.storage.execute("CREATE TRIGGER fail_send BEFORE INSERT ON mqtt_business_outbox BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.sender.encryptAndEnqueue(request, now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertNil(try f.journal.outbox.entry(identity: request.identity, messageID: request.messageID))
    try f.storage.execute("DROP TRIGGER fail_send")
    XCTAssertEqual(try f.decrypt(f.sender.encryptAndEnqueue(request, now: f.date))["text"] as? String, "hello")
  }

  func testCheckpointFailureRollsBackAlreadyInsertedWire() throws {
    let f = try SignalSendFixture()
    let request = try f.request()
    let state = try f.journal.load()
    try f.storage.execute("CREATE TRIGGER fail_state BEFORE UPDATE ON mqtt_signal_state BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.sender.encryptAndEnqueue(request, now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertNil(try f.journal.outbox.entry(identity: request.identity, messageID: request.messageID))
    try f.storage.execute("DROP TRIGGER fail_state")
    XCTAssertEqual(try f.decrypt(f.sender.encryptAndEnqueue(request, now: f.date))["text"] as? String, "hello")
  }

  func testBatchCapacityFailureRollsBackEveryMessageAndRatchet() throws {
    let limits = MqttBusinessOutbox.Limits(records: 8, bytes: 100_000, peerRecords: 2, peerBytes: 100_000, controlReserve: 1)
    let f = try SignalSendFixture(limits: limits)
    let state = try f.journal.load()
    let first = try f.request(id: "first")
    let second = try f.request(id: "second")
    XCTAssertThrowsError(try f.sender.enqueueBatch([first, second], now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertEqual(try f.storage.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 0)
    XCTAssertEqual(try f.decrypt(f.sender.encryptAndEnqueue(first, now: f.date))["message_id"] as? String, "first")
  }

  func testSuccessfulBatchCommitsIndependentCiphertextsInOrder() throws {
    let f = try SignalSendFixture()
    let requests = try [f.request(id: "first"), f.request(id: "second")]
    let entries = try f.sender.enqueueBatch(requests, now: f.date)
    XCTAssertEqual(entries.map(\.message.messageId), ["first", "second"])
    XCTAssertNotEqual(entries[0].wireHash, entries[1].wireHash)
    XCTAssertEqual(try f.decrypt(entries[0])["message_id"] as? String, "first")
    XCTAssertEqual(try f.decrypt(entries[1])["message_id"] as? String, "second")
  }

  func testDeferredSendWaitsForEveryAttachmentAndValidatedNetwork() throws {
    let f = try SignalSendFixture(establishSession: false)
    let request = try f.request(dependencies: [sendDependencyA, sendDependencyB], network: true)
    let before = try f.journal.load()
    let queued = try f.sender.encryptAndEnqueue(request, now: f.date)
    XCTAssertFalse(queued.isPrepared)
    XCTAssertEqual(try f.journal.load(), before)
    XCTAssertNil(try f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: true, now: f.date))
    _ = try f.journal.outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyA)
    XCTAssertNil(try f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: true, now: f.date))
    _ = try f.journal.outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyB)
    XCTAssertNil(try f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: false, now: f.date))
    XCTAssertThrowsError(try f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: true, now: f.date))
    XCTAssertTrue(f.sender.processBundle(try XCTUnwrap(f.receiver.localBundle())))
    let ready = try XCTUnwrap(f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: true, now: f.date))
    XCTAssertTrue(ready.isPrepared)
    XCTAssertNil(ready.deferredRequest)
    XCTAssertTrue(ready.message.blockedByAttachmentTransferIds.isEmpty)
    XCTAssertEqual(try f.decrypt(ready)["text"] as? String, "hello")
    let retry = try f.sender.encryptAndEnqueue(request, now: f.date.addingTimeInterval(1))
    XCTAssertEqual(retry.message.wirePayload, ready.message.wirePayload)
  }

  func testDeferredPreparationFailureRetainsOriginalPayloadAndRatchet() throws {
    let f = try SignalSendFixture()
    let request = try f.request(dependencies: [sendDependencyA])
    _ = try f.sender.encryptAndEnqueue(request, now: f.date)
    _ = try f.journal.outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyA)
    let state = try f.journal.load()
    try f.storage.execute("CREATE TRIGGER fail_prepare BEFORE UPDATE ON mqtt_business_outbox BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: true, now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertEqual(try f.journal.outbox.entry(identity: request.identity, messageID: request.messageID)?.deferredRequest?.payload, request.payload)
    try f.storage.execute("DROP TRIGGER fail_prepare")
    let ready = try XCTUnwrap(f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: true, now: f.date))
    XCTAssertEqual(try f.decrypt(ready)["text"] as? String, "hello")
  }

  func testDeferredIntentAndReleasedDependenciesSurviveReopen() throws {
    let f = try SignalSendFixture()
    let request = try f.request(dependencies: [sendDependencyA])
    _ = try f.sender.encryptAndEnqueue(request, now: f.date)
    _ = try f.journal.outbox.releaseAttachment(identity: request.identity, transferID: sendDependencyA)
    try f.reopen()
    let ready = try XCTUnwrap(f.sender.prepareFirstSend(identity: request.identity, messageID: request.messageID, validatedNetwork: true, now: f.date))
    XCTAssertEqual(try f.decrypt(ready)["message_id"] as? String, request.messageID)
  }

  func testWrongRemoteIdentityDoesNotAdvanceRatchetOrStoreWire() throws {
    let f = try SignalSendFixture()
    let wrong = try sendTestIdentity(local: f.senderIdentity.fingerprint, remote: String(repeating: "c", count: 64))
    let request = try MqttSignalSendRequest(identity: wrong, payload: ["message_id": "wrong"],
      remoteName: f.receiverIdentity.name, topic: sendTopic)
    let state = try f.journal.load()
    XCTAssertThrowsError(try f.sender.encryptAndEnqueue(request, now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertEqual(try f.storage.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 0)
  }

  func testDurableEngineRejectsEncryptOnlyBypassAndDuplicateBatchIDs() throws {
    let f = try SignalSendFixture()
    let request = try f.request()
    let state = try f.journal.load()
    XCTAssertNil(f.sender.encrypt(["message_id": "bypass"], remoteName: f.receiverIdentity.name))
    XCTAssertThrowsError(try f.sender.enqueueBatch([request, request], now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertEqual(try f.storage.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 0)
  }

  func testStaleSenderCannotOverwriteAnotherInstanceCommit() throws {
    let f = try SignalSendFixture()
    let stale = f.sender
    try f.reopen()
    _ = try f.sender.encryptAndEnqueue(f.request(id: "first"), now: f.date)
    let committed = try f.journal.load()
    XCTAssertThrowsError(try stale.encryptAndEnqueue(f.request(id: "stale"), now: f.date))
    XCTAssertEqual(try f.journal.load(), committed)
    XCTAssertEqual(try f.storage.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 1)
  }

  func testPeerControllerQueuesOfflineAndRejectsRevokedSendBeforeEncryption() throws {
    let f = try SignalSendFixture()
    let pool = GalaxySSIMqttBrokerPool { FakeMqttBrokerPath(id: $0.id) }
    let routes = MqttPeerRoutes(pool: pool, persistence: MqttRouteState(defaults: f.senderDefaults, secrets: f.storage.secrets))
    var binding = MqttPeerBinding(scope: "signal-send", sender: f.senderIdentity.fingerprint, receiver: f.receiverIdentity.fingerprint,
      secret: Data(repeating: 7, count: 32).base64URLEncodedString(), sendTopic: sendTopic,
      sendTopics: [sendTopic], receiveTopics: [String(repeating: "r", count: 43)])
    try routes.replace([binding])
    XCTAssertFalse(routes.isReady(scope: binding.scope))
    let entries = try routes.enqueue([f.request(id: "approved")], using: f.sender, now: f.date)
    XCTAssertEqual(try f.decrypt(XCTUnwrap(entries.first))["message_id"] as? String, "approved")
    let state = try f.journal.load()
    binding.enabled = false
    try routes.replace([binding])
    XCTAssertThrowsError(try routes.enqueue([f.request(id: "revoked")], using: f.sender, now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertEqual(try f.storage.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 1)
  }
}

private final class SignalSendFixture {
  let storage: ChunkFixture
  let senderSuite = "signal-sender-" + UUID().uuidString
  let receiverSuite = "signal-receiver-" + UUID().uuidString
  let senderDefaults: UserDefaults
  let receiverDefaults: UserDefaults
  var sender: GalaxySSISignalEngine
  let receiver: GalaxySSISignalEngine
  let senderIdentity: GalaxySSISignalIdentity
  let receiverIdentity: GalaxySSISignalIdentity
  let journal: MqttSignalStateJournal
  let date = Date(timeIntervalSince1970: 100)

  init(limits: MqttBusinessOutbox.Limits = .init(), establishSession: Bool = true) throws {
    storage = try ChunkFixture()
    senderDefaults = try XCTUnwrap(UserDefaults(suiteName: senderSuite))
    receiverDefaults = try XCTUnwrap(UserDefaults(suiteName: receiverSuite))
    journal = try MqttSignalStateJournal(fileURL: storage.url, secrets: storage.secrets, outboxLimits: limits)
    sender = try GalaxySSISignalEngine(profileName: "sender", journal: journal, defaults: senderDefaults, secrets: storage.secrets)
    receiver = GalaxySSISignalEngine(profileName: "receiver", defaults: receiverDefaults, secrets: InMemorySecretStore())
    senderIdentity = sender.identity
    receiverIdentity = receiver.identity
    if establishSession { XCTAssertTrue(sender.processBundle(try XCTUnwrap(receiverIdentity.bundle))) }
  }

  deinit {
    senderDefaults.removePersistentDomain(forName: senderSuite)
    receiverDefaults.removePersistentDomain(forName: receiverSuite)
  }
  func reopen() throws {
    sender = try GalaxySSISignalEngine(profileName: "sender", journal: journal, defaults: senderDefaults, secrets: storage.secrets)
  }
  func request(id: String = "message", text: String = "hello", dependencies: [String] = [], network: Bool = false) throws -> MqttSignalSendRequest {
    try MqttSignalSendRequest(identity: sendTestIdentity(local: senderIdentity.fingerprint, remote: receiverIdentity.fingerprint),
      payload: ["message_id": id, "type": "message", "text": text], remoteName: receiverIdentity.name,
      topic: sendTopic, requiresValidatedNetwork: network, attachmentDependencies: dependencies,
      sourceMessageID: "ui-source", contactID: "contact")
  }
  func decrypt(_ entry: MqttBusinessOutbox.Entry) throws -> [String: Any] {
    let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(entry.message.wirePayload.utf8)) as? [String: Any])
    return try XCTUnwrap(receiver.decrypt(wire))
  }
}
#endif
