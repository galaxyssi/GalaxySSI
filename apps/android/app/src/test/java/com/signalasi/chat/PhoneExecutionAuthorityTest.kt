package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneExecutionAuthorityTest {
    private val screen = ScreenContext(foregroundApp = "SignalASI", pageTitle = "Agent")

    @Test
    fun phoneCloudModelApiRunsAsConcurrentRead() {
        val action = connectorAction(
            id = "cloud-read",
            adapterType = "cloud-model-api"
        )
        val result = PhoneExecutionAuthority.guarded(successfulDelegate()).execute(action, screen)

        assertTrue(result.success)
        assertEquals("false", result.metadata["serialized_side_effect"])
    }

    @Test
    fun remoteAgentConnectorRemainsSerialized() {
        val action = connectorAction(
            id = "remote-agent",
            adapterType = "codex-app-server-or-cli"
        )
        val result = PhoneExecutionAuthority.guarded(successfulDelegate()).execute(action, screen)

        assertTrue(result.success)
        assertEquals("true", result.metadata["serialized_side_effect"])
    }

    private fun successfulDelegate() = object : AgentActionExecutor {
        override fun execute(action: AgentAction, screen: ScreenContext) = AgentActionResult(
            actionId = action.id,
            success = true,
            message = "Dispatched"
        )
    }

    private fun connectorAction(id: String, adapterType: String) = AgentAction(
        id = id,
        kind = AgentActionKind.CALL_CONNECTOR,
        target = id,
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PROPOSED,
        description = "Dispatch connector",
        parameters = mapOf(
            "connector_id" to id,
            "connector_adapter_type" to adapterType,
            "_signalasi_task_id" to "task-$id"
        ),
        requiresConfirmation = false
    )
}
