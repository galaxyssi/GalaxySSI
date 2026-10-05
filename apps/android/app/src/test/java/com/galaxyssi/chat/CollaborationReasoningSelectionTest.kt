package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class CollaborationReasoningSelectionTest {
    private val context = mapOf("collaboration_group_id" to "group", "collaboration_model_id" to "gpt-6-astra",
        CollaborationReasoningSelection.KEY to "xhigh")
    private fun parameters(values: Map<String, String> = context, adapter: String = "codex-app-server-or-cli") =
        CollaborationReasoningSelection.parameters(values, adapter)

    @Test fun explicitXhighUsesTheExistingInvocationWireField() {
        assertEquals(mapOf("agent_reasoning_effort" to "xhigh"), parameters())
        val wire = AgentInvocationRequestJsonCodec.encode("gpt-6-astra",
            AgentModelReasoningEffort.fromWireValue(parameters().getValue("agent_reasoning_effort")))!!
        assertEquals("gpt-6-astra", wire.getString("model_id"))
        assertEquals("xhigh", wire.getString("reasoning_effort"))
    }

    @Test fun ordinaryAssignmentsKeepTheirCurrentDefaultsAndNeedNoNewProfile() {
        for (adapter in listOf("codex-app-server-or-cli", "cloud-model-api", "claude-code-cli", "")) {
            assertTrue(parameters(emptyMap(), adapter).isEmpty())
            assertTrue(parameters(context - CollaborationReasoningSelection.KEY, adapter).isEmpty())
        }
    }

    @Test fun invalidAutomaticOrUnknownEffortsFailClosed() {
        for (bad in listOf(null, "", "auto", "AUTO", "XHIGH", "xhigh ", "max", "ultra", "high\n")) {
            assertThrows(IllegalArgumentException::class.java) { CollaborationReasoningSelection.explicit(bad) }
        }
        for (effort in listOf("low", "medium", "high", "xhigh")) {
            assertEquals(effort, parameters(context + (CollaborationReasoningSelection.KEY to effort))["agent_reasoning_effort"])
        }
    }

    @Test fun explicitSelectionCannotLeakIntoUnsupportedOrUnscopedPaths() {
        for (adapter in listOf("cloud-model-api", "claude-code-cli", "")) {
            assertThrows(IllegalArgumentException::class.java) { parameters(adapter = adapter) }
        }
        for (key in listOf("collaboration_group_id", "collaboration_model_id")) {
            assertThrows(IllegalArgumentException::class.java) { parameters(context - key) }
        }
    }

    @Test fun onlyTheSpecificReasoningKeyIsDurable() {
        assertTrue(isPersistedAgentTeamContextKey(CollaborationReasoningSelection.KEY))
        assertFalse(isPersistedAgentTeamContextKey("collaboration_reasoning_override_permissions"))
        assertFalse(isPersistedAgentTeamContextKey("agent_reasoning_effort"))
    }
}
