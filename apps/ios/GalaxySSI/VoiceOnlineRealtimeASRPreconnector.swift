import Foundation

final class VoiceOnlineRealtimeASREventRelay: @unchecked Sendable {
  typealias EventHandler = VoiceOnlineRealtimeASRSession.EventHandler

  private let lock = NSLock()
  private var handler: EventHandler?
  private var pendingEvents: [VoiceOnlineRealtimeASREvent] = []

  init(handler: EventHandler? = nil) {
    self.handler = handler
  }

  func send(_ event: VoiceOnlineRealtimeASREvent) {
    let currentHandler: EventHandler? = locked {
      guard let handler else {
        pendingEvents.append(event)
        if pendingEvents.count > 12 {
          pendingEvents.removeFirst(pendingEvents.count - 12)
        }
        return nil
      }
      return handler
    }
    currentHandler?(event)
  }

  func install(_ handler: @escaping EventHandler) {
    let events: [VoiceOnlineRealtimeASREvent] = locked {
      self.handler = handler
      let events = pendingEvents
      pendingEvents.removeAll(keepingCapacity: false)
      return events
    }
    events.forEach(handler)
  }

  private func locked<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }
}

final class VoiceOnlineRealtimeASRPreconnector: @unchecked Sendable {
  private struct Prepared {
    let key: String
    let relay: VoiceOnlineRealtimeASREventRelay
    let session: VoiceOnlineRealtimeASRSession
    let expiresAtMillis: Int64
  }

  private let lock = NSLock()
  private let credentialSource: VoiceOnlineRealtimeASRCredentialSource
  private let idleTTLMillis: Int64
  private var prepared: Prepared?

  init(
    credentialSource: VoiceOnlineRealtimeASRCredentialSource = VoiceOnlineRealtimeASRCredentialSource(),
    idleTTLMillis: Int64 = 30_000
  ) {
    self.credentialSource = credentialSource
    self.idleTTLMillis = min(max(idleTTLMillis, 1_000), 120_000)
  }

  func preconnect(config: VoiceOnlineRealtimeASRConfig) async -> Bool {
    let key = preconnectionKey(config)
    let now = Self.nowMillis
    let existing = locked { () -> Prepared? in
      guard let prepared, prepared.expiresAtMillis > now else {
        let expired = prepared
        self.prepared = nil
        return expired
      }
      return prepared.key == key ? prepared : nil
    }
    if let existing, existing.key == key, existing.expiresAtMillis > now {
      return true
    }
    if let existing {
      await existing.session.cancel(reason: "preconnect_replaced")
    }

    let relay = VoiceOnlineRealtimeASREventRelay()
    let session = VoiceOnlineRealtimeASRSession(
      config: config,
      credentialSource: credentialSource,
      eventHandler: relay.send
    )
    guard await session.start() else { return false }

    let replacement = locked { () -> Prepared? in
      let replacement = prepared
      prepared = Prepared(
        key: key,
        relay: relay,
        session: session,
        expiresAtMillis: Self.nowMillis + idleTTLMillis
      )
      return replacement
    }
    if let replacement {
      await replacement.session.cancel(reason: "preconnect_replaced")
    }
    return true
  }

  func acquire(
    config: VoiceOnlineRealtimeASRConfig,
    eventHandler: @escaping VoiceOnlineRealtimeASRSession.EventHandler
  ) -> VoiceOnlineRealtimeASRSession {
    let key = preconnectionKey(config)
    let now = Self.nowMillis
    var stale: Prepared?
    let match = locked { () -> Prepared? in
      guard let prepared else { return nil }
      guard prepared.key == key, prepared.expiresAtMillis > now else {
        stale = prepared
        self.prepared = nil
        return nil
      }
      self.prepared = nil
      return prepared
    }
    if let stale {
      Task { await stale.session.cancel(reason: "preconnect_mismatch") }
    }
    if let match {
      match.relay.install(eventHandler)
      return match.session
    }

    let relay = VoiceOnlineRealtimeASREventRelay(handler: eventHandler)
    return VoiceOnlineRealtimeASRSession(
      config: config,
      credentialSource: credentialSource,
      eventHandler: relay.send
    )
  }

  func discard(reason: String) {
    let session = locked { () -> VoiceOnlineRealtimeASRSession? in
      let session = prepared?.session
      prepared = nil
      return session
    }
    if let session {
      Task { await session.cancel(reason: reason) }
    }
  }

  private func preconnectionKey(_ config: VoiceOnlineRealtimeASRConfig) -> String {
    [
      config.voiceSessionID,
      config.transcriptID,
      config.language,
      config.requestServerDataDeletion ? "delete" : "retain"
    ].joined(separator: ":")
  }

  private static var nowMillis: Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }

  private func locked<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }
}
