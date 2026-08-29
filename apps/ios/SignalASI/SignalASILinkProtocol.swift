import CryptoKit
import Foundation
import Security

struct PairingQRCode {
  var desktopId: String
  var desktopName: String
  var desktopFingerprint: String
  var pairingTopic: String
  var pairingToken: String
  var pairingSecret: Data
  var access: PairingAccess
  var controlAuthorizationToken: String
  var raw: [String: Any]
}

enum SignalASILinkProtocol {
  static let name = "signalasi-link"
  static let version = 2
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
  private static let maxOpaquePacketBytes = 1024 * 1024
  private static let topicEpochSeconds: Int64 = 6 * 60 * 60
  private static let topicReceiveWindow: Int64 = 1
  private static let routePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{22}$")
  private static let secretPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{43}$")
  private static let wireBuckets = [
    1_024,
    16 * 1_024,
    64 * 1_024,
    128 * 1_024,
    256 * 1_024,
    512 * 1_024
  ]

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

  static func newLinkSecret() throws -> String {
    try secureRandomData(count: 32).base64URLEncodedString()
  }

  static func validLinkSecret(_ value: String) -> Bool {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return secretPattern.firstMatch(in: value, range: range) != nil
  }

  static func validTopic(_ value: String) -> Bool {
    validLinkSecret(value)
  }

  static func pairingTopic(secret: String) -> String {
    guard let secretData = Data(base64URLEncoded: secret), secretData.count == 32 else { return "" }
    return kdf(secret: secretData, label: Data("rendezvous-topic".utf8)).base64URLEncodedString()
  }

  static func deriveLinkSecret(
    pairingSecret: String,
    firstFingerprint: String,
    secondFingerprint: String
  ) throws -> String {
    guard let secretData = Data(base64URLEncoded: pairingSecret), secretData.count == 32 else {
      throw SignalASIError.invalidPayload("Pairing secret is malformed.")
    }
    let identities = [firstFingerprint, secondFingerprint].sorted()
    guard identities.allSatisfy({ !$0.isEmpty }) else {
      throw SignalASIError.invalidPayload("Both identity fingerprints are required.")
    }
    let binding = Data(("relationship\0" + identities.joined(separator: "\0")).utf8)
    return kdf(secret: secretData, label: binding).base64URLEncodedString()
  }

  static func deriveIdentityBoundLinkSecret(
    sharedSecret: Data,
    firstFingerprint: String,
    secondFingerprint: String
  ) throws -> String {
    guard sharedSecret.count >= 32 else {
      throw SignalASIError.invalidPayload("Signal identity agreement is too short.")
    }
    let binding = try canonicalPhoneIdentityBinding(firstFingerprint, secondFingerprint)
    let label = Data(("signalasi-phone-link-v3\0" + binding).utf8)
    let code = HMAC<SHA256>.authenticationCode(
      for: label,
      using: SymmetricKey(data: sharedSecret)
    )
    return Data(code).base64URLEncodedString()
  }

  static func deriveIdentityBoundRouteId(
    linkSecret: String,
    firstFingerprint: String,
    secondFingerprint: String
  ) throws -> String {
    guard let secret = Data(base64URLEncoded: linkSecret), secret.count == 32 else {
      throw SignalASIError.invalidPayload("Phone link secret is malformed.")
    }
    let binding = try canonicalPhoneIdentityBinding(firstFingerprint, secondFingerprint)
    let label = Data(("signalasi-phone-route-v3\0" + binding).utf8)
    let code = HMAC<SHA256>.authenticationCode(
      for: label,
      using: SymmetricKey(data: secret)
    )
    return Data(Data(code).prefix(16)).base64URLEncodedString()
  }

  private static func canonicalPhoneIdentityBinding(
    _ firstFingerprint: String,
    _ secondFingerprint: String
  ) throws -> String {
    let identities = [firstFingerprint, secondFingerprint].map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    guard identities.allSatisfy({
      $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }), identities[0] != identities[1] else {
      throw SignalASIError.invalidPayload("Phone relationship identities are invalid.")
    }
    return identities.sorted().joined(separator: "\0")
  }

  static func topicEpoch(at date: Date = Date()) -> Int64 {
    Int64(date.timeIntervalSince1970) / topicEpochSeconds
  }

  static func topicRefreshDelay(now: Date = Date()) -> TimeInterval {
    let nowSeconds = Int64(now.timeIntervalSince1970)
    let nextBoundary = (nowSeconds / topicEpochSeconds + 1) * topicEpochSeconds
    return max(1, TimeInterval(nextBoundary - nowSeconds + 5))
  }

