package com.galaxyssi.chat

import org.json.JSONObject

/** Display/history compaction must not change the executable graph or its tool arguments. */
internal fun SharedPreferencesAgentSessionStore.encodeDurableActivePlan(plan: AgentPlan, sessionGoal: String): Sequence<String> = sequence {
    fun record(kind: String, value: JSONObject) = JSONObject().put("kind", kind).put("value", value).toString()
    val header = encodePlan(plan.copy(actions = emptyList(), actionHistory = emptyList(), checkpoints = emptyList(),
        steps = emptyList(), verificationResults = emptyList(), artifactRichOutputJson = ""))
        .put("goal", plan.goal).put("session_goal", sessionGoal).put("artifact_rich_output", plan.artifactRichOutputJson)
    yield(record("header", header))
    plan.actions.forEach { yield(record("actions", encodeExecutableAction(it))) }
    plan.actionHistory.forEach { yield(record("action_history", encodeExecutableAction(it))) }
    plan.checkpoints.forEach { checkpoint -> yield(record("checkpoints",
        encodeCheckpoint(checkpoint).put("rollback_action", checkpoint.rollbackAction?.let(::encodeExecutableAction)))) }
    plan.steps.forEach { yield(record("steps", encodeStep(it))) }
    plan.verificationResults.forEach { yield(record("verification_results", encodeVerificationResult(it))) }
}

private fun SharedPreferencesAgentSessionStore.encodeExecutableAction(action: AgentAction): JSONObject =
    encodeAction(action).put("description", action.description).put("parameters", JSONObject(action.parameters))
        .put("result", action.result).put("evidence", action.evidence)

internal fun SharedPreferencesAgentSessionStore.restoreDurableActivePlan(
    snapshot: AgentSessionSnapshot, root: JSONObject, persistence: AgentActivePlanPersistence
): AgentSessionSnapshot {
    if (!root.has(AgentActivePlanPersistence.ROOT_KEY) || root.isNull(AgentActivePlanPersistence.ROOT_KEY)) return snapshot
    return try {
        val plan = persistence.read(snapshot.sessionId, root.getJSONObject(AgentActivePlanPersistence.ROOT_KEY))
        snapshot.copy(currentPlan = decodePlan(plan), currentGoal = plan.optString("session_goal", snapshot.currentGoal))
    } catch (error: Exception) {
        val reason = "Active plan recovery failed: ${error.message.orEmpty()}"
        snapshot.copy(currentPlan = null,
            phase = if (snapshot.phase in setOf(AgentPhase.CANCELLED, AgentPhase.COMPLETED)) snapshot.phase else AgentPhase.PAUSED,
            lastActionResult = AgentActionResult("active-plan-recovery", false, reason,
                mapOf("active_plan_recovery_error" to "true")),
            executionLoopSnapshot = snapshot.executionLoopSnapshot?.let { loop ->
                if (loop.phase.isTerminal) loop else loop.copy(phase = AgentExecutionLoopPhase.PAUSED,
                    resumePhase = loop.phase.takeIf { it.isActive } ?: loop.resumePhase,
                    usage = loop.usage.copy(activeSinceMillis = 0L), lastReason = reason, revision = loop.revision + 1)
            })
    }
}
