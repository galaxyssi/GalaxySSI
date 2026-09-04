import SwiftUI
import UIKit

struct GalaxySSISettingsSummarySnapshot {
  var memoryCount = 0
  var memoryConflictCount = 0
  var knowledgeItemCount = 0
  var knowledgeSourceCount = 0
  var knowledgeHitCount = 0
  var taskCount = 0
  var runningTaskCount = 0
  var automationCount = 0
  var enabledAutomationCount = 0
  var sessionCount = 0
  var archivedSessionCount = 0
  var nativeToolTotal = 0
  var nativeToolAvailable = 0
  var mcpInstalled = 0
  var mcpReady = 0
  var mcpRecommended = 0
}

@MainActor
enum GalaxySSISettingsSummaryCache {
  private static var cachedKey = ""
  private static var cachedSnapshot: GalaxySSISettingsSummarySnapshot?
  private static var cachedAt = Date.distantPast
  private static let maximumAge: TimeInterval = 30

  static func key(for store: GalaxySSIStore) -> String {
    let taskRevision = store.agentTaskRecords.map(\.updatedAtMillis).max() ?? 0
    let conversationRevision = store.agentConversations.map(\.updatedAt).max() ?? 0
    let activeConversationCount = store.agentSessionCount(status: .active)
    let archivedConversationCount = store.agentSessionCount(status: .archived)
    let contactRevision = store.contacts.map(\.updatedAt.timeIntervalSince1970).max() ?? 0
    let safety = store.agentSafetySettings
    let safetyKey = [
      safety.taskExecutionMode.rawValue,
      safety.permissionMode.rawValue,
      String(safety.highRiskGuard),
      String(safety.memoryCapture),
      String(safety.screenObservationAllowed),
      String(safety.localActionsAllowed),
      String(safety.connectorCallsAllowed),
      String(safety.deviceControlAllowed),
      String(safety.executionPaused)
    ].joined(separator: ",")
    let localModelKey = LocalModelRuntimeSettings.activeProfiles().map { profile in
      "\(profile.id):\(LocalModelRuntimeSettings.isProfileEnabled(profile))"
    }.joined(separator: ",")
    let nativeToolKey = AgentPhoneNativeToolCatalog.descriptors().map { tool in
      "\(tool.id):\(tool.availability.status.rawValue)"
    }.joined(separator: ",")
    let mcpKey = AgentMcpRegistry(
      FileAgentMcpStore(rootURL: FileAgentMcpStore.defaultRootURL())
    ).list().map { connection in
      "\(connection.id):\(connection.state.rawValue):\(connection.enabled)"
    }.joined(separator: ",")
    return [
      "\(store.agentMemoryItems.count):\(store.agentKnowledgeItems.count):\(store.agentKnowledgeAccessAudit.count)",
      "\(store.agentTaskRecords.count):\(taskRevision)",
      "\(store.proactiveTasks.count):\(store.proactiveRuns.count)",
      "\(activeConversationCount):\(archivedConversationCount):\(conversationRevision)",
      "\(store.contacts.count):\(contactRevision)",
      safetyKey,
      localModelKey,
      nativeToolKey,
      mcpKey
    ].joined(separator: "|")
  }

