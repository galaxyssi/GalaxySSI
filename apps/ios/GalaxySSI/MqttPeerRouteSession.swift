import Foundation

struct MqttPeerRouteBinding: Equatable {
  var scope: String
  var sender: String
  var receiver: String
  // Opaque identity of the authenticated relationship, never supplied by a wire payload.
  var authenticationID: String
  var enabled = true
}

struct MqttPeerRouteControl {
  var brokerID: String
  var generation: Int64
  var payload: [String: Any]
}

struct MqttPeerRouteReception {
  var handled: Bool
  var becameReady = false
  var response: MqttPeerRouteControl?
}

// Transport-independent handshake state. The pool supplies SUBACK-ready path generations
// and must authenticate AEAD before calling receiveVerified; this type never opens sockets.
final class MqttPeerRouteSession {
  private let lock = NSRecursiveLock()
  private let persistence: MqttRouteState
  private let wall: () -> Int64
  private let monotonic: () -> Int64
  private var binding: MqttPeerRouteBinding
  private var active = true
  private var local: MqttRouteAdvertisement?
  private var remote: MqttRouteAdvertisement?
  private var remoteLeaseUntil: Int64 = 0
  private var localGenerations: [String: Int64] = [:]
  private var confirmedEpoch: Int64 = 0
  private var nextSend: Int64 = 0
  private var readyLeaseUntil: Int64 = 0
  private var readyGenerations: [String: Int64] = [:]
  private var responses: [String: (key: String, at: Int64)] = [:]
  private var lastVerifiedAt: Int64?
  private var blockedSince: Int64?
  private var lastRecoveryAt: Int64?

