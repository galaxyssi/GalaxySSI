package com.galaxyssi.chat

import android.content.Context

/** Freeze invocation options with their provider, independently of Auto routing. */
internal object AgentInvocationBinding {
    const val TARGET = "agent_invocation_target_id"
    private val OPTIONS = setOf("agent_model_id", "agent_reasoning_effort", "manual_model_id", "agent_instance_id")

    fun canonicalTargetId(targetId: String, availableTargetIds: List<String>): String {
        if (':' in targetId) return targetId
        return availableTargetIds.filter { it.endsWith(":$targetId") }.distinct().singleOrNull() ?: targetId
    }

    fun bind(context: Context, action: AgentAction, conversationId: String, targetId: String,
             availableTargetIds: List<String> = emptyList()): AgentAction {
        if (conversationId.isBlank() || targetId.isBlank()) return action
        val canonical = canonicalTargetId(targetId, availableTargetIds)
        if (action.parameters[TARGET] == canonical) return action
        return bind(action, canonical, AgentModelSelectionSettings.configurationForTarget(context, conversationId, canonical))
    }

    fun bind(action: AgentAction, targetId: String, saved: AgentTargetConfiguration?): AgentAction {
        val owner = action.parameters[TARGET] ?: action.parameters["connector_id"]
        val sameTarget = owner == targetId || (!owner.isNullOrBlank() && ':' !in owner && targetId.endsWith(":$owner"))
        if (sameTarget && action.parameters[TARGET] == targetId) return action
        val parameters = (if (sameTarget) action.parameters else action.parameters - OPTIONS).toMutableMap()
        // Explicit per-turn/manual options win. Auto fills missing options from this provider only.
        if (!parameters.containsKey("agent_model_id") && saved != null) parameters["agent_model_id"] = saved.modelId
        if (!parameters.containsKey("agent_reasoning_effort") && saved != null) {
            parameters["agent_reasoning_effort"] = saved.reasoningEffort.wireValue
        }
        parameters[TARGET] = targetId
        return action.copy(parameters = parameters)
    }
}
