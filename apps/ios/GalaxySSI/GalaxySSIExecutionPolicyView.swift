import SwiftUI
import UserNotifications

struct GalaxySSIExecutionPolicyView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var notificationsEnabled = false

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_execution_policy_title", "Execution Policy"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Image(systemName: "checkmark.shield")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
            .frame(width: 44, height: 44)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          permissionModeSection
          confirmationRulesSection
          taskControlSection
          privacyBoundarySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refreshNotificationState)
  }

  private var permissionModeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_permission_mode_section", "Action Permissions"))
      GalaxySSISecurityNavigationRow(
        title: t("on_device_agent_permission_mode", "Execution Mode"),
        subtitle: t("on_device_agent_permission_mode_subtitle", "Tap to switch observation, suggestion, confirmation, or low-risk automation"),
        systemImage: "checkmark.shield",
        tint: .blue,
        badge: t(store.agentSafetySettings.permissionMode.displayTitle, store.agentSafetySettings.permissionMode.displayTitle)
      ) {
        AgentSafetySettingsView()
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_task_execution_mode_title", "Task execution"),
        subtitle: t("cc_task_execution_mode_subtitle", "Choose whether tasks stop after a plan or continue through verification"),
        systemImage: "play.circle",
        tint: .galaxySSIAccent,
        badge: t(store.agentSafetySettings.taskExecutionMode.displayTitle, store.agentSafetySettings.taskExecutionMode.displayTitle)
      ) {
        AgentSafetySettingsView()
      }
      GalaxySSIExecutionPolicyToggleRow(
        title: t("on_device_agent_high_risk_guard", "High-risk Guard"),
        subtitle: t("on_device_agent_high_risk_guard_subtitle", "Always protect payments, deletion, privacy sharing, installation, and security changes"),
        systemImage: "lock.shield",
        tint: store.agentSafetySettings.highRiskGuard ? .galaxySSIAccent : .orange,
        isOn: highRiskGuardBinding
      )
    }
  }

  private var confirmationRulesSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_confirmation_rules", "Confirmation Rules"))
      GalaxySSISecurityStatusRow(
        title: t("cc_direct_execution_title", "Direct Execution"),
        subtitle: t("cc_direct_execution_subtitle", "Timers, camera, flashlight, volume, apps, and device status"),
        systemImage: "paperplane",
        tint: .galaxySSIAccent,
        badge: t("cc_status_direct", "Direct")
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_first_confirm_title", "Confirm Once & Remember"),
        subtitle: t("cc_first_confirm_subtitle", "Location, microphone, downloads, contacts, calendar, and normal devices"),
        systemImage: "info.circle",
        tint: .orange,
        badge: t("cc_status_ask", "Ask")
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_always_confirm_title", "Always Confirm"),
        subtitle: t("cc_always_confirm_subtitle", "Messages, calls, deletion, installation, payment, lock, and security"),
        systemImage: "checkmark.shield",
        tint: .red,
        badge: t("galaxyssi.common.confirm", "Confirm")
      )
    }
  }

  private var taskControlSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_task_control", "Task Control"))
      GalaxySSISecurityStatusRow(
        title: t("cc_max_concurrency_title", "Maximum Concurrent Tasks"),
        subtitle: t("cc_max_concurrency_subtitle", "Up to three reasoning tasks; side effects are serialized"),
        systemImage: "rectangle.stack",
        tint: .blue,
        badge: "3 + 1"
      )
      GalaxySSISecurityNavigationRow(
        title: t("cc_tool_budget_title", "Tool-call Budget"),
        subtitle: t("cc_tool_budget_subtitle", "Prevents repeated or uncontrolled autonomous calls"),
        systemImage: "slider.horizontal.3",
        tint: .purple,
        badge: "\(store.modelPlannerSettings.maxToolCalls)"
      ) {
        AgentModelPlannerSettingsView()
      }
      GalaxySSISecurityActionRow(
        title: t("cc_long_task_notifications_title", "Long-task Status Updates"),
        subtitle: t("cc_long_task_notifications_subtitle", "Notify only when task state changes"),
        systemImage: "bell.badge",
        tint: notificationsEnabled ? .galaxySSIAccent : .orange,
        badge: notificationsEnabled ? t("galaxyssi.status.enabled", "Enabled") : t("galaxyssi.status.needs_setup", "Needs Setup")
      ) {
        requestNotifications()
      }
    }
  }

  private var privacyBoundarySection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_section_privacy_boundary", "Privacy Boundary"))
      GalaxySSISecurityNavigationRow(
        title: t("cc_sensitive_local_title", "Keep Sensitive Content Local"),
        subtitle: t("cc_sensitive_local_subtitle", "Ask before sending protected context to a remote resource"),
        systemImage: "lock.shield",
        tint: privacyProtected ? .galaxySSIAccent : .orange,
        badge: privacyProtected ? t("galaxyssi.status.enabled", "Enabled") : t("cc_status_review", "Review")
      ) {
        AgentModelPlannerSettingsView()
      }
    }
  }

  private var highRiskGuardBinding: Binding<Bool> {
    Binding(
      get: { store.agentSafetySettings.highRiskGuard },
      set: { value in store.updateAgentSafetySettings { $0.highRiskGuard = value } }
    )
  }

  private var privacyProtected: Bool {
    !store.modelPlannerSettings.shareScreenText &&
      !store.modelPlannerSettings.shareAgentOutputsWithPlanner
  }

  private func refreshNotificationState() {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        notificationsEnabled = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional ||
          settings.authorizationStatus == .ephemeral
      }
    }
  }

  private func requestNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
      refreshNotificationState()
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIExecutionPolicyToggleRow: View {
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
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Text(subtitle)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .toggleStyle(SwitchToggleStyle(tint: .orange))
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
