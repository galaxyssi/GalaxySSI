import AVFoundation
import Combine
import Foundation

/// Foreground-only, echo-processed speech detection. This path does not save PCM,
/// start ASR, or create a voice interaction trace.
@MainActor
final class VoicePassiveReplyCapture: ObservableObject {
  @Published private(set) var isListening = false
  private var engine: AVAudioEngine?
  private var token: UUID?

  @discardableResult
  func start(onSpeech: @escaping () -> Void) -> Bool {
    if isListening { return true }
    let session = AVAudioSession.sharedInstance()
    guard session.recordPermission == .granted, session.isInputAvailable else { return false }
    let engine = AVAudioEngine()
    let id = UUID()
    token = id
    do {
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)
      let input = engine.inputNode
      try input.setVoiceProcessingEnabled(true)
      guard input.isVoiceProcessingEnabled else { throw CaptureFailure.unprotected }
      input.isVoiceProcessingAGCEnabled = false
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureFailure.unprotected }
      let detector = VoicePassiveSpeechDetector(startedAt: ProcessInfo.processInfo.systemUptime)
      input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 50), format: format) { [weak self] buffer, _ in
        guard detector.accept(VoicePcmTapPipeline.int16Samples(from: buffer),
                              now: ProcessInfo.processInfo.systemUptime) else { return }
        Task { @MainActor [weak self] in
          guard let self, self.token == id, self.isListening, self.engine?.isRunning == true else { return }
          onSpeech()
        }
      }
      self.engine = engine
      engine.prepare()
      try engine.start()
      isListening = true
      return true
    } catch {
      stop()
      return false
    }
  }

  func stop(deactivateSession: Bool = true) {
    guard token != nil else { return }
    token = nil
    isListening = false
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      self.engine = nil
    }
    if deactivateSession {
      try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
  }

  private enum CaptureFailure: Error { case unprotected }
}

final class VoicePassiveSpeechDetector {
  private let vad = AdaptiveSpeechVad(attackFrames: 4, minimumSpeechDb: -36, minimumSnrDb: 12)
  private let armAt: TimeInterval
  private var delivered = false
  private var sequence: Int64 = 0

  init(startedAt: TimeInterval) { armAt = startedAt + 0.35 }

  func accept(_ samples: [Int16], now: TimeInterval) -> Bool {
    guard !delivered, now >= armAt else { return false }
    let frame = AudioFrame(sequence: sequence, captureTimeNanos: 0, samples: samples)
    sequence += 1
    delivered = vad.accept(frame).speechStarted
    return delivered
  }
}
