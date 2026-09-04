import SwiftUI
import UIKit

struct GalaxySSISecurityCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var statusMessage = ""

  private var connectorContacts: [GalaxySSIContact] {
    store.contacts
      .filter { !$0.deleted && $0.deliveryMode.isGalaxySSILinkFamily && $0.type == "agent" }
      .sorted { lhs, rhs in
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
  }

  private var desktopSummaries: [GalaxySSIDesktopSecuritySummary] {
    store.serverLinks
      .sorted { lhs, rhs in
        lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
      }
      .map { link in
        GalaxySSIDesktopSecuritySummary(
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
      GalaxySSITopBar(
        title: t("galaxyssi.security_center.title", "Security Center"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("galaxyssi.security_center.privacy_title", "Privacy & Security"),
            subtitle: t(
              "galaxyssi.security_center.privacy_subtitle",
              "End-to-end encryption; only devices and contacts with confirmed fingerprints can communicate"
            ),
            systemImage: "checkmark.shield",
            tint: .galaxySSIAccent,
            badge: String(
              format: t("galaxyssi.security_center.count_devices", "%d devices"),
              desktopSummaries.count
            )
          )
          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.security_center.status", "Security Status"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var identitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.security_center.section_identity", "Identity"))
      GalaxySSISecurityActionRow(
        title: t("galaxyssi.security.phone_fingerprint", "Phone Fingerprint"),
        subtitle: GalaxySSISecurityFormatter.fingerprint(
          store.profile.identityFingerprint,
          unknown: t("galaxyssi.status.unknown", "Unknown")
        ),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.identityFingerprint, message: t("galaxyssi.security_center.copied_phone_fingerprint", "Phone fingerprint copied"))
      }
      GalaxySSISecurityActionRow(
        title: t("galaxyssi.security_center.galaxyssi_id", "GalaxySSI ID"),
        subtitle: store.profile.galaxySSIId.ifBlank(t("galaxyssi.status.unknown", "Unknown")),
        systemImage: "link",
        tint: .blue,
        badge: t("galaxyssi.common.copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.galaxySSIId, message: t("galaxyssi.security_center.copied_galaxyssi_id", "GalaxySSI ID copied"))
      }
    }
  }

  private var pairedDevicesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.security_center.section_paired_devices", "Paired Devices"))
      if desktopSummaries.isEmpty {
        GalaxySSISecurityNavigationRow(
          title: t("galaxyssi.security_center.no_paired_pc", "No paired computers yet"),
          subtitle: t(
            "galaxyssi.security_center.no_paired_pc_subtitle",
            "Paired desktops appear after scanning and confirming fingerprints"
          ),
          systemImage: "desktopcomputer",
          tint: .orange,
          badge: t("galaxyssi.security_center.scan", "Scan")
        ) {
          AddContactView(autoOpenScanner: true)
        }
      } else {
        ForEach(desktopSummaries) { summary in
          GalaxySSISecurityNavigationRow(
            title: summary.link.desktopName.ifBlank(t("galaxyssi.security_center.pc", "PC")),
            subtitle: deviceSubtitle(summary),
            systemImage: "desktopcomputer",
            tint: summary.link.paired ? .galaxySSIAccent : .orange,
            badge: t("galaxyssi.security_center.manage", "Manage"),
            monospacedSubtitle: true
          ) {
            GalaxySSIDeviceSecurityDetailView(desktopId: summary.link.desktopId)
          }
        }
        GalaxySSISecurityNavigationRow(
          title: t("cc_contacts_title", "Contacts"),
          subtitle: t("cc_contacts_subtitle", "People, Agents, models, devices, and remarks"),
          systemImage: "person.2",
          tint: .purple,
          badge: "\(trustedContactCount)"
        ) {
          GalaxySSIConversationHubView(initialTab: .contacts)
        }
        GalaxySSISecurityNavigationRow(
          title: t("galaxyssi.security_center.scan", "Scan"),
          subtitle: t("galaxyssi.discover.scan_subtitle", "Add contacts or devices"),
          systemImage: "qrcode.viewfinder",
          tint: .galaxySSIAccent,
          badge: "+"
        ) {
          AddContactView(autoOpenScanner: true)
        }
      }
    }
  }

  private var agentPermissionsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.security_center.section_agent_permissions", "Agent Permissions"))
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.security_center.on_device_agent_permissions", "On-device Agent Permissions"),
        subtitle: t(
          "galaxyssi.security_center.on_device_agent_permissions_subtitle",
          "Microphone, camera, notifications, and on-device execution require phone-side authorization"
        ),
        systemImage: "cpu",
        tint: .blue,
        badge: t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle)
      ) {
        OnDeviceAgentPermissionsView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.settings.execution_policy", "Execution Policy"),
        subtitle: "\(t(store.agentSafetySettings.taskExecutionMode.displayTitle, store.agentSafetySettings.taskExecutionMode.displayTitle)) / \(t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle))",
        systemImage: "exclamationmark.shield",
        tint: .orange,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIExecutionPolicyView()
      }
      ForEach(connectorContacts.prefix(8)) { contact in
        GalaxySSISecurityStatusRow(
          title: contact.displayName.ifBlank(contact.name).ifBlank(t("galaxyssi.security_center.agent", "Agent")),
          subtitle: String(
            format: t("galaxyssi.security_center.permission_status", "Permission: PC connector / Status: %@ / %@"),
            GalaxySSISecurityFormatter.securityStatusLabel(contact.setupStatus, language: interfaceLanguage),
            GalaxySSISecurityFormatter.time(
              contact.updatedAt,
              unknown: t("galaxyssi.status.unknown", "Unknown"),
              language: interfaceLanguage
            )
          ),
          systemImage: GalaxySSISecurityFormatter.agentSystemImage(id: contact.id, kind: contact.agentKind),
          tint: .purple,
          badge: GalaxySSISecurityFormatter.securityStatusLabel(contact.setupStatus, language: interfaceLanguage)
        )
      }
      if connectorContacts.count > 8 {
        GalaxySSISecurityStatusRow(
          title: t("galaxyssi.security_center.more_agents", "More Agents"),
          subtitle: String(
            format: t("galaxyssi.security_center.more_agents_subtitle", "%d more PC connector Agents"),
            connectorContacts.count - 8
          ),
          systemImage: "person.3",
          tint: .purple,
          badge: t("galaxyssi.common.view", "View")
        )
      }
    }
  }

  private var identityProtectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("feature_identity_protection", "Identity Protection"))
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_high_risk_guard", "High-risk Guard"),
        subtitle: t("cc_always_confirm_subtitle", "Messages, calls, deletion, installation, payment, lock, and security"),
        systemImage: "checkmark.shield",
        tint: store.agentSafetySettings.highRiskGuard ? .galaxySSIAccent : .orange,
        badge: store.agentSafetySettings.highRiskGuard ? t("status_enabled", "Enabled") : t("common_off", "Off")
      ) {
        store.updateAgentSafetySettings { $0.highRiskGuard.toggle() }
      }
    }
  }

  private var messageProtectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.security_center.section_message_protection", "Message Protection"))
      GalaxySSISecurityStatusRow(
        title: "Signal Protocol",
        subtitle: t("galaxyssi.security_center.signal_protocol_subtitle", "Session keys and message encryption"),
        systemImage: "lock.shield",
        tint: .blue,
        badge: "v1.0.3"
      )
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.security_center.fingerprint_confirm", "Dual Fingerprint Confirmation"),
        subtitle: t(
          "galaxyssi.security_center.fingerprint_confirm_subtitle",
          "First scan must manually confirm phone and computer fingerprints"
        ),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.status.enabled", "Enabled")
      )
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.settings.model_data_sharing", "Model Data Sharing"),
        subtitle: t(
          "galaxyssi.settings.model_data_sharing.subtitle",
          "Review metadata-only disclosure events and destination blocks"
        ),
        systemImage: "doc.text",
        tint: .teal,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIPrivacyDashboardView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.security_center.revoke_all_pc", "Revoke all PC pairings"),
        subtitle: t(
          "galaxyssi.security_center.revoke_all_pc_subtitle",
          "After deletion, you must scan the QR code again before communication"
        ),
        systemImage: "trash",
        tint: .red,
        badge: t("galaxyssi.security_center.manage", "Manage")
      ) {
        GalaxySSIRevokeAllPCPairingsView()
      }
    }
  }

  private func deviceSubtitle(_ summary: GalaxySSIDesktopSecuritySummary) -> String {
    let fingerprint = GalaxySSISecurityFormatter.fingerprint(
      summary.link.desktopFingerprint,
      unknown: t("galaxyssi.status.unknown", "Unknown")
    )
    let lastActive = String(
      format: t("galaxyssi.security_center.last_active", "Last active %@"),
      GalaxySSISecurityFormatter.time(
        summary.link.updatedAt,
        unknown: t("galaxyssi.status.unknown", "Unknown"),
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
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIDeviceSecurityDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var statusMessage = ""
  var desktopId: String

  private var link: ServerLink? {
    store.serverLinks.first { $0.desktopId == desktopId }
  }

  private var agents: [GalaxySSIContact] {
    store.contacts
      .filter { !$0.deleted && $0.deliveryMode.isGalaxySSILinkFamily && $0.type == "agent" && $0.desktopId == desktopId }
      .sorted { lhs, rhs in
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.security_center.device_detail_title", "Device Security"),
        leading: {
          GalaxySSIBackButton()
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  @ViewBuilder
  private func deviceContent(_ link: ServerLink) -> some View {
    GalaxySSISecurityHeroView(
      title: link.desktopName.ifBlank(t("galaxyssi.security_center.pc", "PC")),
      subtitle: t("galaxyssi.security_center.verified_desktop_connector", "Verified Desktop connector"),
      systemImage: "desktopcomputer",
      tint: link.paired ? .galaxySSIAccent : .orange,
      badge: String(format: t("galaxyssi.security_center.count_items", "%d items"), agents.count)
    )
    if !statusMessage.isEmpty {
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.security_center.status", "Security Status"),
        subtitle: statusMessage,
        systemImage: "checkmark.circle",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.status.ready", "Ready")
      )
    }
    GalaxySSISecuritySectionTitle(title: t("galaxyssi.security_center.section_identity", "Identity"))
    GalaxySSISecurityActionRow(
      title: "Desktop ID",
      subtitle: link.desktopId,
      systemImage: "link",
      tint: .blue,
      badge: t("galaxyssi.common.copy", "Copy"),
      monospacedSubtitle: true
    ) {
      copy(link.desktopId, message: t("galaxyssi.security_center.copied_desktop_id", "Desktop ID copied"))
    }
    GalaxySSISecurityActionRow(
      title: t("galaxyssi.security.desktop_fingerprint", "Computer Fingerprint"),
      subtitle: GalaxySSISecurityFormatter.fingerprint(
        link.desktopFingerprint,
        unknown: t("galaxyssi.status.unknown", "Unknown")
      ),
      systemImage: "checkmark.shield",
      tint: .galaxySSIAccent,
      badge: t("galaxyssi.common.copy", "Copy"),
      monospacedSubtitle: true
    ) {
      copy(link.desktopFingerprint, message: t("galaxyssi.security_center.copied_desktop_fingerprint", "Desktop fingerprint copied"))
    }
    GalaxySSISecurityStatusRow(
      title: t("galaxyssi.security_center.last_active_title", "Last active"),
      subtitle: GalaxySSISecurityFormatter.time(
        link.updatedAt,
        unknown: t("galaxyssi.status.unknown", "Unknown"),
        language: interfaceLanguage
      ),
      systemImage: "clock",
      tint: .blue,
      badge: GalaxySSISecurityFormatter.securityStatusLabel(link.paired ? "ready" : "pending", language: interfaceLanguage)
    )
    GalaxySSISecurityNavigationRow(
      title: t("galaxyssi.device.remote_control", "Control Computer"),
      subtitle: t(
        "galaxyssi.device.remote_control_subtitle",
        "Securely view and control an authorized computer from this phone"
      ),
      systemImage: "desktopcomputer",
      tint: .purple,
      badge: link.fullDesktopExecutor
        ? t("galaxyssi.status.enabled", "Enabled")
        : t("galaxyssi.security_center.manage", "Manage")
    ) {
      GalaxySSIDesktopControlView(initialDesktopId: link.desktopId)
    }
    GalaxySSISecuritySectionTitle(title: "Agent")
    if agents.isEmpty {
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.security_center.no_agents", "No Agents"),
        subtitle: t("galaxyssi.security_center.no_agents_subtitle", "Desktop connector Agents appear after pairing metadata syncs"),
        systemImage: "questionmark.circle",
        tint: .orange,
        badge: t("galaxyssi.status.needs_setup", "Needs Setup")
      )
    } else {
      ForEach(agents) { agent in
        GalaxySSISecurityStatusRow(
          title: agent.displayName.ifBlank(agent.name).ifBlank(t("galaxyssi.security_center.agent", "Agent")),
          subtitle: agent.setupDetail.ifBlank(agent.agentKind),
          systemImage: GalaxySSISecurityFormatter.agentSystemImage(id: agent.id, kind: agent.agentKind),
          tint: .purple,
          badge: GalaxySSISecurityFormatter.securityStatusLabel(agent.setupStatus, language: interfaceLanguage)
        )
      }
    }
    GalaxySSISecuritySectionTitle(title: t("galaxyssi.security_center.section_danger", "Danger"))
    GalaxySSISecurityNavigationRow(
      title: t("galaxyssi.security_center.revoke_this_pc", "Revoke this computer"),
      subtitle: t(
        "galaxyssi.security_center.revoke_this_pc_subtitle",
        "Delete this computer's Agent trust and sessions; scan again to connect"
      ),
      systemImage: "trash",
      tint: .red,
      badge: t("galaxyssi.security_center.revoke", "Revoke")
    ) {
      GalaxySSIRevokeDevicePairingView(desktopId: link.desktopId)
    }
  }

  private var revokedContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      GalaxySSISecurityHeroView(
        title: t("galaxyssi.security_center.status_revoked", "Revoked"),
        subtitle: t("galaxyssi.security_center.revoked_device_missing", "This computer pairing is no longer trusted on this phone"),
        systemImage: "trash",
        tint: .red,
        badge: t("galaxyssi.security_center.revoke", "Revoke")
      )
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.security_center.scan", "Scan"),
        subtitle: t("galaxyssi.discover.scan_subtitle", "Add contacts or devices"),
        systemImage: "qrcode.viewfinder",
        tint: .galaxySSIAccent,
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
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIRevokeDevicePairingView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var revocationInFlight = false
  var desktopId: String

  private var link: ServerLink? {
    store.serverLinks.first { $0.desktopId == desktopId }
  }

  private var agents: [GalaxySSIContact] {
    store.contacts.filter { !$0.deleted && $0.deliveryMode.isGalaxySSILinkFamily && $0.type == "agent" && $0.desktopId == desktopId }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.security_center.revoke_device_title", "Revoke Device"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: link?.desktopName.ifBlank(t("galaxyssi.security_center.pc", "PC")) ?? t("galaxyssi.security_center.pc", "PC"),
            subtitle: t(
              "galaxyssi.security_center.revoke_device_subtitle",
              "After revocation, you must scan again and confirm fingerprints before communication."
            ),
            systemImage: "trash",
            tint: .red,
            badge: t("galaxyssi.common.confirm", "Confirm")
          )
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.security_center.revoke_scope", "Scope"),
            subtitle: String(format: t("galaxyssi.security_center.count_pc_connector_agents", "%d PC connector Agents"), agents.count),
            systemImage: "person.3",
            tint: .purple,
            badge: t("galaxyssi.common.delete", "Delete")
          )
          GalaxySSISecurityStatusRow(
            title: t("galaxyssi.security.desktop_fingerprint", "Computer Fingerprint"),
            subtitle: GalaxySSISecurityFormatter.fingerprint(
              link?.desktopFingerprint ?? "",
              unknown: t("galaxyssi.status.unknown", "Unknown")
            ),
            systemImage: "checkmark.shield",
            tint: .galaxySSIAccent,
            badge: ""
          )
          GalaxySSISecurityPrimaryButton(
            title: t("galaxyssi.security_center.revoke_this_pc", "Revoke this computer"),
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIRevokeAllPCPairingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var revocationInFlight = false

  private var summaries: [GalaxySSIDesktopSecuritySummary] {
    let connectorContacts = store.contacts.filter { !$0.deleted && $0.deliveryMode.isGalaxySSILinkFamily && $0.type == "agent" }
    return store.serverLinks
      .sorted { lhs, rhs in
        lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
      }
      .map { link in
        GalaxySSIDesktopSecuritySummary(
          link: link,
          agents: connectorContacts.filter { $0.desktopId == link.desktopId }
        )
      }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.security_center.revoke_all_pc", "Revoke all PC pairings"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("galaxyssi.security_center.revoke_all_pc_title", "Revoke all PCs"),
            subtitle: t(
              "galaxyssi.security_center.revoke_all_pc_hero_subtitle",
              "Delete all computer and Agent trust relationships; scan again to connect."
            ),
            systemImage: "trash",
            tint: .red,
            badge: String(format: t("galaxyssi.security_center.count_devices", "%d devices"), summaries.count)
          )
          if summaries.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("galaxyssi.security_center.no_paired_pc", "No paired computers yet"),
              subtitle: t("galaxyssi.security_center.no_paired_pc_subtitle", "Paired desktops appear after scanning and confirming fingerprints"),
              systemImage: "desktopcomputer",
              tint: .orange,
              badge: t("galaxyssi.status.needs_setup", "Needs Setup")
            )
          } else {
            ForEach(summaries) { summary in
              GalaxySSISecurityStatusRow(
                title: summary.link.desktopName.ifBlank(t("galaxyssi.security_center.pc", "PC")),
                subtitle: String(
                  format: t("galaxyssi.security_center.device_agent_fingerprint_summary", "%d Agents / %@"),
                  summary.agents.count,
                  GalaxySSISecurityFormatter.fingerprint(
                    summary.link.desktopFingerprint,
                    unknown: t("galaxyssi.status.unknown", "Unknown")
                  )
                ),
                systemImage: "desktopcomputer",
                tint: .red,
                badge: t("galaxyssi.security_center.will_revoke", "Will revoke"),
                monospacedSubtitle: true
              )
            }
            GalaxySSISecurityPrimaryButton(
              title: t("galaxyssi.security_center.revoke_all_pc", "Revoke all PC pairings"),
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
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIDesktopSecuritySummary: Identifiable {
  var link: ServerLink
  var agents: [GalaxySSIContact]

  var id: String {
    link.desktopId
  }
}
