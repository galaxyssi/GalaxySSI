import Foundation

// Delivery/UI handoff journal, not a broker-PUBACK journal. Pending events never expire or get evicted.
final class MqttDeliveryCompletions {
  struct Limits {
    var records = 100_000
    var peerRecords = 20_000
    var bytes: Int64 = 64 * 1024 * 1024
    var peerBytes: Int64 = 16 * 1024 * 1024
  }
  struct Event: Codable, Equatable {
    let identity: MqttBusinessIdentity
    let messageID: String
    let wireHash: String
    let traffic: String
    let requestHash: String?
    let sourceMessageID: String
    let contactID: String
    let attachmentTransferID: String
    let receivedAt: Int64
    var consumedAt: Int64?
    var retainUntil: Int64 { (consumedAt ?? receivedAt) + MqttBusinessStorage.retention }
    var isPending: Bool { consumedAt == nil }
  }
  private let database: MqttChunkDatabase
  private let limits: Limits
  private static let maximumBytes = 16 * 1024

  init(database: MqttChunkDatabase, limits: Limits = .init()) throws {
    guard limits.records > 0, limits.peerRecords > 0, limits.bytes > 0, limits.peerBytes > 0 else {
      throw MqttChunkStorageError.capacityExceeded
    }
    self.database = database; self.limits = limits
  }

  func event(identity: MqttBusinessIdentity, messageID: String,
             transaction: MqttChunkDatabase.Transaction? = nil) throws -> Event? {
    let key = try identity.key(messageID: messageID)
    return try database.transaction(joining: transaction) { try read(key) }
  }

  func record(_ entry: MqttBusinessOutbox.Entry, at: Int64, transaction: MqttChunkDatabase.Transaction) throws {
    guard entry.isPrepared else { throw MqttRouteError.invalidPayload }
    let key = try entry.identity.key(messageID: entry.message.messageId)
    let event = Event(identity: entry.identity, messageID: entry.message.messageId, wireHash: entry.wireHash,
      traffic: entry.traffic, requestHash: entry.requestHash, sourceMessageID: entry.message.clientSourceMessageId,
      contactID: entry.message.contactId, attachmentTransferID: entry.message.attachmentTransferId,
      receivedAt: try MqttBusinessStorage.timestamp(at), consumedAt: nil)
    try database.transaction(joining: transaction) {
      guard try read(key) == nil else { throw MqttChunkStorageError.corruptState }
      let data = try encode(event)
      for (scope, maximumRecords, maximumBytes) in [("", limits.records, limits.bytes), (entry.identity.binding, limits.peerRecords, limits.peerBytes)] {
        let condition = scope.isEmpty ? "" : " WHERE binding_digest=?"
        let values: [MqttChunkDatabase.Value] = scope.isEmpty ? [] : [.text(scope)]
        let usage = try database.query("SELECT COUNT(*),COALESCE(SUM(payload_bytes),0) FROM mqtt_delivery_completions" + condition,
          values, maximumRows: 1) { (try $0.number(0), try $0.number(1)) }.first
        guard let usage, usage.0 < Int64(maximumRecords), usage.1 >= 0,
              usage.1 <= maximumBytes - Int64(data.count + 32) else { throw MqttChunkStorageError.capacityExceeded }
      }
      try write(event, key: key)
    }
  }

  func pending(afterKey: String = "", limit: Int = 16) throws -> [Event] {
    guard (1...64).contains(limit), afterKey.isEmpty || MqttRouteProtocol.hex(afterKey, count: 64) else { throw MqttRouteError.invalidPayload }
    return try database.transaction {
      let keys = try database.query("SELECT record_key FROM mqtt_delivery_completions WHERE consumed=0 AND record_key>? ORDER BY record_key LIMIT ?",
        [.text(afterKey), .number(Int64(limit))], maximumRows: limit) { try $0.text(0) }
      return try keys.map { key in
        guard let event = try read(key), event.isPending else { throw MqttChunkStorageError.corruptState }
        return event
      }
    }
  }

  // Call only after idempotently applying the event to durable UI/task state and attachment bookkeeping.
  @discardableResult
  func consume(identity: MqttBusinessIdentity, messageID: String, at: Int64) throws -> Bool {
    let key = try identity.key(messageID: messageID)
    let time = try MqttBusinessStorage.timestamp(at)
    return try database.transaction {
      guard var event = try read(key), event.isPending else { return false }
      event.consumedAt = max(time, event.receivedAt)
      try write(event, key: key)
      return true
    }
  }

