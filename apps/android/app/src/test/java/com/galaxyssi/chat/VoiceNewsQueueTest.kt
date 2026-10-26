package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class VoiceNewsQueueTest {
    @Test fun restoreNeverAutoplaysAndKeepsOffset() {
        val queue = VoiceNewsQueue(VoiceNewsCheckpoint(listOf("one", "two"), 1, 82))
        assertEquals("paused", queue.state)
        assertFalse(queue.playing)
        assertEquals("two", queue.articleId)
        assertEquals(82, queue.checkpoint.offset)
    }
    @Test fun duplicateIdsAreRemovedWithoutChangingOrder() {
        val queue = VoiceNewsQueue()
        queue.replace(listOf("one", "two", "one"))
        assertEquals(listOf("one", "two"), queue.checkpoint.ids)
    }
    @Test fun pausedAndReplacedCallbacksCannotAdvanceQueue() {
        val queue = VoiceNewsQueue()
        queue.replace(listOf("one", "two"))
        val first = queue.resume()
        assertTrue(queue.progress(first, 40))
        queue.pause()
        assertFalse(queue.progress(first, 90))
        val resumed = queue.resume()
        queue.replace(listOf("other"))
        assertFalse(queue.progress(resumed, 100))
        assertEquals(0, queue.checkpoint.offset)
    }
    @Test fun nextStartsAtBeginningAndFinishKeepsLastArticleForFollowup() {
        val queue = VoiceNewsQueue(VoiceNewsCheckpoint(listOf("one", "two"), 0, 50))
        assertTrue(queue.next())
        assertEquals("two", queue.articleId)
        assertEquals(0, queue.checkpoint.offset)
        assertFalse(queue.next())
        assertEquals("finished", queue.state)
        assertEquals("two", queue.articleId)
    }
    @Test fun stopClearsOnlyPlaybackBookmark() {
        val queue = VoiceNewsQueue(VoiceNewsCheckpoint(listOf("one")))
        queue.stop(true)
        assertEquals(VoiceNewsCheckpoint(), queue.checkpoint)
        assertEquals("stopped", queue.state)
    }
    @Test fun corruptOrUnboundedCheckpointsAreDiscarded() {
        for (ids in listOf(List(21) { "$it" }, listOf(""), listOf("x".repeat(257)), listOf("x", "x")))
            assertEquals(VoiceNewsCheckpoint(), VoiceNewsQueue(VoiceNewsCheckpoint(ids)).checkpoint)
        val normalized = VoiceNewsQueue(VoiceNewsCheckpoint(listOf("one"), 99, -4)).checkpoint
        assertEquals(VoiceNewsCheckpoint(listOf("one")), normalized)
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsOversizedPlaylist() { VoiceNewsQueue().replace(List(21) { "$it" }) }
    @Test(expected = IllegalArgumentException::class) fun rejectsEmptyPlaylist() { VoiceNewsQueue().replace(emptyList()) }
    @Test fun staleCallbacksAfterFailureAreIgnored() {
        val queue = VoiceNewsQueue(VoiceNewsCheckpoint(listOf("one")))
        val token = queue.resume()
        queue.fail()
        assertFalse(queue.progress(token, 1))
        assertEquals("failed", queue.state)
    }
    @Test fun highlighterDoesNotTreatEmptyOrUnrelatedTextAsSpoken() {
        assertFalse(VoiceNewsHighlightPolicy.matches("", ""))
        assertFalse(VoiceNewsHighlightPolicy.matches("今天的天气", "人工智能新闻"))
        assertTrue(VoiceNewsHighlightPolicy.matches("第一段。\n今天有新的研究。", "今天有新的研究。"))
        assertTrue(VoiceNewsHighlightPolicy.matches("这是一个很长的新闻段落。接着是第二句。", "这是一个很长的新闻段落。"))
    }
}
