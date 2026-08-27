import SwiftUI
import UIKit

struct SignalASISecurityCenterView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var statusMessage = ""

  private var connectorContacts: [SignalASIContact] {
    store.contacts
      .filter { !$0.deleted && $0.deliveryMode.isSignalASILinkFamily && $0.type == "agent" }
      .sorted { lhs, rhs in
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
  }

  private var desktopSummaries: [SignalASIDesktopSecuritySummary] {
    store.serverLinks
      .sorted { lhs, rhs in
        lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
      }
      .map { link in
        SignalASIDesktopSecuritySummary(
          link: link,
          agents: connectorContacts.filter { $0.desktopId == link.desktopId }
        )
      }
  }

  private var trustedContactCount: Int {
    store.visibleContacts.filter(\.isCommunicable).count
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.security_center.title", "Security Center"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("signalasi.security_center.privacy_title", "Privacy & Security"),
            subtitle: t(
              "signalasi.security_center.privacy_subtitle",
              "End-to-end encryption; only devices and contacts with confirmed fingerprints can communicate"
            ),
            systemImage: "checkmark.shield",
            tint: .signalASIAccent,
            badge: String(
              format: t("signalasi.security_center.count_devices", "%d devices"),
              desktopSummaries.count
            )
          )
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.security_center.status", "Security Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
            )
          }
          identitySection
          pairedDevicesSection
          agentPermissionsSection
          identityProtectionSection
          messageProtectionSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.security_center.section_identity", "Identity"))
      SignalASISecurityActionRow(
        title: t("signalasi.security.phone_fingerprint", "Phone Fingerprint"),
        subtitle: SignalASISecurityFormatter.fingerprint(
          store.profile.identityFingerprint,
          unknown: t("signalasi.status.unknown", "Unknown")
        ),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: t("signalasi.common.copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.identityFingerprint, message: t("signalasi.security_center.copied_phone_fingerprint", "Phone fingerprint copied"))
      }
      SignalASISecurityActionRow(
        title: t("signalasi.security_center.signalasi_id", "SignalASI ID"),
        subtitle: store.profile.signalASIId.ifBlank(t("signalasi.status.unknown", "Unknown")),
        systemImage: "link",
        tint: .blue,
        badge: t("signalasi.common.copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.signalASIId, message: t("signalasi.security_center.copied_signalasi_id", "SignalASI ID copied"))
      }
    }
  }

  private var pairedDevicesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.security_center.section_paired_devices", "Paired Devices"))
      if desktopSummaries.isEmpty {
        SignalASISecurityNavigationRow(
          title: t("signalasi.security_center.no_paired_pc", "No paired computers yet"),
          subtitle: t(
            "signalasi.security_center.no_paired_pc_subtitle",
            "Paired desktops appear after scanning and confirming fingerprints"
          ),
          systemImage: "desktopcomputer",
          tint: .orange,
          badge: t("signalasi.security_center.scan", "Scan")
        ) {
          AddContactView(autoOpenScanner: true)
        }
      } else {
        ForEach(desktopSummaries) { summary in
          SignalASISecurityNavigationRow(
            title: summary.link.desktopName.ifBlank(t("signalasi.security_center.pc", "PC")),
            subtitle: deviceSubtitle(summary),
            systemImage: "desktopcomputer",
            tint: summary.link.paired ? .signalASIAccent : .orange,
            badge: t("signalasi.security_center.manage", "Manage"),
            monospacedSubtitle: true
          ) {
            SignalASIDeviceSecurityDetailView(desktopId: summary.link.desktopId)
          }
        }
        SignalASISecurityNavigationRow(
          title: t("cc_contacts_title", "Contacts"),
          subtitle: t("cc_contacts_subtitle", "People, Agents, models, devices, and remarks"),
          systemImage: "person.2",
          tint: .purple,
          badge: "\(trustedContactCount)"
        ) {
          SignalASIConversationHubView(initialTab: .contacts)
        }
        SignalASISecurityNavigationRow(
          title: t("signalasi.security_center.scan", "Scan"),
          subtitle: t("signalasi.discover.scan_subtitle", "Add contacts or devices"),
          systemImage: "qrcode.viewfinder",
          tint: .signalASIAccent,
          badge: "+"
        ) {
          AddContactView(autoOpenScanner: true)
        }
      }
    }
  }

  private var agentPermissionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.security_center.section_agent_permissions", "Agent Permissions"))
      SignalASISecurityNavigationRow(
        title: t("signalasi.security_center.on_device_agent_permissions", "On-device Agent Permissions"),
        subtitle: t(
          "signalasi.security_center.on_device_agent_permissions_subtitle",
          "Microphone, camera, notifications, and on-device execution require phone-side authorization"
        ),
        systemImage: "cpu",
        tint: .blue,
        badge: t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle)
      ) {
        OnDeviceAgentPermissionsView()
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.settings.execution_policy", "Execution Policy"),
        subtitle: "\(t(store.agentSafetySettings.taskExecutionMode.displayTitle, store.agentSafetySettings.taskExecutionMode.displayTitle)) / \(t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle))",
        systemImage: "exclamationmark.shield",
        tint: .orange,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIExecutionPolicyView()
      }
      ForEach(connectorContacts.prefix(8)) { contact in
        SignalASISecurityStatusRow(
          title: contact.displayName.ifBlank(contact.name).ifBlank(t("signalasi.security_center.agent", "Agent")),
          subtitle: String(
            format: t("signalasi.security_center.permission_status", "Permission: PC connector / Status: %@ / %@"),
            SignalASISecurityFormatter.securityStatusLabel(contact.setupStatus, language: interfaceLanguage),
            SignalASISecurityFormatter.time(
              contact.updatedAt,
              unknown: t("signalasi.status.unknown", "Unknown"),
              language: interfaceLanguage
            )
          ),
          systemImage: SignalASISecurityFormatter.agentSystemImage(id: contact.id, kind: contact.agentKind),
          tint: .purple,
          badge: SignalASISecurityFormatter.securityStatusLabel(contact.setupStatus, language: interfaceLanguage)
        )
      }
      if connectorContacts.count > 8 {
        SignalASISecurityStatusRow(
          title: t("signalasi.security_center.more_agents", "More Agents"),
          subtitle: String(
            format: t("signalasi.security_center.more_agents_subtitle", "%d more PC connector Agents"),
            connectorContacts.count - 8
          ),
          systemImage: "person.3",
          tint: .purple,
          badge: t("signalasi.common.view", "View")
        )
      }
    }
  }

  private var identityProtectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("feature_identity_protection", "Identity Protection"))
      SignalASISecurityActionRow(
        title: t("on_device_agent_high_risk_guard", "High-risk Guard"),
        subtitle: t("cc_always_confirm_subtitle", "Messages, calls, deletion, installation, payment, lock, and security"),
        systemImage: "checkmark.shield",
        tint: store.agentSafetySettings.highRiskGuard ? .signalASIAccent : .orange,
        badge: store.agentSafetySettings.highRiskGuard ? t("status_enabled", "Enabled") : t("common_off", "Off")
      ) {
        store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
      }
    }
  }

  private var messageProtectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("signalasi.security_center.section_message_protection", "Message Protection"))
      SignalASISecurityStatusRow(
        title: "Signal Protocol",
        subtitle: t("signalasi.security_center.signal_protocol_subtitle", "Session keys and message encryption"),
        systemImage: "lock.shield",
        tint: .blue,
        badge: "v1.0.3"
      )
      SignalASISecurityStatusRow(
        title: t("signalasi.security_center.fingerprint_confirm", "Dual Fingerprint Confirmation"),
        subtitle: t(
          "signalasi.security_center.fingerprint_confirm_subtitle",
          "First scan must manually confirm phone and computer fingerprints"
        ),
        systemImage: "checkmark.shield",
        tint: .signalASIAccent,
        badge: t("signalasi.status.enabled", "Enabled")
      )
      SignalASISecurityNavigationRow(
        title: t("signalasi.settings.model_data_sharing", "Model Data Sharing"),
        subtitle: t(
          "signalasi.settings.model_data_sharing.subtitle",
          "Review metadata-only disclosure events and destination blocks"
        ),
        systemImage: "doc.text",
        tint: .teal,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIPrivacyDashboardView()
      }
      SignalASISecurityNavigationRow(
        title: t("signalasi.security_center.revoke_all_pc", "Revoke all PC pairings"),
        subtitle: t(
          "signalasi.security_center.revoke_all_pc_subtitle",
          "After deletion, you must scan the QR code again before communication"
        ),
        systemImage: "trash",
        tint: .red,
        badge: t("signalasi.security_center.manage", "Manage")
      ) {
        SignalASIRevokeAllPCPairingsView()
      }
    }
  }

  private func deviceSubtitle(_ summary: SignalASIDesktopSecuritySummary) -> String {
    let fingerprint = SignalASISecurityFormatter.fingerprint(
      summary.link.desktopFingerprint,
      unknown: t("signalasi.status.unknown", "Unknown")
    )
    let lastActive = String(
      format: t("signalasi.security_center.last_active", "Last active %@"),
      SignalASISecurityFormatter.time(
        summary.link.updatedAt,
        unknown: t("signalasi.status.unknown", "Unknown"),
        language: interfaceLanguage
      )
    )
    return "\(fingerprint)\n\(lastActive)"
  }

  private func copy(_ value: String, message: String) {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    UIPasteboard.general.string = value
    statusMessage = message
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIDeviceSecurityDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var statusMessage = ""
  var desktopId: String

  private var link: ServerLink? {
    store.serverLinks.first { $0.desktopId == desktopId }
  }

  private var agents: [SignalASIContact] {
    store.contacts
      .filter { !$0.deleted && $0.deliveryMode.isSignalASILinkFamily && $0.type == "agent" && $0.desktopId == desktopId }
      .sorted { lhs, rhs in
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.security_center.device_detail_title", "Device Security"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let link {
            deviceContent(link)
          } else {
            revokedContent
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

  @ViewBuilder
  private func deviceContent(_ link: ServerLink) -> some View {
    SignalASISecurityHeroView(
      title: link.desktopName.ifBlank(t("signalasi.security_center.pc", "PC")),
      subtitle: t("signalasi.security_center.verified_desktop_connector", "Verified Desktop connector"),
      systemImage: "desktopcomputer",
      tint: link.paired ? .signalASIAccent : .orange,
      badge: String(format: t("signalasi.security_center.count_items", "%d items"), agents.count)
    )
    if !statusMessage.isEmpty {
      SignalASISecurityStatusRow(
        title: t("signalasi.security_center.status", "Security Status"),
        subtitle: statusMessage,
        systemImage: "checkmark.circle",
        tint: .signalASIAccent,
        badge: t("signalasi.status.ready", "Ready")
      )
    }
    SignalASISecuritySectionTitle(title: t("signalasi.security_center.section_identity", "Identity"))
    SignalASISecurityActionRow(
      title: "Desktop ID",
      subtitle: link.desktopId,
      systemImage: "link",
      tint: .blue,
      badge: t("signalasi.common.copy", "Copy"),
      monospacedSubtitle: true
    ) {
      copy(link.desktopId, message: t("signalasi.security_center.copied_desktop_id", "Desktop ID copied"))
    }
    SignalASISecurityActionRow(
      title: t("signalasi.security.desktop_fingerprint", "Computer Fingerprint"),
      subtitle: SignalASISecurityFormatter.fingerprint(
        link.desktopFingerprint,
        unknown: t("signalasi.status.unknown", "Unknown")
      ),
      systemImage: "checkmark.shield",
      tint: .signalASIAccent,
      badge: t("signalasi.common.copy", "Copy"),
      monospacedSubtitle: true
    ) {
      copy(link.desktopFingerprint, message: t("signalasi.security_center.copied_desktop_fingerprint", "Desktop fingerprint copied"))
    }
    SignalASISecurityStatusRow(
      title: t("signalasi.security_center.last_active_title", "Last active"),
      subtitle: SignalASISecurityFormatter.time(
        link.updatedAt,
        unknown: t("signalasi.status.unknown", "Unknown"),
        language: interfaceLanguage
      ),
      systemImage: "clock",
      tint: .blue,
      badge: SignalASISecurityFormatter.securityStatusLabel(link.paired ? "ready" : "pending", language: interfaceLanguage)
    )
    SignalASISecurityNavigationRow(
      title: t("signalasi.device.remote_control", "Control Computer"),
      subtitle: t(
        "signalasi.device.remote_control_subtitle",
        "Securely view and control an authorized computer from this phone"
      ),
      systemImage: "desktopcomputer",
      tint: .purple,
      badge: link.fullDesktopExecutor
        ? t("signalasi.status.enabled", "Enabled")
        : t("signalasi.security_center.manage", "Manage")
    ) {
      SignalASIDesktopControlView(initialDesktopId: link.desktopId)
    }
    SignalASISecuritySectionTitle(title: "Agent")
    if agents.isEmpty {
      SignalASISecurityStatusRow(
        title: t("signalasi.security_center.no_agents", "No Agents"),
        subtitle: t("signalasi.security_center.no_agents_subtitle", "Desktop connector Agents appear after pairing metadata syncs"),
        systemImage: "questionmark.circle",
        tint: .orange,
        badge: t("signalasi.status.needs_setup", "Needs Setup")
      )
    } else {
      ForEach(agents) { agent in
        SignalASISecurityStatusRow(
          title: agent.displayName.ifBlank(agent.name).ifBlank(t("signalasi.security_center.agent", "Agent")),
          subtitle: agent.setupDetail.ifBlank(agent.agentKind),
          systemImage: SignalASISecurityFormatter.agentSystemImage(id: agent.id, kind: agent.agentKind),
          tint: .purple,
          badge: SignalASISecurityFormatter.securityStatusLabel(agent.setupStatus, language: interfaceLanguage)
        )
      }
    }
    SignalASISecuritySectionTitle(title: t("signalasi.security_center.section_danger", "Danger"))
    SignalASISecurityNavigationRow(
      title: t("signalasi.security_center.revoke_this_pc", "Revoke this computer"),
      subtitle: t(
        "signalasi.security_center.revoke_this_pc_subtitle",
        "Delete this computer's Agent trust and sessions; scan again to connect"
      ),
      systemImage: "trash",
      tint: .red,
      badge: t("signalasi.security_center.revoke", "Revoke")
    ) {
      SignalASIRevokeDevicePairingView(desktopId: link.desktopId)
    }
  }

  private var revokedContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      SignalASISecurityHeroView(
        title: t("signalasi.security_center.status_revoked", "Revoked"),
        subtitle: t("signalasi.security_center.revoked_device_missing", "This computer pairing is no longer trusted on this phone"),
        systemImage: "trash",
        tint: .red,
        badge: t("signalasi.security_center.revoke", "Revoke")
      )
      SignalASISecurityNavigationRow(
        title: t("signalasi.security_center.scan", "Scan"),
        subtitle: t("signalasi.discover.scan_subtitle", "Add contacts or devices"),
        systemImage: "qrcode.viewfinder",
        tint: .signalASIAccent,
        badge: "+"
      ) {
        AddContactView(autoOpenScanner: true)
      }
    }
  }

  private func copy(_ value: String, message: String) {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    UIPasteboard.general.string = value
    statusMessage = message
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIRevokeDevicePairingView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var revocationInFlight = false
  var desktopId: String

  private var link: ServerLink? {
    store.serverLinks.first { $0.desktopId == desktopId }
  }

  private var agents: [SignalASIContact] {
    store.contacts.filter { !$0.deleted && $0.deliveryMode.isSignalASILinkFamily && $0.type == "agent" && $0.desktopId == desktopId }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.security_center.revoke_device_title", "Revoke Device"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: link?.desktopName.ifBlank(t("signalasi.security_center.pc", "PC")) ?? t("signalasi.security_center.pc", "PC"),
            subtitle: t(
              "signalasi.security_center.revoke_device_subtitle",
              "After revocation, you must scan again and confirm fingerprints before communication."
            ),
            systemImage: "trash",
            tint: .red,
            badge: t("signalasi.common.confirm", "Confirm")
          )
          SignalASISecurityStatusRow(
            title: t("signalasi.security_center.revoke_scope", "Scope"),
            subtitle: String(format: t("signalasi.security_center.count_pc_connector_agents", "%d PC connector Agents"), agents.count),
            systemImage: "person.3",
            tint: .purple,
            badge: t("signalasi.common.delete", "Delete")
          )
          SignalASISecurityStatusRow(
            title: t("signalasi.security.desktop_fingerprint", "Computer Fingerprint"),
            subtitle: SignalASISecurityFormatter.fingerprint(
              link?.desktopFingerprint ?? "",
              unknown: t("signalasi.status.unknown", "Unknown")
            ),
            systemImage: "checkmark.shield",
            tint: .signalASIAccent,
            badge: ""
          )
          SignalASISecurityPrimaryButton(
            title: t("signalasi.security_center.revoke_this_pc", "Revoke this computer"),
            systemImage: "trash",
            tint: .red
          ) {
            guard !revocationInFlight else { return }
            revocationInFlight = true
            Task { @MainActor in
              _ = await coordinator.revokeDesktopPairing(desktopId: desktopId)
              dismiss()
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

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIRevokeAllPCPairingsView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var revocationInFlight = false

  private var summaries: [SignalASIDesktopSecuritySummary] {
    let connectorContacts = store.contacts.filter { !$0.deleted && $0.deliveryMode.isSignalASILinkFamily && $0.type == "agent" }
    return store.serverLinks
      .sorted { lhs, rhs in
        lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
      }
      .map { link in
        SignalASIDesktopSecuritySummary(
          link: link,
          agents: connectorContacts.filter { $0.desktopId == link.desktopId }
        )
      }
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("signalasi.security_center.revoke_all_pc", "Revoke all PC pairings"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("signalasi.security_center.revoke_all_pc_title", "Revoke all PCs"),
            subtitle: t(
              "signalasi.security_center.revoke_all_pc_hero_subtitle",
              "Delete all computer and Agent trust relationships; scan again to connect."
            ),
            systemImage: "trash",
            tint: .red,
            badge: String(format: t("signalasi.security_center.count_devices", "%d devices"), summaries.count)
          )
          if summaries.isEmpty {
            SignalASISecurityStatusRow(
              title: t("signalasi.security_center.no_paired_pc", "No paired computers yet"),
              subtitle: t("signalasi.security_center.no_paired_pc_subtitle", "Paired desktops appear after scanning and confirming fingerprints"),
              systemImage: "desktopcomputer",
              tint: .orange,
              badge: t("signalasi.status.needs_setup", "Needs Setup")
            )
          } else {
            ForEach(summaries) { summary in
              SignalASISecurityStatusRow(
                title: summary.link.desktopName.ifBlank(t("signalasi.security_center.pc", "PC")),
                subtitle: String(
                  format: t("signalasi.security_center.device_agent_fingerprint_summary", "%d Agents / %@"),
                  summary.agents.count,
                  SignalASISecurityFormatter.fingerprint(
                    summary.link.desktopFingerprint,
                    unknown: t("signalasi.status.unknown", "Unknown")
                  )
                ),
                systemImage: "desktopcomputer",
                tint: .red,
                badge: t("signalasi.security_center.will_revoke", "Will revoke"),
                monospacedSubtitle: true
              )
            }
            SignalASISecurityPrimaryButton(
              title: t("signalasi.security_center.revoke_all_pc", "Revoke all PC pairings"),
              systemImage: "trash",
              tint: .red
            ) {
              guard !revocationInFlight else { return }
              revocationInFlight = true
              let ids = summaries.map(\.link.desktopId)
              Task { @MainActor in
                for id in ids {
                  _ = await coordinator.revokeDesktopPairing(desktopId: id)
                }
                dismiss()
              }
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

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIDesktopSecuritySummary: Identifiable {
  var link: ServerLink
  var agents: [SignalASIContact]

  var id: String {
    link.desktopId
  }
}
