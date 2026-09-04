import Foundation

enum GlobalAgentEvidenceLifecyclePolicy {
  static let invalidatedReason = "Source evidence was revised or deleted"

  static func isInvalidatedState(_ reason: String) -> Bool {
    reason == invalidatedReason
  }

  static func evidenceIdsForConversation(
    conversationId: String,
    cognitionTasks: [GlobalCognitionTask],
    researchTasks: [GlobalResearchTask],
    autonomousRuns: [GlobalAutonomousRun],
    proactiveMessages: [GlobalProactiveMessage],
    longHorizonGoals: [GlobalLongHorizonGoal]
  ) -> Set<String> {
    let conversationId = normalized(conversationId)
    guard !conversationId.isEmpty else { return [] }

    var evidenceIds = Set<String>()
    for task in cognitionTasks
      where task.sourceEvent.conversationId == conversationId ||
        metadataConversationIds(task.sourceEvent).contains(conversationId) {
      evidenceIds.formUnion(nonEmpty(task.sourceEvent.evidenceRoots))
    }
    for task in researchTasks where task.sourceConversationId == conversationId {
      evidenceIds.formUnion(rootIds(causalEventIds: task.causalEventIds, fallbackEventId: task.sourceEventId))
    }
    for run in autonomousRuns where run.sourceConversationId == conversationId {
      evidenceIds.formUnion(rootIds(causalEventIds: run.causalEventIds, fallbackEventId: run.sourceEventId))
    }
    for message in proactiveMessages where message.sourceConversationId == conversationId {
      evidenceIds.formUnion(rootIds(causalEventIds: message.causalEventIds, fallbackEventId: message.sourceEventId))
    }
    for goal in longHorizonGoals where goal.sourceConversationIds.contains(conversationId) {
      evidenceIds.formUnion(nonEmpty(goal.sourceEventIds))
    }
    return evidenceIds
  }

  static func invalidateCognitionTasks(
    _ tasks: [GlobalCognitionTask],
    eventIds: Set<String>,
    nowMillis: Int64
  ) -> [GlobalCognitionTask] {
    let eventIds = nonEmpty(eventIds)
    guard !eventIds.isEmpty else { return tasks }
    return tasks.map { task in
      guard intersects(task.sourceEvent.evidenceRoots, eventIds) else { return task }
      var copy = task
      copy.status = .failed
      copy.sourceMessageId = 0
      copy.nextAttemptAtMillis = 0
      copy.leaseExpiresAtMillis = 0
      copy.lastError = invalidatedReason
      copy.updatedAtMillis = max(nowMillis, 0)
      return copy
    }
  }

  static func invalidateResearchTasks(
    _ tasks: [GlobalResearchTask],
    eventIds: Set<String>,
    nowMillis: Int64
  ) -> [GlobalResearchTask] {
    let eventIds = nonEmpty(eventIds)
    guard !eventIds.isEmpty else { return tasks }
    return tasks.map { task in
      let roots = rootIds(causalEventIds: task.causalEventIds, fallbackEventId: task.sourceEventId)
      guard intersects(roots, eventIds) else { return task }
      var copy = task
      copy.status = .failed
      copy.sourceMessageId = 0
      copy.nextAttemptAtMillis = 0
      copy.leaseExpiresAtMillis = 0
      copy.lastError = invalidatedReason
      copy.researchPlan = invalidatedResearchPlan(task.researchPlan, nowMillis: nowMillis)
      copy.updatedAtMillis = max(nowMillis, 0)
      return copy
    }
  }

  static func invalidateAutonomousRuns(
    _ runs: [GlobalAutonomousRun],
    eventIds: Set<String>,
    nowMillis: Int64
  ) -> [GlobalAutonomousRun] {
    let eventIds = nonEmpty(eventIds)
    guard !eventIds.isEmpty else { return runs }
    return runs.map { run in
      let roots = rootIds(causalEventIds: run.causalEventIds, fallbackEventId: run.sourceEventId)
      guard intersects(roots, eventIds) else { return run }
      var copy = run
      copy.status = .paused
      copy.actions = run.actions.map {
        invalidatedAutonomousAction($0, nowMillis: nowMillis)
      }
      copy.nextAttemptAtMillis = 0
      copy.leaseExpiresAtMillis = 0
      copy.lastError = invalidatedReason
      copy.updatedAtMillis = max(nowMillis, 0)
      return copy
    }
  }

