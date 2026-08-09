import Foundation

/// Tracks QoS 1 publishes until the broker confirms them with PUBACK.
final class MqttBrokerAckWatchdog {
  private let timeoutSeconds: TimeInterval
  private let lock = NSLock()
  private var publishedAtByPacketId: [UInt16: TimeInterval] = [:]

  init(timeoutSeconds: TimeInterval) {
    precondition(timeoutSeconds > 0)
    self.timeoutSeconds = timeoutSeconds
  }

  func onPublished(packetId: UInt16, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    lock.lock()
    publishedAtByPacketId[packetId] = now
    lock.unlock()
  }

  func onAcknowledged(packetId: UInt16) {
    lock.lock()
    publishedAtByPacketId.removeValue(forKey: packetId)
    lock.unlock()
  }

  func nextCheckDelay(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
    lock.lock()
    defer { lock.unlock() }
    guard let oldest = publishedAtByPacketId.values.min() else { return nil }
    return max(0, timeoutSeconds - max(0, now - oldest))
  }

  func oldestPendingAge(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval? {
    lock.lock()
    defer { lock.unlock() }
    guard let oldest = publishedAtByPacketId.values.min() else { return nil }
    return max(0, now - oldest)
  }

  func clear() {
    lock.lock()
    publishedAtByPacketId.removeAll()
    lock.unlock()
  }
}
