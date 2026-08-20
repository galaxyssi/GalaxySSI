import SwiftUI

struct SignalASISmartSpacesView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  private var homeAssistant: HomeAssistantSettings {
    store.homeAssistantSettings
  }

  private var configuredCustomDeviceCount: Int {
    store.customDeviceConnectors.filter(\.configured).count
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_smart_spaces_title", "Smart Spaces"),
        leading: { SignalASIBackButton() },
        trailing: {
          Image(systemName: "house")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          metrics
          smartSpacesSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var hero: some View {
    SignalASISecurityHeroView(
      title: t("cc_home_assistant_title", "Home Assistant"),
      subtitle: homeAssistantSubtitle,
      systemImage: "house",
      tint: homeAssistant.configured ? .signalASIAccent : .orange,
      badge: homeAssistantBadge
    )
    .padding(.horizontal, 4)
  }

  private var metrics: some View {
    HStack(spacing: 8) {
      metricCard(
        value: "\(configuredCustomDeviceCount)/\(store.customDeviceConnectors.count)",
        label: t("cc_smart_spaces_metric_devices", "Devices")
      )
      metricCard(
        value: homeAssistant.enabled ? t("signalasi.status.on", "On") : t("signalasi.status.off", "Off"),
        label: t("signalasi.common.status", "Status")
      )
      metricCard(
        value: smartSpaceSecurityStatus,
        label: t("cc_metric_security", "Security")
      )
    }
  }

  private var smartSpacesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_smart_spaces_title", "Smart Spaces"))
      SignalASISecurityNavigationRow(
        title: t("signalasi.device.home_assistant", "Home Assistant"),
        subtitle: homeAssistantSubtitle,
        systemImage: "gearshape.2",
        tint: homeAssistant.configured ? .signalASIAccent : .orange,
        badge: homeAssistantBadge
      ) {
        HomeAssistantSettingsView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_home_entities_title", "Entities & Rooms"),
        subtitle: t("cc_home_entities_subtitle", "Browse lights, climate, media, sensors, and scenes"),
        systemImage: "square.grid.2x2",
        tint: homeAssistant.configured ? .signalASIAccent : .orange,
        badge: homeAssistant.configured ? t("signalasi.common.view", "View") : t("signalasi.status.needs_setup", "Needs Setup")
      ) {
        SignalASIHomeAssistantBrowserView(collection: .entities)
      }
      SignalASISecurityNavigationRow(
        title: t("cc_home_automations_title", "Scenes & Automations"),
        subtitle: t("cc_home_automations_subtitle", "Run approved Home Assistant workflows"),
        systemImage: "sparkles",
        tint: homeAssistant.configured ? .blue : .orange,
        badge: homeAssistant.configured ? t("signalasi.common.view", "View") : t("signalasi.status.needs_setup", "Needs Setup")
      ) {
        SignalASIHomeAssistantBrowserView(collection: .automations)
      }
      SignalASISecurityNavigationRow(
        title: t("cc_custom_devices_title", "Custom Devices"),
        subtitle: t("cc_custom_devices_subtitle", "HTTP, MQTT, local intents, and trusted custom connectors"),
        systemImage: "dot.radiowaves.left.and.right",
        tint: .purple,
        badge: "\(store.customDeviceConnectors.count)"
      ) {
        CustomDeviceConnectorsView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_high_risk_devices_title", "High-risk Devices"),
        subtitle: t("cc_high_risk_devices_subtitle", "Locks and security systems always require confirmation"),
        systemImage: "checkmark.shield",
        tint: .red,
        badge: t("signalasi.common.confirm", "Confirm")
      ) {
        SignalASIExecutionPolicyView()
      }
    }
  }

  private var homeAssistantSubtitle: String {
    if !homeAssistant.credentialsConfigured {
      return t("cc_home_assistant_not_configured", "Configure a local URL and access token")
    }
    if homeAssistant.configured {
      return t("cc_home_assistant_connected", "Configured and enabled; connectivity is checked when data is requested")
    }
    return t("cc_home_assistant_disabled", "Configured, but device control is turned off")
  }

  private var homeAssistantBadge: String {
    if !homeAssistant.credentialsConfigured {
      return t("cc_status_not_configured", "Not configured")
    }
    if homeAssistant.configured {
      return t("status_enabled", "Enabled")
    }
    return t("signalasi.status.off", "Off")
  }

  private var smartSpaceSecurityStatus: String {
    if !homeAssistant.credentialsConfigured {
      return t("signalasi.status.needs_setup", "Needs Setup")
    }
    if homeAssistant.configured {
      return t("cc_status_ready", "Ready")
    }
    return t("signalasi.status.off", "Off")
  }

  private func metricCard(value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
