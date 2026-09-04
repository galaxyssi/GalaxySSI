import SwiftUI

struct GalaxySSISelfEvolutionControlView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @EnvironmentObject private var store: GalaxySSIStore
  @State private var tasks: [AgentIOSSelfEvolutionTask] = []
  @State private var statusText = ""
  @State private var isShowingCreateTask = false

  private let taskStore = AgentIOSFileSelfEvolutionTaskStore()
  private let provider = AgentIOSDefaultSelfEvolutionProvider()

  private var runtimeAvailability: AgentNativeToolAvailability {
    provider.availability(operation: .candidatePrepare)
  }

  private var runtimeReady: Bool {
    runtimeAvailability.status == .available
  }

  private var desktopExecutors: [ServerLink] {
    store.serverLinks.filter { $0.paired && $0.fullDesktopExecutor }
  }

  private var health: AgentIOSSelfEvolutionHealth {
    AgentIOSSelfEvolutionHealthAnalyzer.summarize(tasks: tasks, nowMillis: Self.nowMillis())
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_evolution_title", "Self evolution"),
        leading: { GalaxySSIBackButton() },
        trailing: {
          GalaxySSIAndroidIconButton(systemName: "arrow.clockwise", action: refresh)
        }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          hero
          runtimeBanner
          if !statusText.isEmpty {
            GalaxySSISecurityStatusRow(
              title: t("cc_evolution_status_title_ios", "Self evolution status"),
              subtitle: statusText,
              systemImage: "info.circle",
              tint: .blue,
              badge: t("common_view", "View")
            )
          }
          pipelineSection
          recentSection
          desktopSection
          footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: refresh)
    .sheet(isPresented: $isShowingCreateTask) {
      GalaxySSISelfEvolutionCreateTaskSheet(taskStore: taskStore) { task in
        tasks = (try? taskStore.list(limit: 100)) ?? [task]
        statusText = String(format: t("cc_evolution_created_ios", "Created %@"), task.taskId)
        isShowingCreateTask = false
      }
      .galaxySSIInterfaceLanguage(interfaceLanguage)
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 12) {
      GalaxySSISecurityHeroView(
        title: t("cc_evolution_hero_title", "Safe self evolution"),
        subtitle: t("cc_evolution_hero_subtitle", "iOS and Desktop can modify, build, test, and roll back their own isolated candidates"),
        systemImage: "arrow.triangle.2.circlepath",
        tint: runtimeReady ? .galaxySSIAccent : .orange,
        badge: runtimeReady
          ? t("cc_evolution_local_ready", "Local executor ready")
          : t("cc_evolution_runtime_needed", "Runtime setup required")
      )
      HStack(spacing: 8) {
        GalaxySSISelfEvolutionMetricCard(
          value: "\(health.activeTasks)",
          title: t("cc_evolution_metric_active", "Active"),
          systemImage: "play.circle",
          tint: .blue
        )
        GalaxySSISelfEvolutionMetricCard(
          value: "\(health.waitingReview)",
          title: t("cc_evolution_metric_review", "Review"),
          systemImage: "checkmark.seal",
          tint: .purple
        )
        GalaxySSISelfEvolutionMetricCard(
          value: "\(health.attentionTasks)",
          title: t("cc_evolution_metric_attention", "Attention"),
          systemImage: "exclamationmark.triangle",
          tint: health.attentionTasks > 0 ? .orange : .galaxySSITextSecondary
        )
      }
    }
  }

  @ViewBuilder
  private var runtimeBanner: some View {
    if runtimeReady {
      GalaxySSISecurityActionRow(
        title: t("cc_evolution_banner_ready", "Isolated iOS builds are available"),
        subtitle: t("cc_evolution_banner_ready_subtitle", "Source changes run only inside a disposable runtime workspace and never overwrite the installed app"),
        systemImage: "checkmark.shield",
        tint: .galaxySSIAccent,
        badge: t("cc_evolution_new_task", "New evolution task")
      ) {
        isShowingCreateTask = true
      }
    } else {
      GalaxySSISecurityNavigationRow(
        title: t("cc_evolution_banner_setup", "Complete the local development runtime"),
        subtitle: t("cc_evolution_banner_setup_subtitle_ios", "A signed iOS self-evolution runtime is required for complete on-device builds"),
        systemImage: "checkmark.shield",
        tint: .orange,
        badge: t("status_needs_setup", "Needs setup")
      ) {
        GalaxySSIOnDeviceRuntimeView()
      }
    }
  }

  private var pipelineSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_evolution_section_pipeline", "Evolution pipeline"))
      GalaxySSISecurityActionRow(
        title: t("cc_evolution_new_task", "New evolution task"),
        subtitle: t("cc_evolution_new_task_subtitle", "Declare the problem, source scope, and acceptance criteria"),
        systemImage: "scope",
        tint: .purple,
        badge: "+"
      ) {
        isShowingCreateTask = true
      }
      GalaxySSISecurityNavigationRow(
        title: t("cc_evolution_local_runtime", "iOS local executor"),
        subtitle: localizedAvailabilityMessage(
          key: "cc_evolution_local_runtime_subtitle_ios",
          fallback: "Isolated source checkout, patching, app build, tests, and rollback"
        ),
        systemImage: "terminal",
        tint: runtimeReady ? .galaxySSIAccent : .orange,
        badge: runtimeReady ? t("cc_status_ready", "Ready") : t("status_needs_setup", "Needs setup")
      ) {
        GalaxySSIOnDeviceRuntimeView()
      }
      GalaxySSISecurityStatusRow(
        title: t("cc_evolution_desktop_executor", "Desktop executor"),
        subtitle: t("cc_evolution_desktop_executor_subtitle", "Run the same isolated edit, build, test, and rollback loop on an authorized computer"),
        systemImage: "desktopcomputer",
        tint: desktopExecutors.isEmpty ? .galaxySSITextSecondary : .galaxySSIAccent,
        badge: "\(desktopExecutors.count)"
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_evolution_quality_gates", "Quality gates"),
        subtitle: t("cc_evolution_quality_gates_subtitle", "Scope check, source validation, unit tests, and product build"),
        systemImage: "checkmark.shield",
        tint: .blue,
        badge: t("cc_evolution_immutable", "Required")
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_evolution_health", "Evolution health"),
        subtitle: String(
          format: t("cc_evolution_health_subtitle", "%d%% gates passed - %d retries - %d stale"),
          health.gatePassPercent,
          health.retries,
          health.staleTasks
        ),
        systemImage: "waveform.path.ecg",
        tint: health.attentionTasks == 0 ? .galaxySSIAccent : .orange,
        badge: health.attentionTasks == 0
          ? t("cc_evolution_health_good", "Healthy")
          : t("cc_evolution_health_attention", "Needs attention")
      )
      GalaxySSISecurityStatusRow(
        title: t("cc_evolution_rollback", "Candidate rollback"),
        subtitle: t("cc_evolution_rollback_subtitle", "Discard a failed candidate without changing the installed stable version"),
        systemImage: "arrow.uturn.backward",
        tint: .orange,
        badge: t("cc_status_ready", "Ready")
      )
    }
  }

  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_evolution_section_recent", "Recent candidates"))
      if tasks.isEmpty {
        GalaxySSISecurityActionRow(
          title: t("cc_evolution_empty_title", "No evolution tasks"),
          subtitle: t("cc_evolution_empty_subtitle", "Create a scoped task or ask the Agent to improve GalaxySSI"),
          systemImage: "clock.arrow.circlepath",
          tint: .galaxySSITextSecondary,
          badge: "+"
        ) {
          isShowingCreateTask = true
        }
      } else {
        ForEach(Array(tasks.prefix(8))) { task in
          NavigationLink(destination: GalaxySSISelfEvolutionTaskDetailView(taskId: task.taskId)) {
            GalaxySSISelfEvolutionPlainRow(
              title: task.problem,
              subtitle: String(
                format: t("cc_evolution_task_summary", "Attempt %d/%d - %@"),
                task.attempts.count,
                task.maxAttempts,
                statusLabel(task.status)
              ),
              systemImage: "clock.arrow.circlepath",
              tint: statusTint(task.status),
              badge: statusLabel(task.status),
              showsDisclosure: true
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private var desktopSection: some View {
    if !desktopExecutors.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("cc_evolution_section_desktop", "Desktop candidates"))
        ForEach(desktopExecutors) { link in
          GalaxySSISecurityStatusRow(
            title: link.desktopName.ifBlank(link.desktopId),
            subtitle: t("cc_evolution_remote_candidate_ready", "Desktop evolution candidate sync is ready"),
            systemImage: "desktopcomputer",
            tint: .galaxySSIAccent,
            badge: t("cc_evolution_desktop_executor", "Desktop executor")
          )
        }
      }
    }
  }

  private var footer: some View {
    Text(t("cc_evolution_footer", "Candidates remain isolated until every required gate passes and you explicitly approve publication or installation."))
      .font(.system(size: 12))
      .foregroundColor(.galaxySSITextSecondary)
      .padding(.horizontal, 4)
      .padding(.top, 2)
  }

  private func refresh() {
    tasks = (try? taskStore.list(limit: 100)) ?? []
    statusText = ""
  }

  private func statusLabel(_ status: AgentIOSSelfEvolutionTaskStatus) -> String {
    GalaxySSISelfEvolutionText.statusLabel(status, language: interfaceLanguage)
  }

  private func statusTint(_ status: AgentIOSSelfEvolutionTaskStatus) -> Color {
    GalaxySSISelfEvolutionText.statusTint(status)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func localizedAvailabilityMessage(key: String, fallback: String) -> String {
    let localized = t(key, fallback)
    return interfaceLanguage == LanguagePolicySettings.zhCN ? localized : runtimeAvailability.reason.ifBlank(localized)
  }

  private static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

struct GalaxySSISelfEvolutionTaskDetailView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @State private var task: AgentIOSSelfEvolutionTask?
  @State private var statusText = ""

  var taskId: String
  private let taskStore = AgentIOSFileSelfEvolutionTaskStore()
  private let provider = AgentIOSDefaultSelfEvolutionProvider()

  private var runtimeAvailability: AgentNativeToolAvailability {
    provider.availability(operation: .candidatePrepare)
  }

  var body: some View {
    VStack(spacing: 0) {
      GalaxySSITopBar(
        title: t("cc_evolution_title", "Self evolution"),
        leading: { GalaxySSIBackButton() },
        trailing: { Color.clear }
      )
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let task = task {
            GalaxySSISecurityHeroView(
              title: task.problem,
              subtitle: String(
                format: t("cc_evolution_task_summary", "Attempt %d/%d - %@"),
                task.attempts.count,
                task.maxAttempts,
                statusLabel(task.status)
              ),
              systemImage: "clock.arrow.circlepath",
              tint: statusTint(task.status),
              badge: statusLabel(task.status)
            )
            if !statusText.isEmpty {
              GalaxySSISecurityStatusRow(
                title: t("cc_evolution_status_title_ios", "Self evolution status"),
                subtitle: statusText,
                systemImage: "info.circle",
                tint: .blue,
                badge: t("common_view", "View")
              )
            }
            taskSections(task)
          } else {
            GalaxySSISecurityStatusRow(
              title: t("cc_evolution_task_missing", "Evolution task was not found"),
              subtitle: taskId,
              systemImage: "exclamationmark.triangle",
              tint: .orange,
              badge: t("cc_evolution_health_attention", "Needs attention")
            )
          }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 18)
      }
    }
    .background(Color.galaxySSIPageBackground.ignoresSafeArea())
    .navigationBarHidden(true)
    .onAppear(perform: reload)
  }

  private func taskSections(_ task: AgentIOSSelfEvolutionTask) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("cc_evolution_section_pipeline", "Evolution pipeline"))
        GalaxySSISecurityStatusRow(
          title: t("cc_evolution_problem_hint", "Problem to solve"),
          subtitle: task.problem,
          systemImage: "scope",
          tint: .purple,
          badge: task.risk.rawValue
        )
        GalaxySSISecurityStatusRow(
          title: t("cc_evolution_scope_hint", "Allowed source paths, one per line"),
          subtitle: task.scope.joined(separator: "\n"),
          systemImage: "folder",
          tint: .blue,
          badge: "\(task.scope.count)",
          monospacedSubtitle: true
        )
        GalaxySSISecurityStatusRow(
          title: t("cc_evolution_acceptance_hint", "Acceptance criteria, one per line"),
          subtitle: task.acceptance.joined(separator: "\n"),
          systemImage: "checklist",
          tint: .galaxySSIAccent,
          badge: "\(task.acceptance.count)",
          monospacedSubtitle: true
        )
      }
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("cc_evolution_quality_gates", "Quality gates"))
        if let latest = task.attempts.last, !latest.gates.isEmpty {
          ForEach(latest.gates) { gate in
            GalaxySSISecurityStatusRow(
              title: gate.id,
              subtitle: gate.summary.ifBlank("\(gate.durationMillis)ms / exit \(gate.exitCode)"),
              systemImage: "checkmark.shield",
              tint: gate.status == .passed ? .galaxySSIAccent : (gate.status == .failed ? .orange : .blue),
              badge: gate.status.rawValue
            )
          }
        } else {
          GalaxySSISecurityStatusRow(
            title: t("cc_evolution_no_gates", "No quality gates have run yet"),
            subtitle: t("cc_evolution_quality_gates_subtitle", "Scope check, source validation, unit tests, and product build"),
            systemImage: "checkmark.shield",
            tint: .galaxySSITextSecondary,
            badge: t("cc_evolution_immutable", "Required")
          )
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        GalaxySSISecuritySectionTitle(title: t("cc_evolution_section_recent", "Recent candidates"))
        if task.attempts.isEmpty {
          GalaxySSISecurityStatusRow(
            title: t("cc_evolution_empty_title", "No evolution tasks"),
            subtitle: t("cc_evolution_empty_subtitle", "Create a scoped task or ask the Agent to improve GalaxySSI"),
            systemImage: "clock.arrow.circlepath",
            tint: .galaxySSITextSecondary,
            badge: ""
          )
        } else {
          ForEach(Array(task.attempts.reversed().prefix(5))) { attempt in
            GalaxySSISecurityStatusRow(
              title: String(format: t("cc_evolution_attempt_title_ios", "Attempt %d"), attempt.number),
              subtitle: attempt.failureSummary.ifBlank(attempt.changedFiles.joined(separator: "\n").ifBlank(attempt.branch)),
              systemImage: "hammer",
              tint: statusTint(attempt.status),
              badge: statusLabel(attempt.status),
              monospacedSubtitle: true
            )
          }
        }
      }
      if !task.lastError.isEmpty {
        GalaxySSISecurityStatusRow(
          title: t("cc_evolution_health_attention", "Needs attention"),
          subtitle: task.lastError,
          systemImage: "exclamationmark.triangle",
          tint: .orange,
          badge: task.lastErrorCode.ifBlank(t("cc_evolution_status_failed", "Failed"))
        )
      }
      actionRows(task)
    }
  }

  @ViewBuilder
  private func actionRows(_ task: AgentIOSSelfEvolutionTask) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      GalaxySSISecuritySectionTitle(title: t("cc_evolution_section_actions_ios", "Actions"))
      if [.proposed, .blocked].contains(task.status) {
        GalaxySSISecurityActionRow(
          title: t("cc_evolution_prepare", "Prepare candidate"),
          subtitle: localizedAvailabilityMessage(
            key: "cc_evolution_preparing_notice",
            fallback: "Preparing an isolated local candidate"
          ),
          systemImage: "play.circle",
          tint: runtimeAvailability.status == .available ? .galaxySSIAccent : .orange,
          badge: runtimeAvailability.status == .available ? t("cc_status_ready", "Ready") : t("status_needs_setup", "Needs setup")
        ) {
          statusText = localizedAvailabilityMessage(
            key: "cc_evolution_prepare_failed",
            fallback: "Could not prepare the local candidate"
          )
        }
      }
      if ![.cancelled, .rolledBack, .published, .completed].contains(task.status) {
        GalaxySSISecurityActionRow(
          title: t("cc_evolution_discard", "Discard"),
          subtitle: t("cc_evolution_rollback_subtitle", "Discard a failed candidate without changing the installed stable version"),
          systemImage: "arrow.uturn.backward",
          tint: .orange,
          badge: t("cc_evolution_status_rolled_back", "Rolled back")
        ) {
          rollback(task)
        }
      }
    }
  }

  private func rollback(_ task: AgentIOSSelfEvolutionTask) {
    var next = task
    next.status = .rolledBack
    next.updatedAtMillis = Self.nowMillis()
    next.lastError = ""
    next.lastErrorCode = ""
    do {
      try taskStore.save(next)
      self.task = next
      statusText = t("cc_evolution_status_rolled_back", "Rolled back")
    } catch {
      statusText = error.localizedDescription.ifBlank(t("cc_evolution_prepare_failed", "Could not prepare the local candidate"))
    }
  }

  private func reload() {
    task = try? taskStore.get(taskId)
  }

  private func statusLabel(_ status: AgentIOSSelfEvolutionTaskStatus) -> String {
    GalaxySSISelfEvolutionText.statusLabel(status, language: interfaceLanguage)
  }

  private func statusTint(_ status: AgentIOSSelfEvolutionTaskStatus) -> Color {
    GalaxySSISelfEvolutionText.statusTint(status)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func localizedAvailabilityMessage(key: String, fallback: String) -> String {
    let localized = t(key, fallback)
    return interfaceLanguage == LanguagePolicySettings.zhCN ? localized : runtimeAvailability.reason.ifBlank(localized)
  }

  private static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

private struct GalaxySSISelfEvolutionCreateTaskSheet: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.presentationMode) private var presentationMode
  @State private var problem = ""
  @State private var scope = "apps/ios"
  @State private var acceptance = "Focused tests pass\niOS app builds"
  @State private var errorText = ""

  var taskStore: AgentIOSSelfEvolutionTaskStoring
  var onCreate: (AgentIOSSelfEvolutionTask) -> Void

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          fieldTitle(t("cc_evolution_problem_hint", "Problem to solve"))
          TextEditor(text: $problem)
            .frame(minHeight: 92)
            .padding(8)
            .background(Color.galaxySSISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          fieldTitle(t("cc_evolution_scope_hint", "Allowed source paths, one per line"))
          TextEditor(text: $scope)
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 76)
            .padding(8)
            .background(Color.galaxySSISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          fieldTitle(t("cc_evolution_acceptance_hint", "Acceptance criteria, one per line"))
          TextEditor(text: $acceptance)
            .font(.system(size: 13, design: .monospaced))
            .frame(minHeight: 92)
            .padding(8)
            .background(Color.galaxySSISurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          if !errorText.isEmpty {
            Text(errorText)
              .font(.system(size: 12))
              .foregroundColor(.orange)
          }
          GalaxySSISecurityPrimaryButton(
            title: t("common_create", "Create"),
            systemImage: "plus",
            tint: .purple,
            action: createTask
          )
        }
        .padding(16)
      }
      .background(Color.galaxySSIPageBackground.ignoresSafeArea())
      .navigationBarTitle(t("cc_evolution_new_task", "New evolution task"), displayMode: .inline)
      .navigationBarItems(
        leading: Button(t("common_cancel", "Cancel")) {
          presentationMode.wrappedValue.dismiss()
        }
      )
    }
  }

  private func fieldTitle(_ value: String) -> some View {
    Text(value)
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(.galaxySSITextSecondary)
  }

  private func createTask() {
    let cleanProblem = problem.trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleanProblem.count >= 4 else {
      errorText = t("cc_evolution_create_failed", "Could not create the evolution task")
      return
    }
    do {
      let cleanScope = try AgentIOSSelfEvolutionPolicy.normalizedScope(splitLines(scope))
      let cleanAcceptance = splitLines(acceptance)
      guard !cleanAcceptance.isEmpty else {
        errorText = t("cc_evolution_acceptance_hint", "Acceptance criteria, one per line")
        return
      }
      let now = Self.nowMillis()
      let task = AgentIOSSelfEvolutionTask(
        taskId: AgentIOSSelfEvolutionPolicy.taskId(),
        problem: cleanProblem,
        reproductionSteps: [],
        scope: cleanScope,
        acceptance: cleanAcceptance,
        risk: .medium,
        maxAttempts: 3,
        createdAtMillis: now,
        updatedAtMillis: now
      )
      try taskStore.save(task)
      onCreate(task)
      presentationMode.wrappedValue.dismiss()
    } catch {
      errorText = error.localizedDescription.ifBlank(t("cc_evolution_create_failed", "Could not create the evolution task"))
    }
  }

  private func splitLines(_ value: String) -> [String] {
    value
      .replacingOccurrences(of: ",", with: "\n")
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private static func nowMillis() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
}

