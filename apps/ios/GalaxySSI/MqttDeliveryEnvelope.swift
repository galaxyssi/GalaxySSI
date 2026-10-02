import CryptoKit
import Foundation

// These fields are inside pair AEAD. Parsing is not authentication or proof of storage.
enum MqttDeliveryEnvelope {
  static let field = "_mqtt_delivery"
  static let algorithm = "signal-wire-sha256-v1"
  static let receiptType = "link_rx_stored"
  private static let textFields = ["scheme", "from", "to", "signal_type", "type", "body", "protocol"]
  private static let numberFields = ["message_type", "messageType", "device_id", "version"]
  private static let trafficClasses: Set<String> = ["control", "message", "final", "progress", "chunk", "receipt"]

  struct Message: Equatable, Hashable {
    let messageID: String
    let contentHash: String
    let sender: String
    let receiver: String
    let traffic: String

    init(messageID: String, contentHash: String, sender: String, receiver: String, traffic: String) throws {
      _ = try MqttDeliveryEnvelope.checkedText(messageID)
      guard MqttRouteProtocol.hex(contentHash, count: 64), MqttRouteProtocol.hex(sender, count: 64),
            MqttRouteProtocol.hex(receiver, count: 64), sender != receiver, MqttDeliveryEnvelope.trafficClasses.contains(traffic) else {
        throw MqttRouteError.invalidPayload
      }
      self.messageID = messageID
      self.contentHash = contentHash
      self.sender = sender
      self.receiver = receiver
      self.traffic = traffic
    }
  }

  struct Attempt: Equatable, Hashable {
    let attemptID: String
    let brokerID: String
    let generation: Int64

    init(attemptID: String, brokerID: String, generation: Int64) throws {
      guard MqttRouteProtocol.hex(attemptID, count: 32), MqttRouteProtocol.brokerIDs.contains(brokerID),
            (1...MqttRouteProtocol.maximumInteger).contains(generation) else { throw MqttRouteError.invalidPayload }
      self.attemptID = attemptID
      self.brokerID = brokerID
      self.generation = generation
    }
  }

  struct Frame: Equatable, Hashable {
    let message: Message
    let attempt: Attempt

    func metadata() -> [String: Any] {
      ["version": 1, "content_hash_algorithm": MqttDeliveryEnvelope.algorithm, "message_id": message.messageID,
       "content_hash": message.contentHash, "sender": message.sender, "receiver": message.receiver,
       "traffic": message.traffic, "attempt_id": attempt.attemptID, "broker_id": attempt.brokerID,
       "generation": attempt.generation]
    }

    func attach(to wire: [String: Any]) throws -> [String: Any] {
      guard wire[MqttDeliveryEnvelope.field] == nil, try MqttDeliveryEnvelope.contentHash(wire) == message.contentHash else {
        throw MqttRouteError.invalidPayload
      }
      var attached = wire
      attached[MqttDeliveryEnvelope.field] = metadata()
      return attached
    }

    func validateApplication(messageID: String, wireHash: String) throws {
      guard message.messageID == messageID, message.contentHash == wireHash else { throw MqttRouteError.invalidPayload }
    }

    // The caller supplies values read from its committed business inbox, never from the network frame.
    func receiptAfterStore(messageID: String, wireHash: String) throws -> [String: Any] {
      try validateApplication(messageID: messageID, wireHash: wireHash)
      guard message.traffic != "receipt" else { throw MqttRouteError.invalidPayload }
      var receipt = metadata()
      receipt["type"] = MqttDeliveryEnvelope.receiptType
      receipt["status"] = "RX_STORED"
      return receipt
    }
  }

