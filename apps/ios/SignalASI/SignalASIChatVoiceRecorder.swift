import AVFoundation
import Combine
import Foundation
import Speech

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
  @Published private(set) var stableTranscript = ""
  @Published private(set) var unstableTranscript = ""
  @Published private(set) var statusMessage = ""

  private let minimumDuration: TimeInterval = 0.8
  private let maximumDuration: TimeInterval = 120
  private let cancellationDistance: CGFloat = -64

  private let audioEngine = AVAudioEngine()
  private var audioFile: AVAudioFile?
  private var speechRecognizer: SFSpeechRecognizer?
  private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
  private var speechTask: SFSpeechRecognitionTask?
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
      try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
      try session.setActive(true)
      let input = audioEngine.inputNode
      let format = input.outputFormat(forBus: 0)
      let fileSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: max(16_000, format.sampleRate),
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
      ]
      audioFile = try AVAudioFile(
        forWriting: url,
        settings: fileSettings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
      )
      input.removeTap(onBus: 0)
      input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
        self?.append(buffer)
      }
      audioEngine.prepare()
      try audioEngine.start()
      recordingURL = url
      startedAt = Date()
      elapsedSeconds = 0
      waveformPhase = 0
      waveformAmplitude = 0
      stableTranscript = ""
      unstableTranscript = ""
      statusMessage = ""
      isPreparing = false
      isRecording = true
      startSpeechRecognition()
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
    stopAudioCapture()
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

  private func append(_ buffer: AVAudioPCMBuffer) {
    guard isRecording else { return }
    try? audioFile?.write(from: buffer)
    speechRequest?.append(buffer)
    let channel = buffer.floatChannelData?.pointee
    let frameCount = Int(buffer.frameLength)
    guard let channel, frameCount > 0 else { return }
    var sum: Float = 0
    for index in 0..<frameCount {
      let value = channel[index]
      sum += value * value
    }
    let rms = sqrt(sum / Float(frameCount))
    let amplitude = Double(min(1, max(0, rms * 8)))
    Task { @MainActor [weak self] in
      guard let self, self.isRecording else { return }
      self.waveformAmplitude += (amplitude - self.waveformAmplitude) * 0.35
    }
  }

  private func startSpeechRecognition() {
    guard #available(iOS 15.0, *) else { return }
    switch SFSpeechRecognizer.authorizationStatus() {
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { [weak self] status in
        guard status == .authorized else { return }
        DispatchQueue.main.async {
          guard let self, self.isRecording else { return }
          self.startSpeechRecognition()
        }
      }
      return
    case .denied, .restricted:
      return
    case .authorized:
      break
    @unknown default:
      return
    }
    let locale = Locale.current
    guard let recognizer = SFSpeechRecognizer(locale: locale),
          recognizer.isAvailable else {
      return
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if recognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }
    speechRecognizer = recognizer
    speechRequest = request
    speechTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
      guard let text = result?.bestTranscription.formattedString else { return }
      Task { @MainActor [weak self] in
        guard let self, self.isRecording else { return }
        if result?.isFinal == true {
          self.stableTranscript = text
          self.unstableTranscript = ""
        } else {
          self.unstableTranscript = text
        }
      }
    }
  }

  private func stopAudioCapture() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    audioFile = nil
    speechRequest?.endAudio()
    speechTask?.cancel()
    speechTask = nil
    speechRequest = nil
    speechRecognizer = nil
  }

  private func startMetering() {
    meterTimer?.invalidate()
    meterTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let startedAt = self.startedAt else { return }
        self.waveformPhase += 0.35 + self.waveformAmplitude * 0.6
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
    stopAudioCapture()
    if deleteRecording, let recordingURL {
      try? FileManager.default.removeItem(at: recordingURL)
    }
    recordingURL = nil
    startedAt = nil
    isRecording = false
    isPreparing = false
    waveformAmplitude = 0
    stableTranscript = ""
    unstableTranscript = ""
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
}

private enum SignalASIChatVoiceRecorderError: Error {
  case couldNotStart
}
