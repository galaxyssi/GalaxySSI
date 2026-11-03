import Foundation

// Trusted local send intent. Timestamps/retry state are deliberately excluded from its immutable hash.
struct MqttSignalSendRequest: Codable {
  let identity: MqttBusinessIdentity
  let messageID: String
  let remoteName: String
  let deviceID: UInt32
  let topic: String
  let clientRouteID: String?
  let traffic: MqttMultipathPolicy.Traffic
  let payload: Data
  let requiresValidatedNetwork: Bool
  let attachmentDependencies: [String]
  let attachmentTransferID: String
  let sourceMessageID: String
  let contactID: String
  let trustedBackgroundCognitionAuthorized: Bool

  init(identity: MqttBusinessIdentity, payload: [String: Any], remoteName: String, deviceID: UInt32 = 1,
       topic: String, clientRouteID: String? = nil, traffic: MqttMultipathPolicy.Traffic = .message,
       requiresValidatedNetwork: Bool = false, attachmentDependencies: [String] = [],
       attachmentTransferID: String = "", sourceMessageID: String = "", contactID: String = "",
       trustedBackgroundCognitionAuthorized: Bool = false) throws {
    self.identity = identity
    messageID = try MqttDeliveryEnvelope.checkedText(payload["message_id"])
    self.remoteName = remoteName; self.deviceID = deviceID; self.topic = topic; self.clientRouteID = clientRouteID
    self.traffic = traffic
    self.payload = try MqttBusinessStorage.payload(payload)
    self.requiresValidatedNetwork = requiresValidatedNetwork
    self.attachmentDependencies = Array(Set(attachmentDependencies)).sorted()
    self.attachmentTransferID = attachmentTransferID
    self.sourceMessageID = sourceMessageID; self.contactID = contactID
    self.trustedBackgroundCognitionAuthorized = trustedBackgroundCognitionAuthorized
    try validate()
  }

  func validate() throws {
    try identity.validate()
    _ = try identity.key(messageID: messageID)
    _ = try MqttDeliveryEnvelope.checkedText(remoteName, maximum: 512)
    guard deviceID > 0, GalaxySSILinkProtocol.validTopic(topic),
          clientRouteID.map(GalaxySSILinkProtocol.validRouteId) ?? true,
          attachmentDependencies.count <= 64, attachmentDependencies == Array(Set(attachmentDependencies)).sorted(),
          attachmentDependencies.allSatisfy({ MqttRouteProtocol.hex($0, count: 64) }),
          attachmentTransferID.isEmpty || MqttRouteProtocol.hex(attachmentTransferID, count: 64),
          payload.count <= MqttBusinessStorage.maximumPayloadBytes else { throw MqttRouteError.invalidPayload }
    for text in [sourceMessageID, contactID] where !text.isEmpty {
      _ = try MqttDeliveryEnvelope.checkedText(text, maximum: 512)
    }
    let object = try applicationPayload()
    guard object["message_id"] as? String == messageID, object["_link_rx_key"] == nil,
          object[MqttDeliveryEnvelope.field] == nil,
          !GalaxySSITransportPrivacyPolicy.isLocalOnly(object,
            trustedBackgroundCognitionAuthorized: trustedBackgroundCognitionAuthorized),
          try MqttBusinessStorage.payload(object) == payload else { throw MqttRouteError.invalidPayload }
  }

  func applicationPayload() throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw MqttRouteError.invalidPayload }
    return value
  }

  func digest() throws -> String {
    try validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return MqttRouteProtocol.digest(try encoder.encode(self))
  }

  func pendingMessage(wire: String, now: Date) -> PendingLinkMessage {
    PendingLinkMessage(messageId: messageID, topic: topic, wirePayload: wire, status: "queued", attempts: 0,
      nextAttemptAt: now, createdAt: now, updatedAt: now, requiresValidatedNetwork: requiresValidatedNetwork,
      blockedByAttachmentTransferIds: attachmentDependencies, attachmentTransferId: attachmentTransferID,
      clientSourceMessageId: sourceMessageID, contactId: contactID)
  }

  func matches(_ message: PendingLinkMessage) -> Bool {
    message.messageId == messageID && message.topic == topic && message.wirePayloadFile == nil &&
      message.requiresValidatedNetwork == requiresValidatedNetwork && message.attachmentTransferId == attachmentTransferID &&
      message.clientSourceMessageId == sourceMessageID && message.contactId == contactID &&
      Set(message.blockedByAttachmentTransferIds).isSubset(of: Set(attachmentDependencies))
  }
}
