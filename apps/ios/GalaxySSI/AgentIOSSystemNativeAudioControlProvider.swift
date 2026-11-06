import Foundation

protocol AgentIOSAudioControlProviding {
  func setVolume(stream: String, percent: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult
  func setMute(stream: String, muted: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult
}

struct AgentIOSDefaultAudioControlProvider: AgentIOSAudioControlProviding {
  func setVolume(stream: String, percent: Int, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let normalized = AgentIOSDeviceStateEvidence.audioStream(stream)
    let clamped = max(0, min(100, percent))
    return AgentNativeToolExecutionResult.success(
      output: [
        "stream": .string(normalized),
        "requested_percent": .int(Int64(clamped)),
        "dispatch_attempted": .bool(false),
        "request_accepted": .bool(false),
        "state_verified": .bool(false),
        "changed": .bool(false),
        "settings_changed": .bool(false),
        "global_volume_supported": .bool(false),
        "app_visible_output_volume_read_only": .bool(true),
        "platform": .string("ios"),
        "scope": .string("ios_audio_control_unavailable_app_sandbox")
      ],
      message: "iOS does not allow normal apps to set global stream volume."
    )
  }

  func setMute(stream: String, muted: Bool, nowMillis: Int64) -> AgentNativeToolExecutionResult {
    let normalized = AgentIOSDeviceStateEvidence.audioStream(stream)
    return AgentNativeToolExecutionResult.success(
      output: [
        "stream": .string(normalized),
        "requested_muted": .bool(muted),
        "dispatch_attempted": .bool(false),
        "request_accepted": .bool(false),
        "state_verified": .bool(false),
        "changed": .bool(false),
        "settings_changed": .bool(false),
        "global_mute_supported": .bool(false),
        "platform": .string("ios"),
        "scope": .string("ios_audio_control_unavailable_app_sandbox")
      ],
      message: "iOS does not allow normal apps to mute arbitrary global audio streams."
    )
  }

}

enum AgentIOSDeviceStateEvidence {
  static let tools: Set<String> = [
    AgentIOSSystemNativeToolCatalog.audioVolumeSet,
    AgentIOSSystemNativeToolCatalog.audioMuteSet,
    AgentIOSHardwareNativeToolCatalog.flashlightSet
  ]
  private static let audioStreams: Set<String> = ["music", "ring", "alarm", "notification", "voice_call", "system"]

  static func audioStream(_ value: String) -> String {
    let stream = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return stream == "media" ? "music" : stream
  }

  static func acceptsAudioStream(_ value: String) -> Bool { audioStreams.contains(audioStream(value)) }

  static func unavailableAudioControl(_ output: AgentMcpJSONObject) -> Bool {
    output.string("scope") == "ios_audio_control_unavailable_app_sandbox" ||
      output["global_volume_supported"] == .bool(false) || output["global_mute_supported"] == .bool(false)
  }

  private static func integer(_ value: AgentMcpJSONValue?) -> Int64? {
    guard case .int(let number) = value else { return nil }
    return number
  }

  static func verified(_ toolId: String, output: AgentMcpJSONObject, input: AgentMcpJSONObject? = nil) -> Bool {
    guard output["state_verified"] == .bool(true), (integer(output["observed_at_epoch_ms"]) ?? 0) > 0,
          output["dispatch_attempted"]?.boolValue != nil, output["request_accepted"]?.boolValue != nil else { return false }
    switch toolId {
    case AgentIOSHardwareNativeToolCatalog.flashlightSet:
      guard let requested = output["requested_enabled"]?.boolValue,
            input == nil || input?["enabled"] == .bool(requested) else { return false }
      return output["observed_enabled"] == .bool(requested) && output.string("observation_scope") == "app_visible_torch"
    case AgentIOSSystemNativeToolCatalog.audioVolumeSet, AgentIOSSystemNativeToolCatalog.audioMuteSet:
      let stream = audioStream(output.string("stream"))
      guard audioStreams.contains(stream), !unavailableAudioControl(output), !output.string("observation_scope").isBlank,
            input == nil || audioStream(input?.string("stream") ?? "") == stream else { return false }
      if toolId == AgentIOSSystemNativeToolCatalog.audioMuteSet {
        guard let requested = output["requested_muted"]?.boolValue,
              input == nil || input?["muted"] == .bool(requested) else { return false }
        return output["muted"] == .bool(requested)
      }
      guard let percent = integer(output["requested_percent"]), (0...100).contains(percent),
            input == nil || integer(input?["percent"]) == percent,
            let maximum = integer(output["max"]), (1...10_000).contains(maximum),
            let minimum = integer(output["min"]), (0...maximum).contains(minimum),
            let observed = integer(output["volume"]), (minimum...maximum).contains(observed),
            let target = integer(output["target_volume"]) else { return false }
      return observed == target && target == (percent * maximum + 50) / 100
    default:
      return false
    }
  }

  static func normalize(
    _ result: AgentNativeToolExecutionResult, toolId: String, input: AgentMcpJSONObject
  ) -> AgentNativeToolExecutionResult {
    guard result.isSuccess, tools.contains(toolId) else { return result }
    var result = result
    let verified = verified(toolId, output: result.output, input: input)
    switch toolId {
    case AgentIOSSystemNativeToolCatalog.audioVolumeSet:
      result.output["requested_percent"] = input["percent"]
    case AgentIOSSystemNativeToolCatalog.audioMuteSet:
      result.output["requested_muted"] = input["muted"]
    case AgentIOSHardwareNativeToolCatalog.flashlightSet:
      result.output["requested_enabled"] = input["enabled"]
    default: break
    }
    if unavailableAudioControl(result.output) {
      for key in ["volume", "muted", "min", "max", "percent", "target_volume", "observed_at_epoch_ms", "observation_scope"] {
        result.output.removeValue(forKey: key)
      }
      result.output["dispatch_attempted"] = .bool(false)
      result.output["request_accepted"] = .bool(false)
    }
    result.output["state_verified"] = .bool(verified)
    result.metadata["goal_evidence"] = .string(verified ? "observed_device_state" : "device_state_unverified")
    if verified { result.message = "Requested device state verified by readback." }
    else if !unavailableAudioControl(result.output) {
      result.message = "The requested setting is not confirmed; inspect the actual state before retrying."
    }
    return result
  }

  static func outputSchema(_ toolId: String) -> AgentMcpJSONObject {
    let flag: AgentMcpJSONValue = .object(["type": .string("boolean")])
    let number: AgentMcpJSONValue = .object(["type": .string("integer"), "minimum": .int(0)])
    let text: AgentMcpJSONValue = .object(["type": .string("string")])
    var properties: AgentMcpJSONObject = ["state_verified": flag, "dispatch_attempted": flag,
      "request_accepted": flag, "observed_at_epoch_ms": number, "observation_scope": text]
    let requested: String
    switch toolId {
    case AgentIOSHardwareNativeToolCatalog.flashlightSet:
      requested = "requested_enabled"
      properties[requested] = flag
      properties["observed_enabled"] = flag
    case AgentIOSSystemNativeToolCatalog.audioMuteSet:
      requested = "requested_muted"
      properties[requested] = flag
      properties["muted"] = flag
      properties["stream"] = text
    default:
      requested = "requested_percent"
      for key in [requested, "min", "max", "target_volume", "volume"] { properties[key] = number }
      properties["stream"] = text
    }
    return ["type": .string("object"), "properties": .object(properties),
      "required": .array([.string("state_verified"), .string(requested)]), "additionalProperties": .bool(true)]
  }

  static func torchReadback(
    enabled: Bool, read: () -> Bool, write: (Bool) throws -> Void, nowMillis: () -> Int64
  ) -> AgentNativeToolExecutionResult {
    let before = read()
    let attempted = before != enabled
    var accepted = false
    if attempted {
      do { try write(enabled); accepted = true } catch { accepted = false }
    }
    let observed = attempted ? read() : before
    return .success(output: [
      "requested_enabled": .bool(enabled), "observed_enabled": .bool(observed),
      "dispatch_attempted": .bool(attempted), "request_accepted": .bool(accepted),
      "state_verified": .bool(observed == enabled), "settings_changed": .bool(false),
      "observed_at_epoch_ms": .int(nowMillis()), "observation_scope": .string("app_visible_torch")
    ])
  }
}
