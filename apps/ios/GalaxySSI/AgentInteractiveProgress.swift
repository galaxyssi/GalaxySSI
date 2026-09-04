import Foundation

enum AgentInteractiveProgressStepState: String, Codable, Equatable {
  case pending
  case active
  case completed
  case failed
}

struct AgentInteractiveProgressStep: Identifiable, Equatable {
  var id: String
  var text: String
  var state: AgentInteractiveProgressStepState
}

struct AgentInteractiveProgressPresentation: Equatable {
  var visible: Bool
  var summary: String
  var steps: [AgentInteractiveProgressStep]
  var currentStep: Int
  var totalSteps: Int
  var completedSteps: Int
  var running: Bool
  var agentLabel: String
  var recentActivity: [String]

  var counter: String {
    "\(currentStep)/\(totalSteps)"
  }

  static let hidden = AgentInteractiveProgressPresentation(
    visible: false,
    summary: "",
    steps: [],
    currentStep: 0,
    totalSteps: 0,
    completedSteps: 0,
    running: false,
    agentLabel: "",
    recentActivity: []
  )
}

enum AgentInteractiveProgressPolicy {
  static func project(
    task: AgentTaskRecord,
    fallbackSteps: [String]
  ) -> AgentInteractiveProgressPresentation {
    let actions = orderedActions(task)
    let declaredActionCount = max(task.planContext?.actionCount ?? 0, actions.count)
    let activity = task.executionLog
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let declaredPlan: [String]?
    if activity.count == 1 {
      let lines = splitPlanText(activity[0])
      declaredPlan = lines.count >= 2 ? lines : nil
    } else {
      declaredPlan = nil
    }
    let narration = unique(
      activity.flatMap(splitPlanText)
    )
    let supervisedProject = task.planContext?.plannerProfile
      .localizedCaseInsensitiveContains("supervised") == true
    guard isComplex(
      task: task,
      declaredActionCount: declaredActionCount,
      narrationCount: narration.count,
      supervisedProject: supervisedProject,
      hasFallback: fallbackSteps.count >= 2
    ) else {
      return .hidden
    }

    let terminal = terminalPhases.contains(task.phase)
    let steps: [AgentInteractiveProgressStep]
    let usingActions = actions.count >= 2 || (supervisedProject && !actions.isEmpty)
    let usingNarration = !usingActions && narration.count >= 2
    let usingFallback = !usingActions && !usingNarration
    if usingActions {
      steps = actions.map { action in
        AgentInteractiveProgressStep(
          id: action.id.ifBlank(normalizedIdentity(action.description)),
          text: action.description.trimmingCharacters(in: .whitespacesAndNewlines),
          state: state(for: action.status)
        )
      }
    } else if usingNarration {
      steps = narration.enumerated().map { index, description in
        AgentInteractiveProgressStep(
          id: "narration-\(index)-\(normalizedIdentity(description))",
          text: description,
          state: narrationState(
            index: index,
            lastIndex: narration.count - 1,
            terminal: terminal,
            failed: failedPhases.contains(task.phase),
            declaredPlan: declaredPlan != nil
          )
        )
      }
    } else {
      let descriptions = fallbackSteps
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard descriptions.count >= 2 else { return .hidden }
      let activeIndex = terminal ? max(descriptions.count - 1, 0) : 0
      steps = descriptions.enumerated().map { index, description in
        AgentInteractiveProgressStep(
          id: "fallback-\(index)",
          text: description,
          state: fallbackState(
            index: index,
            activeIndex: activeIndex,
            phase: task.phase,
            terminal: terminal
          )
        )
      }
    }

    guard !steps.isEmpty else { return .hidden }
    let currentIndex = resolvedCurrentIndex(in: steps)
    let activeAction = actions.first { activeActionStatuses.contains($0.status) }
    let pendingAction = actions.first { pendingActionStatuses.contains($0.status) }
    let summary = activeAction?.description
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(
        ((declaredPlan != nil || usingFallback) && !terminal)
          ? steps[currentIndex].text
          : narration.last ?? ""
      )
      .ifBlank(pendingAction?.description ?? "")
      .ifBlank(steps[currentIndex].text)
    let agentLabel = task.targetTitle
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(task.planContext?.routeTargetTitle ?? "")
      .ifBlank(task.planContext?.selectedAgentOrModel ?? "")

    return AgentInteractiveProgressPresentation(
      visible: true,
      summary: summary,
      steps: steps,
      currentStep: currentIndex + 1,
      totalSteps: steps.count,
      completedSteps: steps.filter { $0.state == .completed }.count,
      running: !terminal,
      agentLabel: agentLabel,
      recentActivity: Array(narration.suffix(3))
    )
  }

