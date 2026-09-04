import Foundation

enum GlobalRunReplanParser {
  static func parse(_ raw: String) -> GlobalRunReplanDecision? {
    let clean = stripFence(raw)
    guard
      let start = clean.firstIndex(of: "{"),
      let end = clean.lastIndex(of: "}"),
      start < end
    else {
      return nil
    }
    let jsonText = String(clean[start...end])
    guard
      let data = jsonText.data(using: .utf8),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      return nil
    }

    let state = goalState(string(json, "goal_state", "goalState")) ?? .active
    let actions = distinctActions(actionArray(json["actions"]))
    let summary = cleanText(string(json, "summary"), limit: 2_000)
    if summary.isEmpty, actions.isEmpty, state == .active {
      return nil
    }
    return GlobalRunReplanDecision(
      goalState: state,
      summary: summary,
      cancelActionIds: Set(strings(json["cancel_action_ids"] ?? json["cancelActionIds"], limit: 12, maxCharacters: 80)),
      actions: actions,
      nextCheckHours: int(json, keys: ["next_check_hours", "nextCheckHours"], fallback: 24, minimum: 1, maximum: 24 * 30),
      confidence: double(json, "confidence", fallback: 0.5, minimum: 0, maximum: 1)
    )
  }

  private static func actionArray(_ value: Any?) -> [GlobalAutonomousAction] {
    guard let array = value as? [Any] else { return [] }
    var result: [GlobalAutonomousAction] = []
    for value in array.prefix(maxActions) {
      guard let item = value as? [String: Any],
            let kind = actionKind(string(item, "kind")) else {
        continue
      }
      let goal = cleanText(string(item, "goal"), limit: 1_000)
      if goal.isEmpty {
        continue
      }
      let toolId = cleanText(string(item, "tool_id", "toolId"), limit: 180)
      let toolInputJson = cleanToolInput(item["tool_input"] ?? item["toolInput"])
      if kind == .invokeTool, (toolId.isEmpty || toolInputJson.isEmpty) {
        continue
      }
      result.append(GlobalAutonomousAction(
        planKey: cleanText(string(item, "key"), limit: 80),
        dependencyKeys: Set(strings(item["depends_on"] ?? item["dependsOn"], limit: 8, maxCharacters: 80)),
        kind: kind,
        goal: goal,
        rationale: cleanText(string(item, "rationale"), limit: 600),
        expectedResult: cleanText(string(item, "expected_result", "expectedResult"), limit: 600),
        targetTopic: cleanText(string(item, "target_topic", "targetTopic"), limit: 160),
        toolId: toolId,
        toolInputJson: toolInputJson,
        priority: double(item, "priority", fallback: 0.5, minimum: 0, maximum: 1),
        externalEffect: bool(item, keys: ["external_effect", "externalEffect"], fallback: false),
        reversible: bool(item, keys: ["reversible"], fallback: true)
      ))
    }
    return result
  }

  private static func distinctActions(_ actions: [GlobalAutonomousAction]) -> [GlobalAutonomousAction] {
    var seen: Set<String> = []
    var result: [GlobalAutonomousAction] = []
    for action in actions {
      let key = GlobalAgentText.stableKey(
        action.kind.rawValue,
        action.goal,
        action.toolId,
        action.toolInputJson
      )
      guard seen.insert(key).inserted else { continue }
      result.append(action)
    }
    return result
  }

  private static func stripFence(_ raw: String) -> String {
    var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.hasPrefix("```json") {
      clean.removeFirst("```json".count)
    } else if clean.hasPrefix("```") {
      clean.removeFirst("```".count)
    }
    if clean.hasSuffix("```") {
      clean.removeLast("```".count)
    }
    return clean.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func strings(_ value: Any?, limit: Int, maxCharacters: Int) -> [String] {
    guard let array = value as? [Any] else { return [] }
    var seen: Set<String> = []
    var result: [String] = []
    for item in array.prefix(max(limit * 2, 0)) {
      let value = cleanText(String(describing: item), limit: maxCharacters)
      guard !value.isEmpty, seen.insert(value).inserted else { continue }
      result.append(value)
      if result.count >= limit { break }
    }
    return result
  }

  private static func cleanToolInput(_ value: Any?) -> String {
    guard let value else { return "" }
    if let string = value as? String {
      return String(cleanText(string, limit: 8_000).prefix(8_000))
    }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
      return ""
    }
    return String(decoding: data.prefix(8_000), as: UTF8.self)
  }

  private static func cleanText(_ value: String, limit: Int) -> String {
    String(value
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(max(limit, 0)))
  }

  private static func string(_ json: [String: Any], _ keys: String...) -> String {
    for key in keys {
      if let value = json[key] as? String {
        return value
      }
    }
    return ""
  }

  private static func bool(_ json: [String: Any], keys: [String], fallback: Bool) -> Bool {
    for key in keys {
      if let value = json[key] as? Bool { return value }
      if let value = json[key] as? String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: break
        }
      }
    }
    return fallback
  }

  private static func int(
    _ json: [String: Any],
    keys: [String],
    fallback: Int,
    minimum: Int,
    maximum: Int
  ) -> Int {
    var value = fallback
    for key in keys {
      if let number = json[key] as? NSNumber {
        value = number.intValue
        break
      }
      if let string = json[key] as? String, let parsed = Int(string) {
        value = parsed
        break
      }
    }
    return max(minimum, min(value, maximum))
  }

  private static func double(
    _ json: [String: Any],
    _ key: String,
    fallback: Double,
    minimum: Double,
    maximum: Double
  ) -> Double {
    let raw: Double
    if let number = json[key] as? NSNumber {
      raw = number.doubleValue
    } else if let string = json[key] as? String, let parsed = Double(string) {
      raw = parsed
    } else {
      raw = fallback
    }
    return max(minimum, min(raw, maximum))
  }

  private static func goalState(_ value: String) -> GlobalGoalProgressState? {
    let normalized = normalizeEnum(value)
    return GlobalGoalProgressState.allCases.first { $0.rawValue == normalized }
  }

  private static func actionKind(_ value: String) -> GlobalAutonomousActionKind? {
    let normalized = normalizeEnum(value)
    return GlobalAutonomousActionKind.allCases.first { $0.rawValue == normalized }
  }

  private static func normalizeEnum(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_")
  }

  private static let maxActions = 6
}

