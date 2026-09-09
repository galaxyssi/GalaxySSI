package com.galaxyssi.chat

internal const val AGENT_NODE_OBSERVATION_PENDING = "agent_node_observation_pending"

internal data class AgentPlanNodeKey(
    val sessionId: String,
    val planId: String,
    val actionId: String,
    val checkpointId: String,
    val conversationId: String,
    val turnId: String,
    val specificationHash: String
) {
    fun identity(): Map<String, String> = mapOf(
        "session" to sessionId, "plan" to planId, "action" to actionId,
        "checkpoint" to checkpointId, "conversation" to conversationId,
        "turn" to turnId, "specification" to specificationHash
    )

    companion object {
        fun from(sessionId: String, plan: AgentPlan, action: AgentAction): AgentPlanNodeKey? {
            val checkpoint = plan.checkpoints.lastOrNull {
                it.actionId == action.id && it.status == AgentCheckpointStatus.ACTIVE
            } ?: return null
            // History may add a display revision after dispatch; do not change that attempt's identity.
            val parameters = if (checkpoint.revisionParameterPresent == false &&
                action.parameters[PLAN_REVISION_PARAMETER] == checkpoint.planRevision.toString()) {
                action.parameters - PLAN_REVISION_PARAMETER
            } else action.parameters
            return AgentPlanNodeKey(sessionId, plan.planId, action.id, checkpoint.id,
                action.parameters[INTERNAL_CONVERSATION_ID].orEmpty().ifBlank { sessionId },
                action.parameters[INTERNAL_TURN_ID].orEmpty().ifBlank { plan.planId },
                AgentNativeJsonCodec.sha256(mapOf("kind" to action.kind.name, "target" to action.target,
                    "parameters" to parameters, "revision" to checkpoint.planRevision)))
        }
    }
}

internal data class AgentPlanNodeObservation(
    val result: AgentActionResult,
    val verified: Boolean,
    val evidence: String = ""
)

internal interface AgentPlanNodeJournal {
    fun start(key: AgentPlanNodeKey)
    fun record(key: AgentPlanNodeKey, observation: AgentPlanNodeObservation)
    fun read(key: AgentPlanNodeKey): AgentPlanNodeObservation?
}

/** Applies only evidence belonging to the currently checkpointed node attempt. */
internal object AgentPlanNodeRecovery {
    fun restoreOrReport(session: AgentSessionSnapshot, journal: AgentPlanNodeJournal): AgentSessionSnapshot = try {
        restore(session, journal)
    } catch (failure: Exception) {
        if (failure is java.util.concurrent.CancellationException) throw failure
        val failedPlan = session.currentPlan?.let { plan ->
            plan.copy(actions = plan.actions.map { action ->
                if (eligible(action)) action.copy(status = AgentActionStatus.FAILED,
                    evidence = AGENT_INTERRUPTED_EXECUTION_EVIDENCE,
                    result = failure.message ?: failure.javaClass.simpleName) else action
            })
        }
        session.copy(phase = AgentPhase.PAUSED, currentPlan = failedPlan,
            lastActionResult = AgentActionResult("agent-interrupted", false,
                "Plan node recovery failed: ${failure.message ?: failure.javaClass.simpleName}",
                mapOf("plan_node_recovery_error" to "true")))
    }

    fun restore(session: AgentSessionSnapshot, journal: AgentPlanNodeJournal): AgentSessionSnapshot {
        if (session.phase in setOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED)) return session
        val original = session.currentPlan ?: return session
        var plan = original
        var latest = session.lastActionResult
        original.actions.filter(::eligible).forEach { action ->
            val key = AgentPlanNodeKey.from(session.sessionId, original, action) ?: return@forEach
            val observation = journal.read(key) ?: return@forEach
            require(observation.result.actionId == action.id) { "Plan observation belongs to another node" }
            // Keep the loop continuation pending even when observation already committed.
            // Recovery must still run normal continuation/finalization, not just mark a task done.
            plan = plan.copy(actions = plan.actions.map { node ->
                if (node.id == action.id) node.copy(status = AgentActionStatus.RUNNING,
                    result = observation.result.message, evidence = AGENT_NODE_OBSERVATION_PENDING) else node
            })
            latest = observation.result
        }
        return if (plan == original) session else session.copy(currentPlan = plan, lastActionResult = latest)
    }

    fun eligible(action: AgentAction): Boolean = action.status == AgentActionStatus.RUNNING ||
        action.evidence in setOf(AGENT_INTERRUPTED_EXECUTION_EVIDENCE, AGENT_NODE_OBSERVATION_PENDING)

    fun applyVerified(plan: AgentPlan, action: AgentAction, observation: AgentPlanNodeObservation): AgentPlan {
        require(observation.verified && observation.result.actionId == action.id)
        val result = observation.result
        val status = when {
            !result.success -> AgentActionStatus.FAILED
            result.metadata["awaiting_response"] == "true" -> AgentActionStatus.WAITING_RESPONSE
            else -> AgentActionStatus.COMPLETED
        }
        return plan.addArtifactRichOutput(result.metadata["rich_output"].orEmpty())
            .markAction(action.id, status, result)
            .addVerification(AgentVerificationResult(actionId = action.id, success = result.success,
                observedApp = "", observedTitle = "", visibleTextCount = 0, clickableNodeCount = 0,
                evidence = observation.evidence.ifBlank { "durable_plan_node_observation" }))
    }
}
