import Foundation

final class AgentPhoneCapabilityStatusSnapshotProvider {
  static let defaultTtlMillis: Int64 = 5_000

  private let source: () -> [AgentPhoneCapabilityStatus]
  private let ttlMillis: Int64
  private let nowMillis: () -> Int64
  private let lock = NSLock()
  private var snapshot: Snapshot?

  init(
    source: @escaping () -> [AgentPhoneCapabilityStatus],
    ttlMillis: Int64 = AgentPhoneCapabilityStatusSnapshotProvider.defaultTtlMillis,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.source = source
    self.ttlMillis = max(0, ttlMillis)
    self.nowMillis = nowMillis
  }

  func current() -> [AgentPhoneCapabilityStatus] {
    let now = max(0, nowMillis())
    lock.lock()
    defer { lock.unlock() }
    if let snapshot,
       now >= snapshot.createdAtMillis,
       now - snapshot.createdAtMillis <= ttlMillis {
      return snapshot.statuses
    }
    let statuses = source()
    snapshot = Snapshot(createdAtMillis: now, statuses: statuses)
    return statuses
  }

  private struct Snapshot {
    var createdAtMillis: Int64
    var statuses: [AgentPhoneCapabilityStatus]
  }
}
