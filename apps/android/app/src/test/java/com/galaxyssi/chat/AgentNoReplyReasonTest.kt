package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentNoReplyReasonTest {
    @Test
    fun permissionWaitingHasHighestPriority() {
        assertEquals(
            AgentNoReplyReason.PERMISSION_WAITING,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    taskStatus = "waiting_approval",
                    routeKind = AgentRouteKind.DESKTOP_AGENT,
                    routeStatus = AgentConnectorStatus.DISCONNECTED,
                    networkAvailable = false
                )
            )
        )
    }

    @Test
    fun missingPhoneNetworkIsExplainedBeforeRemoteAvailability() {
        assertEquals(
            AgentNoReplyReason.NETWORK_UNAVAILABLE,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    taskStatus = "timed_out",
                    routeKind = AgentRouteKind.DESKTOP_AGENT,
                    endpointStatus = AgentEndpointStatus.OFFLINE,
                    networkAvailable = false
                )
            )
        )
    }

    @Test
    fun disconnectedDesktopIsNotReportedAsGenericTimeout() {
        assertEquals(
            AgentNoReplyReason.DESKTOP_OFFLINE,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    taskStatus = "timed_out",
                    routeKind = AgentRouteKind.DESKTOP_AGENT,
                    endpointStatus = AgentEndpointStatus.UNREACHABLE
                )
            )
        )
    }

    @Test
    fun busyAgentIsDistinctFromUnavailableAgent() {
        assertEquals(
            AgentNoReplyReason.AGENT_BUSY,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    taskStatus = "queued",
                    endpointStatus = AgentEndpointStatus.BUSY
                )
            )
        )
    }

    @Test
    fun setupAndStartFailuresAreActionable() {
        assertEquals(
            AgentNoReplyReason.DESKTOP_AGENT_START_FAILED,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    taskStatus = "failed",
                    error = "Codex could not start",
                    routeKind = AgentRouteKind.DESKTOP_AGENT,
                    routeStatus = AgentConnectorStatus.AVAILABLE
                )
            )
        )
        assertEquals(
            AgentNoReplyReason.CONFIGURATION_REQUIRED,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    routeStatus = AgentConnectorStatus.NEEDS_SETUP
                )
            )
        )
    }

    @Test
    fun authenticationConfigurationToolsAndInvalidInputHaveDistinctReasons() {
        assertEquals(
            AgentNoReplyReason.AUTHENTICATION_REQUIRED,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(error = "HTTP 401: invalid API key")
            )
        )
        assertEquals(
            AgentNoReplyReason.CONFIGURATION_REQUIRED,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(error = "Cloud provider is not configured")
            )
        )
        assertEquals(
            AgentNoReplyReason.TOOL_UNAVAILABLE,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(error = "python: command not found")
            )
        )
        assertEquals(
            AgentNoReplyReason.INVALID_REQUEST,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(error = "Unsupported file format")
            )
        )
    }

    @Test
    fun desktopStartFailureRequiresAnOnlineDesktopRoute() {
        assertEquals(
            AgentNoReplyReason.DESKTOP_OFFLINE,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    error = "Codex could not start",
                    routeKind = AgentRouteKind.DESKTOP_AGENT,
                    routeStatus = AgentConnectorStatus.DISCONNECTED
                )
            )
        )
        assertEquals(
            AgentNoReplyReason.AGENT_UNAVAILABLE,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    error = "Codex could not start",
                    routeKind = AgentRouteKind.UNKNOWN,
                    routeStatus = AgentConnectorStatus.AVAILABLE
                )
            )
        )
    }

    @Test
    fun genericTimeoutAndUnknownRemainSeparate() {
        assertEquals(
            AgentNoReplyReason.TIMED_OUT,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(taskStatus = "timed_out")
            )
        )
        assertEquals(
            AgentNoReplyReason.UNKNOWN,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(taskStatus = "failed", error = "Unexpected terminal state")
            )
        )
        assertEquals(
            AgentNoReplyReason.TIMED_OUT,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    taskStatus = "timed_out",
                    networkRequired = false,
                    networkAvailable = false
                )
            )
        )
    }
}
