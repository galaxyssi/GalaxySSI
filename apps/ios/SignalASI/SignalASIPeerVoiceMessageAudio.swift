import AVFoundation
import Foundation
import SwiftUI
import UIKit

enum SignalASIPeerVoiceMessageAudio {
  static let sampleRateHz = 48_000
  static let channelCount = 2
  static let aacBitRateBps = 128_000
  static let maximumDuration: TimeInterval = 120

  static let recorderSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: sampleRateHz,
    AVNumberOfChannelsKey: channelCount,
    AVEncoderBitRateKey: aacBitRateBps,
    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
  ]

  static func shouldUseDedicatedCapture(purpose: String, isPersonContact: Bool) -> Bool {
    purpose == "chat_message" && isPersonContact
  }

  static func gentleGainDecibels(centerFrequencyHz: Float) -> Float {
    switch centerFrequencyHz {
    case ..<120: return -1.0
    case ..<700: return 1.2
    case ..<4_000: return 0.4
    case ..<8_000: return -0.6
    default: return -1.2
    }
  }
}

struct SignalASIPeerVoiceRecording: Equatable {
  var data: Data
  var durationMillis: Int64
  var fileURL: URL
}

@MainActor
final class SignalASIPeerVoiceMessageRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
  @Published private(set) var isPending = false
  @Published private(set) var isRecording = false
  @Published private(set) var cancelPending = false
  @Published private(set) var elapsedLabel = "00:00"
  @Published private(set) var waveformPhase = 0.0
  @Published private(set) var waveformAmplitude = 0.0
  @Published private(set) var statusMessage = ""

  private var recorder: AVAudioRecorder?
  private var holdTask: Task<Void, Never>?
  private var timer: Timer?
  private var startedAt: Date?
  private var touchActive = false
  private var outputURL: URL?
  private var messages = SignalASIAgentHoldToTalkMessages.default
  private var onFinish: ((SignalASIPeerVoiceRecording) -> Void)?
  private var onCancel: (() -> Void)?

  private static let holdStartDelayNs: UInt64 = 280_000_000
  private static let cancelThreshold: CGFloat = 56
  private static let minimumSendDuration: TimeInterval = 0.8

  func dragChanged(
    translation: CGSize,
    messages: SignalASIAgentHoldToTalkMessages,
    onFinish: @escaping (SignalASIPeerVoiceRecording) -> Void,
    onCancel: @escaping () -> Void
  ) {
    if !touchActive {
      touchActive = true
      beginPending(messages: messages, onFinish: onFinish, onCancel: onCancel)
    }
    updateCancelState(translation: translation)
  }

  func dragEnded(translation: CGSize) {
    let shouldCancel = cancelPending || translation.height <= -Self.cancelThreshold
    touchActive = false
    holdTask?.cancel()
    holdTask = nil
    guard isRecording else {
      cancelFromView()
      return
    }
    let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
    if shouldCancel {
      finish(send: false, status: messages.cancelled)
    } else if elapsed < Self.minimumSendDuration {
      finish(send: false, status: messages.tooShort)
    } else {
      finish(send: true, status: "")
    }
  }

  func cancelFromView() {
    touchActive = false
    holdTask?.cancel()
    holdTask = nil
    if isPending || isRecording {
      finish(send: false, status: "")
    } else {
      reset()
    }
  }

  private func beginPending(
    messages: SignalASIAgentHoldToTalkMessages,
    onFinish: @escaping (SignalASIPeerVoiceRecording) -> Void,
    onCancel: @escaping () -> Void
  ) {
    isPending = true
    isRecording = false
    cancelPending = false
    statusMessage = ""
    elapsedLabel = "00:00"
    waveformPhase = 0
    waveformAmplitude = 0
    self.messages = messages
    self.onFinish = onFinish
    self.onCancel = onCancel
    holdTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: Self.holdStartDelayNs)
      guard !Task.isCancelled else { return }
      await self?.requestPermissionAndStart()
    }
  }

  private func requestPermissionAndStart() async {
    let allowed = await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
    guard isPending else { return }
    guard allowed else {
      fail(messages.permissionDenied)
      return
    }
    do {
      let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("peer-voice-recordings", isDirectory: true)
        ?? FileManager.default.temporaryDirectory.appendingPathComponent("peer-voice-recordings", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appendingPathComponent("voice-\(UUID().uuidString.lowercased()).m4a")
      outputURL = url
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
      try session.setPreferredSampleRate(Double(SignalASIPeerVoiceMessageAudio.sampleRateHz))
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      let recorder = try AVAudioRecorder(
        url: url,
        settings: SignalASIPeerVoiceMessageAudio.recorderSettings
      )
      recorder.delegate = self
      recorder.isMeteringEnabled = true
      guard recorder.prepareToRecord(),
            recorder.record(forDuration: SignalASIPeerVoiceMessageAudio.maximumDuration) else {
        throw SignalASIError.transportUnavailable
      }
      self.recorder = recorder
      startedAt = Date()
      isPending = false
      isRecording = true
      startTimer()
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    } catch {
      fail(error.localizedDescription.ifBlank(messages.speechUnavailable))
    }
  }

  private func updateCancelState(translation: CGSize) {
    guard isRecording else { return }
    let next = translation.height <= -Self.cancelThreshold
    guard next != cancelPending else { return }
    cancelPending = next
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
  }

  private func finish(send: Bool, status: String) {
    let durationMillis = Int64(((startedAt.map { Date().timeIntervalSince($0) } ?? 0) * 1_000).rounded())
    let url = outputURL
    let completion = onFinish
    recorder?.stop()
    releaseRecorder()
    if send,
       let url,
       let data = try? Data(contentsOf: url),
       !data.isEmpty {
      completion?(SignalASIPeerVoiceRecording(
        data: data,
        durationMillis: max(durationMillis, 1),
        fileURL: url
      ))
      reset(keepFile: true)
    } else {
      if let url { try? FileManager.default.removeItem(at: url) }
      onCancel?()
      statusMessage = status
      reset(keepStatus: true)
    }
  }

  private func fail(_ message: String) {
    if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    releaseRecorder()
    onCancel?()
    statusMessage = message
    reset(keepStatus: true)
  }

  private func releaseRecorder() {
    recorder?.stop()
    recorder?.delegate = nil
    recorder = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func startTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
  }

  private func tick() {
    guard let recorder, let startedAt else { return }
    recorder.updateMeters()
    let elapsed = Date().timeIntervalSince(startedAt)
    let seconds = max(0, Int(elapsed))
    elapsedLabel = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    waveformPhase += 0.34
    let normalizedPower = pow(10, recorder.averagePower(forChannel: 0) / 20)
    waveformAmplitude = min(max(Double(normalizedPower) * 2.4, 0.05), 1)
    if elapsed >= SignalASIPeerVoiceMessageAudio.maximumDuration {
      finish(send: true, status: "")
    }
  }

  private func reset(
    keepStatus: Bool = false,
    keepFile: Bool = false
  ) {
    timer?.invalidate()
    timer = nil
    isPending = false
    isRecording = false
    cancelPending = false
    startedAt = nil
    touchActive = false
    holdTask?.cancel()
    holdTask = nil
    onFinish = nil
    onCancel = nil
    if !keepFile, let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    outputURL = nil
    waveformAmplitude = 0
    if !keepStatus { statusMessage = "" }
  }

  nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    Task { @MainActor [weak self] in
      guard let self, isRecording else { return }
      if flag {
        finish(send: true, status: "")
      } else {
        fail(messages.speechUnavailable)
      }
    }
  }

  nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    Task { @MainActor [weak self] in
      guard let self, isRecording else { return }
      fail(error?.localizedDescription ?? messages.speechUnavailable)
    }
  }

  deinit {
    holdTask?.cancel()
    timer?.invalidate()
    recorder?.stop()
    recorder?.delegate = nil
    if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

final class SignalASIGentleSpeechPlaybackEngine {
  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private let equalizer = AVAudioUnitEQ(numberOfBands: 5)
  private let file: AVAudioFile
  private let sampleRate: Double
  private var startFrame: AVAudioFramePosition = 0
  private var generation = 0
  private(set) var isPlaying = false
  var onCompletion: (() -> Void)?

  var duration: TimeInterval {
    sampleRate > 0 ? Double(file.length) / sampleRate : 0
  }

  var currentTime: TimeInterval {
    guard sampleRate > 0 else { return 0 }
    let rendered = playerNode.lastRenderTime
      .flatMap { playerNode.playerTime(forNodeTime: $0) }
      .map { AVAudioFramePosition($0.sampleTime) } ?? 0
    return min(max(Double(startFrame + rendered) / sampleRate, 0), duration)
  }

  init(url: URL) throws {
    file = try AVAudioFile(forReading: url)
    sampleRate = file.processingFormat.sampleRate
    engine.attach(playerNode)
    engine.attach(equalizer)
    Self.configure(equalizer)
    engine.connect(playerNode, to: equalizer, format: file.processingFormat)
    engine.connect(equalizer, to: engine.mainMixerNode, format: file.processingFormat)
    engine.prepare()
  }

  func play() throws {
    if startFrame >= file.length { startFrame = 0 }
    if !engine.isRunning { try engine.start() }
    isPlaying = true
    scheduleFromCurrentFrame()
    playerNode.play()
  }

  func pause() {
    let pausedFrame = frame(for: currentTime)
    generation += 1
    playerNode.stop()
    startFrame = pausedFrame
    isPlaying = false
  }

  func seek(to seconds: TimeInterval) throws {
    let shouldResume = isPlaying
    generation += 1
    playerNode.stop()
    startFrame = frame(for: min(max(seconds, 0), duration))
    isPlaying = false
    if shouldResume { try play() }
  }

  func stop() {
    generation += 1
    playerNode.stop()
    engine.stop()
    startFrame = 0
    isPlaying = false
  }

  private func scheduleFromCurrentFrame() {
    let remaining = max(file.length - startFrame, 0)
    guard remaining > 0 else {
      finishPlayback()
      return
    }
    generation += 1
    let scheduledGeneration = generation
    playerNode.scheduleSegment(
      file,
      startingFrame: startFrame,
      frameCount: AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max))),
      at: nil,
      completionCallbackType: .dataPlayedBack
    ) { [weak self] _ in
      DispatchQueue.main.async { self?.finishPlayback(generation: scheduledGeneration) }
    }
  }

  private func finishPlayback(generation: Int? = nil) {
    if let generation, generation != self.generation { return }
    playerNode.stop()
    engine.stop()
    startFrame = 0
    isPlaying = false
    onCompletion?()
  }

  private func frame(for seconds: TimeInterval) -> AVAudioFramePosition {
    min(max(AVAudioFramePosition((seconds * sampleRate).rounded()), 0), file.length)
  }

  private static func configure(_ equalizer: AVAudioUnitEQ) {
    let frequencies: [Float] = [90, 400, 2_000, 6_000, 10_000]
    for (index, frequency) in frequencies.enumerated() {
      let band = equalizer.bands[index]
      band.filterType = index == 0 ? .lowShelf : index == frequencies.count - 1 ? .highShelf : .parametric
      band.frequency = frequency
      band.bandwidth = 1
      band.gain = SignalASIPeerVoiceMessageAudio.gentleGainDecibels(centerFrequencyHz: frequency)
      band.bypass = false
    }
    equalizer.globalGain = 0
  }
}
