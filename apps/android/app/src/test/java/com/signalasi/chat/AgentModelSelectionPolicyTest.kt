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
    fun unavailableManualModelFallsBackToAutomaticRouting() {
        assertEquals(
            "",
            AgentModelSelectionPolicy.preferredTargetId(
                AgentModelSelection(
                    mode = AgentModelSelectionMode.MANUAL,
                    targetId = "local-llm"
                ),
                listOf(localModel.copy(status = AgentConnectorStatus.NEEDS_SETUP))
            )
        )
    }
}
