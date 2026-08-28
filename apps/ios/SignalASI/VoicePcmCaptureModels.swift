import Foundation

struct PcmCaptureConfig: Equatable {
  var sampleRateHz: Int
  var frameDurationMs: Int
  var maxDurationMs: Int64
  var preferredInputModes: [String]
  var enableAcousticEchoCancellation: Bool
  var enableNoiseSuppression: Bool
  var enableAutomaticGainControl: Bool
  var framePoolSize: Int
  var outputQueueCapacity: Int

  init(
    sampleRateHz: Int = 16_000,
    frameDurationMs: Int = 20,
    maxDurationMs: Int64 = 60_000,
    preferredInputModes: [String] = ["measurement", "default"],
    enableAcousticEchoCancellation: Bool = true,
    enableNoiseSuppression: Bool = true,
    enableAutomaticGainControl: Bool = false,
    framePoolSize: Int = 16,
    outputQueueCapacity: Int = 8
  ) {
    precondition(sampleRateHz > 0)
    precondition((10...100).contains(frameDurationMs))
    precondition(maxDurationMs > 0)
    precondition(!preferredInputModes.isEmpty)
    precondition(framePoolSize >= 4)
    precondition(outputQueueCapacity >= 1)
    self.sampleRateHz = sampleRateHz
    self.frameDurationMs = frameDurationMs
    self.maxDurationMs = maxDurationMs
    self.preferredInputModes = preferredInputModes
    self.enableAcousticEchoCancellation = enableAcousticEchoCancellation
    self.enableNoiseSuppression = enableNoiseSuppression
    self.enableAutomaticGainControl = enableAutomaticGainControl
    self.framePoolSize = framePoolSize
    self.outputQueueCapacity = outputQueueCapacity
  }

  var samplesPerFrame: Int {
    max(1, sampleRateHz * frameDurationMs / 1_000)
  }
}

enum PcmRecorderPhase: String, Codable, Equatable {
  case idle = "IDLE"
  case starting = "STARTING"
  case recording = "RECORDING"
  case stopping = "STOPPING"
  case stopped = "STOPPED"
  case failed = "FAILED"
}

enum PcmStopReason: String, Codable, Equatable {
  case userSend = "USER_SEND"
  case userCancel = "USER_CANCEL"
  case adaptiveEndpoint = "ADAPTIVE_ENDPOINT"
  case noSpeechTimeout = "NO_SPEECH_TIMEOUT"
  case maxDuration = "MAX_DURATION"
  case appBackground = "APP_BACKGROUND"
  case audioInterrupted = "AUDIO_INTERRUPTED"
  case captureFailure = "CAPTURE_FAILURE"
}

struct PcmRecorderDiagnostics: Codable, Equatable {
  var shortReadCount: Int64
  var zeroReadCount: Int64
  var droppedFrameCount: Int64
  var suspectedOverrunCount: Int64
  var inputRouteChangeCount: Int64

  init(
    shortReadCount: Int64 = 0,
    zeroReadCount: Int64 = 0,
    droppedFrameCount: Int64 = 0,
    suspectedOverrunCount: Int64 = 0,
    inputRouteChangeCount: Int64 = 0
  ) {
    self.shortReadCount = max(0, shortReadCount)
    self.zeroReadCount = max(0, zeroReadCount)
    self.droppedFrameCount = max(0, droppedFrameCount)
    self.suspectedOverrunCount = max(0, suspectedOverrunCount)
    self.inputRouteChangeCount = max(0, inputRouteChangeCount)
  }
}

struct PcmRecorderState: Codable, Equatable {
  var phase: PcmRecorderPhase
  var audioSource: String?
  var audioSessionId: Int?
  var inputRoute: String
  var currentAmplitude: Int
  var capturedSamples: Int64
  var stopReason: PcmStopReason?
  var errorCode: String?
  var diagnostics: PcmRecorderDiagnostics

  init(
    phase: PcmRecorderPhase = .idle,
    audioSource: String? = nil,
    audioSessionId: Int? = nil,
    inputRoute: String = "",
    currentAmplitude: Int = 0,
    capturedSamples: Int64 = 0,
    stopReason: PcmStopReason? = nil,
    errorCode: String? = nil,
    diagnostics: PcmRecorderDiagnostics = PcmRecorderDiagnostics()
  ) {
    self.phase = phase
    self.audioSource = audioSource
    self.audioSessionId = audioSessionId
    self.inputRoute = inputRoute
    self.currentAmplitude = max(0, currentAmplitude)
    self.capturedSamples = max(0, capturedSamples)
    self.stopReason = stopReason
    self.errorCode = errorCode
    self.diagnostics = diagnostics
  }
}

final class AudioFrame {
  let sequence: Int64
  let captureTimeNanos: Int64
  private(set) var samples: [Int16]
  let validSamples: Int

  private let lock = NSLock()
  private let releaseAction: ([Int16]) -> Void
  private var released = false

  init(
    sequence: Int64,
    captureTimeNanos: Int64,
    samples: [Int16],
    validSamples: Int? = nil,
    releaseAction: @escaping ([Int16]) -> Void = { _ in }
  ) {
    self.sequence = max(0, sequence)
    self.captureTimeNanos = max(0, captureTimeNanos)
    self.samples = samples
    self.validSamples = min(max(0, validSamples ?? samples.count), samples.count)
    self.releaseAction = releaseAction
  }

  func close() {
    lock.lock()
    guard !released else {
      lock.unlock()
      return
    }
    released = true
    lock.unlock()
    for index in samples.indices {
      samples[index] = 0
    }
    releaseAction(samples)
    samples.removeAll(keepingCapacity: false)
  }

  deinit {
    close()
  }
}

struct PcmSnapshot: Equatable {
  var samples: [Int16]
  var sampleRateHz: Int
  var speechDetected: Bool
  var speechStartSample: Int64?
  var speechEndSampleExclusive: Int64?
  var captureStartSample: Int64
  var captureEndSampleExclusive: Int64

  var durationMs: Int64 {
    guard sampleRateHz > 0 else { return 0 }
    return Int64(samples.count) * 1_000 / Int64(sampleRateHz)
  }

  mutating func wipeSensitive() {
    samples.wipeSensitive()
    speechStartSample = nil
    speechEndSampleExclusive = nil
    captureStartSample = 0
    captureEndSampleExclusive = 0
  }
}

struct VoiceAudioCaptureResult: Equatable {
  var sessionId: String
  var stopReason: PcmStopReason
  var snapshot: PcmSnapshot
  var diagnostics: PcmRecorderDiagnostics
  var audioSource: String?
  var inputRoute: String
}

struct PcmCaptureError: LocalizedError, Equatable {
  var code: String
  var message: String

  var errorDescription: String? { message }
}
