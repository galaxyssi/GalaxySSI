import Foundation

// Coalescing only. Existing MQTT maintenance drains callbacks; senders recheck current pair authorization.
final class MqttChunkFeedback {
  private struct Key: Hashable { let scope: String; let transfer: String; let request: String }
  private struct Pending { let due: Int64; let revision: Int64; let send: () -> Void }
  private let lock = NSLock()
  private var pending: [Key: Pending] = [:]
  private var order: [Key] = []

  func offer(scope: String, transfer: String, request: String, revision: Int64, now: Int64,
             urgent: Bool = false, send: @escaping () -> Void) -> (() -> Void)? {
    lock.lock()
    defer { lock.unlock() }
    guard (try? MqttDeliveryEnvelope.checkedText(scope, maximum: 512)) != nil,
          MqttRouteProtocol.hex(transfer, count: 64), MqttRouteProtocol.hex(request, count: 32),
          (0...MqttRouteProtocol.maximumInteger).contains(revision), now >= 0, now <= Int64.max - 200 else { return nil }
    let key = Key(scope: scope, transfer: transfer, request: request)
    let previous = pending[key]
    if let previous, revision < previous.revision { return nil }
    if urgent {
      pending.removeValue(forKey: key)
      order.removeAll { $0 == key }
      return send
    }
    if previous == nil {
      guard pending.count < 1024, pending.keys.filter({ $0.scope == scope }).count < 64 else { return nil }
      order.append(key)
    }
    pending[key] = Pending(due: previous?.due ?? (now + 200), revision: revision, send: send)
    return nil
  }

  func drain(now: Int64, limit: Int = 16) -> [() -> Void] {
    lock.lock()
    defer { lock.unlock() }
    let keys = Array(order.filter { pending[$0].map { $0.due <= now } ?? false }.prefix(max(0, min(16, limit))))
    let selected = Set(keys)
    order.removeAll { selected.contains($0) }
    return keys.compactMap { pending.removeValue(forKey: $0)?.send }
  }

  func forget(scope: String) {
    lock.lock()
    defer { lock.unlock() }
    pending = pending.filter { $0.key.scope != scope }
    order.removeAll { $0.scope == scope }
  }
  func clear() { lock.lock(); pending.removeAll(); order.removeAll(); lock.unlock() }
  var count: Int { lock.lock(); defer { lock.unlock() }; return pending.count }
}
