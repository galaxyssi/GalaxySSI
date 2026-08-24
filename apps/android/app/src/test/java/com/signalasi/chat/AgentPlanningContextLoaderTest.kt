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
        val started = CountDownLatch(3)
        val release = CountDownLatch(1)
        val caller = Executors.newSingleThreadExecutor()

        val resultFuture = caller.submit<AgentPlanningContextInputs> {
            AgentPlanningContextLoader.load(
                targetsProvider = {
                    started.countDown()
                    release.await()
                    listOf(target())
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
        } finally {
            release.countDown()
            caller.shutdownNow()
        }
    }

    @Test
    fun `source failure is unwrapped for the agent loop`() {
        val failure = assertThrows(IllegalStateException::class.java) {
            AgentPlanningContextLoader.load(
                targetsProvider = { listOf(target()) },
                memoriesProvider = { throw IllegalStateException("memory unavailable") },
                knowledgeProvider = { AgentKnowledgeQuerySnapshot() }
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

    private fun memory() = AgentMemoryItem(
        kind = AgentMemoryKind.TASK,
        value = "project"
    )
}
