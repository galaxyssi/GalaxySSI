import Foundation

enum SignalASIContactExchange {
  static let contactType = "signalasi_contact"
  static let hermesContactType = "hermes_contact"
  static let verifyType = "signalasi_verify"
  static let version = 1

  static func makeContactQRText(
    profile: SignalASIProfile,
    serverLinks: [ServerLink],
    now: Date = Date()
  ) throws -> String {
    let payload = makeContactPayload(profile: profile, serverLinks: serverLinks, now: now)
    let data = try SignalASILinkProtocol.jsonData(payload)
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  static func makeContactPayload(
    profile: SignalASIProfile,
    serverLinks: [ServerLink],
    now: Date = Date()
  ) -> [String: Any] {
    let inboxTopic = localInboxTopic(serverLinks: serverLinks)
    return [
      "type": contactType,
      "version": version,
      "name": profile.name.ifBlank("Me"),
      "signalasi_id": profile.signalASIId,
      "identity_public_key": profile.identityPublicKey,
      "identity_fingerprint": profile.identityFingerprint,
      "mqtt_topic": inboxTopic,
      "mqtt_inbox_topic": inboxTopic,
      "signal_bundle_ref": "mqtt:\(inboxTopic):\(profile.signalASIId)",
      "device_id": "ios-\(profile.identityFingerprint.prefix(16))",
      "created_at": Int64(now.timeIntervalSince1970 * 1000)
    ]
  }

  static func importContactQRCode(_ contents: String, now: Date = Date()) throws -> SignalASIFriendRequest {
    guard let data = contents.data(using: .utf8) else {
      throw SignalASIError.invalidPayload("Contact QR text is not UTF-8.")
    }
    let raw = try JSONSerialization.jsonObject(with: data, options: [])
    guard let object = raw as? [String: Any] else {
      throw SignalASIError.invalidPayload("Contact QR root must be a JSON object.")
    }
    let type = object.string("type")
    guard [contactType, hermesContactType, verifyType].contains(type) else {
      throw SignalASIError.invalidPayload("Contact QR type is not supported.")
    }
    let fingerprint = object.string("identity_fingerprint").ifBlank(object.string("identity_key_sha256"))
    let publicKey = object.string("identity_public_key").ifBlank(object.string("identity_key"))
    guard !fingerprint.isEmpty, !publicKey.isEmpty else {
      throw SignalASIError.invalidPayload("Contact QR is missing identity material.")
    }
    let signalASIId = object.string("signalasi_id")
      .ifBlank(object.string("hermes_id"))
      .ifBlank("signalasi:\(fingerprint.prefix(16))")
    let mqttTopic = object.string("mqtt_topic")
      .ifBlank(object.string("mqtt_inbox_topic"))
      .ifBlank(object.string("mqtt_recv_topic"))
    let name = object.string("name").ifBlank(type == verifyType ? "Hermes" : "Friend")
    let requestType = type == verifyType ? "hermes" : object.string("contact_type").ifBlank("person")
    return SignalASIFriendRequest(
      id: "req_\(Int64(now.timeIntervalSince1970 * 1000))",
      signalASIId: signalASIId,
      name: name,
      type: requestType,
      identityPublicKey: publicKey,
      identityFingerprint: fingerprint,
      mqttTopic: mqttTopic,
      mqttInboxTopic: mqttTopic,
      signalBundleRef: object.string("signal_bundle_ref"),
      source: "qr",
      createdAt: now
    )
  }

  static func localInboxTopic(serverLinks: [ServerLink]) -> String {
    serverLinks.first { $0.paired }?.routes.downTopic ?? ""
  }
}
