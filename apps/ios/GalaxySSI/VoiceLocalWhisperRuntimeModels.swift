import Foundation

enum VoiceNativeWhisperCode: Int, Codable, Equatable {
  case ok = 0
  case aborted = 1
  case invalidHandle = 2
  case modelNotLoaded = 3
  case modelCorrupted = 4
  case unsupportedModel = 5
  case invalidPCM = 6
  case decodeFailed = 7
  case outOfMemory = 8
  case nativeInternalError = 9
  case timeout = 10

  static func fromWire(_ value: Int) -> VoiceNativeWhisperCode {
    VoiceNativeWhisperCode(rawValue: value) ?? .nativeInternalError
  }
}

struct VoiceNativeWhisperSegment: Codable, Equatable {
  var startMillis: Int64
  var endMillis: Int64
  var text: String
  var averageLogProbability: Float
  var noSpeechProbability: Float
}

struct VoiceNativeWhisperTimings: Codable, Equatable {
  var sampleMillis: Double
  var encodeMillis: Double
  var decodeMillis: Double
  var totalMillis: Double
  var audioMillis: Int64
  var realTimeFactor: Double

  static let empty = VoiceNativeWhisperTimings(
    sampleMillis: 0,
    encodeMillis: 0,
    decodeMillis: 0,
    totalMillis: 0,
    audioMillis: 0,
    realTimeFactor: 0
  )
}

struct VoiceNativeWhisperResult: Codable, Equatable {
  var codeValue: Int
  var segments: [VoiceNativeWhisperSegment]
  var detectedLanguage: String?
  var timings: VoiceNativeWhisperTimings
  var aborted: Bool
  var message: String?

  var code: VoiceNativeWhisperCode {
    VoiceNativeWhisperCode.fromWire(codeValue)
  }

  var text: String {
    segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var successful: Bool {
    code == .ok
  }

  static func failure(_ code: VoiceNativeWhisperCode, message: String) -> VoiceNativeWhisperResult {
    VoiceNativeWhisperResult(
      codeValue: code.rawValue,
      segments: [],
      detectedLanguage: nil,
      timings: .empty,
      aborted: code == .aborted,
      message: message
    )
  }
}

struct VoiceWhisperLoadOptions: Equatable {
  var threadCount: Int
  var useGPU: Bool
  var warmUp: Bool
  var warmUpSamples: Int

  init(
    threadCount: Int = min(4, max(1, ProcessInfo.processInfo.processorCount)),
    useGPU: Bool = false,
    warmUp: Bool = true,
    warmUpSamples: Int = 16_000
  ) throws {
    guard (1...16).contains(threadCount), !useGPU, (1_600...32_000).contains(warmUpSamples) else {
      throw VoiceWhisperRuntimeFailure.invalidOptions
    }
    self.threadCount = threadCount
    self.useGPU = useGPU
    self.warmUp = warmUp
    self.warmUpSamples = warmUpSamples
  }
}

struct VoiceLocalWhisperSessionConfig: Equatable {
  var language: String
  var translate: Bool
  var noContext: Bool
  var singleSegment: Bool
  var maxTokens: Int
  var prompt: String
  var mode: VoiceWhisperExecutionMode

  init(
    language: String = "zh",
    translate: Bool = false,
    noContext: Bool = true,
    singleSegment: Bool = false,
    maxTokens: Int = 0,
    prompt: String = "",
    mode: VoiceWhisperExecutionMode = .finalOnly
  ) throws {
    guard language.count <= 16, (0...4_096).contains(maxTokens), prompt.count <= 1_024 else {
      throw VoiceWhisperRuntimeFailure.invalidOptions
    }
    self.language = language
    self.translate = translate
    self.noContext = noContext
    self.singleSegment = singleSegment
    self.maxTokens = maxTokens
    self.prompt = prompt
    self.mode = mode
  }
}

struct VoiceWhisperDecodeRequest: Equatable {
  var pcm16: [Int16]
  var sampleRateHz: Int
  var offset: Int
  var length: Int
  var mode: VoiceWhisperExecutionMode

