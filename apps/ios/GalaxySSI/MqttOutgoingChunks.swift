import Foundation

// Only resume metadata is stored here. The existing durable outbox owns the Signal wire bytes.
final class MqttOutgoingChunks {
  static let retentionMillis: Int64 = 7 * 24 * 60 * 60 * 1000
  private static let brokers = MqttRouteProtocol.brokerIDs.sorted()

  struct Limits {
    var transfers = 65_536
    var peerTransfers = 4_096
  }

  struct Selection {
    let index: Int
    let wire: [String: Any]
  }

  struct Batch {
    let query: MqttChunkReceipts.Query
    let selected: [Selection]
    fileprivate let paths: Data

    func attempted(index: Int) -> Set<String> {
      guard (0..<paths.count).contains(index) else { return [] }
      return Set(MqttOutgoingChunks.brokers.enumerated().compactMap { bit, broker in
        paths[index] & UInt8(1 << bit) != 0 ? broker : nil
      })
    }
  }

  private struct Row: Codable {
    var scope: String
    var transfer: String
    var manifest: String
    var count: Int
    var request: String
    var epoch: String
    var revision: Int64
    var bitmap: Data
    var paths: Data
    var expiresAt: Int64
  }

  private let database: MqttChunkDatabase
  private let now: () -> Int64
  private let limits: Limits

  init(fileURL: URL, secrets: GalaxySSISecretStore = KeychainSecretStore.shared, limits: Limits = Limits(),
       now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) throws {
    guard limits.transfers > 0, limits.peerTransfers > 0 else { throw MqttChunkStorageError.capacityExceeded }
    self.database = try MqttChunkDatabase(fileURL: fileURL, secrets: secrets)
    self.now = now
    self.limits = limits
  }

  func prepare(authenticatedScope: String, parts: [[String: Any]]) throws -> Batch {
    let manifest = try validate(parts)
    let scope = try scopeKey(authenticatedScope)
    return try database.transaction {
      let at = try timestamp()
      try database.run("DELETE FROM mqtt_outgoing_chunks WHERE scope_digest=? AND transfer_id=? AND expires_at<=?",
        [.text(scope), .text(manifest.transfer), .number(at)])
      try database.run("DELETE FROM mqtt_outgoing_chunks WHERE rowid IN (SELECT rowid FROM mqtt_outgoing_chunks WHERE expires_at<=? LIMIT 256)", [.number(at)])
      var row: Row
      if let previous = try read(scope: scope, transfer: manifest.transfer) {
        guard previous.manifest == manifest.manifestHash, previous.count == manifest.count else { throw MqttChunkStorageError.corruptState }
        row = previous
      } else {
        try quota(scope: scope)
        row = Row(scope: scope, transfer: manifest.transfer, manifest: manifest.manifestHash, count: manifest.count,
          request: "", epoch: "", revision: -1, bitmap: Data(repeating: 0, count: (manifest.count + 7) / 8),
          paths: Data(repeating: 0, count: manifest.count), expiresAt: at + Self.retentionMillis)
      }
      // Every publication round gets a fresh request. Keep known bits/path history,
      // but allow the receiver's current store epoch to be learned again after restart.
      row.request = MqttChunkReceipts.newRequest()
      row.epoch = ""
      row.revision = -1
      let query = try makeQuery(row)
      let selected = parts.enumerated().compactMap { index, part -> Selection? in
        guard row.bitmap[index / 8] & UInt8(1 << (index % 8)) == 0 else { return nil }
        var wire = part
        wire[MqttChunkReceipts.field] = query.wire()
        return Selection(index: index, wire: wire)
      }
      try save(row)
      return Batch(query: query, selected: selected.isEmpty ? [Selection(index: -1, wire: query.wire())] : selected, paths: row.paths)
    }
  }

  // Call only after the current relationship AEAD and ingress authorization succeed.
  @discardableResult
  func accept(authenticatedScope: String, state raw: [String: Any]) throws -> Bool {
    let state = try MqttChunkReceipts.parseState(raw)
    let query = state.query
    let scope = try scopeKey(authenticatedScope)
    return try database.transaction {
      guard var row = try read(scope: scope, transfer: query.transfer), row.expiresAt > (try timestamp()),
            row.manifest == query.manifest, row.count == query.count, row.request == query.request else { return false }
      if !row.epoch.isEmpty {
        guard row.epoch == state.epoch, state.revision >= row.revision else { return false }
        if state.revision == row.revision {
          guard row.bitmap == state.bitmap else { throw MqttChunkStorageError.corruptState }
          return false
        }
      }
      row.epoch = state.epoch
      row.revision = state.revision
      row.bitmap = state.bitmap
      try save(row)
      return true
    }
  }

  @discardableResult
  func recordPath(authenticatedScope: String, query: MqttChunkReceipts.Query, index: Int, broker: String) throws -> Bool {
    if index < 0 { return false }
    guard (0..<query.count).contains(index), let bit = Self.brokers.firstIndex(of: broker) else { throw MqttRouteError.invalidPayload }
    let scope = try scopeKey(authenticatedScope)
    return try database.transaction {
      guard var row = try read(scope: scope, transfer: query.transfer), row.expiresAt > (try timestamp()),
            row.manifest == query.manifest, row.count == query.count, row.request == query.request else { return false }
      row.paths[index] |= UInt8(1 << bit)
      try save(row)
      return true
    }
  }

