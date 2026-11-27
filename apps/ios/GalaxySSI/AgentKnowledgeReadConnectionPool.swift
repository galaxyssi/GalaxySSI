import Foundation

// Reservations, active leases and handles being closed all count toward capacity.
// No factory, validation or resource disposal runs under the condition lock.
final class AgentKnowledgeReadConnectionPool<Key: Hashable, Resource: AnyObject> {
  enum Failure: Error { case closed, invalidated, leased }
  struct Stats { var opened: Int64; var reused: Int64; var evicted: Int64; var active: Int; var idle: Int; var peak: Int }
  private final class Entry {
    var key: Key
    var resource: Resource?
    var busy = true
    var discard = false
    init(_ key: Key) { self.key = key }
  }
  final class Lease {
    private let lock = NSRecursiveLock()
    private let resource: Resource
    private var release: ((Bool) -> Void)?
    private var failed = false
    fileprivate init(_ resource: Resource, release: @escaping (Bool) -> Void) { self.resource = resource; self.release = release }
    func access<T>(_ action: (Resource) throws -> T) throws -> T {
      lock.lock(); defer { lock.unlock() }
      guard release != nil else { throw Failure.closed }
      do { return try action(resource) }
      catch { failed = true; throw error }
    }
    func invalidate() { lock.lock(); failed = true; lock.unlock() }
    func end() {
      lock.lock()
      let action = release, discard = failed
      release = nil
      lock.unlock()
      action?(discard)
    }
    deinit { end() }
  }

  private let condition = NSCondition()
  private let capacity: Int
  private let dispose: (Resource) -> Void
  private var entries: [Entry] = []
  private var closed = false
  private var opened: Int64 = 0, reused: Int64 = 0, evicted: Int64 = 0
  private var peak = 0
  init(capacity: Int, dispose: @escaping (Resource) -> Void) {
    precondition((1...64).contains(capacity))
    self.capacity = capacity; self.dispose = dispose
  }
  deinit { close() }
  var stats: Stats {
    condition.lock(); defer { condition.unlock() }
    return Stats(opened: opened, reused: reused, evicted: evicted,
      active: entries.filter { $0.busy }.count, idle: entries.filter { !$0.busy }.count, peak: peak)
  }

  func borrow(_ key: Key, checkActive: () throws -> Void = {},
              valid: (Resource) throws -> Bool = { _ in true }, create: () throws -> Resource) throws -> Lease {
    let entry: Entry, previous: Resource?, sameKey: Bool
    while true {
      try Task.checkCancellation(); try checkActive()
      condition.lock()
      if closed { condition.unlock(); throw Failure.closed }
      let selected: Entry?
      if let hit = entries.first(where: { !$0.busy && $0.key == key }) { selected = hit }
      else if entries.count < capacity {
        let reserved = Entry(key); entries.append(reserved); peak = max(peak, entries.count); selected = reserved
      } else { selected = entries.first(where: { !$0.busy }) }
      guard let selected else {
        _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        condition.unlock(); continue
      }
      entry = selected; previous = selected.resource; sameKey = selected.key == key
      selected.key = key; selected.resource = nil; selected.busy = true; selected.discard = false
      condition.unlock(); break
    }
    var resource = previous
    do {
      if let current = resource {
        if sameKey, try valid(current) {
          condition.lock(); reused += 1; condition.unlock()
        } else {
          resource = nil; dispose(current)
          condition.lock(); evicted += 1; condition.unlock()
        }
      }
      if resource == nil {
        resource = try create()
        condition.lock(); opened += 1; condition.unlock()
      }
      guard let ready = resource else { throw Failure.invalidated }
      try Task.checkCancellation(); try checkActive()
      condition.lock()
      if closed || entry.discard { condition.unlock(); throw Failure.invalidated }
      entry.resource = ready
      condition.unlock()
      return Lease(ready) { self.release(entry, failed: $0) }
    } catch {
      if let resource { dispose(resource) }
      remove(entry)
      throw error
    }
  }

  func invalidate(where matches: (Key) -> Bool, requireIdle: Bool = false) throws {
    condition.lock()
    let selected = entries.filter { matches($0.key) }
    if requireIdle && selected.contains(where: { $0.busy }) { condition.unlock(); throw Failure.leased }
    var disposing: [(Entry, Resource?)] = []
    for entry in selected {
      entry.discard = true
      if !entry.busy {
        entry.busy = true; disposing.append((entry, entry.resource)); entry.resource = nil
      }
    }
    condition.unlock()
    for (entry, resource) in disposing {
      if let resource { dispose(resource) }
      remove(entry)
    }
  }
  func close() {
    condition.lock(); closed = true; condition.broadcast(); condition.unlock()
    try? invalidate(where: { _ in true })
  }
  private func release(_ entry: Entry, failed: Bool) {
    condition.lock()
    if !failed && !closed && !entry.discard {
      entry.busy = false
      entries.removeAll { $0 === entry }; entries.append(entry)
      condition.broadcast(); condition.unlock(); return
    }
    let resource = entry.resource; entry.resource = nil
    condition.unlock()
    if let resource { dispose(resource) }
    remove(entry)
  }
  private func remove(_ entry: Entry) {
    condition.lock(); entries.removeAll { $0 === entry }; condition.broadcast(); condition.unlock()
  }
}
