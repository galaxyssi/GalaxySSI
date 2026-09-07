package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.agent.AgentRunEventVoiceAgentRunRepository
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunRequest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class VoiceProjectionLedgerDeviceTest {
    private fun request(task: String) = VoiceAgentRunRequest(
        conversationId = "conversation-$task", turnId = "turn-$task", taskId = task,
        sourceMessageId = kotlin.math.abs(task.hashCode().toLong()) + 1, contactId = "codex-desktop", agentId = "codex",
        agentName = "Codex", deviceId = "desktop", goal = "Video acceptance", idempotencyKey = "key-$task")

    private fun envelope(task: String, eventId: String) = JSONObject()
        .put("type", "agent_task_event").put("task_id", task)
        .put("source_message_id", kotlin.math.abs(task.hashCode().toLong()) + 1).put("conversation_id", "conversation-$task")
        .put("turn_id", "turn-$task").put("contact_id", "codex-desktop").put("agent_id", "codex")
        .put("desktop_id", "desktop").put("task_status", "running").put("status_seq", 0)
        .put("event_id", eventId)

    private fun isolated(test: (AgentRunEventStore) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "voice-projection-test-${UUID.randomUUID()}.db"
        val store = AgentRunEventStore(context, name)
        try { test(store) } finally { store.close(); context.deleteDatabase(name) }
    }

    @Test fun remoteEventIdentityIsIsolatedFromOtherRunProjections() = isolated { store ->
        store.appendNext(AgentRunControlEvent(eventId = "shared-remote-event", conversationId = "native",
            messageId = "native", taskId = "native", runId = "native", agentId = "codex", deviceId = "desktop",
            type = AgentRunControlEventType.RUN_STARTED, sequence = 0, timestampMillis = 1))
        val bridge = VoiceAgentRunBridge(AgentRunEventVoiceAgentRunRepository(store))
        val first = bridge.createRun(request("first")).snapshot
        val second = bridge.createRun(request("second")).snapshot
        assertEquals(1, bridge.consumeRemoteEnvelope(envelope("first", "shared-remote-event")).size)
        assertEquals(1, bridge.consumeRemoteEnvelope(envelope("second", "shared-remote-event")).size)
        val ids = listOf("native", first.runId, second.runId).map { store.latestEvent(it)!!.eventId }
        assertEquals(3, ids.toSet().size)
        assertEquals("shared-remote-event", store.latestEvent(first.runId)!!.idempotencyKey)
    }

    @Test fun persistentReplayDeduplicationSurvivesTheRecentEventWindow() = isolated { store ->
        val bridge = VoiceAgentRunBridge(AgentRunEventVoiceAgentRunRepository(store))
        val run = bridge.createRun(request("long")).snapshot
        repeat(110) { assertEquals(1, bridge.consumeRemoteEnvelope(envelope("long", "remote-$it")).size) }
        assertFalse(bridge.find(run.runId)!!.seenEventIds.contains("remote-0"))
        val sequence = store.snapshot(run.runId)!!.lastSequence
        val reopened = VoiceAgentRunBridge(AgentRunEventVoiceAgentRunRepository(store))
        assertTrue(reopened.consumeRemoteEnvelope(envelope("long", "remote-0")).isEmpty())
        assertEquals(sequence, store.snapshot(run.runId)!!.lastSequence)
    }
}
