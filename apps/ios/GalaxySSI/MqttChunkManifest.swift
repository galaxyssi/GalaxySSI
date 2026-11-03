import Foundation

struct MqttChunkManifest: Equatable {
  static let dataBytes = 380 * 1024
  static let maximumBytes = 2 * 1024 * 1024
  static let maximumCount = 96

  let transfer: String
  let manifestHash: String
  let count: Int
  let total: Int
  let index: Int
  let digest: String
  let data: Data
  let source: String
  let target: String

  static func parse(_ wire: [String: Any]) throws -> Self {
    guard wire["scheme"] as? String == "signal-chunk" else { throw MqttRouteError.invalidPayload }
    let transfer = try checkedHash(wire["transfer_id"])
    guard try transfer == checkedHash(wire["sha256"]) else { throw MqttRouteError.invalidPayload }
    let digest = try checkedHash(wire["chunk_sha256"])
    let count = try integer(wire, "chunk_count", minimum: 1, maximum: maximumCount)
    let total = try integer(wire, "total_bytes", minimum: count, maximum: maximumBytes)
    let index = try integer(wire, "chunk_index", minimum: 0, maximum: count - 1)
    let source = try MqttDeliveryEnvelope.checkedText(wire["from"], maximum: 512)
    let target = try MqttDeliveryEnvelope.checkedText(wire["to"], maximum: 512)
    guard let encoded = wire["data"] as? String, !encoded.isEmpty,
          encoded.utf8.count <= 4 * ((dataBytes + 2) / 3),
          let data = Data(base64Encoded: encoded), !data.isEmpty, data.count <= min(dataBytes, total),
          data.base64EncodedString() == encoded, MqttRouteProtocol.digest(data) == digest else {
      throw MqttRouteError.invalidPayload
    }
    var canonical = Data("GalaxySSI/WireChunkManifest/v1\0".utf8)
    for value in [transfer, String(count), String(total), source, target] {
      let bytes = Data(value.utf8)
      canonical.append(Data("\(bytes.count):".utf8))
      canonical.append(bytes)
    }
    return Self(transfer: transfer, manifestHash: MqttRouteProtocol.digest(canonical), count: count, total: total,
                index: index, digest: digest, data: data, source: source, target: target)
  }

  static func checkedHash(_ value: Any?) throws -> String {
    guard let value = value as? String, MqttRouteProtocol.hex(value, count: 64) else { throw MqttRouteError.invalidPayload }
    return value
  }

  static func integer(_ object: [String: Any], _ key: String, minimum: Int, maximum: Int) throws -> Int {
    let value = try MqttRouteProtocol.integer(object, key)
    guard value >= Int64(minimum), value <= Int64(maximum) else { throw MqttRouteError.invalidPayload }
    return Int(value)
  }
}
