import Foundation

final class VoiceWhisperThermalController {
  private let elapsedMillis: () -> Int64
  private let lock = NSLock()
  private var heldStatus = 0
  private var releaseAtElapsedMillis: Int64 = 0

  init(elapsedMillis: @escaping () -> Int64 = { Int64(ProcessInfo.processInfo.systemUptime * 1_000) }) {
    self.elapsedMillis = elapsedMillis
  }

  func effectiveStatus(observedStatus: Int) -> Int {
    locked {
      let observed = min(max(observedStatus, Self.thermalNone), Self.thermalShutdown)
      let now = elapsedMillis()
      if observed >= Self.thermalModerate {
        if observed >= heldStatus || now >= releaseAtElapsedMillis {
          heldStatus = observed
          releaseAtElapsedMillis = now + Self.cooldownMillis(for: observed)
        }
        return max(observed, heldStatus)
      }
      if now < releaseAtElapsedMillis {
        return heldStatus
      }
      heldStatus = Self.thermalNone
      releaseAtElapsedMillis = 0
      return observed
    }
  }

  func remainingCooldownMillis() -> Int64 {
    locked {
      max(releaseAtElapsedMillis - elapsedMillis(), 0)
    }
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static func cooldownMillis(for status: Int) -> Int64 {
    if status >= thermalCritical {
      return 180_000
    }
    if status >= thermalSevere {
      return 90_000
    }
    return 30_000
  }

  private static let thermalNone = 0
  private static let thermalModerate = 2
  private static let thermalSevere = 3
  private static let thermalCritical = 4
  private static let thermalShutdown = 4
}
