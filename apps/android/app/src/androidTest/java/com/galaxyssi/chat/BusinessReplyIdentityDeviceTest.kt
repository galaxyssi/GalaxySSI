package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BusinessReplyIdentityDeviceTest {
    private fun rich(uri: String, hash: String = "a".repeat(64)) =
        """{"version":1,"blocks":[{"id":"artifact-a","type":"image","title":"preview","text":"result","mime_type":"image/png","uri":"$uri","metadata":{"sha256":"$hash"}}]}"""

    private fun entry() = AgentTranscriptEntry("old", AgentTranscriptRole.ASSISTANT, "result", 1L,
        conversationId = "conversation", turnId = "turn", taskId = "task", richOutputJson = rich("galaxyssi-artifact://task/result.png"))

    @Test fun followsNewRowWithSameTurnTaskAndArtifactHash() {
        val original = entry()
        val hydrated = original.copy(id = "hydrated", richOutputJson = rich("content://attachments/local"))
        assertEquals(hydrated, resolveBusinessReply(listOf(original, hydrated), original))
    }

    @Test fun cannotMatchAnotherConversationTurnTaskOrText() {
        val original = entry()
        listOf(original.copy(conversationId = "other"), original.copy(turnId = "other"),
            original.copy(taskId = "other"), original.copy(text = "different")).forEach {
            assertNull(resolveBusinessReply(listOf(it), original))
        }
        assertNull(resolveBusinessReply(listOf(original), original.copy(turnId = "")))
    }

    @Test fun cannotSubstituteDifferentOrUnverifiedArtifact() {
        val original = entry()
        listOf("b".repeat(64), "", "not-a-hash").forEach { hash ->
            assertNull(resolveBusinessReply(listOf(original.copy(id = "new", richOutputJson = rich("content://local", hash))), original))
        }
        assertNull(resolveBusinessReply(listOf(original.copy(richOutputJson = "{}")), original))
    }

    @Test fun excludesStreamingApprovalAndNonAssistantRows() {
        val original = entry()
        listOf(original.copy(id = "agent-stream-1"), original.copy(dedupeKey = "remote-approval:1"),
            original.copy(role = AgentTranscriptRole.PROCESS)).forEach {
            assertNull(resolveBusinessReply(listOf(it), original))
        }
    }

    @Test fun permitsIdenticalTextOnlyResultButNotChangedRichContent() {
        val original = entry().copy(richOutputJson = "")
        val current = original.copy(id = "new")
        assertEquals(current, resolveBusinessReply(listOf(current), original))
        assertNull(resolveBusinessReply(listOf(current.copy(richOutputJson = rich("content://local"))), original))
    }
}