  static func contentHash(_ wire: [String: Any]) throws -> String {
    guard wire["scheme"] as? String == "signal" else { throw MqttRouteError.invalidPayload }
    for key in ["from", "to", "body"] { _ = try checkedText(wire[key], maximum: key == "body" ? 4 * 1024 * 1024 : 512) }
    var digest = SHA256()
    digest.update(data: Data("GalaxySSI/SignalWireReceipt/v1\0".utf8))
    for key in textFields + numberFields {
      guard let value = wire[key] else { continue }
      let kind: String
      let bytes: Data
      if textFields.contains(key) {
        kind = "s"
        bytes = Data(try checkedText(value, maximum: key == "body" ? 4 * 1024 * 1024 : 512).utf8)
      } else {
        kind = "i"
        bytes = Data(String(try positiveInteger(wire, key)).utf8)
      }
      digest.update(data: Data("\(key.utf8.count):\(key)\(kind)\(bytes.count):".utf8))
      digest.update(data: bytes)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  static func parseVerifiedFrame(_ wire: [String: Any], sender: String, receiver: String,
                                 ingressBroker: String) throws -> Frame {
    guard let metadata = wire[field] as? [String: Any] else { throw MqttRouteError.invalidPayload }
    let frame = try parseMetadata(metadata)
    guard frame.message.sender == sender, frame.message.receiver == receiver,
          frame.attempt.brokerID == ingressBroker, try frame.message.contentHash == contentHash(wire) else {
      throw MqttRouteError.invalidPayload
    }
    return frame
  }

  // A receipt may return over a different broker. Its actor must be the authenticated original receiver.
  static func parseVerifiedReceipt(_ payload: [String: Any], originalSender: String,
                                   originalReceiver: String) throws -> Frame {
    guard payload["type"] as? String == receiptType, payload["status"] as? String == "RX_STORED" else {
      throw MqttRouteError.invalidPayload
    }
    let frame = try parseMetadata(payload)
    guard frame.message.sender == originalSender, frame.message.receiver == originalReceiver,
          frame.message.traffic != "receipt" else { throw MqttRouteError.invalidPayload }
    return frame
  }

  static func receiptBinding(scope: String, sender: String, receiver: String, secret: String) throws -> String {
    var encoded = Data("GalaxySSI/OutboundReceiptBinding/v1\0".utf8)
    for value in [scope, sender, receiver, secret] {
      let bytes = Data(try checkedText(value, maximum: 512).utf8)
      encoded.append(Data("\(bytes.count):".utf8))
      encoded.append(bytes)
    }
    return MqttRouteProtocol.digest(encoded)
  }

  static func storedReceipt(messageID: String, wireHash: String) throws -> [String: Any] {
    _ = try checkedText(messageID)
    guard MqttRouteProtocol.hex(wireHash, count: 64) else { throw MqttRouteError.invalidPayload }
    return ["type": "delivery_ack", "delivery_status": "RX_STORED", "transport_message_id": messageID,
            "content_hash": wireHash, "content_hash_algorithm": algorithm]
  }

  static func parseStoredReceipt(_ payload: [String: Any]) throws -> (messageID: String, wireHash: String) {
    guard payload["type"] as? String == "delivery_ack", payload["delivery_status"] as? String == "RX_STORED",
          payload["content_hash_algorithm"] as? String == algorithm else { throw MqttRouteError.invalidPayload }
    let messageID = try checkedText(payload["transport_message_id"])
    let hash = try checkedText(payload["content_hash"])
    guard MqttRouteProtocol.hex(hash, count: 64) else { throw MqttRouteError.invalidPayload }
    return (messageID, hash)
  }

  private static func parseMetadata(_ payload: [String: Any]) throws -> Frame {
    guard try positiveInteger(payload, "version") == 1,
          payload["content_hash_algorithm"] as? String == algorithm else { throw MqttRouteError.invalidPayload }
    return try Frame(message: Message(messageID: checkedText(payload["message_id"]),
      contentHash: checkedText(payload["content_hash"]), sender: checkedText(payload["sender"]),
      receiver: checkedText(payload["receiver"]), traffic: checkedText(payload["traffic"])),
      attempt: Attempt(attemptID: checkedText(payload["attempt_id"]), brokerID: checkedText(payload["broker_id"]),
                       generation: positiveInteger(payload, "generation")))
  }

  static func checkedText(_ value: Any?, maximum: Int = 256) throws -> String {
    guard let text = value as? String, !text.isEmpty, text.utf8.count <= maximum,
          text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else { throw MqttRouteError.invalidPayload }
    return text
  }

  private static func positiveInteger(_ payload: [String: Any], _ key: String) throws -> Int64 {
    let value = try MqttRouteProtocol.integer(payload, key)
    guard value > 0 else { throw MqttRouteError.invalidPayload }
    return value
  }
}
