import SwiftUI

struct CustomDeviceConnectorsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  private var configuredCount: Int {
    store.customDeviceConnectors.filter(\.configured).count
  }

  private var highRiskCount: Int {
    store.customDeviceConnectors.filter { $0.risk == .high }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_custom_devices_title", "Custom Devices"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("cc_custom_devices_title", "Custom Devices"),
            subtitle: t("cc_custom_devices_subtitle", "HTTP, MQTT, local intents, and trusted custom connectors"),
            systemImage: "dot.radiowaves.left.and.right",
            tint: configuredCount == store.customDeviceConnectors.count ? .signalASIAccent : .orange,
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var metricsSection: some View {
    HStack(spacing: 8) {
      metricCard(
        value: "\(store.customDeviceConnectors.count)",
        label: t("cc_smart_spaces_metric_devices", "Devices"),
        tint: .signalASIAccent
      )
      metricCard(
        value: "\(configuredCount)",
        label: t("signalasi.status.enabled", "Enabled"),
        tint: .signalASIInsightText
      )
      metricCard(
        value: "\(highRiskCount)",
        label: t("device_custom_risk", "Risk Level"),
        tint: highRiskCount == 0 ? .signalASIAccent : .orange
      )
    }
  }

  private var connectorsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.settings.custom_devices", "Custom Devices"))
      if store.customDeviceConnectors.isEmpty {
        SignalASISecurityStatusRow(
          title: t("signalasi.settings.no_custom_devices", "No custom devices"),
          subtitle: t("device_custom_add_subtitle", "Connect a device endpoint, broker, tool, or trusted Agent"),
          systemImage: "tray",
          tint: .signalASITextSecondary,
          badge: t("signalasi.status.needs_setup", "Needs Setup")
        )
      } else {
        ForEach(store.customDeviceConnectors) { connector in
          SignalASISecurityNavigationRow(
            title: connector.name,
            subtitle: connectorSubtitle(connector),
            systemImage: connectorIcon(connector.transport),
            tint: connectorTint(connector),
            badge: connector.configured ? t("signalasi.status.enabled", "Enabled") : t("signalasi.status.needs_setup", "Needs Setup"),
            monospacedSubtitle: true
          ) {
            CustomDeviceConnectorEditorView(connector: connector)
          }
        }
      }
      SignalASISecurityNavigationRow(
        title: t("device_custom_add", "Add Custom Device"),
        subtitle: t("device_custom_add_subtitle", "Connect a device endpoint, broker, tool, or trusted Agent"),
        systemImage: "plus",
        tint: .signalASIAccent,
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

  private func connectorSubtitle(_ connector: CustomDeviceConnector) -> String {
    let endpoint = connector.endpoint.ifBlank(t("device_custom_endpoint_subtitle", "URL, broker URI, host:port, MAC, or contact ID"))
    return "\(t(connector.transport.displayName, connector.transport.displayName)) / \(endpoint)"
  }

  private func connectorTint(_ connector: CustomDeviceConnector) -> Color {
    if !connector.configured { return .orange }
    switch connector.risk {
    case .low: return .signalASIAccent
    case .medium: return .signalASIInsightText
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
    case .signalASIAgent:
      return "person.crop.circle.badge.checkmark"
    case .ble:
      return "dot.radiowaves.left.and.right"
    case .matterThread:
      return "house.lodge"
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct CustomDeviceConnectorEditorView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
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
      SignalASITopBar(
        title: t("device_custom_editor_title", "Custom Device Connector"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.common.status", "Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var hero: some View {
    SignalASISecurityHeroView(
      title: draft.name.ifBlank(t("device_custom_default_name", "Custom Device")),
      subtitle: t("device_custom_editor_subtitle", "Encrypted transport and execution configuration"),
      systemImage: connectorIcon(draft.transport),
      tint: draft.configured ? connectorTint : .orange,
      badge: draft.configured ? t("signalasi.status.enabled", "Enabled") : t("signalasi.status.needs_setup", "Needs Setup")
    )
    .padding(.horizontal, 4)
  }

  private var connectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("device_custom_section_connection", "Connection"))
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
        tint: .signalASIInsightText
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
      SignalASISecuritySectionTitle(title: t("signalasi.device.section_authentication", "Authentication"))
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
      SignalASISecuritySectionTitle(title: t("device_custom_section_safety", "Safety"))
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
        tint: draft.enabled ? .signalASIAccent : .orange,
        isOn: boolBinding(\.enabled)
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.common.status", "Status"),
        subtitle: draft.configured
          ? t("device_custom_save_subtitle", "Encrypt and register this connector")
          : t("device_custom_required", "Device name and endpoint are required"),
        systemImage: draft.configured ? "checkmark.circle" : "exclamationmark.triangle",
        tint: draft.configured ? .signalASIAccent : .orange,
        badge: draft.configured ? t("signalasi.status.ready", "Ready") : t("signalasi.status.needs_setup", "Needs Setup")
      )
    }
  }

  private var actionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.common.actions", "Actions"))
      SignalASISecurityPrimaryButton(
        title: t("common_save", "Save"),
        systemImage: "checkmark.circle",
        tint: draft.configured ? .signalASIAccent : .gray
      ) {
        save()
      }
      .disabled(!draft.configured)

      if store.customDeviceConnectors.contains(where: { $0.id == originalId }) {
        Button(role: .destructive) {
          store.deleteCustomDeviceConnector(id: originalId)
          dismiss()
        } label: {
          SignalASISecurityRowContent(
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
    case .low: return .signalASIAccent
    case .medium: return .signalASIInsightText
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
      tint: .signalASIInsightText
    ) {
      TextField(subtitle, text: text)
        .font(monospaced ? .system(size: 14, design: .monospaced) : .system(size: 15))
        .foregroundColor(.signalASITextPrimary)
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
      tint: .signalASIInsightText
    ) {
      SecureField(subtitle, text: text)
        .font(.system(size: 14, design: .monospaced))
        .foregroundColor(.signalASITextPrimary)
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
      SignalASISecurityRowContent(
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
    case .signalASIAgent:
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
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
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        content
          .padding(.vertical, 6)
          .padding(.horizontal, 8)
          .background(Color.signalASIPageBackground)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    .background(Color.signalASISurface)
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
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
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
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
