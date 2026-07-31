import Foundation

struct GlobalLongHorizonCycleResult: Codable, Equatable {
  var reconciledGoalCount: Int
  var queuedCheckpointCount: Int
  var nextWakeAtMillis: Int64

  init(
    reconciledGoalCount: Int,
    queuedCheckpointCount: Int,
    nextWakeAtMillis: Int64
  ) {
    self.reconciledGoalCount = max(reconciledGoalCount, 0)
    self.queuedCheckpointCount = max(queuedCheckpointCount, 0)
    self.nextWakeAtMillis = max(nextWakeAtMillis, 0)
  }
}

protocol GlobalLongHorizonRuntimeStore: AnyObject {
  func settings() -> GlobalAgentSettings
  func loadWorld() -> PersonalWorldModel
  func saveWorld(_ world: PersonalWorldModel)
  func topicGraph() -> GlobalTopicProjectGraph
  func cognitionTasks() -> [GlobalCognitionTask]
  func upsertCognitionTask(_ task: GlobalCognitionTask)
  func autonomousRuns() -> [GlobalAutonomousRun]
  func appendProactiveMessage(_ message: GlobalProactiveMessage)
}

extension GlobalLongHorizonRuntimeStore {
  func appendProactiveMessage(_ message: GlobalProactiveMessage) {}
}

final class GlobalLongHorizonCoordinator {
  private let runtimeStore: GlobalLongHorizonRuntimeStore
  private let goalStore: GlobalLongHorizonGoalStoring

  init(
    runtimeStore: GlobalLongHorizonRuntimeStore,
    goalStore: GlobalLongHorizonGoalStoring = GlobalLongHorizonGoalStore()
  ) {
    self.runtimeStore = runtimeStore
    self.goalStore = goalStore
  }

  func processDue(
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis(),
    maxGoals: Int = 4
  ) -> GlobalLongHorizonCycleResult {
    let settings = runtimeStore.settings()
    guard settings.enabled, settings.longHorizonPlanningEnabled else {
      return GlobalLongHorizonCycleResult(
        reconciledGoalCount: 0,
        queuedCheckpointCount: 0,
        nextWakeAtMillis: 0
      )
    }

    let before = goalStore.goals()
    let synchronized = GlobalLongHorizonGoalGraphPolicy.reconcile(
      goals: GlobalLongHorizonGoalGraphPolicy.assignProjects(
        goals: GlobalLongHorizonGoalPolicy.mergeWorld(
          world: runtimeStore.loadWorld(),
          current: before,
          nowMillis: nowMillis
        ),
        graph: runtimeStore.topicGraph(),
        nowMillis: nowMillis
      ),
      nowMillis: nowMillis
    )
    if synchronized != before {
      goalStore.save(synchronized, nowMillis: nowMillis)
    }

    let afterSync = goalStore.goals()
    let reconciled = GlobalLongHorizonGoalGraphPolicy.reconcile(
      goals: reconcile(goals: afterSync, nowMillis: nowMillis),
      nowMillis: nowMillis
    )
    if reconciled != afterSync {
      goalStore.save(reconciled, nowMillis: nowMillis)
    }

    let world = runtimeStore.loadWorld()
    let updatedWorld = GlobalLongHorizonGoalPolicy.applyGoalStatesToWorld(
      world: world,
      goals: reconciled,
      nowMillis: nowMillis
    )
    if updatedWorld != world {
      runtimeStore.saveWorld(updatedWorld)
    }

    ensureLifecycleMessages(goals: goalStore.goals())
    var goals = goalStore.goals()
    var queued = 0
    for goal in GlobalLongHorizonGoalPolicy.nextDue(goals: goals, nowMillis: nowMillis)
      .prefix(max(1, min(maxGoals, 12))) {
      let duplicate = runtimeStore.cognitionTasks().contains {
        $0.longHorizonGoalId == goal.id && [.queued, .running, .waitingForResource].contains($0.status)
      }
      if duplicate {
        continue
      }
      let task = checkpointTask(goal: goal, nowMillis: nowMillis)
      runtimeStore.upsertCognitionTask(task)
      goals = goals.map { candidate in
        guard candidate.id == goal.id else { return candidate }
        var updated = candidate
        updated.status = .inProgress
        updated.activeCognitionTaskId = task.id
        updated.lastCheckAtMillis = max(nowMillis, 0)
        updated.nextCheckAtMillis = max(nowMillis, 0) + candidate.checkpointIntervalMillis
        updated.updatedAtMillis = max(nowMillis, 0)
        return updated
      }
      queued += 1
    }
    if queued > 0 {
      goalStore.save(goals, nowMillis: nowMillis)
    }
    ensureLifecycleMessages(goals: goalStore.goals())

    return GlobalLongHorizonCycleResult(
      reconciledGoalCount: max(synchronized.count - before.count, 0) +
        zip(reconciled, afterSync).filter { pair in pair.0 != pair.1 }.count,
      queuedCheckpointCount: queued,
      nextWakeAtMillis: nextWakeAt(goals: goalStore.goals(), nowMillis: nowMillis)
    )
  }

