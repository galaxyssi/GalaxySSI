import Foundation

struct MqttPeerBinding: Equatable {
  var scope: String
  var sender: String
  var receiver: String
  var secret: String
  var sendTopic: String
  var sendTopics: Set<String>
  var receiveTopics: Set<String>
  var enabled = true

  var secretFingerprint: String { MqttRouteProtocol.digest(Data(secret.utf8)) }
  func authenticationID() throws -> String {
    try MqttDeliveryEnvelope.receiptBinding(scope: scope, sender: sender, receiver: receiver, secret: secret)
  }
  func validate() throws {
    _ = try MqttDeliveryEnvelope.checkedText(scope, maximum: 512)
    guard !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          MqttRouteProtocol.hex(sender, count: 64), MqttRouteProtocol.hex(receiver, count: 64), sender != receiver,
          GalaxySSILinkProtocol.validLinkSecret(secret), sendTopics.contains(sendTopic),
          (1...16).contains(sendTopics.count), (1...16).contains(receiveTopics.count),
          sendTopics.union(receiveTopics).allSatisfy(GalaxySSILinkProtocol.validTopic) else { throw MqttRouteError.invalidPayload }
  }
}

// Owns per-relationship resume state, not sockets or business storage. The application owner feeds
// pool snapshots and authenticated ingress, then calls maintenance from its existing MQTT loop.
final class MqttPeerRoutes {
  struct VerifiedPacket {
    let scope: String
    let authenticationID: String
    let sender: String
    let receiver: String
    let ingress: MqttAuthenticatedIngress
    let payload: [String: Any]
  }
  struct Reception { let handled: Bool; let packet: VerifiedPacket? }
  private final class Peer {
    var binding: MqttPeerBinding
    let identity: String
    let secretFingerprint: String
    let session: MqttPeerRouteSession
    var active = true
    var failureUntil: Int64 = 0
    init(binding: MqttPeerBinding, identity: String, session: MqttPeerRouteSession) {
      self.binding = binding; self.identity = identity; self.session = session
      self.secretFingerprint = binding.secretFingerprint
    }
  }
  private struct Control { let peer: Peer; let binding: MqttPeerBinding; let value: MqttPeerRouteControl }
  private let lock = NSRecursiveLock()
  private let pool: GalaxySSIMqttBrokerPool
  private let persistence: MqttRouteState
  private let wall: () -> Int64
  private let now: () -> Int64
  private let onReady: (String) -> Void
  private let onFailure: (String, Error) -> Void
  private var peers: [String: Peer] = [:]
  private var outgoing: [String: String] = [:]
  private var incoming: [String: Set<String>] = [:]
  private var snapshots: [String: MqttBrokerPathSnapshot] = [:]
  private var rotation: [String] = []
  private var urgent: [String] = []

