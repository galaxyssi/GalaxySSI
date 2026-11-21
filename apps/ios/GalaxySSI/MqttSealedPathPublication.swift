import Foundation

// Already pair-encrypted, exactly one QoS1 packet. Never feed this payload to legacy auto-chunking.
struct MqttSealedPathPublication {
  let publication: MqttDeliveryDispatch.Publication
  let completed: (Bool) -> Void
  var configurationID = ""
  var fragmentTransferID: String? = nil

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

// Tracks physical receipt copies independently of the caller's coalesced feedback slot.
final class MqttReceiptPublication {
  struct Copy { let token: String; let generation: Int64; let configuration: String; let started: Int64; var failed = false }
  let payload: Data
  let expires: Int64
  private let lock = NSLock()
  private var copies: [String: Copy] = [:]
  private var acknowledged = false

  init(payload: Data, now: Int64) { self.payload = payload; self.expires = now + 30_000 }
  var accepted: Bool { locked { acknowledged } }
  var attempted: Set<String> { locked { Set(copies.keys) } }

  func claim(broker: String, generation: Int64, now: Int64, configuration: String = "") -> String? {
    locked {
      guard !acknowledged, now < expires else { return nil }
      if let latest = copies.values.max(by: { $0.started < $1.started }), !latest.failed,
         now - latest.started < 1000 { return nil }
      if let previous = copies[broker], previous.generation == generation, previous.configuration == configuration,
         !previous.failed || now - previous.started < 500 { return nil }
      let token = UUID().uuidString
      copies[broker] = Copy(token: token, generation: generation, configuration: configuration, started: now)
      return token
    }
  }

  func permits(broker: String, token: String) -> Bool {
    locked { !acknowledged && copies[broker]?.token == token && copies[broker]?.failed == false }
  }
  func finish(broker: String, token: String, accepted: Bool) {
    locked {
      guard var copy = copies[broker], copy.token == token else { return }
      if accepted { acknowledged = true }
      else { copy.failed = true; copies[broker] = copy }
    }
  }
  private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}

enum MqttSignalDelivery {
  static let publicBrokerDirectBytes = 60 * 1024
  static let publicBrokerChunkBytes = 44 * 1024

  static func requiresFragments(topic: String, wire: Data, message: MqttDeliveryEnvelope.Message) throws -> Bool {
    guard let object = try JSONSerialization.jsonObject(with: wire) as? [String: Any] else {
      throw MqttRouteError.invalidPayload
    }
    let bytes = try framedBytes(object, message: message)
    if bytes > publicBrokerDirectBytes { return true }
    guard let sealed = try? GalaxySSILinkProtocol.sealedWirePacketByteCount(payloadBytes: bytes) else { return true }
    return (try? MqttDeliveryDispatch.packetBytes(topic: topic, payloadBytes: sealed)) == nil
  }

  private static func framedBytes(_ object: [String: Any], message: MqttDeliveryEnvelope.Message) throws -> Int {
    let largest = try MqttDeliveryEnvelope.Frame(message: message, attempt: .init(
      attemptID: String(repeating: "f", count: 32), brokerID: "mosquitto", generation: MqttRouteProtocol.maximumInteger))
    return try GalaxySSILinkProtocol.jsonData(largest.attach(to: object)).count
  }

  // The caller supplies the currently authorized relationship and authenticated route-session gate.
  static func make(peer: String, topic: String, wire: Data, message: MqttDeliveryEnvelope.Message,
                   secret: String, receiveTopics: Set<String>,
                   authorized: @escaping (String, Int64) -> Bool) throws -> MqttDeliveryDispatch.Delivery {
    guard GalaxySSILinkProtocol.validLinkSecret(secret), GalaxySSILinkProtocol.validTopic(topic),
          !receiveTopics.isEmpty, receiveTopics.allSatisfy(GalaxySSILinkProtocol.validTopic),
          let object = try JSONSerialization.jsonObject(with: wire) as? [String: Any] else { throw MqttRouteError.invalidPayload }
    // Longest catalog broker ID and largest permitted generation bound every later physical copy.
    let bound = try MqttDeliveryDispatch.packetBytes(topic: topic,
      payloadBytes: GalaxySSILinkProtocol.sealedWirePacketByteCount(payloadBytes: framedBytes(object, message: message)))
    return .init(peer: peer, message: message, receiveTopics: receiveTopics,
      secretFingerprint: MqttRouteProtocol.digest(Data(secret.utf8)), sizeBound: bound,
      encodeAttempt: { frame in
        guard frame.message == message else { throw MqttRouteError.invalidPayload }
        return try GalaxySSILinkProtocol.sealWirePacket(GalaxySSILinkProtocol.jsonData(frame.attach(to: object)), secret: secret)
      }, authorized: authorized)
  }
}
