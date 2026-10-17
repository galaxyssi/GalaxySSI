package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentTranscriptWindowTest {
    @Test
    fun `background clear rejects pending reads even for the same conversation`() {
        val window = AgentTranscriptWindow()
        window.reset("conversation")
        val pending = window.loadOwner()
        window.reset("conversation")

        assertFalse(window.ownsLoad(pending))
        assertTrue(window.entries.isEmpty())
    }

    @Test
    fun `foreground restoration loads the currently selected conversation`() {
        val window = AgentTranscriptWindow()
        window.reset("old")
        val oldRead = window.loadOwner()
        window.reset("conversation")
        val resumedRead = window.loadOwner()

        assertFalse(window.ownsLoad(oldRead))
        assertEquals("conversation", resumedRead.conversationId)
        assertTrue(window.ownsLoad(resumedRead))
        window.replace(resumedRead.conversationId, page(entry("answer", text = "Completed")))
        assertEquals("Completed", window.entries.single().text)
    }

    @Test
    fun `leaving and returning to the same conversation does not revive old reads`() {
        val window = AgentTranscriptWindow()
        window.reset("conversation")
        val pending = window.loadOwner()
        window.reset("other")
        window.reset("conversation")

        assertFalse(window.ownsLoad(pending))
        assertTrue(window.ownsLoad(window.loadOwner()))
    }

    @Test
    fun `current refresh keeps ownership valid for older page loading`() {
        val window = AgentTranscriptWindow()
        window.reset("conversation")
        val pendingOlder = window.loadOwner()
        window.replace("conversation", page(entry("answer")))

        assertTrue(window.ownsLoad(pendingOlder))
        window.prependOlder("conversation", page(entry("question")))
        assertEquals(listOf("question", "answer"), window.entries.map { it.id })
    }

    @Test
    fun `replacement with a different conversation invalidates previous owner`() {
        val window = AgentTranscriptWindow()
        window.reset("old")
        val pending = window.loadOwner()
        window.replace("conversation", page(entry("answer")))

        assertFalse(window.ownsLoad(pending))
        assertEquals("conversation", window.loadOwner().conversationId)
    }

    @Test
    fun `old refresh cannot overwrite a completed response after foreground restore`() {
        val window = AgentTranscriptWindow()
        window.reset("conversation")
        val pending = window.loadOwner()
        window.reset("conversation")
        window.replace("conversation", page(entry("answer", text = "Verified result")))

        if (window.ownsLoad(pending)) {
            window.replace("conversation", page(entry("running", text = "Waiting")))
        }
        assertEquals("Verified result", window.entries.single().text)
    }

    private fun page(vararg entries: AgentTranscriptEntry) =
        AgentTranscriptPage(entries.toList(), null, false, entries.size.toLong())

    @Test
    fun `older pages prepend without discarding the latest transcript`() {
        val window = AgentTranscriptWindow()
        window.replace(
            "conversation",
            AgentTranscriptPage(
                entries = listOf(entry("3"), entry("4")),
                nextBeforeSequence = 3L,
                hasMore = true,
                newestSequence = 4L
            )
        )

        val added = window.prependOlder(
            "conversation",
            AgentTranscriptPage(
                entries = listOf(entry("1"), entry("2")),
                nextBeforeSequence = null,
                hasMore = false,
                newestSequence = 2L
            )
        )

        assertEquals(2, added)
        assertEquals(listOf("1", "2", "3", "4"), window.entries.map(AgentTranscriptEntry::id))
        assertFalse(window.hasMore)
        assertEquals(4L, window.newestSequence)
    }

    @Test
    fun `new transcript deltas replace matching live rows and retain older pages`() {
        val window = AgentTranscriptWindow()
        window.replace(
            "conversation",
            AgentTranscriptPage(
                entries = listOf(
                    entry("1"),
                    entry("running", dedupeKey = "task:1", text = "Running")
                ),
                nextBeforeSequence = null,
                hasMore = false,
                newestSequence = 2L
            )
        )

        window.appendNewer(
            "conversation",
            AgentTranscriptDelta(
                entries = listOf(
                    entry("completed", dedupeKey = "task:1", text = "Completed"),
                    entry("answer", text = "Done")
                ),
                newestSequence = 4L,
                hasMore = false
            )
        )

        assertEquals(listOf("1", "completed", "answer"), window.entries.map(AgentTranscriptEntry::id))
        assertEquals(listOf("message 1", "Completed", "Done"), window.entries.map(AgentTranscriptEntry::text))
        assertEquals(4L, window.newestSequence)
    }

    @Test
    fun `removing a loaded entry updates only the visible window`() {
        val window = AgentTranscriptWindow()
        window.replace(
            "conversation",
            AgentTranscriptPage(
                entries = listOf(entry("1"), entry("2")),
                nextBeforeSequence = null,
                hasMore = false,
                newestSequence = 2L
            )
        )

        assertTrue(window.remove("1"))
        assertFalse(window.remove("missing"))
        assertEquals(listOf("2"), window.entries.map(AgentTranscriptEntry::id))
    }

    private fun entry(
        id: String,
        dedupeKey: String = "",
        text: String = "message $id"
    ) = AgentTranscriptEntry(
        id = id,
        role = AgentTranscriptRole.PROCESS,
        text = text,
        timestampMillis = id.hashCode().toLong(),
        dedupeKey = dedupeKey,
        conversationId = "conversation",
        turnId = "turn",
        taskId = "task"
    )
}
