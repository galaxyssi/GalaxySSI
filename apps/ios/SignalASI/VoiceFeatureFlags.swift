import Foundation

let voiceCoordinatorFlag = "voice.coordinator_v1"

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

  #if DEBUG
  private static let defaultCoordinatorEnabled = true
  #else
  private static let defaultCoordinatorEnabled = false
  #endif
}