private struct GalaxySSISelfEvolutionMetricCard: View {
  var value: String
  var title: String
  var systemImage: String
  var tint: Color

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(tint)
      VStack(alignment: .leading, spacing: 2) {
        Text(value)
          .font(.system(size: 17, weight: .bold))
          .foregroundColor(.galaxySSITextPrimary)
          .lineLimit(1)
        Text(title)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.galaxySSITextSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, minHeight: 54)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

private struct GalaxySSISelfEvolutionPlainRow: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var tint: Color
  var badge: String
  var showsDisclosure: Bool

  var body: some View {
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
      Spacer(minLength: 8)
      if !badge.isEmpty {
        Text(badge)
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.horizontal, 8)
          .frame(minHeight: 28)
          .background(tint.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if showsDisclosure {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.galaxySSITextSecondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    .background(Color.galaxySSISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

enum GalaxySSISelfEvolutionText {
  static func statusLabel(_ status: AgentIOSSelfEvolutionTaskStatus, language: String) -> String {
    switch status {
    case .proposed:
      return t("cc_evolution_status_proposed", "Proposed", language)
    case .preparing:
      return t("cc_evolution_status_preparing", "Preparing", language)
    case .running:
      return t("cc_evolution_status_running", "Editing", language)
    case .validating:
      return t("cc_evolution_status_validating", "Validating", language)
    case .waitingApproval:
      return t("cc_evolution_status_review", "Ready for review", language)
    case .publishing:
      return t("cc_evolution_status_publishing", "Publishing", language)
    case .published:
      return t("cc_evolution_status_published", "PR created", language)
    case .completed:
      return t("cc_evolution_status_completed", "Completed", language)
    case .failed:
      return t("cc_evolution_status_failed", "Failed", language)
    case .blocked:
      return t("cc_evolution_status_blocked", "Blocked", language)
    case .cancelled:
      return t("cc_evolution_status_cancelled", "Cancelled", language)
    case .rolledBack:
      return t("cc_evolution_status_rolled_back", "Rolled back", language)
    }
  }

  static func statusTint(_ status: AgentIOSSelfEvolutionTaskStatus) -> Color {
    switch status {
    case .waitingApproval, .publishing:
      return .purple
    case .preparing, .running, .validating:
      return .blue
    case .failed, .blocked:
      return .orange
    case .published, .completed:
      return .galaxySSIAccent
    case .proposed, .cancelled, .rolledBack:
      return .galaxySSITextSecondary
    }
  }

  private static func t(_ key: String, _ fallback: String, _ language: String) -> String {
    GalaxySSILocalization.string(key, fallback: fallback, language: language)
  }
}