  init(
    pcm16: [Int16],
    sampleRateHz: Int = 16_000,
    offset: Int = 0,
    length: Int? = nil,
    mode: VoiceWhisperExecutionMode = .finalOnly
  ) throws {
    let resolvedLength = length ?? (pcm16.count - offset)
    guard sampleRateHz == 16_000,
          offset >= 0,
          resolvedLength > 0,
          offset <= pcm16.count - resolvedLength else {
      throw VoiceWhisperRuntimeFailure.invalidPCM
    }
    self.pcm16 = pcm16
    self.sampleRateHz = sampleRateHz
    self.offset = offset
    self.length = resolvedLength
    self.mode = mode
  }
}

struct VoiceWhisperLoadedModel: Equatable {
  var profile: VoiceWhisperModelProfile
  var threadCount: Int
  var loadedAtMillis: Int64
  var loadDurationMillis: Int64
  var warmUpTimings: VoiceNativeWhisperTimings?
}

enum VoiceWhisperAbortReason: String, Codable, Equatable {
  case userStop = "USER_STOP"
  case newUtterance = "NEW_UTTERANCE"
  case sessionClosed = "SESSION_CLOSED"
  case modelSwitch = "MODEL_SWITCH"
  case thermalCritical = "THERMAL_CRITICAL"
  case timeout = "TIMEOUT"
  case upstreamFinalSelected = "UPSTREAM_FINAL_SELECTED"
  case memoryPressure = "MEMORY_PRESSURE"
  case runtimeUnload = "RUNTIME_UNLOAD"
}

enum VoiceWhisperUnloadReason: String, Codable, Equatable {
  case userRequest = "USER_REQUEST"
  case modelSwitch = "MODEL_SWITCH"
  case memoryPressure = "MEMORY_PRESSURE"
  case thermalCritical = "THERMAL_CRITICAL"
  case appShutdown = "APP_SHUTDOWN"
  case loadFailed = "LOAD_FAILED"
}

struct VoiceWhisperRuntimeError: Equatable {
  var code: VoiceNativeWhisperCode
  var message: String
}

enum VoiceWhisperRuntimeState: Equatable {
  case unloaded
  case loading(profileId: String)
  case ready(VoiceWhisperLoadedModel)
  case decoding(sessionId: String, mode: VoiceWhisperExecutionMode)
  case unloading(reason: VoiceWhisperUnloadReason)
  case failed(VoiceWhisperRuntimeError)
}

struct VoiceWhisperBenchmarkRequest: Equatable {
  var pcm16: [Int16]
  var language: String
  var iterations: Int

  init(pcm16: [Int16], language: String = "zh", iterations: Int = 1) throws {
    guard !pcm16.isEmpty, (1...30).contains(iterations) else {
      throw VoiceWhisperRuntimeFailure.invalidPCM
    }
    self.pcm16 = pcm16
    self.language = language
    self.iterations = iterations
  }
}

struct VoiceWhisperBenchmarkResult: Equatable {
  var profileId: String
  var iterations: Int
  var timings: [VoiceNativeWhisperTimings]
  var medianRealTimeFactor: Double
}

enum VoiceWhisperRuntimeFailure: LocalizedError, Equatable {
  case closed
  case invalidOptions
  case invalidPCM
  case modelNotLoaded
  case verifiedModelUnavailable
  case nativeLoadFailed(String)
  case sessionCreationFailed
  case sessionClosed
  case decodeFailed(String)

  var errorDescription: String? {
    switch self {
    case .closed:
      return "Local Whisper runtime is closed."
    case .invalidOptions:
      return "Local Whisper runtime options are invalid."
    case .invalidPCM:
      return "Local Whisper PCM input is invalid."
    case .modelNotLoaded:
      return "A Whisper model must be loaded before decoding."
    case .verifiedModelUnavailable:
      return "Verified Whisper model file is unavailable."
    case .nativeLoadFailed(let detail):
      return "Native Whisper runtime could not load the model: \(detail)"
    case .sessionCreationFailed:
      return "Native Whisper session could not be created."
    case .sessionClosed:
      return "Whisper session is closed."
    case .decodeFailed(let detail):
      return "Whisper decode failed: \(detail)"
    }
  }
}

protocol VoiceLocalWhisperSession: AnyObject {
  var id: String { get }
  var config: VoiceLocalWhisperSessionConfig { get }
  func decode(_ request: VoiceWhisperDecodeRequest) async throws -> VoiceNativeWhisperResult
  func requestAbort(_ reason: VoiceWhisperAbortReason)
  func close()
}

protocol VoiceStatefulLocalWhisperRuntime: AnyObject {
  var state: VoiceWhisperRuntimeState { get }
  func load(
    profile: VoiceWhisperModelProfile,
    options: VoiceWhisperLoadOptions
  ) async throws -> VoiceWhisperLoadedModel
  func createSession(config: VoiceLocalWhisperSessionConfig) async throws -> VoiceLocalWhisperSession
  func unload(reason: VoiceWhisperUnloadReason) async
  func runBenchmark(_ request: VoiceWhisperBenchmarkRequest) async throws -> VoiceWhisperBenchmarkResult
  func requestAbortAll(_ reason: VoiceWhisperAbortReason)
  func close()
}
