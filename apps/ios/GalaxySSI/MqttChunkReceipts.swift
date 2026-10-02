import Foundation

// Transport storage state only; a full bitmap is not business/task completion.
enum MqttChunkReceipts {
  static let field = "_mqtt_chunks"
  static let probe = "link_chunk_probe"
  static let state = "link_chunk_state"

  struct Query: Equatable {
    let transfer: String
    let manifest: String
    let count: Int
    let request: String

    init(transfer: String, manifest: String, count: Int, request: String) throws {
      _ = try MqttChunkManifest.checkedHash(transfer)
      _ = try MqttChunkManifest.checkedHash(manifest)
      guard (1...MqttChunkManifest.maximumCount).contains(count), MqttRouteProtocol.hex(request, count: 32) else {
        throw MqttRouteError.invalidPayload
      }
      self.transfer = transfer
      self.manifest = manifest
      self.count = count
      self.request = request
    }

    func wire() -> [String: Any] {
      ["type": MqttChunkReceipts.probe, "version": 1, "transfer_id": transfer, "manifest_hash": manifest,
       "chunk_count": count, "request_id": request]
    }

    func response(epoch: String, revision: Int64, indices: Set<Int>) throws -> [String: Any] {
      var bitmap = [UInt8](repeating: 0, count: (count + 7) / 8)
      for index in indices {
        guard (0..<count).contains(index) else { throw MqttRouteError.invalidPayload }
        bitmap[index / 8] |= UInt8(1 << (index % 8))
      }
      var payload = wire()
      payload["type"] = MqttChunkReceipts.state
      payload["store_epoch"] = epoch
      payload["revision"] = revision
      payload["stored_bitmap"] = Data(bitmap).base64EncodedString()
      _ = try MqttChunkReceipts.parseState(payload)
      return payload
    }
  }

  struct State: Equatable {
    let query: Query
    let epoch: String
    let revision: Int64
    let bitmap: Data

    var storedIndices: Set<Int> {
      Set((0..<query.count).filter { bitmap[$0 / 8] & UInt8(1 << ($0 % 8)) != 0 })
    }
  }

  static func newRequest() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }

  static func parse(_ wire: [String: Any]) throws -> Query {
    guard let type = wire["type"] as? String, [probe, state].contains(type),
          try MqttRouteProtocol.integer(wire, "version") == 1,
          let request = wire["request_id"] as? String else { throw MqttRouteError.invalidPayload }
    return try Query(transfer: MqttChunkManifest.checkedHash(wire["transfer_id"]),
      manifest: MqttChunkManifest.checkedHash(wire["manifest_hash"]),
      count: MqttChunkManifest.integer(wire, "chunk_count", minimum: 1, maximum: MqttChunkManifest.maximumCount), request: request)
  }

  static func fromChunk(_ wire: [String: Any]) throws -> Query? {
    guard let value = wire[field] else { return nil }
    guard let metadata = value as? [String: Any] else { throw MqttRouteError.invalidPayload }
    let query = try parse(metadata)
    let chunk = try MqttChunkManifest.parse(wire)
    guard query.transfer == chunk.transfer, query.manifest == chunk.manifestHash, query.count == chunk.count else {
      throw MqttRouteError.invalidPayload
    }
    return query
  }

  static func parseState(_ wire: [String: Any]) throws -> State {
    let query = try parse(wire)
    guard wire["type"] as? String == state, let epoch = wire["store_epoch"] as? String,
          MqttRouteProtocol.hex(epoch, count: 32) else { throw MqttRouteError.invalidPayload }
    let revision = try MqttRouteProtocol.integer(wire, "revision")
    let size = (query.count + 7) / 8
    guard let encoded = wire["stored_bitmap"] as? String, encoded.utf8.count == 4 * ((size + 2) / 3),
          let bitmap = Data(base64Encoded: encoded), bitmap.count == size, bitmap.base64EncodedString() == encoded,
          (query.count % 8 == 0 || Int(bitmap[size - 1]) >> (query.count % 8) == 0),
          (epoch != String(repeating: "0", count: 32) || (revision == 0 && bitmap.allSatisfy { $0 == 0 })) else {
      throw MqttRouteError.invalidPayload
    }
    return State(query: query, epoch: epoch, revision: revision, bitmap: bitmap)
  }
}
