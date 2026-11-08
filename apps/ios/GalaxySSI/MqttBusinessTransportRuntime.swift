import Foundation

// Owns one journal-backed Signal engine and one broker configuration. The application
// supplies durable projections and the foreground/recovery cadence; it owns migration.
@MainActor
final class MqttBusinessTransportRuntime {
  struct Peer {
    let binding: MqttPeerBinding
    let remoteSignalName: String
  }

  private let pool: GalaxySSIMqttBrokerPool
  private let routes: MqttPeerRoutes
  private let dispatcher: MqttDeliveryDispatch
  private let journal: MqttSignalStateJournal
  private let sends: MqttBusinessSendDrain
  private let receipts: MqttBusinessReceipts
  private let completions: MqttBusinessDeliveryDrain
  private let receiptRetry = MqttReceiptRetry()
  private let projectInbound: @MainActor (MqttBusinessInbox.Pending) async throws -> Void
  private let monotonic: () -> Int64
  private let onFailure: @MainActor (Error) -> Void
  let engine: GalaxySSISignalEngine

  private var identities: [MqttBusinessIdentity] = []
  private var remoteNames: [String: String] = [:]
  private var inboxCursor = ""
  private var ingressTask: Task<Void, Never>?
  private var started = false
  private var stopped = false
  private var polling = false
  private var peerChatProjection: MqttPeerChatProjection?
  private var configuredDirectPeers: [Peer] = []

  // The caller must first quiesce legacy Signal, inbox and outbox writers. Once this returns a
  // marker, that account must reopen the new runtime; it must not restart the old sender.
  static func prepareLegacyCutover(journal: MqttSignalStateJournal, legacyOutbox: GalaxySSILinkDeliveryStore,
                                   expectedLocalFingerprint: String, peers: [Peer], defaults: UserDefaults,
                                   secrets: GalaxySSISecretStore,
                                   classify: (PendingLinkMessage) -> MqttMultipathPolicy.Traffic?) throws
    -> MqttSignalStateJournal.LegacyCutover {
    if let existing = try journal.legacyCutover() {
      guard existing.localFingerprint == expectedLocalFingerprint else { throw MqttRouteError.identityChanged }
      return existing
    }
    #if canImport(LibSignalClient)
    let legacy = try GalaxySSISignalProtocolStore.legacyMigrationSnapshot(defaults: defaults, secrets: secrets)
    guard legacy.localFingerprint == expectedLocalFingerprint else { throw MqttRouteError.identityChanged }
    var byTopic: [String: Peer] = [:]
    for peer in peers where peer.binding.enabled {
      try peer.binding.validate()
      guard peer.binding.sender == expectedLocalFingerprint, !peer.remoteSignalName.isBlank else {
        throw MqttRouteError.identityChanged
      }
      for topic in peer.binding.sendTopics {
        guard byTopic.updateValue(peer, forKey: topic) == nil else { throw MqttRouteError.invalidPayload }
      }
    }
    let queue = try legacyOutbox.outboxMigrationSnapshot(requireDrainedInbox: true)
    let entries = try queue.map { item -> MqttSignalStateJournal.LegacyOutboxEntry in
      guard let peer = byTopic[item.topic], let traffic = classify(item), item.deferredTaskPayload == nil,
            let wire = try JSONSerialization.jsonObject(with: Data(item.wirePayload.utf8)) as? [String: Any],
            wire["scheme"] as? String == "signal", wire["from"] as? String == legacy.localName,
            wire["to"] as? String == peer.remoteSignalName,
            wire["message_id"] == nil || wire["message_id"] as? String == item.messageId,
            wire[MqttDeliveryEnvelope.field] == nil else { throw MqttRouteError.invalidPayload }
      let device = try MqttRouteProtocol.integer(wire, "device_id")
      guard (1...127).contains(device),
            legacy.trustedFingerprints["\(peer.remoteSignalName)|\(device)"] == peer.binding.receiver
      else { throw MqttRouteError.identityChanged }
      return .init(identity: try MqttBusinessIdentity(peer.binding), message: item, traffic: traffic)
    }
    return try journal.activateLegacy(localFingerprint: expectedLocalFingerprint, signalState: legacy.state, entries: entries)
    #else
    throw MqttDeliveryDispatch.Failure.unavailable
    #endif
  }

