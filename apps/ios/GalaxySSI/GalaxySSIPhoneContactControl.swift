import Foundation

struct GalaxySSIPhoneContactControl {
  enum Kind: String {
    case request = "opaque_contact_claim"
    case bundle = "opaque_contact_confirm"
    case refresh = "opaque_bundle_refresh"
    case approval = "opaque_contact_accept"
    case rejection = "opaque_contact_reject"
  }

  struct ValidatedPayload {
    let kind: Kind
    let controlId: String
    let contactCard: [String: Any]
    let signalBundle: [String: Any]
    let pairingToken: String
  }

  static let maximumAgeMillis: Int64 = 10 * 60 * 1_000
  private static let maximumFutureSkewMillis: Int64 = 60_000

  static func makePayload(
    kind: Kind,
    targetCard: [String: Any],
    localCard: [String: Any],
    localSignalIdentity: GalaxySSISignalIdentity,
    pairingToken: String = "",
    controlId: String = UUID().uuidString,
    now: Date = Date()
  ) -> [String: Any]? {
    guard (try? GalaxySSIContactExchange.validateSignedPhoneContactCard(targetCard)) != nil,
          (try? GalaxySSIContactExchange.validateSignedPhoneContactCard(localCard)) != nil,
          let bundle = localSignalIdentity.bundle,
          localSignalIdentity.name == localCard.string("galaxyssi_id"),
          localSignalIdentity.name != targetCard.string("galaxyssi_id") else {
      return nil
    }
    if kind == .request, !GalaxySSILinkProtocol.validLinkSecret(pairingToken) {
      return nil
    }
    var payload: [String: Any] = [
      "type": kind.rawValue,
      "version": GalaxySSILinkProtocol.version,
      "control_id": controlId,
      "from": localSignalIdentity.name,
      "to": targetCard.string("galaxyssi_id"),
      "contact_card": localCard,
      "signal_bundle": bundle,
      "time": Int64(now.timeIntervalSince1970 * 1_000)
    ]
    if kind == .request { payload["pairing_token"] = pairingToken }
    return payload
  }

  static func validate(
    _ payload: [String: Any],
    addressedTo localGalaxySSIId: String,
    now: Date = Date()
  ) -> ValidatedPayload? {
    guard let kind = Kind(rawValue: payload.string("type")),
          payload.int("version") == GalaxySSILinkProtocol.version,
          UUID(uuidString: payload.string("control_id")) != nil,
          let card = payload.dictionary("contact_card"),
          let bundle = payload.dictionary("signal_bundle"),
          payload.string("from") == card.string("galaxyssi_id"),
          payload.string("to") == localGalaxySSIId,
          GalaxySSISignalEngine.bundleIdentityFingerprint(bundle)?
            .caseInsensitiveCompare(card.string("identity_fingerprint")) == .orderedSame else {
      return nil
    }
    let sentAt = (payload["time"] as? NSNumber)?.int64Value ?? 0
    let nowMillis = Int64(now.timeIntervalSince1970 * 1_000)
    guard sentAt >= nowMillis - maximumAgeMillis,
          sentAt <= nowMillis + maximumFutureSkewMillis,
          (try? GalaxySSIContactExchange.validateSignedPhoneContactCard(card)) != nil else {
      return nil
    }
    let token = payload.string("pairing_token")
    guard kind != .request || GalaxySSILinkProtocol.validLinkSecret(token) else { return nil }
    return ValidatedPayload(
      kind: kind,
      controlId: payload.string("control_id"),
      contactCard: card,
      signalBundle: bundle,
      pairingToken: token
    )
  }
}

enum GalaxySSIPhoneContactBundlePolicy {
  static func replacesExistingSession(_ kind: GalaxySSIPhoneContactControl.Kind) -> Bool {
    kind == .bundle || kind == .refresh
  }
}

final class GalaxySSIPeerSessionRecoveryGate {
  static let requestCooldownMillis: Int64 = 60_000

  private let lock = NSLock()
  private var requestedAtByContactId: [String: Int64] = [:]

  func begin(contactId: String, nowMillis: Int64) -> Bool {
    let cleanContactId = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanContactId.isEmpty else { return false }
    lock.lock()
    defer { lock.unlock() }
    if let previous = requestedAtByContactId[cleanContactId],
       nowMillis - previous < Self.requestCooldownMillis {
      return false
    }
    requestedAtByContactId[cleanContactId] = nowMillis
    return true
  }

  func requestFailed(contactId: String) {
    update(contactId: contactId, remove: true)
  }

  func sessionHealthy(contactId: String) {
    update(contactId: contactId, remove: true)
  }

  private func update(contactId: String, remove: Bool) {
    let cleanContactId = contactId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanContactId.isEmpty else { return }
    lock.lock()
    if remove { requestedAtByContactId.removeValue(forKey: cleanContactId) }
    lock.unlock()
  }
}
