import Foundation

struct AgentBrowserViewLease: Codable, Equatable, Sendable {
  enum Failure: Error, Equatable { case invalidScope, busy, viewLost }
  let scope: String
  let id: UUID
  let processID: String
  private static let lock = NSLock()
  private static var active: [UUID: AgentBrowserViewLease] = [:]

  static func claim(scope: String, id: UUID, existing: Self?, processID: String,
    persist: (Self) throws -> Void) throws -> Self {
    lock.lock(); defer { lock.unlock() }
    guard scope.count == 64, scope.allSatisfy({ $0.isHexDigit }), !processID.isBlank else { throw Failure.invalidScope }
    if let existing {
      guard existing.scope == scope else { throw Failure.invalidScope }
      guard existing.processID == processID, active[existing.id] == existing else { throw Failure.viewLost }
      guard existing.id == id else { throw Failure.busy }
      return existing
    }
    guard active[id] == nil, active.count < 200 else { throw Failure.busy }
    let lease = Self(scope: scope, id: id, processID: processID)
    try persist(lease)
    active[id] = lease
    return lease
  }

  static func isLive(_ lease: Self, scope: String, processID: String) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return lease.scope == scope && lease.processID == processID && active[lease.id] == lease
  }

  static func release(_ lease: Self) {
    lock.lock(); defer { lock.unlock() }
    if active[lease.id] == lease { active.removeValue(forKey: lease.id) }
  }
}