enum GlobalAutonomousReplanPolicy {
  static func shouldReview(
    run: GlobalAutonomousRun,
    action: GlobalAutonomousAction,
    succeeded: Bool,
    result: String,
    enabled: Bool,
    maxReplans: Int
  ) -> Bool {
    guard enabled, run.replanCount < max(1, min(maxReplans, maxReplansLimit)) else {
      return false
    }
    if [.pending, .running].contains(run.review.status) {
      return false
    }
    if !succeeded {
      return true
    }
    let pendingAfterCurrent = run.actions.contains {
      $0.id != action.id && $0.status == .pending
    }
    let discoveryStep: Set<GlobalAutonomousActionKind> = [.analyze, .readOnlyCheck, .invokeTool]
    let normalized = result.lowercased()
    let changedAssumptions = outcomeReviewSignals.contains { normalized.contains($0) }
    return changedAssumptions || (discoveryStep.contains(action.kind) && pendingAfterCurrent)
  }

  static func requestReview(
    run: GlobalAutonomousRun,
    reason: String,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalAutonomousRun {
    var updated = run
    updated.status = .replanning
    updated.review = GlobalAutonomousRunReview(
      status: .pending,
      reason: String(reason.prefix(600)),
      nextAttemptAtMillis: max(nowMillis, 0),
      createdAtMillis: max(nowMillis, 0),
      updatedAtMillis: max(nowMillis, 0)
    )
    updated.nextAttemptAtMillis = max(nowMillis, 0)
    updated.leaseExpiresAtMillis = 0
    updated.updatedAtMillis = max(nowMillis, 0)
    return updated
  }

  static func applyDecision(
    run: GlobalAutonomousRun,
    decision: GlobalRunReplanDecision,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> GlobalAutonomousRun {
    let cancelled = run.actions.map { action -> GlobalAutonomousAction in
      guard decision.cancelActionIds.contains(action.id), action.status == .pending else {
        return action
      }
      var skipped = action
      skipped.status = .skipped
      skipped.lastError = "Superseded by plan revision"
      skipped.completedAtMillis = max(nowMillis, 0)
      return skipped
    }
    let existingKeys = Set(cancelled.map(actionStableKey))
    let proposedAdditions = decision.actions
      .filter { !existingKeys.contains(actionStableKey($0)) }
      .prefix(max(maxRunActions - cancelled.count, 0))
      .map { $0 }
    let additions = GlobalAutonomousActionGraphPolicy
      .resolveAgainst(existing: cancelled, proposed: proposedAdditions)
      .map { action -> GlobalAutonomousAction in
        action.status == .skipped ? action : GlobalAutonomousActionAuthorityPolicy.prepareProposal(action)
      }
    var actions = GlobalAutonomousActionGraphPolicy.reconcile(cancelled + additions, nowMillis: nowMillis)
    let rejectedCompletion = decision.goalState == .completed &&
      !GlobalAutonomousRunPolicy.completionSupported(cancelled)
    let effectiveGoalState: GlobalGoalProgressState = rejectedCompletion ? .active : decision.goalState
    if effectiveGoalState == .completed {
      actions = actions.map { action in
        guard [.pending, .waitingConfirmation].contains(action.status) else {
          return action
        }
        var skipped = action
        skipped.status = .skipped
        skipped.lastError = "The goal was satisfied before this step was needed"
        skipped.completedAtMillis = max(nowMillis, 0)
        return skipped
      }
    }

    let nextStatus: GlobalAutonomousRunStatus
    switch effectiveGoalState {
    case .completed:
      nextStatus = .completed
    case .blocked, .paused:
      nextStatus = .paused
    case .active:
      nextStatus = GlobalAutonomousRunPolicy.terminalStatus(actions) ??
        (actions.contains { $0.status == .pending } ? .queued : .waitingConfirmation)
    }

    let rejectionSummary = String(
      "Completion was not accepted because the action evidence contract was not satisfied. \(decision.summary)"
        .prefix(2_000)
    )
    var review = run.review
    review.status = .completed
    review.sourceMessageId = 0
    review.leaseExpiresAtMillis = 0
    review.lastError = ""
    review.decision = GlobalRunReplanDecision(
      goalState: effectiveGoalState,
      summary: rejectedCompletion ? rejectionSummary : decision.summary,
      cancelActionIds: decision.cancelActionIds,
      actions: decision.actions,
      nextCheckHours: decision.nextCheckHours,
      confidence: decision.confidence
    )
    review.updatedAtMillis = max(nowMillis, 0)

    var updated = run
    updated.actions = actions
    updated.status = nextStatus
    updated.revision = run.revision + 1
    updated.replanCount = run.replanCount + 1
    updated.outcomeSummary = rejectedCompletion ? rejectionSummary : decision.summary
    updated.review = review
    updated.nextAttemptAtMillis = nextStatus == .queued ? max(nowMillis, 0) : 0
    updated.leaseExpiresAtMillis = 0
    if decision.goalState == .blocked {
      updated.lastError = decision.summary
    } else if rejectedCompletion {
      updated.lastError = "The completion claim did not have sufficient action evidence"
    } else {
      updated.lastError = ""
    }
    updated.updatedAtMillis = max(nowMillis, 0)
    return updated
  }

  static func recoverIfStale(
    run: GlobalAutonomousRun,
    nowMillis: Int64
  ) -> GlobalAutonomousRun {
    let review = run.review
    guard run.status == .replanning,
          review.status == .running,
          review.leaseExpiresAtMillis > 0,
          review.leaseExpiresAtMillis <= nowMillis else {
      return run
    }
    var updatedReview = review
    updatedReview.status = .waitingForResource
    updatedReview.attemptedResourceIds = distinctStrings(review.attemptedResourceIds + [review.resourceId])
    updatedReview.sourceMessageId = 0
    updatedReview.nextAttemptAtMillis = max(nowMillis, 0)
    updatedReview.leaseExpiresAtMillis = 0
    updatedReview.lastError = "The plan review lease expired before a result arrived"
    updatedReview.updatedAtMillis = max(nowMillis, 0)

    var updated = run
    updated.status = .replanning
    updated.review = updatedReview
    updated.nextAttemptAtMillis = max(nowMillis, 0)
    updated.leaseExpiresAtMillis = 0
    updated.updatedAtMillis = max(nowMillis, 0)
    return updated
  }

  private static func actionStableKey(_ action: GlobalAutonomousAction) -> String {
    GlobalAgentText.stableKey(
      action.kind.rawValue,
      action.goal,
      action.toolId,
      action.toolInputJson
    )
  }

  private static func distinctStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
      result.append(clean)
    }
    return result
  }

