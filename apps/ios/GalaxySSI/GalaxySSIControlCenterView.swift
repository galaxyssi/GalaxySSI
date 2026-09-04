import SwiftUI

struct GalaxySSIControlCenterView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var runtimeBrokerHealth = AgentIOSRuntimeBrokerHealth.unchecked
  @State private var showingQRCode = false

  private let runtimeProvider = AgentIOSDefaultOnDeviceRuntimeProvider()
  private let inAppRuntimeBroker = AgentIOSInAppQemuRuntimeBroker(
    runtimeRootURL: AgentIOSDefaultOnDeviceRuntimeProvider.defaultRuntimeRootURL()
  )
  private let learningProposalStore = UserDefaultsAgentLearningProposalStore()
  private let globalAgentDeliberationStore = GlobalAgentDeliberationStore()
  private let globalAgentLongHorizonStore = GlobalLongHorizonGoalStore()
  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("settings_control_center_title", "My Agent"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          overviewCard
          connectedDevicesSection
          modelsRuntimeSection
          voiceInteractionSection
          memoryKnowledgeSection
          skillsTasksSection
          securityDataSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      refreshRuntimeBrokerHealth()
    }
    .sheet(isPresented: $showingQRCode) {
      MyContactQRCodeView()
    }
  }

  private var overviewCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      NavigationLink(destination: GalaxySSIProfileIdentityView()) {
        HStack(alignment: .center, spacing: 14) {
          GalaxySSILogoView(size: 72, cornerRadius: 12)
          VStack(alignment: .leading, spacing: 5) {
            Text(t("settings_my_galaxyssi", "My GalaxySSI"))
              .font(.system(size: 22, weight: .bold))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.72)
            Text(t("cc_product_subtitle", "Agent operating system - This device online"))
              .font(.system(size: 14))
              .foregroundColor(.galaxySSITextSecondary)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
        }
      }
      .buttonStyle(.plain)
      HStack(spacing: 10) {
        NavigationLink(destination: GalaxySSIProfileIdentityView()) {
          HStack(spacing: 6) {
            Text(store.profile.name.ifBlank(t("cc_nickname_title", "Nickname")))
              .font(.system(size: 15, weight: .semibold))
              .lineLimit(1)
            Image(systemName: "chevron.right")
              .font(.system(size: 12, weight: .semibold))
          }
          .foregroundColor(.galaxySSITextPrimary)
        }
        .buttonStyle(.plain)
        Spacer(minLength: 8)
        Button {
          showingQRCode = true
        } label: {
          Image(systemName: "qrcode")
            .font(.system(size: 19, weight: .semibold))
            .foregroundColor(.galaxySSIAccent)
            .frame(width: 38, height: 38)
            .background(Color.galaxySSIAccent.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(t("galaxyssi.discover.my_qr_title", "My QR Code")))
      }
      HStack(spacing: 8) {
        overviewBadge(agentCoreBadge, tint: agentCoreTint)
        overviewBadge(
          String(format: t("cc_trusted_devices_badge", "%d trusted devices"), trustedDeviceCount),
          tint: .blue
        )
        overviewBadge(privacyBadge, tint: privacyTint)
      }
      Divider()
        .overlay(Color.galaxySSISeparator)
      HStack(spacing: 0) {
        overviewMetric(
          value: "\(intelligenceResourceCount)",
          title: t("cc_metric_resources", "Intelligence resources")
        )
        Divider()
          .frame(height: 48)
          .overlay(Color.galaxySSISeparator)
        overviewMetric(
          value: "\(recentTaskCount)",
          title: t("cc_metric_today_tasks", "Recent tasks")
        )
        Divider()
          .frame(height: 48)
          .overlay(Color.galaxySSISeparator)
        overviewMetric(
          value: securityBadge,
          title: t("cc_metric_security", "Security")
        )
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityIdentifier("ios.control-center.overview")
  }

  private var connectedDevicesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      controlCenterSectionTitle(t("cc_section_connected_devices", "Connected devices"))
      controlCenterGroup {
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_phone_title", "Phone Capabilities"),
          subtitle: String(
            format: t("cc_phone_subtitle", "%d native tools - %d need attention"),
            nativeToolSummary.available,
            nativeToolSummary.needingAttention
          ),
          systemImage: "iphone",
          tint: nativeToolSummary.available > 0 ? .galaxySSIAccent : .orange,
          badge: "\(nativeToolSummary.available)/\(nativeToolSummary.total)"
        ) {
          GalaxySSIPhoneCapabilitiesView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_spaces_title", "Smart Spaces"),
          subtitle: t("cc_spaces_subtitle", "Home Assistant and custom devices"),
          systemImage: "homekit",
          tint: homeAssistantTint,
          badge: homeAssistantBadge
        ) {
          GalaxySSISmartSpacesView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("desktop_control_title", "Control Computer"),
          subtitle: t(
            "desktop_control_home_subtitle",
            "View the computer screen and send approved mouse or keyboard actions from this phone"
          ),
          systemImage: "desktopcomputer",
          tint: desktopControlTint,
          badge: desktopControlBadge
        ) {
          GalaxySSIDesktopControlView()
        }
      }
    }
  }

  private var modelsRuntimeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      controlCenterSectionTitle(t("cc_section_models_runtime", "Models & runtime"))
      controlCenterGroup {
        GalaxySSIControlCenterNavigationRow(
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
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_resource_routing_title", "Models & Resource Routing"),
          subtitle: modelPlannerSummary,
          systemImage: "slider.horizontal.3",
          tint: .blue,
          badge: resourcesBadge
        ) {
          GalaxySSIResourceRoutingView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_runtime_title", "On-device Linux Runtime"),
          subtitle: t(
            "cc_runtime_subtitle",
            "Python, uv, Node.js, Go, Rust, C/C++, Java, browser automation, and FFmpeg"
          ),
          systemImage: "terminal",
          tint: runtimeReady ? .galaxySSIAccent : .orange,
          badge: runtimeBadge
        ) {
          GalaxySSIOnDeviceRuntimeView()
        }
      }
    }
  }

  private var voiceInteractionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      controlCenterSectionTitle(t("cc_section_voice_interaction", "Voice & interaction"))
      controlCenterGroup {
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_voice_title", "Voice & Interaction"),
          subtitle: t("cc_voice_subtitle", "Wake word, ASR, TTS, and task routing"),
          systemImage: "waveform",
          tint: store.voiceSettings.wakeListeningEnabled ? .galaxySSIAccent : .blue,
          badge: store.voiceSettings.wakeListeningEnabled ? t("status_enabled", "Enabled") : t("common_off", "Off")
        ) {
          GalaxySSIVoiceControlCenterView()
        }
      }
    }
  }

  private var memoryKnowledgeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      controlCenterSectionTitle(t("cc_section_memory_knowledge", "Memory & knowledge"))
      controlCenterGroup {
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_memory_title", "Memory & Personalization"),
          subtitle: String(
            format: t("cc_memory_subtitle", "%d long-term memories - user controlled"),
            memorySnapshot.activeCount
          ),
          systemImage: "archivebox",
          tint: store.agentSafetySettings.memoryCapture ? .galaxySSIAccent : .orange,
          badge: store.agentSafetySettings.memoryCapture ? t("status_enabled", "Enabled") : t("common_off", "Off")
        ) {
          GalaxySSIMemoryControlCenterView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_knowledge_title", "Knowledge Base"),
          subtitle: String(
            format: t("cc_knowledge_subtitle", "%d sources - traceable citations"),
            store.agentKnowledgeStats.sourceCount
          ),
          systemImage: "book.closed",
          tint: .orange,
          badge: "\(store.agentKnowledgeStats.itemCount)"
        ) {
          GalaxySSIAgentKnowledgeView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_learning_title", "Learning & Skill Evolution"),
          subtitle: t("cc_learning_subtitle", "Learn from successful tasks; generated content requires review"),
          systemImage: "sparkles.rectangle.stack",
          tint: learningPendingCount > 0 ? .purple : .galaxySSIAccent,
          badge: "\(learningPendingCount)"
        ) {
          GalaxySSILearningSkillEvolutionView()
        }
      }
    }
  }

  private var skillsTasksSection: some View {
    let dashboard = globalAgentDashboard
    return VStack(alignment: .leading, spacing: 8) {
      controlCenterSectionTitle(t("cc_section_skills_tasks", "Skills & tasks"))
      controlCenterGroup {
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_global_agent_title", "Global Super Agent"),
          subtitle: String(
            format: t("cc_global_agent_home_subtitle", "%d topics - %d active goals - %d new insights"),
            dashboard.topicCount,
            dashboard.activeGoalCount,
            dashboard.pendingInsightCount
          ),
          systemImage: "circle.hexagongrid",
          tint: dashboard.settings.enabled ? .purple : .orange,
          badge: dashboard.settings.enabled
            ? t("cc_status_online", "Online")
            : t("galaxyssi.status.paused", "Paused")
        ) {
          GalaxySSIGlobalAgentControlView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_agent_core_title", "Agent Core"),
          subtitle: t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"),
          systemImage: "cpu",
          tint: agentCoreTint,
          badge: agentCoreBadge
        ) {
          GalaxySSIAgentCoreView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("agent_capability_library_title", "Capability Library"),
          subtitle: t("agent_capability_library_subtitle", "Manage phone tools, MCP connections, and reusable automation from one place"),
          systemImage: "shippingbox.and.arrow.down",
          tint: .galaxySSIAccent,
          badge: "\(capabilityLibraryInstalledCount)"
        ) {
          GalaxySSICapabilityLibraryView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_evolution_title", "Self evolution"),
          subtitle: t("cc_evolution_subtitle", "Improve GalaxySSI in isolated candidates with builds, tests, and rollback"),
          systemImage: "arrow.triangle.2.circlepath",
          tint: selfEvolutionTint,
          badge: selfEvolutionBadge
        ) {
          GalaxySSISelfEvolutionControlView()
        }
      }
    }
  }

  private var securityDataSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      controlCenterSectionTitle(t("cc_section_security_data", "Security & data"))
      controlCenterGroup {
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_security_title", "Security & Trust"),
          subtitle: t("cc_security_subtitle", "Identity, encryption, trusted devices, and contacts"),
          systemImage: "checkmark.shield",
          tint: .galaxySSIAccent,
          badge: securityBadge
        ) {
          GalaxySSISecurityCenterView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_identity_recovery_title", "Identity Recovery Package"),
          subtitle: t("cc_identity_recovery_subtitle", "Export encrypted identity and trust relationships"),
          systemImage: "square.and.arrow.up",
          tint: .orange,
          badge: t("common_view", "View")
        ) {
          GalaxySSIIdentityRecoveryExportView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_data_title", "Data & Backup"),
          subtitle: t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"),
          systemImage: "externaldrive",
          tint: .purple,
          badge: t("galaxyssi.data_backup.available", "Available")
        ) {
          GalaxySSIDataBackupView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_general_title", "General & About"),
          subtitle: t("cc_general_subtitle", "Language, notifications, diagnostics, version, and reset"),
          systemImage: "gearshape",
          tint: .galaxySSITextSecondary,
          badge: t("common_view", "View")
        ) {
          GalaxySSIControlCenterGeneralView()
        }
        GalaxySSIControlCenterNavigationRow(
          title: t("cc_about_title", "About"),
          subtitle: t("cc_about_subtitle", "Version, protocol, open source, and security information"),
          systemImage: "info.circle",
          tint: .galaxySSITextSecondary,
          badge: "v\(appVersionName)"
        ) {
          GalaxySSIAboutView()
        }
      }
    }
  }

  private var appVersionName: String {
    let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    return raw.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("0.1.0")
  }

  private var nativeToolSummary: (total: Int, available: Int, needingAttention: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available, max(tools.count - available, 0))
  }

  private var capabilityLibraryInstalledCount: Int {
    let installedMcp = GalaxySSIMcpControlStores.makeRegistry().list()
    let installedAutomations = UserDefaultsAgentSkillStore().list()
    let items = AgentDefaultCapabilityCatalog.marketplaceItems(
      nativeTools: AgentPhoneNativeToolCatalog.descriptors(
        capabilityStatuses: AgentPhoneCapabilityCatalog.declaredStatuses()
      ),
      installedMcp: installedMcp,
      installedAutomations: installedAutomations
    )
    return items.filter {
      $0.installState == .builtIn || $0.installState == .installed
    }.count
  }

  private var globalAgentDashboard: GalaxySSIGlobalAgentDashboardSnapshot {
    GalaxySSIGlobalAgentDashboardSnapshot.make(
      settings: store.globalAgentSettings,
      agentTasks: store.recentAgentTasks(limit: 200),
      sessions: store.agentSessions(includeArchived: true),
      memory: store.agentMemorySnapshot(),
      knowledgeStats: store.agentKnowledgeStats,
      knowledgeAudit: store.agentKnowledgeAccessAudit,
      automationTasks: store.automationTasks(),
      automationRuns: store.recentAutomationRuns(limit: 80),
      proactiveMessages: store.globalProactiveMessages,
      proactiveFeedback: store.globalAgentFeedback,
      cognitionTasks: globalAgentDeliberationStore.cognitionTasks(),
      autonomousRuns: globalAgentDeliberationStore.autonomousRuns(),
      longHorizonGoals: globalAgentLongHorizonStore.goals(),
      researchState: GalaxySSIGlobalAgentRuntimeBridge.researchState()
    )
  }

  private var memorySnapshot: AgentMemorySnapshot {
    store.agentMemorySnapshot()
  }

  private var recentTasks: [AgentTaskRecord] {
    store.recentAgentTasks(limit: 200)
  }

  private var recentTaskCount: Int {
    recentTasks.count
  }

  private var trustedDeviceCount: Int {
    store.serverLinks.filter(\.paired).count
  }

  private var runtimeReady: Bool {
    runtimeProvider.availability(operation: .execute).status == .available && runtimeBrokerHealth.isReady
  }

  private var runtimeBadge: String {
    if runtimeReady { return t("cc_status_ready", "Ready") }
    if case .checking = runtimeBrokerHealth {
      return t("galaxyssi.status.loading", "Checking")
    }
    return t("status_needs_setup", "Needs Setup")
  }

  private var learningPendingCount: Int {
    learningProposalStore.loadProposals().filter { $0.status == .pending }.count
  }

  private var selfEvolutionSummary: (review: Int, active: Int, attention: Int) {
    let tasks = (try? AgentIOSFileSelfEvolutionTaskStore().list(limit: 500)) ?? []
    let health = AgentIOSSelfEvolutionHealthAnalyzer.summarize(
      tasks: tasks,
      nowMillis: Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    )
    return (health.waitingReview, health.activeTasks, health.attentionTasks)
  }

  private var selfEvolutionTint: Color {
    if selfEvolutionSummary.attention > 0 { return .orange }
    if selfEvolutionSummary.active > 0 { return .blue }
    return .purple
  }

  private var selfEvolutionBadge: String {
    String(format: t("cc_evolution_candidate_count", "%d to review"), selfEvolutionSummary.review)
  }

  private var intelligenceResourceCount: Int {
    intelligenceResources.filter { $0.status == .available }.count
  }

  private var intelligenceResources: [AgentResourceDescriptor] {
    let targets = AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
    return AgentResourceCatalog.build(targets: targets, tools: [], nativeTools: [])
      .filter { resource in
        resource.targetId != "phone" &&
          resource.targetId != "local-system" &&
          resource.targetId != "cloud-models"
      }
  }

  private var resourcesBadge: String {
    intelligenceResourceCount > 0 ? t("cc_status_available", "Available") : t("status_needs_setup", "Needs Setup")
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

  private var localModelReady: Bool {
    LocalModelInferenceRuntime.shared.ready()
  }

  private var homeAssistantTint: Color {
    store.homeAssistantSettings.configured ? .galaxySSIAccent : .orange
  }

  private var homeAssistantBadge: String {
    if store.homeAssistantSettings.configured { return t("status_enabled", "Enabled") }
    if store.homeAssistantSettings.credentialsConfigured { return t("common_off", "Off") }
    return t("cc_status_not_configured", "Not configured")
  }

  private var securityBadge: String {
    secureLinkReady ? t("cc_status_secure", "Secure") : t("cc_status_degraded", "Degraded")
  }

  private var secureLinkReady: Bool {
    !store.profile.identityFingerprint.isEmpty &&
      store.serverLinks.contains(where: \.paired) &&
      coordinator.mqttClient.isConnected
  }

  private var privacyProtected: Bool {
    !store.modelPlannerSettings.shareScreenText &&
      !store.modelPlannerSettings.shareAgentOutputsWithPlanner
  }

  private var privacyBadge: String {
    privacyProtected
      ? t("cc_privacy_badge", "Privacy protected")
      : t("cc_status_review", "Review")
  }

  private var privacyTint: Color {
    privacyProtected ? .galaxySSIAccent : .orange
  }

  private var desktopControlLinks: [ServerLink] {
    store.serverLinks.filter(\.paired)
  }

  private var desktopControlSnapshots: [AgentDesktopRemoteControlSnapshot] {
    desktopControlLinks.map { coordinator.desktopControlSnapshot(for: $0) }
  }

  private var desktopControlBadge: String {
    guard !desktopControlLinks.isEmpty else {
      return t("status_needs_setup", "Needs Setup")
    }
    if desktopControlSnapshots.contains(where: \.authorized) {
      return t("status_enabled", "Enabled")
    }
    if desktopControlSnapshots.contains(where: \.pending) {
      return t("desktop_control_pending", "Pending")
    }
    if desktopControlSnapshots.contains(where: { $0.enabled }) {
      return t("desktop_control_not_authorized", "Not authorized")
    }
    return t("desktop_control_executor_off", "Executor off")
  }

  private var desktopControlTint: Color {
    guard !desktopControlLinks.isEmpty else { return .galaxySSITextSecondary }
    if desktopControlSnapshots.contains(where: \.authorized) {
      return .galaxySSIAccent
    }
    if desktopControlSnapshots.contains(where: \.pending) {
      return .orange
    }
    return .blue
  }

  private var agentCoreBadge: String {
    store.agentSafetySettings.executionPaused
      ? t("on_device_agent_status_paused", "Paused")
      : t("cc_core_ready", "Core ready")
  }

  private var agentCoreTint: Color {
    store.agentSafetySettings.executionPaused ? .orange : .galaxySSIAccent
  }

  private func overviewBadge(_ title: String, tint: Color) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .medium))
      .foregroundColor(tint)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .padding(.horizontal, 10)
      .frame(minHeight: 30)
      .background(tint.opacity(0.11))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func overviewMetric(value: String, title: String) -> some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.system(size: 19, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
      Text(title)
        .font(.system(size: 11))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity)
  }

  private func controlCenterSectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 17, weight: .bold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 8)
  }

  private func controlCenterGroup<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(spacing: 0) {
      content()
    }
    .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func refreshRuntimeBrokerHealth() {
    let availability = inAppRuntimeBroker.availability()
    guard availability.status == .available else {
      runtimeBrokerHealth = .notConfigured(availability.reason)
      return
    }
    runtimeBrokerHealth = .checking
    let deadline = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
      + AgentIOSInAppQemuRuntimeBroker.coldBootHealthTimeoutMillis
    DispatchQueue.global(qos: .userInitiated).async {
      let health = AgentIOSRuntimeBrokerHealthChecker.check(
        broker: inAppRuntimeBroker,
        deadlineEpochMillis: deadline,
        context: AgentNativeToolInvocationContext(
          invocationId: "control-center-runtime-\(UUID().uuidString)"
        )
      )
      DispatchQueue.main.async {
        runtimeBrokerHealth = health
      }
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIControlCenterGeneralView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_general_title", "General & About"),
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
            title: t("cc_general_title", "General & About"),
            subtitle: t("cc_general_subtitle", "Language, notifications, diagnostics, version, and reset"),
            systemImage: "gearshape",
            tint: .galaxySSITextSecondary,
            badge: t("common_view", "View")
          )
          GalaxySSISecuritySectionTitle(title: t("cc_section_general", "General"))
          GalaxySSIControlCenterNavigationRow(
            title: t("galaxyssi.language_policy.title", "Voice & Language"),
            subtitle: languagePolicySummary,
            systemImage: "globe",
            tint: .galaxySSIAccent,
            badge: languagePolicyBadge
          ) {
            GalaxySSILanguageSettingsView()
          }
          GalaxySSIControlCenterNavigationRow(
            title: t("cc_text_size_title", "Text Size"),
            subtitle: t("cc_text_size_subtitle", "Changes apply immediately across GalaxySSI and remain after restart."),
            systemImage: "textformat.size",
            tint: .blue,
            badge: t("common_view", "View")
          ) {
            GalaxySSITextSizeSettingsView()
          }
          GalaxySSIControlCenterNavigationRow(
            title: t("cc_developer_title", "Developer Options"),
            subtitle: t("cc_developer_subtitle", "Logs, network, protocol diagnostics, and experiments"),
            systemImage: "wrench.and.screwdriver",
            tint: .orange,
            badge: t("common_view", "View")
          ) {
            GalaxySSIAdvancedOptionsView()
          }
          GalaxySSIControlCenterNavigationRow(
            title: t("cc_about_title", "About"),
            subtitle: t("cc_about_subtitle", "Version, protocol, open source, and security information"),
            systemImage: "info.circle",
            tint: .purple,
            badge: t("common_view", "View")
          ) {
            GalaxySSIAboutView()
          }
          GalaxySSIControlCenterNavigationRow(
            title: t("cc_reset_title", "Reset GalaxySSI"),
            subtitle: t("cc_reset_subtitle", "Remove identity, contacts, tasks, knowledge, and local data"),
            systemImage: "trash",
            tint: .red,
            badge: t("cc_reset_irreversible", "Irreversible")
          ) {
            GalaxySSIResetDataView()
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

  private var languageFormatter: GalaxySSILanguagePolicyFormatter {
    GalaxySSILanguagePolicyFormatter { key, fallback in
      t(key, fallback)
    }
  }

  private var languagePolicySummary: String {
    languageFormatter.summary(
      policy: store.languagePolicy,
      asrLocaleIdentifier: store.voiceSettings.preferredLocaleIdentifier
    )
  }

  private var languagePolicyBadge: String {
    languageFormatter.statusBadge(for: store.languagePolicy)
  }
}

private struct GalaxySSIControlCenterNavigationRow<Destination: View>: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  let destination: Destination

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    @ViewBuilder destination: () -> Destination
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self.badge = badge
    self.destination = destination()
  }

  var body: some View {
    NavigationLink(destination: destination) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(tint.opacity(0.16))
          Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Text(subtitle)
            .font(.system(size: 13))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        if !badge.isEmpty {
          Text(badge)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(Color.galaxySSISeparator)
          .frame(height: 0.5)
          .padding(.leading, 66)
      }
    }
    .buttonStyle(.plain)
  }

}