  func forget(authenticatedScope: String) throws {
    let scope = try scopeKey(authenticatedScope)
    try database.transaction { try database.run("DELETE FROM mqtt_outgoing_chunks WHERE scope_digest=?", [.text(scope)]) }
  }

  func clear() throws { try database.transaction { try database.run("DELETE FROM mqtt_outgoing_chunks") } }

  private func validate(_ parts: [[String: Any]]) throws -> MqttChunkManifest {
    guard let first = parts.first, parts.count <= MqttChunkManifest.maximumCount else { throw MqttRouteError.invalidPayload }
    let manifest = try MqttChunkManifest.parse(first)
    guard parts.count == manifest.count else { throw MqttRouteError.invalidPayload }
    var assembled = Data(capacity: manifest.total)
    for (index, wire) in parts.enumerated() {
      let part = try MqttChunkManifest.parse(wire)
      guard part.manifestHash == manifest.manifestHash, part.index == index,
            assembled.count + part.data.count <= manifest.total else { throw MqttRouteError.invalidPayload }
      assembled.append(part.data)
    }
    guard assembled.count == manifest.total, MqttRouteProtocol.digest(assembled) == manifest.transfer else { throw MqttRouteError.invalidPayload }
    return manifest
  }

  private func read(scope: String, transfer: String) throws -> Row? {
    try database.query("SELECT expires_at,encrypted_metadata FROM mqtt_outgoing_chunks WHERE scope_digest=? AND transfer_id=?",
      [.text(scope), .text(transfer)], maximumRows: 1) { row in
        let encoded = try database.open(row.data(1, maximum: 16 * 1024), purpose: purpose(scope, transfer))
        let saved = try JSONDecoder().decode(Row.self, from: encoded)
        guard saved.scope == scope, saved.transfer == transfer,
              (1...MqttChunkManifest.maximumCount).contains(saved.count),
              saved.bitmap.count == (saved.count + 7) / 8, saved.paths.count == saved.count,
              saved.paths.allSatisfy({ $0 & 0xf8 == 0 }),
              (saved.count % 8 == 0 || Int(saved.bitmap[saved.bitmap.count - 1]) >> (saved.count % 8) == 0),
              (0...MqttRouteProtocol.maximumInteger).contains(saved.expiresAt),
              try row.number(0) == saved.expiresAt else { throw MqttChunkStorageError.corruptState }
        let query = try makeQuery(saved)
        if saved.epoch.isEmpty {
          guard saved.revision == -1 else { throw MqttChunkStorageError.corruptState }
        } else {
          var wire = query.wire()
          wire["type"] = MqttChunkReceipts.state
          wire["store_epoch"] = saved.epoch
          wire["revision"] = saved.revision
          wire["stored_bitmap"] = saved.bitmap.base64EncodedString()
          _ = try MqttChunkReceipts.parseState(wire)
        }
        return saved
      }.first
  }

  private func save(_ row: Row) throws {
    let encrypted = try database.seal(JSONEncoder().encode(row), purpose: purpose(row.scope, row.transfer))
    try database.run("""
      INSERT INTO mqtt_outgoing_chunks(scope_digest,transfer_id,expires_at,encrypted_metadata) VALUES(?,?,?,?)
      ON CONFLICT(scope_digest,transfer_id) DO UPDATE SET expires_at=excluded.expires_at,encrypted_metadata=excluded.encrypted_metadata
      """, [.text(row.scope), .text(row.transfer), .number(row.expiresAt), .blob(encrypted)])
  }

  private func quota(scope: String) throws {
    for peer in [false, true] {
      let filter = peer ? " WHERE scope_digest=?" : ""
      let values: [MqttChunkDatabase.Value] = peer ? [.text(scope)] : []
      let count = try database.query("SELECT COUNT(*) FROM mqtt_outgoing_chunks" + filter, values, maximumRows: 1) { try $0.number(0) }.first
      guard let count, count < Int64(peer ? limits.peerTransfers : limits.transfers) else { throw MqttChunkStorageError.capacityExceeded }
    }
  }

  private func makeQuery(_ row: Row) throws -> MqttChunkReceipts.Query {
    try .init(transfer: row.transfer, manifest: row.manifest, count: row.count, request: row.request)
  }

  private func scopeKey(_ scope: String) throws -> String {
    MqttRouteProtocol.digest(Data(try MqttDeliveryEnvelope.checkedText(scope, maximum: 512).utf8))
  }

  private func purpose(_ scope: String, _ transfer: String) -> String {
    "mqtt-outgoing:" + MqttRouteProtocol.digest(Data("\(scope):\(transfer)".utf8))
  }

  private func timestamp() throws -> Int64 {
    let value = now()
    guard value >= 0, value <= MqttRouteProtocol.maximumInteger - Self.retentionMillis else { throw MqttChunkStorageError.corruptState }
    return value
  }
}
