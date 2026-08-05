import SwiftUI

struct SignalASIResourceRoutingView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  private var targets: [AgentCallableTarget] {
    store.visibleContacts
      .map(callableTarget)
      .filter { $0.id != "phone" && $0.id != "local-system" && $0.id != "cloud-models" }
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
      SignalASITopBar(
        title: t("cc_resource_routing_title", "Models & Resource Routing"),
        leading: { SignalASIBackButton() },
        trailing: {
          Image(systemName: "slider.horizontal.3")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
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
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var banner: some View {
    let hasResources = availableCount > 0
    return SignalASISecurityHeroView(
      title: t(hasResources ? "cc_routing_enabled" : "cc_no_resources_title", hasResources ? "Automatic routing is enabled" : "No intelligence resource is currently available"),
      subtitle: t(hasResources ? "cc_routing_enabled_subtitle" : "cc_no_resources_subtitle", hasResources ? "Selects by task fit, health, latency, privacy, and cost" : "Configure a cloud API or pair a Desktop Agent to run remote tasks"),
      systemImage: "slider.horizontal.3",
      tint: hasResources ? .blue : .orange,
      badge: hasResources ? t("cc_status_available", "Available") : t("signalasi.status.needs_setup", "Needs Setup")
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
      SignalASISecuritySectionTitle(title: t("cc_section_current_strategy", "Current Strategy"))
      SignalASISecurityNavigationRow(
        title: t("cc_balanced_strategy_title", "Balanced"),
        subtitle: t("cc_balanced_strategy_subtitle", "Prefer the best healthy resource and fail over without losing context"),
        systemImage: "dial.medium",
        tint: .blue,
        badge: t("cc_status_automatic", "Automatic")
      ) {
        AgentModelPlannerSettingsView()
      }
    }
  }

  private var availableResourcesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_available_resources", "Available Resources"))
      if resources.isEmpty {
        SignalASISecurityNavigationRow(
          title: t("cc_add_cloud_provider_title", "Add Cloud Provider"),
          subtitle: t("cc_add_cloud_provider_subtitle", "Configure a phone-direct API resource"),
          systemImage: "cloud",
          tint: .orange,
          badge: t("signalasi.common.next_step", "Next")
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
      SignalASISecuritySectionTitle(title: t("cc_section_rules", "Rules"))
      SignalASISecurityNavigationRow(
        title: t("cc_route_by_task_title", "Route by Task Type"),
        subtitle: t("cc_route_by_task_subtitle", "Code, real-time, knowledge, privacy, speed, and cost"),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: .signalASITextSecondary,
        badge: t("signalasi.common.view", "View")
      ) {
        AgentModelPlannerSettingsView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_add_cloud_provider_title", "Add Cloud Provider"),
        subtitle: t("cc_add_cloud_provider_subtitle", "Configure a phone-direct API resource"),
        systemImage: "cloud",
        tint: .purple,
        badge: "+"
      ) {
        CloudModelProviderSelectionView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_nodes_title", "Agents, Models & Nodes"),
        subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
        systemImage: "point.3.filled.connected.trianglepath.dotted",
        tint: .blue,
        badge: ""
      ) {
        SignalASIContactDirectoryActionsView()
      }
    }
  }

  private func resourceRow(_ resource: AgentResourceDescriptor) -> some View {
    SignalASISecurityStatusRow(
      title: resource.title,
      subtitle: resourceSubtitle(resource),
      systemImage: resourceIcon(resource),
      tint: statusTint(resource.status),
      badge: statusLabel(resource.status)
    )
  }

  private func metricCard(value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
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

  private func callableTarget(_ contact: SignalASIContact) -> AgentCallableTarget {
    let status = connectorStatus(contact)
    let kind = connectorKind(contact)
    return AgentCallableTarget(
      id: contact.id,
      title: contact.displayName.ifBlank(contact.name).ifBlank(contact.id),
      kind: kind,
      status: status,
      capabilities: capabilities(contact, kind: kind),
      failureDomain: failureDomain(contact, kind: kind),
      adapterType: adapterType(contact),
      desktopAccessProfile: contact.desktopName,
      providerProfile: contact.deliveryMode == .cloudAPI
        ? ProviderProfileCatalog.fromCloudContact(contact, status: status)
        : nil
    )
  }

  private func connectorKind(_ contact: SignalASIContact) -> AgentConnectorKind {
    if contact.deliveryMode == .cloudAPI { return .model }
    if contact.type == "device" { return .device }
    return .agent
  }

  private func connectorStatus(_ contact: SignalASIContact) -> AgentConnectorStatus {
    let status = contact.setupStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if contact.deliveryMode == .cloudAPI {
      guard let model = contact.selectedCloudModel else { return .needsSetup }
      return CloudModelCredentialPolicy.isAutoRoutable(
        model: model,
        apiKey: store.apiKey(for: model),
        provider: contact.cloudProvider,
        setupStatus: contact.setupStatus
      ) ? .available : .needsSetup
    }
    if status == "ready" || status == "verified" {
      return .available
    }
    if status.contains("needs") || status == "pairing" || contact.trustState != .verified {
      return .needsSetup
    }
    return .disconnected
  }

  private func capabilities(_ contact: SignalASIContact, kind: AgentConnectorKind) -> [AgentCapability] {
    switch kind {
    case .model:
      return [.chat, .reasoning, .toolUse, .liveData]
    case .device:
      return [.deviceControl, .appNavigation]
    case .knowledge:
      return [.knowledgeSearch]
    case .agent:
      if contact.deliveryMode == .link {
        return [.chat, .reasoning, .toolUse, .taskExecution]
      }
      return [.chat, .reasoning]
    }
  }

  private func failureDomain(_ contact: SignalASIContact, kind: AgentConnectorKind) -> String {
    if kind == .model {
      return "cloud-model:\(contact.cloudProvider.ifBlank(contact.id))"
    }
    if !contact.desktopId.isBlank {
      return "desktop:\(contact.desktopId)"
    }
    return "contact:\(contact.id)"
  }

  private func adapterType(_ contact: SignalASIContact) -> String {
    switch contact.deliveryMode {
    case .cloudAPI: return "cloud-api"
    case .link: return "signalasi-link"
    case .local: return "local"
    }
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
    case .remoteAgent, .localAgent: return SignalASISecurityFormatter.agentSystemImage(id: resource.targetId, kind: resource.type.rawValue)
    case .customDevice, .homeAssistant: return "antenna.radiowaves.left.and.right"
    case .knowledge: return "book.closed"
    default: return "slider.horizontal.3"
    }
  }

  private func statusLabel(_ status: AgentConnectorStatus) -> String {
    switch status {
    case .available: return t("cc_status_available", "Available")
    case .needsSetup: return t("signalasi.status.needs_setup", "Needs Setup")
    case .disconnected: return t("status_disconnected", "Disconnected")
    }
  }

  private func statusTint(_ status: AgentConnectorStatus) -> Color {
    switch status {
    case .available: return .signalASIAccent
    case .needsSetup: return .orange
    case .disconnected: return .signalASITextSecondary
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
