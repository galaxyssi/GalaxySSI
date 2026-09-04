import Foundation

struct LanguagePolicySettings: Codable, Equatable {
  static let auto = "auto"
  static let zhCN = "zh-CN"
  static let en = "en"
  static let enUS = "en-US"
  static let zhHK = "zh-HK"
  static let zhTW = "zh-TW"

  static let interfaceChoices = [auto, zhCN, en]
  static let voiceChoices = [auto, zhCN, enUS, zhHK, zhTW]

  var interfaceLanguage: String
  var responseLanguage: String
  var asrLanguage: String
  var ttsLanguage: String

  init(
    interfaceLanguage: String = LanguagePolicySettings.auto,
    responseLanguage: String = LanguagePolicySettings.auto,
    asrLanguage: String = LanguagePolicySettings.auto,
    ttsLanguage: String = LanguagePolicySettings.auto
  ) {
    self.interfaceLanguage = Self.normalizeInterface(interfaceLanguage)
    self.responseLanguage = Self.normalizeVoice(responseLanguage)
    self.asrLanguage = Self.normalizeVoice(asrLanguage)
    self.ttsLanguage = Self.normalizeVoice(ttsLanguage)
  }

  static let `default` = LanguagePolicySettings()

  var asrLocaleIdentifier: String {
    Self.localeIdentifier(for: Self.resolve(asrLanguage))
  }

  enum CodingKeys: String, CodingKey {
    case interfaceLanguage = "interface_language"
    case responseLanguage = "response_language"
    case asrLanguage = "asr_language"
    case ttsLanguage = "tts_language"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      interfaceLanguage: try container.decodeIfPresent(String.self, forKey: .interfaceLanguage) ?? Self.auto,
      responseLanguage: try container.decodeIfPresent(String.self, forKey: .responseLanguage) ?? Self.auto,
      asrLanguage: try container.decodeIfPresent(String.self, forKey: .asrLanguage) ?? Self.auto,
      ttsLanguage: try container.decodeIfPresent(String.self, forKey: .ttsLanguage) ?? Self.auto
    )
  }

  static func normalizeInterface(_ value: String) -> String {
    let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return interfaceChoices.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } ?? auto
  }

  static func normalizeVoice(_ value: String) -> String {
    let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return voiceChoices.first { $0.caseInsensitiveCompare(candidate) == .orderedSame } ?? auto
  }

  static func resolve(
    _ value: String,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> String {
    let normalized = normalizeVoice(value)
    guard normalized == auto else { return normalized }
    return automaticVoiceLanguage(locale: locale, timeZone: timeZone)
  }

  static func resolveInterface(
    _ value: String,
    locale: Locale = .autoupdatingCurrent,
    timeZone: TimeZone = .autoupdatingCurrent
  ) -> String {
    let normalized = normalizeInterface(value)
    guard normalized == auto else { return normalized }
    return automaticInterfaceLanguage(locale: locale, timeZone: timeZone)
  }

  static func automaticInterfaceLanguage(locale: Locale, timeZone: TimeZone) -> String {
    if locale.languageCode?.caseInsensitiveCompare("zh") == .orderedSame {
      return zhCN
    }
    if let regionCode = locale.regionCode?.uppercased(), chineseInterfaceRegions.contains(regionCode) {
      return zhCN
    }
    if chineseInterfaceTimeZones.contains(timeZone.identifier) {
      return zhCN
    }
    return en
  }

  static func automaticVoiceLanguage(locale: Locale, timeZone: TimeZone) -> String {
    let localeTag = locale.identifier.replacingOccurrences(of: "_", with: "-")
    if locale.languageCode?.caseInsensitiveCompare("zh") == .orderedSame {
      if localeTag.range(of: "HK", options: .caseInsensitive) != nil {
        return zhHK
      }
      if localeTag.range(of: "TW", options: .caseInsensitive) != nil {
        return zhTW
      }
      return zhCN
    }
    if let regionCode = locale.regionCode?.uppercased() {
      if regionCode == "HK" || regionCode == "MO" {
        return zhHK
      }
      if regionCode == "TW" {
        return zhTW
      }
      if regionCode == "CN" {
        return zhCN
      }
    }
    switch timeZone.identifier {
    case "Asia/Hong_Kong", "Asia/Macau":
      return zhHK
    case "Asia/Taipei":
      return zhTW
    default:
      if chineseInterfaceTimeZones.contains(timeZone.identifier) {
        return zhCN
      }
      return enUS
    }
  }

  static func localeIdentifier(for languageTag: String) -> String {
    resolve(languageTag).replacingOccurrences(of: "-", with: "_")
  }

  static func displayName(_ value: String) -> String {
    switch normalizeVoice(value) {
    case zhCN: return "Simplified Chinese"
    case enUS: return "English (United States)"
    case zhHK: return "Traditional Chinese (Hong Kong)"
    case zhTW: return "Traditional Chinese (Taiwan)"
    default: return "Automatic"
    }
  }

  static func interfaceDisplayName(_ value: String) -> String {
    switch normalizeInterface(value) {
    case zhCN: return "Simplified Chinese"
    case en: return "English"
    default: return "Automatic"
    }
  }

  private static let chineseInterfaceRegions: Set<String> = [
    "CN",
    "HK",
    "MO",
    "TW"
  ]

  private static let chineseInterfaceTimeZones: Set<String> = [
    "Asia/Shanghai",
    "Asia/Chongqing",
    "Asia/Harbin",
    "Asia/Urumqi",
    "Asia/Hong_Kong",
    "Asia/Macau",
    "Asia/Taipei"
  ]

  static func modelLanguageName(_ value: String) -> String {
    let resolved = resolve(value)
    if resolved.caseInsensitiveCompare(zhCN) == .orderedSame || resolved.hasPrefix("zh-Hans") {
      return "Simplified Chinese"
    }
    if resolved.caseInsensitiveCompare(zhHK) == .orderedSame ||
       resolved.caseInsensitiveCompare(zhTW) == .orderedSame ||
       resolved.hasPrefix("zh-Hant") {
      return "Traditional Chinese"
    }
    let locale = Locale(identifier: localeIdentifier(for: resolved))
    let english = Locale(identifier: "en_US")
    return english.localizedString(forLanguageCode: locale.languageCode ?? "")?.capitalized ?? "English"
  }

  static func microsoftVoice(languageTag: String, configuredVoice: String) -> String {
    let resolved = resolve(languageTag)
    let expectedPrefix = "\(resolved.lowercased())-"
    if configuredVoice.lowercased().hasPrefix(expectedPrefix) {
      return configuredVoice
    }
    if resolved.caseInsensitiveCompare(zhHK) == .orderedSame {
      return "zh-HK-HiuMaanNeural"
    }
    if resolved.caseInsensitiveCompare(zhTW) == .orderedSame {
      return "zh-TW-HsiaoChenNeural"
    }
    if resolved.lowercased().hasPrefix("zh") {
      return "zh-CN-XiaoxiaoNeural"
    }
    return "en-US-JennyNeural"
  }
}
