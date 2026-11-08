import Foundation
import UIKit

/// Bounded, fixed-lifetime storage. Reads never extend an entry's deadline.
final class GalaxySSIRuntimeCache<Key: Hashable, Value>: @unchecked Sendable {
  private struct Entry {
    let value: Value
    let deadline: TimeInterval
    let cost: Int
  }

  private let lock = NSLock()
  private let lifetime: TimeInterval
  private let maxCount: Int
  private let maxCost: Int
  private let sensitive: Bool
  private let now: () -> TimeInterval
  private var entries: [Key: Entry] = [:]
  private var order: [Key] = []
  private var totalCost = 0
  private var timer: DispatchWorkItem?
  private var timerID: UInt64 = 0
  private var generation: UInt64 = 0
  private var suspended = false
  private var observers: [NSObjectProtocol] = []

  init(lifetime: TimeInterval = 600, maxCount: Int, maxCost: Int, sensitive: Bool = true,
       now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
    self.lifetime = lifetime
    self.maxCount = maxCount
    self.maxCost = maxCost
    self.sensitive = sensitive
    self.now = now
    if sensitive {
      let center = NotificationCenter.default
      observers.append(center.addObserver(forName: .galaxySSIRuntimePlaintextWillClear, object: nil, queue: nil) {
        [weak self] _ in self?.setSuspended(true)
      })
      observers.append(center.addObserver(forName: .galaxySSIRuntimePlaintextDidRestore, object: nil, queue: nil) {
        [weak self] _ in self?.setSuspended(false)
      })
      observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) {
        [weak self] _ in self?.clear()
      })
    }
  }

  deinit {
    timer?.cancel()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  var revision: UInt64 {
    lock.lock()
    defer { lock.unlock() }
    return generation
  }

  func value(for key: Key) -> Value? {
    lock.lock()
    defer { lock.unlock() }
    guard !sensitive || !GalaxySSIRuntimePlaintextProtection.isBoundaryActive,
          let entry = entries[key] else { return nil }
    guard entry.deadline > now() else { removeLocked(key); return nil }
    order.removeAll { $0 == key }
    order.append(key)
    return entry.value
  }

  func insert(_ value: Value, for key: Key, cost: Int, revision: UInt64) {
    lock.lock()
    defer { lock.unlock() }
    guard revision == generation, !suspended, !sensitive || !GalaxySSIRuntimePlaintextProtection.isBoundaryActive,
          maxCount > 0, cost >= 0, cost <= maxCost else { return }
    let current = now()
    pruneLocked(now: current)
    guard entries[key] == nil else { return }
    while let oldest = order.first, entries.count >= maxCount || totalCost > maxCost - cost {
      removeLocked(oldest)
    }
    entries[key] = Entry(value: value, deadline: current + lifetime, cost: cost)
    totalCost += cost
    order.append(key)
    if timer == nil { scheduleLocked(now: current) }
  }

  func remove(_ key: Key) {
    lock.lock()
    defer { lock.unlock() }
    removeLocked(key)
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    clearLocked()
  }

  private func setSuspended(_ value: Bool) {
    lock.lock()
    defer { lock.unlock() }
    suspended = value
    clearLocked()
  }

  private func clearLocked() {
    generation &+= 1
    timerID &+= 1
    timer?.cancel()
    timer = nil
    entries.removeAll()
    order.removeAll()
    totalCost = 0
  }

  private func removeLocked(_ key: Key) {
    guard let removed = entries.removeValue(forKey: key) else { return }
    totalCost -= removed.cost
    order.removeAll { $0 == key }
  }

  private func pruneLocked(now: TimeInterval) {
    for key in order where entries[key].map({ $0.deadline <= now }) == true { removeLocked(key) }
  }

  private func scheduleLocked(now: TimeInterval) {
    guard let earliest = entries.values.map(\.deadline).min() else { return }
    timerID &+= 1
    let id = timerID
    let work = DispatchWorkItem { [weak self] in self?.expire(timerID: id) }
    timer = work
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.001, earliest - now), execute: work)
  }

  private func expire(timerID id: UInt64) {
    lock.lock()
    defer { lock.unlock() }
    guard timerID == id else { return }
    timer = nil
    let current = now()
    pruneLocked(now: current)
    scheduleLocked(now: current)
  }
}
