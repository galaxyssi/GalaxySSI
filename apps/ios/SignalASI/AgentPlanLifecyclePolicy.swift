import Foundation

struct AgentPlanLifecycleNormalization: Equatable {
  var plan: AgentPlan
  var removedActions: [AgentAction]

  var changed: Bool {
    !removedActions.isEmpty
  }

  func recoverResult(previous: AgentActionResult?) -> AgentActionResult? {
    guard changed else {
      return previous
    }
    let removedIds = Set(removedActions.map(\.id))
    if let previous,
      !removedIds.contains(previous.actionId),
      !previous.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return previous
    }
    guard let action = plan.actions.reversed().first(where: {
      !$0.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Self.resultStatuses.contains($0.status)
    }) else {
      return previous
    }
    return AgentActionResult(
      actionId: action.id,
      success: action.status == .completed,
      message: action.result
    )
  }

  private static let resultStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked
  ]
}

struct AgentSessionLifecycleNormalization: Equatable {
  var session: AgentSessionSnapshot
  var removedActions: [AgentAction]

  var changed: Bool {
    !removedActions.isEmpty
  }
}

enum AgentPlanLifecyclePolicy {
  static func normalize(_ plan: AgentPlan) -> AgentPlanLifecycleNormalization {
    let legacyRuntimeDrafts = !plan.actions.isEmpty &&
      plan.actions.allSatisfy {
        $0.kind == .draftPlan &&
          $0.target.caseInsensitiveCompare(localAgentRuntimeTarget) == .orderedSame
      } ? plan.actions : []

    if !legacyRuntimeDrafts.isEmpty {
      let recovered = recoverCompletedHistory(plan: plan, drafts: legacyRuntimeDrafts)
      if recovered.changed {
        return recovered
      }
      return retireLegacyRuntimeFallback(plan: plan, drafts: legacyRuntimeDrafts)
    }

    let trailingDrafts = trailingRetirableDrafts(plan.actions)
    if trailingDrafts.isEmpty {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    if trailingDrafts.count == plan.actions.count {
      return recoverCompletedHistory(plan: plan, drafts: trailingDrafts)
    }
    let retainedActions = Array(plan.actions.dropLast(trailingDrafts.count))
    if !retainedActions.contains(where: { $0.kind != .draftPlan }) {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    let removedIds = Set(trailingDrafts.map(\.id))
    var normalized = plan
    normalized.actions = retainedActions
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: trailingDrafts)
  }

  static func normalize(_ session: AgentSessionSnapshot) -> AgentSessionLifecycleNormalization {
    guard let plan = session.currentPlan else {
      return AgentSessionLifecycleNormalization(session: session, removedActions: [])
    }
    let planNormalization = normalize(plan)
    guard planNormalization.changed else {
      return AgentSessionLifecycleNormalization(session: session, removedActions: [])
    }
    var normalizedSession = session
    normalizedSession.phase = resolvedPhase(plan: planNormalization.plan, fallback: session.phase)
    normalizedSession.currentPlan = planNormalization.plan
    normalizedSession.lastActionResult = planNormalization.recoverResult(previous: session.lastActionResult)
    return AgentSessionLifecycleNormalization(
      session: normalizedSession,
      removedActions: planNormalization.removedActions
    )
  }

  static func recoverCompletedConnector(
    session: AgentSessionSnapshot,
    persistedTask: AgentTaskRecord?,
    missingResult: String
  ) -> AgentSessionSnapshot {
    guard let plan = session.currentPlan else {
      return session
    }
    let receivedConnectorResponse = session.auditTrail.contains {
      $0.event == .connectorResponseReceived
    }
    let staleRuntimeDrafts = !plan.actions.isEmpty &&
      plan.actions.allSatisfy {
        $0.kind == .draftPlan &&
          $0.target.caseInsensitiveCompare(localAgentRuntimeTarget) == .orderedSame
      }
    guard receivedConnectorResponse, staleRuntimeDrafts else {
      return session
    }

    let durableResult = durableConnectorResult(from: persistedTask)
    let previousResult = session.lastActionResult.flatMap { result -> String? in
      guard !isBlank(result.message),
        plan.actions.allSatisfy({ $0.id != result.actionId }) else {
        return nil
      }
      return result.message
    } ?? ""
    let resultText = firstNonBlank(durableResult, previousResult, missingResult.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !isBlank(resultText) else {
      return session
    }

    let recoveredAction: AgentAction
    if var historicalConnector = plan.actionHistory.reversed().first(where: { $0.kind == .callConnector }) {
      historicalConnector.status = .completed
      historicalConnector.result = resultText
      historicalConnector.evidence = restoredConnectorEvidence
      recoveredAction = historicalConnector
    } else {
      recoveredAction = AgentAction(
        id: "restored-connector-result",
        kind: .callConnector,
        target: firstNonBlank(persistedTask?.targetTitle ?? "", plan.route.targetTitle, "remote-agent"),
        risk: persistedTask?.risk ?? .low,
        status: .completed,
        description: "Restore completed remote Agent result",
        requiresConfirmation: false,
        result: resultText,
        evidence: restoredConnectorEvidence
      )
    }

    var normalizedPlan = plan
    normalizedPlan.actions = [recoveredAction]
    normalizedPlan.selectedAgentOrModel = recoveredAction.target
    normalizedPlan.expectedResult = resultText
    normalizedPlan.actionHistory = plan.actionHistory.filter { $0.id != recoveredAction.id }
    normalizedPlan.confirmationRequired = false
    normalizedPlan.validation = AgentPlanValidator.validate(normalizedPlan)

    var normalizedSession = session
    normalizedSession.phase = .completed
    normalizedSession.currentPlan = normalizedPlan
    normalizedSession.lastActionResult = AgentActionResult(
      actionId: recoveredAction.id,
      success: true,
      message: resultText
    )
    return normalizedSession
  }

  private static func recoverCompletedHistory(
    plan: AgentPlan,
    drafts: [AgentAction]
  ) -> AgentPlanLifecycleNormalization {
    guard let recoveredIndex = plan.actionHistory.lastIndex(where: {
      $0.kind != .draftPlan &&
        $0.status == .completed &&
        !isBlank($0.result)
    }) else {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    let recoveredAction = plan.actionHistory[recoveredIndex]
    var retainedHistory = plan.actionHistory
    retainedHistory.remove(at: recoveredIndex)
    let removedIds = Set(drafts.map(\.id))
    var normalized = plan
    normalized.actions = [recoveredAction]
    normalized.actionHistory = retainedHistory
    normalized.selectedAgentOrModel = recoveredAction.target
    normalized.expectedResult = recoveredAction.result
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: drafts)
  }

  private static func retireLegacyRuntimeFallback(
    plan: AgentPlan,
    drafts: [AgentAction]
  ) -> AgentPlanLifecycleNormalization {
    guard var retired = drafts.last else {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    retired.target = taskCompleteTarget
    retired.status = .failed
    retired.description = "Task routing failed"
    retired.requiresConfirmation = false
    retired.result = "No Agent or model accepted this task. Send it again to retry with current resources."
    retired.evidence = "retired_legacy_runtime_fallback"
    var normalized = plan
    normalized.actions = [retired]
    normalized.selectedAgentOrModel = ""
    normalized.expectedResult = retired.result
    normalized.confirmationRequired = false
    normalized.route = AgentRoute()
    normalized.routeRationale = "Legacy internal planner fallback retired."
    let removedIds = Set(drafts.map(\.id))
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: drafts)
  }

  private static func resolvedPhase(plan: AgentPlan, fallback: AgentPhase) -> AgentPhase {
    if plan.actions.contains(where: { $0.status == .waitingResponse }) {
      return .waitingResponse
    }
    if plan.actions.contains(where: { $0.status == .running }) {
      return .paused
    }
    if plan.actions.contains(where: { $0.status == .pendingConfirmation || $0.status == .proposed }) {
      return .waitingConfirmation
    }
    if plan.actions.contains(where: { $0.status == .failed }) {
      return .failed
    }
    if plan.actions.contains(where: { $0.status == .blocked }) {
      return .blocked
    }
    if !plan.actions.isEmpty && plan.actions.allSatisfy({ terminalStatuses.contains($0.status) }) {
      return .completed
    }
    return fallback
  }

  private static func trailingRetirableDrafts(_ actions: [AgentAction]) -> [AgentAction] {
    var drafts: [AgentAction] = []
    for action in actions.reversed() {
      guard action.kind == .draftPlan,
        action.target.caseInsensitiveCompare(taskCompleteTarget) != .orderedSame else {
        break
      }
      drafts.append(action)
    }
    return Array(drafts.reversed())
  }

  private static func durableConnectorResult(from task: AgentTaskRecord?) -> String {
    guard let task,
      !isBlank(task.result),
      task.targetTitle.caseInsensitiveCompare(localAgentRuntimeTarget) != .orderedSame,
      connectorRouteKinds.contains(task.routeKind) else {
      return ""
    }
    return task.result
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values.first { !isBlank($0) } ?? ""
  }

  private static func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static let terminalStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked,
    .rolledBack
  ]
  private static let connectorRouteKinds: Set<AgentRouteKind> = [
    .desktopAgent,
    .cloudModel,
    .localModel
  ]
  private static let taskCompleteTarget = "task-complete"
  private static let localAgentRuntimeTarget = "local-agent-runtime"
  private static let restoredConnectorEvidence = "restored_connector_terminal_result"
}
