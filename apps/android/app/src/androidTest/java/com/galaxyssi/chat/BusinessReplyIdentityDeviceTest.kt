package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.json.JSONObject

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

    private fun completedWorkspace() = AgentWorkspace("turn", "session", "conversation", "turn",
        status = AgentWorkspaceStatus.COMPLETED)

    @Test fun followsCanonicalParentFinalOnlyWithCompletedWorkspaceEvidence() {
        val original = entry()
        val canonical = original.copy(id = "parent-final", taskId = "local-task",
            dedupeKey = AgentFinalResponseIdentity.dedupeKey(original.turnId),
            richOutputJson = rich("content://attachments/local"))
        assertNull(resolveBusinessReply(listOf(canonical), original))
        assertEquals(canonical, resolveBusinessReply(listOf(canonical), original, completedWorkspace()))
        for (invalid in listOf(
            completedWorkspace().copy(status = AgentWorkspaceStatus.RUNNING),
            completedWorkspace().copy(status = AgentWorkspaceStatus.FAILED),
            completedWorkspace().copy(workspaceId = "other"),
            completedWorkspace().copy(taskId = "other"),
            completedWorkspace().copy(conversationId = "other"),
            completedWorkspace().copy(cancellationRequested = true),
            completedWorkspace().copy(createdAtMillis = 2L)
        )) assertNull(resolveBusinessReply(listOf(canonical), original, invalid))
    }

    @Test fun canonicalReplacementStillRejectsChangedContentAndArtifactOwnership() {
        val original = entry()
        val canonical = original.copy(id = "parent-final", taskId = "local-task",
            dedupeKey = AgentFinalResponseIdentity.dedupeKey(original.turnId))
        for (invalid in listOf(
            canonical.copy(dedupeKey = "child-result"), canonical.copy(turnId = "other"),
            canonical.copy(conversationId = "other"), canonical.copy(text = "changed"),
            canonical.copy(richOutputJson = rich("content://local", "b".repeat(64))),
            canonical.copy(richOutputJson = rich("content://local").replace(
                "\"sha256\":", "\"task_id\":\"foreign\",\"sha256\":"))
        )) assertNull(resolveBusinessReply(listOf(invalid), original, completedWorkspace()))
    }

    private fun connectorSnapshot() = JSONObject()
        .put("phase", "COMPLETED").put("message", "result")
        .put("metadata", JSONObject().put("remote_task_id", "task").put("task_id", "local-task")
            .put("conversation_id", "conversation").put("turn_id", "turn"))
        .put("execution_loop", JSONObject().put("task_id", "turn").put("phase", "COMPLETED")
            .put("updated_at", 3L))

    @Test fun connectorFinalizationAfterReceiptRequiresDurableIdentityProof() {
        val original = entry()
        val canonical = original.copy(taskId = "local-task", dedupeKey = AgentFinalResponseIdentity.dedupeKey("turn"))
        val resumed = completedWorkspace().copy(remoteRunId = "task",
            eventJournal = listOf(AgentWorkspaceEvent(kind = AgentTaskEventKinds.RESUMED, timestampMillis = 2L)),
            resultJson = connectorSnapshot().toString())
        assertFalse(ConversationHubAgentStatusPolicy.hasDeliveredReply(resumed, canonical))
        assertEquals(canonical, resolveBusinessReply(listOf(canonical), original, resumed))
        for (invalid in listOf(resumed.copy(remoteRunId = "other"), resumed.copy(resultJson = "{}"),
            resumed.copy(resultJson = "invalid"), resumed.copy(cancellationRequested = true),
            resumed.copy(createdAtMillis = 2L), resumed.copy(eventJournal = listOf(
                AgentWorkspaceEvent(kind = AgentTaskEventKinds.RESUMED, timestampMillis = 4L))))) {
            assertNull(resolveBusinessReply(listOf(canonical), original, invalid))
        }
        for ((section, key, value) in listOf(
            Triple("", "phase", "RUNNING"), Triple("", "message", "different"),
            Triple("metadata", "remote_task_id", "foreign"), Triple("metadata", "task_id", "foreign"),
            Triple("metadata", "conversation_id", "foreign"), Triple("metadata", "turn_id", "foreign"),
            Triple("execution_loop", "task_id", "foreign"), Triple("execution_loop", "phase", "RUNNING"),
            Triple("execution_loop", "updated_at", "0")
        )) {
            val snapshot = connectorSnapshot()
            (if (section.isBlank()) snapshot else snapshot.getJSONObject(section)).put(key, value)
            assertNull("$section/$key", resolveBusinessReply(listOf(canonical), original,
                resumed.copy(resultJson = snapshot.toString())))
        }
    }
}
