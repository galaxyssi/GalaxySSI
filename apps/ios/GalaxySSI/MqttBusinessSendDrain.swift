import Foundation

// The durable outbox owns retries. A broker enqueue or PUBACK never removes a business message.
actor MqttBusinessSendDrain {
  struct Failure { let scope: String; let messageID: String; let error: Error }
  struct Result {
    var busy = false
    var stopped = false
    var inspected = 0
    var submitted = 0
    var recoveredRoutes = 0
    var failures: [Failure] = []
  }
  private let outbox: MqttBusinessOutbox
  private let routes: MqttPeerRoutes
  private let dispatcher: MqttDeliveryDispatch
  private let chunks: MqttOutgoingChunks
  private let engine: GalaxySSISignalEngine
  private let now: () -> Date
  private var cursors: [String: MqttBusinessOutbox.Cursor] = [:]
  private var nextPeer = 0
  private var running = false
  private var closed = false

  private enum Publication {
    case direct(MqttDeliveryDispatch.Delivery)
    case fragments(MqttDeliveryEnvelope.Message, MqttOutgoingChunks.Batch)
  }

  init(outbox: MqttBusinessOutbox, routes: MqttPeerRoutes, dispatcher: MqttDeliveryDispatch, chunks: MqttOutgoingChunks,
       engine: GalaxySSISignalEngine, now: @escaping () -> Date = Date.init) {
    self.outbox = outbox; self.routes = routes; self.dispatcher = dispatcher
    self.engine = engine; self.now = now; self.chunks = chunks
  }

  func close() { closed = true }

  func drain(identities: [MqttBusinessIdentity], validatedNetwork: Bool, limit: Int = 16,
             authorize: @Sendable (MqttBusinessOutbox.Entry) async throws -> Bool = { _ in true }) async throws -> Result {
    guard (1...64).contains(limit), identities.count <= 10_000,
          Set(identities.map(\.scope)).count == identities.count else { throw MqttRouteError.invalidPayload }
    try identities.forEach { try $0.validate() }
    try Task.checkCancellation()
    if closed { var result = Result(); result.stopped = true; return result }
    if running { var result = Result(); result.busy = true; return result }
    running = true
    defer { running = false }
    var result = Result()
    let peers = identities.sorted { $0.scope < $1.scope }
    let bindings = Set(peers.map(\.binding))
    cursors = cursors.filter { bindings.contains($0.key) }
    guard !peers.isEmpty else { nextPeer = 0; return result }
    routes.wakeTransportForTraffic()
    nextPeer %= peers.count
    // Visit a bounded number of peers as well as records, including offline and blocked peers.
    for _ in 0..<min(limit, peers.count) {
      try Task.checkCancellation()
      if closed { result.stopped = true; return result }
      if result.inspected >= limit { break }
      let identity = peers[nextPeer]
      nextPeer = (nextPeer + 1) % peers.count
      let page: MqttBusinessOutbox.Page
      do {
        page = try routes.withIdentity(identity) {
          try outbox.pendingPage(identity: identity, now: now(), after: cursors[identity.binding],
            limit: min(4, limit - result.inspected))
        }
        cursors[identity.binding] = page.next
      } catch {
        result.failures.append(Failure(scope: identity.scope, messageID: "", error: error))
        continue
      }
      for item in page.entries {
        try Task.checkCancellation()
        if closed { result.stopped = true; return result }
        result.inspected += 1
        do {
          if item.message.blockedByAttachmentTransferIds.isEmpty {
            guard try await authorize(item) else { continue }
          }
          try Task.checkCancellation()
          if closed { result.stopped = true; return result }
          let delivery: (String, Publication)? = try routes.withPendingTopic(identity: identity,
            storedTopic: item.message.topic) { topic in
            // Do not put a ready-route guard before the durable scan: it makes a stalled route
            // invisible forever. Recovery itself retains authentication, epoch and cooldown checks.
            guard routes.readyForTopic(topic) else {
              if routes.recoverBlockedSend(topic: topic) { result.recoveredRoutes += 1 }
              routes.request(identity.scope)
              return nil
            }
            guard var current = try outbox.entry(identity: identity, messageID: item.message.messageId),
                  current.message.blockedByAttachmentTransferIds.isEmpty,
                  !current.message.requiresValidatedNetwork || validatedNetwork else { return nil }
            if !current.isPrepared {
              guard let prepared = try engine.prepareFirstSend(identity: identity,
                messageID: current.message.messageId, validatedNetwork: validatedNetwork, now: now()) else { return nil }
              current = prepared
            }
            let wire = Data(current.message.wirePayload.utf8)
            guard let traffic = MqttMultipathPolicy.Traffic(rawValue: current.traffic) else {
              throw MqttRouteError.invalidPayload
            }
            let message = try MqttDeliveryEnvelope.Message(messageID: current.message.messageId,
              contentHash: current.wireHash, sender: identity.local, receiver: identity.remote, traffic: traffic.rawValue)
            let prepared: Publication
            if try MqttSignalDelivery.requiresFragments(topic: topic, wire: wire, message: message) {
              let parts = try GalaxySSIMqttWireChunking.encode(wirePayload: current.message.wirePayload,
                directLimitBytes: 1).map { part -> [String: Any] in
                  guard let value = try JSONSerialization.jsonObject(with: Data(part.utf8)) as? [String: Any] else {
                    throw MqttRouteError.invalidPayload
                  }
                  return value
                }
              prepared = .fragments(message, try chunks.prepare(authenticatedScope: identity.binding, parts: parts))
            } else {
              guard let direct = try routes.prepareDelivery(topic: topic, wire: wire, messageID: message.messageID,
                traffic: traffic) else { return nil }
              prepared = .direct(direct)
            }
            try outbox.updateRetry(identity: identity, messageID: current.message.messageId, published: false, now: now())
            return (topic, prepared)
          }
          guard let (topic, delivery) = delivery else { continue }
          let submitted: Bool
          switch delivery {
          case .direct(let packet):
            _ = try await dispatcher.submit(topic: topic, delivery: packet)
            submitted = true
          case .fragments(let message, let batch):
            submitted = try await publishFragments(topic: topic, storedTopic: item.message.topic,
              identity: identity, message: message, batch: batch)
          }
          try Task.checkCancellation()
          if closed { result.stopped = true; return result }
          // Submission is a local enqueue, not a physical publication or PUBACK.
          if submitted { result.submitted += 1 }
        } catch {
          if error is CancellationError { throw error }
          result.failures.append(Failure(scope: identity.scope, messageID: item.message.messageId, error: error))
        }
      }
    }
    return result
  }

  private func publishFragments(topic: String, storedTopic: String, identity: MqttBusinessIdentity, message: MqttDeliveryEnvelope.Message,
                                batch: MqttOutgoingChunks.Batch) async throws -> Bool {
    var submitted = false
    let query = batch.query
    for selection in batch.selected {
      try Task.checkCancellation()
      guard !closed else { return submitted }
      let index = selection.index
      let broker = try await routes.publishChunk(topic: topic, identity: identity, message: message,
        query: query, selection: selection, attempted: batch.attempted(index: index),
        isPending: { [outbox, chunks] in
          guard let entry = try outbox.entry(identity: identity, messageID: message.messageID),
                entry.isPrepared, entry.wireHash == message.contentHash, entry.message.topic == storedTopic else { return false }
          return try chunks.permits(authenticatedScope: identity.binding, query: query, index: index)
        })
      if let broker {
        submitted = true
        try routes.withOutgoing(identity: identity, topics: [topic]) {
          _ = try chunks.recordPath(authenticatedScope: identity.binding, query: query, index: index, broker: broker)
        }
      }
    }
    return submitted
  }
}
