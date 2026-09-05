package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentConnectorFallbackTrailTest {
    @Test
    fun `current auto candidates recover a missing persisted fallback`() {
        val candidates = AgentConnectorFallbackTrail.mergeAvailable(
            rememberedResourceIds = emptyList(),
            currentResourceIds = listOf("desktop:codex", "cloud:deepseek", "phone:qwen"),
            failedResourceId = "desktop:codex"
        )

        assertEquals(listOf("cloud:deepseek", "phone:qwen"), candidates)
    }

    @Test
    fun `remembered order remains stable while current candidates fill gaps`() {
        val candidates = AgentConnectorFallbackTrail.mergeAvailable(
            rememberedResourceIds = listOf("cloud:deepseek"),
            currentResourceIds = listOf("desktop:codex", "phone:qwen", "cloud:deepseek"),
            failedResourceId = "desktop:codex"
        )

        assertEquals(listOf("cloud:deepseek", "phone:qwen"), candidates)
    }

    @Test
    fun `untried fallback runs before a soft failed resource is retried`() {
        val next = AgentConnectorFallbackTrail.selectNext(
            failedResourceId = "codex",
            remainingResourceIds = listOf("cloud:deepseek"),
            deferredRetryIds = emptyList(),
            retriedResourceIds = emptySet(),
            retryFailedResource = true
        )!!

        assertEquals("cloud:deepseek", next.resourceId)
        assertEquals(listOf("codex"), next.deferredRetryIds)
        assertEquals(emptySet<String>(), next.retriedResourceIds)
    }

    @Test
    fun `permanent cloud failure returns to deferred codex once`() {
        val next = AgentConnectorFallbackTrail.selectNext(
            failedResourceId = "cloud:deepseek",
            remainingResourceIds = emptyList(),
            deferredRetryIds = listOf("codex"),
            retriedResourceIds = emptySet(),
            retryFailedResource = false
        )!!

        assertEquals("codex", next.resourceId)
        assertEquals(emptyList<String>(), next.deferredRetryIds)
        assertEquals(setOf("codex"), next.retriedResourceIds)
    }

    @Test
    fun `retried resource is not added again`() {
        val next = AgentConnectorFallbackTrail.selectNext(
            failedResourceId = "codex",
            remainingResourceIds = emptyList(),
            deferredRetryIds = emptyList(),
            retriedResourceIds = setOf("codex"),
            retryFailedResource = true
        )

        assertNull(next)
    }

    @Test
    fun `permanent resource is never deferred`() {
        val next = AgentConnectorFallbackTrail.selectNext(
            failedResourceId = "cloud:deepseek",
            remainingResourceIds = emptyList(),
            deferredRetryIds = emptyList(),
            retriedResourceIds = emptySet(),
            retryFailedResource = false
        )

        assertNull(next)
    }

    @Test
    fun `catalog refresh cannot resurrect a permanently failed resource`() {
        val candidates = AgentConnectorFallbackTrail.mergeAvailable(
            listOf("hermes", "codex"), listOf("cloud", "hermes", "codex"), "hermes", setOf("cloud")
        )
        assertEquals(listOf("codex"), candidates)
    }

    @Test
    fun `permanent failure removes any stale deferred retry`() {
        assertNull(AgentConnectorFallbackTrail.selectNext(
            "cloud", listOf("cloud"), listOf("cloud"), emptySet(), false
        ))
    }

    @Test
    fun `catalog refresh cannot promote a deferred retry above untried resources`() {
        val next = AgentConnectorFallbackTrail.selectNext(
            "cloud", listOf("codex", "local"), listOf("codex"), emptySet(), false
        )!!
        assertEquals("local", next.resourceId)
        assertEquals(setOf("codex", "cloud"), next.attemptedResourceIds)
    }

    @Test
    fun `permanent failures terminate even with a fresh catalog each time`() {
        assertEquals(32, runFailingCatalog(32, transient = false))
    }

    @Test
    fun `soft failures get one deferred retry each without cycling forever`() {
        assertEquals(64, runFailingCatalog(32, transient = true))
    }

    @Test
    fun `attempt history is not truncated after twelve resources`() {
        val ids = (1..64).map { "resource-$it" }
        assertEquals(ids, AgentConnectorFallbackTrail.parse(AgentConnectorFallbackTrail.encode(ids)))
    }

    private fun runFailingCatalog(size: Int, transient: Boolean): Int {
        val catalog = (1..size).map { "agent-$it" }
        var failed = catalog.first()
        var remaining = catalog.drop(1)
        var deferred = emptyList<String>()
        var retried = emptySet<String>()
        var attempted = emptySet<String>()
        var calls = 0
        repeat(size * 3) {
            calls++
            val next = AgentConnectorFallbackTrail.selectNext(
                failed,
                AgentConnectorFallbackTrail.mergeAvailable(remaining, catalog, failed, attempted),
                deferred, retried, transient, attempted
            ) ?: return calls
            failed = next.resourceId
            remaining = next.remainingResourceIds
            deferred = next.deferredRetryIds
            retried = next.retriedResourceIds
            attempted = AgentConnectorFallbackTrail.parse(
                AgentConnectorFallbackTrail.encode(next.attemptedResourceIds)
            ).toSet()
        }
        throw AssertionError("Failover catalog did not terminate")
    }
}
