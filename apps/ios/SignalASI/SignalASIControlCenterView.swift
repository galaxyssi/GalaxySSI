import SwiftUI

struct SignalASIControlCenterView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var disclosureRecords: [AgentDataDisclosureRecord] = []

  private let disclosureStore: AgentDataDisclosureStore = FileAgentDataDisclosureStore(
    fileURL: AgentDataDisclosureStorePaths.ledgerURL()
  )

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("settings_my_signalasi", "My SignalASI"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          metrics
          intelligentCoreSection
          executionDevicesSection
          connectionTrustSection
          interactionSystemSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      disclosureRecords = disclosureStore.list(limit: 250)
    }
  }

  private var hero: some View {
    HStack(alignment: .center, spacing: 12) {
      SignalASILogoView(size: 58, cornerRadius: 10)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 8) {
          Text(t("settings_my_signalasi", "My SignalASI"))
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(agentCoreBadge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(agentCoreTint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(agentCoreTint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(t("cc_product_subtitle", "Agent operating system - This device online"))
          .font(.system(size: 14))
          .foregroundColor(.signalASITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var metrics: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
      ],
      spacing: 8
    ) {
      SignalASIControlCenterMetricCard(
        title: t("cc_metric_resources", "Intelligence resources"),
        value: "\(intelligenceResourceCount)",
        systemImage: "cpu",
        tint: .signalASIAccent
      )
      SignalASIControlCenterMetricCard(
        title: t("cc_metric_today_tasks", "Recent tasks"),
        value: "\(recentTaskCount)",
        systemImage: "clock",
        tint: .orange
      )
      SignalASIControlCenterMetricCard(
        title: t("cc_metric_security", "Security"),
        value: securityBadge,
        systemImage: "checkmark.shield",
        tint: securityTint
      )
    }
  }

  private var intelligentCoreSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_intelligent_core", "Intelligent Core"))
      SignalASIControlCenterNavigationRow(
        title: t("cc_global_agent_title", "Global Super Agent"),
        subtitle: t("cc_global_agent_subtitle", "Personal intelligence that works across conversations and long-term goals"),
        systemImage: "sparkles",
        tint: store.globalAgentSettings.enabled ? .signalASIAccent : .orange,
        badge: store.globalAgentSettings.enabled
          ? t("cc_global_understanding_active", "Global understanding active")
          : t("on_device_agent_status_paused", "Paused")
      ) {
        SignalASIGlobalAgentControlView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_agent_core_title", "Agent Core"),
        subtitle: t("cc_agent_core_subtitle", "Planning, tool use, replanning, and recovery"),
        systemImage: "cpu",
        tint: agentCoreTint,
        badge: agentCoreBadge
      ) {
        AgentSafetySettingsView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_resource_routing_title", "Models & Resource Routing"),
        subtitle: modelPlannerSummary,
        systemImage: "slider.horizontal.3",
        tint: .blue,
        badge: resourcesBadge
      ) {
        AgentModelPlannerSettingsView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_memory_title", "Memory & Personalization"),
        subtitle: String(
          format: t("cc_memory_subtitle", "%d long-term memories - user controlled"),
          memorySnapshot.activeCount
        ),
        systemImage: "archivebox",
        tint: store.agentSafetySettings.memoryCapture ? .signalASIAccent : .orange,
        badge: store.agentSafetySettings.memoryCapture ? t("status_enabled", "Enabled") : t("common_off", "Off")
      ) {
        SignalASIMemoryControlView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_knowledge_title", "Knowledge Base"),
        subtitle: String(
          format: t("cc_knowledge_subtitle", "%d sources - traceable citations"),
          store.agentKnowledgeStats.sourceCount
        ),
        systemImage: "book.closed",
        tint: .orange,
        badge: "\(store.agentKnowledgeStats.itemCount)"
      ) {
        SignalASIAgentKnowledgeView()
      }
    }
  }

  private var executionDevicesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_execution_devices", "Execution & Devices"))
      SignalASIControlCenterNavigationRow(
        title: t("cc_phone_title", "Phone Capabilities"),
        subtitle: String(
          format: t("cc_phone_subtitle", "%d native tools - %d need attention"),
          nativeToolSummary.available,
          nativeToolSummary.needingAttention
        ),
        systemImage: "iphone",
        tint: nativeToolSummary.available > 0 ? .signalASIAccent : .orange,
        badge: "\(nativeToolSummary.available)/\(nativeToolSummary.total)"
      ) {
        SignalASINativeToolCatalogView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_runtime_title", "On-device Linux Runtime"),
        subtitle: t("cc_runtime_subtitle_ios", "iOS local model, Whisper, and native runtime readiness"),
        systemImage: "terminal",
        tint: .purple,
        badge: t("cc_status_ready", "Ready")
      ) {
        SignalASILocalModelLabView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_apps_title", "Apps & Tools"),
        subtitle: t("cc_apps_subtitle", "Messaging, calendar, browser, files, and adapters"),
        systemImage: "square.grid.2x2",
        tint: .blue,
        badge: "\(SignalASIAppAdapterCatalog.adapterCount)"
      ) {
        SignalASIAppAdaptersView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_spaces_title", "Smart Spaces"),
        subtitle: t("cc_spaces_subtitle", "Home Assistant and custom devices"),
        systemImage: "homekit",
        tint: homeAssistantTint,
        badge: homeAssistantBadge
      ) {
        DeviceManagementView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_tasks_title", "Task Center"),
        subtitle: t("cc_tasks_subtitle", "Running, waiting, blocked, and completed work"),
        systemImage: "list.bullet.rectangle",
        tint: runningTaskCount > 0 ? .orange : .signalASITextSecondary,
        badge: "\(recentTaskCount)"
      ) {
        SignalASIAgentRecentTasksView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_evolution_title", "Self evolution"),
        subtitle: t("cc_evolution_subtitle", "Improve SignalASI in isolated candidates with builds, tests, and rollback"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: selfEvolutionTint,
        badge: selfEvolutionBadge
      ) {
        SignalASISelfEvolutionControlView()
      }
    }
  }

  private var connectionTrustSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_connection_trust", "Connection & Trust"))
      SignalASIControlCenterNavigationRow(
        title: t("cc_nodes_title", "Agents, Models & Nodes"),
        subtitle: t("cc_nodes_subtitle", "Desktop agents, local models, cloud APIs, and devices"),
        systemImage: "network",
        tint: intelligenceResourceCount > 0 ? .signalASIAccent : .orange,
        badge: "\(intelligenceResourceCount)"
      ) {
        SignalASIAgentsModelsNodesView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_security_title", "Security & Trust"),
        subtitle: t("cc_security_subtitle", "Identity, encryption, trusted devices, and contacts"),
        systemImage: "checkmark.shield",
        tint: securityTint,
        badge: securityBadge
      ) {
        SignalASISecurityCenterView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_audit_title", "Permissions & Audit"),
        subtitle: t("cc_audit_subtitle_ios", "Confirmation policy, iOS permissions, and operation history"),
        systemImage: "fingerprint",
        tint: .purple,
        badge: t("common_view", "View")
      ) {
        OnDeviceAgentPermissionsView()
      }
    }
  }

  private var interactionSystemSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_interaction_system", "Interaction & System"))
      SignalASIControlCenterNavigationRow(
        title: t("cc_voice_title", "Voice & Interaction"),
        subtitle: t("cc_voice_subtitle", "Wake word, ASR, TTS, and task routing"),
        systemImage: "waveform",
        tint: store.voiceSettings.wakeListeningEnabled ? .signalASIAccent : .blue,
        badge: store.voiceSettings.wakeListeningEnabled ? t("status_enabled", "Enabled") : t("common_off", "Off")
      ) {
        VoiceSettingsView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_app_services_title", "Messages - Contacts - Discover"),
        subtitle: t("cc_app_services_subtitle", "App modules, media, contacts, providers, and notifications"),
        systemImage: "rectangle.grid.2x2",
        tint: .blue,
        badge: t("common_view", "View")
      ) {
        SignalASIControlCenterAppServicesView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_data_title", "Data & Backup"),
        subtitle: t("cc_data_subtitle", "Encrypted export, restore, storage, and cache"),
        systemImage: "externaldrive",
        tint: disclosureSummary.blocked > 0 ? .orange : .purple,
        badge: String(
          format: t("cc_privacy_destination_count", "%d destinations"),
          disclosureSummary.destinations
        )
      ) {
        AgentDataDisclosureDashboardView()
      }
      SignalASIControlCenterNavigationRow(
        title: t("cc_general_title", "General & About"),
        subtitle: t("cc_general_subtitle", "Language, notifications, diagnostics, version, and reset"),
        systemImage: "gearshape",
        tint: .signalASITextSecondary,
        badge: t("common_view", "View")
      ) {
        SignalASIControlCenterGeneralView()
      }
    }
  }

  private var nativeToolSummary: (total: Int, available: Int, needingAttention: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available, max(tools.count - available, 0))
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

  private var runningTaskCount: Int {
    recentTasks.filter {
      [.observing, .planning, .executing, .verifying, .waitingConfirmation, .waitingResponse, .paused].contains($0.phase)
    }.count
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
    store.cloudModelContacts.count + store.serverLinks.count + store.customDeviceConnectors.count
  }

  private var resourcesBadge: String {
    intelligenceResourceCount > 0 ? t("cc_status_available", "Available") : t("status_needs_setup", "Needs Setup")
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

  private var homeAssistantTint: Color {
    store.homeAssistantSettings.configured ? .signalASIAccent : .orange
  }

  private var homeAssistantBadge: String {
    if store.homeAssistantSettings.configured { return t("status_enabled", "Enabled") }
    if store.homeAssistantSettings.credentialsConfigured { return t("common_off", "Off") }
    return t("cc_status_not_configured", "Not configured")
  }

  private var disclosureSummary: AgentDataDisclosureSummary {
    AgentDataDisclosureLedger.summary(disclosureRecords)
  }

  private var securityBadge: String {
    store.profile.identityFingerprint.isEmpty ? t("cc_status_degraded", "Degraded") : t("cc_status_secure", "Secure")
  }

  private var securityTint: Color {
    store.profile.identityFingerprint.isEmpty ? .orange : .signalASIAccent
  }

  private var agentCoreBadge: String {
    store.agentSafetySettings.executionPaused
      ? t("on_device_agent_status_paused", "Paused")
      : t("cc_core_ready", "Core ready")
  }

  private var agentCoreTint: Color {
    store.agentSafetySettings.executionPaused ? .orange : .signalASIAccent
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIControlCenterAppServicesView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_app_services_page_title", "Apps & Services"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("cc_app_services_page_title", "Apps & Services"),
            subtitle: t("cc_app_services_subtitle", "App modules, media, contacts, providers, and notifications"),
            systemImage: "rectangle.grid.2x2",
            tint: .blue,
            badge: t("cc_status_ready", "Ready")
          )
          SignalASISecuritySectionTitle(title: t("cc_section_core_modules", "Core Modules"))
          SignalASIControlCenterNavigationRow(
            title: t("cc_messages_title", "Messages"),
            subtitle: t("cc_messages_subtitle", "Conversations, media, delivery, and background connection"),
            systemImage: "bubble.left.and.bubble.right",
            tint: .signalASIAccent,
            badge: t("common_view", "View")
          ) {
            ChatListView()
          }
          SignalASIControlCenterNavigationRow(
            title: t("cc_contacts_title", "Contacts"),
            subtitle: t("cc_contacts_subtitle", "People, Agents, models, devices, and remarks"),
            systemImage: "person.2",
            tint: .blue,
            badge: t("common_view", "View")
          ) {
            ContactsView()
          }
          SignalASIControlCenterNavigationRow(
            title: t("cc_discover_title", "Discover"),
            subtitle: t("cc_discover_subtitle", "Agents, cloud providers, devices, and extensions"),
            systemImage: "safari",
            tint: .purple,
            badge: t("common_view", "View")
          ) {
            DiscoverView()
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIControlCenterGeneralView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_general_title", "General & About"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: t("cc_general_title", "General & About"),
            subtitle: t("cc_general_subtitle", "Language, notifications, diagnostics, version, and reset"),
            systemImage: "gearshape",
            tint: .signalASITextSecondary,
            badge: t("common_view", "View")
          )
          SignalASISecuritySectionTitle(title: t("cc_section_general", "General"))
          SignalASIControlCenterNavigationRow(
            title: t("signalasi.language_policy.title", "Voice & Language"),
            subtitle: languagePolicySummary,
            systemImage: "globe",
            tint: .signalASIAccent,
            badge: languagePolicyBadge
          ) {
            SignalASILanguageSettingsView()
          }
          SignalASIControlCenterNavigationRow(
            title: t("cc_text_size_title", "Text Size"),
            subtitle: t("cc_text_size_subtitle", "Changes apply immediately across SignalASI and remain after restart."),
            systemImage: "textformat.size",
            tint: .blue,
            badge: t("common_view", "View")
          ) {
            SignalASITextSizeSettingsView()
          }
          SignalASIControlCenterNavigationRow(
            title: t("cc_developer_title", "Developer Options"),
            subtitle: t("cc_developer_subtitle", "Logs, network, protocol diagnostics, and experiments"),
            systemImage: "wrench.and.screwdriver",
            tint: .orange,
            badge: t("common_view", "View")
          ) {
            SignalASIAdvancedOptionsView()
          }
          SignalASIControlCenterNavigationRow(
            title: t("cc_about_title", "About"),
            subtitle: t("cc_about_subtitle", "Version, protocol, open source, and security information"),
            systemImage: "info.circle",
            tint: .purple,
            badge: t("common_view", "View")
          ) {
            SignalASIAboutView()
          }
          SignalASIControlCenterNavigationRow(
            title: t("cc_reset_title", "Reset SignalASI"),
            subtitle: t("cc_reset_subtitle", "Remove identity, contacts, tasks, knowledge, and local data"),
            systemImage: "trash",
            tint: .red,
            badge: t("cc_reset_irreversible", "Irreversible")
          ) {
            SignalASIResetDataView()
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private var languageFormatter: SignalASILanguagePolicyFormatter {
    SignalASILanguagePolicyFormatter { key, fallback in
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

private struct SignalASIControlCenterMetricCard: View {
  var title: String
  var value: String
  var systemImage: String
  var tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(tint)
        Spacer(minLength: 0)
      }
      Text(value)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.signalASITextSecondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIControlCenterNavigationRow<Destination: View>: View {
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
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(tint)
        }
        .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
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
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextSecondary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
