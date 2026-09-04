package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentExplicitToolHandlesTest {
    @Test
    fun handleIsOpaqueScopedAndDoesNotExposeItsResource() {
        val clock = MutableClock(1_000L)
        val registry = AgentExplicitToolHandleRegistry(clock)
        val opened = registry.create(
            kind = "browser_session",
            resourceId = "internal-browser-resource",
            scope = AgentExplicitToolHandleScope("owner-1", "conversation-1"),
            capabilities = setOf("browser.navigate"),
            resource = mutableMapOf("url" to "")
        )

        val handleId = opened["handle_id"].toString()
        assertTrue(handleId.startsWith("sth_browsers_"))
        assertFalse(opened.containsKey("resource_id"))
        assertFalse(opened.toString().contains("internal-browser-resource"))

        val resolved = registry.resolve(
            handleId,
            "browser_session",
            AgentExplicitToolHandleScope("owner-1", "conversation-1"),
            "browser.navigate"
        )
        assertEquals("internal-browser-resource", resolved.resourceId)

        val mismatch = runCatching {
            registry.resolve(
                handleId,
                "browser_session",
                AgentExplicitToolHandleScope("owner-1", "conversation-2"),
                "browser.navigate"
            )
        }.exceptionOrNull() as AgentExplicitToolHandleException
        assertEquals("tool_handle_context_mismatch", mismatch.code)
    }

    @Test
    fun expiredAndReleasedHandlesFailExplicitly() {
        val clock = MutableClock(2_000L)
        val registry = AgentExplicitToolHandleRegistry(clock)
        val opened = registry.create(
            kind = "browser_session",
            resourceId = "browser-1",
            scope = AgentExplicitToolHandleScope("owner"),
            capabilities = setOf("browser.close"),
            resource = Any(),
            ttlMillis = 100L,
            idleTimeoutMillis = 0L
        )
        clock.now = 2_100L

        val expired = runCatching {
            registry.resolve(
                opened["handle_id"].toString(),
                "browser_session",
                AgentExplicitToolHandleScope("owner"),
                "browser.close"
            )
        }.exceptionOrNull() as AgentExplicitToolHandleException
        assertEquals("tool_handle_expired", expired.code)
        assertTrue(expired.retryable)

        val replacement = registry.create(
            kind = "browser_session",
            resourceId = "browser-2",
            scope = AgentExplicitToolHandleScope("owner"),
            capabilities = setOf("browser.close"),
            resource = Any()
        )
        assertTrue(
            registry.release(
                replacement["handle_id"].toString(),
                AgentExplicitToolHandleScope("owner")
            )
        )
        assertEquals(0, registry.status()["active_count"])
    }

    private class MutableClock(var now: Long) : AgentNativeClock {
        override fun nowEpochMillis(): Long = now
    }
}
