import Foundation
import UIKit

/// Keeps the two large native runtimes from holding their model allocations at once.
final class LocalModelWhisperResourceArbiter {
  static let shared = LocalModelWhisperResourceArbiter()

  private let lock = NSLock()
  private let pressureQueue = DispatchQueue(
    label: "com.galaxyssi.ios.native-runtime-pressure",
    qos: .utility
  )
  private weak var localModelRuntime: LocalModelInferenceRuntime?
  private weak var whisperRuntime: DefaultVoiceLocalWhisperRuntime?
  private var asrReservesQnn: (() -> Bool)?
  private var pressureObserverTokens: [NSObjectProtocol] = []

  private init() {
    let center = NotificationCenter.default
    pressureObserverTokens = [
      center.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.scheduleResourcePressureRelease()
      },
      center.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in
        self?.scheduleThermalPressureRelease()
      }
    ]
  }

  deinit {
    pressureObserverTokens.forEach(NotificationCenter.default.removeObserver)
  }

  func register(localModelRuntime: LocalModelInferenceRuntime) {
    lock.lock()
    self.localModelRuntime = localModelRuntime
    lock.unlock()
  }

  func register(whisperRuntime: DefaultVoiceLocalWhisperRuntime) {
    lock.lock()
    if self.whisperRuntime == nil {
      self.whisperRuntime = whisperRuntime
      self.asrReservesQnn = { [weak whisperRuntime] in
        whisperRuntime?.reservesQnn() ?? false
      }
    }
    lock.unlock()
  }

  /// Whisper keeps the native accelerator reserved while it is hot or preparing.
  /// Local model routing uses this non-blocking snapshot to yield instead of evicting ASR.
  func asrHasPriority() -> Bool {
    lock.lock()
    let reservesQnn = asrReservesQnn
    lock.unlock()
    return reservesQnn?() ?? false
  }

  func releaseLocalModelForWhisper() {
    lock.lock()
    let runtime = localModelRuntime
    lock.unlock()
    runtime?.releaseForResourcePressure()
  }

  private func scheduleResourcePressureRelease() {
    pressureQueue.async { [weak self] in
      self?.releaseBothForResourcePressure()
    }
  }

  private func scheduleThermalPressureRelease() {
    guard [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) else {
      return
    }
    scheduleResourcePressureRelease()
  }

  private func releaseBothForResourcePressure() {
    lock.lock()
    let localModelRuntime = self.localModelRuntime
    let whisperRuntime = self.whisperRuntime
    lock.unlock()
    localModelRuntime?.releaseForResourcePressure()
    whisperRuntime?.releaseForResourcePressure()
  }
}
