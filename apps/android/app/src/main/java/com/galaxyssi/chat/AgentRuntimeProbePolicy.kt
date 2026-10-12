package com.galaxyssi.chat

/** Missing health evidence must not destroy a multiplexed guest or its in-flight work. */
internal object AgentRuntimeProbePolicy {
    fun shouldDiscardBridge(health: AgentRuntimeBridgeHealth): Boolean =
        health.observationConfirmed && !health.ready

    fun mayLaunchEngine(engineRunning: Boolean): Boolean = !engineRunning

    fun unavailableReason(health: AgentRuntimeBridgeHealth?): String = when {
        health?.observationConfirmed != true ->
            "Runtime engine is running; guest health is unconfirmed. Existing work was not restarted."
        else -> health.reason.ifBlank {
            "Runtime engine is running, but the guest reported that it is not ready"
        }
    }
}
