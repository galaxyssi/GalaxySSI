import SwiftUI
import UIKit

struct GalaxySSIAgentRecentTasksView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  var initialTask: AgentTaskRecord? = nil
  @State private var searchText = ""
  @State private var selectedTask: AgentTaskRecord?
  @State private var deletingTask: AgentTaskRecord?
  @State private var statusText = ""
  @State private var initialTaskPresented = false
  @State private var teamSnapshots: [AgentTeamExecutionSnapshot] = []

  private let teamHistoryStore = AgentTeamExecutionHistoryStore.shared

  private var tasks: [AgentTaskRecord] {
    let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? store.recentAgentTasks(limit: 20) : store.searchAgentTasks(clean, limit: 50)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.agent_tasks.title", "Tasks"),
        leading: {
          GalaxySSIBackButton()
        },
        trailing: {
          Button {
            searchText = ""
            refreshTeamSnapshots()
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 20, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
          }
        }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AgentTaskHeroView(
            title: t("galaxyssi.agent_tasks.hero_title", "Recent Agent tasks"),
            subtitle: t(
              "galaxyssi.agent_tasks.hero_subtitle",
              "Review task status, execution logs, results, retries, and cleanup"
            ),
            badge: String(
              format: t("galaxyssi.agent_tasks.badge", "%d tasks"),
              store.recentAgentTasks(limit: 200).count
            )
          )

          AgentTaskSearchRow(
            searchText: $searchText,
            placeholder: t("galaxyssi.agent_tasks.search_placeholder", "Search task goals, targets, logs, or files")
          )

          if !statusText.isEmpty {
            Text(statusText)
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
              .padding(.horizontal, 4)
          }

          if !tasks.isEmpty {
            sectionTitle(t("galaxyssi.agent_section_recent_tasks", "Recent Tasks"))
            VStack(spacing: 8) {
              ForEach(tasks) { task in
                AgentTaskRow(
                  task: task,
                  status: statusText(task),
                  statusTint: statusTint(task),
                  subtitle: taskSubtitle(task),
                  onOpen: {
                    selectedTask = task
                  },
                  actions: {
                    taskMenu(task)
                  }
                )
              }
            }
          } else if teamSnapshots.isEmpty {
            sectionTitle(t("galaxyssi.agent_section_recent_tasks", "Recent Tasks"))
            AgentTaskInfoRow(
              title: t("galaxyssi.agent_recent_empty", "No recent Agent tasks yet"),
              subtitle: t("galaxyssi.agent_tasks.empty_subtitle", "Tasks created by the phone Agent and paired desktop runtimes appear here."),
              systemImage: "clock",
              tint: .galaxySSIAccent,
              badge: ""
            )
          }

          if !teamSnapshots.isEmpty {
            sectionTitle(t("galaxyssi.agent_team.section_title", "Agent Teams"))
            VStack(spacing: 8) {
              ForEach(teamSnapshots, id: \.supervisorRunId) { snapshot in
                GalaxySSIAgentTeamSummaryRow(snapshot: snapshot)
              }
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear {
      refreshTeamSnapshots()
      guard !initialTaskPresented, let initialTask else { return }
      initialTaskPresented = true
      selectedTask = tasks.first(where: { $0.taskId == initialTask.taskId }) ?? initialTask
    }
    .onReceive(NotificationCenter.default.publisher(for: .galaxySSIAgentTeamExecutionHistoryDidUpdate)) { _ in
      refreshTeamSnapshots()
    }
    .sheet(item: $selectedTask) { task in
      AgentTaskDetailSheet(
        task: task,
        detailText: detailText(task),
        status: statusText(task),
        execution: executionSummary(task),
        onCopy: {
          copyTask(task)
        },
        onRetry: {
          retryTask(task)
        },
        onRollback: {
          rollbackTask(task)
        },
        onCancel: {
          cancelTask(task)
        },
        onDelete: {
          deletingTask = task
        }
      )
    }
    .alert(t("galaxyssi.agent_task_center.delete_title", "Delete task?"), isPresented: deleteAlertPresented) {
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {
        deletingTask = nil
      }
      Button(t("galaxyssi.common.delete", "Delete"), role: .destructive) {
        confirmDelete()
      }
    } message: {
      Text(String(
        format: t("galaxyssi.agent_task_center.delete_message", "Delete the task record for \"%@\"? The conversation will remain available."),
        deletingTask?.goal ?? ""
      ))
    }
  }

  private var deleteAlertPresented: Binding<Bool> {
    Binding(
      get: { deletingTask != nil },
      set: { value in
        if !value {
          deletingTask = nil
        }
      }
    )
  }

  private func refreshTeamSnapshots() {
    teamSnapshots = teamHistoryStore.recent(20)
  }

  @ViewBuilder
  private func taskMenu(_ task: AgentTaskRecord) -> some View {
    Menu {
      ForEach(AgentTaskCenterPolicy.actions(task)) { action in
        Button(actionLabel(action)) {
          handleAction(action, task: task)
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(.galaxySSITextSecondary)
        .frame(width: 36, height: 36)
    }
  }

  private func handleAction(_ action: AgentTaskCenterAction, task: AgentTaskRecord) {
    switch action {
    case .cancel:
      cancelTask(task)
    case .resume:
      resumeTask(task)
    case .retry:
      retryTask(task)
    case .rollback:
      rollbackTask(task)
    case .copy:
      copyTask(task)
    case .viewLog:
      selectedTask = task
    case .delete:
      deletingTask = task
    }
  }

  private func resumeTask(_ task: AgentTaskRecord) {
    guard AgentTaskCenterPolicy.resumable(task) else {
      statusText = t(
        "galaxyssi.agent_tasks.resume_unavailable",
        "This task cannot be resumed now"
      )
      return
    }
    guard coordinator.resumeLocalNativeAction(taskId: task.taskId) else {
      statusText = t(
        "galaxyssi.agent_tasks.resume_failed",
        "The paused task could not be resumed"
      )
      return
    }
    statusText = t("galaxyssi.agent_tasks.resumed", "Task resumed")
  }

  private func retryTask(_ task: AgentTaskRecord) {
    if coordinator.retryFailedLocalNativeAction(taskId: task.taskId) {
      statusText = t(
        "galaxyssi.agent.task_control.action_retrying",
        "Retrying the failed action..."
      )
      selectedTask = nil
      return
    }
    guard AgentTaskCenterPolicy.isReusableGoal(task.goal) else {
      statusText = t(
        "galaxyssi.agent_task_center.retry_unavailable",
        "This task cannot be retried because its goal is unavailable"
      )
      return
    }
    let goal = task.goal
    statusText = t("galaxyssi.agent_tasks.retrying", "Retrying task...")
    Task { @MainActor in
      guard let contact = store.contact(id: "hermes") else {
        statusText = t("galaxyssi.agent_tasks.retry_no_agent", "Agent conversation is not available")
        return
      }
      if let destination = store.agentSessionDestination(id: task.sessionId) {
        _ = store.switchAgentSession(destination)
      } else {
        _ = store.createAgentSession(title: t("galaxyssi.agent_session.new", "New session"))
      }
      let sent = await coordinator.send(goal, to: contact)
      statusText = sent
        ? t("galaxyssi.agent_tasks.retry_sent", "Task sent to Agent")
        : t("galaxyssi.agent_tasks.retry_failed", "The task could not be sent")
    }
  }

  private func rollbackTask(_ task: AgentTaskRecord) {
    statusText = coordinator.rollbackLastLocalNativeAction(taskId: task.taskId)
      ? t("galaxyssi.agent.task_control.rollback_requested", "Rollback requested")
      : t("galaxyssi.agent.task_control.rollback_failed", "This action cannot be rolled back")
    selectedTask = nil
  }

  private func cancelTask(_ task: AgentTaskRecord) {
    guard AgentTaskCenterPolicy.cancellable(task) else {
      statusText = t(
        "galaxyssi.agent_tasks.cancel_unavailable",
        "This task cannot be cancelled now"
      )
      return
    }
    coordinator.cancelLocalNativeAction(taskId: task.taskId)
    statusText = t("galaxyssi.agent_tasks.cancelled", "Task cancelled")
    selectedTask = nil
  }

  private func copyTask(_ task: AgentTaskRecord) {
    UIPasteboard.general.string = detailText(task)
    statusText = t("galaxyssi.agent_task_center.copied", "Task details copied")
  }

  private func confirmDelete() {
    guard let task = deletingTask else { return }
    let deleted = store.deleteAgentTask(id: task.taskId)
    statusText = t(
      deleted ? "galaxyssi.agent_task_center.deleted" : "galaxyssi.agent_task_center.delete_failed",
      deleted ? "Task deleted" : "The task could not be deleted"
    )
    if selectedTask?.taskId == task.taskId {
      selectedTask = nil
    }
    deletingTask = nil
  }

  private func taskSubtitle(_ task: AgentTaskRecord) -> String {
    String(
      format: t("galaxyssi.agent_recent_meta", "%@ / %@ / %@ risk"),
      listTime(task.updatedAtMillis),
      task.targetTitle.ifBlank(t("galaxyssi.agent_tasks.target_phone", "GalaxySSI")),
      riskText(task.risk)
    )
  }

  private func detailText(_ task: AgentTaskRecord) -> String {
    var lines: [String] = [
      task.goal,
      "",
      "\(t("galaxyssi.agent_task_detail.status", "Status")): \(statusText(task))",
      "\(t("galaxyssi.agent_task_detail.execution", "Execution")): \(executionSummary(task))",
      "\(t("galaxyssi.agent_task_detail.route", "Route")): \(routeText(task.routeKind))",
      "\(t("galaxyssi.agent_task_detail.target", "Agent or model")): \(task.targetTitle.ifBlank("-"))",
      "\(t("galaxyssi.agent_task_detail.risk", "Risk")): \(riskText(task.risk))",
      "\(t("galaxyssi.agent_task_detail.updated", "Updated")): \(listTime(task.updatedAtMillis))"
    ]
    if let context = task.planContext {
      let route = [
        context.routeKind.rawValue.lowercased().replacingOccurrences(of: "_", with: " "),
        context.routeTargetTitle,
        context.routeStatus
      ]
        .filter { !$0.isBlank }
        .joined(separator: " / ")
      lines += ["", t("agent_section_plan_context", "Plan context")]
      lines += [
        t("agent_plan_context_planner", "Planner") + ": " + context.plannerProfile.ifBlank("-"),
        t("agent_plan_context_route", "Route") + ": " + route.ifBlank("-"),
        t("agent_plan_context_reason", "Route rationale") + ": " + context.routeRationale.ifBlank("-"),
        t("agent_plan_context_expected", "Expected result") + ": " + context.expectedResult.ifBlank("-"),
        t("agent_plan_context_rollback", "Rollback strategy") + ": " + context.rollbackStrategy.ifBlank("-"),
        String(format: t("galaxyssi.agent_runtime.plan_revision_detail", "Revision %d / %d replans"), context.revision, context.replanCount),
        String(format: t("galaxyssi.agent_runtime.plan_checkpoint_detail", "%d active / %d history actions"), context.activeCheckpointCount, context.actionHistoryCount),
        String(format: t("galaxyssi.agent_runtime.plan_tool_graph_timeout_detail", "Depth %d / %d permissions / %ds timeout"), context.toolGraphDepth, context.requiredPermissionCount, context.timeoutSeconds)
      ]
    }
    if !task.result.isBlank {
      lines += ["", t("galaxyssi.agent_task_detail.result", "Result"), task.result]
    }
    if !task.verification.isBlank {
      lines += ["", t("galaxyssi.agent_task_detail.verification", "Verification"), task.verification]
    }
    if !task.outputFiles.isEmpty {
      lines += ["", t("galaxyssi.agent_task_detail.files", "Output files")]
      lines += task.outputFiles
    }
    if !task.executionLog.isEmpty {
      lines += ["", t("galaxyssi.agent_task_detail.timeline", "Execution timeline")]
      lines += task.executionLog
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func executionSummary(_ task: AgentTaskRecord) -> String {
    let execution = AgentExecutionPresentationPolicy.location(record: task)
    return [
      locationText(execution.locationKind),
      runtimeText(execution.runtimeKind),
      execution.locationName
    ]
      .filter { !$0.isBlank }
      .joined(separator: " / ")
      .ifBlank(t("galaxyssi.agent_tasks.execution_unknown", "Unknown"))
  }

  private func statusText(_ task: AgentTaskRecord) -> String {
    if task.blocked || task.phase == .blocked {
      return t("galaxyssi.agent_recent_status_blocked", "Blocked")
    }
    switch task.phase {
    case .observing, .planning:
      return t("galaxyssi.agent_task_status.created", "Created on this phone")
    case .waitingConfirmation:
      return t("galaxyssi.agent_task_status.waiting_approval", "Waiting for approval")
    case .executing, .verifying:
      return t("galaxyssi.agent_recent_status_running", "Running")
    case .waitingResponse:
      return t("galaxyssi.agent_task_status.waiting_input", "Waiting for input")
    case .paused:
      return t("galaxyssi.agent_recent_status_paused", "Paused")
    case .cancelled:
      return t("galaxyssi.agent_recent_status_cancelled", "Cancelled")
    case .completed:
      return t("galaxyssi.agent_recent_status_done", "Done")
    case .failed:
      return t("galaxyssi.agent_recent_status_failed", "Failed")
    case .blocked:
      return t("galaxyssi.agent_recent_status_blocked", "Blocked")
    }
  }

  private func statusTint(_ task: AgentTaskRecord) -> Color {
    if task.blocked || task.phase == .blocked {
      return .red
    }
    switch task.phase {
    case .completed:
      return .galaxySSIAccent
    case .failed:
      return .red
    case .cancelled, .paused:
      return .galaxySSITextSecondary
    default:
      return .galaxySSIAccent
    }
  }

  private func actionLabel(_ action: AgentTaskCenterAction) -> String {
    switch action {
    case .cancel:
      return t("galaxyssi.common.cancel_task", "Cancel task")
    case .resume:
      return t("galaxyssi.common.resume", "Resume")
    case .retry:
      return t("galaxyssi.common.retry", "Retry")
    case .rollback:
      return t("galaxyssi.agent.task_control.rollback", "Rollback last action")
    case .copy:
      return t("galaxyssi.common.copy", "Copy")
    case .viewLog:
      return t("galaxyssi.agent_task_center.view_log", "View log")
    case .delete:
      return t("galaxyssi.agent_task_center.delete", "Delete task")
    }
  }

  private func routeText(_ route: AgentRouteKind) -> String {
    route.rawValue.lowercased().replacingOccurrences(of: "_", with: " ")
  }

  private func riskText(_ risk: AgentRisk) -> String {
    switch risk {
    case .low:
      return t("galaxyssi.agent_risk.low", "low")
    case .medium:
      return t("galaxyssi.agent_risk.medium", "medium")
    case .high:
      return t("galaxyssi.agent_risk.high", "high")
    case .blocked:
      return t("galaxyssi.agent_risk.blocked", "blocked")
    }
  }

  private func locationText(_ value: AgentExecutionLocationKind) -> String {
    switch value {
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

  private func runtimeText(_ value: AgentExecutionRuntimeKind) -> String {
    switch value {
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

  private func listTime(_ millis: Int64) -> String {
    guard millis > 0 else { return "-" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentTaskDetailSheet: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dismiss) private var dismiss
  var task: AgentTaskRecord
  var detailText: String
  var status: String
  var execution: String
  var onCopy: () -> Void
  var onRetry: () -> Void
  var onRollback: () -> Void
  var onCancel: () -> Void
  var onDelete: () -> Void

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          AgentTaskInfoRow(
            title: task.goal.ifBlank(t("galaxyssi.agent_task_details_title", "Agent task")),
            subtitle: execution,
            systemImage: "bolt.horizontal",
            tint: .galaxySSIAccent,
            badge: status
          )

          VStack(alignment: .leading, spacing: 10) {
            detailBlock(t("galaxyssi.agent_task_detail.status", "Status"), status)
            detailBlock(t("galaxyssi.agent_task_detail.execution", "Execution"), execution)
            detailBlock(t("galaxyssi.agent_task_detail.route", "Route"), task.routeKind.rawValue)
            detailBlock(t("galaxyssi.agent_task_detail.target", "Agent or model"), task.targetTitle.ifBlank("-"))
            detailBlock(t("galaxyssi.agent_task_detail.risk", "Risk"), task.risk.rawValue.lowercased())
            detailBlock(
              t("galaxyssi.agent_task_detail.updated", "Updated"),
              listTime(task.updatedAtMillis)
            )
            detailBlock(
              t("agent_plan_context_progress", "Progress"),
              String(
                format: t(
                  "galaxyssi.agent_runtime.plan_progress_detail",
                  "%d pending / %d native results / %d files"
                ),
                pendingActionCount,
                task.nativeActionResults.count,
                task.outputFiles.count
              )
            )
            if let action = task.lastCompletedNativeAction {
              detailBlock(
                t("galaxyssi.agent_task_detail.last_action", "Last completed action"),
                action.description.ifBlank(action.target).ifBlank(action.kind.rawValue)
              )
            }
            if task.nativeRollbackAction != nil {
              detailBlock(
                t("galaxyssi.agent_task_detail.rollback", "Rollback"),
                t("galaxyssi.agent_task_detail.rollback_available", "The last native action can be rolled back.")
              )
            }
            if !task.result.isBlank {
              detailBlock(t("galaxyssi.agent_task_detail.result", "Result"), task.result)
            }
            if !task.verification.isBlank {
              detailBlock(t("galaxyssi.agent_task_detail.verification", "Verification"), task.verification)
            }
            if !task.outputFiles.isEmpty {
              detailBlock(t("galaxyssi.agent_task_detail.files", "Output files"), task.outputFiles.joined(separator: "\n"))
            }
            detailBlock(
              t("galaxyssi.agent_task_detail.timeline", "Execution timeline"),
              task.executionLog.isEmpty
                ? t("galaxyssi.agent_task_center.log_empty", "No execution log was recorded for this task.")
                : task.executionLog.joined(separator: "\n")
            )
            if !task.nativeActionResults.isEmpty {
              detailBlock(
                t("galaxyssi.agent_task_detail.native_results", "Native action results"),
                task.nativeActionResults.joined(separator: "\n")
              )
            }
          }
        }
        .padding(12)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationTitle(t("galaxyssi.agent_task_detail.title", "Task details"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(t("galaxyssi.common.done", "Done")) {
            dismiss()
          }
        }
        ToolbarItemGroup(placement: .bottomBar) {
          if AgentTaskCenterPolicy.cancellable(task) {
            Button(role: .destructive) {
              dismiss()
              DispatchQueue.main.async {
                onCancel()
              }
            } label: {
              Label(t("galaxyssi.common.cancel_task", "Cancel task"), systemImage: "xmark.circle")
            }
          }
          if AgentTaskCenterPolicy.actions(task).contains(where: { $0.id == AgentTaskCenterAction.retry.id }) {
            Button {
              onRetry()
            } label: {
              Label(t("galaxyssi.common.retry", "Retry"), systemImage: "arrow.clockwise")
            }
          }
          if AgentTaskCenterPolicy.rollbackAvailable(task) {
            Button {
              onRollback()
            } label: {
              Label(
                t("galaxyssi.agent.task_control.rollback", "Rollback last action"),
                systemImage: "arrow.uturn.backward.circle"
              )
            }
          }
          Spacer()
          Button {
            onCopy()
          } label: {
            Label(t("galaxyssi.common.copy", "Copy"), systemImage: "doc.on.doc")
          }
          if AgentTaskCenterPolicy.actions(task).contains(where: { $0.id == AgentTaskCenterAction.delete.id }) {
            Spacer()
            Button(role: .destructive) {
              dismiss()
              DispatchQueue.main.async {
                onDelete()
              }
            } label: {
              Label(t("galaxyssi.common.delete", "Delete"), systemImage: "trash")
            }
          }
        }
      }
    }
  }

  private func detailBlock(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
      Text(value.ifBlank("-"))
        .font(.system(size: 13))
        .foregroundColor(.galaxySSITextPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var pendingActionCount: Int {
    task.pendingActions.isEmpty
      ? (task.pendingAction == nil ? 0 : 1)
      : task.pendingActions.count
  }

  private func listTime(_ millis: Int64) -> String {
    guard millis > 0 else { return "-" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage == LanguagePolicySettings.zhCN ? "zh_Hans_CN" : "en_US_POSIX")
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1_000))
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct AgentTaskHeroView: View {
  var title: String
  var subtitle: String
  var badge: String

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.blue.opacity(0.14))
        Image(systemName: "clock.arrow.circlepath")
          .font(.system(size: 24, weight: .semibold))
          .foregroundColor(.blue)
      }
      .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          Text(title)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.blue)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        Text(subtitle)
          .font(.system(size: 14))
          .foregroundColor(.galaxySSITextSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }
}

private struct AgentTaskSearchRow: View {
  @Binding var searchText: String
  var placeholder: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
      TextField(placeholder, text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
    .background(Color.galaxySSISearchBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentTaskRow<Actions: View>: View {
  var task: AgentTaskRecord
  var status: String
  var statusTint: Color
  var subtitle: String
  var onOpen: () -> Void
  let actions: Actions

  init(
    task: AgentTaskRecord,
    status: String,
    statusTint: Color,
    subtitle: String,
    onOpen: @escaping () -> Void,
    @ViewBuilder actions: () -> Actions
  ) {
    self.task = task
    self.status = status
    self.statusTint = statusTint
    self.subtitle = subtitle
    self.onOpen = onOpen
    self.actions = actions()
  }

  var body: some View {
    HStack(spacing: 10) {
      Button(action: onOpen) {
        HStack(spacing: 12) {
          Circle()
            .fill(statusTint)
            .frame(width: 9, height: 9)
          VStack(alignment: .leading, spacing: 4) {
            Text(task.goal.ifBlank(task.taskId))
              .font(.system(size: 15, weight: .semibold))
              .foregroundColor(.galaxySSITextPrimary)
              .lineLimit(2)
            Text(subtitle)
              .font(.system(size: 12))
              .foregroundColor(.galaxySSITextSecondary)
              .lineLimit(2)
          }
          Spacer(minLength: 8)
          Text(status)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(statusTint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
      }
      .buttonStyle(.plain)
      actions
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct AgentTaskInfoRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.14))
        Image(systemName: systemImage)
          .font(.system(size: 19, weight: .semibold))
          .foregroundColor(tint)
      }
      .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(3)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(3)
      }
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.1))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
