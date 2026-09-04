import Foundation
import SwiftUI

enum GalaxySSILocalization {
  static func string(_ key: String, fallback: String, language: String) -> String {
    let resolved = LanguagePolicySettings.resolveInterface(language)
    guard resolved == LanguagePolicySettings.zhCN,
          let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
          let bundle = Bundle(path: path) else {
      return fallback
    }
    return bundle.localizedString(forKey: key, value: fallback, table: nil)
  }

  static func string(_ key: String, fallback: String) -> String {
    string(key, fallback: fallback, language: LanguagePolicySettings.auto)
  }

  static func interfaceLocale(language: String) -> Locale {
    Locale(identifier: interfaceLocaleIdentifier(language: language))
  }

  static func dateLocale(language: String) -> Locale {
    Locale(identifier: dateLocaleIdentifier(language: language))
  }

  static func interfaceLocaleIdentifier(language: String) -> String {
    let resolved = LanguagePolicySettings.resolveInterface(language)
    return resolved == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en"
  }

  static func dateLocaleIdentifier(language: String) -> String {
    let resolved = LanguagePolicySettings.resolveInterface(language)
    return resolved == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX"
  }
}

private struct GalaxySSIInterfaceLanguageKey: EnvironmentKey {
  static let defaultValue = LanguagePolicySettings.resolveInterface(LanguagePolicySettings.auto)
}

extension EnvironmentValues {
  var galaxySSIInterfaceLanguage: String {
    get { self[GalaxySSIInterfaceLanguageKey.self] }
    set { self[GalaxySSIInterfaceLanguageKey.self] = newValue }
  }
}

extension View {
  func galaxySSIInterfaceLanguage(_ language: String) -> some View {
    let resolved = LanguagePolicySettings.resolveInterface(language)
    return environment(\.galaxySSIInterfaceLanguage, resolved)
      .environment(\.locale, GalaxySSILocalization.interfaceLocale(language: resolved))
  }
}
