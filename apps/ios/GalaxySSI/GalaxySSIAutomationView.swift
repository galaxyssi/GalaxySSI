import SwiftUI

struct GalaxySSIAutomationView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @ObservedObject private var remoteProactiveEventStore = UserDefaultsAgentRemoteProactiveEventStore.shared
  @ObservedObject private var workflowTriggerStore = UserDefaultsAgentWorkflowTriggerStore.shared
  @State private var creatingTask = false
  @State private var errorMessage = ""

  private var tasks: [AgentProactiveTask] {
    store.automationTasks()
  }

  private var recentExecutions: [AgentWorkflowExecutionRecord] {
    store.recentWorkflowExecutions(limit: 6)
  }

  private var savedWorkflowTasks: [AgentProactiveTask] {
    tasks.filter { $0.action.kind == .workflow }
  }

  private var scheduledWorkflowTasks: [AgentProactiveTask] {
    savedWorkflowTasks.filter { task in
      switch task.trigger.kind {
      case .cron, .interval, .goalCheckpoint:
        return true
      case .manual, .webhook:
        return false
      }
    }
  }

  private var eventTriggerTasks: [AgentProactiveTask] {
    tasks.filter { $0.trigger.kind == .webhook }
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.automation.title", "Automation"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          HStack(spacing: 16) {
            NavigationLink(destination: GalaxySSISkillMarketplaceView()) {
              Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.purple)
            }
            .accessibilityLabel(t("galaxyssi.skill_marketplace.title", "Skill Marketplace"))
            NavigationLink(destination: GalaxySSIWorkflowsView()) {
              Image(systemName: "square.stack.3d.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.galaxySSIAccent)
            }
            .accessibilityLabel(t("galaxyssi.workflow.title", "Workflows"))
            NavigationLink(destination: GalaxySSIWorkflowTriggerEditorView()) {
              Image(systemName: "bolt")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.orange)
            }
            .accessibilityLabel(t("galaxyssi.workflow_trigger.title", "Workflow Trigger"))
            Button {
              creatingTask = true
            } label: {
              Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.galaxySSIAccent)
            }
            .accessibilityLabel(t("galaxyssi.automation.new_task", "New proactive task"))
          }
        }
      )

      NavigationLink(
        destination: GalaxySSIAutomationEditorView(
          task: store.makeAutomationTaskDraft(
            name: t("galaxyssi.automation.new_task", "New proactive task")
          )
        ),
        isActive: $creatingTask
      ) {
        EmptyView()
      }
      .hidden()

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AutomationHeroCard(
            title: t("galaxyssi.automation.hero_title", "Task Automation"),
            subtitle: t("galaxyssi.automation.hero_subtitle", "Let AI actively handle fixed tasks"),
            icon: "clock",
            tint: .orange,
            metrics: [
              AutomationMetric(
                value: "\(tasks.count)",
                label: t("galaxyssi.automation.metric_tasks", "Proactive tasks")
              ),
              AutomationMetric(
                value: "\(tasks.filter(\.enabled).count)",
                label: t("galaxyssi.automation.metric_enabled", "Enabled")
              ),
              AutomationMetric(
                value: "\(recentExecutions.count)",
                label: t("galaxyssi.automation.metric_runs", "Recent runs")
              )
            ]
          )

          sectionTitle(t("galaxyssi.automation.proactive_tasks", "Proactive Tasks"))
          AutomationActionRow(
            title: t("galaxyssi.automation.new_task", "New proactive task"),
            subtitle: t("galaxyssi.automation.new_task_subtitle", "Choose an independent trigger and action"),
            icon: "plus.circle",
            tint: .orange,
            badge: t("galaxyssi.common.create", "Create")
          ) {
            creatingTask = true
          }
          if tasks.isEmpty {
            AutomationInfoRow(
              title: t("galaxyssi.automation.no_tasks", "No proactive tasks"),
              subtitle: t("galaxyssi.automation.no_tasks_subtitle", "Create a task that can keep working after the App or phone restarts"),
              icon: "exclamationmark.circle",
              tint: .galaxySSITextSecondary,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(tasks) { task in
                NavigationLink(destination: GalaxySSIAutomationDetailView(taskId: task.taskId)) {
                  AutomationTaskRow(
                    title: task.name,
                    subtitle: proactiveTaskSubtitle(task),
                    icon: "clock",
                    tint: task.enabled ? .galaxySSIAccent : .galaxySSITextSecondary,
                    badge: proactiveRunStatusLabel(task.lastStatus),
                    badgeTint: statusTint(task.lastStatus)
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }

          if !remoteProactiveEventStore.events.isEmpty {
            sectionTitle(t("galaxyssi.automation.remote_activity", "Remote Activity"))
            VStack(spacing: 8) {
              ForEach(remoteProactiveEventStore.recent(limit: 30)) { event in
                let status = AgentProactiveRunStatus.fromWireValue(event.status)
                AutomationInfoRow(
                  title: event.desktopName.ifBlank(t("galaxyssi.automation.remote_desktop", "GalaxySSI Desktop")),
                  subtitle: remoteProactiveEventSubtitle(event),
                  icon: "arrow.down.circle",
                  tint: statusTint(status),
                  badge: proactiveRunStatusLabel(status)
                )
              }
            }
          }

          sectionTitle(t("galaxyssi.automation.saved_workflows", "Saved Workflows"))
          if savedWorkflowTasks.isEmpty {
            AutomationInfoRow(
              title: t("galaxyssi.automation.no_workflows", "No saved workflows"),
              subtitle: t("galaxyssi.automation.create_workflow_hint", "Use: save workflow Name :: goal"),
              icon: "paperplane",
              tint: .galaxySSIAccent,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(savedWorkflowTasks) { task in
                automationTaskNavigationRow(
                  task,
                  icon: "paperplane",
                  tint: task.enabled ? .galaxySSIAccent : .galaxySSITextSecondary,
                  badge: proactiveRunStatusLabel(task.lastStatus),
                  badgeTint: statusTint(task.lastStatus)
                )
              }
            }
          }

          sectionTitle(t("galaxyssi.automation.schedules", "Schedules"))
          if scheduledWorkflowTasks.isEmpty {
            AutomationInfoRow(
              title: t("galaxyssi.automation.no_schedules", "No workflow schedules"),
              subtitle: t("galaxyssi.automation.schedule_hint", "Use: schedule workflow Name at 09:00"),
              icon: "calendar",
              tint: .blue,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(scheduledWorkflowTasks) { task in
                automationTaskNavigationRow(
                  task,
                  icon: "calendar",
                  tint: task.enabled ? .blue : .galaxySSITextSecondary,
                  badge: triggerBadge(task.trigger),
                  badgeTint: .blue
                )
              }
            }
          }

          sectionTitle(t("galaxyssi.automation.event_triggers", "Event Triggers"))
          if eventTriggerTasks.isEmpty {
            AutomationInfoRow(
              title: t("galaxyssi.automation.no_event_triggers", "No event triggers"),
              subtitle: t("galaxyssi.automation.event_trigger_hint", "Run a saved workflow when an event matches"),
              icon: "bolt",
              tint: .orange,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(eventTriggerTasks) { task in
                automationTaskNavigationRow(
                  task,
                  icon: "bolt",
                  tint: task.enabled ? .orange : .galaxySSITextSecondary,
                  badge: triggerBadge(task.trigger),
                  badgeTint: .orange
                )
              }
            }
          }

          sectionTitle(t("galaxyssi.workflow_trigger.device_section", "Device Event Triggers"))
          if workflowTriggerStore.list().isEmpty {
            NavigationLink(destination: GalaxySSIWorkflowTriggerEditorView()) {
              AutomationInfoRow(
                title: t("galaxyssi.workflow_trigger.no_triggers", "No device triggers"),
                subtitle: t("galaxyssi.workflow_trigger.add_hint", "Run a workflow when power connects or battery becomes low"),
                icon: "bolt",
                tint: .orange,
                badge: t("galaxyssi.common.add", "Add")
              )
            }
            .buttonStyle(.plain)
          } else {
            VStack(spacing: 8) {
              NavigationLink(destination: GalaxySSIWorkflowTriggerEditorView()) {
                AutomationActionRow(
                  title: t("galaxyssi.workflow_trigger.add", "Add device trigger"),
                  subtitle: t("galaxyssi.workflow_trigger.add_hint", "Run a workflow when power connects or battery becomes low"),
                  icon: "plus.circle",
                  tint: .orange,
                  badge: t("galaxyssi.common.add", "Add")
                ) {}
              }
              .buttonStyle(.plain)
              ForEach(workflowTriggerStore.list()) { trigger in
                NavigationLink(destination: GalaxySSIWorkflowTriggerEditorView(trigger: trigger)) {
                  GalaxySSIWorkflowTriggerRow(trigger: trigger)
                }
                .buttonStyle(.plain)
              }
            }
          }

          sectionTitle(t("galaxyssi.automation.recent_executions", "Recent Executions"))
          if recentExecutions.isEmpty {
            AutomationInfoRow(
              title: t("galaxyssi.automation.no_recent_executions", "No recent workflow executions"),
              subtitle: t("galaxyssi.automation.run_command_hint", "Use: run workflow Name"),
              icon: "clock.arrow.circlepath",
              tint: .galaxySSITextSecondary,
              badge: ""
            )
          } else {
            VStack(spacing: 8) {
              ForEach(recentExecutions) { execution in
                AutomationInfoRow(
                  title: workflowExecutionStatusLabel(execution.status),
                  subtitle: workflowExecutionSubtitle(execution),
                  icon: "clock.arrow.circlepath",
                  tint: workflowExecutionTint(execution.status),
                  badge: execution.workflowName
                )
              }
            }
          }

          sectionTitle(t("galaxyssi.automation.templates", "Templates"))
          VStack(spacing: 8) {
            AutomationTemplateRow(
              title: t("galaxyssi.automation.morning_brief", "Morning Brief"),
              subtitle: t("galaxyssi.automation.morning_brief_subtitle", "Push news and status every day at 08:00")
            ) { runTemplate(title: $0, prompt: $1) }
            AutomationTemplateRow(
              title: t("galaxyssi.automation.health_check", "Health Check"),
              subtitle: t("galaxyssi.automation.health_check_subtitle", "Check PC, MQTT, and file services")
            ) { runTemplate(title: $0, prompt: $1) }
            AutomationTemplateRow(
              title: t("galaxyssi.automation.device_alert", "Device Status Alert"),
              subtitle: t("galaxyssi.automation.device_alert_subtitle", "Notify when the PC is offline or storage is abnormal")
            ) { runTemplate(title: $0, prompt: $1) }
            AutomationTemplateRow(
              title: t("galaxyssi.automation.knowledge_review", "Knowledge Review"),
              subtitle: t("galaxyssi.automation.knowledge_review_subtitle", "Regular learning review and key questions")
            ) { runTemplate(title: $0, prompt: $1) }
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(t("galaxyssi.automation.invalid", "The proactive task is invalid"), isPresented: Binding(
      get: { !errorMessage.isEmpty },
      set: { if !$0 { errorMessage = "" } }
    )) {
      Button(t("galaxyssi.common.ok", "OK"), role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func automationTaskNavigationRow(
    _ task: AgentProactiveTask,
    icon: String,
    tint: Color,
    badge: String,
    badgeTint: Color
  ) -> some View {
    NavigationLink(destination: GalaxySSIAutomationDetailView(taskId: task.taskId)) {
      AutomationTaskRow(
        title: task.name,
        subtitle: proactiveTaskSubtitle(task),
        icon: icon,
        tint: tint,
        badge: badge,
        badgeTint: badgeTint
      )
    }
    .buttonStyle(.plain)
  }

  private func proactiveTaskSubtitle(_ task: AgentProactiveTask) -> String {
    [
      proactiveTriggerDescription(task.trigger),
      task.nextRunAtMillis > 0
        ? String(format: t("galaxyssi.automation.next", "Next %@"), automationTime(task.nextRunAtMillis))
        : nil,
      String(format: t("galaxyssi.automation.last_status", "Last status: %@"), proactiveRunStatusLabel(task.lastStatus))
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  private func workflowExecutionSubtitle(_ execution: AgentWorkflowExecutionRecord) -> String {
    [
      automationTime(execution.startedAtMillis),
      execution.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  private func remoteProactiveEventSubtitle(_ event: AgentRemoteProactiveEvent) -> String {
    [
      event.taskId.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
      event.detail.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
      automationTime(event.timestampMillis)
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  private func workflowExecutionStatusLabel(_ status: AgentWorkflowExecutionStatus) -> String {
    switch status {
    case .running: return t("galaxyssi.automation.status_running", "Running")
    case .waitingConfirmation: return t("galaxyssi.automation.status_waiting_confirmation", "Waiting confirmation")
    case .waitingResponse: return t("galaxyssi.automation.status_waiting_response", "Waiting response")
    case .completed: return t("galaxyssi.automation.status_completed", "Completed")
    case .skipped: return t("galaxyssi.automation.status_skipped", "Skipped")
    case .failed: return t("galaxyssi.automation.status_failed", "Failed")
    case .cancelled: return t("galaxyssi.automation.status_cancelled", "Cancelled")
    case .blocked: return t("galaxyssi.automation.status_blocked", "Blocked")
    }
  }

  private func workflowExecutionTint(_ status: AgentWorkflowExecutionStatus) -> Color {
    switch status {
    case .completed: return .green
    case .failed, .blocked: return .red
    case .cancelled, .skipped: return .galaxySSITextSecondary
    case .running, .waitingConfirmation, .waitingResponse: return .galaxySSIAccent
    }
  }

  private func proactiveTriggerDescription(_ trigger: AgentProactiveTrigger) -> String {
    switch trigger.kind {
    case .manual:
      return proactiveTriggerLabel(trigger.kind)
    case .cron:
      return "\(trigger.cron) - \(trigger.timeZone)"
    case .interval, .goalCheckpoint:
      return String(format: t("galaxyssi.automation.seconds", "Every %d seconds"), Int(trigger.intervalSeconds))
    case .webhook:
      return t("galaxyssi.automation.webhook_hint", "Only events relayed by a paired Desktop are accepted")
    }
  }

  private func proactiveTriggerLabel(_ kind: AgentProactiveTriggerKind) -> String {
    GalaxySSIAutomationLabels.trigger(kind, language: interfaceLanguage)
  }

  private func triggerBadge(_ trigger: AgentProactiveTrigger) -> String {
    proactiveTriggerLabel(trigger.kind)
  }

  private func proactiveRunStatusLabel(_ status: AgentProactiveRunStatus) -> String {
    GalaxySSIAutomationLabels.status(status, language: interfaceLanguage)
  }

  private func statusTint(_ status: AgentProactiveRunStatus) -> Color {
    GalaxySSIAutomationLabels.statusTint(status)
  }

  private func automationTime(_ millis: Int64) -> String {
    GalaxySSIAutomationLabels.time(millis, language: interfaceLanguage)
  }

  private func runTemplate(title: String, prompt: String) {
    do {
      let saved = try store.saveAutomationTask(store.makeAutomationTaskDraft(name: title, prompt: prompt))
      _ = try store.triggerAutomationTaskNow(id: saved.taskId)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIAutomationDetailView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @EnvironmentObject private var coordinator: MessageCoordinator
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.presentationMode) private var presentationMode
  @State private var deleteConfirmation = false
  @State private var errorMessage = ""

  var taskId: String

  private var task: AgentProactiveTask? {
    store.automationTask(id: taskId)
  }

  private var runs: [AgentProactiveRun] {
    store.automationRuns(taskId: taskId, limit: 50)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.automation.details_title", "Task Details"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )

      if let task {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            AutomationHeroCard(
              title: task.name,
              subtitle: proactiveTaskSubtitle(task),
              icon: "clock",
              tint: task.enabled ? .galaxySSIAccent : .galaxySSITextSecondary,
              metrics: [
                AutomationMetric(value: proactiveRunStatusLabel(task.lastStatus), label: t("galaxyssi.automation.status", "Status")),
                AutomationMetric(value: "\(task.runCount)", label: t("galaxyssi.automation.metric_runs", "Recent runs")),
                AutomationMetric(value: "\(task.revision)", label: t("galaxyssi.automation.revision", "Revision"))
              ]
            )

            sectionTitle(t("galaxyssi.section.actions", "Actions"))
            AutomationActionRow(
              title: t("galaxyssi.automation.run_now", "Run now"),
              subtitle: t("galaxyssi.automation.run_now_subtitle", "Create one idempotent run immediately"),
              icon: "paperplane.fill",
              tint: .galaxySSIAccent,
              badge: t("galaxyssi.automation.run", "Run")
            ) {
              do {
                _ = try store.triggerAutomationTaskNow(id: task.taskId)
                Task {
                  await coordinator.runAutomationSchedulerCycle()
                }
              } catch {
                errorMessage = error.localizedDescription
              }
            }
            NavigationLink(destination: GalaxySSIAutomationEditorView(task: task)) {
              AutomationTaskRow(
                title: t("galaxyssi.automation.edit_task", "Edit task"),
                subtitle: t("galaxyssi.automation.proactive_subtitle", "Durable Cron, goal checkpoint, webhook, Agent, team, workflow, and phone-tool execution"),
                icon: "slider.horizontal.3",
                tint: .blue,
                badge: t("galaxyssi.common.edit", "Edit"),
                badgeTint: .blue
              )
            }
            .buttonStyle(.plain)
            AutomationSwitchRow(
              title: t("galaxyssi.automation.enabled", "Task enabled"),
              subtitle: proactiveTriggerDescription(task.trigger),
              icon: "power",
              tint: task.enabled ? .galaxySSIAccent : .galaxySSITextSecondary,
              isOn: Binding(
                get: { task.enabled },
                set: { enabled in
                  do {
                    _ = try store.setAutomationTaskEnabled(id: task.taskId, enabled: enabled)
                  } catch {
                    errorMessage = error.localizedDescription
                  }
                }
              )
            )

            sectionTitle(t("galaxyssi.automation.runs", "Run History"))
            if runs.isEmpty {
              AutomationInfoRow(
                title: t("galaxyssi.automation.no_runs", "No runs yet"),
                subtitle: t("galaxyssi.automation.run_now_subtitle", "Create one idempotent run immediately"),
                icon: "clock.arrow.circlepath",
                tint: .galaxySSITextSecondary,
                badge: ""
              )
            } else {
              VStack(spacing: 8) {
                ForEach(runs) { run in
                  AutomationActionRow(
                    title: proactiveRunStatusLabel(run.status),
                    subtitle: proactiveRunSubtitle(run),
                    icon: "clock.arrow.circlepath",
                    tint: statusTint(run.status),
                    badge: run.status.terminal ? "" : t("galaxyssi.common.cancel", "Cancel")
                  ) {
                    if !run.status.terminal {
                      _ = store.cancelAutomationRun(id: run.runId)
                    }
                  }
                }
              }
            }

            sectionTitle(t("galaxyssi.security.danger", "Danger"))
            AutomationActionRow(
              title: t("galaxyssi.automation.delete_task", "Delete task"),
              subtitle: t("galaxyssi.automation.delete_confirm", "Delete this proactive task and its run history?"),
              icon: "trash",
              tint: .red,
              badge: t("galaxyssi.common.delete", "Delete")
            ) {
              deleteConfirmation = true
            }
          }
          .padding(.horizontal, 12)
          .padding(.top, 12)
          .padding(.bottom, 18)
        }
      } else {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.circle")
            .font(.system(size: 34, weight: .semibold))
            .foregroundColor(.galaxySSITextSecondary)
          Text(t("galaxyssi.automation.not_found", "Task not found"))
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.galaxySSITextPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(t("galaxyssi.automation.delete_task", "Delete task"), isPresented: $deleteConfirmation) {
      Button(t("galaxyssi.common.delete", "Delete"), role: .destructive) {
        _ = store.deleteAutomationTask(id: taskId)
        presentationMode.wrappedValue.dismiss()
      }
      Button(t("galaxyssi.common.cancel", "Cancel"), role: .cancel) {}
    } message: {
      Text(t("galaxyssi.automation.delete_confirm", "Delete this proactive task and its run history?"))
    }
    .alert(t("galaxyssi.automation.invalid", "The proactive task is invalid"), isPresented: Binding(
      get: { !errorMessage.isEmpty },
      set: { if !$0 { errorMessage = "" } }
    )) {
      Button(t("galaxyssi.common.ok", "OK"), role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func proactiveTaskSubtitle(_ task: AgentProactiveTask) -> String {
    [
      proactiveTriggerDescription(task.trigger),
      task.nextRunAtMillis > 0
        ? String(format: t("galaxyssi.automation.next", "Next %@"), automationTime(task.nextRunAtMillis))
        : nil,
      String(format: t("galaxyssi.automation.last_status", "Last status: %@"), proactiveRunStatusLabel(task.lastStatus))
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  private func proactiveRunSubtitle(_ run: AgentProactiveRun) -> String {
    [
      automationTime(run.scheduledForMillis),
      String(format: t("galaxyssi.automation.attempt", "Attempt %d"), run.attempt),
      run.resultSummary.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    ]
    .compactMap { $0 }
    .joined(separator: "\n")
  }

  private func proactiveTriggerDescription(_ trigger: AgentProactiveTrigger) -> String {
    switch trigger.kind {
    case .manual:
      return GalaxySSIAutomationLabels.trigger(trigger.kind, language: interfaceLanguage)
    case .cron:
      return "\(trigger.cron) - \(trigger.timeZone)"
    case .interval, .goalCheckpoint:
      return String(format: t("galaxyssi.automation.seconds", "Every %d seconds"), Int(trigger.intervalSeconds))
    case .webhook:
      return t("galaxyssi.automation.webhook_hint", "Only events relayed by a paired Desktop are accepted")
    }
  }

  private func proactiveRunStatusLabel(_ status: AgentProactiveRunStatus) -> String {
    GalaxySSIAutomationLabels.status(status, language: interfaceLanguage)
  }

  private func statusTint(_ status: AgentProactiveRunStatus) -> Color {
    GalaxySSIAutomationLabels.statusTint(status)
  }

  private func automationTime(_ millis: Int64) -> String {
    GalaxySSIAutomationLabels.time(millis, language: interfaceLanguage)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct GalaxySSIAutomationEditorView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.presentationMode) private var presentationMode
  @State private var draft: AutomationEditorDraft
  @State private var errorMessage = ""

  init(task: AgentProactiveTask) {
    _draft = State(initialValue: AutomationEditorDraft(task: task))
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("galaxyssi.automation.editor_title", "Proactive Task"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          Button {
            save()
          } label: {
            Image(systemName: "checkmark")
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.galaxySSIAccent)
          }
          .accessibilityLabel(t("galaxyssi.common.save", "Save"))
        }
      )

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          AutomationHeroCard(
            title: draft.name.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank(t("galaxyssi.automation.new_task", "New proactive task")),
            subtitle: t("galaxyssi.automation.proactive_subtitle", "Durable Cron, goal checkpoint, webhook, Agent, team, workflow, and phone-tool execution"),
            icon: "clock",
            tint: .orange,
            metrics: [
              AutomationMetric(value: triggerLabel(draft.triggerKind), label: t("galaxyssi.automation.trigger", "Trigger")),
              AutomationMetric(value: actionLabel(draft.actionKind), label: t("galaxyssi.automation.action", "Action")),
              AutomationMetric(value: draft.enabled ? t("galaxyssi.status.enabled", "Enabled") : t("galaxyssi.common.off", "Off"), label: t("galaxyssi.automation.status", "Status"))
            ]
          )

          sectionTitle(t("galaxyssi.section.plan", "Plan"))
          AutomationTextInputRow(
            title: t("galaxyssi.automation.name", "Name"),
            icon: "textformat",
            tint: .orange,
            text: $draft.name
          )
          AutomationPickerRow(
            title: t("galaxyssi.automation.trigger", "Trigger"),
            icon: "clock",
            tint: .blue,
            selection: $draft.triggerKind,
            values: AgentProactiveTriggerKind.allCases,
            label: triggerLabel
          )
          triggerFields

          sectionTitle(t("galaxyssi.automation.action", "Action"))
          AutomationPickerRow(
            title: t("galaxyssi.automation.action", "Action"),
            icon: "cpu",
            tint: .galaxySSIAccent,
            selection: $draft.actionKind,
            values: AgentProactiveActionKind.allCases,
            label: actionLabel
          )
          if draft.actionKind == .subagentTeam {
            AutomationTextEditorRow(
              title: t("galaxyssi.automation.team", "Agent team"),
              subtitle: t("galaxyssi.automation.team_hint", "One member per line: lead:codex, observer:hermes, verifier:claude"),
              icon: "person.3",
              tint: .blue,
              text: $draft.teamText,
              minHeight: 96
            )
          } else {
            if draft.actionKind == .workflow {
              WorkflowTargetPickerRow(targetId: $draft.targetId, language: interfaceLanguage)
            } else {
              AutomationTextInputRow(
                title: t("galaxyssi.automation.target", "Target"),
                icon: actionIcon(draft.actionKind),
                tint: .galaxySSIAccent,
                text: $draft.targetId
              )
            }
          }
          if draft.actionKind != .workflow {
            AutomationTextEditorRow(
              title: t("galaxyssi.automation.prompt", "Goal or instructions"),
              subtitle: "",
              icon: "paperplane",
              tint: .orange,
              text: $draft.prompt,
              minHeight: 96
            )
          }
          if draft.actionKind == .nativeTool {
            AutomationTextEditorRow(
              title: t("galaxyssi.automation.arguments", "Tool arguments"),
              subtitle: "{}",
              icon: "curlybraces",
              tint: .blue,
              text: $draft.argumentsJson,
              minHeight: 90
            )
          }
          AutomationPickerRow(
            title: t("galaxyssi.automation.delivery", "Delivery"),
            icon: "tray.and.arrow.down",
            tint: .galaxySSIAccent,
            selection: $draft.deliveryMode,
            values: ["store", "notify", "mobile"],
            label: deliveryLabel
          )

          sectionTitle(t("galaxyssi.automation.safety", "Safety"))
          AutomationTextInputRow(
            title: t("galaxyssi.automation.retry", "Maximum attempts"),
            icon: "arrow.clockwise",
            tint: .orange,
            text: $draft.maxAttempts,
            keyboardType: .numberPad
          )
          AutomationTextInputRow(
            title: t("galaxyssi.automation.concurrency", "Maximum concurrency"),
            icon: "person.2",
            tint: .blue,
            text: $draft.maxConcurrency,
            keyboardType: .numberPad
          )
          AutomationPickerRow(
            title: t("galaxyssi.automation.network", "Network policy"),
            icon: "network",
            tint: .galaxySSIAccent,
            selection: $draft.network,
            values: ["any", "unmetered", "offline"],
            label: networkLabel
          )
          AutomationSwitchRow(
            title: t("galaxyssi.automation.charging", "Run only while charging"),
            subtitle: t("galaxyssi.automation.proactive_subtitle", "Durable Cron, goal checkpoint, webhook, Agent, team, workflow, and phone-tool execution"),
            icon: "bolt.fill",
            tint: .orange,
            isOn: $draft.requiresCharging
          )
          AutomationSwitchRow(
            title: t("galaxyssi.automation.enabled", "Task enabled"),
            subtitle: t("galaxyssi.automation.save_subtitle", "Validate, encrypt, and schedule this task"),
            icon: "power",
            tint: .galaxySSIAccent,
            isOn: $draft.enabled
          )

          sectionTitle(t("galaxyssi.section.actions", "Actions"))
          AutomationActionRow(
            title: t("galaxyssi.common.save", "Save"),
            subtitle: t("galaxyssi.automation.save_subtitle", "Validate, encrypt, and schedule this task"),
            icon: "square.and.arrow.down",
            tint: .galaxySSIAccent,
            badge: t("galaxyssi.common.save", "Save"),
            action: save
          )
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .alert(t("galaxyssi.automation.invalid", "The proactive task is invalid"), isPresented: Binding(
      get: { !errorMessage.isEmpty },
      set: { if !$0 { errorMessage = "" } }
    )) {
      Button(t("galaxyssi.common.ok", "OK"), role: .cancel) {}
    } message: {
      Text(errorMessage)
    }
  }

  @ViewBuilder
  private var triggerFields: some View {
    switch draft.triggerKind {
    case .manual:
      EmptyView()
    case .cron:
      AutomationTextInputRow(
        title: t("galaxyssi.automation.schedule", "Schedule"),
        subtitle: t("galaxyssi.automation.cron_hint", "Five fields: minute hour day month weekday"),
        icon: "calendar",
        tint: .blue,
        text: $draft.cron
      )
      AutomationTextInputRow(
        title: t("galaxyssi.automation.time_zone", "Time zone"),
        icon: "globe",
        tint: .blue,
        text: $draft.timeZone
      )
    case .interval, .goalCheckpoint:
      AutomationTextInputRow(
        title: t("galaxyssi.automation.schedule", "Schedule"),
        subtitle: t("galaxyssi.automation.seconds_hint", "Seconds between runs"),
        icon: "timer",
        tint: .blue,
        text: $draft.intervalSeconds,
        keyboardType: .numberPad
      )
      if draft.triggerKind == .goalCheckpoint {
        AutomationTextInputRow(
          title: t("galaxyssi.automation.goal_id", "Goal ID"),
          icon: "target",
          tint: .orange,
          text: $draft.goalId
        )
      }
    case .webhook:
      AutomationTextInputRow(
        title: t("galaxyssi.automation.schedule", "Schedule"),
        subtitle: t("galaxyssi.automation.webhook_hint", "Only events relayed by a paired Desktop are accepted"),
        icon: "link",
        tint: .blue,
        text: $draft.webhookId
      )
    }
  }

  private func save() {
    do {
      _ = try store.saveAutomationTask(draft.makeTask())
      presentationMode.wrappedValue.dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func triggerLabel(_ kind: AgentProactiveTriggerKind) -> String {
    GalaxySSIAutomationLabels.trigger(kind, language: interfaceLanguage)
  }

  private func actionLabel(_ kind: AgentProactiveActionKind) -> String {
    GalaxySSIAutomationLabels.action(kind, language: interfaceLanguage)
  }

  private func actionIcon(_ kind: AgentProactiveActionKind) -> String {
    switch kind {
    case .agent, .subagentTeam: return "cpu"
    case .workflow: return "clock"
    case .nativeTool: return "iphone"
    }
  }

  private func deliveryLabel(_ value: String) -> String {
    GalaxySSIAutomationLabels.delivery(value, language: interfaceLanguage)
  }

  private func networkLabel(_ value: String) -> String {
    GalaxySSIAutomationLabels.network(value, language: interfaceLanguage)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
