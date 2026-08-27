import Foundation
import UIKit

struct SignalASILocalDeviceProfile {
  let deviceId: String
  let displayName: String
  let deviceName: String
  let manufacturer: String
  let model: String
  let platformVersion: String
  let profileName: String
}

enum SignalASIDeviceIdentity {
  static func current(profile: SignalASIProfile) -> SignalASILocalDeviceProfile {
    let model = clean(UIDevice.current.model)
    let configuredName = clean(UIDevice.current.name)
    let deviceName = configuredName.ifBlank(model).ifBlank("iPhone")
    let fingerprint = clean(profile.identityFingerprint)
    return SignalASILocalDeviceProfile(
      deviceId: "ios-\(fingerprint.prefix(16))",
      displayName: composeDisplayName(
        deviceName: deviceName,
        model: model,
        profileName: profile.name,
        fingerprint: fingerprint
      ),
      deviceName: deviceName,
      manufacturer: "Apple",
      model: model,
      platformVersion: clean(UIDevice.current.systemVersion),
      profileName: profileName
    )
  }

  static func composeDisplayName(
    deviceName: String,
    model: String,
    profileName: String,
    fingerprint: String
  ) -> String {
    normalizedDisplayName(rawDisplayName(
      deviceName: deviceName,
      model: model,
      profileName: profileName,
      fingerprint: fingerprint
    ))
  }

  private static func rawDisplayName(
    deviceName: String,
    model: String,
    profileName: String,
    fingerprint: String
  ) -> String {
    let base = clean(deviceName).ifBlank(clean(model)).ifBlank("iPhone")
    let suffix = fingerprint.filter { $0.isLetter || $0.isNumber }.suffix(4).uppercased()
    return suffix.isEmpty ? base : "\(base) · \(suffix)"
  }

  private static func normalizedDisplayName(_ value: String) -> String {
    value.replacingOccurrences(of: "\u{8DEF}", with: "\u{00B7}")
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .prefix(48)
      .description
  }
}
