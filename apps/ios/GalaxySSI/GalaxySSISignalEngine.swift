import CryptoKit
import Foundation

struct GalaxySSISignalIdentity {
  let name: String
  let fingerprint: String
  let publicKey: String
  let bundle: [String: Any]?
}

#if canImport(LibSignalClient)
import LibSignalClient

final class GalaxySSISignalEngine {
  static let isAvailable = true

  private let store: GalaxySSISignalProtocolStore
  private var journal: MqttSignalStateJournal?
  private let context = GalaxySSISignalStoreContext()
  private let localName: String
  private let localDeviceId: UInt32 = 1

  init(
    profileName: String,
    defaults: UserDefaults = .standard,
    secrets: GalaxySSISecretStore = KeychainSecretStore.shared
  ) {
    store = GalaxySSISignalProtocolStore(defaults: defaults, secrets: secrets)
    let fingerprint = Self.sha256(store.identityKeyPair.publicKey.serialize())
    localName = "galaxyssi:\(fingerprint.prefix(16))"
  }

  var identity: GalaxySSISignalIdentity {
    let identityKey = store.identityKeyPair.publicKey.serialize()
    let fingerprint = Self.sha256(identityKey)
    return GalaxySSISignalIdentity(
      name: localName,
      fingerprint: fingerprint,
      publicKey: identityKey.base64EncodedString(),
      bundle: localBundle()
    )
  }

  init(profileName: String, journal: MqttSignalStateJournal, defaults: UserDefaults = .standard,
       secrets: GalaxySSISecretStore = KeychainSecretStore.shared) throws {
    store = try GalaxySSISignalProtocolStore(journal: journal, defaults: defaults, secrets: secrets)
    self.journal = journal
    let fingerprint = Self.sha256(store.identityKeyPair.publicKey.serialize())
    localName = "galaxyssi:\(fingerprint.prefix(16))"
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
    try? store.transaction { _ in try makeLocalBundle() }
  }

  private func makeLocalBundle() throws -> [String: Any] {
    let preKeyId = try store.ensurePreKeyMaterial()
    let preKey = try store.loadPreKey(id: preKeyId, context: context)
    let signedPreKey = try store.loadSignedPreKey(id: 1, context: context)
    let kyberPreKey = try store.loadKyberPreKey(id: 1, context: context)
    let preKeyPublic = try preKey.publicKey()
    let signedPreKeyPublic = try signedPreKey.publicKey()
    let kyberPreKeyPublic = try kyberPreKey.publicKey()
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

  func processBundle(
    _ json: [String: Any],
    remoteName: String = "",
    replaceExisting: Bool = false
  ) -> Bool {
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
      return try store.transaction { _ in
        if !replaceExisting, store.containsSession(name: name, deviceId: deviceId) { return true }
        if replaceExisting {
          try store.removeSession(name: name, deviceId: deviceId)
        }
        try processPreKeyBundle(
          bundle,
          for: address,
          ourAddress: localAddress,
          sessionStore: store,
          identityStore: store,
          context: context
        )
        return true
      }
    } catch {
      return false
    }
  }

