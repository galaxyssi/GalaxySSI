import CryptoKit
import Foundation
import Security

struct PairingQRCode {
  var desktopId: String
  var desktopName: String
  var desktopFingerprint: String
  var serverRouteId: String
  var pairingTopic: String
  var pairingToken: String
  var pairingSecret: Data
  var access: PairingAccess
  var controlAuthorizationToken: String
  var raw: [String: Any]
}

enum SignalASILinkProtocol {
  static let name = "signalasi-link"
  static let version = 1
  static let topicRoot = "signalasichat/v1"
  static let accessContract = "signalasi.pairing-access/1.0"
  static let accessRestricted = "restricted"
  static let accessDesktopExecutor = "desktop_executor"
  static let scopeAgentChat = "agent.chat"
  static let scopeExplicitAttachments = "agent.attachments.explicit"
  static let scopeTaskWorkspace = "desktop.task_workspace"
  static let scopeDesktopExecutor = "desktop.executor.full"
  static let scopeDesktopControl = "desktop.control"
  static let scopeDesktopNativeTools = "desktop.native_tools"
  static let scopeDesktopExternalFiles = "desktop.files.external"
  static let capabilityManifestVersion = 2

  private static let maxQRAgeMilliseconds: Double = 10 * 60 * 1000
  private static let maxClockSkewMilliseconds: Double = 5 * 60 * 1000
  private static let defaultMessageTTLMilliseconds: Double = 7 * 24 * 60 * 60 * 1000
  private static let maxTextBytes = 128 * 1024
  private static let maxEnvelopeBytes = 512 * 1024
  private static let routePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{22}$")

