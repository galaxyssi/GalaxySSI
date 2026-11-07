import XCTest
@testable import GalaxySSI

@MainActor
final class GalaxySSILinkReliabilityTests: XCTestCase {
  func testPausingLearningKeepsOutboxEntriesWithoutBlockingOrdinaryMessages() throws {
    let fixture = try ChunkFixture()
    let suite = "learning-outbox-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let journal = GalaxySSIChatHistoryDatabase(fileURL: fixture.url, secrets: fixture.secrets)
    let store = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    let now = Date(timeIntervalSince1970: 100)
    let learning = UUID().uuidString, chat = UUID().uuidString
    store.enqueue(messageId: learning, topic: "topic/up", wirePayload: "learning", clientSourceMessageId: "123",
      backgroundLearning: true, now: now)
    store.enqueue(messageId: chat, topic: "topic/up", wirePayload: "chat", clientSourceMessageId: "123", now: now)
    store.markAttempt(messageId: learning, now: now)
    let reopened = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    let eligible: (PendingLinkMessage) -> Bool = {
      AgentIOSCognitionSchedulePolicy.allowsTransport($0, learningEnabled: false, legacySources: ["123"])
    }
    let later = now.addingTimeInterval(60)
    XCTAssertTrue(reopened.recoverInterruptedPublishing(eligible: eligible).isEmpty)
    XCTAssertTrue(reopened.discardExhausted(maxAttempts: 1, now: later, eligible: eligible).isEmpty)
    XCTAssertEqual(reopened.pending(now: later, eligible: eligible).map(\.messageId), [chat])
    reopened.acknowledge(messageId: chat)
    XCTAssertNil(reopened.nextRetryDelay(now: later, eligible: eligible))
    XCTAssertTrue(reopened.containsOutboxMessage(learning))
    let restored = try XCTUnwrap(reopened.pending(now: later).first)
    XCTAssertEqual(restored.backgroundLearning, true)
    XCTAssertEqual(restored.messageId, learning)
  }

  func testContactReminderOutboxPersistsCiphertextAndRejectsIdentifierReuse() throws {
    let fixture = try ChunkFixture()
    let suite = "contact-reminder-outbox-" + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let journal = GalaxySSIChatHistoryDatabase(fileURL: fixture.url, secrets: fixture.secrets)
    let delivery = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    let record = GalaxySSIContactReminder(id: UUID().uuidString, peerID: "peer", outgoing: true,
      createdAt: 1_000, expiresAt: 121_000, historyID: UUID(), status: .queued, pendingAction: .request)
    let source = GalaxySSIContactReminderOutbox.source(record, action: .request)
    let now = Date(timeIntervalSince1970: 1)
    let request = LinkDeliveryEnqueueRequest(messageId: UUID().uuidString, topic: "topic/up",
      wirePayload: "encrypted-control", requiresValidatedNetwork: false, blockedByAttachmentTransferIds: [],
      clientSourceMessageId: source, contactId: record.peerID)
    XCTAssertTrue(delivery.enqueueContactReminder(request, now: now))
    XCTAssertTrue(delivery.enqueueContactReminder(request, now: now))
    var other = request
    other.contactId = "other"
    XCTAssertFalse(delivery.enqueueContactReminder(other, now: now))
    let reopened = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertEqual(reopened.pending(now: now).map(\.wirePayload), ["encrypted-control"])
    XCTAssertFalse(GalaxySSIContactReminderOutbox.isExpired(source, now: 120_999))
    XCTAssertTrue(GalaxySSIContactReminderOutbox.isExpired(source, now: 121_000))
    XCTAssertFalse(GalaxySSIContactReminderOutbox.isExpired("ordinary-message", now: 121_000))
  }

