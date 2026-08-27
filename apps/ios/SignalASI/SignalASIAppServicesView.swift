import SwiftUI
import UIKit

struct SignalASIAppServicesView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator

  private var contactCount: Int {
    store.visibleContacts.count
  }

  private var backgroundStatusTitle: String {
    t(
      coordinator.mqttClient.isConnected ? "cc_status_online" : "cc_status_degraded",
      coordinator.mqttClient.isConnected ? "Online" : "Degraded"
    )
  }

  private var backgroundTint: Color {
    coordinator.mqttClient.isConnected ? .signalASIAccent : .orange
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_app_services_page_title", "Apps & Services"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          coreModulesSection
          messageSettingsSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var coreModulesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_core_modules", "Core Modules"))
      SignalASISecurityNavigationRow(
        title: t("cc_conversation_hub_title", "Conversation Hub"),
        subtitle: t(
          "cc_conversation_hub_subtitle",
          "Conversations, contacts, groups, QR pairing, and cloud models"
        ),
        systemImage: "bubble.left.and.bubble.right.fill",
        tint: .signalASIAccent,
        badge: t("cc_status_open", "Open")
      ) {
        SignalASIConversationHubView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_messages_title", "Messages"),
        subtitle: t("cc_messages_subtitle", "Conversations, media, delivery, and background connection"),
        systemImage: "bubble.left.and.bubble.right",
        tint: .signalASIAccent,
        badge: t("cc_status_normal", "Normal")
      ) {
        ChatListView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_contacts_title", "Contacts"),
        subtitle: t("cc_contacts_subtitle", "People, Agents, models, devices, and remarks"),
        systemImage: "person.2",
        tint: .blue,
        badge: "\(contactCount)"
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

  private var messageSettingsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_message_settings", "Message Settings"))
      SignalASISecurityActionRow(
        title: t("cc_background_connection_title", "Background Message Connection"),
        subtitle: t("cc_background_connection_subtitle", "Encrypted MQTT session and offline message recovery"),
        systemImage: "link",
        tint: backgroundTint,
        badge: backgroundStatusTitle
      ) {
        openAppSettings()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_chat_history_title", "Chat History"),
        subtitle: t("cc_chat_history_subtitle", "Encrypted local storage managed per conversation"),
        systemImage: "clock.arrow.circlepath",
        tint: .gray,
        badge: ""
      ) {
        SignalASIConversationHubView()
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
