package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentMemoryAccessTrackerTest {
    @Test
    fun `first recall records access time`() {
        val result = AgentMemoryAccessTracker.refresh(
            items = listOf(memory(lastAccessedAtMillis = 0L)),
            recalledIds = setOf(MEMORY_ID),
            nowMillis = 10_000L
        )

        assertTrue(result.changed)
        assertEquals(10_000L, result.items.single().lastAccessedAtMillis)
    }

    @Test
    fun `repeated recall inside interval avoids encrypted rewrite`() {
        val items = listOf(memory(lastAccessedAtMillis = 10_000L))

        val result = AgentMemoryAccessTracker.refresh(
            items = items,
            recalledIds = setOf(MEMORY_ID),
            nowMillis = 10_000L + AgentMemoryAccessTracker.DEFAULT_WRITE_INTERVAL_MILLIS - 1L
        )

        assertFalse(result.changed)
        assertSame(items, result.items)
    }

    @Test
    fun `recall at interval boundary refreshes access time`() {
        val previous = 10_000L
        val now = previous + AgentMemoryAccessTracker.DEFAULT_WRITE_INTERVAL_MILLIS

        val result = AgentMemoryAccessTracker.refresh(
            items = listOf(memory(lastAccessedAtMillis = previous)),
            recalledIds = setOf(MEMORY_ID),
            nowMillis = now
        )

        assertTrue(result.changed)
        assertEquals(now, result.items.single().lastAccessedAtMillis)
    }

    @Test
    fun `unrecalled memories keep their access metadata`() {
        val item = memory(lastAccessedAtMillis = 20_000L)

        val result = AgentMemoryAccessTracker.refresh(
            items = listOf(item),
            recalledIds = setOf("another-memory"),
            nowMillis = 1_000_000L
        )

        assertFalse(result.changed)
        assertSame(item, result.items.single())
    }

    private fun memory(lastAccessedAtMillis: Long) = AgentMemoryItem(
        id = MEMORY_ID,
        kind = AgentMemoryKind.TASK,
        value = "Continue the phone project",
        lastAccessedAtMillis = lastAccessedAtMillis
    )

    private companion object {
        const val MEMORY_ID = "memory-1"
    }
}