  init(profileName: String, journal: MqttSignalStateJournal, routeState: MqttRouteState,
       defaults: UserDefaults = .standard, secrets: GalaxySSISecretStore = KeychainSecretStore.shared,
       pool: GalaxySSIMqttBrokerPool = .init(),
       wall: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
       monotonic: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1_000) },
       projectInbound: @escaping @MainActor (MqttBusinessInbox.Pending) async throws -> Void,
       projectCompletion: @escaping @MainActor (MqttDeliveryCompletions.Event) async throws -> Void,
       onFailure: @escaping @MainActor (Error) -> Void = { _ in }) throws {
    guard GalaxySSISignalEngine.isAvailable else { throw MqttDeliveryDispatch.Failure.unavailable }
    self.journal = journal
    self.pool = pool
    self.monotonic = monotonic
    self.projectInbound = projectInbound
    self.onFailure = onFailure
    let engine = try GalaxySSISignalEngine(profileName: profileName, journal: journal, defaults: defaults, secrets: secrets)
    if let cutover = try journal.legacyCutover(), cutover.localFingerprint != engine.identity.fingerprint {
      throw MqttRouteError.identityChanged
    }
    self.engine = engine
    let routes = MqttPeerRoutes(pool: pool, persistence: routeState, wall: wall, now: monotonic,
      onFailure: { _, error in Task { @MainActor in onFailure(error) } })
    self.routes = routes
    let dispatcher = pool.makeDeliveryDispatcher(brokerCompleted: { _, _ in }, now: monotonic)
    self.dispatcher = dispatcher
    let date = { Date(timeIntervalSince1970: Double(wall()) / 1_000) }
    sends = MqttBusinessSendDrain(outbox: journal.outbox, routes: routes, dispatcher: dispatcher, engine: engine, now: date)
    let receipts = MqttBusinessReceipts(routes: routes, outbox: journal.outbox, dispatcher: dispatcher, now: date)
    self.receipts = receipts
    completions = MqttBusinessDeliveryDrain(journal: journal, receipts: receipts, routes: routes, now: wall,
      apply: { try await projectCompletion($0) })
  }

  convenience init(peerChatStore store: GalaxySSIStore, localFingerprint: String,
                   journal: MqttSignalStateJournal, routeState: MqttRouteState,
                   pool: GalaxySSIMqttBrokerPool = .init(), onFailure: @escaping @MainActor (Error) -> Void = { _ in }) throws {
    guard let cutover = try journal.legacyCutover(), cutover.localFingerprint == localFingerprint else {
      throw MqttDeliveryDispatch.Failure.unavailable
    }
    let projection = MqttPeerChatProjection(store: store, localFingerprint: localFingerprint)
    try self.init(profileName: store.profile.galaxySSIId, journal: journal, routeState: routeState,
      defaults: store.defaults, secrets: store.secrets, pool: pool,
      projectInbound: { _ = try projection.projectInbound($0) },
      projectCompletion: { try projection.projectCompletion($0) }, onFailure: onFailure)
    guard engine.identity.fingerprint == localFingerprint else { throw MqttRouteError.identityChanged }
    peerChatProjection = projection
  }

  func startDirectPeerChat(configuration: MqttBrokerPathConfiguration) throws {
    guard let projection = peerChatProjection else { throw MqttDeliveryDispatch.Failure.unavailable }
    let peers = projection.currentPeers()
    try start(configuration: configuration, peers: peers)
    configuredDirectPeers = peers
  }

  func enqueueDirectPeerText(messageId: UUID, contactId: String) throws -> MqttBusinessOutbox.Entry {
    guard let projection = peerChatProjection else { throw MqttDeliveryDispatch.Failure.unavailable }
    try refreshDirectPeerBindings()
    let request = try projection.outgoingRequest(for: messageId, contactId: contactId)
    guard let entry = try enqueue([request]).first else { throw MqttRouteError.invalidPayload }
    return entry
  }

  // A changed route must be configured by the owner before it can send. Never silently move
  // an existing durable queue to a different relationship.
  func refreshDirectPeerBindings() throws {
    guard let projection = peerChatProjection, started, !stopped, !configuredDirectPeers.isEmpty else { return }
    let current = Dictionary(grouping: projection.currentPeers(), by: { $0.binding.scope })
    let retained = configuredDirectPeers.filter { peer in
      guard let matches = current[peer.binding.scope], matches.count == 1, let match = matches.first else { return false }
      return match.binding == peer.binding && match.remoteSignalName == peer.remoteSignalName
    }
    guard retained.count != configuredDirectPeers.count else { return }
    let retainedIdentities = try retained.map { try MqttBusinessIdentity($0.binding) }
    try routes.replace(retained.map(\.binding))
    configuredDirectPeers = retained
    identities = retainedIdentities
  }

  func start(configuration: MqttBrokerPathConfiguration, peers: [Peer]) throws {
    guard !started, !stopped else { throw MqttDeliveryDispatch.Failure.unavailable }
    let local = engine.identity.fingerprint
    let configuredRoutes = configuration.serverLinks.filter(\.paired).map(\.routes) + configuration.phoneRoutes
    for peer in peers {
      let binding = peer.binding
      guard binding.sender == local, !peer.remoteSignalName.isBlank,
            configuredRoutes.contains(where: {
              $0.isOpaqueV2Valid && $0.localFingerprint == local && $0.remoteFingerprint == binding.receiver &&
                $0.linkSecret == binding.secret && binding.sendTopics.isSubset(of: $0.sendWindow) &&
                binding.receiveTopics == $0.receiveWindow
            }) else { throw MqttRouteError.identityChanged }
    }
    let identities = try peers.filter { $0.binding.enabled }.map { try MqttBusinessIdentity($0.binding) }
    try routes.replace(peers.map(\.binding))
    self.identities = identities
    remoteNames = Dictionary(uniqueKeysWithValues: peers.map { ($0.binding.scope, $0.remoteSignalName) })
    var captured: AsyncStream<MqttAuthenticatedIngress>.Continuation?
    let ingressStream = AsyncStream<MqttAuthenticatedIngress>(bufferingPolicy: .bufferingOldest(32)) { captured = $0 }
    guard let continuation = captured else { throw MqttDeliveryDispatch.Failure.unavailable }
    pool.onPathState = { [weak routes = self.routes] in routes?.synchronize($0) }
    pool.onAuthenticatedIngress = { ingress in _ = continuation.yield(ingress) }
    ingressTask = Task { [weak self] in
      defer { continuation.finish() }
      for await ingress in ingressStream {
        guard !Task.isCancelled, let self, !self.stopped else { return }
        do { try await self.receive(ingress) } catch { self.onFailure(error) }
      }
    }
    started = true
    pool.connect(configuration)
  }

  func enqueue(_ requests: [MqttSignalSendRequest]) throws -> [MqttBusinessOutbox.Entry] {
    guard started, !stopped else { throw MqttDeliveryDispatch.Failure.unavailable }
    return try routes.enqueue(requests, using: engine)
  }

  func poll(validatedNetwork: Bool) async throws {
    guard started, !stopped, !polling else { return }
    polling = true
    defer { polling = false }
    try Task.checkCancellation()
    try refreshDirectPeerBindings()
    await routes.maintenance()
    guard !stopped else { return }
    await dispatcher.tick()
    await receiptRetry.drain(now: monotonic())
    guard !stopped else { return }
    let outbound = try await sends.drain(identities: identities, validatedNetwork: validatedNetwork)
    outbound.failures.forEach { onFailure($0.error) }
    guard !stopped else { return }
    let projected = try await completions.drain()
    projected.failures.forEach { onFailure($0.error) }
    guard !stopped else { return }
    try await drainInbound()
  }

  func stop() async {
    guard !stopped else { return }
    stopped = true
    let worker = ingressTask
    worker?.cancel()
    ingressTask = nil
    pool.disconnect()
    routes.synchronize([:])
    await sends.close()
    await completions.close()
    await dispatcher.close()
    await receiptRetry.clear()
    await worker?.value
  }

  private func receive(_ ingress: MqttAuthenticatedIngress) async throws {
    try refreshDirectPeerBindings()
    let received = try await routes.receive(ingress)
    guard !stopped, !received.handled, let packet = received.packet else { return }
    if packet.payload["type"] as? String == MqttDeliveryEnvelope.receiptType {
      _ = try await receipts.accept(packet)
      return
    }
    guard let remoteName = remoteNames[packet.scope] else { return }
    switch packet.payload["type"] as? String {
    case MqttChunkReceipts.state:
      _ = try routes.withCurrentIdentity(packet) {
        try journal.outgoingChunks.accept(authenticatedScope: $0.binding, state: packet.payload)
      }
      return
    case MqttChunkReceipts.probe:
      try await receiveChunks(packet, remoteName: remoteName, probe: true)
      return
    default: break
    }
    if packet.payload["scheme"] as? String == "signal-chunk" {
      try await receiveChunks(packet, remoteName: remoteName, probe: false)
      return
    }
    guard packet.payload["scheme"] as? String == "signal" else { return }
    let accepted = try routes.decryptAndStore(packet, using: engine, remoteName: remoteName)
    if let receipt = accepted.receipt, packet.payload[MqttDeliveryEnvelope.field] != nil {
      let frame = try MqttDeliveryEnvelope.parseVerifiedFrame(packet.payload, sender: packet.sender,
        receiver: packet.receiver, ingressBroker: packet.ingress.brokerID)
      _ = await receiptRetry.offer(scope: packet.scope, message: receipt.messageID, attempt: frame.attempt.attemptID,
        now: monotonic()) { [weak routes = self.routes, journal = self.journal] in
          guard let routes else { return false }
          return try await routes.publishStoredReceipt(packet, inbox: journal.inbox)
        }
    }
  }

  private func receiveChunks(_ packet: MqttPeerRoutes.VerifiedPacket, remoteName: String, probe: Bool) async throws {
    let (state, proof) = try routes.withCurrentIdentity(packet) { identity in
      try storeChunks(packet, identity: identity, remoteName: remoteName, probe: probe)
    }
    if let state {
      _ = try await routes.publishIngressReply(packet, payload: state)
    }
    guard !stopped, let proof else { return }
    if let wire = try routes.withCurrentIdentity(packet, commit: { identity in
      try engine.makeStoredReceiptWire(identity: identity, messageID: proof.messageID,
        wireHash: proof.wireHash, remoteName: remoteName)
    }) {
      _ = try await routes.publishIngressReply(packet, payload: wire)
    }
  }

  private func storeChunks(_ packet: MqttPeerRoutes.VerifiedPacket, identity: MqttBusinessIdentity,
                           remoteName: String, probe: Bool) throws -> ([String: Any]?, MqttBusinessInbox.Receipt?) {
    let chunks = journal.incomingChunks
    let query: MqttChunkReceipts.Query
    let sendState: Bool
    let transfer: String
    let assembled: String?
    if probe {
      let request = try MqttChunkReceipts.parse(packet.payload)
      let snapshot = try chunks.snapshot(authenticatedScope: identity.binding, query: request)
      if let proof = snapshot.proof {
        return (snapshot.state, try journal.inbox.storedReceipt(identity: identity,
          messageID: proof.messageID, wireHash: proof.wireHash))
      }
      query = request
      sendState = true
      transfer = request.transfer
      assembled = try chunks.recoverComplete(authenticatedScope: identity.binding, query: request)
    } else {
      let chunk = try MqttChunkManifest.parse(packet.payload)
      guard packet.payload["protocol"] as? String == GalaxySSILinkProtocol.name,
            try MqttRouteProtocol.integer(packet.payload, "version") == Int64(GalaxySSILinkProtocol.version),
            chunk.source == remoteName, chunk.target == engine.identity.name else {
        throw MqttRouteError.invalidPayload
      }
      let request = try MqttChunkReceipts.fromChunk(packet.payload)
      query = try request ?? MqttChunkReceipts.Query(transfer: chunk.transfer, manifest: chunk.manifestHash,
        count: chunk.count, request: MqttChunkReceipts.newRequest())
      sendState = request != nil
      transfer = chunk.transfer
      assembled = try chunks.accept(authenticatedScope: identity.binding, wire: packet.payload)
    }

    var proof: MqttBusinessInbox.Receipt?
    if let assembled {
      guard let wire = try JSONSerialization.jsonObject(with: Data(assembled.utf8)) as? [String: Any] else {
        throw MqttRouteError.invalidPayload
      }
      let accepted = try engine.decryptAndStore(wire, identity: identity, remoteName: remoteName,
        ingressBroker: packet.ingress.brokerID)
      if let receipt = accepted.receipt {
        proof = try journal.inbox.storedReceipt(identity: identity, messageID: receipt.messageID, wireHash: receipt.wireHash)
        if let proof {
          _ = try chunks.releaseAfterStore(authenticatedScope: identity.binding, transfer: transfer,
            storedWireHash: proof.wireHash, messageID: proof.messageID)
        }
      }
    }
    let snapshot = try chunks.snapshot(authenticatedScope: identity.binding, query: query)
    if proof == nil, let saved = snapshot.proof {
      proof = try journal.inbox.storedReceipt(identity: identity, messageID: saved.messageID, wireHash: saved.wireHash)
    }
    return (sendState ? snapshot.state : nil, proof)
  }

  private func drainInbound() async throws {
    let page = try journal.inbox.pending(afterKey: inboxCursor, limit: 16)
    for item in page {
      try Task.checkCancellation()
      guard !stopped else { return }
      inboxCursor = item.key
      do {
        guard let payload = try JSONSerialization.jsonObject(with: item.payload) as? [String: Any] else {
          throw MqttRouteError.invalidPayload
        }
        if payload["type"] as? String == "delivery_ack" { continue }
        try routes.withIdentity(item.identity) {}
        try await projectInbound(item)
        guard !stopped else { return }
        try routes.withIdentity(item.identity) {
          guard try journal.inbox.complete(identity: item.identity, messageID: item.messageID) else {
            throw MqttChunkStorageError.corruptState
          }
        }
      } catch {
        if error is CancellationError { throw error }
        onFailure(error)
      }
    }
    if page.count < 16 { inboxCursor = "" }
  }
}
