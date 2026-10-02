import XCTest
@testable import GalaxySSI

final class MqttPeerRoutesTests: XCTestCase {
  @MainActor
  func testApplicationPeerMappingSeparatesApprovalFromSubscription() throws {
    let (contact, request) = try applicationPeerRecords()
    let pending = try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: String(repeating: "a", count: 64),
      serverLinks: [], contacts: [], requests: [request])
    XCTAssertEqual(pending.count, 1)
    XCTAssertFalse(try XCTUnwrap(pending.first).binding.enabled)
    let approved = try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: String(repeating: "a", count: 64),
      serverLinks: [], contacts: [contact], requests: [request])
    XCTAssertEqual(approved.count, 1)
    XCTAssertTrue(try XCTUnwrap(approved.first).binding.enabled)
    XCTAssertEqual(approved.first?.remoteName, contact.galaxySSIId)
    XCTAssertEqual(approved.first?.binding.scope, contact.linkClientRouteId)
  }

  @MainActor
  func testApplicationPeerMappingCannotResurrectDeletedContactFromOldRequest() throws {
    var (contact, request) = try applicationPeerRecords()
    contact.deleted = true
    request.status = .approved
    let peers = try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: String(repeating: "a", count: 64),
      serverLinks: [], contacts: [contact], requests: [request])
    XCTAssertTrue(peers.isEmpty)
  }

  @MainActor
  func testApplicationPeerMappingRejectsWrongLocalIdentityAndDuplicateRoutes() throws {
    let (contact, _) = try applicationPeerRecords()
    XCTAssertThrowsError(try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: String(repeating: "c", count: 64),
      serverLinks: [], contacts: [contact], requests: []))
    var duplicate = contact
    duplicate.galaxySSIId = "another-name"
    XCTAssertThrowsError(try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: String(repeating: "a", count: 64),
      serverLinks: [], contacts: [contact, duplicate], requests: []))
  }

  @MainActor
  func testApplicationPeerMappingDoesNotEnableUnverifiedContactOrRequestOnlyApproval() throws {
    var (contact, request) = try applicationPeerRecords()
    contact.trustState = .unverified
    request.status = .approved
    let peers = try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: String(repeating: "a", count: 64),
      serverLinks: [], contacts: [contact], requests: [request])
    XCTAssertFalse(try XCTUnwrap(peers.first).binding.enabled)
    let orphan = try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: String(repeating: "a", count: 64),
      serverLinks: [], contacts: [], requests: [request])
    XCTAssertFalse(try XCTUnwrap(orphan.first).binding.enabled)
  }

  @MainActor
  func testApplicationPeerMappingChecksDesktopPairingAndPinnedFingerprint() throws {
    let (contact, _) = try applicationPeerRecords()
    let routes = try XCTUnwrap(contact.opaquePhoneRoutes)
    var link = ServerLink(desktopId: "desktop", desktopName: "Desktop", desktopFingerprint: contact.identityFingerprint,
      signalName: "desktop", routes: routes, paired: false, accessProfile: "", accessScopes: [], updatedAt: Date())
    let pending = try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: routes.localFingerprint,
      serverLinks: [link], contacts: [], requests: [])
    XCTAssertFalse(try XCTUnwrap(pending.first).binding.enabled)
    link.paired = true
    let approved = try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: routes.localFingerprint,
      serverLinks: [link], contacts: [], requests: [])
    XCTAssertTrue(try XCTUnwrap(approved.first).binding.enabled)
    link.desktopFingerprint = String(repeating: "d", count: 64)
    XCTAssertThrowsError(try GalaxySSIPairingLifecycle.mqttPeers(localFingerprint: routes.localFingerprint,
      serverLinks: [link], contacts: [], requests: []))
  }

  private func applicationPeerRecords() throws -> (GalaxySSIContact, GalaxySSIFriendRequest) {
    let local = String(repeating: "a", count: 64)
    let remote = String(repeating: "b", count: 64)
    let secret = try GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(sharedSecret: Data(repeating: 7, count: 32),
      firstFingerprint: local, secondFingerprint: remote)
    let routeID = try GalaxySSILinkProtocol.deriveIdentityBoundRouteId(linkSecret: secret,
      firstFingerprint: local, secondFingerprint: remote)
    var contact = GalaxySSIContact.hermes()
    contact.id = "phone"; contact.galaxySSIId = "phone"; contact.type = "person"
    contact.desktopId = ""; contact.trustState = .verified; contact.deleted = false
    contact.identityFingerprint = remote; contact.linkClientRouteId = routeID
    contact.linkSecret = secret; contact.linkLocalFingerprint = local
    let request = GalaxySSIFriendRequest(id: "request", galaxySSIId: "phone", name: "Phone", type: "person",
      identityPublicKey: "", identityFingerprint: remote, mqttTopic: "", mqttInboxTopic: "",
      linkClientRouteId: routeID, linkSecret: secret, linkLocalFingerprint: local)
    return (contact, request)
  }

  func testSendDrainInspectsBlockedRoutesAndRecoversAfterBoundedWait() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    await f.peer.emit(topics: f.peer.binding.receiveTopics, generation: 2)
    let drain = f.sendDrain()
    let first = try await drain.drain(identities: [f.entry.identity], validatedNetwork: true)
    XCTAssertEqual(first.inspected, 1)
    XCTAssertEqual(first.submitted, 0)
    XCTAssertEqual(first.recoveredRoutes, 0)
    f.peer.time += 30_000
    let recovered = try await drain.drain(identities: [f.entry.identity], validatedNetwork: true)
    XCTAssertEqual(recovered.recoveredRoutes, 1)
    XCTAssertEqual(recovered.submitted, 0)
    XCTAssertEqual(try f.outbox.entry(identity: f.entry.identity, messageID: "message")?.message.attempts, 0)
    let cooldown = try await drain.drain(identities: [f.entry.identity], validatedNetwork: true)
    XCTAssertEqual(cooldown.recoveredRoutes, 0)
    await f.peer.routes.maintenance()
    XCTAssertEqual(f.peer.path.publications.last?.generation, 2)
  }

  func testSendDrainDoesNotTreatBrokerEnqueueAsLogicalDelivery() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    let drain = f.sendDrain()
    let result = try await drain.drain(identities: [f.entry.identity], validatedNetwork: true)
    XCTAssertEqual(result.submitted, 1)
    XCTAssertTrue(result.failures.isEmpty)
    let saved = try XCTUnwrap(f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    XCTAssertEqual(saved.message.status, "published")
    XCTAssertEqual(saved.message.attempts, 1)
    XCTAssertEqual(saved.wireHash, f.entry.wireHash)
    XCTAssertTrue(try f.outbox.completions.pending().isEmpty)
    let duplicate = try await drain.drain(identities: [f.entry.identity], validatedNetwork: true)
    XCTAssertEqual(duplicate.inspected, 0)
  }

  func testSendDrainRejectsRevokedIdentityBeforeOutboxAccess() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    f.peer.binding.enabled = false
    try f.peer.routes.replace([f.peer.binding])
    let result = try await f.sendDrain().drain(identities: [f.entry.identity], validatedNetwork: true)
    XCTAssertEqual(result.inspected, 0)
    XCTAssertEqual(result.failures.count, 1)
    XCTAssertTrue(f.publications.isEmpty)
    XCTAssertEqual(try f.outbox.entry(identity: f.entry.identity, messageID: "message")?.message.attempts, 0)
  }

  func testSendDrainRotatesPastPeerWithoutReadyRoute() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    var blocked = f.peer.binding
    blocked.scope = "other"
    blocked.sendTopic = String(repeating: "o", count: 43)
    blocked.sendTopics = [blocked.sendTopic]
    blocked.receiver = String(repeating: "c", count: 64)
    try f.peer.routes.replace([f.peer.binding, blocked])
    let blockedIdentity = try MqttBusinessIdentity(blocked)
    var message = f.entry.message
    message.topic = blocked.sendTopic
    try f.outbox.enqueue(identity: blockedIdentity, message: message, traffic: .message)
    let drain = f.sendDrain()
    let peers = [f.entry.identity, blockedIdentity]
    let first = try await drain.drain(identities: peers, validatedNetwork: true, limit: 1)
    XCTAssertEqual(first.inspected, 1)
    XCTAssertEqual(first.submitted, 0)
    let second = try await drain.drain(identities: peers, validatedNetwork: true, limit: 1)
    XCTAssertEqual(second.inspected, 1)
    XCTAssertEqual(second.submitted, 1)
  }

  func testSendDrainClosedDoesNotTouchPendingMessages() async throws {
    let f = try ReceiptBridgeFixture()
    let drain = f.sendDrain()
    await drain.close()
    let result = try await drain.drain(identities: [f.entry.identity], validatedNetwork: true)
    XCTAssertTrue(result.stopped)
    XCTAssertEqual(result.inspected, 0)
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
  }

  func testSendDrainPagesPastAttachmentAndNetworkBlockedMessages() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    for index in 0..<6 {
      var message = f.entry.message
      message.messageId = "blocked-\(index)"
      if index.isMultiple(of: 2) { message.requiresValidatedNetwork = true }
      else { message.blockedByAttachmentTransferIds = [String(repeating: "1", count: 64)] }
      try f.outbox.enqueue(identity: f.entry.identity, message: message, traffic: .message)
    }
    let drain = f.sendDrain()
    var sent = 0
    for _ in 0..<9 {
      let result = try await drain.drain(identities: [f.entry.identity], validatedNetwork: false, limit: 1)
      XCTAssertLessThanOrEqual(result.inspected, 1)
      XCTAssertTrue(result.failures.isEmpty)
      sent += result.submitted
    }
    XCTAssertEqual(sent, 1)
    for index in 0..<6 {
      XCTAssertEqual(try f.outbox.entry(identity: f.entry.identity, messageID: "blocked-\(index)")?.message.attempts, 0)
    }
  }

  func testStoredReceiptRequiresCommittedMatchingInboxRecord() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.incomingPacket()
    XCTAssertNil(try f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
    try f.stageIncoming(packet)
    let publication = try XCTUnwrap(f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: publication.payload) as? [String: Any])
    let frame = try MqttDeliveryEnvelope.parseVerifiedReceipt(payload,
      originalSender: f.entry.identity.remote, originalReceiver: f.entry.identity.local)
    XCTAssertEqual(frame.message.messageID, "incoming")
    XCTAssertEqual(publication.topic, f.peer.binding.sendTopic)
    XCTAssertEqual(publication.authorized?(), true)
    // Receiving committed data does not require a completed outgoing resume handshake.
    XCTAssertFalse(f.peer.routes.isReady(scope: f.peer.binding.scope))
    let sent = try await f.peer.routes.publishStoredReceipt(packet, inbox: f.journal.inbox)
    XCTAssertTrue(sent)
    XCTAssertEqual(f.peer.path.publications.count, 1)
  }

  func testStoredReceiptCannotEscapeOpenInboxTransaction() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.incomingPacket()
    let database = try MqttChunkDatabase(fileURL: f.storage.url, secrets: f.storage.secrets)
    let inbox = try MqttBusinessInbox(database: database)
    try database.withTransaction { token in
      let hash = try MqttDeliveryEnvelope.contentHash(packet.payload)
      _ = try inbox.accept(identity: f.entry.identity, messageID: "incoming",
        payload: ["message_id": "incoming", "type": "message"], ciphertextDigest: hash,
        wireHash: hash, receiptRequired: true, transaction: token)
      XCTAssertThrowsError(try f.peer.routes.prepareStoredReceipt(packet, inbox: inbox))
    }
    XCTAssertNotNil(try f.peer.routes.prepareStoredReceipt(packet, inbox: inbox))
  }

  func testStoredReceiptRejectsDifferentCiphertextForSameMessage() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.incomingPacket()
    try f.stageIncoming(packet)
    let changed = try await f.incomingPacket(body: "AQ==")
    XCTAssertNil(try f.peer.routes.prepareStoredReceipt(changed, inbox: f.journal.inbox))
  }

  func testStoredReceiptCanReplayCompletedInboxWithoutReapplyingMessage() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.incomingPacket()
    try f.stageIncoming(packet)
    _ = try f.journal.inbox.complete(identity: f.entry.identity, messageID: "incoming")
    XCTAssertNotNil(try f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
    XCTAssertTrue(try f.journal.inbox.pending().isEmpty)
  }

  func testStoredReceiptAuthorizationRejectsRevocationAndDeletedProof() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.incomingPacket()
    try f.stageIncoming(packet)
    let publication = try XCTUnwrap(f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
    try f.journal.inbox.forget(identity: f.entry.identity)
    XCTAssertEqual(publication.authorized?(), false)
    try f.stageIncoming(packet)
    XCTAssertEqual(publication.authorized?(), true)
    f.peer.binding.enabled = false
    try f.peer.routes.replace([f.peer.binding])
    XCTAssertEqual(publication.authorized?(), false)
    XCTAssertThrowsError(try f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
  }

  func testStoredReceiptAuthorizationRejectsReconnectedPath() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.incomingPacket()
    try f.stageIncoming(packet)
    let publication = try XCTUnwrap(f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
    await f.peer.emit(topics: f.peer.binding.receiveTopics, generation: 2)
    XCTAssertEqual(publication.authorized?(), false)
    XCTAssertThrowsError(try f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
    let replay = try await f.incomingPacket()
    XCTAssertNotNil(try f.peer.routes.prepareStoredReceipt(replay, inbox: f.journal.inbox))
  }

  func testStoredReceiptDoesNotAcknowledgeAnotherReceipt() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.incomingPacket(traffic: "receipt")
    try f.stageIncoming(packet, receiptRequired: false)
    XCTAssertNil(try f.peer.routes.prepareStoredReceipt(packet, inbox: f.journal.inbox))
  }

  func testDeliveryDrainRetriesBusinessHandoffWhenConsumeWriteFails() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    try f.storage.execute("CREATE TRIGGER fail_consumed BEFORE UPDATE ON mqtt_delivery_completions BEGIN SELECT RAISE(ABORT,'forced'); END")
    var applied: Set<String> = []
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes) { event in
      applied.insert(event.messageID)
    }
    let first = try await drain.drain()
    XCTAssertEqual(first.failures.count, 1)
    XCTAssertEqual(first.completions, 0)
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
    try f.storage.execute("DROP TRIGGER fail_consumed")
    let second = try await drain.drain()
    XCTAssertEqual(second.completions, 1)
    XCTAssertEqual(applied, ["message"])
  }

  func testDeliveryDrainIsSingleFlightAcrossAsyncBusinessSave() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    let gate = ReceiptDrainGate()
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes) { _ in await gate.hold() }
    let first = Task { try await drain.drain() }
    await gate.waitForEntry()
    let duplicate = try await drain.drain()
    XCTAssertTrue(duplicate.busy)
    await gate.release()
    let result = try await first.value
    XCTAssertEqual(result.completions, 1)
  }

  func testClosingDuringAsyncBusinessSaveRetainsCompletionForRecovery() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    let gate = ReceiptDrainGate()
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes) { _ in await gate.hold() }
    let task = Task { try await drain.drain() }
    await gate.waitForEntry()
    await drain.close()
    await gate.release()
    let result = try await task.value
    XCTAssertTrue(result.stopped)
    XCTAssertEqual(result.completions, 0)
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
  }

  func testDeliveryDrainPersistsBusinessStateBeforeConsumingCompletion() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    var applied: [String] = []
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes,
      now: { 3000 }) { event in
      XCTAssertEqual(try f.outbox.completions.pending().count, 1)
      applied.append(event.messageID)
    }
    let first = try await drain.drain()
    XCTAssertEqual(first.receipts, 1)
    XCTAssertEqual(first.completions, 1)
    XCTAssertTrue(first.failures.isEmpty)
    XCTAssertEqual(applied, ["message"])
    XCTAssertTrue(try f.outbox.completions.pending().isEmpty)
    let second = try await drain.drain()
    XCTAssertEqual(second.completions, 0)
    XCTAssertEqual(applied.count, 1)
  }

  func testDeliveryDrainKeepsCompletionPendingWhenBusinessSaveFails() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    var fail = true
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes) { _ in
      if fail { throw MqttChunkStorageError.databaseFailure }
    }
    let first = try await drain.drain()
    XCTAssertEqual(first.failures.count, 1)
    XCTAssertEqual(first.completions, 0)
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
    fail = false
    let second = try await drain.drain()
    XCTAssertEqual(second.completions, 1)
    XCTAssertTrue(try f.outbox.completions.pending().isEmpty)
  }

  func testDeliveryDrainDoesNotConsumeWhenRelationshipRevokedDuringApply() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes) { _ in
      f.peer.binding.enabled = false
      try f.peer.routes.replace([f.peer.binding])
    }
    let result = try await drain.drain()
    XCTAssertEqual(result.completions, 0)
    XCTAssertEqual(result.failures.count, 1)
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
  }

  func testClosedDeliveryDrainLeavesDurableWorkUntouched() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes) { _ in
      XCTFail("Closed drain must not apply business state")
    }
    await drain.close()
    let result = try await drain.drain()
    XCTAssertTrue(result.stopped)
    XCTAssertEqual(try f.journal.inbox.pending().count, 1)
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
  }

  func testDeliveryDrainAdvancesPastUnrelatedInboxRecordsAndWraps() async throws {
    let f = try ReceiptBridgeFixture()
    for index in 0..<3 {
      let id = "chat-\(index)"
      _ = try f.journal.inbox.accept(identity: f.entry.identity, messageID: id,
        payload: ["type": "message", "message_id": id], ciphertextDigest: String(repeating: String(index + 1), count: 64),
        wireHash: String(repeating: "a", count: 64), receiptRequired: true)
    }
    try f.stageStoredReceipt()
    var applied = 0
    let drain = MqttBusinessDeliveryDrain(journal: f.journal, receipts: f.receipts, routes: f.peer.routes) { _ in applied += 1 }
    for _ in 0..<6 {
      let result = try await drain.drain(limit: 1)
      XCTAssertLessThanOrEqual(result.receipts, 1)
      XCTAssertLessThanOrEqual(result.completions, 1)
      XCTAssertTrue(result.failures.isEmpty)
    }
    XCTAssertEqual(applied, 1)
    XCTAssertEqual(try f.journal.inbox.pending().count, 3)
  }

  func testStoredReceiptCancelsDispatchOnlyAfterDurableConsumption() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    _ = try await f.dispatch.submit(topic: f.peer.binding.sendTopic, delivery: XCTUnwrap(f.peer.prepare()))
    try f.stageStoredReceipt()
    try f.storage.execute("CREATE TRIGGER fail_consume BEFORE UPDATE ON mqtt_business_inbox BEGIN SELECT RAISE(ABORT,'forced'); END")
    do { _ = try await f.receipts.consumeStored(identity: f.entry.identity, receiptMessageID: "ack", journal: f.journal)
      XCTFail("Consumption failure must propagate") }
    catch { XCTAssertTrue(error is MqttChunkStorageError) }
    XCTAssertTrue(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    try f.storage.execute("DROP TRIGGER fail_consume")
    let event = try await f.receipts.consumeStored(identity: f.entry.identity, receiptMessageID: "ack", journal: f.journal)
    XCTAssertNotNil(event)
    XCTAssertFalse(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    XCTAssertTrue(try f.journal.inbox.pending().isEmpty)
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
    XCTAssertTrue(f.peer.pool.policy.diagnostics(now: f.peer.time).verifiedDelivery.values.allSatisfy { $0.samples == 0 })
  }

  func testCompletionReplayClosesCrashGapWithoutReconsumingReceipt() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    _ = try await f.dispatch.submit(topic: f.peer.binding.sendTopic, delivery: XCTUnwrap(f.peer.prepare()))
    try f.stageStoredReceipt()
    _ = try f.peer.routes.consumeStoredReceipt(identity: f.entry.identity, receiptMessageID: "ack", journal: f.journal)
    XCTAssertTrue(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    let first = try await f.receipts.resumeCompletion(identity: f.entry.identity, messageID: "message", journal: f.journal)
    let second = try await f.receipts.resumeCompletion(identity: f.entry.identity, messageID: "message", journal: f.journal)
    XCTAssertEqual(first, second)
    XCTAssertNotNil(first)
    XCTAssertFalse(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
  }

  func testCompletionReplayRequiresPersistedProof() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    _ = try await f.dispatch.submit(topic: f.peer.binding.sendTopic, delivery: XCTUnwrap(f.peer.prepare()))
    let result = try await f.receipts.resumeCompletion(identity: f.entry.identity, messageID: "message", journal: f.journal)
    XCTAssertNil(result)
    XCTAssertTrue(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
  }

  func testStoredReceiptAndCompletionReplayRejectRevokedRelationship() async throws {
    let f = try ReceiptBridgeFixture()
    try f.stageStoredReceipt()
    f.peer.binding.enabled = false
    try f.peer.routes.replace([f.peer.binding])
    do { _ = try await f.receipts.consumeStored(identity: f.entry.identity, receiptMessageID: "ack", journal: f.journal)
      XCTFail("Revoked relationship must fail") }
    catch MqttRouteError.identityChanged { }
    do { _ = try await f.receipts.resumeCompletion(identity: f.entry.identity, messageID: "message", journal: f.journal)
      XCTFail("Revoked relationship must fail") }
    catch MqttRouteError.identityChanged { }
    XCTAssertEqual(try f.journal.inbox.pending().count, 1)
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
  }

  func testReceiptWithoutLiveAttemptCommitsCompletionAndDuplicateIsIdempotent() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.packet()
    let first = try await f.receipts.accept(packet)
    XCTAssertEqual(first?.messageID, "message")
    XCTAssertNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    let duplicate = try await f.receipts.accept(packet)
    XCTAssertEqual(duplicate?.receivedAt, first?.receivedAt)
    XCTAssertEqual(try f.outbox.completions.pending().count, 1)
    XCTAssertTrue(f.peer.pool.policy.diagnostics(now: f.peer.time).verifiedDelivery.values.allSatisfy { $0.samples == 0 })
  }

  func testRevocationBeforeReceiptCommitKeepsOutgoingMessage() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let packet = try await f.packet()
    f.peer.binding.enabled = false
    try f.peer.routes.replace([f.peer.binding])
    do { _ = try await f.receipts.accept(packet); XCTFail("Revoked receipt must fail") }
    catch MqttRouteError.identityChanged { }
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    XCTAssertTrue(try f.outbox.completions.pending().isEmpty)
  }

  func testReceiptHashMismatchCannotDeleteOutboxAfterRestart() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    let bad = try MqttDeliveryEnvelope.Frame(message: .init(messageID: "message", contentHash: String(repeating: "e", count: 64),
      sender: f.entry.identity.local, receiver: f.entry.identity.remote, traffic: "message"), attempt: f.frame.attempt)
    let packet = try await f.packet(frame: bad)
    do { _ = try await f.receipts.accept(packet); XCTFail("Wrong hash must fail") }
    catch MqttRouteError.unsolicitedAcknowledgement { }
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
  }

  func testCompletionWriteFailureDoesNotConfirmLiveDispatch() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    _ = try await f.dispatch.submit(topic: f.peer.binding.sendTopic, delivery: XCTUnwrap(f.peer.prepare()))
    let frame = try XCTUnwrap(f.publications.first).frame
    let packet = try await f.packet(frame: frame)
    try f.storage.execute("CREATE TRIGGER fail_completion BEFORE INSERT ON mqtt_delivery_completions BEGIN SELECT RAISE(ABORT,'forced'); END")
    do { _ = try await f.receipts.accept(packet); XCTFail("Storage failure must propagate") }
    catch { XCTAssertTrue(error is MqttChunkStorageError) }
    XCTAssertTrue(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    XCTAssertTrue(try f.outbox.completions.pending().isEmpty)
    XCTAssertNotNil(try f.outbox.entry(identity: f.entry.identity, messageID: "message"))
    try f.storage.execute("DROP TRIGGER fail_completion")
    let accepted = try await f.receipts.accept(packet)
    XCTAssertNotNil(accepted)
    XCTAssertFalse(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
  }

  func testUnknownPhysicalAttemptCancelsLogicalRetryWithoutInventingRTT() async throws {
    let f = try ReceiptBridgeFixture()
    await f.peer.start()
    try await f.peer.handshake()
    _ = try await f.dispatch.submit(topic: f.peer.binding.sendTopic, delivery: XCTUnwrap(f.peer.prepare()))
    let packet = try await f.packet()
    let result = try await f.receipts.accept(packet)
    XCTAssertNotNil(result)
    XCTAssertFalse(f.peer.pool.policy.pending(peer: f.peer.binding.scope, messageID: "message"))
    XCTAssertTrue(f.peer.pool.policy.diagnostics(now: f.peer.time).verifiedDelivery.values.allSatisfy { $0.samples == 0 })
  }

  func testApprovedOfflineBindingCanCommitOutboxWithoutRouteReadiness() throws {
    let fixture = try PeerRoutesFixture()
    let identity = try MqttBusinessIdentity(fixture.binding)
    XCTAssertFalse(fixture.routes.isReady(scope: identity.scope))
    let result = try fixture.routes.withOutgoing(identity: identity, topics: [fixture.binding.sendTopic]) { "committed" }
    XCTAssertEqual(result, "committed")
    XCTAssertTrue(fixture.path.publications.isEmpty)
  }

  func testRevocationAndKeyRotationPreventQueuedCommit() throws {
    let fixture = try PeerRoutesFixture()
    let identity = try MqttBusinessIdentity(fixture.binding)
    var called = false
    fixture.binding.enabled = false
    try fixture.routes.replace([fixture.binding])
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity, topics: [fixture.binding.sendTopic]) { called = true })
    fixture.binding.enabled = true
    fixture.binding.secret = Data(repeating: 8, count: 32).base64URLEncodedString()
    try fixture.routes.replace([fixture.binding])
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity, topics: [fixture.binding.sendTopic]) { called = true })
    XCTAssertFalse(called)
  }

  func testOutgoingCommitRequiresEveryTopicToBelongToCurrentPeer() throws {
    let fixture = try PeerRoutesFixture()
    let identity = try MqttBusinessIdentity(fixture.binding)
    var called = false
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity, topics: []) { called = true })
    XCTAssertThrowsError(try fixture.routes.withOutgoing(identity: identity,
      topics: [fixture.binding.sendTopic, String(repeating: "x", count: 43)]) { called = true })
    XCTAssertFalse(called)
  }

  func testConnectedBrokerIsNotReadyUntilMatchingPeerAcknowledgement() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertNil(try fixture.prepare())
    try await fixture.handshake()
    XCTAssertTrue(fixture.routes.readyForTopic(fixture.binding.sendTopic))
    let delivery = try XCTUnwrap(fixture.prepare())
    XCTAssertTrue(delivery.authorized("emqx", 1))
    XCTAssertFalse(delivery.authorized("hivemq", 1))
    XCTAssertFalse(delivery.authorized("emqx", 2))
    XCTAssertEqual(fixture.readyEvents, [fixture.binding.scope])
  }

  func testApprovalEnablesWarmHandshakeAndRevocationInvalidatesPreparedPacket() async throws {
    let fixture = try PeerRoutesFixture(enabled: false)
    await fixture.start()
    try await fixture.handshake()
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertTrue(fixture.readyEvents.isEmpty)
    fixture.binding.enabled = true
    try fixture.routes.replace([fixture.binding])
    XCTAssertEqual(fixture.readyEvents, [fixture.binding.scope])
    let delivery = try XCTUnwrap(fixture.prepare())
    let frame = try MqttDeliveryEnvelope.Frame(message: delivery.message,
      attempt: .init(attemptID: String(repeating: "f", count: 32), brokerID: "emqx", generation: 1))
    var packet = try MqttSealedPathPublication(publication: .init(topic: fixture.binding.sendTopic,
      payload: delivery.encodeAttempt(frame), frame: frame, receiveTopics: delivery.receiveTopics,
      secretFingerprint: delivery.secretFingerprint, authorized: delivery.authorized), completed: { _ in })
    packet.configurationID = fixture.snapshot.configurationID
    XCTAssertTrue(packet.accepts(snapshot: fixture.snapshot, secretFingerprint: fixture.binding.secretFingerprint))
    fixture.binding.enabled = false
    try fixture.routes.replace([fixture.binding])
    XCTAssertFalse(delivery.authorized("emqx", 1))
    XCTAssertFalse(packet.accepts(snapshot: fixture.snapshot, secretFingerprint: fixture.binding.secretFingerprint))
  }

  func testKeyReplacementRetiresOldClosuresAndRequiresNewHandshake() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    let old = try XCTUnwrap(fixture.prepare())
    let oldBinding = fixture.binding
    fixture.binding.secret = Data(repeating: 8, count: 32).base64URLEncodedString()
    try fixture.routes.replace([fixture.binding])
    XCTAssertFalse(old.authorized("emqx", 1))
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertNil(try fixture.prepare())
    let obsolete = try fixture.ingress(["body": "stale"], binding: oldBinding)
    do {
      _ = try await fixture.routes.receive(obsolete)
      XCTFail("An old relationship must not authenticate as its replacement")
    } catch MqttRouteError.identityChanged { }
  }

  func testIngressIsBoundToActualTopicKeyConfigurationAndGeneration() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let original = try fixture.ingress(["body": "business"])
    var wrongTopic = original
    wrongTopic.topic = String(repeating: "x", count: 43)
    var wrongKey = original
    wrongKey.secretFingerprint = String(repeating: "c", count: 64)
    var wrongGeneration = original
    wrongGeneration.generation = 2
    var wrongConfiguration = original
    wrongConfiguration.configurationID = "obsolete"
    for packet in [wrongTopic, wrongKey, wrongGeneration, wrongConfiguration] {
      do { _ = try await fixture.routes.receive(packet); XCTFail("Unbound ingress must be rejected") }
      catch { XCTAssertTrue(error is MqttRouteError) }
    }
  }

  func testBusinessCommitRechecksBindingAfterIngressParsing() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let reception = try await fixture.routes.receive(fixture.ingress(["body": "business"]))
    XCTAssertFalse(reception.handled)
    let packet = try XCTUnwrap(reception.packet)
    XCTAssertTrue(fixture.routes.isCurrent(packet))
    var commits = 0
    try fixture.routes.withCurrent(packet) { commits += 1 }
    fixture.binding.enabled = false
    try fixture.routes.replace([fixture.binding])
    XCTAssertFalse(fixture.routes.isCurrent(packet))
    XCTAssertThrowsError(try fixture.routes.withCurrent(packet) { commits += 1 })
    XCTAssertEqual(commits, 1)
  }

  func testDisabledPairCannotForwardBusinessIngress() async throws {
    let fixture = try PeerRoutesFixture(enabled: false)
    await fixture.start()
    do {
      _ = try await fixture.routes.receive(fixture.ingress(["body": "business"]))
      XCTFail("Approval is required for business ingress")
    } catch MqttRouteError.identityChanged { }
  }

  func testRemoteResumeRespondsOnIngressPathWithoutDeclaringApplicationReady() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let response = try await fixture.routes.receive(fixture.ingress(fixture.remote().wire()))
    XCTAssertTrue(response.handled)
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    let packet = try XCTUnwrap(fixture.path.publications.last)
    let value = try XCTUnwrap(JSONSerialization.jsonObject(with: packet.payload) as? [String: Any])
    XCTAssertEqual(value["type"] as? String, "link_resume_ack")
    XCTAssertEqual(packet.generation, 1)
    XCTAssertEqual(packet.topic, fixture.binding.sendTopic)
    _ = try await fixture.routes.receive(fixture.ingress(fixture.remote().wire()))
    XCTAssertEqual(fixture.path.publications.count, 1)
  }

  func testReceiveTopicRotationInvalidatesHandshakeEvenWithSameBrokerGeneration() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    let old = try XCTUnwrap(fixture.prepare())
    fixture.binding.receiveTopics.insert(String(repeating: "c", count: 43))
    try fixture.routes.replace([fixture.binding])
    await fixture.emit(topics: fixture.binding.receiveTopics)
    XCTAssertFalse(fixture.routes.isReady(scope: fixture.binding.scope))
    XCTAssertFalse(old.authorized("emqx", 1))
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.path.publications.count, 2)
  }

  func testRetirementPreservesEpochAndRemovesOutgoingLookup() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    let first = try fixture.local()
    try fixture.routes.replace([])
    XCTAssertEqual(fixture.routes.blockedReason(topic: fixture.binding.sendTopic), "missing_binding")
    XCTAssertNil(try fixture.persistence.cached(peer: fixture.binding.scope, sender: fixture.binding.receiver,
      receiver: fixture.binding.sender, now: fixture.time))
    try fixture.routes.replace([fixture.binding])
    await fixture.routes.maintenance()
    XCTAssertGreaterThan(try fixture.local().epoch, first.epoch)
  }

  func testMaintenanceRotatesBoundedBatchesAndHonorsUrgentRequest() async throws {
    let fixture = try PeerRoutesFixture()
    let bindings = (0..<20).map { index -> MqttPeerBinding in
      var value = fixture.binding
      value.scope = "peer-\(index)"
      value.sendTopic = Data(repeating: UInt8(index + 10), count: 32).base64URLEncodedString()
      value.sendTopics = [value.sendTopic]
      return value
    }
    try fixture.routes.replace(bindings)
    await fixture.start()
    await fixture.routes.maintenance(limit: 4)
    XCTAssertEqual(fixture.path.publications.count, 4)
    await fixture.routes.maintenance(limit: 4)
    XCTAssertEqual(fixture.path.publications.count, 8)
    fixture.routes.request("peer-19")
    await fixture.routes.maintenance(limit: 1)
    XCTAssertEqual(fixture.path.publications.last?.topic, bindings[19].sendTopic)
    await fixture.routes.maintenance(limit: 0)
    XCTAssertEqual(fixture.path.publications.count, 9)
  }

  func testInvalidReplacementDoesNotRemoveExistingBindings() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    var duplicate = fixture.binding
    duplicate.scope = "other"
    XCTAssertThrowsError(try fixture.routes.replace([fixture.binding, duplicate]))
    XCTAssertTrue(fixture.routes.isReady(scope: fixture.binding.scope))
    var invalid = fixture.binding
    invalid.receiveTopics = []
    XCTAssertThrowsError(try fixture.routes.replace([invalid]))
    XCTAssertTrue(fixture.routes.isReady(scope: fixture.binding.scope))
  }

  func testUnreadablePersistenceBacksOffAndDoesNotEmitSuccessfulHandshake() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    let key = try fixture.persistence.storageKey(fixture.binding.scope)
    fixture.defaults.set(Data([0]), forKey: key + ".encrypted.v1")
    await fixture.routes.maintenance()
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.failures, 1)
    XCTAssertTrue(fixture.path.publications.isEmpty)
    fixture.time += 5000
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.failures, 2)
  }

  func testBlockedRecoveryUsesVerifiedPeerHistoryAndCooldownAfterGenerationChange() async throws {
    let fixture = try PeerRoutesFixture()
    await fixture.start()
    try await fixture.handshake()
    await fixture.emit(topics: fixture.binding.receiveTopics, generation: 2)
    XCTAssertFalse(fixture.routes.readyForTopic(fixture.binding.sendTopic))
    XCTAssertFalse(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    fixture.time += 30_000
    XCTAssertTrue(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    XCTAssertFalse(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    await fixture.routes.maintenance()
    XCTAssertEqual(fixture.path.publications.last?.generation, 2)
    XCTAssertEqual(fixture.routes.blockedReason(topic: fixture.binding.sendTopic), "unconfirmed_local_epoch")
    fixture.time += 119_999
    XCTAssertFalse(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
    fixture.time += 1
    XCTAssertTrue(fixture.routes.recoverBlockedSend(topic: fixture.binding.sendTopic))
  }
}

private final class PeerRoutesFixture {
  let suite: String
  let defaults: UserDefaults
  let persistence: MqttRouteState
  let pool: GalaxySSIMqttBrokerPool
  let path: FakeMqttBrokerPath
  var binding: MqttPeerBinding
  var time: Int64 = 1000
  var readyEvents: [String] = []
  var failures = 0
  private(set) var snapshot = MqttBrokerPathSnapshot(brokerID: "emqx", generation: 1, connected: true, subscriptions: [])
  lazy var routes = MqttPeerRoutes(pool: pool, persistence: persistence, wall: { [weak self] in self?.time ?? 0 },
    now: { [weak self] in self?.time ?? 0 }, onReady: { [weak self] in self?.readyEvents.append($0) },
    onFailure: { [weak self] _, _ in self?.failures += 1 })

  init(enabled: Bool = true) throws {
    let suite = "PeerRoutes-\(UUID().uuidString)"
    self.suite = suite
    let defaults = UserDefaults(suiteName: suite)!
    self.defaults = defaults
    persistence = MqttRouteState(defaults: defaults, secrets: InMemorySecretStore())
    let binding = MqttPeerBinding(scope: "pair", sender: String(repeating: "a", count: 64), receiver: String(repeating: "b", count: 64),
      secret: Data(repeating: 7, count: 32).base64URLEncodedString(), sendTopic: String(repeating: "s", count: 43),
      sendTopics: [String(repeating: "s", count: 43)], receiveTopics: [String(repeating: "r", count: 43)], enabled: enabled)
    self.binding = binding
    var created: [String: FakeMqttBrokerPath] = [:]
    let pool = GalaxySSIMqttBrokerPool { endpoint in
      let value = FakeMqttBrokerPath(id: endpoint.id)
      created[endpoint.id] = value
      return value
    }
    self.pool = pool
    let path = created["emqx"]!
    self.path = path
    path.currentSecretFingerprint = binding.secretFingerprint
    pool.onPathState = { [weak self] in self?.routes.synchronize($0) }
    try routes.replace([binding])
  }
  deinit { defaults.removePersistentDomain(forName: suite) }
  func start() async {
    pool.connect(.init(clientID: "routes", serverLinks: [], phoneRoutes: [], rendezvousSecrets: [:], rendezvousExpirations: [:]))
    _ = await pool.readyGenerations(for: binding.receiveTopics)
    await emit(topics: binding.receiveTopics)
  }
  func emit(topics: Set<String>, generation: Int64 = 1) async {
    snapshot.generation = generation
    snapshot.subscriptions = topics
    snapshot.configurationID = path.configuration?.configurationID ?? ""
    path.emit(snapshot)
    _ = await pool.readyGenerations(for: topics)
  }
  func ingress(_ payload: [String: Any], binding: MqttPeerBinding? = nil) throws -> MqttAuthenticatedIngress {
    let binding = binding ?? self.binding
    return MqttAuthenticatedIngress(brokerID: "emqx", generation: snapshot.generation, topic: binding.receiveTopics.sorted()[0],
      secretFingerprint: binding.secretFingerprint, payload: try GalaxySSILinkProtocol.jsonData(payload),
      configurationID: snapshot.configurationID)
  }
  func remote() -> MqttRouteAdvertisement {
    MqttRouteAdvertisement(sender: binding.receiver, receiver: binding.sender, epoch: 2000,
      resumeId: String(repeating: "c", count: 32), issuedAt: time, expiresAt: time + 300_000,
      receiveBrokers: ["emqx"], packetBytes: 1_048_576)
  }
  func local() throws -> MqttRouteAdvertisement {
    let packet = try XCTUnwrap(path.publications.last)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: packet.payload) as? [String: Any])
    return try MqttRouteAdvertisement.parseVerified(object, sender: binding.sender, receiver: binding.receiver, now: time)
  }
  func handshake() async throws {
    await routes.maintenance()
    let ours = try local()
    _ = try await routes.receive(ingress(["type": "link_resume_ack", "advertisement": remote().wire(),
      "acknowledged_route_epoch": ours.epoch, "acknowledged_resume_id": ours.resumeId, "acknowledged_digest": try ours.digest()]))
  }
  func prepare() throws -> MqttDeliveryDispatch.Delivery? {
    try routes.prepareDelivery(topic: binding.sendTopic,
      wire: GalaxySSILinkProtocol.jsonData(["scheme": "signal", "from": "sender", "to": "receiver", "body": "AA=="]),
      messageID: "message", traffic: .message)
  }
}

private final class ReceiptBridgeFixture {
  let peer: PeerRoutesFixture
  let storage: ChunkFixture
  let journal: MqttSignalStateJournal
  let outbox: MqttBusinessOutbox
  let entry: MqttBusinessOutbox.Entry
  let frame: MqttDeliveryEnvelope.Frame
  var publications: [MqttDeliveryDispatch.Publication] = []
  lazy var dispatch = MqttDeliveryDispatch(policy: peer.pool.policy, publish: { [weak self] packet in
    self?.publications.append(packet); return true
  }, brokerCompleted: { _, _ in }, now: { [weak self] in self?.peer.time ?? 0 })
  lazy var receipts = MqttBusinessReceipts(routes: peer.routes, outbox: outbox, dispatcher: dispatch,
    now: { Date(timeIntervalSince1970: 1) })

  init() throws {
    peer = try PeerRoutesFixture()
    storage = try ChunkFixture()
    journal = try MqttSignalStateJournal(fileURL: storage.url, secrets: storage.secrets)
    outbox = journal.outbox
    let identity = try MqttBusinessIdentity(peer.binding)
    let wire = try GalaxySSILinkProtocol.jsonData(["scheme": "signal", "from": "sender", "to": "receiver", "body": "AA=="])
    let date = Date(timeIntervalSince1970: 1)
    let message = PendingLinkMessage(messageId: "message", topic: peer.binding.sendTopic, wirePayload: String(decoding: wire, as: UTF8.self),
      status: "queued", attempts: 0, nextAttemptAt: date, createdAt: date, updatedAt: date)
    try outbox.enqueue(identity: identity, message: message, traffic: .message)
    entry = try XCTUnwrap(outbox.entry(identity: identity, messageID: "message"))
    frame = try MqttDeliveryEnvelope.Frame(message: .init(messageID: "message", contentHash: entry.wireHash,
      sender: identity.local, receiver: identity.remote, traffic: "message"),
      attempt: .init(attemptID: String(repeating: "d", count: 32), brokerID: "emqx", generation: 1))
  }

  func packet(frame: MqttDeliveryEnvelope.Frame? = nil) async throws -> MqttPeerRoutes.VerifiedPacket {
    let frame = frame ?? self.frame
    let reception = try await peer.routes.receive(peer.ingress(frame.receiptAfterStore(messageID: "message", wireHash: frame.message.contentHash)))
    return try XCTUnwrap(reception.packet)
  }

  func stageStoredReceipt() throws {
    var payload = try MqttDeliveryEnvelope.storedReceipt(messageID: "message", wireHash: entry.wireHash)
    payload["message_id"] = "ack"
    _ = try journal.inbox.accept(identity: entry.identity, messageID: "ack", payload: payload,
      ciphertextDigest: String(repeating: "e", count: 64), wireHash: String(repeating: "f", count: 64), receiptRequired: false)
  }

  func sendDrain() -> MqttBusinessSendDrain {
    MqttBusinessSendDrain(outbox: outbox, routes: peer.routes, dispatcher: dispatch,
      engine: GalaxySSISignalEngine(profileName: "test", defaults: peer.defaults, secrets: storage.secrets),
      now: { [weak self] in Date(timeIntervalSince1970: Double(self?.peer.time ?? 0) / 1000) })
  }

  func incomingPacket(body: String = "AA==", traffic: String = "message") async throws -> MqttPeerRoutes.VerifiedPacket {
    let wire: [String: Any] = ["scheme": "signal", "from": "remote", "to": "local", "body": body]
    let incoming = try MqttDeliveryEnvelope.Frame(message: .init(messageID: "incoming",
      contentHash: MqttDeliveryEnvelope.contentHash(wire), sender: entry.identity.remote,
      receiver: entry.identity.local, traffic: traffic),
      attempt: .init(attemptID: String(repeating: "e", count: 32), brokerID: "emqx", generation: 4))
    let reception = try await peer.routes.receive(peer.ingress(incoming.attach(to: wire)))
    return try XCTUnwrap(reception.packet)
  }

  func stageIncoming(_ packet: MqttPeerRoutes.VerifiedPacket, receiptRequired: Bool = true) throws {
    let hash = try MqttDeliveryEnvelope.contentHash(packet.payload)
    _ = try journal.inbox.accept(identity: entry.identity, messageID: "incoming",
      payload: ["message_id": "incoming", "type": receiptRequired ? "message" : "delivery_ack"],
      ciphertextDigest: hash, wireHash: hash, receiptRequired: receiptRequired)
  }
}

private actor ReceiptDrainGate {
  private var entered = false
  private var entryWaiter: CheckedContinuation<Void, Never>?
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func hold() async {
    await withCheckedContinuation { continuation in
      releaseWaiter = continuation
      entered = true
      entryWaiter?.resume()
      entryWaiter = nil
    }
  }
  func waitForEntry() async {
    if entered { return }
    await withCheckedContinuation { entryWaiter = $0 }
  }
  func release() {
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}
