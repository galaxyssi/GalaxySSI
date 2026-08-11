import SwiftUI

struct DeviceManagementView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator

  private var pairedDesktopLinks: [ServerLink] {
    store.serverLinks.filter(\.paired)
  }

  private var pairedDesktopCount: Int {
    pairedDesktopLinks.count
  }

  private var desktopOnline: Bool {
    pairedDesktopCount > 0 && coordinator.mqttClient.isConnected
  }

  private var visibleDeviceCount: Int {
    1 +
      store.customDeviceConnectors.count +
      pairedDesktopCount +
      (store.homeAssistantSettings.configured ? 1 : 0)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.device.management_title", "Device Management"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          DeviceManagementHeroView(
            title: t("signalasi.device.management_title", "Device Management"),
            subtitle: t("signalasi.device.management_subtitle", "Secure connection between people, AI, and devices"),
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .blue,
            badge: String(format: t("signalasi.device.count_devices", "%d devices"), visibleDeviceCount)
          )
          sectionTitle(t("signalasi.device.section_my_devices", "My Devices"))
          VStack(spacing: 8) {
            DeviceManagementStatusRow(
              title: t("signalasi.device.phone_agent", "Phone Agent"),
              subtitle: t("signalasi.device.phone_agent_subtitle", "This iPhone, online"),
              systemImage: "iphone",
              tint: .signalASIAccent,
              badge: t("signalasi.status.online", "Online")
            )
            DeviceManagementNavigationRow(
              title: t("signalasi.device.pc_agent", "PC Agent"),
              subtitle: t("signalasi.device.pc_agent_subtitle", "Windows backend and file service"),
              systemImage: "desktopcomputer",
              tint: .blue,
              badge: desktopStatusLabel
            ) {
              PairingView()
            }
            DeviceManagementNavigationRow(
              title: t("signalasi.device.home_assistant", "Home Assistant"),
              subtitle: t("signalasi.device.home_assistant_subtitle", "Local smart home control API"),
              systemImage: "house",
              tint: .teal,
              badge: homeAssistantStatusLabel
            ) {
              HomeAssistantSettingsView()
            }
            ForEach(store.customDeviceConnectors) { connector in
              DeviceManagementNavigationRow(
                title: connector.name,
                subtitle: t(connector.transport.displayName, connector.transport.displayName),
                systemImage: "dot.radiowaves.left.and.right",
                tint: connector.configured ? .signalASIAccent : .orange,
                badge: connector.configured
                  ? t("signalasi.status.enabled", "Enabled")
                  : t("signalasi.status.needs_setup", "Needs Setup")
              ) {
                CustomDeviceConnectorEditorView(connector: connector)
              }
            }
            DeviceManagementNavigationRow(
              title: t("signalasi.device.custom_add", "Add Custom Device"),
              subtitle: t("signalasi.device.custom_add_subtitle", "Connect a device endpoint, broker, tool, or trusted Agent"),
              systemImage: "plus",
              tint: .signalASIAccent,
              badge: "+"
            ) {
              CustomDeviceConnectorEditorView(connector: CustomDeviceConnector())
            }
          }
          if !pairedDesktopLinks.isEmpty {
            sectionTitle(t("signalasi.device.section_paired_desktops", "Paired Desktop Connections"))
            VStack(spacing: 8) {
              ForEach(pairedDesktopLinks) { link in
                DeviceManagementNavigationRow(
                  title: link.desktopName.ifBlank(t("signalasi.security_center.pc", "PC")),
                  subtitle: link.accessProfile.ifBlank(link.desktopId),
                  systemImage: "trash",
                  tint: .red,
                  badge: t("signalasi.security_center.revoke", "Revoke")
                ) {
                  SignalASIRevokeDevicePairingView(desktopId: link.desktopId)
                }
              }
            }
          }
          sectionTitle(t("signalasi.device.section_home_assistant", "Home Assistant"))
          VStack(spacing: 8) {
            DeviceManagementNavigationRow(
              title: t("signalasi.device.home_assistant", "Home Assistant"),
              subtitle: t("signalasi.device.home_assistant_subtitle", "Local smart home control API"),
              systemImage: "house.fill",
              tint: .teal,
              badge: store.homeAssistantSettings.enabled
                ? t("signalasi.status.on", "On")
                : t("signalasi.status.off", "Off")
            ) {
              HomeAssistantSettingsView()
            }
            DeviceManagementNavigationRow(
              title: t("signalasi.device.home_assistant_url", "Server URL"),
              subtitle: store.homeAssistantSettings.baseUrl.ifBlank(
                t("signalasi.device.home_assistant_url_subtitle", "Example: http://homeassistant.local:8123")
              ),
              systemImage: "link",
              tint: .teal,
              badge: t("signalasi.common.edit", "Edit")
            ) {
              HomeAssistantSettingsView()
            }
            DeviceManagementNavigationRow(
              title: t("signalasi.device.home_assistant_token", "Access Token"),
              subtitle: homeAssistantTokenSubtitle,
              systemImage: "key",
              tint: .teal,
              badge: t("signalasi.common.edit", "Edit")
            ) {
              HomeAssistantSettingsView()
            }
            DeviceManagementNavigationRow(
              title: t("signalasi.device.home_assistant_default_entity", "Default Entity"),
              subtitle: store.homeAssistantSettings.defaultEntityId.ifBlank(
                t("signalasi.device.home_assistant_default_entity_subtitle", "Example: light.living_room")
              ),
              systemImage: "lightbulb",
              tint: .teal,
              badge: t("signalasi.common.edit", "Edit")
            ) {
              HomeAssistantSettingsView()
            }
          }
          sectionTitle(t("signalasi.device.section_capabilities", "Device Capabilities"))
          VStack(spacing: 8) {
            DeviceManagementNavigationRow(
              title: t("signalasi.device.file_sync", "File Sync"),
              subtitle: t("signalasi.device.file_sync_subtitle", "Transfer images, voice, and backup files"),
              systemImage: "square.and.arrow.up.on.square",
              tint: .blue,
              badge: desktopOnline
                ? t("signalasi.status.enabled", "Enabled")
                : t("signalasi.status.needs_setup", "Needs Setup")
            ) {
              SignalASILinkDiagnosticsView()
            }
            DeviceManagementNavigationRow(
              title: t("signalasi.device.remote_control", "Control Computer"),
              subtitle: t("signalasi.device.remote_control_subtitle", "Securely view and control an authorized computer from this phone"),
              systemImage: "desktopcomputer",
              tint: .purple,
              badge: remoteControlStatusLabel
            ) {
              SignalASIDesktopControlView()
            }
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

  private var desktopStatusLabel: String {
    if desktopOnline {
      return t("signalasi.status.online", "Online")
    }
    if pairedDesktopCount > 0 {
      return t("signalasi.status.disconnected", "Disconnected")
    }
    return t("signalasi.status.needs_setup", "Needs Setup")
  }

  private var homeAssistantStatusLabel: String {
    store.homeAssistantSettings.configured
      ? t("signalasi.device.home_assistant_configured", "Configured")
      : t("signalasi.device.home_assistant_not_configured", "Not configured")
  }

  private var homeAssistantTokenSubtitle: String {
    store.homeAssistantSettings.maskedAccessToken.ifBlank(
      t("signalasi.device.home_assistant_token_subtitle", "Long-lived access token stored on this device")
    )
  }

  private var remoteControlStatusLabel: String {
    if pairedDesktopLinks.isEmpty {
      return t("signalasi.status.needs_setup", "Needs Setup")
    }
    if pairedDesktopLinks.contains(where: \.fullDesktopExecutor) {
      return t("signalasi.status.enabled", "Enabled")
    }
    return t("signalasi.status.protected", "Protected")
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

private struct DeviceManagementHeroView: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

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
            .minimumScaleFactor(0.75)
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

private struct DeviceManagementNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      DeviceManagementRowContent(
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

private struct DeviceManagementStatusRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    DeviceManagementRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: false
    )
  }
}

private struct DeviceManagementRowContent: View {
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
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      if showsDisclosure {
        Image(systemName: "chevron.right")
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
