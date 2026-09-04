import Foundation

enum GlobalLongHorizonGoalPolicy {
  static func mergeCognition(
    task: GlobalCognitionTask,
    current: [GlobalLongHorizonGoal],
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [GlobalLongHorizonGoal] {
    guard task.longHorizonGoalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return current
    }
    let durable = task.baselineUnderstanding.durableFollowUpUseful ||
      task.result.actions.contains { [.createTopic, .startMonitor].contains($0.kind) }
    guard durable else { return current }

    let topic = boundedTopic(firstNonBlank(task.result.topic, task.baselineUnderstanding.topic))
    let candidates = distinctGoalCandidates(
      task.result.goals.isEmpty ? task.baselineUnderstanding.goalCandidates : task.result.goals
    )
    guard !candidates.isEmpty else { return current }

    var merged = current
    for title in candidates {
      let cleanTitle = boundedTitle(title)
      let stableKey = GlobalAgentText.stableKey("long-horizon-goal", topic, cleanTitle)
      let priority = max(
        task.baselineUnderstanding.urgency,
        task.result.actions.map(\.priority).max() ?? 0.5
      ).clamped(minimum: 0.1, maximum: 1)
      let interval = checkpointInterval(priority: priority)
      if let index = matchingGoalIndex(goals: merged, stableKey: stableKey, topic: topic, title: cleanTitle) {
        let existing = merged[index]
        var copy = existing
        copy.topic = topic.isEmpty ? existing.topic : topic
        copy.title = cleanTitle
        copy.description = boundedDescription(task.sourceEvent.content)
        if existing.status != .completed {
          copy.status = .active
        }
        copy.priority = max(existing.priority, priority)
        copy.confidence = max(existing.confidence, task.result.confidence)
        copy.sourceConversationIds = limitedSet(existing.sourceConversationIds, adding: [task.sourceEvent.conversationId], limit: 20)
        copy.sourceEventIds = distinctSuffix(existing.sourceEventIds + [task.sourceEvent.id], limit: 30)
        copy.checkpointIntervalMillis = min(existing.checkpointIntervalMillis, interval)
        copy.nextCheckAtMillis = min(existing.nextCheckAtMillis, nowMillis + interval)
        copy.updatedAtMillis = max(nowMillis, 0)
        merged[index] = copy
      } else {
        merged.append(GlobalLongHorizonGoal(
          stableKey: stableKey,
          topic: topic,
          title: cleanTitle,
          description: boundedDescription(task.sourceEvent.content),
          priority: priority,
          confidence: task.result.confidence.clamped(minimum: 0.35, maximum: 1),
          sourceConversationIds: Set([task.sourceEvent.conversationId].filter { !$0.isEmpty }),
          sourceEventIds: [task.sourceEvent.id].filter { !$0.isEmpty },
          checkpointIntervalMillis: interval,
          nextCheckAtMillis: nowMillis + interval,
          createdAtMillis: nowMillis,
          updatedAtMillis: nowMillis
        ))
      }
    }
    return GlobalLongHorizonGoalGraphPolicy.applyDependencies(
      goals: trimGoals(merged),
      proposals: task.result.goalDependencies,
      nowMillis: nowMillis
    )
  }

  static func checkpointInterval(priority: Double) -> Int64 {
    switch priority {
    case 0.90...:
      return 60 * 60 * 1_000
    case 0.72..<0.90:
      return 6 * 60 * 60 * 1_000
    case 0.50..<0.72:
      return 24 * 60 * 60 * 1_000
    default:
      return 3 * 24 * 60 * 60 * 1_000
    }
  }

