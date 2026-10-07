package com.galaxyssi.chat

/** These polls and RPC replies already have a caller-owned timeout/retry loop. */
internal object MqttQueryDeliveryPolicy {
    private val transientQueries = setOf(
        "connector_status_request", "agent_task_recovery_request", "agent_task_result_page_request",
        "evolution_task_list_request", "desktop_control_authorizations_request", "agent_task_evidence_request",
        "collaboration_recall_result", "collaboration_publish_result"
    )

    fun isTransient(type: String): Boolean = type in transientQueries

    // The receipt coordinator persists its own unique intent until Desktop confirms it.
    fun hasRetryOwner(type: String): Boolean = isTransient(type) || type == "agent_task_result_received"

    /** Content-free readiness of the requested peer, not any other connected relationship. */
    fun readiness(contextAvailable: Boolean, topic: String?, connected: Boolean, routes: MqttPeerRoutes?): String = when {
        !contextAvailable -> "context_unavailable"
        topic.isNullOrBlank() -> "topic_unavailable"
        !connected -> "transport_disconnected"
        routes == null -> "route_manager_unavailable"
        routes.readyForTopic(topic) -> "ready"
        else -> "route_${routes.blockedReasonForTopic(topic)}"
    }
}