  static func newRouteId() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw SignalASIError.invalidPayload("Unable to create a secure route ID.")
    }
    return Data(bytes).base64URLEncodedString()
  }

  static func validRouteId(_ value: String) -> Bool {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return routePattern.firstMatch(in: value, range: range) != nil
  }

  static func needsCapabilityManifest(_ link: ServerLink) -> Bool {
    link.capabilityManifestVersion < capabilityManifestVersion
  }

  static func connectorStatusRequestPayload(
    link: ServerLink,
    contactId: String = "system",
    forceCapabilityManifest: Bool = false,
    now: Date = Date()
  ) -> [String: Any] {
    [
      "type": "connector_status_request",
      "contact_id": contactId,
      "desktop_id": link.desktopId,
      "capability_manifest_version": link.capabilityManifestVersion,
      "request_capability_manifest": forceCapabilityManifest || needsCapabilityManifest(link),
      "time": Int64(now.timeIntervalSince1970 * 1000)
    ]
  }

  static func decodePairingQRCode(from text: String, now: Date = Date()) throws -> PairingQRCode {
    let object = try SignalASIQRCodePayload.decodeObject(from: text, label: "Pairing QR")
    return try validatePairingQRCode(object, now: now)
  }

  static func validatePairingQRCode(_ qr: [String: Any], now: Date = Date()) throws -> PairingQRCode {
    guard qr.string("type") == "signalasi_verify" else {
      throw SignalASIError.invalidPairingQRCode("type must be signalasi_verify.")
    }
    guard qr.string("protocol") == name, qr.int("version") == version else {
      throw SignalASIError.invalidPairingQRCode("protocol version mismatch.")
    }
    guard qr.string("role") == "server" else {
      throw SignalASIError.invalidPairingQRCode("role must be server.")
    }

    let serverRouteId = qr.string("server_route_id")
    guard validRouteId(serverRouteId) else {
      throw SignalASIError.invalidPairingQRCode("server route ID is malformed.")
    }
    let expectedTopic = "\(topicRoot)/\(serverRouteId)/pair"
    guard qr.string("pairing_topic") == expectedTopic else {
      throw SignalASIError.invalidPairingQRCode("pairing topic does not match route.")
    }
    guard qr.string("pairing_token").count >= 32 else {
      throw SignalASIError.invalidPairingQRCode("pairing token is too short.")
    }
    guard let pairingSecret = Data(base64URLEncoded: qr.string("pairing_secret")),
          pairingSecret.count == 32 else {
      throw SignalASIError.invalidPairingQRCode("pairing secret must be 32 bytes.")
    }
    guard !qr.string("desktop_id").isEmpty else {
      throw SignalASIError.invalidPairingQRCode("desktop ID is missing.")
    }
    guard qr.string("identity_key_sha256").count == 64 else {
      throw SignalASIError.invalidPairingQRCode("desktop identity fingerprint is malformed.")
    }
    guard let access = pairingAccess(from: qr.dictionary("pairing_access")) else {
      throw SignalASIError.invalidPairingQRCode("pairing access grant is invalid.")
    }

    let createdAt = qr.double("created_at")
    let createdAtMilliseconds = createdAt < 10_000_000_000 ? createdAt * 1000 : createdAt
    let nowMilliseconds = now.timeIntervalSince1970 * 1000
    guard createdAtMilliseconds > 0,
          abs(nowMilliseconds - createdAtMilliseconds) <= maxQRAgeMilliseconds else {
      throw SignalASIError.invalidPairingQRCode("pairing QR has expired.")
    }

    let authorizationToken = qr.dictionary("desktop_control_authorization")?.string("token") ?? ""
    return PairingQRCode(
      desktopId: qr.string("desktop_id"),
      desktopName: qr.string("desktop_name").ifBlank("SignalASI Desktop"),
      desktopFingerprint: qr.string("identity_key_sha256"),
      serverRouteId: serverRouteId,
      pairingTopic: expectedTopic,
      pairingToken: qr.string("pairing_token"),
      pairingSecret: pairingSecret,
      access: access,
      controlAuthorizationToken: authorizationToken,
      raw: qr
    )
  }

  static func pairingAccess(from object: [String: Any]?) -> PairingAccess? {
    guard let object else { return nil }
    guard object.string("contract_version") == accessContract,
          object.int("version") == 1 else {
      return nil
    }
    let profile = object.string("profile")
    guard [accessRestricted, accessDesktopExecutor].contains(profile) else {
      return nil
    }
    let scopes = Set(object.stringArray("scopes").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    let restrictedScopes: Set<String> = [scopeAgentChat, scopeExplicitAttachments, scopeTaskWorkspace]
    let executorScopes = restrictedScopes.union([
      scopeDesktopExecutor,
      scopeDesktopControl,
      scopeDesktopNativeTools,
      scopeDesktopExternalFiles
    ])
    guard scopes.isSuperset(of: restrictedScopes) else { return nil }
    if profile == accessDesktopExecutor, !scopes.isSuperset(of: executorScopes) {
      return nil
    }
    if profile == accessRestricted, !scopes.intersection(executorScopes.subtracting(restrictedScopes)).isEmpty {
      return nil
    }
    return PairingAccess(profile: profile, scopes: scopes)
  }

  static func makeEnvelope(
    payload: [String: Any],
    sourceId: String,
    targetId: String,
    now: Date = Date()
  ) throws -> [String: Any] {
    if let content = payload["content"] as? String,
       content.data(using: .utf8)?.count ?? 0 > maxTextBytes {
      throw SignalASIError.invalidPayload("text exceeds Link limit.")
    }
    let messageId = (payload["message_id"] as? String).ifBlank(UUID().uuidString)
    let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1000)
    let expiresAt = nowMilliseconds + Int64(defaultMessageTTLMilliseconds)
    var envelope: [String: Any] = [
      "protocol": name,
      "version": version,
      "message_id": messageId,
      "conversation_id": (payload["conversation_id"] as? String).ifBlank(""),
      "source_id": sourceId,
      "target_id": targetId,
      "reply_to": (payload["reply_to"] as? String).ifBlank(""),
      "sent_at": nowMilliseconds,
      "expires_at": expiresAt,
      "payload": payload
    ]
    guard try jsonData(envelope).count <= maxEnvelopeBytes else {
      throw SignalASIError.invalidPayload("envelope exceeds Link limit.")
    }
    envelope["message_id"] = messageId
    return envelope
  }

  static func unwrapEnvelope(_ envelope: [String: Any], now: Date = Date()) -> [String: Any]? {
    guard envelope.string("protocol") == name, envelope.int("version") == version else {
      return nil
    }
    guard (try? jsonData(envelope).count) ?? Int.max <= maxEnvelopeBytes else {
      return nil
    }
    guard UUID(uuidString: envelope.string("message_id")) != nil else {
      return nil
    }
    guard !envelope.string("source_id").isEmpty, !envelope.string("target_id").isEmpty else {
      return nil
    }
    let nowMilliseconds = now.timeIntervalSince1970 * 1000
    let sentAt = envelope.double("sent_at")
    let expiresAt = envelope.double("expires_at")
    guard sentAt > 0,
          sentAt - nowMilliseconds <= maxClockSkewMilliseconds,
          expiresAt > sentAt,
          nowMilliseconds <= expiresAt,
          var payload = envelope.dictionary("payload") else {
      return nil
    }
    payload["message_id"] = envelope.string("message_id")
    if payload.string("reply_to").isEmpty {
      payload["reply_to"] = envelope.string("reply_to")
    }
    if payload.string("conversation_id").isEmpty {
      payload["conversation_id"] = envelope.string("conversation_id")
    }
    return payload
  }

  static func encryptPairingClaim(claim: [String: Any], pairing: PairingQRCode) throws -> [String: Any] {
    let claimData = try jsonData(claim)
    var nonceBytes = [UInt8](repeating: 0, count: 12)
    let status = SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes)
    guard status == errSecSuccess else {
      throw SignalASIError.invalidPayload("Unable to create pairing nonce.")
    }
    let nonceData = Data(nonceBytes)
    let key = SymmetricKey(data: pairing.pairingSecret)
    let aad = "\(name)|\(version)|\(pairing.pairingToken)|\(pairing.serverRouteId)".data(using: .utf8)!
    let sealed = try AES.GCM.seal(
      claimData,
      using: key,
      nonce: AES.GCM.Nonce(data: nonceData),
      authenticating: aad
    )
    var ciphertext = sealed.ciphertext
    ciphertext.append(sealed.tag)
    return [
      "type": "signalasi_pairing_ciphertext",
      "protocol": name,
      "version": version,
      "pairing_token": pairing.pairingToken,
      "server_route_id": pairing.serverRouteId,
      "nonce": nonceData.base64URLEncodedString(),
      "ciphertext": ciphertext.base64URLEncodedString()
    ]
  }

  static func jsonData(_ object: Any) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw SignalASIError.invalidPayload("object is not JSON encodable.")
    }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }
}

