import Foundation

protocol AgentIOSAudioControlProviding {
  func setVolume(stream: String, percent: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult
  func setMute(stream: String, muted: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultAudioControlProvider: AgentIOSAudioControlProviding {
  func setVolume(stream: String, percent: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let normalized = normalizedStream(stream)
    let clamped = max(0, min(100, percent))
    return AgentNativeToolExecutionResult.success(
      output: [
        "stream": .string(normalized),
        "percent": .int(Int64(clamped)),
        "volume": .null,
        "max": .int(100),
        "changed": .bool(false),
        "settings_changed": .bool(false),
        "global_volume_supported": .bool(false),
        "app_visible_output_volume_read_only": .bool(true),
        "platform": .string("ios"),
        "scope": .string("ios_audio_control_unavailable_app_sandbox"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "iOS does not allow normal apps to set global stream volume."
    )
  }

  func setMute(stream: String, muted: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let normalized = normalizedStream(stream)
    return AgentNativeToolExecutionResult.success(
      output: [
        "stream": .string(normalized),
        "muted": .bool(muted),
        "changed": .bool(false),
        "settings_changed": .bool(false),
        "global_mute_supported": .bool(false),
        "platform": .string("ios"),
        "scope": .string("ios_audio_control_unavailable_app_sandbox"),
        "observed_at_epoch_ms": .int(nowMillis)
      ],
      message: "iOS does not allow normal apps to mute arbitrary global audio streams."
    )
  }

  private func normalizedStream(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .prefix(32)
    switch String(normalized) {
    case "media", "music":
      return "music"
    case "ring", "alarm", "notification", "voice_call", "system":
      return String(normalized)
    default:
      return "music"
    }
  }
}
