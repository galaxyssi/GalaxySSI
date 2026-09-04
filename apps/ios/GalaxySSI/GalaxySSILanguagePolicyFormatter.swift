import Foundation

struct GalaxySSILanguagePolicyFormatter {
  typealias Localizer = (String, String) -> String

  private let localized: Localizer

  init(localized: @escaping Localizer) {
    self.localized = localized
  }

  func summary(policy: LanguagePolicySettings, asrLocaleIdentifier: String) -> String {
    String(
      format: t("galaxyssi.language_policy.settings_summary", "%@ / Reply %@ / ASR %@"),
      interfaceLabel(policy.interfaceLanguage),
      voiceLabel(policy.responseLanguage),
      asrLocaleIdentifier
    )
  }

  func statusBadge(for policy: LanguagePolicySettings) -> String {
    let allAuto = LanguagePolicySettings.normalizeInterface(policy.interfaceLanguage) == LanguagePolicySettings.auto &&
      LanguagePolicySettings.normalizeVoice(policy.responseLanguage) == LanguagePolicySettings.auto &&
      LanguagePolicySettings.normalizeVoice(policy.asrLanguage) == LanguagePolicySettings.auto &&
      LanguagePolicySettings.normalizeVoice(policy.ttsLanguage) == LanguagePolicySettings.auto
    return allAuto
      ? t("galaxyssi.language_policy.auto_short", "Auto")
      : t("galaxyssi.language_policy.configured_short", "Configured")
  }

  func interfaceLabel(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeInterface(value) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.en:
      return t("galaxyssi.language.en", "English")
    default:
      return effectiveLabel(resolvedName: interfaceResolvedName(value))
    }
  }

  func interfaceResolvedName(_ value: String) -> String {
    let resolved = LanguagePolicySettings.resolveInterface(value)
    switch LanguagePolicySettings.normalizeInterface(resolved) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.en:
      return t("galaxyssi.language.en", "English")
    default:
      return t("galaxyssi.language_policy.auto", "Automatic (follow system)")
    }
  }

  func voiceLabel(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("galaxyssi.language.en_us", "English (United States)")
    case LanguagePolicySettings.zhHK:
      return t("galaxyssi.language.zh_hk", "Traditional Chinese (Hong Kong)")
    case LanguagePolicySettings.zhTW:
      return t("galaxyssi.language.zh_tw", "Traditional Chinese (Taiwan)")
    default:
      return effectiveLabel(resolvedName: voiceResolvedName(value))
    }
  }

  func voiceDetail(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language_policy.zh_cn_voice_subtitle", "Reply, recognition, and speech use Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("galaxyssi.language_policy.en_us_voice_subtitle", "Reply, recognition, and speech use English")
    case LanguagePolicySettings.zhHK:
      return t("galaxyssi.language_policy.zh_hk_voice_subtitle", "Speech uses Hong Kong Traditional Chinese")
    case LanguagePolicySettings.zhTW:
      return t("galaxyssi.language_policy.zh_tw_voice_subtitle", "Speech uses Taiwan Traditional Chinese")
    default:
      return t("galaxyssi.language_policy.auto_resolution_subtitle", "Follow system locale, region, and time zone")
    }
  }

  func voiceCompactLabel(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language_policy.zh_cn_short", "zh-CN")
    case LanguagePolicySettings.enUS:
      return t("galaxyssi.language_policy.en_us_short", "English")
    case LanguagePolicySettings.zhHK:
      return t("galaxyssi.language_policy.zh_hk_short", "zh-HK")
    case LanguagePolicySettings.zhTW:
      return t("galaxyssi.language_policy.zh_tw_short", "zh-TW")
    default:
      return t("galaxyssi.language_policy.auto_short", "Auto")
    }
  }

  func autoResolutionDetail(resolvedName: String, timeZoneIdentifier: String) -> String {
    String(
      format: t("galaxyssi.language_policy.auto_resolution_detail", "Automatic - %@ / Time zone %@"),
      resolvedName,
      timeZoneIdentifier
    )
  }

  func voiceResolvedName(_ value: String) -> String {
    let resolved = LanguagePolicySettings.resolve(value)
    switch LanguagePolicySettings.normalizeVoice(resolved) {
    case LanguagePolicySettings.zhCN:
      return t("galaxyssi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("galaxyssi.language.en_us", "English (United States)")
    case LanguagePolicySettings.zhHK:
      return t("galaxyssi.language.zh_hk", "Traditional Chinese (Hong Kong)")
    case LanguagePolicySettings.zhTW:
      return t("galaxyssi.language.zh_tw", "Traditional Chinese (Taiwan)")
    default:
      return resolved
    }
  }

  private func effectiveLabel(resolvedName: String) -> String {
    String(
      format: t("galaxyssi.language_policy.effective", "Automatic - %@"),
      resolvedName
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    localized(key, fallback)
  }
}
