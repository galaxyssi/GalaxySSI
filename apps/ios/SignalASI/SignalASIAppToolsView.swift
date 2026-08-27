import SwiftUI
import UIKit
import UserNotifications

struct SignalASIAppToolsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var notificationsAuthorized = false
  @State private var snapshot = SignalASIAppAdapterSnapshot.empty

  private var screenExecutorReady: Bool {
    store.agentSafetySettings.screenObservationAllowed
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_app_tools_title", "Apps & Tools"),
        leading: { SignalASIBackButton() },
        trailing: {
          Image(systemName: "rectangle.3.group")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          banner
          coreModulesSection
          appServicesSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
    .onChange(of: store.agentSafetySettings.screenObservationAllowed) { _ in
      refresh()
    }
  }

  private var banner: some View {
    SignalASISecurityHeroView(
      title: String(
        format: t("cc_adapters_available", "%d app adapters available"),
        snapshot.operationalCount
      ),
      subtitle: t(
        "cc_adapters_available_subtitle",
        "Specific adapters use the safest native or accessibility route"
      ),
      systemImage: "rectangle.3.group",
      tint: screenExecutorReady ? .signalASIAccent : .orange,
      badge: "\(snapshot.operationalCount)/\(snapshot.statuses.count)"
    )
    .padding(.horizontal, 4)
  }

  private var coreModulesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_core_modules", "Core Modules"))
      SignalASISecurityNavigationRow(
        title: t("cc_manage_adapters_title", "Manage App Adapters"),
        subtitle: t(
          "cc_manage_adapters_subtitle",
          "Permissions, data boundaries, and per-app confirmation rules"
        ),
        systemImage: "rectangle.3.group",
        tint: .blue,
        badge: "\(snapshot.operationalCount)"
      ) {
        SignalASIAppAdaptersView()
      }
      SignalASISecurityActionRow(
        title: t("cc_accessibility_executor_title", "Universal App Executor"),
        subtitle: t(
          "cc_accessibility_executor_subtitle",
          "Understand UI and perform verified tap, input, and scroll actions"
        ),
        systemImage: "hand.tap",
        tint: screenExecutorReady ? .signalASIAccent : .orange,
        badge: screenExecutorReady ? t("status_enabled", "Enabled") : t("signalasi.status.needs_setup", "Needs Setup")
      ) {
        openAppSettings()
      }
    }
  }

  private var appServicesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_app_services", "Apps & Services"))
      SignalASISecurityNavigationRow(
        title: t("cc_messages_title", "Messages"),
        subtitle: t(
          "cc_messages_subtitle",
          "Conversations, media, delivery, and background connection"
        ),
        systemImage: "bubble.left.and.bubble.right",
        tint: .signalASIAccent,
        badge: ""
      ) {
        ChatListView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_contacts_title", "Contacts"),
        subtitle: t("cc_contacts_subtitle", "People, Agents, models, devices, and remarks"),
        systemImage: "person.2",
        tint: .blue,
        badge: ""
      ) {
        SignalASIConversationHubView(initialTab: .contacts)
      }
      SignalASISecurityNavigationRow(
        title: t("cc_discover_title", "Discover"),
        subtitle: t("cc_discover_subtitle", "Agents, cloud providers, devices, and extensions"),
        systemImage: "safari",
        tint: .purple,
        badge: ""
      ) {
        DiscoverView()
      }
    }
  }

  private func refresh() {
    snapshot = SignalASIAppAdapterCatalog.snapshot(
      screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
      notificationsAuthorized: notificationsAuthorized
    )
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let granted = settings.authorizationStatus == .authorized ||
        settings.authorizationStatus == .provisional ||
        settings.authorizationStatus == .ephemeral
      DispatchQueue.main.async {
        notificationsAuthorized = granted
        snapshot = SignalASIAppAdapterCatalog.snapshot(
          screenObservationAllowed: store.agentSafetySettings.screenObservationAllowed,
          notificationsAuthorized: granted
        )
      }
    }
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
