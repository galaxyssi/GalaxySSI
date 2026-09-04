import Foundation

struct GlobalActionReservation: Codable, Equatable {
  var actionId: String
  var actions: [GlobalAutonomousAction]

  init(actionId: String, actions: [GlobalAutonomousAction]) {
    self.actionId = actionId
    self.actions = actions
  }

  enum CodingKeys: String, CodingKey {
    case actionId = "action_id"
    case actions
  }
}

enum GlobalAutonomousActionAuthorityPolicy {
  static func prepareProposal(_ action: GlobalAutonomousAction) -> GlobalAutonomousAction {
    if action.status == .skipped {
      return action
    }
    if action.kind == .invokeTool {
      var prepared = action
      prepared.status = .pending
      prepared.confirmationGranted = false
      return prepared
    }
    var prepared = action
    prepared.externalEffect = false
    prepared.reversible = true
    prepared.confirmationGranted = false
    prepared.status = .pending
    return prepared
  }

  static func recoverPersisted(_ action: GlobalAutonomousAction) -> GlobalAutonomousAction {
    guard action.kind != .invokeTool,
          [.pending, .waitingConfirmation].contains(action.status) else {
      return action
    }
    return prepareProposal(action)
  }
}

enum GlobalAutonomousActionGraphPolicy {
  static func prepare(_ actions: [GlobalAutonomousAction]) -> [GlobalAutonomousAction] {
    if actions.isEmpty {
      return []
    }
    let keyed = distinctByPlanKey(actions.enumerated().map { index, action in
      action.withPlanKey(defaultPlanKey(for: action, index: index))
    })
    let byKey = Dictionary(uniqueKeysWithValues: keyed.map { ($0.planKey, $0) })
    let resolved = keyed.map { action -> GlobalAutonomousAction in
      let unknown = action.dependencyKeys.filter { byKey[$0] == nil }.sorted()
      if !unknown.isEmpty {
        var skipped = action
        skipped.status = .skipped
        skipped.lastError = "Unknown prerequisite step: \(String(unknown.joined(separator: ", ").prefix(300)))"
        return skipped
      }
      var resolved = action
      resolved.dependsOnActionIds = Set(action.dependencyKeys.compactMap { byKey[$0]?.id })
      return resolved
    }
    guard isAcyclic(resolved) else {
      return resolved.map { action in
        guard !action.dependsOnActionIds.isEmpty else {
          return action
        }
        var skipped = action
        skipped.status = .skipped
        skipped.lastError = "The proposed step dependencies contain a cycle"
        return skipped
      }
    }
    return resolved
  }

  static func resolveAgainst(
    existing: [GlobalAutonomousAction],
    proposed: [GlobalAutonomousAction]
  ) -> [GlobalAutonomousAction] {
    let keyed = (existing + proposed).enumerated().map { index, action in
      action.withPlanKey(defaultPlanKey(for: action, index: index))
    }
    let byKey = Dictionary(uniqueKeysWithValues: distinctByPlanKey(keyed).map { ($0.planKey, $0) })
    let resolved = proposed.map { action -> GlobalAutonomousAction in
      let source = keyed.first { $0.id == action.id } ?? action.withPlanKey(defaultPlanKey(for: action, index: existing.count))
      let unknown = source.dependencyKeys.filter { byKey[$0] == nil }.sorted()
      if !unknown.isEmpty {
        var skipped = source
        skipped.status = .skipped
        skipped.lastError = "Unknown prerequisite step: \(String(unknown.joined(separator: ", ").prefix(300)))"
        return skipped
      }
      var resolved = source
      resolved.dependsOnActionIds = Set(source.dependencyKeys.compactMap { byKey[$0]?.id })
      return resolved
    }
    guard isAcyclic(existing + resolved) else {
      return resolved.map { action in
        guard !action.dependsOnActionIds.isEmpty else {
          return action
        }
        var skipped = action
        skipped.status = .skipped
        skipped.lastError = "The proposed step dependencies contain a cycle"
        return skipped
      }
    }
    return resolved
  }

