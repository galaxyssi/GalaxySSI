package com.galaxyssi.chat

import android.os.Bundle
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class ConversationHubTerminalStatusDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun persistedFinalReplyOverridesStaleSnapshotWithoutWritingUserData() {
        // Explicit opt-in: inspect only the two user-reported histories, never create or stop runs.
        val arguments = InstrumentationRegistry.getArguments()
        assumeTrue(arguments.getString("inspectReportedSessions") == "true")
        val context = instrumentation.targetContext
        val transcript = AgentTranscriptStore(context)
        val workspaceStore = EncryptedAgentWorkspaceStore(context)
        val workspaces = workspaceStore.list()
        val titles = setOf(requireNotNull(arguments.getString("reportedTitle1")),
            requireNotNull(arguments.getString("reportedTitle2")))
        val conversations = transcript.conversations().filter { it.title in titles }
        assertEquals("Both reported histories must be present", titles, conversations.map { it.title }.toSet())
        var reconciled = 0
        val unresolved = mutableListOf<String>()
        conversations.forEach { conversation ->
            val entry = transcript.previewEntry(conversation.latestMessageEntryId)
            val workspace = ConversationHubAgentStatusPolicy.workspace(conversation.id, entry, workspaces)
            val state = ConversationHubAgentStatusPolicy.resolve(workspace, entry, false)
            report("title=${conversation.title} workspace=${workspace?.status} role=${entry?.role} " +
                "reply_kind=${entry?.dedupeKey?.substringBefore(':')} " +
                "same_task=${entry?.taskId == workspace?.taskId} " +
                "parent_turn=${entry?.turnId == workspace?.workspaceId && entry?.turnId == workspace?.taskId} " +
                "canonical_final=${entry != null && entry.dedupeKey == AgentFinalResponseIdentity.dedupeKey(entry.turnId)} state=$state")
            if (workspace?.status in setOf(AgentWorkspaceStatus.RUNNING, AgentWorkspaceStatus.WAITING_RESPONSE) &&
                entry != null && AgentTaskTerminalReplyPolicy.isTerminalReply(entry)) {
                if (state != ConversationHubAgentStatus.READ) unresolved.add("${conversation.title}:$state")
                reconciled++
            }
        }
        assertTrue("Expected the reported stale rows to be reconciled", reconciled >= 2)
        assertTrue("Unreconciled rows: $unresolved", unresolved.isEmpty())
    }

    @Test fun statusProjectionIsBoundedAndKeepsTenOtherTasksActive() {
        val reply = AgentTranscriptEntry("a", AgentTranscriptRole.ASSISTANT, "done", 10,
            dedupeKey = AgentFinalResponseIdentity.dedupeKey("t"), conversationId = "c", turnId = "t", taskId = "executor-t")
        val stale = AgentWorkspace("t", "s", "c", "t", status = AgentWorkspaceStatus.RUNNING,
            eventJournal = List(100) { AgentWorkspaceEvent(kind = AgentTaskEventKinds.PROGRESS, timestampMillis = 20) })
        repeat(1_000) { ConversationHubAgentStatusPolicy.resolve(stale, reply, false) }
        val started = SystemClock.elapsedRealtimeNanos()
        repeat(10_000) { assertEquals(ConversationHubAgentStatus.READ,
            ConversationHubAgentStatusPolicy.resolve(stale, reply, false)) }
        report("projection_10000_rows_ms=${(SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0}")
        repeat(10) { index ->
            val task = "active-$index"
            val active = stale.copy(workspaceId = task, taskId = task, conversationId = task)
            val question = reply.copy(role = AgentTranscriptRole.USER, taskId = task, turnId = task,
                conversationId = task, dedupeKey = "")
            assertEquals(ConversationHubAgentStatus.RUNNING,
                ConversationHubAgentStatusPolicy.resolve(active, question, false))
        }
    }

    private fun report(value: String) {
        instrumentation.sendStatus(0, Bundle().apply { putString("stream", "$value\n") })
    }
}
