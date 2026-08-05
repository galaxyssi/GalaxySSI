import Foundation

enum SignalASIQRCodeImport {
  case desktopPairing(PairingQRCode)
  case contact(SignalASIFriendRequest)
}

enum SignalASIQRCodePayload {
  static func decodeObject(from contents: String, label: String) throws -> [String: Any] {
    for candidate in candidateTexts(from: contents) {
      guard let data = candidate.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data, options: []),
            let object = raw as? [String: Any] else {
        continue
      }
      return object
    }
    throw SignalASIError.invalidPayload("\(label) root must be a JSON object.")
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
  static let hermesContactType = "hermes_contact"
  static let verifyType = "signalasi_verify"
  static let version = 1
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

  static func classifyQRCode(_ contents: String, now: Date = Date()) throws -> SignalASIQRCodeImport {
    let object = try decodeQRCodeObject(contents, label: "QR")
    let type = object.string("type")
    let isPairingQRCode = type == verifyType &&
      (
        object.string("protocol") == SignalASILinkProtocol.name ||
        !object.string("pairing_token").isEmpty ||
        !object.string("server_route_id").isEmpty
      )
    if isPairingQRCode {
      return .desktopPairing(try SignalASILinkProtocol.validatePairingQRCode(object, now: now))
    }
    if isContactQRCodeObject(object) {
      return .contact(try importContactQRCodeObject(object, now: now))
    }
    throw SignalASIError.invalidPayload("Unsupported SignalASI QR code.")
  }

  static func importContactQRCode(_ contents: String, now: Date = Date()) throws -> SignalASIFriendRequest {
    let object = try decodeQRCodeObject(contents, label: "Contact QR")
    return try importContactQRCodeObject(object, now: now)
  }

  private static func importContactQRCodeObject(_ object: [String: Any], now: Date) throws -> SignalASIFriendRequest {
    let type = object.string("type")
    guard isContactQRCodeObject(object) else {
      throw SignalASIError.invalidPayload("Contact QR type is not supported.")
    }
    let fingerprint = object.string("identity_fingerprint").ifBlank(object.string("identity_key_sha256"))
    let publicKey = object.string("identity_public_key").ifBlank(object.string("identity_key"))
    guard !fingerprint.isEmpty, !publicKey.isEmpty else {
      throw SignalASIError.invalidPayload("Contact QR is missing identity material.")
    }
    let signalASIId = object.string("signalasi_id")
      .ifBlank(object.string("hermes_id"))
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
      requestType = object.string("contact_type").ifBlank("person")
    }
    let agentKind = object.string("agent_kind")
      .ifBlank(object.string("kind"))
      .ifBlank(defaultAgentKind(for: requestType, object: object))
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
      desktopId: object.string("desktop_id"),
      desktopName: object.string("desktop_name"),
      deviceId: object.string("device_id"),
      setupDetail: object.string("setup_detail").ifBlank(object.string("detail")),
      source: "qr",
      createdAt: now
    )
  }

  private static func isContactQRCodeObject(_ object: [String: Any]) -> Bool {
    let type = normalized(object.string("type"))
    return [contactType, hermesContactType, verifyType].contains(type) ||
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
    return agentContactTypes.contains(type) ||
      contactType == "agent" ||
      !object.string("agent_kind").isEmpty ||
      !object.string("agent_id").isEmpty ||
      !object.string("mobile_contact_id").isEmpty
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
}
