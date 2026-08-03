import Foundation
import SwiftUI

enum SignalASILocalization {
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
}

private struct SignalASIInterfaceLanguageKey: EnvironmentKey {
  static let defaultValue = LanguagePolicySettings.resolveInterface(LanguagePolicySettings.auto)
}

extension EnvironmentValues {
  var signalASIInterfaceLanguage: String {
    get { self[SignalASIInterfaceLanguageKey.self] }
    set { self[SignalASIInterfaceLanguageKey.self] = newValue }
  }
}

extension View {
  func signalASIInterfaceLanguage(_ language: String) -> some View {
    let resolved = LanguagePolicySettings.resolveInterface(language)
    let localeIdentifier = resolved == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en"
    return environment(\.signalASIInterfaceLanguage, resolved)
      .environment(\.locale, Locale(identifier: localeIdentifier))
  }
}
