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
    let received = try await routes.receive(ingress)
    guard !stopped, !received.handled, let packet = received.packet else { return }
    if packet.payload["type"] as? String == MqttDeliveryEnvelope.receiptType {
      _ = try await receipts.accept(packet)
      return
    }
    guard packet.payload["scheme"] as? String == "signal",
          let remoteName = remoteNames[packet.scope] else { return }
    let accepted = try routes.decryptAndStore(packet, using: engine, remoteName: remoteName)
    if let receipt = accepted.receipt, packet.payload[MqttDeliveryEnvelope.field] != nil {
      let frame = try MqttDeliveryEnvelope.parseVerifiedFrame(packet.payload, sender: packet.sender,
        receiver: packet.receiver, ingressBroker: ingress.brokerID)
      _ = await receiptRetry.offer(scope: packet.scope, message: receipt.messageID, attempt: frame.attempt.attemptID,
        now: monotonic()) { [weak routes = self.routes, journal = self.journal] in
          guard let routes else { return false }
          return try await routes.publishStoredReceipt(packet, inbox: journal.inbox)
        }
    }
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
