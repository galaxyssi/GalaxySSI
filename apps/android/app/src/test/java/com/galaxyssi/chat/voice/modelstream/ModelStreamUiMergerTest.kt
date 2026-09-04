package com.galaxyssi.chat.voice.modelstream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelStreamUiMergerTest {
    @Test
    fun `first delta is immediate while later deltas are coalesced`() {
        val merger = ModelStreamUiMerger(minUpdateIntervalMs = 80L)

        val first = merger.offer(1, "Hel", 1_000L)
        val held = merger.offer(2, "lo", 1_020L)
        val flushed = merger.flush(1_080L)

        assertEquals("Hel", first?.text)
        assertTrue(first?.firstDelta == true)
        assertNull(held)
        assertEquals("Hello", flushed?.text)
    }

    @Test
    fun `duplicate and out of order sequence cannot duplicate visible text`() {
        val merger = ModelStreamUiMerger(minUpdateIntervalMs = 80L)
        merger.offer(2, "B", 1_000L)

        assertNull(merger.offer(2, "B", 1_100L))
        assertNull(merger.offer(1, "A", 1_100L))
        assertEquals("B", merger.snapshot())
    }

    @Test
    fun `terminal flush marks partial content complete only when requested`() {
        val merger = ModelStreamUiMerger(minUpdateIntervalMs = 80L)
        merger.offer(1, "answer", 1_000L)

        val complete = merger.flush(1_010L, complete = true)

        assertEquals("answer", complete?.text)
        assertTrue(complete?.complete == true)
    }
}
