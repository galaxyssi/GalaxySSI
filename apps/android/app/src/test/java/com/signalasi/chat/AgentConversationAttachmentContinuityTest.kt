package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConversationAttachmentContinuityTest {
    @Test
    fun genericPerItemEditReusesLatestUserAttachment() {
        val selected = AgentConversationAttachmentContinuity.select(
            listOf(
                attachmentEntry("turn-image", "homework.jpg", 1L),
                textEntry("turn-reply", AgentTranscriptRole.ASSISTANT, 2L)
            ),
            currentTurnId = "turn-current",
            request = "\u6bcf\u4e00\u9898\u90fd\u4fee\u6539"
        )

        assertEquals("turn-image", selected?.turnId)
        assertEquals(listOf("homework.jpg"), selected?.blocks?.map(AgentRichBlock::title))
    }

    @Test
    fun explicitFileNameCanReachAnOlderAttachmentTurn() {
        val selected = AgentConversationAttachmentContinuity.select(
            listOf(
                attachmentEntry("turn-old", "report.xlsx", 1L),
                attachmentEntry("turn-new", "photo.jpg", 2L)
            ),
            currentTurnId = "turn-current",
            request = "Please revise report.xlsx."
        )

        assertEquals("turn-old", selected?.turnId)
    }

    @Test
    fun unrelatedNewRequestDoesNotResendPriorAttachment() {
        val selected = AgentConversationAttachmentContinuity.select(
            listOf(attachmentEntry("turn-image", "homework.jpg", 1L)),
            currentTurnId = "turn-current",
            request = "What is the weather in Shanghai today?"
        )

        assertNull(selected)
    }

    @Test
    fun currentTurnAttachmentIsNeverTreatedAsPriorContext() {
        val selected = AgentConversationAttachmentContinuity.select(
            listOf(attachmentEntry("turn-current", "homework.jpg", 1L)),
            currentTurnId = "turn-current",
            request = "Edit this image."
        )

        assertNull(selected)
    }

    @Test
    fun assistantArtifactsAreNotReusedAsOriginalUserInputs() {
        val assistant = attachmentEntry(
            "turn-output",
            "annotated.jpg",
            1L,
            role = AgentTranscriptRole.ASSISTANT
        )

        assertNull(
            AgentConversationAttachmentContinuity.select(
                listOf(assistant),
                currentTurnId = "turn-current",
                request = "Edit this image again."
            )
        )
    }

    @Test
    fun currentRequestExtractionIgnoresAttachmentWordsInHistory() {
        val request = buildString {
            append(AgentTranscriptStore.SIGNALASI_CONTEXT_TRANSPORT_HEADER)
            append("\n{\"turns\":[{\"content\":\"Attachments: old.jpg\"}]}\n")
            append(AgentTranscriptStore.SIGNALASI_CONTEXT_TRANSPORT_FOOTER)
            append("\nWhat is the weather today?")
        }

        assertNull(
            AgentConversationAttachmentContinuity.select(
                listOf(attachmentEntry("turn-image", "old.jpg", 1L)),
                currentTurnId = "turn-current",
                request = request
            )
        )
    }

    @Test
    fun continuationPolicyIsGenericRatherThanHomeworkSpecific() {
        assertTrue(
            AgentConversationAttachmentContinuity.referencesPriorArtifact(
                "Please crop and return the previous photo."
            )
        )
        assertTrue(
            AgentConversationAttachmentContinuity.referencesPriorArtifact(
                "\u518d\u4ed4\u7ec6\u4fee\u6b63\u4e00\u4e0b"
            )
        )
        assertFalse(
            AgentConversationAttachmentContinuity.referencesPriorArtifact(
                "Tell me tomorrow's weather."
            )
        )
    }

    private fun attachmentEntry(
        turnId: String,
        name: String,
        timestamp: Long,
        role: AgentTranscriptRole = AgentTranscriptRole.USER
    ): AgentTranscriptEntry = AgentTranscriptEntry(
        id = "entry-$turnId",
        role = role,
        text = name,
        timestampMillis = timestamp,
        conversationId = "conversation-1",
        turnId = turnId,
        taskId = turnId,
        richOutputJson = AgentRichContentCodec.encode(
            listOf(
                AgentRichBlock(
                    id = "artifact-$turnId",
                    type = AgentRichBlockType.IMAGE,
                    title = name,
                    uri = "content://signalasi/$name",
                    mimeType = "image/jpeg",
                    metadata = mapOf("source" to "user_attachment")
                )
            )
        )
    )

    private fun textEntry(
        turnId: String,
        role: AgentTranscriptRole,
        timestamp: Long
    ): AgentTranscriptEntry = AgentTranscriptEntry(
        id = "entry-$turnId",
        role = role,
        text = "done",
        timestampMillis = timestamp,
        conversationId = "conversation-1",
        turnId = turnId,
        taskId = turnId
    )
}