  static func prepare(store: GalaxySSIStore) async -> GalaxySSISettingsSummarySnapshot {
    let currentKey = key(for: store)
    if currentKey == cachedKey,
       Date().timeIntervalSince(cachedAt) < maximumAge,
       let cachedSnapshot {
      return cachedSnapshot
    }

    let memorySnapshot = store.agentMemorySnapshot()
    let knowledgeStats = store.agentKnowledgeStats
    let knowledgeHitCount = store.agentKnowledgeAccessAudit.count
    let taskRecords = store.recentAgentTasks(limit: 200)
    let automationTasks = store.automationTasks()
    let activeConversationCount = store.agentSessionCount(status: .active)
    let archivedConversationCount = store.agentSessionCount(status: .archived)
    let prepared = await Task.detached(priority: .userInitiated) {
      let runningPhases: Set<AgentPhase> = [
        .observing,
        .planning,
        .executing,
        .verifying,
        .waitingConfirmation,
        .waitingResponse,
        .paused
      ]
      let tools = AgentPhoneNativeToolCatalog.descriptors()
      let availableTools = tools.filter {
        $0.risk != .blocked && $0.availability.status == .available
      }.count
      let mcpConnections = AgentMcpRegistry(
        FileAgentMcpStore(rootURL: FileAgentMcpStore.defaultRootURL())
      ).list()
      return GalaxySSISettingsSummarySnapshot(
        memoryCount: memorySnapshot.activeCount,
        memoryConflictCount: memorySnapshot.conflicts.count,
        knowledgeItemCount: knowledgeStats.itemCount,
        knowledgeSourceCount: knowledgeStats.sourceCount,
        knowledgeHitCount: knowledgeHitCount,
        taskCount: taskRecords.count,
        runningTaskCount: taskRecords.filter { runningPhases.contains($0.phase) }.count,
        automationCount: automationTasks.count,
        enabledAutomationCount: automationTasks.filter(\.enabled).count,
        sessionCount: activeConversationCount + archivedConversationCount,
        archivedSessionCount: archivedConversationCount,
        nativeToolTotal: tools.count,
        nativeToolAvailable: availableTools,
        mcpInstalled: mcpConnections.count,
        mcpReady: mcpConnections.filter {
          $0.isCallable(nowMillis: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
        }.count,
        mcpRecommended: AgentDefaultCapabilityCatalog.mcpEntries.count
      )
    }.value
    cachedKey = currentKey
    cachedSnapshot = prepared
    cachedAt = Date()
    return prepared
  }
}

struct SettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var showingAddModel = false
  @State private var statusText = ""
  @State private var statusIsError = false
  @State private var linkDiagnosticsSnapshot = GalaxySSILinkTransportDiagnostics.snapshot()
  @State private var settingsStatsLoading = true
  @State private var navigationContentGate = GalaxySSINavigationContentGate()
  @State private var settingsStats = GalaxySSISettingsSummarySnapshot()
  var showsBackButton = true
  var onBackToAgent: (() -> Void)? = nil

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        GalaxySSITopBar(
          title: t("galaxyssi.tab.settings", "Settings"),
          leading: {
            if showsBackButton {
              GalaxySSIBackButton()
            } else if let onBackToAgent {
              Button(action: onBackToAgent) {
                Image(systemName: "chevron.left")
                  .font(.system(size: 22, weight: .semibold))
                  .foregroundColor(.galaxySSITextPrimary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Text(t("galaxyssi.common.back", "Back")))
            } else {
              Color.clear
            }
          },
          trailing: { Color.clear }
        )
        ScrollView {
          if settingsStatsLoading {
            settingsLoadingContent
          } else {
            VStack(alignment: .leading, spacing: 12) {
              profileSection
              statusSection
              pagesSection
              agentSection
              agentToolsSection
              knowledgeExecutionSection
              trustSection
              dataSection
              protocolSection
              localIntelligenceSection
              generalSection
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 18)
          }
        }
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationBarHidden(true)
      .sheet(isPresented: $showingAddModel) {
        AddCloudModelView()
      }
      .onAppear(perform: refreshLinkDiagnostics)
      .onDisappear {
        navigationContentGate.invalidate()
      }
      .task(id: settingsStatsTaskID) {
        await prepareSettingsStats()
      }
    }
    .navigationViewStyle(StackNavigationViewStyle())
  }

  private var settingsLoadingContent: some View {
    VStack(alignment: .leading, spacing: 12) {
      GalaxySSISecurityHeroView(
        title: t("settings_my_galaxyssi", "My GalaxySSI"),
        subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
        systemImage: "slider.horizontal.3",
        tint: .galaxySSIAccent,
        badge: t("cc_loading", "Loading...")
      )
      HStack(spacing: 10) {
        ProgressView()
          .tint(.galaxySSIAccent)
        Text(t("cc_loading", "Loading..."))
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: 120)
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 18)
  }

  private var settingsStatsTaskID: String {
    GalaxySSISettingsSummaryCache.key(for: store)
  }

  private func prepareSettingsStats() async {
    let generation = navigationContentGate.begin()
    if let cached = GalaxySSINavigationContentPrewarm.snapshot(for: store)?.settings,
       !Task.isCancelled {
      settingsStats = cached
      settingsStatsLoading = false
    } else {
      settingsStatsLoading = true
    }
    let prepared = await GalaxySSISettingsSummaryCache.prepare(store: store)
    guard !Task.isCancelled, navigationContentGate.isCurrent(generation) else { return }
    settingsStats = prepared
    settingsStatsLoading = false
  }

  private var profileSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsProfileHero(
        title: store.profile.name.ifBlank(t("settings_profile_me", "Me")),
        subtitle: t("settings_control_center_subtitle", "Local Agent control center"),
        galaxySSIIdLabel: t("settings_galaxyssi_id", "GalaxySSI ID"),
        galaxySSIId: store.profile.galaxySSIId,
        avatarData: store.profile.avatarData,
        identityFingerprint: store.profile.identityFingerprint,
        primaryBadge: store.agentSafetySettings.executionPaused
          ? t("galaxyssi.settings.execution_paused", "Execution Paused")
          : t("settings_badge_agent_enabled", "Local Agent Enabled"),
        secondaryBadge: store.serverLinks.contains(where: \.paired)
          ? t("settings_badge_connection_ok", "Connection OK")
          : t("settings_status_link_off", "No trusted Desktop yet"),
        secondaryTint: store.serverLinks.contains(where: \.paired) ? .galaxySSIInsightText : .orange
      )
      SettingsNameEditorRow(
        title: t("galaxyssi.settings.name", "Name"),
        text: Binding(
          get: { store.profile.name },
          set: { store.updateProfileName($0) }
        )
      )
      SettingsActionRow(
        title: t("settings_galaxyssi_id", "GalaxySSI ID"),
        subtitle: store.profile.galaxySSIId,
        systemImage: "link",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.galaxySSIId, message: t("galaxyssi.security_center.copied_galaxyssi_id", "GalaxySSI ID copied"))
      }
      SettingsNavigationRow(
        title: t("cc_profile_title", "My GalaxySSI"),
        subtitle: t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"),
        systemImage: "person.crop.circle",
        tint: .galaxySSITextPrimary,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIProfileIdentityView()
      }
      SettingsNavigationRow(
        title: t("settings_my_galaxyssi", "My GalaxySSI"),
        subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
        systemImage: "slider.horizontal.3",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIControlCenterView()
      }
    }
  }

  @ViewBuilder
  private var statusSection: some View {
    if !statusText.isEmpty {
      GalaxySSISecurityStatusRow(
        title: t("galaxyssi.common.status", "Status"),
        subtitle: statusText,
        systemImage: statusIsError ? "xmark.circle" : "checkmark.circle",
        tint: statusIsError ? .red : .galaxySSIAccent,
        badge: statusIsError
          ? t("galaxyssi.status.needs_setup", "Needs Setup")
          : t("galaxyssi.status.ready", "Ready")
      )
    }
  }

  private var agentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_agent", "Agent & Capabilities"))
      SettingsNavigationRow(
        title: t("galaxyssi.discover.ai_agent_title", "AI Agent"),
        subtitle: t("galaxyssi.discover.ai_agent_subtitle", "Explore powerful AI assistants"),
        systemImage: "cpu",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIMyAgentsView()
      }
      SettingsNavigationRow(
        title: t("cc_agent_core_title", "Agent Core"),
        subtitle: t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"),
        systemImage: "cpu",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentCoreView()
      }
      SettingsNavigationRow(
        title: t("agent_capability_library_title", "Capability Library"),
        subtitle: t("agent_capability_library_subtitle", "Manage phone tools, MCP connections, and reusable automation from one place"),
        systemImage: "shippingbox.and.arrow.down",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSICapabilityLibraryView()
      }
      SettingsNavigationRow(
        title: t("cc_phone_title", "Phone Capabilities"),
        subtitle: phoneCapabilitiesSummary,
        systemImage: "iphone",
        tint: .galaxySSIInsightText,
        badge: "\(nativeToolSummaryCounts.available)/\(nativeToolSummaryCounts.total)"
      ) {
        GalaxySSIPhoneCapabilitiesView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.native_tool_catalog.title", "Native Tools"),
        subtitle: nativeToolsSummary,
        systemImage: "wrench.and.screwdriver",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSINativeToolCatalogView()
      }
      SettingsNavigationRow(
        title: t("agent_mcp_title", "MCP"),
        subtitle: mcpSummary,
        systemImage: "shippingbox",
        tint: .blue,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIMcpControlCenterView()
      }
      SettingsNavigationRow(
        title: t("agent_app_adapters_title", "Specialized App Adapters"),
        subtitle: String(
          format: t("galaxyssi.settings.app_adapters.status", "%d adapters / iOS handoff boundaries"),
          GalaxySSIAppAdapterCatalog.adapterCount
        ),
        systemImage: "square.grid.2x2",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAppAdaptersView()
      }
    }
  }

  private var agentToolsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_agent_tools", "Agent tools"))
      SettingsNavigationRow(
        title: t("agent_quick_understand", "Understand"),
        subtitle: t("galaxyssi.settings.agent_tools.understand_subtitle", "Screen understanding, visible UI, notifications, and device status"),
        systemImage: "rectangle.on.rectangle",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentScreenUnderstandingView()
      }
      SettingsNavigationRow(
        title: t("agent_quick_save_screen", "Memory"),
        subtitle: memorySummary,
        systemImage: "brain",
        tint: .purple,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentMemoryView()
      }
      SettingsNavigationRow(
        title: t("agent_quick_search_knowledge", "Knowledge"),
        subtitle: knowledgeSummary,
        systemImage: "book.closed",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentKnowledgeView()
      }
      SettingsNavigationRow(
        title: t("agent_quick_permissions", "Controls"),
        subtitle: t("galaxyssi.settings.agent_tools.controls_subtitle", "Permissions, on-device access, and action boundaries"),
        systemImage: "hand.raised",
        tint: .orange,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        OnDeviceAgentPermissionsView()
      }
      SettingsNavigationRow(
        title: t("agent_section_recent_tasks", "Recent Tasks"),
        subtitle: recentTaskSummary,
        systemImage: "clock.arrow.circlepath",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentRecentTasksView()
      }
    }
  }

  private var knowledgeExecutionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_knowledge", "Knowledge & Execution"))
      SettingsNavigationRow(
        title: t("cc_execution_policy_title", "Execution Policy"),
        subtitle: t("cc_permission_mode_banner_subtitle", "This setting is enforced by the local safety policy before every action."),
        systemImage: "checkmark.shield",
        tint: .orange,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIExecutionPolicyView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.settings.execution_policy", "Execution Policy"),
        subtitle: "\(t(store.agentSafetySettings.taskExecutionMode.displayTitle, store.agentSafetySettings.taskExecutionMode.displayTitle)) / \(t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle))",
        systemImage: "hand.raised",
        tint: .orange,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        AgentSafetySettingsView()
      }
      SettingsNavigationRow(
        title: t("cc_memory_title", "Memory & Personalization"),
        subtitle: memoryControlSummary,
        systemImage: "memorychip",
        tint: .purple,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIMemoryControlCenterView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.agent_memory.title", "Personal Memory"),
        subtitle: memorySummary,
        systemImage: "brain",
        tint: .purple,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentMemoryView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.agent_knowledge.title", "Knowledge"),
        subtitle: knowledgeSummary,
        systemImage: "book.closed",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentKnowledgeView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.agent_tasks.title", "Tasks"),
        subtitle: recentTaskSummary,
        systemImage: "checklist",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentRecentTasksView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.automation.title", "Automation"),
        subtitle: automationSummary,
        systemImage: "clock",
        tint: .orange,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIAutomationView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.skill_marketplace.title", "Skill Marketplace"),
        subtitle: t("galaxyssi.skill_marketplace.settings_subtitle", "Install, enable, and review reusable Agent Skills"),
        systemImage: "sparkles.rectangle.stack",
        tint: .purple,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSISkillMarketplaceView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.agent_sessions.title", "Sessions"),
        subtitle: agentSessionsSummary,
        systemImage: "bubble.left.and.bubble.right",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIConversationHubView()
      }
      SettingsNavigationRow(
        title: t("cc_learning_title", "Learning & Skill Evolution"),
        subtitle: t("cc_learning_subtitle", "Learn from successful tasks; generated content requires review"),
        systemImage: "sparkles.rectangle.stack",
        tint: .purple,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSILearningSkillEvolutionView()
      }
      SettingsNavigationRow(
        title: t("cc_resource_routing_title", "Models & Resource Routing"),
        subtitle: t("cc_resource_routing_subtitle", "Choose by quality, latency, privacy, cost, and availability"),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: .blue,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIResourceRoutingView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.discover.model_planner", "Model Planner"),
        subtitle: modelPlannerSummary,
        systemImage: "slider.horizontal.3",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        AgentModelPlannerSettingsView()
      }
    }
  }

  private var trustSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_trust", "Connections & Trust"))
      SettingsNavigationRow(
        title: t("settings_trusted_devices", "Trusted Devices"),
        subtitle: t("settings_trusted_devices_subtitle", "Manage paired desktops, phones, and local nodes"),
        systemImage: "desktopcomputer",
        tint: .galaxySSIAccent,
        badge: pairedDesktopBadge
      ) {
        GalaxySSISecurityCenterView()
      }
      SettingsNavigationRow(
        title: t("settings_permission_audit", "Permission Audit"),
        subtitle: t("settings_permission_audit_subtitle", "Check phone permissions and Agent action grants"),
        systemImage: "checkmark.shield",
        tint: .orange,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIPermissionsAuditView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.discover.device_center", "Device Center"),
        subtitle: t("galaxyssi.discover.device.subtitle", "Custom devices, Home Assistant and connectors"),
        systemImage: "antenna.radiowaves.left.and.right",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        DeviceManagementView()
      }
      SettingsNavigationRow(
        title: t("cc_nodes_title", "Agents, Models & Nodes"),
        subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
        systemImage: "link.circle",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIAgentsModelsNodesView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.discover.pairing", "Pairing"),
        subtitle: t("galaxyssi.discover.pairing.subtitle", "Scan QR codes and connect GalaxySSI Desktop"),
        systemImage: "qrcode.viewfinder",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.connect", "Connect")
      ) {
        PairingView()
      }
      SettingsNavigationRow(
        title: t("cc_system_status_title", "System Status"),
        subtitle: systemStatusSubtitle,
        systemImage: systemStatusIcon,
        tint: systemStatusNeedsAttention ? .orange : .galaxySSIAccent,
        badge: systemStatusNeedsAttention ? t("cc_status_degraded", "Degraded") : t("cc_status_normal", "Normal")
      ) {
        GalaxySSISystemStatusView()
      }
    }
  }

  private var protocolSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_protocol_quality", "Protocol & Quality"))
      SettingsNavigationRow(
        title: t("settings_protocol_quality", "Protocol & Quality"),
        subtitle: t("settings_protocol_quality_subtitle", "Secure communication and Agent coordination status"),
        systemImage: "checkmark.shield",
        tint: .blue,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIProtocolQualityView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.settings.link_diagnostics", "Link Diagnostics"),
        subtitle: linkDiagnosticsSummary,
        systemImage: "waveform.path.ecg",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSILinkDiagnosticsView()
      }
      SettingsNavigationRow(
        title: t("settings_advanced_options", "Advanced Options"),
        subtitle: t("settings_advanced_options_subtitle", "Logs, network, and protocol diagnostics"),
        systemImage: "exclamationmark.triangle",
        tint: .orange,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIAdvancedOptionsView()
      }
    }
  }

  private var localIntelligenceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_local_intelligence", "Local Intelligence"))
      SettingsNavigationRow(
        title: t("galaxyssi.settings.local_model", "Local Model Settings"),
        subtitle: t("galaxyssi.settings.local_model.status", "Configure on-device inference"),
        systemImage: "cpu",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSILocalModelLabView()
      }
      SettingsNavigationRow(
        title: t("cc_runtime_title", "On-device Linux Runtime"),
        subtitle: t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"),
        systemImage: "terminal",
        tint: .teal,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIOnDeviceRuntimeView()
      }
      SettingsNavigationRow(
        title: t("settings_on_device_agent", "On-device Agent & Permissions"),
        subtitle: t("settings_on_device_agent_subtitle", "Manage perception, voice, automation permissions, and local action boundaries"),
        systemImage: "hand.raised",
        tint: .orange,
        badge: store.agentSafetySettings.executionPaused
          ? t("on_device_agent_status_paused", "Paused")
          : t("on_device_agent_status_running", "Running")
      ) {
        OnDeviceAgentPermissionsView()
      }
      SettingsNavigationRow(
        title: t("voice_settings_title", "Voice Wake & ASR/TTS"),
        subtitle: voiceSettingsSummary,
        systemImage: "waveform",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIVoiceAssistantSettingsView()
      }
      SettingsNavigationRow(
        title: t("cc_voice_title", "Voice & Interaction"),
        subtitle: t("galaxyssi.discover.voice.subtitle", "Wake, transcription and local voice models"),
        systemImage: "mic",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIVoiceControlCenterView()
      }
      if store.cloudModelContacts.isEmpty {
        SettingsActionRow(
          title: t("galaxyssi.settings.add_model", "Add Model"),
          subtitle: t("discover_add_cloud_model_subtitle", "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"),
          systemImage: "plus.circle",
          tint: .galaxySSIAccent,
          badge: t("galaxyssi.common.add", "Add")
        ) {
          showingAddModel = true
        }
      } else {
        ForEach(store.cloudModelContacts) { contact in
          SettingsNavigationRow(
            title: contact.displayName,
            subtitle: contact.selectedCloudModel?.modelId ?? t("galaxyssi.settings.no_model", "No model"),
            systemImage: "cloud",
            tint: .blue,
            badge: t("galaxyssi.common.manage", "Manage")
          ) {
            GalaxySSICloudModelSwitchView(contactId: contact.id)
          }
        }
        SettingsActionRow(
          title: t("galaxyssi.settings.add_model", "Add Model"),
          subtitle: t("discover_add_cloud_model_subtitle", "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"),
          systemImage: "plus.circle",
          tint: .galaxySSIAccent,
          badge: t("galaxyssi.common.add", "Add")
        ) {
          showingAddModel = true
        }
      }
    }
  }

  private var dataSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_data", "Data"))
      SettingsNavigationRow(
        title: t("cc_data_title", "Data & Backup"),
        subtitle: t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"),
        systemImage: "externaldrive",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIDataBackupView()
      }
      SettingsNavigationRow(
        title: t("settings_backup_chat", "Backup"),
        subtitle: t("settings_backup_scope", "Encrypted export of identity, contacts, Agent data, and chats"),
        systemImage: "square.and.arrow.up",
        tint: .blue,
        badge: t("galaxyssi.common.export", "Export")
      ) {
        GalaxySSIDataBackupView(initialMode: .export)
      }
      SettingsNavigationRow(
        title: t("settings_import_backup", "Import"),
        subtitle: t("settings_import_scope", "Restore data from an encrypted .hcback backup"),
        systemImage: "square.and.arrow.down",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.import", "Import")
      ) {
        GalaxySSIDataBackupView(initialMode: .importBackup)
      }
      SettingsNavigationRow(
        title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
        subtitle: t("cc_privacy_dashboard_hero_subtitle", "A metadata-only audit of data sent to cloud models and trusted Desktop Agents"),
        systemImage: "lock.doc",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIPrivacyControlCenterView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.settings.model_data_sharing", "Model Data Sharing"),
        subtitle: t("galaxyssi.settings.model_data_sharing.subtitle", "Review metadata-only disclosure events and destination blocks"),
        systemImage: "doc.text.magnifyingglass",
        tint: .blue,
        badge: t("galaxyssi.common.view", "View")
      ) {
        GalaxySSIPrivacyDashboardView()
      }
      SettingsNavigationRow(
        title: t("settings_destroy_data", "Reset Data"),
        subtitle: t("destroy_data_hero_subtitle", "This deletes identity, contacts, chat history, keys, cache, and backup data."),
        systemImage: "trash",
        tint: .red,
        badge: t("settings_reset_short", "Reset")
      ) {
        GalaxySSIResetDataView()
      }
    }
  }

  private var generalSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_general", "General"))
      SettingsNavigationRow(
        title: t("cc_general_page_title", "General"),
        subtitle: t("galaxyssi.general_settings.subtitle", "Language, appearance, text size, notifications, and app information"),
        systemImage: "gearshape",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSIGeneralSettingsView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.language_policy.title", "Voice & Language"),
        subtitle: languagePolicySummary,
        systemImage: "globe",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSILanguageSettingsView()
      }
      SettingsNavigationRow(
        title: t("cc_text_size_title", "Text Size"),
        subtitle: textScaleSummary,
        systemImage: "textformat.size",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.manage", "Manage")
      ) {
        GalaxySSITextSizeSettingsView()
      }
      SettingsActionRow(
        title: t("settings_notifications", "Notifications"),
        subtitle: t("settings_notifications_subtitle", "Agent actions, safety alerts, and background status"),
        systemImage: "bell.badge",
        tint: .orange,
        badge: t("galaxyssi.common.open", "Open")
      ) {
        requestNotifications()
      }
      SettingsNavigationRow(
        title: t("settings_about_galaxyssi", "About GalaxySSI"),
        subtitle: String(format: t("settings_about_version_summary", "Version %@ - Signal Link v2"), appVersionName),
        systemImage: "info.circle",
        tint: .galaxySSITextPrimary,
        badge: t("settings_about_short", "About")
      ) {
        GalaxySSIAboutView()
      }
    }
  }

  private var pagesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_pages", "App Pages"))
      SettingsNavigationRow(
        title: t("cc_general_page_title", "General"),
        subtitle: t("cc_general_page_subtitle", "Device, display, notifications, reset, and about"),
        systemImage: "gearshape",
        tint: .galaxySSIInsightText,
        badge: t("galaxyssi.common.open", "Open")
      ) {
        GalaxySSIGeneralControlCenterView()
      }
      SettingsNavigationRow(
        title: t("cc_smart_spaces_title", "Smart Spaces"),
        subtitle: t("cc_spaces_subtitle", "Home Assistant and custom devices"),
        systemImage: "house",
        tint: .purple,
        badge: t("galaxyssi.common.open", "Open")
      ) {
        GalaxySSISmartSpacesView()
      }
      SettingsNavigationRow(
        title: t("cc_runtime_title", "On-device Linux Runtime"),
        subtitle: t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"),
        systemImage: "terminal",
        tint: .teal,
        badge: t("galaxyssi.common.open", "Open")
      ) {
        GalaxySSIOnDeviceRuntimeView()
      }
      SettingsNavigationRow(
        title: t("cc_runtime_software_center_title", "Software Center"),
        subtitle: t("cc_runtime_software_center_subtitle", "Find and install verified language, browser, and media tools"),
        systemImage: "shippingbox",
        tint: .blue,
        badge: t("galaxyssi.common.open", "Open")
      ) {
        GalaxySSIRuntimeSoftwareCenterView()
      }
      SettingsNavigationRow(
        title: t("galaxyssi.discover.pairing", "Pairing"),
        subtitle: t("galaxyssi.discover.pairing.subtitle", "Scan QR codes and connect GalaxySSI Desktop"),
        systemImage: "qrcode.viewfinder",
        tint: .galaxySSIAccent,
        badge: t("galaxyssi.common.connect", "Connect")
      ) {
        PairingView()
      }
    }
  }

  private var pairedDesktopBadge: String {
    let count = store.serverLinks.filter(\.paired).count
    if count > 0 {
      return String(format: t("galaxyssi.settings.paired_desktop_count", "%d paired"), count)
    }
    return t("settings_status_link_off", "No trusted Desktop yet")
  }

  private var systemStatusIcon: String {
    systemStatusNeedsAttention ? "exclamationmark.triangle" : "checkmark.shield"
  }

  private var systemStatusSubtitle: String {
    if systemStatusNeedsAttention {
      return t("cc_services_need_attention_subtitle", "Unavailable resources are excluded from automatic routing")
    }
    return t("cc_all_services_normal_subtitle", "Local execution, routing, messaging, and security are available")
  }

  private var systemStatusNeedsAttention: Bool {
    store.agentSafetySettings.executionPaused ||
      !systemStatusLinkReady ||
      systemStatusAvailableResourceCount == 0
  }

  private var systemStatusLinkReady: Bool {
    store.serverLinks.contains(where: \.paired) && linkDiagnosticsSnapshot.failureCount == 0
  }

  private var systemStatusAvailableResourceCount: Int {
    store.cloudModelContacts.count +
      store.serverLinks.filter(\.paired).count +
      store.customDeviceConnectors.filter(\.enabled).count
  }

  private var modelPlannerSummary: String {
    let settings = store.modelPlannerSettings
    guard settings.enabled else { return t("galaxyssi.settings.local_planner", "Local deterministic planner") }
    return String(
      format: t("galaxyssi.settings.model_planner.summary", "Model planning / %d actions / %d replans"),
      settings.maxActions,
      settings.maxReplans
    )
  }

  private var voiceSettingsSummary: String {
    let enabled = store.voiceSettings.wakeListeningEnabled ? t("common_on", "On") : t("common_off", "Off")
    let model = VoiceWhisperModelCatalog.model(store.voiceSettings.asrModelId).displayName
    return "\(enabled) / \(model) / \(store.voiceSettings.preferredLocaleIdentifier)"
  }

  private var textScaleSummary: String {
    let mode = store.displaySettings.textScale
    return "\(textScaleLabel(mode)) / \(textScaleDescription(mode))"
  }

  private func textScaleLabel(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system", "Follow system")
    case .standard:
      return t("cc_text_size_standard", "Standard")
    case .comfortable:
      return t("cc_text_size_comfortable", "Comfortable")
    case .large:
      return t("cc_text_size_large", "Large")
    case .extraLarge:
      return t("cc_text_size_extra_large", "Extra large")
    }
  }

  private func textScaleDescription(_ mode: AppTextScaleMode) -> String {
    switch mode {
    case .system:
      return t("cc_text_size_system_subtitle", "Use the iOS text-size preference")
    case .standard:
      return t("cc_text_size_standard_subtitle", "100% - More content on screen")
    case .comfortable:
      return t("cc_text_size_comfortable_subtitle", "110% - Recommended")
    case .large:
      return t("cc_text_size_large_subtitle", "120% - Easier to read")
    case .extraLarge:
      return t("cc_text_size_extra_large_subtitle", "132% - Maximum readability")
    }
  }

  private var languagePolicySummary: String {
    GalaxySSILanguagePolicyFormatter { key, fallback in
      t(key, fallback)
    }.summary(
      policy: store.languagePolicy,
      asrLocaleIdentifier: store.voiceSettings.preferredLocaleIdentifier
    )
  }

  private var memorySummary: String {
    return String(
      format: t("galaxyssi.agent_memory.value", "Memory: %d / conflicts: %d"),
      settingsStats.memoryCount,
      settingsStats.memoryConflictCount
    )
  }

  private var memoryControlSummary: String {
    return String(
      format: t("cc_memory_subtitle", "%d long-term memories / user controlled"),
      settingsStats.memoryCount
    )
  }

  private var knowledgeSummary: String {
    return String(
      format: t("galaxyssi.agent_knowledge.value", "Knowledge: %d items / %d sources / %d hits"),
      settingsStats.knowledgeItemCount,
      settingsStats.knowledgeSourceCount,
      settingsStats.knowledgeHitCount
    )
  }

  private var recentTaskSummary: String {
    return String(
      format: t("galaxyssi.agent_tasks.value", "Tasks: %d / running: %d"),
      settingsStats.taskCount,
      settingsStats.runningTaskCount
    )
  }

  private var automationSummary: String {
    return String(
      format: t("galaxyssi.automation.value", "Tasks: %d / enabled: %d"),
      settingsStats.automationCount,
      settingsStats.enabledAutomationCount
    )
  }

  private var agentSessionsSummary: String {
    return String(
      format: t("galaxyssi.agent_sessions.value", "Sessions: %d / archived: %d"),
      settingsStats.sessionCount,
      settingsStats.archivedSessionCount
    )
  }

  private var nativeToolsSummary: String {
    return String(
      format: t("galaxyssi.native_tool_catalog.value", "Tools: %d / available: %d"),
      settingsStats.nativeToolTotal,
      settingsStats.nativeToolAvailable
    )
  }

  private var phoneCapabilitiesSummary: String {
    return String(
      format: t("cc_phone_subtitle", "%d native tools - %d need attention"),
      settingsStats.nativeToolAvailable,
      max(settingsStats.nativeToolTotal - settingsStats.nativeToolAvailable, 0)
    )
  }

  private var nativeToolSummaryCounts: (total: Int, available: Int, needingAttention: Int) {
    (
      settingsStats.nativeToolTotal,
      settingsStats.nativeToolAvailable,
      max(settingsStats.nativeToolTotal - settingsStats.nativeToolAvailable, 0)
    )
  }

  private var mcpSummary: String {
    return String(
      format: t("galaxyssi.mcp.summary", "%d installed / %d ready / %d recommended"),
      settingsStats.mcpInstalled,
      settingsStats.mcpReady,
      settingsStats.mcpRecommended
    )
  }

  private var appVersionName: String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
      return "0.1.0"
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "0.1.0" : trimmed
  }

  private var linkDiagnosticsSummary: String {
    let snapshot = linkDiagnosticsSnapshot
    if snapshot.totalEvents == 0 {
      return t("galaxyssi.settings.link_stable", "Stable / 0 events")
    }
    return String(
      format: t("galaxyssi.settings.link.summary", "%d events / %d replay / %d failures"),
      snapshot.totalEvents,
      snapshot.replayCount,
      snapshot.failureCount
    )
  }

  private func refreshLinkDiagnostics() {
    linkDiagnosticsSnapshot = GalaxySSILinkTransportDiagnostics.snapshot()
  }

  private func requestNotifications() {
    Task {
      let allowed = await NotificationService.requestAuthorization()
      await MainActor.run {
        statusText = allowed
          ? t("galaxyssi.status.allowed", "Allowed")
          : t("galaxyssi.status.not_allowed", "Not allowed")
        statusIsError = !allowed
      }
    }
  }

  private func copy(_ value: String, message: String) {
    UIPasteboard.general.string = value
    statusText = message
    statusIsError = false
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SettingsProfileHero: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  var title: String
  var subtitle: String
  var galaxySSIIdLabel: String
  var galaxySSIId: String
  var avatarData: Data?
  var identityFingerprint: String
  var primaryBadge: String
  var secondaryBadge: String
  var secondaryTint: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      NavigationLink(destination: GalaxySSIProfileIdentityView()) {
        GalaxySSIProfileAvatar(
          data: avatarData,
          size: 52,
          fingerprint: identityFingerprint
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(
        GalaxySSILocalization.string(
          "galaxyssi.profile.avatar_edit",
          fallback: "Change profile photo",
          language: interfaceLanguage
        )
      ))
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Text(subtitle)
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(galaxySSIIdLabel): \(galaxySSIId)")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        HStack(spacing: 7) {
          SettingsStatusChip(title: primaryBadge, tint: .galaxySSIAccent)
          SettingsStatusChip(title: secondaryBadge, tint: secondaryTint)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SettingsStatusChip: View {
  var title: String
  var tint: Color

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(tint)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 8)
      .frame(minHeight: 24)
      .background(tint.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SettingsNameEditorRow: View {
  var title: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: 12) {
      SettingsIconBox(systemImage: "person.crop.circle", tint: .galaxySSITextPrimary)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
        TextField(title, text: $text)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled(true)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SettingsSectionTitle: View {
  var title: String

  var body: some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextPrimary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }
}

private struct SettingsNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    monospacedSubtitle: Bool = false,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.monospacedSubtitle = monospacedSubtitle
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      SettingsRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: monospacedSubtitle,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }
}

private struct SettingsActionRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      SettingsRowContent(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        monospacedSubtitle: monospacedSubtitle,
        showsDisclosure: false
      )
    }
    .buttonStyle(.plain)
  }
}

private struct SettingsRowContent: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var monospacedSubtitle: Bool
  var showsDisclosure: Bool

  var body: some View {
    HStack(spacing: 12) {
      SettingsIconBox(systemImage: systemImage, tint: tint)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(monospacedSubtitle ? .system(size: 12, design: .monospaced) : .system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(monospacedSubtitle ? 3 : 2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
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

private struct SettingsIconBox: View {
  var systemImage: String
  var tint: Color

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(tint.opacity(0.16))
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(tint)
    }
    .frame(width: 42, height: 42)
  }
}
