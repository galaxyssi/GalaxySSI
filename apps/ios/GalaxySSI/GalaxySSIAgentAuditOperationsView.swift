import SwiftUI

struct GalaxySSIAgentAuditOperationsView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var nativeToolAudits: [AgentNativeToolAuditRecord] = []
  @State private var taskRecords: [AgentTaskRecord] = []

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_audit_operations_title", "Audit Operations"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          GalaxySSISecurityHeroView(
            title: t("cc_audit_operations_title", "Audit Operations"),
            subtitle: t("cc_audit_operations_subtitle", "Review native tool execution and recent Agent tasks on this phone"),
            systemImage: "list.clipboard",
            tint: .blue,
            badge: "\(nativeToolAudits.count + taskRecords.count)"
          )
          metricsSection
          nativeToolSection
          executionEventSection
          taskSection
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
    .refreshable { refresh() }
  }

  private var metricsSection: some View {
    HStack(spacing: 8) {
      auditMetric(
        value: "\(nativeToolAudits.count)",
        label: t("cc_tool_audit_title", "Native tools"),
        tint: .blue
      )
      auditMetric(
        value: "\(taskRecords.count)",
        label: t("cc_tasks_title", "Agent tasks"),
        tint: .purple
      )
      auditMetric(
        value: "\(failedToolCount)",
        label: t("cc_audit_failures", "Failures"),
        tint: failedToolCount == 0 ? .galaxySSIAccent : .orange
      )
    }
  }

  private var nativeToolSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_tool_audit_title", "Native tool audit"))
      if nativeToolAudits.isEmpty {
        emptyRow(
          title: t("cc_audit_empty", "No audit records"),
          subtitle: t("cc_audit_empty_subtitle", "Native tool executions will appear here after they run")
        )
      } else {
        ForEach(Array(nativeToolAudits.prefix(50))) { record in
          auditRow(
            title: record.toolId,
            subtitle: toolSubtitle(record),
            status: statusLabel(record.status.rawValue),
            tint: toolTint(record.status),
            systemImage: toolIcon(record.status)
          )
        }
      }
    }
  }

  private var taskSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_tasks_title", "Recent Agent tasks"))
      if taskRecords.isEmpty {
        emptyRow(
          title: t("cc_audit_empty", "No audit records"),
          subtitle: t("cc_tasks_empty_subtitle", "Recent Agent task activity will appear here")
        )
      } else {
        ForEach(Array(taskRecords.prefix(50))) { task in
          auditRow(
            title: task.goal.ifBlank(t("cc_task_untitled", "Untitled task")),
            subtitle: task.targetTitle.ifBlank(task.routeKind.rawValue),
            status: statusLabel(task.phase.rawValue),
            tint: taskTint(task.phase),
            systemImage: "arrow.triangle.branch"
          )
        }
      }
    }
  }

  private var executionEventSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_audit_execution_title", "Agent execution events"))
      if executionEvents.isEmpty {
        emptyRow(
          title: t("cc_audit_empty", "No audit records"),
          subtitle: t("cc_audit_execution_empty_subtitle", "Planning, recovery, and action events will appear here")
        )
      } else {
        ForEach(executionEvents) { event in
          auditRow(
            title: event.detail,
            subtitle: event.taskTitle,
            status: dateText(event.timestampMillis),
            tint: .blue,
            systemImage: "arrow.triangle.branch"
          )
        }
      }
    }
  }

  private var failedToolCount: Int {
    nativeToolAudits.filter { $0.status != .succeeded }.count
  }

  private var executionEvents: [GalaxySSIAuditExecutionEvent] {
    taskRecords.flatMap { task in
      task.executionLog.enumerated().map { index, detail in
        GalaxySSIAuditExecutionEvent(
          id: "\(task.taskId)-\(index)",
          detail: detail,
          taskTitle: task.goal.ifBlank(task.taskId),
          timestampMillis: task.updatedAtMillis
        )
      }
    }
    .sorted { $0.timestampMillis > $1.timestampMillis }
    .prefix(50)
    .map { $0 }
  }

  private func auditMetric(value: String, label: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(tint)
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.galaxySSITextSecondary)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .padding(.horizontal, 10)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func auditRow(
    title: String,
    subtitle: String,
    status: String,
    tint: Color,
    systemImage: String
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(tint)
        .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        Text(subtitle)
          .font(.system(size: 12))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      Text(status)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func emptyRow(title: String, subtitle: String) -> some View {
    auditRow(
      title: title,
      subtitle: subtitle,
      status: t("galaxyssi.status.ready", "Ready"),
      tint: .galaxySSITextSecondary,
      systemImage: "info.circle"
    )
  }

  private func toolSubtitle(_ record: AgentNativeToolAuditRecord) -> String {
    let duration = String(format: t("cc_tool_audit_detail", "%@ · %lld ms"), statusLabel(record.status.rawValue), record.durationMillis)
    return "\(duration) · \(dateText(record.finishedAtEpochMillis))"
  }

  private func dateText(_ millis: Int64) -> String {
    guard millis > 0 else { return t("galaxyssi.status.unknown", "Unknown") }
    return Date(timeIntervalSince1970: Double(millis) / 1_000)
      .formatted(date: .abbreviated, time: .shortened)
  }

  private func statusLabel(_ rawValue: String) -> String {
    switch rawValue.lowercased() {
    case "succeeded", "completed": return t("cc_audit_succeeded", "Succeeded")
    case "failed", "verification_failed": return t("cc_audit_failed", "Failed")
    case "rejected": return t("cc_audit_rejected", "Rejected")
    case "cancelled": return t("cc_audit_cancelled", "Cancelled")
    case "timed_out": return t("cc_audit_timed_out", "Timed out")
    case "blocked": return t("cc_audit_blocked", "Blocked")
    case "paused": return t("cc_audit_paused", "Paused")
    default: return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  private func toolTint(_ status: AgentNativeToolResultStatus) -> Color {
    status == .succeeded ? .galaxySSIAccent : .orange
  }

  private func toolIcon(_ status: AgentNativeToolResultStatus) -> String {
    status == .succeeded ? "checkmark.circle" : "exclamationmark.circle"
  }

  private func taskTint(_ phase: AgentPhase) -> Color {
    switch phase {
    case .completed: return .galaxySSIAccent
    case .failed, .blocked: return .red
    case .cancelled, .paused: return .orange
    default: return .blue
    }
  }

  private func refresh() {
    nativeToolAudits = AgentNativeToolDefaultStores
      .makePersistentStores()
      .auditStore
      .list(limit: 50, toolId: "", status: nil)
    taskRecords = store.recentAgentTasks(limit: 50)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

private struct GalaxySSIAuditExecutionEvent: Identifiable {
  var id: String
  var detail: String
  var taskTitle: String
  var timestampMillis: Int64
}