  @discardableResult
  func pruneConsumed(at: Int64, limit: Int = 256) throws -> Int {
    let time = try MqttBusinessStorage.timestamp(at)
    guard (1...1024).contains(limit) else { throw MqttRouteError.invalidPayload }
    return try database.transaction {
      let keys = try database.query("SELECT record_key FROM mqtt_delivery_completions WHERE consumed=1 AND retain_until<? LIMIT ?",
        [.number(time), .number(Int64(limit))], maximumRows: limit) { try $0.text(0) }
      for key in keys {
        guard let event = try read(key), !event.isPending, event.retainUntil < time else { throw MqttChunkStorageError.corruptState }
        try database.run("DELETE FROM mqtt_delivery_completions WHERE record_key=?", [.text(key)])
      }
      return keys.count
    }
  }

  func forget(identity: MqttBusinessIdentity, transaction: MqttChunkDatabase.Transaction) throws {
    try identity.validate()
    try database.transaction(joining: transaction) {
      try database.run("DELETE FROM mqtt_delivery_completions WHERE binding_digest=?", [.text(identity.binding)])
    }
  }
  func clear(transaction: MqttChunkDatabase.Transaction) throws {
    try database.transaction(joining: transaction) { try database.run("DELETE FROM mqtt_delivery_completions") }
  }

  private func encode(_ event: Event) throws -> Data {
    _ = try event.identity.key(messageID: event.messageID)
    guard MqttRouteProtocol.hex(event.wireHash, count: 64),
          MqttMultipathPolicy.Traffic(rawValue: event.traffic) != nil,
          event.requestHash.map({ MqttRouteProtocol.hex($0, count: 64) }) ?? true,
          event.attachmentTransferID.isEmpty || MqttRouteProtocol.hex(event.attachmentTransferID, count: 64) else { throw MqttChunkStorageError.corruptState }
    _ = try MqttBusinessStorage.timestamp(event.receivedAt)
    if let consumed = event.consumedAt {
      _ = try MqttBusinessStorage.timestamp(consumed)
      guard consumed >= event.receivedAt else { throw MqttChunkStorageError.corruptState }
    }
    let data = try JSONEncoder().encode(event)
    guard data.count <= Self.maximumBytes - 8192 - (event.isPending ? 32 : 0) else { throw MqttChunkStorageError.capacityExceeded }
    return data
  }

  private func read(_ key: String) throws -> Event? {
    try database.query("SELECT binding_digest,consumed,retain_until,payload_bytes,encrypted_metadata FROM mqtt_delivery_completions WHERE record_key=?",
      [.text(key)], maximumRows: 1) { row in
      let data = try database.open(row.data(4, maximum: Self.maximumBytes), purpose: "mqtt-delivery-completion-" + key)
      let event = try JSONDecoder().decode(Event.self, from: data)
      _ = try encode(event)
      guard try event.identity.key(messageID: event.messageID) == key,
            try row.text(0) == event.identity.binding, try row.number(1) == (event.isPending ? 0 : 1),
            try row.number(2) == event.retainUntil,
            try row.number(3) == Int64(data.count + (event.isPending ? 32 : 0)) else { throw MqttChunkStorageError.corruptState }
      return event
    }.first
  }

  private func write(_ event: Event, key: String) throws {
    let data = try encode(event)
    let encrypted = try database.seal(data, purpose: "mqtt-delivery-completion-" + key)
    try database.run("""
      INSERT INTO mqtt_delivery_completions(record_key,binding_digest,consumed,retain_until,payload_bytes,encrypted_metadata)
      VALUES(?,?,?,?,?,?) ON CONFLICT(record_key) DO UPDATE SET consumed=excluded.consumed,
      retain_until=excluded.retain_until,payload_bytes=excluded.payload_bytes,encrypted_metadata=excluded.encrypted_metadata
      """, [.text(key), .text(event.identity.binding), .number(event.isPending ? 0 : 1), .number(event.retainUntil),
             // Reserve the maximum encoded consumedAt field so consumption never requires extra quota.
             .number(Int64(data.count + (event.isPending ? 32 : 0))), .blob(encrypted)])
  }
}
