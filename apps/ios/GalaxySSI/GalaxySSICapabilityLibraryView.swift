import SwiftUI

enum GalaxySSICapabilityLibraryKind: String, CaseIterable, Identifiable {
  case nativeTools
  case mcp
  case automation

  var id: String { rawValue }
}

struct GalaxySSICapabilityLibraryView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var selectedKind: GalaxySSICapabilityLibraryKind = .nativeTools
  @State private var desktopMarketplaceRevision = 0
  @State private var mcpRevision = 0

  init(initialKind: GalaxySSICapabilityLibraryKind = .nativeTools) {
    _selectedKind = State(initialValue: initialKind)
  }

  private var nativeTools: [AgentNativeToolDescriptor] {
    AgentPhoneNativeToolCatalog.descriptors(
      capabilityStatuses: AgentPhoneCapabilityCatalog.declaredStatuses()
    )
    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  private var mcpConnections: [AgentMcpConnection] {
    GalaxySSIMcpControlStores.makeRegistry().list()
  }

  private var automationTasks: [AgentProactiveTask] {
    store.automationTasks()
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("agent_capability_library_title", "Capability Library"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("agent_capability_library_title", "Capability Library"),
            subtitle: t(
              "agent_capability_library_subtitle",
              "Manage phone tools, MCP connections, and reusable automation from one place"
            ),
            systemImage: "shippingbox.and.arrow.down",
            tint: .galaxySSIAccent,
            badge: String(format: t("galaxyssi.capability_library.total", "%d types"), GalaxySSICapabilityLibraryKind.allCases.count)
          )

          Picker(
            t("galaxyssi.capability_library.tabs", "Capability type"),
            selection: $selectedKind
          ) {
            Text(t("galaxyssi.capability_library.native_tools", "Native Tools"))
              .tag(GalaxySSICapabilityLibraryKind.nativeTools)
            Text(t("agent_mcp_title", "MCP"))
              .tag(GalaxySSICapabilityLibraryKind.mcp)
            Text(t("galaxyssi.automation.title", "Automation"))
              .tag(GalaxySSICapabilityLibraryKind.automation)
          }
          .pickerStyle(.segmented)
          .accessibilityLabel(t("galaxyssi.capability_library.tabs", "Capability type"))

          selectedContent
            .id("\(desktopMarketplaceRevision)-\(mcpRevision)")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIDesktopMarketplaceDidUpdate)) { _ in
      desktopMarketplaceRevision += 1
    }
    .onAppear {
      mcpRevision += 1
    }
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedKind {
    case .nativeTools:
      nativeToolsContent
    case .mcp:
      mcpContent
    case .automation:
      automationContent
    }
  }

  private var nativeToolsContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.capability_library.native_section", "Phone Native Tools"))
      GalaxySSISecurityStatusRow(
        title: String(format: t("galaxyssi.capability_library.native_summary", "%d tools / %d available"), nativeTools.count, nativeTools.filter(isAvailable).count),
        subtitle: t("galaxyssi.capability_library.native_subtitle", "Built-in iOS tools stay inside the local permission and confirmation boundary"),
        systemImage: "iphone.and.arrow.forward",
        tint: .galaxySSIAccent,
        badge: t("agent_marketplace_built_in", "Built in")
      )
      ForEach(nativeTools) { tool in
        GalaxySSISecurityNavigationRow(
          title: tool.title,
          subtitle: tool.description,
          systemImage: "wrench.and.screwdriver",
          tint: isAvailable(tool) ? .galaxySSIAccent : .orange,
          badge: statusLabel(tool)
        ) {
          GalaxySSINativeToolDetailView(tool: tool)
        }
      }
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.capability_library.open_native_catalog", "Open Native Tool Catalog"),
        subtitle: t("galaxyssi.capability_library.open_native_catalog_subtitle", "Review every tool, schema, risk, permission, and consent"),
        systemImage: "list.bullet.rectangle",
        tint: .blue,
        badge: "\(nativeTools.count)"
      ) {
        GalaxySSINativeToolCatalogView()
      }
      desktopMarketplaceContent(kind: .nativeTool)
    }
  }

  private var mcpContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.capability_library.mcp_section", "MCP Services"))
      GalaxySSISecurityStatusRow(
        title: String(format: t("galaxyssi.capability_library.mcp_summary", "%d installed connections"), mcpConnections.count),
        subtitle: t("galaxyssi.capability_library.mcp_subtitle", "Connect remote services or install verified local MCP packages"),
        systemImage: "shippingbox",
        tint: .blue,
        badge: mcpConnections.isEmpty ? t("agent_capability_requires_setup", "Setup") : t("status_ready", "Ready")
      )
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.capability_library.open_mcp", "Manage MCP"),
        subtitle: t("galaxyssi.capability_library.open_mcp_subtitle", "Add services, install packages, test connections, and review permissions"),
        systemImage: "slider.horizontal.3",
        tint: .blue,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIMcpControlCenterView()
      }
      GalaxySSISecuritySectionTitle(
        title: t("galaxyssi.capability_library.mcp_recommended", "Recommended MCP")
      )
      ForEach(mcpMarketplaceItems) { item in
        mcpMarketplaceRow(item)
      }
      desktopMarketplaceContent(kind: .mcp)
    }
  }

  private var mcpMarketplaceItems: [AgentMarketplaceItem] {
    AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: nativeTools,
      installedMcp: mcpConnections,
      installedAutomations: []
    )
    .filter { $0.kind == .mcp }
    .sorted {
      if $0.featured != $1.featured { return $0.featured && !$1.featured }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  @ViewBuilder
  private func mcpMarketplaceRow(_ item: AgentMarketplaceItem) -> some View {
    let connection = mcpConnections.first { $0.catalogId == item.id }
    if let connection {
      GalaxySSISecurityNavigationRow(
        title: item.name,
        subtitle: mcpMarketplaceSummary(item),
        systemImage: mcpMarketplaceSystemImage(item),
        tint: item.revoked ? .orange : .blue,
        badge: mcpMarketplaceStatus(item)
      ) {
        GalaxySSIMcpConnectionDetailView(
          connectionId: connection.id,
          onChanged: { mcpRevision += 1 }
        )
      }
    } else if let entry = AgentDefaultCapabilityCatalog.mcp(item.id), !entry.requiresPackage {
      GalaxySSISecurityNavigationRow(
        title: item.name,
        subtitle: mcpMarketplaceSummary(item),
        systemImage: mcpMarketplaceSystemImage(item),
        tint: .blue,
        badge: mcpMarketplaceStatus(item)
      ) {
        GalaxySSIMcpRemoteSetupView(entry: entry, onSaved: { mcpRevision += 1 })
      }
    } else {
      GalaxySSISecurityNavigationRow(
        title: item.name,
        subtitle: mcpMarketplaceSummary(item),
        systemImage: mcpMarketplaceSystemImage(item),
        tint: .orange,
        badge: mcpMarketplaceStatus(item)
      ) {
        GalaxySSIMcpControlCenterView()
      }
    }
  }

  private func mcpMarketplaceSummary(_ item: AgentMarketplaceItem) -> String {
    var parts = [String(format: t("agent_marketplace_version", "v%@"), item.availableVersion)]
    if !item.capabilities.isEmpty {
      parts.append(String(format: t("agent_marketplace_capability_count", "%d capabilities"), item.capabilities.count))
    }
    if !item.permissions.isEmpty {
      parts.append(String(format: t("agent_marketplace_permission_count", "%d permissions"), item.permissions.count))
    }
    if !item.summary.isBlank {
      parts.append(localizedMcpSummary(item.id, fallback: item.summary))
    }
    return parts.joined(separator: " / ")
  }

  private func mcpMarketplaceStatus(_ item: AgentMarketplaceItem) -> String {
    if item.revoked {
      return t("agent_marketplace_access_revoked", "Access revoked")
    }
    if item.updateAvailable {
      return t("agent_marketplace_update", "Update")
    }
    switch item.installState {
    case .builtIn:
      return t("agent_marketplace_built_in", "Built in")
    case .available:
      return t("agent_capability_add", "Add")
    case .installed:
      return t("agent_capability_added", "Added")
    case .needsSetup:
      return t("agent_capability_requires_setup", "Setup")
    case .unavailable:
      return t("badge_unavailable", "Unavailable")
    }
  }

  private func mcpMarketplaceSystemImage(_ item: AgentMarketplaceItem) -> String {
    if item.id.contains("github") { return "chevron.left.forwardslash.chevron.right" }
    if item.id.contains("notion") { return "doc.text" }
    if item.id.contains("home_assistant") { return "house" }
    if item.requiresLocalPackage { return "shippingbox" }
    return "link"
  }

  private func localizedMcpSummary(_ id: String, fallback: String) -> String {
    switch id {
    case "galaxyssi.mcp.github":
      return t("agent_mcp_catalog_github", fallback)
    case "galaxyssi.mcp.notion":
      return t("agent_mcp_catalog_notion", fallback)
    case "galaxyssi.mcp.home_assistant":
      return t("agent_mcp_catalog_home_assistant", fallback)
    case "galaxyssi.mcp.relay_controller":
      return t("agent_mcp_catalog_relay", fallback)
    case "galaxyssi.catalog.deep-research":
      return t("agent_skill_catalog_research", fallback)
    case "galaxyssi.catalog.device-health":
      return t("agent_skill_catalog_device_health", fallback)
    case "galaxyssi.catalog.github-triage":
      return t("agent_skill_catalog_github", fallback)
    case "galaxyssi.catalog.notion-brief":
      return t("agent_skill_catalog_notion", fallback)
    case "galaxyssi.catalog.smart-home-routine":
      return t("agent_skill_catalog_smart_home", fallback)
    default:
      return fallback
    }
  }

  private var automationContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.capability_library.automation_section", "Reusable Automation"))
      GalaxySSISecurityStatusRow(
        title: String(format: t("galaxyssi.capability_library.automation_summary", "%d proactive tasks"), automationTasks.count),
        subtitle: t("galaxyssi.capability_library.automation_subtitle", "Create workflows, schedules, and device event triggers that can run after the app restarts"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: .orange,
        badge: automationTasks.filter { $0.enabled }.isEmpty ? t("common_off", "Off") : t("status_enabled", "Enabled")
      )
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.skill_marketplace.title", "Skill Marketplace"),
        subtitle: t("galaxyssi.skill_marketplace.settings_subtitle", "Install, enable, and review reusable Agent Skills"),
        systemImage: "sparkles.rectangle.stack",
        tint: .purple,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSISkillMarketplaceView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.capability_library.open_automation", "Manage Automation"),
        subtitle: t("galaxyssi.capability_library.open_automation_subtitle", "Review tasks, workflows, schedules, triggers, and recent runs"),
        systemImage: "clock",
        tint: .orange,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIAutomationView()
      }
      desktopMarketplaceContent(kind: .automation)
    }
  }

  @ViewBuilder
  private func desktopMarketplaceContent(kind: AgentCapabilityCatalogKind) -> some View {
    let items = coordinator.desktopMarketplaceItems(kind: kind)
    if !items.isEmpty {
      GalaxySSISecuritySectionTitle(title: t("agent_marketplace_desktop_title", "Desktop Marketplace"))
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        GalaxySSISecurityStatusRow(
          title: item.name,
          subtitle: desktopMarketplaceSummary(item),
          systemImage: desktopMarketplaceSystemImage(item),
          tint: desktopMarketplaceTint(item),
          badge: desktopMarketplaceStatus(item)
        )
      }
    }
  }

  private func desktopMarketplaceSummary(_ item: AgentDesktopMarketplaceItem) -> String {
    let version = !item.installedVersion.isEmpty && item.installedVersion != item.availableVersion
      ? "\(item.installedVersion) -> \(item.availableVersion)"
      : item.availableVersion
    var parts = [
      item.desktopName,
      String(format: t("agent_marketplace_version", "v%@"), version)
    ]
    if !item.capabilities.isEmpty {
      parts.append(String(format: t("agent_marketplace_capability_count", "%d capabilities"), item.capabilities.count))
    }
    if !item.permissionDiff.added.isEmpty {
      parts.append(String(format: t("agent_marketplace_new_permission_count", "%d new permissions"), item.permissionDiff.added.count))
    } else if !item.permissions.isEmpty {
      parts.append(String(format: t("agent_marketplace_permission_count", "%d permissions"), item.permissions.count))
    }
    if !item.summary.isBlank {
      parts.append(item.summary)
    }
    return parts.joined(separator: " / ")
  }

  private func desktopMarketplaceStatus(_ item: AgentDesktopMarketplaceItem) -> String {
    if item.revoked {
      return t("agent_marketplace_access_revoked", "Access revoked")
    }
    if item.updateAvailable {
      return t("agent_marketplace_update", "Update")
    }
    switch item.installState {
    case .builtIn:
      return t("agent_marketplace_built_in", "Built in")
    case .available:
      return t("agent_capability_install", "Install")
    case .installed:
      return item.enabled
        ? t("agent_capability_added", "Added")
        : t("agent_marketplace_disabled", "Disabled")
    case .needsSetup:
      return t("agent_capability_requires_setup", "Setup")
    case .unavailable:
      return t("badge_unavailable", "Unavailable")
    }
  }

  private func desktopMarketplaceSystemImage(_ item: AgentDesktopMarketplaceItem) -> String {
    switch item.kind {
    case .nativeTool:
      return "wrench.and.screwdriver"
    case .mcp:
      return "shippingbox"
    case .automation:
      return "arrow.triangle.2.circlepath"
    }
  }

  private func desktopMarketplaceTint(_ item: AgentDesktopMarketplaceItem) -> Color {
    if item.revoked || item.installState == .unavailable {
      return .orange
    }
    if item.installState == .needsSetup {
      return .yellow
    }
    return .blue
  }

  private func isAvailable(_ tool: AgentNativeToolDescriptor) -> Bool {
    tool.risk != .blocked && tool.availability.status == .available
  }

  private func statusLabel(_ tool: AgentNativeToolDescriptor) -> String {
    switch tool.availability.status {
    case .available:
      return t("galaxyssi.capability_library.available", "Available")
    case .requiresSetup:
      return t("agent_capability_requires_setup", "Setup")
    case .unavailable:
      return t("badge_unavailable", "Unavailable")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
