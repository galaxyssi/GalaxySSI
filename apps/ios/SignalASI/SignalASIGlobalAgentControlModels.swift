import Foundation
import SwiftUI

extension GlobalAgentSettings {
  var normalized: GlobalAgentSettings {
    GlobalAgentSettings(
      backgroundCognitionArchitectureVersion: backgroundCognitionArchitectureVersion,
      enabled: enabled,
      proactiveInsightsEnabled: proactiveInsightsEnabled,
      proactiveDiscoveryEnabled: proactiveDiscoveryEnabled,
      modelUnderstandingEnabled: modelUnderstandingEnabled,
      autonomousPreparationEnabled: autonomousPreparationEnabled,
      autonomousToolExecutionEnabled: autonomousToolExecutionEnabled,
      dynamicAutonomousReplanningEnabled: dynamicAutonomousReplanningEnabled,
      longHorizonPlanningEnabled: longHorizonPlanningEnabled,
      maxAutonomousReplans: maxAutonomousReplans,
      allowCloudCognition: allowCloudCognition,
      autonomousResearchEnabled: autonomousResearchEnabled,
      autoCreateConversationsEnabled: autoCreateConversationsEnabled,
      notificationsEnabled: notificationsEnabled,
      adaptiveLearningEnabled: adaptiveLearningEnabled,
      allowMeteredBackgroundResearch: allowMeteredBackgroundResearch,
      dailyBackgroundModelCallBudget: dailyBackgroundModelCallBudget,
      maxConcurrentBackgroundModelCalls: maxConcurrentBackgroundModelCalls,
      dailyBackgroundTokenBudget: dailyBackgroundTokenBudget,
      dailyBackgroundReportedCostBudgetMicros: dailyBackgroundReportedCostBudgetMicros,
      dailyMessageBudget: dailyMessageBudget,
      dailyDiscoveryTaskBudget: dailyDiscoveryTaskBudget,
      topicCooldownMillis: topicCooldownMillis,
      discoveryIntervalMillis: discoveryIntervalMillis,
      monitorIntervalMillis: monitorIntervalMillis
    )
  }
}

enum SignalASIGlobalAgentTone {
  case accent
  case blue
  case green
  case purple
  case amber
  case neutral
}

enum SignalASIGlobalAgentDetailKind: String, CaseIterable, Identifiable {
  case goals
  case tasks
  case conflicts
  case links
  case cognition
  case runs
  case longHorizon
  case research
  case insights
  case learning
  case continuity

  var id: String { rawValue }
}

struct SignalASIGlobalAgentRowItem: Identifiable {
  var id: String
  var title: String
  var subtitle: String
  var systemImage: String
  var badge: String
  var tone: SignalASIGlobalAgentTone
}

struct SignalASIGlobalAgentDashboardSnapshot {
  var settings: GlobalAgentSettings
  var modelBudget: GlobalModelCallBudgetSnapshot
  var topicCount: Int
  var crossConversationLinkCount: Int
  var pendingInsightCount: Int
  var activeGoalCount: Int
  var activeTaskCount: Int
  var unresolvedConflictCount: Int
  var activeCognitionCount: Int
  var activeRunCount: Int
  var waitingConfirmationCount: Int
  var longHorizonGoalCount: Int
  var blockedLongHorizonGoalCount: Int
  var activeResearchCount: Int
  var feedbackCount: Int
  var learnedTopicCount: Int
  var continuityPendingCount: Int
  var continuityRetryingCount: Int
  var continuityQuarantinedCount: Int
  var goals: [SignalASIGlobalAgentRowItem]
  var tasks: [SignalASIGlobalAgentRowItem]
  var conflicts: [SignalASIGlobalAgentRowItem]
  var links: [SignalASIGlobalAgentRowItem]
  var cognition: [SignalASIGlobalAgentRowItem]
  var runs: [SignalASIGlobalAgentRowItem]
  var longHorizon: [SignalASIGlobalAgentRowItem]
  var research: [SignalASIGlobalAgentRowItem]
  var insights: [SignalASIGlobalAgentRowItem]
  var learning: [SignalASIGlobalAgentRowItem]
  var continuity: [SignalASIGlobalAgentRowItem]

