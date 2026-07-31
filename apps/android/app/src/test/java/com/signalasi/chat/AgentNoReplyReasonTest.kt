package com.signalasi.chat

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
            AgentNoReplyReason.AGENT_UNAVAILABLE,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    taskStatus = "failed",
                    error = "Codex could not start",
                    routeStatus = AgentConnectorStatus.AVAILABLE
                )
            )
        )
        assertEquals(
            AgentNoReplyReason.AGENT_UNAVAILABLE,
            AgentNoReplyReasonPolicy.classify(
                AgentNoReplySignal(
                    routeStatus = AgentConnectorStatus.NEEDS_SETUP
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
