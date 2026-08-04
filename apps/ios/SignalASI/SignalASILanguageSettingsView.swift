import SwiftUI

struct SignalASILanguageSettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.language_policy.title", "Voice & Language"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          LanguageSettingsHeroView(
            title: t("signalasi.language_policy.title", "Voice & Language"),
            subtitle: t(
              "signalasi.language_policy.subtitle",
              "Manage interface, model reply, ASR, and TTS languages in one place."
            ),
            badge: languagePolicySummary,
            systemImage: "globe",
            tint: .signalASIAccent
          )

          sectionTitle(t("signalasi.language_policy.interface_section", "Interface language"))
          VStack(spacing: 8) {
            ForEach(interfaceChoices) { choice in
              LanguageSettingsOptionRow(
                title: choice.title,
                subtitle: choice.subtitle,
                systemImage: choice.systemImage,
                tint: choice.tint,
                badge: store.languagePolicy.interfaceLanguage == choice.value
                  ? t("signalasi.settings_language.selected", "Selected")
                  : t("signalasi.settings_language.use", "Use")
              ) {
                setInterfaceLanguage(choice.value)
              }
            }
          }

          sectionTitle(t("signalasi.language_policy.voice_section", "Model & speech language"))
          VStack(spacing: 8) {
            LanguageSettingsMenuRow(
              title: t("signalasi.language_policy.response_language", "Model response language"),
              subtitle: t(
                "signalasi.language_policy.response_subtitle",
                "Tell every model and Agent which language to use for replies"
              ),
              systemImage: "bubble.left",
              tint: .blue,
              badge: voiceCompactLabel(store.languagePolicy.responseLanguage),
              choices: voiceChoices,
              selectedValue: store.languagePolicy.responseLanguage
            ) { value in
              store.updateLanguagePolicy { $0.responseLanguage = value }
            }

            LanguageSettingsMenuRow(
              title: t("signalasi.language_policy.asr_language", "ASR language"),
              subtitle: t(
                "signalasi.language_policy.asr_subtitle",
                "Language used for on-device and system speech recognition"
              ),
              systemImage: "waveform",
              tint: .purple,
              badge: voiceCompactLabel(store.languagePolicy.asrLanguage),
              choices: voiceChoices,
              selectedValue: store.languagePolicy.asrLanguage
            ) { value in
              store.updateLanguagePolicy { $0.asrLanguage = value }
            }

            LanguageSettingsMenuRow(
              title: t("signalasi.language_policy.tts_language", "TTS language"),
              subtitle: t(
                "signalasi.language_policy.tts_subtitle",
                "Language and matching voice used for speech playback"
              ),
              systemImage: "speaker.wave.2",
              tint: .orange,
              badge: voiceCompactLabel(store.languagePolicy.ttsLanguage),
              choices: voiceChoices,
              selectedValue: store.languagePolicy.ttsLanguage
            ) { value in
              store.updateLanguagePolicy { $0.ttsLanguage = value }
            }
          }

          sectionTitle(t("signalasi.language_policy.current_section", "Current resolution"))
          VStack(spacing: 8) {
            LanguageSettingsStatusRow(
              title: t("signalasi.language_policy.effective_interface", "Effective interface"),
              subtitle: t(
                "signalasi.language_policy.effective_interface_subtitle",
                "Automatic mode follows system locale and Chinese time zones"
              ),
              systemImage: "textformat",
              tint: .signalASIAccent,
              badge: interfaceResolvedLabel
            )
            LanguageSettingsStatusRow(
              title: t("signalasi.language_policy.system_locale", "System locale"),
              subtitle: t("signalasi.language_policy.system_locale_subtitle", "Current iOS locale identifier"),
              systemImage: "iphone",
              tint: .blue,
              badge: Locale.autoupdatingCurrent.identifier.replacingOccurrences(of: "_", with: "-")
            )
            LanguageSettingsStatusRow(
              title: t("signalasi.language_policy.time_zone", "Time zone"),
              subtitle: t(
                "signalasi.language_policy.time_zone_subtitle",
                "Used as a fallback when the app language is Automatic"
              ),
              systemImage: "clock",
              tint: .purple,
              badge: TimeZone.autoupdatingCurrent.identifier
            )
            LanguageSettingsStatusRow(
              title: t("signalasi.language_policy.asr_locale", "ASR locale"),
              subtitle: t(
                "signalasi.language_policy.asr_locale_subtitle",
                "Applied to speech recognition requests"
              ),
              systemImage: "mic",
              tint: .teal,
              badge: store.voiceSettings.preferredLocaleIdentifier
            )
            LanguageSettingsStatusRow(
              title: t("signalasi.language_policy.tts_voice", "TTS voice"),
              subtitle: t(
                "signalasi.language_policy.tts_voice_subtitle",
                "Microsoft voice follows the selected TTS language when needed"
              ),
              systemImage: "speaker",
              tint: .orange,
              badge: store.voiceSettings.microsoftVoice
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var interfaceChoices: [LanguageSettingsChoice] {
    [
      LanguageSettingsChoice(
        value: LanguagePolicySettings.auto,
        title: t("signalasi.settings_language.auto", "Automatic (follow system)"),
        subtitle: String(
          format: t("signalasi.language_policy.effective", "Automatic - %@"),
          interfaceResolvedLabel
        ),
        systemImage: "location.circle",
        tint: .signalASIAccent
      ),
      LanguageSettingsChoice(
        value: LanguagePolicySettings.zhCN,
        title: t("signalasi.language.zh_cn", "Simplified Chinese"),
        subtitle: t("signalasi.language_policy.zh_cn_subtitle", "Use the Simplified Chinese interface"),
        systemImage: "character",
        tint: .red
      ),
      LanguageSettingsChoice(
        value: LanguagePolicySettings.en,
        title: t("signalasi.language.en", "English"),
        subtitle: t("signalasi.language_policy.en_subtitle", "Use the English interface"),
        systemImage: "textformat.abc",
        tint: .blue
      )
    ]
  }

  private var voiceChoices: [LanguageSettingsChoice] {
    LanguagePolicySettings.voiceChoices.map { value in
      LanguageSettingsChoice(
        value: value,
        title: voiceLanguageLabel(value),
        subtitle: value == LanguagePolicySettings.auto
          ? String(format: t("signalasi.language_policy.effective", "Automatic - %@"), voiceResolvedLabel(value))
          : voiceLanguageDetail(value),
        systemImage: "globe",
        tint: .blue
      )
    }
  }

  private var languagePolicySummary: String {
    let allAuto = store.languagePolicy.interfaceLanguage == LanguagePolicySettings.auto &&
      store.languagePolicy.responseLanguage == LanguagePolicySettings.auto &&
      store.languagePolicy.asrLanguage == LanguagePolicySettings.auto &&
      store.languagePolicy.ttsLanguage == LanguagePolicySettings.auto
    return allAuto
      ? t("signalasi.language_policy.auto_short", "Auto")
      : t("signalasi.language_policy.configured_short", "Configured")
  }

  private var interfaceResolvedLabel: String {
    let resolved = LanguagePolicySettings.resolveInterface(store.languagePolicy.interfaceLanguage)
    return resolved == LanguagePolicySettings.zhCN
      ? t("signalasi.language.zh_cn", "Simplified Chinese")
      : t("signalasi.language.en", "English")
  }

  private func setInterfaceLanguage(_ value: String) {
    guard store.languagePolicy.interfaceLanguage != value else { return }
    store.updateLanguagePolicy { $0.interfaceLanguage = value }
  }

  private func voiceLanguageLabel(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("signalasi.language.en_us", "English (United States)")
    case LanguagePolicySettings.zhHK:
      return t("signalasi.language.zh_hk", "Traditional Chinese (Hong Kong)")
    case LanguagePolicySettings.zhTW:
      return t("signalasi.language.zh_tw", "Traditional Chinese (Taiwan)")
    default:
      return t("signalasi.language_policy.auto", "Automatic (follow system)")
    }
  }

  private func voiceLanguageDetail(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language_policy.zh_cn_voice_subtitle", "Reply, recognition, and speech use Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("signalasi.language_policy.en_us_voice_subtitle", "Reply, recognition, and speech use English")
    case LanguagePolicySettings.zhHK:
      return t("signalasi.language_policy.zh_hk_voice_subtitle", "Speech uses Hong Kong Traditional Chinese")
    case LanguagePolicySettings.zhTW:
      return t("signalasi.language_policy.zh_tw_voice_subtitle", "Speech uses Taiwan Traditional Chinese")
    default:
      return String(format: t("signalasi.language_policy.effective", "Automatic - %@"), voiceResolvedLabel(value))
    }
  }

  private func voiceResolvedLabel(_ value: String) -> String {
    let resolved = LanguagePolicySettings.resolve(value)
    switch LanguagePolicySettings.normalizeVoice(resolved) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.enUS:
      return t("signalasi.language.en_us", "English (United States)")
    case LanguagePolicySettings.zhHK:
      return t("signalasi.language.zh_hk", "Traditional Chinese (Hong Kong)")
    case LanguagePolicySettings.zhTW:
      return t("signalasi.language.zh_tw", "Traditional Chinese (Taiwan)")
    default:
      return resolved
    }
  }

  private func voiceCompactLabel(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeVoice(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language_policy.zh_cn_short", "zh-CN")
    case LanguagePolicySettings.enUS:
      return t("signalasi.language_policy.en_us_short", "English")
    case LanguagePolicySettings.zhHK:
      return t("signalasi.language_policy.zh_hk_short", "zh-HK")
    case LanguagePolicySettings.zhTW:
      return t("signalasi.language_policy.zh_tw_short", "zh-TW")
    default:
      return t("signalasi.language_policy.auto_short", "Auto")
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct LanguageSettingsChoice: Identifiable {
  var value: String
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color

  var id: String { value }
}

private struct LanguageSettingsHeroView: View {
  var title: String
  var subtitle: String
  var badge: String
  var systemImage: String
  var tint: Color

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct LanguageSettingsOptionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      LanguageSettingsRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct LanguageSettingsMenuRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var choices: [LanguageSettingsChoice]
  var selectedValue: String
  var onSelect: (String) -> Void

  var body: some View {
    Menu {
      ForEach(choices) { choice in
        Button {
          onSelect(choice.value)
        } label: {
          if choice.value == selectedValue {
            Label(choice.title, systemImage: "checkmark")
          } else {
            Text(choice.title)
          }
        }
      }
    } label: {
      LanguageSettingsRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

private struct LanguageSettingsStatusRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    LanguageSettingsRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: false
    )
  }
}

private struct LanguageSettingsRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      if showsDisclosure {
        Image(systemName: "chevron.down")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
