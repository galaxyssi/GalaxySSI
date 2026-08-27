import SwiftUI
import UIKit

struct SignalASISettingsSummarySnapshot {
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
enum SignalASISettingsSummaryCache {
  private static var cachedKey = ""
  private static var cachedSnapshot: SignalASISettingsSummarySnapshot?
  private static var cachedAt = Date.distantPast
  private static let maximumAge: TimeInterval = 30

  static func key(for store: SignalASIStore) -> String {
    let taskRevision = store.agentTaskRecords.map(\.updatedAtMillis).max() ?? 0
    let conversationRevision = store.agentConversations.map(\.updatedAt).max() ?? 0
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
      "\(store.agentConversations.count):\(conversationRevision)",
      "\(store.contacts.count):\(contactRevision)",
      safetyKey,
      localModelKey,
      nativeToolKey,
      mcpKey
    ].joined(separator: "|")
  }

  static func prepare(store: SignalASIStore) async -> SignalASISettingsSummarySnapshot {
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
    let conversations = store.agentSessions(includeArchived: true)
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
      return SignalASISettingsSummarySnapshot(
        memoryCount: memorySnapshot.activeCount,
        memoryConflictCount: memorySnapshot.conflicts.count,
        knowledgeItemCount: knowledgeStats.itemCount,
        knowledgeSourceCount: knowledgeStats.sourceCount,
        knowledgeHitCount: knowledgeHitCount,
        taskCount: taskRecords.count,
        runningTaskCount: taskRecords.filter { runningPhases.contains($0.phase) }.count,
        automationCount: automationTasks.count,
        enabledAutomationCount: automationTasks.filter(\.enabled).count,
        sessionCount: conversations.count,
        archivedSessionCount: conversations.filter { $0.status == .archived }.count,
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
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var showingAddModel = false
  @State private var statusText = ""
  @State private var statusIsError = false
  @State private var linkDiagnosticsSnapshot = SignalASILinkTransportDiagnostics.snapshot()
  @State private var settingsStatsLoading = true
  @State private var navigationContentGate = SignalASINavigationContentGate()
  @State private var settingsStats = SignalASISettingsSummarySnapshot()
  var navigateToMainTab: ((SignalASIMainTab) -> Void)? = nil
  var showsBackButton = true
  var onBackToAgent: (() -> Void)? = nil

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        SignalASITopBar(
          title: t("signalasi.tab.settings", "Settings"),
          leading: {
            if showsBackButton {
              SignalASIBackButton()
            } else if let onBackToAgent {
              Button(action: onBackToAgent) {
                Image(systemName: "chevron.left")
                  .font(.system(size: 22, weight: .semibold))
                  .foregroundColor(.signalASITextPrimary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel(Text(t("signalasi.common.back", "Back")))
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
      .background(Color.signalASIPageBackground.ignoresSafeArea())
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
      SignalASISecurityHeroView(
        title: t("settings_my_signalasi", "My SignalASI"),
        subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
        systemImage: "slider.horizontal.3",
        tint: .signalASIAccent,
        badge: t("cc_loading", "Loading...")
      )
      HStack(spacing: 10) {
        ProgressView()
          .tint(.signalASIAccent)
        Text(t("cc_loading", "Loading..."))
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
      }
      .frame(maxWidth: .infinity, minHeight: 120)
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 18)
  }

  private var settingsStatsTaskID: String {
    SignalASISettingsSummaryCache.key(for: store)
  }

  private func prepareSettingsStats() async {
    let generation = navigationContentGate.begin()
    if let cached = SignalASINavigationContentPrewarm.snapshot(for: store)?.settings,
       !Task.isCancelled {
      settingsStats = cached
      settingsStatsLoading = false
    } else {
      settingsStatsLoading = true
    }
    let prepared = await SignalASISettingsSummaryCache.prepare(store: store)
    guard !Task.isCancelled, navigationContentGate.isCurrent(generation) else { return }
    settingsStats = prepared
    settingsStatsLoading = false
  }

  private var profileSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsProfileHero(
        title: store.profile.name.ifBlank(t("settings_profile_me", "Me")),
        subtitle: t("settings_control_center_subtitle", "Local Agent control center"),
        signalASIIdLabel: t("settings_signalasi_id", "SignalASI ID"),
        signalASIId: store.profile.signalASIId,
        avatarData: store.profile.avatarData,
        identityFingerprint: store.profile.identityFingerprint,
        primaryBadge: store.agentSafetySettings.executionPaused
          ? t("signalasi.settings.execution_paused", "Execution Paused")
          : t("settings_badge_agent_enabled", "Local Agent Enabled"),
        secondaryBadge: store.serverLinks.contains(where: \.paired)
          ? t("settings_badge_connection_ok", "Connection OK")
          : t("settings_status_link_off", "No trusted Desktop yet"),
        secondaryTint: store.serverLinks.contains(where: \.paired) ? .signalASIInsightText : .orange
      )
      SettingsNameEditorRow(
        title: t("signalasi.settings.name", "Name"),
        text: Binding(
          get: { store.profile.name },
          set: { store.updateProfileName($0) }
        )
      )
      SettingsActionRow(
        title: t("settings_signalasi_id", "SignalASI ID"),
        subtitle: store.profile.signalASIId,
        systemImage: "link",
        tint: .signalASIAccent,
        badge: t("signalasi.common.copy", "Copy"),
        monospacedSubtitle: true
      ) {
        copy(store.profile.signalASIId, message: t("signalasi.security_center.copied_signalasi_id", "SignalASI ID copied"))
      }
      SettingsNavigationRow(
        title: t("cc_profile_title", "My SignalASI"),
        subtitle: t("cc_profile_subtitle_ios", "Identity protected by the iOS security boundary"),
        systemImage: "person.crop.circle",
        tint: .signalASITextPrimary,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIProfileIdentityView()
      }
      SettingsNavigationRow(
        title: t("settings_my_signalasi", "My SignalASI"),
        subtitle: t("cc_product_subtitle", "Agent operating system - This device online"),
        systemImage: "slider.horizontal.3",
        tint: .signalASIAccent,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIControlCenterView()
      }
    }
  }

  @ViewBuilder
  private var statusSection: some View {
    if !statusText.isEmpty {
      SignalASISecurityStatusRow(
        title: t("signalasi.common.status", "Status"),
        subtitle: statusText,
        systemImage: statusIsError ? "xmark.circle" : "checkmark.circle",
        tint: statusIsError ? .red : .signalASIAccent,
        badge: statusIsError
          ? t("signalasi.status.needs_setup", "Needs Setup")
          : t("signalasi.status.ready", "Ready")
      )
    }
  }

  private var agentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_agent", "Agent & Capabilities"))
      SettingsNavigationRow(
        title: t("signalasi.discover.ai_agent_title", "AI Agent"),
        subtitle: t("signalasi.discover.ai_agent_subtitle", "Explore powerful AI assistants"),
        systemImage: "cpu",
        tint: .signalASIAccent,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIMyAgentsView()
      }
      SettingsNavigationRow(
        title: t("cc_agent_core_title", "Agent Core"),
        subtitle: t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"),
        systemImage: "cpu",
        tint: .signalASIAccent,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentCoreView()
      }
      SettingsNavigationRow(
        title: t("agent_capability_library_title", "Capability Library"),
        subtitle: t("agent_capability_library_subtitle", "Manage phone tools, MCP connections, and reusable automation from one place"),
        systemImage: "shippingbox.and.arrow.down",
        tint: .signalASIAccent,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASICapabilityLibraryView()
      }
      SettingsNavigationRow(
        title: t("cc_phone_title", "Phone Capabilities"),
        subtitle: phoneCapabilitiesSummary,
        systemImage: "iphone",
        tint: .signalASIInsightText,
        badge: "\(nativeToolSummaryCounts.available)/\(nativeToolSummaryCounts.total)"
      ) {
        SignalASIPhoneCapabilitiesView()
      }
      SettingsNavigationRow(
        title: t("signalasi.native_tool_catalog.title", "Native Tools"),
        subtitle: nativeToolsSummary,
        systemImage: "wrench.and.screwdriver",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASINativeToolCatalogView()
      }
      SettingsNavigationRow(
        title: t("agent_mcp_title", "MCP"),
        subtitle: mcpSummary,
        systemImage: "shippingbox",
        tint: .blue,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIMcpControlCenterView()
      }
      SettingsNavigationRow(
        title: t("cc_app_tools_title", "Apps & Tools"),
        subtitle: t("cc_apps_subtitle", "Messaging, calendar, browser, files, and adapters"),
        systemImage: "rectangle.3.group",
        tint: .blue,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAppToolsView()
      }
      SettingsNavigationRow(
        title: t("agent_app_adapters_title", "Specialized App Adapters"),
        subtitle: String(
          format: t("signalasi.settings.app_adapters.status", "%d adapters / iOS handoff boundaries"),
          SignalASIAppAdapterCatalog.adapterCount
        ),
        systemImage: "square.grid.2x2",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAppAdaptersView()
      }
    }
  }

  private var agentToolsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_agent_tools", "Agent tools"))
      SettingsNavigationRow(
        title: t("agent_quick_understand", "Understand"),
        subtitle: t("signalasi.settings.agent_tools.understand_subtitle", "Screen understanding, visible UI, notifications, and device status"),
        systemImage: "rectangle.on.rectangle",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentScreenUnderstandingView()
      }
      SettingsNavigationRow(
        title: t("agent_quick_save_screen", "Memory"),
        subtitle: memorySummary,
        systemImage: "brain",
        tint: .purple,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentMemoryView()
      }
      SettingsNavigationRow(
        title: t("agent_quick_search_knowledge", "Knowledge"),
        subtitle: knowledgeSummary,
        systemImage: "book.closed",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentKnowledgeView()
      }
      SettingsNavigationRow(
        title: t("agent_quick_permissions", "Controls"),
        subtitle: t("signalasi.settings.agent_tools.controls_subtitle", "Permissions, on-device access, and action boundaries"),
        systemImage: "hand.raised",
        tint: .orange,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        OnDeviceAgentPermissionsView()
      }
      SettingsNavigationRow(
        title: t("agent_section_recent_tasks", "Recent Tasks"),
        subtitle: recentTaskSummary,
        systemImage: "clock.arrow.circlepath",
        tint: .signalASIAccent,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentRecentTasksView()
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
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIExecutionPolicyView()
      }
      SettingsNavigationRow(
        title: t("signalasi.settings.execution_policy", "Execution Policy"),
        subtitle: "\(t(store.agentSafetySettings.taskExecutionMode.displayTitle, store.agentSafetySettings.taskExecutionMode.displayTitle)) / \(t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle))",
        systemImage: "hand.raised",
        tint: .orange,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        AgentSafetySettingsView()
      }
      SettingsNavigationRow(
        title: t("cc_memory_title", "Memory & Personalization"),
        subtitle: memoryControlSummary,
        systemImage: "memorychip",
        tint: .purple,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIMemoryControlCenterView()
      }
      SettingsNavigationRow(
        title: t("signalasi.agent_memory.title", "Personal Memory"),
        subtitle: memorySummary,
        systemImage: "brain",
        tint: .purple,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentMemoryView()
      }
      SettingsNavigationRow(
        title: t("signalasi.agent_knowledge.title", "Knowledge"),
        subtitle: knowledgeSummary,
        systemImage: "book.closed",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentKnowledgeView()
      }
      SettingsNavigationRow(
        title: t("signalasi.agent_tasks.title", "Tasks"),
        subtitle: recentTaskSummary,
        systemImage: "checklist",
        tint: .signalASIAccent,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentRecentTasksView()
      }
      SettingsNavigationRow(
        title: t("signalasi.automation.title", "Automation"),
        subtitle: automationSummary,
        systemImage: "clock",
        tint: .orange,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIAutomationView()
      }
      SettingsNavigationRow(
        title: t("signalasi.skill_marketplace.title", "Skill Marketplace"),
        subtitle: t("signalasi.skill_marketplace.settings_subtitle", "Install, enable, and review reusable Agent Skills"),
        systemImage: "sparkles.rectangle.stack",
        tint: .purple,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASISkillMarketplaceView()
      }
      SettingsNavigationRow(
        title: t("signalasi.agent_sessions.title", "Sessions"),
        subtitle: agentSessionsSummary,
        systemImage: "bubble.left.and.bubble.right",
        tint: .signalASIAccent,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIConversationHubView()
      }
      SettingsNavigationRow(
        title: t("cc_learning_title", "Learning & Skill Evolution"),
        subtitle: t("cc_learning_subtitle", "Learn from successful tasks; generated content requires review"),
        systemImage: "sparkles.rectangle.stack",
        tint: .purple,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASILearningSkillEvolutionView()
      }
      SettingsNavigationRow(
        title: t("cc_resource_routing_title", "Models & Resource Routing"),
        subtitle: t("cc_resource_routing_subtitle", "Choose by quality, latency, privacy, cost, and availability"),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: .blue,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIResourceRoutingView()
      }
      SettingsNavigationRow(
        title: t("signalasi.discover.model_planner", "Model Planner"),
        subtitle: modelPlannerSummary,
        systemImage: "slider.horizontal.3",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.manage", "Manage")
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
        tint: .signalASIAccent,
        badge: pairedDesktopBadge
      ) {
        SignalASISecurityCenterView()
      }
      SettingsNavigationRow(
        title: t("settings_permission_audit", "Permission Audit"),
        subtitle: t("settings_permission_audit_subtitle", "Check phone permissions and Agent action grants"),
        systemImage: "checkmark.shield",
        tint: .orange,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIPermissionsAuditView()
      }
      SettingsNavigationRow(
        title: t("signalasi.discover.device_center", "Device Center"),
        subtitle: t("signalasi.discover.device.subtitle", "Custom devices, Home Assistant and connectors"),
        systemImage: "antenna.radiowaves.left.and.right",
        tint: .signalASIAccent,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        DeviceManagementView()
      }
      SettingsNavigationRow(
        title: t("cc_nodes_title", "Agents, Models & Nodes"),
        subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
        systemImage: "link.circle",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIAgentsModelsNodesView()
      }
      SettingsNavigationRow(
        title: t("signalasi.discover.pairing", "Pairing"),
        subtitle: t("signalasi.discover.pairing.subtitle", "Scan QR codes and connect SignalASI Desktop"),
        systemImage: "qrcode.viewfinder",
        tint: .signalASIAccent,
        badge: t("signalasi.common.connect", "Connect")
      ) {
        PairingView()
      }
      SettingsNavigationRow(
        title: t("cc_system_status_title", "System Status"),
        subtitle: systemStatusSubtitle,
        systemImage: systemStatusIcon,
        tint: systemStatusNeedsAttention ? .orange : .signalASIAccent,
        badge: systemStatusNeedsAttention ? t("cc_status_degraded", "Degraded") : t("cc_status_normal", "Normal")
      ) {
        SignalASISystemStatusView()
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
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIProtocolQualityView()
      }
      SettingsNavigationRow(
        title: t("signalasi.settings.link_diagnostics", "Link Diagnostics"),
        subtitle: linkDiagnosticsSummary,
        systemImage: "waveform.path.ecg",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASILinkDiagnosticsView()
      }
      SettingsNavigationRow(
        title: t("settings_advanced_options", "Advanced Options"),
        subtitle: t("settings_advanced_options_subtitle", "Logs, network, and protocol diagnostics"),
        systemImage: "exclamationmark.triangle",
        tint: .orange,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIAdvancedOptionsView()
      }
    }
  }

  private var localIntelligenceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_local_intelligence", "Local Intelligence"))
      SettingsNavigationRow(
        title: t("signalasi.settings.local_model", "Local Model Settings"),
        subtitle: t("signalasi.settings.local_model.status", "Configure on-device inference"),
        systemImage: "cpu",
        tint: .signalASIAccent,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASILocalModelLabView()
      }
      SettingsNavigationRow(
        title: t("cc_runtime_title", "On-device Linux Runtime"),
        subtitle: t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"),
        systemImage: "terminal",
        tint: .teal,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIOnDeviceRuntimeView()
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
        tint: .signalASIInsightText,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIVoiceAssistantSettingsView()
      }
      SettingsNavigationRow(
        title: t("cc_voice_title", "Voice & Interaction"),
        subtitle: t("signalasi.discover.voice.subtitle", "Wake, transcription and local voice models"),
        systemImage: "mic",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIVoiceControlCenterView()
      }
      if store.cloudModelContacts.isEmpty {
        SettingsActionRow(
          title: t("signalasi.settings.add_model", "Add Model"),
          subtitle: t("discover_add_cloud_model_subtitle", "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"),
          systemImage: "plus.circle",
          tint: .signalASIAccent,
          badge: t("signalasi.common.add", "Add")
        ) {
          showingAddModel = true
        }
      } else {
        ForEach(store.cloudModelContacts) { contact in
          SettingsNavigationRow(
            title: contact.displayName,
            subtitle: contact.selectedCloudModel?.modelId ?? t("signalasi.settings.no_model", "No model"),
            systemImage: "cloud",
            tint: .blue,
            badge: t("signalasi.common.manage", "Manage")
          ) {
            SignalASICloudModelSwitchView(contactId: contact.id)
          }
        }
        SettingsActionRow(
          title: t("signalasi.settings.add_model", "Add Model"),
          subtitle: t("discover_add_cloud_model_subtitle", "Call OpenAI, Claude, Gemini, DeepSeek, Qwen, and other APIs directly on the phone"),
          systemImage: "plus.circle",
          tint: .signalASIAccent,
          badge: t("signalasi.common.add", "Add")
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
        tint: .signalASIInsightText,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIDataBackupView()
      }
      SettingsNavigationRow(
        title: t("settings_backup_chat", "Backup"),
        subtitle: t("settings_backup_scope", "Encrypted export of identity, contacts, Agent data, and chats"),
        systemImage: "square.and.arrow.up",
        tint: .blue,
        badge: t("signalasi.common.export", "Export")
      ) {
        SignalASIDataBackupView(initialMode: .export)
      }
      SettingsNavigationRow(
        title: t("settings_import_backup", "Import"),
        subtitle: t("settings_import_scope", "Restore data from an encrypted .hcback backup"),
        systemImage: "square.and.arrow.down",
        tint: .signalASIAccent,
        badge: t("signalasi.common.import", "Import")
      ) {
        SignalASIDataBackupView(initialMode: .importBackup)
      }
      SettingsNavigationRow(
        title: t("cc_privacy_dashboard_title", "Privacy Dashboard"),
        subtitle: t("cc_privacy_dashboard_hero_subtitle", "A metadata-only audit of data sent to cloud models and trusted Desktop Agents"),
        systemImage: "lock.doc",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIPrivacyControlCenterView()
      }
      SettingsNavigationRow(
        title: t("signalasi.settings.model_data_sharing", "Model Data Sharing"),
        subtitle: t("signalasi.settings.model_data_sharing.subtitle", "Review metadata-only disclosure events and destination blocks"),
        systemImage: "doc.text.magnifyingglass",
        tint: .blue,
        badge: t("signalasi.common.view", "View")
      ) {
        SignalASIPrivacyDashboardView()
      }
      SettingsNavigationRow(
        title: t("settings_destroy_data", "Reset Data"),
        subtitle: t("destroy_data_hero_subtitle", "This deletes identity, contacts, chat history, keys, cache, and backup data."),
        systemImage: "trash",
        tint: .red,
        badge: t("settings_reset_short", "Reset")
      ) {
        SignalASIResetDataView()
      }
    }
  }

  private var generalSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_general", "General"))
      SettingsNavigationRow(
        title: t("cc_general_page_title", "General"),
        subtitle: t("signalasi.general_settings.subtitle", "Language, appearance, text size, notifications, and app information"),
        systemImage: "gearshape",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASIGeneralSettingsView()
      }
      SettingsNavigationRow(
        title: t("signalasi.language_policy.title", "Voice & Language"),
        subtitle: languagePolicySummary,
        systemImage: "globe",
        tint: .signalASIAccent,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASILanguageSettingsView()
      }
      SettingsNavigationRow(
        title: t("cc_text_size_title", "Text Size"),
        subtitle: textScaleSummary,
        systemImage: "textformat.size",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.manage", "Manage")
      ) {
        SignalASITextSizeSettingsView()
      }
      SettingsActionRow(
        title: t("settings_notifications", "Notifications"),
        subtitle: t("settings_notifications_subtitle", "Agent actions, safety alerts, and background status"),
        systemImage: "bell.badge",
        tint: .orange,
        badge: t("signalasi.common.open", "Open")
      ) {
        requestNotifications()
      }
      SettingsNavigationRow(
        title: t("settings_about_signalasi", "About SignalASI"),
        subtitle: String(format: t("settings_about_version_summary", "Version %@ - Signal Link v2"), appVersionName),
        systemImage: "info.circle",
        tint: .signalASITextPrimary,
        badge: t("settings_about_short", "About")
      ) {
        SignalASIAboutView()
      }
    }
  }

  private var pagesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsSectionTitle(title: t("settings_control_pages", "App Pages"))
      mainPageRow(
        title: t("signalasi.tab.messages", "Messages"),
        subtitle: t("signalasi.settings.page_messages_subtitle", "Conversations with people, Agents, and devices"),
        systemImage: "bubble.left.and.bubble.right",
        tint: .signalASIAccent,
        badge: t("signalasi.common.open", "Open"),
        tab: .messages
      ) {
        ChatListView()
      }
      mainPageRow(
        title: t("signalasi.tab.contacts", "Contacts"),
        subtitle: t("signalasi.settings.page_contacts_subtitle", "People, friend requests, and trusted Agent contacts"),
        systemImage: "person.2",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.open", "Open"),
        tab: .contacts
      ) {
        ContactsView()
      }
      mainPageRow(
        title: t("signalasi.tab.discover", "Discover"),
        subtitle: t("discover_mesh_subtitle", "End-to-end encrypted network for people, agents, and devices"),
        systemImage: "safari",
        tint: .blue,
        badge: t("signalasi.common.open", "Open"),
        tab: .discover
      ) {
        DiscoverView()
      }
      SettingsNavigationRow(
        title: t("cc_general_page_title", "General"),
        subtitle: t("cc_general_page_subtitle", "Device, display, notifications, reset, and about"),
        systemImage: "gearshape",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.open", "Open")
      ) {
        SignalASIGeneralControlCenterView()
      }
      SettingsNavigationRow(
        title: t("cc_app_services_page_title", "Apps & Services"),
        subtitle: t("cc_app_services_subtitle", "App modules, media, contacts, providers, and notifications"),
        systemImage: "square.grid.2x2",
        tint: .signalASIInsightText,
        badge: t("signalasi.common.open", "Open")
      ) {
        SignalASIAppServicesView()
      }
      SettingsNavigationRow(
        title: t("cc_smart_spaces_title", "Smart Spaces"),
        subtitle: t("cc_spaces_subtitle", "Home Assistant and custom devices"),
        systemImage: "house",
        tint: .purple,
        badge: t("signalasi.common.open", "Open")
      ) {
        SignalASISmartSpacesView()
      }
      SettingsNavigationRow(
        title: t("cc_runtime_title", "On-device Linux Runtime"),
        subtitle: t("cc_runtime_subtitle", "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"),
        systemImage: "terminal",
        tint: .teal,
        badge: t("signalasi.common.open", "Open")
      ) {
        SignalASIOnDeviceRuntimeView()
      }
      SettingsNavigationRow(
        title: t("cc_runtime_software_center_title", "Software Center"),
        subtitle: t("cc_runtime_software_center_subtitle", "Find and install verified language, browser, and media tools"),
        systemImage: "shippingbox",
        tint: .blue,
        badge: t("signalasi.common.open", "Open")
      ) {
        SignalASIRuntimeSoftwareCenterView()
      }
      SettingsNavigationRow(
        title: t("signalasi.discover.pairing", "Pairing"),
        subtitle: t("signalasi.discover.pairing.subtitle", "Scan QR codes and connect SignalASI Desktop"),
        systemImage: "qrcode.viewfinder",
        tint: .signalASIAccent,
        badge: t("signalasi.common.connect", "Connect")
      ) {
        PairingView()
      }
    }
  }

  @ViewBuilder
  private func mainPageRow<Destination: View>(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    tab: SignalASIMainTab,
    @ViewBuilder fallbackDestination: () -> Destination
  ) -> some View {
    if let navigateToMainTab {
      SettingsActionRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge
      ) {
        navigateToMainTab(tab)
      }
    } else {
      SettingsNavigationRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge
      ) {
        fallbackDestination()
      }
    }
  }

  private var pairedDesktopBadge: String {
    let count = store.serverLinks.filter(\.paired).count
    if count > 0 {
      return String(format: t("signalasi.settings.paired_desktop_count", "%d paired"), count)
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
    guard settings.enabled else { return t("signalasi.settings.local_planner", "Local deterministic planner") }
    return String(
      format: t("signalasi.settings.model_planner.summary", "Model planning / %d actions / %d replans"),
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
    SignalASILanguagePolicyFormatter { key, fallback in
      t(key, fallback)
    }.summary(
      policy: store.languagePolicy,
      asrLocaleIdentifier: store.voiceSettings.preferredLocaleIdentifier
    )
  }

  private var memorySummary: String {
    return String(
      format: t("signalasi.agent_memory.value", "Memory: %d / conflicts: %d"),
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
      format: t("signalasi.agent_knowledge.value", "Knowledge: %d items / %d sources / %d hits"),
      settingsStats.knowledgeItemCount,
      settingsStats.knowledgeSourceCount,
      settingsStats.knowledgeHitCount
    )
  }

  private var recentTaskSummary: String {
    return String(
      format: t("signalasi.agent_tasks.value", "Tasks: %d / running: %d"),
      settingsStats.taskCount,
      settingsStats.runningTaskCount
    )
  }

  private var automationSummary: String {
    return String(
      format: t("signalasi.automation.value", "Tasks: %d / enabled: %d"),
      settingsStats.automationCount,
      settingsStats.enabledAutomationCount
    )
  }

  private var agentSessionsSummary: String {
    return String(
      format: t("signalasi.agent_sessions.value", "Sessions: %d / archived: %d"),
      settingsStats.sessionCount,
      settingsStats.archivedSessionCount
    )
  }

  private var nativeToolsSummary: String {
    return String(
      format: t("signalasi.native_tool_catalog.value", "Tools: %d / available: %d"),
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
      format: t("signalasi.mcp.summary", "%d installed / %d ready / %d recommended"),
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
      return t("signalasi.settings.link_stable", "Stable / 0 events")
    }
    return String(
      format: t("signalasi.settings.link.summary", "%d events / %d replay / %d failures"),
      snapshot.totalEvents,
      snapshot.replayCount,
      snapshot.failureCount
    )
  }

  private func refreshLinkDiagnostics() {
    linkDiagnosticsSnapshot = SignalASILinkTransportDiagnostics.snapshot()
  }

  private func requestNotifications() {
    Task {
      let allowed = await NotificationService.requestAuthorization()
      await MainActor.run {
        statusText = allowed
          ? t("signalasi.status.allowed", "Allowed")
          : t("signalasi.status.not_allowed", "Not allowed")
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
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SettingsProfileHero: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var title: String
  var subtitle: String
  var signalASIIdLabel: String
  var signalASIId: String
  var avatarData: Data?
  var identityFingerprint: String
  var primaryBadge: String
  var secondaryBadge: String
  var secondaryTint: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      NavigationLink(destination: SignalASIProfileIdentityView()) {
        SignalASIProfileAvatar(
          data: avatarData,
          size: 52,
          fingerprint: identityFingerprint
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(
        SignalASILocalization.string(
          "signalasi.profile.avatar_edit",
          fallback: "Change profile photo",
          language: interfaceLanguage
        )
      ))
      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Text(subtitle)
          .font(.system(size: 13))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text("\(signalASIIdLabel): \(signalASIId)")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        HStack(spacing: 7) {
          SettingsStatusChip(title: primaryBadge, tint: .signalASIAccent)
          SettingsStatusChip(title: secondaryBadge, tint: secondaryTint)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASISurface)
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
      SettingsIconBox(systemImage: "person.crop.circle", tint: .signalASITextPrimary)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
        TextField(title, text: $text)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled(true)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SettingsSectionTitle: View {
  var title: String

  var body: some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.signalASITextPrimary)
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
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(monospacedSubtitle ? .system(size: 12, design: .monospaced) : .system(size: 12))
          .foregroundColor(.signalASITextSecondary)
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
          .foregroundColor(.signalASITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
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