  func derivePhoneRelationshipRoutes(
    remoteIdentityPublicKey: String,
    expectedRemoteFingerprint: String
  ) -> GalaxySSILinkRoutes? {
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
    guard let linkSecret = try? GalaxySSILinkProtocol.deriveIdentityBoundLinkSecret(
      sharedSecret: sharedSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    ), let routeId = try? GalaxySSILinkProtocol.deriveIdentityBoundRouteId(
      linkSecret: linkSecret,
      firstFingerprint: localFingerprint,
      secondFingerprint: remoteFingerprint
    ) else { return nil }
    let routes = GalaxySSILinkRoutes(
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

  @discardableResult
  func forgetRemote(remoteName: String) -> Bool {
    do {
      try store.transaction { _ in try store.removeRemote(name: remoteName) }
      return true
    } catch { return false }
  }

  func encrypt(_ payload: [String: Any], remoteName: String, deviceId: UInt32 = 1) -> [String: Any]? {
    guard journal == nil, hasSession(remoteName: remoteName, deviceId: deviceId),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
    return try? store.transaction { _ in
      try encryptPayload(data, remoteName: remoteName, deviceID: deviceId, now: Date())
    }
  }

  func encryptAndEnqueue(_ request: MqttSignalSendRequest, now: Date = Date()) throws -> MqttBusinessOutbox.Entry {
    guard let entry = try enqueueBatch([request], now: now).first else { throw MqttRouteError.invalidPayload }
    return entry
  }

  // The coordinator must hold its current approved binding while queueing. No network I/O is done here.
  // Attachment-blocked requests remain encrypted at rest, without advancing a Signal sending chain.
  func enqueueBatch(_ requests: [MqttSignalSendRequest], now: Date = Date()) throws -> [MqttBusinessOutbox.Entry] {
    guard let journal, let first = requests.first, (1...64).contains(requests.count),
          requests.allSatisfy({ $0.identity == first.identity }),
          first.identity.local == Self.sha256(store.identityKeyPair.publicKey.serialize()),
          requests.reduce(0, { $0 + $1.payload.count }) <= 4 * 1024 * 1024 else { throw MqttRouteError.invalidPayload }
    let hashes = try requests.map { try $0.digest() }
    guard Set(requests.map(\.messageID)).count == requests.count else { throw MqttRouteError.invalidPayload }
    return try store.transaction { token in
      guard let token else { throw MqttChunkStorageError.databaseFailure }
      return try zip(requests, hashes).map { request, hash in
        if let existing = try journal.outbox.entry(identity: request.identity, messageID: request.messageID, transaction: token) {
          guard existing.requestHash == hash, existing.traffic == request.traffic.rawValue, request.matches(existing.message) else {
            throw MqttChunkStorageError.corruptState
          }
          return existing
        }
        if request.attachmentDependencies.isEmpty {
          let wire = try outgoingWire(request, now: now)
          try journal.outbox.enqueue(identity: request.identity, message: request.pendingMessage(wire: wire, now: now),
            traffic: request.traffic, requestHash: hash, transaction: token)
        } else {
          try journal.outbox.enqueueDeferred(request, now: now, transaction: token)
        }
        guard let saved = try journal.outbox.entry(identity: request.identity, messageID: request.messageID, transaction: token) else {
          throw MqttChunkStorageError.corruptState
        }
        return saved
      }
    }
  }

  func prepareFirstSend(identity: MqttBusinessIdentity, messageID: String, validatedNetwork: Bool,
                        now: Date = Date()) throws -> MqttBusinessOutbox.Entry? {
    guard let journal, identity.local == Self.sha256(store.identityKeyPair.publicKey.serialize()) else { throw MqttRouteError.identityChanged }
    return try store.transaction { token in
      guard let token else { throw MqttChunkStorageError.databaseFailure }
      guard let entry = try journal.outbox.entry(identity: identity, messageID: messageID, transaction: token),
            entry.message.blockedByAttachmentTransferIds.isEmpty,
            !entry.message.requiresValidatedNetwork || validatedNetwork else { return nil }
      guard let request = entry.deferredRequest else { return entry }
      let hash = try request.digest()
      let wire = try outgoingWire(request, now: now)
      return try journal.outbox.prepare(identity: identity, messageID: messageID, requestHash: hash, wire: wire, now: now, transaction: token)
    }
  }

  private func outgoingWire(_ request: MqttSignalSendRequest, now: Date) throws -> String {
    try request.validate()
    let address = try ProtocolAddress(name: request.remoteName, deviceId: request.deviceID)
    guard let known = try store.identity(for: address, context: context),
          Self.sha256(known.serialize()) == request.identity.remote,
          store.containsSession(name: request.remoteName, deviceId: request.deviceID) else { throw MqttRouteError.identityChanged }
    var wire = try encryptPayload(request.payload, remoteName: request.remoteName, deviceID: request.deviceID, now: now)
    wire["message_id"] = request.messageID
    if let route = request.clientRouteID { wire["_client_route_id"] = route }
    return String(decoding: try GalaxySSILinkProtocol.jsonData(wire), as: UTF8.self)
  }

  private func encryptPayload(_ data: Data, remoteName: String, deviceID: UInt32, now: Date) throws -> [String: Any] {
    let time = now.timeIntervalSince1970 * 1000
    guard time.isFinite, time >= 0, time <= Double(MqttRouteProtocol.maximumInteger) else { throw MqttRouteError.invalidPayload }
    let address = try ProtocolAddress(name: remoteName, deviceId: deviceID)
    let localAddress = try ProtocolAddress(name: localName, deviceId: localDeviceId)
    let message = try signalEncrypt(message: data, for: address, localAddress: localAddress,
      sessionStore: store, identityStore: store, context: context)
    return ["version": 1, "scheme": "signal", "from": localName, "to": remoteName, "device_id": deviceID,
      "signal_type": message.messageType == .preKey ? "prekey" : "signal",
      "message_type": Int(message.messageType.rawValue), "body": message.serialize().base64EncodedString(), "time": Int64(time)]
  }

  func decrypt(_ envelope: [String: Any]) -> [String: Any]? {
    // Durable callers must use decryptAndStore so a successful decrypt cannot lose its inbox record.
    guard journal == nil else { return nil }
    return try? store.transaction { _ in try decryptPayload(envelope) }
  }

  // The coordinator must invoke this under MqttPeerRoutes.withCurrent after pair-AEAD authentication.
  func decryptAndStore(_ envelope: [String: Any], identity: MqttBusinessIdentity,
                       remoteName: String, ingressBroker: String) throws -> MqttBusinessInbox.Accepted {
    guard let journal, identity.local == Self.sha256(store.identityKeyPair.publicKey.serialize()),
          envelope["from"] as? String == remoteName, envelope["to"] as? String == localName else {
      throw MqttRouteError.identityChanged
    }
    try identity.validate()
    let wireHash = try MqttDeliveryEnvelope.contentHash(envelope)
    let frame = try envelope[MqttDeliveryEnvelope.field].map { _ in
      try MqttDeliveryEnvelope.parseVerifiedFrame(envelope, sender: identity.remote,
        receiver: identity.local, ingressBroker: ingressBroker)
    }
    return try store.transaction { token in
      guard let token else { throw MqttChunkStorageError.databaseFailure }
      if let replay = try journal.inbox.replay(identity: identity, ciphertextDigest: wireHash, transaction: token) {
        if let frame {
          guard replay.key == (try identity.key(messageID: frame.message.messageID)),
                (replay.receipt != nil) == (frame.message.traffic != "receipt") else { throw MqttRouteError.invalidPayload }
        }
        return replay
      }
      let payload = try decryptPayload(envelope)
      let address = try ProtocolAddress(name: remoteName, deviceId: signalDeviceID(envelope))
      guard let remoteKey = try store.identity(for: address, context: context),
            Self.sha256(remoteKey.serialize()) == identity.remote else { throw MqttRouteError.identityChanged }
      let messageID = try MqttDeliveryEnvelope.checkedText(payload["message_id"])
      let type = payload["type"] as? String
      return try journal.inbox.accept(identity: identity, messageID: messageID, payload: payload,
        ciphertextDigest: wireHash, wireHash: wireHash,
        receiptRequired: type != "delivery_ack" && type != MqttDeliveryEnvelope.receiptType,
        frame: frame, transaction: token)
    }
  }

  private func signalDeviceID(_ envelope: [String: Any]) throws -> UInt32 {
    guard envelope["device_id"] != nil else { return 1 }
    let id = try MqttRouteProtocol.integer(envelope, "device_id")
    guard id > 0, id <= Int64(UInt32.max) else { throw MqttRouteError.invalidPayload }
    return UInt32(id)
  }

  private func decryptPayload(_ envelope: [String: Any]) throws -> [String: Any] {
    guard envelope.string("scheme") == "signal",
          let from = envelope["from"] as? String,
          !from.isEmpty,
          let body = Data(base64Encoded: envelope.string("body")) else { throw MqttRouteError.invalidPayload }
    let remoteAddress = try ProtocolAddress(name: from, deviceId: signalDeviceID(envelope))
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
    guard let payload = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else { throw MqttRouteError.invalidPayload }
    return payload
  }

  private func decode(_ value: String) throws -> Data {
    guard let data = Data(base64Encoded: value), !data.isEmpty else {
      throw GalaxySSIError.invalidPayload("Invalid Signal bundle encoding")
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
final class GalaxySSISignalEngine {
  static let isAvailable = false
  init(profileName: String, defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {}
  init(profileName: String, journal: MqttSignalStateJournal, defaults: UserDefaults = .standard,
       secrets: GalaxySSISecretStore = KeychainSecretStore.shared) throws { throw MqttRouteError.invalidPayload }
  var identity: GalaxySSISignalIdentity { GalaxySSISignalIdentity(name: "", fingerprint: "", publicKey: "", bundle: nil) }
  func signContactCard(_ payload: Data) -> String? { nil }
  static func verifyContactCard(publicKey: String, payload: Data, signature: String) -> Bool { false }
  static func bundleIdentityFingerprint(_ bundle: [String: Any]) -> String? { nil }
  func localBundle() -> [String: Any]? { nil }
  func processBundle(
    _ json: [String: Any],
    remoteName: String = "",
    replaceExisting: Bool = false
  ) -> Bool { false }
  func derivePhoneRelationshipRoutes(
    remoteIdentityPublicKey: String,
    expectedRemoteFingerprint: String
  ) -> GalaxySSILinkRoutes? { nil }
  func hasSession(remoteName: String, deviceId: UInt32 = 1) -> Bool { false }
  @discardableResult
  func forgetRemote(remoteName: String) -> Bool { false }
  func decryptAndStore(_ envelope: [String: Any], identity: MqttBusinessIdentity,
                       remoteName: String, ingressBroker: String) throws -> MqttBusinessInbox.Accepted {
    throw MqttRouteError.invalidPayload
  }
  func encrypt(_ payload: [String: Any], remoteName: String, deviceId: UInt32 = 1) -> [String: Any]? { nil }
  func encryptAndEnqueue(_ request: MqttSignalSendRequest, now: Date = Date()) throws -> MqttBusinessOutbox.Entry { throw MqttRouteError.invalidPayload }
  func enqueueBatch(_ requests: [MqttSignalSendRequest], now: Date = Date()) throws -> [MqttBusinessOutbox.Entry] { throw MqttRouteError.invalidPayload }
  func prepareFirstSend(identity: MqttBusinessIdentity, messageID: String, validatedNetwork: Bool,
                        now: Date = Date()) throws -> MqttBusinessOutbox.Entry? { throw MqttRouteError.invalidPayload }
  func decrypt(_ envelope: [String: Any]) -> [String: Any]? { nil }
}
#endif

private extension String? {
  func ifBlank(_ fallback: String) -> String {
    guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
    return value
  }
}
