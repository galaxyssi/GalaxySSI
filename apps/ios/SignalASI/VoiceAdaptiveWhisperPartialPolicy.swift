import Foundation

struct VoiceWhisperDecodeQueueSnapshot: Codable, Equatable {
  var activeRequestId: String?
  var activeSessionId: String?
  var activeMode: VoiceWhisperExecutionMode?
  var queued: Int
  var queuedPartials: Int
  var dropped: Int64

  init(
    activeRequestId: String? = nil,
    activeSessionId: String? = nil,
    activeMode: VoiceWhisperExecutionMode? = nil,
    queued: Int = 0,
    queuedPartials: Int = 0,
    dropped: Int64 = 0
  ) {
    self.activeRequestId = activeRequestId
    self.activeSessionId = activeSessionId
    self.activeMode = activeMode
    self.queued = max(0, queued)
    self.queuedPartials = max(0, queuedPartials)
    self.dropped = max(0, dropped)
  }
}

struct VoiceAdaptiveWhisperPartialSnapshot: Codable, Equatable {
  var enabled: Bool
  var intervalMillis: Int64
  var windowMillis: Int64
  var backlogStreak: Int
  var recentRealTimeFactor: Double?
}

final class VoiceAdaptiveWhisperPartialPolicy {
  private let certifiedBaseIntervalMillis: Int64
  private let baseWindowMillis: Int64
  private var intervalMillis: Int64
  private var windowMillis: Int64
  private var lastSubmittedAtMillis = Int64.min
  private var backlogStreak = 0
  private var healthyStreak = 0
  private var recentRealTimeFactor: Double?
  private var enabled: Bool
  private let lock = NSLock()

  init(
    profile: VoiceWhisperModelProfile,
    certifiedPartialIntervalMillis: Int64? = nil,
    realtimeCertified: Bool? = nil
  ) {
    let baseInterval: Int64
    switch profile.family {
    case .tiny:
      baseInterval = Self.clamp(profile.defaultPartialIntervalMillis, min: 500, max: 1_000)
    case .base:
      baseInterval = Self.clamp(profile.defaultPartialIntervalMillis, min: 800, max: 1_500)
    default:
      baseInterval = Self.clamp(profile.defaultPartialIntervalMillis, min: 1_500, max: Self.maximumPartialIntervalMillis)
    }

    let baseWindow: Int64
    switch profile.family {
    case .tiny:
      baseWindow = Self.clamp(profile.maxWindowMillis, min: 4_000, max: 8_000)
    case .base:
      baseWindow = Self.clamp(profile.maxWindowMillis, min: 5_000, max: 10_000)
    default:
      baseWindow = Self.clamp(profile.maxWindowMillis, min: 6_000, max: 20_000)
    }

    let certified = certifiedPartialIntervalMillis
      .flatMap { $0 > 0 ? $0 : nil }
      .map { Self.clamp($0, min: Self.minimumPartialIntervalMillis, max: Self.maximumPartialIntervalMillis) }
      ?? baseInterval
    self.certifiedBaseIntervalMillis = certified
    self.baseWindowMillis = baseWindow
    self.intervalMillis = certified
    self.windowMillis = baseWindow
    self.enabled = realtimeCertified ?? (profile.recommendedMode == .realtimePartial)
  }

  func shouldSubmit(
    nowMillis: Int64,
    capturedAudioMillis: Int64,
    queue: VoiceWhisperDecodeQueueSnapshot = VoiceWhisperDecodeQueueSnapshot()
  ) -> Bool {
    locked {
      guard enabled, capturedAudioMillis >= Self.minimumPartialAudioMillis else {
        return false
      }
      let backlog = partialBacklog(queue)
      if backlog >= 2 {
        backlogStreak += 1
        healthyStreak = 0
        intervalMillis = min(intervalMillis * 2, Self.maximumPartialIntervalMillis)
        return false
      }
      if lastSubmittedAtMillis != Int64.min,
         nowMillis - lastSubmittedAtMillis < intervalMillis {
        return false
      }
      lastSubmittedAtMillis = nowMillis
      return true
    }
  }

  func onDecodeCompleted(
    realTimeFactor: Double,
    queue: VoiceWhisperDecodeQueueSnapshot = VoiceWhisperDecodeQueueSnapshot()
  ) {
    locked {
      recentRealTimeFactor = realTimeFactor.isFinite && realTimeFactor >= 0 ? realTimeFactor : nil
      let backlog = partialBacklog(queue)
      if backlog > 0 {
        backlogStreak += 1
        healthyStreak = 0
      } else {
        backlogStreak = 0
        healthyStreak += 1
      }

      switch realTimeFactor {
      case let value where value > 1.50:
        enabled = false
      case let value where value > 1.20:
        intervalMillis = min(certifiedBaseIntervalMillis * 3, Self.maximumPartialIntervalMillis)
      case let value where value > 0.80:
        intervalMillis = min(certifiedBaseIntervalMillis * 3 / 2, Self.maximumPartialIntervalMillis)
      case let value where value > 0.50:
        intervalMillis = certifiedBaseIntervalMillis
      default:
        intervalMillis = max(certifiedBaseIntervalMillis * 4 / 5, Self.minimumPartialIntervalMillis)
      }

      if realTimeFactor > 0.80 {
        windowMillis = max(baseWindowMillis * 3 / 4, Self.minimumPartialWindowMillis)
      } else if healthyStreak >= 2 {
        windowMillis = baseWindowMillis
      }
    }
  }

  func snapshot() -> VoiceAdaptiveWhisperPartialSnapshot {
    locked {
      VoiceAdaptiveWhisperPartialSnapshot(
        enabled: enabled,
        intervalMillis: intervalMillis,
        windowMillis: windowMillis,
        backlogStreak: backlogStreak,
        recentRealTimeFactor: recentRealTimeFactor
      )
    }
  }

  private func partialBacklog(_ queue: VoiceWhisperDecodeQueueSnapshot) -> Int {
    queue.queuedPartials + (queue.activeMode == .realtimePartial ? 1 : 0)
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  private static func clamp(_ value: Int64, min minimum: Int64, max maximum: Int64) -> Int64 {
    Swift.max(minimum, Swift.min(value, maximum))
  }

  private static let minimumPartialAudioMillis: Int64 = 800
  private static let minimumPartialIntervalMillis: Int64 = 400
  private static let maximumPartialIntervalMillis: Int64 = 6_000
  private static let minimumPartialWindowMillis: Int64 = 3_000
}
