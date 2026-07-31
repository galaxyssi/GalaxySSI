import Foundation

let voiceCoordinatorFlag = "voice.coordinator_v1"
let voicePcmCaptureFlag = "voice.audio_record_pcm_v1"

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

  #if DEBUG
  private static let defaultCoordinatorEnabled = true
  private static let defaultPcmCaptureEnabled = true
  #else
  private static let defaultCoordinatorEnabled = false
  private static let defaultPcmCaptureEnabled = false
  #endif
}
