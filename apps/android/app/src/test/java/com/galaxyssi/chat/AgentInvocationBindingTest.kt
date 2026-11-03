package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentInvocationBindingTest {
    private val astra = AgentTargetConfiguration("gpt-6-astra", AgentModelReasoningEffort.HIGH)
    private fun action(parameters: Map<String, String> = emptyMap()) = AgentAction(
        id = "route", kind = AgentActionKind.CALL_CONNECTOR, target = "Codex",
        risk = AgentRisk.LOW, status = AgentActionStatus.PROPOSED, description = "Ask",
        parameters = mapOf("connector_id" to "desktop:codex") + parameters)

    @Test fun autoUsesSavedModelAndEffortWithoutLockingTheProvider() {
        val bound = AgentInvocationBinding.bind(action(), "desktop:codex", astra)
        assertEquals("gpt-6-astra", bound.parameters["agent_model_id"])
        assertEquals("high", bound.parameters["agent_reasoning_effort"])
        assertNull(bound.parameters["manual_target_locked"])
        assertEquals("gpt-6-astra", AgentInvocationRequestJsonCodec.encode(
            bound.parameters.getValue("agent_model_id"), AgentModelReasoningEffort.HIGH)!!.getString("model_id"))
    }

    @Test fun explicitManualOptionsWinOverDefaults() {
        val source = action(mapOf("agent_model_id" to "gpt-6-sol", "agent_reasoning_effort" to "xhigh", "manual_target_locked" to "true"))
        val bound = AgentInvocationBinding.bind(source, "desktop:codex", astra)
        assertEquals("gpt-6-sol", bound.parameters["agent_model_id"])
        assertEquals("xhigh", bound.parameters["agent_reasoning_effort"])
        assertEquals("true", bound.parameters["manual_target_locked"])
    }

    @Test fun frozenTurnDoesNotAdoptLaterSettingChanges() {
        val bound = AgentInvocationBinding.bind(action(), "desktop:codex", astra)
        assertEquals(bound, AgentInvocationBinding.bind(bound, "desktop:codex",
            AgentTargetConfiguration("gpt-6-luna", AgentModelReasoningEffort.LOW)))
    }

    @Test fun fallbackUsesItsOwnConfigurationAndNeverCarriesCodexOptions() {
        val bound = AgentInvocationBinding.bind(action(), "desktop:codex", astra)
        val next = AgentInvocationBinding.bind(bound, "cloud:deepseek",
            AgentTargetConfiguration("deepseek-v4-pro", AgentModelReasoningEffort.AUTO))
        assertEquals("deepseek-v4-pro", next.parameters["agent_model_id"])
        assertEquals("auto", next.parameters["agent_reasoning_effort"])
        assertEquals("cloud:deepseek", next.parameters[AgentInvocationBinding.TARGET])
    }

    @Test fun fallbackWithoutConfigurationClearsThePreviousModel() {
        val bound = AgentInvocationBinding.bind(action(), "desktop:codex", astra)
        val next = AgentInvocationBinding.bind(bound, "desktop:claude", null)
        assertNull(next.parameters["agent_model_id"])
        assertNull(next.parameters["agent_reasoning_effort"])
    }

    @Test fun providersAndConversationsAreNotMatchedBySuffix() {
        val bound = AgentInvocationBinding.bind(action(), "desktop:codex", astra)
        val otherDesktop = AgentInvocationBinding.bind(bound, "other-desktop:codex", null)
        assertNull(otherDesktop.parameters["agent_model_id"])
    }

    @Test fun shortAliasResolvesOnlyAnUnambiguousPairedTarget() {
        assertEquals("desktop:codex", AgentInvocationBinding.canonicalTargetId("codex", listOf("codex", "desktop:codex")))
        assertEquals("codex", AgentInvocationBinding.canonicalTargetId("codex", listOf("desktop:codex", "other:codex")))
        assertEquals("desktop:codex", AgentInvocationBinding.canonicalTargetId("desktop:codex", listOf("other:codex")))
    }

    @Test fun aliasBindingWithoutOptionsDoesNotFreezeMissingConfiguration() {
        val source = action(mapOf("connector_id" to "codex", AgentInvocationBinding.TARGET to "codex"))
        val bound = AgentInvocationBinding.bind(source, "desktop:codex", astra)
        assertEquals("gpt-6-astra", bound.parameters["agent_model_id"])
        assertEquals("high", bound.parameters["agent_reasoning_effort"])
        assertEquals("desktop:codex", bound.parameters[AgentInvocationBinding.TARGET])
    }

    @Test fun explicitAliasInvocationSurvivesCanonicalization() {
        val source = action(mapOf("connector_id" to "codex", "agent_model_id" to "gpt-6-sol", "agent_reasoning_effort" to "xhigh"))
        val bound = AgentInvocationBinding.bind(source, "desktop:codex", astra)
        assertEquals("gpt-6-sol", bound.parameters["agent_model_id"])
        assertEquals("xhigh", bound.parameters["agent_reasoning_effort"])
    }
}
