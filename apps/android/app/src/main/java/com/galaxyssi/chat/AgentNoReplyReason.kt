package com.galaxyssi.chat

import java.util.Locale

enum class AgentNoReplyReason {
    NETWORK_UNAVAILABLE,
    DESKTOP_OFFLINE,
    DESKTOP_AGENT_START_FAILED,
    AGENT_BUSY,
    PERMISSION_WAITING,
    AUTHENTICATION_REQUIRED,
    CONFIGURATION_REQUIRED,
    TOOL_UNAVAILABLE,
    AGENT_UNAVAILABLE,
    TIMED_OUT,
    INVALID_REQUEST,
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

            signal.routeKind == AgentRouteKind.DESKTOP_AGENT &&
                signal.routeStatus == AgentConnectorStatus.AVAILABLE &&
                signal.endpointStatus !in setOf(
                    AgentEndpointStatus.OFFLINE,
                    AgentEndpointStatus.UNREACHABLE
                ) &&
                (
                    status == "start_failed" ||
                        containsAny(
                            details,
                            "could not start",
                            "failed to start",
                            "launch failed",
                            "process exited during startup",
                            "startup failed",
                            "\u542f\u52a8\u5931\u8d25",
                            "\u65e0\u6cd5\u542f\u52a8",
                            "\u672a\u80fd\u542f\u52a8"
                        )
                    ) -> AgentNoReplyReason.DESKTOP_AGENT_START_FAILED

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

            containsAny(
                details,
                "unauthorized",
                "authentication failed",
                "invalid api key",
                "invalid token",
                "token expired",
                "credentials expired",
                "http 401",
                "http 403",
                "\u8ba4\u8bc1\u5931\u8d25",
                "\u5bc6\u94a5\u65e0\u6548",
                "\u4ee4\u724c\u8fc7\u671f",
                "\u767b\u5f55\u5df2\u8fc7\u671f"
            ) -> AgentNoReplyReason.AUTHENTICATION_REQUIRED

            signal.routeStatus == AgentConnectorStatus.NEEDS_SETUP ||
                containsAny(
                    details,
                    "not configured",
                    "missing api key",
                    "missing credentials",
                    "setup required",
                    "needs setup",
                    "\u672a\u914d\u7f6e",
                    "\u7f3a\u5c11\u5bc6\u94a5",
                    "\u9700\u8981\u914d\u7f6e"
                ) -> AgentNoReplyReason.CONFIGURATION_REQUIRED

            containsAny(
                details,
                "command not found",
                "executable not found",
                "tool unavailable",
                "runtime pack missing",
                "dependency missing",
                "no such executable",
                "\u547d\u4ee4\u4e0d\u5b58\u5728",
                "\u5de5\u5177\u4e0d\u53ef\u7528",
                "\u7f3a\u5c11\u8fd0\u884c\u5305",
                "\u7f3a\u5c11\u4f9d\u8d56"
            ) -> AgentNoReplyReason.TOOL_UNAVAILABLE

            signal.routeStatus in setOf(
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
                    "\u65e0\u6cd5\u4f7f\u7528"
                ) -> AgentNoReplyReason.AGENT_UNAVAILABLE

            status == "timed_out" ||
                containsAny(details, "timed out", "timeout", "\u8d85\u65f6") ->
                AgentNoReplyReason.TIMED_OUT

            status in setOf("invalid", "invalid_request", "unsupported") ||
                containsAny(
                    details,
                    "invalid request",
                    "invalid input",
                    "unsupported file",
                    "unsupported format",
                    "malformed",
                    "\u8bf7\u6c42\u65e0\u6548",
                    "\u8f93\u5165\u65e0\u6548",
                    "\u683c\u5f0f\u4e0d\u652f\u6301",
                    "\u6587\u4ef6\u4e0d\u652f\u6301"
                ) -> AgentNoReplyReason.INVALID_REQUEST

            else -> AgentNoReplyReason.UNKNOWN
        }
    }

    private fun containsAny(value: String, vararg candidates: String): Boolean =
        candidates.any(value::contains)
}