  init(pool: GalaxySSIMqttBrokerPool, persistence: MqttRouteState,
       wall: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
       now: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1000) },
       onReady: @escaping (String) -> Void = { _ in }, onFailure: @escaping (String, Error) -> Void = { _, _ in }) {
    self.pool = pool; self.persistence = persistence; self.wall = wall; self.now = now
    self.onReady = onReady; self.onFailure = onFailure
  }

  // Call from pool.onPathState; that callback has already fenced old configuration events.
  func synchronize(_ snapshots: [String: MqttBrokerPathSnapshot]) { locked { self.snapshots = snapshots } }

  func replace(_ bindings: [MqttPeerBinding]) throws {
    guard bindings.count <= 10_000, Set(bindings.map(\.scope)).count == bindings.count else { throw MqttRouteError.invalidPayload }
    try bindings.forEach { try $0.validate() }
    let topics = bindings.flatMap(\.sendTopics)
    guard Set(topics).count == topics.count else { throw MqttRouteError.invalidPayload }
    var failures: [(String, Error)] = []
    let enabled: [String] = try locked {
      var retained: [String: Peer] = [:]
      // Construct all replacement sessions before retiring any current record.
      for binding in bindings {
        let identity = try binding.authenticationID()
        if let existing = peers[binding.scope], existing.identity == identity { retained[binding.scope] = existing }
        else {
          let session = try MqttPeerRouteSession(binding: .init(scope: binding.scope, sender: binding.sender,
            receiver: binding.receiver, authenticationID: identity, enabled: binding.enabled), persistence: persistence,
            wall: wall, monotonic: now)
          retained[binding.scope] = Peer(binding: binding, identity: identity, session: session)
        }
      }
      for (scope, peer) in peers where retained[scope] !== peer {
        peer.active = false
        do { try peer.session.retire() } catch { failures.append((scope, error)) }
        pool.policy.forgetPeer(scope)
      }
      var newlyEnabled: [String] = []
      for binding in bindings {
        guard let peer = retained[binding.scope] else { continue }
        if !peer.binding.enabled && binding.enabled { newlyEnabled.append(binding.scope) }
        if peer.binding.receiveTopics != binding.receiveTopics { peer.session.invalidateLocalAdvertisement() }
        peer.binding = binding
        peer.session.setEnabled(binding.enabled)
      }
      rotation.removeAll { retained[$0] == nil }
      let existing = Set(rotation)
      rotation.append(contentsOf: bindings.map(\.scope).filter { !existing.contains($0) })
      urgent.removeAll { retained[$0] == nil }
      peers = retained
      outgoing = Dictionary(uniqueKeysWithValues: bindings.flatMap { binding in binding.sendTopics.map { ($0, binding.scope) } })
      incoming.removeAll()
      for binding in bindings {
        for topic in binding.receiveTopics { incoming[topic, default: []].insert(binding.scope) }
      }
      return newlyEnabled.filter { peers[$0].map(ready) ?? false }
    }
    failures.forEach { onFailure($0.0, $0.1) }
    enabled.forEach(onReady)
  }

  func request(_ scope: String) {
    locked { if peers[scope] != nil && urgent.count < 64 && !urgent.contains(scope) { urgent.append(scope) } }
  }

  func maintenance(limit: Int = 16) async {
    guard (1...64).contains(limit) else { return }
    var failures: [(String, Error)] = []
    let controls: [Control] = locked {
      var scopes = Array(urgent.prefix(limit))
      urgent.removeFirst(scopes.count)
      let rotations = min(rotation.count, limit - scopes.count)
      for _ in 0..<rotations {
        let scope = rotation.removeFirst()
        rotation.append(scope)
        if !scopes.contains(scope) { scopes.append(scope) }
      }
      return scopes.flatMap { scope -> [Control] in
        guard let peer = peers[scope], peer.active, now() >= peer.failureUntil else { return [] }
        do {
          let controls = try peer.session.maintenance(readyGenerations: generations(peer.binding))
          return controls.map { Control(peer: peer, binding: peer.binding, value: $0) }
        } catch {
          peer.failureUntil = now() + 5000
          failures.append((scope, error))
          return []
        }
      }
    }
    failures.forEach { onFailure($0.0, $0.1) }
    for control in controls { await send(control) }
  }

  // Ingress must originate from the pool after native pair-AEAD verification. A wire field cannot
  // select its own relationship: current topic, secret fingerprint and path determine that binding.
  func receive(_ ingress: MqttAuthenticatedIngress) async throws -> Reception {
    var response: Control?
    var notify: String?
    let reception: Reception = try locked {
      let peer = try authenticatedPeer(ingress, allowDisabled: true)
      guard let payload = try JSONSerialization.jsonObject(with: ingress.payload) as? [String: Any] else { throw MqttRouteError.invalidPayload }
      let received = try peer.session.receiveVerified(payload, brokerID: ingress.brokerID, generation: ingress.generation,
        authenticationID: peer.identity, readyGenerations: generations(peer.binding))
      if received.handled {
        if let value = received.response { response = Control(peer: peer, binding: peer.binding, value: value) }
        if received.becameReady && ready(peer) { notify = peer.binding.scope }
        request(peer.binding.scope)
        return Reception(handled: true, packet: nil)
      }
      guard peer.binding.enabled else { throw MqttRouteError.identityChanged }
      return Reception(handled: false, packet: VerifiedPacket(scope: peer.binding.scope, authenticationID: peer.identity,
        sender: peer.binding.receiver, receiver: peer.binding.sender, ingress: ingress, payload: payload))
    }
    if let response { await send(response) }
    // Recheck after the asynchronous response: replacement/approval can change while enqueueing.
    if let notify, isReady(scope: notify) { onReady(notify) }
    return reception
  }

  func isCurrent(_ packet: VerifiedPacket) -> Bool {
    locked {
      guard let peer = try? authenticatedPeer(packet.ingress, allowDisabled: false) else { return false }
      return peer.binding.scope == packet.scope && peer.identity == packet.authenticationID &&
        peer.binding.receiver == packet.sender && peer.binding.sender == packet.receiver
    }
  }

  // Synchronous business-inbox/outbox commits can share the same relationship fence as parsing.
  func withCurrent<T>(_ packet: VerifiedPacket, commit: () throws -> T) throws -> T {
    try withCurrentIdentity(packet) { _ in try commit() }
  }

  func withCurrentIdentity<T>(_ packet: VerifiedPacket, commit: (MqttBusinessIdentity) throws -> T) throws -> T {
    try locked {
      guard isCurrent(packet), let peer = peers[packet.scope] else { throw MqttRouteError.identityChanged }
      return try commit(MqttBusinessIdentity(peer.binding))
    }
  }

  // Queueing is allowed while offline, but approval, relationship key and destination must still be current.
  func withOutgoing<T>(identity: MqttBusinessIdentity, topics: Set<String>, commit: () throws -> T) throws -> T {
    try locked {
      guard let peer = peers[identity.scope], peer.active, peer.binding.enabled, !topics.isEmpty,
            topics.isSubset(of: peer.binding.sendTopics),
            try MqttBusinessIdentity(peer.binding) == identity else { throw MqttRouteError.identityChanged }
      return try commit()
    }
  }

  func enqueue(_ requests: [MqttSignalSendRequest], using engine: GalaxySSISignalEngine,
               now: Date = Date()) throws -> [MqttBusinessOutbox.Entry] {
    guard let first = requests.first, (1...64).contains(requests.count),
          requests.allSatisfy({ $0.identity == first.identity }) else { throw MqttRouteError.invalidPayload }
    return try withOutgoing(identity: first.identity, topics: Set(requests.map(\.topic))) {
      try engine.enqueueBatch(requests, now: now)
    }
  }

  func consumeStoredReceipt(identity: MqttBusinessIdentity, receiptMessageID: String,
                            journal: MqttSignalStateJournal, now: Date = Date()) throws -> MqttDeliveryCompletions.Event? {
    try locked {
      guard let peer = peers[identity.scope], peer.active, peer.binding.enabled,
            try MqttBusinessIdentity(peer.binding) == identity else { throw MqttRouteError.identityChanged }
      return try journal.consumeStoredReceipt(identity: identity, receiptMessageID: receiptMessageID, now: now)
    }
  }

  func isReady(scope: String) -> Bool { locked { peers[scope].map(ready) ?? false } }
  func readyForTopic(_ topic: String) -> Bool { locked { outgoing[topic].flatMap { peers[$0] }.map(ready) ?? false } }

  func prepareDelivery(topic: String, wire: Data, messageID: String, traffic: MqttMultipathPolicy.Traffic) throws -> MqttDeliveryDispatch.Delivery? {
    try locked {
      guard let scope = outgoing[topic], let peer = peers[scope] else { return nil }
      guard ready(peer) else { request(scope); return nil }
      let binding = peer.binding
      guard let object = try JSONSerialization.jsonObject(with: wire) as? [String: Any] else { throw MqttRouteError.invalidPayload }
      let message = try MqttDeliveryEnvelope.Message(messageID: messageID, contentHash: MqttDeliveryEnvelope.contentHash(object),
        sender: binding.sender, receiver: binding.receiver, traffic: traffic.rawValue)
      return try MqttSignalDelivery.make(peer: scope, topic: topic, wire: wire, message: message, secret: binding.secret,
        receiveTopics: binding.receiveTopics, authorized: { [weak self, weak peer] broker, generation in
          guard let self, let peer else { return false }
          return self.locked {
            self.current(peer, binding: binding) && self.ready(peer) && self.generations(binding)[broker] == generation
          }
        })
    }
  }

  func recoverBlockedSend(topic: String) -> Bool {
    locked {
      guard let scope = outgoing[topic], let peer = peers[scope] else { return false }
      let recovered = peer.session.recoverBlockedSend(readyGenerations: generations(peer.binding))
      request(scope)
      return recovered
    }
  }
  func blockedReason(topic: String) -> String {
    locked {
      guard let scope = outgoing[topic], let peer = peers[scope] else { return "missing_binding" }
      return peer.session.blockedReason(readyGenerations: generations(peer.binding))
    }
  }

  private func send(_ control: Control) async {
    do {
      let binding = control.binding
      let value = control.value
      let packet: MqttPathPublication? = try locked {
        guard current(control.peer, binding: control.binding),
              generations(control.binding)[control.value.brokerID] == control.value.generation else { return nil }
        return MqttPathPublication(topic: control.binding.sendTopic,
          payload: try GalaxySSILinkProtocol.jsonData(control.value.payload), generation: control.value.generation,
          receiveTopics: control.binding.receiveTopics, secretFingerprint: control.binding.secretFingerprint,
          authorized: { [weak self, weak peer = control.peer] in
            guard let self, let peer else { return false }
            return self.locked { self.current(peer, binding: binding) &&
              self.generations(binding)[value.brokerID] == value.generation }
          })
      }
      if let packet { _ = await pool.publish(packet, brokerID: control.value.brokerID) }
    } catch { onFailure(control.binding.scope, error) }
  }
  private func authenticatedPeer(_ ingress: MqttAuthenticatedIngress, allowDisabled: Bool) throws -> Peer {
    guard let snapshot = snapshots[ingress.brokerID], snapshot.connected, snapshot.brokerID == ingress.brokerID,
          snapshot.configurationID == ingress.configurationID, snapshot.generation == ingress.generation,
          snapshot.subscriptions.contains(ingress.topic) else { throw MqttRouteError.staleGeneration }
    let matches = (incoming[ingress.topic] ?? []).compactMap { peers[$0] }.filter { $0.active &&
      $0.secretFingerprint == ingress.secretFingerprint && snapshot.isReady(for: $0.binding.receiveTopics) }
    guard matches.count == 1, let peer = matches.first, allowDisabled || peer.binding.enabled else { throw MqttRouteError.identityChanged }
    return peer
  }
  private func current(_ peer: Peer, binding: MqttPeerBinding) -> Bool {
    peer.active && peers[binding.scope] === peer && peer.binding == binding
  }
  private func generations(_ binding: MqttPeerBinding) -> [String: Int64] {
    MqttBrokerPathPolicy.readyGenerations(snapshots, topics: binding.receiveTopics)
  }
  private func ready(_ peer: Peer) -> Bool {
    guard peer.active, let route = peer.session.schedulingRoute(readyGenerations: generations(peer.binding)) else { return false }
    return pool.policy.acceptVerifiedResume(peer: peer.binding.scope, route: route, now: now())
  }
  private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
}
