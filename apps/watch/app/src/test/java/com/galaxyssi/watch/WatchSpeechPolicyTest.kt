package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchSpeechPolicyTest {
    @Test fun completedParagraphsPlayOnceAndFinalTailFlushes() {
        val policy = WatchSpeechPolicy()
        policy.observe("", "", true, true)
        assertTrue(policy.observe("one", "First", false, true).chunks.isEmpty())
        assertEquals(listOf("First.\n"), policy.observe("one", "First.\nNext", false, true).chunks)
        assertTrue(policy.observe("one", "First.\nNext", false, true).chunks.isEmpty())
        assertEquals(listOf("Next."), policy.observe("one", "First.\nNext.", true, true).chunks)
    }
    @Test fun stopSuppressesCurrentResponseButNextReplyAutoPlays() {
        val policy = WatchSpeechPolicy()
        policy.observe("one", "", false, true)
        policy.stop()
        assertTrue(policy.observe("one", "Stopped.\n", false, true).chunks.isEmpty())
        assertFalse(policy.observe("one", "Stopped.\nMore.", true, true).awaitingMore)
        policy.observe("two", "", false, true)
        assertEquals(listOf("New reply."), policy.observe("two", "New reply.", true, true).chunks)
    }
    @Test fun historyAndDisabledSpeechDoNotReplay() {
        val policy = WatchSpeechPolicy()
        assertTrue(policy.observe("old", "History.", true, true).chunks.isEmpty())
        assertTrue(policy.observe("older", "Other history.", true, true).chunks.isEmpty())
        policy.observe("new", "", false, false)
        assertTrue(policy.observe("new", "Silent.", true, false).chunks.isEmpty())
        assertTrue(policy.observe("new", "Silent.", true, true).chunks.isEmpty())
    }
    @Test fun rewrittenReplyCancelsInsteadOfRepeating() {
        val policy = WatchSpeechPolicy()
        policy.observe("one", "", false, true)
        policy.observe("one", "First.\n", false, true)
        val rewritten = policy.observe("one", "Replacement.\n", false, true)
        assertTrue(rewritten.reset)
        assertTrue(rewritten.chunks.isEmpty())
        assertFalse(rewritten.awaitingMore)
    }
    @Test fun speechChunksStripMarkdownAndEmptyParagraphs() {
        val chunks = WatchSpeechPolicy.chunks("# Hello **world**.\n\n[Source](https://example.com)")
        assertTrue(chunks.isNotEmpty())
        assertFalse(chunks.joinToString().contains("https://"))
        assertFalse(chunks.joinToString().contains("**"))
    }
}
