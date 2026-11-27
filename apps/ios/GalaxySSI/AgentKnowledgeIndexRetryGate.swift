import Foundation

// The query path only submits a hint. Repairs run on the utility queue and may
// wait for the writer there, never on the caller's snapshot-admission path.
final class AgentKnowledgeIndexRetryGate {
  private let lock = NSLock()
  private let queue: DispatchQueue
  private var needed = false, queued = false
  private var generation = UUID()
  init(queue: DispatchQueue = DispatchQueue(label: "galaxyssi.knowledge.index-retry", qos: .utility)) {
    self.queue = queue
  }
  func markFailure() {
    lock.lock(); defer { lock.unlock() }
    needed = true; generation = UUID()
  }
  @discardableResult
  func request(_ repair: @escaping () -> Bool) -> Bool {
    lock.lock()
    guard needed, !queued else { lock.unlock(); return false }
    queued = true; let admitted = generation
    lock.unlock()
    queue.async { [self] in
      let success = repair()
      lock.lock(); defer { lock.unlock() }
      if success && generation == admitted { needed = false }
      queued = false
    }
    return true
  }
}
