import SwiftUI

struct DeviceManagementView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
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
      GalaxySSITopBar(
        title: t("galaxyssi.device.management_title", "Device Management"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          DeviceManagementHeroView(
            title: t("galaxyssi.device.management_title", "Device Management"),
            subtitle: t("galaxyssi.device.management_subtitle", "Secure connection between people, AI, and devices"),
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .blue,
            badge: String(format: t("galaxyssi.device.count_devices", "%d devices"), visibleDeviceCount)
          )
          sectionTitle(t("galaxyssi.device.section_my_devices", "My Devices"))
          VStack(spacing: 8) {
            DeviceManagementStatusRow(
              title: t("galaxyssi.device.phone_agent", "Phone Agent"),
              subtitle: t("galaxyssi.device.phone_agent_subtitle", "This iPhone, online"),
              systemImage: "iphone",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.online", "Online")
            )
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.pc_agent", "PC Agent"),
              subtitle: pcAgentSubtitle,
              systemImage: "desktopcomputer",
              tint: .blue,
              badge: desktopStatusLabel
            ) {
              PairingView()
            }
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.home_assistant", "Home Assistant"),
              subtitle: t("galaxyssi.device.home_assistant_subtitle", "Local smart home control API"),
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
                tint: connector.configured ? .galaxySSIAccent : .orange,
                badge: connector.configured
                  ? t("galaxyssi.status.enabled", "Enabled")
                  : t("galaxyssi.status.needs_setup", "Needs Setup")
              ) {
                CustomDeviceConnectorEditorView(connector: connector)
              }
            }
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.custom_add", "Add Custom Device"),
              subtitle: t("galaxyssi.device.custom_add_subtitle", "Connect a device endpoint, broker, tool, or trusted Agent"),
              systemImage: "plus",
              tint: .galaxySSIAccent,
              badge: "+"
            ) {
              CustomDeviceConnectorEditorView(connector: CustomDeviceConnector())
            }
          }
          if !pairedDesktopLinks.isEmpty {
            sectionTitle(t("galaxyssi.device.section_paired_desktops", "Paired Desktop Connections"))
            VStack(spacing: 8) {
              ForEach(pairedDesktopLinks) { link in
                DeviceManagementNavigationRow(
                  title: link.desktopName.ifBlank(t("galaxyssi.security_center.pc", "PC")),
                  subtitle: link.accessProfile.ifBlank(link.desktopId),
                  systemImage: "trash",
                  tint: .red,
                  badge: t("galaxyssi.security_center.revoke", "Revoke")
                ) {
                  GalaxySSIRevokeDevicePairingView(desktopId: link.desktopId)
                }
              }
            }
          }
          sectionTitle(t("galaxyssi.device.section_home_assistant", "Home Assistant"))
          VStack(spacing: 8) {
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.home_assistant", "Home Assistant"),
              subtitle: t("galaxyssi.device.home_assistant_subtitle", "Local smart home control API"),
              systemImage: "house.fill",
              tint: .teal,
              badge: store.homeAssistantSettings.enabled
                ? t("galaxyssi.status.on", "On")
                : t("galaxyssi.status.off", "Off")
            ) {
              HomeAssistantSettingsView()
            }
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.home_assistant_url", "Server URL"),
              subtitle: store.homeAssistantSettings.baseUrl.ifBlank(
                t("galaxyssi.device.home_assistant_url_subtitle", "Example: http://homeassistant.local:8123")
              ),
              systemImage: "link",
              tint: .teal,
              badge: t("galaxyssi.common.edit", "Edit")
            ) {
              HomeAssistantSettingsView()
            }
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.home_assistant_token", "Access Token"),
              subtitle: homeAssistantTokenSubtitle,
              systemImage: "key",
              tint: .teal,
              badge: t("galaxyssi.common.edit", "Edit")
            ) {
              HomeAssistantSettingsView()
            }
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.home_assistant_default_entity", "Default Entity"),
              subtitle: store.homeAssistantSettings.defaultEntityId.ifBlank(
                t("galaxyssi.device.home_assistant_default_entity_subtitle", "Example: light.living_room")
              ),
              systemImage: "lightbulb",
              tint: .teal,
              badge: t("galaxyssi.common.edit", "Edit")
            ) {
              HomeAssistantSettingsView()
            }
          }
          sectionTitle(t("galaxyssi.device.section_capabilities", "Device Capabilities"))
          VStack(spacing: 8) {
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.file_sync", "File Sync"),
              subtitle: t("galaxyssi.device.file_sync_subtitle", "Transfer images, voice, and backup files"),
              systemImage: "square.and.arrow.up.on.square",
              tint: .blue,
              badge: desktopOnline
                ? t("galaxyssi.status.enabled", "Enabled")
                : t("galaxyssi.status.needs_setup", "Needs Setup")
            ) {
              GalaxySSILinkDiagnosticsView()
            }
            DeviceManagementNavigationRow(
              title: t("galaxyssi.device.remote_control", "Control Computer"),
              subtitle: t("galaxyssi.device.remote_control_subtitle", "Securely view and control an authorized computer from this phone"),
              systemImage: "desktopcomputer",
              tint: .purple,
              badge: remoteControlStatusLabel
            ) {
              GalaxySSIDesktopControlView()
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var desktopStatusLabel: String {
    if desktopOnline {
      return t("galaxyssi.status.online", "Online")
    }
    if pairedDesktopCount > 0 {
      return t("galaxyssi.status.disconnected", "Disconnected")
    }
    return t("galaxyssi.status.needs_setup", "Needs Setup")
  }

  private var pcAgentSubtitle: String {
    let descriptions = pairedDesktopLinks.compactMap { link -> String? in
      let detail = link.deviceMetadata?.displayLabel ?? ""
      return detail.isEmpty ? nil : detail
    }
    return descriptions.first
      ?? t("galaxyssi.device.pc_agent_subtitle", "Windows backend and file service")
  }

  private var homeAssistantStatusLabel: String {
    store.homeAssistantSettings.configured
      ? t("galaxyssi.device.home_assistant_configured", "Configured")
      : t("galaxyssi.device.home_assistant_not_configured", "Not configured")
  }

  private var homeAssistantTokenSubtitle: String {
    store.homeAssistantSettings.maskedAccessToken.ifBlank(
      t("galaxyssi.device.home_assistant_token_subtitle", "Long-lived access token stored on this device")
    )
  }

  private var remoteControlStatusLabel: String {
    if pairedDesktopLinks.isEmpty {
      return t("galaxyssi.status.needs_setup", "Needs Setup")
    }
    if pairedDesktopLinks.contains(where: \.fullDesktopExecutor) {
      return t("galaxyssi.status.enabled", "Enabled")
    }
    return t("galaxyssi.status.protected", "Protected")
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
            .foregroundColor(.galaxySSITextPrimary)
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
          .foregroundColor(.galaxySSITextSecondary)
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
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      if showsDisclosure {
        Image(systemName: "chevron.right")
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
