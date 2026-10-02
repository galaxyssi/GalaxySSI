import Foundation

// Pair-AEAD ingress only. Signal-encrypted application delivery_ack replay is owned by the inbox consumer.
final class MqttBusinessReceipts {
  private let routes: MqttPeerRoutes
  private let outbox: MqttBusinessOutbox
  private let dispatcher: MqttDeliveryDispatch
  private let now: () -> Date

  init(routes: MqttPeerRoutes, outbox: MqttBusinessOutbox, dispatcher: MqttDeliveryDispatch,
       now: @escaping () -> Date = Date.init) {
    self.routes = routes; self.outbox = outbox; self.dispatcher = dispatcher; self.now = now
  }

  func accept(_ packet: MqttPeerRoutes.VerifiedPacket) async throws -> MqttDeliveryCompletions.Event? {
    guard packet.payload["type"] as? String == MqttDeliveryEnvelope.receiptType else { return nil }
    let frame = try routes.withCurrentIdentity(packet) { identity in
      try MqttDeliveryEnvelope.parseVerifiedReceipt(packet.payload, originalSender: identity.local, originalReceiver: identity.remote)
    }
    var completion: MqttDeliveryCompletions.Event?
    let commit = {
      completion = try self.routes.withCurrentIdentity(packet) { identity in
        if let pending = try self.outbox.entry(identity: identity, messageID: frame.message.messageID) {
          guard pending.isPrepared, pending.wireHash == frame.message.contentHash,
                pending.traffic == frame.message.traffic else { throw MqttRouteError.unsolicitedAcknowledgement }
          _ = try self.outbox.acknowledgeVerified(identity: identity, messageID: frame.message.messageID,
            wireHash: frame.message.contentHash, now: self.now())
        }
        guard let saved = try self.outbox.completions.event(identity: identity, messageID: frame.message.messageID),
              saved.wireHash == frame.message.contentHash, saved.traffic == frame.message.traffic else {
          throw MqttRouteError.unsolicitedAcknowledgement
        }
        return saved
      }
    }
    if try await dispatcher.acceptVerifiedReceipt(peer: packet.scope, frame: frame, commit: commit) { return completion }
    // A restart/expired observation may lose attempt attribution while the durable message remains.
    // Cancel matching logical copies without inventing an RTT sample for that unknown physical attempt.
    if try await dispatcher.acceptVerifiedMessage(peer: packet.scope, messageID: frame.message.messageID,
      contentHash: frame.message.contentHash, commit: commit) { return completion }
    try commit()
    return completion
  }
}
