import SwiftUI

struct SignalASIAgentBlockedTaskCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var title: String
  var goal: String
  var subtitle: String
  var retryTitle: String
  var replanTitle: String
  var retryingTitle: String
  var isRetrying: Bool
  var onRetry: () -> Void
  var onReplan: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.octagon")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.orange)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Spacer(minLength: 0)
      }
      Text(goal)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
      Text(subtitle)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      recoveryControls
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var recoveryControls: some View {
    if usesAccessibilityDynamicType {
      VStack(spacing: 8) {
        retryControl
        replanControl
      }
    } else {
      HStack(spacing: 8) {
        retryControl
        replanControl
      }
    }
  }

  private var retryControl: some View {
    Button(action: onRetry) {
      Label(
        isRetrying ? retryingTitle : retryTitle,
        systemImage: isRetrying ? "hourglass" : "arrow.clockwise"
      )
      .font(.system(size: 13, weight: .semibold))
      .frame(maxWidth: .infinity, minHeight: 38)
    }
    .buttonStyle(.borderedProminent)
    .tint(.signalASIAccent)
    .disabled(isRetrying)
    .accessibilityIdentifier("ios.agent.task.retry")
  }

  private var replanControl: some View {
    Button(action: onReplan) {
      Label(replanTitle, systemImage: "arrow.triangle.2.circlepath")
        .font(.system(size: 13, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 38)
    }
    .buttonStyle(.bordered)
    .disabled(isRetrying)
    .accessibilityIdentifier("ios.agent.task.replan")
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }
}

struct SignalASIAgentRetryCard: View {
  var title: String
  var subtitle: String
  var retryTitle: String
  var retryingTitle: String
  var isRetrying: Bool
  var onRetry: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle")
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(.orange)
          .frame(width: 20, height: 20)
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(2)
        Spacer(minLength: 0)
      }
      Text(subtitle)
        .font(.system(size: 12))
        .foregroundColor(.signalASITextSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: onRetry) {
        Label(
          isRetrying ? retryingTitle : retryTitle,
          systemImage: isRetrying ? "hourglass" : "arrow.clockwise"
        )
        .font(.system(size: 13, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 38)
      }
      .buttonStyle(.borderedProminent)
      .tint(.signalASIAccent)
      .disabled(isRetrying)
      .accessibilityIdentifier("ios.agent.task.retry")
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.orange.opacity(0.55), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }
}