  static let leaseMillis: Int64 = 4 * 60 * 1_000
  static let maxReviewAttempts = 3
  private static let maxReplansLimit = 5
  private static let maxRunActions = 12
  private static let outcomeReviewSignals = [
    "blocked", "failed", "failure", "missing", "cannot", "unable", "uncertain",
    "requires", "not available", "conflict", "changed assumption", "incomplete"
  ]
}

enum GlobalAutonomousRunPolicy {
  static func recoverIfStale(
    run: GlobalAutonomousRun,
    nowMillis: Int64
  ) -> GlobalAutonomousRun {
    let recoveredReview = GlobalAutonomousReplanPolicy.recoverIfStale(run: run, nowMillis: nowMillis)
    if recoveredReview != run {
      return recoveredReview
    }
    let actions = run.actions.map { storedAction -> GlobalAutonomousAction in
      var action = GlobalAutonomousActionAuthorityPolicy.recoverPersisted(storedAction)
      if action.status == .running,
         action.leaseExpiresAtMillis > 0,
         action.leaseExpiresAtMillis <= nowMillis {
        action.status = .pending
        action.attemptedResourceIds = distinctStrings(action.attemptedResourceIds + [action.resourceId])
        action.sourceMessageId = 0
        action.leaseExpiresAtMillis = 0
        action.lastError = "The delegated action lease expired before a result arrived"
      }
      return action
    }
    guard actions != run.actions else {
      return run
    }
    let activeLease = actions
      .filter { $0.status == .running }
      .map(\.leaseExpiresAtMillis)
      .filter { $0 > 0 }
      .max() ?? 0
    let terminal = terminalStatus(actions)
    var updated = run
    updated.actions = actions
    updated.status = terminal ?? (actions.contains { $0.status == .pending } ? .waitingForResource : .running)
    updated.nextAttemptAtMillis = max(nowMillis, 0)
    updated.leaseExpiresAtMillis = activeLease
    updated.updatedAtMillis = max(nowMillis, 0)
    return updated
  }