private extension String? {
  func ifBlank(_ fallback: String) -> String {
    guard let value = self, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return fallback
    }
    return value
  }
}

extension String {
  func ifBlank(_ fallback: String) -> String {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
  }
}

extension Data {
  init?(base64URLEncoded value: String) {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padding = (4 - base64.count % 4) % 4
    if padding > 0 {
      base64.append(String(repeating: "=", count: padding))
    }
    self.init(base64Encoded: base64)
  }

  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  func hexString() -> String {
    map { String(format: "%02x", $0) }.joined()
  }
}

extension Dictionary where Key == String, Value == Any {
  func string(_ key: String) -> String {
    if let value = self[key] as? String { return value }
    if let value = self[key] as? NSNumber { return value.stringValue }
    return ""
  }

  func int(_ key: String) -> Int {
    if let value = self[key] as? Int { return value }
    if let value = self[key] as? NSNumber { return value.intValue }
    if let value = self[key] as? String { return Int(value) ?? 0 }
    return 0
  }

  func double(_ key: String) -> Double {
    if let value = self[key] as? Double { return value }
    if let value = self[key] as? Int { return Double(value) }
    if let value = self[key] as? NSNumber { return value.doubleValue }
    if let value = self[key] as? String { return Double(value) ?? 0 }
    return 0
  }

  func dictionary(_ key: String) -> [String: Any]? {
    self[key] as? [String: Any]
  }

  func stringArray(_ key: String) -> [String] {
    self[key] as? [String] ?? []
  }
}
