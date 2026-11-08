import Foundation

// One local Signal identity per database. The owner must quiesce the legacy engine before migration.
final class MqttSignalStateJournal {
  static let maximumBytes = 32 * 1024 * 1024
  private let database: MqttChunkDatabase
  let inbox: MqttBusinessInbox
  let outbox: MqttBusinessOutbox
  let incomingChunks: MqttDurableChunks
  let outgoingChunks: MqttOutgoingChunks

  static func profileFileURL(profileID: String, root: URL? = nil) -> URL {
    let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
      FileManager.default.temporaryDirectory
    return base.appendingPathComponent("GalaxySSI/MQTT", isDirectory: true)
      .appendingPathComponent(MqttRouteProtocol.digest(Data(profileID.utf8)) + ".sqlite3")
  }

  // An unreadable or partially installed journal must never be treated as an un-migrated profile.
  static func openMigrated(fileURL: URL, expectedFingerprint: String,
                           secrets: GalaxySSISecretStore) throws -> MqttSignalStateJournal? {
    let files = FileManager.default
    guard files.fileExists(atPath: fileURL.path) else {
      if ["-wal", "-shm", "-journal"].contains(where: { files.fileExists(atPath: fileURL.path + $0) }) {
        throw MqttChunkStorageError.corruptState
      }
      return nil
    }
    let journal = try MqttSignalStateJournal(fileURL: fileURL, secrets: secrets)
    guard let marker = try journal.legacyCutover() else {
      guard try journal.load() == nil else { throw MqttChunkStorageError.corruptState }
      return nil
    }
    guard marker.localFingerprint == expectedFingerprint else { throw MqttRouteError.identityChanged }
    return journal
  }

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
       inboxLimits: MqttBusinessInbox.Limits = .init(), outboxLimits: MqttBusinessOutbox.Limits = .init()) throws {
    database = try MqttChunkDatabase(fileURL: fileURL, secrets: secrets)
    inbox = try MqttBusinessInbox(database: database, limits: inboxLimits)
    outbox = try MqttBusinessOutbox(database: database, limits: outboxLimits)
    incomingChunks = try MqttDurableChunks(database: database)
    outgoingChunks = try MqttOutgoingChunks(database: database)
  }

  func load() throws -> Data? { try database.transaction { try read() } }

  struct LegacyOutboxEntry {
    let identity: MqttBusinessIdentity
    let message: PendingLinkMessage
    let traffic: MqttMultipathPolicy.Traffic
  }

  struct LegacyCutover: Codable, Equatable {
    let localFingerprint: String
    let legacyStateDigest: String
    let importedMessages: Int
  }

  func legacyCutover() throws -> LegacyCutover? {
    try database.transaction {
      guard let record = try readCutover() else { return nil }
      guard try read() != nil else { throw MqttChunkStorageError.corruptState }
      return record
    }
  }

  func activateLegacy(localFingerprint: String, signalState: Data, entries: [LegacyOutboxEntry]) throws -> LegacyCutover {
    guard MqttRouteProtocol.hex(localFingerprint, count: 64), !signalState.isEmpty,
          signalState.count <= Self.maximumBytes, entries.count <= 4096,
          entries.allSatisfy({ $0.identity.local == localFingerprint }) else { throw MqttRouteError.invalidPayload }
    let (cutover, _) = try commit(expected: nil) { token in
      guard try readCutover() == nil else { throw MqttChunkStorageError.corruptState }
      let imported = try importLegacyEntries(entries, token: token)
      let cutover = LegacyCutover(localFingerprint: localFingerprint, legacyStateDigest: MqttRouteProtocol.digest(signalState),
        importedMessages: imported)
      let encoded = try database.seal(JSONEncoder().encode(cutover), purpose: "mqtt-legacy-cutover-v1")
      try database.run("INSERT INTO mqtt_legacy_cutover(id,encrypted_record) VALUES(1,?)", [.blob(encoded)])
      return (cutover, signalState)
    }
    return cutover
  }

  private func readCutover() throws -> LegacyCutover? {
    try database.query("SELECT encrypted_record FROM mqtt_legacy_cutover WHERE id=1", maximumRows: 1) {
      let data = try database.open($0.data(0, maximum: 8192), purpose: "mqtt-legacy-cutover-v1")
      let record = try JSONDecoder().decode(LegacyCutover.self, from: data)
      guard MqttRouteProtocol.hex(record.localFingerprint, count: 64),
            MqttRouteProtocol.hex(record.legacyStateDigest, count: 64), (0...4096).contains(record.importedMessages)
      else { throw MqttChunkStorageError.corruptState }
      return record
    }.first
  }

  // The owner quiesces legacy writers and holds all current relationship fences. A failed import
  // leaves the whole source queue intact; no ratchet is advanced or ciphertext regenerated.
  func importLegacyOutbox(_ entries: [LegacyOutboxEntry], expectedSignalState: Data) throws -> Int {
    guard entries.count <= 4096 else { throw MqttChunkStorageError.capacityExceeded }
    let (imported, _) = try commit(expected: expectedSignalState) { token in
      guard try readCutover() == nil else { throw MqttChunkStorageError.corruptState }
      return (try importLegacyEntries(entries, token: token), expectedSignalState)
    }
    return imported
  }

  private func importLegacyEntries(_ entries: [LegacyOutboxEntry], token: MqttChunkDatabase.Transaction) throws -> Int {
    var imported = 0
    var keys = Set<String>()
    for entry in entries {
      let key = try entry.identity.key(messageID: entry.message.messageId)
      guard keys.insert(key).inserted, entry.message.wirePayloadFile == nil else {
        throw MqttChunkStorageError.corruptState
      }
      if let completed = try outbox.completions.event(identity: entry.identity,
        messageID: entry.message.messageId, transaction: token) {
        guard let wire = try JSONSerialization.jsonObject(with: Data(entry.message.wirePayload.utf8)) as? [String: Any],
              completed.wireHash == (try MqttDeliveryEnvelope.contentHash(wire)),
              completed.traffic == entry.traffic.rawValue,
              completed.sourceMessageID == entry.message.clientSourceMessageId,
              completed.contactID == entry.message.contactId,
              completed.attachmentTransferID == entry.message.attachmentTransferId else {
          throw MqttChunkStorageError.corruptState
        }
        continue
      }
      if let existing = try outbox.entry(identity: entry.identity, messageID: entry.message.messageId, transaction: token) {
        guard existing.isPrepared, existing.requestHash == nil, existing.traffic == entry.traffic.rawValue,
              existing.message.topic == entry.message.topic,
              existing.message.wirePayload == entry.message.wirePayload,
              existing.message.clientSourceMessageId == entry.message.clientSourceMessageId,
              existing.message.contactId == entry.message.contactId,
              existing.message.attachmentTransferId == entry.message.attachmentTransferId,
              existing.message.requiresValidatedNetwork == entry.message.requiresValidatedNetwork,
              Set(existing.message.blockedByAttachmentTransferIds)
                .isSubset(of: Set(entry.message.blockedByAttachmentTransferIds)) else {
          throw MqttChunkStorageError.corruptState
        }
        continue
      }
      if try outbox.enqueue(identity: entry.identity, message: entry.message,
        traffic: entry.traffic, transaction: token) { imported += 1 }
    }
    return imported
  }

  // The owner holds the current relationship fence. Read only previously decrypted, durable inbox
  // content; dispatch cancellation and UI/attachment side effects must wait for this COMMIT.
  func consumeStoredReceipt(identity: MqttBusinessIdentity, receiptMessageID: String,
                            now: Date = Date()) throws -> MqttDeliveryCompletions.Event? {
    try database.withTransaction { token in
      guard let pending = try inbox.pending(identity: identity, messageID: receiptMessageID, transaction: token) else { return nil }
      guard let payload = try JSONSerialization.jsonObject(with: pending.payload) as? [String: Any] else {
        throw MqttRouteError.invalidPayload
      }
      guard payload["type"] as? String == "delivery_ack" else { return nil }
      if payload["delivery_status"] as? String == "accepted",
         payload["content_hash"] == nil, payload["content_hash_algorithm"] == nil {
        // Legacy acceptance is not storage proof. Retire only the incoming control message.
        guard try inbox.complete(identity: identity, messageID: receiptMessageID, transaction: token) else {
          throw MqttChunkStorageError.corruptState
        }
        return nil
      }
      let receipt = try MqttDeliveryEnvelope.parseStoredReceipt(payload)
      _ = try outbox.acknowledgeVerified(identity: identity, messageID: receipt.messageID,
        wireHash: receipt.wireHash, now: now, transaction: token)
      guard let event = try outbox.completions.event(identity: identity, messageID: receipt.messageID, transaction: token),
            event.wireHash == receipt.wireHash else { throw MqttRouteError.unsolicitedAcknowledgement }
      guard try inbox.complete(identity: identity, messageID: receiptMessageID, transaction: token) else {
        throw MqttChunkStorageError.corruptState
      }
      return event
    }
  }

  func consumeStoredAttachment(_ item: MqttBusinessInbox.Pending, bodyID: String,
                               transfer: AgentPreparedOutboundAttachment) throws {
    try database.withTransaction { token in
      guard let saved = try inbox.pending(identity: item.identity, messageID: item.messageID, transaction: token),
            saved.key == item.key, saved.payload == item.payload,
            let payload = try JSONSerialization.jsonObject(with: saved.payload) as? [String: Any],
            payload.string("type") == "input_attachment_receipt", transfer.scope.clientMessageId == bodyID,
            transfer.matchesStoredReceipt(payload)
      else { throw MqttRouteError.invalidPayload }
      if try outbox.entry(identity: item.identity, messageID: bodyID, transaction: token)?
        .deferredRequest?.blobAttachmentDependencies?.contains(transfer.transferId) == true {
        guard AgentBlobProtocol.receiptMatches(attachment: transfer, receipt: payload)
        else { throw MqttRouteError.invalidPayload }
      }
      _ = try outbox.releaseAttachment(identity: item.identity, messageID: bodyID,
        transferID: transfer.transferId, transaction: token)
      guard try inbox.complete(identity: item.identity, messageID: item.messageID, transaction: token) else {
        throw MqttChunkStorageError.corruptState
      }
    }
  }

  func consumeFailedBlobAttachment(_ item: MqttBusinessInbox.Pending, bodyID: String,
                                   transfer: AgentPreparedOutboundAttachment) throws {
    try database.withTransaction { token in
      guard let saved = try inbox.pending(identity: item.identity, messageID: item.messageID, transaction: token),
            saved.key == item.key, saved.payload == item.payload,
            var proof = try JSONSerialization.jsonObject(with: saved.payload) as? [String: Any],
            proof.string("type") == "input_attachment_receipt", proof.string("status") == "failed",
            transfer.scope.clientMessageId == bodyID else { throw MqttRouteError.invalidPayload }
      proof["status"] = "stored"
      guard transfer.matchesStoredReceipt(proof), AgentBlobProtocol.receiptMatches(attachment: transfer, receipt: proof)
      else { throw MqttRouteError.invalidPayload }
      try outbox.discardDeferredBlobBody(identity: item.identity, messageID: bodyID,
        transferID: transfer.transferId, transaction: token)
      guard try inbox.complete(identity: item.identity, messageID: item.messageID, transaction: token) else {
        throw MqttChunkStorageError.corruptState
      }
    }
  }

  // Compare the exact last committed snapshot before invoking libsignal. A stale engine must reopen,
  // not overwrite another engine's ratchet. Neither the result nor its receipt escapes before COMMIT.
  func commit<T>(expected: Data?, _ operation: (MqttChunkDatabase.Transaction) throws -> (T, Data)) throws -> (T, Data) {
    try database.withTransaction { transaction in
      guard try read() == expected else { throw MqttChunkStorageError.corruptState }
      let (result, state) = try operation(transaction)
      guard !state.isEmpty, state.count <= Self.maximumBytes else { throw MqttChunkStorageError.capacityExceeded }
      if state != expected {
        let encrypted = try database.seal(state, purpose: "mqtt-signal-state-v1")
        try database.run("INSERT INTO mqtt_signal_state(id,encrypted_state) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET encrypted_state=excluded.encrypted_state",
          [.blob(encrypted)])
      }
      return (result, state)
    }
  }

  private func read() throws -> Data? {
    let saved = try database.query("SELECT encrypted_state FROM mqtt_signal_state WHERE id=1", maximumRows: 1) {
      let state = try database.open($0.data(0, maximum: Self.maximumBytes + 8192), purpose: "mqtt-signal-state-v1")
      guard !state.isEmpty, state.count <= Self.maximumBytes else { throw MqttChunkStorageError.corruptState }
      return state
    }.first
    if saved == nil {
      let businessRecords = try database.query("SELECT (SELECT COUNT(*) FROM mqtt_business_inbox) + (SELECT COUNT(*) FROM mqtt_business_ciphertexts) + (SELECT COUNT(*) FROM mqtt_business_outbox) + (SELECT COUNT(*) FROM mqtt_delivery_completions) + (SELECT COUNT(*) FROM mqtt_legacy_cutover)",
        maximumRows: 1) { try $0.number(0) }.first
      guard businessRecords == 0 else { throw MqttChunkStorageError.corruptState }
    }
    return saved
  }
}
