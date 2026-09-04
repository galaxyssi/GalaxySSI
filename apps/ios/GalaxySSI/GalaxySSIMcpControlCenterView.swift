import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct GalaxySSIMcpControlCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var connections: [AgentMcpConnection] = []
  @State private var statusMessage = ""
  @State private var statusIsError = false
  @State private var importingPackage = false

  private let registry = GalaxySSIMcpControlStores.makeRegistry()

  private var readyCount: Int {
    let now = GalaxySSIMcpControlStores.nowMillis()
    return connections.filter { $0.isCallable(nowMillis: now) }.count
  }

  private var marketplaceItems: [AgentMarketplaceItem] {
    AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: AgentPhoneNativeToolCatalog.descriptors(),
      installedMcp: connections,
      installedAutomations: []
    )
    .filter { $0.kind == .mcp }
    .sorted {
      if $0.featured != $1.featured { return $0.featured && !$1.featured }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("agent_mcp_title", "MCP"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("agent_capability_library_title", "Tool Marketplace"),
            subtitle: t("agent_mcp_control_center_subtitle", "External tools, services, and device connectors"),
            systemImage: "shippingbox",
            tint: .blue,
            badge: String(format: t("galaxyssi.mcp.connection_count", "%d connections"), connections.count)
          )

          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: statusIsError
                ? t("agent_mcp_status_error", "Error")
                : t("galaxyssi.mcp.latest_change", "Latest change"),
              subtitle: statusMessage,
              systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
              tint: statusIsError ? .red : .galaxySSIAccent,
              badge: statusIsError
                ? t("agent_mcp_status_error", "Error")
                : t("galaxyssi.status.ready", "Ready")
            )
          }

          overviewSection
          addSection
          installedSection
          recommendedSection
          desktopMarketplaceSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIDesktopMarketplaceDidUpdate)) { _ in
      refresh()
    }
    .fileImporter(
      isPresented: $importingPackage,
      allowedContentTypes: [.zip, .data, .item],
      allowsMultipleSelection: false
    ) { result in
      handlePackageImport(result)
    }
  }

  private var overviewSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.mcp.section_overview", "Overview"))
      GalaxySSISecurityStatusRow(
        title: t("agent_mcp_tools", "Tools"),
        subtitle: String(
          format: t("galaxyssi.mcp.summary", "%d installed / %d ready / %d recommended"),
          connections.count,
          readyCount,
          marketplaceItems.count
        ),
        systemImage: "wrench.and.screwdriver",
        tint: .galaxySSIAccent,
        badge: readyCount > 0
          ? t("status_ready", "Ready")
          : t("agent_capability_requires_setup", "Setup")
      )
      GalaxySSISecurityNavigationRow(
        title: t("galaxyssi.native_tool_catalog.title", "Native Tools"),
        subtitle: t("cc_global_autonomous_tools_subtitle", "Allow the global Agent to call phone tools and MCP within local permission and confirmation policy"),
        systemImage: "iphone.and.arrow.forward",
        tint: .purple,
        badge: String(format: t("galaxyssi.native_tool_catalog.badge", "%d tools"), AgentPhoneNativeToolCatalog.descriptors().count)
      ) {
        GalaxySSINativeToolCatalogView()
      }
    }
  }

  private var addSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.mcp.section_add", "Add MCP"))
      GalaxySSISecurityNavigationRow(
        title: t("agent_mcp_add_remote", "Add Remote MCP"),
        subtitle: t("agent_mcp_add_remote_subtitle", "Connect a Streamable HTTP MCP service by URL"),
        systemImage: "link",
        tint: .blue,
        badge: t("agent_mcp_remote_badge", "Remote")
      ) {
        GalaxySSIMcpRemoteSetupView(entry: nil, onSaved: refresh)
      }
      GalaxySSISecurityActionRow(
        title: t("agent_mcp_install_package", "Install Local MCP Package"),
        subtitle: t("agent_mcp_install_package_subtitle", "Select a verified .sasi-mcp declarative package"),
        systemImage: "square.and.arrow.down",
        tint: .orange,
        badge: t("common_select", "Select")
      ) {
        importingPackage = true
      }
    }
  }

  private var installedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_capability_installed", "Installed"))
      if connections.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("agent_mcp_empty", "No MCP connections"),
          subtitle: t("agent_mcp_empty_subtitle", "Add a recommended service, server URL, or local package"),
          systemImage: "shippingbox",
          tint: .galaxySSITextSecondary,
          badge: ""
        )
      } else {
        ForEach(connections) { connection in
          GalaxySSISecurityNavigationRow(
            title: connection.displayName,
            subtitle: connectionSubtitle(connection),
            systemImage: mcpSystemImage(connection),
            tint: connectionTint(connection),
            badge: connectionStatus(connection)
          ) {
            GalaxySSIMcpConnectionDetailView(connectionId: connection.id, onChanged: refresh)
          }
        }
      }
    }
  }

  private var recommendedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_capability_recommended", "Recommended"))
      ForEach(marketplaceItems) { item in
        if let connection = connections.first(where: { $0.catalogId == item.id }) {
          GalaxySSISecurityNavigationRow(
            title: item.name,
            subtitle: marketplaceSummary(item),
            systemImage: marketplaceSystemImage(item),
            tint: item.revoked ? .orange : .blue,
            badge: itemStatus(item)
          ) {
            GalaxySSIMcpConnectionDetailView(connectionId: connection.id, onChanged: refresh)
          }
        } else if let entry = AgentDefaultCapabilityCatalog.mcp(item.id), entry.requiresPackage {
          GalaxySSISecurityActionRow(
            title: item.name,
            subtitle: marketplaceSummary(item),
            systemImage: marketplaceSystemImage(item),
            tint: .orange,
            badge: t("agent_capability_install", "Install")
          ) {
            importingPackage = true
          }
        } else if let entry = AgentDefaultCapabilityCatalog.mcp(item.id) {
          GalaxySSISecurityNavigationRow(
            title: item.name,
            subtitle: marketplaceSummary(item),
            systemImage: marketplaceSystemImage(item),
            tint: .blue,
            badge: t("agent_capability_add", "Add")
          ) {
            GalaxySSIMcpRemoteSetupView(entry: entry, onSaved: refresh)
          }
        }
      }
    }
  }

  private var desktopMarketplaceSection: some View {
    let items = coordinator.desktopMarketplaceItems()
    return VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_marketplace_desktop_title", "Desktop Marketplace"))
      if items.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("agent_marketplace_desktop_empty", "No Desktop capabilities available"),
          subtitle: t(
            "agent_marketplace_desktop_empty_subtitle",
            "Pair a Desktop and wait for its capability manifest to appear here"
          ),
          systemImage: "desktopcomputer",
          tint: .galaxySSITextSecondary,
          badge: t("agent_marketplace_desktop_waiting", "Waiting")
        )
      } else {
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
  }

  private func handlePackageImport(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else { return }
      let didAccess = url.startAccessingSecurityScopedResource()
      defer {
        if didAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
      let data = try Data(contentsOf: url)
      let inspection = try AgentMcpPackageInstaller().inspect(data)
      guard let repository = GalaxySSIMcpControlStores.makePackageRepository() else {
        throw AgentRuntimeCapabilityError.invalid("MCP package storage is unavailable")
      }
      try repository.save(inspection)
      let connection = try registry.installPackage(
        inspection.manifest,
        packageSha256: inspection.packageSha256
      )
      if connection.authProfile.method != .none {
        _ = try registry.beginAuthentication(connection.id)
      }
      refresh()
      setStatus(
        String(format: t("galaxyssi.mcp.package_installed", "%@ installed"), connection.displayName),
        isError: false
      )
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private func refresh() {
    connections = registry.list()
  }

  private func setStatus(_ message: String, isError: Bool) {
    statusMessage = message
    statusIsError = isError
  }

  private func marketplaceSummary(_ item: AgentMarketplaceItem) -> String {
    var parts = [String]()
    parts.append(String(format: t("agent_marketplace_version", "v%@"), item.availableVersion))
    if !item.capabilities.isEmpty {
      parts.append(String(format: t("agent_marketplace_capability_count", "%d capabilities"), item.capabilities.count))
    }
    if !item.permissionDiff.added.isEmpty {
      parts.append(String(format: t("agent_marketplace_new_permission_count", "%d new permissions"), item.permissionDiff.added.count))
    } else if !item.permissions.isEmpty {
      parts.append(String(format: t("agent_marketplace_permission_count", "%d permissions"), item.permissions.count))
    }
    if !item.summary.isBlank {
      parts.append(localizedMcpSummary(item.id, fallback: item.summary))
    }
    return parts.joined(separator: " / ")
  }

  private func itemStatus(_ item: AgentMarketplaceItem) -> String {
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
      return t("agent_capability_added", "Added")
    case .needsSetup:
      return t("agent_capability_requires_setup", "Setup")
    case .unavailable:
      return t("badge_unavailable", "Unavailable")
    }
  }

  private func desktopMarketplaceSummary(_ item: AgentDesktopMarketplaceItem) -> String {
    var parts = [item.desktopName, String(format: t("agent_marketplace_version", "v%@"), item.availableVersion)]
    if !item.capabilities.isEmpty {
      parts.append(String(format: t("agent_marketplace_capability_count", "%d capabilities"), item.capabilities.count))
    }
    if !item.permissions.isEmpty {
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

  private func connectionSubtitle(_ connection: AgentMcpConnection) -> String {
    [
      connection.distribution == .localPackage
        ? t("agent_mcp_local_package_badge", "Local package")
        : t("agent_mcp_remote_badge", "Remote"),
      authMethodLabel(connection.authProfile.method),
      connection.lastError.nilIfEmpty
    ]
    .compactMap { $0 }
    .joined(separator: " / ")
  }

  private func connectionStatus(_ connection: AgentMcpConnection) -> String {
    mcpConnectionStatus(connection, language: interfaceLanguage)
  }

  private func connectionTint(_ connection: AgentMcpConnection) -> Color {
    connection.isCallable(nowMillis: GalaxySSIMcpControlStores.nowMillis()) ? .galaxySSIAccent : .orange
  }

  private func authMethodLabel(_ method: AgentMcpAuthMethod) -> String {
    mcpAuthMethodLabel(method, language: interfaceLanguage)
  }

  private func marketplaceSystemImage(_ item: AgentMarketplaceItem) -> String {
    if item.id.contains("github") { return "chevron.left.forwardslash.chevron.right" }
    if item.id.contains("notion") { return "doc.text" }
    if item.id.contains("home_assistant") { return "house" }
    if item.requiresLocalPackage { return "shippingbox" }
    return "link"
  }

  private func mcpSystemImage(_ connection: AgentMcpConnection) -> String {
    if connection.catalogId.contains("github") { return "chevron.left.forwardslash.chevron.right" }
    if connection.catalogId.contains("notion") { return "doc.text" }
    if connection.catalogId.contains("home_assistant") { return "house" }
    if connection.distribution == .localPackage { return "shippingbox" }
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
    default:
      return fallback
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIMcpRemoteSetupView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var entry: AgentMcpCatalogEntry?
  var onSaved: () -> Void

  @State private var displayName = ""
  @State private var endpoint = ""
  @State private var selectedAuthMethod: AgentMcpAuthMethod = .none
  @State private var statusMessage = ""
  @State private var statusIsError = false
  @State private var createdConnectionId = ""
  @State private var openCreatedConnection = false

  private let registry = GalaxySSIMcpControlStores.makeRegistry()

  private var authProfiles: [AgentMcpAuthProfile] {
    entry?.authProfiles ?? GalaxySSIMcpControlStores.defaultAuthProfiles()
  }

  private var selectedProfile: AgentMcpAuthProfile? {
    authProfiles.first { $0.method == selectedAuthMethod } ?? authProfiles.first
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("agent_mcp_add_remote", "Add Remote MCP"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: entry?.name ?? t("agent_mcp_custom_server", "Custom MCP Server"),
            subtitle: entry.map { localizedMcpSummary($0.id, fallback: $0.summary) }
              ?? t("agent_mcp_custom_server_subtitle", "Connect any compatible Streamable HTTP MCP endpoint"),
            systemImage: "link",
            tint: .blue,
            badge: t("agent_mcp_remote_badge", "Remote")
          )

          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: statusIsError
                ? t("agent_mcp_add_failed", "Unable to add MCP service")
                : t("galaxyssi.mcp.latest_change", "Latest change"),
              subtitle: statusMessage,
              systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
              tint: statusIsError ? .red : .galaxySSIAccent,
              badge: statusIsError
                ? t("agent_mcp_status_error", "Error")
                : t("galaxyssi.status.ready", "Ready")
            )
          }

          formSection

          GalaxySSISecurityPrimaryButton(
            title: t("agent_mcp_continue", "Continue"),
            systemImage: "arrow.right",
            tint: .galaxySSIAccent,
            action: save
          )

          NavigationLink(
            destination: GalaxySSIMcpConnectionDetailView(connectionId: createdConnectionId, onChanged: onSaved),
            isActive: $openCreatedConnection
          ) {
            EmptyView()
          }
          .hidden()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: loadDefaults)
  }

  private var formSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_mcp_endpoint", "Endpoint"))
      labeledTextField(
        title: t("agent_mcp_server_name", "Name"),
        placeholder: t("agent_mcp_server_name_hint", "My MCP service"),
        text: $displayName
      )
      labeledTextField(
        title: t("agent_mcp_server_url", "Server URL"),
        placeholder: "https://example.com/mcp",
        text: $endpoint
      )
      Menu {
        ForEach(authProfiles, id: \.method) { profile in
          Button(mcpAuthMethodLabel(profile.method, language: interfaceLanguage)) {
            selectedAuthMethod = profile.method
          }
        }
      } label: {
        GalaxySSISecurityStatusRow(
          title: t("agent_mcp_auth_method", "Authentication"),
          subtitle: t("agent_mcp_sign_in_subtitle", "Only enter fields required by this service"),
          systemImage: "lock.shield",
          tint: .blue,
          badge: mcpAuthMethodLabel(selectedAuthMethod, language: interfaceLanguage)
        )
      }
      .buttonStyle(.plain)
    }
  }

  private func labeledTextField(
    title: String,
    placeholder: String,
    text: Binding<String>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .padding(.horizontal, 4)
      TextField(placeholder, text: text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .font(.system(size: 15))
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func loadDefaults() {
    if displayName.isEmpty {
      displayName = entry?.name ?? ""
    }
    if endpoint.isEmpty {
      endpoint = entry?.defaultEndpoint ?? ""
    }
    if let method = authProfiles.first?.method {
      selectedAuthMethod = method
    }
  }

  private func save() {
    do {
      guard let profile = selectedProfile else {
        throw AgentRuntimeCapabilityError.invalid("MCP authentication profile is unavailable")
      }
      let connection: AgentMcpConnection
      if let entry {
        connection = try registry.installCatalogEntry(
          entry,
          endpoint: endpoint,
          authMethod: selectedAuthMethod
        )
      } else {
        connection = try registry.addRemote(
          displayName: displayName,
          endpoint: endpoint,
          authProfile: profile
        )
      }
      if connection.authProfile.method != .none {
        _ = try registry.beginAuthentication(connection.id)
      }
      createdConnectionId = connection.id
      onSaved()
      statusMessage = String(format: t("galaxyssi.mcp.connection_saved", "%@ saved"), connection.displayName)
      statusIsError = false
      openCreatedConnection = true
    } catch {
      statusMessage = error.localizedDescription
      statusIsError = true
    }
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
    default:
      return fallback
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIMcpConnectionDetailView: View {
  @Environment(\.presentationMode) private var presentationMode
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var connectionId: String
  var onChanged: () -> Void

  @State private var connection: AgentMcpConnection?
  @State private var audits: [AgentMcpAuditRecord] = []
  @State private var statusMessage = ""
  @State private var statusIsError = false
  @State private var confirmDelete = false

  private let registry = GalaxySSIMcpControlStores.makeRegistry()
  private let auditStore = GalaxySSIMcpControlStores.makeAuditStore()

  private var marketplaceItem: AgentMarketplaceItem? {
    guard let connection else { return nil }
    return AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: AgentPhoneNativeToolCatalog.descriptors(),
      installedMcp: [connection],
      installedAutomations: []
    ).first { $0.kind == .mcp && $0.id == connection.catalogId }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: connection?.displayName ?? t("agent_mcp_title", "MCP"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let connection {
            GalaxySSISecurityHeroView(
              title: connection.displayName,
              subtitle: connectionSubtitle(connection),
              systemImage: mcpSystemImage(connection),
              tint: connectionTint(connection),
              badge: mcpConnectionStatus(connection, language: interfaceLanguage)
            )

            if !statusMessage.isEmpty {
              GalaxySSISecurityStatusRow(
                title: statusIsError
                  ? t("agent_mcp_status_error", "Error")
                  : t("galaxyssi.mcp.latest_change", "Latest change"),
                subtitle: statusMessage,
                systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
                tint: statusIsError ? .red : .galaxySSIAccent,
                badge: statusIsError
                  ? t("agent_mcp_status_error", "Error")
                  : t("galaxyssi.status.ready", "Ready")
              )
            }

            connectionSection(connection)
            permissionsSection(connection)
            toolsSection(connection)
            recentActivitySection
            maintenanceSection(connection)
          } else {
            GalaxySSISecurityStatusRow(
              title: t("agent_mcp_empty", "No MCP connections"),
              subtitle: connectionId,
              systemImage: "exclamationmark.triangle",
              tint: .orange,
              badge: t("agent_capability_requires_setup", "Setup"),
              monospacedSubtitle: true
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
    .alert(isPresented: $confirmDelete) {
      Alert(
        title: Text(t("agent_mcp_remove", "Remove MCP")),
        message: Text(connection?.displayName ?? connectionId),
        primaryButton: .destructive(Text(t("common_delete", "Delete"))) {
          deleteConnection()
        },
        secondaryButton: .cancel(Text(t("common_cancel", "Cancel")))
      )
    }
  }

  private func connectionSection(_ connection: AgentMcpConnection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_marketplace_release", "Release"))
      if let marketplaceItem {
        GalaxySSISecurityStatusRow(
          title: t("agent_marketplace_release", "Release"),
          subtitle: String(
            format: t("agent_marketplace_release_detail", "Installed v%@ - Available v%@"),
            marketplaceItem.installedVersion.ifBlank(marketplaceItem.availableVersion),
            marketplaceItem.availableVersion
          ),
          systemImage: "info.circle",
          tint: marketplaceItem.updateAvailable ? .orange : .galaxySSIAccent,
          badge: marketplaceItem.updateAvailable
            ? t("agent_marketplace_update", "Update")
            : t("agent_marketplace_current", "Current")
        )
        GalaxySSISecurityStatusRow(
          title: t("agent_marketplace_capabilities_permissions", "Capabilities and permissions"),
          subtitle: capabilityPermissionSummary(marketplaceItem),
          systemImage: "checklist",
          tint: .blue,
          badge: String(
            format: t("agent_marketplace_capability_permission_count", "%d capabilities / %d permissions"),
            marketplaceItem.capabilities.count,
            marketplaceItem.permissions.count
          )
        )
      }

      if connection.transport == .localStdio {
        let manifest = GalaxySSIMcpControlStores.makePackageRepository()?.get(connection.id)
        GalaxySSISecurityStatusRow(
          title: t("agent_mcp_runtime", "Runtime"),
          subtitle: manifest?.localRuntime.map {
            String(format: t("agent_mcp_runtime_value", "%@ - phone-local Linux"), $0.language.rawValue)
          } ?? t("badge_unavailable", "Unavailable"),
          systemImage: "cpu",
          tint: .purple,
          badge: t("agent_mcp_local_package_badge", "Local package")
        )
      } else {
        GalaxySSISecurityStatusRow(
          title: t("agent_mcp_endpoint", "Endpoint"),
          subtitle: connection.endpoint,
          systemImage: "link",
          tint: .blue,
          badge: "",
          monospacedSubtitle: true
        )
      }
    }
  }

  private func permissionsSection(_ connection: AgentMcpConnection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_mcp_permission_policy", "Permission policy"))
      GalaxySSISecurityNavigationRow(
        title: t("agent_mcp_auth_method", "Authentication"),
        subtitle: mcpAuthMethodLabel(connection.authProfile.method, language: interfaceLanguage),
        systemImage: "lock.shield",
        tint: authTint(connection),
        badge: mcpAuthStateLabel(connection.effectiveAuthState(nowMillis: GalaxySSIMcpControlStores.nowMillis()), language: interfaceLanguage)
      ) {
        GalaxySSIMcpAuthenticationView(connectionId: connection.id, onChanged: refreshAndNotify)
      }
      Menu {
        ForEach(GalaxySSIMcpControlStores.permissionModes) { mode in
          Button(mcpPermissionModeLabel(mode, language: interfaceLanguage)) {
            setPermissionMode(mode)
          }
        }
      } label: {
        GalaxySSISecurityStatusRow(
          title: t("agent_mcp_permission_policy", "Permission policy"),
          subtitle: t("agent_mcp_permission_policy_subtitle", "Control which MCP tools can run automatically and which need confirmation"),
          systemImage: "shield.lefthalf.filled",
          tint: .blue,
          badge: mcpPermissionModeLabel(connection.permissionMode, language: interfaceLanguage)
        )
      }
      .buttonStyle(.plain)
    }
  }

  private func toolsSection(_ connection: AgentMcpConnection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_mcp_tools", "Tools"))
      GalaxySSISecurityStatusRow(
        title: t("agent_mcp_tools", "Tools"),
        subtitle: connection.toolIds.isEmpty
          ? t("agent_mcp_tools_not_discovered", "Discover tools after testing the connection")
          : connection.toolIds.prefix(24).joined(separator: " / "),
        systemImage: "wrench.and.screwdriver",
        tint: connection.toolIds.isEmpty ? .orange : .galaxySSIAccent,
        badge: "\(connection.toolIds.count)"
      )
      GalaxySSISecurityActionRow(
        title: t("agent_mcp_test_connection", "Test connection"),
        subtitle: connection.lastError.ifBlank(t("agent_mcp_test_connection_subtitle", "Initialize MCP and refresh tools")),
        systemImage: "antenna.radiowaves.left.and.right",
        tint: .blue,
        badge: t("common_test", "Test")
      ) {
        testConnection(connection.id)
      }
    }
  }

  private var recentActivitySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("agent_mcp_recent_activity", "Recent tool activity"))
      if audits.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("agent_mcp_no_activity", "No tool activity yet"),
          subtitle: t("agent_mcp_no_activity_subtitle", "Redacted parameters, permissions, risk, and results appear here after calls"),
          systemImage: "clock.arrow.circlepath",
          tint: .galaxySSITextSecondary,
          badge: ""
        )
      } else {
        ForEach(audits.prefix(20)) { audit in
          GalaxySSISecurityStatusRow(
            title: audit.toolName.ifBlank(t("agent_mcp_tools", "Tools")),
            subtitle: auditDetail(audit),
            systemImage: "terminal",
            tint: audit.status == "succeeded" ? .galaxySSIAccent : .orange,
            badge: String(format: t("agent_mcp_audit_duration", "%d ms"), audit.durationMillis),
            monospacedSubtitle: true
          )
        }
      }
    }
  }

  private func maintenanceSection(_ connection: AgentMcpConnection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("galaxyssi.mcp.section_maintenance", "Maintenance"))
      GalaxySSISecurityActionRow(
        title: connection.enabled
          ? t("agent_marketplace_access_active", "Access active")
          : t("agent_marketplace_access_revoked", "Access revoked"),
        subtitle: t("agent_marketplace_revoke_access_subtitle", "Stop or restore access without deleting configuration"),
        systemImage: "power",
        tint: connection.enabled ? .galaxySSIAccent : .orange,
        badge: connection.enabled
          ? t("agent_marketplace_revoke", "Revoke")
          : t("agent_marketplace_restore_access", "Restore")
      ) {
        setEnabled(!connection.enabled)
      }
      GalaxySSISecurityActionRow(
        title: t("agent_mcp_remove", "Remove MCP"),
        subtitle: t("agent_mcp_remove_subtitle", "Delete configuration, local package metadata, and encrypted credentials"),
        systemImage: "trash",
        tint: .red,
        badge: t("common_delete", "Delete")
      ) {
        confirmDelete = true
      }
    }
  }

  private func refresh() {
    connection = registry.get(connectionId)
    audits = auditStore.list(connectionId: connectionId, limit: 20)
  }

  private func refreshAndNotify() {
    refresh()
    onChanged()
  }

  private func setPermissionMode(_ mode: AgentMcpPermissionMode) {
    do {
      _ = try registry.setPermissionMode(connectionId, mode: mode)
      setStatus(t("common_saved", "Saved"), isError: false)
      refreshAndNotify()
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private func setEnabled(_ enabled: Bool) {
    do {
      _ = try registry.setEnabled(connectionId, enabled: enabled)
      setStatus(t("common_saved", "Saved"), isError: false)
      refreshAndNotify()
    } catch {
      setStatus(error.localizedDescription, isError: true)
    }
  }

  private func deleteConnection() {
    GalaxySSIMcpControlStores.makeManager(registry: registry, auditStore: auditStore)?.close(connectionId: connectionId)
    GalaxySSIMcpControlStores.makePackageRepository()?.delete(connectionId)
    _ = auditStore.clear(connectionId: connectionId)
    _ = registry.delete(connectionId)
    onChanged()
    presentationMode.wrappedValue.dismiss()
  }

  private func testConnection(_ id: String) {
    setStatus(t("agent_mcp_testing", "Testing MCP connection..."), isError: false)
    Task {
      guard let manager = GalaxySSIMcpControlStores.makeManager(registry: registry, auditStore: auditStore) else {
        await MainActor.run {
          setStatus(t("agent_mcp_test_failed", "MCP connection test failed"), isError: true)
        }
        return
      }
      do {
        let tools = try await manager.listTools(connectionId: id)
        await MainActor.run {
          setStatus(String(format: t("agent_mcp_test_success", "Connected - %d tools"), tools.count), isError: false)
          refreshAndNotify()
        }
      } catch {
        await MainActor.run {
          setStatus(error.localizedDescription, isError: true)
          refreshAndNotify()
        }
      }
    }
  }

  private func setStatus(_ message: String, isError: Bool) {
    statusMessage = message
    statusIsError = isError
  }

  private func connectionSubtitle(_ connection: AgentMcpConnection) -> String {
    [
      connection.distribution == .localPackage
        ? t("agent_mcp_local_package_badge", "Local package")
        : t("agent_mcp_remote_badge", "Remote"),
      mcpAuthMethodLabel(connection.authProfile.method, language: interfaceLanguage),
      connection.lastError.nilIfEmpty
    ]
    .compactMap { $0 }
    .joined(separator: " / ")
  }

  private func capabilityPermissionSummary(_ item: AgentMarketplaceItem) -> String {
    let values = Array(item.capabilities).sorted() + item.permissions.map(\.title).sorted()
    return values.isEmpty ? "-" : values.joined(separator: "\n")
  }

  private func auditDetail(_ audit: AgentMcpAuditRecord) -> String {
    String(
      format: t("agent_mcp_audit_detail", "%@ risk / %@\nSource: %@\n%@\n%@"),
      mcpRiskLabel(audit.risk, language: interfaceLanguage),
      mcpAuditStatusLabel(audit.status, language: interfaceLanguage),
      audit.source,
      audit.permissions.joined(separator: " / "),
      AgentMcpJSONCodec.stringify(audit.parameterPreview)
    )
  }

  private func connectionTint(_ connection: AgentMcpConnection) -> Color {
    connection.isCallable(nowMillis: GalaxySSIMcpControlStores.nowMillis()) ? .galaxySSIAccent : .orange
  }

  private func authTint(_ connection: AgentMcpConnection) -> Color {
    switch connection.effectiveAuthState(nowMillis: GalaxySSIMcpControlStores.nowMillis()) {
    case .notRequired, .authenticated, .refreshing:
      return .galaxySSIAccent
    default:
      return .orange
    }
  }

  private func mcpSystemImage(_ connection: AgentMcpConnection) -> String {
    if connection.catalogId.contains("github") { return "chevron.left.forwardslash.chevron.right" }
    if connection.catalogId.contains("notion") { return "doc.text" }
    if connection.catalogId.contains("home_assistant") { return "house" }
    if connection.distribution == .localPackage { return "shippingbox" }
    return "link"
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIMcpAuthenticationView: View {
  @Environment(\.presentationMode) private var presentationMode
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var connectionId: String
  var onChanged: () -> Void

  @State private var connection: AgentMcpConnection?
  @State private var fieldValues: [String: String] = [:]
  @State private var statusMessage = ""
  @State private var statusIsError = false

  private let registry = GalaxySSIMcpControlStores.makeRegistry()

  private var step: AgentMcpAuthStepSpec? {
    connection?.currentAuthStep
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("agent_mcp_sign_in", "Sign in to MCP"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: connection?.displayName ?? t("agent_mcp_title", "MCP"),
            subtitle: step?.description.ifBlank(t("agent_mcp_sign_in_subtitle", "Only enter fields required by this service"))
              ?? t("agent_mcp_auth_not_required", "Authentication not required"),
            systemImage: "lock.shield",
            tint: .blue,
            badge: stepCountLabel
          )

          if !statusMessage.isEmpty {
            GalaxySSISecurityStatusRow(
              title: statusIsError
                ? t("agent_mcp_auth_failed", "Unable to complete authentication")
                : t("galaxyssi.mcp.latest_change", "Latest change"),
              subtitle: statusMessage,
              systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle",
              tint: statusIsError ? .red : .galaxySSIAccent,
              badge: statusIsError
                ? t("agent_mcp_status_error", "Error")
                : t("galaxyssi.status.ready", "Ready")
            )
          }

          if let urlString = connection?.authProfile.authorizationUrl, !urlString.isBlank {
            GalaxySSISecurityActionRow(
              title: t("agent_mcp_open_authorization", "Open authorization page"),
              subtitle: urlString,
              systemImage: "safari",
              tint: .blue,
              badge: t("common_open", "Open"),
              monospacedSubtitle: true
            ) {
              if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
              }
            }
          }

          if let step {
            fieldsSection(step)
            GalaxySSISecurityPrimaryButton(
              title: t("agent_mcp_continue", "Continue"),
              systemImage: "arrow.right",
              tint: .galaxySSIAccent,
              action: submit
            )
          } else {
            GalaxySSISecurityStatusRow(
              title: t("agent_mcp_auth_not_required", "Authentication not required"),
              subtitle: t("agent_mcp_permission_policy_subtitle", "Control which MCP tools can run automatically and which need confirmation"),
              systemImage: "checkmark.shield",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.status.ready", "Ready")
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: load)
  }

  private var stepCountLabel: String {
    guard let connection, !connection.authProfile.steps.isEmpty else {
      return t("agent_mcp_auth_not_required", "Authentication not required")
    }
    return String(
      format: t("agent_mcp_step_count", "Step %d of %d"),
      connection.authStepIndex + 1,
      connection.authProfile.steps.count
    )
  }

  private func fieldsSection(_ step: AgentMcpAuthStepSpec) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: step.title)
      ForEach(step.fields) { field in
        fieldInput(field)
      }
    }
  }

  @ViewBuilder
  private func fieldInput(_ field: AgentMcpAuthFieldSpec) -> some View {
    switch field.type {
    case .checkbox:
      Toggle(isOn: Binding(
        get: { (fieldValues[field.id] ?? "false") == "true" },
        set: { fieldValues[field.id] = $0 ? "true" : "false" }
      )) {
        VStack(alignment: .leading, spacing: 3) {
          Text(field.label)
            .font(.system(size: 15, weight: .semibold))
          if !field.placeholder.isBlank {
            Text(field.placeholder)
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
          }
        }
      }
      .padding(12)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    case .select:
      Menu {
        ForEach(field.options, id: \.self) { option in
          Button(option) {
            fieldValues[field.id] = option
          }
        }
      } label: {
        GalaxySSISecurityStatusRow(
          title: field.label,
          subtitle: field.placeholder.ifBlank(t("agent_mcp_sign_in_subtitle", "Only enter fields required by this service")),
          systemImage: "list.bullet",
          tint: .blue,
          badge: fieldValues[field.id]?.nilIfEmpty ?? field.options.first ?? ""
        )
      }
      .buttonStyle(.plain)
    case .password, .apiKey, .otp, .totp:
      secretField(field)
    default:
      plainField(field)
    }
  }

  private func plainField(_ field: AgentMcpAuthFieldSpec) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(field.label)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .padding(.horizontal, 4)
      TextField(field.placeholder, text: Binding(
        get: { fieldValues[field.id] ?? "" },
        set: { fieldValues[field.id] = $0 }
      ))
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled(true)
      .keyboardType(keyboardType(field.type))
      .font(.system(size: 15))
      .padding(.horizontal, 12)
      .frame(minHeight: 48)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func secretField(_ field: AgentMcpAuthFieldSpec) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(field.label)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .padding(.horizontal, 4)
      SecureField(field.placeholder, text: Binding(
        get: { fieldValues[field.id] ?? "" },
        set: { fieldValues[field.id] = $0 }
      ))
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled(true)
      .keyboardType(keyboardType(field.type))
      .font(.system(size: 15))
      .padding(.horizontal, 12)
      .frame(minHeight: 48)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private func load() {
    do {
      guard let current = registry.get(connectionId) else {
        throw AgentRuntimeCapabilityError.invalid("MCP connection is not available")
      }
      if current.authProfile.method == .none {
        connection = current
        return
      }
      let pending: AgentMcpConnection
      if current.authState == .challengeRequired {
        pending = current
      } else {
        _ = try registry.beginAuthentication(connectionId)
        pending = registry.get(connectionId) ?? current
      }
      connection = pending
      if let step = pending.currentAuthStep {
        fieldValues = Dictionary(uniqueKeysWithValues: step.fields.map { field in
          (field.id, field.type == .select ? (field.options.first ?? "") : "")
        })
      }
    } catch {
      statusMessage = error.localizedDescription
      statusIsError = true
    }
  }

  private func submit() {
    statusMessage = t("agent_mcp_auth_refreshing", "Refreshing")
    statusIsError = false
    Task {
      do {
        let updated = try await AgentMcpAuthenticationCoordinator(registry: registry)
          .submitStep(connectionId: connectionId, values: fieldValues)
        await MainActor.run {
          handleAuthenticationUpdate(updated)
        }
      } catch {
        await MainActor.run {
          statusMessage = error.localizedDescription
          statusIsError = true
        }
      }
    }
  }

  private func handleAuthenticationUpdate(_ updated: AgentMcpConnection) {
    connection = updated
    onChanged()
    if updated.effectiveAuthState(nowMillis: GalaxySSIMcpControlStores.nowMillis()) == .authenticated ||
      updated.effectiveAuthState(nowMillis: GalaxySSIMcpControlStores.nowMillis()) == .notRequired {
      statusMessage = t("agent_mcp_auth_authenticated", "Authenticated")
      statusIsError = false
      presentationMode.wrappedValue.dismiss()
    } else {
      statusMessage = t("common_saved", "Saved")
      statusIsError = false
      if let step = updated.currentAuthStep {
        fieldValues = Dictionary(uniqueKeysWithValues: step.fields.map { field in
          (field.id, field.type == .select ? (field.options.first ?? "") : "")
        })
      }
    }
  }

  private func keyboardType(_ type: AgentMcpAuthFieldType) -> UIKeyboardType {
    switch type {
    case .email:
      return .emailAddress
    case .phone:
      return .phonePad
    case .otp, .totp:
      return .numberPad
    case .url:
      return .URL
    default:
      return .default
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

enum GalaxySSIMcpControlStores {
  static let permissionModes: [AgentMcpPermissionMode] = [
    .askForChanges,
    .readOnly,
    .trusted,
    .disabled
  ]

  static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }

  static func makeRegistry() -> AgentMcpRegistry {
    AgentMcpRegistry(FileAgentMcpStore(rootURL: FileAgentMcpStore.defaultRootURL()))
  }

  static func makePackageRepository() -> AgentMcpPackageRepository? {
    AgentMcpPackageRepository(
      rootDirectory: AgentIOSMcpClientNativeProvider.defaultPackageRootURL()
    )
  }

  static func makeAuditStore() -> FileAgentMcpAuditStore {
    FileAgentMcpAuditStore(directory: FileAgentMcpStore.defaultRootURL())
  }

  static func makeManager(
    registry: AgentMcpRegistry,
    auditStore: AgentMcpAuditStore
  ) -> AgentMcpClientManager? {
    guard let repository = makePackageRepository() else { return nil }
    return AgentMcpClientManager(
      registry: registry,
      packageRepository: repository,
      auditStore: auditStore
    )
  }

  static func defaultAuthProfiles() -> [AgentMcpAuthProfile] {
    [
      try? AgentMcpAuthProfile(.none),
      try? AgentMcpAuthProfile(.bearerToken),
      try? AgentMcpAuthProfile(.apiKey),
      try? AgentMcpAuthProfile(.usernamePassword),
      try? AgentMcpAuthProfile(.oauth2, supportsRefresh: true),
      try? AgentMcpAuthProfile(.deviceCode),
      try? AgentMcpAuthProfile(.dynamic)
    ].compactMap { $0 }
  }
}

private func mcpConnectionStatus(_ connection: AgentMcpConnection, language: String) -> String {
  if !connection.enabled {
    return GalaxySSILocalization.string("status_disabled", fallback: "Disabled", language: language)
  }
  if connection.state == .connected {
    return GalaxySSILocalization.string("status_connected", fallback: "Connected", language: language)
  }
  let authState = connection.effectiveAuthState(nowMillis: GalaxySSIMcpControlStores.nowMillis())
  if [.notConfigured, .challengeRequired, .reauthenticationRequired, .error].contains(authState) {
    return GalaxySSILocalization.string("agent_capability_requires_setup", fallback: "Setup", language: language)
  }
  if connection.state == .error {
    return GalaxySSILocalization.string("agent_mcp_status_error", fallback: "Error", language: language)
  }
  return GalaxySSILocalization.string("status_ready", fallback: "Ready", language: language)
}

private func mcpAuthMethodLabel(_ method: AgentMcpAuthMethod, language: String) -> String {
  switch method {
  case .none:
    return GalaxySSILocalization.string("agent_mcp_auth_none", fallback: "No authentication", language: language)
  case .bearerToken:
    return GalaxySSILocalization.string("agent_mcp_auth_token", fallback: "Bearer token", language: language)
  case .apiKey:
    return GalaxySSILocalization.string("agent_mcp_auth_api_key", fallback: "API key", language: language)
  case .usernamePassword:
    return GalaxySSILocalization.string("agent_mcp_auth_password", fallback: "Username and password", language: language)
  case .oauth2:
    return GalaxySSILocalization.string("agent_mcp_auth_oauth", fallback: "OAuth 2.1", language: language)
  case .deviceCode:
    return GalaxySSILocalization.string("agent_mcp_auth_device_code", fallback: "Device code", language: language)
  case .dynamic:
    return GalaxySSILocalization.string("agent_mcp_auth_dynamic", fallback: "Service-defined login", language: language)
  }
}

private func mcpAuthStateLabel(_ state: AgentMcpAuthState, language: String) -> String {
  switch state {
  case .notRequired:
    return GalaxySSILocalization.string("agent_mcp_auth_not_required", fallback: "Not required", language: language)
  case .authenticated:
    return GalaxySSILocalization.string("agent_mcp_auth_authenticated", fallback: "Authenticated", language: language)
  case .refreshing:
    return GalaxySSILocalization.string("agent_mcp_auth_refreshing", fallback: "Refreshing", language: language)
  case .reauthenticationRequired:
    return GalaxySSILocalization.string("agent_mcp_auth_reauth_required", fallback: "Reauthentication required", language: language)
  case .error:
    return GalaxySSILocalization.string("agent_mcp_status_error", fallback: "Error", language: language)
  default:
    return GalaxySSILocalization.string("agent_capability_requires_setup", fallback: "Setup", language: language)
  }
}

private func mcpPermissionModeLabel(_ mode: AgentMcpPermissionMode, language: String) -> String {
  switch mode {
  case .askForChanges:
    return GalaxySSILocalization.string("agent_mcp_permission_ask", fallback: "Ask before changes", language: language)
  case .readOnly:
    return GalaxySSILocalization.string("agent_mcp_permission_read_only", fallback: "Read only", language: language)
  case .trusted:
    return GalaxySSILocalization.string("agent_mcp_permission_trusted", fallback: "Trusted", language: language)
  case .disabled:
    return GalaxySSILocalization.string("status_disabled", fallback: "Disabled", language: language)
  }
}

private func mcpRiskLabel(_ risk: String, language: String) -> String {
  switch risk {
  case AgentMcpToolRisk.low.rawValue:
    return GalaxySSILocalization.string("agent_mcp_risk_low", fallback: "Low", language: language)
  case AgentMcpToolRisk.high.rawValue:
    return GalaxySSILocalization.string("agent_mcp_risk_high", fallback: "High", language: language)
  default:
    return GalaxySSILocalization.string("agent_mcp_risk_medium", fallback: "Medium", language: language)
  }
}

private func mcpAuditStatusLabel(_ status: String, language: String) -> String {
  switch status {
  case "succeeded":
    return GalaxySSILocalization.string("agent_mcp_audit_succeeded", fallback: "Succeeded", language: language)
  case "denied":
    return GalaxySSILocalization.string("agent_mcp_audit_denied", fallback: "Denied", language: language)
  default:
    return GalaxySSILocalization.string("agent_mcp_audit_failed", fallback: "Failed", language: language)
  }
}
