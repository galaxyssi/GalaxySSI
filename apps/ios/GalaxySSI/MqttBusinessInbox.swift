import Foundation

// A joined result must stay inside the owning transaction until its outer COMMIT succeeds.
final class MqttBusinessInbox {
  struct Limits {
    var records = 100_000
    var peerRecords = 20_000
    var pendingBytes: Int64 = 64 * 1024 * 1024
    var peerPendingBytes: Int64 = 16 * 1024 * 1024
  }
  enum Stage: Equatable { case stored, pending, completed }
  struct Receipt {
    let identity: MqttBusinessIdentity
    let messageID: String
    let wireHash: String
    let recordKey: String
    fileprivate init(identity: MqttBusinessIdentity, messageID: String, wireHash: String, recordKey: String) {
      self.identity = identity; self.messageID = messageID; self.wireHash = wireHash; self.recordKey = recordKey
    }
  }
  struct Accepted { let key: String; let stage: Stage; let receipt: Receipt? }
  struct Pending { let key: String; let identity: MqttBusinessIdentity; let messageID: String; let payload: Data; let createdAt: Int64 }
  private struct Record: Codable {
    var identity: MqttBusinessIdentity
    var messageID: String
    var contentHash: String
    var createdAt: Int64
    var retainUntil: Int64
    var completed: Bool
    var receiptRequired: Bool
    var payload: Data?
    var aliases: [String: String]
  }
  private let database: MqttChunkDatabase
  private let limits: Limits
  private let now: () -> Int64

