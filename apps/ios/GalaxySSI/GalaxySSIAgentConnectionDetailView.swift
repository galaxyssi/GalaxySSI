import SwiftUI

struct GalaxySSIAgentConnectionDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  var item: GalaxySSIAgentDirectoryItem

  private var contact: GalaxySSIContact? {
    store.contact(id: item.contactId) ?? store.contact(id: item.id)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: title,
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSIAgentConnectionHeroCard(
            title: title,
            subtitle: subtitle,
            systemImage: item.systemImage,
            tint: item.tint,
            badge: statusBadge
          )

          sectionTitle(t("galaxyssi.agent_connection.section_status", "Status"))
          VStack(spacing: 8) {
            GalaxySSIAgentConnectionInfoRow(
              title: t("galaxyssi.agent_connection.connection_state", "Connection State"),
              subtitle: statusSubtitle,
              systemImage: statusIcon,
              tint: statusTint,
              badge: statusBadge
            )
            GalaxySSIAgentConnectionInfoRow(
              title: t("galaxyssi.agent_connection.route", "Route"),
              subtitle: routeSubtitle,
              systemImage: routeIcon,
              tint: .galaxySSIInsightText,
              badge: routeBadge
            )
            GalaxySSIAgentConnectionInfoRow(
              title: t("galaxyssi.agent_connection.identity", "Identity"),
              subtitle: identitySubtitle,
              systemImage: "checkmark.shield",
              tint: identityTint,
              badge: identityBadge
            )
          }

          sectionTitle(t("galaxyssi.agent_connection.section_capabilities", "Capabilities"))
          VStack(spacing: 8) {
            GalaxySSIAgentConnectionInfoRow(
              title: t("galaxyssi.agent_connection.capability_chat", "Agent Chat"),
              subtitle: t("galaxyssi.agent_connection.capability_chat_subtitle", "Use this Agent as a direct conversation target"),
              systemImage: "bubble.left.and.bubble.right",
              tint: .blue,
              badge: chatBadge
            )
            GalaxySSIAgentConnectionInfoRow(
              title: t("galaxyssi.agent_connection.capability_tools", "Native Tools"),
              subtitle: t("galaxyssi.agent_connection.capability_tools_subtitle", "Expose Android-parity phone, app, and route tools when the Agent is ready"),
              systemImage: "wrench.and.screwdriver",
              tint: .teal,
              badge: toolsBadge
            )
            GalaxySSIAgentConnectionInfoRow(
              title: t("galaxyssi.agent_connection.capability_planning", "Planner Routing"),
              subtitle: t("galaxyssi.agent_connection.capability_planning_subtitle", "Can be selected by resource routing and model planner policies"),
              systemImage: "point.3.connected.trianglepath.dotted",
              tint: .purple,
              badge: routingBadge
            )
          }

          sectionTitle(t("galaxyssi.agent_connection.section_actions", "Actions"))
          VStack(spacing: 8) {
            if let contact {
              NavigationLink(destination: ContactDetailView(contactId: contact.id)) {
                GalaxySSIAgentConnectionActionRow(
                  title: t("galaxyssi.agent_connection.open_detail", "Open Agent Detail"),
                  subtitle: t("galaxyssi.agent_connection.open_detail_subtitle", "View identity, route, cloud model, and security settings"),
                  systemImage: "person.crop.circle.badge.checkmark",
                  tint: .galaxySSIAccent,
                  badge: t("galaxyssi.common.open", "Open")
                )
              }
              .buttonStyle(.plain)

              if contact.isCommunicable {
                NavigationLink(destination: GalaxySSIContactMessagingDestination(contactId: contact.id)) {
                  GalaxySSIAgentConnectionActionRow(
                    title: t("galaxyssi.agent_connection.open_chat", "Open Chat"),
                    subtitle: t("galaxyssi.agent_connection.open_chat_subtitle", "Start a GalaxySSI conversation with this Agent"),
                    systemImage: "message.fill",
                    tint: .blue,
                    badge: t("galaxyssi.common.chat", "Chat")
                  )
                }
                .buttonStyle(.plain)
              }
            }

            NavigationLink(destination: AddContactView(autoOpenScanner: true)) {
              GalaxySSIAgentConnectionActionRow(
                title: t("galaxyssi.agent_connection.scan_qr", "Scan or Paste Agent QR"),
                subtitle: t("galaxyssi.agent_connection.scan_qr_subtitle", "Pair Codex, Claude Code, local models, or desktop Agents with the Android-compatible QR flow"),
                systemImage: "qrcode.viewfinder",
                tint: .orange,
                badge: t("galaxyssi.common.connect", "Connect")
              )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: GalaxySSIResourceRoutingView()) {
              GalaxySSIAgentConnectionActionRow(
                title: t("galaxyssi.agent_connection.routing", "Routing & Fallback"),
                subtitle: t("galaxyssi.agent_connection.routing_subtitle", "Manage local, cloud, desktop, and phone resource routing"),
                systemImage: "arrow.triangle.branch",
                tint: .purple,
                badge: t("galaxyssi.common.manage", "Manage")
              )
            }
            .buttonStyle(.plain)

            NavigationLink(destination: AgentModelPlannerSettingsView()) {
              GalaxySSIAgentConnectionActionRow(
                title: t("galaxyssi.agent_connection.planner", "Planner Settings"),
                subtitle: t("galaxyssi.agent_connection.planner_subtitle", "Configure replanning, coordination, screen context, and autonomy limits"),
                systemImage: "brain.head.profile",
                tint: .galaxySSIInsightText,
                badge: t("galaxyssi.common.configure", "Configure")
              )
            }
            .buttonStyle(.plain)

            if isLocalModelRoute {
              NavigationLink(destination: GalaxySSILocalModelLabView()) {
                GalaxySSIAgentConnectionActionRow(
                  title: t("galaxyssi.agent_connection.local_model_lab", "Local Model Lab"),
                  subtitle: t("galaxyssi.agent_connection.local_model_lab_subtitle", "Inspect model storage, context window, accelerators, and local runtime readiness"),
                  systemImage: "memorychip",
                  tint: .teal,
                  badge: t("galaxyssi.common.open", "Open")
                )
              }
              .buttonStyle(.plain)
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

  private var title: String {
    contact?.displayName.ifBlank(contact?.name ?? item.title) ?? item.title
  }

  private var subtitle: String {
    contact.map { connectorDetail($0, fallback: item.subtitle) } ?? item.subtitle
  }

  private var statusBadge: String {
    if let contact {
      return statusLabel(contact.setupStatus, fallback: item.badge)
    }
    return item.badge
  }

  private var statusSubtitle: String {
    if let contact {
      let detail = connectorDetail(contact, fallback: item.subtitle)
      return "\(detail) - \(routeBadge)"
    }
    return t(
      "galaxyssi.agent_connection.pending_subtitle",
      "Not paired yet. Scan the Agent QR code or add a cloud model to make this route available."
    )
  }

  private var statusIcon: String {
    switch normalizedStatus {
    case "ready", "running", "paired":
      return "checkmark.circle.fill"
    case "needs_setup", "needs-pairing", "needs_pairing", "pending_pairing", "pairing":
      return "exclamationmark.triangle.fill"
    default:
      return item.connected ? "checkmark.circle" : "clock"
    }
  }

  private var statusTint: Color {
    switch normalizedStatus {
    case "ready", "running", "paired":
      return .galaxySSIAccent
    case "needs_setup", "needs-pairing", "needs_pairing", "pending_pairing", "pairing":
      return .orange
    default:
      return item.connected ? .galaxySSIAccent : .galaxySSITextSecondary
    }
  }

  private var normalizedStatus: String {
    let raw = contact?.setupStatus.ifBlank(item.statusKey) ?? item.statusKey
    return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private var routeBadge: String {
    guard let contact else {
      return t("galaxyssi.status.pending_connection", "Pending Connection")
    }
    switch contact.deliveryMode {
    case .cloudAPI:
      return t("galaxyssi.agent_connection.route_cloud", "Cloud API")
    case .link, .pcConnector:
      return t("galaxyssi.agent_connection.route_link", "GalaxySSI Link")
    case .local:
      return t("galaxyssi.agent_connection.route_local", "Local")
    }
  }

  private var routeSubtitle: String {
    guard let contact else {
      return t(
        "galaxyssi.agent_connection.route_pending_subtitle",
        "The route appears in the Agent directory and becomes callable after pairing."
      )
    }
    if !contact.desktopName.isEmpty {
      return "\(contact.desktopName) - \(contact.agentKind.ifBlank(contact.type))"
    }
    if !contact.desktopId.isEmpty {
      return "\(contact.desktopId) - \(contact.agentKind.ifBlank(contact.type))"
    }
    return contact.agentKind.ifBlank(contact.type).ifBlank(item.subtitle)
  }

  private var routeIcon: String {
    if contact?.deliveryMode == .cloudAPI {
      return "cloud.fill"
    }
    if isLocalModelRoute {
      return "memorychip"
    }
    return "point.3.connected.trianglepath.dotted"
  }

  private var identityBadge: String {
    guard let contact else {
      return t("galaxyssi.agent_connection.identity_unpaired", "Unpaired")
    }
    switch contact.trustState {
    case .verified:
      return t("galaxyssi.agent_connection.identity_verified", "Verified")
    case .deleted:
      return t("galaxyssi.status.deleted", "Deleted")
    case .unverified:
      return t("galaxyssi.agent_connection.identity_unverified", "Unverified")
    }
  }

  private var identitySubtitle: String {
    guard let contact else {
      return t(
        "galaxyssi.agent_connection.identity_pending_subtitle",
        "Mutual identity verification starts from the same QR import flow used on Android."
      )
    }
    let fingerprint = contact.identityFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
    if fingerprint.isEmpty {
      return t("galaxyssi.agent_connection.identity_missing", "No identity fingerprint is stored yet.")
    }
    return fingerprint.galaxySSIAgentConnectionChunked(into: 16).joined(separator: " ")
  }

  private var identityTint: Color {
    contact?.trustState == .verified ? .galaxySSIAccent : .orange
  }

  private var chatBadge: String {
    guard let contact else { return t("galaxyssi.status.needs_setup", "Needs Setup") }
    return contact.isCommunicable ? t("galaxyssi.status.ready", "Ready") : t("galaxyssi.status.pending_connection", "Pending")
  }

  private var toolsBadge: String {
    if item.connected || contact?.setupStatus == "ready" {
      return t("galaxyssi.status.ready", "Ready")
    }
    return t("galaxyssi.status.needs_setup", "Needs Setup")
  }

  private var routingBadge: String {
    item.connected ? t("galaxyssi.common.enabled", "Enabled") : t("galaxyssi.common.available", "Available")
  }

  private var isLocalModelRoute: Bool {
    let kind = contact?.agentKind.lowercased() ?? item.id.lowercased()
    return kind.contains("local-model") || kind.contains("local_llm") || item.id == "local-llm"
  }

  private func connectorDetail(_ contact: GalaxySSIContact, fallback: String) -> String {
    contact.setupDetail
      .ifBlank(contact.connectorSetupNextStep)
      .ifBlank(fallback)
  }

  private func statusLabel(_ value: String, fallback: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "ready":
      return t("galaxyssi.status.ready", "Ready")
    case "running":
      return t("galaxyssi.status.running", "Running")
    case "needs_setup", "needs-pairing", "needs_pairing":
      return t("galaxyssi.status.needs_setup", "Needs Setup")
    case "pairing", "pending_pairing":
      return t("galaxyssi.status.pending_pairing", "Pending Pairing")
    case "deleted":
      return t("galaxyssi.status.deleted", "Deleted")
    default:
      return fallback
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIAgentConnectionHeroCard: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(spacing: 12) {
      icon(size: 52)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Text(subtitle)
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Text(badge)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.center)
        .frame(width: 74, height: 30)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func icon(size: CGFloat) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(tint.opacity(0.16))
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(tint)
    }
    .frame(width: size, height: size)
  }
}

private struct GalaxySSIAgentConnectionInfoRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    GalaxySSIAgentConnectionRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: false
    )
  }
}

private struct GalaxySSIAgentConnectionActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    GalaxySSIAgentConnectionRowContent(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      badge: badge,
      showsDisclosure: true
    )
  }
}

private struct GalaxySSIAgentConnectionRowContent: View {
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
          .font(.system(size: 17, weight: .semibold))
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
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
        .frame(width: 76, height: 30)
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

private extension String {
  func galaxySSIAgentConnectionChunked(into size: Int) -> [String] {
    guard size > 0 else { return [self] }
    var chunks: [String] = []
    var index = startIndex
    while index < endIndex {
      let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
      chunks.append(String(self[index..<next]))
      index = next
    }
    return chunks
  }
}