  static func relationshipTopic(
    linkSecret: String,
    senderFingerprint: String,
    receiverFingerprint: String,
    epoch: Int64? = nil
  ) -> String {
    guard let secretData = Data(base64URLEncoded: linkSecret), secretData.count == 32,
          !senderFingerprint.isEmpty, !receiverFingerprint.isEmpty,
          senderFingerprint != receiverFingerprint else {
      return ""
    }
    let binding = "mailbox\0\(senderFingerprint)\0\(receiverFingerprint)\0\(epoch ?? topicEpoch())"
    return kdf(secret: secretData, label: Data(binding.utf8)).base64URLEncodedString()
  }

  static func topicWindow(
    linkSecret: String,
    senderFingerprint: String,
    receiverFingerprint: String,
    now: Date = Date()
  ) -> Set<String> {
    let current = topicEpoch(at: now)
    return Set((-topicReceiveWindow...topicReceiveWindow).compactMap { offset in
      let topic = relationshipTopic(
        linkSecret: linkSecret,
        senderFingerprint: senderFingerprint,
        receiverFingerprint: receiverFingerprint,
        epoch: current + offset
      )
      return topic.isEmpty ? nil : topic
    })
  }

  static func sealWirePacket(_ payload: Data, secret: String) throws -> Data {
    guard let secretData = Data(base64URLEncoded: secret), secretData.count == 32 else {
      throw SignalASIError.invalidPayload("Link secret is malformed.")
    }
    let required = 5 + payload.count
    guard let bucket = wireBuckets.first(where: { required <= $0 }) else {
      throw SignalASIError.invalidPayload("Wire payload exceeds opaque packet limit.")
    }
    var plaintext = Data([UInt8(version)])
    let payloadSize = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: payloadSize) { plaintext.append(contentsOf: $0) }
    plaintext.append(payload)
    plaintext.append(try secureRandomData(count: bucket - required))
    let nonceData = try secureRandomData(count: 12)
    let key = SymmetricKey(data: kdf(secret: secretData, label: Data("wire-aead".utf8)))
    let sealed = try AES.GCM.seal(
      plaintext,
      using: key,
      nonce: AES.GCM.Nonce(data: nonceData)
    )
    var packet = nonceData
    packet.append(sealed.ciphertext)
    packet.append(sealed.tag)
    let encoded = Data(packet.base64URLEncodedString().utf8)
    guard encoded.count <= maxOpaquePacketBytes else {
      throw SignalASIError.invalidPayload("Opaque packet exceeds broker limit.")
    }
    return encoded
  }

  static func openWirePacket(_ wire: Data, secret: String) throws -> Data {
    guard let secretData = Data(base64URLEncoded: secret), secretData.count == 32,
          let sealed = Data(base64URLEncoded: String(decoding: wire, as: UTF8.self)),
          sealed.count >= 33 else {
      throw SignalASIError.invalidPayload("Opaque packet is malformed or truncated.")
    }
    let nonceData = sealed.prefix(12)
    let ciphertext = sealed.dropFirst(12).dropLast(16)
    let tag = sealed.suffix(16)
    let key = SymmetricKey(data: kdf(secret: secretData, label: Data("wire-aead".utf8)))
    let box = try AES.GCM.SealedBox(
      nonce: AES.GCM.Nonce(data: nonceData),
      ciphertext: ciphertext,
      tag: tag
    )
    let plaintext = try AES.GCM.open(box, using: key)
    guard plaintext.count >= 5, plaintext[plaintext.startIndex] == UInt8(version) else {
      throw SignalASIError.invalidPayload("Unsupported opaque packet version.")
    }
    let lengthBytes = plaintext.dropFirst().prefix(4)
    let payloadSize = lengthBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard payloadSize <= plaintext.count - 5 else {
      throw SignalASIError.invalidPayload("Invalid opaque packet length.")
    }
    return plaintext.subdata(in: 5..<(5 + Int(payloadSize)))
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
    guard let normalized = normalizePairingQRCode(object) else {
      throw SignalASIError.invalidPairingQRCode("Unsupported SignalASI pairing QR format.")
    }
    return try validatePairingQRCode(normalized, now: now)
  }

  static func normalizePairingQRCode(_ source: [String: Any]) -> [String: Any]? {
    if source.string("type") == "opaque_pairing" {
      return source
    }
    guard source.string("t") == "o2" else { return nil }

    let fingerprint = source.string("h")
    let pairingSecret = source.string("e")
    let desktopName = source.string("n").ifBlank("SignalASI Desktop")
    let executor = source.int("a") == 1
    let restrictedScopes = [scopeAgentChat, scopeExplicitAttachments, scopeTaskWorkspace]
    let executorScopes = restrictedScopes + [
      scopeDesktopExecutor,
      scopeDesktopControl,
      scopeDesktopNativeTools,
      scopeDesktopExternalFiles
    ]
    var normalized: [String: Any] = [
      "type": "opaque_pairing",
      "version": version,
      "desktop_id": "desktop_" + String(fingerprint.prefix(16)),
      "desktop_name": desktopName,
      "desktop_display_name": desktopName,
      "device_id": 1,
      "identity_key": source.string("k"),
      "identity_key_sha256": fingerprint,
      "created_at": source.double("c"),
      "pairing_topic": pairingTopic(secret: pairingSecret),
      "pairing_token": source.string("x"),
      "pairing_secret": pairingSecret,
      "pairing_access": [
        "contract_version": accessContract,
        "version": 1,
        "profile": executor ? accessDesktopExecutor : accessRestricted,
        "scopes": executor ? executorScopes : restrictedScopes,
        "desktop_executor": executor,
        "issued_at": source.double("c") * 1_000
      ]
    ]
    let authorizationToken = source.string("o")
    if !authorizationToken.isEmpty {
      normalized["desktop_control_authorization"] = ["token": authorizationToken]
    }
    return normalized
  }

  static func validatePairingQRCode(_ qr: [String: Any], now: Date = Date()) throws -> PairingQRCode {
    guard qr.string("type") == "opaque_pairing" else {
      throw SignalASIError.invalidPairingQRCode("type must be opaque_pairing.")
    }
    guard qr.int("version") == version else {
      throw SignalASIError.invalidPairingQRCode("protocol version mismatch.")
    }
    let pairingSecretString = qr.string("pairing_secret")
    let expectedTopic = pairingTopic(secret: pairingSecretString)
    guard validLinkSecret(pairingSecretString), !expectedTopic.isEmpty else {
      throw SignalASIError.invalidPairingQRCode("pairing secret must be 32 bytes.")
    }
    guard qr.string("pairing_topic") == expectedTopic else {
      throw SignalASIError.invalidPairingQRCode("pairing topic does not match secret.")
    }
    guard qr.string("pairing_token").count >= 32 else {
      throw SignalASIError.invalidPairingQRCode("pairing token is too short.")
    }
    guard let pairingSecret = Data(base64URLEncoded: pairingSecretString),
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
      desktopName: SignalASIDesktopDeviceMetadata.displayName(
        from: qr,
        fallback: "SignalASI Desktop"
      ),
      desktopFingerprint: qr.string("identity_key_sha256"),
      pairingTopic: expectedTopic,
      pairingToken: qr.string("pairing_token"),
      pairingSecret: pairingSecret,
      access: access,
      controlAuthorizationToken: authorizationToken,
      raw: qr
    )
  }

  static func hasVerifiedDesktopIdentity(_ pairing: PairingQRCode) -> Bool {
    let encodedKey = pairing.raw.string("identity_key")
    guard let key = Data(base64URLEncoded: encodedKey) ?? Data(
      base64Encoded: encodedKey,
      options: [.ignoreUnknownCharacters]
    ), !key.isEmpty else {
      return false
    }
    let digest = SHA256.hash(data: key)
      .map { String(format: "%02x", $0) }
      .joined()
    return digest.caseInsensitiveCompare(pairing.desktopFingerprint) == .orderedSame
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
    let messageId = normalizedMessageId(payload["message_id"] as? String ?? "")
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

  static func normalizedMessageId(_ value: String) -> String {
    UUID(uuidString: value.trimmingCharacters(in: .whitespacesAndNewlines))?.uuidString
      ?? UUID().uuidString
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

  static func encryptPairingClaim(claim: [String: Any], pairing: PairingQRCode) throws -> Data {
    try sealWirePacket(
      jsonData(claim),
      secret: pairing.pairingSecret.base64URLEncodedString()
    )
  }

  static func jsonData(_ object: Any) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw SignalASIError.invalidPayload("object is not JSON encodable.")
    }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
  }

  private static func kdf(secret: Data, label: Data) -> Data {
    let key = SymmetricKey(data: secret)
    let input = Data("signalasi-opaque-v2\0".utf8) + label
    return Data(HMAC<SHA256>.authenticationCode(for: input, using: key))
  }

  private static func secureRandomData(count: Int) throws -> Data {
    guard count >= 0 else { throw SignalASIError.invalidPayload("Invalid random byte count.") }
    var bytes = [UInt8](repeating: 0, count: count)
    guard count == 0 || SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
      throw SignalASIError.invalidPayload("Unable to create secure random data.")
    }
    return Data(bytes)
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
    if let values = self[key] as? [String] {
      return values
    }
    if let values = self[key] as? [Any] {
      return values.compactMap { value in
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
      }
    }
    if let value = self[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return value
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
    return []
  }
}
