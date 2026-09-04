import Foundation
import SwiftUI

struct GalaxySSIAgentRuntimePanelView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var safetySettings: AgentSafetySettings
  var taskExecutionMode: AgentTaskExecutionMode
  var modelPlannerSettings: AgentModelPlannerSettings
  var taskBudget: AgentTaskBudget
  var callableTargets: Int
  var currentGoal: String
  var currentApp: String
  var memorySnapshot: AgentMemorySnapshot
  var knowledgeStats: AgentKnowledgeStats
  var knowledgeHitCount: Int
  var recentTasks: [AgentTaskRecord]
  var nativeTools: [AgentNativeToolDescriptor]
  var auditRecords: [AgentNativeToolAuditRecord]
  var onCyclePermissionMode: () -> Void
  var onCycleTaskExecutionMode: () -> Void
  var onToggleHighRiskGuard: () -> Void
  var onToggleMemoryCapture: () -> Void
  var onToggleExecutionPaused: () -> Void
  var onUpdatePendingAction: (String, String, String, String) -> AgentPendingActionEditResult
  var onMovePendingAction: (String, String, Int) -> AgentPendingActionEditResult
  var onRemovePendingAction: (String, String) -> AgentPendingActionEditResult
  var onTaskAction: (AgentTaskCenterAction, AgentTaskRecord) -> Void
  var onOpenRecentTasks: () -> Void
  var t: (String, String) -> String

  @State private var expandedSectionIds: Set<String> = ["info", "requirements", "recent_tasks"]
  @State private var selectedTask: AgentTaskRecord?
  @State private var selectedAction: GalaxySSIAgentRuntimeActionSelection?
  @State private var deletingTask: AgentTaskRecord?
  @State private var memoryViewActive = false
  @State private var knowledgeViewActive = false

  private var activeTasks: [AgentTaskRecord] {
    recentTasks.filter { task in
      switch task.phase {
      case .observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused:
        return true
      case .cancelled, .blocked, .completed, .failed:
        return false
      }
    }
  }

  private var availableTools: [AgentNativeToolDescriptor] {
    nativeTools
      .filter { effectiveToolStatus($0) == .available }
      .sorted { lhs, rhs in
        if lhs.risk != rhs.risk {
          return lhs.risk.weight < rhs.risk.weight
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
      }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      statusHeader
      controlStrip
      runtimeSection(
        id: "info",
        title: t("agent_section_info", "Info"),
        subtitle: String(
          format: t("galaxyssi.agent_runtime.info_summary", "%d targets / %d running tasks"),
          callableTargets,
          activeTasks.count
        ),
        systemImage: "info.circle",
        rows: infoRows,
        emptyTitle: t("agent_info_empty", "No Agent runtime information")
      )
      runtimeSection(
        id: "toolbox",
        title: t("agent_section_toolbox", "Toolbox"),
        subtitle: String(format: t("galaxyssi.agent_runtime.toolbox_summary", "%d local tools"), availableTools.count),
        systemImage: "wrench.and.screwdriver",
        rows: toolboxRows,
        emptyTitle: t("agent_toolbox_empty", "No local tools are available")
      )
      runtimeSection(
        id: "action_queue",
        title: t("agent_section_action_queue", "Action Queue"),
        subtitle: String(format: t("galaxyssi.agent_runtime.action_queue_summary", "%d active"), actionQueueItemCount),
        systemImage: "list.bullet.rectangle",
        rows: actionQueueRows,
        emptyTitle: t("agent_action_queue_empty", "No active Agent plan")
      )
      runtimeSection(
        id: "requirements",
        title: t("agent_section_requirements", "Requirements"),
        subtitle: requirementsSubtitle,
        systemImage: "checklist",
        rows: requirementRows,
        emptyTitle: t("agent_requirements_empty", "No active execution requirements")
      )
      runtimeSection(
        id: "plan_context",
        title: t("agent_section_plan_context", "Plan Context"),
        subtitle: plannerSubtitle,
        systemImage: "point.topleft.down.curvedto.point.bottomright.up",
        rows: planContextRows,
        emptyTitle: t("agent_plan_context_empty", "No active plan context")
      )
      runtimeSection(
        id: "verification",
        title: t("agent_section_verification", "Verification"),
        subtitle: String(format: t("galaxyssi.agent_runtime.verification_summary", "%d evidence rows"), verificationRows.count),
        systemImage: "checkmark.seal",
        rows: verificationRows,
        emptyTitle: t("agent_verification_empty", "No execution evidence yet")
      )
      runtimeSection(
        id: "recent_tasks",
        title: t("agent_section_recent_tasks", "Recent Tasks"),
        subtitle: String(format: t("galaxyssi.agent_runtime.recent_summary", "%d tasks"), recentTasks.count),
        systemImage: "clock.arrow.circlepath",
        rows: recentTaskRows,
        emptyTitle: t("agent_recent_empty", "No recent Agent tasks yet"),
        action: onOpenRecentTasks,
        actionTitle: t("galaxyssi.agent_tasks.title", "Tasks")
      )
      runtimeSection(
        id: "audit_trail",
        title: t("agent_section_audit_trail", "Audit Trail"),
        subtitle: String(format: t("galaxyssi.agent_runtime.audit_summary", "%d events"), auditEventCount),
        systemImage: "list.clipboard",
        rows: auditRows,
        emptyTitle: t("agent_audit_empty", "No Agent audit events yet")
      )
    }
    .sheet(item: $selectedTask) { task in
      GalaxySSIAgentRuntimeTaskDetailSheet(
        task: task,
        t: t,
        taskActions: AgentTaskCenterPolicy.actions(task),
        onAction: { action in
          if action == .delete {
            selectedTask = nil
            deletingTask = task
          } else {
            onTaskAction(action, task)
          }
        }
      )
    }
    .alert(item: $deletingTask) { task in
      Alert(
        title: Text(t("galaxyssi.agent_task_center.delete_title", "Delete task?")),
        message: Text(
          String(
            format: t(
              "galaxyssi.agent_task_center.delete_message",
              "Delete the task record for \"%@\"? The conversation will remain available."
            ),
            task.goal
          )
        ),
        primaryButton: .destructive(Text(t("galaxyssi.common.delete", "Delete"))) {
          onTaskAction(.delete, task)
        },
        secondaryButton: .cancel(Text(t("galaxyssi.common.cancel", "Cancel")))
      )
    }
    .sheet(item: $selectedAction) { selection in
      GalaxySSIAgentRuntimeActionEditorSheet(
        task: selection.task,
        action: selection.action,
        t: t,
        onUpdate: onUpdatePendingAction,
        onMove: onMovePendingAction,
        onRemove: onRemovePendingAction
      )
    }
    .background(
      NavigationLink(
        destination: GalaxySSIAgentMemoryView(),
        isActive: $memoryViewActive
      ) {
        EmptyView()
      }
      .hidden()
    )
    .background(
      NavigationLink(
        destination: GalaxySSIAgentKnowledgeView(),
        isActive: $knowledgeViewActive
      ) {
        EmptyView()
      }
      .hidden()
    )
  }

  @ViewBuilder
  private var statusHeader: some View {
    if !safetySettings.screenObservationAllowed {
      NavigationLink(destination: OnDeviceAgentPermissionsView()) {
        statusHeaderContent
      }
      .buttonStyle(.plain)
    } else {
      statusHeaderContent
    }
  }

  private var statusHeaderContent: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: statusIcon)
        .font(.system(size: 20, weight: .semibold))
        .foregroundColor(statusTint)
        .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 3) {
        Text(statusTitle)
          .font(.system(size: 14, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        Text(statusSubtitle)
          .font(.system(size: 11))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(statusBadge)
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(statusTint)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(minHeight: 26)
        .background(statusTint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var controlStrip: some View {
    Group {
      if usesAccessibilityDynamicType {
        VStack(spacing: 8) {
          permissionModeControl
          highRiskGuardControl
          memoryCaptureControl
          taskExecutionModeControl
          executionControl
        }
      } else {
        standardControlStrip
      }
    }
  }

  private var standardControlStrip: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        permissionModeControl
        highRiskGuardControl
        memoryCaptureControl
      }
      taskExecutionModeControl
      executionControl
    }
  }

  private var permissionModeControl: some View {
    runtimeControlButton(
      title: String(
        format: t("agent_safety_permission_mode_value", "Mode: %@"),
        permissionModeTitle(safetySettings.permissionMode)
      ),
      tint: .galaxySSITextPrimary,
      action: onCyclePermissionMode
    )
  }

  private var highRiskGuardControl: some View {
    runtimeControlButton(
      title: String(format: t("agent_safety_high_risk_guard_value", "High-risk Guard: %@"), onOff(safetySettings.highRiskGuard)),
      tint: safetySettings.highRiskGuard ? .galaxySSIAccent : .orange,
      action: onToggleHighRiskGuard
    )
  }

  private var memoryCaptureControl: some View {
    runtimeControlButton(
      title: String(format: t("agent_safety_memory_capture_value", "Memory: %@"), onOff(safetySettings.memoryCapture)),
      tint: safetySettings.memoryCapture ? .galaxySSIAccent : .orange,
      action: onToggleMemoryCapture
    )
  }

  private var taskExecutionModeControl: some View {
    runtimeControlButton(
      title: String(
        format: t("agent_safety_task_execution_value", "Task execution: %@"),
        taskExecutionModeTitle(taskExecutionMode)
      ),
      tint: taskExecutionMode == .planOnly ? .orange : .galaxySSIAccent,
      action: onCycleTaskExecutionMode
    )
  }

  private var executionControl: some View {
    runtimeControlButton(
      title: String(
        format: t("agent_safety_execution_value", "Execution: %@"),
        safetySettings.executionPaused
          ? t("galaxyssi.status.paused", "Paused")
          : t("common_on", "On")
      ),
      tint: safetySettings.executionPaused ? .orange : .galaxySSIAccent,
      action: onToggleExecutionPaused
    )
  }

  private func runtimeControlButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: usesAccessibilityDynamicType ? 13 : 12, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        .minimumScaleFactor(usesAccessibilityDynamicType ? 0.82 : 0.6)
        .multilineTextAlignment(.leading)
        .frame(
          maxWidth: .infinity,
          minHeight: usesAccessibilityDynamicType ? 48 : 42,
          alignment: .leading
        )
        .padding(.horizontal, 6)
        .background(Color.galaxySSISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func runtimeSection(
    id: String,
    title: String,
    subtitle: String,
    systemImage: String,
    rows: [GalaxySSIAgentRuntimeRow],
    emptyTitle: String,
    action: (() -> Void)? = nil,
    actionTitle: String = ""
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Button {
          withAnimation(.easeOut(duration: 0.16)) {
            if expandedSectionIds.contains(id) {
              expandedSectionIds.remove(id)
            } else {
              expandedSectionIds.insert(id)
            }
          }
        } label: {
          HStack(spacing: 10) {
            Image(systemName: systemImage)
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.galaxySSIAccent)
              .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.galaxySSITextPrimary)
                .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
              Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.galaxySSITextSecondary)
                .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
            }
            Spacer(minLength: 8)
            Image(systemName: expandedSectionIds.contains(id) ? "chevron.up" : "chevron.down")
              .font(.system(size: 12, weight: .bold))
              .foregroundColor(.galaxySSITextSecondary)
              .frame(width: 28, height: 28)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          Text(
            expandedSectionIds.contains(id)
              ? t("galaxyssi.agent_runtime.collapse", "Collapse")
              : t("galaxyssi.agent_runtime.expand", "Expand")
          )
        )
        .frame(maxWidth: .infinity, alignment: .leading)

        if let action {
          Button(action: action) {
            Image(systemName: "arrow.up.right.square")
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(.galaxySSIAccent)
              .frame(width: 28, height: 28)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(actionTitle))
        }
      }

      if expandedSectionIds.contains(id) {
        if rows.isEmpty {
          runtimeRow(
            GalaxySSIAgentRuntimeRow(
              id: "\(id)-empty",
              title: emptyTitle,
              detail: "",
              badge: "",
              systemImage: "info.circle",
              tint: .galaxySSITextSecondary
            )
          )
        } else {
          ForEach(rows) { row in
            runtimeRow(row)
          }
        }
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

  @ViewBuilder
  private func runtimeRow(_ row: GalaxySSIAgentRuntimeRow) -> some View {
    if let onTap = row.onTap {
      Button(action: onTap) {
        runtimeRowContent(row)
      }
      .buttonStyle(.plain)
    } else {
      runtimeRowContent(row)
    }
  }

  private func runtimeRowContent(_ row: GalaxySSIAgentRuntimeRow) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: row.systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(row.tint)
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text(row.title)
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
        if !row.detail.isEmpty {
          Text(row.detail)
            .font(.system(size: 11))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 8)
      if !row.badge.isEmpty {
        Text(row.badge)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(row.tint)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .padding(.horizontal, 7)
          .frame(minHeight: 24)
          .background(row.tint.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }

  private var toolboxRows: [GalaxySSIAgentRuntimeRow] {
    availableTools.prefix(6).map { tool in
      GalaxySSIAgentRuntimeRow(
        id: "tool-\(tool.id)",
        title: tool.title,
        detail: String(
          format: t("agent_toolbox_meta", "%@ / %@ risk"),
          tool.id,
          nativeRiskText(tool.risk)
        ),
        badge: toolStatusText(effectiveToolStatus(tool)),
        systemImage: toolLocationIcon(tool.location),
        tint: nativeRiskTint(tool.risk)
      )
    }
  }

  private var infoRows: [GalaxySSIAgentRuntimeRow] {
    [
      GalaxySSIAgentRuntimeRow(
        id: "info-current-app",
        title: String(
          format: t("agent_current_app_value", "Current app: %@"),
          currentApp.ifBlank(t("agent_current_app_unknown", "Unknown"))
        ),
        detail: "",
        badge: "",
        systemImage: "app",
        tint: .galaxySSIAccent
      ),
      GalaxySSIAgentRuntimeRow(
        id: "info-callable-targets",
        title: String(
          format: t("agent_callable_targets_value", "Callable targets: %d"),
          callableTargets
        ),
        detail: "",
        badge: "",
        systemImage: "person.2",
        tint: .galaxySSIAccent
      ),
      GalaxySSIAgentRuntimeRow(
        id: "info-running-tasks",
        title: String(
          format: t("agent_running_tasks_value", "Running tasks: %d"),
          activeTasks.count
        ),
        detail: "",
        badge: "",
        systemImage: "bolt.circle",
        tint: .galaxySSIAccent
      ),
      GalaxySSIAgentRuntimeRow(
        id: "info-memory",
        title: String(
          format: t("agent_memory_value", "Memory: %d / conflicts: %d"),
          memorySnapshot.activeCount,
          memorySnapshot.conflicts.count
        ),
        detail: t("agent_runtime.open_memory_detail", "Open Agent memory"),
        badge: "",
        systemImage: "brain",
        tint: .galaxySSIAccent,
        onTap: { memoryViewActive = true }
      ),
      GalaxySSIAgentRuntimeRow(
        id: "info-knowledge",
        title: String(
          format: t("agent_knowledge_value", "Knowledge: %d items / %d sources / %d hits"),
          knowledgeStats.itemCount,
          knowledgeStats.sourceCount,
          knowledgeHitCount
        ),
        detail: t("agent_runtime.open_knowledge_detail", "Open Agent knowledge"),
        badge: "",
        systemImage: "books.vertical",
        tint: .galaxySSIAccent,
        onTap: { knowledgeViewActive = true }
      )
    ]
  }

  private var actionQueueRows: [GalaxySSIAgentRuntimeRow] {
    if !queuedActionEntries.isEmpty {
      return queuedActionEntries.map { entry in
        let action = entry.action
        let target = action.target.ifBlank(entry.task.targetTitle)
          .ifBlank(t("galaxyssi.agent_tasks.target_phone", "GalaxySSI"))
        let kind = action.kind.rawValue
          .lowercased()
          .replacingOccurrences(of: "_", with: " ")
        return GalaxySSIAgentRuntimeRow(
          id: "queue-action-\(action.id)",
          title: action.description.ifBlank(kind),
          detail: actionQueueDetail(action, target: target),
          badge: actionStatusText(action.status),
          systemImage: action.status == .blocked ? "hand.raised" : "arrow.triangle.2.circlepath",
          tint: actionStatusTint(action.status),
          onTap: AgentPlanEditor.isEditablePending(action)
            ? { selectedAction = GalaxySSIAgentRuntimeActionSelection(task: entry.task, action: action) }
            : nil
        )
      }
    }
    return activeTasks.map { task in
      GalaxySSIAgentRuntimeRow(
        id: "queue-\(task.taskId)",
        title: task.goal.ifBlank(statusText(task)),
        detail: String(
          format: t("agent_action_queue_meta", "%@ / %@ risk"),
          task.targetTitle.ifBlank(t("galaxyssi.agent_tasks.target_phone", "GalaxySSI")),
          riskText(task.risk)
        ),
        badge: statusText(task),
        systemImage: task.blocked ? "hand.raised" : "arrow.triangle.2.circlepath",
        tint: statusTint(task)
      )
    }
  }

  private func actionQueueDetail(_ action: AgentAction, target: String) -> String {
    var details = [
      String(
        format: t("agent_action_queue_meta", "%@ / %@ risk"),
        target,
        riskText(action.risk)
      )
    ]
    let dependencyCount = AgentToolCoordination.dependencyIds(action).count
    let outputSourceCount = AgentToolCoordination.outputSourceIds(action).count
    if dependencyCount > 0 || outputSourceCount > 0 {
      details.append(
        String(
          format: t("agent_action_queue_dependencies", "%d dependencies / %d output sources"),
          dependencyCount,
          outputSourceCount
        )
      )
    }
    if !action.result.isBlank {
      details.append(
        String(
          format: t("agent_action_queue_result", "Result: %@"),
          action.result
        )
      )
    }
    return details.joined(separator: " / ")
  }

  private var queuedActionEntries: [(task: AgentTaskRecord, action: AgentAction)] {
    var seen = Set<String>()
    return activeTasks.flatMap { task in
      let actions = task.pendingActions.isEmpty
        ? task.pendingAction.map { [$0] } ?? []
        : task.pendingActions
      return actions.compactMap { action -> (task: AgentTaskRecord, action: AgentAction)? in
        let actionID = action.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actionID.isEmpty, seen.insert(actionID).inserted else { return nil }
        return (task: task, action: action)
      }
    }
  }

  private var actionQueueItemCount: Int {
    queuedActionEntries.isEmpty ? activeTasks.count : queuedActionEntries.count
  }

  private func actionStatusText(_ status: AgentActionStatus) -> String {
    switch status {
    case .proposed: return t("agent_task_status_queued", "Queued")
    case .pendingConfirmation: return t("agent_task_status_waiting_approval", "Waiting for approval")
    case .running: return t("agent_task_status_running", "Running")
    case .waitingResponse: return t("agent_task_status_waiting_input", "Waiting for input")
    case .completed: return t("agent_task_status_completed", "Completed")
    case .failed: return t("agent_task_status_failed", "Failed")
    case .blocked: return t("agent_recent_status_blocked", "Blocked")
    case .rolledBack: return t("agent_recent_status_cancelled", "Rolled back")
    }
  }

  private func actionStatusTint(_ status: AgentActionStatus) -> Color {
    switch status {
    case .completed: return .galaxySSIAccent
    case .failed, .blocked: return .red
    case .pendingConfirmation, .waitingResponse, .rolledBack: return .orange
    case .proposed, .running: return .blue
    }
  }

  private var requirementRows: [GalaxySSIAgentRuntimeRow] {
    var rows = [
      requirementRow(
        id: "screen",
        title: t("agent_accessibility_status_enabled", "Screen access: enabled"),
        missingTitle: t("agent_accessibility_status_disabled", "Screen access: needs permission"),
        granted: safetySettings.screenObservationAllowed,
        systemImage: "rectangle.on.rectangle"
      ),
      requirementRow(
        id: "local-actions",
        title: t("galaxyssi.agent_runtime.local_actions", "Local actions"),
        missingTitle: t("galaxyssi.agent_runtime.local_actions_blocked", "Local actions blocked"),
        granted: safetySettings.localActionsAllowed,
        systemImage: "iphone"
      ),
      requirementRow(
        id: "connectors",
        title: t("galaxyssi.agent_runtime.connector_calls", "Connector calls"),
        missingTitle: t("galaxyssi.agent_runtime.connector_calls_blocked", "Connector calls blocked"),
        granted: safetySettings.connectorCallsAllowed,
        systemImage: "point.3.connected.trianglepath.dotted"
      ),
      requirementRow(
        id: "device-control",
        title: t("galaxyssi.agent_runtime.device_control", "Device control"),
        missingTitle: t("galaxyssi.agent_runtime.device_control_blocked", "Device control blocked"),
        granted: safetySettings.deviceControlAllowed,
        systemImage: "switch.2"
      ),
      requirementRow(
        id: "planner",
        title: t("galaxyssi.agent_runtime.model_planner", "Model planner"),
        missingTitle: t("galaxyssi.agent_runtime.local_planner", "Local planner"),
        granted: modelPlannerSettings.enabled,
        systemImage: "brain"
      )
    ]
    if let permissions = planTask?.planContext?.requiredPermissions {
      rows.append(contentsOf: permissions.enumerated().map { index, permission in
        planPermissionRow(permission, index: index)
      })
    }
    return rows
  }

  private func planPermissionRow(
    _ permission: AgentPermissionRequirement,
    index: Int
  ) -> GalaxySSIAgentRuntimeRow {
    let status = permission.granted
      ? t("agent_requirement_granted", "Ready")
      : t("agent_requirement_missing", "Needed")
    return GalaxySSIAgentRuntimeRow(
      id: "plan-permission-\(permission.id)-\(index)",
      title: permission.title.ifBlank(permission.id),
      detail: permission.id,
      badge: status,
      systemImage: permission.granted ? "checkmark.circle.fill" : "exclamationmark.circle",
      tint: permission.granted ? .galaxySSIAccent : .orange
    )
  }

  private var planContextRows: [GalaxySSIAgentRuntimeRow] {
    let draftGoal = currentGoal.trimmingCharacters(in: .whitespacesAndNewlines)
    let activeGoal = planTask?.goal.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let cleanGoal = draftGoal.isEmpty ? activeGoal : draftGoal
    guard !cleanGoal.isEmpty else { return [] }
    let savedPlanContext = planTask?.planContext
    var rows = [
      GalaxySSIAgentRuntimeRow(
        id: "goal",
        title: t("agent_plan_context_goal", "Goal"),
        detail: cleanGoal,
        badge: "",
        systemImage: "text.quote",
        tint: .galaxySSIAccent
      ),
      GalaxySSIAgentRuntimeRow(
        id: "planner",
        title: t("agent_plan_context_planner", "Planner"),
        detail: savedPlanContext?.plannerProfile.ifBlank(
          modelPlannerSettings.enabled
            ? t("galaxyssi.agent_runtime.model_planner_enabled", "Model planner enabled")
            : t("galaxyssi.agent_runtime.local_deterministic_planner", "Local deterministic planner")
        ) ?? (
          modelPlannerSettings.enabled
            ? t("galaxyssi.agent_runtime.model_planner_enabled", "Model planner enabled")
            : t("galaxyssi.agent_runtime.local_deterministic_planner", "Local deterministic planner")
        ),
        badge: savedPlanContext == nil
          ? (modelPlannerSettings.enabled ? t("common_on", "On") : t("common_off", "Off"))
          : t("agent_plan_context_saved", "Saved"),
        systemImage: "cpu",
        tint: modelPlannerSettings.enabled ? .galaxySSIAccent : .galaxySSITextSecondary
      ),
      GalaxySSIAgentRuntimeRow(
        id: "route",
        title: t("agent_plan_context_route", "Route"),
        detail: savedPlanContext.map { context in
          [
            routeLabel(context.routeKind),
            context.routeTargetTitle,
            context.routeStatus
          ]
            .filter { !$0.isBlank }
            .joined(separator: " / ")
        } ?? planTask.map(taskRouteDetail) ?? routeDetail,
        badge: permissionModeTitle(safetySettings.permissionMode),
        systemImage: "arrow.triangle.branch",
        tint: .galaxySSIInsightText
      ),
      GalaxySSIAgentRuntimeRow(
        id: "tool-budget",
        title: t("agent_plan_context_tool_budget", "Tool Budget"),
        detail: String(
          format: t("galaxyssi.agent_runtime.tool_budget_detail", "%d actions / %d tool calls / %d replans"),
          modelPlannerSettings.maxActions,
          modelPlannerSettings.maxToolCalls,
          modelPlannerSettings.maxReplans
        ),
        badge: t(taskBudget.profile.displayName, taskBudget.profile.displayName),
        systemImage: "timer",
        tint: .galaxySSITextPrimary
      )
    ]
    if let task = planTask {
      rows.append(contentsOf: [
        GalaxySSIAgentRuntimeRow(
          id: "execution-location",
          title: t("agent_plan_context_execution", "Execution"),
          detail: executionLocationDetail(task),
          badge: task.executionLocationTrusted
            ? t("agent_plan_context_trusted", "Trusted")
            : t("agent_plan_context_untrusted", "Review"),
          systemImage: "iphone.and.arrow.forward",
          tint: task.executionLocationTrusted ? .galaxySSIAccent : .orange
        ),
        GalaxySSIAgentRuntimeRow(
          id: "execution-progress",
          title: t("agent_plan_context_progress", "Progress"),
          detail: String(
            format: t("galaxyssi.agent_runtime.plan_progress_detail", "%d pending / %d native results / %d files"),
            pendingActionCount(task),
            task.nativeActionResults.count,
            task.outputFiles.count
          ),
          badge: statusText(task),
          systemImage: "chart.bar.xaxis",
          tint: statusTint(task)
        ),
        GalaxySSIAgentRuntimeRow(
          id: "execution-updated",
          title: t("agent_plan_context_updated", "Updated"),
          detail: String(
            format: t("galaxyssi.agent_runtime.plan_updated_detail", "%@ ago / %@"),
            relativeTime(task.updatedAtMillis),
            task.verification.ifBlank(task.result).ifBlank(t("agent_plan_context_no_result", "No result yet"))
          ),
          badge: statusText(task),
          systemImage: "arrow.clockwise",
          tint: .galaxySSITextSecondary
        )
      ])
    }
    if let savedPlanContext {
      rows.append(contentsOf: persistedPlanContextRows(savedPlanContext))
    }
    return rows
  }

  private func persistedPlanContextRows(_ context: AgentTaskPlanContext) -> [GalaxySSIAgentRuntimeRow] {
    [
      GalaxySSIAgentRuntimeRow(
        id: "plan-route-rationale",
        title: t("agent_plan_context_reason", "Route rationale"),
        detail: context.routeRationale.ifBlank(t("agent_plan_context_no_reason", "No route rationale")),
        badge: "",
        systemImage: "text.magnifyingglass",
        tint: .galaxySSIInsightText
      ),
      GalaxySSIAgentRuntimeRow(
        id: "plan-expected-result",
        title: t("agent_plan_context_expected", "Expected result"),
        detail: context.expectedResult.ifBlank(t("agent_plan_context_no_expected", "No expected result")),
        badge: "",
        systemImage: "checkmark.circle",
        tint: .galaxySSIAccent
      ),
      GalaxySSIAgentRuntimeRow(
        id: "plan-rollback",
        title: t("agent_plan_context_rollback", "Rollback strategy"),
        detail: context.rollbackStrategy.ifBlank(t("agent_plan_context_no_rollback", "No rollback strategy")),
        badge: context.confirmationRequired
          ? t("agent_plan_context_confirmation", "Confirm")
          : t("agent_plan_context_no_confirmation", "Automatic"),
        systemImage: "arrow.uturn.backward",
        tint: .orange
      ),
      GalaxySSIAgentRuntimeRow(
        id: "plan-revision",
        title: t("agent_plan_context_revision", "Revision"),
        detail: String(
          format: t("galaxyssi.agent_runtime.plan_revision_detail", "Revision %d / %d replans"),
          context.revision,
          context.replanCount
        ),
        badge: context.planId.prefix(8).description,
        systemImage: "arrow.triangle.2.circlepath",
        tint: .blue
      ),
      GalaxySSIAgentRuntimeRow(
        id: "plan-checkpoints",
        title: t("agent_plan_context_checkpoints", "Checkpoints"),
        detail: String(
          format: t("galaxyssi.agent_runtime.plan_checkpoint_detail", "%d active / %d history actions"),
          context.activeCheckpointCount,
          context.actionHistoryCount
        ),
        badge: String(context.actionCount),
        systemImage: "bookmark",
        tint: .galaxySSITextPrimary
      ),
      GalaxySSIAgentRuntimeRow(
        id: "plan-tool-graph",
        title: t("agent_plan_context_tool_graph", "Tool graph"),
        detail: String(
          format: t("galaxyssi.agent_runtime.plan_tool_graph_detail", "Depth %d / %d permissions"),
          context.toolGraphDepth,
          context.requiredPermissionCount
        ),
        badge: String(
          format: t("galaxyssi.agent_runtime.plan_timeout_badge", "%ds"),
          context.timeoutSeconds
        ),
        systemImage: "point.3.connected.trianglepath.dotted",
        tint: .galaxySSIInsightText
      )
    ]
  }

  private var verificationRows: [GalaxySSIAgentRuntimeRow] {
    recentTasks
      .filter { !$0.verification.isBlank || !$0.result.isBlank || $0.phase == .completed || $0.phase == .failed }
      .prefix(4)
      .map { task in
        return GalaxySSIAgentRuntimeRow(
          id: "verification-\(task.taskId)",
          title: task.goal.ifBlank(t("agent_section_verification", "Verification")),
          detail: verificationDetail(task),
          badge: task.phase == .completed
            ? t("agent_verification_success", "Verified")
            : t("agent_verification_failed", "Check"),
          systemImage: task.phase == .completed ? "checkmark.seal" : "exclamationmark.triangle",
          tint: task.phase == .completed ? .galaxySSIAccent : .orange
        )
      }
  }

  private func verificationDetail(_ task: AgentTaskRecord) -> String {
    String(
      format: t(
        "galaxyssi.agent_runtime.verification_evidence_detail",
        "%@ / %d timeline events / %d files / %d native results"
      ),
      task.verification.ifBlank(task.result).ifBlank(statusText(task)),
      task.executionLog.count,
      task.outputFiles.count,
      task.nativeActionResults.count
    )
  }

  private var recentTaskRows: [GalaxySSIAgentRuntimeRow] {
    recentTasks.prefix(3).map { task in
      GalaxySSIAgentRuntimeRow(
        id: "recent-\(task.taskId)",
        title: task.goal.ifBlank(task.taskId),
        detail: String(
          format: t("agent_recent_meta", "%@ / %@ / %@ risk"),
          relativeTime(task.updatedAtMillis),
          task.targetTitle.ifBlank(t("galaxyssi.agent_tasks.target_phone", "GalaxySSI")),
          riskText(task.risk)
        ),
        badge: statusText(task),
        systemImage: "clock",
        tint: statusTint(task),
        onTap: { selectedTask = task }
      )
    }
  }

  private var auditRows: [GalaxySSIAgentRuntimeRow] {
    let nativeRows = auditRecords.prefix(6).map { record in
      GalaxySSIAgentRuntimeRow(
        id: "audit-\(record.auditId)",
        title: record.toolId,
        detail: String(
          format: t("galaxyssi.agent_runtime.audit_detail", "%@ / %@ / %@"),
          relativeTime(record.finishedAtEpochMillis),
          nativeRiskText(record.risk),
          record.errorCode.ifBlank(record.invocationId)
        ),
        badge: auditStatusText(record.status),
        systemImage: record.status == .succeeded ? "checkmark.circle" : "exclamationmark.circle",
        tint: record.status == .succeeded ? .galaxySSIAccent : .orange
      )
    }
    let taskRows = recentTasks.flatMap { task in
      task.executionLog.suffix(2).enumerated().map { index, entry in
        GalaxySSIAgentRuntimeRow(
          id: "audit-task-\(task.taskId)-\(index)",
          title: task.goal.ifBlank(task.targetTitle).ifBlank(t("agent_section_recent_tasks", "Recent task")),
          detail: String(
            format: t("galaxyssi.agent_runtime.task_audit_detail", "%@ / %@ / %@"),
            relativeTime(task.updatedAtMillis),
            statusText(task),
            entry
          ),
          badge: statusText(task),
          systemImage: task.phase == .failed || task.phase == .blocked
            ? "exclamationmark.circle"
            : "clock.arrow.circlepath",
          tint: statusTint(task)
        )
      }
    }
    return Array((nativeRows + taskRows).prefix(6))
  }

  private var auditEventCount: Int {
    auditRecords.count + recentTasks.reduce(0) { count, task in
      count + task.executionLog.count
    }
  }

  private var statusTitle: String {
    if safetySettings.executionPaused {
      return t("agent_status_paused", "Task paused")
    }
    if activeTasks.contains(where: { $0.phase == .waitingConfirmation }) {
      return t("agent_status_waiting_confirmation", "Confirm action")
    }
    if activeTasks.contains(where: { $0.phase == .executing }) {
      return t("agent_status_executing", "Executing action")
    }
    if activeTasks.contains(where: { $0.phase == .verifying }) {
      return t("agent_status_verifying", "Verifying result")
    }
    if activeTasks.contains(where: { $0.phase == .waitingResponse }) {
      return t("agent_status_waiting_response", "Waiting for response")
    }
    if activeTasks.contains(where: { $0.phase == .planning }) {
      return t("agent_status_planning", "Planning from your goal")
    }
    if !safetySettings.screenObservationAllowed {
      return t("agent_status_accessibility_needed", "Screen access is not enabled")
    }
    return t("agent_status_observing", "Observing current screen")
  }

  private var statusSubtitle: String {
    if safetySettings.executionPaused {
      return t("agent_status_paused_subtitle", "Execution is paused. Resume when you are ready.")
    }
    if let task = activeTasks.first {
      return task.goal.ifBlank(
        String(format: t("agent_status_waiting_response_subtitle", "Waiting for %@"), task.targetTitle.ifBlank("GalaxySSI"))
      )
    }
    if !safetySettings.screenObservationAllowed {
      return t("agent_status_accessibility_needed_subtitle", "Tap here to open Accessibility settings")
    }
    return t("agent_status_default_subtitle", "GalaxySSI - ask before action - high-risk guard on")
  }

  private var statusBadge: String {
    if safetySettings.highRiskGuard {
      return t("agent_badge_safe", "Safe")
    }
    return t("common_off", "Off")
  }

  private var statusTint: Color {
    if safetySettings.executionPaused || !safetySettings.screenObservationAllowed {
      return .orange
    }
    if !safetySettings.highRiskGuard {
      return .orange
    }
    if activeTasks.contains(where: { $0.phase == .failed || $0.phase == .blocked }) {
      return .red
    }
    return .galaxySSIAccent
  }

  private var statusIcon: String {
    if safetySettings.executionPaused {
      return "pause.circle"
    }
    if !safetySettings.screenObservationAllowed {
      return "hand.raised"
    }
    if activeTasks.isEmpty {
      return "eye"
    }
    return "arrow.triangle.2.circlepath"
  }

  private var requirementsSubtitle: String {
    let missing = requirementRows.filter { $0.badge == t("agent_requirement_missing", "Needed") }.count
    return missing == 0
      ? t("galaxyssi.agent_runtime.requirements_ready", "All requirements ready")
      : String(format: t("galaxyssi.agent_runtime.requirements_missing", "%d needed"), missing)
  }

  private var plannerSubtitle: String {
    modelPlannerSettings.enabled
      ? t("galaxyssi.agent_runtime.model_planner_enabled", "Model planner enabled")
      : t("galaxyssi.agent_runtime.local_deterministic_planner", "Local deterministic planner")
  }

  private var planTask: AgentTaskRecord? {
    activeTasks.first ?? recentTasks.first
  }

  private var routeDetail: String {
    let route = modelPlannerSettings.enabled && taskBudget.allowCloud
      ? t("galaxyssi.agent_runtime.route_model", "model planner / phone native execution")
      : t("galaxyssi.agent_runtime.route_local", "local planner / phone native execution")
    return String(format: t("agent_running_tasks_targets_value", "Running tasks: %d / targets: %d"), activeTasks.count, callableTargets)
      + " / " + route
  }

  private func taskRouteDetail(_ task: AgentTaskRecord) -> String {
    let route = routeLabel(task.routeKind)
    let target = task.targetTitle.ifBlank(t("galaxyssi.agent_tasks.target_phone", "GalaxySSI"))
    return [route, target].filter { !$0.isBlank }.joined(separator: " / ")
  }

  private func routeLabel(_ route: AgentRouteKind) -> String {
    switch route {
    case .localSystem:
      return t("galaxyssi.agent_route.local_system", "Local system")
    case .cloudModel:
      return t("galaxyssi.agent_route.cloud_model", "Cloud model")
    case .localModel:
      return t("galaxyssi.agent_route.local_model", "Local model")
    case .desktopAgent:
      return t("galaxyssi.agent_route.desktop_agent", "Desktop Agent")
    case .deviceConnector:
      return t("galaxyssi.agent_route.device_connector", "Device connector")
    case .knowledge:
      return t("galaxyssi.agent_route.knowledge", "Knowledge")
    case .unknown:
      return t("galaxyssi.agent_route.unknown", "Unknown route")
    }
  }

  private func executionLocationDetail(_ task: AgentTaskRecord) -> String {
    let location = AgentExecutionPresentationPolicy.location(record: task)
    return [
      executionLocationLabel(location.locationKind),
      executionRuntimeLabel(location.runtimeKind),
      location.locationName
    ]
      .filter { !$0.isBlank }
      .joined(separator: " / ")
      .ifBlank(t("galaxyssi.agent_tasks.execution_unknown", "Execution location unavailable"))
  }

  private func pendingActionCount(_ task: AgentTaskRecord) -> Int {
    task.pendingActions.isEmpty
      ? (task.pendingAction == nil ? 0 : 1)
      : task.pendingActions.count
  }

  private func executionLocationLabel(_ value: AgentExecutionLocationKind) -> String {
    switch value {
    case .phone: return t("galaxyssi.agent_execution.location.phone", "Phone")
    case .desktop: return t("galaxyssi.agent_execution.location.desktop", "Desktop")
    case .cloud: return t("galaxyssi.agent_execution.location.cloud", "Cloud")
    case .connectedDevice: return t("galaxyssi.agent_execution.location.device", "Connected device")
    case .unknown: return ""
    }
  }

  private func executionRuntimeLabel(_ value: AgentExecutionRuntimeKind) -> String {
    switch value {
    case .phoneNative: return t("galaxyssi.agent_execution.runtime.phone_native", "Phone native")
    case .phoneLinux: return t("galaxyssi.agent_execution.runtime.phone_linux", "Phone Linux")
    case .phoneLocalModel: return t("galaxyssi.agent_execution.runtime.local_model", "Local model")
    case .phoneCloudAPI: return t("galaxyssi.agent_execution.runtime.cloud_api", "Cloud API")
    case .desktopAgent: return t("galaxyssi.agent_execution.runtime.desktop_agent", "Desktop Agent")
    case .desktopTool: return t("galaxyssi.agent_execution.runtime.desktop_tool", "Desktop tool")
    case .connectedDevice: return t("galaxyssi.agent_execution.runtime.connected_device", "Connected device")
    case .knowledge: return t("galaxyssi.agent_execution.runtime.knowledge", "Knowledge")
    case .unknown: return ""
    }
  }

  private func requirementRow(
    id: String,
    title: String,
    missingTitle: String,
    granted: Bool,
    systemImage: String
  ) -> GalaxySSIAgentRuntimeRow {
    let status = granted
      ? t("agent_requirement_granted", "Ready")
      : t("agent_requirement_missing", "Needed")
    return GalaxySSIAgentRuntimeRow(
      id: "requirement-\(id)",
      title: granted ? title : missingTitle,
      detail: String(
        format: t("galaxyssi.agent_runtime.requirement_detail", "%@ / %@"),
        status,
        id
      ),
      badge: status,
      systemImage: systemImage,
      tint: granted ? .galaxySSIAccent : .orange
    )
  }

  private func statusText(_ task: AgentTaskRecord) -> String {
    if task.blocked || task.phase == .blocked {
      return t("agent_recent_status_blocked", "Blocked")
    }
    switch task.phase {
    case .observing, .planning:
      return t("galaxyssi.agent_task_status.created", "Created on this phone")
    case .waitingConfirmation:
      return t("galaxyssi.agent_task_status.waiting_approval", "Waiting for approval")
    case .executing, .verifying:
      return t("agent_recent_status_running", "Running")
    case .waitingResponse:
      return t("galaxyssi.agent_task_status.waiting_input", "Waiting for input")
    case .paused:
      return t("agent_recent_status_paused", "Paused")
    case .cancelled:
      return t("agent_recent_status_cancelled", "Cancelled")
    case .completed:
      return t("agent_recent_status_done", "Done")
    case .failed:
      return t("agent_recent_status_failed", "Failed")
    case .blocked:
      return t("agent_recent_status_blocked", "Blocked")
    }
  }

  private func statusTint(_ task: AgentTaskRecord) -> Color {
    if task.blocked || task.phase == .blocked {
      return .orange
    }
    switch task.phase {
    case .completed:
      return .galaxySSIAccent
    case .failed, .cancelled:
      return .red
    case .paused, .waitingConfirmation, .waitingResponse:
      return .orange
    default:
      return .blue
    }
  }

  private func riskText(_ risk: AgentRisk) -> String {
    switch risk {
    case .low: return t("agent_risk_low", "low")
    case .medium: return t("agent_risk_medium", "medium")
    case .high: return t("agent_risk_high", "high")
    case .blocked: return t("agent_risk_blocked", "blocked")
    }
  }

  private func nativeRiskText(_ risk: AgentNativeToolRisk) -> String {
    switch risk {
    case .low: return t("agent_risk_low", "low")
    case .medium: return t("agent_risk_medium", "medium")
    case .high: return t("agent_risk_high", "high")
    case .blocked: return t("agent_risk_blocked", "blocked")
    }
  }

  private func nativeRiskTint(_ risk: AgentNativeToolRisk) -> Color {
    switch risk {
    case .low: return .galaxySSIAccent
    case .medium: return .orange
    case .high: return .red
    case .blocked: return .galaxySSITextSecondary
    }
  }

  private func permissionModeTitle(_ mode: AgentPermissionMode) -> String {
    t(mode.displayTitle, mode.displayTitle)
  }

  private func taskExecutionModeTitle(_ mode: AgentTaskExecutionMode) -> String {
    t(mode.displayTitle, mode.displayTitle)
  }

  private func onOff(_ value: Bool) -> String {
    value ? t("common_on", "On") : t("common_off", "Off")
  }

  private func toolStatusText(_ status: AgentNativeToolAvailabilityStatus) -> String {
    switch status {
    case .available: return t("galaxyssi.native_tool_catalog.status_available", "Available")
    case .requiresSetup: return t("galaxyssi.native_tool_catalog.status_requires_setup", "Set up")
    case .unavailable: return t("galaxyssi.native_tool_catalog.status_unavailable", "Unavailable")
    }
  }

  private func auditStatusText(_ status: AgentNativeToolResultStatus) -> String {
    switch status {
    case .succeeded: return t("agent_recent_status_done", "Done")
    case .failed: return t("agent_recent_status_failed", "Failed")
    case .verificationFailed: return t("agent_verification_failed", "Check")
    case .rejected: return t("galaxyssi.common.reject", "Reject")
    case .unavailable: return t("galaxyssi.status.not_available", "Not available")
    case .cancelled: return t("agent_recent_status_cancelled", "Cancelled")
    case .timedOut: return t("agent_observation_timed_out", "No change observed")
    }
  }

  private func effectiveToolStatus(_ tool: AgentNativeToolDescriptor) -> AgentNativeToolAvailabilityStatus {
    tool.risk == .blocked ? .unavailable : tool.availability.status
  }

  private func toolLocationIcon(_ location: AgentNativeToolLocation) -> String {
    switch location {
    case .phone: return "iphone"
    case .desktop: return "desktopcomputer"
    case .application: return "app.badge"
    case .androidSystem: return "gearshape.2"
    case .accessibilityService: return "hand.tap"
    case .unknown: return "questionmark.circle"
    }
  }

  private func relativeTime(_ timestampMillis: Int64) -> String {
    guard timestampMillis > 0 else { return "-" }
    let deltaSeconds = max(0, Int64(Date().timeIntervalSince1970) - timestampMillis / 1000)
    switch deltaSeconds {
    case 0..<60:
      return "\(deltaSeconds)s"
    case 60..<3_600:
      return "\(deltaSeconds / 60)m"
    case 3_600..<86_400:
      return "\(deltaSeconds / 3_600)h"
    default:
      return "\(deltaSeconds / 86_400)d"
    }
  }
}

private struct GalaxySSIAgentRuntimeRow: Identifiable {
  var id: String
  var title: String
  var detail: String
  var badge: String
  var systemImage: String
  var tint: Color
  var onTap: (() -> Void)? = nil
}
