import Foundation

enum GalaxySSIGlassesWifiQR {
  static func validSSID(_ ssid: String) -> Bool {
    !ssid.isBlank && ssid.utf8.count <= 32 && ssid.rangeOfCharacter(from: .controlCharacters) == nil
  }

  static func validPassword(_ password: String) -> Bool {
    (8...63).contains(password.utf8.count) && password.utf8.allSatisfy { (32...126).contains($0) }
  }

  static func payload(ssid: String, password: String) -> String? {
    guard validSSID(ssid), validPassword(password),
          let encoded = try? JSONSerialization.data(withJSONObject: [
            "type": "galaxyssi_wifi_v1", "ssid": ssid, "passphrase": password
          ], options: [.sortedKeys]) else { return nil }
    // ASCII-only JSON preserves non-ASCII SSIDs even when a QR reader assumes a legacy encoding.
    var ascii = ""
    for unit in String(decoding: encoded, as: UTF8.self).utf16 {
      if unit < 128, let scalar = UnicodeScalar(unit) { ascii.unicodeScalars.append(scalar) }
      else { ascii += String(format: "\\u%04x", Int(unit)) }
    }
    return ascii.utf8.count <= 1_024 ? ascii : nil
  }
}
