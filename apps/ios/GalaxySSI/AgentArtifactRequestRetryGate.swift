import Foundation

struct AgentArtifactRequestRetryGate {
  private var requestedAtMillis: [String: Int64] = [:]
  private let nowMillis: () -> Int64
  private let retryAfterMillis: Int64

  init(
    retryAfterMillis: Int64 = 30_000,
    nowMillis: @escaping () -> Int64 = {
      Int64((ProcessInfo.processInfo.systemUptime * 1_000).rounded())
    }
  ) {
    self.retryAfterMillis = max(retryAfterMillis, 1)
    self.nowMillis = nowMillis
  }

  mutating func add(_ key: String) -> Bool {
    guard !key.isEmpty else { return false }
    let now = nowMillis()
    if let previous = requestedAtMillis[key], now >= previous, now - previous < retryAfterMillis {
      return false
    }
    requestedAtMillis[key] = now
    return true
  }

  @discardableResult
  mutating func remove(_ key: String) -> Bool {
    requestedAtMillis.removeValue(forKey: key) != nil
  }
}
