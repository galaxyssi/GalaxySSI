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
      profileName: profile.name
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

enum SignalASIDeviceIdentityName {
  private static let maxDeviceNameLength = 48

  static func current(profile: SignalASIProfile) -> String {
    current(signalASIId: profile.signalASIId)
  }

  static func current(signalASIId: String) -> String {
    format(
      deviceName: UIDevice.current.name.ifBlank(UIDevice.current.model).ifBlank("iPhone"),
      signalASIId: signalASIId
    )
  }

  static func format(deviceName: String, signalASIId: String) -> String {
    let normalizedName = deviceName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .prefix(maxDeviceNameLength)
      .description
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank("iPhone")
    let identitySource = signalASIId
      .split(separator: ":", maxSplits: 1)
      .last
      .map(String.init)
      ?? signalASIId
    let identity = identitySource.filter { $0.isLetter || $0.isNumber }
    let suffix = identity.suffix(4).uppercased()
    return suffix.isEmpty ? normalizedName : "\(normalizedName) · \(suffix)"
  }

  static func isLegacyDefault(_ name: String) -> Bool {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ||
      normalized.caseInsensitiveCompare("Me") == .orderedSame ||
      normalized == "\u{6211}"
  }
}
