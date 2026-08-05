import Foundation
import SwiftUI

struct SignalASIAgentRuntimePanelView: View {
  var safetySettings: AgentSafetySettings
  var modelPlannerSettings: AgentModelPlannerSettings
  var taskBudget: AgentTaskBudget
  var callableTargets: Int
  var currentGoal: String
  var recentTasks: [AgentTaskRecord]
  var nativeTools: [AgentNativeToolDescriptor]
  var auditRecords: [AgentNativeToolAuditRecord]
  var onCyclePermissionMode: () -> Void
  var onToggleHighRiskGuard: () -> Void
  var onToggleMemoryCapture: () -> Void
  var t: (String, String) -> String

  @State private var expandedSectionIds: Set<String> = ["requirements", "recent_tasks"]

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
        id: "toolbox",
        title: t("agent_section_toolbox", "Toolbox"),
        subtitle: String(format: t("signalasi.agent_runtime.toolbox_summary", "%d local tools"), availableTools.count),
        systemImage: "wrench.and.screwdriver",
        rows: toolboxRows,
        emptyTitle: t("agent_toolbox_empty", "No local tools are available")
      )
      runtimeSection(
        id: "action_queue",
        title: t("agent_section_action_queue", "Action Queue"),
        subtitle: String(format: t("signalasi.agent_runtime.action_queue_summary", "%d active"), activeTasks.count),
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
        subtitle: String(format: t("signalasi.agent_runtime.verification_summary", "%d evidence rows"), verificationRows.count),
        systemImage: "checkmark.seal",
        rows: verificationRows,
        emptyTitle: t("agent_verification_empty", "No execution evidence yet")
      )
      runtimeSection(
        id: "recent_tasks",
        title: t("agent_section_recent_tasks", "Recent Tasks"),
        subtitle: String(format: t("signalasi.agent_runtime.recent_summary", "%d tasks"), recentTasks.count),
        systemImage: "clock.arrow.circlepath",
        rows: recentTaskRows,
        emptyTitle: t("agent_recent_empty", "No recent Agent tasks yet")
      )
      runtimeSection(
        id: "audit_trail",
        title: t("agent_section_audit_trail", "Audit Trail"),
        subtitle: String(format: t("signalasi.agent_runtime.audit_summary", "%d events"), auditRecords.count),
        systemImage: "list.clipboard",
        rows: auditRows,
        emptyTitle: t("agent_audit_empty", "No Agent audit events yet")
      )
    }
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
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
        Text(statusSubtitle)
          .font(.system(size: 11))
          .foregroundColor(.signalASITextSecondary)
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
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var controlStrip: some View {
    HStack(spacing: 8) {
      runtimeControlButton(
        title: String(
          format: t("agent_safety_permission_mode_value", "Mode: %@"),
          permissionModeTitle(safetySettings.permissionMode)
        ),
        tint: .signalASITextPrimary,
        action: onCyclePermissionMode
      )
      runtimeControlButton(
        title: String(format: t("agent_safety_high_risk_guard_value", "High-risk Guard: %@"), onOff(safetySettings.highRiskGuard)),
        tint: safetySettings.highRiskGuard ? .signalASIAccent : .orange,
        action: onToggleHighRiskGuard
      )
      runtimeControlButton(
        title: String(format: t("agent_safety_memory_capture_value", "Memory: %@"), onOff(safetySettings.memoryCapture)),
        tint: safetySettings.memoryCapture ? .signalASIAccent : .orange,
        action: onToggleMemoryCapture
      )
    }
  }

  private func runtimeControlButton(title: String, tint: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, minHeight: 42)
        .padding(.horizontal, 6)
        .background(Color.signalASISurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func runtimeSection(
    id: String,
    title: String,
    subtitle: String,
    systemImage: String,
    rows: [SignalASIAgentRuntimeRow],
    emptyTitle: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
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
            .foregroundColor(.signalASIAccent)
            .frame(width: 24, height: 24)
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(.signalASITextPrimary)
              .lineLimit(1)
            Text(subtitle)
              .font(.system(size: 11))
              .foregroundColor(.signalASITextSecondary)
              .lineLimit(1)
          }
          Spacer(minLength: 8)
          Image(systemName: expandedSectionIds.contains(id) ? "chevron.up" : "chevron.down")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.signalASITextSecondary)
        }
      }
      .buttonStyle(.plain)

      if expandedSectionIds.contains(id) {
        if rows.isEmpty {
          runtimeRow(
            SignalASIAgentRuntimeRow(
              id: "\(id)-empty",
              title: emptyTitle,
              detail: "",
              badge: "",
              systemImage: "info.circle",
              tint: .signalASITextSecondary
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
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func runtimeRow(_ row: SignalASIAgentRuntimeRow) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: row.systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(row.tint)
        .frame(width: 22, height: 22)
      VStack(alignment: .leading, spacing: 3) {
        Text(row.title)
          .font(.system(size: 13))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        if !row.detail.isEmpty {
          Text(row.detail)
            .font(.system(size: 11))
            .foregroundColor(.signalASITextSecondary)
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
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var toolboxRows: [SignalASIAgentRuntimeRow] {
    availableTools.prefix(4).map { tool in
      SignalASIAgentRuntimeRow(
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

  private var actionQueueRows: [SignalASIAgentRuntimeRow] {
    activeTasks.prefix(4).map { task in
      SignalASIAgentRuntimeRow(
        id: "queue-\(task.taskId)",
        title: task.goal.ifBlank(statusText(task)),
        detail: String(
          format: t("agent_action_queue_meta", "%@ / %@ risk"),
          task.targetTitle.ifBlank(t("signalasi.agent_tasks.target_phone", "SignalASI")),
          riskText(task.risk)
        ),
        badge: statusText(task),
        systemImage: task.blocked ? "hand.raised" : "arrow.triangle.2.circlepath",
        tint: statusTint(task)
      )
    }
  }

  private var requirementRows: [SignalASIAgentRuntimeRow] {
    [
      requirementRow(
        id: "screen",
        title: t("agent_accessibility_status_enabled", "Screen access: enabled"),
        missingTitle: t("agent_accessibility_status_disabled", "Screen access: needs permission"),
        granted: safetySettings.screenObservationAllowed,
        systemImage: "rectangle.on.rectangle"
      ),
      requirementRow(
        id: "local-actions",
        title: t("signalasi.agent_runtime.local_actions", "Local actions"),
        missingTitle: t("signalasi.agent_runtime.local_actions_blocked", "Local actions blocked"),
        granted: safetySettings.localActionsAllowed,
        systemImage: "iphone"
      ),
      requirementRow(
        id: "connectors",
        title: t("signalasi.agent_runtime.connector_calls", "Connector calls"),
        missingTitle: t("signalasi.agent_runtime.connector_calls_blocked", "Connector calls blocked"),
        granted: safetySettings.connectorCallsAllowed,
        systemImage: "point.3.connected.trianglepath.dotted"
      ),
      requirementRow(
        id: "device-control",
        title: t("signalasi.agent_runtime.device_control", "Device control"),
        missingTitle: t("signalasi.agent_runtime.device_control_blocked", "Device control blocked"),
        granted: safetySettings.deviceControlAllowed,
        systemImage: "switch.2"
      ),
      requirementRow(
        id: "planner",
        title: t("signalasi.agent_runtime.model_planner", "Model planner"),
        missingTitle: t("signalasi.agent_runtime.local_planner", "Local planner"),
        granted: modelPlannerSettings.enabled,
        systemImage: "brain"
      )
    ]
  }

  private var planContextRows: [SignalASIAgentRuntimeRow] {
    let draftGoal = currentGoal.trimmingCharacters(in: .whitespacesAndNewlines)
    let activeGoal = activeTasks.first?.goal.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let cleanGoal = draftGoal.isEmpty ? activeGoal : draftGoal
    guard !cleanGoal.isEmpty else { return [] }
    return [
      SignalASIAgentRuntimeRow(
        id: "goal",
        title: t("agent_plan_context_goal", "Goal"),
        detail: cleanGoal,
        badge: "",
        systemImage: "text.quote",
        tint: .signalASIAccent
      ),
      SignalASIAgentRuntimeRow(
        id: "planner",
        title: t("agent_plan_context_planner", "Planner"),
        detail: modelPlannerSettings.enabled
          ? t("signalasi.agent_runtime.model_planner_enabled", "Model planner enabled")
          : t("signalasi.agent_runtime.local_deterministic_planner", "Local deterministic planner"),
        badge: modelPlannerSettings.enabled ? t("common_on", "On") : t("common_off", "Off"),
        systemImage: "cpu",
        tint: modelPlannerSettings.enabled ? .signalASIAccent : .signalASITextSecondary
      ),
      SignalASIAgentRuntimeRow(
        id: "route",
        title: t("agent_plan_context_route", "Route"),
        detail: routeDetail,
        badge: permissionModeTitle(safetySettings.permissionMode),
        systemImage: "arrow.triangle.branch",
        tint: .signalASIInsightText
      ),
      SignalASIAgentRuntimeRow(
        id: "tool-budget",
        title: t("agent_plan_context_tool_budget", "Tool Budget"),
        detail: String(
          format: t("signalasi.agent_runtime.tool_budget_detail", "%d actions / %d tool calls / %d replans"),
          modelPlannerSettings.maxActions,
          modelPlannerSettings.maxToolCalls,
          modelPlannerSettings.maxReplans
        ),
        badge: t(taskBudget.profile.displayName, taskBudget.profile.displayName),
        systemImage: "timer",
        tint: .signalASITextPrimary
      )
    ]
  }

  private var verificationRows: [SignalASIAgentRuntimeRow] {
    recentTasks
      .filter { !$0.verification.isBlank || !$0.result.isBlank || $0.phase == .completed || $0.phase == .failed }
      .prefix(3)
      .map { task in
        let detail = task.verification.ifBlank(task.result).ifBlank(statusText(task))
        return SignalASIAgentRuntimeRow(
          id: "verification-\(task.taskId)",
          title: task.goal.ifBlank(t("agent_section_verification", "Verification")),
          detail: detail,
          badge: task.phase == .completed
            ? t("agent_verification_success", "Verified")
            : t("agent_verification_failed", "Check"),
          systemImage: task.phase == .completed ? "checkmark.seal" : "exclamationmark.triangle",
          tint: task.phase == .completed ? .signalASIAccent : .orange
        )
      }
  }

  private var recentTaskRows: [SignalASIAgentRuntimeRow] {
    recentTasks.prefix(3).map { task in
      SignalASIAgentRuntimeRow(
        id: "recent-\(task.taskId)",
        title: task.goal.ifBlank(task.taskId),
        detail: String(
          format: t("agent_recent_meta", "%@ / %@ / %@ risk"),
          relativeTime(task.updatedAtMillis),
          task.targetTitle.ifBlank(t("signalasi.agent_tasks.target_phone", "SignalASI")),
          riskText(task.risk)
        ),
        badge: statusText(task),
        systemImage: "clock",
        tint: statusTint(task)
      )
    }
  }

  private var auditRows: [SignalASIAgentRuntimeRow] {
    auditRecords.prefix(3).map { record in
      SignalASIAgentRuntimeRow(
        id: "audit-\(record.auditId)",
        title: record.toolId,
        detail: String(
          format: t("signalasi.agent_runtime.audit_detail", "%@ / %@ / %@"),
          relativeTime(record.finishedAtEpochMillis),
          nativeRiskText(record.risk),
          record.errorCode.ifBlank(record.invocationId)
        ),
        badge: auditStatusText(record.status),
        systemImage: record.status == .succeeded ? "checkmark.circle" : "exclamationmark.circle",
        tint: record.status == .succeeded ? .signalASIAccent : .orange
      )
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
        String(format: t("agent_status_waiting_response_subtitle", "Waiting for %@"), task.targetTitle.ifBlank("SignalASI"))
      )
    }
    if !safetySettings.screenObservationAllowed {
      return t("agent_status_accessibility_needed_subtitle", "Tap here to open Accessibility settings")
    }
    return t("agent_status_default_subtitle", "SignalASI - ask before action - high-risk guard on")
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
    return .signalASIAccent
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
      ? t("signalasi.agent_runtime.requirements_ready", "All requirements ready")
      : String(format: t("signalasi.agent_runtime.requirements_missing", "%d needed"), missing)
  }

  private var plannerSubtitle: String {
    modelPlannerSettings.enabled
      ? t("signalasi.agent_runtime.model_planner_enabled", "Model planner enabled")
      : t("signalasi.agent_runtime.local_deterministic_planner", "Local deterministic planner")
  }

  private var routeDetail: String {
    let route = modelPlannerSettings.enabled && taskBudget.allowCloud
      ? t("signalasi.agent_runtime.route_model", "model planner / phone native execution")
      : t("signalasi.agent_runtime.route_local", "local planner / phone native execution")
    return String(format: t("agent_running_tasks_targets_value", "Running tasks: %d / targets: %d"), activeTasks.count, callableTargets)
      + " / " + route
  }

  private func requirementRow(
    id: String,
    title: String,
    missingTitle: String,
    granted: Bool,
    systemImage: String
  ) -> SignalASIAgentRuntimeRow {
    SignalASIAgentRuntimeRow(
      id: "requirement-\(id)",
      title: granted ? title : missingTitle,
      detail: granted
        ? t("agent_requirement_granted", "Ready")
        : t("agent_requirement_missing", "Needed"),
      badge: granted
        ? t("agent_requirement_granted", "Ready")
        : t("agent_requirement_missing", "Needed"),
      systemImage: systemImage,
      tint: granted ? .signalASIAccent : .orange
    )
  }

  private func statusText(_ task: AgentTaskRecord) -> String {
    if task.blocked || task.phase == .blocked {
      return t("agent_recent_status_blocked", "Blocked")
    }
    switch task.phase {
    case .observing, .planning:
      return t("signalasi.agent_task_status.created", "Created on this phone")
    case .waitingConfirmation:
      return t("signalasi.agent_task_status.waiting_approval", "Waiting for approval")
    case .executing, .verifying:
      return t("agent_recent_status_running", "Running")
    case .waitingResponse:
      return t("signalasi.agent_task_status.waiting_input", "Waiting for input")
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
      return .signalASIAccent
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
    case .low: return .signalASIAccent
    case .medium: return .orange
    case .high: return .red
    case .blocked: return .signalASITextSecondary
    }
  }

  private func permissionModeTitle(_ mode: AgentPermissionMode) -> String {
    t(mode.displayTitle, mode.displayTitle)
  }

  private func onOff(_ value: Bool) -> String {
    value ? t("common_on", "On") : t("common_off", "Off")
  }

  private func toolStatusText(_ status: AgentNativeToolAvailabilityStatus) -> String {
    switch status {
    case .available: return t("signalasi.native_tool_catalog.status_available", "Available")
    case .requiresSetup: return t("signalasi.native_tool_catalog.status_requires_setup", "Set up")
    case .unavailable: return t("signalasi.native_tool_catalog.status_unavailable", "Unavailable")
    }
  }

  private func auditStatusText(_ status: AgentNativeToolResultStatus) -> String {
    switch status {
    case .succeeded: return t("agent_recent_status_done", "Done")
    case .failed: return t("agent_recent_status_failed", "Failed")
    case .verificationFailed: return t("agent_verification_failed", "Check")
    case .rejected: return t("signalasi.common.reject", "Reject")
    case .unavailable: return t("signalasi.status.not_available", "Not available")
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

private struct SignalASIAgentRuntimeRow: Identifiable {
  var id: String
  var title: String
  var detail: String
  var badge: String
  var systemImage: String
  var tint: Color
}
