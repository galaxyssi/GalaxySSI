package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class AgentModelSelectionPolicyTest {
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
}
