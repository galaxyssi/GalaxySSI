package com.galaxyssi.chat

import java.util.Locale

/** Reuse the nearest owned goal, never search past an intervening request for an executable one. */
internal object AgentSupervisedProjectContinuationPolicy {
    fun wantsContext(request: String): Boolean = AgentDeviceIntent.needsOperationContext(request) ||
        AgentActiveTurnPolicy.hasExplicitContinuationLead(request)

    fun scopedOperation(context: AgentConversationContext, operation: AgentDeviceOperation?): AgentDeviceOperation? {
        if (operation == null || operation.conversationId != context.conversationId || operation.status == "cancelled") return null
        // Timer controls retain their existing dedicated context and executor.
        if (operation.kind == "timer") return operation.takeUnless { it.status == "completed" }
        val latest = userTurns(context).lastOrNull() ?: return null
        return operation.takeIf { it.kind == "agent" && it.goal.isNotBlank() &&
            it.sourceTurnId.isNotBlank() && it.sourceTurnId == latest.turnId && owns(context, latest) }
    }

    fun mergedGoal(
        latestRequest: String,
        conversationContext: AgentConversationContext,
        independentRequest: Boolean = false,
        operation: AgentDeviceOperation? = null
    ): String? {
        val request = latestRequest.trim()
        if (independentRequest || (!AgentActiveTurnPolicy.hasExplicitContinuationLead(request) && AgentDeviceIntent.followup(request) == null) ||
            AgentActiveTurnPolicy.decide(request, "scoped goal").disposition == AgentActiveTurnDisposition.INTERRUPT) return null
        val turns = userTurns(conversationContext)
        val latest = turns.lastOrNull() ?: return null
        if (!owns(conversationContext, latest)) return null
        if (operation?.conversationId == conversationContext.conversationId &&
            operation.sourceTurnId.isNotBlank() && operation.sourceTurnId == latest.turnId &&
            operation.status == "cancelled") return null
        val scoped = scopedOperation(conversationContext, operation)?.takeIf { it.kind == "agent" }
        val priorGoal = scoped?.goal ?: nearestTranscriptGoal(conversationContext, turns) ?: return null
        return AgentActiveTurnPolicy.supersedingGoal(priorGoal, request, AgentActiveTurnInterventionKind.CONSTRAINT) +
            "\nUse prior observations as context, not permission to repeat completed effects. Inspect before retrying uncertain work."
    }

    private fun nearestTranscriptGoal(context: AgentConversationContext, turns: List<AgentTranscriptEntry>): String? {
        for (entry in turns.asReversed()) {
            if (!owns(context, entry)) return null
            val candidate = entry.text.trim()
            if (isBareContinuation(candidate)) continue
            // Nontrivial intervening instructions belong to the model unless a scoped checkpoint already resolves them.
            return candidate.takeIf { it.isNotBlank() && !AgentActiveTurnPolicy.hasExplicitContinuationLead(it) &&
                AgentSupervisedProjectRoutingPolicy.requiresModelDirectedExecution(it) }
        }
        return null
    }

    private fun userTurns(context: AgentConversationContext) = context.turns.filter { it.role == AgentTranscriptRole.USER }
    private fun owns(context: AgentConversationContext, entry: AgentTranscriptEntry): Boolean =
        (entry.conversationId.isBlank() || entry.conversationId == context.conversationId) &&
            (entry.sourceConversationId.isBlank() || entry.sourceConversationId == context.conversationId)

    private fun isBareContinuation(value: String): Boolean = value.lowercase(Locale.ROOT).trim()
        .trimEnd('.', '!', '?', '\u3002', '\uff01', '\uff1f') in setOf(
            "continue", "resume", "keep going", "go on", "retry", "try again",
            "\u7ee7\u7eed", "\u7e7c\u7e8c", "\u63a5\u7740", "\u91cd\u8bd5", "\u518d\u8bd5\u8bd5")
}
