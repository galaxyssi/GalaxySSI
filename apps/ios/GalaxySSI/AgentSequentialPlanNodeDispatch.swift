import Foundation

enum AgentSequentialPlanNodeDispatch {
  struct Prepared {
    var plan: AgentPlan
    var action: AgentAction
    var checkpoint: AgentExecutionCheckpoint
    var key: AgentPlanNodeKey
  }
  struct Replay {
    var action: AgentAction
    var result: AgentActionResult
  }

  static func prepare(plan: AgentPlan, action: AgentAction, screen: AgentScreenContext,
    sessionId: String, conversationId: String, turnId: String) -> Prepared? {
    guard plan.revision > 0, plan.actions.filter({ $0.id == action.id }).count == 1,
          plan.checkpoints.filter({ $0.actionId == action.id && $0.status == .active }).count <= 1,
          let index = plan.actions.firstIndex(where: { $0.id == action.id }) else { return nil }
    var staged = plan, running = action
    running.status = .running
    staged.actions[index] = running
    if !staged.checkpoints.contains(where: { $0.actionId == action.id && $0.status == .active }) {
      staged = staged.addCheckpoint(AgentExecutionContinuity.checkpointBefore(action: action, screen: screen,
        planRevision: plan.revision))
    }
    guard let checkpoint = staged.checkpoints.last(where: { $0.actionId == action.id && $0.status == .active }),
          checkpoint.planRevision == plan.revision,
          let key = AgentPlanNodeKey.make(sessionId: sessionId, plan: staged, action: running,
            conversationId: conversationId, turnId: turnId) else { return nil }
    return Prepared(plan: staged, action: running, checkpoint: checkpoint, key: key)
  }

  static func replay(plan: AgentPlan?, actionId: String, sessionId: String, conversationId: String,
    turnId: String, journal: EncryptedAgentPlanNodeJournal) throws -> Replay? {
    guard let plan else { return nil }
    let actions = plan.actions.filter { $0.id == actionId }
    let checkpoints = plan.checkpoints.filter { $0.actionId == actionId && $0.status == .active }
    guard plan.revision > 0, actions.count <= 1, checkpoints.count <= 1 else {
      throw AgentPlanNodeJournalError.identityMismatch
    }
    guard let action = actions.first, let checkpoint = checkpoints.first else { return nil }
    guard checkpoint.planRevision == plan.revision,
          let key = AgentPlanNodeKey.make(sessionId: sessionId, plan: plan, action: action,
            conversationId: conversationId, turnId: turnId) else { throw AgentPlanNodeJournalError.identityMismatch }
    guard let claim = try journal.observe(key) else { return nil }
    let dispatch = try journal.readDispatch(key)
    if let dispatch {
      guard dispatch.action.id == actionId, dispatch.checkpoint == checkpoint else {
        throw AgentPlanNodeJournalError.identityMismatch
      }
    }
    let dispatched = dispatch?.action ?? action
    switch claim {
    case .observed(let observation) where observation.verified && observation.result.actionId == actionId:
      return Replay(action: dispatched, result: observation.result)
    case .pending, .observed:
      return Replay(action: dispatched, result: unknown(actionId))
    case .acquired:
      throw AgentPlanNodeJournalError.identityMismatch
    }
  }

  static func execute(_ prepared: Prepared, journal: EncryptedAgentPlanNodeJournal,
    operation: () -> AgentActionResult) -> AgentActionResult {
    guard prepared.plan.revision > 0, prepared.checkpoint.planRevision == prepared.plan.revision,
          prepared.plan.checkpoints.filter({ $0.actionId == prepared.action.id && $0.status == .active }) == [prepared.checkpoint],
          prepared.plan.actions.filter({ $0.id == prepared.action.id }) == [prepared.action],
          AgentPlanNodeKey.make(sessionId: prepared.key.sessionId, plan: prepared.plan, action: prepared.action,
            conversationId: prepared.key.conversationId, turnId: prepared.key.turnId) == prepared.key else {
      return AgentActionResult(actionId: prepared.action.id, success: false, message: "The prepared plan-node identity is inconsistent.",
        metadata: ["plan_node_journal_error": "identity_mismatch", "execution_started": "false", "non_retriable": "true"])
    }
    do {
      let claim = try journal.claim(prepared.key, action: prepared.action, checkpoint: prepared.checkpoint)
      let dispatch = try journal.readDispatch(prepared.key)
      if let dispatch {
        guard dispatch.action.id == prepared.action.id, dispatch.checkpoint == prepared.checkpoint else {
          throw AgentPlanNodeJournalError.identityMismatch
        }
      } else if claim == .acquired { throw AgentPlanNodeJournalError.missingDispatch }
      switch claim {
      case .observed(let observation):
        return observation.verified && observation.result.actionId == prepared.action.id
          ? observation.result : unknown(prepared.action.id)
      case .pending:
        return unknown(prepared.action.id)
      case .acquired:
        let result = operation()
        do {
          try journal.record(prepared.key, observation: .init(result: result, verified: true,
            evidence: result.metadata["evidence"] ?? result.metadata["receipt"] ?? "durable_plan_node_observation"))
          return result
        } catch {
          return unknown(prepared.action.id, error: "observation_commit_failed")
        }
      }
    } catch {
      return AgentActionResult(actionId: prepared.action.id, success: false,
        message: "The plan node could not acquire durable execution ownership.",
        metadata: ["plan_node_journal_error": "dispatch_claim_failed", "execution_started": "false", "non_retriable": "true"])
    }
  }

  private static func unknown(_ actionId: String, error: String = "observation_pending") -> AgentActionResult {
    AgentActionResult(actionId: actionId, success: false,
      message: "This plan node has a prior dispatch but no verified durable result. It will not be repeated.",
      metadata: ["plan_node_outcome_unknown": "true", "plan_node_journal_error": error,
        "evidence": agentPlanNodeObservationPendingEvidence, "non_retriable": "true"])
  }
}
