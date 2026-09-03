import SwiftUI

struct SignalASIGlobalAgentControlView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @State private var cognitionTasks: [GlobalCognitionTask] = []
  @State private var autonomousRuns: [GlobalAutonomousRun] = []
  @State private var longHorizonGoals: [GlobalLongHorizonGoal] = []
  @State private var researchState = GlobalResearchExecutorState()
  @State private var statusMessage = ""

  private let deliberationStore = GlobalAgentDeliberationStore()
  private let longHorizonStore = GlobalLongHorizonGoalStore()

  private var snapshot: SignalASIGlobalAgentDashboardSnapshot {
    SignalASIGlobalAgentDashboardSnapshot.make(
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
      cognitionTasks: cognitionTasks,
      autonomousRuns: autonomousRuns,
      longHorizonGoals: longHorizonGoals,
      researchState: researchState
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_global_agent_title", "Global Super Agent"),
        leading: { SignalASIBackButton() },
        trailing: {
          SignalASIAndroidIconButton(systemName: "arrow.clockwise", action: refreshRuntime)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          heroSection
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("cc_global_status_title", "Global context"),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
            )
          }
          autonomySection
          worldSection
          intelligenceSection
          resourcesSection
          privacySection
          Text(t("cc_global_footer", "Private conversations are never added to the global world model. External side effects still follow SignalASI confirmation policy."))
            .font(.system(size: 12))
            .foregroundColor(.signalASITextSecondary)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshRuntime)
  }

  private var heroSection: some View {
    let current = snapshot
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        SignalASILogoView(size: 56, cornerRadius: 10)
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            Text(t("cc_global_agent_title", "Global Super Agent"))
              .font(.system(size: 22, weight: .bold))
              .foregroundColor(.signalASITextPrimary)
              .lineLimit(1)
              .minimumScaleFactor(0.78)
            SignalASIGlobalAgentBadge(
              text: current.settings.enabled
                ? t("cc_global_understanding_active", "Global understanding active")
                : t("signalasi.status.paused", "Paused"),
              tint: current.settings.enabled ? .signalASIAccent : .orange
            )
          }
          Text(t("cc_global_agent_subtitle", "Persistent personal intelligence across every conversation and long-term goal"))
            .font(.system(size: 14))
            .foregroundColor(.signalASITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            SignalASIGlobalAgentBadge(
              text: current.settings.autonomousResearchEnabled
                ? t("cc_global_research_active", "Research active")
                : t("signalasi.status.off", "Off"),
              tint: current.settings.autonomousResearchEnabled ? .blue : .gray
            )
            SignalASIGlobalAgentBadge(
              text: current.settings.allowCloudCognition
                ? t("cc_global_cloud_allowed", "Cloud cognition")
                : t("cc_global_local_first", "Local first"),
              tint: current.settings.allowCloudCognition ? .purple : .signalASIAccent
            )
          }
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 8) {
        SignalASIGlobalAgentMetricView(
          title: t("cc_global_metric_topics", "Topics"),
          value: "\(current.topicCount)",
          systemImage: "circle.hexagongrid"
        )
        SignalASIGlobalAgentMetricView(
          title: t("cc_global_metric_links", "Links"),
          value: "\(current.crossConversationLinkCount)",
          systemImage: "link"
        )
        SignalASIGlobalAgentMetricView(
          title: t("cc_global_metric_insights", "Insights"),
          value: "\(current.pendingInsightCount)",
          systemImage: "sparkles"
        )
      }
      if current.unresolvedConflictCount > 0 {
        NavigationLink(
          destination: SignalASIGlobalAgentDetailView(kind: .conflicts, snapshot: current)
        ) {
          SignalASIGlobalAgentPlainRow(
            title: t("cc_global_conflicts_title", "Conflicts"),
            subtitle: t("cc_global_conflicts_attention", "Some memory, task, or long-horizon items need review"),
            systemImage: "exclamationmark.shield",
            tint: .orange,
            badge: "\(current.unresolvedConflictCount)",
            showsDisclosure: true
          )
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var autonomySection: some View {
    section(t("cc_global_section_autonomy", "Autonomy")) {
      toggleRow(
        title: t("cc_global_master_title", "Global understanding"),
        subtitle: t("cc_global_master_subtitle", "Observe authorized conversations and maintain the personal world model"),
        systemImage: "power",
        tint: .signalASIAccent,
        keyPath: \.enabled,
        enabled: false
      )
      toggleRow(
        title: t("cc_global_model_understanding_title", "Model-assisted understanding"),
        subtitle: t("cc_global_model_understanding_subtitle", "Use a trusted reasoning resource only when cross-topic meaning needs deeper analysis"),
        systemImage: "cpu",
        tint: .purple,
        keyPath: \.modelUnderstandingEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_autonomous_preparation_title", "Autonomous preparation"),
        subtitle: t("cc_global_autonomous_preparation_subtitle", "Prepare research, analysis, drafts, checks, and topic workspaces without external side effects"),
        systemImage: "wand.and.stars",
        tint: .blue,
        keyPath: \.autonomousPreparationEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_autonomous_tools_title", "Autonomous tools"),
        subtitle: t("cc_global_autonomous_tools_subtitle", "Let the global Agent use available phone tools and MCP under local permission and confirmation policy"),
        systemImage: "hammer",
        tint: .orange,
        keyPath: \.autonomousToolExecutionEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_dynamic_replanning_title", "Dynamic replanning"),
        subtitle: t("cc_global_dynamic_replanning_subtitle", "Review real outcomes and revise remaining steps without discarding completed evidence"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: .blue,
        keyPath: \.dynamicAutonomousReplanningEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_long_horizon_toggle_title", "Long-horizon planning"),
        subtitle: t("cc_global_long_horizon_toggle_subtitle", "Keep durable goals alive across sessions, restarts, and resource outages"),
        systemImage: "calendar.badge.clock",
        tint: .purple,
        keyPath: \.longHorizonPlanningEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_discovery_title", "Continuous discovery"),
        subtitle: t("cc_global_discovery_subtitle", "Re-evaluate authorized world-model evidence even when no new message arrives"),
        systemImage: "safari",
        tint: .signalASIAccent,
        keyPath: \.proactiveDiscoveryEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_proactive_title", "Proactive insights"),
        subtitle: t("cc_global_proactive_subtitle", "Surface valuable risks, conflicts, opportunities, and omissions"),
        systemImage: "sparkles",
        tint: .purple,
        keyPath: \.proactiveInsightsEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_learning_toggle_title", "Adaptive autonomy"),
        subtitle: t("cc_global_learning_toggle_subtitle", "Learn when, where, and how often proactive help is useful"),
        systemImage: "brain",
        tint: .blue,
        keyPath: \.adaptiveLearningEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_research_title", "Autonomous research"),
        subtitle: t("cc_global_research_subtitle", "Use available models and Agents for deeper evidence-based analysis"),
        systemImage: "magnifyingglass",
        tint: .blue,
        keyPath: \.autonomousResearchEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_topics_title", "Create topic conversations"),
        subtitle: t("cc_global_topics_subtitle", "Organize durable work into reusable Agent-created conversations"),
        systemImage: "bubble.left.and.bubble.right",
        tint: .green,
        keyPath: \.autoCreateConversationsEnabled,
        enabled: store.globalAgentSettings.enabled
      )
      toggleRow(
        title: t("cc_global_notifications_title", "Proactive notifications"),
        subtitle: t("cc_global_notifications_subtitle", "Notify only for high-value results within the daily budget"),
        systemImage: "bell.badge",
        tint: .orange,
        keyPath: \.notificationsEnabled,
        enabled: store.globalAgentSettings.enabled
      )
    }
  }

  private var worldSection: some View {
    let current = snapshot
    return section(t("cc_global_section_world", "Personal world model")) {
      navigationRow(
        kind: .goals,
        snapshot: current,
        title: t("cc_global_goals_title", "Long-term goals"),
        subtitle: t("cc_global_goals_subtitle", "Goals detected across conversations"),
        systemImage: "scope",
        tint: .purple
      )
      navigationRow(
        kind: .tasks,
        snapshot: current,
        title: t("cc_global_tasks_title", "Tracked tasks"),
        subtitle: t("cc_global_tasks_subtitle", "Open work inferred from current and past topics"),
        systemImage: "checklist",
        tint: .blue
      )
      navigationRow(
        kind: .conflicts,
        snapshot: current,
        title: t("cc_global_conflicts_title", "Conflicts"),
        subtitle: t("cc_global_conflicts_subtitle", "Decisions or constraints that need reconciliation"),
        systemImage: "exclamationmark.shield",
        tint: .orange
      )
      navigationRow(
        kind: .links,
        snapshot: current,
        title: t("cc_global_links_title", "Topic and project graph"),
        subtitle: t("cc_global_links_subtitle", "Projects, topic workspaces, and evidence-backed cross-session relationships"),
        systemImage: "link",
        tint: .green
      )
    }
  }

  private var intelligenceSection: some View {
    let current = snapshot
    return section(t("cc_global_section_intelligence", "Intelligence acquisition")) {
      navigationRow(
        kind: .cognition,
        snapshot: current,
        title: t("cc_global_cognition_queue_title", "Deep understanding"),
        subtitle: t("cc_global_cognition_queue_subtitle", "Model deliberation queued for valuable cross-conversation events"),
        systemImage: "cpu",
        tint: .purple
      )
      navigationRow(
        kind: .runs,
        snapshot: current,
        title: t("cc_global_runs_title", "Autonomous work"),
        subtitle: t("cc_global_runs_subtitle", "Safe preparation plans, delegated work, recovery, and confirmation"),
        systemImage: "play.circle",
        tint: .green
      )
      navigationRow(
        kind: .longHorizon,
        snapshot: current,
        title: t("cc_global_long_horizon_title", "Goal scheduler"),
        subtitle: t("cc_global_long_horizon_subtitle", "Persistent checkpoints and progress across every conversation"),
        systemImage: "calendar.badge.clock",
        tint: .purple
      )
      navigationRow(
        kind: .research,
        snapshot: current,
        title: t("cc_global_research_queue_title", "Research and monitoring"),
        subtitle: t("cc_global_research_queue_subtitle", "Queued, running, scheduled, and recovering research work"),
        systemImage: "magnifyingglass",
        tint: .blue
      )
      navigationRow(
        kind: .insights,
        snapshot: current,
        title: t("cc_global_pending_insights_title", "Pending insights"),
        subtitle: t("cc_global_pending_insights_subtitle", "Findings waiting for the right delivery moment"),
        systemImage: "sparkles",
        tint: .purple
      )
      navigationRow(
        kind: .learning,
        snapshot: current,
        title: t("cc_global_learning_title", "Learned behavior"),
        subtitle: t("cc_global_learning_subtitle", "Review feedback shaping proactive research and delivery"),
        systemImage: "brain",
        tint: .blue
      )
      navigationRow(
        kind: .continuity,
        snapshot: current,
        title: t("cc_global_continuity_title", "Continuity"),
        subtitle: t(current.continuityStatusKey, "Healthy"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: current.continuityQuarantinedCount > 0 ? .orange : .signalASIAccent
      )
      SignalASISecurityActionRow(
        title: t("cc_global_process_now_title", "Process now"),
        subtitle: t("cc_global_process_now_subtitle", "Process pending events and start available research work"),
        systemImage: "bolt.circle",
        tint: .signalASIAccent,
        badge: t("cc_global_process_now_action", "Run"),
        action: processNow
      )
    }
  }

  private var resourcesSection: some View {
    let current = snapshot
    return section(t("cc_global_section_resources", "Resource policy")) {
      toggleRow(
        title: t("cc_global_metered_research_title", "Research on metered networks"),
        subtitle: t("cc_global_metered_research_subtitle", "Allow autonomous research to use cellular or another metered connection"),
        systemImage: "antenna.radiowaves.left.and.right",
        tint: .orange,
        keyPath: \.allowMeteredBackgroundResearch
      )
      choiceRow(
        title: t("cc_global_daily_model_calls_title", "Daily background model calls"),
        subtitle: "\(current.modelBudget.dispatchesInWindow) / \(store.globalAgentSettings.dailyBackgroundModelCallBudget)",
        systemImage: "number",
        tint: .blue,
        badge: "\(store.globalAgentSettings.dailyBackgroundModelCallBudget)",
        choices: [12, 24, 48, 96, 200],
        label: { "\($0)" },
        set: { value in store.updateGlobalAgentSettings { $0.dailyBackgroundModelCallBudget = value } }
      )
      choiceRow(
        title: t("cc_global_concurrent_model_calls_title", "Concurrent background model calls"),
        subtitle: "\(current.modelBudget.activeCalls) / \(store.globalAgentSettings.maxConcurrentBackgroundModelCalls)",
        systemImage: "rectangle.stack",
        tint: .purple,
        badge: "\(store.globalAgentSettings.maxConcurrentBackgroundModelCalls)",
        choices: [1, 2, 3, 4, 6],
        label: { "\($0)" },
        set: { value in store.updateGlobalAgentSettings { $0.maxConcurrentBackgroundModelCalls = value } }
      )
      choiceRow(
        title: t("cc_global_daily_model_tokens_title", "Daily background tokens"),
        subtitle: "\(current.modelBudget.totalTokensInWindow) / \(store.globalAgentSettings.dailyBackgroundTokenBudget)",
        systemImage: "textformat.abc",
        tint: .green,
        badge: compactNumber(store.globalAgentSettings.dailyBackgroundTokenBudget),
        choices: [50_000, 100_000, 250_000, 500_000, 1_000_000].map(Int64.init),
        label: { compactNumber($0) },
        set: { value in store.updateGlobalAgentSettings { $0.dailyBackgroundTokenBudget = value } }
      )
      choiceRow(
        title: t("cc_global_daily_reported_cost_title", "Daily reported model spend"),
        subtitle: "\(costLabel(current.modelBudget.reportedCostMicrosInWindow)) / \(costLabel(store.globalAgentSettings.dailyBackgroundReportedCostBudgetMicros))",
        systemImage: "creditcard",
        tint: .orange,
        badge: costLabel(store.globalAgentSettings.dailyBackgroundReportedCostBudgetMicros),
        choices: [0, 250_000, 1_000_000, 5_000_000, 10_000_000].map(Int64.init),
        label: costLabel,
        set: { value in store.updateGlobalAgentSettings { $0.dailyBackgroundReportedCostBudgetMicros = value } }
      )
    }
  }

  private var privacySection: some View {
    section(t("cc_global_section_privacy", "Conversation boundaries")) {
      toggleRow(
        title: t("cc_global_cloud_cognition_title", "Allow cloud understanding"),
        subtitle: t("cc_global_cloud_cognition_subtitle", "Off by default; when enabled, relevant personal context may be sent to a configured cloud model"),
        systemImage: "cloud",
        tint: .purple,
        keyPath: \.allowCloudCognition,
        enabled: store.globalAgentSettings.enabled
      )
      SignalASISecurityNavigationRow(
        title: t("cc_global_sessions_title", "Conversation tracking"),
        subtitle: t("cc_global_sessions_subtitle", "Manage private, paused, and Agent-created topic conversations"),
        systemImage: "bubble.left.and.bubble.right",
        tint: .blue,
        badge: "\(store.agentSessions(includeArchived: true).count)"
      ) {
        SignalASIConversationHubView()
      }
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: title)
      content()
    }
  }

  private func navigationRow(
    kind: SignalASIGlobalAgentDetailKind,
    snapshot: SignalASIGlobalAgentDashboardSnapshot,
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color
  ) -> AnyView {
    if kind == .insights {
      return AnyView(
        SignalASISecurityNavigationRow(
          title: title,
          subtitle: subtitle,
          systemImage: systemImage,
          tint: tint,
          badge: "\(snapshot.count(for: kind))"
        ) {
          SignalASIGlobalAgentInsightInboxView()
        }
      )
    }
    if kind == .runs {
      return AnyView(
        SignalASISecurityNavigationRow(
          title: title,
          subtitle: subtitle,
          systemImage: systemImage,
          tint: tint,
          badge: "\(snapshot.count(for: kind))"
        ) {
          SignalASIGlobalAgentRunsView()
        }
      )
    }
    return AnyView(
      SignalASISecurityNavigationRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: "\(snapshot.count(for: kind))"
      ) {
        SignalASIGlobalAgentDetailView(kind: kind, snapshot: snapshot)
      }
    )
  }

  private func toggleRow(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    keyPath: WritableKeyPath<GlobalAgentSettings, Bool>,
    enabled: Bool = true
  ) -> some View {
    SignalASIGlobalAgentToggleRow(
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      tint: tint,
      isOn: store.globalAgentSettings[keyPath: keyPath],
      isEnabled: enabled
    ) {
      guard enabled else { return }
      store.updateGlobalAgentSettings { $0[keyPath: keyPath].toggle() }
    }
  }

  private func choiceRow<Value: Hashable>(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    badge: String,
    choices: [Value],
    label: @escaping (Value) -> String,
    set: @escaping (Value) -> Void
  ) -> some View {
    Menu {
      ForEach(choices, id: \.self) { value in
        Button(label(value)) { set(value) }
      }
    } label: {
      SignalASIGlobalAgentPlainRow(
        title: title,
        subtitle: subtitle,
        systemImage: systemImage,
        tint: tint,
        badge: badge,
        showsDisclosure: true
      )
    }
    .buttonStyle(.plain)
  }

  private var agentSessionsSummary: String {
    let sessions = store.agentSessions(includeArchived: true)
    let archived = sessions.filter { $0.status == .archived }.count
    return String(
      format: t("signalasi.agent_sessions.value", "Sessions: %d / archived: %d"),
      sessions.count,
      archived
    )
  }

  private func refreshRuntime() {
    cognitionTasks = deliberationStore.cognitionTasks()
    autonomousRuns = deliberationStore.autonomousRuns()
    longHorizonGoals = longHorizonStore.goals()
    researchState = SignalASIGlobalAgentRuntimeBridge.researchState()
  }

  private func processNow() {
    guard store.globalAgentSettings.enabled else {
      statusMessage = t("signalasi.status.paused", "Paused")
      return
    }
    let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    let limit = max(1, min(store.globalAgentSettings.dailyDiscoveryTaskBudget, 8))
    let dueTasks = store.automationTasks()
      .filter { task in
        task.enabled && (task.nextRunAtMillis <= now || task.trigger.kind == .manual)
      }
      .prefix(limit)
    var queued = 0
    for task in dueTasks {
      if (try? store.triggerAutomationTaskNow(id: task.taskId)) != nil {
        queued += 1
      }
    }
    let longHorizon = SignalASIGlobalAgentRuntimeBridge.processLongHorizonCycle(
      store: store,
      nowMillis: now
    )
    let discovery = SignalASIGlobalAgentRuntimeBridge.processProactiveDiscoveryCycle(
      store: store,
      nowMillis: now,
      force: true,
      maxTasks: limit
    )
    Task {
      await coordinator.runAutomationSchedulerCycle()
    }
    Task { @MainActor in
      _ = await coordinator.runGlobalResearchCycle(nowMillis: now)
      _ = await coordinator.runGlobalCognitionCycle(nowMillis: now)
      _ = coordinator.runGlobalAutonomousCycle(nowMillis: now)
      refreshRuntime()
    }
    refreshRuntime()
    statusMessage = String(
      format: t("cc_global_processed_result", "Processed %d events"),
      queued + discovery.queuedTaskCount + longHorizon.queuedCheckpointCount
    )
  }

  private func compactNumber(_ value: Int64) -> String {
    if value >= 1_000_000 { return "\(value / 1_000_000)M" }
    if value >= 1_000 { return "\(value / 1_000)K" }
    return "\(value)"
  }

  private func costLabel(_ micros: Int64) -> String {
    if micros <= 0 { return t("cc_global_unlimited", "Unlimited") }
    return String(format: "$%.2f", Double(micros) / 1_000_000.0)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    return SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct SignalASIGlobalAgentInsightInboxView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore
  @State private var statusMessage = ""

  private var items: [GlobalProactiveInboxItem] {
    store.globalProactiveInboxItems(limit: 40)
  }

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("agent_global_insights_title", "SignalASI insights"),
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if !statusMessage.isEmpty {
            SignalASISecurityStatusRow(
              title: t("agent_global_feedback_saved", "Feedback saved. SignalASI will adapt future insights."),
              subtitle: statusMessage,
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
            )
          }
          if items.isEmpty {
            SignalASIGlobalAgentPlainRow(
              title: t("agent_global_insights_empty", "No recent SignalASI insights."),
              subtitle: t("cc_global_pending_insights_subtitle", "Findings waiting for the right delivery moment"),
              systemImage: "sparkles",
              tint: .purple,
              badge: "0",
              showsDisclosure: false
            )
          } else {
            ForEach(items) { item in
              SignalASIGlobalInsightCard(
                item: item,
                targetLabel: targetLabel(item.target),
                feedbackLabel: item.feedbackKind.map(feedbackLabel),
                feedbackHint: t(
                  "agent_global_insight_feedback_hint",
                  "Your feedback changes when and where SignalASI intervenes."
                ),
                sourceLabel: sourceLabel(item),
                canOpenTopic: store.agentSessionDestination(id: item.destinationConversationId) != nil,
                openTitle: t("agent_global_insight_open_topic", "Open topic"),
                helpfulTitle: t("agent_global_feedback_helpful", "Helpful"),
                notRelevantTitle: t("agent_global_feedback_not_relevant", "Not relevant"),
                tooFrequentTitle: t("agent_global_feedback_too_frequent", "Too frequent"),
                onOpen: openTopic,
                onFeedback: recordFeedback
              )
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      // Match Android: opening the inbox acknowledges the currently available findings,
      // including cards that are below the initial viewport.
      items.forEach { store.markGlobalProactiveInboxViewed($0) }
    }
  }

  private func sourceLabel(_ item: GlobalProactiveInboxItem) -> String {
    var parts = [targetLabel(item.target)]
    if item.urgent {
      parts.append(t("agent_global_insight_urgent", "Important"))
    }
    let source = store.agentSession(id: item.sourceConversationId)?.title
      .ifBlank(item.topic)
      .ifBlank(item.sourceConversationId)
      .ifBlank("SignalASI") ?? item.topic.ifBlank(item.sourceConversationId).ifBlank("SignalASI")
    parts.append(String(format: t("agent_global_insight_source", "From %@"), source))
    if let deliveredAt = deliveredAtLabel(item.deliveredAtMillis) {
      parts.append(deliveredAt)
    }
    return parts.joined(separator: " / ")
  }

  private func deliveredAtLabel(_ millis: Int64) -> String? {
    guard millis > 0 else { return nil }
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = .current
    formatter.dateFormat = "MMM d, HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }

  private func targetLabel(_ target: GlobalProactiveTarget) -> String {
    switch target {
    case .currentConversation:
      return t("agent_global_insight_current_topic", "Current topic")
    case .newConversation:
      return t("agent_global_insight_new_topic", "New topic")
    case .globalDigest:
      return t("agent_global_insight_digest", "Digest")
    }
  }

  private func feedbackLabel(_ kind: GlobalAgentFeedbackKind) -> String {
    switch kind {
    case .helpful:
      return t("agent_global_feedback_helpful", "Helpful")
    case .notRelevant:
      return t("agent_global_feedback_not_relevant", "Not relevant")
    case .tooFrequent:
      return t("agent_global_feedback_too_frequent", "Too frequent")
    }
  }

  private func openTopic(_ item: GlobalProactiveInboxItem) {
    guard let destination = store.agentSessionDestination(id: item.destinationConversationId),
          store.switchAgentSession(destination) else {
      return
    }
    store.markGlobalProactiveInboxViewed(item)
    dismiss()
  }

  private func recordFeedback(_ item: GlobalProactiveInboxItem, _ kind: GlobalAgentFeedbackKind) {
    if store.recordGlobalInsightFeedback(inboxItem: item, kind: kind) {
      statusMessage = t("agent_global_feedback_saved", "Feedback saved. SignalASI will adapt future insights.")
    } else {
      statusMessage = t("agent_global_feedback_unavailable", "This insight can no longer be linked to its source.")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    return SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIGlobalInsightCard: View {
  var item: GlobalProactiveInboxItem
  var targetLabel: String
  var feedbackLabel: String?
  var feedbackHint: String
  var sourceLabel: String
  var canOpenTopic: Bool
  var openTitle: String
  var helpfulTitle: String
  var notRelevantTitle: String
  var tooFrequentTitle: String
  var onOpen: (GlobalProactiveInboxItem) -> Void
  var onFeedback: (GlobalProactiveInboxItem, GlobalAgentFeedbackKind) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill((item.urgent ? Color.orange : Color.purple).opacity(0.14))
          Image(systemName: item.urgent ? "exclamationmark.bubble" : "sparkles")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(item.urgent ? .orange : .purple)
        }
        .frame(width: 38, height: 38)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(item.title.ifBlank(targetLabel))
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
              .lineLimit(2)
            if item.isNew {
              SignalASIGlobalAgentBadge(text: "NEW", tint: .purple)
            }
            if let feedbackLabel {
              SignalASIGlobalAgentBadge(text: feedbackLabel, tint: .signalASIAccent)
            }
          }
          Text(sourceLabel)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.signalASITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      Text(item.content.ifBlank(item.topic))
        .font(.system(size: 14))
        .foregroundColor(.signalASITextPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text(feedbackHint)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      LazyVGrid(columns: feedbackColumns, alignment: .leading, spacing: 8) {
        if canOpenTopic {
          Button {
            onOpen(item)
          } label: {
            SignalASIGlobalFeedbackChip(title: openTitle, emphasized: false)
          }
        }
        Button { onFeedback(item, .helpful) } label: {
          SignalASIGlobalFeedbackChip(title: helpfulTitle, emphasized: item.feedbackKind == .helpful)
        }
        Button { onFeedback(item, .notRelevant) } label: {
          SignalASIGlobalFeedbackChip(title: notRelevantTitle, emphasized: item.feedbackKind == .notRelevant)
        }
        Button { onFeedback(item, .tooFrequent) } label: {
          SignalASIGlobalFeedbackChip(title: tooFrequentTitle, emphasized: item.feedbackKind == .tooFrequent)
        }
      }
      .buttonStyle(.plain)
    }
    .padding(12)
    .background(Color.signalASISurface)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
      .stroke(Color.signalASISeparator, lineWidth: 0.5)
    )
    .cornerRadius(8)
  }

  private var feedbackColumns: [GridItem] {
    [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)]
  }
}

private struct SignalASIGlobalFeedbackChip: View {
  var title: String
  var emphasized: Bool

  var body: some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundColor(emphasized ? .white : .signalASITextPrimary)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(emphasized ? Color.signalASIAccent : Color.signalASIButtonSoft)
      .cornerRadius(7)
  }
}