  static func make(
    settings: GlobalAgentSettings,
    agentTasks: [AgentTaskRecord],
    sessions: [AgentConversation],
    memory: AgentMemorySnapshot,
    knowledgeStats: AgentKnowledgeStats,
    knowledgeAudit: [AgentKnowledgeAccessAuditEntry],
    automationTasks: [AgentProactiveTask],
    automationRuns: [AgentProactiveRun],
    proactiveMessages: [GlobalProactiveMessage] = [],
    proactiveFeedback: [GlobalAgentFeedback] = [],
    cognitionTasks: [GlobalCognitionTask],
    autonomousRuns: [GlobalAutonomousRun],
    longHorizonGoals: [GlobalLongHorizonGoal],
    researchState: GlobalResearchExecutorState,
    nowMillis: Int64 = GlobalRealtimeClock.nowMillis()
  ) -> SignalASIGlobalAgentDashboardSnapshot {
    let activeTasks = agentTasks.filter { Self.isActiveTask($0) }
    let activeCognition = cognitionTasks.filter { [.queued, .running, .waitingForResource].contains($0.status) }
    let activeRuns = autonomousRuns.filter { [.queued, .running, .replanning, .waitingForResource].contains($0.status) }
    let waitingConfirmations = autonomousRuns.filter { $0.status == .waitingConfirmation }.count +
      agentTasks.filter { $0.phase == .waitingConfirmation }.count
    let activeResearch = researchState.tasks.filter {
      [.queued, .running, .scheduled, .waitingForResource].contains($0.status)
    }
    let activeGoals = longHorizonGoals.filter {
      [.active, .inProgress, .waitingDependency, .waitingConfirmation, .blocked].contains($0.status)
    }
    let blockedGoals = longHorizonGoals.filter { $0.status == .blocked }
    let unresolvedConflicts = memory.conflicts.count + agentTasks.filter(\.blocked).count + blockedGoals.count
    let topics = Self.topicCount(
      tasks: agentTasks,
      goals: longHorizonGoals,
      knowledgeStats: knowledgeStats,
      automationTasks: automationTasks
    )
    let links = max(
      sessions.filter { $0.status != .archived && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count - 1,
      0
    )
    let modelBudget = GlobalModelCallBudgetPolicy.snapshot(
      state: researchState.modelBudget,
      dailyLimit: settings.dailyBackgroundModelCallBudget,
      concurrencyLimit: settings.maxConcurrentBackgroundModelCalls,
      nowMillis: nowMillis,
      dailyTokenLimit: settings.dailyBackgroundTokenBudget,
      dailyReportedCostLimitMicros: settings.dailyBackgroundReportedCostBudgetMicros
    )
    let inboxItems = GlobalProactiveInboxPolicy.project(
      messages: proactiveMessages,
      feedback: proactiveFeedback,
      limit: 80
    )
    let pendingInsights = inboxItems.isEmpty
      ? automationRuns.filter { $0.status == .waiting || $0.status == .failed }.count
      : inboxItems.count

    return SignalASIGlobalAgentDashboardSnapshot(
      settings: settings,
      modelBudget: modelBudget,
      topicCount: topics,
      crossConversationLinkCount: links,
      pendingInsightCount: pendingInsights,
      activeGoalCount: activeGoals.count,
      activeTaskCount: activeTasks.count,
      unresolvedConflictCount: unresolvedConflicts,
      activeCognitionCount: activeCognition.count,
      activeRunCount: activeRuns.count,
      waitingConfirmationCount: waitingConfirmations,
      longHorizonGoalCount: activeGoals.count,
      blockedLongHorizonGoalCount: blockedGoals.count,
      activeResearchCount: activeResearch.count,
      feedbackCount: proactiveFeedback.count + knowledgeAudit.count,
      learnedTopicCount: knowledgeStats.sourceCount,
      continuityPendingCount: researchState.events.count,
      continuityRetryingCount: cognitionTasks.filter { $0.status == .waitingForResource }.count +
        researchState.tasks.filter { $0.status == .waitingForResource }.count,
      continuityQuarantinedCount: agentTasks.filter { $0.phase == .failed && $0.blocked }.count,
      goals: Self.goalRows(activeGoals),
      tasks: Self.taskRows(activeTasks),
      conflicts: Self.conflictRows(memory: memory, tasks: agentTasks, goals: blockedGoals),
      links: Self.linkRows(sessions),
      cognition: Self.cognitionRows(cognitionTasks),
      runs: Self.runRows(autonomousRuns),
      longHorizon: Self.longHorizonRows(longHorizonGoals),
      research: Self.researchRows(researchState.tasks),
      insights: Self.insightRows(tasks: automationTasks, runs: automationRuns, inboxItems: inboxItems),
      learning: Self.learningRows(memory: memory, knowledgeStats: knowledgeStats, audit: knowledgeAudit),
      continuity: Self.continuityRows(researchState: researchState, cognitionTasks: cognitionTasks, blockedTasks: agentTasks.filter(\.blocked))
    )
  }

  func rows(for kind: SignalASIGlobalAgentDetailKind) -> [SignalASIGlobalAgentRowItem] {
    switch kind {
    case .goals: return goals
    case .tasks: return tasks
    case .conflicts: return conflicts
    case .links: return links
    case .cognition: return cognition
    case .runs: return runs
    case .longHorizon: return longHorizon
    case .research: return research
    case .insights: return insights
    case .learning: return learning
    case .continuity: return continuity
    }
  }

  func count(for kind: SignalASIGlobalAgentDetailKind) -> Int {
    switch kind {
    case .goals: return activeGoalCount
    case .tasks: return activeTaskCount
    case .conflicts: return unresolvedConflictCount
    case .links: return crossConversationLinkCount
    case .cognition: return activeCognitionCount
    case .runs: return activeRunCount + waitingConfirmationCount
    case .longHorizon: return longHorizonGoalCount
    case .research: return activeResearchCount
    case .insights: return pendingInsightCount
    case .learning: return feedbackCount + learnedTopicCount
    case .continuity: return continuityPendingCount + continuityRetryingCount + continuityQuarantinedCount
    }
  }

  var continuityStatusKey: String {
    if continuityQuarantinedCount > 0 { return "cc_global_continuity_attention" }
    if continuityRetryingCount > 0 || continuityPendingCount > 0 { return "cc_global_continuity_recovering" }
    return "cc_global_continuity_healthy"
  }

  private static func isActiveTask(_ task: AgentTaskRecord) -> Bool {
    [.observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused, .blocked].contains(task.phase)
  }

  private static func topicCount(
    tasks: [AgentTaskRecord],
    goals: [GlobalLongHorizonGoal],
    knowledgeStats: AgentKnowledgeStats,
    automationTasks: [AgentProactiveTask]
  ) -> Int {
    var topics = Set<String>()
    tasks.map(\.goal).forEach { insertTopic($0, into: &topics) }
    goals.map(\.topic).forEach { insertTopic($0, into: &topics) }
    goals.map(\.title).forEach { insertTopic($0, into: &topics) }
    automationTasks.map(\.name).forEach { insertTopic($0, into: &topics) }
    return max(topics.count, knowledgeStats.sourceCount)
  }

  private static func insertTopic(_ value: String, into topics: inout Set<String>) {
    let clean = GlobalAgentText.normalize(value)
    if !clean.isEmpty { topics.insert(clean) }
  }

  private static func goalRows(_ goals: [GlobalLongHorizonGoal]) -> [SignalASIGlobalAgentRowItem] {
    goals.sorted { $0.updatedAtMillis > $1.updatedAtMillis }.map { goal in
      SignalASIGlobalAgentRowItem(
        id: goal.id,
        title: goal.title.ifBlank(goal.topic),
        subtitle: goal.progressSummary.ifBlank(goal.description).ifBlank(goal.blocker),
        systemImage: "scope",
        badge: goal.status.rawValue,
        tone: goal.status == .blocked ? .amber : .purple
      )
    }
  }

  private static func taskRows(_ tasks: [AgentTaskRecord]) -> [SignalASIGlobalAgentRowItem] {
    tasks.sorted { $0.updatedAtMillis > $1.updatedAtMillis }.map { task in
      SignalASIGlobalAgentRowItem(
        id: task.taskId,
        title: task.goal,
        subtitle: task.targetTitle.ifBlank(task.executionLog.last ?? ""),
        systemImage: "checklist",
        badge: task.phase.rawValue,
        tone: task.blocked ? .amber : .blue
      )
    }
  }

  private static func conflictRows(
    memory: AgentMemorySnapshot,
    tasks: [AgentTaskRecord],
    goals: [GlobalLongHorizonGoal]
  ) -> [SignalASIGlobalAgentRowItem] {
    let memoryRows = memory.conflicts.map { conflict in
      SignalASIGlobalAgentRowItem(
        id: "memory:\(conflict.groupId)",
        title: conflict.key.ifBlank(conflict.kind.rawValue),
        subtitle: "\(conflict.candidates.count) memory versions disagree",
        systemImage: "exclamationmark.shield",
        badge: "MEMORY",
        tone: .amber
      )
    }
    let taskRows = tasks.filter(\.blocked).map { task in
      SignalASIGlobalAgentRowItem(
        id: "task:\(task.taskId)",
        title: task.goal,
        subtitle: task.executionLog.last ?? task.targetTitle,
        systemImage: "pause.circle",
        badge: task.phase.rawValue,
        tone: .amber
      )
    }
    let goalRows = goals.map { goal in
      SignalASIGlobalAgentRowItem(
        id: "goal:\(goal.id)",
        title: goal.title.ifBlank(goal.topic),
        subtitle: goal.blocker.ifBlank(goal.progressSummary),
        systemImage: "scope",
        badge: goal.status.rawValue,
        tone: .amber
      )
    }
    return memoryRows + taskRows + goalRows
  }

  private static func linkRows(_ sessions: [AgentConversation]) -> [SignalASIGlobalAgentRowItem] {
    sessions.filter { $0.status != .archived }.sorted { $0.updatedAt > $1.updatedAt }.map { session in
      SignalASIGlobalAgentRowItem(
        id: session.id,
        title: session.title,
        subtitle: session.summary.ifBlank(session.selectedModelOrAgent).ifBlank(session.contextPolicy),
        systemImage: "link",
        badge: session.status.rawValue,
        tone: .green
      )
    }
  }

  private static func cognitionRows(_ tasks: [GlobalCognitionTask]) -> [SignalASIGlobalAgentRowItem] {
    tasks.sorted { $0.updatedAtMillis > $1.updatedAtMillis }.map { task in
      SignalASIGlobalAgentRowItem(
        id: task.id,
        title: task.result.topic.ifBlank(task.baselineUnderstanding.topic).ifBlank(task.baselineIntent),
        subtitle: task.lastError.ifBlank(task.resourceId).ifBlank(task.baselineUnderstanding.intent),
        systemImage: "cpu",
        badge: task.status.rawValue,
        tone: [.queued, .running].contains(task.status) ? .purple : .neutral
      )
    }
  }

  private static func runRows(_ runs: [GlobalAutonomousRun]) -> [SignalASIGlobalAgentRowItem] {
    runs.sorted { $0.updatedAtMillis > $1.updatedAtMillis }.map { run in
      SignalASIGlobalAgentRowItem(
        id: run.id,
        title: run.topic.ifBlank(run.goal),
        subtitle: run.outcomeSummary.ifBlank(run.lastError).ifBlank("\(run.actions.count) actions"),
        systemImage: "play.circle",
        badge: run.status.rawValue,
        tone: run.status == .failed ? .amber : .green
      )
    }
  }

  private static func longHorizonRows(_ goals: [GlobalLongHorizonGoal]) -> [SignalASIGlobalAgentRowItem] {
    goals.sorted { $0.updatedAtMillis > $1.updatedAtMillis }.map { goal in
      SignalASIGlobalAgentRowItem(
        id: goal.id,
        title: goal.title.ifBlank(goal.topic),
        subtitle: goal.verificationSummary.ifBlank(goal.progressSummary).ifBlank(goal.description),
        systemImage: "calendar.badge.clock",
        badge: goal.status.rawValue,
        tone: goal.status == .blocked ? .amber : .purple
      )
    }
  }

  private static func researchRows(_ tasks: [GlobalResearchTask]) -> [SignalASIGlobalAgentRowItem] {
    tasks.sorted { $0.updatedAtMillis > $1.updatedAtMillis }.map { task in
      SignalASIGlobalAgentRowItem(
        id: task.id,
        title: task.question,
        subtitle: task.result.ifBlank(task.lastError).ifBlank(task.depth.rawValue),
        systemImage: "magnifyingglass",
        badge: task.status.rawValue,
        tone: [.queued, .running, .scheduled, .waitingForResource].contains(task.status) ? .blue : .neutral
      )
    }
  }

  private static func insightRows(
    tasks: [AgentProactiveTask],
    runs: [AgentProactiveRun],
    inboxItems: [GlobalProactiveInboxItem] = []
  ) -> [SignalASIGlobalAgentRowItem] {
    let inboxRows = inboxItems.map { item in
      SignalASIGlobalAgentRowItem(
        id: "inbox:\(item.id)",
        title: item.title,
        subtitle: item.content.ifBlank(item.topic),
        systemImage: item.urgent ? "exclamationmark.bubble" : "sparkles",
        badge: item.feedbackKind?.rawValue ?? (item.isNew ? "NEW" : item.target.rawValue),
        tone: item.urgent ? .amber : .purple
      )
    }
    let taskRows = tasks.sorted { $0.updatedAtMillis > $1.updatedAtMillis }.map { task in
      SignalASIGlobalAgentRowItem(
        id: "task:\(task.taskId)",
        title: task.name,
        subtitle: task.action.prompt.ifBlank(task.trigger.kind.rawValue),
        systemImage: "sparkles",
        badge: task.enabled ? "ENABLED" : "OFF",
        tone: task.enabled ? .purple : .neutral
      )
    }
    let taskNames = tasks.reduce(into: [String: String]()) { names, task in
      names[task.taskId] = task.name
    }
    let runRows = runs.sorted { $0.scheduledForMillis > $1.scheduledForMillis }.map { run in
      SignalASIGlobalAgentRowItem(
        id: "run:\(run.id)",
        title: (taskNames[run.taskId] ?? "").ifBlank(run.taskId),
        subtitle: run.resultSummary.ifBlank(run.errorCode).ifBlank(run.causeJson),
        systemImage: "bell.badge",
        badge: run.status.rawValue,
        tone: run.status == .failed ? .amber : .green
      )
    }
    return Array((inboxRows + taskRows + runRows).prefix(80))
  }

  private static func learningRows(
    memory: AgentMemorySnapshot,
    knowledgeStats: AgentKnowledgeStats,
    audit: [AgentKnowledgeAccessAuditEntry]
  ) -> [SignalASIGlobalAgentRowItem] {
    [
      SignalASIGlobalAgentRowItem(
        id: "memory",
        title: "Personal memory",
        subtitle: "\(memory.activeCount) active / \(memory.historyCount) previous versions",
        systemImage: "brain",
        badge: "\(memory.conflicts.count)",
        tone: memory.conflicts.isEmpty ? .green : .amber
      ),
      SignalASIGlobalAgentRowItem(
        id: "knowledge",
        title: "Knowledge sources",
        subtitle: "\(knowledgeStats.itemCount) items / \(knowledgeStats.sourceCount) sources",
        systemImage: "books.vertical",
        badge: "\(audit.count)",
        tone: .blue
      )
    ]
  }

  private static func continuityRows(
    researchState: GlobalResearchExecutorState,
    cognitionTasks: [GlobalCognitionTask],
    blockedTasks: [AgentTaskRecord]
  ) -> [SignalASIGlobalAgentRowItem] {
    [
      SignalASIGlobalAgentRowItem(
        id: "pending-events",
        title: "Pending event replay",
        subtitle: "\(researchState.events.count) events waiting to be folded into global context",
        systemImage: "arrow.triangle.2.circlepath",
        badge: "\(researchState.events.count)",
        tone: researchState.events.isEmpty ? .green : .blue
      ),
      SignalASIGlobalAgentRowItem(
        id: "retrying",
        title: "Retrying work",
        subtitle: "\(cognitionTasks.filter { $0.status == .waitingForResource }.count + researchState.tasks.filter { $0.status == .waitingForResource }.count) tasks waiting for resources",
        systemImage: "clock.arrow.circlepath",
        badge: "RETRY",
        tone: .blue
      ),
      SignalASIGlobalAgentRowItem(
        id: "quarantine",
        title: "Isolated failures",
        subtitle: "\(blockedTasks.count) blocked task records are isolated from autonomous progress",
        systemImage: "lock.shield",
        badge: "\(blockedTasks.count)",
        tone: blockedTasks.isEmpty ? .green : .amber
      )
    ]
  }
}
