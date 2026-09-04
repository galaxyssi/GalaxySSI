import Foundation

final class GlobalAgentRecoverySignalGate {
  static let defaultCooldownMillis: Int64 = 2_000

  private let cooldownMillis: Int64
  private let lock = NSLock()
  private var pending = false
  private var lastAcceptedAtMillis: Int64 = 0

  init(cooldownMillis: Int64 = GlobalAgentRecoverySignalGate.defaultCooldownMillis) {
    self.cooldownMillis = max(cooldownMillis, 0)
  }

  func tryAcquire(nowMillis: Int64 = GlobalRealtimeClock.nowMillis()) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if pending {
      return false
    }
    if lastAcceptedAtMillis > 0 && nowMillis - lastAcceptedAtMillis < cooldownMillis {
      return false
    }
    pending = true
    lastAcceptedAtMillis = nowMillis
    return true
  }

  func release() {
    lock.lock()
    defer { lock.unlock() }
    pending = false
  }
}

enum GlobalAgentServiceContinuityPolicy {
  static let serviceRecoveryDelayMillis: Int64 = 60_000

  static func recoveryWakeAt(
    nowMillis: Int64,
    scheduledWorkWakeAtMillis: Int64
  ) -> Int64 {
    let serviceRecovery = nowMillis + serviceRecoveryDelayMillis
    if scheduledWorkWakeAtMillis > nowMillis {
      return min(scheduledWorkWakeAtMillis, serviceRecovery)
    }
    return serviceRecovery
  }
}
