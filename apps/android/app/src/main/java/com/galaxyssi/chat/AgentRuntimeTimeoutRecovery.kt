package com.galaxyssi.chat

/** A request deadline is not proof that the shared guest has failed. */
internal object AgentRuntimeTimeoutRecovery {
    fun shouldQuarantine(error: Throwable, health: AgentRuntimeBridgeHealth?): Boolean =
        error is AgentNativeToolTimeoutException && health?.observationConfirmed == true && !health.ready

    fun evidence(health: AgentRuntimeBridgeHealth?, reset: Boolean): AgentNativeJsonObject = buildMap {
        put("goal_terminal", false)
        put("runtime_reset", reset)
        put("runtime_health_observed", health?.observationConfirmed == true)
        if (health?.observationConfirmed == true) put("runtime_ready", health.ready)
        put("next_action", "inspect_current_state_before_repeating_a_mutation")
    }
}
