import Foundation

struct VoiceLocalWhisperRuntimeRequest: Equatable {
  var model: VoiceWhisperModelProfile
  var modelFileURL: URL?
  var language: String
  var samples: [Float]
  var sampleRateHz: Int
  var threadCount: Int
}

struct VoiceLocalWhisperTranscriptionResult: Equatable {
  var text: String
  var selectedModel: VoiceWhisperModelProfile
  var model: VoiceWhisperModelProfile
  var language: String
  var audioDurationMs: Int64
  var sampleRateHz: Int
  var threadCount: Int
  var runtimeDecision: VoiceWhisperRuntimeDecision?

  init(
    text: String,
    selectedModel: VoiceWhisperModelProfile,
    model: VoiceWhisperModelProfile,
    language: String,
    audioDurationMs: Int64,
    sampleRateHz: Int,
    threadCount: Int,
    runtimeDecision: VoiceWhisperRuntimeDecision? = nil
  ) {
    self.text = text
    self.selectedModel = selectedModel
    self.model = model
    self.language = language
    self.audioDurationMs = audioDurationMs
    self.sampleRateHz = sampleRateHz
    self.threadCount = max(threadCount, 1)
    self.runtimeDecision = runtimeDecision
  }

  var secondPassProfileId: String? {
    guard runtimeDecision?.runSecondPass == true else { return nil }
    return runtimeDecision?.accurateProfileId
  }

  var secondPassMode: VoiceWhisperExecutionMode? {
    guard runtimeDecision?.runSecondPass == true else { return nil }
    return runtimeDecision?.accurateMode ?? .secondPass
  }
}

enum VoiceLocalWhisperASRError: LocalizedError, Equatable {
  case runtimeUnavailable
  case modelUnavailable(String)
  case emptyAudio
  case inferenceFailed(String)

  var errorDescription: String? {
    switch self {
    case .runtimeUnavailable:
      return "Local Whisper runtime is not available on this iOS build."
    case .modelUnavailable(let modelId):
      return "Local Whisper model is not available: \(modelId)"
    case .emptyAudio:
      return "Decoded local Whisper audio is empty."
    case .inferenceFailed(let detail):
      return "Local Whisper inference failed: \(detail)"
    }
  }
}

protocol VoiceLocalWhisperRuntime {
  func transcribe(_ request: VoiceLocalWhisperRuntimeRequest) async throws -> String
  func release()
}

struct UnavailableVoiceLocalWhisperRuntime: VoiceLocalWhisperRuntime {
  func transcribe(_ request: VoiceLocalWhisperRuntimeRequest) async throws -> String {
    throw VoiceLocalWhisperASRError.runtimeUnavailable
  }

  func release() {}
}

enum VoiceWhisperLanguagePolicy {
  static func normalizedRecognitionLanguage(_ language: String) -> String {
    let normalized = language
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .split(separator: "-")
      .first
      .map(String.init) ?? ""
    return ["zh", "en"].contains(normalized) ? normalized : "auto"
  }

  static func normalizeTranscript(_ text: String, language: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard language.caseInsensitiveCompare("zh-CN") == .orderedSame, !trimmed.isEmpty else {
      return trimmed
    }
    let mutable = NSMutableString(string: trimmed)
    if CFStringTransform(mutable as CFMutableString, nil, "Traditional-Simplified" as CFString, false) {
      return mutable as String
    }
    return trimmed
  }
}
