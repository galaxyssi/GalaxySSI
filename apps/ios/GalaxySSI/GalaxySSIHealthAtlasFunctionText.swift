import Foundation

enum GalaxySSIHealthAtlasFunctionText {
  static func get(_ key: String, _ language: String, bundle: Bundle = .main) -> String {
    func value(_ locale: String, fallback: String) -> String {
      guard let path = bundle.path(forResource: locale, ofType: "lproj"), let localized = Bundle(path: path) else { return fallback }
      let prior = localized.localizedString(forKey: key, value: fallback, table: "AtlasFunction")
      let regional = localized.localizedString(forKey: key, value: prior, table: "AtlasRegional")
      let complete = localized.localizedString(forKey: key, value: regional, table: "AtlasComplete")
      let guided = localized.localizedString(forKey: key, value: complete, table: "AtlasGuidedFunction")
      let scenes = localized.localizedString(forKey: key, value: guided, table: "AtlasSynchronizedLessons")
      let closeups = localized.localizedString(forKey: key, value: scenes, table: "AtlasMechanismCloseups")
      let cellular = localized.localizedString(forKey: key, value: closeups, table: "AtlasCellularCloseups")
      return localized.localizedString(forKey: key, value: cellular, table: "AtlasFilmCaptions")
    }
    let english = value("en", fallback: GalaxySSIHealthAtlasText.get(key, "en"))
    return value(LanguagePolicySettings.resolveInterface(language) == LanguagePolicySettings.zhCN ? "zh-Hans" : "en", fallback: english)
  }
}
