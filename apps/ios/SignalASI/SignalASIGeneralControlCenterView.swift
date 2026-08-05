import SwiftUI
import UserNotifications

struct SignalASIGeneralControlCenterView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var notificationsEnabled = false
  @State private var notificationStatusMessage = ""

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_general_page_title", "General"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          generalSection
          notificationsSection
          aboutSection
          resetSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshNotifications)
  }

  private var generalSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("settings_control_general", "General"))
      SignalASISecurityNavigationRow(
        title: t("signalasi.language_policy.title", "Voice & Language"),
        subtitle: languagePolicySummary,
        systemImage: "globe",
        tint: .gray,
        badge: ""
      ) {
        SignalASILanguageSettingsView()
      }
      SignalASISecurityStatusRow(
        title: t("cc_appearance_title", "Appearance"),
        subtitle: t("cc_appearance_subtitle_ios", "Use iOS light and dark appearance"),
        systemImage: "circle.lefthalf.filled",
        tint: .blue,
        badge: t("cc_managed_by_ios", "iOS")
      )
      SignalASISecurityNavigationRow(
        title: t("cc_text_size_title", "Text Size"),
        subtitle: textScaleSummary,
        systemImage: "textformat.size",
        tint: .gray,
        badge: ""
      ) {
        SignalASITextSizeSettingsView()
      }
    }
  }

  private var notificationsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_notifications_title", "Notifications"))
      SignalASISecurityActionRow(
        title: t("cc_notifications_title", "Notifications"),
        subtitle: notificationStatusMessage.ifBlank(t("cc_notifications_subtitle", "Agent tasks, security events, messages, and connection status")),
        systemImage: "bell.badge",
        tint: notificationsEnabled ? .signalASIAccent : .orange,
        badge: notificationsEnabled ? t("signalasi.status.allowed", "Allowed") : t("signalasi.status.needs_setup", "Needs setup")
      ) {
        requestNotifications()
      }
    }
  }

  private var aboutSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("settings_about_section", "About"))
      SignalASISecurityNavigationRow(
        title: t("cc_about_title", "About"),
        subtitle: t("cc_about_subtitle", "Version, protocol, open source, and security information"),
        systemImage: "info.circle",
        tint: .gray,
        badge: "v\(appVersionName)"
      ) {
        SignalASIAboutView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_developer_title", "Developer Options"),
        subtitle: t("cc_developer_subtitle", "Logs, network, protocol diagnostics, and experiments"),
        systemImage: "stethoscope",
        tint: .gray,
        badge: ""
      ) {
        SignalASIAdvancedOptionsView()
      }
    }
  }

  private var resetSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("settings_reset_short", "Reset"))
      SignalASISecurityNavigationRow(
        title: t("cc_reset_title", "Reset SignalASI"),
        subtitle: t("cc_reset_subtitle", "Remove identity, contacts, tasks, knowledge, and local data"),
        systemImage: "trash",
        tint: .red,
        badge: ""
      ) {
        SignalASIResetDataView()
      }
    }
  }

  private var textScaleSummary: String {
    let mode = store.displaySettings.textScale
    return "\(textScaleLabel(mode)) / \(textScaleDescription(mode))"
  }

  private func textScaleLabel(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system", "Follow system")
    case .standard:
      return t("cc_text_size_standard", "Standard")
    case .comfortable:
      return t("cc_text_size_comfortable", "Comfortable")
    case .large:
      return t("cc_text_size_large", "Large")
    case .extraLarge:
      return t("cc_text_size_extra_large", "Extra large")
    }
  }

  private func textScaleDescription(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system_subtitle", "Use the iOS text-size preference")
    case .standard:
      return t("cc_text_size_standard_subtitle", "100% - More content on screen")
    case .comfortable:
      return t("cc_text_size_comfortable_subtitle", "110% - Recommended")
    case .large:
      return t("cc_text_size_large_subtitle", "120% - Easier to read")
    case .extraLarge:
      return t("cc_text_size_extra_large_subtitle", "132% - Maximum readability")
    }
  }

  private var languagePolicySummary: String {
    let interface = interfaceLanguageDisplayName(store.languagePolicy.interfaceLanguage)
    let response = voiceLanguageDisplayName(store.languagePolicy.responseLanguage)
    return String(
      format: t("signalasi.language_policy.settings_summary", "%@ / Reply %@ / ASR %@"),
      interface,
      response,
      store.voiceSettings.preferredLocaleIdentifier
    )
  }

  private func interfaceLanguageDisplayName(_ value: String) -> String {
    switch LanguagePolicySettings.normalizeInterface(value) {
    case LanguagePolicySettings.zhCN:
      return t("signalasi.language.zh_cn", "Simplified Chinese")
    case LanguagePolicySettings.en:
      return t("signalasi.language.en", "English")
    default:
      let resolved = LanguagePolicySettings.resolveInterface(LanguagePolicySettings.auto)
      let resolvedName = resolved == LanguagePolicySettings.zhCN
        ? t("signalasi.language.zh_cn", "Simplified Chinese")
        : t("signalasi.language.en", "English")
      return String(format: t("signalasi.language.auto_format", "Automatic (%@)"), resolvedName)
    }
  }

  private func voiceLanguageDisplayName(_ value: String) -> String {
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
      return t("signalasi.language.auto", "Automatic")
    }
  }

  private var appVersionName: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      return "0.1.0"
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "0.1.0" : trimmed
  }

  private func refreshNotifications() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationsEnabled = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        notificationStatusMessage = ""
      }
    }
  }

  private func requestNotifications() {
    Task {
      let allowed = await NotificationService.requestAuthorization()
      await MainActor.run {
        notificationsEnabled = allowed
        notificationStatusMessage = allowed
          ? t("signalasi.status.allowed", "Allowed")
          : t("signalasi.status.not_allowed", "Not allowed")
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
