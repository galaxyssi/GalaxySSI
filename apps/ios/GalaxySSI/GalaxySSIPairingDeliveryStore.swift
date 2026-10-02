import CoreFoundation
import CryptoKit
import Foundation

struct GalaxySSIPairingDelivery: Codable, Equatable {
  var controlId: String
  var kind: String
  var peer: String
  var fingerprint: String
  var topic: String
  var secret: String
  var payload: Data
  var payloadHash: String
  var sessionRecovery: Bool
  var expiresAt: Int64
  var attempts = 0
  var nextAttemptAt: Int64
  var desktopName = ""
  var clientRouteId = ""

  var isDesktop: Bool { kind == "galaxyssi_pairing_claim" }
  var desktopId: String { peer }
  var desktopFingerprint: String { fingerprint }
}

// Broker ACKs never retire pairing controls. Only authenticated peer evidence does.
final class GalaxySSIPairingDeliveryStore {
  static let storageKey = "galaxyssi.pairing.delivery.v1"
  static let maximumPending = 64
  static let maximumAttempts = 20
  private static let lock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private let localIdentity: String
  private let clock: () -> Int64

  private struct State: Codable {
    var localIdentity: String
    var pending: [GalaxySSIPairingDelivery] = []
    var accepted: [String: Int64] = [:]
  }

  init(
    localIdentity: String,
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
    clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.localIdentity = localIdentity
    self.defaults = defaults
    self.secrets = secrets
    self.clock = clock
  }

  func enqueue(
    payload: [String: Any], topic: String, secret: String, fingerprint: String,
    desktopId: String = "", desktopName: String = "", clientRouteId: String = ""
  ) -> Bool {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let now = clock()
    let kind = payload.string("type")
    let desktop = kind == "galaxyssi_pairing_claim"
    let peer = desktop ? desktopId : payload.string("to")
    let sentAt = (payload["time"] as? NSNumber)?.int64Value ?? 0
    let age: Int64 = desktop ? 9 * 60 * 1_000 : GalaxySSIPhoneContactControl.maximumAgeMillis
    guard !localIdentity.isEmpty, !peer.isEmpty, !fingerprint.isEmpty,
          GalaxySSILinkProtocol.validTopic(topic), GalaxySSILinkProtocol.validLinkSecret(secret),
          (desktop || GalaxySSIPhoneContactControl.Kind(rawValue: kind) != nil),
          kind != GalaxySSIPhoneContactControl.Kind.receipt.rawValue,
          sentAt > now - age, sentAt <= now + 60_000,
          desktop || UUID(uuidString: payload.string("control_id")) != nil,
          let data = try? GalaxySSILinkProtocol.jsonData(payload), data.count <= 128 * 1_024,
          let hash = Self.payloadHash(payload) else { return false }
    var state = load()
    let recovery = payload["session_recovery"] as? Bool ?? false
    if !desktop, state.pending.contains(where: {
      $0.peer == peer && $0.kind == kind && $0.topic == topic &&
        $0.fingerprint == fingerprint && $0.sessionRecovery == recovery
    }) { return true }
    if desktop {
      state.pending.removeAll { $0.isDesktop }
    } else if ["opaque_contact_accept", "opaque_contact_reject"].contains(kind) {
      state.pending.removeAll {
        $0.peer == peer && ["opaque_contact_accept", "opaque_contact_reject"].contains($0.kind)
      }
    }
    guard state.pending.count < Self.maximumPending else { return false }
    state.pending.append(GalaxySSIPairingDelivery(
      controlId: desktop ? UUID().uuidString : payload.string("control_id"), kind: kind,
      peer: peer, fingerprint: fingerprint, topic: topic, secret: secret, payload: data,
      payloadHash: hash, sessionRecovery: recovery, expiresAt: sentAt + age,
      nextAttemptAt: now, desktopName: desktopName, clientRouteId: clientRouteId
    ))
    return save(state)
  }

  func pending() -> [GalaxySSIPairingDelivery] {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    return load().pending
  }

