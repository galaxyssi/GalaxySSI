package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** A blocked outcome is a retained task, not permission to replay its accepted effects. */
internal data class AgentRuntimeOutcomeContinuation(
    val sessionId: String, val conversationId: String, val turnId: String,
    val planId: String, val revision: Int, val actionIdsDigest: String
) {
    fun matches(session: String, scope: AgentPlanContinuationScope, plan: AgentPlan): Boolean =
        sessionId == session && conversationId == scope.conversationId && turnId == scope.turnId &&
            planId == plan.planId && revision == plan.revision && actionIdsDigest == pendingDigest(plan, scope)

    fun bind(result: AgentActionResult): AgentActionResult = result.copy(metadata = result.metadata + (KEY to
        JSONObject().put("session_id", sessionId).put("conversation_id", conversationId).put("turn_id", turnId)
            .put("plan_id", planId).put("revision", revision).put("action_ids_sha256", actionIdsDigest).toString()))

    companion object {
        const val KEY = "unverified_outcome_continuation"
        private fun pendingDigest(plan: AgentPlan, scope: AgentPlanContinuationScope): String? {
            val ids = AgentGoalEvidence.pendingReceipts(AgentCompletionEvidenceHistory.resolve(plan, scope))
                .map { it.actionId }.sorted()
            return ids.takeIf { it.isNotEmpty() }?.let { AgentNativeJsonCodec.sha256(it) }
        }

        fun forPlan(session: String, scope: AgentPlanContinuationScope, plan: AgentPlan): AgentRuntimeOutcomeContinuation? =
            pendingDigest(plan, scope)?.let { AgentRuntimeOutcomeContinuation(session, scope.conversationId,
                scope.turnId, plan.planId, plan.revision, it) }

        fun parse(result: AgentActionResult?): AgentRuntimeOutcomeContinuation? {
            if (result?.metadata?.get("failure_kind") != AgentOutcomeCompletion.FAILURE_KIND) return null
            return runCatching {
                val value = JSONObject(result.metadata.getValue(KEY))
                AgentRuntimeOutcomeContinuation(value.getString("session_id"), value.getString("conversation_id"),
                    value.getString("turn_id"), value.getString("plan_id"), value.getInt("revision"),
                    value.getString("action_ids_sha256"))
            }.getOrNull()?.takeIf {
                listOf(it.sessionId, it.conversationId, it.turnId, it.planId).none(String::isBlank) &&
                    it.revision > 0 && it.actionIdsDigest.length == 64 && it.actionIdsDigest.all { char -> char in "0123456789abcdef" }
            }
        }
    }
}

internal object AgentOutcomeCompletion {
    const val FAILURE_KIND = "business_outcome_unverified"

    fun blockedResult(base: AgentActionResult, receipts: List<AgentGoalEvidence.PendingReceipt>): AgentActionResult {
        require(receipts.isNotEmpty())
        return base.copy(success = false, message = receipts.map { it.message }.distinct().joinToString("\n"),
            metadata = base.metadata + mapOf("goal_status" to "blocked", "business_success_verified" to "false",
                "failure_kind" to FAILURE_KIND, "unverified_outcomes" to JSONArray(receipts.map { receipt ->
                    JSONObject().put("action_id", receipt.actionId).put("tool_id", receipt.toolId)
                        .put("required_capability", receipt.requiredCapability).put("next_action", receipt.nextAction)
                }).toString()))
    }

    fun pending(phase: AgentPhase, plan: AgentPlan, scope: AgentPlanContinuationScope?,
        descriptorFor: (String) -> AgentNativeToolDescriptor?): List<AgentGoalEvidence.PendingReceipt> {
        if (phase != AgentPhase.COMPLETED || plan.executionMode == AgentTaskExecutionMode.PLAN_ONLY) return emptyList()
        // A conflicting owner cannot borrow history or complete an uncertain current action.
        if (scope == null) return AgentGoalEvidence.pendingReceipts(plan.actions).map { it.copy(
            message = "The task outcome cannot be verified because its execution ownership is inconsistent.",
            requiredCapability = "valid_task_ownership") }
        return AgentPendingOutcomeEvidence.unresolved(plan.completionRequirements,
            AgentCompletionEvidenceHistory.resolve(plan, scope), descriptorFor).map { it.receipt }
    }
}

