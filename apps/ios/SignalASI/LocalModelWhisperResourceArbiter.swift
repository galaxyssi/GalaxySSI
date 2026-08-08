import Foundation

/// Keeps the two large native runtimes from holding their model allocations at once.
final class LocalModelWhisperResourceArbiter {
  static let shared = LocalModelWhisperResourceArbiter()

  private let lock = NSLock()
  private weak var localModelRuntime: LocalModelInferenceRuntime?
  private weak var whisperRuntime: DefaultVoiceLocalWhisperRuntime?

  private init() {}

  func register(localModelRuntime: LocalModelInferenceRuntime) {
    lock.lock()
    self.localModelRuntime = localModelRuntime
    lock.unlock()
  }

  func register(whisperRuntime: DefaultVoiceLocalWhisperRuntime) {
    lock.lock()
    if self.whisperRuntime == nil {
      self.whisperRuntime = whisperRuntime
    }
    lock.unlock()
  }

  func releaseWhisperForLocalModel() {
    lock.lock()
    let runtime = whisperRuntime
    lock.unlock()
    runtime?.releaseForResourcePressure()
  }

  func releaseLocalModelForWhisper() {
    lock.lock()
    let runtime = localModelRuntime
    lock.unlock()
    runtime?.releaseForResourcePressure()
  }
}