  func testConfirmedVoiceTextIsQueuedOnlyAfterAnEncryptedJournalWrite() throws {
    let fixture = try ChunkFixture()
    let suite = "voice-peer-outbox-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let journal = GalaxySSIChatHistoryDatabase(fileURL: fixture.url, secrets: fixture.secrets)
    let outbox = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    let request = LinkDeliveryEnqueueRequest(messageId: "voice", topic: "topic/up", wirePayload: "voice-ciphertext",
      requiresValidatedNetwork: false, blockedByAttachmentTransferIds: [], clientSourceMessageId: "source", contactId: "peer")
    XCTAssertTrue(outbox.stageAttachmentControl(messageId: "seed", payload: "seed"))
    try fixture.execute("CREATE TRIGGER reject_voice BEFORE UPDATE ON link_delivery_state BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertFalse(outbox.enqueueConfirmedVoiceText(request))
    XCTAssertNil(outbox.voiceTextQueueStatus(messageId: "voice", sourceId: "source", contactId: "peer"))
    try fixture.execute("DROP TRIGGER reject_voice")
    XCTAssertTrue(outbox.enqueueConfirmedVoiceText(request))
    XCTAssertFalse(outbox.enqueueConfirmedVoiceText(request))
    let reopened = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertEqual(reopened.voiceTextQueueStatus(messageId: "voice", sourceId: "source", contactId: "peer"), "queued")
    XCTAssertNil(reopened.voiceTextQueueStatus(messageId: "voice", sourceId: "source", contactId: "other"))
    XCTAssertNil(try fixture.blob("SELECT encrypted_payload FROM link_delivery_state").range(of: Data("voice-ciphertext".utf8)))
  }

  func testDeferredAttachmentTaskRequiresEveryReceiptAndPersistsCiphertext() throws {
    let fixture = try ChunkFixture()
    let suite = "deferred-task-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let journal = GalaxySSIChatHistoryDatabase(fileURL: fixture.url, secrets: fixture.secrets)
    let store = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    let ids = ["a", "b"].map { String(repeating: $0, count: 64) }
    let task = LinkDeliveryEnqueueRequest(messageId: "task", topic: "topic/up", wirePayload: "",
      requiresValidatedNetwork: false, blockedByAttachmentTransferIds: ids,
      clientSourceMessageId: "source", contactId: "contact")
    let manifests = ids.map {
      LinkDeliveryEnqueueRequest(messageId: $0, topic: "topic/up", wirePayload: "encrypted-manifest",
        requiresValidatedNetwork: false, blockedByAttachmentTransferIds: [],
        clientSourceMessageId: "source", contactId: "contact", attachmentTransferId: $0)
    }
    let now = Date()
    XCTAssertTrue(store.enqueueDeferredAttachmentTask(task, payload: "private-task", attachments: manifests, now: now))
    XCTAssertFalse(store.pending(now: now).contains { $0.messageId == "task" })
    XCTAssertEqual(store.releaseAttachmentDependency(ids[0], now: now), 0)
    XCTAssertFalse(store.pending(now: now).contains { $0.messageId == "task" })
    XCTAssertEqual(store.releaseAttachmentDependency(ids[1], now: now), 1)
    let ready = try XCTUnwrap(store.pending(now: now).first { $0.messageId == "task" })
    XCTAssertEqual(ready.deferredTaskPayload, "private-task")
    XCTAssertTrue(ready.wirePayload.isEmpty)
    XCTAssertTrue(store.commitDeferredTaskCiphertext(ready, wirePayload: "encrypted-task"))
    XCTAssertFalse(store.commitDeferredTaskCiphertext(ready, wirePayload: "replacement"))
    let reopened = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    let saved = try XCTUnwrap(reopened.pending(now: now.addingTimeInterval(1)).first { $0.messageId == "task" })
    XCTAssertNil(saved.deferredTaskPayload)
    XCTAssertEqual(saved.wirePayload, "encrypted-task")
  }

  func testReceiptCreditIsPerRouteAndReleasedByPeerReceiptOrTimeout() {
    var window = LinkOutboxReceiptWindow()
    for index in 0..<8 {
      XCTAssertTrue(window.acquire(topic: "a", messageId: "message-\(index)", now: 100))
    }
    XCTAssertEqual(window.delay(topic: "a", messageId: "fresh", now: 101), 29)
    XCTAssertEqual(window.delay(topic: "a", messageId: "message-0", now: 101), 29)
    XCTAssertTrue(window.acquire(topic: "b", messageId: "other", now: 101))
    XCTAssertFalse(window.acquire(topic: "a", messageId: "fresh", now: 101))
    window.release("message-0")
    XCTAssertTrue(window.acquire(topic: "a", messageId: "fresh", now: 101))
    window.reconcile(now: 102) { $0 != "message-1" }
    XCTAssertTrue(window.acquire(topic: "a", messageId: "next", now: 102))
    window.reconcile(now: 130) { _ in true }
    XCTAssertFalse(window.messageIds.contains("message-2"))
    XCTAssertTrue(window.acquire(topic: "a", messageId: "message-2", now: 130))
  }

  func testReceiptCreditDelayDoesNotModifyDurableRetryBudget() throws {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 1_000)
    store.enqueue(messageId: "send", topic: "topic/up", wirePayload: "encrypted-wire", now: now)
    XCTAssertEqual(store.nextRetryDelay(now: now, minimumDelay: { _ in 1 }), 1)
    XCTAssertEqual(try XCTUnwrap(store.pending(now: now).first).attempts, 0)
  }

