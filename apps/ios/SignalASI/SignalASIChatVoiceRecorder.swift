import AVFoundation
import Combine
import Foundation

struct SignalASIChatVoiceRecorderMessages {
  var permissionDenied: String
  var recordingFailed: String
  var tooShort: String
  var cancelled: String
}

@MainActor
final class SignalASIChatVoiceRecorder: ObservableObject {
  @Published private(set) var isPreparing = false
  @Published private(set) var isRecording = false
  @Published private(set) var cancelPending = false
  @Published private(set) var elapsedSeconds: TimeInterval = 0
  @Published private(set) var waveformPhase: Double = 0
  @Published private(set) var waveformAmplitude: Double = 0
  @Published private(set) var statusMessage = ""

  private let minimumDuration: TimeInterval = 0.8
  private let maximumDuration: TimeInterval = 120
  private let cancellationDistance: CGFloat = -64

  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var startedAt: Date?
  private var meterTimer: Timer?
  private var startTask: Task<Void, Never>?
  private var touchActive = false
  private var awaitingTouchRelease = false
  private var onFinish: ((SignalASIDraftAttachment, TimeInterval) -> Void)?
  private var activeMessages: SignalASIChatVoiceRecorderMessages?

  var isPending: Bool { isPreparing }

  var elapsedLabel: String {
    let totalSeconds = max(0, Int(elapsedSeconds.rounded(.down)))
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
  }

  func dragChanged(
    translation: CGSize,
    messages: SignalASIChatVoiceRecorderMessages,
    onFinish: @escaping (SignalASIDraftAttachment, TimeInterval) -> Void
  ) {
    guard !awaitingTouchRelease else { return }
    touchActive = true
    self.onFinish = onFinish
    activeMessages = messages
    cancelPending = translation.height <= cancellationDistance
    guard !isPreparing, !isRecording, startTask == nil else { return }
    startTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 280_000_000)
      guard !Task.isCancelled, let self, self.touchActive else { return }
      self.startTask = nil
      self.requestPermissionAndStart()
    }
  }

  func dragEnded(translation: CGSize) {
    startTask?.cancel()
    startTask = nil
    awaitingTouchRelease = false
    touchActive = false
    cancelPending = translation.height <= cancellationDistance
    guard isRecording else { return }
    finishRecording(send: !cancelPending)
  }

  func cancelFromView() {
    startTask?.cancel()
    startTask = nil
    touchActive = false
    guard isPreparing || isRecording else { return }
    cancelPending = true
    finishRecording(send: false)
  }

  private func requestPermissionAndStart() {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      startRecording()
    case .undetermined:
      isPreparing = true
      AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          self.isPreparing = false
          guard granted, self.touchActive else {
            if !granted {
              self.statusMessage = self.activeMessages?.permissionDenied ?? ""
            }
            return
          }
          self.startRecording()
        }
      }
    case .denied:
      statusMessage = activeMessages?.permissionDenied ?? ""
    @unknown default:
      statusMessage = activeMessages?.permissionDenied ?? ""
    }
  }

  private func startRecording() {
    guard touchActive, !isRecording else { return }
    isPreparing = true
    do {
      let url = try makeRecordingURL()
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 24_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
      ]
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.isMeteringEnabled = true
      guard recorder.record() else {
        throw SignalASIChatVoiceRecorderError.couldNotStart
      }
      recordingURL = url
      self.recorder = recorder
      startedAt = Date()
      elapsedSeconds = 0
      waveformPhase = 0
      waveformAmplitude = 0
      statusMessage = ""
      isPreparing = false
      isRecording = true
      startMetering()
    } catch {
      isPreparing = false
      statusMessage = activeMessages?.recordingFailed ?? ""
      cleanup(deleteRecording: true)
    }
  }

  private func finishRecording(send: Bool) {
    let duration = max(0, Date().timeIntervalSince(startedAt ?? Date()))
    let url = recordingURL
    recorder?.stop()
    recorder = nil
    isPreparing = false
    isRecording = false
    stopMetering()
    awaitingTouchRelease = touchActive
    defer {
      touchActive = false
      activeMessages = nil
      onFinish = nil
    }

    guard send, duration >= minimumDuration, let url else {
      statusMessage = send ? activeMessages?.tooShort ?? "" : activeMessages?.cancelled ?? ""
      cleanup(deleteRecording: true)
      return
    }
    guard let data = try? Data(contentsOf: url), !data.isEmpty else {
      statusMessage = activeMessages?.recordingFailed ?? ""
      cleanup(deleteRecording: true)
      return
    }

    let attachment = SignalASIDraftAttachment(
      displayName: "voice-\(Int(Date().timeIntervalSince1970)).m4a",
      mimeType: "audio/mp4",
      data: data,
      sourceDescription: url.absoluteString
    )
    recordingURL = nil
    startedAt = nil
    onFinish?(attachment, duration)
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  private func makeRecordingURL() throws -> URL {
    let fileManager = FileManager.default
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
      fileManager.temporaryDirectory
    let directory = root.appendingPathComponent("signalasi-chat-voice", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("\(UUID().uuidString).m4a", isDirectory: false)
  }

  private func startMetering() {
    meterTimer?.invalidate()
    meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let startedAt = self.startedAt else { return }
        self.recorder?.updateMeters()
        let power = self.recorder?.averagePower(forChannel: 0) ?? -60
        let amplitude = Double(max(0, min(1, (power + 60) / 60)))
        self.waveformPhase += 0.35 + Double(amplitude) * 0.6
        self.waveformAmplitude += (amplitude - self.waveformAmplitude) * 0.35
        self.elapsedSeconds = Date().timeIntervalSince(startedAt)
        if self.elapsedSeconds >= self.maximumDuration {
          self.finishRecording(send: true)
        }
      }
    }
  }

  private func stopMetering() {
    meterTimer?.invalidate()
    meterTimer = nil
  }

  private func cleanup(deleteRecording: Bool) {
    stopMetering()
    recorder?.stop()
    recorder = nil
    if deleteRecording, let recordingURL {
      try? FileManager.default.removeItem(at: recordingURL)
    }
    recordingURL = nil
    startedAt = nil
    isRecording = false
    isPreparing = false
    waveformAmplitude = 0
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
}

private enum SignalASIChatVoiceRecorderError: Error {
  case couldNotStart
}
