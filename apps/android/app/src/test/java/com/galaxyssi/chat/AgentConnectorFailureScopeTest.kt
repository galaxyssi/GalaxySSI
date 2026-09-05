package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorFailureScopeTest {
    private val desktop = mapOf("failure_domain" to "desktop:t14", "resource_location" to "desktop")

    @Test fun agentStartupTimeoutKeepsOtherAgentsOnDesktopEligible() {
        val failure = desktop + ("timeout_stage" to AgentConnectorTimeoutStage.NOT_RUNNING.name)
        assertFalse(AgentConnectorFailureScope.sharedTransportFailed(failure))
        assertTrue(AgentConnectorFailureScope.permitsFallback(failure, "desktop:t14"))
    }

    @Test fun terminalExecutionTimeoutDoesNotQuarantineTheDesktop() {
        val failure = desktop + ("timeout_stage" to AgentRemoteTaskStatusPolicy.REMOTE_TIMEOUT_STAGE)
        assertFalse(AgentConnectorFailureScope.sharedTransportFailed(failure))
        assertTrue(AgentConnectorFailureScope.permitsFallback(failure, "desktop:t14"))
    }

    @Test fun staleAgentExecutionKeepsIndependentAgentsEligible() {
        val failure = desktop + ("timeout_stage" to AgentConnectorTimeoutStage.READ_ONLY_STALE.name)
        assertTrue(AgentConnectorFailureScope.permitsFallback(failure, "desktop:t14"))
    }

    @Test fun unacceptedTransportExcludesOnlyTheSameDesktop() {
        val failure = desktop + ("timeout_stage" to AgentConnectorTimeoutStage.NOT_ACCEPTED.name)
        assertTrue(AgentConnectorFailureScope.sharedTransportFailed(failure))
        assertFalse(AgentConnectorFailureScope.permitsFallback(failure, "desktop:t14"))
        assertTrue(AgentConnectorFailureScope.permitsFallback(failure, "desktop:other"))
        assertTrue(AgentConnectorFailureScope.permitsFallback(failure, "cloud:provider"))
        assertTrue(AgentConnectorFailureScope.permitsFallback(failure, "phone:local-model"))
    }

    @Test fun explicitDeliveryFailureStillQuarantinesSharedTransport() {
        val failure = desktop + ("delivery_failed" to "true")
        assertFalse(AgentConnectorFailureScope.permitsFallback(failure, "desktop:t14"))
    }

    @Test fun unknownDomainDoesNotExcludeEveryUnknownTarget() {
        assertTrue(AgentConnectorFailureScope.permitsFallback(mapOf("delivery_failed" to "true"), ""))
    }

    @Test fun providerErrorsDoNotBecomeDesktopTransportEvidence() {
        assertTrue(AgentConnectorFailureScope.remoteExecutionReached(desktop))
        assertFalse(AgentConnectorFailureScope.remoteExecutionReached(mapOf("resource_location" to "cloud")))
    }
}
