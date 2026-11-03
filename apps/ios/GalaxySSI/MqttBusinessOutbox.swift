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
    var wireHash: String
    let traffic: String
    var requestHash: String? = nil
    var deferredRequest: MqttSignalSendRequest? = nil
    var isPrepared: Bool { deferredRequest == nil && !wireHash.isEmpty }
  }
  struct DependencyPage { let nextKey: String?; let matched: Int; let released: Int }
  struct Cursor { let nextAttemptAt: Int64; let recordKey: String }
  struct Page { let entries: [Entry]; let next: Cursor? }
  private let database: MqttChunkDatabase
  private let limits: Limits
  let completions: MqttDeliveryCompletions

  convenience init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared, limits: Limits = .init(),
                   completionLimits: MqttDeliveryCompletions.Limits = .init()) throws {
    try self.init(database: MqttChunkDatabase(fileURL: fileURL, secrets: secrets), limits: limits, completionLimits: completionLimits)
  }

  init(database: MqttChunkDatabase, limits: Limits = .init(), completionLimits: MqttDeliveryCompletions.Limits = .init()) throws {
    guard limits.records > 0, limits.peerRecords > 0, limits.bytes > 0, limits.peerBytes > 0,
          limits.controlReserve >= 0, limits.controlReserve < limits.peerRecords,
          limits.controlReserve < limits.records else { throw MqttChunkStorageError.capacityExceeded }
    self.database = database
    self.limits = limits
    completions = try MqttDeliveryCompletions(database: database, limits: completionLimits)
  }

  @discardableResult
  func enqueue(identity: MqttBusinessIdentity, message: PendingLinkMessage, traffic: MqttMultipathPolicy.Traffic,
               requestHash: String? = nil, transaction: MqttChunkDatabase.Transaction? = nil) throws -> Bool {
    let key = try identity.key(messageID: message.messageId)
    let hash = try wireHash(message)
    let entry = Entry(identity: identity, message: message, wireHash: hash, traffic: traffic.rawValue, requestHash: requestHash)
    return try insert(entry, key: key, transaction: transaction)
  }

  @discardableResult
  func enqueueDeferred(_ request: MqttSignalSendRequest, now: Date,
                       transaction: MqttChunkDatabase.Transaction? = nil) throws -> Bool {
    guard !request.attachmentDependencies.isEmpty else { throw MqttRouteError.invalidPayload }
    let key = try request.identity.key(messageID: request.messageID)
    let entry = try Entry(identity: request.identity, message: request.pendingMessage(wire: "", now: now), wireHash: "",
      traffic: request.traffic.rawValue, requestHash: request.digest(), deferredRequest: request)
    return try insert(entry, key: key, transaction: transaction)
  }

  private func insert(_ entry: Entry, key: String, transaction: MqttChunkDatabase.Transaction?) throws -> Bool {
    let encoded = try encode(entry)
    return try database.withTransaction(joining: transaction) { token in
      guard try completions.event(identity: entry.identity, messageID: entry.message.messageId, transaction: token) == nil else {
        throw MqttChunkStorageError.alreadyDelivered
      }
      if let existing = try read(key) {
        guard existing.identity == entry.identity, existing.wireHash == entry.wireHash, existing.traffic == entry.traffic,
              existing.requestHash == entry.requestHash, existing.isPrepared == entry.isPrepared,
              existing.message.topic == entry.message.topic else { throw MqttChunkStorageError.corruptState }
        return false
      }
      try quota(identity: entry.identity, bytes: encoded.count, control: entry.traffic == "control")
      try write(entry, key: key)
      return true
    }
  }

  func entry(identity: MqttBusinessIdentity, messageID: String,
             transaction: MqttChunkDatabase.Transaction? = nil) throws -> Entry? {
    let key = try identity.key(messageID: messageID)
    return try database.transaction(joining: transaction) { try read(key) }
  }

  func prepare(identity: MqttBusinessIdentity, messageID: String, requestHash: String, wire: String, now: Date,
               transaction: MqttChunkDatabase.Transaction) throws -> Entry {
    let key = try identity.key(messageID: messageID)
    return try database.transaction(joining: transaction) {
      guard var saved = try read(key), saved.identity == identity, saved.requestHash == requestHash,
            let request = saved.deferredRequest, saved.message.blockedByAttachmentTransferIds.isEmpty,
            saved.message.attempts == 0, saved.message.status == "queued" else { throw MqttRouteError.invalidPayload }
      guard let envelope = try JSONSerialization.jsonObject(with: Data(wire.utf8)) as? [String: Any],
            envelope["message_id"] as? String == request.messageID,
            envelope["to"] as? String == request.remoteName,
            envelope["from"] as? String == "galaxyssi:\(request.identity.local.prefix(16))",
            envelope["_client_route_id"] as? String == request.clientRouteID,
            envelope[MqttDeliveryEnvelope.field] == nil,
            try MqttRouteProtocol.integer(envelope, "device_id") == Int64(request.deviceID) else { throw MqttRouteError.invalidPayload }
      saved.message.wirePayload = wire
      saved.message.updatedAt = now
      saved.message.nextAttemptAt = now
      saved.wireHash = try wireHash(saved.message)
      saved.deferredRequest = nil
      try write(saved, key: key)
      return saved
    }
  }

  // Only a committed attachment receipt may authorize this operation; callers finish every page.
  func releaseAttachment(identity: MqttBusinessIdentity, transferID: String, afterKey: String = "", limit: Int = 16) throws -> DependencyPage {
    try identity.validate()
    guard MqttRouteProtocol.hex(transferID, count: 64), (1...64).contains(limit),
          afterKey.isEmpty || MqttRouteProtocol.hex(afterKey, count: 64) else { throw MqttRouteError.invalidPayload }
    return try database.transaction {
      let keys = try database.query("SELECT record_key FROM mqtt_business_outbox WHERE binding_digest=? AND record_key>? ORDER BY record_key LIMIT ?",
        [.text(identity.binding), .text(afterKey), .number(Int64(limit))], maximumRows: limit) { try $0.text(0) }
      var matched = 0
      var released = 0
      for key in keys {
        guard var saved = try read(key), saved.identity == identity else { throw MqttChunkStorageError.corruptState }
        if saved.message.blockedByAttachmentTransferIds.contains(transferID) {
          saved.message.blockedByAttachmentTransferIds.removeAll { $0 == transferID }
          try write(saved, key: key)
          matched += 1
          if saved.message.blockedByAttachmentTransferIds.isEmpty { released += 1 }
        }
      }
      return DependencyPage(nextKey: keys.count == limit ? keys.last : nil, matched: matched, released: released)
    }
  }

  // Both the authenticated relationship generation and canonical Signal wire hash must match.
  // No payload cleanup or success notification is legal until this transaction returns.
  @discardableResult
  func acknowledgeVerified(identity: MqttBusinessIdentity, messageID: String, wireHash: String, now: Date = Date(),
                           transaction: MqttChunkDatabase.Transaction? = nil) throws -> Entry? {
    let key = try identity.key(messageID: messageID)
    guard MqttRouteProtocol.hex(wireHash, count: 64) else { throw MqttRouteError.invalidPayload }
    let at = try milliseconds(now)
    return try database.withTransaction(joining: transaction) { token in
      guard let stored = try read(key), stored.identity == identity, stored.isPrepared, stored.wireHash == wireHash else { return nil }
      try completions.record(stored, at: at, transaction: token)
      try database.run("DELETE FROM mqtt_business_outbox WHERE record_key=?", [.text(key)])
      return stored
    }
  }

  func updateRetry(identity: MqttBusinessIdentity, messageID: String, published: Bool, now: Date) throws {
    let key = try identity.key(messageID: messageID)
    _ = try milliseconds(now)
    try database.transaction {
      guard var saved = try read(key), saved.identity == identity else { return }
      guard saved.isPrepared, saved.message.blockedByAttachmentTransferIds.isEmpty else { throw MqttRouteError.invalidPayload }
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
    try pendingPage(identity: identity, now: now, limit: limit).entries
  }

  func pendingPage(identity: MqttBusinessIdentity, now: Date, after: Cursor? = nil, limit: Int = 16) throws -> Page {
    try identity.validate()
    guard (1...64).contains(limit) else { throw MqttRouteError.invalidPayload }
    let at = try milliseconds(now)
    if let after {
      guard after.nextAttemptAt >= 0, after.nextAttemptAt <= MqttRouteProtocol.maximumInteger,
            MqttRouteProtocol.hex(after.recordKey, count: 64) else { throw MqttRouteError.invalidPayload }
    }
    return try database.transaction {
      let start = after?.nextAttemptAt ?? -1
      let keys = try database.query("SELECT record_key FROM mqtt_business_outbox WHERE binding_digest=? AND next_attempt_at<=? AND (next_attempt_at>? OR (next_attempt_at=? AND record_key>?)) ORDER BY next_attempt_at,record_key LIMIT ?",
        [.text(identity.binding), .number(at), .number(start), .number(start), .text(after?.recordKey ?? ""), .number(Int64(limit))],
        maximumRows: limit) { try $0.text(0) }
      var entries: [Entry] = []
      var last: Cursor?
      var bytes = 0
      for key in keys {
        guard let saved = try read(key), saved.identity == identity else { throw MqttChunkStorageError.corruptState }
        let size = saved.message.wirePayload.utf8.count + (saved.deferredRequest?.payload.count ?? 0)
        if !entries.isEmpty && bytes + size > 4 * 1024 * 1024 { break }
        entries.append(saved)
        bytes += size
        last = Cursor(nextAttemptAt: try milliseconds(saved.message.nextAttemptAt), recordKey: key)
      }
      return Page(entries: entries, next: entries.count < keys.count || keys.count == limit ? last : nil)
    }
  }
  func forget(identity: MqttBusinessIdentity) throws {
    try identity.validate()
    try database.withTransaction { token in
      try completions.forget(identity: identity, transaction: token)
      try database.run("DELETE FROM mqtt_business_outbox WHERE binding_digest=?", [.text(identity.binding)])
    }
  }
  func clear() throws {
    try database.withTransaction { token in
      try completions.clear(transaction: token)
      try database.run("DELETE FROM mqtt_business_outbox")
    }
  }

  private func read(_ key: String) throws -> Entry? {
    try database.query("SELECT binding_digest,next_attempt_at,payload_bytes,encrypted_metadata FROM mqtt_business_outbox WHERE record_key=?",
      [.text(key)], maximumRows: 1) { row in
      let encoded = try database.open(row.data(3, maximum: MqttBusinessStorage.maximumRecordBytes), purpose: "mqtt-business-outbox-" + key)
      let entry = try JSONDecoder().decode(Entry.self, from: encoded)
      let binding = try row.text(0)
      let next = try row.number(1)
      let bytes = try row.number(2)
      try validate(entry)
      guard try entry.identity.key(messageID: entry.message.messageId) == key,
            entry.identity.binding == binding, Int64(encoded.count) == bytes,
            try milliseconds(entry.message.nextAttemptAt) == next else { throw MqttChunkStorageError.corruptState }
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
    try validate(entry)
    let data = try JSONEncoder().encode(entry)
    guard data.count <= MqttBusinessStorage.maximumRecordBytes - 8192 else { throw MqttChunkStorageError.capacityExceeded }
    return data
  }
  private func validate(_ entry: Entry) throws {
    _ = try entry.identity.key(messageID: entry.message.messageId)
    guard MqttMultipathPolicy.Traffic(rawValue: entry.traffic) != nil,
          entry.requestHash.map({ MqttRouteProtocol.hex($0, count: 64) }) ?? true else { throw MqttChunkStorageError.corruptState }
    if let request = entry.deferredRequest {
      guard try request.digest() == entry.requestHash, request.identity == entry.identity, request.matches(entry.message),
            request.traffic.rawValue == entry.traffic, !request.attachmentDependencies.isEmpty,
            entry.wireHash.isEmpty, entry.message.wirePayload.isEmpty,
            entry.message.attempts == 0, entry.message.status == "queued" else { throw MqttChunkStorageError.corruptState }
      _ = try milliseconds(entry.message.createdAt)
      _ = try milliseconds(entry.message.updatedAt)
      _ = try milliseconds(entry.message.nextAttemptAt)
    } else {
      guard try wireHash(entry.message) == entry.wireHash else { throw MqttChunkStorageError.corruptState }
    }
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
