import SwiftUI

struct GalaxySSIAgentActionQueueItem: Identifiable {
  var task: AgentTaskRecord
  var action: AgentAction

  var id: String {
    "\(task.taskId)-\(action.id)"
  }
}

struct GalaxySSIAgentActionQueueCard: View {
  var items: [GalaxySSIAgentActionQueueItem]
  var onEditAction: ((GalaxySSIAgentActionQueueItem) -> Void)? = nil
  var t: (String, String) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "list.bullet.rectangle")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSIAccent)
          .frame(width: 22, height: 22)
        Text(t("agent_section_action_queue", "Action Queue"))
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
        Spacer(minLength: 8)
        Text(String(items.count))
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(.galaxySSIAccent)
          .padding(.horizontal, 8)
          .frame(minHeight: 24)
          .background(Color.galaxySSIAccent.opacity(0.12))
          .clipShape(Capsule())
      }
      ForEach(items) { item in
        actionRow(item)
      }
    }
    .padding(12)
    .background(Color.galaxySSIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func actionRow(_ item: GalaxySSIAgentActionQueueItem) -> some View {
    let action = item.action
    let target = action.target.ifBlank(item.task.targetTitle)
      .ifBlank(t("galaxyssi.agent_tasks.target_phone", "GalaxySSI"))
    let status = actionStatusText(action.status)
    let tint = actionStatusTint(action.status)

    if AgentPlanEditor.isEditablePending(action), let onEditAction {
      Button {
        onEditAction(item)
      } label: {
        actionRowContent(
          action: action,
          target: target,
          status: status,
          tint: tint,
          showsEditIndicator: true
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(t("agent_plan_edit_action", "Edit action")))
    } else {
      actionRowContent(
        action: action,
        target: target,
        status: status,
        tint: tint,
        showsEditIndicator: false
      )
    }
  }

  private func actionRowContent(
    action: AgentAction,
    target: String,
    status: String,
    tint: Color,
    showsEditIndicator: Bool
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Circle()
        .fill(tint)
        .frame(width: 8, height: 8)
        .padding(.top, 5)
      VStack(alignment: .leading, spacing: 3) {
        Text(action.description.ifBlank(action.kind.rawValue))
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text(actionDetail(action, target: target))
          .font(.system(size: 11))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 6)
      Text(status)
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
        .frame(minWidth: 48, alignment: .trailing)
      if showsEditIndicator {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
          .frame(width: 30, height: 30)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func actionDetail(_ action: AgentAction, target: String) -> String {
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
      details.append(String(
        format: t("agent_action_queue_dependencies", "%d dependencies / %d output sources"),
        dependencyCount,
        outputSourceCount
      ))
    }
    if !action.result.isBlank {
      details.append(String(
        format: t("agent_action_queue_result", "Result: %@"),
        action.result
      ))
    }
    return details.joined(separator: " / ")
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

  private func riskText(_ risk: AgentRisk) -> String {
    switch risk {
    case .low: return t("agent_risk_low", "low")
    case .medium: return t("agent_risk_medium", "medium")
    case .high: return t("agent_risk_high", "high")
    case .blocked: return t("agent_risk_blocked", "blocked")
    }
  }
}
