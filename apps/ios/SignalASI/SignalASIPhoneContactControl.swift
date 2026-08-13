import Foundation

struct SignalASIPhoneContactControl {
  enum Kind: String {
    case request = "signalasi_contact_request"
    case bundle = "signalasi_contact_bundle"
  }

  struct ValidatedPayload {
    let kind: Kind
    let controlId: String
    let contactCard: [String: Any]
    let signalBundle: [String: Any]
    let replyTopic: String
  }

  static let maximumAgeMillis: Int64 = 24 * 60 * 60 * 1_000
  private static let maximumFutureSkewMillis: Int64 = 60_000
  private static let signedFields = [
    "type",
    "version",
    "control_id",
    "from",
    "to",
    "reply_topic",
    "contact_card_signature",
    "bundle_identity_fingerprint",
    "time"
  ]

  static func inboxTopic(routeId: String) -> String? {
    guard SignalASILinkProtocol.validRouteId(routeId) else { return nil }
    return "\(SignalASILinkProtocol.topicRoot)/contact/\(routeId)/inbox"
  }

  static func retainedTopic(inboxTopic: String, controlId: String) -> String? {
    let cleanInbox = inboxTopic.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanControlId = controlId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanInbox.isEmpty, !cleanControlId.isEmpty, !cleanControlId.contains("/") else {
      return nil
    }
    return "\(cleanInbox)/\(cleanControlId)"
  }

  static func makePayload(
    kind: Kind,
    targetCard: [String: Any],
    localCard: [String: Any],
    localSignalIdentity: SignalASISignalIdentity,
    replyTopic: String,
    controlId: String = UUID().uuidString,
    now: Date = Date(),
    sign: (Data) -> String?
  ) -> [String: Any]? {
    guard (try? SignalASIContactExchange.validateSignedPhoneContactCard(targetCard)) != nil,
          (try? SignalASIContactExchange.validateSignedPhoneContactCard(localCard)) != nil,
          !targetCard.string("signature").isEmpty else {
      return nil
    }
    let localId = localSignalIdentity.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let targetId = targetCard.string("signalasi_id")
    let localSignature = localCard.string("signature")
    let cleanReplyTopic = replyTopic.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !localId.isEmpty,
          localId != targetId,
          !targetId.isEmpty,
          !localSignature.isEmpty,
          !cleanReplyTopic.isEmpty,
          let bundle = localSignalIdentity.bundle,
          let bundleFingerprint = SignalASISignalEngine.bundleIdentityFingerprint(bundle),
          bundleFingerprint.caseInsensitiveCompare(localCard.string("identity_fingerprint")) == .orderedSame else {
      return nil
    }
    var payload: [String: Any] = [
      "type": kind.rawValue,
      "version": SignalASIContactExchange.version,
      "control_id": controlId,
      "from": localId,
      "to": targetId,
      "reply_topic": cleanReplyTopic,
      "contact_card": localCard,
      "contact_card_signature": localSignature,
      "signal_bundle": bundle,
      "bundle_identity_fingerprint": bundleFingerprint,
      "time": Int64(now.timeIntervalSince1970 * 1_000)
    ]
    guard let signature = sign(canonicalBytes(payload)), !signature.isEmpty else {
      return nil
    }
    payload["control_signature"] = signature
    return payload
  }

  static func validate(
    _ payload: [String: Any],
    addressedTo localSignalASIId: String,
    now: Date = Date()
  ) -> ValidatedPayload? {
    guard let kind = Kind(rawValue: payload.string("type")),
          payload.int("version") == SignalASIContactExchange.version,
          let card = payload.dictionary("contact_card"),
          let bundle = payload.dictionary("signal_bundle") else {
      return nil
    }
    let controlId = payload.string("control_id")
    let localId = localSignalASIId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cardSignature = card.string("signature")
    let bundleFingerprint = payload.string("bundle_identity_fingerprint")
    let controlSignature = payload.string("control_signature")
    let sentAt = payload.int64("time")
    let nowMillis = Int64(now.timeIntervalSince1970 * 1_000)
    guard !localId.isEmpty,
          !controlId.isEmpty,
          payload.string("from") == card.string("signalasi_id"),
          payload.string("to") == localId,
          payload.string("reply_topic") == card.string("mqtt_inbox_topic"),
          payload.string("contact_card_signature") == cardSignature,
          !cardSignature.isEmpty,
          bundleFingerprint.caseInsensitiveCompare(card.string("identity_fingerprint")) == .orderedSame,
          SignalASISignalEngine.bundleIdentityFingerprint(bundle)?.caseInsensitiveCompare(bundleFingerprint) == .orderedSame,
          controlSignature.count >= 40,
          controlSignature.count <= 256,
          sentAt >= nowMillis - maximumAgeMillis,
          sentAt <= nowMillis + maximumFutureSkewMillis else {
      return nil
    }
    do {
      try SignalASIContactExchange.validateSignedPhoneContactCard(card)
    } catch {
      return nil
    }
    guard SignalASISignalEngine.verifyContactCard(
      publicKey: card.string("identity_public_key"),
      payload: canonicalBytes(payload),
      signature: controlSignature
    ) else {
      return nil
    }
    return ValidatedPayload(
      kind: kind,
      controlId: controlId,
      contactCard: card,
      signalBundle: bundle,
      replyTopic: payload.string("reply_topic")
    )
  }

  static func canonicalBytes(_ payload: [String: Any]) -> Data {
    let canonical = signedFields.map { key -> String in
      let value = String(describing: payload[key] ?? "")
      return "\(key.utf16.count):\(key)\(value.utf16.count):\(value)|"
    }.joined()
    return Data(canonical.utf8)
  }
}