internal fun MobileNativeAgent.guardOutcomeCompletion() {
    val plan = currentPlan ?: return
    if (phase != AgentPhase.COMPLETED && !(phase == AgentPhase.BLOCKED &&
            lastActionResult?.metadata?.get("failure_kind") == AgentOutcomeCompletion.FAILURE_KIND)) return
    val scope = AgentPlanContinuationScope.resolve(plan, activeConversationContext.conversationId,
        activeConversationTurnId, sessionId)
    val receipts = AgentOutcomeCompletion.pending(AgentPhase.COMPLETED, plan, scope) {
        nativeToolRegistry.lookup(it)?.descriptor
    }
    if (receipts.isEmpty()) return
    val base = lastActionResult ?: AgentActionResult(receipts.first().actionId, false, "")
    var blocked = AgentOutcomeCompletion.blockedResult(base, receipts)
    if (scope != null) blocked = AgentRuntimeOutcomeContinuation.forPlan(sessionId, scope, plan)?.bind(blocked) ?: blocked
    phase = AgentPhase.BLOCKED
    lastActionResult = blocked
    appendAudits(AgentAuditRecord(AgentAuditEvent.ACTION_BLOCKED,
        "business_outcome_unverified:actions=${receipts.joinToString(",") { it.actionId }}"))
}

internal fun MobileNativeAgent.continueBlockedOutcome(): AgentUiState {
    val plan = currentPlan ?: return snapshot()
    val saved = AgentRuntimeOutcomeContinuation.parse(lastActionResult) ?: return snapshot()
    val scope = AgentPlanContinuationScope.resolve(plan, activeConversationContext.conversationId,
        activeConversationTurnId, sessionId) ?: return snapshot()
    if (phase != AgentPhase.BLOCKED || !saved.matches(sessionId, scope, plan) || planningWasStopped()) return snapshot()
    val candidate = AgentUnverifiedOutcomeRecovery.reviewCandidate(plan, scope,
        { nativeToolRegistry.lookup(it)?.descriptor }, resumingBlockedOutcome = true) { action ->
        AgentPlanNodeKey.from(sessionId, plan, action)?.let {
            planNodeJournal.read(it)?.result
        }
    } ?: return snapshot()
    val continued = continueUnverifiedOutcome(plan, candidate.first, candidate.second, resumingBlockedOutcome = true)
    if (continued === plan || continued.safetyReview.blocked || planningWasStopped()) return snapshot()
    val loop = executionLoop.snapshot
    if (loop != null && loop.phase != AgentExecutionLoopPhase.BLOCKED) {
        if (loop.phase.isTerminal || loop.phase == AgentExecutionLoopPhase.WAITING_RESPONSE) return snapshot()
        if (!advanceExecutionLoop(AgentExecutionLoopPhase.BLOCKED, "Outcome verification remains pending")) return snapshot()
    }
    if (!advanceExecutionLoop(AgentExecutionLoopPhase.PLAN, "Resuming read-first outcome verification", retry = true))
        return snapshot()
    currentPlan = continued
    phase = if (continued.safetyReview.requiresConfirmation) AgentPhase.WAITING_CONFIRMATION else AgentPhase.PLANNING
    recordAudit(AgentAuditEvent.TASK_RESUMED, "unverified_outcome_review:revision=${continued.revision}")
    saveTaskRecord()
    return reconcileExecutionLoop(if (phase == AgentPhase.PLANNING) executeFirstPendingAction() else snapshot())
}