  static func mergeWorld(
    world: PersonalWorldModel,
    current: [GlobalLongHorizonGoal],
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [GlobalLongHorizonGoal] {
    let activeTaskTopics = Set(world.items
      .filter { $0.kind == .task && $0.status == .active }
      .map { GlobalAgentText.normalize($0.topic) }
      .filter { !$0.isEmpty })
    let candidates = world.items
      .filter { $0.kind == .goal && $0.status == .active }
      .filter { $0.confidence >= worldGoalConfidenceThreshold }
      .filter { item in
        item.evidenceCount >= 2 ||
          item.conversationIds.count >= 2 ||
          activeTaskTopics.contains(GlobalAgentText.normalize(item.topic)) ||
          durableSignals.contains { "\(item.topic) \(item.value)".lowercased().contains($0) }
      }
      .sorted {
        if $0.evidenceCount != $1.evidenceCount { return $0.evidenceCount > $1.evidenceCount }
        if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
        return $0.lastSeenAtMillis > $1.lastSeenAtMillis
      }
      .prefix(maxWorldGoals)

    guard !candidates.isEmpty else { return current }
    var merged = current
    for item in candidates {
      let title = boundedTitle(item.value)
      let stableKey = GlobalAgentText.stableKey("long-horizon-goal", item.topic, item.value)
      let priority = (
        item.confidence * 0.72 +
          Double(min(item.evidenceCount, 4)) * 0.05 +
          (item.conversationIds.count >= 2 ? 0.08 : 0)
      ).clamped(minimum: 0.1, maximum: 1)
      let interval = checkpointInterval(priority: priority)
      if let index = matchingGoalIndex(goals: merged, stableKey: stableKey, topic: item.topic, title: item.value) {
        let existing = merged[index]
        var copy = existing
        copy.priority = max(existing.priority, priority)
        copy.confidence = max(existing.confidence, item.confidence)
        copy.sourceConversationIds = limitedSet(existing.sourceConversationIds, adding: Array(item.conversationIds), limit: 20)
        copy.sourceEventIds = distinctSuffix(existing.sourceEventIds + item.evidenceEventIds, limit: 30)
        copy.checkpointIntervalMillis = min(existing.checkpointIntervalMillis, interval)
        if ![GlobalLongHorizonGoalStatus.completed, .paused].contains(existing.status) {
          let existingNext = existing.nextCheckAtMillis > 0 ? existing.nextCheckAtMillis : Int64.max
          copy.nextCheckAtMillis = min(existingNext, nowMillis + interval)
        }
        copy.updatedAtMillis = copy == existing ? existing.updatedAtMillis : max(nowMillis, 0)
        merged[index] = copy
      } else {
        merged.append(GlobalLongHorizonGoal(
          stableKey: stableKey,
          topic: item.topic,
          title: title,
          description: "Derived from \(item.evidenceCount) authorized world-model observations",
          priority: priority,
          confidence: item.confidence,
          sourceConversationIds: item.conversationIds,
          sourceEventIds: item.evidenceEventIds,
          checkpointIntervalMillis: interval,
          nextCheckAtMillis: nowMillis + min(interval, initialCheckpointDelayMillis),
          createdAtMillis: nowMillis,
          updatedAtMillis: nowMillis
        ))
      }
    }
    return trimGoals(merged)
  }

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
  private static let maxGoalsPerCognition = 4
  private static let maxWorldGoals = 80
  private static let maxGoals = 200
  private static let initialCheckpointDelayMillis: Int64 = 5 * 60 * 1_000
  private static let worldGoalConfidenceThreshold = 0.65
  private static let durableSignals = [
    "long term",
    "ongoing",
    "project",
    "roadmap",
    "monitor",
    "track",
    "\u{957f}\u{671f}",
    "\u{6301}\u{7eed}",
    "\u{9879}\u{76ee}",
    "\u{8def}\u{7ebf}\u{56fe}",
    "\u{76d1}\u{63a7}",
    "\u{8ddf}\u{8e2a}"
  ]

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func distinctGoalCandidates(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let clean = boundedTitle(value)
      let key = GlobalAgentText.normalize(clean)
      guard !clean.isEmpty, seen.insert(key).inserted else { continue }
      result.append(clean)
      if result.count >= maxGoalsPerCognition { break }
    }
    return result
  }

  private static func matchingGoalIndex(
    goals: [GlobalLongHorizonGoal],
    stableKey: String,
    topic: String,
    title: String
  ) -> Int? {
    goals.firstIndex { goal in
      goal.stableKey == stableKey ||
        (
          GlobalAgentText.normalize(goal.topic) == GlobalAgentText.normalize(topic) &&
            GlobalAgentText.overlap(GlobalAgentText.tokens(goal.title), GlobalAgentText.tokens(title)) >=
            worldGoalCompletionOverlap
        )
    }
  }

  private static func trimGoals(_ goals: [GlobalLongHorizonGoal]) -> [GlobalLongHorizonGoal] {
    Array(goals.sorted { $0.createdAtMillis < $1.createdAtMillis }.suffix(maxGoals))
  }

  private static func limitedSet(_ values: Set<String>, adding additions: [String], limit: Int) -> Set<String> {
    Set((values.sorted() + additions.sorted())
      .map(clean)
      .filter { !$0.isEmpty }
      .prefix(limit))
  }

  private static func distinctSuffix(_ values: [String], limit: Int) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values {
      let clean = clean(value)
      guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
      result.append(clean)
    }
    return Array(result.suffix(limit))
  }

  private static func firstNonBlank(_ first: String, _ fallback: String) -> String {
    let first = clean(first)
    return first.isEmpty ? clean(fallback) : first
  }

  private static func boundedTopic(_ value: String) -> String {
    String(clean(value).prefix(160))
  }

  private static func boundedTitle(_ value: String) -> String {
    String(clean(value)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .prefix(1_000))
  }

  private static func boundedDescription(_ value: String) -> String {
    String(clean(value).prefix(2_000))
  }
}

private extension Double {
  func clamped(minimum: Double, maximum: Double) -> Double {
    min(max(self, minimum), maximum)
  }
}
