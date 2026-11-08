import XCTest
@testable import GalaxySSI

#if canImport(LibSignalClient)
final class MqttSignalSendTransactionTests: XCTestCase {
  func testRecoveryQueryEncryptsWithoutCreatingBusinessOutboxRecord() throws {
    let f = try SignalSendFixture()
    let identity = try MqttBusinessIdentity(MqttPeerBinding(scope: "direct:receiver",
      sender: f.senderIdentity.fingerprint, receiver: f.receiverIdentity.fingerprint,
      secret: Data(repeating: 7, count: 32).base64URLEncodedString(), sendTopic: sendTopic,
      sendTopics: [sendTopic], receiveTopics: [String(repeating: "r", count: 43)]))
    let nonce = UUID().uuidString
    let request = try MqttSignalSendRequest(identity: identity, payload: ["type": "agent_task_result_page_request",
      "message_id": nonce, "request_id": nonce, "page_index": 1],
      remoteName: f.receiverIdentity.name, topic: sendTopic, traffic: .control)
    let bytes = try f.sender.makeRecoveryQueryWire(request)
    let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let envelope = try XCTUnwrap(f.receiver.decrypt(wire))
    let payload = try XCTUnwrap(GalaxySSILinkProtocol.unwrapEnvelope(envelope))
    XCTAssertEqual(payload["request_id"] as? String, nonce)
    XCTAssertEqual(payload["page_index"] as? Int, 1)
    XCTAssertNil(try f.journal.outbox.entry(identity: identity, messageID: nonce))
  }

  func testDirectApplicationReceiptUsesInteroperableLinkEnvelope() throws {
    let f = try SignalSendFixture()
    let identity = try MqttBusinessIdentity(MqttPeerBinding(scope: "direct:receiver",
      sender: f.senderIdentity.fingerprint, receiver: f.receiverIdentity.fingerprint,
      secret: Data(repeating: 7, count: 32).base64URLEncodedString(), sendTopic: sendTopic,
      sendTopics: [sendTopic], receiveTopics: [String(repeating: "r", count: 43)]))
    let id = UUID().uuidString
    let request = try MqttSignalSendRequest(identity: identity, payload: ["type": "input_attachment_receipt",
      "message_id": id, "status": "stored"], remoteName: f.receiverIdentity.name, topic: sendTopic, traffic: .control)
    let entry = try f.sender.encryptAndEnqueue(request, now: f.date)
    let envelope = try f.decrypt(entry)
    XCTAssertEqual(envelope["source_id"] as? String, f.senderIdentity.name)
    XCTAssertEqual(envelope["target_id"] as? String, f.receiverIdentity.name)
    let payload = try XCTUnwrap(GalaxySSILinkProtocol.unwrapEnvelope(envelope, now: f.date))
    XCTAssertEqual(payload["message_id"] as? String, id)
    XCTAssertEqual(payload["type"] as? String, "input_attachment_receipt")
    XCTAssertEqual(payload["status"] as? String, "stored")
  }

