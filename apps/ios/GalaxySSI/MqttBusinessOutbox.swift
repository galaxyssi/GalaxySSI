import Foundation

// Immutable Signal wire bytes and receipt bindings share one committed encrypted record.
final class MqttBusinessOutbox {
  struct Limits {
    var records = 4096
    var bytes: Int64 = 64 * 1024 * 1024
    var peerRecords = 64
    var peerBytes: Int64 = 16 * 1024 * 1024
    var controlReserve = 8
  }
  struct Entry: Codable {
    let identity: MqttBusinessIdentity
    var message: PendingLinkMessage
    let wireHash: String
    let traffic: String
  }
  private let database: MqttChunkDatabase
  private let limits: Limits

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared, limits: Limits = .init()) throws {
    guard limits.records > 0, limits.peerRecords > 0, limits.bytes > 0, limits.peerBytes > 0,
          limits.controlReserve >= 0, limits.controlReserve < limits.peerRecords,
          limits.controlReserve < limits.records else { throw MqttChunkStorageError.capacityExceeded }
    database = try MqttChunkDatabase(fileURL: fileURL, secrets: secrets)
    self.limits = limits
  }

  @discardableResult
  func enqueue(identity: MqttBusinessIdentity, message: PendingLinkMessage, traffic: MqttMultipathPolicy.Traffic) throws -> Bool {
    let key = try identity.key(messageID: message.messageId)
    let hash = try wireHash(message)
    let entry = Entry(identity: identity, message: message, wireHash: hash, traffic: traffic.rawValue)
    let encoded = try encode(entry)
    return try database.transaction {
      if let existing = try read(key) {
        guard existing.identity == identity, existing.wireHash == hash, existing.traffic == entry.traffic,
              existing.message.topic == message.topic else { throw MqttChunkStorageError.corruptState }
        return false
      }
      try quota(identity: identity, bytes: encoded.count, control: traffic == .control)
      try write(entry, key: key)
      return true
    }
  }

  func entry(identity: MqttBusinessIdentity, messageID: String) throws -> Entry? {
    let key = try identity.key(messageID: messageID)
    return try database.transaction { try read(key) }
  }

  // Both the authenticated relationship generation and canonical Signal wire hash must match.
  // No payload cleanup or success notification is legal until this transaction returns.
  @discardableResult
  func acknowledgeVerified(identity: MqttBusinessIdentity, messageID: String, wireHash: String) throws -> Entry? {
    let key = try identity.key(messageID: messageID)
    guard MqttRouteProtocol.hex(wireHash, count: 64) else { throw MqttRouteError.invalidPayload }
    return try database.transaction {
      guard let stored = try read(key), stored.identity == identity, stored.wireHash == wireHash else { return nil }
      try database.run("DELETE FROM mqtt_business_outbox WHERE record_key=?", [.text(key)])
      return stored
    }
  }

  func updateRetry(identity: MqttBusinessIdentity, messageID: String, published: Bool, now: Date) throws {
    let key = try identity.key(messageID: messageID)
    _ = try milliseconds(now)
    try database.transaction {
      guard var saved = try read(key), saved.identity == identity else { return }
      if !published {
        guard saved.message.attempts < Int.max else { throw MqttRouteError.invalidPayload }
        saved.message.attempts += 1
      }
      saved.message.status = published ? "published" : "publishing"
      saved.message.updatedAt = now
      saved.message.nextAttemptAt = now.addingTimeInterval(GalaxySSILinkRetryPolicy.delaySeconds(attempt: max(1, saved.message.attempts)))
      try write(saved, key: key)
    }
  }

  // The coordinator supplies route fairness/attachment/network policy; this is a bounded route scan.
  func pending(identity: MqttBusinessIdentity, now: Date, limit: Int = 16) throws -> [Entry] {
    try identity.validate()
    guard (1...64).contains(limit) else { throw MqttRouteError.invalidPayload }
    let at = try milliseconds(now)
    return try database.transaction {
      let keys = try database.query("SELECT record_key FROM mqtt_business_outbox WHERE binding_digest=? AND next_attempt_at<=? ORDER BY next_attempt_at,record_key LIMIT ?",
        [.text(identity.binding), .number(at), .number(Int64(limit))], maximumRows: limit) { try $0.text(0) }
      return try keys.map { key in
        guard let saved = try read(key), saved.identity == identity else { throw MqttChunkStorageError.corruptState }
        return saved
      }
    }
  }
  func forget(identity: MqttBusinessIdentity) throws {
    try identity.validate()
    try database.transaction { try database.run("DELETE FROM mqtt_business_outbox WHERE binding_digest=?", [.text(identity.binding)]) }
  }
  func clear() throws { try database.transaction { try database.run("DELETE FROM mqtt_business_outbox") } }

  private func read(_ key: String) throws -> Entry? {
    try database.query("SELECT binding_digest,next_attempt_at,payload_bytes,encrypted_metadata FROM mqtt_business_outbox WHERE record_key=?",
      [.text(key)], maximumRows: 1) { row in
      let encoded = try database.open(row.data(3, maximum: MqttBusinessStorage.maximumRecordBytes), purpose: "mqtt-business-outbox-" + key)
      let entry = try JSONDecoder().decode(Entry.self, from: encoded)
      let binding = try row.text(0)
      let next = try row.number(1)
      let bytes = try row.number(2)
      guard try entry.identity.key(messageID: entry.message.messageId) == key,
            entry.identity.binding == binding, Int64(encoded.count) == bytes,
            MqttMultipathPolicy.Traffic(rawValue: entry.traffic) != nil,
            try milliseconds(entry.message.nextAttemptAt) == next,
            try wireHash(entry.message) == entry.wireHash else { throw MqttChunkStorageError.corruptState }
      return entry
    }.first
  }
  private func write(_ entry: Entry, key: String) throws {
    let encoded = try encode(entry)
    let previousBytes = try database.query("SELECT payload_bytes FROM mqtt_business_outbox WHERE record_key=?",
      [.text(key)], maximumRows: 1) { try $0.number(0) }.first ?? 0
    let delta = Int64(encoded.count) - previousBytes
    if delta > 0 {
      for (scope, maximum) in [("", limits.bytes), (entry.identity.binding, limits.peerBytes)] {
        let condition = scope.isEmpty ? "" : " WHERE binding_digest=?"
        let values: [MqttChunkDatabase.Value] = scope.isEmpty ? [] : [.text(scope)]
        let used = try database.query("SELECT COALESCE(SUM(payload_bytes),0) FROM mqtt_business_outbox" + condition,
          values, maximumRows: 1) { try $0.number(0) }.first ?? 0
        guard used >= 0, used <= maximum - delta else { throw MqttChunkStorageError.capacityExceeded }
      }
    }
    let next = try milliseconds(entry.message.nextAttemptAt)
    let encrypted = try database.seal(encoded, purpose: "mqtt-business-outbox-" + key)
    try database.run("""
      INSERT INTO mqtt_business_outbox(record_key,binding_digest,next_attempt_at,payload_bytes,encrypted_metadata)
      VALUES(?,?,?,?,?) ON CONFLICT(record_key) DO UPDATE SET next_attempt_at=excluded.next_attempt_at,
      payload_bytes=excluded.payload_bytes,encrypted_metadata=excluded.encrypted_metadata
      """, [.text(key), .text(entry.identity.binding), .number(next), .number(Int64(encoded.count)), .blob(encrypted)])
  }
  private func encode(_ entry: Entry) throws -> Data {
    let data = try JSONEncoder().encode(entry)
    guard data.count <= MqttBusinessStorage.maximumRecordBytes - 8192 else { throw MqttChunkStorageError.capacityExceeded }
    return data
  }
  private func wireHash(_ message: PendingLinkMessage) throws -> String {
    guard GalaxySSILinkProtocol.validTopic(message.topic), message.attempts >= 0,
          message.wirePayload.utf8.count <= MqttBusinessStorage.maximumPayloadBytes,
          let wire = try JSONSerialization.jsonObject(with: Data(message.wirePayload.utf8)) as? [String: Any] else { throw MqttRouteError.invalidPayload }
    _ = try milliseconds(message.createdAt)
    _ = try milliseconds(message.updatedAt)
    _ = try milliseconds(message.nextAttemptAt)
    return try MqttDeliveryEnvelope.contentHash(wire)
  }
  private func milliseconds(_ date: Date) throws -> Int64 {
    let value = date.timeIntervalSince1970 * 1000
    guard value.isFinite, value >= 0, value <= Double(MqttRouteProtocol.maximumInteger - MqttBusinessStorage.retention) else {
      throw MqttRouteError.invalidPayload
    }
    return Int64(value)
  }
  private func quota(identity: MqttBusinessIdentity, bytes: Int, control: Bool) throws {
    for (scope, records, maximum) in [("", limits.records, limits.bytes), (identity.binding, limits.peerRecords, limits.peerBytes)] {
      let condition = scope.isEmpty ? "" : " WHERE binding_digest=?"
      let values: [MqttChunkDatabase.Value] = scope.isEmpty ? [] : [.text(scope)]
      let usage = try database.query("SELECT COUNT(*),COALESCE(SUM(payload_bytes),0) FROM mqtt_business_outbox" + condition,
        values, maximumRows: 1) { (try $0.number(0), try $0.number(1)) }.first
      let reserve = control ? 0 : limits.controlReserve
      guard let usage, usage.0 < Int64(records - reserve), usage.1 >= 0, usage.1 <= maximum - Int64(bytes) else {
        throw MqttChunkStorageError.capacityExceeded
      }
    }
  }
}
