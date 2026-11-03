import Foundation

// Derived from a trusted local binding, never an identity claimed by a network payload.
struct MqttBusinessIdentity: Codable, Equatable {
  let scope: String
  let binding: String
  let local: String
  let remote: String

  init(_ peer: MqttPeerBinding) throws {
    try peer.validate()
    scope = peer.scope; binding = try peer.authenticationID(); local = peer.sender; remote = peer.receiver
  }

  func validate() throws {
    _ = try MqttDeliveryEnvelope.checkedText(scope, maximum: 512)
    guard MqttRouteProtocol.hex(binding, count: 64), MqttRouteProtocol.hex(local, count: 64),
          MqttRouteProtocol.hex(remote, count: 64), local != remote else { throw MqttRouteError.invalidPayload }
  }
  func key(messageID: String) throws -> String {
    try validate()
    _ = try MqttDeliveryEnvelope.checkedText(messageID)
    return MqttRouteProtocol.digest(Data("\(binding)\0\(messageID)".utf8))
  }
}

enum MqttBusinessStorage {
  static let maximumPayloadBytes = 2 * 1024 * 1024 + 4096
  static let maximumRecordBytes = 3 * 1024 * 1024
  static let retention: Int64 = 8 * 24 * 60 * 60 * 1000

  static func payload(_ object: [String: Any]) throws -> Data {
    try checkDepth(object)
    let data = try GalaxySSILinkProtocol.jsonData(object)
    guard data.count <= maximumPayloadBytes else { throw MqttRouteError.invalidPayload }
    return data
  }
  private static func checkDepth(_ object: Any, depth: Int = 0) throws {
    guard depth <= 64 else { throw MqttRouteError.invalidPayload }
    if let values = object as? [String: Any] { try values.values.forEach { try checkDepth($0, depth: depth + 1) } }
    else if let values = object as? [Any] { try values.forEach { try checkDepth($0, depth: depth + 1) } }
  }
  static func timestamp(_ value: Int64) throws -> Int64 {
    guard value >= 0, value <= MqttRouteProtocol.maximumInteger - retention else { throw MqttRouteError.invalidPayload }
    return value
  }
}
