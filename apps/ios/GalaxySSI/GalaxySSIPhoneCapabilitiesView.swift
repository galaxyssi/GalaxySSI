import SwiftUI

struct GalaxySSIPhoneCapabilitiesView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage

  private var capabilityStatuses: [AgentPhoneCapabilityStatus] {
    AgentPhoneCapabilityCatalog.declaredStatuses()
  }

  private var nativeTools: [AgentNativeToolDescriptor] {
    AgentPhoneNativeToolCatalog.descriptors(capabilityStatuses: capabilityStatuses)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_phone_title", "Phone Capabilities"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Image(systemName: "iphone")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .frame(width: 44, height: 44)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          banner
          deviceControlSection
          informationSystemSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var banner: some View {
    let tone: Color = attentionCount == 0 ? .galaxySSIAccent : .orange
    return HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tone.opacity(0.16))
        Image(systemName: "iphone")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(tone)
      }
      .frame(width: 48, height: 48)
      VStack(alignment: .leading, spacing: 4) {
        Text(String(format: t("cc_phone_ready_title", "%d phone capabilities available"), availableToolCount))
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Text(String(format: t("cc_phone_ready_subtitle", "%d require permission or device setup"), attentionCount))
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var deviceControlSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_device_control", "Device Control"))
      capabilityRow(
        title: t("cc_camera_flash_title", "Camera & Flash"),
        subtitle: t("cc_camera_flash_subtitle", "Visible capture and flashlight actions stay user-visible"),
        systemImage: "camera",
        tint: .orange,
        keywords: ["camera", "torch", "flash"]
      )
      capabilityRow(
        title: t("cc_audio_title", "Audio"),
        subtitle: t("cc_audio_subtitle", "Microphone, media playback, and bounded audio status"),
        systemImage: "waveform",
        tint: .blue,
        keywords: ["audio", "volume", "microphone", "media"]
      )
      capabilityRow(
        title: t("cc_alarm_timer_title", "Alarm & Timer"),
        subtitle: t("cc_alarm_timer_subtitle", "Timer and reminder style actions are explicit handoffs on iOS"),
        systemImage: "clock",
        tint: .galaxySSIAccent,
        keywords: ["alarm", "timer", "reminder"]
      )
      capabilityRow(
        title: t("cc_network_title", "Network & Radios"),
        subtitle: t("cc_network_subtitle", "Wi-Fi, Bluetooth, NFC, VPN, and network status are bounded by iOS"),
        systemImage: "antenna.radiowaves.left.and.right",
        tint: .purple,
        keywords: ["network", "wifi", "wi-fi", "bluetooth", "nfc", "vpn"]
      )
    }
  }

  private var informationSystemSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_information_system", "Information System"))
      capabilityRow(
        title: t("cc_device_status_title", "Device Status"),
        subtitle: t("cc_device_status_subtitle", "Battery, memory, storage, network, and power state"),
        systemImage: "iphone",
        tint: .galaxySSIAccent,
        keywords: ["device.status", "battery", "memory", "ram", "storage", "network", "wifi", "power"]
      )
      capabilityRow(
        title: t("cc_location_title", "Location"),
        subtitle: t("cc_location_subtitle", "Foreground location reads require user permission and purpose"),
        systemImage: "location",
        tint: .orange,
        keywords: ["location"]
      )
      GalaxySSISecurityNavigationRow(
        title: t("cc_tool_catalog_title", "Native Tool Catalog"),
        subtitle: t("cc_tool_catalog_subtitle", "Review iOS tool availability, risk, permissions, and consent boundaries"),
        systemImage: "wrench.and.screwdriver",
        tint: .galaxySSITextSecondary,
        badge: "\(nativeTools.count)"
      ) {
        GalaxySSINativeToolCatalogView()
      }
    }
  }

  private func capabilityRow(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    keywords: [String]
  ) -> some View {
    GalaxySSISecurityNavigationRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: phoneCapabilityStatus(keywords: keywords)
    ) {
      GalaxySSINativeToolCatalogView()
    }
  }

  private var availableToolCount: Int {
    nativeTools.filter(isExecutable).count
  }

  private var attentionCount: Int {
    max(nativeTools.count - availableToolCount, 0)
  }

  private func phoneCapabilityStatus(keywords: [String]) -> String {
    let matching = nativeTools.filter { tool in
      let haystack = ([tool.id, tool.title] + Array(tool.capabilities)).joined(separator: " ").lowercased()
      return keywords.contains { haystack.contains($0.lowercased()) }
    }
    guard !matching.isEmpty else {
      return t("cc_status_not_configured", "Not configured")
    }
    let available = matching.filter(isExecutable).count
    if available == matching.count {
      return t("cc_status_available", "Available")
    }
    if available > 0 {
      return String(format: t("cc_status_available_ratio", "%d/%d available"), available, matching.count)
    }
    if matching.contains(where: { $0.availability.status == .requiresSetup }) {
      return t("galaxyssi.status.needs_setup", "Needs Setup")
    }
    return t("cc_status_unavailable", "Unavailable")
  }

  private func isExecutable(_ tool: AgentNativeToolDescriptor) -> Bool {
    tool.risk != .blocked && tool.availability.status == .available
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
