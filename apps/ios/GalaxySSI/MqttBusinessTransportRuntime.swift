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
  private var configuredDirectRoutes: [String: GalaxySSILinkRoutes] = [:]
  private var directConfiguration: MqttBrokerPathConfiguration?
  private var incomingAttachments: AgentIncomingAttachmentTransferStore?
  private var outgoingAttachments: AgentOutboundAttachmentTransferStore?
  private var desktopArtifacts: AgentDesktopArtifactStore?
  private var desktopConnector: MqttDesktopConnectorProjection?
  private var receiveDesktopBlobControl: (@MainActor ([String: Any], MqttPeerChatProjection.Destination, MqttBusinessIdentity) async throws -> Void)?
  private struct EvidenceWaiter {
    let identity: MqttBusinessIdentity
    let request: AgentDesktopToolEvidenceWire.Request
    let mode: String
    let signal: AsyncStream<AgentMcpJSONObject>.Continuation
  }
  private var evidenceWaiters: [String: EvidenceWaiter] = [:]
  private final class LogicalReceiptWire { var payload: [String: Any]? }
  private enum DesktopPeerArtifactPending: Error { case awaitingChunks }
  private let attachmentQueue = DispatchQueue(label: "galaxyssi.mqtt.peer-attachments", qos: .utility)

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
    sends = MqttBusinessSendDrain(outbox: journal.outbox, routes: routes, dispatcher: dispatcher,
      chunks: journal.outgoingChunks, engine: engine, now: date)
    let receipts = MqttBusinessReceipts(routes: routes, outbox: journal.outbox, dispatcher: dispatcher, now: date)
    self.receipts = receipts
    completions = MqttBusinessDeliveryDrain(journal: journal, receipts: receipts, routes: routes, now: wall,
      apply: { try await projectCompletion($0) })
  }

  convenience init(peerChatStore store: GalaxySSIStore, localFingerprint: String,
                   journal: MqttSignalStateJournal, routeState: MqttRouteState,
                   pool: GalaxySSIMqttBrokerPool = .init(),
                   incomingAttachments: AgentIncomingAttachmentTransferStore = .init(),
                   outgoingAttachments: AgentOutboundAttachmentTransferStore = .init(),
                   desktopArtifacts: AgentDesktopArtifactStore? = nil,
                   desktopConnector: MqttDesktopConnectorProjection? = nil,
                   receiveDesktopBlobControl: (@MainActor ([String: Any], MqttPeerChatProjection.Destination, MqttBusinessIdentity) async throws -> Void)? = nil,
                   onFailure: @escaping @MainActor (Error) -> Void = { _ in }) throws {
    guard let cutover = try journal.legacyCutover(), cutover.localFingerprint == localFingerprint else {
      throw MqttDeliveryDispatch.Failure.unavailable
    }
    let projection = MqttPeerChatProjection(store: store, localFingerprint: localFingerprint)
    try self.init(profileName: store.profile.galaxySSIId, journal: journal, routeState: routeState,
      defaults: store.defaults, secrets: store.secrets, pool: pool,
      projectInbound: { _ = try projection.projectInbound($0) },
      projectCompletion: { event in
        if let desktopConnector, let target = try projection.currentDestination(event.identity), target.desktop {
          if !event.attachmentTransferID.isEmpty,
             [MqttMultipathPolicy.Traffic.control.rawValue, MqttMultipathPolicy.Traffic.chunk.rawValue].contains(event.traffic) { return }
          if target.contactId != event.contactID {
            try desktopConnector.projectCompletion(event, target: target)
          } else if event.traffic != MqttMultipathPolicy.Traffic.control.rawValue ||
                      !event.sourceMessageID.isEmpty || !event.attachmentTransferID.isEmpty {
            try projection.projectCompletion(event)
          }
        } else {
          try projection.projectCompletion(event)
        }
      }, onFailure: onFailure)
    guard engine.identity.fingerprint == localFingerprint else { throw MqttRouteError.identityChanged }
    peerChatProjection = projection
    self.incomingAttachments = incomingAttachments
    self.outgoingAttachments = outgoingAttachments
    self.desktopArtifacts = desktopArtifacts
    self.desktopConnector = desktopConnector
    self.receiveDesktopBlobControl = receiveDesktopBlobControl
  }

  func startDirectPeerChat(configuration: MqttBrokerPathConfiguration) throws {
    guard let projection = peerChatProjection else { throw MqttDeliveryDispatch.Failure.unavailable }
    let destinations = projection.currentDestinations()
    let peers = destinations.map(\.peer)
    try start(configuration: configuration, peers: peers)
    configuredDirectPeers = peers
    configuredDirectRoutes = Dictionary(uniqueKeysWithValues: destinations.map { ($0.peer.binding.scope, $0.routes) })
    directConfiguration = configuration
  }

  var hasReadyPeer: Bool { started && !stopped && identities.contains { routes.isReady(scope: $0.scope) } }

  func enqueueDirectPeerText(messageId: UUID, contactId: String, messageKind: String = "",
                             durationMillis: Int64 = 0) throws -> MqttBusinessOutbox.Entry {
    guard let projection = peerChatProjection else { throw MqttDeliveryDispatch.Failure.unavailable }
    try refreshDirectPeerBindings()
    let request = try projection.outgoingRequest(for: messageId, contactId: contactId,
      messageKind: messageKind, durationMillis: durationMillis)
    guard let entry = try enqueue([request]).first else { throw MqttRouteError.invalidPayload }
    return entry
  }

  func enqueueDirectPeerAttachments(messageId: UUID, contactId: String,
                                    attachments: [AgentPreparedOutboundAttachment], messageKind: String = "",
                                    durationMillis: Int64 = 0, blobTransfers: Set<String> = []) throws -> MqttBusinessOutbox.Entry {
    guard let projection = peerChatProjection, !attachments.isEmpty, started, !stopped else {
      throw MqttDeliveryDispatch.Failure.unavailable
    }
    try refreshDirectPeerBindings()
    let requests = try projection.outgoingRequests(for: messageId, contactId: contactId, attachments: attachments,
      messageKind: messageKind, durationMillis: durationMillis, blobTransfers: blobTransfers)
    guard let body = requests.last else { throw MqttRouteError.invalidPayload }
    if let existing = try routes.withOutgoing(identity: body.identity, topics: [body.topic], commit: {
      try journal.outbox.entry(identity: body.identity, messageID: body.messageID)
    }) {
      guard try body.matchesIntent(existing.requestHash, storedTopic: existing.message.topic),
            body.matches(existing.message, allowRotatedTopic: true) else {
        throw MqttChunkStorageError.corruptState
      }
      return existing
    }
    guard let entry = try enqueue(requests).last else { throw MqttRouteError.invalidPayload }
    return entry
  }

  func enqueueDesktopConnectorRequest(_ payload: [String: Any], desktopId: String,
                                      attachments: [AgentPreparedOutboundAttachment] = [], blobTransfers: Set<String> = [],
                                      ownerContactID: String? = nil) throws -> MqttBusinessOutbox.Entry {
    guard let projection = peerChatProjection, let desktopConnector else { throw MqttDeliveryDispatch.Failure.unavailable }
    try refreshDirectPeerBindings()
    let matches = projection.store.contacts.compactMap { projection.destination(for: $0) }.filter {
      $0.desktop && $0.peer.remoteSignalName == desktopId
    }
    guard matches.count == 1, let target = matches.first else { throw MqttRouteError.identityChanged }
    let requests = try desktopConnector.outgoingRequests(payload, target: target, attachments: attachments,
      blobTransfers: blobTransfers, ownerContactID: ownerContactID)
    guard let entry = try enqueue(requests).last else { throw MqttRouteError.invalidPayload }
    return entry
  }

  func enqueueDesktopBlobControl(_ payload: [String: Any], desktopId: String) throws {
    guard let projection = peerChatProjection else { throw MqttDeliveryDispatch.Failure.unavailable }
    try refreshDirectPeerBindings()
    let candidates = projection.currentDestinations().filter {
      $0.desktop && $0.peer.remoteSignalName == desktopId && $0.routeId == payload.string("client_route_id")
    }
    guard candidates.count == 1, let target = candidates.first else { throw MqttRouteError.identityChanged }
    let request = try payload.string("type") == AgentBlobArtifactContract.receiptType
      ? MqttPeerChatProjection.desktopBlobReceiptRequest(payload, target: target)
      : MqttPeerChatProjection.desktopBlobCapabilityRequest(payload, target: target)
    try enqueueExactControl(request)
  }

  private func desktopBlobDestination(_ attachment: AgentPreparedOutboundAttachment) throws -> MqttPeerChatProjection.Destination {
    guard started, !stopped, let projection = peerChatProjection else { throw MqttDeliveryDispatch.Failure.unavailable }
    try refreshDirectPeerBindings()
    let matches = projection.currentDestinations().filter {
      $0.desktop && $0.peer.remoteSignalName == attachment.scope.desktopId && $0.routeId == attachment.scope.clientRouteId
    }
    guard matches.count == 1, let target = matches.first else { throw MqttRouteError.identityChanged }
    return target
  }

  func journalBlobDisposition(_ attachment: AgentPreparedOutboundAttachment, binding: String) throws
    -> AgentBlobOutgoingCoordinator.JournalDisposition {
    let target = try desktopBlobDestination(attachment)
    let identity = try MqttBusinessIdentity(target.peer.binding)
    guard identity.binding == binding, let source = attachment.scope.clientMessageId,
          let sourceID = UUID(uuidString: source),
          let projection = peerChatProjection else { return .retire }
    return try routes.withIdentity(identity) {
      guard let body = try journal.outbox.entry(identity: identity, messageID: sourceID.uuidString) else {
        if try journal.outbox.completions.event(identity: identity, messageID: sourceID.uuidString) != nil { return .retire }
        if let message = projection.store.persistedOutboundTransportSource(id: sourceID) {
          return message.deliveryStatus == .failed ? .retire : .wait
        }
        return desktopConnector?.isCurrentSendOwner(contactID: attachment.scope.contactId, source: source, target: target) == true
          ? .wait : .retire
      }
      guard body.message.clientSourceMessageId == source,
            body.message.blockedByAttachmentTransferIds.contains(attachment.transferId),
            let request = body.deferredRequest, request.blobAttachmentDependencies?.contains(attachment.transferId) == true,
            try queuedAttachmentOwner(attachment, body: request, target: target, projection: projection)?.maySend == true
      else { return .retire }
      return .upload
    }
  }

  func enqueueDesktopBlobOffer(_ payload: [String: Any], attachment: AgentPreparedOutboundAttachment) throws {
    let target = try desktopBlobDestination(attachment)
    let identity = try MqttBusinessIdentity(target.peer.binding)
    guard try journalBlobDisposition(attachment, binding: identity.binding) == .upload else {
      throw MqttRouteError.identityChanged
    }
    try enqueueExactControl(MqttPeerChatProjection.desktopBlobOfferRequest(payload, attachment: attachment,
      target: target, peerChat: attachment.scope.contactId == target.peer.remoteSignalName))
  }

  private func queuedAttachmentOwner(_ transfer: AgentPreparedOutboundAttachment, body: MqttSignalSendRequest,
                                    target: MqttPeerChatProjection.Destination, projection: MqttPeerChatProjection) throws
    -> MqttDesktopConnectorProjection.TaskOwner? {
    guard body.attachmentDependencies.contains(transfer.transferId),
          let sourceID = UUID(uuidString: body.sourceMessageID) else { throw MqttRouteError.invalidPayload }
    if body.contactID == target.contactId {
      guard projection.matches(transfer, target: target, source: body.sourceMessageID) else { throw MqttRouteError.identityChanged }
      return projection.store.persistedMessage(id: sourceID, contactId: target.contactId)
        .map { .init(message: $0) }
    }
    guard target.desktop, let desktopConnector else { throw MqttRouteError.identityChanged }
    return try desktopConnector.attachmentOwner(transfer, body: body, target: target)
  }

  private func enqueueExactControl(_ request: MqttSignalSendRequest) throws {
    do {
      guard try enqueue([request]).count == 1 else { throw MqttChunkStorageError.corruptState }
    } catch MqttChunkStorageError.alreadyDelivered {
      guard let event = try journal.outbox.completions.event(identity: request.identity, messageID: request.messageID),
            try request.matchesIntent(event.requestHash, storedTopic: event.topic) else {
        throw MqttChunkStorageError.corruptState
      }
    }
  }

  // Only the topic window may change in place. Approval and relationship material stay pinned.
  func refreshDirectPeerBindings() throws {
    guard let projection = peerChatProjection, started, !stopped, !configuredDirectPeers.isEmpty else { return }
    let current = Dictionary(grouping: projection.currentDestinations(), by: { $0.peer.binding.scope })
    let retained = try configuredDirectPeers.compactMap { peer -> Peer? in
      guard let matches = current[peer.binding.scope], matches.count == 1, let match = matches.first else { return nil }
      guard let original = configuredDirectRoutes[peer.binding.scope], match.routes == original,
            match.peer.remoteSignalName == peer.remoteSignalName,
            try MqttBusinessIdentity(match.peer.binding) == MqttBusinessIdentity(peer.binding) else { return nil }
      return match.peer
    }
    guard retained.count != configuredDirectPeers.count ||
          zip(retained, configuredDirectPeers).contains(where: { $0.0.binding != $0.1.binding }) else { return }
    let removed = retained.count != configuredDirectPeers.count
    let retainedIdentities = try retained.map { try MqttBusinessIdentity($0.binding) }
    try routes.replace(retained.map(\.binding))
    configuredDirectPeers = retained
    identities = retainedIdentities
    remoteNames = Dictionary(uniqueKeysWithValues: retained.map { ($0.binding.scope, $0.remoteSignalName) })
    if removed, var configuration = directConfiguration {
      let scopes = Set(retained.map(\.binding.scope))
      configuredDirectRoutes = configuredDirectRoutes.filter { scopes.contains($0.key) }
      let approved = Set(configuredDirectRoutes.values)
      configuration.serverLinks = configuration.serverLinks.filter { approved.contains($0.routes) }
      configuration.phoneRoutes = configuration.phoneRoutes.filter { approved.contains($0) }
      directConfiguration = configuration
      routes.synchronize([:])
      pool.connect(configuration)
    }
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
    let outbound = try await sends.drain(identities: identities, validatedNetwork: validatedNetwork) { [weak self] entry in
      try await self?.authorizeConnectorSend(entry) ?? false
    }
    outbound.failures.forEach { onFailure($0.error) }
    guard !stopped else { return }
    let projected = try await completions.drain()
    projected.failures.forEach { onFailure($0.error) }
    guard !stopped else { return }
    try await drainInbound()
    if !stopped { await pumpDesktopRecoveryQueries() }
    if !stopped { pumpDesktopResultReceipts() }
    if !stopped { desktopConnector?.resumeEvidenceJobs?(self) }
  }

  private func authorizeConnectorSend(_ entry: MqttBusinessOutbox.Entry) throws -> Bool {
    guard !stopped else { return false }
    guard let projection = peerChatProjection, entry.identity.scope.hasPrefix("direct:") else { return true }
    guard let target = try projection.currentDestination(entry.identity) else { return false }
    guard target.desktop, target.contactId != entry.message.contactId else { return true }
    return desktopConnector?.isCurrentSendOwner(contactID: entry.message.contactId,
      source: entry.message.clientSourceMessageId, target: target) == true
  }

  private func evidenceDestination(_ binding: AgentDesktopReplyBinding) -> MqttPeerChatProjection.Destination? {
    guard started, !stopped, let projection = peerChatProjection else { return nil }
    let matches = projection.store.contacts.compactMap { projection.destination(for: $0) }.filter {
      $0.desktop && $0.peer.remoteSignalName == binding.desktopId && $0.routeId == binding.identity.clientRouteId
    }
    guard matches.count == 1, let target = matches.first,
          let identity = try? MqttBusinessIdentity(target.peer.binding),
          (try? routes.withIdentity(identity) { routes.readyForTopic(target.peer.binding.sendTopic) }) == true else { return nil }
    return target
  }

  func canQueryDesktopEvidence(_ binding: AgentDesktopReplyBinding) -> Bool {
    evidenceDestination(binding) != nil
  }

  func queryDesktopEvidence(_ request: AgentDesktopToolEvidenceWire.Request,
                            payload: AgentMcpJSONObject) async -> AgentMcpJSONObject? {
    guard !Task.isCancelled, evidenceWaiters.count < 2, evidenceWaiters[request.nonce] == nil,
          let connector = desktopConnector else { return nil }
    do {
      try refreshDirectPeerBindings()
      guard let target = evidenceDestination(request.binding),
            let object = try JSONSerialization.jsonObject(with: Data(AgentMcpJSONCodec.stringify(payload).utf8)) as? [String: Any]
      else { return nil }
      let outgoing = try connector.evidenceQueryRequest(request, payload: object, target: target)
      var signal: AsyncStream<AgentMcpJSONObject>.Continuation?
      let stream = AsyncStream<AgentMcpJSONObject>(bufferingPolicy: .bufferingNewest(1)) { signal = $0 }
      guard let signal else { return nil }
      evidenceWaiters[request.nonce] = EvidenceWaiter(identity: outgoing.identity, request: request,
        mode: object.string("mode"), signal: signal)
      let timer = Task {
        do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
        signal.finish()
      }
      defer {
        timer.cancel()
        evidenceWaiters.removeValue(forKey: request.nonce)
        signal.finish()
      }
      let wire = try routes.withOutgoing(identity: outgoing.identity, topics: [outgoing.topic]) {
        try engine.makeRecoveryQueryWire(outgoing)
      }
      guard await routes.publishTransientControl(topic: outgoing.topic, wire: wire, secret: target.peer.binding.secret).accepted
      else { return nil }
      for await result in stream where !stopped && !Task.isCancelled { return result }
    } catch { onFailure(error) }
    return nil
  }

  private func pumpDesktopRecoveryQueries() async {
    guard let projection = peerChatProjection, let connector = desktopConnector,
          let recoveryQueries = connector.recoveryQueries else { return }
    let destinations = Dictionary(grouping: projection.store.contacts.compactMap { projection.destination(for: $0) }
      .filter(\.desktop), by: { $0.peer.remoteSignalName })
    let work = recoveryQueries { binding in
      guard let targets = destinations[binding.desktopId], targets.count == 1, let target = targets.first,
            target.routeId == binding.identity.clientRouteId,
            let identity = try? MqttBusinessIdentity(target.peer.binding) else { return false }
      return (try? routes.withIdentity(identity) { routes.readyForTopic(target.peer.binding.sendTopic) }) == true
    }
    for payload in work {
      guard !stopped, !Task.isCancelled else { return }
      do {
        try refreshDirectPeerBindings()
        guard let targets = destinations[payload.string("desktop_id")], targets.count == 1,
              let target = targets.first else { continue }
        let request = try connector.recoveryQueryRequest(payload, target: target)
        let wire = try routes.withOutgoing(identity: request.identity, topics: [request.topic]) {
          try engine.makeRecoveryQueryWire(request)
        }
        _ = await routes.publishTransientControl(topic: request.topic, wire: wire, secret: target.peer.binding.secret)
      } catch { onFailure(error) }
    }
  }

  private func pumpDesktopResultReceipts() {
    guard let projection = peerChatProjection, let connector = desktopConnector,
          let recovery = connector.resultRecovery?() else { return }
    let now = Int64(Date().timeIntervalSince1970 * 1_000)
    let destinations = Dictionary(grouping: projection.store.contacts.compactMap { projection.destination(for: $0) }
      .filter(\.desktop), by: { $0.peer.remoteSignalName })
    for work in recovery.receipts.due(nowMillis: now) {
      guard let targets = destinations[work.receipt.desktopId], targets.count == 1, let target = targets.first else { continue }
      do {
        if work.state == .confirmed {
          try connector.validateResultReceipt(work.receipt, target: target)
          try routes.withIdentity(MqttBusinessIdentity(target.peer.binding)) { _ = recovery.cleanup(work.receipt) }
          continue
        }
        let request = try connector.resultReceiptRequest(work, target: target)
        try routes.withOutgoing(identity: request.identity, topics: [request.topic]) {
          if let event = try journal.outbox.completions.event(identity: request.identity, messageID: request.messageID) {
            guard try request.matchesIntent(event.requestHash, storedTopic: event.topic) else { throw MqttChunkStorageError.corruptState }
            _ = recovery.receipts.claim(work, nowMillis: now)
          } else if let existing = try journal.outbox.entry(identity: request.identity, messageID: request.messageID) {
            guard try request.matchesIntent(existing.requestHash, storedTopic: existing.message.topic) else {
              throw MqttChunkStorageError.corruptState
            }
          } else {
            _ = try enqueue([request])
          }
        }
      } catch { onFailure(error) }
    }
  }

  func stop() async {
    guard !stopped else { return }
    stopped = true
    evidenceWaiters.values.forEach { $0.signal.finish() }
    evidenceWaiters.removeAll()
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
      try routes.acceptChunkState(packet, chunks: journal.outgoingChunks)
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
    guard let receipt = accepted.receipt else { return }
    if packet.payload[MqttDeliveryEnvelope.field] != nil {
      let frame = try MqttDeliveryEnvelope.parseVerifiedFrame(packet.payload, sender: packet.sender,
        receiver: packet.receiver, ingressBroker: packet.ingress.brokerID)
      _ = await receiptRetry.offer(scope: packet.scope, message: receipt.messageID, attempt: frame.attempt.attemptID,
        now: monotonic()) { [weak routes = self.routes, journal = self.journal] in
          guard let routes else { return false }
          return try await routes.publishStoredReceipt(packet, inbox: journal.inbox)
        }
    } else {
      await offerLogicalReceipt(packet, proof: receipt, remoteName: remoteName)
    }
  }

  private func receiveChunks(_ packet: MqttPeerRoutes.VerifiedPacket, remoteName: String, probe: Bool) async throws {
    let (state, proof) = try routes.withCurrentIdentity(packet) { identity in
      try storeChunks(packet, identity: identity, remoteName: remoteName, probe: probe)
    }
    if let state {
      _ = try await routes.publishIngressReply(packet, payload: state)
    }
    if !stopped, let proof { await offerLogicalReceipt(packet, proof: proof, remoteName: remoteName) }
  }

  private func offerLogicalReceipt(_ packet: MqttPeerRoutes.VerifiedPacket, proof: MqttBusinessInbox.Receipt,
                                   remoteName: String) async {
    let cache = LogicalReceiptWire()
    let ingress = packet.ingress
    let retryIdentity = [proof.identity.binding, ingress.configurationID, ingress.brokerID,
      String(ingress.generation), proof.wireHash].joined(separator: "\0")
    let attempt = "logical:" + MqttRouteProtocol.digest(Data(retryIdentity.utf8))
    _ = await receiptRetry.offer(scope: packet.scope, message: proof.messageID, attempt: attempt,
      now: monotonic()) { [weak self] in
        guard let self else { return false }
        return try await self.publishLogicalReceipt(packet, proof: proof, remoteName: remoteName, cache: cache)
      }
  }

  private func publishLogicalReceipt(_ packet: MqttPeerRoutes.VerifiedPacket, proof: MqttBusinessInbox.Receipt,
                                     remoteName: String, cache: LogicalReceiptWire) async throws -> Bool {
    guard !stopped else { return false }
    let inbox = journal.inbox
    let stillValid = {
      try inbox.storedReceipt(identity: proof.identity, messageID: proof.messageID, wireHash: proof.wireHash) != nil
    }
    let destination = try peerChatProjection?.currentDestination(proof.identity)
    let peerChat = destination?.desktop == false
    let payload: [String: Any]? = try routes.withCurrentIdentity(packet) { identity in
      guard identity == proof.identity, try stillValid() else { return nil }
      if cache.payload == nil {
        cache.payload = try engine.makeStoredReceiptWire(identity: identity, messageID: proof.messageID,
          wireHash: proof.wireHash, remoteName: remoteName, peerChat: peerChat)
      }
      return cache.payload
    }
    guard let payload else { return false }
    return try await routes.publishIngressReply(packet, payload: payload, stillValid: stillValid)
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
        if payload.string("type") == "input_attachment_receipt",
           let projection = peerChatProjection, let attachments = outgoingAttachments {
          try await processOutgoingAttachmentReceipt(item, payload: payload, projection: projection, attachments: attachments)
          continue
        }
        if let projection = peerChatProjection, let attachments = incomingAttachments {
          try await projectDirectInbound(item, payload: payload, projection: projection, attachments: attachments)
        } else {
          try await projectInbound(item)
        }
        guard !stopped else { return }
        try routes.withIdentity(item.identity) {
          guard try journal.inbox.complete(identity: item.identity, messageID: item.messageID) else {
            throw MqttChunkStorageError.corruptState
          }
        }
      } catch DesktopPeerArtifactPending.awaitingChunks {
        continue
      } catch {
        if error is CancellationError { throw error }
        onFailure(error)
      }
    }
    if page.count < 16 { inboxCursor = "" }
  }

  private func processOutgoingAttachmentReceipt(_ item: MqttBusinessInbox.Pending, payload: [String: Any],
      projection: MqttPeerChatProjection, attachments: AgentOutboundAttachmentTransferStore) async throws {
    guard let target = try projection.currentDestination(item.identity),
          payload.string("client_route_id") == target.routeId,
          payload.string("message_id") == item.messageID,
          ["stored", "missing", "failed"].contains(payload.string("status")) else { throw MqttRouteError.invalidPayload }
    let transferID = payload.string("transfer_id").lowercased()
    let source = payload.string("source_message_id")
    guard MqttRouteProtocol.hex(transferID, count: 64),
          let sourceID = UUID(uuidString: source) else { throw MqttRouteError.invalidPayload }
    let bodyID = sourceID.uuidString
    func awaitingAttachment() throws -> MqttSignalSendRequest? {
      try routes.withIdentity(item.identity) {
        guard let body = try journal.outbox.entry(identity: item.identity, messageID: bodyID),
              body.message.blockedByAttachmentTransferIds.contains(transferID) else { return nil }
        guard let request = body.deferredRequest, request.attachmentDependencies.contains(transferID),
              body.message.clientSourceMessageId == source else {
          throw MqttChunkStorageError.corruptState
        }
        return request
      }
    }
    func complete() throws {
      try routes.withIdentity(item.identity) {
        guard try journal.inbox.complete(identity: item.identity, messageID: item.messageID) else {
          throw MqttChunkStorageError.corruptState
        }
      }
    }
    guard try awaitingAttachment() != nil else { try complete(); return }
    let transfer = try await onAttachmentQueue {
      guard let value = attachments.find(transferID) else { throw AgentAttachmentTransferError.contentUnavailable }
      return value
    }
    try Task.checkCancellation()
    guard !stopped else { throw CancellationError() }
    try refreshDirectPeerBindings()
    guard let body = try awaitingAttachment() else { try complete(); return }
    guard let owner = try queuedAttachmentOwner(transfer, body: body, target: target, projection: projection)
    else { try complete(); return }
    let blob = body.blobAttachmentDependencies?.contains(transferID) == true
    var proof = payload
    proof["status"] = "stored"
    guard transfer.matchesStoredReceipt(proof) else {
      throw MqttRouteError.identityChanged
    }
    if blob {
      if payload.string("status") == "missing" { try complete(); return }
      guard AgentBlobProtocol.receiptMatches(attachment: transfer, receipt: proof) else { throw MqttRouteError.identityChanged }
    }
    if payload.string("status") == "failed" {
      guard blob else { throw MqttRouteError.invalidPayload }
      try routes.withIdentity(item.identity) {
        if let team = owner.team {
          guard let record = desktopConnector?.recordTeamAttachmentFailure else { throw MqttRouteError.identityChanged }
          try record(team)
        }
        if owner.projectsAttachmentToTranscript {
          try projection.store.projectPeerAttachmentReceipt(transfer, sourceID: owner.message.id,
            contactID: owner.message.contactId, failed: true, wireSourceID: source)
        }
        try journal.consumeFailedBlobAttachment(item, bodyID: bodyID, transfer: transfer)
      }
      return
    }
    guard owner.maySend else { try complete(); return }
    if payload.string("status") == "stored" {
      try routes.withIdentity(item.identity) {
        if owner.projectsAttachmentToTranscript {
          try projection.store.projectPeerAttachmentReceipt(transfer, sourceID: owner.message.id,
            contactID: owner.message.contactId, wireSourceID: source)
        }
        try journal.consumeStoredAttachment(item, bodyID: bodyID, transfer: transfer)
      }
      return
    }

    let indices = try AgentAttachmentTransferProtocol.expandMissingRanges(payload["missing_ranges"], chunkCount: transfer.chunkCount)
    guard !indices.isEmpty else { throw MqttRouteError.invalidPayload }
    var scheduled = 0
    for index in indices {
      let id = try MqttPeerChatProjection.stableID([item.key, transferID, String(index), "missing"])
      if try journal.outbox.entry(identity: item.identity, messageID: id) != nil ||
        journal.outbox.completions.event(identity: item.identity, messageID: id) != nil { continue }
      // The durable request and deterministic chunk IDs are the restart cursor.
      guard scheduled < 4 else { return }
      var chunk = try await onAttachmentQueue { try transfer.chunkPayload(index: index, nowMillis: item.createdAt) }
      try Task.checkCancellation()
      guard !stopped else { throw CancellationError() }
      try refreshDirectPeerBindings()
      guard let current = try awaitingAttachment(),
            try queuedAttachmentOwner(transfer, body: current, target: target, projection: projection)?.maySend == true
      else { try complete(); return }
      chunk["message_id"] = id
      if body.contactID == target.contactId { chunk["peer_chat"] = true }
      let request = try MqttSignalSendRequest(identity: item.identity, payload: chunk, remoteName: target.peer.remoteSignalName,
        topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .chunk,
        requiresValidatedNetwork: transfer.requiresValidatedNetwork, attachmentTransferID: transferID,
        sourceMessageID: body.contactID == target.contactId ? "" : source, contactID: body.contactID)
      do { _ = try enqueue([request]) }
      catch MqttChunkStorageError.alreadyDelivered { }
      catch MqttChunkStorageError.capacityExceeded { return }
      scheduled += 1
    }
    try complete()
  }

  private func projectDirectInbound(_ item: MqttBusinessInbox.Pending, payload: [String: Any],
                                    projection: MqttPeerChatProjection, attachments: AgentIncomingAttachmentTransferStore) async throws {
    guard let target = try projection.currentDestination(item.identity),
          payload["message_id"] as? String == item.messageID else { throw MqttRouteError.identityChanged }
    let type = payload.string("type")
    if type == AgentBlobRelayConfiguration.payloadType || type == AgentBlobArtifactContract.offerType {
      guard target.desktop, let receiveDesktopBlobControl else { throw MqttRouteError.identityChanged }
      try await receiveDesktopBlobControl(payload, target, item.identity)
      return
    }
    if type == "agent_task_evidence" {
      guard target.desktop else { throw MqttRouteError.identityChanged }
      guard let pending = evidenceWaiters[payload.string("request_id")] else { return }
      guard pending.identity == item.identity,
            let response = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: item.payload),
            pending.request.matchesTransportResponse(response, authenticatedDesktopId: target.peer.remoteSignalName,
              mode: pending.mode) else { throw MqttRouteError.identityChanged }
      pending.signal.yield(response)
      pending.signal.finish()
      return
    }
    if target.desktop, let desktopConnector, MqttDesktopConnectorProjection.handles(payload) {
      try desktopConnector.project(item, payload: payload, target: target)
      return
    }
    if target.desktop, type == "artifact_chunk" {
      try await storeDesktopPeerArtifact(item, payload: payload, projection: projection, target: target)
      return
    }
    let localName = engine.identity.name
    let remoteName = target.peer.remoteSignalName
    let route = target.routes
    if type == "input_attachment_manifest" || type == "input_attachment_chunk" {
      guard !target.desktop else { throw MqttRouteError.invalidPayload }
      let receipt: [String: Any]? = try await onAttachmentQueue {
        try attachments.ingestDurably(payload: payload, sourceId: remoteName, localGalaxySSIId: localName, routes: route)
      }
      try Task.checkCancellation()
      guard !stopped else { throw CancellationError() }
      try refreshDirectPeerBindings()
      if let receipt {
        let request = try projection.attachmentReceiptRequest(receipt, for: item)
        do { _ = try enqueue([request]) }
        catch MqttChunkStorageError.alreadyDelivered { }
      }
      return
    }
    if let descriptors = payload["attachments"] as? [[String: Any]], !descriptors.isEmpty {
      if target.desktop {
        guard type == "peer_message", descriptors.count <= 12, let desktopArtifacts else {
          throw MqttRouteError.invalidPayload
        }
        let source = try projection.desktopPeerSource(payload, target: target)
        guard UUID(uuidString: source) == UUID(uuidString: item.messageID) else { throw MqttRouteError.identityChanged }
        let resolved: [[String: Any]]
        if descriptors.contains(where: { $0.string("artifact_uri").hasPrefix("galaxyssi-artifact://blob/") }) {
          let artifacts = try projection.desktopPeerBlobDescriptors(descriptors, payload: payload, item: item, target: target)
          resolved = try await onAttachmentQueue {
            try zip(artifacts, descriptors).map { artifact, descriptor in
              guard let stored = try desktopArtifacts.verifiedPeerBlobDescriptor(artifact,
                durationMillis: descriptor.int64("duration_ms")) else { throw DesktopPeerArtifactPending.awaitingChunks }
              return stored
            }
          }
        } else {
          let artifacts = try descriptors.map { try MqttDesktopPeerArtifact($0, source: source, identity: item.identity) }
          guard Set(artifacts.map(\.localID)).count == artifacts.count else { throw MqttRouteError.invalidPayload }
          resolved = try await onAttachmentQueue {
            try zip(artifacts, descriptors).map { artifact, descriptor in
              guard let stored = try desktopArtifacts.verifiedPeerDescriptor(artifact, durationMillis: descriptor.int64("duration_ms"))
              else { throw DesktopPeerArtifactPending.awaitingChunks }
              return stored
            }
          }
        }
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        try refreshDirectPeerBindings()
        try routes.withIdentity(item.identity) {
          _ = try projection.projectInbound(item, resolvedAttachments: resolved)
        }
        return
      }
      guard !target.desktop, descriptors.count <= 64, type == "peer_message" || type == "text" else {
        throw MqttRouteError.invalidPayload
      }
      let resolved: [[String: Any]] = try await onAttachmentQueue {
        guard let value = attachments.resolveMessageAttachments(sourceId: remoteName, payload: payload,
          routes: route, localGalaxySSIId: localName) else { throw AgentAttachmentTransferError.contentUnavailable }
        return value
      }
      try Task.checkCancellation()
      guard !stopped else { throw CancellationError() }
      try refreshDirectPeerBindings()
      _ = try projection.projectInbound(item, resolvedAttachments: resolved)
    } else {
      _ = try projection.projectInbound(item)
    }
  }

  private func storeDesktopPeerArtifact(_ item: MqttBusinessInbox.Pending, payload: [String: Any],
      projection: MqttPeerChatProjection, target: MqttPeerChatProjection.Destination) async throws {
    guard let desktopArtifacts, payload["peer_chat"] as? Bool == true, payload["phone_owned"] as? Bool == true,
          item.payload.count <= 512 * 1_024 else { throw MqttRouteError.invalidPayload }
    let source = try projection.desktopPeerSource(payload, target: target)
    guard payload.string("task_id") == source else { throw MqttRouteError.identityChanged }
    let artifact = try MqttDesktopPeerArtifact(payload, source: source, identity: item.identity)
    let result = try await onAttachmentQueue {
      try desktopArtifacts.ingest(artifact.storagePayload(payload))
    }
    try Task.checkCancellation()
    guard !stopped else { throw CancellationError() }
    try refreshDirectPeerBindings()
    try routes.withIdentity(item.identity) {}
    guard result.completed else { return }
    let id = try MqttPeerChatProjection.stableID([artifact.localID, artifact.digest, "desktop-artifact-stored"])
    let receipt: [String: Any] = ["type": "artifact_receipt", "message_id": id, "desktop_id": target.peer.remoteSignalName,
      "artifact_id": artifact.id, "artifact_uri": artifact.uri, "task_id": artifact.taskID, "sha256": artifact.digest,
      "status": "stored", "client_route_id": target.routeId]
    let request = try MqttSignalSendRequest(identity: item.identity, payload: receipt, remoteName: target.peer.remoteSignalName,
      topic: target.peer.binding.sendTopic, clientRouteID: target.routeId, traffic: .control, contactID: target.contactId)
    do { _ = try enqueue([request]) }
    catch MqttChunkStorageError.alreadyDelivered { }
  }

  private func onAttachmentQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
      attachmentQueue.async { continuation.resume(with: Result { try work() }) }
    }
  }
}
