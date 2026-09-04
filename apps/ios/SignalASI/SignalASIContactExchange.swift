import CryptoKit
import Foundation

enum SignalASIQRCodeImport {
  case desktopPairing(PairingQRCode)
  case contact(SignalASIFriendRequest)
  case contacts([SignalASIFriendRequest])
}

struct SignalASIConnectorAgentSource {
  var parentPayload: [String: Any]
  var agents: [[String: Any]]
}

enum SignalASIQRCodePayload {
  static func decodeObject(from contents: String, label: String) throws -> [String: Any] {
    var texts = candidateTexts(from: contents)
    var objects: [[String: Any]] = []
    var fallback: [String: Any]?
    var textIndex = 0
    var objectIndex = 0

    func addText(_ value: String) {
      candidateTexts(from: value).forEach { candidate in
        if texts.count < 48, !texts.contains(candidate) {
          texts.append(candidate)
        }
      }
    }

    func addObject(_ object: [String: Any]) {
      if objects.count < 48 {
        objects.append(object)
      }
    }

    while textIndex < texts.count || objectIndex < objects.count {
      while textIndex < texts.count {
        let candidate = texts[textIndex]
        textIndex += 1
        guard let data = candidate.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data, options: []) else {
          continue
        }
        if let object = raw as? [String: Any] {
          addObject(object)
        } else if let array = raw as? [Any], !array.isEmpty {
          addObject(["connector_agents": array])
        }
      }

      while objectIndex < objects.count {
        let object = objects[objectIndex]
        objectIndex += 1
        if looksLikeSignalASIObject(object) {
          return object
        }
        if fallback == nil {
          fallback = object
        }
        for key in wrappedPayloadKeys {
          if let nested = object.dictionary(key) {
            addObject(nested)
          }
          if let nestedText = object[key] as? String {
            addText(nestedText)
          }
        }
      }
    }
    if let fallback {
      return fallback
    }
    throw SignalASIError.invalidPayload("\(label) root must be a JSON object.")
  }

  private static let wrappedPayloadKeys = [
    "payload",
    "payload_b64",
    "data",
    "data_b64",
    "json",
    "qr",
    "qr_b64",
    "contact",
    "pairing",
    "signalasi",
    "signalasi_payload",
    "signalasi_qr",
    "capability_manifest",
    "connector_status",
    "manifest",
    "mobile_manifest"
  ]

  private static func looksLikeSignalASIObject(_ object: [String: Any]) -> Bool {
    if object.string("t") == SignalASIContactExchange.compactPhoneQRType {
      return true
    }
    let type = object.string("type").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hasIdentity = !object.string("signalasi_id").isEmpty ||
      !object.string("hermes_id").isEmpty ||
      !object.string("identity_public_key").isEmpty ||
      !object.string("identity_key").isEmpty ||
      !object.string("identity_fingerprint").isEmpty ||
      !object.string("identity_key_sha256").isEmpty ||
      !object.string("desktop_fingerprint").isEmpty
    let hasPairing = !object.string("pairing_token").isEmpty ||
      !object.string("server_route_id").isEmpty ||
      object.string("protocol") == SignalASILinkProtocol.name
    let hasAgentList = SignalASIContactExchange.connectorAgentListKeys.contains { object[$0] != nil }
    let hasAgentIdentity = !object.string("agent_id").isEmpty ||
      !object.string("mobile_contact_id").isEmpty ||
      !object.string("device_id").isEmpty

    switch type {
    case "opaque_pairing":
      return hasPairing || hasIdentity
    case "signalasi_contact", "hermes_contact", "opaque_contact", "opaque_identity":
      return hasIdentity
    case "agent", "agent_contact", "signalasi_agent", "signalasi_agent_contact",
         "device", "device_contact", "signalasi_device", "signalasi_device_contact":
      return hasIdentity || hasAgentIdentity
    case "connector_status", "capability_manifest", "pairing_confirmed":
      return hasAgentList || hasPairing || hasIdentity
    default:
      break
    }
    return hasIdentity || hasPairing || hasAgentList || hasAgentIdentity
  }

  private static func candidateTexts(from contents: String) -> [String] {
    var results: [String] = []

    func add(_ value: String) {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty, !results.contains(clean) else { return }
      results.append(clean)
      if let decoded = clean.removingPercentEncoding,
         decoded != clean {
        add(decoded)
      }
      if let base64Decoded = decodeBase64Text(clean) {
        add(base64Decoded)
      }
      if let jsonSlice = embeddedJSONObject(in: clean) {
        add(jsonSlice)
      }
    }

    let clean = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    add(clean)

    if let components = URLComponents(string: clean),
       components.scheme != nil || components.host != nil {
      let payloadKeys: Set<String> = [
        "payload", "payload_b64", "data", "data_b64", "json", "qr", "qr_b64",
        "q", "text", "value", "contact", "pairing"
      ]
      components.queryItems?.forEach { item in
        guard let value = item.value else { return }
        if payloadKeys.contains(item.name.lowercased()) {
          add(value)
        }
      }
      if let fragment = components.percentEncodedFragment?.removingPercentEncoding ?? components.fragment {
        add(fragment)
      }
      if let host = components.host {
        add(host)
      }
      let pathParts = components.path
        .split(separator: "/")
        .map(String.init)
      pathParts.forEach(add)
      pathParts.last.map(add)
    }

    return results
  }

  private static func decodeBase64Text(_ value: String) -> String? {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let encoded = clean.contains(",") && clean.lowercased().contains(";base64,")
      ? (clean.split(separator: ",").last.map(String.init) ?? "")
      : clean
    guard encoded.count >= 16 else { return nil }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
    guard encoded.rangeOfCharacter(from: allowed.inverted) == nil else { return nil }
    let data = Data(base64URLEncoded: encoded) ?? Data(base64Encoded: encoded)
    guard let data,
          let text = String(data: data, encoding: .utf8) else {
      return nil
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
  }

  private static func embeddedJSONObject(in value: String) -> String? {
    guard let start = value.firstIndex(of: "{"),
          let end = value.lastIndex(of: "}"),
          start < end else {
      return nil
    }
    return String(value[start...end])
  }
}

