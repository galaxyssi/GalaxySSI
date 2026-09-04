package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentConversationVisualContextTest {
    @Test
    fun latestUserImageIsAvailableForAVisualFollowUp() {
        val older = userEntry("turn-1", "old-image", AgentRichBlockType.IMAGE)
        val newer = userEntry("turn-2", "homework-image", AgentRichBlockType.IMAGE)
        val context = context(listOf(older, assistantEntry(), newer, assistantEntry()))

        val reference = AgentConversationVisualContext.latest(context)

        assertEquals("turn-2", reference?.turnId)
        assertEquals(listOf("homework-image"), reference?.blocks?.map(AgentRichBlock::id))
    }

    @Test
    fun assistantArtifactsAndUserFilesAreNotReplayedAsVisualInput() {
        val assistantImage = assistantEntry(
            richOutputJson = rich(AgentRichBlock("assistant-image", AgentRichBlockType.IMAGE))
        )
        val userFile = userEntry("turn-file", "document", AgentRichBlockType.FILE)

        assertNull(AgentConversationVisualContext.latest(context(listOf(userFile, assistantImage))))
    }

    @Test
    fun entryListLookupSupportsAnUncachedConversationWindow() {
        val reference = AgentConversationVisualContext.latest(
            listOf(userEntry("turn-visible", "visible-image", AgentRichBlockType.IMAGE))
        )

        assertEquals("turn-visible", reference?.turnId)
    }

    private fun userEntry(turnId: String, id: String, type: AgentRichBlockType) = AgentTranscriptEntry(
        id = "entry-$turnId",
        role = AgentTranscriptRole.USER,
        text = "",
        timestampMillis = 1L,
        conversationId = "conversation",
        turnId = turnId,
        richOutputJson = rich(
            AgentRichBlock(
                id = id,
                type = type,
                title = "$id.jpg",
                mimeType = if (type == AgentRichBlockType.IMAGE) "image/jpeg" else "application/pdf",
                metadata = mapOf("source" to "user_attachment")
            )
        )
    )

    private fun assistantEntry(richOutputJson: String = "") = AgentTranscriptEntry(
        id = "assistant-entry",
        role = AgentTranscriptRole.ASSISTANT,
        text = "response",
        timestampMillis = 2L,
        conversationId = "conversation",
        turnId = "assistant-turn",
        richOutputJson = richOutputJson
    )

    private fun context(turns: List<AgentTranscriptEntry>) = AgentConversationContext(
        conversationId = "conversation",
        summary = "",
        turns = turns,
        privateMode = false
    )

    private fun rich(block: AgentRichBlock): String = AgentRichContentCodec.encode(listOf(block))
}
