import SwiftUI

struct GalaxySSIAgentHomeReadinessView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var runningTasks: Int
  var callableTargets: Int
  var nativeToolSummary: (total: Int, available: Int)
  var nativeTools: [AgentNativeToolDescriptor]
  var screenObservationAllowed: Bool
  var executionPaused: Bool
  var currentApp: String
  var memorySnapshot: AgentMemorySnapshot
  var knowledgeStats: AgentKnowledgeStats
  var knowledgeHitCount: Int
  var screen: AgentScreenContext
  var screenSections: [GalaxySSIAgentScreenDetailSection]
  var recentTaskCount: Int = 0
  var recentTasks: [AgentTaskRecord] = []
  var permissionMode: AgentPermissionMode = .askBeforeAction
  var highRiskGuard: Bool = true
  var memoryCapture: Bool = true
  var taskExecutionMode: AgentTaskExecutionMode = .autoComplete
  var onCyclePermissionMode: () -> Void = {}
  var onToggleHighRiskGuard: () -> Void = {}
  var onToggleMemoryCapture: () -> Void = {}
  var onCycleTaskExecutionMode: () -> Void = {}
  var onToggleExecutionPaused: () -> Void = {}
  var onOpenRecentTasks: () -> Void = {}
  var onOpenRecentTask: (AgentTaskRecord) -> Void = { _ in }
  var onTaskAction: (AgentTaskCenterAction, AgentTaskRecord) -> Void = { _, _ in }
  var onModelSelectionChanged: () -> Void = {}
  var routeTitle: String = ""
  var routeSubtitle: String = ""
  var routeStatus: String = ""
  var routeReady: Bool = true
  var onOpenRouteSelection: () -> Void = {}
  var onScreenCommand: (String) -> Void = { _ in }
  var t: (String, String) -> String
  var onRefreshScreenContext: () -> Void = {}

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 9) {
        Image(systemName: executionPaused ? "pause.circle" : "checkmark.seal")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(executionPaused ? .orange : .galaxySSIAccent)
          .frame(width: 24, height: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(t("galaxyssi.agent.readiness.title", "Agent readiness"))
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(readinessSubtitle)
            .font(.system(size: 11))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
        }
        Spacer(minLength: 8)
        Text(executionPaused
          ? t("on_device_agent_status_paused", "Paused")
          : t("on_device_agent_status_running", "Ready"))
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(executionPaused ? .orange : .galaxySSIAccent)
          .lineLimit(1)
      }

      readinessMetrics

      GalaxySSIAgentHomeRouteSummaryView(
        title: t("galaxyssi.agent.route.current", "Current route"),
        route: routeTitle.ifBlank(t("galaxyssi.agent.model_selection.automatic", "Automatic")),
        subtitle: routeSubtitle,
        status: routeStatus,
        ready: routeReady,
        onTap: onOpenRouteSelection
      )

      GalaxySSIAgentHomePhoneStatusView(t: t)

      GalaxySSIAgentHomeToolboxView(
        tools: nativeTools,
        t: t,
        onCommand: onScreenCommand
      )

      safetyControls

      Text(t("agent_section_info", "Info"))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.galaxySSITextPrimary)
        .padding(.top, 2)

      VStack(spacing: 0) {
        infoValueRow(
          String(
            format: t("agent_current_app_value", "Current app: %@"),
            currentApp.ifBlank(t("agent_current_app_unknown", "Unknown"))
          )
        )
        separator
        infoValueRow(
          String(
            format: t("agent_callable_targets_value", "Callable targets: %d"),
            callableTargets
          )
        )
        separator
        infoValueRow(
          String(
            format: t("agent_running_tasks_value", "Running tasks: %d"),
            runningTasks
          )
        )
        separator
        NavigationLink(destination: GalaxySSIAgentMemoryView()) {
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
        NavigationLink(destination: GalaxySSIAgentKnowledgeView()) {
          infoNavigationRow(
            String(
              format: t("agent_knowledge_value", "Knowledge: %d items / %d sources / %d hits"),
              knowledgeStats.itemCount,
              knowledgeStats.sourceCount,
              knowledgeHitCount
            ),
            systemImage: "books.vertical"
          )
        }
        .buttonStyle(.plain)
        separator
        NavigationLink(
          destination: GalaxySSIAgentScreenContextDetailView(
              screen: screen,
              sections: screenSections,
              onCommand: onScreenCommand,
              t: t,
              onRefresh: onRefreshScreenContext
          )
        ) {
          infoNavigationRow(
            String(
              format: t("agent_screen_context_value", "Screen: %d text / %d actions / %d fields"),
              max(screen.visibleTextCount, screen.visibleTexts.count),
              screen.clickableNodeCount,
              screen.inputFieldCount
            ),
            systemImage: "rectangle.on.rectangle"
          )
        }
        .buttonStyle(.plain)
        separator
        Button(action: onOpenRecentTasks) {
          infoNavigationRow(
            String(
              format: t("galaxyssi.agent.recent_tasks_value", "Recent tasks: %d"),
              recentTaskCount
            ),
            systemImage: "clock.arrow.circlepath"
          )
        }
        .buttonStyle(.plain)
        if recentTasks.isEmpty {
          separator
          infoValueRow(t("agent_recent_empty", "No recent Agent tasks yet"))
        } else {
          ForEach(Array(recentTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
            separator
            HStack(spacing: 0) {
              Button(action: { onOpenRecentTask(task) }) {
                recentTaskRow(task, index: index)
                  .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
              }
              .buttonStyle(.plain)
              Menu {
                ForEach(AgentTaskCenterPolicy.actions(task)) { action in
                  Button(role: action == .delete ? .destructive : nil) {
                    onTaskAction(action, task)
                  } label: {
                    Label(
                      AgentTaskCenterActionPresentation.title(action, t: t),
                      systemImage: AgentTaskCenterActionPresentation.icon(action)
                    )
                  }
                }
              } label: {
                Image(systemName: "ellipsis.circle")
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundColor(.galaxySSITextSecondary)
                  .frame(width: 42, height: 42)
              }
              .accessibilityLabel(Text(t("galaxyssi.agent_task_center.actions", "Task actions")))
            }
          }
        }
      }
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      if !screenObservationAllowed {
        NavigationLink(destination: OnDeviceAgentPermissionsView()) {
          HStack(spacing: 8) {
            Image(systemName: "eye.slash")
              .foregroundColor(.orange)
            Text(t("agent_accessibility_status_disabled", "Screen access: needs permission"))
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
            Spacer(minLength: 4)
            Text(t("galaxyssi.common.manage", "Manage"))
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
    .background(Color.galaxySSIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
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

  @ViewBuilder
  private var readinessMetrics: some View {
    if usesAccessibilityDynamicType {
      VStack(spacing: 8) {
        targetMetric
        nativeToolMetric
      }
    } else {
      HStack(spacing: 8) {
        targetMetric
        nativeToolMetric
      }
    }
  }

  private var targetMetric: some View {
    NavigationLink(
      destination: GalaxySSIAgentModelSelectionView(
        onSelectionChanged: onModelSelectionChanged
      )
    ) {
      metric(
        title: t("galaxyssi.agent.readiness.targets", "Targets"),
        value: "\(callableTargets)",
        systemImage: "person.2"
      )
    }
    .buttonStyle(.plain)
  }

  private var nativeToolMetric: some View {
    NavigationLink(destination: GalaxySSINativeToolCatalogView()) {
      metric(
        title: t("cc_metric_native_tools", "Native tools"),
        value: "\(nativeToolSummary.available)/\(nativeToolSummary.total)",
        systemImage: "wrench.and.screwdriver"
      )
    }
    .buttonStyle(.plain)
  }

  private func metric(title: String, value: String, systemImage: String) -> some View {
    HStack(spacing: 7) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.galaxySSIAccent)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 10))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        Text(value)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .padding(.horizontal, 9)
    .frame(
      maxWidth: .infinity,
      minHeight: usesAccessibilityDynamicType ? 52 : 44,
      alignment: .leading
    )
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var safetyControls: some View {
    if usesAccessibilityDynamicType {
      VStack(spacing: 8) {
        permissionModeControl
        highRiskGuardControl
        memoryCaptureControl
        executionControl
        taskExecutionModeControl
      }
    } else {
      HStack(spacing: 8) {
        permissionModeControl
        highRiskGuardControl
      }
      HStack(spacing: 8) {
        memoryCaptureControl
        executionControl
      }
      taskExecutionModeControl
    }
  }

  private var permissionModeControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_permission_mode_value", "Mode: %@"),
        t(permissionMode.displayTitle, permissionMode.displayTitle)
      ),
      systemImage: "checklist",
      tint: .galaxySSITextPrimary,
      action: onCyclePermissionMode
    )
  }

  private var highRiskGuardControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_high_risk_guard_value", "High-risk Guard: %@"),
        onOff(highRiskGuard)
      ),
      systemImage: "shield.lefthalf.filled",
      tint: highRiskGuard ? .galaxySSIAccent : .orange,
      action: onToggleHighRiskGuard
    )
  }

  private var memoryCaptureControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_memory_capture_value", "Memory: %@"),
        onOff(memoryCapture)
      ),
      systemImage: "brain",
      tint: memoryCapture ? .galaxySSIAccent : .orange,
      action: onToggleMemoryCapture
    )
  }

  private var executionControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_execution_value", "Execution: %@"),
        executionPaused
          ? t("galaxyssi.status.paused", "Paused")
          : t("common_on", "On")
      ),
      systemImage: executionPaused ? "pause.circle" : "play.circle",
      tint: executionPaused ? .orange : .galaxySSIAccent,
      action: onToggleExecutionPaused
    )
  }

  private var taskExecutionModeControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_task_execution_value", "Task execution: %@"),
        t(taskExecutionMode.displayTitle, taskExecutionMode.displayTitle)
      ),
      systemImage: taskExecutionMode == .planOnly
        ? "list.bullet.rectangle"
        : "play.rectangle",
      tint: taskExecutionMode == .planOnly ? .orange : .galaxySSIAccent,
      action: onCycleTaskExecutionMode
    )
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
          .font(.system(size: usesAccessibilityDynamicType ? 13 : 11, weight: .bold))
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
          .minimumScaleFactor(usesAccessibilityDynamicType ? 0.82 : 0.58)
          .multilineTextAlignment(.leading)
      }
      .foregroundColor(tint)
      .frame(maxWidth: .infinity, minHeight: usesAccessibilityDynamicType ? 48 : 40, alignment: .leading)
      .padding(.horizontal, 6)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }

  private func onOff(_ value: Bool) -> String {
    value ? t("common_on", "On") : t("common_off", "Off")
  }

  private var usesAccessibilityDynamicType: Bool {
    switch dynamicTypeSize {
    case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
      return true
    default:
      return false
    }
  }

  private var separator: some View {
    Rectangle()
      .fill(Color.galaxySSISeparator)
      .frame(height: 0.5)
      .padding(.leading, 14)
  }

  private func infoValueRow(_ value: String) -> some View {
    Text(value)
      .font(.system(size: 13))
      .foregroundColor(.galaxySSITextPrimary)
      .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
      .minimumScaleFactor(usesAccessibilityDynamicType ? 1 : 0.75)
      .frame(
        maxWidth: .infinity,
        minHeight: usesAccessibilityDynamicType ? 54 : 42,
        alignment: .leading
      )
      .padding(.horizontal, 14)
  }

  private func infoNavigationRow(_ value: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.galaxySSIAccent)
        .frame(width: 18)
        .padding(.top, usesAccessibilityDynamicType ? 2 : 0)
      Text(value)
        .font(.system(size: 13))
        .foregroundColor(.galaxySSITextPrimary)
        .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        .minimumScaleFactor(usesAccessibilityDynamicType ? 1 : 0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 8)
      Image(systemName: "chevron.right")
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.galaxySSITextSecondary)
    }
    .frame(
      maxWidth: .infinity,
      minHeight: usesAccessibilityDynamicType ? 54 : 42,
      alignment: .leading
    )
    .padding(.horizontal, 14)
  }

  private func recentTaskRow(_ task: AgentTaskRecord, index: Int) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Text("\(index + 1)")
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 28, height: 28)
        .background(recentTaskTint(task.phase))
        .clipShape(Circle())
        .padding(.top, usesAccessibilityDynamicType ? 2 : 0)
      VStack(alignment: .leading, spacing: 2) {
        Text(task.goal.ifBlank(t("galaxyssi.agent_tasks.title", "Agent task")))
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        Text(recentTaskSubtitle(task))
          .font(.system(size: 10.5))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 6)
      Text(recentTaskStatus(task.phase))
        .font(.system(size: 10.5, weight: .bold))
        .foregroundColor(recentTaskTint(task.phase))
        .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 14)
  }

  private func recentTaskStatus(_ phase: AgentPhase) -> String {
    switch phase {
    case .observing, .planning, .executing, .verifying:
      return t("agent_task_status_running", "Running")
    case .waitingConfirmation:
      return t("agent_task_status_waiting_approval", "Waiting for approval")
    case .waitingResponse:
      return t("agent_task_status_waiting_input", "Waiting for input")
    case .paused:
      return t("agent_recent_status_paused", "Paused")
    case .blocked:
      return t("agent_recent_status_blocked", "Blocked")
    case .completed:
      return t("agent_task_status_completed", "Completed")
    case .failed:
      return t("agent_task_status_failed", "Failed")
    case .cancelled:
      return t("agent_task_status_cancelled", "Cancelled")
    }
  }

  private func recentTaskTint(_ phase: AgentPhase) -> Color {
    switch phase {
    case .blocked, .failed:
      return .red
    case .cancelled, .paused:
      return .galaxySSITextSecondary
    case .completed,
      .waitingConfirmation,
      .observing,
      .planning,
      .executing,
      .verifying,
      .waitingResponse:
      return .galaxySSIAccent
    }
  }

  private func recentTaskSubtitle(_ task: AgentTaskRecord) -> String {
    let execution = AgentExecutionPresentationPolicy.location(record: task)
    let summary = [
      executionLocationLabel(execution.locationKind),
      executionRuntimeLabel(execution.runtimeKind),
      execution.locationName,
      task.targetTitle,
      riskLabel(task.risk)
    ]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    return summary.replacingOccurrences(of: " \u{8DEF} ", with: " \u{00B7} ")
  }

  private func executionLocationLabel(_ kind: AgentExecutionLocationKind) -> String {
    switch kind {
    case .phone:
      return t("galaxyssi.agent_execution.location.phone", "Phone")
    case .desktop:
      return t("galaxyssi.agent_execution.location.desktop", "Desktop")
    case .cloud:
      return t("galaxyssi.agent_execution.location.cloud", "Cloud")
    case .connectedDevice:
      return t("galaxyssi.agent_execution.location.device", "Connected device")
    case .unknown:
      return ""
    }
  }

  private func executionRuntimeLabel(_ kind: AgentExecutionRuntimeKind) -> String {
    switch kind {
    case .phoneNative:
      return t("galaxyssi.agent_execution.runtime.phone_native", "Phone native")
    case .phoneLinux:
      return t("galaxyssi.agent_execution.runtime.phone_linux", "Phone Linux")
    case .phoneLocalModel:
      return t("galaxyssi.agent_execution.runtime.local_model", "Local model")
    case .phoneCloudAPI:
      return t("galaxyssi.agent_execution.runtime.cloud_api", "Cloud API")
    case .desktopAgent:
      return t("galaxyssi.agent_execution.runtime.desktop_agent", "Desktop Agent")
    case .desktopTool:
      return t("galaxyssi.agent_execution.runtime.desktop_tool", "Desktop tool")
    case .connectedDevice:
      return t("galaxyssi.agent_execution.runtime.connected_device", "Connected device")
    case .knowledge:
      return t("galaxyssi.agent_execution.runtime.knowledge", "Knowledge")
    case .unknown:
      return ""
    }
  }

  private func riskLabel(_ risk: AgentRisk) -> String {
    switch risk {
    case .low:
      return t("galaxyssi.agent_risk.low", "low risk")
    case .medium:
      return t("galaxyssi.agent_risk.medium", "medium risk")
    case .high:
      return t("galaxyssi.agent_risk.high", "high risk")
    case .blocked:
      return t("galaxyssi.agent_risk.blocked", "blocked")
    }
  }
}