  static func invalidateProactiveMessages(
    _ messages: [GlobalProactiveMessage],
    eventIds: Set<String>
  ) -> [GlobalProactiveMessage] {
    let eventIds = nonEmpty(eventIds)
    guard !eventIds.isEmpty else { return messages }
    return messages.map { message in
      let roots = rootIds(causalEventIds: message.causalEventIds, fallbackEventId: message.sourceEventId)
      guard intersects(roots, eventIds), invalidatableProactiveStatuses.contains(message.status) else {
        return message
      }
      var copy = message
      copy.status = .dismissed
      copy.deliveryLeaseExpiresAtMillis = 0
      copy.lastDeliveryError = invalidatedReason
      return copy
    }
  }

  static func invalidateLongHorizonGoals(
    _ goals: [GlobalLongHorizonGoal],
    eventIds: Set<String>,
    nowMillis: Int64
  ) -> [GlobalLongHorizonGoal] {
    let eventIds = nonEmpty(eventIds)
    guard !eventIds.isEmpty else { return goals }
    let updated = goals.compactMap { goal -> GlobalLongHorizonGoal? in
      guard intersects(Set(goal.sourceEventIds), eventIds) else { return goal }
      let retained = goal.sourceEventIds.filter { !eventIds.contains($0) && !normalized($0).isEmpty }
      guard !retained.isEmpty else { return nil }
      var copy = goal
      copy.sourceEventIds = retained
      copy.activeCognitionTaskId = ""
      copy.activeRunId = ""
      copy.nextCheckAtMillis = max(nowMillis, 0)
      copy.updatedAtMillis = max(nowMillis, 0)
      return copy
    }
    let retainedIds = Set(updated.map(\.id))
    return GlobalLongHorizonGoalGraphPolicy.reconcile(
      goals: updated.map { goal in
        var copy = goal
        copy.dependencyGoalIds = goal.dependencyGoalIds.intersection(retainedIds)
        return copy
      },
      nowMillis: nowMillis
    )
  }

  private static let invalidatableProactiveStatuses: Set<GlobalProactiveMessageStatus> = [
    .pending,
    .notified,
    .delivering
  ]

  private static func invalidatedResearchPlan(
    _ plan: GlobalResearchPlan,
    nowMillis: Int64
  ) -> GlobalResearchPlan {
    let now = max(nowMillis, 0)
    var copy = plan
    copy.units = plan.units.map { unit in
      guard [.pending, .running].contains(unit.status) else { return unit }
      var unitCopy = unit
      unitCopy.status = .failed
      unitCopy.sourceMessageId = 0
      unitCopy.leaseExpiresAtMillis = 0
      unitCopy.lastError = invalidatedReason
      unitCopy.completedAtMillis = now
      return unitCopy
    }
    copy.synthesisSourceMessageId = 0
    copy.synthesisLeaseExpiresAtMillis = 0
    copy.updatedAtMillis = now
    return copy
  }

  private static func invalidatedAutonomousAction(
    _ action: GlobalAutonomousAction,
    nowMillis: Int64
  ) -> GlobalAutonomousAction {
    guard [.pending, .running, .waitingConfirmation].contains(action.status) else {
      return action
    }
    var copy = action
    copy.status = .skipped
    copy.sourceMessageId = 0
    copy.leaseExpiresAtMillis = 0
    copy.lastError = invalidatedReason
    copy.completedAtMillis = max(nowMillis, 0)
    return copy
  }

  private static func metadataConversationIds(_ event: GlobalConversationEvent) -> Set<String> {
    Set((event.metadata["source_conversation_ids"] ?? "")
      .split(separator: ",")
      .map { normalized($0) }
      .filter { !$0.isEmpty })
  }

  private static func rootIds(causalEventIds: Set<String>, fallbackEventId: String) -> Set<String> {
    let roots = nonEmpty(causalEventIds)
    return roots.isEmpty ? nonEmpty([fallbackEventId]) : roots
  }

  private static func intersects(_ left: Set<String>, _ right: Set<String>) -> Bool {
    !nonEmpty(left).isDisjoint(with: right)
  }

  private static func nonEmpty<S: Sequence>(_ values: S) -> Set<String> where S.Element == String {
    Set(values.map { normalized($0) }.filter { !$0.isEmpty })
  }

  private static func normalized<S: StringProtocol>(_ value: S) -> String {
    String(value).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
