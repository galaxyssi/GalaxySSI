import CryptoKit
import Foundation

struct SignalASISignalIdentity {
  let name: String
  let fingerprint: String
  let publicKey: String
  let bundle: [String: Any]?
}

#if canImport(LibSignalClient)
import LibSignalClient

final class SignalASISignalEngine {
  static let isAvailable = true

  private let store: SignalASISignalProtocolStore
  private let context = SignalASISignalStoreContext()
  private let localName: String
  private let localDeviceId: UInt32 = 1

  init(
    profileName: String,
    defaults: UserDefaults = .standard,
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    store = SignalASISignalProtocolStore(defaults: defaults, secrets: secrets)
    let fingerprint = Self.sha256(store.identityKeyPair.publicKey.serialize())
    localName = "signalasi:\(fingerprint.prefix(16))"
  }

  var identity: SignalASISignalIdentity {
    let identityKey = store.identityKeyPair.publicKey.serialize()
    let fingerprint = Self.sha256(identityKey)
    return SignalASISignalIdentity(
      name: localName,
      fingerprint: fingerprint,
      publicKey: identityKey.base64EncodedString(),
      bundle: localBundle()
    )
  }

  func signContactCard(_ payload: Data) -> String? {
    guard !payload.isEmpty else { return nil }
    return identityKeySignature(payload)?.base64EncodedString()
  }

  static func verifyContactCard(
    publicKey: String,
    payload: Data,
    signature: String
  ) -> Bool {
    guard !payload.isEmpty,
          let publicKeyData = Data(base64Encoded: publicKey),
          let signatureData = Data(base64Encoded: signature),
          !publicKeyData.isEmpty,
          !signatureData.isEmpty,
          let key = try? PublicKey(publicKeyData) else {
      return false
    }
    return (try? key.verifySignature(message: payload, signature: signatureData)) == true
  }

  static func bundleIdentityFingerprint(_ bundle: [String: Any]) -> String? {
    guard let identityKey = Data(base64Encoded: bundle.string("identityKey")), !identityKey.isEmpty else {
      return nil
    }
    return sha256(identityKey)
  }

  func localBundle() -> [String: Any]? {
    guard let preKeyId = try? store.ensurePreKeyMaterial(),
          let preKey = try? store.loadPreKey(id: preKeyId, context: context),
          let signedPreKey = try? store.loadSignedPreKey(id: 1, context: context),
          let kyberPreKey = try? store.loadKyberPreKey(id: 1, context: context),
          let preKeyPublic = try? preKey.publicKey(),
          let signedPreKeyPublic = try? signedPreKey.publicKey(),
          let kyberPreKeyPublic = try? kyberPreKey.publicKey() else { return nil }
    let identityKey = store.identityKeyPair.publicKey.serialize()
    return [
      "version": 1,
      "scheme": "signal",
      "name": localName,
      "deviceId": localDeviceId,
      "registrationId": store.registrationId,
      "identityKey": identityKey.base64EncodedString(),
      "identityKeySha256": Self.sha256(identityKey),
      "preKeyId": preKeyId,
      "preKey": preKeyPublic.serialize().base64EncodedString(),
      "signedPreKeyId": 1,
      "signedPreKey": signedPreKeyPublic.serialize().base64EncodedString(),
      "signedPreKeySignature": signedPreKey.signature.base64EncodedString(),
      "kyberPreKeyId": 1,
      "kyberPreKey": kyberPreKeyPublic.serialize().base64EncodedString(),
      "kyberPreKeySignature": kyberPreKey.signature.base64EncodedString()
    ]
  }

  func processBundle(_ json: [String: Any], remoteName: String = "") -> Bool {
    do {
      let name = (json["name"] as? String).ifBlank(remoteName)
      guard !name.isEmpty else { return false }
      let deviceId = UInt32(json["deviceId"] as? Int ?? 1)
      let bundle = try PreKeyBundle(
        registrationId: UInt32(json["registrationId"] as? Int ?? 0),
        deviceId: deviceId,
        prekeyId: UInt32(json["preKeyId"] as? Int ?? 1),
        prekey: try PublicKey(bytes: decode(json.string("preKey"))),
        signedPrekeyId: UInt32(json["signedPreKeyId"] as? Int ?? 1),
        signedPrekey: try PublicKey(bytes: decode(json.string("signedPreKey"))),
        signedPrekeySignature: decode(json.string("signedPreKeySignature")),
        identity: IdentityKey(bytes: decode(json.string("identityKey"))),
        kyberPrekeyId: UInt32(json["kyberPreKeyId"] as? Int ?? 1),
        kyberPrekey: try KEMPublicKey(decode(json.string("kyberPreKey"))),
        kyberPrekeySignature: decode(json.string("kyberPreKeySignature"))
      )
      let address = try ProtocolAddress(name: name, deviceId: deviceId)
      let localAddress = try ProtocolAddress(name: localName, deviceId: localDeviceId)
      try processPreKeyBundle(
        bundle,
        for: address,
        ourAddress: localAddress,
        sessionStore: store,
        identityStore: store,
        context: context
      )
      return true
    } catch {
      return false
    }
  }

