package com.galaxyssi.chat

/** These read-only polls already have a caller-owned timeout/refresh loop. */
internal object MqttQueryDeliveryPolicy {
    private val transientQueries = setOf(
        "connector_status_request", "agent_task_recovery_request", "agent_task_result_page_request",
        "evolution_task_list_request", "desktop_control_authorizations_request"
    )

    fun isTransient(type: String): Boolean = type in transientQueries

    // The receipt coordinator persists its own unique intent until Desktop confirms it.
    fun hasRetryOwner(type: String): Boolean = isTransient(type) || type == "agent_task_result_received"
}
