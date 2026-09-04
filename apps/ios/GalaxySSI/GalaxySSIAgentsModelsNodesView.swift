import SwiftUI

struct GalaxySSIAgentsModelsNodesView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var localModelReady = false

  private var desktopLinks: [ServerLink] {
    store.serverLinks.sorted { lhs, rhs in
      lhs.desktopName.localizedCaseInsensitiveCompare(rhs.desktopName) == .orderedAscending
    }
  }

  private var cloudContacts: [GalaxySSIContact] {
    store.cloudModelContacts
  }

  private var resourceTargets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  private var availableResourceCount: Int {
    resourceTargets.filter { $0.status == .available }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_nodes_title", "Agents, Models & Nodes"),
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
            title: String(
              format: t("cc_nodes_ready_title", "%d intelligence resources available"),
              availableResourceCount
            ),
            subtitle: t(
              "cc_nodes_ready_subtitle",
              "Nodes publish health; offline resources are excluded from routing"
            ),
            systemImage: "link.circle",
            tint: availableResourceCount > 0 ? .galaxySSIAccent : .orange,
            badge: "\(availableResourceCount)"
          )
          desktopSection
          thisDeviceSection
          cloudAPISection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      localModelReady = LocalModelInferenceRuntime.shared.ready()
    }
  }

  private var desktopSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("default_desktop_name", "Computer"))
      if desktopLinks.isEmpty {
        GalaxySSISecurityNavigationRow(
          title: t("cc_no_desktop_title", "No trusted Desktop node"),
          subtitle: t("cc_no_desktop_subtitle", "Scan a GalaxySSI Desktop QR code to add its available Agents"),
          systemImage: "qrcode.viewfinder",
          tint: .orange,
          badge: t("security_scan", "Scan")
        ) {
          AddContactView(autoOpenScanner: true)
        }
      } else {
        ForEach(desktopLinks) { link in
          GalaxySSISecurityNavigationRow(
            title: desktopTitle(link),
            subtitle: String(format: t("count_items", "%d items"), desktopAgentCount(link)),
            systemImage: "desktopcomputer",
            tint: desktopOnline(link) ? .galaxySSIAccent : .gray,
            badge: desktopOnline(link)
              ? t("cc_status_online", "Online")
              : t("status_disconnected", "Disconnected")
          ) {
            GalaxySSIDesktopControlView(initialDesktopId: link.desktopId)
          }
        }
      }
    }
  }

  private var thisDeviceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_this_device", "This Device"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_agent_identity_title", "Agent Identity"),
        subtitle: t(
          "cc_nodes_phone_agent_subtitle",
          "This iPhone, local Agent identity, and trusted contact context"
        ),
        systemImage: "iphone",
        tint: .galaxySSIAccent,
        badge: t("cc_status_ready", "Ready")
      ) {
        GalaxySSIMyAgentsView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_nodes_local_model_title", "Local Model Runtime"),
        subtitle: t(
          "cc_nodes_local_model_subtitle",
          "On-device model lab, routing plans, and local inference settings"
        ),
        systemImage: "memorychip",
        tint: localModelReady ? .galaxySSIAccent : .blue,
        badge: localModelReady
          ? t("galaxyssi.local_model.download_ready", "Ready")
          : t("status_needs_setup", "Needs Setup")
      ) {
        GalaxySSILocalModelLabView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_device_info_title", "Device Information"),
        subtitle: t(
          "cc_nodes_device_info_subtitle",
          "Phone permissions, paired computers, custom devices, and connectors"
        ),
        systemImage: "antenna.radiowaves.left.and.right",
        tint: .blue,
        badge: t("cc_status_ready", "Ready")
      ) {
        DeviceManagementView()
      }
    }
  }

  private var cloudAPISection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_cloud_apis", "Cloud APIs"))
      if cloudContacts.isEmpty {
        GalaxySSISecurityNavigationRow(
          title: t("cc_add_cloud_provider_title", "Add Cloud Provider"),
          subtitle: t("cc_add_cloud_provider_subtitle", "Configure a phone-direct API resource"),
          systemImage: "cloud.fill",
          tint: .purple,
          badge: "+"
        ) {
          CloudModelProviderSelectionView()
        }
      } else {
        ForEach(cloudContacts) { contact in
          let status = cloudConnectorStatus(contact)
          GalaxySSISecurityNavigationRow(
            title: contact.displayName.ifBlank(contact.name).ifBlank(contact.id),
            subtitle: cloudSubtitle(contact),
            systemImage: "cloud.fill",
            assetImage: cloudAssetName(contact),
            tint: cloudStatusTint(status),
            badge: cloudStatusLabel(status)
          ) {
            CloudModelProviderDetailView(contactId: contact.id)
          }
        }
        GalaxySSISecurityNavigationRow(
          title: t("cc_add_cloud_provider_title", "Add Cloud Provider"),
          subtitle: t("cc_add_cloud_provider_subtitle", "Configure a phone-direct API resource"),
          systemImage: "plus",
          tint: .purple,
          badge: "+"
        ) {
          CloudModelProviderSelectionView()
        }
      }
    }
  }

  private func desktopTitle(_ link: ServerLink) -> String {
    link.desktopName.ifBlank(link.signalName).ifBlank(t("default_desktop_name", "Computer"))
  }

  private func desktopOnline(_ link: ServerLink) -> Bool {
    guard link.paired && coordinator.mqttClient.isConnected else { return false }
    let desktopAgentIds = Set(desktopAgentContacts(link).map(\.id))
    return resourceTargets.contains { target in
      desktopAgentIds.contains(target.id) && target.status == .available
    }
  }

  private func desktopAgentCount(_ link: ServerLink) -> Int {
    desktopAgentContacts(link).count
  }

  private func desktopAgentContacts(_ link: ServerLink) -> [GalaxySSIContact] {
    store.contacts.filter { contact in
      !contact.deleted &&
        contact.desktopId == link.desktopId &&
        (contact.type == "agent" || contact.id == "hermes" || contact.deliveryMode.isGalaxySSILinkFamily)
    }
  }

  private func cloudConnectorStatus(_ contact: GalaxySSIContact) -> AgentConnectorStatus {
    resourceTargets.first { $0.id == contact.id }?.status ?? .needsSetup
  }

  private func cloudStatusLabel(_ status: AgentConnectorStatus) -> String {
    switch status {
    case .available:
      return t("cc_status_ready", "Ready")
    case .needsSetup:
      return t("status_needs_setup", "Needs Setup")
    case .disconnected:
      return t("status_disconnected", "Disconnected")
    }
  }

  private func cloudStatusTint(_ status: AgentConnectorStatus) -> Color {
    switch status {
    case .available:
      return .galaxySSIInsightText
    case .needsSetup:
      return .orange
    case .disconnected:
      return .galaxySSITextSecondary
    }
  }

  private func cloudSubtitle(_ contact: GalaxySSIContact) -> String {
    let provider = contact.cloudProvider.ifBlank(contact.galaxySSIId).ifBlank(contact.id)
    let model = contact.selectedCloudModel?.modelId ?? t("galaxyssi.settings.no_model", "No model")
    return "\(provider) / \(model)"
  }

  private func cloudAssetName(_ contact: GalaxySSIContact) -> String? {
    GalaxySSIAgentAvatarAssetCatalog.cloudProviderAssetName(for: [
      contact.id,
      contact.galaxySSIId,
      contact.name,
      contact.displayName,
      contact.cloudProvider,
      contact.selectedCloudModel?.provider ?? "",
      contact.selectedCloudModel?.modelId ?? ""
    ])
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
