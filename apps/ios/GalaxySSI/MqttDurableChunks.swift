import Foundation

// Scope must come from the authenticated relationship (including its key generation),
// never a sender-supplied field. No method here claims business delivery completion.
final class MqttDurableChunks {
  static let retentionMillis: Int64 = 8 * 24 * 60 * 60 * 1000

  struct Limits {
    var transfers = 16
    var bytes: Int64 = 32 * 1024 * 1024
    var peerTransfers = 8
    var peerBytes: Int64 = 16 * 1024 * 1024
  }

  struct Snapshot {
    let state: [String: Any]
    let proof: (messageID: String, wireHash: String)?
  }

  private struct Metadata: Codable {
    var scope: String
    var transfer: String
    var manifestHash: String
    var count: Int
    var total: Int
    var storedBytes: Int
    var source: String
    var target: String
    var epoch: String
    var revision: Int64
    var expiresAt: Int64
    var wireHash = ""
    var messageID = ""
  }

  private struct Part {
    let index: Int
    let digest: String
    let encrypted: Data
  }

  private let database: MqttChunkDatabase
  private let limits: Limits
  private let now: () -> Int64

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared, limits: Limits = Limits(),
       now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
    guard limits.transfers > 0, limits.peerTransfers > 0, limits.bytes > 0, limits.peerBytes > 0 else {
      throw MqttChunkStorageError.capacityExceeded
    }
    self.database = try MqttChunkDatabase(fileURL: fileURL, secrets: secrets)
    self.limits = limits
    self.now = now
  }

  func accept(authenticatedScope: String, wire: [String: Any]) throws -> String? {
    let chunk = try MqttChunkManifest.parse(wire)
    _ = try MqttChunkReceipts.fromChunk(wire)
    let scope = try scopeKey(authenticatedScope)
    return try database.transaction {
      let at = try timestamp()
      try prune(at: at)
      var saved = try metadata(scope: scope, transfer: chunk.transfer)
      if let expired = saved, expired.expiresAt <= at {
        try delete(scope: scope, transfer: chunk.transfer)
        saved = nil
      }
      if saved == nil {
        try quota(scope: scope, total: chunk.total)
        saved = Metadata(scope: scope, transfer: chunk.transfer, manifestHash: chunk.manifestHash, count: chunk.count,
          total: chunk.total, storedBytes: 0, source: chunk.source, target: chunk.target,
          epoch: MqttChunkReceipts.newRequest(), revision: 0, expiresAt: at + Self.retentionMillis)
      }
      guard var record = saved, record.manifestHash == chunk.manifestHash else { throw MqttChunkStorageError.corruptState }
      if !record.messageID.isEmpty { return nil }
      let old = try parts(scope: scope, transfer: chunk.transfer).first { $0.index == chunk.index }
      if let old {
        guard old.digest == chunk.digest else { throw MqttChunkStorageError.corruptState }
        if let data = try? open(old, record: record) {
          guard data == chunk.data else { throw MqttChunkStorageError.corruptState }
        } else {
          try writePart(chunk, scope: scope)
          try advanceRevision(&record)
        }
      } else {
        guard record.storedBytes + chunk.data.count <= record.total else { throw MqttChunkStorageError.corruptState }
        try writePart(chunk, scope: scope)
        record.storedBytes += chunk.data.count
        try advanceRevision(&record)
      }
      let assembled = try assemble(&record)
      try save(record)
      return assembled
    }
  }

  func snapshot(authenticatedScope: String, query: MqttChunkReceipts.Query) throws -> Snapshot {
    let scope = try scopeKey(authenticatedScope)
    return try database.transaction {
      guard var record = try metadata(scope: scope, transfer: query.transfer), record.expiresAt > (try timestamp()) else {
        return Snapshot(state: try query.response(epoch: String(repeating: "0", count: 32), revision: 0, indices: []), proof: nil)
      }
      guard record.manifestHash == query.manifest, record.count == query.count else { throw MqttChunkStorageError.corruptState }
      if !record.messageID.isEmpty {
        return Snapshot(state: try query.response(epoch: record.epoch, revision: record.revision, indices: Set(0..<record.count)),
                        proof: (record.messageID, record.wireHash))
      }
      var valid = Set<Int>()
      var storedBytes = 0
      var corrupt: [Int] = []
      for part in try parts(scope: scope, transfer: query.transfer) {
        if let data = try? open(part, record: record) {
          valid.insert(part.index)
          storedBytes += data.count
        } else { corrupt.append(part.index) }
      }
      guard storedBytes <= record.total else { throw MqttChunkStorageError.corruptState }
      if !corrupt.isEmpty {
        for index in corrupt {
          try database.run("DELETE FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? AND chunk_index=?",
            [.text(scope), .text(record.transfer), .number(Int64(index))])
        }
        record.storedBytes = storedBytes
        record.wireHash = ""
        try advanceRevision(&record)
        try save(record)
      } else if record.storedBytes != storedBytes { throw MqttChunkStorageError.corruptState }
      return Snapshot(state: try query.response(epoch: record.epoch, revision: record.revision, indices: valid), proof: nil)
    }
  }

  func recoverComplete(authenticatedScope: String, query: MqttChunkReceipts.Query) throws -> String? {
    let scope = try scopeKey(authenticatedScope)
    return try database.transaction {
      guard var record = try metadata(scope: scope, transfer: query.transfer), record.expiresAt > (try timestamp()),
            record.messageID.isEmpty, record.manifestHash == query.manifest, record.count == query.count else { return nil }
      let wire = try assemble(&record)
      if wire != nil { try save(record) }
      return wire
    }
  }

  // Supply the hash/ID read from a committed inbox record. Failed commits must not call this.
  @discardableResult
  func releaseAfterStore(authenticatedScope: String, transfer: String, storedWireHash: String, messageID: String = "") throws -> Bool {
    let scope = try scopeKey(authenticatedScope)
    _ = try MqttChunkManifest.checkedHash(transfer)
    _ = try MqttChunkManifest.checkedHash(storedWireHash)
    if !messageID.isEmpty { _ = try MqttDeliveryEnvelope.checkedText(messageID, maximum: 512) }
    return try database.transaction {
      guard var record = try metadata(scope: scope, transfer: transfer), record.expiresAt > (try timestamp()),
            record.wireHash == storedWireHash else { return false }
      if !record.messageID.isEmpty { return record.messageID == messageID }
      if messageID.isEmpty { try delete(scope: scope, transfer: transfer) }
      else {
        record.messageID = messageID
        record.storedBytes = 0
        try advanceRevision(&record)
        try database.run("DELETE FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=?", [.text(scope), .text(transfer)])
        try save(record)
      }
      return true
    }
  }

  func forget(authenticatedScope: String) throws {
    let scope = try scopeKey(authenticatedScope)
    try database.transaction {
      try database.run("DELETE FROM mqtt_wire_parts WHERE scope_digest=?", [.text(scope)])
      try database.run("DELETE FROM mqtt_wire_transfers WHERE scope_digest=?", [.text(scope)])
    }
  }

  func clear() throws {
    try database.transaction {
      try database.run("DELETE FROM mqtt_wire_parts")
      try database.run("DELETE FROM mqtt_wire_transfers")
    }
  }

  private func metadata(scope: String, transfer: String) throws -> Metadata? {
    try database.query("SELECT total_bytes,expires_at,completed,encrypted_metadata FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?",
      [.text(scope), .text(transfer)], maximumRows: 1) { row in
        let bytes = try database.open(row.data(3, maximum: 16 * 1024), purpose: purpose(scope, transfer, "manifest"))
        let record = try JSONDecoder().decode(Metadata.self, from: bytes)
        let indexedTotal = try row.number(0)
        let indexedExpiry = try row.number(1)
        let indexedCompleted = try row.number(2)
        guard record.scope == scope, record.transfer == transfer, MqttRouteProtocol.hex(record.manifestHash, count: 64),
              (1...MqttChunkManifest.maximumCount).contains(record.count),
              (record.count...MqttChunkManifest.maximumBytes).contains(record.total),
              (0...record.total).contains(record.storedBytes), MqttRouteProtocol.hex(record.epoch, count: 32),
              record.epoch != String(repeating: "0", count: 32),
              (0...MqttRouteProtocol.maximumInteger).contains(record.revision),
              (0...MqttRouteProtocol.maximumInteger).contains(record.expiresAt),
              record.wireHash.isEmpty || MqttRouteProtocol.hex(record.wireHash, count: 64),
              record.messageID.isEmpty || (!record.wireHash.isEmpty && record.storedBytes == 0),
              indexedTotal == Int64(record.total), indexedExpiry == record.expiresAt,
              indexedCompleted == (record.messageID.isEmpty ? 0 : 1) else { throw MqttChunkStorageError.corruptState }
        _ = try MqttDeliveryEnvelope.checkedText(record.source, maximum: 512)
        _ = try MqttDeliveryEnvelope.checkedText(record.target, maximum: 512)
        if !record.messageID.isEmpty { _ = try MqttDeliveryEnvelope.checkedText(record.messageID, maximum: 512) }
        return record
      }.first
  }

  private func save(_ record: Metadata) throws {
    let encrypted = try database.seal(JSONEncoder().encode(record), purpose: purpose(record.scope, record.transfer, "manifest"))
    try database.run("""
      INSERT INTO mqtt_wire_transfers(scope_digest,transfer_id,total_bytes,expires_at,completed,encrypted_metadata) VALUES(?,?,?,?,?,?)
      ON CONFLICT(scope_digest,transfer_id) DO UPDATE SET total_bytes=excluded.total_bytes,expires_at=excluded.expires_at,
        completed=excluded.completed,encrypted_metadata=excluded.encrypted_metadata
      """, [.text(record.scope), .text(record.transfer), .number(Int64(record.total)), .number(record.expiresAt),
             .number(record.messageID.isEmpty ? 0 : 1), .blob(encrypted)])
  }

  private func parts(scope: String, transfer: String) throws -> [Part] {
    try database.query("SELECT chunk_index,chunk_hash,encrypted_data FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=? ORDER BY chunk_index",
      [.text(scope), .text(transfer)], maximumRows: MqttChunkManifest.maximumCount) { row in
        let index = try row.number(0)
        guard (0..<Int64(MqttChunkManifest.maximumCount)).contains(index) else { throw MqttChunkStorageError.corruptState }
        return try Part(index: Int(index), digest: MqttChunkManifest.checkedHash(row.text(1)),
                        encrypted: row.data(2, maximum: MqttChunkManifest.dataBytes + 8192, allowEmpty: true))
      }
  }

  private func open(_ part: Part, record: Metadata) throws -> Data {
    guard (0..<record.count).contains(part.index) else { throw MqttChunkStorageError.corruptState }
    let data = try database.open(part.encrypted, purpose: purpose(record.scope, record.transfer, "\(part.index):\(part.digest)"))
    guard !data.isEmpty, data.count <= min(MqttChunkManifest.dataBytes, record.total),
          MqttRouteProtocol.digest(data) == part.digest else { throw MqttChunkStorageError.corruptState }
    return data
  }

  private func writePart(_ chunk: MqttChunkManifest, scope: String) throws {
    let encrypted = try database.seal(chunk.data, purpose: purpose(scope, chunk.transfer, "\(chunk.index):\(chunk.digest)"))
    try database.run("INSERT OR REPLACE INTO mqtt_wire_parts(scope_digest,transfer_id,chunk_index,chunk_hash,encrypted_data) VALUES(?,?,?,?,?)",
      [.text(scope), .text(chunk.transfer), .number(Int64(chunk.index)), .text(chunk.digest), .blob(encrypted)])
  }

  private func assemble(_ record: inout Metadata) throws -> String? {
    let saved = try parts(scope: record.scope, transfer: record.transfer)
    guard saved.count == record.count else { return nil }
    var assembled = Data(capacity: record.total)
    for (index, part) in saved.enumerated() {
      guard part.index == index else { throw MqttChunkStorageError.corruptState }
      let data = try open(part, record: record)
      guard assembled.count + data.count <= record.total else { throw MqttChunkStorageError.corruptState }
      assembled.append(data)
    }
    guard assembled.count == record.total, assembled.count == record.storedBytes,
          MqttRouteProtocol.digest(assembled) == record.transfer, let result = String(data: assembled, encoding: .utf8),
          let object = try JSONSerialization.jsonObject(with: assembled) as? [String: Any],
          object["from"] as? String == record.source, object["to"] as? String == record.target else {
      throw MqttChunkStorageError.corruptState
    }
    record.wireHash = try MqttDeliveryEnvelope.contentHash(object)
    return result
  }

  private func quota(scope: String, total: Int) throws {
    for (peer, maximum) in [(false, 65536), (true, 4096)] {
      let filter = peer ? " WHERE scope_digest=?" : ""
      let values: [MqttChunkDatabase.Value] = peer ? [.text(scope)] : []
      let count = try database.query("SELECT COUNT(*) FROM mqtt_wire_transfers" + filter, values, maximumRows: 1) { try $0.number(0) }.first
      guard let count, count < Int64(maximum) else { throw MqttChunkStorageError.capacityExceeded }
    }
    for peer in [false, true] {
      let filter = peer ? " AND scope_digest=?" : ""
      let values: [MqttChunkDatabase.Value] = peer ? [.text(scope)] : []
      let usage = try database.query("SELECT COUNT(*),COALESCE(SUM(total_bytes),0) FROM mqtt_wire_transfers WHERE completed=0" + filter,
        values, maximumRows: 1) { (try $0.number(0), try $0.number(1)) }.first
      guard let (count, bytes) = usage, count < Int64(peer ? limits.peerTransfers : limits.transfers), bytes >= 0,
            bytes <= (peer ? limits.peerBytes : limits.bytes) - Int64(total) else { throw MqttChunkStorageError.capacityExceeded }
    }
  }

  private func prune(at time: Int64) throws {
    let expired = try database.query("SELECT scope_digest,transfer_id FROM mqtt_wire_transfers WHERE expires_at<=? ORDER BY expires_at LIMIT 256",
      [.number(time)], maximumRows: 256) { (try $0.text(0), try $0.text(1)) }
    for (scope, transfer) in expired { try delete(scope: scope, transfer: transfer) }
  }

  private func delete(scope: String, transfer: String) throws {
    try database.run("DELETE FROM mqtt_wire_parts WHERE scope_digest=? AND transfer_id=?", [.text(scope), .text(transfer)])
    try database.run("DELETE FROM mqtt_wire_transfers WHERE scope_digest=? AND transfer_id=?", [.text(scope), .text(transfer)])
  }

  private func advanceRevision(_ record: inout Metadata) throws {
    guard record.revision < MqttRouteProtocol.maximumInteger else { throw MqttChunkStorageError.corruptState }
    record.revision += 1
  }

  private func scopeKey(_ scope: String) throws -> String {
    MqttRouteProtocol.digest(Data(try MqttDeliveryEnvelope.checkedText(scope, maximum: 512).utf8))
  }

  private func purpose(_ scope: String, _ transfer: String, _ suffix: String) -> String {
    "mqtt-chunk:" + MqttRouteProtocol.digest(Data("\(scope):\(transfer):\(suffix)".utf8))
  }

  private func timestamp() throws -> Int64 {
    let value = now()
    guard value >= 0, value <= MqttRouteProtocol.maximumInteger - Self.retentionMillis else { throw MqttChunkStorageError.corruptState }
    return value
  }
}
