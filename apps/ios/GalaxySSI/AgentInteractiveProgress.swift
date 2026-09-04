import Foundation

enum AgentInteractiveProgressStepState: String, Codable, Equatable {
  case pending
  case active
  case completed
  case superseded
  case failed
}

struct AgentInteractiveProgressStep: Identifiable, Equatable {
  var id: String
  var text: String
  var state: AgentInteractiveProgressStepState
  var actionId: String
  var planRevision: Int

  init(
    id: String,
    text: String,
    state: AgentInteractiveProgressStepState,
    actionId: String = "",
    planRevision: Int = 1
  ) {
    self.id = id
    self.text = text
    self.state = state
    self.actionId = actionId
    self.planRevision = max(planRevision, 1)
  }
}

struct AgentInteractiveProgressBatch: Identifiable, Equatable {
  var planRevision: Int
  var steps: [AgentInteractiveProgressStep]
  var current: Bool

  var id: Int { planRevision }
}

struct AgentInteractiveProgressPresentation: Equatable {
  var visible: Bool
  var summary: String
  var steps: [AgentInteractiveProgressStep]
  var batches: [AgentInteractiveProgressBatch]
  var currentStep: Int
  var totalSteps: Int
  var completedSteps: Int
  var planRevision: Int
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
    batches: [],
    currentStep: 0,
    totalSteps: 0,
    completedSteps: 0,
    planRevision: 1,
    running: false,
    agentLabel: "",
    recentActivity: []
  )
}

enum AgentInteractiveProgressPolicy {
  static func project(task: AgentTaskRecord) -> AgentInteractiveProgressPresentation {
    let plan = task.activePlan
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
    let narration = unique(activity.flatMap(splitPlanText))
    let legacyActions = orderedLegacyActions(task)
    let currentActionIds = Set((plan?.actions ?? legacyActions).map(\.id))
    let planActions = latestActions(
      plan.map { $0.actionHistory + $0.actions } ?? legacyActions
    )
      .filter { !isTaskCompleteMarker($0) }
      .filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let actionDescriptions = unique(planActions.map(\.description))
    let plannedDescriptions: [String]
    if actionDescriptions.count >= 2 {
      plannedDescriptions = actionDescriptions
    } else if narration.count >= 2 {
      plannedDescriptions = narration
    } else {
      plannedDescriptions = unique(actionDescriptions + narration)
    }
    guard isComplex(
      task: task,
      plan: plan,
      legacyActionCount: legacyActions.count,
      narrationCount: narration.count
    ), !plannedDescriptions.isEmpty else {
      return .hidden
    }

    let terminal = terminalPhases.contains(task.phase)
    let steps: [AgentInteractiveProgressStep]
    if !planActions.isEmpty {
      let checkpointRevisions = Dictionary(
        (plan?.checkpoints ?? []).map { ($0.actionId, $0.planRevision) }
      ) { _, latest in latest }
      var carriedRevision = 1
      steps = planActions.map { action in
        let inferredRevision: Int
        if currentActionIds.contains(action.id) {
          inferredRevision = plan?.revision ?? carriedRevision
        } else {
          inferredRevision = actionRevision(
            action,
            checkpointRevisions: checkpointRevisions,
            fallback: carriedRevision
          )
        }
        let revision = min(
          max(inferredRevision, 1),
          max(plan?.revision ?? inferredRevision, 1)
        )
        carriedRevision = max(carriedRevision, revision)
        let superseded = revision < (plan?.revision ?? revision)
        let actionId = action.id.ifBlank(normalizedIdentity(action.description))
        return AgentInteractiveProgressStep(
          id: "revision-\(revision)-\(actionId)",
          text: action.description.trimmingCharacters(in: .whitespacesAndNewlines),
          state: state(for: action.status, superseded: superseded),
          actionId: action.id,
          planRevision: revision
        )
      }
    } else {
      steps = plannedDescriptions.enumerated().map { index, text in
        AgentInteractiveProgressStep(
          id: "narration-\(index)-\(normalizedIdentity(text))",
          text: text,
          state: narrationState(
            index: index,
            lastIndex: plannedDescriptions.count - 1,
            terminal: terminal,
            failed: failedPhases.contains(task.phase),
            declaredPlan: declaredPlan != nil
          )
        )
      }
    }
    guard !steps.isEmpty else { return .hidden }

    let batches = progressBatches(steps, currentRevision: plan?.revision)
    guard let currentBatch = batches.first(where: \.current) ?? batches.last else {
      return .hidden
    }
    let currentIndex = resolvedCurrentIndex(in: currentBatch.steps)
    let activeAction = planActions.first { activeActionStatuses.contains($0.status) }
    let pendingAction = planActions.first { pendingActionStatuses.contains($0.status) }
    let summary = activeAction?.description
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(
        declaredPlan != nil && !terminal
          ? currentBatch.steps[currentIndex].text
          : narration.last ?? ""
      )
      .ifBlank(pendingAction?.description ?? "")
      .ifBlank(currentBatch.steps[currentIndex].text)
    let agentLabel = plan?.route.targetTitle
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .ifBlank(plan?.selectedAgentOrModel ?? "")
      .ifBlank(task.targetTitle)
      .ifBlank(task.planContext?.routeTargetTitle ?? "")

    return AgentInteractiveProgressPresentation(
      visible: true,
      summary: summary,
      steps: steps,
      batches: batches,
      currentStep: currentIndex + 1,
      totalSteps: currentBatch.steps.count,
      completedSteps: steps.filter { $0.state == .completed }.count,
      planRevision: max(plan?.revision ?? currentBatch.planRevision, 1),
      running: !terminal,
      agentLabel: agentLabel,
      recentActivity: Array(narration.suffix(2))
    )
  }

