package com.galaxyssi.chat

/** Keep the business blocker distinct from a policy denial and from a finished failed run. */
internal object AgentBlockedStatePolicy {
    fun reason(state: AgentUiState, fallback: String = "Task blocked"): String {
        if (state.phase != AgentPhase.BLOCKED) return ""
        return state.plan?.safetyReview?.takeIf { it.blocked }?.reason?.trim()?.takeIf(String::isNotEmpty)
            ?: state.lastActionResult?.takeUnless { it.success }?.message?.trim()?.takeIf(String::isNotEmpty)
            ?: fallback
    }

    fun retainsRun(state: AgentUiState): Boolean =
        AgentOutcomeCompletion.isBlocked(state.phase, state.lastActionResult) ||
            AgentRuntimePermissionContinuation.waiting(state) != null

    fun outcomeWaitEvent(state: AgentUiState, runId: String, conversationId: String, turnId: String,
        deviceId: String): AgentRunControlEvent? {
        if (!AgentOutcomeCompletion.isBlocked(state.phase, state.lastActionResult)) return null
        val loop = state.executionLoop ?: return null
        val plan = state.plan ?: return null
        val scope = AgentPlanContinuationScope.resolve(plan, "", "", state.sessionId) ?: return null
        if (runId.isBlank() || scope.conversationId != conversationId || scope.turnId != turnId ||
            loop.taskId != turnId) return null
        val reason = reason(state)
        val key = AgentNativeJsonCodec.sha256(mapOf("session" to state.sessionId, "run" to runId,
            "conversation" to conversationId, "turn" to turnId, "plan" to plan.planId,
            "revision" to plan.revision, "loop_revision" to loop.revision, "reason" to reason,
            "at" to loop.updatedAtMillis, "device" to deviceId))
        return AgentRunControlEvent(eventId = "outcome-wait:$key", conversationId = conversationId,
            messageId = turnId, taskId = turnId, runId = runId, agentId = "galaxyssi-mobile", deviceId = deviceId,
            type = AgentRunControlEventType.WAITING_FOR_USER, sequence = 0L,
            timestampMillis = loop.updatedAtMillis,
            payload = mapOf("timeline_contract" to AgentRunTimelineContract.VERSION, "timeline_kind" to "other",
                "loop_outcome_wait" to true, "loop_reason" to reason, "loop_revision" to loop.revision))
    }
}
