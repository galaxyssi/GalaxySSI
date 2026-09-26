package com.galaxyssi.chat

import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GlobalConversationJournalControlIndexTest {
    @Test
    fun `durable control lookups do not rescan every control for every semantic event`() {
        val reads = AtomicInteger()
        val controls = (0 until 5_000).map { index ->
            val metadata = object : Map<String, String> by mapOf(
                GlobalConversationMergeLifecycle.SOURCE_CONVERSATION_ID to "source-$index",
                GlobalConversationMergeLifecycle.TARGET_CONVERSATION_ID to "target-$index"
            ) {
                override fun get(key: String): String? {
                    reads.incrementAndGet()
                    return when (key) {
                        GlobalConversationMergeLifecycle.SOURCE_CONVERSATION_ID -> "source-$index"
                        GlobalConversationMergeLifecycle.TARGET_CONVERSATION_ID -> "target-$index"
                        else -> null
                    }
                }
            }
            GlobalConversationEvent(
                id = "journal-control:merge-$index",
                type = GlobalConversationEventType.CONVERSATION_MERGED,
                conversationId = "target-$index",
                actor = GlobalConversationActor.SYSTEM,
                timestampMillis = index.toLong(),
                metadata = metadata
            )
        }
        val semantic = (0 until 1_200).map { index ->
            GlobalConversationEvent(
                id = "message-$index",
                type = GlobalConversationEventType.MESSAGE_CREATED,
                conversationId = "kept-${index / 32}",
                actor = GlobalConversationActor.USER,
                timestampMillis = 10_000L + index,
                content = "Synthetic authorized evidence"
            )
        }
        val delayed = semantic.first().copy(id = "delayed", conversationId = "source-0")
        val result = GlobalConversationContextJournalPolicy.apply(controls + semantic, listOf(delayed))
        assertEquals(1_200, result.count(GlobalConversationContextJournalPolicy::eligible))
        assertTrue(result.none { it.id == delayed.id })
        assertTrue("Control access must scale with controls, not controls x messages: ${reads.get()}",
            reads.get() < controls.size * 30)
    }
}
