package com.galaxyssi.chat

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
        val default = AgentModelSelectionSettings.defaultPreferenceKey("mode")

        assertNotEquals(first, second)
        assertNotEquals(first, default)
        assertNotEquals(second, default)
        assertTrue(first.contains("conversation-a"))
        assertTrue(second.contains("conversation-b"))
        assertEquals("default.mode", default)
    }

    @Test
    fun perAgentConfigurationKeysAreIsolatedAcrossAgentsAndConversations() {
        val firstCodex = AgentModelSelectionSettings.conversationTargetPreferenceKey(
            "conversation-a",
            "desktop-t14:codex",
            "model_id"
        )
        val firstClaude = AgentModelSelectionSettings.conversationTargetPreferenceKey(
            "conversation-a",
            "desktop-t14:claude",
            "model_id"
        )
        val secondCodex = AgentModelSelectionSettings.conversationTargetPreferenceKey(
            "conversation-b",
            "desktop-t14:codex",
            "model_id"
        )
        val defaultCodex = AgentModelSelectionSettings.defaultTargetPreferenceKey(
            "desktop-t14:codex",
            "model_id"
        )

        assertNotEquals(firstCodex, firstClaude)
        assertNotEquals(firstCodex, secondCodex)
        assertNotEquals(firstCodex, defaultCodex)
        assertTrue(firstCodex.startsWith("conversation.conversation-a.target."))
        assertTrue(defaultCodex.startsWith("default.target."))
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
                    JSONObject()
                        .put("id", "gpt-5.6-sol")
                        .put("display_name", "GPT-5.6 Sol")
                        .put("description", "\u80fd\u529b\u6700\u5f3a\uff0c\u590d\u6742\u7f16\u7801\u4e0e\u957f\u671f\u4efb\u52a1")
                ))
                .put("reasoning_efforts", JSONArray(listOf("low", "medium", "high", "xhigh")))
        )

        assertEquals("gpt-5.6-sol", profile.defaultModelId)
        assertEquals(listOf("gpt-5.6-sol"), profile.models.map(AgentModelOption::id))
        assertEquals("\u80fd\u529b\u6700\u5f3a\uff0c\u590d\u6742\u7f16\u7801\u4e0e\u957f\u671f\u4efb\u52a1", profile.models.single().description)
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
    fun onlyScannedDesktopAgentsOpenAgentConversations() {
        val scannedAgent = JSONObject()
            .put("id", "desktop_t14:codex")
            .put("type", "agent")
            .put("delivery_mode", "pc_connector")
            .put("agent_id", "codex")

        assertTrue(ScannedAgentConversationPolicy.opensAgentConversation(scannedAgent))
        assertTrue(!ScannedAgentConversationPolicy.opensAgentConversation(
            JSONObject(scannedAgent.toString()).put("type", "device")
        ))
        assertTrue(!ScannedAgentConversationPolicy.opensAgentConversation(
            JSONObject(scannedAgent.toString()).put("delivery_mode", "cloud_api")
        ))
        assertTrue(!ScannedAgentConversationPolicy.opensAgentConversation(
            JSONObject(scannedAgent.toString()).put("deleted", true)
        ))
    }

    @Test
    fun scannedAgentResolvesItsConcreteDesktopTarget() {
        val contact = JSONObject()
            .put("id", "desktop_t14:claude")
            .put("type", "agent")
            .put("delivery_mode", "pc_connector")
            .put("agent_id", "claude")
        val generic = AgentCallableTarget(
            id = "claude",
            title = "Claude Code",
            kind = AgentConnectorKind.AGENT,
            status = AgentConnectorStatus.AVAILABLE,
            capabilities = listOf(AgentCapability.CHAT)
        )
        val concrete = generic.copy(
            id = "desktop_t14:claude",
            title = "Claude Code · DESKTOP-T14"
        )

        assertEquals(
            concrete,
            ScannedAgentConversationPolicy.resolveTarget(
                contactId = "desktop_t14:claude",
                contact = contact,
                targets = listOf(generic, concrete)
            )
        )
    }

    @Test
    fun claudeInvocationProfileHasModelsWithoutReasoningOptions() {
        val profile = AgentInvocationProfileJsonCodec.decode(
            JSONObject()
                .put("default_model", "best")
                .put("models", JSONArray().put(
                    JSONObject()
                        .put("id", "best")
                        .put("description", "\u6709\u6743\u9650\u65f6\u4f7f\u7528 Fable 5\uff0c\u5426\u5219 Opus 5")
                ))
                .put("reasoning_efforts", JSONArray())
        )

        assertEquals("best", profile.defaultModelId)
        assertEquals("\u6709\u6743\u9650\u65f6\u4f7f\u7528 Fable 5\uff0c\u5426\u5219 Opus 5", profile.models.single().description)
        assertTrue(profile.reasoningEfforts.isEmpty())
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
