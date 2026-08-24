package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class AgentPlanningContextLoaderTest {
    @Test
    fun `independent planning sources start concurrently`() {
        val started = CountDownLatch(5)
        val release = CountDownLatch(1)
        val caller = Executors.newSingleThreadExecutor()

        val resultFuture = caller.submit<AgentPlanningContextInputs> {
            AgentPlanningContextLoader.load(
                connectorsProvider = {
                    started.countDown()
                    release.await()
                    connectorSnapshot()
                },
                memoriesProvider = {
                    started.countDown()
                    release.await()
                    listOf(memory())
                },
                knowledgeProvider = {
                    started.countDown()
                    release.await()
                    AgentKnowledgeQuerySnapshot()
                },
                settingsProvider = {
                    started.countDown()
                    release.await()
                    AgentModelPlannerSettings(shareScreenText = true)
                },
                runtimeProvider = {
                    started.countDown()
                    release.await()
                    runtimeSnapshot()
                }
            )
        }

        try {
            assertTrue(started.await(2, TimeUnit.SECONDS))
            release.countDown()
            val result = resultFuture.get(2, TimeUnit.SECONDS)

            assertEquals("codex", result.targets.single().id)
            assertEquals("project", result.memories.single().value)
            assertTrue(result.knowledge.items.isEmpty())
            assertTrue(result.settings.shareScreenText)
            assertTrue(result.runtime.memoryCapture)
        } finally {
            release.countDown()
            caller.shutdownNow()
        }
    }

    @Test
    fun `source failure is unwrapped for the agent loop`() {
        val failure = assertThrows(IllegalStateException::class.java) {
            AgentPlanningContextLoader.load(
                connectorsProvider = ::connectorSnapshot,
                memoriesProvider = { throw IllegalStateException("memory unavailable") },
                knowledgeProvider = { AgentKnowledgeQuerySnapshot() },
                settingsProvider = { AgentModelPlannerSettings() },
                runtimeProvider = ::runtimeSnapshot
            )
        }

        assertEquals("memory unavailable", failure.message)
    }

    private fun target() = AgentCallableTarget(
        id = "codex",
        title = "Codex",
        kind = AgentConnectorKind.AGENT,
        status = AgentConnectorStatus.AVAILABLE,
        capabilities = listOf(AgentCapability.REASONING)
    )

    private fun connectorSnapshot() = AgentConnectorPlanningSnapshot(
        targets = listOf(target()),
        registrations = emptyList()
    )

    private fun memory() = AgentMemoryItem(
        kind = AgentMemoryKind.TASK,
        value = "project"
    )

    private fun runtimeSnapshot() = AgentPlanningRuntimeSnapshot(
        permissionMode = PermissionMode.FULL_ACCESS,
        highRiskGuard = false,
        memoryCapture = true,
        systemTools = emptyList(),
        nativeTools = emptyList()
    )
}
