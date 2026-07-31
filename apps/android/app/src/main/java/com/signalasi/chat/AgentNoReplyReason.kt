package com.signalasi.chat

import java.util.Locale

enum class AgentNoReplyReason {
    NETWORK_UNAVAILABLE,
    DESKTOP_OFFLINE,
    AGENT_BUSY,
    PERMISSION_WAITING,
    AGENT_UNAVAILABLE,
    TIMED_OUT,
    UNKNOWN
}

data class AgentNoReplySignal(
    val taskStatus: String = "",
    val error: String = "",
    val currentStep: String = "",
    val routeKind: AgentRouteKind = AgentRouteKind.UNKNOWN,
    val routeStatus: AgentConnectorStatus = AgentConnectorStatus.AVAILABLE,
    val endpointStatus: AgentEndpointStatus? = null,
    val networkRequired: Boolean = true,
    val networkAvailable: Boolean = true
)

object AgentNoReplyReasonPolicy {
    fun classify(signal: AgentNoReplySignal): AgentNoReplyReason {
        val status = signal.taskStatus.trim().lowercase(Locale.ROOT)
        val details = buildString {
            append(status)
            append(' ')
            append(signal.error)
            append(' ')
            append(signal.currentStep)
        }.lowercase(Locale.ROOT)

        return when {
            status == "waiting_approval" ||
                signal.endpointStatus == AgentEndpointStatus.PERMISSION_REQUIRED ||
                containsAny(
                    details,
                    "waiting for approval",
                    "waiting for permission",
                    "permission required",
                    "approval required",
                    "needs permission",
                    "\u7b49\u5f85\u6388\u6743",
                    "\u9700\u8981\u6388\u6743",
                    "\u7b49\u5f85\u6279\u51c6"
                ) -> AgentNoReplyReason.PERMISSION_WAITING

            (signal.networkRequired && !signal.networkAvailable) ||
                containsAny(
                    details,
                    "network unavailable",
                    "network is offline",
                    "no network",
                    "mqtt disconnected",
                    "network disconnected",
                    "\u7f51\u7edc\u4e0d\u53ef\u7528",
                    "\u624b\u673a\u65e0\u7f51\u7edc"
                ) -> AgentNoReplyReason.NETWORK_UNAVAILABLE

            signal.routeKind == AgentRouteKind.DESKTOP_AGENT && (
                signal.routeStatus == AgentConnectorStatus.DISCONNECTED ||
                    signal.endpointStatus in setOf(
                        AgentEndpointStatus.OFFLINE,
                        AgentEndpointStatus.UNREACHABLE
                    ) ||
                    containsAny(
                        details,
                        "desktop offline",
                        "desktop disconnected",
                        "gateway offline",
                        "desktop unreachable",
                        "\u7535\u8111\u79bb\u7ebf",
                        "\u684c\u9762\u7aef\u79bb\u7ebf"
                    )
                ) -> AgentNoReplyReason.DESKTOP_OFFLINE

            signal.endpointStatus == AgentEndpointStatus.BUSY ||
                containsAny(
                    details,
                    "agent busy",
                    "provider busy",
                    "capacity exhausted",
                    "queue is full",
                    "worker pool is full",
                    "\u667a\u80fd\u4f53\u5fd9",
                    "\u961f\u5217\u5df2\u6ee1"
                ) -> AgentNoReplyReason.AGENT_BUSY

            signal.routeStatus in setOf(
                AgentConnectorStatus.NEEDS_SETUP,
                AgentConnectorStatus.DISCONNECTED
            ) ||
                signal.endpointStatus in setOf(
                    AgentEndpointStatus.OFFLINE,
                    AgentEndpointStatus.UNREACHABLE
                ) ||
                containsAny(
                    details,
                    "agent unavailable",
                    "provider unavailable",
                    "not installed",
                    "not configured",
                    "could not start",
                    "failed to start",
                    "not found",
                    "\u667a\u80fd\u4f53\u4e0d\u53ef\u7528",
                    "\u672a\u5b89\u88c5",
                    "\u672a\u914d\u7f6e"
                ) -> AgentNoReplyReason.AGENT_UNAVAILABLE

            status == "timed_out" ||
                containsAny(details, "timed out", "timeout", "\u8d85\u65f6") ->
                AgentNoReplyReason.TIMED_OUT

            else -> AgentNoReplyReason.UNKNOWN
        }
    }

    private fun containsAny(value: String, vararg candidates: String): Boolean =
        candidates.any(value::contains)
}