  private static func orderedActions(_ task: AgentTaskRecord) -> [AgentAction] {
    var actions: [AgentAction] = []
    var indices: [String: Int] = [:]

    func append(_ action: AgentAction?) {
      guard let action else { return }
      let description = action.description.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !description.isEmpty else { return }
      let key = action.id.ifBlank(normalizedIdentity(description))
      if let index = indices[key] {
        actions[index] = action
      } else {
        indices[key] = actions.count
        actions.append(action)
      }
    }

    append(task.lastCompletedNativeAction)
    task.pendingActions.forEach { append($0) }
    append(task.pendingAction)
    return actions
  }

  private static func isComplex(
    task: AgentTaskRecord,
    declaredActionCount: Int,
    narrationCount: Int,
    supervisedProject: Bool,
    hasFallback: Bool
  ) -> Bool {
    let requirements = AgentTaskRequirementAnalyzer.analyze(task.goal)
    let intent = AgentTaskIntentClassifier.classify(goal: task.goal).intent
    return supervisedProject ||
      declaredActionCount >= 2 ||
      (task.planContext?.toolGraphDepth ?? 0) >= 2 ||
      requirements.complexReasoning ||
      (immediateComplexIntents.contains(intent) && hasFallback) ||
      (complexIntents.contains(intent) && (declaredActionCount > 0 || narrationCount >= 2)) ||
      narrationCount >= 3
  }

  private static func resolvedCurrentIndex(
    in steps: [AgentInteractiveProgressStep]
  ) -> Int {
    for state in [
      AgentInteractiveProgressStepState.active,
      .failed,
      .pending
    ] {
      if let index = steps.firstIndex(where: { $0.state == state }) {
        return index
      }
    }
    return max(steps.count - 1, 0)
  }

  private static func fallbackState(
    index: Int,
    activeIndex: Int,
    phase: AgentPhase,
    terminal: Bool
  ) -> AgentInteractiveProgressStepState {
    if phase == .completed { return .completed }
    if terminal {
      if index < activeIndex { return .completed }
      if index == activeIndex { return .failed }
      return .pending
    }
    if index < activeIndex { return .completed }
    if index == activeIndex { return .active }
    return .pending
  }

  private static func narrationState(
    index: Int,
    lastIndex: Int,
    terminal: Bool,
    failed: Bool,
    declaredPlan: Bool
  ) -> AgentInteractiveProgressStepState {
    if terminal && failed && index == lastIndex { return .failed }
    if terminal { return .completed }
    if declaredPlan { return index == 0 ? .active : .pending }
    if index < lastIndex { return .completed }
    return .active
  }

  private static func state(for status: AgentActionStatus) -> AgentInteractiveProgressStepState {
    switch status {
    case .completed:
      return .completed
    case .running, .waitingResponse:
      return .active
    case .failed, .blocked, .rolledBack:
      return .failed
    case .proposed, .pendingConfirmation:
      return .pending
    }
  }

  private static func normalizedIdentity(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .lowercased()
  }

  private static func splitPlanText(_ value: String) -> [String] {
    let lines = value
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let listed = lines.compactMap { line -> String? in
      guard let range = line.range(
        of: #"^(?:[-*\u2022]|\d+[.)])\s+(.+)$"#,
        options: .regularExpression
      ) else {
        return nil
      }
      let matched = String(line[range])
      return matched.replacingOccurrences(
        of: #"^(?:[-*\u2022]|\d+[.)])\s+"#,
        with: "",
        options: .regularExpression
      )
    }
    return listed.count >= 2 ? listed : [value.trimmingCharacters(in: .whitespacesAndNewlines)]
  }

  private static func unique(_ values: [String]) -> [String] {
    var identities = Set<String>()
    return values.filter { value in
      let identity = normalizedIdentity(value)
      return !identity.isEmpty && identities.insert(identity).inserted
    }
  }

  private static let complexIntents: [AgentTaskIntent] = [
    .code,
    .phoneControl,
    .desktopControl,
    .research,
    .file,
    .automation
  ]
  private static let immediateComplexIntents: [AgentTaskIntent] = [
    .code,
    .desktopControl,
    .automation
  ]
  private static let activeActionStatuses: [AgentActionStatus] = [
    .running,
    .waitingResponse
  ]
  private static let pendingActionStatuses: [AgentActionStatus] = [
    .proposed,
    .pendingConfirmation
  ]
  private static let terminalPhases: [AgentPhase] = [
    .completed,
    .failed,
    .cancelled,
    .blocked
  ]
  private static let failedPhases: [AgentPhase] = [
    .failed,
    .cancelled,
    .blocked
  ]
}
