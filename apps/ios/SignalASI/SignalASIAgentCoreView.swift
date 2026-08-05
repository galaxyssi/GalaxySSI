import SwiftUI

struct SignalASIAgentCoreView: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: SignalASIStore

  var body: some View {
    VStack(spacing: 0) {
      SignalASITopBar(
        title: t("cc_agent_core_title", "Agent Core"),
        leading: {
          SignalASIBackButton()
        },
        trailing: {
          Image(systemName: "cpu")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.signalASITextPrimary)
            .frame(width: 44, height: 44)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          statusBanner
          autonomySection
          coreCapabilitiesSection
          runtimeProtectionSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.signalASIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
  }

  private var statusBanner: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill((isPaused ? Color.orange : Color.signalASIAccent).opacity(0.16))
        Image(systemName: isPaused ? "pause.circle" : "checkmark.shield")
          .font(.system(size: 22, weight: .semibold))
          .foregroundColor(isPaused ? .orange : .signalASIAccent)
      }
      .frame(width: 48, height: 48)

      VStack(alignment: .leading, spacing: 4) {
        Text(isPaused ? t("cc_agent_paused", "Agent execution paused") : t("cc_agent_running", "Agent core is running"))
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.78)
        Text(isPaused ? t("signalasi.agent_core.paused_subtitle", "Tasks keep their state and can continue after execution is resumed") : t("cc_agent_running_subtitle", "Planning, tools, recovery, and safety controls are active"))
          .font(.system(size: 12))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var autonomySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_autonomy", "Autonomy"))
      SignalASISecurityNavigationRow(
        title: t("cc_autonomy_title", "Smart Automatic"),
        subtitle: t("cc_autonomy_subtitle", "Low-risk actions run directly; sensitive actions ask first"),
        systemImage: "checkmark.shield",
        tint: .blue,
        badge: t(store.agentPreferenceMode.titleKey, store.agentPreferenceMode.titleFallback)
      ) {
        SignalASIExecutionPolicyView()
      }
    }
  }

  private var coreCapabilitiesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_core_capabilities", "Core Capabilities"))
      SignalASISecurityNavigationRow(
        title: t("cc_planning_title", "Planning & Replanning"),
        subtitle: String(
          format: t("cc_planning_subtitle", "Model-driven planning / up to %d replans"),
          store.modelPlannerSettings.maxReplans
        ),
        systemImage: "slider.horizontal.3",
        tint: .blue,
        badge: enabledBadge(store.modelPlannerSettings.dynamicReplanning)
      ) {
        AgentModelPlannerSettingsView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_multitask_title", "Concurrent Tasks"),
        subtitle: t("cc_multitask_subtitle", "Independent tasks run without blocking the interface"),
        systemImage: "rectangle.stack",
        tint: .signalASIAccent,
        badge: enabledBadge(store.modelPlannerSettings.multiAgentCoordination)
      ) {
        AgentModelPlannerSettingsView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_failure_recovery_title", "Failure Recovery"),
        subtitle: t("cc_failure_recovery_subtitle", "Resume checkpoints and select a healthy fallback resource"),
        systemImage: "arrow.clockwise.circle",
        tint: .orange,
        badge: t("signalasi.status.ready", "Ready")
      ) {
        SignalASIResourceRoutingView()
      }
      SignalASISecurityNavigationRow(
        title: t("cc_resource_routing_title", "Models & Resource Routing"),
        subtitle: t("cc_resource_routing_subtitle", "Choose by quality, latency, privacy, cost, and availability"),
        systemImage: "cpu",
        tint: .purple,
        badge: resourceRoutingBadge
      ) {
        SignalASIResourceRoutingView()
      }
    }
  }

  private var runtimeProtectionSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SignalASISecuritySectionTitle(title: t("cc_section_runtime_protection", "Runtime Protection"))
      SignalASIAgentCoreToggleRow(
        title: t("cc_pause_all_title", "Pause All Execution"),
        subtitle: t("cc_pause_all_subtitle", "Preserve task state and resume later"),
        systemImage: "pause.circle",
        tint: isPaused ? .orange : .signalASIAccent,
        isOn: pauseBinding
      )
      SignalASISecurityNavigationRow(
        title: t("cc_advanced_agent_settings", "Advanced Agent Settings"),
        subtitle: t("cc_advanced_agent_settings_subtitle", "Tool limits, model planner, sharing, and capability grants"),
        systemImage: "gearshape",
        tint: .signalASITextSecondary,
        badge: ""
      ) {
        AgentModelPlannerSettingsView()
      }
    }
  }

  private var isPaused: Bool {
    store.agentSafetySettings.executionPaused
  }

  private var pauseBinding: Binding<Bool> {
    Binding(
      get: { store.agentSafetySettings.executionPaused },
      set: { value in store.updateAgentSafetySettings { $0.executionPaused = value } }
    )
  }

  private var resourceRoutingBadge: String {
    if store.modelPlannerSettings.enabled {
      return t("status_enabled", "Enabled")
    }
    return store.cloudModelContacts.isEmpty ? t("signalasi.status.needs_setup", "Needs Setup") : t("signalasi.common.off", "Off")
  }

  private func enabledBadge(_ enabled: Bool) -> String {
    enabled ? t("signalasi.common.on", "Enabled") : t("signalasi.common.off", "Off")
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct SignalASIAgentCoreToggleRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  @Binding var isOn: Bool

  init(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    isOn: Binding<Bool>
  ) {
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.tint = tint
    self._isOn = isOn
  }

  var body: some View {
    Toggle(isOn: $isOn) {
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
      }
    }
    .toggleStyle(SwitchToggleStyle(tint: .orange))
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
