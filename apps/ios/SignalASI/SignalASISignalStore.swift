import CryptoKit
import Foundation

#if canImport(LibSignalClient)
import LibSignalClient

struct SignalASISignalStoreContext: StoreContext {}

final class SignalASISignalProtocolStore: IdentityKeyStore, PreKeyStore, SignedPreKeyStore, KyberPreKeyStore,
  SessionStore, SenderKeyStore {
  private struct State: Codable {
    var identityKeyPair: Data
    var registrationId: UInt32
    var identities: [String: Data]
    var preKeys: [String: Data]
    var activePreKeyId: UInt32?
    var signedPreKeys: [String: Data]
    var kyberPreKeys: [String: Data]
    var sessions: [String: Data]
    var senderKeys: [String: Data]
    var usedKyberKeys: Set<String>
  }

  private let defaults: UserDefaults
  private let secrets: SignalASISecretStore
  private let stateKey = "signalasi-ios-libsignal-state-v1"
  private let encryptionKeyAccount = "signal.libsignal.state.aes256"
  private let context = SignalASISignalStoreContext()
  private let lock = NSLock()
  private var state: State
  let identityKeyPair: IdentityKeyPair
  let registrationId: UInt32

  init(
    defaults: UserDefaults = .standard,
    secrets: SignalASISecretStore = KeychainSecretStore.shared
  ) {
    self.defaults = defaults
    self.secrets = secrets
    let createdIdentity: Bool
    if let restored = Self.loadState(
      defaults: defaults,
      secrets: secrets,
      stateKey: stateKey,
      encryptionKeyAccount: encryptionKeyAccount
    ), let pair = try? IdentityKeyPair(bytes: restored.identityKeyPair) {
      state = restored
      identityKeyPair = pair
      registrationId = restored.registrationId
      createdIdentity = false
    } else {
      let pair = IdentityKeyPair.generate()
      let registration = UInt32.random(in: 1..<16_384)
      state = State(
        identityKeyPair: pair.serialize(),
        registrationId: registration,
        identities: [:],
        preKeys: [:],
        activePreKeyId: nil,
        signedPreKeys: [:],
        kyberPreKeys: [:],
        sessions: [:],
        senderKeys: [:],
        usedKyberKeys: []
      )
      identityKeyPair = pair
      registrationId = registration
      createdIdentity = true
      persist()
    }
    do {
      try ensurePreKeyMaterial(newIdentity: createdIdentity)
    } catch {
      assertionFailure("Unable to initialize Signal pre-key material: \(error)")
    }
  }

  func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair { identityKeyPair }

  func localRegistrationId(context: StoreContext) throws -> UInt32 { registrationId }

  func saveIdentity(
    _ identity: IdentityKey,
    for address: ProtocolAddress,
    context: StoreContext
  ) throws -> IdentityChange {
    lock.lock()
    defer { lock.unlock() }
    let key = addressKey(address)
    let encoded = identity.serialize()
    let previous = state.identities.updateValue(encoded, forKey: key)
    persistLocked()
    return previous == nil || previous == encoded ? .newOrUnchanged : .replacedExisting
  }

  func isTrustedIdentity(
    _ identity: IdentityKey,
    for address: ProtocolAddress,
    direction: Direction,
    context: StoreContext
  ) throws -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let known = state.identities[addressKey(address)] else { return true }
    return known == identity.serialize()
  }

  func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
    lock.lock()
    let bytes = state.identities[addressKey(address)]
    lock.unlock()
    guard let bytes else { return nil }
    return try IdentityKey(bytes: bytes)
  }

  func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
    lock.lock()
    let bytes = state.preKeys[String(id)]
    lock.unlock()
    guard let bytes else { throw SignalError.invalidKeyIdentifier("No pre-key: \(id)") }
    return try PreKeyRecord(bytes: bytes)
  }

  func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
    lock.lock()
    state.preKeys[String(id)] = record.serialize()
    persistLocked()
    lock.unlock()
  }

  func removePreKey(id: UInt32, context: StoreContext) throws {
    lock.lock()
    state.preKeys.removeValue(forKey: String(id))
    persistLocked()
    lock.unlock()
  }

  func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
    lock.lock()
    let bytes = state.signedPreKeys[String(id)]
    lock.unlock()
    guard let bytes else { throw SignalError.invalidKeyIdentifier("No signed pre-key: \(id)") }
    return try SignedPreKeyRecord(bytes: bytes)
  }

  func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
    lock.lock()
    state.signedPreKeys[String(id)] = record.serialize()
    persistLocked()
    lock.unlock()
  }

  func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
    lock.lock()
    let bytes = state.kyberPreKeys[String(id)]
    lock.unlock()
    guard let bytes else { throw SignalError.invalidKeyIdentifier("No Kyber pre-key: \(id)") }
    return try KyberPreKeyRecord(bytes: bytes)
  }

  func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
    lock.lock()
    state.kyberPreKeys[String(id)] = record.serialize()
    persistLocked()
    lock.unlock()
  }

  func markKyberPreKeyUsed(
    id: UInt32,
    signedPreKeyId: UInt32,
    baseKey: PublicKey,
    context: StoreContext
  ) throws {
    lock.lock()
    defer { lock.unlock() }
    let key = "\(id)|\(signedPreKeyId)|\(baseKey.serialize().base64EncodedString())"
    guard !state.usedKyberKeys.contains(key) else {
      throw SignalError.invalidMessage("reused Kyber base key")
    }
    state.usedKyberKeys.insert(key)
    persistLocked()
  }

  func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
    lock.lock()
    let bytes = state.sessions[addressKey(address)]
    lock.unlock()
    return try bytes.map { try SessionRecord(bytes: $0) }
  }

  func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
    try addresses.map { address in
      guard let record = try loadSession(for: address, context: context) else {
        throw SignalError.sessionNotFound(address.debugDescription)
      }
      return record
    }
  }

  func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
    lock.lock()
    state.sessions[addressKey(address)] = record.serialize()
    persistLocked()
    lock.unlock()
  }

  func storeSenderKey(
    from sender: ProtocolAddress,
    distributionId: UUID,
    record: SenderKeyRecord,
    context: StoreContext
  ) throws {
    lock.lock()
    state.senderKeys[senderKey(sender, distributionId)] = record.serialize()
    persistLocked()
    lock.unlock()
  }

  func loadSenderKey(
    from sender: ProtocolAddress,
    distributionId: UUID,
    context: StoreContext
  ) throws -> SenderKeyRecord? {
    lock.lock()
    let bytes = state.senderKeys[senderKey(sender, distributionId)]
    lock.unlock()
    return try bytes.map { try SenderKeyRecord(bytes: $0) }
  }

  func containsSession(name: String, deviceId: UInt32) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return state.sessions["\(name)|\(deviceId)"] != nil
  }

  func removeSession(name: String, deviceId: UInt32) {
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty else { return }
    lock.lock()
    state.sessions.removeValue(forKey: "\(cleanName)|\(deviceId)")
    persistLocked()
    lock.unlock()
  }

  func removeRemote(name: String) {
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty else { return }
    let prefix = "\(cleanName)|"
    lock.lock()
    state.identities.removeAll { $0.key.hasPrefix(prefix) }
    state.sessions.removeAll { $0.key.hasPrefix(prefix) }
    state.senderKeys.removeAll { $0.key.hasPrefix(prefix) }
    persistLocked()
    lock.unlock()
  }

  @discardableResult
  func ensurePreKeyMaterial(newIdentity: Bool = false) throws -> UInt32 {
    lock.lock()
    defer { lock.unlock() }

    let validPreKeyIds = state.preKeys.compactMap { key, value -> UInt32? in
      guard let id = UInt32(key), Self.validPreKeyId(id),
            (try? PreKeyRecord(bytes: value)) != nil else { return nil }
      return id
    }.sorted()
    let occupiedPreKeyIds = Set(state.preKeys.keys.compactMap { UInt32($0) })
    let storedActiveId = state.activePreKeyId.flatMap { Self.validPreKeyId($0) ? $0 : nil }
    let reusableId = storedActiveId.flatMap { validPreKeyIds.contains($0) ? $0 : nil }
      ?? (storedActiveId == nil ? validPreKeyIds.first : nil)
    let activeId = reusableId ?? Self.nextAvailablePreKeyId(
      after: storedActiveId ?? (newIdentity ? 0 : 1),
      occupied: occupiedPreKeyIds
    )

    if !validPreKeyIds.contains(activeId) {
      state.preKeys[String(activeId)] = PreKeyRecord(
        id: activeId,
        privateKey: PrivateKey.generate()
      ).serialize()
    }
    state.activePreKeyId = activeId

    if state.signedPreKeys["1"].flatMap({ try? SignedPreKeyRecord(bytes: $0) }) == nil {
      let privateKey = PrivateKey.generate()
      let signature = identityKeyPair.privateKey.generateSignature(message: privateKey.publicKey.serialize())
      state.signedPreKeys["1"] = try SignedPreKeyRecord(
        id: 1,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1_000),
        privateKey: privateKey,
        signature: signature
      ).serialize()
    }
    if state.kyberPreKeys["1"].flatMap({ try? KyberPreKeyRecord(bytes: $0) }) == nil {
      let keyPair = KEMKeyPair.generate()
      let signature = identityKeyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())
      state.kyberPreKeys["1"] = try KyberPreKeyRecord(
        id: 1,
        timestamp: UInt64(Date().timeIntervalSince1970 * 1_000),
        keyPair: keyPair,
        signature: signature
      ).serialize()
    }
    persistLocked()
    return activeId
  }

  private static func validPreKeyId(_ id: UInt32) -> Bool {
    id >= 1 && id <= 0xFF_FFFF
  }

  private static func nextAvailablePreKeyId(after id: UInt32, occupied: Set<UInt32>) -> UInt32 {
    var candidate = id >= 0xFF_FFFF || id == 0 ? 1 : id + 1
    for _ in 0...occupied.count {
      if !occupied.contains(candidate) { return candidate }
      candidate = candidate >= 0xFF_FFFF ? 1 : candidate + 1
    }
    preconditionFailure("No Signal pre-key ID is available")
  }

  private func persist() {
    lock.lock()
    persistLocked()
    lock.unlock()
  }

  private func persistLocked() {
    guard let encoded = try? JSONEncoder().encode(state),
          let key = encryptionKey(),
          let sealed = try? AES.GCM.seal(encoded, using: key, authenticating: Data(stateKey.utf8)),
          let combined = sealed.combined else { return }
    defaults.set(combined, forKey: stateKey)
  }

  private func encryptionKey() -> SymmetricKey? {
    if let encoded = secrets.string(account: encryptionKeyAccount),
       let data = Data(base64Encoded: encoded),
       data.count == 32 {
      return SymmetricKey(data: data)
    }
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    try? secrets.setString(data.base64EncodedString(), account: encryptionKeyAccount)
    return key
  }

  private func addressKey(_ address: ProtocolAddress) -> String { "\(address.name)|\(address.deviceId)" }

  private func senderKey(_ address: ProtocolAddress, _ distributionId: UUID) -> String {
    "\(addressKey(address))|\(distributionId.uuidString)"
  }

  private static func loadState(
    defaults: UserDefaults,
    secrets: SignalASISecretStore,
    stateKey: String,
    encryptionKeyAccount: String
  ) -> State? {
    guard let combined = defaults.data(forKey: stateKey),
          let encodedKey = secrets.string(account: encryptionKeyAccount),
          let keyData = Data(base64Encoded: encodedKey),
          keyData.count == 32,
          let sealed = try? AES.GCM.SealedBox(combined: combined),
          let decoded = try? AES.GCM.open(
            sealed,
            using: SymmetricKey(data: keyData),
            authenticating: Data(stateKey.utf8)
          ) else { return nil }
    return try? JSONDecoder().decode(State.self, from: decoded)
  }
}
#endif