  convenience init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared, limits: Limits = .init(),
       now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
    try self.init(database: MqttChunkDatabase(fileURL: fileURL, secrets: secrets), limits: limits, now: now)
  }

  init(database: MqttChunkDatabase, limits: Limits = .init(),
       now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
    guard limits.records > 0, limits.peerRecords > 0, limits.pendingBytes > 0, limits.peerPendingBytes > 0 else {
      throw MqttChunkStorageError.capacityExceeded
    }
    self.database = database
    self.limits = limits; self.now = now
  }

  func accept(identity: MqttBusinessIdentity, messageID: String, payload: [String: Any],
              ciphertextDigest: String, wireHash: String, receiptRequired: Bool,
              frame: MqttDeliveryEnvelope.Frame? = nil,
              transaction: MqttChunkDatabase.Transaction? = nil) throws -> Accepted {
    let key = try identity.key(messageID: messageID)
    guard payload["message_id"] as? String == messageID, MqttRouteProtocol.hex(ciphertextDigest, count: 64),
          MqttRouteProtocol.hex(wireHash, count: 64), payload["_link_rx_key"] == nil else { throw MqttRouteError.invalidPayload }
    if let frame {
      guard frame.message.sender == identity.remote, frame.message.receiver == identity.local,
            receiptRequired == (frame.message.traffic != "receipt") else { throw MqttRouteError.identityChanged }
      try frame.validateApplication(messageID: messageID, wireHash: wireHash)
    }
    let body = try MqttBusinessStorage.payload(payload)
    let hash = MqttRouteProtocol.digest(body)
    return try database.transaction(joining: transaction) {
      let at = try MqttBusinessStorage.timestamp(now())
      let existing = try record(key)
      if let existing {
        guard existing.identity == identity, existing.messageID == messageID, existing.contentHash == hash,
              existing.receiptRequired == receiptRequired else { throw MqttChunkStorageError.corruptState }
      } else {
        try quota(binding: identity.binding, bytes: body.count)
      }
      var saved = existing ?? Record(identity: identity, messageID: messageID, contentHash: hash, createdAt: at,
        retainUntil: at + MqttBusinessStorage.retention, completed: false, receiptRequired: receiptRequired, payload: body, aliases: [:])
      if let previous = saved.aliases[ciphertextDigest] {
        guard previous == wireHash else { throw MqttChunkStorageError.corruptState }
      } else {
        guard saved.aliases.count < 8 else { throw MqttChunkStorageError.capacityExceeded }
        saved.aliases[ciphertextDigest] = wireHash
      }
      let bound = try alias(binding: identity.binding, digest: ciphertextDigest)
      guard bound == nil || bound == key else { throw MqttChunkStorageError.corruptState }
      try write(saved, key: key)
      try database.run("INSERT OR IGNORE INTO mqtt_business_ciphertexts(binding_digest,ciphertext_digest,record_key) VALUES(?,?,?)",
        [.text(identity.binding), .text(ciphertextDigest), .text(key)])
      return Accepted(key: key, stage: existing == nil ? .stored : (saved.completed ? .completed : .pending),
        receipt: saved.receiptRequired ? Receipt(identity: identity, messageID: messageID, wireHash: wireHash, recordKey: key) : nil)
    }
  }

  func replay(identity: MqttBusinessIdentity, ciphertextDigest: String,
              transaction: MqttChunkDatabase.Transaction? = nil) throws -> Accepted? {
    try identity.validate()
    guard MqttRouteProtocol.hex(ciphertextDigest, count: 64) else { throw MqttRouteError.invalidPayload }
    return try database.transaction(joining: transaction) {
      guard let key = try alias(binding: identity.binding, digest: ciphertextDigest) else { return nil }
      guard let saved = try record(key), saved.identity == identity, let hash = saved.aliases[ciphertextDigest] else {
        throw MqttChunkStorageError.corruptState
      }
      return Accepted(key: key, stage: saved.completed ? .completed : .pending, receipt: saved.receiptRequired ?
        Receipt(identity: identity, messageID: saved.messageID, wireHash: hash, recordKey: key) : nil)
    }
  }

  func storedReceipt(identity: MqttBusinessIdentity, messageID: String, wireHash: String) throws -> Receipt? {
    let key = try identity.key(messageID: messageID)
    return try database.transaction {
      guard let saved = try record(key), saved.identity == identity, saved.receiptRequired,
            saved.aliases.values.contains(wireHash) else { return nil }
      return Receipt(identity: identity, messageID: messageID, wireHash: wireHash, recordKey: key)
    }
  }

  @discardableResult
  func complete(identity: MqttBusinessIdentity, messageID: String,
                transaction: MqttChunkDatabase.Transaction? = nil) throws -> Bool {
    let key = try identity.key(messageID: messageID)
    return try database.transaction(joining: transaction) {
      guard var saved = try record(key), saved.identity == identity else { return false }
      saved.completed = true
      saved.payload = nil
      try write(saved, key: key)
      return true
    }
  }

  func pending(identity: MqttBusinessIdentity, messageID: String,
               transaction: MqttChunkDatabase.Transaction) throws -> Pending? {
    let key = try identity.key(messageID: messageID)
    return try database.transaction(joining: transaction) {
      guard let saved = try record(key), !saved.completed else { return nil }
      guard saved.identity == identity, let body = saved.payload else { throw MqttChunkStorageError.corruptState }
      return Pending(key: key, identity: saved.identity, messageID: saved.messageID, payload: body, createdAt: saved.createdAt)
    }
  }

  func pending(afterKey: String = "", limit: Int = 16) throws -> [Pending] {
    guard (1...64).contains(limit), afterKey.isEmpty || MqttRouteProtocol.hex(afterKey, count: 64) else { throw MqttRouteError.invalidPayload }
    return try database.transaction {
      let keys = try database.query("SELECT record_key FROM mqtt_business_inbox WHERE completed=0 AND record_key>? ORDER BY record_key LIMIT ?",
        [.text(afterKey), .number(Int64(limit))], maximumRows: limit) { try $0.text(0) }
      var bytes = 0
      var result: [Pending] = []
      for key in keys {
        guard let saved = try record(key), let body = saved.payload else { throw MqttChunkStorageError.corruptState }
        if !result.isEmpty && bytes + body.count > 4 * 1024 * 1024 { break }
        bytes += body.count
        result.append(Pending(key: key, identity: saved.identity, messageID: saved.messageID, payload: body, createdAt: saved.createdAt))
      }
      return result
    }
  }

  @discardableResult
  func pruneCompleted(limit: Int = 256) throws -> Int {
    guard (1...1024).contains(limit) else { throw MqttRouteError.invalidPayload }
    return try database.transaction {
      let at = try MqttBusinessStorage.timestamp(now())
      let keys = try database.query("SELECT record_key FROM mqtt_business_inbox WHERE completed=1 AND retain_until<? LIMIT ?",
        [.number(at), .number(Int64(limit))], maximumRows: limit) { try $0.text(0) }
      for key in keys {
        guard let saved = try record(key), saved.completed, saved.retainUntil < at else { throw MqttChunkStorageError.corruptState }
        try delete(key)
      }
      return keys.count
    }
  }

  func forget(identity: MqttBusinessIdentity) throws {
    try identity.validate()
    try database.transaction {
      try database.run("DELETE FROM mqtt_business_ciphertexts WHERE binding_digest=?", [.text(identity.binding)])
      try database.run("DELETE FROM mqtt_business_inbox WHERE binding_digest=?", [.text(identity.binding)])
    }
  }
  func clear() throws {
    try database.transaction {
      try database.run("DELETE FROM mqtt_business_ciphertexts")
      try database.run("DELETE FROM mqtt_business_inbox")
    }
  }

  private func record(_ key: String) throws -> Record? {
    try database.query("SELECT binding_digest,completed,retain_until,payload_bytes,encrypted_metadata FROM mqtt_business_inbox WHERE record_key=?",
      [.text(key)], maximumRows: 1) { row in
      let data = try database.open(row.data(4, maximum: MqttBusinessStorage.maximumRecordBytes), purpose: "mqtt-business-inbox-" + key)
      let value = try JSONDecoder().decode(Record.self, from: data)
      let binding = try row.text(0)
      let completed = try row.number(1)
      let expiry = try row.number(2)
      let bytes = try row.number(3)
      guard try value.identity.key(messageID: value.messageID) == key, value.identity.binding == binding,
            (value.completed ? 1 : 0) == completed, value.retainUntil == expiry,
            Int64(value.payload?.count ?? 0) == bytes, value.createdAt >= 0,
            value.createdAt <= MqttRouteProtocol.maximumInteger - MqttBusinessStorage.retention,
            value.retainUntil >= value.createdAt, value.retainUntil <= MqttRouteProtocol.maximumInteger,
            value.retainUntil - value.createdAt == MqttBusinessStorage.retention,
            value.completed == (value.payload == nil), MqttRouteProtocol.hex(value.contentHash, count: 64),
            !value.aliases.isEmpty, value.aliases.count <= 8,
            value.aliases.allSatisfy({ MqttRouteProtocol.hex($0.key, count: 64) && MqttRouteProtocol.hex($0.value, count: 64) }) else {
        throw MqttChunkStorageError.corruptState
      }
      if let payload = value.payload {
        guard payload.count <= MqttBusinessStorage.maximumPayloadBytes, MqttRouteProtocol.digest(payload) == value.contentHash,
              let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              object["message_id"] as? String == value.messageID else { throw MqttChunkStorageError.corruptState }
      }
      return value
    }.first
  }
  private func write(_ record: Record, key: String) throws {
    let encoded = try JSONEncoder().encode(record)
    guard encoded.count <= MqttBusinessStorage.maximumRecordBytes - 8192 else { throw MqttChunkStorageError.capacityExceeded }
    let encrypted = try database.seal(encoded, purpose: "mqtt-business-inbox-" + key)
    try database.run("""
      INSERT INTO mqtt_business_inbox(record_key,binding_digest,completed,retain_until,payload_bytes,encrypted_metadata)
      VALUES(?,?,?,?,?,?) ON CONFLICT(record_key) DO UPDATE SET completed=excluded.completed,
      retain_until=excluded.retain_until,payload_bytes=excluded.payload_bytes,encrypted_metadata=excluded.encrypted_metadata
      """, [.text(key), .text(record.identity.binding), .number(record.completed ? 1 : 0), .number(record.retainUntil),
             .number(Int64(record.payload?.count ?? 0)), .blob(encrypted)])
  }
  private func alias(binding: String, digest: String) throws -> String? {
    try database.query("SELECT record_key FROM mqtt_business_ciphertexts WHERE binding_digest=? AND ciphertext_digest=?",
      [.text(binding), .text(digest)], maximumRows: 1) { try $0.text(0) }.first
  }
  private func delete(_ key: String) throws {
    try database.run("DELETE FROM mqtt_business_ciphertexts WHERE record_key=?", [.text(key)])
    try database.run("DELETE FROM mqtt_business_inbox WHERE record_key=?", [.text(key)])
  }
  private func quota(binding: String, bytes: Int) throws {
    for (scope, records, maximum) in [("", limits.records, limits.pendingBytes), (binding, limits.peerRecords, limits.peerPendingBytes)] {
      let condition = scope.isEmpty ? "" : " WHERE binding_digest=?"
      let values: [MqttChunkDatabase.Value] = scope.isEmpty ? [] : [.text(scope)]
      let usage = try database.query("SELECT COUNT(*),COALESCE(SUM(payload_bytes),0) FROM mqtt_business_inbox" + condition,
        values, maximumRows: 1) { (try $0.number(0), try $0.number(1)) }.first
      guard let usage, usage.0 < Int64(records), usage.1 >= 0, usage.1 <= maximum - Int64(bytes) else { throw MqttChunkStorageError.capacityExceeded }
    }
  }
}
