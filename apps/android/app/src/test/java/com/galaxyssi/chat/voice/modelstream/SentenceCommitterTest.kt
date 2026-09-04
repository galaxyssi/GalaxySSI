package com.galaxyssi.chat.voice.modelstream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SentenceCommitterTest {
    private class FakeClock(var nowMs: Long = 0L) : SentenceCommitterClock {
        override fun elapsedRealtimeMs(): Long = nowMs
    }

    @Test
    fun commitsChineseAndEnglishSentenceBoundaries() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")

        val chinese = committer.acceptDelta(1, "\u4F60\u597D，\u8FD9\u662F\u7B2C\u4E00\u53E5。\u4E0B\u4E00\u53E5")
        val english = committer.acceptDelta(2, " continues and finishes!")

        assertEquals(listOf("\u4F60\u597D，\u8FD9\u662F\u7B2C\u4E00\u53E5。"), chinese.map { it.speechText })
        assertEquals(listOf("\u4E0B\u4E00\u53E5 continues and finishes!"), english.map { it.speechText })
    }

    @Test
    fun ignoresDecimalAndCommonEnglishAbbreviationPeriods() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")

        val chunks = committer.acceptDelta(1, "Dr. Smith measured 3.14 units. It passed.")

        assertEquals(
            listOf("Dr. Smith measured 3.14 units.", "It passed."),
            chunks.map { it.speechText }
        )
    }

    @Test
    fun firstChunkCanCommitAfterBoundedWaitWithoutPunctuation() {
        val clock = FakeClock()
        val committer = DefaultSentenceCommitter(clock = clock)
        committer.reset("request-1")
        assertTrue(committer.acceptDelta(1, "\u8FD9\u662F\u4E00\u4E2A\u6CA1\u6709\u6807\u70B9\u4F46\u662F\u5DF2\u7ECF\u8DB3\u591F\u957F\u7684\u56DE\u7B54\u5185\u5BB9").isEmpty())

        clock.nowMs = 499L
        assertTrue(committer.commitDue().isEmpty())
        clock.nowMs = 500L

        assertEquals("\u8FD9\u662F\u4E00\u4E2A\u6CA1\u6709\u6807\u70B9\u4F46\u662F\u5DF2\u7ECF\u8DB3\u591F\u957F\u7684\u56DE\u7B54\u5185\u5BB9", committer.commitDue().single().speechText)
    }

    @Test
    fun neverCommitsHalfCodeFenceAndDoesNotSpeakCode() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")

        assertTrue(committer.acceptDelta(1, "```json\n{\"answer\":").isEmpty())
        val chunks = committer.acceptDelta(2, "42}\n```\n\u5904\u7406\u5B8C\u6210。")

        assertEquals(listOf("\u5904\u7406\u5B8C\u6210。"), chunks.map { it.speechText })
        assertTrue(chunks.none { it.speechText.contains("answer") || it.speechText.contains("42") })
    }

    @Test
    fun neverCommitsHalfJsonAndOmitsCompletedJson() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")

        assertTrue(committer.acceptDelta(1, "{\"status\":\"run").isEmpty())
        val chunks = committer.acceptDelta(2, "ning\",\"value\":7} \u5DF2\u7ECF\u5B8C\u6210。")

        assertEquals(listOf("\u5DF2\u7ECF\u5B8C\u6210。"), chunks.map { it.speechText })
    }

    @Test
    fun urlIsNotReadOrSplitMidToken() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")

        assertTrue(committer.acceptDelta(1, "\u8BE6\u60C5 https://example.com/a.b").isEmpty())
        val chunks = committer.acceptDelta(2, " \u8BF7\u67E5\u770B。")

        assertEquals(listOf("\u8BE6\u60C5 \u8BF7\u67E5\u770B。"), chunks.map { it.speechText })
        assertTrue(chunks.none { it.speechText.contains("http") })
    }

    @Test
    fun stripsMarkdownDecorationsTablesPathsAndPrivateReasoning() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")
        val input = "<think>secret</think>\n# Result\n| A | B |\n|---|---|\n" +
            "\u8BF7\u67E5\u770B **\u62A5\u544A** C:\\private\\report.txt，\u7ED3\u679C\u6B63\u786E。"

        val chunks = committer.acceptDelta(1, input)
        val spoken = chunks.joinToString(" ") { it.speechText }

        assertTrue(spoken.contains("Result"))
        assertTrue(spoken.contains("\u8BF7\u67E5\u770B \u62A5\u544A"))
        assertTrue(!spoken.contains("secret") && !spoken.contains("private") && !spoken.contains("|"))
    }

    @Test
    fun duplicateOrOutOfOrderDeltaIsIgnored() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")

        val first = committer.acceptDelta(4, "\u7B2C\u4E00\u53E5\u5B8C\u6210。")
        val duplicate = committer.acceptDelta(4, "\u7B2C\u4E00\u53E5\u5B8C\u6210。")
        val older = committer.acceptDelta(3, "\u4E0D\u5E94\u51FA\u73B0。")

        assertEquals(1, first.size)
        assertTrue(duplicate.isEmpty())
        assertTrue(older.isEmpty())
    }

    @Test
    fun commaThresholdAndFlushProduceOrderedFinalChunk() {
        val committer = DefaultSentenceCommitter(
            SentenceCommitterConfig(commaCommitCharacters = 12, targetChunkCharacters = 24, maxChunkCharacters = 40)
        )
        committer.reset("request-1")

        val first = committer.acceptDelta(1, "\u8FD9\u662F\u4E00\u6BB5\u5DF2\u7ECF\u8DB3\u591F\u957F\u7684\u5185\u5BB9，\u53EF\u4EE5\u5148\u64AD\u653E，")
        val final = committer.acceptDelta(2, "\u5269\u4F59\u5185\u5BB9").let { it + committer.flush() }

        assertTrue(first.isNotEmpty())
        assertEquals("\u53EF\u4EE5\u5148\u64AD\u653E，\u5269\u4F59\u5185\u5BB9", final.last().speechText)
        assertTrue(final.last().isFinal)
        assertTrue((first + final).zipWithNext().all { (left, right) -> left.sequence < right.sequence })
    }

    @Test
    fun flushDropsUnclosedCodeAndJsonFragments() {
        val code = DefaultSentenceCommitter().apply { reset("code") }
        code.acceptDelta(1, "\u8BF4\u660E。```kotlin\nprintln(\"secret\")")
        val codeFlush = code.flush()

        val json = DefaultSentenceCommitter().apply { reset("json") }
        json.acceptDelta(1, "{\"token\":\"secret")
        val jsonFlush = json.flush()

        assertTrue(codeFlush.none { it.speechText.contains("println") || it.speechText.contains("secret") })
        assertTrue(jsonFlush.isEmpty())
    }

    @Test
    fun maxWaitNeverConsumesIntoAnUnclosedCodeBlock() {
        val clock = FakeClock()
        val committer = DefaultSentenceCommitter(clock = clock)
        committer.reset("request-1")
        committer.acceptDelta(1, "\u8FD9\u91CC\u5148\u8BF4\u660E\u81EA\u7136\u8BED\u8A00\u5185\u5BB9```python\nprint('secret')")
        clock.nowMs = 500L

        val due = committer.commitDue()
        val afterFence = committer.acceptDelta(2, "\n```\n\u540E\u7EED\u7ED3\u8BBA\u6B63\u786E。")

        assertEquals(listOf("\u8FD9\u91CC\u5148\u8BF4\u660E\u81EA\u7136\u8BED\u8A00\u5185\u5BB9"), due.map { it.speechText })
        assertEquals(listOf("\u540E\u7EED\u7ED3\u8BBA\u6B63\u786E。"), afterFence.map { it.speechText })
        assertTrue((due + afterFence).none { it.speechText.contains("secret") || it.speechText.contains("print") })
    }

    @Test
    fun splitPrivateReasoningTagNeverLeaksIntoSpeech() {
        val committer = DefaultSentenceCommitter()
        committer.reset("request-1")

        assertTrue(committer.acceptDelta(1, "<think>private plan. still private").isEmpty())
        val result = committer.acceptDelta(2, "</think>Public answer.")

        assertEquals(listOf("Public answer."), result.map { it.speechText })
        assertTrue(result.none { it.speechText.contains("private") || it.speechText.contains("plan") })
    }
}
