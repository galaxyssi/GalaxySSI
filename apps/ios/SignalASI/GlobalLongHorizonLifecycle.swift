import Foundation

enum GlobalLongHorizonLifecyclePolicy {
  static func stampTransition(
    previous: GlobalLongHorizonGoal?,
    next: GlobalLongHorizonGoal,
    nowMillis: Int64 = 0
  ) -> GlobalLongHorizonGoal {
    let now = effectiveNow(nowMillis: nowMillis, next: next)
    guard let previous else {
      guard next.statusChangedAtMillis <= 0 else { return next }
      var copy = next
      copy.statusChangedAtMillis = next.createdAtMillis > 0 ? next.createdAtMillis : now
      return copy
    }
    if previous.status == next.status {
      var copy = next
      copy.previousStatus = next.previousStatus ?? previous.previousStatus
      copy.statusChangedAtMillis = firstPositive(
        next.statusChangedAtMillis,
        previous.statusChangedAtMillis,
        previous.updatedAtMillis,
        now
      )
      return copy
    }
    var copy = next
    copy.previousStatus = previous.status
    copy.statusChangedAtMillis = now
    return copy
  }

  static func stampTransitions(
    previous: [GlobalLongHorizonGoal],
    next: [GlobalLongHorizonGoal]
  ) -> [GlobalLongHorizonGoal] {
    var previousById: [String: GlobalLongHorizonGoal] = [:]
    for goal in previous {
      previousById[goal.id] = goal
    }
    return next.map {
      stampTransition(previous: previousById[$0.id], next: $0)
    }
  }

  static func proactiveMessage(goal: GlobalLongHorizonGoal) -> GlobalProactiveMessage? {
    guard
      let previous = goal.previousStatus,
      previous != goal.status,
      goal.statusChangedAtMillis > 0
    else {
      return nil
    }

    let chinese = containsCjk("\(goal.topic) \(goal.title) \(goal.description)")
    let detail = transitionDetail(goal)
    let resumed = goal.status == .active && [
      .blocked,
      .waitingDependency,
      .waitingConfirmation
    ].contains(previous)
    let material = [
      .completed,
      .blocked,
      .waitingDependency,
      .waitingConfirmation
    ].contains(goal.status) || resumed
    guard material, let title = transitionTitle(status: goal.status, chinese: chinese) else {
      return nil
    }

    let content = boundedContent(
      statusContent(status: goal.status, title: goal.title, chinese: chinese),
      detail: detail
    )
    let urgent = goal.status == .waitingConfirmation ||
      (goal.status == .blocked && goal.priority >= highPriorityThreshold)
    guard let target = target(status: goal.status, priority: goal.priority) else {
      return nil
    }
    let sourceId = [
      "long-horizon-lifecycle",
      goal.id,
      previous.rawValue,
      goal.status.rawValue,
      String(goal.statusChangedAtMillis),
      String(goal.checkpointCount)
    ].joined(separator: ":")

    return GlobalProactiveMessage(
      id: GlobalAgentText.stableKey(sourceId),
      sourceEventId: sourceId,
      sourceConversationId: goal.sourceConversationIds.sorted().first ?? "",
      target: target,
      title: title,
      content: content,
      topic: boundedTopic(firstNonBlank(goal.topic, goal.title)),
      urgent: urgent,
      causalEventIds: Set(goal.sourceEventIds.map(clean).filter { !$0.isEmpty }),
      createdAtMillis: goal.statusChangedAtMillis
    )
  }

  private static let highPriorityThreshold = 0.90
  private static let currentConversationBlockedThreshold = 0.72
  private static let maxDetailCharacters = 1_200
  private static let maxContentCharacters = 4_000
  private static let maxTopicCharacters = 160

  private static func effectiveNow(
    nowMillis: Int64,
    next: GlobalLongHorizonGoal
  ) -> Int64 {
    if nowMillis > 0 { return nowMillis }
    if next.updatedAtMillis > 0 { return next.updatedAtMillis }
    return GlobalRealtimeClock.nowMillis()
  }

  private static func firstPositive(_ values: Int64...) -> Int64 {
    values.first { $0 > 0 } ?? 0
  }

