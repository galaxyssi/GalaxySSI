import SwiftUI

struct CustomDeviceConnectorsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  private var configuredCount: Int {
    store.customDeviceConnectors.filter(\.configured).count
  }

  private var highRiskCount: Int {
    store.customDeviceConnectors.filter { $0.risk == .high }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_custom_devices_title", "Custom Devices"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("cc_custom_devices_title", "Custom Devices"),
            subtitle: t("cc_custom_devices_subtitle", "HTTP, MQTT, local intents, and trusted custom connectors"),
            systemImage: "dot.radiowaves.left.and.right",
            tint: configuredCount == store.customDeviceConnectors.count ? .galaxySSIAccent : .orange,
            badge: "\(configuredCount)/\(store.customDeviceConnectors.count)"
          )
          metricsSection
          connectorsSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var metricsSection: some View {
    HStack(spacing: 8) {
      metricCard(
        value: "\(store.customDeviceConnectors.count)",
        label: t("cc_smart_spaces_metric_devices", "Devices"),
        tint: .galaxySSIAccent
      )
      metricCard(
        value: "\(configuredCount)",
        label: t("galaxyssi.status.enabled", "Enabled"),
        tint: .galaxySSIInsightText
      )
      metricCard(
        value: "\(highRiskCount)",
        label: t("device_custom_risk", "Risk Level"),
        tint: highRiskCount == 0 ? .galaxySSIAccent : .orange
      )
    }
  }

  private var connectorsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.settings.custom_devices", "Custom Devices"))
      if store.customDeviceConnectors.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.settings.no_custom_devices", "No custom devices"),
          subtitle: t("device_custom_add_subtitle", "Connect a device endpoint, broker, tool, or trusted Agent"),
          systemImage: "tray",
          tint: .galaxySSITextSecondary,
          badge: t("galaxyssi.status.needs_setup", "Needs Setup")
        )
      } else {
        ForEach(store.customDeviceConnectors) { connector in
          GalaxySSISecurityNavigationRow(
            title: connector.name,
            subtitle: connectorSubtitle(connector),
            systemImage: connectorIcon(connector.transport),
            tint: connectorTint(connector),
            badge: connector.configured ? t("galaxyssi.status.enabled", "Enabled") : t("galaxyssi.status.needs_setup", "Needs Setup"),
            monospacedSubtitle: true
          ) {
            CustomDeviceConnectorEditorView(connector: connector)
          }
        }
      }
      GalaxySSISecurityNavigationRow(
        title: t("device_custom_add", "Add Custom Device"),
        subtitle: t("device_custom_add_subtitle", "Connect a device endpoint, broker, tool, or trusted Agent"),
        systemImage: "plus",
        tint: .galaxySSIAccent,
        badge: "+"
      ) {
        CustomDeviceConnectorEditorView(connector: CustomDeviceConnector(name: t("device_custom_default_name", "Custom Device")))
      }
    }
  }

  private func metricCard(value: String, label: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func connectorSubtitle(_ connector: CustomDeviceConnector) -> String {
    let endpoint = connector.endpoint.ifBlank(t("device_custom_endpoint_subtitle", "URL, broker URI, host:port, MAC, or contact ID"))
    return "\(t(connector.transport.displayName, connector.transport.displayName)) / \(endpoint)"
  }

  private func connectorTint(_ connector: CustomDeviceConnector) -> Color {
    if !connector.configured { return .orange }
    switch connector.risk {
    case .low: return .galaxySSIAccent
    case .medium: return .galaxySSIInsightText
    case .high: return .red
    }
  }

  private func connectorIcon(_ transport: CustomDeviceTransport) -> String {
    switch transport {
    case .httpRest, .websocket:
      return "network"
    case .mqtt:
      return "antenna.radiowaves.left.and.right"
    case .tcp, .udp:
      return "cable.connector"
    case .mcp:
      return "shippingbox"
    case .galaxySSIAgent:
      return "person.crop.circle.badge.checkmark"
    case .ble:
      return "dot.radiowaves.left.and.right"
    case .matterThread:
      return "house.lodge"
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct CustomDeviceConnectorEditorView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.dismiss) private var dismiss

  @State private var draft: CustomDeviceConnector
  @State private var statusMessage = ""
  private let originalId: String

  init(connector: CustomDeviceConnector) {
    _draft = State(initialValue: connector)
    originalId = connector.id
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("device_custom_editor_title", "Custom Device Connector"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.common.status", "Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
            )
          }
          connectionSection
          authenticationSection
          safetySection
          actionSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var hero: some View {
    GalaxySSISecurityHeroView(
      title: draft.name.ifBlank(t("device_custom_default_name", "Custom Device")),
      subtitle: t("device_custom_editor_subtitle", "Encrypted transport and execution configuration"),
      systemImage: connectorIcon(draft.transport),
      tint: draft.configured ? connectorTint : .orange,
      badge: draft.configured ? t("galaxyssi.status.enabled", "Enabled") : t("galaxyssi.status.needs_setup", "Needs Setup")
    )
    .padding(.horizontal, 4)
  }

  private var connectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("device_custom_section_connection", "Connection"))
      textFieldRow(
        title: t("device_custom_name", "Device Name"),
        subtitle: t("device_custom_default_name", "Custom Device"),
        systemImage: "tag",
        text: stringBinding(\.name)
      )
      menuRow(
        title: t("device_custom_transport", "Transport"),
        subtitle: t("device_custom_transport_subtitle", "HTTP, MQTT, WebSocket, TCP, UDP, MCP, Agent, BLE, or Matter"),
        systemImage: connectorIcon(draft.transport),
        badge: t(draft.transport.displayName, draft.transport.displayName),
        tint: .galaxySSIInsightText
      ) {
        ForEach(CustomDeviceTransport.allCases) { transport in
          Button(t(transport.displayName, transport.displayName)) {
            draft.transport = transport
          }
        }
      }
      textFieldRow(
        title: t("device_custom_endpoint", "Endpoint"),
        subtitle: t("device_custom_endpoint_subtitle", "URL, broker URI, host:port, MAC, or contact ID"),
        systemImage: "link",
        text: stringBinding(\.endpoint),
        monospaced: true
      )
      textFieldRow(
        title: t("device_custom_target", "Command Target"),
        subtitle: t("device_custom_target_subtitle", "Topic, MCP tool, characteristic, or verified contact ID"),
        systemImage: "scope",
        text: stringBinding(\.commandTarget),
        monospaced: true
      )
    }
  }

  private var authenticationSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.device.section_authentication", "Authentication"))
      textFieldRow(
        title: t("device_custom_username", "Username"),
        subtitle: t("device_custom_username", "Username"),
        systemImage: "person.crop.circle",
        text: stringBinding(\.username),
        monospaced: true
      )
      secureFieldRow(
        title: t("device_custom_token", "Token or Password"),
        subtitle: draft.maskedAuthToken.ifBlank(t("device_custom_token", "Token or Password")),
        systemImage: "key",
        text: stringBinding(\.authToken)
      )
    }
  }

  private var safetySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("device_custom_section_safety", "Safety"))
      menuRow(
        title: t("device_custom_risk", "Risk Level"),
        subtitle: t("device_custom_risk_subtitle", "High-risk connectors always require secondary confirmation"),
        systemImage: "exclamationmark.shield",
        badge: t(draft.risk.displayName, draft.risk.displayName),
        tint: connectorTint
      ) {
        ForEach(CustomDeviceRisk.allCases) { risk in
          Button(t(risk.displayName, risk.displayName)) {
            draft.risk = risk
          }
        }
      }
      CustomDeviceToggleRow(
        title: t("device_custom_enabled", "Connector Enabled"),
        subtitle: t("device_custom_enabled_subtitle", "Allow this connector to appear as an Agent device target"),
        systemImage: "power",
        tint: draft.enabled ? .galaxySSIAccent : .orange,
        isOn: boolBinding(\.enabled)
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.common.status", "Status"),
        subtitle: draft.configured
          ? t("device_custom_save_subtitle", "Encrypt and register this connector")
          : t("device_custom_required", "Device name and endpoint are required"),
        systemImage: draft.configured ? "checkmark.circle" : "exclamationmark.triangle",
        tint: draft.configured ? .galaxySSIAccent : .orange,
        badge: draft.configured ? t("galaxyssi.status.ready", "Ready") : t("galaxyssi.status.needs_setup", "Needs Setup")
      )
    }
  }

  private var actionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.common.actions", "Actions"))
      GalaxySSISecurityPrimaryButton(
        title: t("common_save", "Save"),
        systemImage: "checkmark.circle",
        tint: draft.configured ? .galaxySSIAccent : .gray
      ) {
        save()
      }
      .disabled(!draft.configured)

      if store.customDeviceConnectors.contains(where: { $0.id == originalId }) {
        Button(role: .destructive) {
          store.deleteCustomDeviceConnector(id: originalId)
          dismiss()
        } label: {
          GalaxySSISecurityRowContent(
            title: t("common_delete", "Delete"),
            subtitle: t("device_custom_delete_subtitle", "Remove the connector and its stored credentials"),
            systemImage: "trash",
            tint: .red,
            badge: t("common_delete", "Delete"),
            monospacedSubtitle: false,
            showsDisclosure: false
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var connectorTint: Color {
    switch draft.risk {
    case .low: return .galaxySSIAccent
    case .medium: return .galaxySSIInsightText
    case .high: return .red
    }
  }

  private func textFieldRow(
    title: String,
    subtitle: String,
    systemImage: String,
    text: Binding<String>,
    monospaced: Bool = false
  ) -> some View {
    CustomDeviceInputShell(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: .galaxySSIInsightText
    ) {
      TextField(subtitle, text: text)
        .font(monospaced ? .system(size: 14, design: .monospaced) : .system(size: 15))
        .foregroundColor(.galaxySSITextPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
    }
  }

  private func secureFieldRow(
    title: String,
    subtitle: String,
    systemImage: String,
    text: Binding<String>
  ) -> some View {
    CustomDeviceInputShell(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: .galaxySSIInsightText
    ) {
      SecureField(subtitle, text: text)
        .font(.system(size: 14, design: .monospaced))
        .foregroundColor(.galaxySSITextPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
    }
  }

  private func menuRow<MenuContent: View>(
    title: String,
    subtitle: String,
    systemImage: String,
    badge: String,
    tint: Color,
    @ViewBuilder menuContent: () -> MenuContent
  ) -> some View {
    Menu {
      menuContent()
    } label: {
      GalaxySSISecurityRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: false,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }

  private func save() {
    guard draft.configured else {
      statusMessage = t("device_custom_required", "Device name and endpoint are required")
      return
    }
    store.upsertCustomDeviceConnector(draft)
    statusMessage = t("common_saved", "Saved")
    dismiss()
  }

  private func connectorIcon(_ transport: CustomDeviceTransport) -> String {
    switch transport {
    case .httpRest, .websocket:
      return "network"
    case .mqtt:
      return "antenna.radiowaves.left.and.right"
    case .tcp, .udp:
      return "cable.connector"
    case .mcp:
      return "shippingbox"
    case .galaxySSIAgent:
      return "person.crop.circle.badge.checkmark"
    case .ble:
      return "dot.radiowaves.left.and.right"
    case .matterThread:
      return "house.lodge"
    }
  }

  private func boolBinding(_ keyPath: WritableKeyPath<CustomDeviceConnector, Bool>) -> Binding<Bool> {
    Binding(
      get: { draft[keyPath: keyPath] },
      set: { draft[keyPath: keyPath] = $0 }
    )
  }

  private func stringBinding(_ keyPath: WritableKeyPath<CustomDeviceConnector, String>) -> Binding<String> {
    Binding(
      get: { draft[keyPath: keyPath] },
      set: { draft[keyPath: keyPath] = $0 }
    )
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct CustomDeviceInputShell<Content: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  let content: Content

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.content = content()
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.16))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 42, height: 42)

      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        content
          .padding(.vertical, 6)
          .padding(.horizontal, 8)
          .background(Color.galaxySSIPageBackground)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct CustomDeviceToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var isOn: Binding<Bool>

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
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: isOn)
        .labelsHidden()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
