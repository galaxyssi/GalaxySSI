package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Test

class AgentVoiceAttachmentSubmissionPolicyTest {
    @Test
    fun `typed submission uses current composer attachments`() {
        val composer = mutableListOf("photo", "document")

        val selected = AgentVoiceAttachmentSubmissionPolicy.select(
            goalOverride = null,
            composerAttachments = composer,
            attachmentSnapshot = null
        )

        assertEquals(listOf("photo", "document"), selected)
        assertNotSame(composer, selected)
    }

    @Test
    fun `voice submission uses frozen attachment snapshot`() {
        val composer = listOf("newer-file")
        val snapshot = mutableListOf("captured-photo")

        val selected = AgentVoiceAttachmentSubmissionPolicy.select(
            goalOverride = "Please check this photo",
            composerAttachments = composer,
            attachmentSnapshot = snapshot
        )
        snapshot.clear()

        assertEquals(listOf("captured-photo"), selected)
    }

    @Test
    fun `voice submission without a snapshot does not consume unrelated drafts`() {
        val selected = AgentVoiceAttachmentSubmissionPolicy.select(
            goalOverride = "Hello",
            composerAttachments = listOf("unrelated-draft"),
            attachmentSnapshot = null
        )

        assertEquals(emptyList<String>(), selected)
    }
}