  init(binding: MqttPeerRouteBinding, persistence: MqttRouteState,
       wall: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
       monotonic: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1_000) }) throws {
    guard !binding.scope.isEmpty, binding.scope.utf16.count <= 512, !binding.authenticationID.isEmpty,
          MqttRouteProtocol.hex(binding.sender, count: 64), MqttRouteProtocol.hex(binding.receiver, count: 64),
          binding.sender != binding.receiver else { throw MqttRouteError.invalidPayload }
    self.binding = binding
    self.persistence = persistence
    self.wall = wall
    self.monotonic = monotonic
  }

  func setEnabled(_ enabled: Bool) {
    lock.lock()
    defer { lock.unlock() }
    binding.enabled = enabled
    if !enabled { blockedSince = nil }
  }

  func retire() throws {
    lock.lock()
    defer { lock.unlock() }
    active = false
    local = nil
    remote = nil
    localGenerations.removeAll()
    confirmedEpoch = 0
    try persistence.forget(peer: binding.scope)
  }

  func maintenance(readyGenerations: [String: Int64]) throws -> [MqttPeerRouteControl] {
    lock.lock()
    defer { lock.unlock() }
    guard active else { return [] }
    let previous = local
    guard let advertisement = try prepareLocal(readyGenerations) else { return [] }
    if previous == advertisement && (confirmedEpoch == advertisement.epoch || monotonic() < nextSend) { return [] }
    nextSend = monotonic() + 5_000
    return readyGenerations.keys.sorted().map {
      MqttPeerRouteControl(brokerID: $0, generation: readyGenerations[$0]!, payload: advertisement.wire())
    }
  }

  func receiveVerified(_ payload: [String: Any], brokerID: String, generation: Int64,
                       authenticationID: String, readyGenerations: [String: Int64]) throws -> MqttPeerRouteReception {
    lock.lock()
    defer { lock.unlock() }
    guard let type = payload["type"] as? String, ["link_resume", "link_resume_ack"].contains(type) else {
      return MqttPeerRouteReception(handled: false)
    }
    guard active, authenticationID == binding.authenticationID else { throw MqttRouteError.identityChanged }
    try validateGenerations(readyGenerations)
    guard readyGenerations[brokerID] == generation else { throw MqttRouteError.staleGeneration }
    let at = wall()
    let object: [String: Any]
    if type == "link_resume" { object = payload }
    else {
      guard let advertisement = payload["advertisement"] as? [String: Any] else { throw MqttRouteError.invalidPayload }
      object = advertisement
    }
    let advertisement = try MqttRouteAdvertisement.parseVerified(object, sender: binding.receiver,
                                                                 receiver: binding.sender, now: at)
    if type == "link_resume_ack" {
      guard let local else { throw MqttRouteError.unsolicitedAcknowledgement }
      let epoch = try MqttRouteProtocol.integer(payload, "acknowledged_route_epoch")
      guard let id = payload["acknowledged_resume_id"] as? String, MqttRouteProtocol.hex(id, count: 32),
            let digest = payload["acknowledged_digest"] as? String, MqttRouteProtocol.hex(digest, count: 64) else {
        throw MqttRouteError.invalidPayload
      }
      if epoch > 0 && epoch < local.epoch { return MqttPeerRouteReception(handled: true) }
      guard local.expiresAt > at, epoch == local.epoch, id == local.resumeId, digest == (try local.digest()),
            localGenerations[brokerID] == generation else { throw MqttRouteError.unsolicitedAcknowledgement }
    }
    let committed = try persistence.record(peer: binding.scope, advertisement: advertisement, now: at)
    guard committed == .new || committed == .duplicate else { return MqttPeerRouteReception(handled: true) }
    lastVerifiedAt = monotonic()
    if remote == nil || advertisement.epoch > remote!.epoch {
      remoteLeaseUntil = monotonic() + min(MqttRouteProtocol.resumeTTL, advertisement.expiresAt - at)
      remote = advertisement
    }
    if local == nil || confirmedEpoch != local?.epoch { nextSend = 0 }
    var result = MqttPeerRouteReception(handled: true)
    if type == "link_resume_ack", let local {
      let priorPathSurvives = localGenerations.contains { readyGenerations[$0.key] == $0.value && self.readyGenerations[$0.key] == $0.value }
      result.becameReady = binding.enabled && confirmedEpoch != local.epoch &&
        (readyLeaseUntil <= at || !priorPathSurvives) &&
        !advertisement.receiveBrokers.intersection(readyGenerations.keys).isEmpty
      confirmedEpoch = local.epoch
      self.readyGenerations = localGenerations
      readyLeaseUntil = min(local.expiresAt, advertisement.expiresAt)
    } else if let ours = try prepareLocal(readyGenerations) {
      let key = "\(advertisement.epoch):\(advertisement.resumeId)"
      let previous = responses[brokerID]
      if previous?.key != key || monotonic() - (previous?.at ?? 0) >= 1_000 {
        responses[brokerID] = (key, monotonic())
        result.response = MqttPeerRouteControl(brokerID: brokerID, generation: generation, payload: [
          "type": "link_resume_ack", "advertisement": ours.wire(),
          "acknowledged_route_epoch": advertisement.epoch, "acknowledged_resume_id": advertisement.resumeId,
          "acknowledged_digest": try advertisement.digest()
        ])
      }
    }
    return result
  }

  func ready(readyGenerations: [String: Int64]) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard active, binding.enabled, let local, let remote,
          local.expiresAt > wall(), remote.expiresAt > wall(), confirmedEpoch == local.epoch,
          remoteLeaseUntil > monotonic(),
          !readyGenerations.isEmpty,
          readyGenerations.allSatisfy({ localGenerations[$0.key] == $0.value }),
          !remote.receiveBrokers.intersection(readyGenerations.keys).isEmpty else { return false }
    blockedSince = nil
    return true
  }

  // Android #3234: renew only this verified peer after 30s blocked, at most once per 120s.
  // Durable epoch/replay metadata, relationship keys, and other peers remain untouched.
  func recoverBlockedSend(readyGenerations: [String: Int64]) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !ready(readyGenerations: readyGenerations), active, binding.enabled else { return false }
    let at = monotonic()
    guard !readyGenerations.isEmpty, (try? validateGenerations(readyGenerations)) != nil,
          let verified = lastVerifiedAt, at >= verified, at - verified <= MqttRouteProtocol.resumeTTL else {
      blockedSince = nil
      return false
    }
    guard let since = blockedSince else { blockedSince = at; return false }
    guard at >= since, at - since >= 30_000,
          lastRecoveryAt.map({ at >= $0 && at - $0 >= 120_000 }) ?? true else { return false }
    local = nil
    remote = nil
    remoteLeaseUntil = 0
    localGenerations.removeAll()
    confirmedEpoch = 0
    readyLeaseUntil = 0
    self.readyGenerations.removeAll()
    responses.removeAll()
    nextSend = 0
    blockedSince = at
    lastRecoveryAt = at
    return true
  }

  func blockedReason(readyGenerations: [String: Int64]) -> String {
    lock.lock()
    defer { lock.unlock() }
    if !active || !binding.enabled { return "inactive_binding" }
    if readyGenerations.isEmpty { return "no_local_subscription" }
    guard let local else { return "no_local_advertisement" }
    if local.expiresAt <= wall() { return "expired_local_advertisement" }
    if confirmedEpoch != local.epoch { return "unconfirmed_local_epoch" }
    if readyGenerations.contains(where: { localGenerations[$0.key] != $0.value }) { return "changed_broker_generation" }
    return "no_verified_common_route"
  }

  private func prepareLocal(_ generations: [String: Int64]) throws -> MqttRouteAdvertisement? {
    try validateGenerations(generations)
    guard !generations.isEmpty else { return nil }
    let at = wall()
    if local == nil || localGenerations != generations || local!.expiresAt - at < MqttRouteProtocol.resumeTTL / 2 {
      let next = try persistence.issue(peer: binding.scope, sender: binding.sender, receiver: binding.receiver,
                                       brokers: Set(generations.keys), now: at)
      local = next
      localGenerations = generations
      confirmedEpoch = 0
    }
    return local
  }

  private func validateGenerations(_ generations: [String: Int64]) throws {
    guard Set(generations.keys).isSubset(of: MqttRouteProtocol.brokerIDs), generations.values.allSatisfy({ $0 > 0 }) else {
      throw MqttRouteError.invalidPayload
    }
  }
}
