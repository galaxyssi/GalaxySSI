import Foundation

protocol VoiceWhisperNativeAPI {
  func createRuntime(modelPath: String, threadCount: Int, useGPU: Bool) -> Int64
  func createSession(runtimeHandle: Int64, config: VoiceLocalWhisperSessionConfig) -> Int64
  func decodePcm16(
    sessionHandle: Int64,
    pcm: [Int16],
    offset: Int,
    length: Int
  ) -> VoiceNativeWhisperResult
  func requestAbort(sessionHandle: Int64)
  func getTimings(sessionHandle: Int64) -> VoiceNativeWhisperTimings
  func destroySession(sessionHandle: Int64)
  func destroyRuntime(runtimeHandle: Int64)
  func activeRuntimeCount() -> Int
  func activeSessionCount() -> Int
}

struct UnavailableVoiceWhisperNativeBridge: VoiceWhisperNativeAPI {
  func createRuntime(modelPath: String, threadCount: Int, useGPU: Bool) -> Int64 { 0 }
  func createSession(runtimeHandle: Int64, config: VoiceLocalWhisperSessionConfig) -> Int64 { 0 }

  func decodePcm16(
    sessionHandle: Int64,
    pcm: [Int16],
    offset: Int,
    length: Int
  ) -> VoiceNativeWhisperResult {
    VoiceNativeWhisperResult.failure(.modelNotLoaded, message: "Native Whisper bridge is unavailable")
  }

  func requestAbort(sessionHandle: Int64) {}
  func getTimings(sessionHandle: Int64) -> VoiceNativeWhisperTimings { .empty }
  func destroySession(sessionHandle: Int64) {}
  func destroyRuntime(runtimeHandle: Int64) {}
  func activeRuntimeCount() -> Int { 0 }
  func activeSessionCount() -> Int { 0 }
}
