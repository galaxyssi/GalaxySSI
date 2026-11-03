import Foundation

// Already pair-encrypted, exactly one QoS1 packet. Never feed this payload to legacy auto-chunking.
struct MqttSealedPathPublication {
  let publication: MqttDeliveryDispatch.Publication
  let completed: (Bool) -> Void
  var configurationID = ""

  var authorization: MqttPathPublication {
    MqttPathPublication(topic: publication.topic, payload: Data(), generation: publication.frame.attempt.generation,
      receiveTopics: publication.receiveTopics, secretFingerprint: publication.secretFingerprint,
      durableMessageID: publication.frame.message.messageID, configurationID: configurationID,
      authorized: { [publication] in publication.authorized(publication.frame.attempt.brokerID, publication.frame.attempt.generation) })
  }

  func accepts(snapshot: MqttBrokerPathSnapshot, secretFingerprint: String) -> Bool {
    publication.frame.attempt.brokerID == snapshot.brokerID &&
      MqttRouteProtocol.hex(publication.secretFingerprint, count: 64) &&
      MqttBrokerPathPolicy.accepts(authorization, snapshot: snapshot, currentSecretFingerprint: secretFingerprint) &&
      (try? MqttDeliveryDispatch.packetBytes(topic: publication.topic, payloadBytes: publication.payload.count)) != nil
  }
}

// Client invalidation and PUBACK callbacks can race after leaving the transport queue.
final class MqttPhysicalCompletion {
  private let lock = NSLock()
  private var callback: ((Bool) -> Void)?
  init(_ callback: @escaping (Bool) -> Void) { self.callback = callback }
  func finish(_ acknowledged: Bool) {
    lock.lock()
    let current = callback
    callback = nil
    lock.unlock()
    current?(acknowledged)
  }
}

// Keeps callbacks from retaining the dispatcher through its own publish closure.
final class MqttDeliveryCompletionRelay {
  private let lock = NSLock()
  private weak var dispatcher: MqttDeliveryDispatch?
  func bind(_ dispatcher: MqttDeliveryDispatch) { lock.lock(); self.dispatcher = dispatcher; lock.unlock() }
  func complete(_ attempt: MqttDeliveryEnvelope.Attempt, acknowledged: Bool) {
    lock.lock()
    let target = dispatcher
    lock.unlock()
    guard let target else { return }
    Task {
      await target.published(attemptID: attempt.attemptID, broker: attempt.brokerID,
                             generation: attempt.generation, acknowledged: acknowledged)
    }
  }
}

enum MqttSignalDelivery {
  // The caller supplies the currently authorized relationship and authenticated route-session gate.
  static func make(peer: String, topic: String, wire: Data, message: MqttDeliveryEnvelope.Message,
                   secret: String, receiveTopics: Set<String>,
                   authorized: @escaping (String, Int64) -> Bool) throws -> MqttDeliveryDispatch.Delivery {
    guard GalaxySSILinkProtocol.validLinkSecret(secret), GalaxySSILinkProtocol.validTopic(topic),
          !receiveTopics.isEmpty, receiveTopics.allSatisfy(GalaxySSILinkProtocol.validTopic),
          let object = try JSONSerialization.jsonObject(with: wire) as? [String: Any] else { throw MqttRouteError.invalidPayload }
    // Longest catalog broker ID and largest permitted generation bound every later physical copy.
    let largest = try MqttDeliveryEnvelope.Frame(message: message, attempt: .init(
      attemptID: String(repeating: "f", count: 32), brokerID: "mosquitto", generation: MqttRouteProtocol.maximumInteger))
    let measured = try GalaxySSILinkProtocol.jsonData(largest.attach(to: object))
    let bound = try MqttDeliveryDispatch.packetBytes(topic: topic,
      payloadBytes: GalaxySSILinkProtocol.sealedWirePacketByteCount(payloadBytes: measured.count))
    return .init(peer: peer, message: message, receiveTopics: receiveTopics,
      secretFingerprint: MqttRouteProtocol.digest(Data(secret.utf8)), sizeBound: bound,
      encodeAttempt: { frame in
        guard frame.message == message else { throw MqttRouteError.invalidPayload }
        return try GalaxySSILinkProtocol.sealWirePacket(GalaxySSILinkProtocol.jsonData(frame.attach(to: object)), secret: secret)
      }, authorized: authorized)
  }
}
