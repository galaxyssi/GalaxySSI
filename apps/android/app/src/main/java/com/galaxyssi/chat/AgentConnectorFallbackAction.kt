package com.galaxyssi.chat

import java.util.Locale

internal object AgentConnectorFallbackAction {
    const val ATTEMPTED_PARAMETER = "routing_attempted_resource_ids"
    const val ATTEMPTED_RESULT = "attempted_resource_ids"
    private const val ACTION_ID_PARAMETER = "routing_fallback_action_id"

    fun hasActiveTrail(action: AgentAction): Boolean =
        action.parameters[ACTION_ID_PARAMETER] == action.id &&
            action.parameters[ATTEMPTED_PARAMETER].orEmpty().isNotBlank()

    fun forDispatch(action: AgentAction): AgentAction {
        val owner = action.parameters[ACTION_ID_PARAMETER] ?: return action
        if (owner == action.id) return action
        return action.copy(parameters = action.parameters - setOf(
            ACTION_ID_PARAMETER, ATTEMPTED_PARAMETER, "routing_deferred_retry_ids", "routing_retried_resource_ids"
        ))
    }

    fun prepare(
        action: AgentAction,
        selection: AgentConnectorFallbackSelection,
        target: AgentCallableTarget?
    ): AgentAction {
        // Model IDs and instance IDs belong to the previous resource, not the fallback.
        val parameters = action.parameters - setOf(
            "manual_model_id", "agent_model_id", "agent_reasoning_effort", "agent_instance_id"
        ) + mapOf(
            "connector_id" to selection.resourceId,
            "connector_kind" to target?.kind?.name.orEmpty().lowercase(Locale.ROOT),
            "connector_adapter_type" to target?.adapterType.orEmpty(),
            "connector_failure_domain" to target?.failureDomain.orEmpty(),
            ACTION_ID_PARAMETER to action.id,
            "routing_fallback_ids" to AgentConnectorFallbackTrail.encode(selection.remainingResourceIds),
            "routing_deferred_retry_ids" to AgentConnectorFallbackTrail.encode(selection.deferredRetryIds),
            "routing_retried_resource_ids" to AgentConnectorFallbackTrail.encode(selection.retriedResourceIds),
            ATTEMPTED_PARAMETER to AgentConnectorFallbackTrail.encode(selection.attemptedResourceIds)
        )
        return action.copy(
            target = target?.title ?: selection.resourceId,
            parameters = parameters,
            status = AgentActionStatus.PROPOSED,
            result = "",
            evidence = ""
        )
    }

    fun attempted(metadata: Map<String, String>): Set<String> =
        AgentConnectorFallbackTrail.parse(metadata[ATTEMPTED_RESULT].orEmpty()).toSet() +
            AgentConnectorFallbackTrail.parse(metadata["deferred_retry_ids"].orEmpty()) +
            AgentConnectorFallbackTrail.parse(metadata["retried_resource_ids"].orEmpty())

    fun dispatchIds(action: AgentAction): List<String> {
        val selected = action.parameters["connector_id"].orEmpty().trim()
        if (action.parameters["manual_target_locked"] == "true") return listOf(selected).filter(String::isNotBlank)
        val attempted = if (action.parameters[ACTION_ID_PARAMETER].let { it == null || it == action.id }) {
            AgentConnectorFallbackTrail.parse(action.parameters[ATTEMPTED_PARAMETER].orEmpty()).toSet()
        } else emptySet()
        return (listOf(selected) + AgentConnectorFallbackTrail.parse(action.parameters["routing_fallback_ids"].orEmpty()))
            .filter { it.isNotBlank() && (it == selected || it !in attempted) }.distinct()
    }

    fun resultMetadata(action: AgentAction): Map<String, String> = mapOf(
        ATTEMPTED_RESULT to action.parameters[ATTEMPTED_PARAMETER].orEmpty(),
        "remaining_fallback_ids" to action.parameters["routing_fallback_ids"].orEmpty(),
        "deferred_retry_ids" to action.parameters["routing_deferred_retry_ids"].orEmpty(),
        "retried_resource_ids" to action.parameters["routing_retried_resource_ids"].orEmpty(),
        "manual_target_locked" to action.parameters["manual_target_locked"].orEmpty()
    )
}
