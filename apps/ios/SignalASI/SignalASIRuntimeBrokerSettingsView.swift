import SwiftUI
import UIKit

struct SignalASIRuntimeBrokerSettingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @State private var enabled = false
  @State private var port = "\(AgentIOSRuntimeBrokerConfiguration.defaultPort)"
  @State private var pairingKey = ""
  @State private var statusMessage = ""
  @State private var statusIsFailure = false
  @State private var isChecking = false

  private let configurationStore = AgentIOSRuntimeBrokerConfigurationStore()
  private let credentials = AgentIOSRuntimeBrokerCredentials()
  private let lifecycleStore = AgentIOSRuntimeBrokerLifecycleStore()

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_runtime_broker_title", "Runtime Broker"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Button(action: save) {
            Image(systemName: "checkmark")
              .font(.system(size: 17, weight: .semibold))
              .frame(width: 36, height: 36)
          }
          .foregroundColor(.signalASIAccent)
          .accessibilityLabel(t("signalasi.common.save", "Save"))
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("cc_runtime_broker_hero_title", "Local Linux Broker"),
            subtitle: t(
              "cc_runtime_broker_hero_subtitle",
              "SignalASI connects only to a paired runtime service on this iPhone."
            ),
            systemImage: "terminal",
            tint: enabled && credentials.sessionKey() != nil ? .signalASIAccent : .orange,
            badge: enabled && credentials.sessionKey() != nil
              ? t("cc_status_ready", "Ready")
              : t("cc_status_not_configured", "Not configured")
          )
          connectionSection
          pairingSection
          statusSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: load)
  }

  private var connectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_broker_connection", "Connection"))
      RuntimeBrokerInputShell(
        title: t("cc_runtime_broker_enable", "Enable broker"),
        subtitle: t("cc_runtime_broker_enable_subtitle", "Allow paired Linux runtime requests on this device"),
        systemImage: "bolt.shield",
        tint: .signalASIAccent
      ) {
        Toggle("", isOn: $enabled)
          .labelsHidden()
      }
      RuntimeBrokerInputShell(
        title: t("cc_runtime_broker_endpoint", "Loopback endpoint"),
        subtitle: AgentIOSRuntimeBrokerConfiguration.defaultHost,
        systemImage: "network",
        tint: .blue
      ) {
        Text(AgentIOSRuntimeBrokerConfiguration.defaultHost)
          .font(.system(size: 15, design: .monospaced))
          .foregroundColor(.signalASITextSecondary)
      }
      RuntimeBrokerInputShell(
        title: t("cc_runtime_broker_port", "Port"),
        subtitle: t("cc_runtime_broker_port_subtitle", "The paired local service port"),
        systemImage: "number",
        tint: .blue
      ) {
        TextField("39761", text: $port)
          .keyboardType(.numberPad)
          .font(.system(size: 15, design: .monospaced))
          .multilineTextAlignment(.trailing)
      }
    }
  }

  private var pairingSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_broker_pairing", "Pairing"))
      RuntimeBrokerInputShell(
        title: t("cc_runtime_broker_key", "Pairing key"),
        subtitle: t("cc_runtime_broker_key_subtitle", "Base64 key stored only in the iOS Keychain"),
        systemImage: "key",
        tint: .purple
      ) {
        SecureField(t("cc_runtime_broker_key", "Pairing key"), text: $pairingKey)
          .font(.system(size: 14, design: .monospaced))
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled(true)
      }
      SignalASISecurityActionRow(
        title: t("cc_runtime_broker_generate_key", "Generate pairing key"),
        subtitle: t(
          "cc_runtime_broker_generate_key_subtitle",
          "Create and copy a new 256-bit key, then save it after configuring the broker"
        ),
        systemImage: "key.badge.plus",
        tint: .purple,
        badge: "256-bit"
      ) {
        generatePairingKey()
      }
      SignalASISecurityActionRow(
        title: t("cc_runtime_broker_clear_key", "Remove pairing key"),
        subtitle: t("cc_runtime_broker_clear_key_subtitle", "Disable this app's access to the local runtime service"),
        systemImage: "key.slash",
        tint: .red,
        badge: ""
      ) {
        credentials.clearSessionKey()
        pairingKey = ""
        statusMessage = t("cc_runtime_broker_key_removed", "Pairing key removed")
        statusIsFailure = false
      }
    }
  }

  private var statusSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_runtime_broker_status", "Broker Status"))
      SignalASISecurityActionRow(
        title: t("cc_runtime_broker_check", "Check connection"),
        subtitle: statusMessage.ifBlank(t(
          "cc_runtime_broker_check_subtitle",
          "Confirm the paired runtime service is reachable"
        )),
        systemImage: isChecking ? "arrow.triangle.2.circlepath" : "checkmark.shield",
        tint: statusIsFailure ? .orange : .signalASIAccent,
        badge: isChecking ? t("signalasi.status.loading", "Checking") : ""
      ) {
        checkConnection()
      }
      .disabled(isChecking)
    }
  }

  private func load() {
    let configuration = configurationStore.load()
    enabled = configuration.enabled
    port = String(configuration.port)
  }

  private func generatePairingKey() {
    do {
      pairingKey = try AgentIOSRuntimeBrokerPairingKey.generate()
      UIPasteboard.general.string = pairingKey
      statusMessage = t(
        "cc_runtime_broker_key_generated",
        "New pairing key generated and copied. Save to store it in the iOS Keychain."
      )
      statusIsFailure = false
    } catch {
      statusMessage = error.localizedDescription
      statusIsFailure = true
    }
  }

  private func save() {
    guard let portValue = Int(port) else {
      statusMessage = t("cc_runtime_broker_invalid_port", "Enter a valid broker port")
      statusIsFailure = true
      return
    }
    do {
      try configurationStore.save(AgentIOSRuntimeBrokerConfiguration(
        enabled: enabled,
        host: AgentIOSRuntimeBrokerConfiguration.defaultHost,
        port: portValue
      ))
      if !pairingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        try credentials.storeSessionKey(base64Encoded: pairingKey)
        pairingKey = ""
      }
      statusMessage = t("cc_runtime_broker_saved", "Runtime broker settings saved")
      statusIsFailure = false
    } catch {
      statusMessage = error.localizedDescription
      statusIsFailure = true
    }
  }

  private func checkConnection() {
    save()
    guard !statusIsFailure else { return }
    isChecking = true
    statusMessage = t("signalasi.status.loading", "Checking")
    let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    DispatchQueue.global(qos: .userInitiated).async {
      let client = AgentIOSRuntimeBrokerClient()
      let outcome: Result<AgentMcpJSONObject, Error>
      do {
        outcome = .success(try client.invoke(
          operation: .status,
          input: [:],
          context: AgentNativeToolInvocationContext(invocationId: "runtime-broker-settings-\(UUID().uuidString)"),
          deadlineEpochMillis: now + 15_000
        ))
      } catch {
        outcome = .failure(error)
      }
      DispatchQueue.main.async {
        isChecking = false
        switch outcome {
        case .success(let output):
          let isReady = output["backend_ready"]?.boolValue == true
          let message = output["reason"]?.stringValue?.nonEmpty ?? t(
            isReady ? "cc_runtime_broker_connected" : "cc_runtime_broker_unavailable",
            isReady ? "Runtime broker connected" : "The local Linux runtime service is not ready"
          )
          if isReady {
            _ = lifecycleStore.ready()
            statusMessage = message
            statusIsFailure = false
          } else {
            _ = lifecycleStore.failed(reason: message)
            statusMessage = message
            statusIsFailure = true
          }
        case .failure(let error):
          let message = error.localizedDescription.ifBlank(t(
            "cc_runtime_broker_unavailable",
            "The local Linux runtime service is not ready"
          ))
          _ = lifecycleStore.failed(reason: message)
          statusMessage = message
          statusIsFailure = true
        }
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct RuntimeBrokerInputShell<Content: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  @ViewBuilder var content: Content

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(tint)
        .frame(width: 30, height: 30)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.signalASITextPrimary)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      content
        .foregroundColor(.signalASITextPrimary)
        .frame(maxWidth: 150, alignment: .trailing)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
