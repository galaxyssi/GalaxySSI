package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchSpeechPolicyTest {
    @Test fun displayedRangesStayAlignedAcrossRepeatedSentencesAndLongParagraphs() {
        val text = "相同句子。相同句子。\n" + "这是很长的说明，".repeat(30) + "结束。"
        val parts = WatchSpeechPolicy.displayChunks(text)
        assertTrue(parts.size > 4)
        assertEquals(0, parts.first().start)
        assertEquals(5, parts[1].start)
        parts.forEach {
            assertTrue(it.end > it.start)
            assertTrue(it.end - it.start <= 64)
            assertEquals(WatchSpeechPolicy.chunks(text.substring(it.start, it.end)).joinToString(" "), it.text)
        }
        assertEquals(text.filterNot(Char::isWhitespace), parts.joinToString("") { text.substring(it.start, it.end) }.filterNot(Char::isWhitespace))
        assertTrue(WatchSpeechPolicy.displayChunks(text, 6).all { it.start >= 6 })
    }

    @Test fun chunkBoundaryDoesNotSplitAnEmoji() {
        val text = "字".repeat(63) + "😀" + "继续。"
        val parts = WatchSpeechPolicy.displayChunks(text)
        assertEquals(63, parts.first().end)
        assertEquals(63, parts[1].start)
    }

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
