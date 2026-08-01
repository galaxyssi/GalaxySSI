import Foundation

let voiceCoordinatorFlag = "voice.coordinator_v1"
let voicePcmCaptureFlag = "voice.audio_record_pcm_v1"
let voiceLocalWhisperRuntimeV2Flag = "voice.local_whisper_runtime_v2"
let voiceWhisperAdaptivePartialV1Flag = "voice.whisper_adaptive_partial_v1"
let voiceWhisperAutoBenchmarkV1Flag = "voice.whisper_auto_benchmark_v1"
let voiceWhisperPolicyEngineV1Flag = "voice.whisper_policy_engine_v1"

enum VoiceFeatureFlags {
  static func isCoordinatorEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultCoordinatorEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceCoordinatorFlag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceCoordinatorFlag)
  }

  static func setCoordinatorEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceCoordinatorFlag)
  }

  static func resetCoordinatorEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceCoordinatorFlag)
  }

  static func isPcmCaptureEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultPcmCaptureEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voicePcmCaptureFlag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voicePcmCaptureFlag)
  }

  static func setPcmCaptureEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voicePcmCaptureFlag)
  }

  static func resetPcmCaptureEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voicePcmCaptureFlag)
  }

  static func isLocalWhisperRuntimeV2Enabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultLocalWhisperRuntimeV2Enabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceLocalWhisperRuntimeV2Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceLocalWhisperRuntimeV2Flag)
  }

  static func setLocalWhisperRuntimeV2Enabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceLocalWhisperRuntimeV2Flag)
  }

  static func resetLocalWhisperRuntimeV2Enabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceLocalWhisperRuntimeV2Flag)
  }

  static func isWhisperAdaptivePartialEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultWhisperAdaptivePartialEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceWhisperAdaptivePartialV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceWhisperAdaptivePartialV1Flag)
  }

  static func setWhisperAdaptivePartialEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceWhisperAdaptivePartialV1Flag)
  }

  static func resetWhisperAdaptivePartialEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceWhisperAdaptivePartialV1Flag)
  }

  static func isWhisperAutoBenchmarkEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultWhisperAutoBenchmarkEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceWhisperAutoBenchmarkV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceWhisperAutoBenchmarkV1Flag)
  }

  static func setWhisperAutoBenchmarkEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceWhisperAutoBenchmarkV1Flag)
  }

  static func resetWhisperAutoBenchmarkEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceWhisperAutoBenchmarkV1Flag)
  }

  static func isWhisperPolicyEngineEnabled(
    userDefaults: UserDefaults = .standard,
    defaultEnabled: Bool = defaultWhisperPolicyEngineEnabled
  ) -> Bool {
    guard userDefaults.object(forKey: voiceWhisperPolicyEngineV1Flag) != nil else {
      return defaultEnabled
    }
    return userDefaults.bool(forKey: voiceWhisperPolicyEngineV1Flag)
  }

  static func setWhisperPolicyEngineEnabled(
    _ enabled: Bool,
    userDefaults: UserDefaults = .standard
  ) {
    userDefaults.set(enabled, forKey: voiceWhisperPolicyEngineV1Flag)
  }

  static func resetWhisperPolicyEngineEnabled(userDefaults: UserDefaults = .standard) {
    userDefaults.removeObject(forKey: voiceWhisperPolicyEngineV1Flag)
  }

  #if DEBUG
  private static let defaultCoordinatorEnabled = true
  private static let defaultPcmCaptureEnabled = true
  private static let defaultLocalWhisperRuntimeV2Enabled = true
  private static let defaultWhisperAdaptivePartialEnabled = true
  private static let defaultWhisperAutoBenchmarkEnabled = true
  private static let defaultWhisperPolicyEngineEnabled = true
  #else
  private static let defaultCoordinatorEnabled = false
  private static let defaultPcmCaptureEnabled = false
  private static let defaultLocalWhisperRuntimeV2Enabled = false
  private static let defaultWhisperAdaptivePartialEnabled = false
  private static let defaultWhisperAutoBenchmarkEnabled = false
  private static let defaultWhisperPolicyEngineEnabled = false
  #endif
}
