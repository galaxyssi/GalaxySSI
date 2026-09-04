import Foundation

enum VoiceTracePrivacy {
  static func safeIdentifier(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return matches(trimmed, pattern: "[A-Za-z0-9][A-Za-z0-9._:-]{0,127}") ? trimmed : nil
  }

  static func safeEvent(_ value: String) -> String? {
    let event = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return matches(event, pattern: "[a-z][a-z0-9_]{0,95}") ? event : nil
  }

  static func sanitizeAttributes(_ attributes: [String: String]) -> [String: String] {
    var sanitized: [String: String] = [:]
    for (rawKey, rawValue) in attributes {
      let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard allowedKeys.contains(key) else { continue }
      let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let safe: String?
      if key == "model_sha256" {
        safe = matches(value.lowercased(), pattern: "[a-f0-9]{64}") ? value.lowercased() : nil
      } else if numericKeys.contains(key) {
        if let number = Double(value), number.isFinite {
          safe = value
        } else {
          safe = nil
        }
      } else if booleanKeys.contains(key) {
        let lowered = value.lowercased()
        safe = lowered == "true" || lowered == "false" ? lowered : nil
      } else if value.contains("/") || value.contains("\\") || value.contains("@") {
        safe = nil
      } else {
        safe = matches(value, pattern: "[A-Za-z0-9][A-Za-z0-9 ._:+-]{0,119}") ? value : nil
      }
      if let safe = safe {
        sanitized[key] = safe
      }
    }
    return sanitized
  }

  private static func matches(_ value: String, pattern: String) -> Bool {
    value.range(of: "^\(pattern)$", options: .regularExpression) != nil
  }

  private static let allowedKeys: Set<String> = [
    "device_model", "soc", "android_api", "ios_version", "app_version", "native_version",
    "network_type", "asr_provider", "model_provider", "model_profile_id", "model_sha256",
    "quantization", "execution_mode", "thread_count", "thermal_status",
    "battery_percent", "is_charging", "audio_duration_ms", "rtf",
    "agent_provider", "tts_provider", "error_code", "recording_source", "endpoint_reason",
    "http_status", "success", "cold_start", "queue_depth", "transport",
    "task_status", "retry_count", "fallback", "duration_ms",
  ]
  private static let numericKeys: Set<String> = [
    "android_api", "ios_version", "thread_count", "thermal_status", "battery_percent",
    "audio_duration_ms", "rtf", "http_status", "queue_depth", "retry_count",
    "duration_ms",
  ]
  private static let booleanKeys: Set<String> = ["is_charging", "success", "cold_start", "fallback"]
}

enum VoiceLatencyFeatureFlags {
  static func isEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = true
  ) -> Bool {
    guard userDefaults.object(forKey: voiceLatencyTraceFlag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceLatencyTraceFlag)
  }

  static func setEnabled(_ enabled: Bool, userDefaults: UserDefaults = .standard) {
    userDefaults.set(enabled, forKey: voiceLatencyTraceFlag)
  }
}

enum VoiceLatencyTraceContext {
  private static let key = "galaxyssi.voice_latency_trace_id"

  static func currentTraceId() -> String {
    Thread.current.threadDictionary[key] as? String ?? ""
  }

  static func withTrace<T>(_ traceId: String, operation: () -> T) -> T {
    let previous = currentTraceId()
    if traceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Thread.current.threadDictionary.removeObject(forKey: key)
    } else {
      Thread.current.threadDictionary[key] = traceId
    }
    defer {
      if previous.isEmpty {
        Thread.current.threadDictionary.removeObject(forKey: key)
      } else {
        Thread.current.threadDictionary[key] = previous
      }
    }
    return operation()
  }
}
