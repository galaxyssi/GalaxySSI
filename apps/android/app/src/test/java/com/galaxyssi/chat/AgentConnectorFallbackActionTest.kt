package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentConnectorFallbackActionTest {
    private fun action(parameters: Map<String, String> = emptyMap()) = AgentAction(
        "action", AgentActionKind.CALL_CONNECTOR, "Old provider", AgentRisk.LOW,
        AgentActionStatus.WAITING_RESPONSE, "Reply", parameters = parameters, requiresConfirmation = false
    )

    private fun selection() = AgentConnectorFallbackSelection(
        "codex", listOf("local"), listOf("hermes"), emptySet(), setOf("cloud", "hermes")
    )

    @Test fun fallbackChangesAdapterAndDropsOnlyPreviousProviderOverrides() {
        val previous = action(mapOf(
            "connector_id" to "cloud", "connector_adapter_type" to "cloud-model-api",
            "manual_model_id" to "cloud-model", "agent_model_id" to "old-agent-model",
            "agent_reasoning_effort" to "high", "agent_instance_id" to "old-instance",
            "prompt" to "Test prompt", "conversation_id" to "conversation", "turn_id" to "turn"
        ))
        val target = AgentCallableTarget(
            "codex", "Codex", AgentConnectorKind.AGENT, AgentConnectorStatus.AVAILABLE,
            listOf(AgentCapability.CHAT), failureDomain = "desktop:t14", adapterType = "desktop-agent"
        )
        val retry = AgentConnectorFallbackAction.prepare(previous, selection(), target)
        assertEquals("Codex", retry.target)
        assertEquals("desktop-agent", retry.parameters["connector_adapter_type"])
        assertEquals("desktop:t14", retry.parameters["connector_failure_domain"])
        assertFalse(retry.parameters.containsKey("manual_model_id"))
        assertFalse(retry.parameters.containsKey("agent_model_id"))
        assertFalse(retry.parameters.containsKey("agent_reasoning_effort"))
        assertFalse(retry.parameters.containsKey("agent_instance_id"))
        assertEquals("Test prompt", retry.parameters["prompt"])
        assertEquals("conversation", retry.parameters["conversation_id"])
        assertEquals("turn", retry.parameters["turn_id"])
        assertEquals(AgentActionStatus.PROPOSED, retry.status)
    }

    @Test fun missingCatalogTargetCannotReuseThePreviousCloudAdapter() {
        val retry = AgentConnectorFallbackAction.prepare(
            action(mapOf("connector_adapter_type" to "cloud-model-api")), selection(), null
        )
        assertEquals("", retry.parameters["connector_adapter_type"])
        assertEquals("codex", retry.target)
    }

    @Test fun manualLockRejectsEvenStaleFallbackParameters() {
        assertEquals(listOf("codex"), AgentConnectorFallbackAction.dispatchIds(action(mapOf(
            "connector_id" to "codex", "routing_fallback_ids" to "cloud,hermes", "manual_target_locked" to "true"
        ))))
    }

    @Test fun dispatchSkipsExhaustedResourcesButAllowsExplicitDeferredRetry() {
        assertEquals(listOf("codex", "new-agent"), AgentConnectorFallbackAction.dispatchIds(action(mapOf(
            "connector_id" to "codex", "routing_fallback_ids" to "cloud,hermes,new-agent,codex",
            AgentConnectorFallbackAction.ATTEMPTED_PARAMETER to "cloud,hermes,codex"
        ))))
    }

    @Test fun resultRoundTripRetainsTheWholeFallbackTrail() {
        val retry = AgentConnectorFallbackAction.prepare(action(), selection(), null)
        val metadata = AgentConnectorFallbackAction.resultMetadata(retry)
        assertEquals(setOf("cloud", "hermes"), AgentConnectorFallbackAction.attempted(metadata))
        assertEquals("local", metadata["remaining_fallback_ids"])
        assertEquals("hermes", metadata["deferred_retry_ids"])
    }

    @Test fun legacyDeferredAndRetriedResourcesAreNotForgotten() {
        assertEquals(setOf("hermes", "codex"), AgentConnectorFallbackAction.attempted(mapOf(
            "deferred_retry_ids" to "hermes", "retried_resource_ids" to "codex"
        )))
    }

    @Test fun newReviewerActionDoesNotInheritThePreviousActionsFailures() {
        val retry = AgentConnectorFallbackAction.prepare(action(), selection(), null)
        assertTrue(AgentConnectorFallbackAction.hasActiveTrail(retry))
        val reviewer = retry.copy(id = "next-reviewer")
        assertFalse(AgentConnectorFallbackAction.hasActiveTrail(reviewer))
        val prepared = AgentConnectorFallbackAction.forDispatch(reviewer)
        assertTrue(AgentConnectorFallbackAction.attempted(AgentConnectorFallbackAction.resultMetadata(prepared)).isEmpty())
        assertEquals(listOf("codex", "cloud", "hermes"), AgentConnectorFallbackAction.dispatchIds(
            reviewer.copy(parameters = reviewer.parameters + ("routing_fallback_ids" to "cloud,hermes"))
        ))
    }
}
