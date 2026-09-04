import Foundation

struct GlobalGoalDependencyProposal: Codable, Equatable {
  var goal: String
  var dependsOn: String

  init(goal: String, dependsOn: String) {
    self.goal = Self.clean(goal)
    self.dependsOn = Self.clean(dependsOn)
  }

  enum CodingKeys: String, CodingKey {
    case goal
    case dependsOn = "depends_on"
  }

  private static func clean(_ value: String) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextCharacters))
  }

  private static let maxTextCharacters = 500
}

enum GlobalLongHorizonGoalGraphPolicy {
  static func applyDependencies(
    goals: [GlobalLongHorizonGoal],
    proposals: [GlobalGoalDependencyProposal],
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [GlobalLongHorizonGoal] {
    guard !goals.isEmpty, !proposals.isEmpty else {
      return reconcile(goals: goals, nowMillis: nowMillis)
    }
    var updated = goals
    for proposal in proposals.prefix(maxDependencyProposals) {
      guard
        let target = bestMatch(goals: updated, value: proposal.goal),
        let prerequisite = bestMatch(goals: updated, value: proposal.dependsOn),
        target.id != prerequisite.id,
        !target.dependencyGoalIds.contains(prerequisite.id),
        !wouldCreateCycle(goals: updated, targetId: target.id, prerequisiteId: prerequisite.id)
      else {
        continue
      }

      updated = updated.map { goal in
        guard goal.id == target.id else { return goal }
        var copy = goal
        let dependencies = (goal.dependencyGoalIds.sorted() + [prerequisite.id])
          .prefix(maxDependenciesPerGoal)
        copy.dependencyGoalIds = Set(dependencies)
        if copy.completionCriteria.isEmpty {
          let title = String(copy.title.prefix(500))
          copy.completionCriteria = ["Verified evidence that \(title) is complete"]
        }
        copy.updatedAtMillis = max(nowMillis, 0)
        return copy
      }
    }
    return reconcile(goals: updated, nowMillis: nowMillis)
  }

  static func assignProjects(
    goals: [GlobalLongHorizonGoal],
    graph: GlobalTopicProjectGraph,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [GlobalLongHorizonGoal] {
    let projects = graph.activeNodes().filter { $0.kind == .project }
    guard !projects.isEmpty else { return goals }
    return goals.map { goal in
      guard let best = bestProject(for: goal, projects: projects) else {
        return goal
      }
      let score = projectScore(goal: goal, project: best)
      guard score >= minimumProjectMatch, goal.projectNodeId != best.id else {
        return goal
      }
      var copy = goal
      copy.projectNodeId = best.id
      copy.updatedAtMillis = max(nowMillis, 0)
      return copy
    }
  }

  static func reconcile(
    goals: [GlobalLongHorizonGoal],
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> [GlobalLongHorizonGoal] {
    let byId = goalMap(goals)
    return goals.map { goal in
      if terminalOrOwnedStatuses.contains(goal.status) {
        return goal
      }
      let incomplete = goal.dependencyGoalIds
        .compactMap { byId[$0] }
        .filter { $0.status != .completed }
      if !incomplete.isEmpty && goal.status != .waitingDependency {
        var copy = goal
        copy.status = .waitingDependency
        copy.blocker = "Waiting for \(incomplete.count) prerequisite goal(s)"
        copy.nextCheckAtMillis = 0
        copy.updatedAtMillis = max(nowMillis, 0)
        return copy
      }
      if incomplete.isEmpty && goal.status == .waitingDependency {
        var copy = goal
        copy.status = .active
        copy.blocker = ""
        copy.nextCheckAtMillis = max(nowMillis, 0)
        copy.updatedAtMillis = max(nowMillis, 0)
        return copy
      }
      return goal
    }
  }

  static func ready(
    goal: GlobalLongHorizonGoal,
    goals: [GlobalLongHorizonGoal]
  ) -> Bool {
    guard !goal.dependencyGoalIds.isEmpty else { return true }
    let byId = goalMap(goals)
    return goal.dependencyGoalIds.allSatisfy { byId[$0]?.status == .completed }
  }

  private static let terminalOrOwnedStatuses: Set<GlobalLongHorizonGoalStatus> = [
    .completed,
    .paused,
    .inProgress,
    .waitingConfirmation
  ]
  private static let minimumGoalMatch = 0.52
  private static let minimumProjectMatch = 0.40
  private static let maxDependencyProposals = 12
  private static let maxDependenciesPerGoal = 8

  private static func bestMatch(
    goals: [GlobalLongHorizonGoal],
    value: String
  ) -> GlobalLongHorizonGoal? {
    let normalized = GlobalAgentText.normalize(value)
    if let exact = goals.first(where: { GlobalAgentText.normalize($0.title) == normalized }) {
      return exact
    }
    let tokens = GlobalAgentText.tokens(value)
    return goals
      .map { goal in
        (goal, GlobalAgentText.overlap(tokens, GlobalAgentText.tokens(goal.title)))
      }
      .filter { $0.1 >= minimumGoalMatch }
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        if $0.0.priority != $1.0.priority { return $0.0.priority > $1.0.priority }
        return $0.0.createdAtMillis < $1.0.createdAtMillis
      }
      .first?
      .0
  }

  private static func bestProject(
    for goal: GlobalLongHorizonGoal,
    projects: [GlobalTopicNode]
  ) -> GlobalTopicNode? {
    projects
      .map { ($0, projectScore(goal: goal, project: $0)) }
      .sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.lastSeenAtMillis > $1.0.lastSeenAtMillis
      }
      .first?
      .0
  }

  private static func projectScore(
    goal: GlobalLongHorizonGoal,
    project: GlobalTopicNode
  ) -> Double {
    GlobalAgentText.overlap(
      GlobalAgentText.tokens(goal.topic),
      GlobalAgentText.tokens(project.name)
    ) + (project.conversationIds.isDisjoint(with: goal.sourceConversationIds) ? 0 : 0.45)
  }

  private static func wouldCreateCycle(
    goals: [GlobalLongHorizonGoal],
    targetId: String,
    prerequisiteId: String
  ) -> Bool {
    let byId = goalMap(goals)
    var visited = Set<String>()
    func reachesTarget(_ currentId: String) -> Bool {
      if currentId == targetId { return true }
      guard visited.insert(currentId).inserted else { return false }
      return byId[currentId]?.dependencyGoalIds.contains(where: reachesTarget) ?? false
    }
    return reachesTarget(prerequisiteId)
  }

  private static func goalMap(_ goals: [GlobalLongHorizonGoal]) -> [String: GlobalLongHorizonGoal] {
    var byId: [String: GlobalLongHorizonGoal] = [:]
    for goal in goals {
      byId[goal.id] = goal
    }
    return byId
  }
}
