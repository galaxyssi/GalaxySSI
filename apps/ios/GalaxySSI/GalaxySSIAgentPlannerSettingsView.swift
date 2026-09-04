import SwiftUI

struct AgentModelPlannerSettingsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var sourceSheetPresented = false

  private var settings: AgentModelPlannerSettings {
    store.modelPlannerSettings
  }

  private var plannerReady: Bool {
    guard settings.enabled else { return true }
    if settings.cloudContactId == "local-llm" {
      return LocalModelInferenceRuntime.shared.ready()
    }
    return !plannerSources.isEmpty
  }

  private var plannerSources: [PlannerModelSource] {
    let local = PlannerModelSource(
      id: "local-llm",
      title: t("galaxyssi.local_model.planner_source", "On-device model")
    )
    return [local] + store.cloudModelContacts.map { contact in
      PlannerModelSource(id: contact.id, title: contact.displayName)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_planner_settings_title", "Planning & Coordination"),
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
            title: plannerHeroTitle,
            subtitle: plannerHeroSubtitle,
            systemImage: "gearshape.2.fill",
            tint: plannerReady ? .blue : .orange,
            badge: plannerReady ? t("galaxyssi.status.ready", "Ready") : t("status_needs_setup", "Needs setup")
          )
          intelligenceSection
          taskControlSection
          privacySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .sheet(isPresented: $sourceSheetPresented) {
      PlannerSourcePickerSheet()
        .environmentObject(store)
    }
  }

  private var intelligenceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("on_device_agent_section_intelligence", "Planning Intelligence"))
      PlannerSwitchRow(
        title: t("on_device_agent_model_planner", "Model-driven Planning"),
        subtitle: t("on_device_agent_model_planner_subtitle", "Let an on-device or configured cloud model propose ActionPlans; iOS validates every action locally"),
        systemImage: "cpu",
        tint: .blue,
        isOn: boolBinding(\.enabled)
      )
      modelSourceRow
      PlannerSwitchRow(
        title: t("on_device_agent_dynamic_replanning", "Dynamic Replanning"),
        subtitle: t("on_device_agent_dynamic_replanning_subtitle", "Observe after each action and rebuild remaining steps when the screen changes or execution fails"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: .blue,
        isOn: boolBinding(\.dynamicReplanning)
      )
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_max_replans", "Maximum Replans"),
        subtitle: t("on_device_agent_max_replans_subtitle", "Bound autonomous recovery to 1, 3, or 5 plan revisions per task"),
        systemImage: "arrow.clockwise.circle.fill",
        tint: .blue,
        badge: "\(settings.maxReplans)"
      ) {
        cycleInt(\.maxReplans, values: [1, 3, 5])
      }
      PlannerSwitchRow(
        title: t("on_device_agent_multi_agent_coordination", "Multi-Agent Coordination"),
        subtitle: t("on_device_agent_multi_agent_coordination_subtitle", "Allow validated task graphs to call multiple paired Agents with explicit dependencies"),
        systemImage: "link.circle.fill",
        tint: .purple,
        isOn: boolBinding(\.multiAgentCoordination)
      )
    }
  }

  @ViewBuilder
  private var modelSourceRow: some View {
    if plannerSources.isEmpty {
      GalaxySSISecurityNavigationRow(
        title: t("on_device_agent_model_source", "Planning Model"),
        subtitle: t("on_device_agent_model_source_subtitle", "Choose an on-device or configured cloud model that proposes ActionPlans"),
        systemImage: "cpu",
        tint: .orange,
        badge: t("status_needs_setup", "Needs setup")
      ) {
        CloudModelProviderSelectionView()
      }
    } else {
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_model_source", "Planning Model"),
        subtitle: t("on_device_agent_model_source_subtitle", "Choose an on-device or configured cloud model that proposes ActionPlans"),
        systemImage: "cpu",
        tint: .blue,
        badge: plannerSourceLabel
      ) {
        sourceSheetPresented = true
      }
    }
  }

  private var taskControlSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_task_control", "Task Control"))
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_model_max_actions", "Maximum Planned Actions"),
        subtitle: t("on_device_agent_model_max_actions_subtitle", "Limit each model-generated plan to 4, 8, or 12 validated actions"),
        systemImage: "list.bullet",
        tint: .blue,
        badge: "\(settings.maxActions)"
      ) {
        cycleInt(\.maxActions, values: [4, 8, 12])
      }
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_max_tool_calls", "Maximum Tool Calls"),
        subtitle: t("on_device_agent_max_tool_calls_subtitle", "Stop repeated or runaway tool execution after 8, 16, or 32 calls"),
        systemImage: "slider.horizontal.3",
        tint: .purple,
        badge: "\(settings.maxToolCalls)"
      ) {
        cycleInt(\.maxToolCalls, values: [8, 16, 32])
      }
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_max_agent_hops", "Maximum Agent Hops"),
        subtitle: t("on_device_agent_max_agent_hops_subtitle", "Limit each task graph to 2, 4, or 8 dependency levels"),
        systemImage: "link",
        tint: .orange,
        badge: "\(settings.maxAgentHops)"
      ) {
        cycleInt(\.maxAgentHops, values: [2, 4, 8])
      }
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_max_loop_iterations", "Maximum Loop Iterations"),
        subtitle: t("on_device_agent_max_loop_iterations_subtitle", "Bound Plan, Act, Observe, and Replan cycles for every task"),
        systemImage: "repeat",
        tint: .blue,
        badge: "\(settings.maxLoopIterations)"
      ) {
        cycleInt(\.maxLoopIterations, values: [4, 8, 16, 24])
      }
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_max_phase_retries", "Maximum Phase Retries"),
        subtitle: t("on_device_agent_max_phase_retries_subtitle", "Limit retries after failed actions or verification"),
        systemImage: "arrow.uturn.left.circle.fill",
        tint: .orange,
        badge: "\(settings.maxPhaseRetries)"
      ) {
        cycleInt(\.maxPhaseRetries, values: [0, 1, 2, 3, 5])
      }
      GalaxySSISecurityActionRow(
        title: t("on_device_agent_no_progress_timeout", "No-progress Recovery"),
        subtitle: t("on_device_agent_no_progress_timeout_subtitle", "Replan only when execution stops making meaningful progress; there is no fixed task deadline"),
        systemImage: "timer",
        tint: .purple,
        badge: noProgressTimeoutLabel(settings.noProgressTimeoutSeconds)
      ) {
        cycleInt(\.noProgressTimeoutSeconds, values: [120, 300, 600, 1_200, 3_600])
      }
    }
  }

  private var privacySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_privacy_boundary", "Privacy Boundary"))
      PlannerSwitchRow(
        title: t("on_device_agent_model_screen_text", "Share Screen Text for Planning"),
        subtitle: t("on_device_agent_model_screen_text_subtitle", "Include non-sensitive visible text and element labels in model planning requests"),
        systemImage: "text.alignleft",
        tint: .purple,
        isOn: boolBinding(\.shareScreenText)
      )
      PlannerSwitchRow(
        title: t("on_device_agent_share_agent_outputs", "Share Agent Outputs with Planner"),
        subtitle: t("on_device_agent_share_agent_outputs_subtitle", "Send redacted Agent results to the selected planning model for the next decision"),
        systemImage: "shield.fill",
        tint: .orange,
        isOn: boolBinding(\.shareAgentOutputsWithPlanner)
      )
    }
  }

  private var plannerHeroSubtitle: String {
    if !settings.enabled {
      return t("cc_planner_local_subtitle", "Fast local rules remain active; model planning is disabled.")
    }
    if plannerSources.isEmpty {
      return t("cc_planner_needs_model_subtitle", "Model planning is enabled, but no ready model is configured. Local fallback remains active.")
    }
    return t("cc_planner_ready_subtitle", "A configured model can propose plans; iOS validates every action locally.")
  }

  private var plannerHeroTitle: String {
    settings.enabled
      ? t("on_device_agent_model_planner", "Model-driven Planning")
      : t("cc_planner_local_title", "Local deterministic planner")
  }

  private var plannerSourceLabel: String {
    let selected = settings.cloudContactId
    guard !selected.isEmpty else {
      return t("on_device_agent_model_source_automatic", "Automatic")
    }
    if let source = plannerSources.first(where: { $0.id == selected }) {
      return source.title
    }
    return String(format: t("galaxyssi.missing_format", "Missing: %@"), selected)
  }

  private func boolBinding(_ keyPath: WritableKeyPath<AgentModelPlannerSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { store.modelPlannerSettings[keyPath: keyPath] },
      set: { value in store.updateModelPlannerSettings { $0[keyPath: keyPath] = value } }
    )
  }

  private func cycleInt(_ keyPath: WritableKeyPath<AgentModelPlannerSettings, Int>, values: [Int]) {
    guard !values.isEmpty else { return }
    let current = store.modelPlannerSettings[keyPath: keyPath]
    let next = values.first { $0 > current } ?? values[0]
    store.updateModelPlannerSettings { $0[keyPath: keyPath] = next }
  }

  private func noProgressTimeoutLabel(_ seconds: Int) -> String {
    if seconds % 60 == 0 {
      return String(format: t("on_device_agent_no_progress_minutes", "%d min"), seconds / 60)
    }
    return String(format: t("on_device_agent_no_progress_seconds", "%d s"), seconds)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct PlannerSourcePickerSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore

  private var sources: [PlannerModelSource] {
    [
      PlannerModelSource(
        id: "local-llm",
        title: t("galaxyssi.local_model.planner_source", "On-device model")
      )
    ] + store.cloudModelContacts.map { PlannerModelSource(id: $0.id, title: $0.displayName) }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("on_device_agent_model_source", "Planning Model"),
        leading: {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
        },
        trailing: {
          Color.clear
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          GalaxySSISecuritySectionTitle(title: t("on_device_agent_model_source_subtitle", "Choose an on-device or configured cloud model that proposes ActionPlans"))
          sourceRow(
            id: "",
            title: t("on_device_agent_model_source_automatic", "Automatic"),
            subtitle: t("cc_planner_local_subtitle", "Fast local rules remain active; model planning is disabled.")
          )
          ForEach(sources) { source in
            sourceRow(id: source.id, title: source.title, subtitle: source.id)
          }
          if selectedSourceMissing {
            sourceRow(
              id: store.modelPlannerSettings.cloudContactId,
              title: String(format: t("galaxyssi.missing_format", "Missing: %@"), store.modelPlannerSettings.cloudContactId),
              subtitle: t("status_needs_setup", "Needs setup")
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
  }

  private var selectedSourceMissing: Bool {
    let selected = store.modelPlannerSettings.cloudContactId
    guard !selected.isEmpty else { return false }
    return !sources.contains { $0.id == selected }
  }

  private func sourceRow(id: String, title: String, subtitle: String) -> some View {
    let selected = id == store.modelPlannerSettings.cloudContactId
    return GalaxySSISecurityActionRow(
      title: title,
      subtitle: subtitle,
      systemImage: selected ? "checkmark.circle.fill" : (id == "local-llm" ? "cpu" : "cloud.fill"),
      tint: selected ? .galaxySSIAccent : .blue,
      badge: selected ? t("settings_language_selected", "Selected") : t("galaxyssi.common.select", "Select"),
      monospacedSubtitle: !id.isEmpty
    ) {
      store.updateModelPlannerSettings { $0.cloudContactId = id }
      dismiss()
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct PlannerSwitchRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  @Binding var isOn: Bool

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
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.82)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn)
        .labelsHidden()
        .tint(tint)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct PlannerModelSource: Identifiable {
  var id: String
  var title: String
}
