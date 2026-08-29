import Foundation

enum MqttBrokerAckTimeoutPolicy {
  static let defaultTimeoutSeconds: TimeInterval = 12
  static let attachmentTimeoutSeconds: TimeInterval = 30

  static func timeoutSeconds(wirePayloadBytes: Int) -> TimeInterval {
    wirePayloadBytes >= 96 * 1024 ? attachmentTimeoutSeconds : defaultTimeoutSeconds
  }
}

/// Tracks QoS 1 publishes until the broker confirms them with PUBACK.
final class MqttBrokerAckWatchdog {
  private struct PendingPublish {
    var publishedAt: TimeInterval
    var timeoutSeconds: TimeInterval
  }

  private let defaultTimeoutSeconds: TimeInterval
  private let lock = NSLock()
  private var pendingByPacketId: [UInt16: PendingPublish] = [:]

  init(timeoutSeconds: TimeInterval) {
    precondition(timeoutSeconds > 0)
    defaultTimeoutSeconds = timeoutSeconds
  }

  func onPublished(
    packetId: UInt16,
    now: TimeInterval = ProcessInfo.processInfo.systemUptime,
    timeoutSeconds: TimeInterval? = nil
  ) {
    let timeout = timeoutSeconds ?? defaultTimeoutSeconds
    guard timeout > 0 else { return }
    lock.lock()
    pendingByPacketId[packetId] = pendingByPacketId[packetId] ?? PendingPublish(
      publishedAt: now,
      timeoutSeconds: timeout
    )
    lock.unlock()
  }

  func onAcknowledged(packetId: UInt16) {
    lock.lock()
    pendingByPacketId.removeValue(forKey: packetId)
    lock.unlock()
  }

  func nextCheckDelay(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
    lock.lock()
    defer { lock.unlock() }
    return pendingByPacketId.values.map {
      max(0, $0.timeoutSeconds - max(0, now - $0.publishedAt))
    }.min()
  }

  func oldestPendingAge(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
    lock.lock()
    defer { lock.unlock() }
    guard let oldest = pendingByPacketId.values.map(\.publishedAt).min() else { return nil }
    return max(0, now - oldest)
  }

  func oldestTimedOutPendingAge(
    now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> TimeInterval? {
    lock.lock()
    defer { lock.unlock() }
    return pendingByPacketId.values
      .filter { now - $0.publishedAt >= $0.timeoutSeconds }
      .map { max(0, now - $0.publishedAt) }
      .max()
  }

  func clear() {
    lock.lock()
    pendingByPacketId.removeAll()
    lock.unlock()
  }
}
