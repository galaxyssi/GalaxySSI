package com.galaxyssi.chat

import org.json.JSONObject

/** Completion reads durable execution facts, never the token-budgeted planner projection. */
internal object AgentCompletionEvidenceHistory {
    fun resolve(plan: AgentPlan, scope: AgentPlanContinuationScope): List<AgentAction> =
        AgentProjectHistoryRetentionPolicy.latestSnapshots(
            (plan.actionHistory + plan.actions).filter(scope::owns)
        ).filterNot(AgentAction::isSupervisedProjectConnector)

    fun needsBusinessPostcondition(
        requirements: AgentCompletionRequirements?,
        history: List<AgentAction>,
        descriptorFor: (String) -> AgentNativeToolDescriptor?
    ): Boolean {
        if (requirements == null || requirements.outcomes.isNotEmpty() || requirements.artifacts.isNotEmpty() ||
            requirements.publication != AgentPublicationRequirement.NONE) return false
        return history.any { action ->
            val tool = action.parameters["tool_id"].orEmpty().ifBlank { action.target }
            action.kind == AgentActionKind.CALL_NATIVE_TOOL && !AgentObservedOutcomeEvidence.isUndispatched(action) &&
                action.status != AgentActionStatus.BLOCKED && descriptorFor(tool)?.requiresEffectClaim == true &&
                !isBrowserNavigation(action, tool) && !AgentGoalEvidence.hasVerifiedOutcome(listOf(action))
        }
    }

    private fun isBrowserNavigation(action: AgentAction, tool: String): Boolean {
        if (tool != AgentInteractiveBrowserTools.ACT || action.status != AgentActionStatus.COMPLETED ||
            AgentSupervisedProjectRecoveryPolicy.hasUnknownOutcome(action)) return false
        val input = runCatching { JSONObject(action.parameters["input_json"].orEmpty()) }.getOrNull() ?: return false
        // These mutate browser context, not the requested external business state. Click/fill/select
        // remain conservative: they can submit a form, send a message, or change a server-side value.
        return input.optString("operation") in setOf("create", "navigate", "back", "close")
    }
}
