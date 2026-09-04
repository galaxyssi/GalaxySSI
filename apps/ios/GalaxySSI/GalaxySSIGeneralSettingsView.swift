import SwiftUI
import UIKit
import UserNotifications

struct GalaxySSIGeneralSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_general_page_title", "General"),
        leading: {
          GalaxySSIBackButton()
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshNotificationStatus)
  }

  private var generalSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("settings_control_general", "General"))
      GalaxySSISecurityNavigationRow(
        title: t("language_policy_title", "Voice & Language"),
        subtitle: languagePolicySummary,
        systemImage: "globe",
        tint: .gray,
        badge: ""
      ) {
        GalaxySSILanguageSettingsView()
      }
      GalaxySSISecurityActionRow(
        title: t("cc_appearance_title", "Appearance"),
        subtitle: t("cc_appearance_subtitle", "Use iOS light and dark appearance"),
        systemImage: "paintpalette",
        tint: .blue,
        badge: t("cc_managed_by_ios", "iOS")
      ) {
        openAppSettings()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_text_size_title", "Text Size"),
        subtitle: textScaleSummary,
        systemImage: "textformat.size",
        tint: .gray,
        badge: ""
      ) {
        GalaxySSITextSizeSettingsView()
      }
    }
  }

  private var notificationsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_notifications_title", "Notifications"))
      GalaxySSISecurityActionRow(
        title: t("cc_notifications_title", "Notifications"),
        subtitle: t("cc_notifications_subtitle", "Agent tasks, security events, messages, and connection status"),
        systemImage: "bell.badge",
        tint: notificationsAuthorized ? .galaxySSIAccent : .orange,
        badge: notificationStatusLabel
      ) {
        handleNotifications()
      }
    }
  }

  private var aboutSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("settings_about_section", "About"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_about_title", "About"),
        subtitle: t("cc_about_subtitle", "Version, protocol, open source, and security information"),
        systemImage: "info.circle",
        tint: .gray,
        badge: "v\(appVersionName)"
      ) {
        GalaxySSIAboutView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_developer_title", "Developer Options"),
        subtitle: t("cc_developer_subtitle", "Logs, network, protocol diagnostics, and experiments"),
        systemImage: "waveform.path.ecg",
        tint: .gray,
        badge: ""
      ) {
        GalaxySSIAdvancedOptionsView()
      }
    }
  }

  private var resetSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("settings_reset_short", "Reset"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_reset_title", "Reset GalaxySSI"),
        subtitle: t("cc_reset_subtitle", "Remove identity, contacts, tasks, knowledge, and local data"),
        systemImage: "trash",
        tint: .red,
        badge: ""
      ) {
        GalaxySSIResetDataView()
      }
    }
  }

  private var languagePolicySummary: String {
    GalaxySSILanguagePolicyFormatter { key, fallback in
      t(key, fallback)
    }.summary(
      policy: store.languagePolicy,
      asrLocaleIdentifier: store.voiceSettings.preferredLocaleIdentifier
    )
  }

  private var textScaleSummary: String {
    let mode = store.displaySettings.textScale
    return "\(textScaleLabel(mode)) / \(textScaleDescription(mode))"
  }

  private var notificationsAuthorized: Bool {
    switch notificationAuthorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    default:
      return false
    }
  }

  private var notificationStatusLabel: String {
    switch notificationAuthorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return t("galaxyssi.status.enabled", "Enabled")
    case .denied:
      return t("galaxyssi.status.protected", "Protected")
    case .notDetermined:
      return t("galaxyssi.status.needs_setup", "Needs Setup")
    @unknown default:
      return t("galaxyssi.status.unknown", "Unknown")
    }
  }

  private var appVersionName: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      return "0.1.0"
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "0.1.0" : trimmed
  }

  private func handleNotifications() {
    if notificationAuthorizationStatus == .notDetermined {
      Task {
        _ = await NotificationService.requestAuthorization()
        refreshNotificationStatus()
      }
    } else {
      openAppSettings()
    }
  }

  private func refreshNotificationStatus() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationAuthorizationStatus = settings.authorizationStatus
      }
    }
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
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

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