  func testReconnectOnlyWakesUnsentRowsAndKeepsAttemptedBackoff() throws {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 1_000)
    store.enqueue(messageId: "sent", topic: "topic/up", wirePayload: "wire", now: now)
    store.markAttempt(messageId: "sent", now: now)
    store.markPublished(messageId: "sent", now: now)
    store.enqueue(messageId: "new", topic: "topic/up", wirePayload: "wire", now: now.addingTimeInterval(100))
    let deadline = try XCTUnwrap(store.outboxMigrationSnapshot().first { $0.messageId == "sent" }?.nextAttemptAt)
    store.makePendingImmediatelyRetryable(now: now)
    XCTAssertEqual(store.pending(now: now).map(\.messageId), ["new"])
    let attempted = try XCTUnwrap(store.outboxMigrationSnapshot().first { $0.messageId == "sent" })
    XCTAssertEqual(attempted.nextAttemptAt, deadline)
    XCTAssertEqual(attempted.status, "published")
  }

  func testStaleUnclassifiedLegacyOutboxRowIsRetainedWithoutReplaying() throws {
    let suite = "held-outbox-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let secrets = InMemorySecretStore()
    let old = Date(timeIntervalSince1970: 1_000)
    let now = old.addingTimeInterval(901)
    let original = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: secrets)
    original.enqueue(messageId: "legacy", topic: "topic/up", wirePayload: "legacy-wire", now: old)
    original.enqueue(messageId: "tracked", topic: "topic/up", wirePayload: "tracked-wire",
      clientSourceMessageId: "source", now: old)
    original.enqueue(messageId: "modern", topic: "topic/up", wirePayload: "modern-wire", now: old)
    let key = "galaxyssi-ios-link-delivery-v1"
    let data = try XCTUnwrap(defaults.data(forKey: key))
    var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var rows = try XCTUnwrap(snapshot["outbox"] as? [[String: Any]])
    for index in rows.indices where rows[index]["messageId"] as? String != "modern" {
      rows[index].removeValue(forKey: "retry_classified")
    }
    snapshot["outbox"] = rows
    defaults.set(try JSONSerialization.data(withJSONObject: snapshot), forKey: key)
    let restored = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: secrets)
    XCTAssertEqual(restored.holdStaleUnclassified(now: now, activeMessageIds: ["legacy"]), 0)
    XCTAssertEqual(restored.holdStaleUnclassified(now: now), 1)
    restored.makePendingImmediatelyRetryable(now: now)
    restored.markPublished(messageId: "legacy", now: now)
    let reopened = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: secrets)
    XCTAssertEqual(Set(reopened.pending(now: now).map(\.messageId)), ["tracked", "modern"])
    XCTAssertTrue(reopened.discardExhausted(maxAttempts: 1, now: now).isEmpty)
    let held = try XCTUnwrap(reopened.outboxMigrationSnapshot().first { $0.messageId == "legacy" })
    XCTAssertTrue(held.isHeld)
    XCTAssertEqual(held.wirePayload, "legacy-wire")
  }

  func testAdmissionDeferralPreservesEarlierAttemptAndCiphertext() throws {
    let store = makeDeliveryStore()
    let start = Date(timeIntervalSince1970: 1_000)
    let reservation = start.addingTimeInterval(10)
    store.enqueue(messageId: "send", topic: "topic/up", wirePayload: "encrypted-wire", now: start)
    store.markAttempt(messageId: "send", now: start)
    store.markAttempt(messageId: "send", now: reservation)
    XCTAssertTrue(store.deferUnadmittedAttempt(messageId: "send", reservedAttempts: 2,
      reservedAt: reservation, now: reservation))
    XCTAssertTrue(store.pending(now: reservation).isEmpty)
    let retried = try XCTUnwrap(store.pending(now: reservation.addingTimeInterval(2)).first)
    XCTAssertEqual(retried.attempts, 1)
    XCTAssertEqual(retried.wirePayload, "encrypted-wire")
    XCTAssertEqual(retried.status, "queued")
  }

  func testAdmissionDeferralDoesNotOverwriteBrokerOrPeerReceipt() throws {
    let store = makeDeliveryStore()
    let start = Date(timeIntervalSince1970: 1_000)
    store.enqueue(messageId: "send", topic: "topic/up", wirePayload: "encrypted-wire", now: start)
    store.markAttempt(messageId: "send", now: start)
    store.markPublished(messageId: "send", now: start)
    XCTAssertFalse(store.deferUnadmittedAttempt(messageId: "send", reservedAttempts: 1,
      reservedAt: start, now: start))
    XCTAssertEqual(try store.outboxMigrationSnapshot().first?.status, "published")
    store.acknowledge(messageId: "send")
    XCTAssertFalse(store.deferUnadmittedAttempt(messageId: "send", reservedAttempts: 1,
      reservedAt: start, now: start))
    XCTAssertTrue(try store.outboxMigrationSnapshot().isEmpty)
  }

  func testAttachmentControlQueueFailureRetainsControlAcrossReopen() throws {
    let fixture = try ChunkFixture()
    let suite = "attachment-control-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let journal = GalaxySSIChatHistoryDatabase(fileURL: fixture.url, secrets: fixture.secrets)
    let store = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertTrue(store.stageAttachmentControl(messageId: "control", payload: "authenticated-private-control"))
    let requests = ["result", "manifest", "chunk"].map { id in
      LinkDeliveryEnqueueRequest(messageId: id, topic: "topic/up", wirePayload: "ciphertext-\(id)",
        requiresValidatedNetwork: false, blockedByAttachmentTransferIds: [], clientSourceMessageId: "source", contactId: "contact")
    }
    try fixture.execute("CREATE TRIGGER reject_control BEFORE UPDATE ON link_delivery_state BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertFalse(store.commitAttachmentControl(requests, messageId: "control"))
    XCTAssertTrue(try store.outboxMigrationSnapshot().isEmpty)
    XCTAssertEqual(store.pendingIncoming().map(\.messageId), ["control"])
    let reopened = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertEqual(reopened.pendingIncoming().first?.payload, "authenticated-private-control")
    XCTAssertTrue(try reopened.outboxMigrationSnapshot().isEmpty)
    try fixture.execute("DROP TRIGGER reject_control")
    XCTAssertTrue(reopened.commitAttachmentControl(requests, messageId: "control"))
    let accepted = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertTrue(accepted.pendingIncoming().isEmpty)
    XCTAssertEqual(try accepted.outboxMigrationSnapshot().map(\.messageId), ["result", "manifest", "chunk"])
    XCTAssertEqual(accepted.stageIncoming(messageId: "control", payload: "duplicate"), .completed)
    XCTAssertNil(try fixture.blob("SELECT encrypted_payload FROM link_delivery_state").range(of: Data("authenticated-private-control".utf8)))
  }

  func testAttachmentControlRejectsInvalidBatchAndConflictingWireIdentity() throws {
    let fixture = try ChunkFixture()
    let suite = "attachment-control-invalid-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let journal = GalaxySSIChatHistoryDatabase(fileURL: fixture.url, secrets: fixture.secrets)
    let store = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    store.enqueue(messageId: "existing", topic: "topic/up", wirePayload: "original")
    XCTAssertTrue(store.stageAttachmentControl(messageId: "control", payload: "authenticated"))
    let conflict = LinkDeliveryEnqueueRequest(messageId: "existing", topic: "topic/up", wirePayload: "changed",
      requiresValidatedNetwork: false, blockedByAttachmentTransferIds: [], clientSourceMessageId: "source", contactId: "contact")
    XCTAssertFalse(store.commitAttachmentControl([conflict], messageId: "control"))
    XCTAssertEqual(try store.outboxMigrationSnapshot().first?.wirePayload, "original")
    XCTAssertEqual(store.pendingIncoming().map(\.messageId), ["control"])
    XCTAssertFalse(store.commitAttachmentControl([], messageId: "control"))
    XCTAssertFalse(store.commitAttachmentControl([conflict, conflict], messageId: "control"))
  }

  func testLinkDeliveryMigrationCommitsBeforeDeletingLegacyAndRejectsCorruption() throws {
    let fixture = try ChunkFixture()
    let suite = "attachment-control-migration-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets)
    legacy.enqueue(messageId: "old", topic: "topic/up", wirePayload: "old-wire")
    let key = "galaxyssi-ios-link-delivery-v1"
    let saved = try XCTUnwrap(defaults.data(forKey: key))
    let journal = GalaxySSIChatHistoryDatabase(fileURL: fixture.url, secrets: fixture.secrets)
    try fixture.execute("CREATE TRIGGER reject_migration BEFORE INSERT ON link_delivery_state BEGIN SELECT RAISE(ABORT,'forced'); END")
    let rejected = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertEqual(defaults.data(forKey: key), saved)
    XCTAssertFalse(rejected.stageAttachmentControl(messageId: "new", payload: "control"))
    try fixture.execute("DROP TRIGGER reject_migration")
    let migrated = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertNil(defaults.data(forKey: key))
    XCTAssertEqual(try migrated.outboxMigrationSnapshot().first?.messageId, "old")
    defaults.set(saved, forKey: key)
    try fixture.execute("UPDATE link_delivery_state SET encrypted_payload=X'00'")
    let corrupt = GalaxySSILinkDeliveryStore(defaults: defaults, secrets: fixture.secrets, journal: journal)
    XCTAssertFalse(corrupt.stageAttachmentControl(messageId: "new", payload: "control"))
    XCTAssertThrowsError(try corrupt.outboxMigrationSnapshot())
    XCTAssertEqual(defaults.data(forKey: key), saved)
  }

  func testMigrationSnapshotIncludesBlockedNetworkAndFutureMessages() throws {
    let store = makeDeliveryStore()
    let future = Date(timeIntervalSince1970: 10_000)
    store.enqueue(messageId: "attachment", topic: "topic/up", wirePayload: "attachment-wire",
      blockedByAttachmentTransferIds: [String(repeating: "a", count: 64)], now: future)
    store.enqueue(messageId: "network", topic: "topic/up", wirePayload: "network-wire",
      requiresValidatedNetwork: true, now: future)
    XCTAssertTrue(store.pending(now: Date(timeIntervalSince1970: 1), allowValidatedNetworkMessages: false).isEmpty)
    let snapshot = try store.outboxMigrationSnapshot()
    XCTAssertEqual(Set(snapshot.map(\.messageId)), ["attachment", "network"])
    XCTAssertEqual(snapshot.first?.nextAttemptAt, future)
    XCTAssertEqual(try store.outboxMigrationSnapshot(), snapshot)
  }

  func testTransportTimingSeparatesQueueBrokerAndPeerMetricsWithBoundedHistory() {
    let store = AgentTransportTimingStore()
    for index in 0..<(AgentTransportTimingStore.maximumEvents + 8) {
      store.record(AgentTransportTimingEvent(
        kind: index % 3 == 0 ? .durableQueueWait : (index % 3 == 1 ? .brokerPublishAck : .encryptedPeerReceipt),
        attemptId: "attempt-\(index)",
        logicalMessageId: "opaque-\(index)",
        connectionGeneration: 4,
        durationMillis: Int64(index),
        recordedAtMillis: Int64(10_000 + index)
      ))
    }

    let events = store.snapshot()
    XCTAssertEqual(events.count, AgentTransportTimingStore.maximumEvents)
    XCTAssertEqual(events.first?.attemptId, "attempt-8")
    XCTAssertEqual(Set(events.map(\.kind), Set(AgentTransportTimingKind.allCases))
    XCTAssertTrue(events.allSatisfy { $0.connectionGeneration == 4 })
  }
  func testTransportPrivacyRequiresExplicitAuthorizationForBackgroundCognition() {
    let cognition: [String: Any] = [
      "type": "text",
      "conversation_id": "global-cognition:task-1"
    ]
    let evolution: [String: Any] = [
      "type": "text",
      "conversation_id": "self-evolution:task-1"
    ]
    let autonomous: [String: Any] = [
      "type": "text",
      "conversation_id": "global-autonomous:run-1"
    ]

    XCTAssertTrue(GalaxySSITransportPrivacyPolicy.isLocalOnly(cognition))
    XCTAssertFalse(GalaxySSITransportPrivacyPolicy.isLocalOnly(
      cognition,
      trustedBackgroundCognitionAuthorized: true
    ))
    XCTAssertTrue(GalaxySSITransportPrivacyPolicy.isLocalOnly(autonomous))
    XCTAssertFalse(GalaxySSITransportPrivacyPolicy.isLocalOnly(
      autonomous,
      trustedBackgroundCognitionAuthorized: true
    ))
    XCTAssertTrue(GalaxySSITransportPrivacyPolicy.isLocalOnly(
      evolution,
      trustedBackgroundCognitionAuthorized: true
    ))
  }

  func testGlobalAgentSettingsDecodePairedAuthorizationAsOptIn() throws {
    let defaults = try JSONDecoder().decode(GlobalAgentSettings.self, from: Data("{}".utf8))
    XCTAssertFalse(defaults.allowPairedAgentCognition)

    var authorized = defaults
    authorized.allowPairedAgentCognition = true
    let restored = try JSONDecoder().decode(
      GlobalAgentSettings.self,
      from: JSONEncoder().encode(authorized)
    )
    XCTAssertTrue(restored.allowPairedAgentCognition)
  }

  func testOutboxRetriesAndAcknowledgesMessages() {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 100)

    store.enqueue(messageId: "m1", topic: "topic/up", wirePayload: "{\"type\":\"text\"}", now: now)
    XCTAssertEqual(store.pending(now: now).map(\.messageId), ["m1"])

    store.markAttempt(messageId: "m1", now: now)
    XCTAssertTrue(store.pending(now: now).isEmpty)
    XCTAssertTrue(store.pending(now: now.addingTimeInterval(29)).isEmpty)
    XCTAssertEqual(store.pending(now: now.addingTimeInterval(30)).map(\.messageId), ["m1"])

    store.markPublished(messageId: "m1", now: now.addingTimeInterval(30))
    XCTAssertNotNil(store.nextRetryDelay(now: now.addingTimeInterval(30)))

    store.acknowledge(messageId: "m1")
    XCTAssertTrue(store.pending(now: now.addingTimeInterval(10)).isEmpty)
  }

  func testOutboxAttachmentDependenciesBlockReleaseAndDiscard() {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 100)
    let transferId = String(repeating: "a", count: 64)

    store.enqueue(
      messageId: "blocked",
      topic: "topic/up",
      wirePayload: "{\"type\":\"text\"}",
      blockedByAttachmentTransferIds: [transferId.uppercased(), transferId],
      now: now
    )
    XCTAssertTrue(store.pending(now: now).isEmpty)
    XCTAssertNil(store.nextRetryDelay(now: now))

    XCTAssertEqual(store.releaseAttachmentDependency(transferId.uppercased(), now: now), 1)
    XCTAssertEqual(store.pending(now: now).map(\.messageId), ["blocked"])
    XCTAssertEqual(store.releaseAttachmentDependency(transferId, now: now), 0)

    let discardStore = makeDeliveryStore()
    discardStore.enqueue(
      messageId: "blocked-discard",
      topic: "topic/up",
      wirePayload: "{\"type\":\"text\"}",
      blockedByAttachmentTransferIds: [String(repeating: "b", count: 64)],
      now: now
    )
    discardStore.enqueue(messageId: "ready", topic: "topic/up", wirePayload: "{\"type\":\"text\"}", now: now)

    XCTAssertEqual(discardStore.discardBlockedByAttachmentTransfers([String(repeating: "b", count: 64)]), 1)
    XCTAssertEqual(discardStore.pending(now: now).map(\.messageId), ["ready"])
  }

  func testPendingLinkMessageEncodesAndroidAttachmentDependencyKey() throws {
    let transferId = String(repeating: "a", count: 64)
    let message = PendingLinkMessage(
      messageId: "m1",
      topic: "topic/up",
      wirePayload: "{}",
      status: "queued",
      attempts: 0,
      nextAttemptAt: Date(timeIntervalSince1970: 100),
      createdAt: Date(timeIntervalSince1970: 100),
      updatedAt: Date(timeIntervalSince1970: 100),
      blockedByAttachmentTransferIds: [transferId.uppercased(), "invalid", transferId],
      attachmentTransferId: transferId.uppercased()
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try encoder.encode(message)) as? [String: Any])

    XCTAssertEqual(object["blocked_by_attachment_transfers"] as? [String], [transferId])
    XCTAssertEqual(object["attachment_transfer_id"] as? String, transferId)
    XCTAssertNil(object["blockedByAttachmentTransferIds"])
  }

  func testAttachmentPacketsUseSeparateBoundedRetryBudget() {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 100)
    let transferId = String(repeating: "a", count: 64)
    store.enqueue(
      messageId: "attachment-chunk",
      topic: "topic/up",
      wirePayload: "{}",
      attachmentTransferId: transferId,
      now: now
    )
    for _ in 0..<8 {
      store.markAttempt(messageId: "attachment-chunk", now: now)
    }

    XCTAssertEqual(
      store.pending(
        now: now.addingTimeInterval(60),
        maxAttempts: 6,
        attachmentMaxAttempts: 9
      ).map(\.messageId),
      ["attachment-chunk"]
    )
    XCTAssertTrue(store.discardExhausted(
      maxAttempts: 6,
      attachmentMaxAttempts: 9,
      now: now.addingTimeInterval(60)
    ).isEmpty)

    store.markAttempt(messageId: "attachment-chunk", now: now)
    let exhausted = store.discardExhausted(
      maxAttempts: 6,
      attachmentMaxAttempts: 9,
      now: now.addingTimeInterval(60)
    )

    XCTAssertEqual(exhausted.map(\.attachmentTransferId), [transferId])
    XCTAssertTrue(store.pending(now: now.addingTimeInterval(60)).isEmpty)
  }

  func testExhaustionDoesNotDiscardMessagesWithOutstandingBrokerTokens() {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 100)
    store.enqueue(messageId: "active", topic: "topic/up", wirePayload: "{}", now: now)
    for _ in 0..<6 {
      store.markAttempt(messageId: "active", now: now)
    }

    XCTAssertTrue(store.discardExhausted(
      maxAttempts: 6,
      now: now.addingTimeInterval(600),
      activeMessageIds: ["active"]
    ).isEmpty)
    XCTAssertEqual(
      store.discardExhausted(maxAttempts: 6, now: now.addingTimeInterval(600)).map(\.messageId),
      ["active"]
    )
  }

  func testExhaustedAttachmentDiscardsWholeSourceMessageGroup() throws {
    let store = makeDeliveryStore()
    let now = Date(timeIntervalSince1970: 100)
    let sourceId = UUID().uuidString
    let failedTransferId = String(repeating: "a", count: 64)
    let siblingTransferId = String(repeating: "b", count: 64)
    store.enqueueBatch([
      LinkDeliveryEnqueueRequest(
        messageId: "failed-chunk",
        topic: "topic/up",
        wirePayload: "failed",
        requiresValidatedNetwork: false,
        blockedByAttachmentTransferIds: [],
        clientSourceMessageId: sourceId,
        contactId: "phone:a",
        attachmentTransferId: failedTransferId
      ),
      LinkDeliveryEnqueueRequest(
        messageId: "sibling-chunk",
        topic: "topic/up",
        wirePayload: "sibling",
        requiresValidatedNetwork: false,
        blockedByAttachmentTransferIds: [],
        clientSourceMessageId: sourceId,
        contactId: "phone:a",
        attachmentTransferId: siblingTransferId
      ),
      LinkDeliveryEnqueueRequest(
        messageId: sourceId,
        topic: "topic/up",
        wirePayload: "parent",
        requiresValidatedNetwork: false,
        blockedByAttachmentTransferIds: [failedTransferId, siblingTransferId],
        clientSourceMessageId: sourceId,
        contactId: "phone:a"
      ),
      LinkDeliveryEnqueueRequest(
        messageId: "unrelated",
        topic: "topic/up",
        wirePayload: "keep",
        requiresValidatedNetwork: false,
        blockedByAttachmentTransferIds: [],
        clientSourceMessageId: "other",
        contactId: "phone:b"
      )
    ], now: now)
    for _ in 0..<9 {
      store.markAttempt(messageId: "failed-chunk", now: now)
    }

    let exhausted = store.discardExhausted(
      maxAttempts: 6,
      attachmentMaxAttempts: 9,
      now: now.addingTimeInterval(60)
    )

    XCTAssertEqual(exhausted.count, 1)
    XCTAssertEqual(exhausted.first?.clientSourceMessageId, sourceId)
    XCTAssertEqual(exhausted.first?.attachmentTransferId, failedTransferId)
    XCTAssertEqual(store.pending(now: now.addingTimeInterval(60)).map(\.messageId), ["unrelated"])
    XCTAssertEqual(store.releaseAttachmentDependency(siblingTransferId, now: now), 0)
  }

  func testMqttClientIdIsStableAndOpaque() {
    let source = "galaxyssi-ios-v11-sensitive-fingerprint"
    let first = GalaxySSIMqttClientId.opaque(from: source)

    XCTAssertEqual(first, GalaxySSIMqttClientId.opaque(from: source))
    XCTAssertNotEqual(first, GalaxySSIMqttClientId.opaque(from: source + "-other"))
    XCTAssertFalse(first.contains("sensitive"))
    XCTAssertEqual(first.count, 36)
  }

  func testOutboxFileBacksLargeWirePayloads() throws {
    let suite = "GalaxySSILinkReliabilityTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let payloadRoot = temporaryOutboxPayloadRoot()
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: payloadRoot.deletingLastPathComponent())
    }
    let store = GalaxySSILinkDeliveryStore(
      defaults: defaults,
      payloadStore: GalaxySSILinkOutboxPayloadStore(rootURL: payloadRoot)
    )
    let now = Date(timeIntervalSince1970: 100)
    let largePayload = String(
      repeating: "x",
      count: GalaxySSILinkOutboxPayloadStore.fileBackedWireThresholdBytes + 1
    )

    store.enqueue(messageId: "large", topic: "topic/up", wirePayload: largePayload, now: now)

    let persisted = try XCTUnwrap(defaults.data(forKey: "galaxyssi-ios-link-delivery-v1"))
    XCTAssertFalse(String(decoding: persisted, as: UTF8.self).contains(largePayload))
    XCTAssertEqual(store.pending(now: now).first?.wirePayload, largePayload)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).count, 1)

    let migration = try XCTUnwrap(store.outboxMigrationSnapshot().first)
    XCTAssertEqual(migration.wirePayload, largePayload)
    XCTAssertNil(migration.wirePayloadFile)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).count, 1)

    store.acknowledge(messageId: "large")

    XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).isEmpty) ?? true)
  }

  func testAttachmentBrokerAckDeadlineExtendsFollowingControlMessage() {
    let watchdog = MqttBrokerAckWatchdog(timeoutSeconds: 30)
    watchdog.onPublished(packetId: 7, now: 1, timeoutSeconds: 60)
    watchdog.onPublished(packetId: 8, now: 1, timeoutSeconds: 30)

    XCTAssertEqual(watchdog.nextCheckDelay(now: 31), 30)
    XCTAssertNil(watchdog.oldestTimedOutPendingAge(now: 31))

    watchdog.onAcknowledged(packetId: 7)

    XCTAssertEqual(watchdog.nextCheckDelay(now: 61), 0)
    XCTAssertEqual(watchdog.oldestTimedOutPendingAge(now: 61), 60)
  }

  func testLargeEncryptedWirePayloadUsesAttachmentAckTimeout() {
    XCTAssertEqual(
      MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 1_024),
      MqttBrokerAckTimeoutPolicy.defaultTimeoutSeconds
    )
    XCTAssertEqual(
      MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 128 * 1_024),
      MqttBrokerAckTimeoutPolicy.attachmentTimeoutSeconds
    )
  }

  func testBrokerAckTimeoutMatchesAndroidSmallPacketBoundary() {
    XCTAssertEqual(MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 65_536), 30)
    XCTAssertEqual(MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 65_537), 120)
    XCTAssertEqual(MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 96 * 1_024), 120)
  }

  func testLargePublicationHasTwoMinuteGraceWithoutExtendingOtherBroker() {
    let largePath = MqttBrokerAckWatchdog(timeoutSeconds: 30)
    let smallPath = MqttBrokerAckWatchdog(timeoutSeconds: 30)
    largePath.onPublished(packetId: 1, now: 1,
      timeoutSeconds: MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 65_537))
    smallPath.onPublished(packetId: 1, now: 1,
      timeoutSeconds: MqttBrokerAckTimeoutPolicy.timeoutSeconds(wirePayloadBytes: 65_536))

    XCTAssertNil(largePath.oldestTimedOutPendingAge(now: 31))
    XCTAssertEqual(smallPath.oldestTimedOutPendingAge(now: 31), 30)
    XCTAssertNil(largePath.oldestTimedOutPendingAge(now: 120))
    XCTAssertEqual(largePath.oldestTimedOutPendingAge(now: 121), 120)
    largePath.onAcknowledged(packetId: 1)
    XCTAssertNil(largePath.nextCheckDelay(now: 122))
    XCTAssertEqual(smallPath.oldestTimedOutPendingAge(now: 122), 121)
  }

  func testPeerSessionRecoveryRequestsAreRateLimitedPerContact() {
    let gate = GalaxySSIPeerSessionRecoveryGate()

    XCTAssertTrue(gate.begin(contactId: "phone:a", nowMillis: 1_000))
    XCTAssertFalse(gate.begin(contactId: "phone:a", nowMillis: 1_001))
    XCTAssertTrue(gate.begin(contactId: "phone:b", nowMillis: 1_001))
    XCTAssertTrue(gate.begin(
      contactId: "phone:a",
      nowMillis: 1_000 + GalaxySSIPeerSessionRecoveryGate.requestCooldownMillis
    ))

    gate.requestFailed(contactId: "phone:a")
    XCTAssertTrue(gate.begin(contactId: "phone:a", nowMillis: 1_002))
    gate.sessionHealthy(contactId: "phone:a")
    XCTAssertTrue(gate.begin(contactId: "phone:a", nowMillis: 1_003))
  }

  func testOnlyExplicitPhoneBundleRefreshReplacesExistingSession() {
    XCTAssertFalse(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.request))
    XCTAssertTrue(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.refresh))
    XCTAssertFalse(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.bundle))
    XCTAssertTrue(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.bundle, sessionRecovery: true))
    XCTAssertFalse(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.receipt, sessionRecovery: true))
    XCTAssertFalse(GalaxySSIPhoneContactBundlePolicy.replacesExistingSession(.approval))
  }

  func testRecoverablePeerEnvelopeIsBoundedAndDirectOnly() throws {
    let payload: [String: Any] = ["type": "peer_message", "content": "hello"]
    let envelope: [String: Any] = ["message_id": "message-1", "payload": payload]
    let encoded = GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: payload,
      applicationEnvelope: envelope,
      isDirectPhoneContact: true
    )

    XCTAssertFalse(encoded.isEmpty)
    XCTAssertEqual(jsonObject(encoded).string("message_id"), "message-1")
    XCTAssertTrue(GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: payload,
      applicationEnvelope: envelope,
      isDirectPhoneContact: false
    ).isEmpty)
    XCTAssertTrue(GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: ["type": "delivery_ack"],
      applicationEnvelope: envelope,
      isDirectPhoneContact: true
    ).isEmpty)
    XCTAssertTrue(GalaxySSILinkDeliveryStore.recoverablePeerEnvelope(
      payload: payload,
      applicationEnvelope: ["content": String(repeating: "x", count: 70 * 1_024)],
      isDirectPhoneContact: true
    ).isEmpty)
  }

  func testPendingPeerMessageIsReencryptedAfterSessionRefresh() {
    let suite = "GalaxySSILinkPeerRecoveryTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = GalaxySSILinkDeliveryStore(
      defaults: defaults,
      secrets: InMemorySecretStore()
    )
    let now = Date(timeIntervalSince1970: 100)
    let envelope = #"{"message_id":"message-1","payload":{"type":"peer_message"}}"#
    store.enqueue(
      messageId: "message-1",
      topic: "old/topic",
      wirePayload: "old-ciphertext",
      contactId: "phone:a",
      recoverableEnvelope: envelope,
      now: now
    )
    store.markAttempt(messageId: "message-1", now: now)

    let recovered = store.reencryptRecoverableMessages(
      contactId: "phone:a",
      topic: "new/topic",
      now: now.addingTimeInterval(1)
    ) { recoveredEnvelope in
      XCTAssertEqual(recoveredEnvelope.string("message_id"), "message-1")
      return "new-ciphertext"
    }

    XCTAssertEqual(recovered, 1)
    let pending = store.pending(now: now.addingTimeInterval(1)).first
    XCTAssertEqual(pending?.topic, "new/topic")
    XCTAssertEqual(pending?.wirePayload, "new-ciphertext")
    XCTAssertEqual(pending?.attempts, 0)

    store.discard(messageId: "message-1")
    XCTAssertEqual(store.reencryptRecoverableMessages(
      contactId: "phone:a",
      topic: "new/topic",
      now: now.addingTimeInterval(2),
      encrypt: { _ in "unused" }
    ), 0)
  }

  func testDiscardingPermanentlyRejectedOutboxEntryPreservesFollowingMessage() throws {
    let suite = "GalaxySSILinkRejectedOutboxTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let payloadRoot = temporaryOutboxPayloadRoot()
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: payloadRoot.deletingLastPathComponent())
    }
    let store = GalaxySSILinkDeliveryStore(
      defaults: defaults,
      payloadStore: GalaxySSILinkOutboxPayloadStore(rootURL: payloadRoot)
    )
    let now = Date(timeIntervalSince1970: 100)
    let rejected = String(
      repeating: "x",
      count: GalaxySSIMqttWireChunking.maximumReassembledBytes + 1
    )
    store.enqueue(messageId: "rejected", topic: "topic/up", wirePayload: rejected, now: now)
    store.enqueue(messageId: "valid", topic: "topic/up", wirePayload: "encrypted-voice", now: now)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).count, 1)

    store.discard(messageId: "rejected")

    XCTAssertEqual(store.pending(now: now).map(\.messageId), ["valid"])
    XCTAssertEqual(store.pending(now: now).first?.wirePayload, "encrypted-voice")
    XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: payloadRoot.path).isEmpty) ?? true)
  }

  func testIncomingStageDedupeAndCompletion() {
    let store = makeDeliveryStore()

    XCTAssertEqual(store.stageIncoming(messageId: "in-1", payload: "{\"content\":\"hi\"}"), .staged)
    XCTAssertEqual(store.stageIncoming(messageId: "in-1", payload: "{\"content\":\"hi\"}"), .pending)

    store.completeIncoming(messageId: "in-1")

    XCTAssertEqual(store.stageIncoming(messageId: "in-1", payload: "{\"content\":\"hi\"}"), .completed)
  }

  func testAckPolicyMatchesAndroidFallbacks() {
    let transportId = UUID().uuidString
    XCTAssertEqual(
      GalaxySSILinkDeliveryAckPolicy.transportMessageId(payload: ["source_message_id": transportId]),
      transportId
    )
    XCTAssertEqual(
      GalaxySSILinkDeliveryAckPolicy.clientSourceMessageId(payload: ["source_message_id": "local-client-id"]),
      "local-client-id"
    )
  }

  func testChunkingRoundTripsLargeWirePayload() throws {
    let body = String(repeating: "x", count: 700 * 1024)
    let wire = #"{"scheme":"galaxyssi-link-ios-preview","from":"ios","to":"desktop","body":""# +
      body +
      #""}"#

    let packets = try GalaxySSIMqttWireChunking.encode(wirePayload: wire)
    XCTAssertGreaterThan(packets.count, 1)
    XCTAssertTrue(packets.allSatisfy {
      $0.utf8.count <= GalaxySSIMqttWireChunking.maximumPacketBytes
    })

    let assembler = GalaxySSIMqttChunkAssembler()
    var assembled: String?
    for packet in packets {
      assembled = try assembler.accept(scope: "topic", wire: jsonObject(packet))
    }

    XCTAssertEqual(assembled, wire)
  }

  func testCurrentAndroidWireLimitKeepsFittingPayloadDirect() throws {
    let wire = String(repeating: "x", count: 500 * 1024)

    XCTAssertEqual(
      try GalaxySSIMqttWireChunking.encode(wirePayload: wire),
      [wire]
    )
  }

  func testEveryLargePayloadChunkFitsOuterPrivacyEnvelope() throws {
    let wire = String(
      repeating: "x",
      count: GalaxySSIMqttWireChunking.maximumReassembledBytes - 256
    )
    let packets = try GalaxySSIMqttWireChunking.encode(wirePayload: wire)
    let linkSecret = try GalaxySSILinkProtocol.newLinkSecret()

    XCTAssertGreaterThan(packets.count, 1)
    for packet in packets {
      XCTAssertNoThrow(
        try GalaxySSILinkProtocol.sealWirePacket(Data(packet.utf8), secret: linkSecret)
      )
    }
  }

  func testOversizedMqttPayloadIsPermanentlyRejectedBeforeRetry() {
    let wire = String(repeating: "x", count: GalaxySSIMqttWireChunking.maximumReassembledBytes + 1)

    XCTAssertEqual(
      GalaxySSIMqttWireChunking.permanentRejectionReason(wirePayload: wire),
      "MQTT wire payload exceeds reassembly limit."
    )
    XCTAssertThrowsError(try GalaxySSIMqttWireChunking.encode(wirePayload: wire))
  }

  func testExcessiveMqttChunkCountIsPermanentlyRejectedBeforeRetry() {
    let wire = String(repeating: "x", count: 2_000)

    XCTAssertEqual(
      GalaxySSIMqttWireChunking.permanentRejectionReason(
        wirePayload: wire,
        directLimitBytes: 1,
        chunkDataBytes: 1
      ),
      "MQTT wire payload requires too many chunks."
    )
  }

  func testChunkAssemblerRejectsConflictingDuplicate() throws {
    let wire = #"{"scheme":"galaxyssi-link-ios-preview","from":"ios","to":"desktop","body":""# +
      String(repeating: "x", count: 80 * 1024) +
      #""}"#
    let packet = try GalaxySSIMqttWireChunking.encode(wirePayload: wire, directLimitBytes: 1024,
                                                      chunkDataBytes: 4096).first!
    let object = jsonObject(packet)
    var conflicting = object
    conflicting["data"] = Data("different".utf8).base64EncodedString()
    conflicting["chunk_sha256"] = GalaxySSIMqttWireChunking.sha256(Data("different".utf8))

    let assembler = GalaxySSIMqttChunkAssembler()
    _ = try assembler.accept(scope: "topic", wire: object)

    XCTAssertThrowsError(try assembler.accept(scope: "topic", wire: conflicting))
  }

  func testCiphertextDigestIsStableAndFieldBounded() {
    let digest = GalaxySSILinkCiphertextReplayPolicy.digest(wire: [
      "scheme": "signal",
      "from": "desktop",
      "to": "ios",
      "body": "encrypted",
      "ignored": UUID().uuidString
    ])
    let sameDigest = GalaxySSILinkCiphertextReplayPolicy.digest(wire: [
      "scheme": "signal",
      "from": "desktop",
      "to": "ios",
      "body": "encrypted",
      "ignored": UUID().uuidString
    ])

    XCTAssertEqual(digest, sameDigest)
    XCTAssertEqual(digest.count, 64)
  }

  func testMqttPublishGuardCapturesPublishBackpressure() throws {
    let success = MqttPublishGuard.attempt { 42 }
    let failure = MqttPublishGuard.attempt { () -> Int in
      throw GalaxySSIError.invalidPayload("max in-flight")
    }

    XCTAssertEqual(try success.get(), 42)
    XCTAssertThrowsError(try failure.get())
  }

  func testMqttOutboxDispatchPolicyKeepsOfflineAndBackpressureAccepted() {
    let offline = MqttOutboxDispatchPolicy.result(connected: false, published: false)
    let backpressure = MqttOutboxDispatchPolicy.result(connected: true, published: false)
    let immediate = MqttOutboxDispatchPolicy.result(connected: true, published: true)

    XCTAssertEqual(offline, .queued)
    XCTAssertEqual(backpressure, .queued)
    XCTAssertEqual(immediate, .published)
    XCTAssertTrue(offline.accepted)
    XCTAssertTrue(backpressure.accepted)
    XCTAssertTrue(immediate.accepted)
    XCTAssertFalse(MqttPublishResult.failed.accepted)
  }

  func testMqttConnectionRetryBacksOffCapsAndResets() {
    let policy = MqttConnectionRetryPolicy(delaysMillis: [2, 5, 10])

    XCTAssertEqual(policy.nextDelayMillis(), 2)
    XCTAssertEqual(policy.nextDelayMillis(), 5)
    XCTAssertEqual(policy.nextDelayMillis(), 10)
    XCTAssertEqual(policy.nextDelayMillis(), 10)
    policy.reset()
    XCTAssertEqual(policy.nextDelayMillis(), 2)
  }

  func testMqttSubscriptionRecoveryWaitsForAllResultsAndIgnoresStaleGenerations() {
    let state = MqttSubscriptionRecoveryState()
    let firstGeneration = state.begin(subscriptionCount: 2)

    XCTAssertEqual(state.complete(generation: firstGeneration, succeeded: true), .pending)
    XCTAssertEqual(state.complete(generation: firstGeneration, succeeded: true), .ready)

    let retryGeneration = state.begin(subscriptionCount: 2)
    XCTAssertEqual(state.complete(generation: retryGeneration, succeeded: false), .pending)
    XCTAssertEqual(state.complete(generation: retryGeneration, succeeded: true), .retry)

    let staleGeneration = state.begin(subscriptionCount: 1)
    state.invalidate()
    XCTAssertEqual(state.complete(generation: staleGeneration, succeeded: true), .stale)
  }

  private func makeDeliveryStore() -> GalaxySSILinkDeliveryStore {
    let suite = "GalaxySSILinkReliabilityTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return GalaxySSILinkDeliveryStore(defaults: defaults)
  }

  private func temporaryOutboxPayloadRoot() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("GalaxySSILinkOutboxPayloadTests-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("galaxyssi-link-outbox-v1", isDirectory: true)
  }

  private func jsonObject(_ text: String) -> [String: Any] {
    let data = Data(text.utf8)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
}
