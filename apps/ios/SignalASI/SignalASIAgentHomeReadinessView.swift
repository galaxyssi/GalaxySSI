import SwiftUI

struct SignalASIAgentHomeReadinessView: View {
  var runningTasks: Int
  var callableTargets: Int
  var nativeToolSummary: (total: Int, available: Int)
  var screenObservationAllowed: Bool
  var executionPaused: Bool
  var currentApp: String
  var memorySnapshot: AgentMemorySnapshot
  var knowledgeStats: AgentKnowledgeStats
  var recentTaskCount: Int = 0
  var permissionMode: AgentPermissionMode = .askBeforeAction
  var highRiskGuard: Bool = true
  var memoryCapture: Bool = true
  var onCyclePermissionMode: () -> Void = {}
  var onToggleHighRiskGuard: () -> Void = {}
  var onToggleMemoryCapture: () -> Void = {}
  var onToggleExecutionPaused: () -> Void = {}
  var onOpenRecentTasks: () -> Void = {}
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 9) {
        Image(systemName: executionPaused ? "pause.circle" : "checkmark.seal")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(executionPaused ? .orange : .signalASIAccent)
          .frame(width: 24, height: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(t("signalasi.agent.readiness.title", "Agent readiness"))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.signalASITextPrimary)
          Text(readinessSubtitle)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        Text(executionPaused
          ? t("on_device_agent_status_paused", "Paused")
          : t("on_device_agent_status_running", "Ready"))
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(executionPaused ? .orange : .signalASIAccent)
          .lineLimit(1)
      }

      HStack(spacing: 8) {
        metric(
          title: t("signalasi.agent.readiness.targets", "Targets"),
          value: "\(callableTargets)",
          systemImage: "person.2"
        )
        metric(
          title: t("cc_metric_native_tools", "Native tools"),
          value: "\(nativeToolSummary.available)/\(nativeToolSummary.total)",
          systemImage: "wrench.and.screwdriver"
        )
      }

      HStack(spacing: 8) {
        controlButton(
          title: String(
            format: t("agent_safety_permission_mode_value", "Mode: %@"),
            t(permissionMode.displayTitle, permissionMode.displayTitle)
          ),
          systemImage: "checklist",
          tint: .signalASITextPrimary,
          action: onCyclePermissionMode
        )
        controlButton(
          title: String(
            format: t("agent_safety_high_risk_guard_value", "High-risk Guard: %@"),
            onOff(highRiskGuard)
          ),
          systemImage: "shield.lefthalf.filled",
          tint: highRiskGuard ? .signalASIAccent : .orange,
          action: onToggleHighRiskGuard
        )
      }
      HStack(spacing: 8) {
        controlButton(
          title: String(
            format: t("agent_safety_memory_capture_value", "Memory: %@"),
            onOff(memoryCapture)
          ),
          systemImage: "brain",
          tint: memoryCapture ? .signalASIAccent : .orange,
          action: onToggleMemoryCapture
        )
        controlButton(
          title: String(
            format: t("agent_safety_execution_value", "Execution: %@"),
            executionPaused
              ? t("signalasi.status.paused", "Paused")
              : t("common_on", "On")
          ),
          systemImage: executionPaused ? "pause.circle" : "play.circle",
          tint: executionPaused ? .orange : .signalASIAccent,
          action: onToggleExecutionPaused
        )
      }

      VStack(spacing: 0) {
        infoValueRow(
          String(
            format: t("agent_current_app_value", "Current app: %@"),
            currentApp.ifBlank(t("agent_current_app_unknown", "Unknown"))
          )
        )
        separator
        NavigationLink(destination: SignalASIAgentMemoryView()) {
          infoNavigationRow(
            String(
              format: t("agent_memory_value", "Memory: %d / conflicts: %d"),
              memorySnapshot.activeCount,
              memorySnapshot.conflicts.count
            ),
            systemImage: "brain"
          )
        }
        .buttonStyle(.plain)
        separator
        NavigationLink(destination: SignalASIAgentKnowledgeView()) {
          infoNavigationRow(
            String(
              format: t("agent_knowledge_value", "Knowledge: %d items / %d sources / %d hits"),
              knowledgeStats.itemCount,
              knowledgeStats.sourceCount,
              0
            ),
            systemImage: "books.vertical"
          )
        }
        .buttonStyle(.plain)
        separator
        Button(action: onOpenRecentTasks) {
          infoNavigationRow(
            String(
              format: t("signalasi.agent.recent_tasks_value", "Recent tasks: %d"),
              recentTaskCount
            ),
            systemImage: "clock.arrow.circlepath"
          )
        }
        .buttonStyle(.plain)
      }
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      if !screenObservationAllowed {
        NavigationLink(destination: OnDeviceAgentPermissionsView()) {
          HStack(spacing: 8) {
            Image(systemName: "eye.slash")
              .foregroundColor(.orange)
            Text(t("agent_accessibility_status_disabled", "Screen access: needs permission"))
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.signalASITextPrimary)
            Spacer(minLength: 4)
            Text(t("signalasi.common.manage", "Manage"))
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.orange)
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.orange)
          }
          .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var readinessSubtitle: String {
    if executionPaused {
      return t("agent_status_paused_subtitle", "Execution is paused. Resume when you are ready.")
    }
    return String(
      format: t("agent_running_tasks_targets_value", "Running tasks: %d / targets: %d"),
      runningTasks,
      callableTargets
    )
  }

  private func metric(title: String, value: String, systemImage: String) -> some View {
    HStack(spacing: 7) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASIAccent)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 10))
          .foregroundColor(.signalASITextSecondary)
          .lineLimit(1)
        Text(value)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 9)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func controlButton(
    title: String,
    systemImage: String,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .semibold))
        Text(title)
          .font(.system(size: 11, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.58)
      }
      .foregroundColor(tint)
      .frame(maxWidth: .infinity, minHeight: 40)
      .padding(.horizontal, 6)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }

  private func onOff(_ value: Bool) -> String {
    value ? t("common_on", "On") : t("common_off", "Off")
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.signalASISeparator)
      .frame(height: 0.5)
      .padding(.leading, 14)
  }

  private func infoValueRow(_ value: String) -> some View {
    Text(value)
      .font(.system(size: 13))
      .foregroundColor(.signalASITextPrimary)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
      .padding(.horizontal, 14)
  }

  private func infoNavigationRow(_ value: String, systemImage: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.signalASIAccent)
        .frame(width: 18)
      Text(value)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.signalASITextSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
    .padding(.horizontal, 14)
  }
}

