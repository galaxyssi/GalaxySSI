import Foundation

// Maintenance owns scheduling; callbacks recheck the authenticated relationship before publishing.
final class MqttChunkFeedback {
  private struct Key: Hashable { let scope: String; let transfer: String; let request: String }
  private final class Pending {
    var due: Int64
    let expires: Int64
    let revision: Int64
    let send: () async -> Bool
    var running = false
    init(due: Int64, expires: Int64, revision: Int64, send: @escaping () async -> Bool) {
      self.due = due; self.expires = expires; self.revision = revision; self.send = send
    }
  }
  private let lock = NSLock()
  private var pending: [Key: Pending] = [:]
  private var order: [Key] = []

  func offer(scope: String, transfer: String, request: String, revision: Int64, now: Int64,
             urgent: Bool = false, send: @escaping () async -> Bool) -> (() async -> Void)? {
    locked {
      guard (try? MqttDeliveryEnvelope.checkedText(scope, maximum: 512)) != nil,
            MqttRouteProtocol.hex(transfer, count: 64), MqttRouteProtocol.hex(request, count: 32),
            (0...MqttRouteProtocol.maximumInteger).contains(revision), now >= 0, now <= Int64.max - 30_000 else { return nil }
      expire(now: now)
      let key = Key(scope: scope, transfer: transfer, request: request)
      let previous = pending[key]
      if let previous, revision < previous.revision { return nil }
      if previous == nil {
        guard pending.count < 1024, pending.keys.filter({ $0.scope == scope }).count < 64 else { return nil }
        order.append(key)
      }
      let item = Pending(due: urgent ? now : (previous?.due ?? now + 200), expires: now + 30_000,
        revision: revision, send: send)
      pending[key] = item
      return urgent ? claim(key, item: item, now: now) : nil
    }
  }

  func drain(now: Int64, limit: Int = 16) -> [() async -> Void] {
    locked {
      guard now >= 0, now <= Int64.max - 30_000 else { return [] }
      expire(now: now)
      let keys = Array(order.filter { key in
        pending[key].map { !$0.running && $0.due <= now } ?? false
      }.prefix(max(0, min(16, limit))))
      return keys.compactMap { key in pending[key].map { claim(key, item: $0, now: now) } }
    }
  }

  // Reference identity prevents a late completion deleting a newer bitmap.
  private func claim(_ key: Key, item: Pending, now: Int64) -> () async -> Void {
    item.running = true
    item.due = now + 500
    order.removeAll { $0 == key }
    order.append(key)
    return { [weak self] in
      guard let self, self.locked({ self.pending[key] === item }) else { return }
      let accepted = await item.send()
      self.locked {
        item.running = false
        if accepted, self.pending[key] === item {
          self.pending.removeValue(forKey: key)
          self.order.removeAll { $0 == key }
        }
      }
    }
  }

  private func expire(now: Int64) {
    pending = pending.filter { $0.value.running || $0.value.expires > now }
    order.removeAll { pending[$0] == nil }
  }
  func forget(scope: String) {
    locked {
      pending = pending.filter { $0.key.scope != scope }
      order.removeAll { $0.scope == scope }
    }
  }
  func clear() { locked { pending.removeAll(); order.removeAll() } }
  var count: Int { locked { pending.count } }
  private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
}