struct SignalASIAgentExecutionStatusCard: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var detailsExpanded = false
  var completed: Bool
  var duration: String = ""
  var liveDurationStartMillis: Int64 = 0
  var liveDurationFormatter: ((Int64) -> String)?
  var detailsTitle: String = ""
  var details: [String] = []
  var canResume: Bool
  var resumeTitle: String
  var canCancel: Bool
  var cancelTitle: String
  var onResume: () -> Void
  var onCancel: () -> Void
  var timelineActions: [AgentExecutionLoopTimelineAction] = []
  var timelineActionTitle: (AgentExecutionLoopTimelineAction) -> String = { $0.rawValue }
  var timelineActionIcon: (AgentExecutionLoopTimelineAction) -> String = { _ in "ellipsis" }
  var onTimelineAction: (AgentExecutionLoopTimelineAction) -> Void = { _ in }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let liveDurationFormatter, liveDurationStartMillis > 0 {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
          Text(processingSummary(liveDurationFormatter(
            max(0, Int64(context.date.timeIntervalSince1970 * 1_000) - liveDurationStartMillis)
          )))
            .font(.system(size: 13))
            .foregroundColor(.signalASITextPrimary)
            .lineLimit(1)
        }
      } else if !duration.isEmpty {
        Text(processingSummary(duration))
          .font(.system(size: 13))
          .foregroundColor(.signalASITextPrimary)
          .lineLimit(1)
      }
      if !details.isEmpty {
        Button {
          detailsExpanded.toggle()
        } label: {
          Label(
            detailsTitle.ifBlank(t("signalasi.agent.task_details", "Details")),
            systemImage: detailsExpanded ? "chevron.up" : "chevron.down"
          )
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(.signalASIInsightText)
        }
        .buttonStyle(.plain)
        if detailsExpanded {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(details.suffix(8).enumerated()), id: \.offset) { _, detail in
              HStack(alignment: .top, spacing: 6) {
                Circle()
                  .fill(Color.signalASIInsightText)
                  .frame(width: 4, height: 4)
                  .padding(.top, 5)
                Text(detail)
                  .font(.system(size: 11))
                  .foregroundColor(.signalASITextSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          .padding(.leading, 4)
        }
      }
      if canResume || canCancel || !timelineActions.isEmpty {
        taskControls
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }

  private func processingSummary(_ duration: String) -> String {
    AgentTranscriptPresentationPolicy.processedSummary(
      completed: completed,
      duration: duration,
      processingFormat: t("signalasi.agent.trace.processing", "Working for %@"),
      processedFormat: t("signalasi.agent.trace.processed", "Worked for %@")
    )
  }

  @ViewBuilder
  private var taskControls: some View {
    if usesAccessibilityDynamicType {
      VStack(spacing: 8) {
        resumeControl
        cancelControl
        timelineControl
      }
    } else {
      HStack(spacing: 8) {
        resumeControl
        cancelControl
        timelineControl
      }
    }
  }

  @ViewBuilder
  private var resumeControl: some View {
    if canResume {
      Button(action: onResume) {
        Label(resumeTitle, systemImage: "play.fill")
          .font(.system(size: 12, weight: .semibold))
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("ios.agent.task.resume")
    }
  }

  @ViewBuilder
  private var cancelControl: some View {
    if canCancel {
      Button(role: .destructive, action: onCancel) {
        Label(cancelTitle, systemImage: "xmark.circle")
          .font(.system(size: 12, weight: .semibold))
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("ios.agent.task.cancel")
    }
  }

  @ViewBuilder
  private var timelineControl: some View {
    if !timelineActions.isEmpty {
      Menu {
        ForEach(timelineActions) { action in
          Button {
            onTimelineAction(action)
          } label: {
            Label(timelineActionTitle(action), systemImage: timelineActionIcon(action))
          }
        }
      } label: {
        Label("", systemImage: "ellipsis.circle")
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 42, height: 36)
      }
      .menuStyle(.automatic)
      .accessibilityLabel(Text(t("signalasi.agent.task_control.title", "Task controls")))
      .accessibilityIdentifier("ios.agent.task.controls")
    }
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }
}

struct AgentProcessCard: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var activePhase: AgentPhase?
  var executionPaused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(t("agent_section_process", "Process"))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
      AgentProcessStepRow(
        number: 1,
        title: t("agent_step_observe", "Read current screen structure"),
        status: statusText(stepStatus(for: .observeScreen)),
        statusValue: stepStatus(for: .observeScreen)
      )
      AgentProcessStepRow(
        number: 2,
        title: t("agent_step_analyze", "Analyze user goal"),
        status: statusText(stepStatus(for: .analyzeGoal)),
        statusValue: stepStatus(for: .analyzeGoal)
      )
      AgentProcessStepRow(
        number: 3,
        title: t("agent_step_plan", "Build executable plan"),
        status: statusText(stepStatus(for: .buildPlan)),
        statusValue: stepStatus(for: .buildPlan)
      )
      AgentProcessStepRow(
        number: 4,
        title: t("agent_step_act", "Confirm before action"),
        status: statusText(stepStatus(for: .confirmAndAct)),
        statusValue: stepStatus(for: .confirmAndAct)
      )
    }
    .padding(12)
    .background(Color.signalASISurface)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func stepStatus(for kind: AgentStepKind) -> AgentStepStatus {
    if executionPaused {
      return kind == .confirmAndAct ? .current : .done
    }
    switch activePhase {
    case .some(.observing):
      return kind == .observeScreen ? .current : (kind == .confirmAndAct ? .safe : .waiting)
    case .some(.planning):
      if kind == .observeScreen { return .done }
      return kind == .analyzeGoal ? .current : (kind == .confirmAndAct ? .safe : .waiting)
    case .some(.waitingConfirmation), .some(.executing), .some(.verifying), .some(.waitingResponse), .some(.paused):
      return kind == .confirmAndAct ? .current : .done
    case .some(.completed):
      return .done
    case .some(.cancelled), .some(.blocked), .some(.failed):
      return kind == .confirmAndAct ? .safe : .done
    case .none:
      return kind == .observeScreen ? .current : (kind == .confirmAndAct ? .safe : .waiting)
    }
  }

  private func statusText(_ status: AgentStepStatus) -> String {
    switch status {
    case .current:
      return t("agent_step_status_current", "Current")
    case .done:
      return t("agent_step_status_done", "Done")
    case .waiting:
      return t("agent_step_status_waiting", "Waiting")
    case .safe:
      return t("agent_step_status_safe", "Safe")
    }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}

struct AgentProcessStepRow: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var number: Int
  var title: String
  var status: String
  var statusValue: AgentStepStatus

  private var isCurrent: Bool { statusValue == .current }
  private var isDone: Bool { statusValue == .done }
  private var tint: Color {
    switch statusValue {
    case .current, .done:
      return .signalASIAccent
    case .safe:
      return .signalASITextSecondary
    case .waiting:
      return .signalASITextSecondary
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Circle()
        .fill(isCurrent ? Color.signalASIAccent : (isDone ? Color.signalASIAccent.opacity(0.14) : Color.signalASISurface))
        .overlay(
          Circle()
            .stroke(isCurrent || isDone ? Color.signalASIAccent : Color.signalASISeparator, lineWidth: 1)
        )
        .overlay(
          Text("\(number)")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(isCurrent ? .white : tint)
        )
        .frame(width: 24, height: 24)
        .padding(.top, usesAccessibilityDynamicType ? 2 : 0)
      Text(title)
        .font(.system(size: 13))
        .foregroundColor(.signalASITextPrimary)
        .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 8)
      Text(status)
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(tint)
        .lineLimit(usesAccessibilityDynamicType ? 2 : 1)
        .multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 14)
    .frame(minHeight: usesAccessibilityDynamicType ? 64 : 50)
    .background(Color.signalASIInsightBackground)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var usesAccessibilityDynamicType: Bool {
    dynamicTypeSize.isAccessibilitySize
  }
}

