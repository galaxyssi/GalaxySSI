import Foundation

enum GalaxySSIHealthAtlasFunctionText {
  static func get(_ key: String, _ language: String, bundle: Bundle = .main) -> String {
    func value(_ locale: String, fallback: String) -> String {
      guard let path = bundle.path(forResource: locale, ofType: "lproj"), let localized = Bundle(path: path) else { return fallback }
      return localized.localizedString(forKey: key, value: fallback, table: "AtlasFunction")
    }
    let english = value("en", fallback: GalaxySSIHealthAtlasText.get(key, "en"))
    return value(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
  }
}