  func derivePhoneRelationshipRoutes(
    remoteIdentityPublicKey: String,
    expectedRemoteFingerprint: String
  ) -> SignalASILinkRoutes? {
    guard let remoteData = Data(base64Encoded: remoteIdentityPublicKey),
          let remoteKey = try? PublicKey(remoteData) else { return nil }
    let remoteFingerprint = Self.sha256(remoteKey.serialize())
    guard remoteFingerprint.caseInsensitiveCompare(expectedRemoteFingerprint) == .orderedSame else {
      return nil
    }
    let localFingerprint = identity.fingerprint
    guard localFingerprint.caseInsensitiveCompare(remoteFingerprint) != .orderedSame else {
      return nil
    }
    let sharedSecret = store.identityKeyPair.privateKey.keyAgreement(with: remoteKey)
    guard let linkSecret = try? SignalASILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: sharedSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    ), let routeId = try? SignalASILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: linkSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    ) else { return nil }
    let routes = SignalASILinkRoutes(
      clientRouteId: routeId,
      linkSecret: linkSecret,
      localFingerprint: localFingerprint,
      remoteFingerprint: remoteFingerprint
    )
    return routes.isOpaqueV2Valid ? routes : nil
  }

  func hasSession(remoteName: String, deviceId: UInt32 = 1) -> Bool {
    store.containsSession(name: remoteName, deviceId: deviceId)
  }

  func forgetRemote(remoteName: String) {
    store.removeRemote(name: remoteName)
  }

  func encrypt(_ payload: [String: Any], remoteName: String, deviceId: UInt32 = 1) -> [String: Any]? {
    guard hasSession(remoteName: remoteName, deviceId: deviceId),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
    do {
      let address = try ProtocolAddress(name: remoteName, deviceId: deviceId)
      let localAddress = try ProtocolAddress(name: localName, deviceId: localDeviceId)
      let message = try signalEncrypt(
        message: data,
        for: address,
        localAddress: localAddress,
        sessionStore: store,
        identityStore: store,
        context: context
      )
      return [
        "version": 1,
        "scheme": "signal",
        "from": localName,
        "to": remoteName,
        "device_id": deviceId,
        "signal_type": message.messageType == .preKey ? "prekey" : "signal",
        "message_type": Int(message.messageType.rawValue),
        "body": message.serialize().base64EncodedString(),
        "time": Int64(Date().timeIntervalSince1970 * 1_000)
      ]
    } catch {
      return nil
    }
  }

  func decrypt(_ envelope: [String: Any]) -> [String: Any]? {
    guard envelope.string("scheme") == "signal",
          let from = envelope["from"] as? String,
          !from.isEmpty,
          let body = Data(base64Encoded: envelope.string("body")) else { return nil }
    do {
      let remoteAddress = try ProtocolAddress(name: from, deviceId: UInt32(envelope["device_id"] as? Int ?? 1))
      let localAddress = try ProtocolAddress(name: localName, deviceId: localDeviceId)
      let type = envelope.string("signal_type")
      let plaintext: Data
      if type == "prekey" || (envelope["message_type"] as? Int) == Int(CiphertextMessage.MessageType.preKey.rawValue) {
        plaintext = try signalDecryptPreKey(
          message: PreKeySignalMessage(bytes: body),
          from: remoteAddress,
          localAddress: localAddress,
          sessionStore: store,
          identityStore: store,
          preKeyStore: store,
          signedPreKeyStore: store,
          kyberPreKeyStore: store,
          context: context
        )
      } else {
        plaintext = try signalDecrypt(
          message: SignalMessage(bytes: body),
          from: remoteAddress,
          to: localAddress,
          sessionStore: store,
          identityStore: store,
          context: context
        )
      }
      return try JSONSerialization.jsonObject(with: plaintext) as? [String: Any]
    } catch {
      return nil
    }
  }

  private func decode(_ value: String) throws -> Data {
    guard let data = Data(base64Encoded: value), !data.isEmpty else {
      throw SignalASIError.invalidPayload("Invalid Signal bundle encoding")
    }
    return data
  }

  private func identityKeySignature(_ payload: Data) -> Data? {
    store.identityKeyPair.privateKey.generateSignature(message: payload)
  }

  private static func sha256(_ data: Data) -> String {
    Data(CryptoKit.SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
  }
}
#else
final class SignalASISignalEngine {
  static let isAvailable = false
  init(profileName: String, defaults: UserDefaults = .standard, secrets: SignalASISecretStore = KeychainSecretStore.shared) {}
  var identity: SignalASISignalIdentity { SignalASISignalIdentity(name: "", fingerprint: "", publicKey: "", bundle: nil) }
  func signContactCard(_ payload: Data) -> String? { nil }
  static func verifyContactCard(publicKey: String, payload: Data, signature: String) -> Bool { false }
  static func bundleIdentityFingerprint(_ bundle: [String: Any]) -> String? { nil }
  func localBundle() -> [String: Any]? { nil }
  func processBundle(_ json: [String: Any], remoteName: String = "") -> Bool { false }
  func derivePhoneRelationshipRoutes(
    remoteIdentityPublicKey: String,
    expectedRemoteFingerprint: String
  ) -> SignalASILinkRoutes? { nil }
  func hasSession(remoteName: String, deviceId: UInt32 = 1) -> Bool { false }
  func forgetRemote(remoteName: String) {}
  func encrypt(_ payload: [String: Any], remoteName: String, deviceId: UInt32 = 1) -> [String: Any]? { nil }
  func decrypt(_ envelope: [String: Any]) -> [String: Any]? { nil }
}
#endif

private extension String? {
  func ifBlank(_ fallback: String) -> String {
    guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
    return value
  }
}
