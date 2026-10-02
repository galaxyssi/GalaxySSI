import CoreFoundation
import CryptoKit
import Foundation

enum MqttRouteProtocol {
  static let version: Int64 = 1
  static let brokerIDs: Set<String> = ["emqx", "hivemq", "mosquitto"]
  static let packetBytes = 1_048_576
  static let resumeTTL: Int64 = 300_000
  static let maximumInteger: Int64 = 9_007_199_254_740_991

  static func integer(_ object: [String: Any], _ key: String) throws -> Int64 {
    guard let value = object[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
          !["f", "d"].contains(String(cString: value.objCType)),
          value.doubleValue >= 0, value.doubleValue <= Double(maximumInteger) else {
      throw MqttRouteError.invalidPayload
    }
    return value.int64Value
  }

  static func hex(_ value: String, count: Int) -> Bool {
    value.utf8.count == count && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

enum MqttRouteError: Error {
  case invalidPayload
  case unreadableState
  case persistenceFailed
  case exhaustedEpoch
  case staleGeneration
  case identityChanged
  case unsolicitedAcknowledgement
}

struct MqttRouteAdvertisement: Codable, Equatable {
  var sender: String
  var receiver: String
  var epoch: Int64
  var resumeId: String
  var issuedAt: Int64
  var expiresAt: Int64
  var receiveBrokers: Set<String>
  var packetBytes: Int

  func wire() -> [String: Any] {
    ["type": "link_resume", "transport_version": MqttRouteProtocol.version,
     "sender_fingerprint": sender, "receiver_fingerprint": receiver, "route_epoch": epoch,
     "resume_id": resumeId, "issued_at_ms": issuedAt, "expires_at_ms": expiresAt,
     "supported_brokers": MqttRouteProtocol.brokerIDs.sorted(), "receive_brokers": receiveBrokers.sorted(),
     "max_encoded_packet_bytes": packetBytes, "multipath": true, "chunk_acks": true]
  }

  func digest() throws -> String {
    // All permitted keys and string values are ASCII identifiers without slashes.
    MqttRouteProtocol.digest(try JSONSerialization.data(withJSONObject: wire(), options: [.sortedKeys]))
  }

  // Call only after authenticating the relationship AEAD and ingress generation.
  static func parseVerified(_ object: [String: Any], sender: String, receiver: String, now: Int64) throws -> Self {
    guard object["type"] as? String == "link_resume",
          try MqttRouteProtocol.integer(object, "transport_version") == MqttRouteProtocol.version,
          let multipath = object["multipath"] as? NSNumber, CFGetTypeID(multipath) == CFBooleanGetTypeID(), multipath.boolValue,
          let chunkACKs = object["chunk_acks"] as? NSNumber, CFGetTypeID(chunkACKs) == CFBooleanGetTypeID(), chunkACKs.boolValue,
          MqttRouteProtocol.hex(sender, count: 64), MqttRouteProtocol.hex(receiver, count: 64), sender != receiver,
          object["sender_fingerprint"] as? String == sender,
          object["receiver_fingerprint"] as? String == receiver else { throw MqttRouteError.invalidPayload }
    let epoch = try MqttRouteProtocol.integer(object, "route_epoch")
    let issued = try MqttRouteProtocol.integer(object, "issued_at_ms")
    let expires = try MqttRouteProtocol.integer(object, "expires_at_ms")
    let bytes = try MqttRouteProtocol.integer(object, "max_encoded_packet_bytes")
    guard now >= 0, now <= MqttRouteProtocol.maximumInteger,
          epoch > 0, issued <= now + 300_000, expires > issued,
          expires - issued <= MqttRouteProtocol.resumeTTL, expires > now,
          bytes > 0, bytes <= MqttRouteProtocol.packetBytes,
          let resumeId = object["resume_id"] as? String, MqttRouteProtocol.hex(resumeId, count: 32),
          let supported = object["supported_brokers"] as? [String], supported.count == 3,
          Set(supported) == MqttRouteProtocol.brokerIDs,
          let active = object["receive_brokers"] as? [String], active.count <= 3,
          Set(active).count == active.count, Set(active).isSubset(of: MqttRouteProtocol.brokerIDs) else {
      throw MqttRouteError.invalidPayload
    }
    return Self(sender: sender, receiver: receiver, epoch: epoch, resumeId: resumeId,
                issuedAt: issued, expiresAt: expires, receiveBrokers: Set(active), packetBytes: Int(bytes))
  }
}