struct SignalASIAgentHomeSafetyStrip: View {
  var permissionMode: AgentPermissionMode
  var highRiskGuard: Bool
  var memoryCapture: Bool
  var executionPaused: Bool
  var onCyclePermissionMode: () -> Void
  var onToggleHighRiskGuard: () -> Void
  var onToggleMemoryCapture: () -> Void
  var onToggleExecutionPaused: () -> Void
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASIAccent)
        Text(t("signalasi.agent.readiness.title", "Agent controls"))
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.signalASITextPrimary)
        Spacer(minLength: 0)
      }
      HStack(spacing: 7) {
        controlButton(
          title: String(
            format: t("agent_safety_permission_mode_value", "Mode: %@"),
            t(permissionMode.displayTitle, permissionMode.displayTitle)
          ),
          systemImage: "checklist",
          tint: .signalASITextPrimary,
          action: onCyclePermissionMode
        )
        controlButton(
          title: String(
            format: t("agent_safety_high_risk_guard_value", "High-risk Guard: %@"),
            onOff(highRiskGuard)
          ),
          systemImage: "shield.lefthalf.filled",
          tint: highRiskGuard ? .signalASIAccent : .orange,
          action: onToggleHighRiskGuard
        )
      }
      HStack(spacing: 7) {
        controlButton(
          title: String(
            format: t("agent_safety_memory_capture_value", "Memory: %@"),
            onOff(memoryCapture)
          ),
          systemImage: "brain",
          tint: memoryCapture ? .signalASIAccent : .orange,
          action: onToggleMemoryCapture
        )
        controlButton(
          title: String(
            format: t("agent_safety_execution_value", "Execution: %@"),
            executionPaused
              ? t("signalasi.status.paused", "Paused")
              : t("common_on", "On")
          ),
          systemImage: executionPaused ? "pause.circle" : "play.circle",
          tint: executionPaused ? .orange : .signalASIAccent,
          action: onToggleExecutionPaused
        )
      }
    }
    .padding(9)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  private func controlButton(
    title: String,
    systemImage: String,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: systemImage)
          .font(.system(size: 11, weight: .semibold))
        Text(title)
          .font(.system(size: 10.5, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.55)
      }
      .foregroundColor(tint)
      .frame(maxWidth: .infinity, minHeight: 36)
      .padding(.horizontal, 5)
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }

  private func onOff(_ value: Bool) -> String {
    value ? t("common_on", "On") : t("common_off", "Off")
  }
}
