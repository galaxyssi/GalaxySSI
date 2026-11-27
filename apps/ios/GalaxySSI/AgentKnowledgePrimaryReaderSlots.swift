import Dispatch
import Foundation

final class AgentKnowledgePrimaryReaderSlots {
  static let shared = AgentKnowledgePrimaryReaderSlots(capacity: 8)
  private let semaphore: DispatchSemaphore

  final class Lease {
    private let lock = NSLock()
    private var release: (() -> Void)?

    fileprivate init(release: @escaping () -> Void) { self.release = release }
    deinit { end() }

    func end() {
      lock.lock()
      let action = release
      release = nil
      lock.unlock()
      action?()
    }
  }

  init(capacity: Int) {
    precondition((1...8).contains(capacity))
    semaphore = DispatchSemaphore(value: capacity)
  }

  // Timed waits let a task's cancellation/deadline policy run even when every reader is busy.
  func acquire(checkActive: () throws -> Void = {}) throws -> Lease {
    while true {
      try Task.checkCancellation()
      try checkActive()
      guard semaphore.wait(timeout: .now() + .milliseconds(50)) == .success else { continue }
      do {
        try Task.checkCancellation()
        try checkActive()
        return Lease { _ = self.semaphore.signal() }
      } catch {
        semaphore.signal()
        throw error
      }
    }
  }
}
