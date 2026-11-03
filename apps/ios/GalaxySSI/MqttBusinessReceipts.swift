import Foundation

// Both raw pair-AEAD receipts and previously decrypted durable application receipts.
final class MqttBusinessReceipts {
  private let routes: MqttPeerRoutes
  private let outbox: MqttBusinessOutbox
  private let dispatcher: MqttDeliveryDispatch
  private let now: () -> Date

  init(routes: MqttPeerRoutes, outbox: MqttBusinessOutbox, dispatcher: MqttDeliveryDispatch,
       now: @escaping () -> Date = Date.init) {
    self.routes = routes; self.outbox = outbox; self.dispatcher = dispatcher; self.now = now
  }

  func consumeStored(identity: MqttBusinessIdentity, receiptMessageID: String,
                     journal: MqttSignalStateJournal) async throws -> MqttDeliveryCompletions.Event? {
    guard let event = try routes.consumeStoredReceipt(identity: identity, receiptMessageID: receiptMessageID,
      journal: journal, now: now()) else { return nil }
    return try await resumeCompletion(identity: identity, messageID: event.messageID, journal: journal)
  }

  // Recover the commit-to-dispatch gap without consuming the UI/attachment event. Never trust a
  // caller-supplied event as delivery proof; reload it under the current relationship fence.
  func resumeCompletion(identity: MqttBusinessIdentity, messageID: String,
                        journal: MqttSignalStateJournal) async throws -> MqttDeliveryCompletions.Event? {
    guard let event = try routes.withIdentity(identity, commit: {
      try journal.outbox.completions.event(identity: identity, messageID: messageID)
    }) else { return nil }
    let verify = {
      try self.routes.withIdentity(identity) {
        guard let saved = try journal.outbox.completions.event(identity: identity, messageID: messageID),
              saved.wireHash == event.wireHash, saved.traffic == event.traffic else {
          throw MqttRouteError.unsolicitedAcknowledgement
        }
      }
    }
    // Application receipts prove logical delivery, not the RTT of any physical broker attempt.
    let accepted = try await dispatcher.acceptVerifiedMessage(peer: identity.scope, messageID: messageID,
      contentHash: event.wireHash, commit: verify)
    if !accepted { try verify() }
    return event
  }

  func accept(_ packet: MqttPeerRoutes.VerifiedPacket) async throws -> MqttDeliveryCompletions.Event? {
    guard packet.payload["type"] as? String == MqttDeliveryEnvelope.receiptType else { return nil }
    let frame = try routes.withCurrentIdentity(packet) { identity in
      try MqttDeliveryEnvelope.parseVerifiedReceipt(packet.payload, originalSender: identity.local, originalReceiver: identity.remote)
    }
    var completion: MqttDeliveryCompletions.Event?
    let commit = {
      completion = try self.routes.withCurrentIdentity(packet) { identity in
        if let pending = try self.outbox.entry(identity: identity, messageID: frame.message.messageID) {
          guard pending.isPrepared, pending.wireHash == frame.message.contentHash,
                pending.traffic == frame.message.traffic else { throw MqttRouteError.unsolicitedAcknowledgement }
          _ = try self.outbox.acknowledgeVerified(identity: identity, messageID: frame.message.messageID,
            wireHash: frame.message.contentHash, now: self.now())
        }
        guard let saved = try self.outbox.completions.event(identity: identity, messageID: frame.message.messageID),
              saved.wireHash == frame.message.contentHash, saved.traffic == frame.message.traffic else {
          throw MqttRouteError.unsolicitedAcknowledgement
        }
        return saved
      }
    }
    if try await dispatcher.acceptVerifiedReceipt(peer: packet.scope, frame: frame, commit: commit) { return completion }
    // A restart/expired observation may lose attempt attribution while the durable message remains.
    // Cancel matching logical copies without inventing an RTT sample for that unknown physical attempt.
    if try await dispatcher.acceptVerifiedMessage(peer: packet.scope, messageID: frame.message.messageID,
      contentHash: frame.message.contentHash, commit: commit) { return completion }
    try commit()
    return completion
  }
}

// The owner schedules repeated drains and supplies an idempotent DURABLE business-state writer.
// Returning from apply before persistence succeeds would lose the handoff after consume.
actor MqttBusinessDeliveryDrain {
  struct Failure { let key: String; let error: Error }
  struct Result {
    var busy = false
    var stopped = false
    var receipts = 0
    var completions = 0
    var failures: [Failure] = []
  }
  private let journal: MqttSignalStateJournal
  private let receipts: MqttBusinessReceipts
  private let routes: MqttPeerRoutes
  private let apply: (MqttDeliveryCompletions.Event) async throws -> Void
  private let now: () -> Int64
  private var inboxCursor = ""
  private var completionCursor = ""
  private var running = false
  private var closed = false

  init(journal: MqttSignalStateJournal, receipts: MqttBusinessReceipts, routes: MqttPeerRoutes,
       now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
       apply: @escaping (MqttDeliveryCompletions.Event) async throws -> Void) {
    self.journal = journal; self.receipts = receipts; self.routes = routes
    self.now = now; self.apply = apply
  }

  func close() { closed = true }

  // Keyset cursors advance over failures and unrelated inbox messages. A poison record cannot
  // starve later peers; failed records remain durable and are revisited on the next scan cycle.
  func drain(limit: Int = 8) async throws -> Result {
    guard (1...32).contains(limit) else { throw MqttRouteError.invalidPayload }
    try Task.checkCancellation()
    if closed { var result = Result(); result.stopped = true; return result }
    if running { var result = Result(); result.busy = true; return result }
    running = true
    defer { running = false }
    var result = Result()
    let pending = try journal.inbox.pending(afterKey: inboxCursor, limit: limit)
    for item in pending {
      try Task.checkCancellation()
      if closed { result.stopped = true; return result }
      inboxCursor = item.key
      do {
        if try await receipts.consumeStored(identity: item.identity, receiptMessageID: item.messageID, journal: journal) != nil {
          result.receipts += 1
        }
      } catch { result.failures.append(Failure(key: item.key, error: error)) }
    }
    if pending.count < limit { inboxCursor = "" }
    if closed { result.stopped = true; return result }
    let events = try journal.outbox.completions.pending(afterKey: completionCursor, limit: limit)
    for event in events {
      try Task.checkCancellation()
      if closed { result.stopped = true; return result }
      let key = try event.identity.key(messageID: event.messageID)
      completionCursor = key
      do {
        guard let current = try await receipts.resumeCompletion(identity: event.identity,
          messageID: event.messageID, journal: journal) else { throw MqttRouteError.unsolicitedAcknowledgement }
        if closed { result.stopped = true; return result }
        try Task.checkCancellation()
        // The business writer must also fence any asynchronous side effects against revocation.
        try await apply(current)
        if closed { result.stopped = true; return result }
        try Task.checkCancellation()
        try routes.withIdentity(event.identity) {
          _ = try journal.outbox.completions.consume(identity: event.identity, messageID: event.messageID, at: now())
        }
        result.completions += 1
      } catch { result.failures.append(Failure(key: key, error: error)) }
    }
    if events.count < limit { completionCursor = "" }
    return result
  }
}
