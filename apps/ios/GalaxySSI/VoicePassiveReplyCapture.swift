import AVFoundation
import Combine
import Foundation
import UIKit
import OSLog

struct VoicePassiveCaptureLease {
  private(set) var owner: UUID?
  private(set) var capture: UUID?
  private var startedAt: TimeInterval?

  mutating func begin() -> UUID {
    let id = UUID()
    owner = id
    capture = nil
    startedAt = nil
    return id
  }

  mutating func renew(owner id: UUID, at now: TimeInterval) -> UUID? {
    guard owner == id else { return nil }
    let captureID = UUID()
    capture = captureID
    startedAt = now
    return captureID
  }

  func accepts(owner id: UUID, capture captureID: UUID) -> Bool { owner == id && capture == captureID }

  func needsRenewal(at now: TimeInterval, healthy: Bool) -> Bool {
    guard owner != nil else { return false }
    guard healthy, let startedAt else { return true }
    return now >= startedAt && now - startedAt >= 50
  }

  mutating func stop() { owner = nil; capture = nil; startedAt = nil }
}

enum VoiceInputCaptionPolicy {
  static func text(_ state: VoiceInteractionState, capturing: Bool, submittedSession: String) -> String {
    guard capturing, !state.sessionId.isEmpty, state.sessionId != submittedSession,
          [.preparing, .listening, .endpointing, .finalizingASR].contains(state.phase) else { return "" }
    return (state.correctedText ?? "").ifBlank(state.finalText ?? "")
      .ifBlank(state.stableText).ifBlank(state.partialText)
  }
}

/// Foreground-only, echo-processed speech detection. This path does not save PCM,
/// start ASR, or create a voice interaction trace.
@MainActor
final class VoicePassiveReplyCapture: ObservableObject {
  @Published private(set) var isListening = false
  private var engine: AVAudioEngine?
  private var lease = VoicePassiveCaptureLease()
  private var maintenance: Task<Void, Never>?
  let echoReference = VoicePlaybackEchoReference()
  private let logger = Logger(subsystem: "com.galaxyssi.ios", category: "passive-voice-capture")
  var isArmed: Bool { lease.owner != nil }

  @discardableResult
  func start(onSpeech: @escaping () -> Void) -> Bool {
    if isArmed { return isListening }
    let owner = lease.begin()
    guard launch(owner: owner, onSpeech: onSpeech) else { stop(); return false }
    maintenance = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
        guard let self, self.lease.owner == owner else { return }
        guard UIApplication.shared.applicationState == .active else { self.stop(); return }
        let session = AVAudioSession.sharedInstance()
        let healthy = self.engine?.isRunning == true && session.category == .playAndRecord &&
          session.mode == .voiceChat && self.engine?.inputNode.isVoiceProcessingEnabled == true
        if self.lease.needsRenewal(at: ProcessInfo.processInfo.systemUptime, healthy: healthy) {
          if self.launch(owner: owner, onSpeech: onSpeech) {
            self.logger.info("Passive voice capture renewed")
          }
        }
      }
    }
    return true
  }

  private func launch(owner: UUID, onSpeech: @escaping () -> Void) -> Bool {
    guard let captureID = lease.renew(owner: owner, at: ProcessInfo.processInfo.systemUptime) else { return false }
    releaseEngine()
    isListening = false
    let session = AVAudioSession.sharedInstance()
    guard session.recordPermission == .granted else { return false }
    let engine = AVAudioEngine()
    do {
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setActive(true)
      guard session.isInputAvailable else { throw CaptureFailure.unprotected }
      let input = engine.inputNode
      try input.setVoiceProcessingEnabled(true)
      guard input.isVoiceProcessingEnabled else { throw CaptureFailure.unprotected }
      input.isVoiceProcessingAGCEnabled = false
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureFailure.unprotected }
      let detector = VoicePassiveSpeechDetector(startedAt: ProcessInfo.processInfo.systemUptime)
      let reference = echoReference
      let logger = self.logger
      input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate / 50), format: format) { [weak self] buffer, timestamp in
        let samples = VoicePcmTapPipeline.int16Samples(from: buffer)
        let now = ProcessInfo.processInfo.systemUptime
        detector.observeCapturePosition(timestamp.isSampleTimeValid ? timestamp.sampleTime : nil, length: buffer.frameLength)
        if reference.matches(samples, rate: buffer.format.sampleRate, endingAt: now) {
          detector.rejectEcho()
          logger.debug("Passive voice capture rejected playback echo")
          return
        }
        guard detector.accept(samples, now: now) else { return }
        Task { @MainActor [weak self] in
          guard let self, self.lease.accepts(owner: owner, capture: captureID),
                self.isListening, self.engine?.isRunning == true else { return }
          onSpeech()
        }
      }
      self.engine = engine
      engine.prepare()
      try engine.start()
      isListening = true
      return true
    } catch {
      releaseEngine()
      return false
    }
  }

  func stop(deactivateSession: Bool = true) {
    guard isArmed else { return }
    lease.stop()
    maintenance?.cancel()
    maintenance = nil
    isListening = false
    releaseEngine()
    if deactivateSession {
      try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
  }

  private func releaseEngine() {
    if let engine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      self.engine = nil
    }
  }

  private enum CaptureFailure: Error { case unprotected }
}

final class VoicePassiveSpeechDetector {
  private let vad = AdaptiveSpeechVad(attackFrames: 4, minimumSpeechDb: -36, minimumSnrDb: 12)
  private let armAt: TimeInterval
  private var delivered = false
  private var sequence: Int64 = 0
  private var nextCapturePosition: Int64?

  init(startedAt: TimeInterval) { armAt = startedAt + 0.35 }

  func rejectEcho() { vad.resetAttack() }

  func observeCapturePosition(_ position: Int64?, length: UInt32) {
    if let expected = nextCapturePosition, expected != position { vad.resetAttack() }
    nextCapturePosition = position.map { $0 + Int64(length) }
  }

  func accept(_ samples: [Int16], now: TimeInterval) -> Bool {
    guard !delivered, now >= armAt else { return false }
    let frame = AudioFrame(sequence: sequence, captureTimeNanos: 0, samples: samples)
    sequence += 1
    delivered = vad.accept(frame).speechStarted
    return delivered
  }
}