  private static func transitionDetail(_ goal: GlobalLongHorizonGoal) -> String {
    let detail: String
    switch goal.status {
    case .completed:
      detail = firstNonBlank(goal.verificationSummary, goal.progressSummary)
    case .blocked:
      detail = firstNonBlank(goal.blocker, goal.progressSummary)
    case .waitingDependency, .waitingConfirmation:
      detail = goal.blocker
    case .active:
      detail = goal.progressSummary
    case .inProgress, .paused:
      detail = ""
    }
    return String(cleanWhitespace(detail).prefix(maxDetailCharacters))
  }

  private static func transitionTitle(
    status: GlobalLongHorizonGoalStatus,
    chinese: Bool
  ) -> String? {
    switch status {
    case .completed:
      return chinese ? "\u{76ee}\u{6807}\u{5df2}\u{5b8c}\u{6210}" : "Goal completed"
    case .blocked:
      return chinese ? "\u{76ee}\u{6807}\u{53d7}\u{963b}" : "Goal blocked"
    case .waitingDependency:
      return chinese ? "\u{6b63}\u{5728}\u{7b49}\u{5f85}\u{524d}\u{7f6e}\u{76ee}\u{6807}" :
        "Waiting for a prerequisite"
    case .waitingConfirmation:
      return chinese ? "\u{9700}\u{8981}\u{4f60}\u{7684}\u{786e}\u{8ba4}" : "Confirmation required"
    case .active:
      return chinese ? "\u{76ee}\u{6807}\u{5df2}\u{6062}\u{590d}" : "Goal resumed"
    case .inProgress, .paused:
      return nil
    }
  }

  private static func statusContent(
    status: GlobalLongHorizonGoalStatus,
    title: String,
    chinese: Bool
  ) -> String {
    switch status {
    case .completed:
      return chinese
        ? "\u{201c}\(title)\u{201d}\u{5df2}\u{7ecf}\u{5b8c}\u{6210}\u{5e76}\u{9a8c}\u{8bc1}\u{3002}"
        : "\(title) is complete and verified."
    case .blocked:
      return chinese
        ? "\u{201c}\(title)\u{201d}\u{5f53}\u{524d}\u{53d7}\u{963b}\u{3002}"
        : "\(title) is currently blocked."
    case .waitingDependency:
      return chinese
        ? "\u{201c}\(title)\u{201d}\u{6b63}\u{5728}\u{7b49}\u{5f85}\u{524d}\u{7f6e}\u{76ee}\u{6807}\u{5b8c}\u{6210}\u{3002}"
        : "\(title) is waiting for a prerequisite goal."
    case .waitingConfirmation:
      return chinese
        ? "\u{201c}\(title)\u{201d}\u{9700}\u{8981}\u{4f60}\u{786e}\u{8ba4}\u{540e}\u{624d}\u{80fd}\u{7ee7}\u{7eed}\u{3002}"
        : "\(title) needs your confirmation before it can continue."
    case .active:
      return chinese
        ? "\u{201c}\(title)\u{201d}\u{5df2}\u{6062}\u{590d}\u{ff0c}\u{5c06}\u{7ee7}\u{7eed}\u{8ddf}\u{8fdb}\u{3002}"
        : "\(title) has resumed and will continue to be tracked."
    case .inProgress, .paused:
      return ""
    }
  }

  private static func boundedContent(_ base: String, detail: String) -> String {
    let content = detail.isEmpty ? base : "\(base)\n\n\(detail)"
    return String(content.prefix(maxContentCharacters))
  }

  private static func target(
    status: GlobalLongHorizonGoalStatus,
    priority: Double
  ) -> GlobalProactiveTarget? {
    switch status {
    case .waitingConfirmation:
      return .currentConversation
    case .waitingDependency:
      return .globalDigest
    case .blocked:
      return priority >= currentConversationBlockedThreshold ? .currentConversation : .globalDigest
    case .completed, .active:
      return .newConversation
    case .inProgress, .paused:
      return nil
    }
  }

  private static func boundedTopic(_ value: String) -> String {
    String(clean(value).prefix(maxTopicCharacters))
  }

  private static func cleanWhitespace(_ value: String) -> String {
    clean(value)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func firstNonBlank(_ first: String, _ fallback: String) -> String {
    let first = clean(first)
    return first.isEmpty ? clean(fallback) : first
  }

  private static func containsCjk(_ value: String) -> Bool {
    value.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
  }
}