enum SignalASIContactExchange {
  static let contactType = "signalasi_contact"
  static let opaqueContactType = "opaque_contact"
  static let opaqueIdentityType = "opaque_identity"
  static let hermesContactType = "hermes_contact"
  static let verifyType = "signalasi_verify"
  static let version = 1
  fileprivate static let compactPhoneQRType = "p2"
  static let maximumCompactPhoneQRBytes = 1_000
  fileprivate static let connectorAgentListKeys = [
    "connector_agents",
    "desktop_agents",
    "mobile_agents",
    "agent_contacts",
    "agent_list",
    "agent_catalog",
    "agents",
    "available_agents",
    "connected_agents",
    "available_connectors",
    "connector_catalog",
    "agent_statuses",
    "agent_targets",
    "callable_targets",
    "available_targets",
    "targets",
    "connectors"
  ]
  private static let agentContactTypes: Set<String> = [
    "agent",
    "agent_contact",
    "signalasi_agent",
    "signalasi_agent_contact"
  ]
  private static let deviceContactTypes: Set<String> = [
    "device",
    "device_contact",
    "signalasi_device",
    "signalasi_device_contact"
  ]

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
    let device = SignalASIDeviceIdentity.current(profile: profile)
    return [
      "type": contactType,
      "version": version,
      "name": device.displayName,
      "display_name": device.displayName,
      "signalasi_id": profile.signalASIId,
      "identity_public_key": profile.identityPublicKey,
      "identity_fingerprint": profile.identityFingerprint,
      "device_id": device.deviceId,
      "device_name": device.deviceName,
      "device_manufacturer": device.manufacturer,
      "device_model": device.model,
      "platform": "ios",
      "platform_version": device.platformVersion,
      "profile_name": device.profileName,
      "created_at": Int64(now.timeIntervalSince1970 * 1000)
    ]
  }

  static func makeSignedPhoneContactQRText(
    profile: SignalASIProfile,
    signalIdentity: SignalASISignalIdentity,
    pairingToken: String,
    pairingSecret: String,
    pairingTopic: String,
    now: Date = Date(),
    sign: (Data) -> String?
  ) throws -> String? {
    guard SignalASILinkProtocol.validLinkSecret(pairingToken),
          SignalASILinkProtocol.validLinkSecret(pairingSecret),
          pairingTopic == SignalASILinkProtocol.pairingTopic(secret: pairingSecret),
          signalIdentity.name.hasPrefix("signalasi:"),
          signalIdentity.fingerprint.count == 64,
          !signalIdentity.publicKey.isEmpty,
          let bundle = signalIdentity.bundle else {
      return nil
    }
    let device = SignalASIDeviceIdentity.current(profile: profile)
    var card: [String: Any] = [
      "type": opaqueContactType,
      "version": SignalASILinkProtocol.version,
      "signalasi_id": signalIdentity.name,
      "name": String(device.displayName.prefix(64)),
      "identity_public_key": signalIdentity.publicKey,
      "identity_fingerprint": signalIdentity.fingerprint,
      "signal_bundle": bundle,
      "bundle_identity_fingerprint": signalIdentity.fingerprint,
      "pairing_token": pairingToken,
      "pairing_secret": pairingSecret,
      "pairing_topic": pairingTopic,
      "device_id": SignalASIDeviceIdentity.current(profile: profile).deviceId,
      "created_at": Int64(now.timeIntervalSince1970 * 1_000)
    ]
    guard let signature = sign(canonicalPhoneContactCardBytes(card)), !signature.isEmpty else {
      return nil
    }
    card["signature"] = signature
    let compact = compactPhoneContactQR(card)
    guard compact["signal_bundle"] == nil,
          normalizeCompactPhoneContactQR(compact) != nil else {
      return nil
    }
    let data = try SignalASILinkProtocol.jsonData(compact)
    guard data.count < maximumCompactPhoneQRBytes else {
      throw SignalASIError.invalidPayload("Compact contact QR payload exceeds 1 KB.")
    }
    return String(data: data, encoding: .utf8)
  }

  static func compactPhoneContactQR(_ card: [String: Any]) -> [String: Any] {
    [
      "t": compactPhoneQRType,
      "i": card.string("signalasi_id"),
      "n": card.string("name"),
      "k": card.string("identity_public_key"),
      "h": card.string("identity_fingerprint"),
      "x": card.string("pairing_token"),
      "e": card.string("pairing_secret"),
      "d": card.string("device_id"),
      "c": (card["created_at"] as? NSNumber)?.int64Value ?? 0,
      "s": card.string("signature")
    ]
  }

  static func normalizeCompactPhoneContactQR(_ source: [String: Any]) -> [String: Any]? {
    guard source.string("t") == compactPhoneQRType else { return nil }
    let fingerprint = source.string("h")
    let secret = source.string("e")
    guard SignalASILinkProtocol.validLinkSecret(secret),
          SignalASILinkProtocol.validLinkSecret(source.string("x")) else {
      return nil
    }
    let card: [String: Any] = [
      "type": opaqueContactType,
      "version": SignalASILinkProtocol.version,
      "signalasi_id": source.string("i"),
      "name": source.string("n"),
      "identity_public_key": source.string("k"),
      "identity_fingerprint": fingerprint,
      "bundle_identity_fingerprint": fingerprint,
      "pairing_token": source.string("x"),
      "pairing_secret": secret,
      "pairing_topic": SignalASILinkProtocol.pairingTopic(secret: secret),
      "device_id": source.string("d"),
      "created_at": (source["c"] as? NSNumber)?.int64Value ?? 0,
      "signature": source.string("s")
    ]
    return (try? validateSignedPhoneContactCard(card)) == nil ? nil : card
  }

  static func canonicalPhoneContactCardBytes(_ card: [String: Any]) -> Data {
    let fields = [
      "type",
      "version",
      "signalasi_id",
      "name",
      "identity_public_key",
      "identity_fingerprint",
      "bundle_identity_fingerprint",
      "pairing_token",
      "pairing_secret",
      "pairing_topic",
      "device_id",
      "created_at"
    ]
    let payload = fields.map { key -> String in
      let value = String(describing: card[key] ?? "")
      return "\(key.utf16.count):\(key)\(value.utf16.count):\(value)|"
    }.joined()
    return Data(payload.utf8)
  }

  static func validateSignedPhoneContactCard(_ card: [String: Any]) throws {
    let signature = card.string("signature")
    let opaque = [opaqueContactType, opaqueIdentityType].contains(card.string("type"))
    guard !signature.isEmpty else {
      if opaque {
        throw SignalASIError.invalidPayload("Opaque contact card is unsigned.")
      }
      return
    }
    let signalASIId = card.string("signalasi_id")
    let fingerprint = card.string("identity_fingerprint")
    let publicKey = card.string("identity_public_key")
    let pairingSecret = card.string("pairing_secret")
    let fingerprintMatches = fingerprint.range(
      of: "^[a-fA-F0-9]{64}$",
      options: .regularExpression
    ) != nil
    let idMatches = signalASIId.range(
      of: "^signalasi:[a-fA-F0-9]{16}$",
      options: .regularExpression
    ) != nil
    let publicKeyFingerprint = Data(base64Encoded: publicKey).map { key in
      SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
    } ?? ""
    let createdAtMillis = (card["created_at"] as? NSNumber)?.int64Value ?? 0
    let nowMillis = Int64(Date().timeIntervalSince1970 * 1_000)
    guard [opaqueContactType, opaqueIdentityType].contains(card.string("type")),
          card.int("version") == SignalASILinkProtocol.version,
          idMatches,
          signalASIId.dropFirst("signalasi:".count).caseInsensitiveCompare(fingerprint.prefix(16)) == .orderedSame,
          !card.string("name").isEmpty,
          card.string("name").utf16.count <= 64,
          publicKey.count >= 40,
          publicKey.count <= 256,
          fingerprintMatches,
          publicKeyFingerprint.caseInsensitiveCompare(fingerprint) == .orderedSame,
          card.string("bundle_identity_fingerprint").caseInsensitiveCompare(fingerprint) == .orderedSame,
          (card.string("type") == opaqueIdentityType || (
            SignalASILinkProtocol.validLinkSecret(card.string("pairing_token")) &&
              SignalASILinkProtocol.validLinkSecret(pairingSecret) &&
              card.string("pairing_topic") == SignalASILinkProtocol.pairingTopic(secret: pairingSecret)
          )),
          createdAtMillis > 0,
          abs(nowMillis - createdAtMillis) <= SignalASIPhoneContactControl.maximumAgeMillis,
          signature.count >= 40,
          signature.count <= 256,
          SignalASISignalEngine.verifyContactCard(
            publicKey: publicKey,
            payload: canonicalPhoneContactCardBytes(card),
            signature: signature
          ) else {
      throw SignalASIError.invalidPayload("Signed contact QR verification failed.")
    }
  }

  static func classifyQRCode(_ contents: String, now: Date = Date()) throws -> SignalASIQRCodeImport {
    let rawObject = try decodeQRCodeObject(contents, label: "QR")
    let object = SignalASILinkProtocol.normalizePairingQRCode(rawObject)
      ?? normalizeCompactPhoneContactQR(rawObject)
      ?? rawObject
    let type = normalized(object.string("type"))
    let isPairingQRCode = type == "opaque_pairing"
    if isPairingQRCode {
      return .desktopPairing(try SignalASILinkProtocol.validatePairingQRCode(object, now: now))
    }
    let connectorRequests = try importConnectorAgentRequests(object, now: now)
    if !connectorRequests.isEmpty {
      return .contacts(connectorRequests)
    }
    if isContactQRCodeObject(object) {
      return .contact(try importContactQRCodeObject(object, now: now))
    }
    throw SignalASIError.invalidPayload("Unsupported SignalASI QR code.")
  }

  static func importContactQRCode(_ contents: String, now: Date = Date()) throws -> SignalASIFriendRequest {
    let rawObject = try decodeQRCodeObject(contents, label: "Contact QR")
    let object = normalizeCompactPhoneContactQR(rawObject) ?? rawObject
    return try importContactQRCodeObject(object, now: now)
  }

  static func connectorAgentSource(from object: [String: Any]) -> SignalASIConnectorAgentSource? {
    var candidates: [[String: Any]] = [object]
    let nestedKeys = [
      "capability_manifest",
      "connector_status",
      "diagnostics",
      "manifest",
      "payload",
      "data",
      "runtime",
      "status",
      "mobile_manifest",
      "agent_manifest",
      "connector_manifest",
      "desktop_status",
      "desktop_state"
    ]
    var index = 0
    while index < candidates.count, candidates.count < 24 {
      let candidate = candidates[index]
      nestedKeys.forEach { key in
        if let nested = candidate.dictionary(key) {
          candidates.append(nested)
        }
      }
      index += 1
    }

    for candidate in candidates {
      guard let agents = connectorAgents(in: candidate), !agents.isEmpty else {
        continue
      }
      var parent = object
      candidate.forEach { key, value in
        parent[key] = value
      }
      return SignalASIConnectorAgentSource(parentPayload: parent, agents: agents)
    }
    return nil
  }

  private static func importContactQRCodeObject(_ object: [String: Any], now: Date) throws -> SignalASIFriendRequest {
    let type = normalized(object.string("type"))
    guard isContactQRCodeObject(object) else {
      throw SignalASIError.invalidPayload("Contact QR type is not supported.")
    }
    try validateSignedPhoneContactCard(object)
    let server = desktopServerObject(from: object)
    let fingerprint = object.string("identity_fingerprint")
      .ifBlank(object.string("identity_key_sha256"))
      .ifBlank(object.string("desktop_fingerprint"))
      .ifBlank(server?.string("identity_key_sha256") ?? "")
      .ifBlank(server?.string("identity_fingerprint") ?? "")
      .ifBlank(server?.string("desktop_fingerprint") ?? "")
      .ifBlank(server?.string("fingerprint") ?? "")
    let publicKey = object.string("identity_public_key")
      .ifBlank(object.string("identity_key"))
      .ifBlank(object.string("desktop_public_key"))
      .ifBlank(object.string("public_key"))
      .ifBlank(server?.string("identity_public_key") ?? "")
      .ifBlank(server?.string("desktop_public_key") ?? "")
      .ifBlank(server?.string("public_key") ?? "")
    let desktopAgent = isDesktopAgentQRCodeObject(object)
    guard !fingerprint.isEmpty, !publicKey.isEmpty || desktopAgent else {
      throw SignalASIError.invalidPayload("Contact QR is missing identity material.")
    }
    let signalASIId = object.string("signalasi_id")
      .ifBlank(object.string("hermes_id"))
      .ifBlank(scopedDesktopAgentId(from: object))
      .ifBlank(object.string("mobile_contact_id"))
      .ifBlank(object.string("agent_id"))
      .ifBlank(object.string("id"))
      .ifBlank("signalasi:\(fingerprint.prefix(16))")
    let mqttTopic = object.string("mqtt_topic")
      .ifBlank(object.string("mqtt_inbox_topic"))
      .ifBlank(object.string("mqtt_recv_topic"))
    let name = object.string("display_name")
      .ifBlank(object.string("name"))
      .ifBlank(type == verifyType ? "Hermes" : "Friend")
    let requestType: String
    if type == verifyType {
      requestType = "hermes"
    } else if isDeviceQRCodeObject(object) {
      requestType = "device"
    } else if isAgentQRCodeObject(object) {
      requestType = "agent"
    } else {
      requestType = normalized(object.string("contact_type")).ifBlank("person")
    }
    let agentKind = object.string("agent_kind")
      .ifBlank(object.string("kind"))
      .ifBlank(defaultAgentKind(for: requestType, object: object))
    let connectorCapabilities = connectorStringArray(object, key: "capabilities")
    let connectorProtocols = connectorStringArray(object, key: "protocols")
    let connectorProtocolFeatures = connectorStringArray(object, key: "protocol_features")
      .ifEmpty(connectorStringArray(object.dictionary("adapter") ?? [:], key: "features"))
    let deviceMetadata = SignalASIDesktopDeviceMetadata.from(payload: object)
    return SignalASIFriendRequest(
      id: "req_\(Int64(now.timeIntervalSince1970 * 1000))",
      signalASIId: signalASIId,
      name: name,
      type: requestType,
      identityPublicKey: publicKey,
      identityFingerprint: fingerprint,
      mqttTopic: mqttTopic,
      mqttInboxTopic: mqttTopic,
      signalBundleRef: signalBundleReference(object),
      agentKind: agentKind,
      desktopId: desktopId(from: object),
      desktopName: desktopName(from: object),
      deviceId: object.string("device_id"),
      deviceName: object.string("device_name"),
      deviceManufacturer: object.string("device_manufacturer")
        .ifBlank(object.string("manufacturer")),
      deviceModel: object.string("device_model")
        .ifBlank(object.string("model")),
      devicePlatform: deviceMetadata?.platform ?? object.string("platform"),
      devicePlatformVersion: object.string("platform_version"),
      deviceProfileName: object.string("profile_name"),
      deviceHostName: deviceMetadata?.hostName ?? "",
      setupDetail: object.string("setup_detail").ifBlank(object.string("detail")),
      setupNextStep: object.string("setup_next_step").ifBlank(object.string("setup")),
      desktopAccessProfile: object.string("desktop_access_profile")
        .ifBlank(desktopAgent ? SignalASILinkProtocol.accessRestricted : ""),
      desktopAccessScopes: object.stringArray("desktop_access_scopes")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty },
      connectorCapabilities: connectorCapabilities,
      connectorCapabilitiesHash: object.string("capabilities_hash")
        .ifBlank(capabilitiesHash(for: connectorCapabilities)),
      connectorProtocols: connectorProtocols,
      connectorProtocolFeatures: connectorProtocolFeatures,
      connectorAdapterType: connectorAdapterType(from: object),
      connectorProviderProfileJSON: providerProfileJSON(from: object),
      connectorInvocationProfileJSON: invocationProfileJSON(from: object),
      source: "qr",
      createdAt: now
    )
  }

  private static func importConnectorAgentRequests(_ object: [String: Any], now: Date) throws -> [SignalASIFriendRequest] {
    guard let source = connectorAgentSource(from: object) else {
      return []
    }
    let parent = source.parentPayload
    let agents = source.agents
    let type = normalized(parent.string("type"))
    guard ["connector_status", "capability_manifest", "pairing_confirmed"].contains(type) ||
      ["agent_manifest", "connector_manifest", "desktop_status", "signalasi_agents"].contains(type) ||
      isPairingOrConnectorStatusObject(parent) ||
      agents.contains(where: isContactQRCodeObject) else {
      return []
    }
    let inherited = inheritedDesktopAgentFields(from: parent)
    var requests: [SignalASIFriendRequest] = []
    for (index, rawAgent) in agents.enumerated() {
      var agent = rawAgent
      inherited.forEach { key, value in
        if agent.string(key).isEmpty {
          agent[key] = value
        }
      }
      if agent.string("type").isEmpty {
        agent["type"] = "agent"
      }
      if agent.string("contact_type").isEmpty {
        agent["contact_type"] = "agent"
      }
      if agent.string("agent_id").isEmpty {
        let rawId = agent.string("id")
        let idSuffix = rawId.contains(":")
          ? (rawId.split(separator: ":").last.map(String.init) ?? rawId)
          : rawId
        agent["agent_id"] = idSuffix
      }
      if agent.string("display_name").isEmpty {
        let agentName = agent.string("name").ifBlank(agent.string("agent_id")).ifBlank(agent.string("id"))
        let desktopName = agent.string("host_name")
          .ifBlank(agent.string("hostname"))
          .ifBlank(agent.string("desktop_name"))
        if !agentName.isEmpty, !desktopName.isEmpty {
          agent["display_name"] = "\(agentName) · \(desktopName)"
        }
      }
      if agent.string("setup_detail").isEmpty, !agent.string("detail").isEmpty {
        agent["setup_detail"] = agent.string("detail")
      }
      if agent.string("agent_id") == "cloud-model" || agent.string("kind") == "cloud-model" {
        continue
      }
      do {
        var request = try importContactQRCodeObject(
          agent,
          now: now.addingTimeInterval(Double(index) / 1_000.0)
        )
        request.id = "\(request.id)_\(index + 1)"
        requests.append(request)
      } catch {
        continue
      }
    }
    return requests
  }

  private static func inheritedDesktopAgentFields(from object: [String: Any]) -> [String: Any] {
    var inherited: [String: Any] = [:]
    let server = desktopServerObject(from: object)
    let desktopFingerprint = object.string("desktop_fingerprint")
      .ifBlank(object.string("identity_key_sha256"))
      .ifBlank(object.string("identity_fingerprint"))
      .ifBlank(server?.string("desktop_fingerprint") ?? "")
      .ifBlank(server?.string("identity_key_sha256") ?? "")
      .ifBlank(server?.string("identity_fingerprint") ?? "")
      .ifBlank(server?.string("fingerprint") ?? "")
    let desktopId = object.string("desktop_id")
      .ifBlank(server?.string("desktop_id") ?? "")
      .ifBlank(server?.string("id") ?? "")
      .ifBlank(desktopFingerprint.isEmpty ? "" : "desktop_\(desktopFingerprint.prefix(16))")
    let desktopName = object.string("desktop_name")
      .ifBlank(server?.string("desktop_name") ?? "")
      .ifBlank(server?.string("name") ?? "")
    [
      "desktop_id": desktopId,
      "desktop_name": desktopName,
      "desktop_fingerprint": desktopFingerprint,
      "desktop_public_key": object.string("desktop_public_key")
        .ifBlank(object.string("identity_public_key"))
        .ifBlank(server?.string("desktop_public_key") ?? "")
        .ifBlank(server?.string("identity_public_key") ?? "")
        .ifBlank(server?.string("public_key") ?? ""),
      "mqtt_topic": object.string("mqtt_topic").ifBlank(object.string("mqtt_inbox_topic")).ifBlank(object.string("mqtt_recv_topic")),
      "mqtt_inbox_topic": object.string("mqtt_inbox_topic").ifBlank(object.string("mqtt_topic")),
      "desktop_access_profile": object.string("desktop_access_profile"),
      "setup_next_step": object.string("setup_next_step").ifBlank(object.string("setup"))
    ].forEach { key, value in
      if !value.isEmpty {
        inherited[key] = value
      }
    }
    [
      "desktop_access_scopes",
      "capabilities",
      "protocols",
      "protocol_features",
      "provider_profile",
      "invocation_profile",
      "adapter",
      "reputation"
    ].forEach { key in
      if let value = object[key] {
        inherited[key] = value
      }
    }
    return inherited
  }

  private static func isPairingOrConnectorStatusObject(_ object: [String: Any]) -> Bool {
    !object.string("desktop_id").isEmpty ||
      !object.string("desktop_fingerprint").isEmpty ||
      !object.string("identity_key_sha256").isEmpty ||
      !object.string("identity_fingerprint").isEmpty ||
      desktopServerObject(from: object) != nil
  }

  private static func isContactQRCodeObject(_ object: [String: Any]) -> Bool {
    let type = normalized(object.string("type"))
    return [contactType, hermesContactType, verifyType, opaqueContactType, opaqueIdentityType].contains(type) ||
      agentContactTypes.contains(type) ||
      deviceContactTypes.contains(type) ||
      !object.string("signalasi_id").isEmpty ||
      !object.string("hermes_id").isEmpty ||
      isDeviceQRCodeObject(object) ||
      isAgentQRCodeObject(object)
  }

  private static func isAgentQRCodeObject(_ object: [String: Any]) -> Bool {
    let type = normalized(object.string("type"))
    let contactType = normalized(object.string("contact_type"))
    let kind = normalized(object.string("agent_kind").ifBlank(object.string("kind")))
    let rawId = object.string("id")
    let hasDesktopContext = !desktopId(from: object).isEmpty ||
      !object.string("desktop_fingerprint").isEmpty ||
      !object.string("desktop_id").isEmpty
    let agentLikeKind = [
      "agent",
      "desktop-agent",
      "local-cli",
      "custom-cli",
      "local-model",
      "model"
    ].contains(kind) ||
      kind.contains("agent") ||
      kind.contains("model") ||
      kind.contains("cli")
    return agentContactTypes.contains(type) ||
      contactType == "agent" ||
      !object.string("agent_kind").isEmpty ||
      !object.string("agent_id").isEmpty ||
      !object.string("mobile_contact_id").isEmpty ||
      (hasDesktopContext && !rawId.isEmpty && agentLikeKind)
  }

  private static func isDesktopAgentQRCodeObject(_ object: [String: Any]) -> Bool {
    isAgentQRCodeObject(object) &&
      (!desktopId(from: object).isEmpty || !object.string("desktop_fingerprint").isEmpty)
  }

  private static func isDeviceQRCodeObject(_ object: [String: Any]) -> Bool {
    let type = normalized(object.string("type"))
    let contactType = normalized(object.string("contact_type"))
    let kind = normalized(object.string("agent_kind").ifBlank(object.string("kind")))
    let deviceId = normalized(object.string("device_id"))
    let agentId = normalized(
      object.string("agent_id")
        .ifBlank(object.string("mobile_contact_id"))
        .ifBlank(object.string("id"))
    )
    return deviceContactTypes.contains(type) ||
      contactType == "device" ||
      kind == "device" ||
      agentId == "pc_agent" ||
      agentId == "home_hub" ||
      agentId.contains("device") ||
      agentId.contains("hub") ||
      (!deviceId.isEmpty && !isAgentQRCodeObject(object))
  }

  private static func scopedDesktopAgentId(from object: [String: Any]) -> String {
    guard isAgentQRCodeObject(object) else { return "" }
    let rawId = object.string("id")
    if normalized(rawId).hasPrefix("desktop_"), rawId.contains(":") {
      return rawId
    }
    let desktopId = desktopId(from: object)
    let idSuffix = rawId.contains(":")
      ? (rawId.split(separator: ":").last.map(String.init) ?? rawId)
      : rawId
    let agentId = object.string("agent_id")
      .ifBlank(object.string("mobile_contact_id"))
      .ifBlank(idSuffix)
    guard !desktopId.isEmpty, !agentId.isEmpty else { return "" }
    return "\(desktopId):\(agentId)"
  }

  private static func desktopId(from object: [String: Any]) -> String {
    let explicit = object.string("desktop_id")
    if !explicit.isEmpty { return explicit }
    if let server = desktopServerObject(from: object) {
      let serverDesktopId = server.string("desktop_id").ifBlank(server.string("id"))
      if !serverDesktopId.isEmpty { return serverDesktopId }
    }
    let rawId = object.string("id")
    if normalized(rawId).hasPrefix("desktop_"), rawId.contains(":") {
      return rawId.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    }
    let fingerprint = object.string("desktop_fingerprint")
      .ifBlank(object.string("identity_key_sha256"))
      .ifBlank(object.string("identity_fingerprint"))
      .ifBlank(desktopServerObject(from: object)?.string("desktop_fingerprint") ?? "")
      .ifBlank(desktopServerObject(from: object)?.string("identity_key_sha256") ?? "")
      .ifBlank(desktopServerObject(from: object)?.string("identity_fingerprint") ?? "")
      .ifBlank(desktopServerObject(from: object)?.string("fingerprint") ?? "")
    return fingerprint.isEmpty ? "" : "desktop_\(fingerprint.prefix(16))"
  }

  private static func desktopName(from object: [String: Any]) -> String {
    SignalASIDesktopDeviceMetadata.displayName(from: object)
      .ifBlank(desktopServerObject(from: object)?.string("desktop_name") ?? "")
      .ifBlank(desktopServerObject(from: object)?.string("name") ?? "")
  }

  private static func desktopServerObject(from object: [String: Any]) -> [String: Any]? {
    object.dictionary("server") ??
      object.dictionary("desktop") ??
      object.dictionary("desktop_identity")
  }

  private static func connectorAgents(in object: [String: Any]) -> [[String: Any]]? {
    for key in connectorAgentListKeys {
      guard let rawValue = object[key] else { continue }
      let agents = connectorAgentObjects(from: rawValue)
      if !agents.isEmpty {
        return agents
      }
    }
    return nil
  }

  private static func connectorAgentObjects(from value: Any) -> [[String: Any]] {
    if let agents = value as? [[String: Any]] {
      return agents
    }
    if let values = value as? [Any] {
      return values.flatMap { connectorAgentObjects(from: $0) }
    }
    if let rawJSON = value as? String,
       let data = rawJSON.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data, options: []) {
      return connectorAgentObjects(from: decoded)
    }
    guard let object = value as? [String: Any] else { return [] }
    if isConnectorAgentObject(object) {
      return [object]
    }
    return object.compactMap { id, raw -> [String: Any]? in
      guard var agent = raw as? [String: Any] else { return nil }
      if agent.string("id").isEmpty {
        agent["id"] = id
      }
      if agent.string("agent_id").isEmpty, agent.string("mobile_contact_id").isEmpty {
        agent["agent_id"] = id
      }
      return agent
    }
  }

  private static func isConnectorAgentObject(_ object: [String: Any]) -> Bool {
    !object.string("agent_id").isEmpty ||
      !object.string("mobile_contact_id").isEmpty ||
      !object.string("agent_kind").isEmpty ||
      !object.string("kind").isEmpty ||
      !object.string("display_name").isEmpty ||
      !object.string("name").isEmpty ||
      !object.string("status").isEmpty
  }

  private static func defaultAgentKind(for requestType: String, object: [String: Any]) -> String {
    switch requestType {
    case "hermes":
      return "desktop-agent"
    case "agent":
      let identifier = normalized(
        object.string("agent_id")
          .ifBlank(object.string("mobile_contact_id"))
          .ifBlank(object.string("signalasi_id"))
      )
      if identifier.contains("model") || identifier.contains("llm") {
        return "local-model"
      }
      return "custom-cli"
    case "device":
      return "device"
    default:
      return ""
    }
  }

  private static func signalBundleReference(_ object: [String: Any]) -> String {
    if !object.string("signal_bundle_ref").isEmpty {
      return object.string("signal_bundle_ref")
    }
    guard let bundle = object["signal_bundle"] as? [String: Any] else {
      return ""
    }
    return bundle.string("signal_bundle_ref")
      .ifBlank(bundle.string("bundle_ref"))
      .ifBlank(bundle.string("ref"))
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func decodeQRCodeObject(_ contents: String, label: String) throws -> [String: Any] {
    try SignalASIQRCodePayload.decodeObject(from: contents, label: label)
  }

  static func localInboxTopic(serverLinks: [ServerLink]) -> String {
    serverLinks.first { $0.paired }?.routes.downTopic ?? ""
  }

  private static func connectorStringArray(_ object: [String: Any], key: String) -> [String] {
    let direct = object.stringArray(key)
    if !direct.isEmpty {
      return direct
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
    return (object.dictionary("adapter")?.stringArray(key) ?? [])
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func connectorAdapterType(from object: [String: Any]) -> String {
    let adapter = object.dictionary("adapter")
    return object.string("adapter_type")
      .ifBlank(adapter?.string("adapter_type") ?? "")
      .ifBlank(adapter?.string("type") ?? "")
      .ifBlank(object.string("kind"))
      .ifBlank(object.string("agent_kind"))
  }

  private static func providerProfileJSON(from object: [String: Any]) -> Data? {
    guard let profile = object.dictionary("provider_profile"),
          JSONSerialization.isValidJSONObject(profile) else {
      return nil
    }
    return try? JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys])
  }

  private static func invocationProfileJSON(from object: [String: Any]) -> Data? {
    guard let profile = object.dictionary("invocation_profile"),
          JSONSerialization.isValidJSONObject(profile) else {
      return nil
    }
    return try? JSONSerialization.data(withJSONObject: profile, options: [.sortedKeys])
  }

  private static func capabilitiesHash(for capabilities: [String]) -> String {
    guard !capabilities.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: capabilities, options: []),
          let encoded = String(data: data, encoding: .utf8) else {
      return ""
    }
    return javaHashHex(encoded)
  }

  private static func javaHashHex(_ value: String) -> String {
    var hash: Int32 = 0
    for scalar in value.unicodeScalars {
      hash = hash &* 31 &+ Int32(bitPattern: UInt32(scalar.value))
    }
    return String(UInt32(bitPattern: hash), radix: 16)
  }
}

private extension Array where Element == String {
  func ifEmpty(_ fallback: [String]) -> [String] {
    isEmpty ? fallback : self
  }
}