  static func reconcile(
    _ actions: [GlobalAutonomousAction],
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [GlobalAutonomousAction] {
    let byId = dictionaryById(actions)
    return actions.map { action in
      guard [.pending, .waitingConfirmation].contains(action.status) else {
        return action
      }
      let failedDependencies = action.dependsOnActionIds
        .compactMap { byId[$0] }
        .filter { [.failed, .skipped].contains($0.status) }
      let missingDependencies = action.dependsOnActionIds.filter { byId[$0] == nil }
      if failedDependencies.isEmpty && missingDependencies.isEmpty {
        return action
      }
      var skipped = action
      skipped.status = .skipped
      skipped.lastError = "A prerequisite step did not complete"
      skipped.completedAtMillis = max(action.completedAtMillis, nowMillis)
      return skipped
    }
  }

  static func readyActions(_ actions: [GlobalAutonomousAction]) -> [GlobalAutonomousAction] {
    let byId = dictionaryById(actions)
    return actions
      .filter { action in
        action.status == .pending &&
          action.dependsOnActionIds.allSatisfy { byId[$0]?.status == .completed }
      }
      .sorted { left, right in
        if left.priority != right.priority {
          return left.priority > right.priority
        }
        return left.id < right.id
      }
  }

  static func reserveNext(
    actions: [GlobalAutonomousAction],
    nowMillis: Int64,
    leaseExpiresAtMillis: Int64
  ) -> GlobalActionReservation? {
    guard let action = readyActions(actions).first else {
      return nil
    }
    return GlobalActionReservation(
      actionId: action.id,
      actions: actions.map { candidate in
        guard candidate.id == action.id else {
          return candidate
        }
        var reserved = candidate
        reserved.status = .running
        reserved.attemptCount += 1
        reserved.leaseExpiresAtMillis = max(leaseExpiresAtMillis, 0)
        reserved.lastError = ""
        reserved.startedAtMillis = max(nowMillis, 0)
        return reserved
      }
    )
  }

  private static func defaultPlanKey(
    for action: GlobalAutonomousAction,
    index: Int
  ) -> String {
    let existing = action.planKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !existing.isEmpty {
      return String(existing.prefix(80))
    }
    let fingerprint = GlobalAgentText.stableKey(
      action.kind.rawValue,
      action.goal,
      action.toolId,
      action.toolInputJson
    )
    return "step-\(index + 1)-\(fingerprint.prefix(8))"
  }

  private static func distinctByPlanKey(_ actions: [GlobalAutonomousAction]) -> [GlobalAutonomousAction] {
    var seen: Set<String> = []
    var result: [GlobalAutonomousAction] = []
    for action in actions where seen.insert(action.planKey).inserted {
      result.append(action)
    }
    return result
  }

  private static func isAcyclic(_ actions: [GlobalAutonomousAction]) -> Bool {
    let byId = dictionaryById(actions)
    var visiting: Set<String> = []
    var visited: Set<String> = []

    func visit(_ id: String) -> Bool {
      if visited.contains(id) {
        return true
      }
      if !visiting.insert(id).inserted {
        return false
      }
      let valid = byId[id]?.dependsOnActionIds.allSatisfy(visit) ?? true
      visiting.remove(id)
      if valid {
        visited.insert(id)
      }
      return valid
    }

    return actions.allSatisfy { visit($0.id) }
  }

  private static func dictionaryById(_ actions: [GlobalAutonomousAction]) -> [String: GlobalAutonomousAction] {
    actions.reduce(into: [:]) { result, action in
      if result[action.id] == nil {
        result[action.id] = action
      }
    }
  }
}

private extension GlobalAutonomousAction {
  func withPlanKey(_ value: String) -> GlobalAutonomousAction {
    var copy = self
    copy.planKey = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
    return copy
  }
}
