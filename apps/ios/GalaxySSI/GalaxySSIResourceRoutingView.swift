import SwiftUI

struct GalaxySSIResourceRoutingView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  private var targets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  private var resources: [AgentResourceDescriptor] {
    AgentResourceCatalog.build(targets: targets, tools: [], nativeTools: [])
      .filter { $0.targetId != "phone" && $0.targetId != "local-system" && $0.targetId != "cloud-models" }
      .sorted { left, right in
        if left.status == .available, right.status != .available { return true }
        if left.status != .available, right.status == .available { return false }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
      }
  }

  private var availableCount: Int {
    resources.filter { $0.status == .available }.count
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_resource_routing_title", "Models & Resource Routing"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          banner
          metrics
          strategySection
          availableResourcesSection
          rulesSection
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
    let hasResources = availableCount > 0
    return GalaxySSISecurityHeroView(
      title: t(hasResources ? "cc_routing_enabled" : "cc_no_resources_title", hasResources ? "Automatic routing is enabled" : "No intelligence resource is currently available"),
      subtitle: t(hasResources ? "cc_routing_enabled_subtitle" : "cc_no_resources_subtitle", hasResources ? "Selects by task fit, health, latency, privacy, and cost" : "Configure a cloud API or pair a Desktop Agent to run remote tasks"),
      systemImage: "slider.horizontal.3",
      tint: hasResources ? .blue : .orange,
      badge: hasResources ? t("cc_status_available", "Available") : t("galaxyssi.status.needs_setup", "Needs Setup")
    )
    .padding(.horizontal, 4)
  }

  private var metrics: some View {
    HStack(spacing: 8) {
      metricCard(
        value: "\(availableCount)/\(resources.count)",
        label: t("cc_metric_available_resources", "Available resources")
      )
      metricCard(
        value: "\(resources.filter { $0.location == .cloud }.count)",
        label: t("cc_routing_metric_cloud", "Cloud")
      )
      metricCard(
        value: "\(resources.filter { $0.location != .cloud }.count)",
        label: t("cc_routing_metric_local", "Local")
      )
    }
  }

  private var strategySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_current_strategy", "Current Strategy"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_balanced_strategy_title", "Balanced"),
        subtitle: t("cc_balanced_strategy_subtitle", "Prefer the best healthy resource and fail over without losing context"),
        systemImage: "dial.medium",
        tint: .blue,
        badge: t("cc_status_automatic", "Automatic")
      ) {
        GalaxySSIRoutingPolicyView()
      }
    }
  }

  private var availableResourcesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_available_resources", "Available Resources"))
      if resources.isEmpty {
        GalaxySSISecurityNavigationRow(
          title: t("cc_add_cloud_provider_title", "Add Cloud Provider"),
          subtitle: t("cc_add_cloud_provider_subtitle", "Configure a phone-direct API resource"),
          systemImage: "cloud",
          tint: .orange,
          badge: t("galaxyssi.common.next_step", "Next")
        ) {
          CloudModelProviderSelectionView()
        }
      } else {
        ForEach(Array(resources.prefix(12))) { resource in
          resourceRow(resource)
        }
      }
    }
  }

  private var rulesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_rules", "Rules"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_route_by_task_title", "Route by Task Type"),
        subtitle: t("cc_route_by_task_subtitle", "Code, real-time, knowledge, privacy, speed, and cost"),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: .galaxySSITextSecondary,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIRoutingPolicyView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_add_cloud_provider_title", "Add Cloud Provider"),
        subtitle: t("cc_add_cloud_provider_subtitle", "Configure a phone-direct API resource"),
        systemImage: "cloud",
        tint: .purple,
        badge: "+"
      ) {
        CloudModelProviderSelectionView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_nodes_title", "Agents, Models & Nodes"),
        subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
        systemImage: "point.3.filled.connected.trianglepath.dotted",
        tint: .blue,
        badge: ""
      ) {
        GalaxySSIAgentsModelsNodesView()
      }
    }
  }

  @ViewBuilder
  private func resourceRow(_ resource: AgentResourceDescriptor) -> some View {
    let title = resource.title
    let subtitle = resourceSubtitle(resource)
    let systemImage = resourceIcon(resource)
    let tint = statusTint(resource.status)
    let badge = statusLabel(resource.status)

    if let contact = routeContact(for: resource) {
      GalaxySSISecurityNavigationRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        assetImage: resourceAssetName(resource),
        tint: tint,
        badge: badge
      ) {
        if contact.deliveryMode == .cloudAPI {
          CloudModelProviderDetailView(contactId: contact.id)
        } else {
          ContactDetailView(contactId: contact.id)
        }
      }
    } else {
      GalaxySSISecurityStatusRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge
      )
    }
  }

  private func metricCard(value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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

  private func routeContact(for resource: AgentResourceDescriptor) -> GalaxySSIContact? {
    let candidates = [resource.targetId, resource.id].flatMap { raw in
      let withoutTarget = raw.hasPrefix("target:") ? String(raw.dropFirst("target:".count)) : raw
      let withoutCloud = withoutTarget.hasPrefix("cloud:") ? String(withoutTarget.dropFirst("cloud:".count)) : withoutTarget
      return [raw, withoutTarget, withoutCloud]
    }
    for candidate in candidates {
      let id = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
      if let contact = store.contact(id: id), !contact.deleted {
        return contact
      }
    }
    return nil
  }

  private func resourceAssetName(_ resource: AgentResourceDescriptor) -> String? {
    let contact = routeContact(for: resource)
    let identityFields = [
      resource.targetId,
      resource.title,
      contact?.id ?? "",
      contact?.galaxySSIId ?? "",
      contact?.name ?? "",
      contact?.displayName ?? "",
      contact?.agentKind ?? "",
      contact?.cloudProvider ?? "",
      contact?.selectedCloudModel?.provider ?? "",
      contact?.selectedCloudModel?.modelId ?? ""
    ]
    if case .cloudModel = resource.type {
      return GalaxySSIAgentAvatarAssetCatalog.cloudProviderAssetName(for: identityFields)
    }
    return GalaxySSIAgentAvatarAssetCatalog.assetName(for: identityFields)
  }

  private func resourceSubtitle(_ resource: AgentResourceDescriptor) -> String {
    let capabilityText = resource.capabilities
      .sorted { $0.rawValue < $1.rawValue }
      .prefix(3)
      .map(capabilityLabel)
      .joined(separator: " / ")
    let profile = String(
      format: t("cc_agent_cost_latency", "%@ / %@"),
      costLabel(resource.cost),
      latencyLabel(resource.latency)
    )
    let route = "\(kindLabel(resource.type)) / \(locationLabel(resource.location))"
    return capabilityText.isEmpty ? "\(route) / \(profile)" : "\(capabilityText) / \(profile)"
  }

  private func resourceIcon(_ resource: AgentResourceDescriptor) -> String {
    switch resource.type {
    case .cloudModel: return "cloud"
    case .remoteLocalModel, .onDeviceModel: return "cpu"
    case .remoteAgent, .localAgent: return GalaxySSISecurityFormatter.agentSystemImage(id: resource.targetId, kind: resource.type.rawValue)
    case .customDevice, .homeAssistant: return "antenna.radiowaves.left.and.right"
    case .knowledge: return "book.closed"
    default: return "slider.horizontal.3"
    }
  }

  private func statusLabel(_ status: AgentConnectorStatus) -> String {
    switch status {
    case .available: return t("cc_status_available", "Available")
    case .needsSetup: return t("galaxyssi.status.needs_setup", "Needs Setup")
    case .disconnected: return t("status_disconnected", "Disconnected")
    }
  }

  private func statusTint(_ status: AgentConnectorStatus) -> Color {
    switch status {
    case .available: return .galaxySSIAccent
    case .needsSetup: return .orange
    case .disconnected: return .galaxySSITextSecondary
    }
  }

  private func costLabel(_ cost: AgentResourceCost) -> String {
    switch cost {
    case .free: return t("cc_agent_cost_free", "Free")
    case .low: return t("cc_agent_cost_low", "Low cost")
    case .medium: return t("cc_agent_cost_medium", "Medium cost")
    case .high: return t("cc_agent_cost_high", "High cost")
    }
  }

  private func latencyLabel(_ latency: AgentResourceLatency) -> String {
    switch latency {
    case .instant: return t("cc_agent_latency_instant", "Instant")
    case .fast: return t("cc_agent_latency_fast", "Fast")
    case .normal: return t("cc_agent_latency_normal", "Normal")
    case .slow: return t("cc_agent_latency_slow", "Slow")
    }
  }

  private func capabilityLabel(_ capability: AgentCapability) -> String {
    switch capability {
    case .chat: return t("cc_capability_chat", "Chat")
    case .reasoning: return t("cc_capability_reasoning", "Reasoning")
    case .liveData: return t("cc_capability_live_data", "Live data")
    case .toolUse: return t("cc_capability_tool_use", "Tool use")
    case .mcp: return t("cc_capability_mcp", "MCP")
    case .skill: return t("cc_capability_skill", "Skill")
    case .localInference: return t("cc_capability_local_inference", "Local inference")
    case .research: return t("cc_capability_research", "Research")
    case .code: return t("cc_capability_code", "Code")
    case .taskExecution: return t("cc_capability_task_execution", "Task execution")
    case .smartHome: return t("cc_capability_smart_home", "Smart home")
    case .deviceControl: return t("cc_capability_device_control", "Device control")
    case .knowledgeSearch: return t("cc_capability_knowledge_search", "Knowledge search")
    case .screenReading: return t("cc_capability_screen_reading", "Screen reading")
    case .clipboard: return t("cc_capability_clipboard", "Clipboard")
    case .systemSettings: return t("cc_capability_system_settings", "System settings")
    case .appNavigation: return t("cc_capability_app_navigation", "App navigation")
    case .alarm: return t("cc_capability_alarm", "Alarm")
    }
  }

  private func kindLabel(_ type: AgentResourceType) -> String {
    switch type {
    case .cloudModel, .remoteLocalModel, .onDeviceModel:
      return t("cc_kind_model", "Model")
    case .localAgent, .remoteAgent:
      return t("cc_kind_agent", "Agent")
    case .customDevice, .homeAssistant:
      return t("cc_kind_device", "Device")
    case .knowledge:
      return t("cc_kind_knowledge", "Knowledge")
    default:
      return t("cc_kind_tool", "Tool")
    }
  }

  private func locationLabel(_ location: AgentResourceLocation) -> String {
    switch location {
    case .phone: return t("cc_privacy_location_phone", "Phone")
    case .trustedDesktop: return t("cc_privacy_location_desktop", "Trusted Desktop")
    case .privateNetwork: return t("cc_privacy_location_private", "Private Network")
    case .cloud: return t("cc_privacy_location_cloud", "Cloud")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
