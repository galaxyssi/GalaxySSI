import XCTest
@testable import GalaxySSI

final class MqttSignalStateJournalTests: XCTestCase {
  private let snapshot = Data("test-ratchet-state".utf8)
  private let next = Data("advanced-test-ratchet-state".utf8)

  func testCheckpointAndInboxCommitTogetherAndReopen() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    let (accepted, saved) = try journal.commit(expected: nil) { token in
      (try accept(journal, token: token), snapshot)
    }
    XCTAssertNotNil(accepted.receipt)
    XCTAssertEqual(saved, snapshot)
    let reopened = try makeJournal(f)
    XCTAssertEqual(try reopened.load(), snapshot)
    XCTAssertEqual(try reopened.inbox.pending().count, 1)
  }

  func testCheckpointFailureRollsBackAlreadyStagedInboxAndAlias() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    try f.execute("CREATE TRIGGER fail_state BEFORE INSERT ON mqtt_signal_state BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try journal.commit(expected: nil) { token in
      (try self.accept(journal, token: token), self.snapshot)
    })
    XCTAssertNil(try journal.load())
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
    XCTAssertEqual(try f.scalar("SELECT COUNT(*) FROM mqtt_business_ciphertexts"), 0)
  }

  func testInboxFailureKeepsPreviousCheckpointAndRetrySucceeds() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    _ = try journal.commit(expected: nil) { _ in ((), snapshot) }
    try f.execute("CREATE TRIGGER fail_alias BEFORE INSERT ON mqtt_business_ciphertexts BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try journal.commit(expected: snapshot) { token in
      (try self.accept(journal, token: token), self.next)
    })
    XCTAssertEqual(try journal.load(), snapshot)
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
    try f.execute("DROP TRIGGER fail_alias")
    let (accepted, _) = try journal.commit(expected: snapshot) { token in (try accept(journal, token: token), next) }
    XCTAssertNotNil(accepted.receipt)
    XCTAssertEqual(try journal.load(), next)
  }

  func testStaleInstanceCannotInvokeDecryptOrOverwriteSnapshot() throws {
    let f = try ChunkFixture()
    let first = try makeJournal(f)
    let second = try makeJournal(f)
    _ = try first.commit(expected: nil) { _ in ((), snapshot) }
    var called = false
    XCTAssertThrowsError(try second.commit(expected: nil) { _ in called = true; return ((), self.next) })
    XCTAssertFalse(called)
    XCTAssertEqual(try second.load(), snapshot)
  }

  func testExpiredTransactionCannotWriteAfterCommit() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    var escaped: MqttChunkDatabase.Transaction?
    _ = try journal.commit(expected: nil) { token in escaped = token; return ((), snapshot) }
    XCTAssertThrowsError(try accept(journal, token: XCTUnwrap(escaped)))
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
  }

  func testTransactionFromAnotherConnectionCannotWriteInbox() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    let separateInbox = try MqttBusinessInbox(fileURL: f.url, secrets: f.secrets)
    XCTAssertThrowsError(try journal.commit(expected: nil) { token in
      let accepted = try separateInbox.accept(identity: self.identity(), messageID: "message",
        payload: ["message_id": "message"], ciphertextDigest: String(repeating: "c", count: 64),
        wireHash: String(repeating: "d", count: 64), receiptRequired: true, transaction: token)
      return (accepted, self.snapshot)
    })
    XCTAssertNil(try journal.load())
  }

  func testCaughtJoinedFailureStillPreventsOuterCommit() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    try f.execute("CREATE TRIGGER fail_alias BEFORE INSERT ON mqtt_business_ciphertexts BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try journal.commit(expected: nil) { token in
      _ = try? self.accept(journal, token: token)
      return ((), self.snapshot)
    })
    XCTAssertNil(try journal.load())
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
  }

  func testBodyFailureAfterInboxWriteRollsBackBoth() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    XCTAssertThrowsError(try journal.commit(expected: nil) { token -> ((), Data) in
      _ = try self.accept(journal, token: token)
      throw MqttChunkStorageError.databaseFailure
    })
    XCTAssertNil(try journal.load())
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
  }

  func testMissingKeyMarkerAndCorruptStateFailClosed() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    _ = try journal.commit(expected: nil) { _ in ((), snapshot) }
    let sealed = try f.blob("SELECT encrypted_state FROM mqtt_signal_state")
    XCTAssertNil(sealed.range(of: snapshot))
    try f.execute("UPDATE mqtt_signal_state SET encrypted_state=zeroblob(12)")
    XCTAssertThrowsError(try journal.load())
    try f.execute("DELETE FROM mqtt_chunk_key")
    XCTAssertThrowsError(try makeJournal(f))
  }

  func testEmptySnapshotCannotCommitInbox() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    XCTAssertThrowsError(try journal.commit(expected: nil) { token in (try self.accept(journal, token: token), Data()) })
    XCTAssertNil(try journal.load())
    XCTAssertTrue(try journal.inbox.pending().isEmpty)
  }

  func testMissingRatchetWithRetainedInboxCannotInitializeNewIdentity() throws {
    let f = try ChunkFixture()
    let journal = try makeJournal(f)
    _ = try journal.commit(expected: nil) { token in (try accept(journal, token: token), snapshot) }
    try f.execute("DELETE FROM mqtt_signal_state")
    XCTAssertThrowsError(try journal.load())
    XCTAssertThrowsError(try journal.commit(expected: nil) { _ in ((), self.next) })
    XCTAssertEqual(try journal.inbox.pending().count, 1)
  }

  private func makeJournal(_ f: ChunkFixture) throws -> MqttSignalStateJournal {
    try MqttSignalStateJournal(fileURL: f.url, secrets: f.secrets)
  }
  private func identity() throws -> MqttBusinessIdentity { try signalTestIdentity() }
  private func accept(_ journal: MqttSignalStateJournal, token: MqttChunkDatabase.Transaction) throws -> MqttBusinessInbox.Accepted {
    try journal.inbox.accept(identity: identity(), messageID: "message", payload: ["message_id": "message", "text": "stored"],
      ciphertextDigest: String(repeating: "c", count: 64), wireHash: String(repeating: "d", count: 64),
      receiptRequired: true, transaction: token)
  }
}