  func goals() -> [GlobalLongHorizonGoal] {
    goalStore.goals()
  }

  @discardableResult
  func pause(
    goalId: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> Bool {
    goalStore.update(goalId: goalId, nowMillis: nowMillis) { goal in
      var updated = goal
      updated.status = .paused
      updated.activeCognitionTaskId = ""
      updated.activeRunId = ""
      updated.nextCheckAtMillis = 0
      updated.updatedAtMillis = max(nowMillis, 0)
      return updated
    } != nil
  }

  @discardableResult
  func resume(
    goalId: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> Bool {
    goalStore.update(goalId: goalId, nowMillis: nowMillis) { goal in
      var updated = goal
      updated.status = .active
      updated.nextCheckAtMillis = max(nowMillis, 0)
      updated.blocker = ""
      updated.updatedAtMillis = max(nowMillis, 0)
      return updated
    } != nil
  }

  private func reconcile(
    goals: [GlobalLongHorizonGoal],
    nowMillis: Int64
  ) -> [GlobalLongHorizonGoal] {
    let cognitionById = dictionaryById(runtimeStore.cognitionTasks())
    let runsById = dictionaryById(runtimeStore.autonomousRuns())
    return goals.map { goal in
      if [.completed, .paused].contains(goal.status) {
        return goal
      }
      if !goal.activeCognitionTaskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        switch cognitionById[goal.activeCognitionTaskId]?.status {
        case .some(.queued), .some(.running), .some(.waitingForResource):
          var updated = goal
          updated.status = .inProgress
          updated.updatedAtMillis = max(goal.updatedAtMillis, cognitionById[goal.activeCognitionTaskId]?.updatedAtMillis ?? 0)
          return updated
        case .some(.failed), .none:
          var updated = goal
          updated.status = .blocked
          updated.activeCognitionTaskId = ""
          updated.blocker = firstNonBlank(
            cognitionById[goal.activeCognitionTaskId]?.lastError ?? "",
            "The checkpoint cognition task was lost"
          )
          updated.nextCheckAtMillis = max(nowMillis, 0) + retryCheckpointMillis
          updated.updatedAtMillis = max(nowMillis, 0)
          return updated
        case .some(.completed):
          break
        }
      }
      let cleanRunId = goal.activeRunId.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanRunId.isEmpty else {
        return goal
      }
      switch runsById[cleanRunId]?.status {
      case .some(.queued), .some(.running), .some(.replanning), .some(.waitingForResource):
        var updated = goal
        updated.status = .inProgress
        updated.updatedAtMillis = max(goal.updatedAtMillis, runsById[cleanRunId]?.updatedAtMillis ?? 0)
        return updated
      case .some(.waitingConfirmation):
        var updated = goal
        updated.status = .waitingConfirmation
        updated.updatedAtMillis = max(goal.updatedAtMillis, runsById[cleanRunId]?.updatedAtMillis ?? 0)
        return updated
      case .some(.completed):
        guard let run = runsById[cleanRunId] else { return goal }
        let completedGoal = run.review.decision.goalState == .completed &&
          GlobalAutonomousRunPolicy.completionSupported(run.actions)
        var updated = goal
        updated.status = completedGoal ? .completed : .active
        updated.activeRunId = ""
        updated.lastProgressAtMillis = run.updatedAtMillis
        let lastCompletedResult = run.completedActions().last.map { String($0.result.prefix(2_000)) } ?? ""
        updated.progressSummary = firstNonBlank(
          run.outcomeSummary,
          lastCompletedResult
        )
        updated.nextCheckAtMillis = completedGoal ? 0 : max(nowMillis, 0) + goal.checkpointIntervalMillis
        updated.blocker = ""
        if completedGoal {
          updated.verificationSummary =
            "Completion is supported by \(run.completedActions().count) action evidence contract(s)"
          updated.verifiedAtMillis = max(nowMillis, 0)
        }
        updated.updatedAtMillis = max(nowMillis, 0)
        return updated
      case .some(.partial), .some(.failed), .some(.paused), .none:
        let run = runsById[cleanRunId]
        var updated = goal
        updated.status = .blocked
        updated.activeRunId = ""
        updated.lastProgressAtMillis = run?.updatedAtMillis ?? goal.lastProgressAtMillis
        updated.progressSummary = firstNonBlank(run?.outcomeSummary ?? "", goal.progressSummary)
        updated.blocker = firstNonBlank(run?.lastError ?? "", "The autonomous run could not complete")
        updated.nextCheckAtMillis = max(nowMillis, 0) + retryCheckpointMillis
        updated.updatedAtMillis = max(nowMillis, 0)
        return updated
      }
    }
  }

  private func checkpointTask(
    goal: GlobalLongHorizonGoal,
    nowMillis: Int64
  ) -> GlobalCognitionTask {
    var lines = ["Review progress toward this long-horizon goal: \(goal.title)"]
    if !goal.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lines.append("Original context: \(String(goal.description.prefix(1_500)))")
    }
    if !goal.progressSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lines.append("Last progress: \(String(goal.progressSummary.prefix(1_500)))")
    }
    if !goal.blocker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      lines.append("Current blocker: \(String(goal.blocker.prefix(600)))")
    }
    let conversationId = goal.sourceConversationIds.sorted().first.flatMap {
      $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
    } ?? "global-goal:\(goal.id)"
    let topic = goal.topic.trimmingCharacters(in: .whitespacesAndNewlines)
    let event = GlobalConversationEvent(
      id: "long-horizon-checkpoint:\(goal.id):\(goal.checkpointCount + 1)",
      type: .taskUpdated,
      conversationId: conversationId,
      actor: .tool,
      timestampMillis: max(nowMillis, 0),
      content: String(lines.joined(separator: "\n").prefix(12_000)),
      contentRef: "encrypted://global-agent/goal/\(goal.id)",
      conversationTitle: topic,
      topicHints: topic.isEmpty ? [] : [topic],
      metadata: [
        "long_horizon_goal_id": goal.id,
        "checkpoint_count": "\(goal.checkpointCount + 1)",
        "origin": "global_long_horizon_scheduler"
      ],
      causalEventIds: Set(goal.sourceEventIds.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    )
    let baseline = GlobalUnderstanding(
      eventId: event.id,
      topic: goal.topic,
      intent: "long_horizon_checkpoint",
      goalCandidates: [goal.title],
      taskCandidates: ["Review progress and revise the next safe actions"],
      complexity: 0.72,
      urgency: goal.priority,
      novelty: 0.35,
      uncertainty: 0.42,
      externalResearchUseful: true,
      durableFollowUpUseful: true
    )
    return GlobalCognitionTask(
      sourceEvent: event,
      baselineUnderstanding: baseline,
      longHorizonGoalId: goal.id,
      createdAtMillis: max(nowMillis, 0),
      updatedAtMillis: max(nowMillis, 0)
    )
  }

  private func nextWakeAt(goals: [GlobalLongHorizonGoal], nowMillis: Int64) -> Int64 {
    let candidates = goals
      .filter {
        [.active, .inProgress, .blocked].contains($0.status) &&
          $0.activeCognitionTaskId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
          $0.activeRunId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      .map(\.nextCheckAtMillis)
      .filter { $0 > 0 }
    guard let next = candidates.min() else { return 0 }
    return max(next, max(nowMillis, 0) + minimumWakeDelayMillis)
  }

  private func ensureLifecycleMessages(goals: [GlobalLongHorizonGoal]) {
    for message in goals.compactMap(GlobalLongHorizonLifecyclePolicy.proactiveMessage) {
      runtimeStore.appendProactiveMessage(message)
    }
  }

  private func firstNonBlank(_ first: String, _ fallback: String) -> String {
    let clean = first.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : clean
  }

  private func dictionaryById<T: Identifiable>(_ values: [T]) -> [T.ID: T] {
    var result: [T.ID: T] = [:]
    for value in values {
      result[value.id] = value
    }
    return result
  }

  private let retryCheckpointMillis: Int64 = 60 * 60 * 1_000
  private let minimumWakeDelayMillis: Int64 = 60_000
}