  func takeDue() -> [GalaxySSIPairingDelivery] {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var state = load()
    let now = clock()
    let indices = state.pending.indices.filter {
      state.pending[$0].attempts < Self.maximumAttempts && state.pending[$0].nextAttemptAt <= now
    }.prefix(4)
    for index in indices {
      state.pending[index].attempts += 1
      let delay: Int64 = min(30_000, 2_000 << min(4, state.pending[index].attempts - 1))
      state.pending[index].nextAttemptAt = now + delay
    }
    guard save(state) else { return [] }
    return indices.map { state.pending[$0] }
  }

  func nextDelayMillis() -> Int64? {
    pending().filter { $0.attempts < Self.maximumAttempts }
      .map { max(250, $0.nextAttemptAt - clock()) }.min()
  }

  func acknowledge(peer: String, fingerprint: String, receipt: [String: Any]) -> Bool {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var state = load()
    guard let index = state.pending.firstIndex(where: {
      !$0.isDesktop && $0.peer == peer && $0.fingerprint == fingerprint &&
        $0.controlId == receipt.string("ack_control_id") && $0.payloadHash == receipt.string("ack_payload_hash")
    }) else { return false }
    state.pending.remove(at: index)
    return save(state)
  }

  func discard(controlId: String) {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    var state = load()
    state.pending.removeAll { $0.controlId == controlId }
    _ = save(state)
  }

  func accepted(_ payload: [String: Any]) -> Bool {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    guard let key = acceptedKey(payload) else { return false }
    return load().accepted[key] != nil
  }

  func markAccepted(_ payload: [String: Any]) -> Bool {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    guard let key = acceptedKey(payload) else { return false }
    var state = load()
    state.accepted[key] = clock() + GalaxySSIPhoneContactControl.maximumAgeMillis
    state.accepted = Dictionary(uniqueKeysWithValues: state.accepted.sorted { $0.value > $1.value }.prefix(256).map { ($0.key, $0.value) })
    return save(state)
  }

  private func acceptedKey(_ payload: [String: Any]) -> String? {
    guard let hash = Self.payloadHash(payload), UUID(uuidString: payload.string("control_id")) != nil else { return nil }
    return payload.string("from") + ":" + payload.string("control_id") + ":" + hash
  }

  private func load() -> State {
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: Self.storageKey, secrets: secrets),
          var state = try? JSONDecoder().decode(State.self, from: data), state.localIdentity == localIdentity else {
      return State(localIdentity: localIdentity)
    }
    state.pending = Array(state.pending.filter { $0.expiresAt > clock() }.prefix(Self.maximumPending))
    state.accepted = state.accepted.filter { $0.value > clock() }
    return state
  }

  private func save(_ state: State) -> Bool {
    guard let data = try? JSONEncoder().encode(state) else { return false }
    return GalaxySSIEncryptedUserDefaultsStore.write(data, defaults: defaults, key: Self.storageKey, secrets: secrets)
  }

  static func payloadHash(_ payload: [String: Any]) -> String? {
    guard let canonical = canonical(payload) else { return nil }
    return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  // Match PhonePairingDeliveryLedger, including Android JSONObject.quote's escaped slash.
  private static func canonical(_ value: Any) -> String? {
    if let object = value as? [String: Any] {
      var fields: [String] = []
      for key in object.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
        guard let encoded = canonical(object[key]!) else { return nil }
        fields.append(quote(key) + ":" + encoded)
      }
      return "{" + fields.joined(separator: ",") + "}"
    }
    if let array = value as? [Any] {
      let encoded = array.compactMap(canonical)
      return encoded.count == array.count ? "[" + encoded.joined(separator: ",") + "]" : nil
    }
    if let string = value as? String { return quote(string) }
    if value is NSNull { return "null" }
    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
      // Pairing schemas contain integer counters/timestamps, never floating point values.
      guard !["f", "d"].contains(String(cString: number.objCType)) else { return nil }
      return number.stringValue
    }
    return nil
  }

  private static func quote(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
      switch scalar.value {
      case 0x22: result += "\\\""
      case 0x5c: result += "\\\\"
      case 0x2f: result += "\\/"
      case 0x08: result += "\\b"
      case 0x0c: result += "\\f"
      case 0x0a: result += "\\n"
      case 0x0d: result += "\\r"
      case 0x09: result += "\\t"
      case 0..<0x20: result += String(format: "\\u%04x", scalar.value)
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result + "\""
  }
}
