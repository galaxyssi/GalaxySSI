package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONArray
import org.json.JSONObject

class AgentModelSelectionPolicyTest {
    @Test
    fun conversationSelectionKeysAreIsolated() {
        val first = AgentModelSelectionSettings.conversationPreferenceKey("conversation-a", "mode")
        val second = AgentModelSelectionSettings.conversationPreferenceKey("conversation-b", "mode")

        assertNotEquals(first, second)
        assertTrue(first.contains("conversation-a"))
        assertTrue(second.contains("conversation-b"))
    }

    private val localModel = AgentCallableTarget(
        id = "local-llm",
        title = "Qwen3 1.7B QNN",
        kind = AgentConnectorKind.MODEL,
        status = AgentConnectorStatus.AVAILABLE,
        capabilities = listOf(AgentCapability.CHAT, AgentCapability.REASONING)
    )

    @Test
    fun automaticModeDoesNotOverrideRouter() {
        assertEquals(
            "",
            AgentModelSelectionPolicy.preferredTargetId(
                AgentModelSelection(mode = AgentModelSelectionMode.AUTO),
                listOf(localModel)
            )
        )
    }

    @Test
    fun availableManualModelOverridesRouter() {
        assertEquals(
            "local-llm",
            AgentModelSelectionPolicy.preferredTargetId(
                AgentModelSelection(
                    mode = AgentModelSelectionMode.MANUAL,
                    targetId = "local-llm",
                    modelId = "qwen3-1-7b-qairt"
                ),
                listOf(localModel)
            )
        )
    }

    @Test
    fun unavailableManualModelRemainsLockedInsteadOfFallingBack() {
        assertEquals(
            "local-llm",
            AgentModelSelectionPolicy.preferredTargetId(
                AgentModelSelection(
                    mode = AgentModelSelectionMode.MANUAL,
                    targetId = "local-llm"
                ),
                listOf(localModel.copy(status = AgentConnectorStatus.NEEDS_SETUP))
            )
        )
    }

    @Test
    fun concreteDesktopAgentReplacesGenericDuplicateInSelector() {
        val genericCodex = AgentCallableTarget(
            id = "codex",
            title = "Codex Agent",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT)
        )
        val t14Codex = genericCodex.copy(
            id = "desktop_t14:codex",
            title = "Codex · T14"
        )

        assertEquals(
            listOf("desktop_t14:codex"),
            AgentModelSelectionPolicy.selectableAgentTargets(
                listOf(genericCodex, t14Codex)
            ).map(AgentCallableTarget::id)
        )
    }

    @Test
    fun liveStatusPrefersConcreteResponseContact() {
        val t14Codex = AgentCallableTarget(
            id = "desktop_t14:codex",
            title = "Codex · T14",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT)
        )

        assertEquals(
            t14Codex,
            AgentExecutionTargetStatusPolicy.resolveTarget(
                connectorId = "codex",
                contactId = "desktop_t14:codex",
                targets = listOf(t14Codex)
            )
        )
    }

    @Test
    fun desktopInvocationProfileDecodesModelAndReasoningOptions() {
        val profile = AgentInvocationProfileJsonCodec.decode(
            JSONObject()
                .put("default_model", "gpt-5.6-sol")
                .put("models", JSONArray().put(
                    JSONObject().put("id", "gpt-5.6-sol").put("display_name", "GPT-5.6 Sol")
                ))
                .put("reasoning_efforts", JSONArray(listOf("low", "medium", "high", "xhigh")))
        )

        assertEquals("gpt-5.6-sol", profile.defaultModelId)
        assertEquals(listOf("gpt-5.6-sol"), profile.models.map(AgentModelOption::id))
        assertEquals(
            listOf(
                AgentModelReasoningEffort.LOW,
                AgentModelReasoningEffort.MEDIUM,
                AgentModelReasoningEffort.HIGH,
                AgentModelReasoningEffort.XHIGH
            ),
            profile.reasoningEfforts
        )
    }

    @Test
    fun invocationRequestCarriesSelectedModelAndExtraHighEffort() {
        val encoded = checkNotNull(
            AgentInvocationRequestJsonCodec.encode(
                "gpt-5.6-sol",
                AgentModelReasoningEffort.XHIGH
            )
        )

        assertEquals("gpt-5.6-sol", encoded.getString("model_id"))
        assertEquals("xhigh", encoded.getString("reasoning_effort"))
        assertNull(AgentInvocationRequestJsonCodec.encode("", AgentModelReasoningEffort.AUTO))
    }
}
