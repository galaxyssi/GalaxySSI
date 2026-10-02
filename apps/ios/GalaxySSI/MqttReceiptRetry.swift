import Foundation

// Callers supply monotonic milliseconds. Durable sender replay owns recovery after expiry/process death.
actor MqttReceiptRetry {
  private struct Key: Hashable { let scope: String; let message: String; let attempt: String }
  private final class Pending {
    var due: Int64
    let expires: Int64
    let send: () async throws -> Bool
    var running = false
    init(now: Int64, send: @escaping () async throws -> Bool) {
      due = now
      expires = now + 30_000
      self.send = send
    }
  }

  private var pending: [Key: Pending] = [:]
  private var order: [Key] = []
  var count: Int { pending.count }

  @discardableResult
  func offer(scope: String, message: String, attempt: String, now: Int64,
             send: @escaping () async throws -> Bool) async -> Bool {
    guard now >= 0, now <= Int64.max - 30_000,
          !scope.isEmpty, scope.utf8.count <= 512, !message.isEmpty, message.utf8.count <= 256,
          !attempt.isEmpty, attempt.utf8.count <= 256 else { return false }
    expire(now: now)
    let key = Key(scope: scope, message: message, attempt: attempt)
    guard pending[key] == nil, pending.count < 1024, pending.keys.filter({ $0.scope == scope }).count < 64 else { return false }
    let item = Pending(now: now, send: send)
    pending[key] = item
    order.append(key)
    await run(key, item: item, now: now)
    return true
  }

  func drain(now: Int64, limit: Int = 16) async {
    guard now >= 0, now <= Int64.max - 30_000 else { return }
    expire(now: now)
    let selected = order.compactMap { key -> (Key, Pending)? in
      guard let item = pending[key], !item.running, item.due <= now else { return nil }
      return (key, item)
    }.prefix(max(0, min(16, limit)))
    for (key, item) in selected { await run(key, item: item, now: now) }
  }

  func forget(scope: String) {
    order.removeAll { key in
      guard key.scope == scope else { return false }
      pending.removeValue(forKey: key)
      return true
    }
  }

  func clear() { pending.removeAll(); order.removeAll() }

  private func expire(now: Int64) {
    order.removeAll { key in
      guard let item = pending[key] else { return true }
      guard !item.running, item.expires <= now else { return false }
      pending.removeValue(forKey: key)
      return true
    }
  }

  private func run(_ key: Key, item: Pending, now: Int64) async {
    guard pending[key] === item, !item.running, item.due <= now, item.expires > now else { return }
    item.running = true
    item.due = now + 500
    order.removeAll { $0 == key }
    order.append(key)
    let sent = (try? await item.send()) ?? false
    item.running = false
    if sent, pending[key] === item {
      pending.removeValue(forKey: key)
      order.removeAll { $0 == key }
    }
  }
}
