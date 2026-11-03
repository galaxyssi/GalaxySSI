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
  private let engine: GalaxySSISignalEngine
  private let now: () -> Date
  private var cursors: [String: MqttBusinessOutbox.Cursor] = [:]
  private var nextPeer = 0
  private var running = false
  private var closed = false

  init(outbox: MqttBusinessOutbox, routes: MqttPeerRoutes, dispatcher: MqttDeliveryDispatch,
       engine: GalaxySSISignalEngine, now: @escaping () -> Date = Date.init) {
    self.outbox = outbox; self.routes = routes; self.dispatcher = dispatcher
    self.engine = engine; self.now = now
  }

  func close() { closed = true }

  func drain(identities: [MqttBusinessIdentity], validatedNetwork: Bool, limit: Int = 16) async throws -> Result {
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
          let delivery: MqttDeliveryDispatch.Delivery? = try routes.withOutgoing(identity: identity,
            topics: [item.message.topic]) {
            // Do not put a ready-route guard before the durable scan: it makes a stalled route
            // invisible forever. Recovery itself retains authentication, epoch and cooldown checks.
            guard routes.readyForTopic(item.message.topic) else {
              if routes.recoverBlockedSend(topic: item.message.topic) { result.recoveredRoutes += 1 }
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
            guard let traffic = MqttMultipathPolicy.Traffic(rawValue: current.traffic),
                  let prepared = try routes.prepareDelivery(topic: current.message.topic,
                    wire: Data(current.message.wirePayload.utf8), messageID: current.message.messageId, traffic: traffic) else { return nil }
            try outbox.updateRetry(identity: identity, messageID: current.message.messageId, published: false, now: now())
            return prepared
          }
          guard let delivery else { continue }
          _ = try await dispatcher.submit(topic: item.message.topic, delivery: delivery)
          try Task.checkCancellation()
          if closed { result.stopped = true; return result }
          try routes.withOutgoing(identity: identity, topics: [item.message.topic]) {
            try outbox.updateRetry(identity: identity, messageID: item.message.messageId, published: true, now: now())
          }
          result.submitted += 1
        } catch {
          if error is CancellationError { throw error }
          result.failures.append(Failure(scope: identity.scope, messageID: item.message.messageId, error: error))
        }
      }
    }
    return result
  }
}