struct SignalASIGlobalAgentDetailView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var kind: SignalASIGlobalAgentDetailKind
  var snapshot: SignalASIGlobalAgentDashboardSnapshot

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: title,
        leading: { SignalASIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SignalASISecurityHeroView(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint,
            badge: "\(snapshot.count(for: kind))"
          )
          if rows.isEmpty {
            SignalASISecurityStatusRow(
              title: t("cc_global_empty_title", "Nothing queued"),
              subtitle: t("cc_global_empty_subtitle", "This area is quiet right now."),
              systemImage: "checkmark.circle",
              tint: .signalASIAccent,
              badge: t("signalasi.status.ready", "Ready")
            )
          } else {
            ForEach(rows) { row in
              SignalASIGlobalAgentPlainRow(
                title: row.title,
                subtitle: row.subtitle.ifBlank(t("cc_global_detail_no_detail", "No extra detail")),
                systemImage: row.systemImage,
                tint: row.tone.color,
                badge: row.badge,
                showsDisclosure: false
              )
            }
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

  private var title: String {
    switch kind {
    case .goals: return t("cc_global_goals_title", "Long-term goals")
    case .tasks: return t("cc_global_tasks_title", "Tracked tasks")
    case .conflicts: return t("cc_global_conflicts_title", "Conflicts")
    case .links: return t("cc_global_links_title", "Topic and project graph")
    case .cognition: return t("cc_global_cognition_queue_title", "Deep understanding")
    case .runs: return t("cc_global_runs_title", "Autonomous work")
    case .longHorizon: return t("cc_global_long_horizon_title", "Goal scheduler")
    case .research: return t("cc_global_research_queue_title", "Research and monitoring")
    case .insights: return t("cc_global_pending_insights_title", "Pending insights")
    case .learning: return t("cc_global_learning_title", "Learned behavior")
    case .continuity: return t("cc_global_continuity_title", "Continuity")
    }
  }

  private var rows: [SignalASIGlobalAgentRowItem] {
    snapshot.rows(for: kind)
  }

  private var subtitle: String {
    switch kind {
    case .goals: return t("cc_global_goals_subtitle", "Goals detected across conversations")
    case .tasks: return t("cc_global_tasks_subtitle", "Open work inferred from current and past topics")
    case .conflicts: return t("cc_global_conflicts_subtitle", "Decisions or constraints that need reconciliation")
    case .links: return t("cc_global_links_subtitle", "Projects, topic workspaces, and evidence-backed cross-session relationships")
    case .cognition: return t("cc_global_cognition_queue_subtitle", "Model deliberation queued for valuable cross-conversation events")
    case .runs: return t("cc_global_runs_subtitle", "Safe preparation plans, delegated work, recovery, and confirmation")
    case .longHorizon: return t("cc_global_long_horizon_subtitle", "Persistent checkpoints and progress across every conversation")
    case .research: return t("cc_global_research_queue_subtitle", "Queued, running, scheduled, and recovering research work")
    case .insights: return t("cc_global_pending_insights_subtitle", "Findings waiting for the right delivery moment")
    case .learning: return t("cc_global_learning_subtitle", "Review feedback shaping proactive research and delivery")
    case .continuity: return t("cc_global_continuity_subtitle", "Pending, retrying, and isolated runtime work")
    }
  }

  private var systemImage: String {
    switch kind {
    case .goals: return "scope"
    case .tasks: return "checklist"
    case .conflicts: return "exclamationmark.shield"
    case .links: return "link"
    case .cognition: return "cpu"
    case .runs: return "play.circle"
    case .longHorizon: return "calendar.badge.clock"
    case .research: return "magnifyingglass"
    case .insights: return "sparkles"
    case .learning: return "brain"
    case .continuity: return "arrow.triangle.2.circlepath"
    }
  }

  private var tint: Color {
    switch kind {
    case .conflicts: return .orange
    case .goals, .longHorizon, .cognition, .insights: return .purple
    case .links, .runs, .continuity: return .signalASIAccent
    case .tasks, .research, .learning: return .blue
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIGlobalAgentMetricView: View {
  var title: String
  var value: String
  var systemImage: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.signalASIAccent)
      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.system(size: 17, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Text(title)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 54)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct SignalASIGlobalAgentBadge: View {
  var text: String
  var tint: Color

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold))
      .foregroundColor(tint)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .padding(.horizontal, 7)
      .frame(minHeight: 22)
      .background(tint.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct SignalASIGlobalAgentToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var isOn: Bool
  var isEnabled: Bool
  var action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(isEnabled ? 0.16 : 0.08))
        Image(systemName: systemImage)
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(isEnabled ? tint : .signalASITextSecondary)
      }
      .frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(isEnabled ? .signalASITextPrimary : .signalASITextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: Binding(get: { isOn }, set: { _ in action() }))
        .labelsHidden()
        .disabled(!isEnabled)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .opacity(isEnabled ? 1 : 0.64)
  }
}

private struct SignalASIGlobalAgentPlainRow: View {
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

private extension SignalASIGlobalAgentTone {
  var color: Color {
    switch self {
    case .accent: return .signalASIAccent
    case .blue: return .blue
    case .green: return .green
    case .purple: return .purple
    case .amber: return .orange
    case .neutral: return .signalASITextSecondary
    }
  }
}
