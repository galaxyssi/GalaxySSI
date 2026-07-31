import Foundation

enum GlobalLongHorizonGoalPolicy {
  static func nextDue(
    goals: [GlobalLongHorizonGoal],
    nowMillis: Int64
  ) -> [GlobalLongHorizonGoal] {
    goals
      .filter { goal in
        dueStatuses.contains(goal.status) &&
          clean(goal.activeCognitionTaskId).isEmpty &&
          clean(goal.activeRunId).isEmpty &&
          goal.nextCheckAtMillis <= nowMillis
      }
      .sorted {
        if $0.priority != $1.priority { return $0.priority > $1.priority }
        return $0.nextCheckAtMillis < $1.nextCheckAtMillis
      }
  }

  static func applyGoalStatesToWorld(
    world: PersonalWorldModel,
    goals: [GlobalLongHorizonGoal],
    nowMillis: Int64 = GlobalMemoryClock.nowMillis()
  ) -> PersonalWorldModel {
    let completed = goals.filter {
      $0.status == .completed &&
        $0.confidence >= completedConfidenceThreshold &&
        $0.verifiedAtMillis > 0
    }
    guard !completed.isEmpty else { return world }

    var changed = false
    let items = world.items.map { item in
      guard item.kind == .goal, item.status != .completed else {
        return item
      }
      let match = completed.contains { goal in
        GlobalAgentText.normalize(goal.topic) == GlobalAgentText.normalize(item.topic) &&
          GlobalAgentText.overlap(
            GlobalAgentText.tokens(goal.title),
            GlobalAgentText.tokens(item.value)
          ) >= worldGoalCompletionOverlap
      }
      guard match else { return item }
      changed = true
      var copy = item
      copy.status = .completed
      copy.lastSeenAtMillis = max(nowMillis, 0)
      return copy
    }
    guard changed else { return world }
    var copy = world
    copy.items = items
    copy.updatedAtMillis = max(nowMillis, 0)
    return copy
  }

  static func completionEvidence(
    world: PersonalWorldModel,
    goal: GlobalLongHorizonGoal,
    progressSummary: String = "",
    limit: Int = 8
  ) -> [GlobalWorldItem] {
    let query = GlobalAgentText.tokens("\(goal.topic) \(goal.title) \(progressSummary)")
    let boundedLimit = min(max(limit, 1), maxCompletionEvidence)
    return world.items
      .filter { item in
        !item.evidenceEventIds.isEmpty &&
          (item.status == .completed || (item.kind == .fact && item.confidence >= factEvidenceConfidenceThreshold))
      }
      .map { item in
        (
          item,
          GlobalAgentText.overlap(
            query,
            GlobalAgentText.tokens("\(item.topic) \(item.value)")
          )
        )
      }
      .filter { $0.1 >= completionEvidenceOverlap }
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        if $0.0.confidence != $1.0.confidence { return $0.0.confidence > $1.0.confidence }
        return $0.0.lastSeenAtMillis > $1.0.lastSeenAtMillis
      }
      .prefix(boundedLimit)
      .map(\.0)
  }

  private static let dueStatuses: Set<GlobalLongHorizonGoalStatus> = [
    .active,
    .inProgress,
    .blocked
  ]
  private static let completedConfidenceThreshold = 0.65
  private static let worldGoalCompletionOverlap = 0.72
  private static let factEvidenceConfidenceThreshold = 0.75
  private static let completionEvidenceOverlap = 0.24
  private static let maxCompletionEvidence = 16

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