  private static func orderedLegacyActions(_ task: AgentTaskRecord) -> [AgentAction] {
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

  private static func latestActions(_ actions: [AgentAction]) -> [AgentAction] {
    guard actions.count > 1 else { return actions }
    var seen: Set<String> = []
    var retained: [AgentAction] = []
    for action in actions.reversed() where action.id.isEmpty || seen.insert(action.id).inserted {
      retained.append(action)
    }
    return Array(retained.reversed())
  }

  private static func progressBatches(
    _ steps: [AgentInteractiveProgressStep],
    currentRevision: Int?
  ) -> [AgentInteractiveProgressBatch] {
    var batches: [AgentInteractiveProgressBatch] = []
    for step in steps {
      if let index = batches.firstIndex(where: { $0.planRevision == step.planRevision }) {
        batches[index].steps.append(step)
      } else {
        batches.append(
          AgentInteractiveProgressBatch(
            planRevision: step.planRevision,
            steps: [step],
            current: false
          )
        )
      }
    }
    let selectedRevision = currentRevision ?? batches.last?.planRevision ?? 1
    for index in batches.indices {
      batches[index].current = batches[index].planRevision == selectedRevision
    }
    if !batches.contains(where: \.current), let lastIndex = batches.indices.last {
      batches[lastIndex].current = true
    }
    return batches
  }

  private static func isComplex(
    task: AgentTaskRecord,
    plan: AgentPlan?,
    legacyActionCount: Int,
    narrationCount: Int
  ) -> Bool {
    let requirements = AgentTaskRequirementAnalyzer.analyze(task.goal)
    let intent = AgentTaskIntentClassifier.classify(goal: task.goal).intent
    let currentActions = plan?.actions.filter {
      !isTaskCompleteMarker($0) &&
        !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }.count ?? legacyActionCount
    let supervised = plan?.plannerProfile.localizedCaseInsensitiveContains("supervised") == true ||
      task.planContext?.plannerProfile.localizedCaseInsensitiveContains("supervised") == true
    return supervised ||
      currentActions >= 2 ||
      requirements.complexReasoning ||
      (complexIntents.contains(intent) && (plan != nil || narrationCount >= 2)) ||
      narrationCount >= 3
  }

  private static func resolvedCurrentIndex(in steps: [AgentInteractiveProgressStep]) -> Int {
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

  private static func state(
    for status: AgentActionStatus,
    superseded: Bool
  ) -> AgentInteractiveProgressStepState {
    switch status {
    case .completed:
      return .completed
    case .running, .waitingResponse:
      return .active
    case .failed, .blocked, .rolledBack:
      return superseded ? .superseded : .failed
    case .proposed, .pendingConfirmation:
      return .pending
    }
  }

  private static func actionRevision(
    _ action: AgentAction,
    checkpointRevisions: [String: Int],
    fallback: Int
  ) -> Int {
    if let declared = action.parameters["plan_revision"].flatMap(Int.init) {
      return declared
    }
    if let checkpointRevision = checkpointRevisions[action.id] {
      return checkpointRevision
    }
    return revisionFromActionId(action.id) ?? fallback
  }

  private static func revisionFromActionId(_ id: String) -> Int? {
    let normalized = id.lowercased()
    for prefix in ["r", "sp"] where normalized.hasPrefix(prefix) {
      let remainder = normalized.dropFirst(prefix.count)
      let digits = remainder.prefix { $0.isNumber }
      if !digits.isEmpty, remainder.dropFirst(digits.count).first == "-" {
        return Int(digits)
      }
    }
    for prefix in supervisedRevisionPrefixes where normalized.hasPrefix(prefix) {
      let remainder = normalized.dropFirst(prefix.count)
      let digits = remainder.prefix { $0.isNumber }
      if !digits.isEmpty, remainder.dropFirst(digits.count).first == "-" {
        return Int(digits)
      }
    }
    return nil
  }

  private static func isTaskCompleteMarker(_ action: AgentAction) -> Bool {
    action.kind == .draftPlan &&
      action.target.caseInsensitiveCompare("task-complete") == .orderedSame
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

  private static let supervisedRevisionPrefixes = [
    "supervise-phone-project-recovery-",
    "supervise-phone-project-format-",
    "supervise-phone-project-progress-",
    "supervise-phone-project-completion-"
  ]
  private static let complexIntents: [AgentTaskIntent] = [
    .code,
    .phoneControl,
    .desktopControl,
    .research,
    .file,
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
