package com.galaxyssi.chat

import org.json.JSONObject

internal object AgentVerifiedTimerStart {
    val toolId = AgentNativeToolAgentActionAdapter.defaultToolId(AgentActionKind.SET_ALARM)

    // The only work we may skip is the synthetic reviewer of this single operation.
    fun isReviewer(action: AgentAction, timerId: String): Boolean =
        action.isSupervisedProjectConnector() && action.outputSourceIds() == listOf(timerId) &&
            action.dependencyIds() == listOf(timerId)

    fun waitingStart(actions: List<AgentAction>, waitingId: String): AgentAction? {
        if (actions.size != 2) return null
        val timer = actions.singleOrNull { it.kind == AgentActionKind.CALL_NATIVE_TOOL &&
            it.parameters["tool_id"] == toolId && it.status == AgentActionStatus.COMPLETED } ?: return null
        return timer.takeIf { actions.any { it.id == waitingId && it.status == AgentActionStatus.WAITING_RESPONSE &&
            isReviewer(it, timer.id) } }
    }

    fun completion(goal: String, active: List<AgentAction>, action: AgentAction, result: AgentActionResult,
        output: JSONObject): AgentVerifiedProjectCompletion? {
        val observed = active.singleOrNull { it.id == action.id } ?: return null
        if (result.actionId != action.id || observed.kind != AgentActionKind.CALL_NATIVE_TOOL ||
            observed.parameters["tool_id"] != toolId || observed.status != AgentActionStatus.COMPLETED ||
            observed.parameters["input_json"] != action.parameters["input_json"])
            return null
        if (active.any { it.id != action.id && (!isReviewer(it, action.id) || it.status !in
                    setOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION, AgentActionStatus.WAITING_RESPONSE)) })
            return null
        val args = runCatching { JSONObject(action.parameters.getValue("input_json")) }.getOrNull()
            ?.optJSONObject("parameters") ?: return null
        if (args.optString("timer_operation", "start") != "start") return null
        val seconds = args.optString("timer_seconds").toIntOrNull()?.takeIf { it > 0 } ?: return null
        val requested = AgentDeviceIntent.completeDurationSeconds(goal) ?: AgentDeviceIntent.exactTimerSeconds(goal)
        if (requested != null && requested != seconds) return null
        if (requested == null && action.parameters[AgentSupervisedProjectCompletionPolicy.MODEL_TERMINAL_OUTCOME_PARAMETER] != "true")
            return null
        val meta = output.optJSONObject("metadata") ?: return null
        val id = meta.optString("operation_id")
        if (output.opt("success") != true || meta.optString("execution_authority") != "galaxyssi-phone" ||
            meta.optString("goal_status") != "verified" || meta.optString("business_success_verified") != "true" ||
            meta.optString("timer_state") != "running" || meta.optString("duration_seconds").toIntOrNull() != seconds ||
            id.isBlank() || args.optString("operation_id").let { it.isNotBlank() && it != id }) return null
        val message = output.optString("message").takeIf(String::isNotBlank) ?: return null
        return AgentVerifiedProjectCompletion(message, output.toString(), toolId)
    }
}
