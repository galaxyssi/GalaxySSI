package com.signalasi.chat

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
}
