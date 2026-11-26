import Foundation

// One dispatch owns this monotonic, lock-protected observation across stream/tool worker queues.
final class AgentConnectorModelFailureEvidence: @unchecked Sendable {
  private enum Backend: Equatable { case phone, cloud }
  private let owner: String
  private let lock = NSLock()
  private var backend: Backend?
  private var cloudObserved = false
  private var effectsPossible = false
  private var streamCancelled = false

  init(owner: String) { self.owner = owner }

  func beginPhoneInference() { begin(.phone) }
  func beginCloudInference() { begin(.cloud) }

  private func begin(_ value: Backend) {
    lock.lock()
    defer { lock.unlock() }
    guard backend == nil, !owner.isBlank, owner.count <= 200,
          owner == owner.trimmingCharacters(in: .whitespacesAndNewlines) else { effectsPossible = true; return }
    backend = value
  }

  func installCloudObserver(requestId: String) {
    lock.lock()
    defer { lock.unlock() }
    guard requestId == owner, backend == .cloud else { effectsPossible = true; return }
    cloudObserved = true
  }

  func markPossibleEffects() {
    lock.lock()
    effectsPossible = true
    lock.unlock()
  }

  func recordStreamFailure(code: String, requestId: String) {
    lock.lock()
    defer { lock.unlock() }
    guard requestId == owner, backend == .cloud else { effectsPossible = true; return }
    if code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CANCELLED" { streamCancelled = true }
  }

  func permitsKnownFailure(requestId: String, error: Error, taskCancelled: Bool) -> Bool {
    let value = error as NSError
    guard !taskCancelled, !(error is CancellationError),
          !(value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled) else { return false }
    lock.lock()
    defer { lock.unlock() }
    guard requestId == owner, !effectsPossible, !streamCancelled else { return false }
    switch backend {
    case .some(.phone): return true
    case .some(.cloud): return cloudObserved
    case .none: return false
    }
  }
}
