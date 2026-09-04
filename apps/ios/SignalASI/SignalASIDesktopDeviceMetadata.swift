import Foundation

struct SignalASIDesktopDeviceMetadata: Codable, Equatable, Hashable {
  var deviceName: String
  var manufacturer: String
  var model: String
  var platform: String
  var platformVersion: String
  var hostName: String
  var profileName: String
  var lastSeenAt: Date

  init(
    deviceName: String = "",
    manufacturer: String = "",
    model: String = "",
    platform: String = "",
    platformVersion: String = "",
    hostName: String = "",
    profileName: String = "",
    lastSeenAt: Date = Date()
  ) {
    self.deviceName = Self.clean(deviceName)
    self.manufacturer = Self.clean(manufacturer)
    self.model = Self.clean(model)
    self.platform = Self.clean(platform)
    self.platformVersion = Self.clean(platformVersion)
    self.hostName = Self.clean(hostName)
    self.profileName = Self.clean(profileName)
    self.lastSeenAt = lastSeenAt
  }

  var isEmpty: Bool {
    deviceName.isEmpty && manufacturer.isEmpty && model.isEmpty &&
      platform.isEmpty && platformVersion.isEmpty && hostName.isEmpty && profileName.isEmpty
  }

  var displayLabel: String {
    let hardware = [manufacturer, model].filter { !$0.isEmpty }.joined(separator: " ")
    let platformLabel = [platform, platformVersion].filter { !$0.isEmpty }.joined(separator: " ")
    return [hardware, platformLabel].filter { !$0.isEmpty }.joined(separator: " - ")
      .ifBlank(deviceName)
      .ifBlank(hostName)
  }

  static func from(payload: [String: Any], now: Date = Date()) -> SignalASIDesktopDeviceMetadata? {
    let device = payload.dictionary("desktop_device") ?? [:]
    let metadata = SignalASIDesktopDeviceMetadata(
      deviceName: firstValue(in: device, payload: payload, keys: ["device_name", "name"]),
      manufacturer: firstValue(in: device, payload: payload, keys: ["manufacturer", "device_manufacturer"]),
      model: firstValue(in: device, payload: payload, keys: ["model", "device_model"]),
      platform: firstValue(in: device, payload: payload, keys: ["platform"]),
      platformVersion: firstValue(in: device, payload: payload, keys: ["platform_version"]),
      hostName: firstValue(in: device, payload: payload, keys: ["host_name", "hostname"]),
      profileName: firstValue(in: device, payload: payload, keys: ["profile_name"]),
      lastSeenAt: now
    )
    return metadata.isEmpty ? nil : metadata
  }

  static func displayName(from payload: [String: Any], fallback: String = "") -> String {
    let device = payload.dictionary("desktop_device") ?? [:]
    return firstValue(in: device, payload: payload, keys: ["host_name", "hostname"])
      .ifBlank(payload.string("desktop_display_name"))
      .ifBlank(device.string("display_name"))
      .ifBlank(payload.string("desktop_name"))
      .ifBlank(fallback)
  }

  func merged(with newer: SignalASIDesktopDeviceMetadata) -> SignalASIDesktopDeviceMetadata {
    SignalASIDesktopDeviceMetadata(
      deviceName: newer.deviceName.ifBlank(deviceName),
      manufacturer: newer.manufacturer.ifBlank(manufacturer),
      model: newer.model.ifBlank(model),
      platform: newer.platform.ifBlank(platform),
      platformVersion: newer.platformVersion.ifBlank(platformVersion),
      hostName: newer.hostName.ifBlank(hostName),
      profileName: newer.profileName.ifBlank(profileName),
      lastSeenAt: newer.lastSeenAt
    )
  }

  private static func firstValue(
    in device: [String: Any],
    payload: [String: Any],
    keys: [String]
  ) -> String {
    for key in keys {
      let nested = clean(device[key] as? String)
      if !nested.isEmpty { return nested }
      let root = clean(payload[key] as? String)
      if !root.isEmpty { return root }
    }
    return ""
  }

  private static func clean(_ value: String?) -> String {
    String((value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
  }
}
