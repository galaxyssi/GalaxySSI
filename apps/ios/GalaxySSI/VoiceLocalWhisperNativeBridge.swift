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

final class GalaxySSIWhisperNativeBridge: VoiceWhisperNativeAPI {
  func createRuntime(modelPath: String, threadCount: Int, useGPU: Bool) -> Int64 {
    #if GALAXYSSI_NATIVE_WHISPER
    guard !useGPU else { return 0 }
    return modelPath.withCString {
      galaxyssi_whisper_create_runtime($0, Int32(threadCount), 0)
    }
    #else
    return 0
    #endif
  }

  func createSession(runtimeHandle: Int64, config: VoiceLocalWhisperSessionConfig) -> Int64 {
    #if GALAXYSSI_NATIVE_WHISPER
    return config.language.withCString { language in
      config.prompt.withCString { prompt in
        galaxyssi_whisper_create_session(
          runtimeHandle,
          language,
          config.translate ? 1 : 0,
          config.noContext ? 1 : 0,
          config.singleSegment ? 1 : 0,
          Int32(config.maxTokens),
          prompt
        )
      }
    }
    #else
    return 0
    #endif
  }

  func decodePcm16(
    sessionHandle: Int64,
    pcm: [Int16],
    offset: Int,
    length: Int
  ) -> VoiceNativeWhisperResult {
    #if GALAXYSSI_NATIVE_WHISPER
    guard offset >= 0, length > 0, offset <= pcm.count, length <= pcm.count - offset else {
      return .failure(.invalidPCM, message: "PCM16 input is invalid")
    }
    return pcm.withUnsafeBufferPointer { buffer in
      guard let baseAddress = buffer.baseAddress else {
        return .failure(.invalidPCM, message: "PCM16 input is empty")
      }
      guard let pointer = galaxyssi_whisper_decode_json(
        sessionHandle,
        baseAddress.advanced(by: offset),
        Int32(length)
      ) else {
        return .failure(.nativeInternalError, message: "Whisper native runtime returned no result")
      }
      defer { galaxyssi_whisper_free_string(pointer) }
      return Self.decodeResult(String(cString: pointer))
    }
    #else
    return .failure(.modelNotLoaded, message: "Native Whisper bridge is unavailable")
    #endif
  }

  func requestAbort(sessionHandle: Int64) {
    #if GALAXYSSI_NATIVE_WHISPER
    galaxyssi_whisper_request_abort(sessionHandle)
    #endif
  }

  func getTimings(sessionHandle: Int64) -> VoiceNativeWhisperTimings {
    #if GALAXYSSI_NATIVE_WHISPER
    guard let pointer = galaxyssi_whisper_timings_json(sessionHandle) else { return .empty }
    defer { galaxyssi_whisper_free_string(pointer) }
    return Self.decodeTimings(String(cString: pointer))
    #else
    return .empty
    #endif
  }

  func destroySession(sessionHandle: Int64) {
    #if GALAXYSSI_NATIVE_WHISPER
    galaxyssi_whisper_destroy_session(sessionHandle)
    #endif
  }

  func destroyRuntime(runtimeHandle: Int64) {
    #if GALAXYSSI_NATIVE_WHISPER
    galaxyssi_whisper_destroy_runtime(runtimeHandle)
    #endif
  }

  func activeRuntimeCount() -> Int {
    #if GALAXYSSI_NATIVE_WHISPER
    return Int(galaxyssi_whisper_active_runtime_count())
    #else
    return 0
    #endif
  }

  func activeSessionCount() -> Int {
    #if GALAXYSSI_NATIVE_WHISPER
    return Int(galaxyssi_whisper_active_session_count())
    #else
    return 0
    #endif
  }

  private static func decodeResult(_ raw: String) -> VoiceNativeWhisperResult {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let value = object as? [String: Any] else {
      return .failure(.nativeInternalError, message: "Whisper native result was invalid")
    }
    let segments = (value["segments"] as? [[String: Any]] ?? []).map { segment in
      VoiceNativeWhisperSegment(
        startMillis: integer(segment["start_ms"]),
        endMillis: integer(segment["end_ms"]),
        text: segment["text"] as? String ?? "",
        averageLogProbability: float(segment["average_log_probability"]),
        noSpeechProbability: float(segment["no_speech_probability"])
      )
    }
    return VoiceNativeWhisperResult(
      codeValue: Int(integer(value["code"])),
      segments: segments,
      detectedLanguage: value["detected_language"] as? String,
      timings: decodeTimings(value["timings"] as? [String: Any] ?? [:]),
      aborted: value["aborted"] as? Bool ?? false,
      message: value["message"] as? String
    )
  }

  private static func decodeTimings(_ raw: String) -> VoiceNativeWhisperTimings {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let value = object as? [String: Any] else {
      return .empty
    }
    return decodeTimings(value)
  }

  private static func decodeTimings(_ value: [String: Any]) -> VoiceNativeWhisperTimings {
    VoiceNativeWhisperTimings(
      sampleMillis: double(value["sample_ms"]),
      encodeMillis: double(value["encode_ms"]),
      decodeMillis: double(value["decode_ms"]),
      totalMillis: double(value["total_ms"]),
      audioMillis: integer(value["audio_ms"]),
      realTimeFactor: double(value["rtf"])
    )
  }

  private static func integer(_ value: Any?) -> Int64 {
    (value as? NSNumber)?.int64Value ?? 0
  }

  private static func double(_ value: Any?) -> Double {
    (value as? NSNumber)?.doubleValue ?? 0
  }

  private static func float(_ value: Any?) -> Float {
    Float(double(value))
  }
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

#if GALAXYSSI_NATIVE_WHISPER
@_silgen_name("galaxyssi_whisper_create_runtime")
private func galaxyssi_whisper_create_runtime(
  _ modelPath: UnsafePointer<CChar>,
  _ threadCount: Int32,
  _ useGPU: Int32
) -> Int64

@_silgen_name("galaxyssi_whisper_create_session")
private func galaxyssi_whisper_create_session(
  _ runtimeHandle: Int64,
  _ language: UnsafePointer<CChar>,
  _ translate: Int32,
  _ noContext: Int32,
  _ singleSegment: Int32,
  _ maxTokens: Int32,
  _ prompt: UnsafePointer<CChar>
) -> Int64

@_silgen_name("galaxyssi_whisper_decode_json")
private func galaxyssi_whisper_decode_json(
  _ sessionHandle: Int64,
  _ pcm: UnsafePointer<Int16>,
  _ length: Int32
) -> UnsafeMutablePointer<CChar>?

@_silgen_name("galaxyssi_whisper_timings_json")
private func galaxyssi_whisper_timings_json(_ sessionHandle: Int64) -> UnsafeMutablePointer<CChar>?

@_silgen_name("galaxyssi_whisper_request_abort")
private func galaxyssi_whisper_request_abort(_ sessionHandle: Int64)

@_silgen_name("galaxyssi_whisper_destroy_session")
private func galaxyssi_whisper_destroy_session(_ sessionHandle: Int64)

@_silgen_name("galaxyssi_whisper_destroy_runtime")
private func galaxyssi_whisper_destroy_runtime(_ runtimeHandle: Int64)

@_silgen_name("galaxyssi_whisper_active_runtime_count")
private func galaxyssi_whisper_active_runtime_count() -> Int32

@_silgen_name("galaxyssi_whisper_active_session_count")
private func galaxyssi_whisper_active_session_count() -> Int32

@_silgen_name("galaxyssi_whisper_free_string")
private func galaxyssi_whisper_free_string(_ value: UnsafeMutablePointer<CChar>?)
#endif
