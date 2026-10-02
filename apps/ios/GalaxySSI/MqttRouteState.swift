import Foundation

// Counters and remote watermarks survive retiring a connection or unpairing a live binding.
final class MqttRouteState {
  enum RecordResult: Equatable { case new, duplicate, stale, conflict }
  private static let lock = NSRecursiveLock()
  private let defaults: UserDefaults
  private let secrets: GalaxySSISecretStore
  private struct State: Codable {
    var localEpoch: Int64 = 0
    var remoteEpoch: Int64 = 0
    var remoteDigest = ""
    var remote: MqttRouteAdvertisement?
  }

  init(defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared) {
    self.defaults = defaults
    self.secrets = secrets
  }

  func issue(peer: String, sender: String, receiver: String, brokers: Set<String>, now: Int64) throws -> MqttRouteAdvertisement {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let key = try storageKey(peer)
    var state = try load(key)
    guard state.localEpoch < MqttRouteProtocol.maximumInteger else { throw MqttRouteError.exhaustedEpoch }
    guard now >= 0, now <= MqttRouteProtocol.maximumInteger - MqttRouteProtocol.resumeTTL else {
      throw MqttRouteError.invalidPayload
    }
    let advertisement = MqttRouteAdvertisement(
      sender: sender, receiver: receiver, epoch: max(state.localEpoch + 1, now),
      resumeId: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
      issuedAt: now, expiresAt: now + MqttRouteProtocol.resumeTTL,
      receiveBrokers: brokers, packetBytes: MqttRouteProtocol.packetBytes
    )
    _ = try MqttRouteAdvertisement.parseVerified(advertisement.wire(), sender: sender, receiver: receiver, now: now)
    state.localEpoch = advertisement.epoch
    try save(state, key: key)
    return advertisement
  }

  func record(peer: String, advertisement: MqttRouteAdvertisement, now: Int64) throws -> RecordResult {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    _ = try MqttRouteAdvertisement.parseVerified(advertisement.wire(), sender: advertisement.sender,
                                               receiver: advertisement.receiver, now: now)
    let key = try storageKey(peer)
    var state = try load(key)
    let digest = try advertisement.digest()
    if advertisement.epoch < state.remoteEpoch { return .stale }
    if advertisement.epoch == state.remoteEpoch { return digest == state.remoteDigest ? .duplicate : .conflict }
    state.remoteEpoch = advertisement.epoch
    state.remoteDigest = digest
    state.remote = advertisement
    try save(state, key: key)
    return .new
  }

  func cached(peer: String, sender: String, receiver: String, now: Int64) throws -> MqttRouteAdvertisement? {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    guard let cached = try load(storageKey(peer)).remote else { return nil }
    return try? MqttRouteAdvertisement.parseVerified(cached.wire(), sender: sender, receiver: receiver, now: now)
  }

  func forget(peer: String) throws {
    Self.lock.lock()
    defer { Self.lock.unlock() }
    let key = try storageKey(peer)
    var state = try load(key)
    state.remote = nil
    try save(state, key: key)
  }

  func storageKey(_ peer: String) throws -> String {
    guard !peer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, peer.utf16.count <= 512 else {
      throw MqttRouteError.invalidPayload
    }
    return "galaxyssi.mqtt.route.v1." + MqttRouteProtocol.digest(Data(peer.utf8))
  }

  private func load(_ key: String) throws -> State {
    guard defaults.object(forKey: key + ".encrypted.v1") != nil else {
      // Unexpected legacy/plaintext metadata cannot reset an anti-replay watermark.
      guard defaults.object(forKey: key) == nil else { throw MqttRouteError.unreadableState }
      return State()
    }
    guard let data = GalaxySSIEncryptedUserDefaultsStore.load(defaults: defaults, key: key, secrets: secrets),
          let state = try? JSONDecoder().decode(State.self, from: data),
          (0...MqttRouteProtocol.maximumInteger).contains(state.localEpoch),
          (0...MqttRouteProtocol.maximumInteger).contains(state.remoteEpoch),
          state.remoteEpoch == 0 || MqttRouteProtocol.hex(state.remoteDigest, count: 64) else {
      throw MqttRouteError.unreadableState
    }
    if let cached = state.remote {
      guard cached.epoch == state.remoteEpoch, (try? cached.digest()) == state.remoteDigest else {
        throw MqttRouteError.unreadableState
      }
    }
    return state
  }

  private func save(_ state: State, key: String) throws {
    guard GalaxySSIEncryptedUserDefaultsStore.write(try JSONEncoder().encode(state), defaults: defaults,
                                                   key: key, secrets: secrets) else {
      throw MqttRouteError.persistenceFailed
    }
  }
}