  @MainActor
  func testLegacyCutoverPreservesIdentityRatchetAndExactQueuedCiphertext() throws {
    let storage = try ChunkFixture()
    let suite = "mqtt-cutover-\(UUID().uuidString)", remoteSuite = "mqtt-cutover-remote-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let remoteDefaults = try XCTUnwrap(UserDefaults(suiteName: remoteSuite))
    defer {
      defaults.removePersistentDomain(forName: suite)
      remoteDefaults.removePersistentDomain(forName: remoteSuite)
    }
    let legacy = GalaxySSISignalEngine(profileName: "legacy", defaults: defaults, secrets: storage.secrets)
    let remote = GalaxySSISignalEngine(profileName: "remote", defaults: remoteDefaults, secrets: InMemorySecretStore())
    XCTAssertTrue(legacy.processBundle(try XCTUnwrap(remote.identity.bundle)))
    let local = legacy.identity.fingerprint
    let secret = Data(repeating: 7, count: 32).base64URLEncodedString()
    let topic = String(repeating: "s", count: 43)
    let binding = MqttPeerBinding(scope: "peer", sender: local, receiver: remote.identity.fingerprint, secret: secret,
      sendTopic: topic, sendTopics: [topic], receiveTopics: [String(repeating: "r", count: 43)])
    let peers = [MqttBusinessTransportRuntime.Peer(binding: binding, remoteSignalName: remote.identity.name)]
    let identity = try MqttBusinessIdentity(binding)
    let wire = try XCTUnwrap(legacy.encrypt(["type": "peer_message", "message_id": "pending"], remoteName: remote.identity.name))
    let bytes = String(decoding: try GalaxySSILinkProtocol.jsonData(wire), as: UTF8.self)
    let legacyQueue = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: storage.secrets)
    legacyQueue.enqueue(messageId: "pending", topic: topic, wirePayload: bytes, contactId: "peer")
    let journal = try MqttSignalStateJournal(fileURL: storage.url, secrets: storage.secrets)
    XCTAssertEqual(legacyQueue.stageIncoming(messageId: "waiting", payload: "{}"), .staged)
    XCTAssertThrowsError(try MqttBusinessTransportRuntime.prepareLegacyCutover(journal: journal,
      legacyOutbox: legacyQueue, expectedLocalFingerprint: local, peers: peers, defaults: defaults,
      secrets: storage.secrets, classify: { _ in .message }))
    XCTAssertNil(try journal.legacyCutover())
    legacyQueue.completeIncoming(messageId: "waiting")
    let marker = try MqttBusinessTransportRuntime.prepareLegacyCutover(journal: journal,
      legacyOutbox: legacyQueue, expectedLocalFingerprint: local, peers: peers, defaults: defaults,
      secrets: storage.secrets, classify: { _ in .message })
    XCTAssertEqual(marker.localFingerprint, local)
    XCTAssertEqual(marker.importedMessages, 1)
    XCTAssertTrue(legacyQueue.containsOutboxMessage("pending"))
    XCTAssertEqual(try journal.outbox.entry(identity: identity, messageID: "pending")?.message.wirePayload, bytes)
    let migrated = try GalaxySSISignalEngine(profileName: "legacy", journal: journal, defaults: defaults, secrets: storage.secrets)
    XCTAssertEqual(migrated.identity.fingerprint, local)
    XCTAssertEqual(remote.decrypt(wire)?["message_id"] as? String, "pending")
    let request = try MqttSignalSendRequest(identity: identity, payload: ["type": "peer_message", "message_id": "next"],
      remoteName: remote.identity.name, topic: topic, sourceMessageID: "source", contactID: "peer")
    let next = try migrated.encryptAndEnqueue(request)
    let nextWire = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(next.message.wirePayload.utf8)) as? [String: Any])
    XCTAssertEqual(remote.decrypt(nextWire)?["message_id"] as? String, "next")
    XCTAssertEqual(try MqttBusinessTransportRuntime.prepareLegacyCutover(journal: journal,
      legacyOutbox: legacyQueue, expectedLocalFingerprint: local, peers: [], defaults: defaults,
      secrets: storage.secrets, classify: { _ in XCTFail("Never replay the legacy queue after cutover"); return nil }), marker)
  }

  func testDeliveredRequestCannotAdvanceRatchetOrRecreateOutbox() throws {
    let f = try SignalSendFixture()
    let request = try f.request()
    let entry = try f.sender.encryptAndEnqueue(request, now: f.date)
    _ = try f.journal.outbox.acknowledgeVerified(identity: request.identity, messageID: request.messageID, wireHash: entry.wireHash, now: f.date)
    let state = try f.journal.load()
    XCTAssertThrowsError(try f.sender.encryptAndEnqueue(request, now: f.date))
    XCTAssertEqual(try f.journal.load(), state)
    XCTAssertEqual(try f.storage.scalar("SELECT COUNT(*) FROM mqtt_business_outbox"), 0)
    XCTAssertEqual(try f.journal.outbox.completions.pending().count, 1)
  }

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