struct AgentInfoCard: View {
  @Environment(\.signalASIInterfaceLanguage) private var interfaceLanguage
  var currentApp: String
  var callableTargets: Int
  var runningTasks: Int
  var memorySnapshot: AgentMemorySnapshot
  var knowledgeStats: AgentKnowledgeStats

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(t("agent_section_info", "Info"))
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.signalASITextPrimary)
      VStack(spacing: 0) {
        infoValueRow(String(format: t("agent_current_app_value", "Current app: %@"), currentApp))
        separator
        infoValueRow(String(format: t("agent_callable_targets_value", "Callable targets: %d"), callableTargets))
        separator
        infoValueRow(String(format: t("agent_running_tasks_value", "Running tasks: %d"), runningTasks))
        separator
        NavigationLink(destination: SignalASIAgentMemoryView()) {
          infoNavigationRow(
            String(format: t("agent_memory_value", "Memory: %d / conflicts: %d"), memorySnapshot.activeCount, memorySnapshot.conflicts.count),
            systemImage: "brain"
          )
        }
        .buttonStyle(.plain)
        separator
        NavigationLink(destination: SignalASIAgentKnowledgeView()) {
          infoNavigationRow(
            String(format: t("agent_knowledge_value", "Knowledge: %d items / %d sources / %d hits"), knowledgeStats.itemCount, knowledgeStats.sourceCount, 0),
            systemImage: "books.vertical"
          )
        }
        .buttonStyle(.plain)
      }
      .background(Color.signalASISurface)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .font(.system(size: 13))
    .foregroundColor(.signalASIInsightText)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.signalASIInsightBackground)
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.signalASIInsightStroke, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    .frame(maxWidth: .infinity, minHeight: 42)
    .padding(.horizontal, 14)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    SignalASILocalization.string(key, fallback: fallback, language: interfaceLanguage)
  }
}
