import SwiftUI

struct GalaxySSIAgentRuntimeTaskDetailSheet: View {
  @Environment(\.dismiss) private var dismiss

  var task: AgentTaskRecord
  var t: (String, String) -> String
  var taskActions: [AgentTaskCenterAction] = []
  var onAction: (AgentTaskCenterAction) -> Void = { _ in }

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          Text(task.goal.ifBlank(task.taskId))
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .fixedSize(horizontal: false, vertical: true)

          VStack(alignment: .leading, spacing: 8) {
            ForEach(detailRows) { row in
              HStack(alignment: .top, spacing: 10) {
                Text(row.title)
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundColor(.galaxySSITextSecondary)
                  .frame(width: 92, alignment: .leading)
                Text(row.detail)
                  .font(.system(size: 13))
                  .foregroundColor(.galaxySSITextPrimary)
                  .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
              }
            }
          }
          .padding(12)
          .background(Color.galaxySSISurface)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

          detailSection(
            title: t("galaxyssi.agent_task_detail.result", "Result"),
            value: task.result
          )
          detailSection(
            title: t("galaxyssi.agent_task_detail.verification", "Verification"),
            value: task.verification
          )
          detailSection(
            title: t("agent_section_plan_context", "Plan context"),
            value: planContextText
          )
          detailListSection(
            title: t("galaxyssi.agent_task_detail.files", "Output files"),
            values: task.outputFiles
          )
          detailListSection(
            title: t("galaxyssi.agent_task_detail.timeline", "Execution timeline"),
            values: task.executionLog
          )
        }
        .padding(16)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationTitle(t("galaxyssi.agent_task_detail.title", "Task details"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("common_close", "Close")) {
            dismiss()
          }
        }
        ToolbarItem(placement: .primaryAction) {
          if !taskActions.isEmpty {
            Menu {
              ForEach(taskActions) { action in
                Button {
                  onAction(action)
                } label: {
                  Label(
                    AgentTaskCenterActionPresentation.title(action, t: t),
                    systemImage: AgentTaskCenterActionPresentation.icon(action)
                  )
                }
              }
            } label: {
              Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
            }
            .accessibilityLabel(Text(t("galaxyssi.agent_task_center.actions", "Task actions")))
          }
        }
      }
    }
  }

  private var detailRows: [GalaxySSIAgentRuntimeTaskDetailRow] {
    [
      GalaxySSIAgentRuntimeTaskDetailRow(
        title: t("galaxyssi.agent_task_detail.status", "Status"),
        detail: statusText
      ),
      GalaxySSIAgentRuntimeTaskDetailRow(
        title: t("galaxyssi.agent_task_detail.execution", "Execution"),
        detail: executionSummary
      ),
      GalaxySSIAgentRuntimeTaskDetailRow(
        title: t("galaxyssi.agent_task_detail.route", "Route"),
        detail: routeText
      ),
      GalaxySSIAgentRuntimeTaskDetailRow(
        title: t("galaxyssi.agent_task_detail.target", "Agent or model"),
        detail: task.targetTitle.ifBlank("-")
      ),
      GalaxySSIAgentRuntimeTaskDetailRow(
        title: t("galaxyssi.agent_task_detail.risk", "Risk"),
        detail: riskText
      ),
      GalaxySSIAgentRuntimeTaskDetailRow(
        title: t("galaxyssi.agent_task_detail.updated", "Updated"),
        detail: relativeTime(task.updatedAtMillis)
      )
    ]
  }

  private var planContextText: String {
    guard let context = task.planContext else { return "" }
    let route = [
      context.routeKind.rawValue.lowercased().replacingOccurrences(of: "_", with: " "),
      context.routeTargetTitle,
      context.routeStatus
    ]
      .filter { !$0.isBlank }
      .joined(separator: " / ")
    return [
      "\(t("agent_plan_context_planner", "Planner")): \(context.plannerProfile.ifBlank("-"))",
      "\(t("agent_plan_context_route", "Route")): \(route.ifBlank("-"))",
      "\(t("agent_plan_context_reason", "Route rationale")): \(context.routeRationale.ifBlank("-"))",
      "\(t("agent_plan_context_expected", "Expected result")): \(context.expectedResult.ifBlank("-"))",
      "\(t("agent_plan_context_rollback", "Rollback strategy")): \(context.rollbackStrategy.ifBlank("-"))",
      "\(t("agent_plan_context_revision", "Revision")): \(String(format: t("galaxyssi.agent_runtime.plan_revision_detail", "Revision %d / %d replans"), context.revision, context.replanCount))",
      "\(t("agent_plan_context_checkpoints", "Checkpoints")): \(String(format: t("galaxyssi.agent_runtime.plan_checkpoint_detail", "%d active / %d history actions"), context.activeCheckpointCount, context.actionHistoryCount))",
      "\(t("agent_plan_context_tool_graph", "Tool graph")): \(String(format: t("galaxyssi.agent_runtime.plan_tool_graph_timeout_detail", "Depth %d / %d permissions / %ds timeout"), context.toolGraphDepth, context.requiredPermissionCount, context.timeoutSeconds))"
    ].joined(separator: "\n")
  }

  @ViewBuilder
  private func detailSection(title: String, value: String) -> some View {
    if !value.isBlank {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
        Text(value)
          .font(.system(size: 13))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.galaxySSIInsightBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  @ViewBuilder
  private func detailListSection(title: String, values: [String]) -> some View {
    if !values.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          Text(value)
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.galaxySSIInsightBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var statusText: String {
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

  private var executionSummary: String {
    let location = AgentExecutionPresentationPolicy.location(record: task)
    return [
      locationLabel(location.locationKind),
      runtimeLabel(location.runtimeKind),
      location.locationName
    ]
      .filter { !$0.isBlank }
      .joined(separator: " / ")
      .ifBlank(t("galaxyssi.agent_tasks.execution_unknown", "Unknown"))
  }

  private var routeText: String {
    task.routeKind.rawValue
      .lowercased()
      .replacingOccurrences(of: "_", with: " ")
  }

  private var riskText: String {
    switch task.risk {
    case .low: return t("galaxyssi.agent_risk.low", "low")
    case .medium: return t("galaxyssi.agent_risk.medium", "medium")
    case .high: return t("galaxyssi.agent_risk.high", "high")
    case .blocked: return t("galaxyssi.agent_risk.blocked", "blocked")
    }
  }

  private func locationLabel(_ value: AgentExecutionLocationKind) -> String {
    switch value {
    case .phone: return t("galaxyssi.agent_execution.location.phone", "Phone")
    case .desktop: return t("galaxyssi.agent_execution.location.desktop", "Desktop")
    case .cloud: return t("galaxyssi.agent_execution.location.cloud", "Cloud")
    case .connectedDevice: return t("galaxyssi.agent_execution.location.device", "Connected device")
    case .unknown: return ""
    }
  }

  private func runtimeLabel(_ value: AgentExecutionRuntimeKind) -> String {
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

  private func relativeTime(_ timestampMillis: Int64) -> String {
    guard timestampMillis > 0 else { return "-" }
    let deltaSeconds = max(0, Int64(Date().timeIntervalSince1970) - timestampMillis / 1_000)
    switch deltaSeconds {
    case 0..<60: return "\(deltaSeconds)s"
    case 60..<3_600: return "\(deltaSeconds / 60)m"
    case 3_600..<86_400: return "\(deltaSeconds / 3_600)h"
    default: return "\(deltaSeconds / 86_400)d"
    }
  }
}

private struct GalaxySSIAgentRuntimeTaskDetailRow: Identifiable {
  let id = UUID()
  var title: String
  var detail: String
}