private func signalTestIdentity(local: String = String(repeating: "a", count: 64),
                                remote: String = String(repeating: "b", count: 64)) throws -> MqttBusinessIdentity {
  let topic = String(repeating: "A", count: 43)
  return try MqttBusinessIdentity(MqttPeerBinding(scope: "signal-test", sender: local, receiver: remote,
    secret: Data(repeating: 7, count: 32).base64URLEncodedString(), sendTopic: topic,
    sendTopics: [topic], receiveTopics: [topic]))
}

#if canImport(LibSignalClient)
final class MqttSignalAtomicReceiveTests: XCTestCase {
  func testSignalReceiveAndDuplicateSurviveEngineReopen() throws {
    let f = try SignalReceiveFixture()
    let wire = try f.wire()
    XCTAssertEqual(try f.receive(wire).stage, .stored)
    try f.reopen()
    let saved = try f.journal.load()
    XCTAssertEqual(try f.receive(wire).stage, .pending)
    XCTAssertEqual(try f.journal.load(), saved)
    XCTAssertEqual(try f.journal.inbox.pending().count, 1)
  }

  func testSQLFailureRestoresRatchetAndPreKeyForSameCiphertextRetry() throws {
    let f = try SignalReceiveFixture()
    let wire = try f.wire()
    let saved = try f.journal.load()
    try f.storage.execute("CREATE TRIGGER fail_alias BEFORE INSERT ON mqtt_business_ciphertexts BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.receive(wire))
    XCTAssertEqual(try f.journal.load(), saved)
    XCTAssertFalse(f.bob.hasSession(remoteName: f.alice.identity.name))
    try f.storage.execute("DROP TRIGGER fail_alias")
    XCTAssertNotNil(try f.receive(wire).receipt)
    XCTAssertTrue(f.bob.hasSession(remoteName: f.alice.identity.name))
  }

  func testSignalCheckpointWriteFailureDoesNotExposeInboxReceipt() throws {
    let f = try SignalReceiveFixture()
    let wire = try f.wire()
    let saved = try f.journal.load()
    try f.storage.execute("CREATE TRIGGER fail_state BEFORE UPDATE ON mqtt_signal_state BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.receive(wire))
    XCTAssertEqual(try f.journal.load(), saved)
    XCTAssertTrue(try f.journal.inbox.pending().isEmpty)
    try f.storage.execute("DROP TRIGGER fail_state")
    XCTAssertEqual(try f.receive(wire).stage, .stored)
  }

  func testWrongRemoteFingerprintRollsBackFirstContactAndAllowsCorrectRetry() throws {
    let f = try SignalReceiveFixture()
    let wire = try f.wire()
    let wrong = try signalTestIdentity(local: f.bob.identity.fingerprint)
    XCTAssertThrowsError(try f.bob.decryptAndStore(wire, identity: wrong,
      remoteName: f.alice.identity.name, ingressBroker: "emqx"))
    XCTAssertFalse(f.bob.hasSession(remoteName: f.alice.identity.name))
    XCTAssertNotNil(try f.receive(wire).receipt)
  }

  func testDurableEngineCannotBypassInboxWithLegacyDecrypt() throws {
    let f = try SignalReceiveFixture()
    let wire = try f.wire()
    XCTAssertNil(f.bob.decrypt(wire))
    XCTAssertEqual(try f.receive(wire).stage, .stored)
  }

  func testEstablishedRatchetAlsoRollsBackAndRetries() throws {
    let f = try SignalReceiveFixture()
    _ = try f.receive(f.wire())
    let reply = try XCTUnwrap(f.bob.encrypt(["message_id": "reply"], remoteName: f.aliceIdentity.name))
    XCTAssertNotNil(f.alice.decrypt(reply))
    let wire = try f.wire(messageID: "second")
    XCTAssertEqual(wire["signal_type"] as? String, "signal")
    let saved = try f.journal.load()
    try f.storage.execute("CREATE TRIGGER fail_alias BEFORE INSERT ON mqtt_business_ciphertexts BEGIN SELECT RAISE(ABORT,'forced'); END")
    XCTAssertThrowsError(try f.receive(wire))
    XCTAssertEqual(try f.journal.load(), saved)
    try f.storage.execute("DROP TRIGGER fail_alias")
    XCTAssertEqual(try f.receive(wire).stage, .stored)
    XCTAssertEqual(try f.journal.inbox.pending().count, 2)
  }

  func testWrongApplicationIDInFrameCannotConsumeCiphertext() throws {
    let f = try SignalReceiveFixture()
    let wire = try f.wire()
    let frame = try MqttDeliveryEnvelope.Frame(message: .init(messageID: "wrong-id",
      contentHash: MqttDeliveryEnvelope.contentHash(wire), sender: f.aliceIdentity.fingerprint,
      receiver: f.bobIdentity.fingerprint, traffic: "message"),
      attempt: .init(attemptID: String(repeating: "a", count: 32), brokerID: "emqx", generation: 1))
    XCTAssertThrowsError(try f.receive(frame.attach(to: wire)))
    XCTAssertTrue(try f.journal.inbox.pending().isEmpty)
    XCTAssertEqual(try f.receive(wire).stage, .stored)
    XCTAssertThrowsError(try f.receive(frame.attach(to: wire)))
  }

  func testEncryptedReceiptDoesNotGenerateAnotherReceipt() throws {
    let f = try SignalReceiveFixture()
    let wire = try XCTUnwrap(f.alice.encrypt(["message_id": "receipt", "type": "delivery_ack"], remoteName: f.bobIdentity.name))
    XCTAssertNil(try f.receive(wire).receipt)
    XCTAssertNil(try f.receive(wire).receipt)
    XCTAssertEqual(try f.journal.inbox.pending().count, 1)
  }

  func testInvalidDeviceIDFailsWithoutChangingRatchet() throws {
    let f = try SignalReceiveFixture()
    let original = try f.wire()
    let saved = try f.journal.load()
    for bad in [Int64(-1), 0, Int64(UInt32.max) + 1] {
      var wire = original
      wire["device_id"] = bad
      XCTAssertThrowsError(try f.receive(wire))
      XCTAssertEqual(try f.journal.load(), saved)
    }
    XCTAssertEqual(try f.receive(original).stage, .stored)
  }

  func testLegacyMigrationPreservesIdentityAndLeavesLegacySnapshotUntouched() throws {
    let f = try SignalReceiveFixture()
    let legacy = GalaxySSISignalEngine(profileName: "migration", defaults: f.bobDefaults, secrets: f.storage.secrets)
    let fingerprint = legacy.identity.fingerprint
    let bytes = f.bobDefaults.data(forKey: "galaxyssi-ios-libsignal-state-v1")
    let url = f.storage.root.appendingPathComponent("migration.sqlite")
    let journal = try MqttSignalStateJournal(fileURL: url, secrets: f.storage.secrets)
    let migrated = try GalaxySSISignalEngine(profileName: "migration", journal: journal,
      defaults: f.bobDefaults, secrets: f.storage.secrets)
    XCTAssertEqual(migrated.identity.fingerprint, fingerprint)
    XCTAssertEqual(f.bobDefaults.data(forKey: "galaxyssi-ios-libsignal-state-v1"), bytes)
    XCTAssertNotNil(try journal.load())
  }

  func testCorruptLegacyStateIsNotReplacedWithNewIdentity() throws {
    let f = try SignalReceiveFixture()
    f.bobDefaults.set(Data("corrupt".utf8), forKey: "galaxyssi-ios-libsignal-state-v1")
    let journal = try MqttSignalStateJournal(fileURL: f.storage.root.appendingPathComponent("bad-migration.sqlite"), secrets: f.storage.secrets)
    XCTAssertThrowsError(try GalaxySSISignalEngine(profileName: "bad", journal: journal,
      defaults: f.bobDefaults, secrets: f.storage.secrets))
    XCTAssertNil(try journal.load())
  }
}

private final class SignalReceiveFixture {
  let storage: ChunkFixture
  let aliceSuite = "signal-alice-" + UUID().uuidString
  let bobSuite = "signal-bob-" + UUID().uuidString
  let aliceDefaults: UserDefaults
  let bobDefaults: UserDefaults
  let alice: GalaxySSISignalEngine
  var bob: GalaxySSISignalEngine
  let journal: MqttSignalStateJournal
  let aliceIdentity: GalaxySSISignalIdentity
  let bobIdentity: GalaxySSISignalIdentity

  init() throws {
    storage = try ChunkFixture()
    aliceDefaults = try XCTUnwrap(UserDefaults(suiteName: aliceSuite))
    bobDefaults = try XCTUnwrap(UserDefaults(suiteName: bobSuite))
    alice = GalaxySSISignalEngine(profileName: "alice", defaults: aliceDefaults, secrets: InMemorySecretStore())
    journal = try MqttSignalStateJournal(fileURL: storage.url, secrets: storage.secrets)
    bob = try GalaxySSISignalEngine(profileName: "bob", journal: journal, defaults: bobDefaults, secrets: storage.secrets)
    aliceIdentity = alice.identity
    bobIdentity = bob.identity
    XCTAssertTrue(alice.processBundle(try XCTUnwrap(bob.localBundle())))
  }

  deinit {
    aliceDefaults.removePersistentDomain(forName: aliceSuite)
    bobDefaults.removePersistentDomain(forName: bobSuite)
  }
  func reopen() throws {
    bob = try GalaxySSISignalEngine(profileName: "bob", journal: journal, defaults: bobDefaults, secrets: storage.secrets)
  }
  func wire(messageID: String = "message") throws -> [String: Any] {
    try XCTUnwrap(alice.encrypt(["message_id": messageID, "type": "message", "text": "hello"], remoteName: bobIdentity.name))
  }
  func receive(_ wire: [String: Any]) throws -> MqttBusinessInbox.Accepted {
    try bob.decryptAndStore(wire, identity: signalTestIdentity(local: bobIdentity.fingerprint, remote: aliceIdentity.fingerprint),
      remoteName: aliceIdentity.name, ingressBroker: "emqx")
  }
}
#endif
