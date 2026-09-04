package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class PhoneExecutionAuthorityTest {
    private val screen = ScreenContext(foregroundApp = "GalaxySSI", pageTitle = "Agent")

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
    fun remoteAgentConnectorRunsOutsidePhoneSideEffectLock() {
        val action = connectorAction(
            id = "remote-agent",
            adapterType = "codex-app-server-or-cli"
        )
        val result = PhoneExecutionAuthority.guarded(successfulDelegate()).execute(action, screen)

        assertTrue(result.success)
        assertEquals("false", result.metadata["serialized_side_effect"])
    }

    @Test
    fun remoteAgentConnectorDoesNotWaitForActivePhoneMutation() {
        val mutationStarted = CountDownLatch(1)
        val releaseMutation = CountDownLatch(1)
        val mutationFinished = CountDownLatch(1)
        val guarded = PhoneExecutionAuthority.guarded(object : AgentActionExecutor {
            override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
                if (action.kind == AgentActionKind.OPEN_APP) {
                    mutationStarted.countDown()
                    assertTrue(releaseMutation.await(2, TimeUnit.SECONDS))
                }
                return AgentActionResult(action.id, true, "Dispatched")
            }
        })
        val mutation = Thread {
            guarded.execute(phoneMutationAction(), screen)
            mutationFinished.countDown()
        }
        mutation.start()
        assertTrue(mutationStarted.await(1, TimeUnit.SECONDS))

        val startedAt = System.nanoTime()
        val connectorResult = guarded.execute(
            connectorAction("remote-agent-concurrent", "codex-app-server-or-cli"),
            screen
        )
        val elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt)

        assertTrue(connectorResult.success)
        assertEquals("false", connectorResult.metadata["serialized_side_effect"])
        assertTrue("Connector dispatch waited ${elapsedMillis}ms for the phone lock", elapsedMillis < 500L)
        releaseMutation.countDown()
        assertTrue(mutationFinished.await(1, TimeUnit.SECONDS))
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
            "_galaxyssi_task_id" to "task-$id"
        ),
        requiresConfirmation = false
    )

    private fun phoneMutationAction() = AgentAction(
        id = "phone-mutation",
        kind = AgentActionKind.OPEN_APP,
        target = "Settings",
        risk = AgentRisk.LOW,
        status = AgentActionStatus.PROPOSED,
        description = "Open Settings",
        parameters = mapOf("_galaxyssi_task_id" to "task-phone-mutation"),
        requiresConfirmation = false
    )
}
