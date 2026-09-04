import Foundation
import SwiftUI

struct GalaxySSILanguageSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var confirmationMessage: String?
  @State private var confirmationMessageID = UUID()

  var body: some View {
    ZStack(alignment: .bottom) {
      VStack(spacing: 0) {
        GalaxySSITopBar(
          title: t("galaxyssi.language_policy.title", "Voice & Language"),
          leading: {
            GalaxySSIBackButton()
          },
          trailing: {
            Color.clear
          }
        )
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            LanguageSettingsHeroView(
              title: t("galaxyssi.language_policy.title", "Voice & Language"),
              subtitle: t(
                "galaxyssi.language_policy.subtitle",
                "Manage interface, model reply, ASR, and TTS languages in one place."
              ),
              badge: languagePolicySummary,
              systemImage: "globe",
              tint: .galaxySSIAccent
            )

            sectionTitle(t("galaxyssi.language_policy.interface_section", "Interface language"))
            VStack(spacing: 8) {
              ForEach(interfaceChoices) { choice in
                LanguageSettingsOptionRow(
                  title: choice.title,
                  subtitle: choice.subtitle,
                  systemImage: choice.systemImage,
                  tint: choice.tint,
                  badge: store.languagePolicy.interfaceLanguage == choice.value
                    ? t("galaxyssi.settings_language.selected", "Selected")
                    : t("galaxyssi.settings_language.use", "Use")
                ) {
                  setInterfaceLanguage(choice.value)
                }
              }
            }

            sectionTitle(t("galaxyssi.language_policy.voice_section", "Model & speech language"))
            VStack(spacing: 8) {
              LanguageSettingsMenuRow(
                title: t("galaxyssi.language_policy.response_language", "Model response language"),
                subtitle: t(
                  "galaxyssi.language_policy.response_subtitle",
                  "Tell every model and Agent which language to use for replies"
                ),
                systemImage: "bubble.left",
                tint: .blue,
                badge: languageFormatter.voiceCompactLabel(store.languagePolicy.responseLanguage),
                choices: voiceChoices,
                selectedValue: store.languagePolicy.responseLanguage
              ) { value in
                setResponseLanguage(value)
              }

              LanguageSettingsMenuRow(
                title: t("galaxyssi.language_policy.asr_language", "ASR language"),
                subtitle: t(
                  "galaxyssi.language_policy.asr_subtitle",
                  "Language used for on-device and system speech recognition"
                ),
                systemImage: "waveform",
                tint: .purple,
                badge: languageFormatter.voiceCompactLabel(store.languagePolicy.asrLanguage),
                choices: voiceChoices,
                selectedValue: store.languagePolicy.asrLanguage
              ) { value in
                setASRLanguage(value)
              }

              LanguageSettingsMenuRow(
                title: t("galaxyssi.language_policy.tts_language", "TTS language"),
                subtitle: t(
                  "galaxyssi.language_policy.tts_subtitle",
                  "Language and matching voice used for speech playback"
                ),
                systemImage: "speaker.wave.2",
                tint: .orange,
                badge: languageFormatter.voiceCompactLabel(store.languagePolicy.ttsLanguage),
                choices: voiceChoices,
                selectedValue: store.languagePolicy.ttsLanguage
              ) { value in
                setTTSLanguage(value)
              }
            }

            sectionTitle(t("galaxyssi.language_policy.current_section", "Current resolution"))
            VStack(spacing: 8) {
              LanguageSettingsStatusRow(
                title: t("galaxyssi.language_policy.effective_interface", "Effective interface"),
                subtitle: t(
                  "galaxyssi.language_policy.effective_interface_subtitle",
                  "Automatic mode follows system locale and Chinese time zones"
                ),
                systemImage: "textformat",
                tint: .galaxySSIAccent,
                badge: interfaceResolvedLabel
              )
              LanguageSettingsStatusRow(
                title: t("galaxyssi.language_policy.system_locale", "System locale"),
                subtitle: t("galaxyssi.language_policy.system_locale_subtitle", "Current iOS locale identifier"),
                systemImage: "iphone",
                tint: .blue,
                badge: Locale.autoupdatingCurrent.identifier.replacingOccurrences(of: "_", with: "-")
              )
              LanguageSettingsStatusRow(
                title: t("galaxyssi.language_policy.time_zone", "Time zone"),
                subtitle: t(
                  "galaxyssi.language_policy.time_zone_subtitle",
                  "Used as a fallback when the app language is Automatic"
                ),
                systemImage: "clock",
                tint: .purple,
                badge: TimeZone.autoupdatingCurrent.identifier
              )
              LanguageSettingsStatusRow(
                title: t("galaxyssi.language_policy.asr_locale", "ASR locale"),
                subtitle: t(
                  "galaxyssi.language_policy.asr_locale_subtitle",
                  "Applied to speech recognition requests"
                ),
                systemImage: "mic",
                tint: .teal,
                badge: resolvedASRLocaleIdentifier
              )
              LanguageSettingsStatusRow(
                title: t("galaxyssi.language_policy.tts_voice", "TTS voice"),
                subtitle: t(
                  "galaxyssi.language_policy.tts_voice_subtitle",
                  "Microsoft voice follows the selected TTS language when needed"
                ),
                systemImage: "speaker",
                tint: .orange,
                badge: resolvedTTSVoice
              )
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      }
      if let confirmationMessage {
        LanguageSettingsConfirmationToast(message: confirmationMessage)
          .padding(.horizontal, 12)
          .padding(.bottom, 16)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var interfaceChoices: [LanguageSettingsChoice] {
    [
      LanguageSettingsChoice(
        value: LanguagePolicySettings.auto,
        title: t("galaxyssi.settings_language.auto", "Automatic (follow system)"),
        subtitle: languageFormatter.autoResolutionDetail(
          resolvedName: languageFormatter.interfaceResolvedName(LanguagePolicySettings.auto),
          timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        ),
        systemImage: "location.circle",
        tint: .galaxySSIAccent
      ),
      LanguageSettingsChoice(
        value: LanguagePolicySettings.zhCN,
        title: t("galaxyssi.language.zh_cn", "Simplified Chinese"),
        subtitle: t("galaxyssi.language_policy.zh_cn_subtitle", "Use the Simplified Chinese interface"),
        systemImage: "character",
        tint: .red
      ),
      LanguageSettingsChoice(
        value: LanguagePolicySettings.en,
        title: t("galaxyssi.language.en", "English"),
        subtitle: t("galaxyssi.language_policy.en_subtitle", "Use the English interface"),
        systemImage: "textformat.abc",
        tint: .blue
      )
    ]
  }

  private var voiceChoices: [LanguageSettingsChoice] {
    LanguagePolicySettings.voiceChoices.map { value in
      LanguageSettingsChoice(
        value: value,
        title: languageFormatter.voiceLabel(value),
        subtitle: languageFormatter.voiceDetail(value),
        systemImage: "globe",
        tint: .blue
      )
    }
  }

  private var languageFormatter: GalaxySSILanguagePolicyFormatter {
    GalaxySSILanguagePolicyFormatter { key, fallback in
      t(key, fallback)
    }
  }

  private var languagePolicySummary: String {
    languageFormatter.statusBadge(for: store.languagePolicy)
  }

  private var interfaceResolvedLabel: String {
    languageFormatter.interfaceResolvedName(store.languagePolicy.interfaceLanguage)
  }

  private var resolvedASRLocaleIdentifier: String {
    store.languagePolicy.asrLocaleIdentifier
  }

  private var resolvedTTSVoice: String {
    LanguagePolicySettings.microsoftVoice(
      languageTag: store.languagePolicy.ttsLanguage,
      configuredVoice: store.voiceSettings.microsoftVoice
    )
  }

  private func setInterfaceLanguage(_ value: String) {
    guard store.languagePolicy.interfaceLanguage != value else { return }
    store.updateLanguagePolicy { $0.interfaceLanguage = value }
    showSavedConfirmation()
  }

  private func setResponseLanguage(_ value: String) {
    let normalized = LanguagePolicySettings.normalizeVoice(value)
    guard store.languagePolicy.responseLanguage != normalized else { return }
    store.updateLanguagePolicy { $0.responseLanguage = normalized }
    showSavedConfirmation()
  }

  private func setASRLanguage(_ value: String) {
    let normalized = LanguagePolicySettings.normalizeVoice(value)
    guard store.languagePolicy.asrLanguage != normalized else { return }
    store.updateLanguagePolicy { $0.asrLanguage = normalized }
    showSavedConfirmation()
  }

  private func setTTSLanguage(_ value: String) {
    let normalized = LanguagePolicySettings.normalizeVoice(value)
    guard store.languagePolicy.ttsLanguage != normalized else { return }
    store.updateLanguagePolicy { $0.ttsLanguage = normalized }
    showSavedConfirmation()
  }

  private func showSavedConfirmation() {
    let nextID = UUID()
    confirmationMessageID = nextID
    withAnimation(.easeOut(duration: 0.18)) {
      confirmationMessage = t("galaxyssi.language_policy.saved", "Language policy updated")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
      guard confirmationMessageID == nextID else { return }
      withAnimation(.easeIn(duration: 0.18)) {
        confirmationMessage = nil
      }
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
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
            .foregroundColor(.galaxySSITextPrimary)
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
          .foregroundColor(.galaxySSITextSecondary)
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

private struct LanguageSettingsConfirmationToast: View {
  var message: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(.galaxySSIAccent)
      Text(message)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 42)
    .frame(maxWidth: .infinity)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
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
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
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
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