struct GalaxySSIAgentHomeRouteSummaryView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var title: String
  var route: String
  var subtitle: String
  var status: String
  var ready: Bool
  var onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(ready ? .galaxySSIAccent : .orange)
          .frame(width: 24, height: 24)
          .padding(.top, usesAccessibilityDynamicType ? 2 : 0)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(1)
          Text(route)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .minimumScaleFactor(usesAccessibilityDynamicType ? 1 : 0.78)
          if !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: 10.5))
              .foregroundColor(.galaxySSITextSecondary)
              .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 6)
        VStack(alignment: .trailing, spacing: 3) {
          Text(status)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(ready ? .galaxySSIAccent : .orange)
            .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            .multilineTextAlignment(.trailing)
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.galaxySSITextSecondary)
        }
      }
      .padding(.horizontal, 12)
      .frame(
        maxWidth: .infinity,
        minHeight: usesAccessibilityDynamicType ? 84 : 64,
        alignment: .leading
      )
      .background(Color.galaxySSISurface)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke((ready ? Color.galaxySSIAccent : Color.orange).opacity(0.55), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("\(title): \(route), \(status)"))
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }
}

struct GalaxySSIAgentHomeSafetyStrip: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var permissionMode: AgentPermissionMode
  var highRiskGuard: Bool
  var memoryCapture: Bool
  var taskExecutionMode: AgentTaskExecutionMode
  var executionPaused: Bool
  var onCyclePermissionMode: () -> Void
  var onToggleHighRiskGuard: () -> Void
  var onToggleMemoryCapture: () -> Void
  var onCycleTaskExecutionMode: () -> Void
  var onToggleExecutionPaused: () -> Void
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 7) {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSIAccent)
        Text(t("galaxyssi.agent.readiness.title", "Agent controls"))
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
        Spacer(minLength: 0)
      }
      controls
    }
    .padding(9)
    .background(Color.galaxySSIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var controls: some View {
    if usesAccessibilityDynamicType {
      VStack(spacing: 7) {
        permissionModeControl
        highRiskGuardControl
        memoryCaptureControl
        executionControl
        taskExecutionModeControl
      }
    } else {
      HStack(spacing: 7) {
        permissionModeControl
        highRiskGuardControl
      }
      HStack(spacing: 7) {
        memoryCaptureControl
        executionControl
      }
      taskExecutionModeControl
    }
  }

  private var permissionModeControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_permission_mode_value", "Mode: %@"),
        t(permissionMode.displayTitle, permissionMode.displayTitle)
      ),
      systemImage: "checklist",
      tint: .galaxySSITextPrimary,
      action: onCyclePermissionMode
    )
  }

  private var highRiskGuardControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_high_risk_guard_value", "High-risk Guard: %@"),
        onOff(highRiskGuard)
      ),
      systemImage: "shield.lefthalf.filled",
      tint: highRiskGuard ? .galaxySSIAccent : .orange,
      action: onToggleHighRiskGuard
    )
  }

  private var memoryCaptureControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_memory_capture_value", "Memory: %@"),
        onOff(memoryCapture)
      ),
      systemImage: "brain",
      tint: memoryCapture ? .galaxySSIAccent : .orange,
      action: onToggleMemoryCapture
    )
  }

  private var executionControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_execution_value", "Execution: %@"),
        executionPaused
          ? t("galaxyssi.status.paused", "Paused")
          : t("common_on", "On")
      ),
      systemImage: executionPaused ? "pause.circle" : "play.circle",
      tint: executionPaused ? .orange : .galaxySSIAccent,
      action: onToggleExecutionPaused
    )
  }

  private var taskExecutionModeControl: some View {
    controlButton(
      title: String(
        format: t("agent_safety_task_execution_value", "Task execution: %@"),
        t(taskExecutionMode.displayTitle, taskExecutionMode.displayTitle)
      ),
      systemImage: taskExecutionMode == .planOnly
        ? "list.bullet.rectangle"
        : "play.rectangle",
      tint: taskExecutionMode == .planOnly ? .orange : .galaxySSIAccent,
      action: onCycleTaskExecutionMode
    )
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
          .font(.system(size: usesAccessibilityDynamicType ? 13 : 10.5, weight: .bold))
          .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
          .minimumScaleFactor(usesAccessibilityDynamicType ? 0.82 : 0.55)
          .multilineTextAlignment(.leading)
      }
      .foregroundColor(tint)
      .frame(maxWidth: .infinity, minHeight: usesAccessibilityDynamicType ? 48 : 36, alignment: .leading)
      .padding(.horizontal, 5)
      .background(Color.galaxySSISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }

  private func onOff(_ value: Bool) -> String {
    value ? t("common_on", "On") : t("common_off", "Off")
  }

  private var usesAccessibilityDynamicType: Bool {
    switch dynamicTypeSize {
    case .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5:
      return true
    default:
      return false
    }
  }
}