  static func terminalStatus(_ actions: [GlobalAutonomousAction]) -> GlobalAutonomousRunStatus? {
    if actions.contains(where: { [.pending, .running].contains($0.status) }) {
      return nil
    }
    let completed = actions.filter { $0.status == .completed }.count
    let failed = actions.filter { $0.status == .failed }.count
    let waiting = actions.contains { $0.status == .waitingConfirmation }
    if waiting { return .waitingConfirmation }
    if completed > 0, failed > 0 { return .partial }
    if completed > 0 { return .completed }
    return .failed
  }

  static func completionSupported(_ actions: [GlobalAutonomousAction]) -> Bool {
    let completed = actions.filter { $0.status == .completed }
    guard !completed.isEmpty else { return false }
    return completed.allSatisfy {
      [.supported, .verified].contains($0.verificationStatus)
    }
  }

  static func retryDelayMillis(attemptCount: Int) -> Int64 {
    switch max(attemptCount, 1) {
    case 1: return 15_000
    case 2: return 60_000
    default: return 5 * 60 * 1_000
    }
  }

  private static func distinctStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty, seen.insert(clean).inserted else { continue }
      result.append(clean)
    }
    return result
  }

  static let leaseMillis: Int64 = 8 * 60 * 1_000
  static let maxActionAttempts = 3
}
